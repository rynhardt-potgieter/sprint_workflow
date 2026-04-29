---
description: Revert the last sprint's commits and reset Linear/MD task statuses. Safety-gated — never force-pushes, never destroys work, always uses revert branches over reset --hard
argument-hint: "[milestone-id | sprint-name]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`
Status: !`git status --short 2>/dev/null | head -10 || echo "n/a"`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking & Version Control Detection

### Linear MCP Check
Same as `/sprint-start`. Set `TRACKING_MODE`.

### Version Control
1. `git rev-parse --is-inside-work-tree 2>/dev/null` → **Git mode**, read `${CLAUDE_PLUGIN_ROOT}/skills/git-flow/SKILL.md`.
2. Else `tf vc workspaces 2>/dev/null` → **TFVC mode**, read `${CLAUDE_PLUGIN_ROOT}/skills/tfs-flow/SKILL.md`.
3. Else fail with a clear error — this command requires version control.

## Your Task

Revert a completed (or partially completed) sprint. This is **destructive** — every step is gated on user confirmation, and you NEVER use force-push, `reset --hard` on a shared branch, or `tf vc rollback` without confirmation.

### 1. Refuse Easy Footguns First

Before doing ANY work, check:

1. **Uncommitted changes**: if `git status --short` is non-empty (or `tf vc status` shows pending), tell the user to commit/shelve/stash first and exit. We will not throw away in-flight work.
2. **Detached HEAD**: if HEAD is detached, exit with an error.
3. **Currently on `main` / `master` / `trunk`**: if so, refuse. Rollback creates a revert branch off the sprint branch — running on main is almost certainly a mistake. Ask the user to checkout the correct branch first.

### 2. Identify The Sprint

`$ARGUMENTS` resolves a milestone (Linear) or sprint name (MD). If empty, list candidate sprints (most recently completed first) and ask the user to pick.

For the chosen sprint, gather:
- All commits attributable to it (Git: commits on the sprint branch since branch-off from main; TFVC: changesets in the workspace's sprint folder)
- All Linear Tasks/Stories in the milestone — current statuses
- The current state: was the sprint fully merged to main? partially? not yet?

### 3. Determine Rollback Strategy

| Sprint state | Strategy |
|---|---|
| Not merged to main, not pushed | Strategy A — local branch deletion (after confirmation) |
| Not merged to main, pushed | Strategy B — keep remote branch, create revert branch locally |
| Merged to main, not yet on shared remote | Strategy C — `git revert` of merge commit on a new branch |
| Merged to main, pushed to shared remote | **Refuse if anyone else has pushed since.** Otherwise, Strategy C with extra confirmation |

For TFVC, the analogues:

| State | Strategy |
|---|---|
| Pending changes only | Discard pending after confirmation |
| Checked in, not merged to trunk | `tf vc rollback` per changeset on the sprint branch |
| Merged to trunk | `tf vc merge /discard` from trunk back to a recovery branch |

**Strategy never includes**:
- `git reset --hard` on a remote-tracking branch
- `git push --force` to a shared branch
- `tf vc rollback` on a changeset that other engineers have built changes on top of

### 4. Show The User What Will Happen

Present the plan in detail before any state mutation:

```
## Rollback Plan — <sprint name>

### Sprint State Detected
- Branch: <name>
- Commits to revert: <count> (<oldest> .. <newest>)
- Pushed to remote: <yes / no>
- Merged to main: <yes / no>
- Other authors after merge: <none / list>

### Strategy
<A/B/C>

### Actions That Will Run
1. Create branch `revert/<sprint-name>` from <ref>
2. Run: <git command(s) verbatim>
3. (Linear) Move <N> tasks: Done → Todo. Move <N> stories: Done → Todo.
4. (Linear) Post comment on each: "Rolled back via /sprint-rollback at <timestamp>. Reason: <to be filled>"
5. (MD) Update plan document: mark all stories from `completed` back to `not-started`.
6. (MD) If `docs/BUG_BACKLOG.md` was created during this sprint's bug triage, leave it intact.

### Actions That Will NOT Run
- No force-push
- No deletion of remote branches
- No deletion of unrelated commits

Reason for rollback (will be recorded): _<wait for user>_

Confirm? (type the sprint name to proceed, anything else to abort)
```

Wait for the user to type the sprint name verbatim. Any other input → abort cleanly. This is the explicit confirmation gate.

### 5. Capture The Reason

After the user confirms, ask for a one-line reason. This goes into:
- The revert commit message
- Linear comments
- The MD plan note

If the user gives nothing, default to "Sprint rolled back via /sprint-rollback — no reason provided."

### 6. Execute The Strategy

#### Strategy A — local-only

```bash
git branch -m <sprint-branch> archive/<sprint-branch>-<timestamp>
git checkout main
```

(Don't delete — rename to `archive/`. Recovery is trivial later.)

#### Strategy B — pushed but not merged

```bash
git checkout -b revert/<sprint-name> origin/main
# No revert commits needed — main is already clean
git push -u origin revert/<sprint-name>
```

The original sprint branch stays on the remote untouched. Anyone with that branch can keep working — we have not destroyed history.

#### Strategy C — merged to main

```bash
git checkout -b revert/<sprint-name> main
git revert -m 1 <merge-commit-sha> --no-edit
# Edit revert commit message to include the user-supplied reason
git commit --amend -m "revert(<scope>): roll back sprint <name>

<user-supplied reason>

This reverts merge commit <sha>."
git push -u origin revert/<sprint-name>
```

Then tell the user: "Open a PR from `revert/<sprint-name>` → `main`. We do not auto-merge."

#### TFVC analogues

Use `tf vc rollback /changeset:<id>` on a fresh local branch derived from the sprint workspace, never from trunk directly. After rollback, `tf vc checkin` on the recovery branch only.

### 7. Update Tracking

**Linear mode:**

For each Task and Story in the milestone:
- `save_issue` → status `Todo` (do NOT delete the issue)
- `save_comment` → "Rolled back via /sprint-rollback at <timestamp>. Reason: <reason>. Revert branch: <branch>."

**Do NOT** delete the Linear milestone — it's historical.

**MD mode:**

In the plan document:
- Mark all stories' status fields back to `not-started`
- Append a `## Rollback History` section if not present, with an entry: timestamp, reason, revert branch.

### 8. Final Report

```
## Rollback Complete — <sprint name>

### Strategy
<A/B/C>

### Branch Created
<revert branch name> — <pushed? open PR link if applicable>

### Archived Branch (if applicable)
<archive/<sprint-branch>-<timestamp>>

### Tracking Updated
- Linear: <N> tasks reset to Todo, <N> stories reset to Todo
- (or MD plan reset)

### What Was Preserved
- Original sprint branch (pushed): <yes / no — kept on remote>
- Archived sprint branch (local): <yes / no — local recovery available>
- Linear milestone: kept (historical)
- Linear comments / commit history: kept

### Next Steps
- Open the revert PR (if Strategy C) and merge after review.
- Re-plan via /sprint-plan or /sprint-grill if the sprint is to be re-attempted.
```

---

## Hard Rules

- **Never** force-push to a shared branch.
- **Never** `git reset --hard` on a branch with remote tracking.
- **Never** `git branch -D` — always rename to `archive/`.
- **Never** roll back a sprint that has unrelated commits on top from other engineers — refuse with a clear message.
- **Always** ask the user to type the sprint name to confirm.
- **Always** capture a reason in writing.

## When To Use

- A sprint shipped a regression that's worse than reverting
- A sprint was based on the wrong spec and needs a clean restart
- An incident requires reverting recent changes pending RCA

Do NOT use this for: small bug fixes (use a normal `fix(...)` commit), individual task failures (use `/sprint-resume-task`), or "I changed my mind on the implementation" (just keep iterating in normal flow).
