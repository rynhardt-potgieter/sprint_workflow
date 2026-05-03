---
name: worktree-handoff
description: Contract for moving code OUT of a git worktree (subagent or Codex thread) back into the orchestrator's branch without losing work or manually copying files. Use this skill any time an agent is launched with `isolation: worktree`, any time `/codex:rescue` or Codex Handoff produces a branch in a separate working tree, or any time the orchestrator is about to integrate work from one or more parallel agents. Defines the subagent-side exit contract (commit, verify, emit HANDOFF block) and the orchestrator-side integration contract (parse, fetch, merge, cleanup).
version: 1.0.0
---

# Worktree Handoff

Worktree isolation is a **safety boundary**, not a delivery mechanism. The boundary protects the main session from concurrent edits — but the code only gets back if both sides follow the contract below. When the contract is skipped, work gets lost in three ways: (1) the agent exits with uncommitted changes and the branch points at an old commit; (2) the orchestrator forgets to `git fetch` the branch and "fixes" the missing files by copying them by hand; (3) the worktree is removed before the merge is confirmed.

This skill defines two roles. Every agent operating in a worktree plays the **Subagent** role. The session that dispatched it plays the **Orchestrator** role. Codex threads created via `/codex:rescue` or Codex Handoff follow the same contract — they are subagents for the purpose of this skill.

---

## When This Skill Applies

- An agent was launched with `isolation: worktree` (Anthropic Agent tool).
- A `/codex:rescue` invocation created a branch in a Codex-managed worktree.
- The orchestrator is about to merge work from one or more parallel agents.
- A Codex thread is being moved Local ↔ Worktree via Codex Handoff.

This skill does **NOT** apply to:

- Read-only research agents (Explore, code-reviewer, security-agent in audit mode). Worktree isolation for these is wasted setup — they should not be launched with `isolation: worktree` in the first place.
- Tasks that the main session executes directly in the main working tree.

---

## Subagent Contract (Exit Checklist)

Every agent operating inside a worktree MUST do all of the following before its final message. No exceptions.

1. **Commit every change.** No exit with a dirty tree.
   - Run `git status --porcelain` — if it returns anything, commit it.
   - Use a real commit message even for WIP. `git commit -m "wip(<task-id>): <one line>"` is fine; `git commit -m "wip"` is not.
   - Untracked files count. `git add -A` if you intended them to be part of the task; otherwise delete them before commit.

2. **Verify the build.** Run the project's build/typecheck command. Capture the exit status.
   - If it fails, commit anyway, then report `build: fail` in the handoff block.
   - Do not silently fix unrelated issues to make the build pass — that pollutes the diff.

3. **Run tests if cheap.** If the project has a fast test suite (under ~60s), run it and capture the result. Otherwise skip and report `tests: skipped`.

4. **Emit the HANDOFF block.** This is the orchestrator's only reliable signal. Print it as the LAST thing in your final message, in this exact shape (it is parsed):

   ```
   HANDOFF
   branch: agent/<task-id>-<slug>
   worktree: <absolute or repo-relative path>
   head: <full commit SHA>
   files: <comma-separated list of changed files, or "see git diff">
   build: pass | fail | skipped
   tests: pass | fail | skipped
   notes: <one short line — blockers, follow-ups, or "ok">
   ```

   Get the SHA via `git rev-parse HEAD`. Get the file list via `git diff --name-only main..HEAD` (or whatever base branch was used).

5. **Never `git worktree remove` your own worktree.** Cleanup belongs to the orchestrator. Removing it yourself before the orchestrator has fetched the branch can leave the branch unreachable.

6. **Never push.** Pushing is the orchestrator's call. The orchestrator may decide to merge locally, open a PR, or discard.

### Subagent failure modes

- **Build won't run** (missing toolchain in worktree): commit what you have, report `build: skipped`, and add a `notes:` line explaining. Do not abandon the work.
- **Conflicts with main appeared mid-task** (rare with isolation, possible with rebases): do NOT resolve them — commit your changes on the agent branch as-is and let the orchestrator handle integration. Resolving conflicts inside a transient worktree often loses context the orchestrator needs.
- **Out of scope discovery**: if you find work that exceeds your task, commit your in-scope work and put a `TODO(handoff):` note in `notes:`. Do not expand scope.

---

## Orchestrator Contract (Integration Checklist)

Every session that dispatched a worktree-isolated agent MUST do all of the following.

### Before dispatch

1. **Verify worktree directory is gitignored.** If using a project-local convention like `.worktrees/`:
   ```bash
   git check-ignore -q .worktrees || { echo ".worktrees/" >> .gitignore && git add .gitignore && git commit -m "chore: ignore worktree directory"; }
   ```
   If the worktree path leaks into `git status` of the main tree, agents will accidentally commit each other's files.

2. **Choose a unique branch name per task.** Format: `agent/<task-id>-<slug>`. Two parallel agents must never share a branch.

3. **For research-only agents, do NOT use `isolation: worktree`.** It is wasted setup with no payoff.

### After dispatch — parsing

4. **Find the HANDOFF block in the agent's final message.** If it is missing, treat the task as **failed**. Do not try to recover by reading the worktree directly — a missing block usually means uncommitted state. Re-dispatch with: "Your previous run did not emit the required HANDOFF block. Commit any pending changes and emit it now."

5. **Trust the block. Verify the SHA.** Run `git -C <worktree> rev-parse HEAD` and confirm it matches `head:` in the block. Mismatch = the agent kept working after emitting the block; treat as failed and re-dispatch.

### Integration — single agent

6. **Fetch the branch into the main repo.** A worktree's commits are already in the shared `.git/`, but the branch ref needs to be visible from your working tree:
   ```bash
   git fetch <worktree-path> <branch-name>:<branch-name>
   ```
   Or, if the worktree shares the same `.git/`, the branch is already visible — just `git branch --list <branch-name>` to confirm.

7. **Merge into the orchestrator's branch.** Default to a real merge commit for traceability:
   ```bash
   git merge --no-ff agent/<task-id>-<slug> -m "merge(<task-id>): <task title>"
   ```
   Use `--squash` only if the project's commit-style convention requires it (check `git-flow` or `tfs-flow`).

8. **Resolve conflicts in the orchestrator's tree only.** Never check out the agent's branch inside its worktree to resolve — that fragments the resolution across two working copies.

9. **If the agent reported `build: fail` — DO NOT MERGE.** Re-dispatch the agent (or route a surgical fix to Codex per `codex-delegation`) with the failure as input. A merged broken build pollutes main and is the most common cause of "where did this regression come from" later.

### Integration — multiple parallel agents

10. **For 1–2 agents:** merge sequentially into the orchestrator branch. Conflicts, if any, are handled normally.

11. **For 3+ agents:** create an integration branch, merge each agent branch into it, run the build/tests once, then fast-forward the orchestrator branch. This isolates merge-time failures from main and from individual agent branches.
    ```bash
    git checkout -b integration/<sprint-id>
    git merge --no-ff agent/...   # repeat per agent
    <build && test>
    git checkout <orchestrator-branch> && git merge --ff-only integration/<sprint-id>
    ```

### Cleanup — only after merge is committed

12. **Remove the worktree.**
    ```bash
    git worktree remove <worktree-path>
    ```
    If the agent left lock files or build artifacts, prefer `git worktree remove --force` over manual `rm -rf` — the latter leaves the worktree registered.

13. **Delete the branch ONLY if it was merged with `--no-ff` or `--squash`.**
    ```bash
    git branch -d agent/<task-id>-<slug>   # safe delete; refuses if unmerged
    ```
    Never use `-D` unless you have explicit confirmation the branch is fully integrated.

14. **Do not delete the integration branch immediately.** Keep it for the rest of the sprint as a recovery point.

---

## Codex-Specific Notes

Codex CLI threads behave like subagents for this skill, with three additions:

- **Detached HEAD by default.** A Codex worktree may not be on a named branch. Before exiting, the Codex thread must run `git checkout -b agent/<task-id>-<slug>` and commit on that branch. Without a branch, the orchestrator cannot fetch the work.
- **`.gitignored` files don't survive Handoff.** If the task requires uncommitted local config (e.g., `.env`), the orchestrator must regenerate it on its side; the agent must NOT include it in the diff.
- **Codex Handoff (Local ↔ Worktree) replaces step 6 (fetch).** The branch becomes available in Local automatically. The orchestrator still does steps 7–14 unchanged.

Reference `codex-delegation` SKILL.md for when to delegate to Codex in the first place; this skill picks up at the moment Codex starts writing code.

---

## Anti-Patterns (Hard Rules)

- **Never copy files out of a worktree manually.** If the orchestrator finds itself reading files from `.worktrees/...` and writing them into the main tree, stop — the agent skipped the commit step. Re-dispatch with the exit contract.
- **Never share a branch name across two parallel agents.** Each task gets `agent/<task-id>-<slug>`.
- **Never let a subagent push.** The orchestrator owns the remote.
- **Never let a subagent remove its own worktree.** Cleanup is the orchestrator's job, after merge.
- **Never run `isolation: worktree` for read-only research agents.** Setup cost without benefit.
- **Never reuse a worktree across tasks.** One worktree per task; remove and recreate.
- **Never merge a branch where the agent reported `build: fail`.** Fix first, merge second.

---

## Quick Reference

**Subagent (5 lines before exit):**
```bash
git add -A && git commit -m "feat(<task-id>): <summary>" || true
<project build command>; BUILD_STATUS=$?
git rev-parse HEAD
git diff --name-only main..HEAD
# Then print the HANDOFF block as the last thing in your final message.
```

**Orchestrator (after seeing HANDOFF block):**
```bash
git fetch <worktree-path> <branch>:<branch>
git merge --no-ff <branch> -m "merge(<task-id>): <title>"
# resolve conflicts here, in main tree, if any
<project build command>   # verify
git worktree remove <worktree-path>
git branch -d <branch>
```
