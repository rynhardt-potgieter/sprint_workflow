# Task Status Transitions

## Valid Transitions

| From | To | When |
|------|-----|------|
| not-started | ready | Prerequisites met, task is unblocked |
| not-started | in-progress | Claimed directly (no ready gate needed) |
| ready | in-progress | Agent or developer claims the task |
| in-progress | ready-to-test | Implementation done, needs QA validation |
| in-progress | blocked | Dependency or issue discovered |
| ready-to-test | completed | QA passed all checks |
| ready-to-test | in-progress | QA failed, needs rework |
| blocked | in-progress | Blocker resolved |

## Status Definitions

- **not-started**: No work begun, may have unmet dependencies
- **ready**: All prerequisites met, available for claiming
- **in-progress**: Actively being worked on by an assignee
- **ready-to-test**: Implementation complete, awaiting QA validation
- **completed**: QA passed, all acceptance criteria met
- **blocked**: Cannot proceed due to external dependency or issue

## Commit Convention for Status Changes

- Claiming: `chore(pm): claim TASK_ID - <title>`
- Completing: `chore(pm): complete TASK_ID - <title>`
- Blocking: `chore(pm): block TASK_ID - <reason>`
- Unblocking: `chore(pm): unblock TASK_ID - <resolution>`
