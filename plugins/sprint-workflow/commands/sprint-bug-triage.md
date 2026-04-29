---
description: Run a multi-agent bug review (code-reviewer, security-agent, qa-agent spec-compliance, and Codex adversarial review when available) over a target. Dedup findings, present to user for triage, and create Linear sub-issues under an Epic OR append to docs/BUG_BACKLOG.md
argument-hint: "[target: file paths | --branch | --epic <id>]"
allowed-tools: Bash, Glob, Grep, Read, Write, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`
Diff stats: !`git diff --stat 2>/dev/null | tail -5 || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

### Linear MCP Check
1. Look for `mcp__linear__*` or `mcp__claude_ai_Linear__*`. Try `list_teams`. Success → **Linear mode**, read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
2. `-32600` → retry once. All fail → **MD mode**.

### Codex CLI Check
1. Check for `/codex:rescue` and `/codex:adversarial-review`.
2. Both present → **Codex available**, read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.

### Diagnose Skill
Always read `${CLAUDE_PLUGIN_ROOT}/skills/diagnose/SKILL.md` — every reviewer in this command must report findings with a hypothesis/cause, not just symptoms.

## Your Task

Run a multi-reviewer pass over a target, consolidate findings, get user approval, then create bug tickets. **You are the orchestrator.** You do not write code or fix bugs — only review and ticket creation.

### 1. Resolve Target

Parse `$ARGUMENTS`:

| Argument | Meaning |
|---|---|
| `<file paths>` | Review only those files |
| `--branch` (default) | Review all changes on current branch since `main` |
| `--epic <id>` | Review only files associated with the given Epic (Linear) — derive scope from Tasks under that Epic |
| (empty) | Default to `--branch` |

Resolve the target into a concrete file list. If the list is empty (e.g., no diff), warn and exit.

### 2. Determine Epic Context (for ticket attachment later)

**Linear mode:**

Try, in order:
1. If `--epic <id>` was passed, use it.
2. Check the current branch name for an Epic ID (e.g., `feat/PROJ-42-...`).
3. If a sprint is active (latest milestone with In Progress issues), find the Epic Story most directly tied to the changed files via Task assignments.
4. If no Epic can be determined, **create an on-the-fly "Bug Backlog" Epic** in the active milestone (or no milestone if none active):
   - Title: `Bug Backlog — <YYYY-MM>`
   - Labels: `Epic`, `Bug`
   - Description: "Auto-created by `/sprint-bug-triage` for bugs without a parent Epic. Bugs filed here can be re-parented later."
   - Use `save_issue` to create it.
   - Reuse any existing `Bug Backlog — <YYYY-MM>` Epic for the current month before creating a new one.
5. Confirm the chosen Epic with the user before creating any sub-issues.

**MD mode:**

Bugs go to `docs/BUG_BACKLOG.md` (create if missing). No Epic resolution needed.

### 3. Dispatch Reviewers In Parallel

Launch **all** of these in a single message (parallel execution). Each reviewer must:
- Read `${CLAUDE_PLUGIN_ROOT}/skills/diagnose/SKILL.md` first
- Read its own always-read skills
- Inspect ONLY the resolved target file list
- Return findings in the structured format below

#### Reviewer 1: `pr-review-toolkit:code-reviewer`

Standard review focus: code quality, patterns, consumer breakage, naming, error handling, security smells.

#### Reviewer 2: `security-agent`

OWASP Top 10, auth/authz gaps, PII handling, secret exposure, injection vectors, dependency CVEs, audit-trail gaps.

#### Reviewer 3: `qa-agent` (spec-compliance mode)

Acceptance-criteria verification only — no build/lint/type runs (those are Phase 3's job, not bug triage's). If acceptance criteria are not provided in `$ARGUMENTS` or derivable from Linear/MD, instruct the agent to focus on user-facing-label audit and consumer-breakage check only.

#### Reviewer 4: Codex adversarial review (when Codex available)

Compose focus strings from skills relevant to the target files (per `codex-delegation` skill mapping table). Invoke:

```
/codex:adversarial-review --base main "focus: correctness, security, hidden-coupling; <composed focus strings>"
```

Each reviewer returns:

```
## Findings — <reviewer name>

| Severity | Area | File:Line | Title | Description | Hypothesis | Suggested Fix |
|----------|------|-----------|-------|-------------|------------|---------------|

(Severity: CRITICAL / HIGH / MEDIUM / LOW)
```

### 4. Consolidate & Dedup

After all reviewers return:

1. Collect all findings into a single table.
2. **Dedup key**: `(file_path, normalized_line_range, category)` where `normalized_line_range` is the floor-rounded 5-line bucket (e.g., line 47 → bucket 45–49). Two findings in the same file within ±5 lines on the same category are the same finding.
3. For duplicates, merge: take the highest severity, concatenate hypotheses, and record `Found by:` with all reviewer names.
4. Sort the consolidated list: CRITICAL → HIGH → MEDIUM → LOW; ties by file path.

### 5. Present To User For Triage

```
## Bug Triage — <project> — <YYYY-MM-DD>

### Target
<file list or branch>

### Epic / Destination
<Linear: <epic-id> "<title>" | MD: docs/BUG_BACKLOG.md>

### Findings (<N total after dedup>)

| # | Severity | File:Line | Title | Found By | Suggested Fix |
|---|----------|-----------|-------|----------|---------------|

### Per-Finding Detail

#### 1. <title>
- **Severity**: HIGH
- **Location**: <file:line>
- **Found by**: code-reviewer, codex
- **Description**: ...
- **Hypothesis (root cause)**: ...
- **Suggested fix**: ...

(Repeat for each finding)

### Triage Decisions Required

For each finding, you (the user) decide:
- **(a)ccept** — file as a bug ticket
- **(d)efer** — file with `tech-debt` label, no immediate action
- **(r)eject** — false positive, drop it
- **(m)erge with #N** — combine with another finding

You can reply with: `1a 2a 3r 4d 5m1` (per-finding decisions), or `all-a` to accept all, or `select 1,2,4` to accept only those.
```

Wait for the user's triage response. Parse it. **Do not** create any tickets until the user has explicitly approved.

### 6. Create Tickets

#### Linear mode

For each accepted/deferred finding:

1. `save_issue` with:
   - `parentId`: the Epic resolved in step 2
   - `title`: the finding title
   - Labels: `Task` (always) + `Bug` (always) + `tech-debt` (if deferred)
   - Description: structured markdown including:
     - **Severity:** HIGH/MEDIUM/LOW
     - **Found by:** <reviewer names>
     - **File:** `<path:line>`
     - **Description:** ...
     - **Hypothesis:** ...
     - **Suggested fix:** ...
     - **Acceptance criteria:** "Bug no longer reproduces" + a regression test asserting the fix
2. Capture the new issue ID.

After all tickets are created, post a single `save_comment` on the parent Epic summarizing what was filed (count + IDs).

If the `Bug` label doesn't yet exist on the team, create it first: `create_issue_label` with name `Bug`, color `#EB5757` (red). Existing teams with their own colour are unaffected.

#### MD mode

Append accepted findings to `docs/BUG_BACKLOG.md`. Create the file with this header if missing:

```markdown
# Bug Backlog

Bugs filed via `/sprint-bug-triage`. Each entry is a candidate for a future sprint.
Status: `open` | `in-progress` | `fixed` | `wontfix`.

---
```

Each finding becomes an entry:

```markdown
## BUG-<YYYYMMDD>-<NN> — <title>

- **Status**: open
- **Severity**: HIGH
- **Found**: <YYYY-MM-DD> via /sprint-bug-triage
- **Found by**: <reviewer names>
- **File**: `<path:line>`
- **Description**: ...
- **Hypothesis**: ...
- **Suggested fix**: ...
- **Acceptance criteria**:
  - [ ] Bug no longer reproduces
  - [ ] Regression test added
```

`<NN>` is a sequential counter for the day, scanning existing BUG-IDs in the file.

### 7. Final Report

```
## Bug Triage Complete

### Reviewers Run
- <list>

### Findings Summary
- Total: <N> | Accepted: <N> | Deferred: <N> | Rejected: <N>

### Tickets Created
<Linear: list of issue IDs with links | MD: list of BUG-IDs added to docs/BUG_BACKLOG.md>

### Next Steps
- Tickets are ready to be picked up in the next sprint plan.
- Re-run `/sprint-plan` to incorporate them, or address ad-hoc via `/sprint-resume-task`.
```

This command **never** dispatches fix work itself. It is review + triage + ticket only.

---

## Anti-Patterns

- **Do not** auto-accept findings without user triage. False positives are common, especially from adversarial review.
- **Do not** create tickets in a non-active Epic just because the file paths match. Always confirm Epic with the user.
- **Do not** report findings without hypotheses. The `diagnose` skill is required reading for every reviewer.
- **Do not** dispatch reviewers serially. Parallel is mandatory — they're independent and the user is waiting.
