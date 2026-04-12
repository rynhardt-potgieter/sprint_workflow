---
description: Review completed work in the current project — runs builds, tests, and code review against all 14 discovered skills
allowed-tools: Bash, Glob, Grep, Read, Agent
---

## Context

Current directory: !`pwd`
Project: !`basename $(pwd)`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "not a git repo"`
Unstaged changes: !`git diff --stat 2>/dev/null`
Staged changes: !`git diff --cached --stat 2>/dev/null`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — discover manually by searching for .claude/skills/*/SKILL.md and .claude/plugins/engineering-standards/skills/*/SKILL.md"`

## Your Task

Review all recent work in the current project.

### 1. Read Relevant Skills

From the **Available Skills** section above, read the skill files relevant to the changed files:
- Backend changes (.cs, .rs, .py, .go) → read backend/language skills + `code-standards`
- Frontend changes (.tsx, .ts, .vue) → read frontend skills + `code-standards`
- Schema/migration changes → read data/database skills (e.g., `postgresql-data`)
- Auth/security changes → read `security-compliance`
- API endpoint changes → read `api-design`
- MQTT/event changes → read `event-mqtt`
- Workflow/BPMN changes → read `bpmn-workflow`
- CQRS/MediatR changes → read `cqrs-patterns`
- Geometry/spatial changes → read `geometry`
- Rust CLI changes → read `rust-cli`
- Git commit quality → read `code-standards` (git conventions section)

### 2. Identify Changes

- Review recent git commits and diffs
- Check for unstaged/staged changes
- Identify which files and areas were modified

### 3. Run Quality Gates

Detect the stack and run appropriate checks:
- **Build**: Run the project's build command (from CLAUDE.md or detected)
- **Type-check**: `npx tsc --noEmit`, `mypy`, `dotnet build`, `cargo check`, etc.
- **Lint**: `npx eslint .`, `ruff check .`, `cargo clippy -- -D warnings`, `cargo fmt --check`, etc.
- **Tests**: Run the project's test suite
- **Consumer breakage**: Grep for any renamed/removed exports

### 4. Standards Compliance Check

Using the skill files read in Step 1, verify the changes follow them:
- Naming conventions match the skill definitions
- Security patterns followed (auth, PII handling, secrets management)
- Git commit messages follow the format in skills
- API design / output format patterns match
- Language-specific patterns followed
- Database schema conventions followed (if applicable)
- DBA review: query performance, index usage, migration safety (if schema changes)

### 5. Security Review

If any changes touch auth, user data, API endpoints, or configuration:
- Verify no secrets or PII in source code or logs
- Check auth/authorization on all endpoints
- Verify parameterized queries (no SQL string concatenation)
- Check CancellationToken propagation on async calls
- Review CORS, CSP, and header configurations if applicable

### 6. Code Review

Launch `pr-review-toolkit:code-reviewer` to review recent changes. Include in its prompt:
- The list of skill file paths (so it can read and validate against them)
- The acceptance criteria from the sprint plan (if known)

### 7. Report

```
## Sprint Review — [project name]

### Skills Reviewed Against
[list skill files read with their source (local/global)]

### Quality Gate Results
| Check | Result | Details |
|-------|--------|---------|

### Standards Compliance
| Standard (from skill) | Status | Issues |
|----------------------|--------|--------|

### Security Review
| Check | Status | Details |
|-------|--------|---------|

### DBA Review (if applicable)
| Check | Status | Details |
|-------|--------|---------|

### Code Review Summary
- Critical issues: N
- Suggestions: N

### New Patterns to Document
- Any CLAUDE.md or skill updates recommended

### Follow-up Items
- Issues or tech debt to address
```
