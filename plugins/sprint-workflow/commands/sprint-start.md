---
description: Execute an approved sprint plan — dispatches agents in the defined flow, runs quality gates, fixes issues, documents, and commits
argument-hint: "<epic-id> | <plan-path>"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

Before doing anything else, detect which tracking backend and delegation tools are available:

### Linear MCP Check
1. Look for available MCP tools matching `mcp__linear__*` or `mcp__claude_ai_Linear__*`
2. Try calling `list_teams` with whichever prefix exists
3. If it succeeds → **Linear mode**. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
4. If it returns error `-32600` → retry once. If both fail → **MD mode**
5. If no Linear MCP tools exist → **MD mode** (default)

### Codex CLI Check
1. Check if `/codex:rescue` and `/codex:adversarial-review` are available as skills
2. If both present → **Codex available**. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.
3. If either missing → **Codex unavailable**

Set two flags: `TRACKING_MODE` ("linear" / "md") and `CODEX_AVAILABLE` (true / false).

## Your Task

Execute an approved sprint plan. You are the orchestrator. **You NEVER write code yourself** — you dispatch specialist agents and track progress.

> **If this sprint was interrupted (network loss, usage limit, manual stop), do NOT re-run `/sprint-start`.** Run `/sprint-continue` instead — it detects the current phase from Linear/MD state and resumes without re-doing completed work. Use `/sprint-handoff` before stopping if you want a clean snapshot for the next session.

### 1. Load the Sprint Plan

`$ARGUMENTS` is **required** — pass either an Epic ID (Linear mode) or a plan-file path (MD mode). If empty, refuse and tell the user to specify which Epic to execute.

**If `$ARGUMENTS` looks like a Linear Epic ID** (e.g., `PROJ-122`, or a Linear issue URL):
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` for query patterns
2. `get_issue({id, includeRelations: true})` → confirm it has the `Epic` label and `parentId === null`
3. Query Tasks: `list_issues({ parentId: <epic-id> })`
4. Reconstruct the sprint plan structure from these tasks:
   - Parse structured fields from descriptions: `**Agent:**`, `**Skills:**`, `**Codex-eligible:**`, `**Phase:**`
   - Parse acceptance criteria (checkbox items)
   - Parse anti-patterns
   - Check current status of each task — skip tasks already `Done`
5. If any tasks are already `In Progress` or `Done`, note them as resumed/completed
6. If reconstruction fails (missing fields, parse errors), warn the user and ask whether to proceed

**If `$ARGUMENTS` looks like a path** (ends in `.md`, exists on disk):
- Read the file. Confirm it contains stories with agent assignments, acceptance criteria, skill assignments, and execution groups.
- If the plan is missing these, tell the user to run `/sprint-plan` first.

**If `$ARGUMENTS` is empty:**
- In Linear mode, list active Epics (`list_issues({ label: "Epic", state: ["In Progress", "Todo"] })`) and ask the user which one to start. Do not auto-pick — `/sprint-start` is a destructive operation, the user must confirm.
- In MD mode, refuse and ask for a path.

### 2. Read Project Context

- Read `CLAUDE.md` if present
- **Detect version control**: Run `git rev-parse --is-inside-work-tree 2>/dev/null`. If it succeeds, read `${CLAUDE_PLUGIN_ROOT}/skills/git-flow/SKILL.md`. If not, check for TFVC (`tf vc workspaces 2>/dev/null`) and read `${CLAUDE_PLUGIN_ROOT}/skills/tfs-flow/SKILL.md`. You will use the appropriate skill for commits at the end.
- Identify build/test/lint commands for the project

### 3. Confirm Execution Plan with User

Before dispatching ANY agents, present:

```
## Execution Confirmation

### Phase 1: Implementation (parallel)
| Agent | Story/Task | Skills | Executor |
|-------|-----------|--------|----------|

The Executor column shows:
- "Codex" for codex-eligible tasks when Codex is available
- "Claude opus" for tasks routed to Claude agents

### Phase 2: Tests
| Agent | Scope | Skills |
|-------|-------|--------|

### Phase 3: Quality Gates (parallel)
- QA: Codex adversarial review + direct build/lint/spec checks (if Codex available) OR qa-agent (if Codex unavailable)
- pr-review-toolkit:code-reviewer: code quality + patterns (always Claude)

### Phase 4: Fix Loop
- Agents fix their own issues from Phase 3 reviews

### Phase 5: Documentation
- docs-agent: technical docs, version bumps, READMEs

### Phase 6: Commit & Push
- Logical commit/checkin units using git-flow or tfs-flow conventions

Proceed? (y/n)
```

Wait for user approval.

---

## Sprint Sentinel (write before Phase 1, delete in Phase 6)

After approval and BEFORE dispatching any agent, write the sprint-active sentinel so the Stop hook knows to remind you about tracking:

```bash
mkdir -p .claude
# First line: "linear" or "md" — the active tracking source
# Second line (optional): sprint id / milestone / plan filename for reference
echo "linear" > .claude/.sprint-active   # or "md"
```

This sentinel is what activates the Stop hook's tracking reminder. In sessions where it doesn't exist, the hook stays silent. The sentinel MUST be deleted in Phase 6 after final commits land (see "Clear Sprint Sentinel" below).

#### Ensure Stop-hook rate limit is configured

Right after writing the sentinel, ensure `.claude/settings.local.json` has a default rate limit for the Stop hook. **Only set it if missing — never overwrite a user's existing value.**

Run via Bash:

```bash
node -e '
const fs = require("fs");
const path = ".claude/settings.local.json";
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(path, "utf8")); } catch(e) {}
cfg.env = cfg.env || {};
if (!("SPRINT_STOP_HOOK_RATE_LIMIT_S" in cfg.env)) {
  cfg.env.SPRINT_STOP_HOOK_RATE_LIMIT_S = "600";
  fs.mkdirSync(".claude", { recursive: true });
  fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
  console.log("Set SPRINT_STOP_HOOK_RATE_LIMIT_S=600 (10 min) in " + path);
} else {
  console.log("Existing SPRINT_STOP_HOOK_RATE_LIMIT_S=" + cfg.env.SPRINT_STOP_HOOK_RATE_LIMIT_S + " kept.");
}
'
```

Default 600s (10 min) keeps the hook from spamming during active sprint work while still nagging often enough that the agent doesn't forget. The user can override per-project by editing the value directly. See the script header for tuning guidance.

---

## Execution Flow

### Phase 1: Implementation Agents

Dispatch implementation agents according to the plan's parallel groups. For each task, determine the executor based on `codex-eligible` flag and Codex availability.

#### Branching base for Phase 1 (READ FIRST)

**All task branches MUST be created from local `master` (or `main`) at dispatch time** — not from `origin/HEAD`, not via `Agent(isolation: "worktree")`. The built-in worktree isolation bases worktrees on `origin/HEAD`, which loses any commits already on the local integration branch from earlier tasks in this sprint. Manual branching avoids that footgun.

For each task before dispatch, the orchestrator runs (via Bash) on the integration branch (default: local `master`):

```bash
git switch master
git pull --ff-only origin master   # only on first task of sprint; skip if offline
git switch -c sprint/<task-id>
```

Then dispatch the implementation agent against the current working directory on `sprint/<task-id>`. Agents work on the branch directly — do NOT pass `isolation: "worktree"` to the `Agent` tool. The agent commits to its task branch. The orchestrator integrates branches in Phase 1.5.



#### Step 0: Pull prior context for the task (BEFORE dispatch)

**For every task about to be dispatched, regardless of executor (Codex or Claude), the orchestrator first gathers user notes and deferred items from prior turns.** Without this step, sub-agents miss context that the user added directly in Linear or that earlier tasks deferred.

**Linear mode:**
1. `list_comments({ issueId: <task-id> })` → all comments on the task itself
2. If the task has a parent Story: `list_comments({ issueId: <story-id> })` → all comments on the parent
3. Filter comments for relevance:
   - Tagged: `[NOTE]`, `[USER]`, `[DEFERRED]`, `[CARRYOVER]`, `[FOLLOW-UP]`
   - Or authored by a non-bot user (humans typing into Linear directly)
   - Or the most recent 5 comments if none match the above (gives the dispatched agent recent state)
4. Compose a "Prior Context From Linear" block to include in the agent prompt — preserve original wording verbatim, attribute by author, oldest-first.

**MD mode:**
1. Read the plan document's `## Carryover` section (if present)
2. Read any `Notes:` lines under the specific task entry
3. Compose a "Prior Context From Plan" block with the same shape as Linear mode.

**Inject into the agent prompt under the heading `## Prior Context (read carefully before starting)`** — placed BEFORE acceptance criteria, AFTER the spec section. The agent must read this; it may contain user constraints not captured in the original spec.

If no prior context exists, skip the section entirely (do not inject empty headings).

#### Step 1: Determine executor and dispatch

**For codex-eligible tasks (when Codex is available):**
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for context passing patterns
2. Read the relevant skill files for this task
3. Compose a full context prompt including:
   - Story title and task title
   - **Prior Context block from Step 0** (verbatim — Codex must see user notes/deferred items)
   - Acceptance criteria (verbatim)
   - Key patterns/standards from skill files (paste content, not just paths — Codex cannot read plugin skills)
   - Target file paths to create/modify
   - Anti-patterns
   - Build/type-check command for self-verification
4. **Update tracking BEFORE dispatch:**
   - MD mode: mark task status as `in-progress` in the plan document
   - Linear mode: call `save_issue` to set task status to "In Progress"
5. Invoke `/codex:rescue --effort high "<composed context>"`
6. After Codex completes:
   - Run build/type-check via Bash to verify
   - Spot-check key acceptance criteria by reading output files
   - If build fails or key ACs are not met → fall back to dispatching the original Claude agent
7. **Update tracking AFTER agent completion (BEFORE integration):**
   - MD mode: mark task status as `implementation-complete` (NOT `in-review` yet — In Review is reserved for "merged to local master and green")
   - Linear mode: call `save_comment` with completion summary (files changed, build result on the branch). Status stays at "In Progress" until Phase 1.5 successfully integrates the branch.

**For Claude tasks (codex-eligible: false, or Codex unavailable):**
1. Dispatch the assigned agent (`backend-dev`, `frontend-dev`, etc.) — do NOT use `Agent(isolation: "worktree")`. Agent works on the `sprint/<task-id>` branch created above.
2. Include in the agent prompt: **the Prior Context block from Step 0 (verbatim)**, skill file paths, acceptance criteria, anti-patterns, build/lint/test commands, file paths, the branch name they are working on, and "commit your work to this branch when done — orchestrator will integrate".
3. **Update tracking BEFORE dispatch:**
   - MD mode: mark task status as `in-progress`
   - Linear mode: call `save_issue` to set task status to "In Progress"
4. **Update tracking AFTER agent completion (BEFORE integration):**
   - MD mode: mark task status as `implementation-complete` (NOT `in-review` yet)
   - Linear mode: call `save_comment` with completion summary. Status stays at "In Progress" until Phase 1.5.

**Parallel execution rules remain the same:** Launch independent tasks in parallel (multiple Agent calls or Codex invocations in one message). Wait for sequential groups to complete before dispatching the next group.

> **Codex parallelism note:** When multiple tasks route to Codex, dispatch them sequentially (one foreground `/codex:rescue` after another), NOT via `run_in_background`. Background Codex causes lost work in this user's setup. For parallelism, prefer routing tasks to Claude agents (which can run concurrently via parallel `Agent` tool calls).

### Phase 1.5: Integrate (NEW)

After all Phase 1 tasks have reported `implementation-complete` on their branches, the orchestrator integrates them onto local `master` one at a time. **Sequential, not parallel** — merges are not commutative.

For each completed task branch (process in dependency order — sequential groups before parallel groups within a group), the orchestrator runs:

```bash
# 1. Make sure local master is up to date with the integration line
git switch master

# 2. Rebase the task branch onto current master, resolve conflicts
git switch sprint/<task-id>
git rebase master
# If conflicts: resolve via Edit, git add, git rebase --continue
# If unresolvable in <5 minutes: abort (git rebase --abort), bounce task back

# 3. Fast-forward master onto the rebased branch
git switch master
git merge --ff-only sprint/<task-id>

# 4. Run integration checks ON LOCAL MASTER
<build command>
<lint command>
<test command>
```

**On green (all checks pass):**
- Linear mode: `save_issue` → status "In Review" for the task
- MD mode: mark task status `in-review`
- `save_comment` (Linear) or plan note (MD): "Integrated to local master at <sha>. Build/lint/test green."
- Delete the task branch: `git branch -d sprint/<task-id>`
- Move to next task

**On failure (build/lint/test red after merge):**
- Revert the merge: `git reset --hard master@{1}` (or `git reset --hard <pre-merge-sha>` if reflog is unreliable)
- Linear mode: `save_issue` → status remains "In Progress". `save_comment` with the failure output and "Integration reverted — rework required."
- MD mode: status stays `implementation-complete`, plan note records failure
- **Bounce back to Phase 1**: re-dispatch the SAME agent (or Codex) with the original prompt PLUS:
  - "Integration on local master failed with: <output>"
  - "Your branch was reverted. Re-create it from current local master and fix."
- Other tasks proceed independently — one task's integration failure does not halt the sprint.

**No remote push happens in Phase 1.5.** All integration is local. `origin/master` only sees the result at Phase 6.

After ALL Phase 1 tasks have integrated successfully (or been bounced + retried), proceed to Phase 2.

### Phase 2: Test Writer

After implementation agents complete, dispatch `test-writer`:
- Include the list of implemented stories and their acceptance criteria
- Include test cases from the enrichment (if `/sprint-enrich` was run)
- Include skill file paths for the relevant test frameworks
- Tell it which files were created/modified in Phase 1

**After test-writer completes — update tracking:**
- **MD mode:** Update plan document with test status for each story
- **Linear mode:** Call `save_comment` on relevant Story issues with test coverage summary (unit count, integration count, frameworks used)

### Phase 3: Quality Gates (parallel)

**Review base: local `master`, not task branches.** By Phase 3, all task branches have been integrated into local `master` (Phase 1.5) and tests written on top (Phase 2). Reviews compare against `origin/master..HEAD` on local `master` — i.e., the diff between what's been pushed and the integrated sprint state. **Nothing is pushed to `origin` yet.** This is intentional: reviews see the same final shape that will land remotely, and Codex's origin/HEAD-base bias becomes correct (origin/HEAD = origin/master = the comparison baseline).

Dispatch two quality checks in parallel:

#### Gate 1: QA

**If Codex is available (Codex-first QA):**
The main session orchestrator handles QA directly — do NOT dispatch the sonnet qa-agent:

1. **Mechanical checks**: Run build, type-check, lint, and test suite via Bash (same commands qa-agent would run)
2. **Spec compliance**: Read implementation files and verify each acceptance criterion is met. Produce a checklist:
   ```
   | Criterion | Met? | Notes |
   |-----------|------|-------|
   ```
3. **Adversarial review**: Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for the focus string mapping table. Compose focus strings from all skills assigned to the sprint's tasks. Invoke:
   ```
   /codex:adversarial-review --base <sprint-branch-or-main> "focus: correctness; <composed focus strings>"
   ```
4. **Parse result**: Convert Codex output into the standard QA report format:
   - CRITICAL issues → BLOCKING
   - MAJOR issues → BLOCKING
   - MINOR issues → WARNING
5. **Consumer breakage check**: Grep for any renamed/removed exports across the codebase
6. **User-facing label audit**: Grep for raw technical strings (snake_case, camelCase, enum values) in UI code

**If Codex is NOT available (fallback):**
Dispatch `qa-agent` (sonnet) as in v2.2.2:
- Include all acceptance criteria from the plan
- Include skill file paths for the domains being validated
- Tell it to run: build, type-check, lint, tests, spec compliance
- Tell it to produce a structured report with BLOCKING/WARNING/INFO
- Architecture drift check (see "Architecture Drift in Phase 3" below)

#### Gate 2: Code Review

Dispatch `pr-review-toolkit:code-reviewer` — **ALWAYS Claude, never Codex.**
- Include skill file paths
- Include acceptance criteria
- Tell it to review all changes since the sprint started
- Tell it to flag UX regressions, spec mismatches, and pattern violations
- Architecture drift check (see "Architecture Drift in Phase 3" below)

#### Architecture Drift in Phase 3

When Linear mode is active AND the sprint's parent Project has an `Architecture & Roadmap` document, both Gate 1 and Gate 2 MUST run the drift check per `${CLAUDE_PLUGIN_ROOT}/skills/architecture-drift-check/SKILL.md`.

Pre-fetch the document **once** in the orchestrator (main session), then pass the body inline to both gates so neither has to call Linear MCP themselves:

1. Pick any Story from this sprint → `get_issue({id, includeRelations: true})` → capture `projectId`.
2. `list_documents({projectId})` → find `Architecture & Roadmap`.
3. `get_document({id})` → capture body.
4. Pass body + the skill path to:
   - **Codex adversarial review** (when Codex available): include the prescribed-model summary in the focus string. Codex doesn't have Linear MCP — it relies on the inline context.
   - **`qa-agent`** (Claude fallback): include in prompt as `## Architecture & Roadmap (compare diff against this)` section + skill path.
   - **`pr-review-toolkit:code-reviewer`**: same as qa-agent.

If the document doesn't exist → both gates skip the drift check with a one-line note (per skill §9). The sprint still completes — the check is graceful.

Findings are merged into the gate's standard report:
- **Erosion** → `BLOCKING` (counted in the existing BLOCKING list, fix loop applies)
- **Drift** → `WARNING` (counted in WARNING list; informational, doesn't block)

**After both gates complete:**
- Collect BLOCKING issues from both reports
- If ZERO blocking issues → proceed to Phase 5
- If ANY blocking issues → proceed to Phase 4
- **Update tracking:**
  - MD mode: update plan document with QA results and review results
  - Linear mode: call `save_comment` on each reviewed Story/Task with the QA report. If BLOCKING issues found, call `save_issue` to set affected task status back to "In Progress"

### Phase 4: Fix Loop

**Fix base: local `master`.** Each fix branches off the current local `master`, lands its change, then merges back to local `master` exactly like Phase 1.5. Re-reviews after fixes also compare against `origin/master..HEAD` on local `master`. Loop until clean. No remote push happens here.

For each BLOCKING issue, classify and route the fix:

**Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for fix routing criteria.**

#### Surgical fixes (Codex — when available)
Route to Codex when ALL of these are true:
- Single file affected
- Fix is mechanical (lint error, null check, missing import, typo, off-by-one, test assertion)
- No design decision required
- No interface/API change

For each surgical fix, the orchestrator:
1. Creates a fix branch from current local `master`: `git switch master && git switch -c sprint/fix-<issue-id>`
2. Invokes (foreground only, NEVER `run_in_background`): `/codex:rescue --effort high "Fix BLOCKING issue in <file>:<line>: <specific error>. Do not change any other files. Run <build command> after fixing."`
3. After Codex completes, integrates per Phase 1.5: `git switch master && git merge --ff-only sprint/fix-<issue-id>`, run build/lint/test on local master
4. On green → delete the fix branch, queue re-review. On red → revert and re-dispatch with the failure context.

#### Architectural fixes (Claude agent)
Route to the original Claude agent when ANY of these are true:
- Multiple files affected
- Interface or API signature change required
- Design pattern issue
- Cross-cutting concern

For each architectural fix, the orchestrator:
1. Creates a fix branch from current local `master`: `git switch master && git switch -c sprint/fix-<issue-id>`
2. Re-dispatches the SAME Claude agent that wrote the code (NOT via `Agent(isolation: "worktree")` — agent works on the fix branch in current dir) with:
   - The original acceptance criteria
   - The specific BLOCKING issues to fix
   - The branch name
   - Instruction: "Fix ONLY these issues. Do not refactor or add features."
3. After agent completes, integrates per Phase 1.5: `git switch master && git merge --ff-only sprint/fix-<issue-id>`, run build/lint/test on local master
4. On green → delete the fix branch, queue re-review. On red → revert and re-dispatch.

#### After each fix
1. Re-run QA on the fixed items (using Codex adversarial review or qa-agent, per Phase 3 logic)
2. Loop until all BLOCKING issues are resolved
3. **Update tracking:**
   - MD mode: note which issues were found and resolved in the plan document
   - Linear mode: call `save_comment` on affected task issues with fix details and re-validation result

### Phase 5: Documentation

Dispatch `docs-agent`:
- Update technical documentation for any new features/APIs
- Update CHANGELOG.md with new entries (if the project uses one)
- Update README.md if user-facing behavior changed
- Bump version numbers if applicable
- Create ADRs for any significant architectural decisions made during the sprint

**Update the plan** after docs complete.

**After docs complete — update tracking:**
- **MD mode:** Update plan document with documentation status
- **Linear mode:** Call `save_comment` on relevant Story issues noting which documentation was updated (files list)

### Phase 6: Commit & Push

YOU (the orchestrator) handle commits/push directly — do NOT dispatch an agent for this.

By the time Phase 6 runs:
- All task branches have been integrated into local `master` via ff-merges (Phase 1.5)
- Tests have been written and committed on top of local `master` (Phase 2)
- All BLOCKING issues have been fixed and ff-merged into local `master` (Phase 4)
- Documentation has been written and committed on top of local `master` (Phase 5)
- Local `master` is several commits ahead of `origin/master`, all reviewed clean
- `origin/master` has not been touched since the sprint started

The job here is to push that integrated history to the remote in **one** push, then mark Linear `Done`.

1. **Use the version control skill** read in Step 2 (`git-flow` or `tfs-flow`)
2. **Pre-push verification on local `master`**:
   - `git switch master`
   - `git log --oneline origin/master..HEAD` — confirm the commit list matches what was reviewed
   - Re-run build/lint/test ONE more time on local `master` to confirm it's still green
   - `git diff --stat origin/master..HEAD` — sanity-check scope
3. **Logical commits should already exist** — Phase 1.5 / 2 / 4 / 5 each landed their own commits on local `master` as they ran. If multiple intermediate commits accumulated for a single logical unit (e.g., several rebase iterations), optionally squash with `git rebase -i origin/master` BEFORE pushing.
4. **Message format** (same for both Git and TFVC, applied at the time each commit was made in earlier phases):
   - `feat(<scope>): <summary>` for new features
   - `fix(<scope>): <summary>` for bug fixes
   - `test(<scope>): <summary>` for test additions
   - `docs(<scope>): <summary>` for documentation
5. **Push to remote — single push, only after all gates clean**:
   - Git: `git push origin master` (no `--force`; if rejected, something went wrong — investigate, do NOT force)
   - TFVC: `tf vc checkin` per logical unit (TFVC has no separate "push" step)
6. **Associate work items** (TFVC): use `/associate` or `/resolve` with checkins

#### Finalize Tracking

**MD mode:**
- Mark all stories as `completed` in the plan document
- Commit the plan update separately: `chore(pm): update sprint plan — mark stories complete`

**Linear mode:**
- For each completed Task: call `save_issue` to set status to "Done"
- For each completed Story (all tasks Done): call `save_issue` to set status to "Done"
- Call `save_comment` on each Story with commit hashes and sprint summary
- Do NOT update any markdown plan file

#### Clear Sprint Sentinel

After tracking is finalized AND commits/checkins have landed, remove the sentinel so future ordinary sessions don't get nagged:

```bash
rm -f .claude/.sprint-active .claude/.sprint-active.last-nag .claude/.sprint-active.last-fire
```

Do NOT delete the sentinel earlier — it must survive until tracking is fully reconciled, otherwise an interrupted Phase 6 leaves no signal for the next session.

---

## Plan Status Tracking

**CRITICAL: Update tracking after EVERY phase transition.**

**MD mode:**
The plan document is the source of truth. If you get interrupted, the next session must be able to pick up by reading the plan.

Status flow per story:
```
not-started → in-progress → implementation-complete → tests-written → review-complete → fixes-applied → documented → committed
```

**Linear mode:**
Linear issues are the source of truth. Status transitions via `save_issue`:
```
Backlog → Todo → In Progress → In Review → Done
```

Phase mapping:
- Sprint starts: all tasks Backlog → Todo (bulk move)
- Phase 1 dispatch: Todo → In Progress
- Phase 1 agent complete (branch committed, NOT yet integrated): In Progress (stays — only a comment is added)
- Phase 1.5 integration green: In Progress → In Review (this is the new transition point)
- Phase 1.5 integration red: In Progress (stays, branch reverted, re-dispatched)
- Phase 3 pass: In Review (stays — Done waits for push)
- Phase 3 fail (blocking): In Review → In Progress (back for fixes)
- Phase 4 fix + re-integrate green: In Progress → In Review
- Phase 6 push successful: In Review → Done (bulk transition for all sprint tasks)

**If Linear fails mid-sprint:** Prompt user to approve markdown fallback. If approved, create `docs/SPRINT_PLAN.md` with current state reconstructed from Linear and continue in MD mode.

---

## Sprint Summary

After all phases complete, present:

```
## Sprint Complete — [project name]

### Stories Delivered
| Story | Agent | Status | Commit |
|-------|-------|--------|--------|

### Quality Gate Results
- QA: PASS/FAIL (N blocking, N warnings)
- Code Review: PASS/FAIL (N issues)
- Fix iterations: N

### Tests Added
- Unit: N | Integration: N | E2E: N

### Documentation Updated
- [list of files updated]

### Commits
- [list of commits with hashes]

### Follow-up Items
- [any warnings, tech debt, or deferred items]
```

**If Linear mode:** Also post this complete summary as a `save_comment` on each Epic-labeled Story issue in the sprint.
