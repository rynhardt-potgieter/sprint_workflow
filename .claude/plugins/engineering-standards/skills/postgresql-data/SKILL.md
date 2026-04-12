---
name: postgresql-data
description: "PostgreSQL database design and data access patterns — schema design, EF Core migrations, indexing strategies, JSONB, connection pooling, Dapper for performance-critical queries, and Npgsql conventions. Use this skill when designing database schemas, writing migrations, optimizing queries, adding indexes, using JSONB columns, or troubleshooting database performance."
---

# PostgreSQL & Data Access Standards

This skill defines authoritative patterns for all database work across projects.

## Schema Design Conventions

### Naming
| Item | Convention | Example |
|------|-----------|---------|
| Tables | snake_case, plural | `user_profiles`, `workflow_instances` |
| Columns | snake_case | `created_at`, `auth0_id` |
| Primary keys | `id` (Guid/UUID) | `id UUID PRIMARY KEY DEFAULT gen_random_uuid()` |
| Foreign keys | `<entity>_id` | `user_id`, `tenant_id` |
| Indexes | `ix_<table>_<columns>` | `ix_users_auth0_id` |
| Unique constraints | `uq_<table>_<columns>` | `uq_users_email` |

### Standard Columns (All Entities)
```csharp
public Guid Id { get; set; }
public DateTimeOffset CreatedAt { get; set; }
public DateTimeOffset UpdatedAt { get; set; }
```

Always use `DateTimeOffset`, never `DateTime` — PostgreSQL stores as `timestamptz`.

### EF Core Mapping
```csharp
builder.ToTable("user_profiles");  // Explicit snake_case table name
builder.Property(e => e.CreatedAt).HasDefaultValueSql("now()");
builder.Property(e => e.UpdatedAt).HasDefaultValueSql("now()");
```

## Indexing Strategy

### When to Add Indexes
- Foreign keys (EF Core does NOT auto-index FK columns in PostgreSQL)
- Columns used in WHERE clauses of frequent queries
- Columns used in ORDER BY of paginated queries
- Unique business identifiers (`auth0_id`, `email`, `slug`)

### Index Types
```sql
-- B-tree (default) — equality, range, sorting
CREATE INDEX ix_users_email ON users (email);

-- Unique
CREATE UNIQUE INDEX uq_users_auth0_id ON users (auth0_id);

-- Partial — index only relevant rows
CREATE INDEX ix_instances_running ON workflow_instances (status) WHERE status = 'Running';

-- GIN — for JSONB containment queries
CREATE INDEX ix_profiles_metadata ON user_profiles USING gin (metadata);

-- Composite — for multi-column queries (put most selective column first)
CREATE INDEX ix_instances_tenant_status ON workflow_instances (tenant_id, status);
```

### Anti-Patterns
- Indexing every column "just in case" — each index slows writes
- Missing indexes on foreign keys — causes slow JOINs
- Using `LIKE '%search%'` on large tables — use full-text search or trigram indexes instead
- Indexing low-cardinality columns (e.g., boolean) without a partial index

## JSONB Best Practices

### When to Use JSONB
- Flexible metadata/configuration that varies per record
- Nested structures that would require many join tables
- Semi-structured data (allocations, badge data, radar metrics)

### When NOT to Use JSONB
- Data you need to JOIN on regularly — use a proper column
- Data you need referential integrity on — use a foreign key
- Frequently queried/filtered fields — promote to a column with an index

### EF Core JSONB Configuration
```csharp
builder.Property(e => e.Allocations)
    .HasColumnType("jsonb")
    .HasConversion(
        v => JsonSerializer.Serialize(v, JsonOpts),
        v => JsonSerializer.Deserialize<Dictionary<string, decimal>>(v, JsonOpts)!);
```

### Querying JSONB
```sql
-- Containment (uses GIN index)
SELECT * FROM profiles WHERE metadata @> '{"role": "admin"}';

-- Path extraction
SELECT metadata->>'name' FROM profiles;

-- Array containment
SELECT * FROM profiles WHERE metadata->'tags' ? 'premium';
```

## Connection Pooling (Npgsql)

```csharp
// In Program.cs — connection string must include pooling params
"Host=localhost;Database=mydb;Username=user;Password=pass;Maximum Pool Size=20;Minimum Pool Size=5"
```

### Rules
- Default pool: 20 max connections per app instance
- Scale pool size with instance count (total connections <= PostgreSQL max_connections - 10)
- Use `NpgsqlDataSource` (Npgsql 7+) as singleton for raw ADO.NET access
- Never open/close connections manually in EF Core — let the context manage it

## Data Access Patterns

### EF Core (Default — 90% of queries)
```csharp
// Read with projection
var goals = await _db.Goals
    .Where(g => g.UserId == userId)
    .OrderByDescending(g => g.CreatedAt)
    .Select(g => new GoalDto(g.Id, g.Name, g.TargetAmount, g.CurrentAmount))
    .ToListAsync(ct);

// Write
_db.Goals.Add(new Goal { Name = name, UserId = userId });
await _db.SaveChangesAsync(ct);
```

### Dapper (Performance-Critical — 10% of queries)
Use Dapper when:
- Complex reporting queries with multiple CTEs
- Bulk operations where EF Core generates inefficient SQL
- Raw SQL is clearer than LINQ for the query

```csharp
using var conn = _dataSource.OpenConnection();
var results = await conn.QueryAsync<ReportRow>(
    "SELECT ... FROM ... WHERE tenant_id = @TenantId",
    new { TenantId = tenantId });
```

### Pagination Pattern
```csharp
var query = _db.Items.Where(i => i.TenantId == tenantId);
var total = await query.CountAsync(ct);
var items = await query
    .OrderByDescending(i => i.CreatedAt)
    .Skip((page - 1) * pageSize)
    .Take(pageSize)
    .Select(i => new ItemDto(...))
    .ToListAsync(ct);

return new PagedResponse<ItemDto>(items.ToArray(), total, page, pageSize, page * pageSize < total);
```

## Migration Workflow

```bash
# 1. Stop running .NET process (file locks block dotnet ef)
# 2. Generate migration
dotnet ef migrations add AddGoalTracking \
  --project ProjectName.Infrastructure \
  --startup-project ProjectName.Api

# 3. Review generated migration SQL
dotnet ef migrations script --idempotent \
  --project ProjectName.Infrastructure \
  --startup-project ProjectName.Api

# 4. Apply
dotnet ef database update \
  --project ProjectName.Infrastructure \
  --startup-project ProjectName.Api
```

### Migration Safety
- Always review auto-generated migrations before applying
- Destructive changes (drop column, drop table) need explicit confirmation
- Data migrations: Write both Up and Down methods
- Production: Use idempotent scripts, never `database update` directly

## Multi-Tenancy Pattern
- `TenantId` column on all tenant-scoped entities
- Global query filter: `modelBuilder.Entity<T>().HasQueryFilter(e => e.TenantId == _tenantId)`
- Extracted from JWT `tenant_id` claim in controllers
- Index all `tenant_id` columns

## Soft Deletes (When Used)
```csharp
builder.Property(e => e.DeletedAt).IsRequired(false);
builder.HasQueryFilter(e => e.DeletedAt == null);  // Global filter
builder.HasIndex(e => e.DeletedAt).HasFilter("deleted_at IS NULL");  // Partial index
```
