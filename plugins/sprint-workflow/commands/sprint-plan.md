---
description: Create a sprint plan — invokes the Product Manager agent to analyze specs and produce a structured plan with agent assignments, parallel work, and dependencies
argument-hint: "[goal or spec reference] from [plan-file-path]"
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

You are the orchestrator. You have context from the user about what they want to build. Your job is to feed that context to the `product-manager` agent and get back a structured sprint plan.

**You do NOT write the plan yourself.** You dispatch the PM agent with the right context.

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
7. **Output format requirements** — the PM MUST produce:

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
6. Commit (logical units via git-flow) → Push

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

Once approved, write the plan to a file:
- Default: `docs/SPRINT_PLAN.md` (or the path the user specifies)
- If a plan file already exists, append as a new sprint section or create a new file

The plan document is the source of truth for `/sprint-start`.
