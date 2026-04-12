# Phase Board Markdown Format

## Table Structure

Every phase board uses this exact column order. Do NOT reorder or add columns.

```markdown
| TASK_ID | Title | Status | Priority | Assignee | Repo | PR | Commit | Detail |
|---------|-------|--------|----------|----------|------|----|--------|--------|
| SET-001 | Setup Dev Environment | completed | high | alice | my-project | #12 | abc123 | [Detail](./DETAILS/SET-001.md) |
```

## Column Rules

- **TASK_ID**: Phase prefix + sequential number (SET-001, COR-002, etc.)
- **Title**: Short descriptive title (< 60 chars)
- **Status**: One of: not-started, ready, in-progress, ready-to-test, completed, blocked
- **Priority**: One of: high, medium, low
- **Assignee**: Agent name or developer name. Empty if unassigned.
- **Repo**: Target repository name (e.g., my-project, my-api)
- **PR**: Pull request number/link. Empty until PR created.
- **Commit**: Short commit hash. Empty until committed.
- **Detail**: Markdown link to `./DETAILS/<TASK_ID>.md`

## Formatting Rules

1. Keep pipe alignment consistent — do not introduce extra spaces
2. Never delete rows — only update cell values
3. If adding new tasks, append to the bottom of the table
4. Use lowercase for status values
5. Detail links must use relative paths: `[Detail](./DETAILS/TASK_ID.md)`

## Detail File Structure

Each `DETAILS/<TASK_ID>.md` file follows:

```markdown
# TASK_ID — Title

## Summary
Brief description of what needs to be done.

## Steps
1. Step-by-step implementation plan

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Repositories Impacted
- repo-name

## Links
- References to specs, designs, or related tasks
```
