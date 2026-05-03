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

## Tracking Mode Detection

Before doing anything else, detect which tracking backend and delegation tools are available:

### Linear MCP Check
1. Look for available MCP tools matching `mcp__linear__*` or `mcp__claude_ai_Linear__*`
2. Try calling `list_teams` with whichever prefix exists
3. If it succeeds → **Linear mode**. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
4. If it returns error `-32600` → retry once. If both fail → **MD mode**
5. If no Linear MCP tools exist → **MD mode** (default)

### Codex CLI Check
1. Check if `/codex:rescue` and `/codex:adversarial-review` are available as skills
2. If both present → **Codex available**. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.
3. If either missing → **Codex unavailable**

Set two flags: `TRACKING_MODE` ("linear" / "md") and `CODEX_AVAILABLE` (true / false).

## Your Task

Execute an approved sprint plan. You are the orchestrator. **You NEVER write code yourself** — you dispatch specialist agents and track progress.

> **If this sprint was interrupted (network loss, usage limit, manual stop), do NOT re-run `/sprint-start`.** Run `/sprint-continue` instead — it detects the current phase from Linear/MD state and resumes without re-doing completed work. Use `/sprint-handoff` before stopping if you want a clean snapshot for the next session.

### 1. Load the Sprint Plan

**If MD mode:**
Locate the plan document:
- If arguments specify a path, use that
- Otherwise search: `docs/SPRINT_PLAN.md`, `docs/SPRINT*.md`, `SPRINT_PLAN.md`

Read the full plan. Confirm it contains stories with agent assignments, acceptance criteria, skill assignments, and execution groups.

If the plan is missing these, tell the user to run `/sprint-plan` first.

**If Linear mode:**
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` for query patterns
2. Discover team/project: call `list_teams` / `list_projects` — ask user to confirm (or reuse from sprint-plan session)
3. Find the sprint: call `list_milestones` to find the active sprint milestone (or ask user which milestone)
4. Query Stories: call `list_issues` filtered by `milestoneId` and "Epic" label
5. For each Story, query Tasks: call `list_issues` with `parentId`
6. Reconstruct the sprint plan structure from Linear issues:
   - Parse structured fields from descriptions: `**Agent:**`, `**Skills:**`, `**Codex-eligible:**`, `**Phase:**`
   - Parse acceptance criteria (checkbox items)
   - Parse anti-patterns
   - Check current status of each task — skip tasks already Done
7. If any tasks are already "In Progress" or "Done", note them as resumed/completed
8. If reconstruction fails (missing fields, parse errors), warn the user and ask whether to proceed or fix the issues first

### 2. Read Project Context

- Read `CLAUDE.md` if present
- **Detect version control**: Run `git rev-parse --is-inside-work-tree 2>/dev/null`. If it succeeds, read `${CLAUDE_PLUGIN_ROOT}/skills/git-flow/SKILL.md`. If not, check for TFVC (`tf vc workspaces 2>/dev/null`) and read `${CLAUDE_PLUGIN_ROOT}/skills/tfs-flow/SKILL.md`. You will use the appropriate skill for commits at the end.
- Identify build/test/lint commands for the project

### 3. Confirm Execution Plan with User

Before dispatching ANY agents, present:

```
## Execution Confirmation

### Phase 1: Implementation (parallel)
| Agent | Story/Task | Skills | Executor |
|-------|-----------|--------|----------|

The Executor column shows:
- "Codex" for codex-eligible tasks when Codex is available
- "Claude opus" for tasks routed to Claude agents

### Phase 2: Tests
| Agent | Scope | Skills |
|-------|-------|--------|

### Phase 3: Quality Gates (parallel)
- QA: Codex adversarial review + direct build/lint/spec checks (if Codex available) OR qa-agent (if Codex unavailable)
- pr-review-toolkit:code-reviewer: code quality + patterns (always Claude)

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

## Sprint Sentinel (write before Phase 1, delete in Phase 6)

After approval and BEFORE dispatching any agent, write the sprint-active sentinel so the Stop hook knows to remind you about tracking:

```bash
mkdir -p .claude
# First line: "linear" or "md" — the active tracking source
# Second line (optional): sprint id / milestone / plan filename for reference
echo "linear" > .claude/.sprint-active   # or "md"
```

This sentinel is what activates the Stop hook's tracking reminder. In sessions where it doesn't exist, the hook stays silent. The sentinel MUST be deleted in Phase 6 after final commits land (see "Clear Sprint Sentinel" below).

---

## Execution Flow

### Phase 1: Implementation Agents

Dispatch implementation agents according to the plan's parallel groups. For each task, determine the executor based on `codex-eligible` flag and Codex availability.

**For codex-eligible tasks (when Codex is available):**
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for context passing patterns
2. Read the relevant skill files for this task
3. Compose a full context prompt including:
   - Story title and task title
   - Acceptance criteria (verbatim)
   - Key patterns/standards from skill files (paste content, not just paths — Codex cannot read plugin skills)
   - Target file paths to create/modify
   - Anti-patterns
   - Build/type-check command for self-verification
4. **Update tracking BEFORE dispatch:**
   - MD mode: mark task status as `in-progress` in the plan document
   - Linear mode: call `save_issue` to set task status to "In Progress"
5. Invoke `/codex:rescue --effort high "<composed context>"`
6. After Codex completes:
   - Run build/type-check via Bash to verify
   - Spot-check key acceptance criteria by reading output files
   - If build fails or key ACs are not met → fall back to dispatching the original Claude agent
7. **Update tracking AFTER completion:**
   - MD mode: mark task status as `implementation-complete`
   - Linear mode: call `save_issue` to set status to "In Review". Call `save_comment` with completion summary (files changed, build result)

**For Claude tasks (codex-eligible: false, or Codex unavailable):**
1. Dispatch the assigned agent (`backend-dev`, `frontend-dev`, etc.) as in v2.2.2
2. Include in the agent prompt: skill file paths, acceptance criteria, anti-patterns, build/lint/test commands, file paths
3. **Update tracking BEFORE dispatch:**
   - MD mode: mark task status as `in-progress`
   - Linear mode: call `save_issue` to set task status to "In Progress"
4. **Update tracking AFTER completion:**
   - MD mode: mark task status as `implementation-complete`
   - Linear mode: call `save_issue` to set status to "In Review". Call `save_comment` with completion summary

**Parallel execution rules remain the same:** Launch independent tasks in parallel (multiple Agent calls or Codex invocations in one message). Wait for sequential groups to complete before dispatching the next group.

### Phase 2: Test Writer

After implementation agents complete, dispatch `test-writer`:
- Include the list of implemented stories and their acceptance criteria
- Include test cases from the enrichment (if `/sprint-enrich` was run)
- Include skill file paths for the relevant test frameworks
- Tell it which files were created/modified in Phase 1

**After test-writer completes — update tracking:**
- **MD mode:** Update plan document with test status for each story
- **Linear mode:** Call `save_comment` on relevant Story issues with test coverage summary (unit count, integration count, frameworks used)

### Phase 3: Quality Gates (parallel)

Dispatch two quality checks in parallel:

#### Gate 1: QA

**If Codex is available (Codex-first QA):**
The main session orchestrator handles QA directly — do NOT dispatch the sonnet qa-agent:

1. **Mechanical checks**: Run build, type-check, lint, and test suite via Bash (same commands qa-agent would run)
2. **Spec compliance**: Read implementation files and verify each acceptance criterion is met. Produce a checklist:
   ```
   | Criterion | Met? | Notes |
   |-----------|------|-------|
   ```
3. **Adversarial review**: Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for the focus string mapping table. Compose focus strings from all skills assigned to the sprint's tasks. Invoke:
   ```
   /codex:adversarial-review --base <sprint-branch-or-main> "focus: correctness; <composed focus strings>"
   ```
4. **Parse result**: Convert Codex output into the standard QA report format:
   - CRITICAL issues → BLOCKING
   - MAJOR issues → BLOCKING
   - MINOR issues → WARNING
5. **Consumer breakage check**: Grep for any renamed/removed exports across the codebase
6. **User-facing label audit**: Grep for raw technical strings (snake_case, camelCase, enum values) in UI code

**If Codex is NOT available (fallback):**
Dispatch `qa-agent` (sonnet) as in v2.2.2:
- Include all acceptance criteria from the plan
- Include skill file paths for the domains being validated
- Tell it to run: build, type-check, lint, tests, spec compliance
- Tell it to produce a structured report with BLOCKING/WARNING/INFO
- Architecture drift check (see "Architecture Drift in Phase 3" below)

#### Gate 2: Code Review

Dispatch `pr-review-toolkit:code-reviewer` — **ALWAYS Claude, never Codex.**
- Include skill file paths
- Include acceptance criteria
- Tell it to review all changes since the sprint started
- Tell it to flag UX regressions, spec mismatches, and pattern violations
- Architecture drift check (see "Architecture Drift in Phase 3" below)

#### Architecture Drift in Phase 3

When Linear mode is active AND the sprint's parent Project has an `Architecture & Roadmap` document, both Gate 1 and Gate 2 MUST run the drift check per `${CLAUDE_PLUGIN_ROOT}/skills/architecture-drift-check/SKILL.md`.

Pre-fetch the document **once** in the orchestrator (main session), then pass the body inline to both gates so neither has to call Linear MCP themselves:

1. Pick any Story from this sprint → `get_issue({id, includeRelations: true})` → capture `projectId`.
2. `list_documents({projectId})` → find `Architecture & Roadmap`.
3. `get_document({id})` → capture body.
4. Pass body + the skill path to:
   - **Codex adversarial review** (when Codex available): include the prescribed-model summary in the focus string. Codex doesn't have Linear MCP — it relies on the inline context.
   - **`qa-agent`** (Claude fallback): include in prompt as `## Architecture & Roadmap (compare diff against this)` section + skill path.
   - **`pr-review-toolkit:code-reviewer`**: same as qa-agent.

If the document doesn't exist → both gates skip the drift check with a one-line note (per skill §9). The sprint still completes — the check is graceful.

Findings are merged into the gate's standard report:
- **Erosion** → `BLOCKING` (counted in the existing BLOCKING list, fix loop applies)
- **Drift** → `WARNING` (counted in WARNING list; informational, doesn't block)

**After both gates complete:**
- Collect BLOCKING issues from both reports
- If ZERO blocking issues → proceed to Phase 5
- If ANY blocking issues → proceed to Phase 4
- **Update tracking:**
  - MD mode: update plan document with QA results and review results
  - Linear mode: call `save_comment` on each reviewed Story/Task with the QA report. If BLOCKING issues found, call `save_issue` to set affected task status back to "In Progress"

### Phase 4: Fix Loop

For each BLOCKING issue, classify and route the fix:

**Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for fix routing criteria.**

#### Surgical fixes (Codex — when available)
Route to Codex when ALL of these are true:
- Single file affected
- Fix is mechanical (lint error, null check, missing import, typo, off-by-one, test assertion)
- No design decision required
- No interface/API change

Invoke: `/codex:rescue --effort high "Fix BLOCKING issue in <file>:<line>: <specific error>. Do not change any other files. Run <build command> after fixing."`

#### Architectural fixes (Claude agent)
Route to the original Claude agent when ANY of these are true:
- Multiple files affected
- Interface or API signature change required
- Design pattern issue
- Cross-cutting concern

Re-dispatch the SAME agent that wrote the code with:
1. The original acceptance criteria
2. The specific BLOCKING issues to fix
3. Instruction: "Fix ONLY these issues. Do not refactor or add features."

#### After each fix
1. Re-run QA on the fixed items (using Codex adversarial review or qa-agent, per Phase 3 logic)
2. Loop until all BLOCKING issues are resolved
3. **Update tracking:**
   - MD mode: note which issues were found and resolved in the plan document
   - Linear mode: call `save_comment` on affected task issues with fix details and re-validation result

### Phase 5: Documentation

Dispatch `docs-agent`:
- Update technical documentation for any new features/APIs
- Update CHANGELOG.md with new entries (if the project uses one)
- Update README.md if user-facing behavior changed
- Bump version numbers if applicable
- Create ADRs for any significant architectural decisions made during the sprint

**Update the plan** after docs complete.

**After docs complete — update tracking:**
- **MD mode:** Update plan document with documentation status
- **Linear mode:** Call `save_comment` on relevant Story issues noting which documentation was updated (files list)

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
6. **Associate work items** (TFVC): use `/associate` or `/resolve` with checkins

#### Finalize Tracking

**MD mode:**
- Mark all stories as `completed` in the plan document
- Commit the plan update separately: `chore(pm): update sprint plan — mark stories complete`

**Linear mode:**
- For each completed Task: call `save_issue` to set status to "Done"
- For each completed Story (all tasks Done): call `save_issue` to set status to "Done"
- Call `save_comment` on each Story with commit hashes and sprint summary
- Do NOT update any markdown plan file

#### Clear Sprint Sentinel

After tracking is finalized AND commits/checkins have landed, remove the sentinel so future ordinary sessions don't get nagged:

```bash
rm -f .claude/.sprint-active .claude/.sprint-active.last-nag
```

Do NOT delete the sentinel earlier — it must survive until tracking is fully reconciled, otherwise an interrupted Phase 6 leaves no signal for the next session.

---

## Plan Status Tracking

**CRITICAL: Update tracking after EVERY phase transition.**

**MD mode:**
The plan document is the source of truth. If you get interrupted, the next session must be able to pick up by reading the plan.

Status flow per story:
```
not-started → in-progress → implementation-complete → tests-written → review-complete → fixes-applied → documented → committed
```

**Linear mode:**
Linear issues are the source of truth. Status transitions via `save_issue`:
```
Backlog → Todo → In Progress → In Review → Done
```

Phase mapping:
- Sprint starts: all tasks Backlog → Todo (bulk move)
- Phase 1 dispatch: Todo → In Progress
- Phase 1 complete: In Progress → In Review
- Phase 3 pass: In Review → Done
- Phase 3 fail (blocking): In Review → In Progress (back for fixes)
- Phase 4 fix + re-validate: In Progress → Done
- Phase 6 complete: verify all → Done

**If Linear fails mid-sprint:** Prompt user to approve markdown fallback. If approved, create `docs/SPRINT_PLAN.md` with current state reconstructed from Linear and continue in MD mode.

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

**If Linear mode:** Also post this complete summary as a `save_comment` on each Epic-labeled Story issue in the sprint.
