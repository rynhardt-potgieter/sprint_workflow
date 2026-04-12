---
name: api-design
description: "RESTful API design standards — endpoint naming, HTTP methods, response wrappers, error handling (RFC 7807), pagination, versioning, rate limiting, and OpenAPI conventions. Use this skill when designing new API endpoints, reviewing API contracts, adding error handling, implementing pagination, or ensuring API consistency across the project."
---

# RESTful API Design Standards

This skill defines authoritative patterns for all API design across projects.

## URL Structure

### Resource Naming
```
GET    /api/goals              # List goals (paginated)
GET    /api/goals/{id}         # Get single goal
POST   /api/goals              # Create goal
PUT    /api/goals/{id}         # Full update
PATCH  /api/goals/{id}         # Partial update
DELETE /api/goals/{id}         # Delete goal
```

### Rules
- **Nouns, not verbs**: `/api/goals`, not `/api/getGoals`
- **Plural**: `/api/goals`, not `/api/goal`
- **Lowercase kebab-case for multi-word**: `/api/fund-bundles`, not `/api/fundBundles`
- **Nested resources for containment**: `/api/goals/{goalId}/positions`
- **Max 2 levels of nesting**: Beyond that, promote to top-level with query filters
- **Actions as sub-resources**: `POST /api/goals/{id}/archive` (not `PUT /api/goals/{id}` with `{ archived: true }`)

## HTTP Methods & Status Codes

| Method | Purpose | Success Code | Body |
|--------|---------|-------------|------|
| GET | Read | 200 | Resource or list |
| POST | Create | 201 | Created resource + `Location` header |
| PUT | Full replace | 200 | Updated resource |
| PATCH | Partial update | 200 | Updated resource |
| DELETE | Remove | 204 | No body |

### Error Codes
| Code | Meaning | When |
|------|---------|------|
| 400 | Bad Request | Validation failures, malformed input |
| 401 | Unauthorized | Missing/invalid token |
| 403 | Forbidden | Valid token, insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate resource, concurrency conflict |
| 422 | Unprocessable Entity | Business rule violation |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Server Error | Unhandled exception (log + generic message) |

## Response Wrappers

### Success Response
```json
{
  "data": { "id": "...", "name": "Emergency Fund", ... },
  "success": true,
  "message": null
}
```

### Error Response (RFC 7807-inspired)
```json
{
  "data": null,
  "success": false,
  "message": "Goal target amount must be positive",
  "errors": ["TargetAmount must be greater than 0"]
}
```

### Paginated Response
```json
{
  "items": [...],
  "totalItems": 42,
  "pageNumber": 1,
  "pageSize": 20,
  "hasNextPage": true
}
```

### Implementation
```csharp
public static class ApiResponse
{
    public static ApiResponse<T> Ok<T>(T data, string? message = null)
        => new(data, true, message);
    public static ApiResponse<T> Fail<T>(string message, params string[] errors)
        => new(default, false, message, errors);
}
```

## Pagination

### Query Parameters
```
GET /api/goals?page=1&pageSize=20&sortBy=createdAt&sortDir=desc
```

- Default `pageSize`: 20, max: 100
- Default `sortDir`: `desc` (newest first)
- Always return `totalItems` and `hasNextPage`

### Cursor-Based (For Large Datasets)
```
GET /api/activity?cursor=eyJpZCI6MTIzfQ&limit=20
```
Use cursor pagination when offset-based becomes expensive (>10K rows).

## Filtering & Search

```
GET /api/goals?status=active&type=emergency&search=house
```

- Simple filters: query parameters matching field names
- Search: `search` parameter for free-text across multiple fields
- Date ranges: `createdAfter=2025-01-01&createdBefore=2025-12-31`
- Never filter on sensitive fields (password, tokens)

## Request Validation

### Controller Level
```csharp
[HttpPost]
public async Task<IActionResult> Create([FromBody] CreateGoalRequest request, CancellationToken ct)
{
    if (string.IsNullOrWhiteSpace(request.Name))
        return BadRequest(ApiResponse.Fail<GoalDto>("Name is required"));

    // Or use FluentValidation / DataAnnotations
}
```

### DTO Naming
- **Requests**: `CreateGoalRequest`, `UpdateGoalRequest`
- **Responses**: `GoalDto`, `GoalSummaryDto`
- **Service results**: `TradeResult`, `XpAwardResult`

## Versioning Strategy

For breaking changes only:
```
/api/v2/goals    # URL path versioning (preferred for simplicity)
```

Non-breaking changes (adding fields, new endpoints) don't need versioning.

## OpenAPI / Swagger

```csharp
[HttpGet("{id:guid}")]
[ProducesResponseType<ApiResponse<GoalDto>>(200)]
[ProducesResponseType(404)]
[ProducesResponseType(401)]
public async Task<IActionResult> GetById(Guid id, CancellationToken ct) { ... }
```

- Always specify `ProducesResponseType` for documentation
- Use `[FromQuery]`, `[FromBody]`, `[FromRoute]` explicitly
- Add `/// <summary>` XML docs on endpoints for Swagger UI descriptions

## CORS (ASP.NET Core)

```csharp
builder.Services.AddCors(o => o.AddPolicy("Default", p =>
    p.WithOrigins("http://localhost:5173", "https://app.example.com")
     .AllowAnyHeader()
     .AllowAnyMethod()
     .AllowCredentials()));
```

- Never `AllowAnyOrigin()` in production
- Always pair with `AllowCredentials()` when using Auth0 cookies

## Rate Limiting

Use ASP.NET Core rate limiting middleware for public or expensive endpoints:
```csharp
builder.Services.AddRateLimiter(o =>
{
    o.AddFixedWindowLimiter("api", opt =>
    {
        opt.Window = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 100;
        opt.QueueLimit = 0;
    });
});
```

## API Design Checklist

Before shipping any new endpoint:
- [ ] Correct HTTP method and status codes
- [ ] Wrapped in `ApiResponse<T>` or `PagedResponse<T>`
- [ ] `[Authorize]` applied (or explicit `[AllowAnonymous]` with justification)
- [ ] `CancellationToken` propagated
- [ ] Input validation with clear error messages
- [ ] `ProducesResponseType` attributes for Swagger
- [ ] Consistent naming with existing endpoints
