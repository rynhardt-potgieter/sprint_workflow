---
name: code-standards
description: "Code quality and formatting standards — C# naming conventions, TypeScript strict mode, SQL formatting, git commit style, code review checklist, error handling patterns, and logging conventions. Use this skill when writing new code, reviewing code quality, establishing naming conventions, setting up linting, or ensuring consistency across the codebase. Also use when subagents need a reference for coding style."
---

# Code Quality & Formatting Standards

This skill defines mandatory code quality conventions across all projects.

## C# Conventions

### Naming
| Element | Convention | Example |
|---------|-----------|---------|
| Classes / Records | PascalCase | `WorkflowEngine`, `GoalDto` |
| Interfaces | IPascalCase | `IUserService`, `INodeExecutor` |
| Methods | PascalCase | `ExecuteAsync`, `GetByIdAsync` |
| Properties | PascalCase | `CurrentUserId`, `IsTest` |
| Private fields | _camelCase | `_userService`, `_db` |
| Parameters | camelCase | `userId`, `cancellationToken` |
| Constants | PascalCase | `MaxRetries`, `DefaultPageSize` |
| Enums | PascalCase | `WorkflowStatus.Running` |
| Local variables | camelCase | `totalAmount`, `isValid` |

### Async Conventions
- All async methods end with `Async` suffix
- Always accept `CancellationToken ct` as last parameter
- Propagate `ct` to all async calls
- Use `Task` not `void` for async returns (except event handlers)

### Record Types
Prefer records for:
- DTOs: `public record GoalDto(Guid Id, string Name, decimal TargetAmount);`
- Commands: `public record CreateGoalCommand(string Name) : IRequest<GoalDto>;`
- Events: `public record GoalCreatedEvent(Guid GoalId) : INotification;`
- Value objects: `public record Money(decimal Amount, string Currency);`

### Null Handling
- `Nullable` enabled in all projects
- Use `?` for nullable types, never return null for collections (return empty)
- Use null-conditional: `user?.Email`
- Use null-coalescing: `name ?? "Unknown"`
- Pattern matching: `if (result is not null)` over `if (result != null)`

### File Organization
```csharp
// 1. Usings (IDE-managed)
using Microsoft.AspNetCore.Mvc;

// 2. Namespace (file-scoped)
namespace ProjectName.Api.Controllers;

// 3. Type declaration
[ApiController]
public class GoalsController : ControllerBase
{
    // 4. Fields (private, readonly)
    private readonly IGoalService _goalService;

    // 5. Constructor
    public GoalsController(IGoalService goalService) => _goalService = goalService;

    // 6. Properties
    private string CurrentUserId => User.FindFirst("sub")?.Value ?? "unknown";

    // 7. Public methods
    // 8. Private methods
}
```

### Error Handling
```csharp
// Service layer — throw specific exceptions
public async Task<GoalDto> GetByIdAsync(Guid id, CancellationToken ct)
{
    var goal = await _db.Goals.FindAsync(new object[] { id }, ct)
        ?? throw new NotFoundException($"Goal {id} not found");
    return GoalDto.From(goal);
}

// Controller layer — catch and map to HTTP
try { ... }
catch (NotFoundException) { return NotFound(); }
catch (BusinessRuleException ex) { return UnprocessableEntity(ApiResponse.Fail<T>(ex.Message)); }
```

## TypeScript Conventions

### Naming
| Element | Convention | Example |
|---------|-----------|---------|
| Components | PascalCase file + export | `GoalCard.tsx`, `export function GoalCard` |
| Hooks | camelCase with `use` | `useGoals.ts`, `export function useGoals` |
| Stores | camelCase + Store | `uiStore.ts`, `useUiStore` |
| Types / Interfaces | PascalCase | `GoalDto`, `CreateGoalRequest` |
| Constants | UPPER_SNAKE | `USE_MOCKS`, `MAX_RETRIES` |
| Utilities | camelCase | `formatCurrency.ts` |
| Event handlers | `handle` + noun + verb | `handleGoalClick`, `handleFormSubmit` |

### Strict Mode Checklist
- No `any` — use `unknown` and type-narrow
- Explicit return types on exported functions
- `satisfies` over `as` for type assertions
- Discriminated unions for state machines
- Zod schemas for runtime validation at boundaries

### Import Order
```typescript
// 1. React / framework
import { useState, useEffect } from 'react'
// 2. Third-party libraries
import { useQuery } from '@tanstack/react-query'
// 3. Project imports (absolute paths)
import { apiFetch } from '@/api/client'
import { useUiStore } from '@/stores/uiStore'
// 4. Relative imports (same feature)
import { GoalCard } from './GoalCard'
// 5. Types
import type { GoalDto } from '@/types/goal'
```

### Error Boundaries
- Wrap route-level components in error boundaries
- Display user-friendly error messages, not stack traces
- Log errors to console in development, to telemetry in production

## SQL Conventions

### Formatting
```sql
SELECT
    u.id,
    u.email,
    p.first_name,
    p.last_name
FROM users u
    INNER JOIN user_profiles p ON p.user_id = u.id
WHERE u.tenant_id = @TenantId
    AND u.deleted_at IS NULL
ORDER BY u.created_at DESC
LIMIT @PageSize OFFSET @Offset;
```

- Keywords in UPPERCASE: `SELECT`, `FROM`, `WHERE`, `ORDER BY`
- Table aliases: short, meaningful (`u` for users, `p` for profiles)
- One column per line in SELECT
- Each JOIN/WHERE condition on its own line
- Always use parameterized queries (`@Param`)

## Logging Conventions

### What to Log
| Level | When | Example |
|-------|------|---------|
| Information | Key business events | `"User {UserId} created goal {GoalId}"` |
| Warning | Recoverable issues | `"Retry {Count} for workflow {InstanceId}"` |
| Error | Failures requiring attention | `"Failed to process event: {Error}"` |
| Debug | Detailed diagnostic info | `"Evaluating expression: {Expr}"` |

### What NOT to Log
- Passwords, tokens, API keys
- PII (email, phone, names, ID numbers)
- Full request/response bodies (log summaries instead)
- High-frequency telemetry at Info level (use Debug)

### Structured Logging
```csharp
// Good — structured, no PII
_logger.LogInformation("Goal {GoalId} created by user {UserId}", goalId, userId);

// Bad — string interpolation, PII
_logger.LogInformation($"Goal created for {userEmail}");  // NEVER
```

## Git Conventions

### Branch Strategy

```
main                          — always deployable, never commit broken code
feat/<short-description>      — new features
fix/<short-description>       — bug fixes
refactor/<short-description>  — code changes with no behaviour change
perf/<short-description>      — performance improvements
test/<short-description>      — test additions/fixes
docs/<short-description>      — documentation only
chore/<short-description>     — tooling, deps, CI, build changes
sprint/<n>                    — sprint work
```

- All work happens on feature branches. No direct commits to main except version bumps.
- Branch lifetime: as short as possible. Branches older than 2 weeks without activity should be deleted or finished.
- Always start from a fresh main: `git checkout main && git pull origin main && git checkout -b feat/your-feature`

### Commit Message Format

```
<type>(<scope>): <summary>

<body — optional but encouraged for non-trivial changes>

<footer — optional>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

### Types

| Type | When to use |
|---|---|
| `feat` | New user-facing functionality |
| `fix` | Bug fix |
| `refactor` | Code change with no behaviour change |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `docs` | Documentation only |
| `chore` | Tooling, deps, CI, build changes |
| `style` | Formatting, whitespace (no logic change) |

### Scopes (use the module/area affected)

Use the logical area: `api`, `web`, `auth`, `goals`, `workflow`, `db`, `config`, `ci`, `deps`, `onboarding`, `gamification`, etc. Omit scope only if the change truly spans the entire project.

### Summary Rules

- **Imperative mood**: "add" not "added" or "adds"
- **Lowercase** first letter
- **No period** at end
- **Max 72 chars** for the entire first line (type + scope + summary)
- **Specific**: "add caller count to sketch method output" not "improve sketch"

### Body Rules

- Blank line between summary and body
- **Explain WHY not WHAT** (the diff shows what)
- Wrap at 80 characters
- Use bullet points for multiple points

### Footer

- `Closes #N` for issues
- `BREAKING CHANGE: <description>` for breaking changes

### Examples — Good Commits

```
feat(goals): add fund bundle suitability matching

Selects the optimal fund bundle based on goal type, time horizon,
and risk ceiling. Previously users had to manually pick bundles.

This enables the "auto-assign" flow in the goal creation wizard
so the user test scenario completes without help.
```

```
fix(workflow): prevent stale edges after node rename

When a node was renamed, edges referencing the old config keys were
not cleaned up, causing ghost references in downstream expressions.

Now performs a key-based edge cleanup before inserting new edges
on every graph save.

Closes #14
```

```
perf(db): add covering index on workflow_instances(tenant_id, status)

List queries on large tenants (10k+ instances) were doing full table
scans. This index reduces query time from ~800ms to <50ms.
```

### Examples — Bad Commits (Don't Do These)

```
# Too vague
fix: bug fix

# Past tense
feat(goals): added fund bundle matching

# Trailing period
feat(goals): add fund bundle matching.

# No scope when scope is obvious
feat: add fund bundle matching to goals

# Describes WHAT not WHY
refactor(db): changed SQL query structure
```

### Pre-Commit Checklist

Before every commit, verify:

**Backend (.NET):**
```bash
cd api && dotnet build              # Must compile
cd api && dotnet test               # Must pass (if tests exist)
```

**Frontend (React/TS):**
```bash
cd web && npx tsc --noEmit          # Must type-check
cd web && pnpm lint                 # Must pass (zero errors)
```

All checks must pass. No exceptions. No `--no-verify`.

### Staging

```bash
# Review what changed
git diff

# Stage specific files (prefer this over git add .)
git add api/ProjectName.Core/Models/Goal.cs
git add web/src/components/GoalCard.tsx

# Never stage .env, credentials, or secrets
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
- [ ] Backend builds (`dotnet build`)
- [ ] Frontend type-checks (`npx tsc --noEmit`)
- [ ] Frontend lints (`pnpm lint`)
- [ ] Tests pass
- [ ] Mock data updated if API shape changed
- [ ] Manually tested the user flow

## Breaking Changes
None / [describe any breaking changes]
```

### Handling Merge Conflicts

```bash
# Get latest main
git fetch origin main

# Rebase onto main (preferred over merge for feature branches)
git rebase origin/main

# If conflicts:
# 1. Fix the conflicted files
# 2. Run build/type-check to verify nothing broke
# 3. git add <fixed files>
# 4. git rebase --continue
```

**Never** use `git merge main` into a feature branch — always rebase. Keeps history linear and easier to review.

### After PR is Merged

```bash
git checkout main
git pull origin main
git branch -d feat/your-feature-name
```

## Code Review Checklist

Before marking any task complete:
- [ ] `dotnet build` passes (backend)
- [ ] `npx tsc --noEmit` passes (frontend)
- [ ] `pnpm lint` passes (frontend)
- [ ] No `any` types introduced
- [ ] No PII in logs
- [ ] No secrets in code
- [ ] CancellationToken propagated
- [ ] New endpoints have `[Authorize]`
- [ ] Mock data updated if API shape changed
- [ ] CLAUDE.md updated if new patterns established
