---
name: dotnet-api
description: ".NET 8 backend development standards — Clean Architecture, EF Core, dependency injection, middleware, serialization, async patterns, and API controller conventions. Use this skill when writing or reviewing any C#/.NET backend code, creating new controllers, services, domain models, or infrastructure. Also use when debugging EF Core issues, DI lifetime bugs, or JSON serialization problems."
---

# .NET 8 Backend Development Standards

This skill defines authoritative patterns for all .NET 8 backend work across projects. Agents MUST follow these standards when writing or modifying C# code.

## Clean Architecture (Mandatory)

All projects follow a 3-layer Clean Architecture:

```
ProjectName.Core/           # Domain models, DTOs, interfaces, enums — ZERO dependencies
ProjectName.Infrastructure/  # EF Core, external services, repositories — depends on Core
ProjectName.Api/            # Controllers, Program.cs, middleware — depends on Core + Infrastructure
```

### Layer Rules
- **Core**: No NuGet packages except MediatR (if using CQRS). No EF Core references. No HTTP references. Pure domain logic.
- **Infrastructure**: Implements interfaces from Core. Contains DbContext, migrations, service implementations, external API clients.
- **Api**: Composition root. Registers DI. Configures middleware pipeline. Controllers only call interfaces from Core.

### Anti-Patterns to Reject
- DbContext in controllers (bypass service layer)
- Domain entities with EF navigation properties exposed through DTOs
- Business logic in controllers
- Infrastructure references from Core

## Dependency Injection

### Lifetime Rules
| Registration | Use When | Example |
|---|---|---|
| `Scoped` | Default for services, DbContext, repositories | `IUserService`, `AppDbContext` |
| `Singleton` | Stateless utilities, configuration objects, `HttpClient` factories | `INodeRegistry` (with static data), `IHttpClientFactory` |
| `Transient` | Lightweight, stateless, no shared state | Validators, mappers |

### Critical DI Patterns
- Register interfaces, not implementations: `services.AddScoped<IUserService, UserService>()`
- Use `IServiceProvider` sparingly — only for runtime resolution of node executors or plugin-style architectures
- Never capture `Scoped` services in `Singleton` — causes captive dependency bugs (silent in dev, crashes in prod under load)
- Use `IOptions<T>` / `IOptionsSnapshot<T>` for configuration, not direct `IConfiguration` injection in services

## EF Core Patterns

### DbContext Configuration
```csharp
// In Infrastructure/Data/AppDbContext.cs
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    // Entity configs in separate IEntityTypeConfiguration<T> files
}
```

### Entity Configuration (Fluent API, not attributes)
```csharp
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.ToTable("users");
        builder.HasKey(u => u.Id);
        builder.Property(u => u.Email).IsRequired().HasMaxLength(255);
        builder.HasIndex(u => u.Auth0Id).IsUnique();
    }
}
```

### Migration Rules
- **Every schema change needs a migration** — never rely on `EnsureCreated()`
- **Generate via CLI**: `dotnet ef migrations add <Name> --project ProjectName.Infrastructure --startup-project ProjectName.Api`
- **Stop running processes** before running `dotnet ef` — file locks block the command
- **Naming**: `Add<WhatChanged>` (e.g., `AddUserManagement`, `AddRetryCountColumn`)
- **One migration per feature** — don't bundle unrelated schema changes
- **Parallel agents**: Each agent creates its own migration; last agent regenerates if snapshot conflicts

### Query Patterns
- Use `AsNoTracking()` for read-only queries
- Avoid `Include()` chains deeper than 2 levels — use projections instead
- Use `Select()` projections to DTOs for list endpoints
- Never call `ToList()` then filter — filter in the query
- Use `AsSplitQuery()` for queries with multiple collection includes

### JSONB Columns (PostgreSQL)
```csharp
builder.Property(e => e.Allocations)
    .HasColumnType("jsonb")
    .HasConversion(
        v => JsonSerializer.Serialize(v, JsonOptions),
        v => JsonSerializer.Deserialize<Dictionary<string, decimal>>(v, JsonOptions)!);
```

## JSON Serialization

### Global Configuration
```csharp
// In Program.cs — applied to ALL controllers
builder.Services.AddControllers()
    .AddJsonOptions(o =>
    {
        o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower));
    });
```

### Critical: JsonElement Round-Trip
After JSON deserialization, `object?` values become `JsonElement`, not CLR primitives. Every `switch` over `object?` must handle `JsonElement`:
```csharp
value switch
{
    string s => s,
    int i => i.ToString(),
    JsonElement je when je.ValueKind == JsonValueKind.String => je.GetString()!,
    JsonElement je when je.ValueKind == JsonValueKind.Number => je.GetDecimal(),
    // ... always include JsonElement arms
};
```

## Async Patterns

- All service methods: `async Task<T>` with `CancellationToken` parameter
- Use `ConfigureAwait(false)` in library code (Infrastructure), not in ASP.NET controllers
- Never use `.Result` or `.Wait()` — causes deadlocks
- Use `Task.WhenAll()` for independent parallel operations
- Use `IAsyncEnumerable<T>` for streaming large result sets

## Controller Patterns

```csharp
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class UsersController : ControllerBase
{
    private readonly IUserService _userService;

    public UsersController(IUserService userService)
        => _userService = userService;

    private string CurrentUserId => User.FindFirst("sub")?.Value ?? "unknown";

    [HttpGet("{id:guid}")]
    [ProducesResponseType<ApiResponse<UserDto>>(200)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var user = await _userService.GetByIdAsync(id, ct);
        if (user is null) return NotFound();
        return Ok(ApiResponse.Ok(user));
    }
}
```

### Response Wrapper
```csharp
public record ApiResponse<T>(T? Data, bool Success, string? Message = null, string[]? Errors = null);
public record PagedResponse<T>(T[] Items, int TotalItems, int PageNumber, int PageSize, bool HasNextPage);
```

## Background Services

Use `BackgroundService` / `IHostedService` for:
- Polling-based schedulers (check every N seconds)
- Event consumers (MQTT, SSE)
- Retry/recovery loops

Always include:
- Try/catch with logging in the main loop
- `CancellationToken` checks
- Exponential backoff for transient failures
- Configurable poll intervals via `IOptions<T>`

## Build Verification

After ANY backend change: `cd api && dotnet build`
After schema changes: Generate and apply migrations
