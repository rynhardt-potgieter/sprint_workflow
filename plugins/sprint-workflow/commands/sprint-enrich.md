---
description: Enrich a sprint plan — invokes specialist agents to review the plan and add critical details, gotchas, anti-patterns, and test cases
argument-hint: "[plan-file-path]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Your Task

You have a sprint plan (from `/sprint-plan`). Your job is to dispatch specialist agents to review and enrich it with domain expertise BEFORE execution begins.

**You do NOT modify the plan yourself.** You dispatch agents, collect their feedback, and present a consolidated enrichment to the user.

### 1. Locate the Sprint Plan

If arguments specify a file path, use that. Otherwise search for:
- `docs/SPRINT_PLAN.md`
- `docs/SPRINT*.md`
- `SPRINT_PLAN.md`

Read the full plan document.

### 2. Analyze the Plan for Enrichment Opportunities

Scan each story in the plan and identify which specialist agents should review it:

| If the story involves... | Dispatch this agent |
|--------------------------|-------------------|
| Database schema, migrations, or queries | `dba-agent` |
| Auth, user data, API endpoints, secrets | `security-agent` |
| New API endpoints or contract changes | `backend-dev` (for API design review) |
| UI components or user flows | `frontend-dev` (for UX/accessibility review) |
| E2E user flows or critical paths | `qa-playwright` (for test case planning) |
| All stories | `test-writer` (for test strategy) |

### 3. Dispatch Review Agents in Parallel

Launch the relevant agents simultaneously. Each agent prompt MUST include:

1. **The full sprint plan** (or the relevant stories)
2. **Their skill file paths** from `${CLAUDE_PLUGIN_ROOT}/skills/`
3. **Project CLAUDE.md path** (if present)
4. **Their specific review mandate:**

#### dba-agent Review Mandate
- Review all stories that touch the database
- Flag migration safety issues (locking, backward compatibility)
- Recommend indexes for new query patterns
- Identify PII/compliance concerns with new data
- Add migration pre-flight checklist items to relevant stories
- Suggest expand-contract pattern where needed

#### security-agent Review Mandate
- Review all stories for OWASP Top 10 2025 concerns
- Flag auth/authorization gaps in acceptance criteria
- Identify PII exposure risks in new features
- Add security-specific acceptance criteria to stories
- Flag any dependency additions that need vetting

#### test-writer Review Mandate
- For each story, list the test cases that should be written:
  - Unit tests (happy path, error path, edge cases)
  - Integration tests (API contracts, database interactions)
  - What should be mocked vs tested against real services
- Flag stories with insufficient testability (missing acceptance criteria)
- Recommend test fixtures or setup needed

#### qa-playwright Review Mandate
- For each user-facing story, list E2E test scenarios:
  - Critical user flows to test
  - Accessibility checks needed
  - Visual regression baseline pages
- Flag stories that need E2E coverage vs unit-test-only stories

#### backend-dev / frontend-dev Review Mandate
- Flag technical risks or complexity the PM may have underestimated
- Identify missing technical acceptance criteria
- Note anti-patterns to avoid for each story
- Suggest implementation approach or existing patterns to reuse

### 4. Consolidate Enrichments

When all review agents return, consolidate their feedback into a structured enrichment report:

```
## Sprint Enrichment Report

### DBA Review
| Story | Finding | Severity | Addition to Plan |
|-------|---------|----------|-----------------|

### Security Review
| Story | Finding | Severity | Addition to Plan |
|-------|---------|----------|-----------------|

### Test Strategy
| Story | Test Cases | Type | Notes |
|-------|-----------|------|-------|

### E2E Test Plan
| Story | Scenario | Priority | Notes |
|-------|----------|----------|-------|

### Technical Risk Review
| Story | Risk | Agent | Mitigation |
|-------|------|-------|------------|

### Additions to Acceptance Criteria
[List specific AC items to add to each story]

### Anti-Patterns to Avoid
[List per story]

### Gotchas
[Unexpected issues the specialists flagged]
```

### 5. Present to User and Update Plan

Present the consolidated enrichment to the user. After approval:

1. **Update the plan document** with:
   - Additional acceptance criteria from specialist reviews
   - Anti-patterns added to relevant stories
   - Test cases listed under each story
   - Migration safety notes on DB stories
   - Security requirements on auth/data stories
2. **Mark the plan as enriched** (add a header: `Enriched: [date] by dba-agent, security-agent, test-writer, ...`)

The enriched plan is now ready for `/sprint-start`.
