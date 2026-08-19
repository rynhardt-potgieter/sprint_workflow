---
name: serverless-lambda-api
description: "Serverless/Lambda API standards — route-module structure (Hono or lambda-api style), Zod request validation, a VisibleError + centralized error-handler pattern, RFC-7807-style responses, the auth request-context singleton, and the add-model sentinel convention. Use this skill when writing or reviewing any serverless HTTP API code. Enforces the tenant-isolation rule: scope every read/write to the caller's org(s) from the auth context, never a body/path/query-supplied id."
---

# Serverless / Lambda API Standards

Authoritative patterns for a TypeScript HTTP API deployed as a **single app behind one Lambda** (Hono or lambda-api), proxied via API Gateway. No .NET, no MediatR, no Clean-Architecture layering — route modules and a thin middleware stack.

## Runtime shape
- One entry point (e.g. `src/lambdas/api.ts`) builds one app, applies global middleware, mounts route modules, and exports `handler = handle(app)`.
- Deployed by the Serverless Framework (`serverless.yml`), Node runtime, bundled by esbuild. Local dev via `serverless-offline`.
- One Lambda, `/{proxy+}` → the handler. Note `{proxy+}` does **not** match the root `/`, so real health is a concrete route like `GET /health`.

## Route-module contract
Every model is a self-contained sub-app that `export default`s. One module per entity, mounted at a plural path:
```ts
import { Hono } from 'hono'
import { zodValidator } from '../../middleware/zod-validator'
import { RecordSchema } from '@lib/schemas'
import { Auth, VisibleError } from '../../core'

const app = new Hono()

app.get('/', async (c) => {
  const orgId = Auth.organisations()?.[0]?.id
  if (!orgId) throw new VisibleError('forbidden', 'No organisation in context')
  // ...load from the repository, scoped to orgId (see dynamodb-single-table)
  return c.json({ success: true, data: [] })
})

app.post('/', zodValidator('json', RecordSchema), async (c) => {
  const body = c.req.valid('json')
  return c.json({ success: true, data: body }, 201)
})

export default app
```

## The add-model sentinels (do NOT remove)
A scaffolding step (a codegen CLI or hand-editing) inserts new routes at fixed marker comments in the entry file. Keep them intact:
- `// <add-model:imports>` → `import recordRoutes from '../core/record'`
- `// <add-model:routes>`  → `app.route('/records', recordRoutes)`

Mount routes **after** the global auth middleware so every route is authed. Convention: **plural mount path** (`/records`), **singular module folder** (`core/record`).

## Request validation — a Zod validator, not raw handlers
Wrap the framework's Zod validator to return structured errors, and validate `json`/`query`/`param` against a schema from the shared schemas package. Never redeclare a shape inline:
```ts
app.post('/', zodValidator('json', CreateRecordSchema), async (c) => {
  const dto = c.req.valid('json')   // typed + validated
})
```

## Errors — throw `VisibleError`, map it centrally
Define a `VisibleError(type, message, param?, details?)` with `type ∈ {validation, authentication, forbidden, not_found, rate_limit, internal}`, a `statusCode()` map, and a `toResponse()` that emits an RFC-7807-style body. Wire the mapper as the app-level error handler:
```ts
app.onError(onError)              // maps thrown VisibleError → statusCode() + toResponse() JSON
app.use('/*', authorizerMiddleware)
```
> **GOTCHA (Hono 4.x):** the app always has a default `onError`, so a `try/catch` middleware wrapping `next()` never catches a *thrown* error — the composer routes it to the app-level `onError`. Map `VisibleError` via **`app.onError`**, NOT a `app.use('/*', errorHandler)` wrapper — the latter silently turns every thrown `VisibleError` into a plaintext 500.

Rules:
- **Throw `VisibleError`** for all expected failures — never hand-write `c.json({error}, 4xx)` in a handler.
- `authentication` for missing/invalid identity, `forbidden` for authz (wrong org), `not_found` for missing entities, `validation` for semantic (non-schema) validation.
- Unexpected throws fall through to a generic 500 — never leak internals.

## Auth context — a request-scoped `Auth` singleton
A global `authorizerMiddleware` populates an `Auth` request-context singleton from the API Gateway authorizer (or an offline stub):
```ts
Auth.userId()          // the caller's subject id
Auth.organisations()   // [{ id, name, ... }] the caller belongs to
Auth.getContext()      // full authorizer context
```

## Tenant isolation is NOT optional
**Always scope every read/write to `Auth.organisations()` — never trust an orgId (or any tenant id) from the request body, path, or query.** A handler must not read or write another org's data because the request said so.
- Derive the data partition from the auth context, validate the caller actually has the referenced org in context, and throw `new VisibleError('forbidden', ...)` otherwise.
- Note the auth context may be **cached** (a short TTL) — it is the trust boundary for *authorization/partitioning*, not necessarily a fresh read. To *list/display* a user's current resources, read fresh from the source of truth (an external org/permissions provider); keep the cached `Auth` for scoping.

## Response envelope & pagination
- Return `{ success: true, data }` for success; errors go through `VisibleError` → `app.onError`.
- Lists support `?limit=&cursor=` — cursor-based pagination over the datastore's continuation token, not offset/page (see `dynamodb-single-table`).

## Persistence & config
- Data access goes through a repository abstraction (see `dynamodb-single-table`) — do not hand-roll the low-level client in a handler.
- Resolve table/resource names from **SSM parameters** (or an env var wired in `serverless.yml`) — never hardcode stage-suffixed names (see `pulumi-aws`).
- Tighten `serverless.yml` IAM to specific resource ARNs rather than `service:*` on `*` when practical.

## Verification
```bash
pnpm --filter <api-pkg> check-types
pnpm --filter <api-pkg> lint
```
