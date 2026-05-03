---
description: Resume an interrupted sprint — detects current phase from Linear/MD state, re-enters the correct phase logic from /sprint-start, and continues without re-doing completed work
argument-hint: "[plan-file-path | linear-milestone-id]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`
Git status: !`git status --short 2>/dev/null | head -20 || echo "not a git repo"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

Detect tracking backend and delegation tools (same pattern as `/sprint-start`):

### Linear MCP Check
1. Look for available MCP tools matching `mcp__linear__*` or `mcp__claude_ai_Linear__*`
2. Try calling `list_teams` with whichever prefix exists. If success → **Linear mode**. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
3. On `-32600`, retry once. On total failure → **MD mode**.
4. No Linear tools at all → **MD mode**.

### Codex CLI Check
1. Check for `/codex:rescue` and `/codex:adversarial-review` skills.
2. Both present → **Codex available**. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.
3. Either missing → **Codex unavailable**.

Set `TRACKING_MODE` and `CODEX_AVAILABLE` flags.

## Your Task

Resume an interrupted sprint. You are the orchestrator — you NEVER write code yourself.

This command is **idempotent**: running it on a clean sprint reports "nothing to resume" and exits. Tasks already `In Review` / `Done` are NEVER re-dispatched. Only re-validation runs against them.

### 1. Load Sprint State

**If a handoff document exists** at `docs/SPRINT_HANDOFF.md`, read it first. It tells you the current phase, in-flight tasks, blockers, and any session-specific notes. Treat it as a hint — verify against the live tracking source before acting.

**Linear mode:**
1. Discover team/project. If `$ARGUMENTS` includes a milestone ID, use it. Otherwise call `list_milestones` and pick the most recent active milestone (most `In Progress` issues). Confirm with the user if ambiguous.
2. Query Stories: `list_issues` by `milestoneId` + `Epic` label.
3. For each Story, query Tasks: `list_issues` with `parentId`.
4. Parse structured fields from descriptions per `linear-sprint-planning` skill (`Agent`, `Skills`, `Codex-eligible`, `Phase`).
5. Capture each issue's current status.

**MD mode:**
1. Locate plan document — `$ARGUMENTS` path takes precedence, else `docs/SPRINT_PLAN.md`, `docs/SPRINT*.md`, `SPRINT_PLAN.md`.
2. Parse stories, tasks, statuses, and the per-task fields.

If no plan can be found in either mode → tell the user to run `/sprint-plan` and exit.

### 1b. Re-Assert Sprint Sentinel

A sprint is being resumed → ensure the Stop hook will remind about tracking. Re-create the sentinel if missing (idempotent — does nothing if already there):

```bash
mkdir -p .claude
[ -f .claude/.sprint-active ] || echo "<linear|md>" > .claude/.sprint-active
```

(First line should be `linear` or `md` matching the active tracking mode detected above.)

### 2. Determine Current Phase

Map the status distribution to the 6-phase model. Same table as `/sprint-handoff`:

| Distribution | Phase to Resume |
|---|---|
| Any task `In Progress` / `in-progress` | **Phase 1** — finish remaining implementation |
| All implementation `In Review` / `implementation-complete`, no test artefacts | **Phase 2** — tests |
| Tests present, no QA gate run | **Phase 3** — quality gates |
| QA returned BLOCKING and tasks bounced back | **Phase 4** — fix loop |
| All `In Review` / `review-complete`, no docs work | **Phase 5** — docs |
| All `documented`, no commit/checkin | **Phase 6** — commit & push |
| All `Done` / `completed` | **Sprint Complete — nothing to resume** |

If mixed (e.g., 2 tasks `In Progress` AND 3 tasks `In Review`), **resume the earliest phase first**. Phase 1 work must finish before Phase 2 starts. The orchestrator will re-enter Phase 2 once Phase 1 completes.

### 3. Read Project Context

- Read `CLAUDE.md` if present.
- **Detect version control**: `git rev-parse --is-inside-work-tree 2>/dev/null` → `git-flow`; else check for TFVC → `tfs-flow`. Read the appropriate skill.
- Identify build/test/lint commands.

### 4. Confirm Resume Plan with User

Present the resume plan before dispatching anything:

```
## Resume Plan — <project> — <sprint name>

### Current Phase Detected
<Phase N — Name>

### Tasks Already Complete (skipped)
| Task | Story | Status | Completed In |
|------|-------|--------|--------------|

### Tasks To Resume
| Task | Story | Agent | Executor | Action |
|------|-------|-------|----------|--------|

(Action column: "continue", "re-validate", "fix BLOCKING")

### Tasks Already In Progress (verify state first)
<list any tasks marked In Progress that may have been partially executed by a prior session — these need careful re-entry, see step 5>

### Phases After This One
<list the remaining phases that will run after the resumed phase completes>

Proceed? (y/n)
```

Wait for user approval.

### 5. Re-Enter Phase Logic

**You do NOT duplicate the phase logic.** Use the same procedures defined in `${CLAUDE_PLUGIN_ROOT}/commands/sprint-start.md`. Read that file's "Execution Flow" section and apply the phase you determined.

#### Special handling for partial Phase 1 tasks

A task marked `In Progress` may have been partially completed by a prior session before interruption. Before dispatching the agent again:

1. **Check git for uncommitted changes** related to the task's target files. If present, read them — the prior agent may have already done substantial work.
2. **Check Linear comments** (or MD plan notes) for any "files modified" entries the prior session left. The `sprint-start` orchestrator records these after Codex/agent completion.
3. **Decide: resume vs restart.**
   - If files exist with partial implementation → instruct the resuming agent to **continue from current state**: include in the prompt "Files <list> already modified by previous session. Read them, complete the remaining acceptance criteria, do NOT restart from scratch."
   - If no files exist → dispatch fresh as in `/sprint-start` Phase 1.
4. **Update tracking BEFORE dispatch** (same as `sprint-start`): mark task `In Progress` (already true) and add a comment "Resumed by /sprint-continue at <timestamp>".

#### Phase 3 re-entry (QA + code review)

If resuming at Phase 3, re-run **both** gates from scratch — QA results from a prior session are stale once new fixes have been applied. The exception: if the user explicitly says "Phase 3 already completed cleanly, just continue" via the confirmation dialog, skip to Phase 4 fix loop with the prior session's BLOCKING list (sourced from Linear comment / MD plan).

#### Phase 6 re-entry (commit & push)

If resuming at Phase 6:
1. Run `git status` / `tf vc status` to see what's uncommitted
2. Verify nothing has been pushed already (Linear: check for "Committed" comment markers; git: `git log origin/<branch>..HEAD`)
3. Continue commit/checkin sequence from where it stopped
4. Do NOT amend already-pushed commits

### 6. Continue To Completion

Once the resumed phase completes, proceed through the remaining phases per `sprint-start.md`. The sprint is only complete when Phase 6 finalizes tracking.

### 7. Update Handoff (Optional)

If `docs/SPRINT_HANDOFF.md` existed when this command started, **delete it** after successful sprint completion. The handoff was a transient artefact — leaving stale ones around invites confusion.

If the sprint is interrupted again before completion, the next `/sprint-handoff` invocation will produce a fresh one.

---

## Idempotency Guarantee

- Running `/sprint-continue` on a sprint with all tasks `Done` → reports "nothing to resume", does not modify any state, exits cleanly.
- Running it twice in a row at the same phase → second run picks up where the first left off (or where the first failed).
- Tasks already `In Review` are never re-implemented. They are only re-validated if Phase 3 needs to re-run.

## When To Use vs `/sprint-resume-task`

- `/sprint-continue` — the **whole sprint** was interrupted. Resume from the current phase across all tasks.
- `/sprint-resume-task <id>` — only **one specific task** failed or got stuck. Re-run that single task without re-entering the full phase.
