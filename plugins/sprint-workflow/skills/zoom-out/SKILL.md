---
name: zoom-out
description: Recovery procedure for agents stuck in unfamiliar code — when grep/find/scope returns confusing results, when 3+ navigation attempts have failed, or when the task touches a subsystem the agent doesn't understand. Defines a fast widening recipe to build context before continuing.
version: 1.0.0
---

# Zoom Out

A small skill that defines what to do when an agent is **stuck**. Stuck means: navigation has failed repeatedly, the local code doesn't make sense in isolation, or the task crosses a boundary into unfamiliar architecture.

The default failure mode is to keep grepping more aggressively. This skill prescribes the opposite: **stop, widen, then return**.

---

## Trigger Conditions

Use this skill when **any** of the following are true:

- You have run 3+ search/navigation commands without converging on the right file
- You found the file but can't tell which function/class is the entry point
- The code uses naming conventions or patterns that don't match anything you've seen
- The task description references a concept (e.g., "the workflow runtime", "the audit pipeline") and you can't locate where that concept lives
- An interface/abstraction is involved and you don't know who its callers or implementers are

Do **not** use this skill for routine searches that are working. The 3-command rule (CLAUDE.md) still applies — you should also be writing code, not navigating forever.

---

## The Recipe

### 1. Stop searching

Set down whatever grep/find loop you were running. It is not converging. More searches will not help.

### 2. Find the entry point

Use the project's structural intelligence, in this order:

1. **Scope CLI** (mandatory per global CLAUDE.md): `scope status`, then `scope sketch <path>` for class/module structure, `scope callers <symbol>` to walk up, `scope find <pattern>` for symbol lookup. Cheaper than grep and returns structure.
2. **README / CLAUDE.md / docs/** at the project root. Read whatever section names the subsystem you're in.
3. **Folder structure**: `ls` the parent directories. Folder names often name the entry point (`*/handlers`, `*/runtime`, `*/api`).
4. **`main.rs` / `Program.cs` / `index.ts` / `App.tsx`**: if the project has an entry point, read its top 100 lines. Routing tables usually live there.

### 3. Read the immediate ancestor

Once you find the entry point or the nearest landmark, read **one level above** the file you were stuck on:

- The module that imports your file
- The interface your class implements
- The route that calls your handler
- The parent component that renders your component

This is almost always where the missing context lives.

### 4. Read CLAUDE.md / spec docs

If a spec document is referenced in CLAUDE.md (e.g., "see `docs/ux-report.md`"), read the relevant section. Specs explain *why* the code is shaped the way it is, which grep cannot tell you.

### 5. Git history as last resort

`git log --oneline <file>` and `git blame` on the confusing region. Recent commit messages often explain the design choice that's making the code hard to read.

### 6. Return to the task

You should now have:
- The entry point and its name
- The boundary your task lives inside
- The conventions used in this subsystem

If you still don't, **escalate**. Tell the orchestrator (or the user, if you're the main session) that you're blocked, list what you tried, and ask for the missing context. Do not guess.

---

## What "Returning" Looks Like

When you come back to the task after zooming out, write down (in your own working notes or in your eventual report):

- The entry point: `<file>:<line>` and `<symbol>`
- The boundary: which module/layer you're operating inside
- The conventions: naming, error handling, async style — whatever you saw in the ancestor

This forces the context to actually land. Skipping this step means the next grep will leave you re-stuck.

---

## Anti-Patterns

| Anti-pattern | Better |
|---|---|
| Running grep with progressively longer regexes | Run `scope sketch` on the directory once |
| Reading 10 files at random to "build context" | Find the entry point first, then read 1 file above your target |
| Asking the user for help on the first failed search | Try the recipe; ask only after step 6 |
| Inferring conventions from the file you're stuck on | The file may itself be wrong; read the ancestor instead |
| Skipping spec/CLAUDE.md because "the code is the truth" | Specs explain intent; intent prevents the wrong fix |

---

## Integration

This skill is a **read-when-stuck** dependency for `backend-dev`, `frontend-dev`, `test-writer`, `qa-agent`, `dba-agent`, `security-agent`. They do not read it preventively — only when the trigger conditions hit.

The 3-command rule from global CLAUDE.md applies first. If you have run 3 navigation commands and not edited a file, switch to this skill instead of running a 4th.
