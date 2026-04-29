---
description: Create a sprint plan — invokes the Product Manager agent to analyze specs and produce a structured plan with agent assignments, parallel work, and dependencies. Pass --grill to interrogate the user against the domain model before planning when the spec is loose.
argument-hint: "[--grill] [goal or spec reference] [from <plan-file-path>]"
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
3. If it succeeds → **Linear mode**. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` for taxonomy, labels, and creation patterns.
4. If it returns error `-32600` → retry once. If both fail → **MD mode**
5. If no Linear MCP tools exist → **MD mode** (default)

### Codex CLI Check
1. Check if `/codex:rescue` and `/codex:adversarial-review` are available as skills in this session
2. If both present → **Codex available**. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for eligibility criteria.
3. If either missing → **Codex unavailable**

Set two flags for the rest of this command:
- `TRACKING_MODE`: "linear" or "md"
- `CODEX_AVAILABLE`: true or false

Report detected mode to the user:
```
Tracking: [Linear (project: X) | Markdown]
Codex delegation: [Available | Unavailable]
```

## Your Task

You are the orchestrator. You have context from the user about what they want to build. Your job is to feed that context to the `product-manager` agent and get back a structured sprint plan.

**You do NOT write the plan yourself.** You dispatch the PM agent with the right context.

### 0. Grill Pre-Flight (when `--grill` is passed)

If `$ARGUMENTS` contains `--grill`, OR the user's request is high-level / ambiguous and you sense unstated decisions:

1. Strip the `--grill` flag from the arguments.
2. Run `/sprint-grill` first with the remaining arguments as its topic. See `${CLAUDE_PLUGIN_ROOT}/commands/sprint-grill.md` for the procedure.
3. The grilling session writes a structured summary to `docs/grilling/<topic-slug>-<YYYY-MM-DD>.md` with locked decisions, scope, API contracts, failure modes, and suggested sprint-plan inputs.
4. Once grilling completes, continue with Step 1 below — pass the grilling summary's path into the PM agent's context as the **primary spec input**. The PM uses the locked decisions verbatim, not the original loose request.

If the user did not pass `--grill` and the spec is already detailed (full PRD, finished issue list, locked design doc), skip this step and go straight to Step 1.

### 1. Gather Context

Before dispatching the PM agent, collect what it needs:

1. **User's intent**: The arguments above contain what the user wants. If vague, ask for clarification before proceeding.
2. **Project conventions**: Read `CLAUDE.md` if present — note the tech stack, architecture, and any spec document paths referenced.
3. **Spec documents**: If arguments reference a file path (e.g., "from docs/PRD.md"), read it. If CLAUDE.md references spec docs, note their paths.
4. **Current codebase state**: Run a quick `git log --oneline -10` and check project structure to understand what's already built.
5. **Available skills**: Use the auto-discovered skills above to understand what standards apply.

### 2. Dispatch the Product Manager Agent

Launch the `product-manager` agent with a prompt that includes:

1. **The user's goal** — quote verbatim from the arguments or conversation context
2. **Spec document paths** — tell the agent which files to read for full requirements
3. **CLAUDE.md path** — so it reads project conventions
4. **Current state summary** — what's already built (from your quick scan)
5. **Available skills list** — paste the skill discovery output so the PM knows the tech stack
6. **Agent roster** — the PM must assign tasks to these agents:
   - `backend-dev` — server-side code (.NET, Rust, Go, Python, Node.js)
   - `frontend-dev` — client-side UI (React, Vue, Svelte, Angular)
   - `test-writer` — unit, integration, and snapshot tests
   - `qa-playwright` — E2E browser testing, visual regression, accessibility
   - `dba-agent` — schema design, migrations, index audit
   - `security-agent` — security audit, secret scanning, dependency check
   - `docs-agent` — documentation, changelogs, ADRs
7. **Tracking mode**: Tell the PM whether we are in Linear mode or MD mode:
   - If Linear mode: instruct the PM to read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` and structure each story description as a self-contained Linear issue (include all ACs, agent assignment, skills, anti-patterns, and codex eligibility as structured markdown fields)
   - If MD mode: standard plan document format (no change from current behavior)
8. **Codex eligibility**: If Codex is available, instruct the PM to flag each Task with `codex-eligible: true/false` and a one-line rationale, using the criteria from `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`. If Codex is unavailable, omit these fields.
9. **Output format requirements** — the PM MUST produce:

```
# Sprint Plan — [Sprint Name]

## Sprint Goal
[One sentence]

## Definition of Done
[Checklist — the standard DoD from PM agent]

## Stories

### Parallel Group 1: [Feature/Theme]
Stories in this group have NO dependencies on each other and CAN run in parallel.

#### US-01: [Title]
- **Agent**: [agent name]
- **Skills**: [skill files the agent must read]
- **As a** [role], **I want** [feature], **So that** [value]
- **Acceptance Criteria:**
  - [ ] ...
- **Anti-patterns:** ...
- **Technical Notes:** ...
- **Estimate:** [S/M/L]
- **Codex-eligible:** [true/false — only if Codex is available]
- **Codex rationale:** [one-line reason — only if Codex is available]

#### US-02: [Title]
[same format]

### Sequential Group 2: [depends on Group 1]
Stories in this group depend on Group 1 completing first.

[stories...]

### Post-Implementation
- **test-writer**: Write tests for all implemented features
- **qa-agent + pr-review-toolkit:code-reviewer**: Run in parallel after tests
- **docs-agent**: Technical docs, version bumps, READMEs

## Execution Flow
1. Parallel Group 1 agents → 
2. test-writer → 
3. qa-agent + pr-review-toolkit (parallel) → 
4. Fix loop (agents fix their own issues) → 
5. docs-agent → 
6. Commit/Checkin (logical units via git-flow or tfs-flow) → Push

## Dependencies
[Cross-story dependencies]

## Risks & Open Questions
[Flagged ambiguities]

## Out of Scope
[Explicitly deferred items]
```

### 3. Present the Plan to the User

When the PM agent returns, present the complete plan to the user. Do NOT start execution. Wait for the user to:
- **Approve** the plan as-is
- **Request changes** (re-dispatch PM with feedback)
- **Run `/sprint-enrich`** to have specialist agents review the plan before starting

### 4. Save the Plan

Once approved:

**If MD mode (default):**
- Write the plan to `docs/SPRINT_PLAN.md` (or the path the user specifies)
- If a plan file already exists, append as a new sprint section or create a new file
- The plan document is the source of truth for `/sprint-start`

**If Linear mode:**
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` for exact creation patterns
2. **Discover team/project**: Call `list_teams` and `list_projects` — ask the user which project to use (skip if already known from detection)
3. **Ensure labels exist**: Call `list_issue_labels` on the team. For each required label (Epic, Task, Feature, Bug, Improvement, QA, tech-debt, Decision, Deferred) that doesn't exist, create it via `create_issue_label` with the hex color from the skill file
4. **Create Sprint Milestone**: Call `save_milestone` with the sprint name and optional target date
5. **Create Story issues**: For each Story in the plan, call `save_issue` with:
   - Title: the story title
   - Labels: Epic + relevant type label (Feature, Bug, etc.)
   - milestoneId: the sprint milestone ID
   - Description: full self-contained description with ACs, agent, skills, codex-eligible fields, anti-patterns, dependencies
   - Priority and estimate from the plan
6. **Create Task sub-issues**: For each Task under a Story, call `save_issue` with:
   - parentId: the Story's issue ID
   - Labels: Task + relevant type label
   - Description: agent assignment, skills, codex-eligible flag, ACs, dependencies
7. **Set dependencies**: For tasks with dependencies, call `save_issue` with `blockedBy` field
8. **Discover statuses**: Call `list_issue_statuses` on the team to get status name → ID mapping
9. **Set initial status**: Move all created Stories and Tasks from Backlog to "Todo" — call `save_issue` with the "Todo" status ID for each issue. This marks them as sprint-ready.
10. **Present results**: Show created issue IDs/URLs to the user
11. Do **NOT** also create a markdown plan file — Linear IS the source of truth
