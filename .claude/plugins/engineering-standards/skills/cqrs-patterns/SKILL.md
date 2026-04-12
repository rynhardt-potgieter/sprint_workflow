---
name: cqrs-patterns
description: "CQRS and MediatR patterns — command/query separation, handler design, pipeline behaviors, read/write model separation, domain events, and notification handlers. Use this skill when implementing MediatR commands or queries, designing CQRS pipelines, adding validation behaviors, or separating read and write concerns."
---

# CQRS & MediatR Standards

This skill defines patterns for CQRS (Command Query Responsibility Segregation) using MediatR in .NET projects.

## When to Use CQRS

### Use CQRS When
- Read and write models have different shapes (list views vs edit forms)
- Write operations have complex validation or side effects
- You need audit trails on state changes
- Domain events should trigger downstream actions
- Multiple teams work on the same domain

### Don't Use CQRS When
- Simple CRUD with identical read/write shapes
- No complex business rules
- Small domain with few entities
- Adding complexity outweighs the benefit

## MediatR Setup

### Registration
```csharp
// Program.cs
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(AppDbContext).Assembly));
```

### Project Structure
```
Core/
  Commands/          # IRequest<TResult> command types
    CreateGoal.cs    # Contains Command record + Handler class
  Queries/           # IRequest<TResult> query types
    GetGoalById.cs   # Contains Query record + Handler class
  Events/            # INotification types for domain events
    GoalCreated.cs
```

## Command Pattern

### Command + Handler (Same File)
```csharp
// Commands/CreateGoal.cs
public record CreateGoalCommand(
    string Name,
    GoalType Type,
    decimal TargetAmount,
    DateOnly? Deadline,
    string UserId
) : IRequest<ApiResponse<GoalDto>>;

public class CreateGoalHandler : IRequestHandler<CreateGoalCommand, ApiResponse<GoalDto>>
{
    private readonly AppDbContext _db;
    private readonly IPublisher _publisher;

    public CreateGoalHandler(AppDbContext db, IPublisher publisher)
    {
        _db = db;
        _publisher = publisher;
    }

    public async Task<ApiResponse<GoalDto>> Handle(
        CreateGoalCommand request, CancellationToken ct)
    {
        var goal = new Goal
        {
            Name = request.Name,
            Type = request.Type,
            TargetAmount = request.TargetAmount,
            Deadline = request.Deadline,
            UserId = request.UserId,
        };

        _db.Goals.Add(goal);
        await _db.SaveChangesAsync(ct);

        await _publisher.Publish(new GoalCreatedEvent(goal.Id, goal.UserId), ct);

        return ApiResponse.Ok(GoalDto.From(goal));
    }
}
```

### Command Rules
- Commands represent intent: `CreateGoal`, `ArchiveWorkflow`, `ApproveHumanTask`
- Commands are records (immutable)
- One handler per command
- Commands return results (not void) — caller needs to know success/failure
- Commands can publish domain events via `IPublisher`

## Query Pattern

```csharp
// Queries/GetGoalById.cs
public record GetGoalByIdQuery(Guid GoalId, string UserId) : IRequest<GoalDto?>;

public class GetGoalByIdHandler : IRequestHandler<GetGoalByIdQuery, GoalDto?>
{
    private readonly AppDbContext _db;

    public GetGoalByIdHandler(AppDbContext db) => _db = db;

    public async Task<GoalDto?> Handle(GetGoalByIdQuery request, CancellationToken ct)
    {
        return await _db.Goals
            .AsNoTracking()
            .Where(g => g.Id == request.GoalId && g.UserId == request.UserId)
            .Select(g => new GoalDto(g.Id, g.Name, g.TargetAmount, g.CurrentAmount))
            .FirstOrDefaultAsync(ct);
    }
}
```

### Query Rules
- Queries are read-only — NEVER modify state
- Use `AsNoTracking()` for all query handlers
- Project directly to DTOs — never return domain entities
- Filter by `UserId` / `TenantId` in the query (access control)

## Domain Events

```csharp
// Events/GoalCreated.cs
public record GoalCreatedEvent(Guid GoalId, string UserId) : INotification;

// Handlers can be in Infrastructure (for side effects)
public class GoalCreatedHandler : INotificationHandler<GoalCreatedEvent>
{
    private readonly IXpService _xpService;

    public GoalCreatedHandler(IXpService xpService) => _xpService = xpService;

    public async Task Handle(GoalCreatedEvent notification, CancellationToken ct)
    {
        await _xpService.AwardXpAsync(notification.UserId, XpAction.GoalCreated, ct);
    }
}
```

### Event Rules
- Events are past tense: `GoalCreated`, `WorkflowCompleted`, `HumanTaskApproved`
- Events are notifications (`INotification`) — multiple handlers can respond
- Handlers should be idempotent (events may be replayed)
- Side-effecting handlers go in Infrastructure, not Core

## Pipeline Behaviors

### Validation Behavior
```csharp
public class ValidationBehavior<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        var failures = _validators
            .Select(v => v.Validate(request))
            .SelectMany(r => r.Errors)
            .Where(f => f != null)
            .ToList();

        if (failures.Any())
            throw new ValidationException(failures);

        return await next();
    }
}
```

### Logging Behavior
```csharp
public class LoggingBehavior<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        _logger.LogInformation("Handling {RequestType}", typeof(TRequest).Name);
        var response = await next();
        _logger.LogInformation("Handled {RequestType}", typeof(TRequest).Name);
        return response;
    }
}
```

### Registration Order
```csharp
// Pipeline behaviors execute in registration order (outermost first)
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
// Request → Logging → Validation → Handler → Validation → Logging → Response
```

## Controller Integration

```csharp
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class GoalsController : ControllerBase
{
    private readonly ISender _sender;

    public GoalsController(ISender sender) => _sender = sender;

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateGoalRequest req, CancellationToken ct)
    {
        var command = new CreateGoalCommand(req.Name, req.Type, req.TargetAmount, req.Deadline, CurrentUserId);
        var result = await _sender.Send(command, ct);

        if (!result.Success) return BadRequest(result);
        return CreatedAtAction(nameof(GetById), new { id = result.Data!.Id }, result);
    }
}
```

## Anti-Patterns
- Handler calling another handler via `ISender.Send()` — compose in the service layer instead
- Commands that return complex domain objects — return DTOs only
- Queries that modify state — strict read-only enforcement
- Monolithic handlers with 200+ lines — extract domain logic to services
- Missing `CancellationToken` propagation through the pipeline
- Publishing events before `SaveChangesAsync` — data might not persist if save fails
