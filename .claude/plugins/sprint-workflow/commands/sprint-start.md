---
description: Start a sprint cycle — discovers tasks, creates a plan, and delegates work to specialist agents
argument-hint: "[sprint/task refs] from [plan-file-path]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — agents must discover skills manually by searching for .claude/skills/*/SKILL.md (project-local) and .claude/plugins/engineering-standards/skills/*/SKILL.md (global)."`

## Your Task

Plan and initiate a sprint cycle for the current project.

### 1. Locate the Project Plan

If the arguments reference a file path (e.g., "from docs/PROJECT_PLAN.md"), use that as the **source plan document**. Otherwise search for it:
- `docs/PROJECT_PLAN*.md`, `docs/SPRINT*.md`
- `PROJECT_PLAN*.md`, `SPRINT*.md`, `TASKS.md`, `TODO.md`
- `project_management/TASKS/`

**Remember this file path — you will update it as tasks complete.**

### 2. Understand the Project

- Read `CLAUDE.md` if present
- Read the project plan document fully
- Identify the tech stack from config files
- Find build/test/lint commands

### 3. Build Skill Assignments for Agents

Using the **Available Skills** section above (already resolved), assign skills to each agent:

**Rules:**
1. **If project-local skills exist (priority = LOCAL or MIXED)**: Assign local skills that match the agent's domain. For a Rust project, `rust-cli` goes to backend-dev, `rust-testing` goes to test-writer, etc.
2. **Global engineering-standards fill gaps**: If no local skill covers a domain needed for the task (e.g., security, API design), assign the relevant global skill.
3. **`code-standards` is always additive**: Include the global `code-standards` skill for all agents even when local skills exist — it provides universal conventions (git, logging, naming).
4. **Only assign relevant skills**: Don't give `react-typescript` to an agent working on a Rust CLI. Match skills to the actual work.

Build a concrete mapping:
```
| Agent | Skill Files to Read (full paths) |
|-------|----------------------------------|
```

### 4. Select Tasks

If arguments specify a sprint number, task IDs, or descriptions, scope to those. Otherwise pick the next incomplete sprint/phase from the plan.

### 5. Present Sprint Plan

Show the user a plan before executing:

```
## Sprint Plan — [project name]

### Source Plan: [file path]

### Skills (auto-discovered)
[paste the skill priority summary from above]

### Selected Tasks (N items)
| Task | Agent | Priority | Skills to Read |
|------|-------|----------|----------------|

### Execution Order
1. [Independent tasks — run in parallel]
2. [Dependent tasks — sequential]
3. [Final validation with qa-agent]

### Dependencies
- Any cross-task dependencies noted
```

### 6. Execute (after user approval)

Once approved, YOU orchestrate directly — do NOT use a sprint-lead agent. You are the orchestrator.

1. **Dispatch specialist agents directly** using the Agent tool:
   - `frontend-dev` for UI / client work
   - `backend-dev` for server-side / API work
   - `test-writer` for writing tests
   - `qa-agent` for validation and quality checks
   - `docs-agent` for documentation, READMEs, and guides
   - `product-manager` for requirements analysis, user stories, and acceptance criteria
   - `dba-agent` for database schema design, migrations, and query optimization
   - `security-agent` for security audits, auth flows, and vulnerability checks
2. Launch independent tasks **in parallel** (multiple Agent calls in a single message)
3. Each agent prompt MUST include:
   - **Skill file paths to read**: Include the FULL PATHS from the skill assignment table. Example: "Before starting, read these skill files:\n- `/d/Users/rynha/repos/scope/.claude/skills/rust-cli/SKILL.md`\n- `/d/Users/rynha/repos/.claude/plugins/engineering-standards/skills/code-standards/SKILL.md`"
   - **Verbatim acceptance criteria** from the plan document
   - Relevant spec sections (design system, architecture docs) — quote them or tell the agent which files to read
   - Anti-patterns and constraints
   - File paths for where to create/modify things
   - Build/lint/test commands to verify their work
4. After each task completes, **update the plan file** (`- [ ]` → `- [x]`, status fields)
5. After implementation tasks, dispatch `qa-agent` to validate — include the acceptance criteria AND the skill file paths it should check against
6. Update the plan document after each completed task

### 7. Sprint Summary

After all tasks complete:
1. Verify the plan document is fully updated
2. Summarize results and note follow-up items
3. Show the updated verification checklist from the plan
4. List which skills (local and global) were applied and any violations found
