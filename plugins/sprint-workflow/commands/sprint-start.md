---
description: Execute an approved sprint plan — dispatches agents in the defined flow, runs quality gates, fixes issues, documents, and commits
argument-hint: "[plan-file-path]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Your Task

Execute an approved sprint plan. You are the orchestrator. **You NEVER write code yourself** — you dispatch specialist agents and track progress.

### 1. Load the Sprint Plan

Locate the plan document:
- If arguments specify a path, use that
- Otherwise search: `docs/SPRINT_PLAN.md`, `docs/SPRINT*.md`, `SPRINT_PLAN.md`

Read the full plan. Confirm it contains:
- Stories with agent assignments
- Acceptance criteria per story
- Skill assignments per agent
- Execution groups (parallel vs sequential)

If the plan is missing these, tell the user to run `/sprint-plan` first.

### 2. Read Project Context

- Read `CLAUDE.md` if present
- **Detect version control**: Run `git rev-parse --is-inside-work-tree 2>/dev/null`. If it succeeds, read `${CLAUDE_PLUGIN_ROOT}/skills/git-flow/SKILL.md`. If not, check for TFVC (`tf vc workspaces 2>/dev/null`) and read `${CLAUDE_PLUGIN_ROOT}/skills/tfs-flow/SKILL.md`. You will use the appropriate skill for commits at the end.
- Identify build/test/lint commands for the project

### 3. Confirm Execution Plan with User

Before dispatching ANY agents, present:

```
## Execution Confirmation

### Phase 1: Implementation (parallel)
| Agent | Story | Skills |
|-------|-------|--------|

### Phase 2: Tests
| Agent | Scope | Skills |
|-------|-------|--------|

### Phase 3: Quality Gates (parallel)
- qa-agent: build + lint + test + spec compliance
- pr-review-toolkit:code-reviewer: code quality + patterns

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

## Execution Flow

### Phase 1: Implementation Agents

Dispatch implementation agents (`backend-dev`, `frontend-dev`, `dba-agent`, etc.) according to the plan's parallel groups.

**For each agent prompt, include:**
- Skill file paths to read (from the plan's skill assignments)
- Verbatim acceptance criteria from the plan
- Anti-patterns from the plan (if enriched via `/sprint-enrich`)
- Build/lint/test commands to verify their work
- File paths for where to create/modify things

Launch independent stories **in parallel** (multiple Agent calls in one message).
For sequential groups, wait for the previous group to complete before dispatching.

**After each agent completes:**
- Update the plan document: mark story status as `in-progress` → `implementation-complete`
- Note any issues or deviations the agent reported

### Phase 2: Test Writer

After implementation agents complete, dispatch `test-writer`:
- Include the list of implemented stories and their acceptance criteria
- Include test cases from the enrichment (if `/sprint-enrich` was run)
- Include skill file paths for the relevant test frameworks
- Tell it which files were created/modified in Phase 1

**After test-writer completes:**
- Update the plan: mark test status for each story

### Phase 3: Quality Gates (parallel)

Dispatch BOTH in parallel:

#### qa-agent
- Include all acceptance criteria from the plan
- Include skill file paths for the domains being validated
- Tell it to run: build, type-check, lint, tests, spec compliance
- Tell it to produce a structured report with BLOCKING/WARNING/INFO

#### pr-review-toolkit:code-reviewer
- Include skill file paths
- Include acceptance criteria
- Tell it to review all changes since the sprint branch started
- Tell it to flag UX regressions, spec mismatches, and pattern violations

**After both complete:**
- Collect BLOCKING issues from both reports
- If ZERO blocking issues → proceed to Phase 5
- If ANY blocking issues → proceed to Phase 4

### Phase 4: Fix Loop

For each BLOCKING issue:
1. Identify which agent's work is affected (backend-dev, frontend-dev, etc.)
2. Re-dispatch THAT SAME agent with:
   - The original story + acceptance criteria
   - The specific BLOCKING issues to fix
   - Instruction: "Fix ONLY these issues. Do not refactor or add features."
3. After fixes, re-dispatch qa-agent to validate ONLY the fixed issues
4. Loop until all BLOCKING issues are resolved

**Update the plan** after each fix: note which issues were found and resolved.

### Phase 5: Documentation

Dispatch `docs-agent`:
- Update technical documentation for any new features/APIs
- Update CHANGELOG.md with new entries (if the project uses one)
- Update README.md if user-facing behavior changed
- Bump version numbers if applicable
- Create ADRs for any significant architectural decisions made during the sprint

**Update the plan** after docs complete.

### Phase 6: Commit & Push

YOU (the orchestrator) handle commits directly — do NOT dispatch an agent for this.

1. **Use the version control skill** read in Step 2 (`git-flow` or `tfs-flow`)
2. **Review all changes**:
   - Git: `git diff --stat`
   - TFVC: `tf vc status`
3. **Commit/checkin in logical units** — NOT one giant changeset. Split by:
   - Each feature/story gets its own commit/checkin
   - Test additions get their own commit/checkin
   - Documentation gets its own commit/checkin
   - Fixes from the review loop get their own commit/checkin
4. **Message format** (same for both Git and TFVC):
   - `feat(<scope>): <summary>` for new features
   - `fix(<scope>): <summary>` for bug fixes
   - `test(<scope>): <summary>` for test additions
   - `docs(<scope>): <summary>` for documentation
5. **Push/checkin** to the remote:
   - Git: `git push`
   - TFVC: changes are on the server after `tf vc checkin`
6. **Update the plan document** — mark all stories as `completed`
7. **Commit the plan update** separately: `chore(pm): update sprint plan — mark stories complete`
8. **Associate work items** (TFVC): use `/associate` or `/resolve` with checkins

---

## Plan Status Tracking

**CRITICAL: Update the plan document after EVERY phase transition.**

The plan is the source of truth. If you get interrupted or the session ends, the next session must be able to pick up where you left off by reading the plan.

Status flow per story:
```
not-started → in-progress → implementation-complete → tests-written → review-complete → fixes-applied → documented → committed
```

After each phase, update the relevant stories in the plan file with their current status.

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
