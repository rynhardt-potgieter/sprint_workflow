---
description: Show current sprint/task status for the current project
allowed-tools: Bash, Glob, Grep, Read
---

## Context

Current directory: !`pwd`
Git status: !`git log --oneline -5 2>/dev/null || echo "not a git repo"`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — discover manually by searching for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

Detect tracking backend and delegation tools:

### Linear MCP Check
1. Look for available MCP tools matching `mcp__linear__*` or `mcp__claude_ai_Linear__*`
2. Try calling `list_teams` with whichever prefix exists
3. If it succeeds → **Linear mode**. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
4. If it returns error `-32600` → retry once. If both fail → **MD mode**
5. If no Linear MCP tools exist → **MD mode** (default)

### Codex CLI Check
1. Check if `/codex:rescue` and `/codex:adversarial-review` are available as skills
2. If both present → **Codex available**
3. If either missing → **Codex unavailable**

Set flags: `TRACKING_MODE` ("linear" / "md") and `CODEX_AVAILABLE` (true / false).

## Your Task

Find and report the current task/sprint status for this project. **Read the project plan document directly — do NOT review code to determine status.**

### 1. Find the Project Plan

**If Linear mode (check first):**
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` for query patterns
2. Discover team/project: call `list_teams` / `list_projects` — ask user to confirm
3. Find active sprint: call `list_milestones` — look for the most recent active milestone
4. Query Stories: call `list_issues` filtered by `milestoneId` and "Epic" label
5. For each Story, query Tasks: call `list_issues` with `parentId`
6. Each issue already has its status — no need to parse from a file
7. Skip the markdown file search entirely

**If MD mode:**
Search for the active project plan or task tracking document. Check these locations in order:
- `docs/PROJECT_PLAN*.md`, `docs/SPRINT*.md`, `docs/ROADMAP*.md`
- `PROJECT_PLAN*.md`, `SPRINT*.md`, `TASKS.md`, `TODO.md`, `BACKLOG.md`
- `project_management/TASKS/`
- Any markdown file with sprint/task tables

### 2. Read Status

**If Linear mode:**
Status is already available from the `list_issues` queries in Step 1. Each issue has a `state` field. No parsing needed.

**If MD mode:**
The project plan should already have status markers:
- Checklists: `- [x]` (done) vs `- [ ]` (pending)
- Status fields: `completed`, `in-progress`, `not-started`, `blocked`
- Table columns with status values

**If the document has NOT been updated** (everything still shows as pending but code clearly exists), note this as a problem in your report — the sprint-lead failed to update the plan.

### 3. Present Status Report

```
## Sprint Status — [project name] — [date]

### Source: [Linear project: <project-name> (milestone: <sprint-name>) | File: <path to plan document>]

### Available Skills
[paste the skill discovery summary from above — lets the user know what standards apply]

### [Sprint/Phase Name]
| Task | Status | Notes |
|------|--------|-------|

### Summary
- Total: N | Completed: N (X%) | In Progress: N | Blocked: N | Remaining: N

### Verification Checklist Progress
[If the plan has a verification checklist, show checked vs unchecked]

### Recommended Next Actions
- Next tasks to pick up
- Any blocked items and their blockers
```

### 4. Warn on Stale Plan

If the plan document appears out of date (tasks marked pending but related code/commits exist), flag it:
```
Warning: Project plan may be stale — [N] tasks appear implemented but are not marked complete in the document.
Recommend running /sprint-review to reconcile.
```
