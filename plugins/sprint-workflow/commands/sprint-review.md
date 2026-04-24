---
description: Review completed work in the current project — runs builds, tests, and code review against discovered skills
allowed-tools: Bash, Glob, Grep, Read, Agent
---

## Context

Current directory: !`pwd`
Project: !`basename $(pwd)`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "not a git repo"`
Unstaged changes: !`git diff --stat 2>/dev/null`
Staged changes: !`git diff --cached --stat 2>/dev/null`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — discover manually by searching for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

Detect tracking backend and delegation tools:

1. **Linear check**: Look for available MCP tools matching `mcp__linear__*` or `mcp__claude_ai_Linear__*`. Try `list_teams`. If it succeeds → Linear mode. Read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.
2. **Codex check**: Check if `/codex:rescue` **and** `/codex:adversarial-review` are both available as skills. If both present → Codex available. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md`.

Set flags: `TRACKING_MODE` ("linear" / "md") and `CODEX_AVAILABLE` (true / false).

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

### 5b. Codex Adversarial Review (if Codex available)

If Codex is available, run a cross-model adversarial review in ADDITION to the Claude code review:

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/codex-delegation/SKILL.md` for focus string mapping
2. Compose focus strings from all skills relevant to the changed files
3. Invoke: `/codex:adversarial-review --base main "focus: correctness; <composed focus strings>"`
4. Include Codex findings in the report under a "### Codex Adversarial Review" section
5. Codex findings follow the same severity classification: CRITICAL → BLOCKING, MAJOR → BLOCKING, MINOR → WARNING

This is ADDITIVE to the pr-review-toolkit code review (Step 6), not a replacement. Sprint-review is a standalone review command, so both Claude and Codex reviews provide independent quality signals.

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

### 8. Update Tracking

**MD mode:** If a sprint plan document exists, update it with review findings.

**Linear mode:** If an active sprint milestone exists:
1. Call `save_comment` on each reviewed Story issue with the review report
2. If BLOCKING issues were found, update relevant task statuses if appropriate
