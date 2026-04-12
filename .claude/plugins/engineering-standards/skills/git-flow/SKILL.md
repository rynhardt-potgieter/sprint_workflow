---
name: git-flow
description: Use this skill before any git operation — committing, branching, opening PRs, tagging releases, or resolving conflicts. This skill defines the exact workflow, branch naming, commit message format, and PR requirements. Always invoke it before touching git.
---

# Git Workflow

## Branch Strategy

```
main
 |-- feat/user-authentication
 |-- fix/payment-rounding-error
 |-- refactor/database-layer
 |-- bench/api-load-tests
 |-- docs/api-documentation
 |-- chore/update-dependencies
```

- `main` is always deployable. Never commit broken code to main.
- All work happens on feature branches. No direct commits to main except version bumps from releases.
- Branch lifetime: as short as possible. Branches older than 2 weeks without activity should be deleted or finished.

## Starting New Work

```bash
# Always start from a fresh main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feat/your-feature-name

# Do your work, then...
```

## Commit Message Format

```
<type>(<scope>): <summary>

<body -- optional but encouraged for non-trivial changes>

<footer -- optional>
```

### Types

| Type | When to use |
|---|---|
| `feat` | New user-facing functionality |
| `fix` | Bug fix |
| `refactor` | Code change with no behaviour change |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `bench` | Benchmark task or harness work |
| `docs` | Documentation only |
| `chore` | Tooling, deps, CI, build changes |

### Scopes

Use the module or domain area affected by the change. Examples:

`auth`, `api`, `db`, `ui`, `config`, `ci`, `deps`, `parser`, `output`, `store`, `renderer`, `export`

Choose scopes that are meaningful in your project. Keep them short and consistent.

### Summary rules

- Imperative mood: "add" not "added" or "adds"
- Lowercase first letter
- No period at end
- Max 72 chars for the entire first line (type + scope + summary)
- Specific: "add pagination to user list endpoint" not "improve users"

### Body rules

- Blank line between summary and body
- Explain WHY not WHAT (the diff shows what)
- Wrap at 80 characters
- Use bullet points for multiple points

### Footer

- `Closes #N` for issues
- `BREAKING CHANGE: <description>` for breaking changes
- `Co-authored-by: Name <email>` for pair work

### Examples -- Good commits

```
feat(auth): add JWT refresh token rotation

Implements automatic token rotation on refresh. Old refresh tokens
are invalidated immediately after use to prevent replay attacks.

Addresses security audit finding SA-2024-003.
```

```
fix(db): prevent stale references after record deletion

When a record was deleted, foreign key references were not cleaned
up, causing ghost entries in query results.

Now performs a cascade cleanup before confirming deletion.

Closes #14
```

```
perf(api): add covering index on orders(user_id, status)

List-orders queries on large datasets were doing full table scans.
This index reduces query time from ~800ms to <50ms on the benchmark
dataset.
```

### Examples -- Bad commits (don't do these)

```
# Too vague
fix: bug fix

# Past tense
feat(auth): added token rotation

# Trailing period
feat(auth): add token rotation.

# No scope when scope is obvious
feat: add token rotation to auth flow

# Describes what not why
refactor(db): changed SQL query structure
```

## Before Every Commit

```bash
# 1. Format
<project-specific formatter>

# 2. Lint — must be zero warnings
<project-specific linter>

# 3. Tests — must all pass
<project-specific test runner>

# 4. If output format changed — review snapshots (if applicable)
<project-specific snapshot review>
```

All checks must pass. No exceptions.

## Staging and Committing

```bash
# Review what changed
git diff

# Stage specific files (prefer this over git add .)
git add src/auth/token.rs
git add src/auth/middleware.rs

# Commit
git commit
```

## Pushing and PRs

```bash
# Push your branch
git push -u origin feat/your-feature-name
```

### PR Description Template

```markdown
## What

Brief description of what this PR does.

## Why

Why is this change needed? What problem does it solve?

## How

Any non-obvious implementation decisions worth explaining.

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Snapshot tests reviewed (if applicable)
- [ ] Tested against representative data/fixtures
- [ ] Performance targets still met

## Breaking Changes

None / [describe any breaking changes]
```

## After PR is Merged

```bash
# Delete local branch
git checkout main
git pull origin main
git branch -d feat/your-feature-name
```

## Release Process

```bash
# Bump version in project config (Cargo.toml, package.json, .csproj, etc.)
# Update CHANGELOG.md

# Commit the version bump
git add <version-files> CHANGELOG.md
git commit -m "chore: release v1.2.0"

# Tag the release
git tag -a v1.2.0 -m "Release v1.2.0"

# Push with tags
git push origin main --tags
```

## Handling Merge Conflicts

```bash
# Get latest main
git fetch origin main

# Rebase onto main (preferred over merge for feature branches)
git rebase origin/main

# If conflicts:
# 1. Fix the conflicted files
# 2. Run tests to verify nothing broke
# 3. git add <fixed files>
# 4. git rebase --continue
```

Never use `git merge main` into a feature branch — always rebase. Keeps history linear and easier to read.

## GitHub Issue Workflow

Every piece of work that addresses a GitHub issue MUST follow this flow:

### 1. Before starting work

```bash
# Assign the issue
gh issue edit <N> --add-assignee <your-username>

# Add appropriate label
gh issue edit <N> --add-label "enhancement"   # or "bug", "documentation", "chore"
```

**Labels:**
| Label | When |
|-------|------|
| `bug` | Something is broken |
| `enhancement` | New feature or improvement |
| `documentation` | Docs only |
| `chore` | Tooling, deps, CI |
| `performance` | Speed/memory issues |

### 2. Reference the issue in commits

Use closing keywords in the **commit message footer** (not the subject line):

```
feat(auth): add OAuth2 provider support

Implement OAuth2 authorization code flow with PKCE for
third-party identity providers.

Closes #42
```

**Keywords (case-insensitive, auto-close when commit hits main):**
- `Fixes #N` -- for bug fixes
- `Closes #N` -- for features/enhancements
- `Resolves #N` -- for discussion-type issues

Multiple issues: `Closes #2, closes #5`

### 3. After pushing to main

Add a detailed closing comment on the issue:

```bash
gh issue comment <N> --body "Fixed in v1.2.0 (commit abc1234).

**What changed:**
- [bullet summary of changes]

**How to verify:**
- [steps to test the fix]"
```

### 4. Close the issue

If the commit has `Closes #N` / `Fixes #N`, GitHub auto-closes when pushed to main. If not:

```bash
gh issue close <N>
```

### Key Rules

- **Every commit that completes work references the issue number** with a closing keyword
- Auto-close only triggers on the **default branch** (main) -- feature branch commits don't close issues
- If a fix is incomplete after merging, **open a new issue** referencing the original -- don't reopen
- Don't comment if the commit message already explains everything and the auto-close link is sufficient
- For external contributor issues, ALWAYS add a closing comment thanking them and explaining what shipped
