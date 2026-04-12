---
name: Task Board Operations
description: Use this skill when working with task boards, sprint planning, or task management. Covers discovering task tracking, claiming tasks, status updates, and sprint workflows. Activates when users mention tasks, sprints, backlogs, or task IDs.
version: 1.0.0
---

## Discovering Task Tracking

Projects may track tasks in different ways. Search in this order:

1. **Markdown task boards**: Look for `project_management/TASKS/`, `TODO.md`, `TASKS.md`, `SPRINT.md`, `BACKLOG.md`
2. **GitHub Issues**: `gh issue list --state open`
3. **In-code markers**: Grep for `TODO`, `FIXME`, `HACK` comments
4. **CLAUDE.md**: May reference task tracking conventions

## Markdown Task Board Format

When task boards use markdown tables, they typically follow:
```
| TASK_ID | Title | Status | Priority | Assignee | Detail |
```

## Status Flow

```
not-started --> ready --> in-progress --> ready-to-test --> completed
                  |                          |
                  +--> blocked (with notes) --+
```

## Task Claiming

1. Find available tasks (status: `not-started` or `ready`)
2. Read any detail file or description to understand scope
3. Update status to `in-progress` and set assignee
4. Commit the status change if using file-based tracking

## Task Completion

1. Verify acceptance criteria are met
2. Run quality checks (build, type-check, lint, tests)
3. Update status to `completed`
4. Commit the status change

## Rules

- Always understand the task before starting work
- Keep task tracking formatting intact when editing
- Only one assignee per task at a time
- Blocked tasks must note the blocker
