---
name: tfs-flow
description: Use this skill before any version control operation in a TFVC (Team Foundation Version Control) project — checking in, shelving, branching, merging, or associating work items. Defines the workspace workflow, checkin conventions, branching strategy, and work item association. Always invoke this instead of git-flow when the project uses TFVC.
---

# TFS / TFVC Workflow

This skill applies when the project uses **Team Foundation Version Control (TFVC)** instead of Git. If you see a `.git` directory, use the `git-flow` skill instead. If you see a `$tf/` workspace mapping or `*.vssscc` files, use this skill.

## Detecting TFVC vs Git

Before any version control operation, check which system the project uses:

```bash
# If this succeeds, it's a git repo — use git-flow
git rev-parse --is-inside-work-tree 2>/dev/null && echo "GIT"

# If no .git, check for TFVC workspace
tf vc workspaces 2>/dev/null && echo "TFVC"
```

## Workspace Setup

TFVC uses server workspaces (or local workspaces) mapped to local folders.

```bash
# List current workspace mappings
tf vc workspaces

# Show workspace details
tf vc workfold

# Get latest from server
tf vc get /recursive
```

### Workspace Types

| Type | When to Use | Behavior |
|------|------------|----------|
| **Local** | Default, most development | Files are read/write, changes tracked locally |
| **Server** | Large repos, many files | Files are read-only until checked out, changes tracked on server |

## Branching Strategy

TFVC branches are server-side copies, not lightweight like Git branches.

```
$/Project
 ├── Main                              # Always deployable
 ├── Dev                                # Integration branch
 │    ├── Features/user-authentication  # Feature work
 │    ├── Features/payment-processing   # Feature work
 │    └── Bugfix/fix-rounding-error     # Bug fixes
 └── Releases/v1.2                      # Release stabilization
```

### Branch Naming

| Pattern | When to Use |
|---------|------------|
| `$/Project/Main` | Production-ready code. Always stable. |
| `$/Project/Dev` | Integration branch. Features merge here first. |
| `$/Project/Features/<name>` | New feature work. Short-lived. |
| `$/Project/Bugfix/<name>` | Bug fix branches. |
| `$/Project/Releases/<version>` | Release stabilization. Only bug fixes allowed. |

### Branch Commands

```bash
# Create a feature branch from Main
tf vc branch "$/Project/Main" "$/Project/Features/user-authentication"

# Merge feature into Dev (forward integration)
tf vc merge "$/Project/Features/user-authentication" "$/Project/Dev" /recursive

# Merge Dev into Main (reverse integration — after testing)
tf vc merge "$/Project/Dev" "$/Project/Main" /recursive

# Delete a completed feature branch
tf vc destroy "$/Project/Features/user-authentication"
```

### Integration Rules

1. **Forward integrate (FI)**: Feature → Dev. Developer merges their feature into Dev for integration testing.
2. **Reverse integrate (RI)**: Dev → Main. After integration tests pass, merge Dev into Main.
3. **Never merge directly** from Feature → Main. Always go through Dev.
4. **Keep branches short-lived**. Merge frequently to minimize conflicts.

## Checkin Workflow

### Getting Latest

```bash
# Always get latest before starting work
tf vc get /recursive

# Get latest for a specific path
tf vc get "$/Project/Main/src" /recursive
```

### Checking Out (Edit)

```bash
# Check out a file for editing (server workspace only — local workspaces auto-detect)
tf vc checkout "src/Services/PaymentService.cs"

# Check out multiple files
tf vc checkout "src/Services/*.cs"
```

### Viewing Pending Changes

```bash
# Show all pending changes in your workspace
tf vc status

# Show pending changes for a specific path
tf vc status "src/" /recursive
```

### Shelving (TFVC's equivalent of stashing/draft PRs)

Shelvesets store pending changes on the server without committing them. Use shelvesets for:
- Code review before checkin
- Saving work-in-progress
- Sharing changes with another developer
- Backing up local work

```bash
# Create a shelveset
tf vc shelve "my-feature-wip" /comment:"Work in progress on user auth"

# Create and preserve local changes (don't undo local edits)
tf vc shelve "my-feature-wip" /noprompt /move:false

# List shelvesets
tf vc shelvesets

# Unshelve (restore to workspace)
tf vc unshelve "my-feature-wip"

# Delete a shelveset
tf vc shelve /delete "my-feature-wip"
```

### Checking In

```bash
# Check in all pending changes
tf vc checkin /comment:"feat(auth): add JWT token validation"

# Check in specific files
tf vc checkin "src/Services/AuthService.cs" "src/Models/Token.cs" /comment:"feat(auth): add JWT token validation"

# Check in and associate a work item
tf vc checkin /comment:"feat(auth): add JWT token validation" /associate:12345

# Check in and resolve a work item
tf vc checkin /comment:"fix(payment): correct rounding error" /resolve:12340

# Check in with checkin notes
tf vc checkin /comment:"feat(auth): add JWT token validation" /notes:"Code Reviewer=John Smith"
```

## Checkin Message Format

Use the **same conventional commit format** as git-flow — consistency across projects matters more than tool differences:

```
<type>(<scope>): <summary>

<body -- optional>

<footer -- optional>
```

### Types

| Type | When to Use |
|------|------------|
| `feat` | New user-facing functionality |
| `fix` | Bug fix |
| `refactor` | Code change with no behavior change |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `docs` | Documentation only |
| `chore` | Tooling, deps, CI, build changes |

### Summary Rules

- Imperative mood: "add" not "added" or "adds"
- Lowercase first letter
- No period at end
- Max 72 chars
- Specific: "add pagination to user list endpoint" not "improve users"

### Examples — Good Checkin Messages

```
feat(auth): add JWT refresh token rotation

Implements automatic token rotation on refresh. Old refresh tokens
are invalidated immediately after use to prevent replay attacks.

Work Item: #12345
```

```
fix(db): prevent stale references after record deletion

Cascade cleanup now runs before confirming deletion.

Resolves: #12340
```

### Examples — Bad Checkin Messages

```
# Too vague
Updated files

# No type or scope
fixed the bug

# Past tense
feat(auth): added token rotation
```

## Work Item Association

Every checkin should associate or resolve a work item. This is how TFVC tracks what changed and why.

```bash
# Associate (link without closing)
tf vc checkin /associate:12345

# Resolve (link and set to resolved)
tf vc checkin /resolve:12340

# Multiple work items
tf vc checkin /associate:12345 /resolve:12340
```

### Work Item Types

| Type | TFVC Action | When |
|------|------------|------|
| **User Story** | `/associate` | Feature work linked to the story |
| **Bug** | `/resolve` | Bug fix — closes the bug |
| **Task** | `/resolve` | Completing a task |
| **Product Backlog Item** | `/associate` | Linking work to a PBI |

## Before Every Checkin

```bash
# 1. Get latest and resolve conflicts
tf vc get /recursive

# 2. Build — must pass
<project-specific build command>

# 3. Run tests — must all pass
<project-specific test runner>

# 4. Review pending changes
tf vc status

# 5. Check in
tf vc checkin /comment:"<message>" /associate:<work-item-id>
```

All checks must pass. No exceptions.

## Handling Merge Conflicts

```bash
# Merge and resolve conflicts
tf vc merge "$/Project/Features/my-feature" "$/Project/Dev" /recursive

# If conflicts arise:
# 1. tf vc resolve to launch the merge tool
tf vc resolve /auto:acceptmerge   # Auto-resolve non-conflicting
tf vc resolve "src/file.cs"       # Manual resolve for conflicting files

# 2. After resolving, verify the build
<project-specific build command>

# 3. Check in the merge result
tf vc checkin /comment:"merge(dev): integrate feature/my-feature"
```

## Code Review via Shelvesets

TFVC doesn't have pull requests natively. Use shelvesets for code review:

1. **Developer** creates a shelveset: `tf vc shelve "review/auth-feature"`
2. **Reviewer** unshelves into their workspace: `tf vc unshelve "review/auth-feature"`
3. **Reviewer** reviews the code, provides feedback
4. **Developer** makes changes, creates a new shelveset
5. Once approved, **developer** checks in from their workspace

If Azure DevOps is configured, you can also use the web-based code review workflow with shelvesets.

## History and Comparison

```bash
# View changeset history
tf vc history "$/Project/Main" /recursive /format:detailed

# View history for a specific file
tf vc history "src/Services/AuthService.cs"

# Compare a file with a specific changeset
tf vc diff "src/Services/AuthService.cs" /version:C12345

# View changeset details
tf vc changeset 12345
```

## Key Differences from Git

| Concept | Git | TFVC |
|---------|-----|------|
| Branch | Lightweight pointer | Server-side copy of files |
| Stash | `git stash` | `tf vc shelve` (persisted on server) |
| Commit | Local then push | Direct checkin to server |
| Pull Request | GitHub/GitLab PR | Shelveset code review (or Azure DevOps PR) |
| History | Distributed, full clone | Centralized, query server |
| Staging area | `git add` (index) | Pending changes (auto-tracked in local workspace) |
| Revert | `git revert` / `git reset` | `tf vc undo` (pending) / `tf vc rollback` (committed) |
| Ignore | `.gitignore` | `.tfignore` |

## .tfignore

Create a `.tfignore` file in the workspace root to exclude files from version control:

```
# Build outputs
bin
obj
*.dll
*.exe
*.pdb

# IDE
.vs
*.suo
*.user

# OS
Thumbs.db
.DS_Store

# Dependencies
node_modules
packages

# Environment
.env
*.local
```
