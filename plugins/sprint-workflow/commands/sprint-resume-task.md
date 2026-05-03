---
description: Re-run a single failed or stuck task by ID using the same agent and the original spec section. Use when only one task needs re-dispatching — not the whole sprint.
argument-hint: "<task-id>"
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

Same as `/sprint-start`:

### Linear MCP Check
1. Look for `mcp__linear__*` or `mcp__claude_ai_Linear__*` tools.
2. Try `list_teams`. Success → **Linear mode**, read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
3. `-32600` → retry once. Both fail → **MD mode**.
4. No tools → **MD mode**.

### Codex CLI Check
1. Check for `/codex:rescue` and `/codex:adversarial-review`.
2. Both present → **Codex available**, read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.

Set `TRACKING_MODE` and `CODEX_AVAILABLE`.

## Your Task

Re-run a single sprint task. Use the same agent and the same spec section that the original `/sprint-start` would have used. Don't re-enter the whole sprint flow.

### 1. Resolve Task Identifier

`$ARGUMENTS` may be:
- A Linear issue ID (e.g., `T-123`, `ABC-45`)
- A task title or partial title (case-insensitive substring)
- Empty — in which case prompt the user

**Linear mode:**
- If the argument looks like an ID, call `get_issue` directly.
- Otherwise, call `list_issues` filtered by current sprint milestone, fuzzy-match the title, and confirm with the user before proceeding.

**MD mode:**
- Search the plan document(s) for matching task titles or IDs.
- If multiple matches, list them and ask the user to disambiguate.

If the task isn't found → exit with a helpful error listing the candidates.

### 2. Load Task Context

For the resolved task, gather:

- **Story / Epic** it belongs to (parent issue in Linear, parent section in MD)
- **Agent** assigned (from structured fields)
- **Skills** assigned (from structured fields)
- **Codex-eligible** flag
- **Acceptance criteria** (verbatim — checkbox items in Linear description, or list under the task in MD)
- **Anti-patterns** if listed
- **Spec section reference** if the task points to a spec file (e.g., "see `docs/ux-report.md` Section 5")
- **Current status** of the task
- **Prior comments / notes** on the task (Linear comments, MD plan notes) — these tell you what went wrong before

### 3. Determine Re-Run Reason

Ask the user (single-line confirmation):

```
Task: <id> — <title>
Agent: <agent>
Current status: <status>
Codex-eligible: <true/false>

Reason for re-run? (choose one)
1. Implementation incomplete — re-dispatch from current state
2. QA found BLOCKING issues — fix only the listed issues
3. Code review rejected — fix specific review comments
4. Stuck / errored mid-execution — restart fresh

Or describe the reason in your own words.
```

This shapes the prompt sent to the agent. Capture the reason verbatim and include it in the agent's context.

### 4. Read Project Context

- Read `CLAUDE.md` if present.
- Detect version control (`git-flow` vs `tfs-flow`) — load the relevant skill if commits will follow.
- Identify build/test/lint commands.

### 5. Read Skill Files

For each skill assigned to the task, read it from `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`. If the agent is going to be dispatched (not Codex), pass file paths in the prompt. If Codex is going to handle the work, paste relevant skill content into the prompt (Codex cannot read plugin skill files).

### 6. Update Tracking Before Dispatch

**Linear mode:**
- `save_issue` → status `In Progress` (if not already)
- `save_comment` → "Re-dispatched by /sprint-resume-task at <timestamp>. Reason: <reason>."

**MD mode:**
- Update task status field to `in-progress`
- Append a note line: `Re-dispatched <timestamp> — reason: <reason>`

### 7. Dispatch

#### Codex-eligible task (when Codex is available)

Compose the full Codex prompt per `codex-delegation` skill:
- Task title and Story title
- Reason for re-run (from step 3)
- Acceptance criteria verbatim
- Anti-patterns
- Skill content pasted inline
- Target file paths
- Build/type-check command for self-verification
- **If reason is QA BLOCKING / review rejection**: include the specific issue list verbatim and instruct: "Fix ONLY these issues. Do not refactor or add features."

Invoke: `/codex:rescue --effort high "<composed prompt>"`

#### Claude task (codex-eligible: false, or Codex unavailable, or reason requires architectural change)

Dispatch the assigned Claude agent (`backend-dev`, `frontend-dev`, etc.) with:
- The skill file paths (not pasted content — Claude agents can read them)
- Reason for re-run
- Acceptance criteria
- Anti-patterns
- File paths to inspect
- Build/lint/test commands
- **If reason is "fix BLOCKING / review issues"**: include the specific issue list verbatim and instruct: "Fix ONLY these issues. Do not refactor or add features."

### 8. Verify

After the dispatched work completes:

1. **Build check**: run the project's build/type-check command via Bash.
2. **Spec compliance**: re-read each acceptance criterion and confirm it's met (read the actual files).
3. **Consumer search**: if any exports/public APIs changed, grep the codebase for old names per global CLAUDE.md.
4. **If reason was QA BLOCKING**: re-run the failed checks. They must pass.

If verification fails → loop: re-dispatch with the new failure list. Do **not** loop more than 3 times — after 3 failures, escalate to the user with what you've learned.

### 9. Update Tracking After Completion

**Linear mode:**
- `save_issue` → status `In Review` (if implementation completed cleanly)
- `save_comment` → completion summary: files changed, build result, ACs met, any follow-ups

**MD mode:**
- Update task status to `implementation-complete` (or further along if you ran QA)
- Note files changed and build result

### 10. Report

```
## Task Re-Run Complete — <task id>

### Task
<id> — <title> (Story: <story title>)

### Reason
<reason>

### Executor
<Codex / agent name>

### Build Result
<pass / fail with details>

### Acceptance Criteria
| # | Criterion | Met? |
|---|-----------|------|

### Files Modified
- <path>

### Status Update
<Linear: status → In Review | MD: status → implementation-complete>

### Next Steps
- <e.g., "Re-run /sprint-start at Phase 3 to validate against the rest of the sprint" or "Sprint can resume via /sprint-continue">
```

This command **does not** advance the sprint to subsequent phases. It only completes the single task. To continue the sprint after this, the user runs `/sprint-continue`.

---

## When To Use vs `/sprint-continue`

- `/sprint-resume-task <id>` — single task is broken; rest of the sprint is fine. Surgical.
- `/sprint-continue` — the whole sprint flow was interrupted; multiple tasks need attention. Holistic.

If you can't tell which fits, prefer `/sprint-continue` — it's idempotent and will detect what's actually needed.
