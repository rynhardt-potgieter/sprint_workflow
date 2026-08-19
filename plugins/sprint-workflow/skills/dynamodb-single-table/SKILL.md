---
name: dynamodb-single-table
description: "DynamoDB single-table design and data-access standards — partition/sort key modelling, GSIs, a generic Repository<T> base-class access pattern, org-scoped partitioning for tenant isolation, cursor pagination, and idempotency. Use this skill when designing DynamoDB tables, writing repositories, or persisting any model to DynamoDB. Replaces the postgresql-data skill on a DynamoDB stack — there is no SQL, no EF Core, and no migrations."
---

# DynamoDB Single-Table Data Standards

Authoritative data-access patterns for a DynamoDB-backed service. Ignore the `postgresql-data` skill on this stack — no SQL, no ORM, no migrations. Persist your own state (drafts, declarations, snapshots) in DynamoDB; reference externally-owned data (company/person records owned by another system) by id rather than duplicating it.

## Use a `Repository<T>` base class — don't touch the client directly
Do not instantiate `DynamoDBClient` in a handler. Put marshalling, key handling, and the common access methods in a generic base class and extend it per model:
```ts
// A generic single-table repository base.
export abstract class Repository<T> {
  constructor(
    protected readonly tableName: string,
    protected readonly pk = 'pk',
    protected readonly sk = 'sk',
  ) {}
  abstract // getById / putOne / delete / list / query — marshal & unmarshal here
}

export class RecordRepository extends Repository<Record> {
  constructor(tableName: string) { super(tableName, 'pk', 'sk') }
}
```
Typical surface: `getById(partition, id)`, `putOne(partition, id, data)`, `delete(partition, id)`, `list(partition)`, `query(partition, attributes)`, `findAll(partition, { filter, parameters, projection? })`. The base class marshals/unmarshals so callers work in domain types.

## Key design (single-table)
- **Partition by tenant/organisation.** Every entity belongs to a tenant (from the auth context), so the natural partition is the org id/URN. This gives cheap `list(orgId)` **and** enforces tenant isolation at the storage layer.
- **Sort key encodes type + id** so one table holds many entity types per tenant and supports prefix range-queries: `RECORD#<uuid>`, `DECLARATION#<uuid>`, `DOC#<uuid>`.
- Example: `pk = ORG#<orgId>`, `sk = RECORD#<id>` → `getById('ORG#'+orgId, 'RECORD#'+id)`.
- Add **GSIs** only for real alternate access paths (e.g. a status index, a by-date index). Each GSI is a cost and a write-amplification — model the access pattern first, then add the index; don't mirror a relational schema.
- Store `createdOn`/`updatedOn` timestamps and `createdBy` (the caller's id) on every write. Pick one suffix convention (`...On`) and keep it consistent.

## Access control is not optional
- **Always derive the partition from the auth context (`Auth.organisations()`), never from the request body/path/query.** A handler must not read or write another tenant's partition. This is the primary tenant-isolation boundary — the storage-layer half of the API-layer rule in `serverless-lambda-api`.
- Validate the caller actually holds the referenced org in context before any repository call; throw a `forbidden` error otherwise.

## Idempotency
- Writes that can be retried (queue consumers, at-least-once webhooks, client re-submits) must be **idempotent**. Use a deterministic key (`pk`/`sk` derived from a stable business id, or a dedicated idempotency-key attribute) plus a conditional write (`attribute_not_exists(pk)`) so a replay is a no-op, not a duplicate.

## Table-name resolution
Tables are created in IaC (see `pulumi-aws`) and their names published to **SSM** at a path like `/<app>/<stage>/<unit>/<model>-table-name`. Resolve at runtime via a parameter provider (`get(namespace, keys)`) or an env var wired into `serverless.yml`. **Never hardcode table names** — they are stage-suffixed.

## Schemas define the shape
The `T` in `Repository<T>` is a Zod-inferred type from the shared schemas package (see `zod-rjsf-forms`). Validate on the way in (a Zod validator at the route) and trust the type internally; persisted records should round-trip through the schema.

## Pagination — cursor, not offset
DynamoDB paginates with `LastEvaluatedKey`. For list endpoints expose an opaque base64 `cursor` (the encoded last key) plus `limit` — never offset/page. Keep **`Query` over `Scan`**: always query by partition; never full-table `Scan` in a request path.

## Local development
Point at a LocalStack DynamoDB endpoint, or stub the repository behind an interface, so `pnpm dev` never needs real AWS credentials.

## Anti-patterns
- ❌ `new DynamoDBClient()` in a handler — use the repository.
- ❌ A tenant id from the request used as a partition — derive it from the auth context.
- ❌ `Scan` in a request path.
- ❌ Storing externally-owned data (a company's legal name, its directors) as the source of truth — reference by id; the owning system is authoritative.
- ❌ Hardcoded or non-stage-suffixed table names.
- ❌ A GSI per column "just in case" — model the access pattern first.
