---
name: contract-safety
description: "Rules for keeping contracts honest across compile boundaries and HTTP boundaries — the excess-property object-literal canary for cross-boundary type drift, why an alias to a third-party type tracks drift rather than detecting it, consumer-search before rename/remove, verifying a client's route exists on the other side of the boundary, verifying property-claiming comments against source, and verifying security flags against the deploy toolchain. Use this skill when changing a shared type, an exported symbol, an API contract, a security env-var gate, or when reviewing any comment that asserts a property."
---

# Contract Safety

A collection of hard-won rules about a single failure class: **both sides build green, the runtime is broken.** Type checkers, aliases, and confident comments all *look* like enforcement while enforcing nothing. Each rule below is crisp, states the "why", and shows the smallest example that bites.

## 1. An alias to a third-party type tracks drift — it does not detect it
`type Local = SdkType['field']` **reads** like it pins a contract. It doesn't: it silently absorbs upstream changes. If the SDK renames `legalName` → `name`, the alias quietly becomes the new shape, your build passes, and any independently-written mirror on the other side of a boundary (another package, another service, a hand-written type) also passes — because nothing links them. The break surfaces at runtime, on a dependency bump, with green CI.

- An alias is documentation, not enforcement. So is a comment claiming the alias enforces something.
- A **shared schema package** is the real fix when the cost is justified.

## 2. The excess-property object-literal canary
When two independently-compiled sides must agree on a shape and you can't share a schema, write a canary **that names the fields**, on the side that owns the dependency:
```ts
const _contract: SdkDerivedType = { id: '', slug: '', legalName: '', registrationNo: '' }
void _contract
```
**The mechanism matters — most "type assertions" fail vacuously here.** Against an SDK rename of an *optional* field:
- `AssertExtends<Sdk, Local>` passes silently.
- `value satisfies Local` passes silently — a shape missing an optional field still satisfies the constraint.
- Only **excess-property checking on an object literal** fails the build (`TS2353`).

If the fields you care about are optional, constraint-based assertions prove nothing. **Prove the canary bites:** temporarily rename the field in the installed `.d.ts`, confirm the build fails, restore. An unverified canary is a comment.

Apply this to every hand-mirrored cross-app view model — e.g. the same `Record` shape declared in both an API client and a web server module. A prose "keep these in sync" comment is not enforcement; the canary is.

## 3. Consumer-search before rename/remove (migrate in the same change)
When removing, renaming, or changing the signature of any exported function, type, component, API endpoint, or interface:
1. **Before touching the declaration**, grep for the old name across the **entire** codebase — not just the file you're in.
2. **Update every consumer in the same change.** If you replace `createFoo` with `openFoo`, every importer migrates now.
3. Applies to TS/JS exports, public methods, API routes, store actions, hooks, types/interfaces, CSS class names.
4. **Why:** a type checker can pass if the broken file isn't in the active compilation path, but the app crashes at runtime. Grep is the only reliable safety net.

## 4. A client must not assert API behavior for a route that doesn't exist
The inverse of rule 3 — here the **consumer precedes the producer.** Before a server/data client's comment claims something the API does — "the API re-scopes this to the caller's orgs", "the server re-validates" — grep the API source and confirm the route it calls (a) **exists** and (b) actually does that.

In a multi-app repo a web consumer can be written against a producer that was never built, and a security-property comment then papers over a silent 404. Verify the route on the other side of the HTTP boundary, the same way you'd verify any property claim against source.

## 5. A comment that asserts a property must be verified against source
A comment saying *what* code does is cheap to check. A comment asserting a **property** — "breaks the build", "requires X", "guarantees Y", "fails closed" — is the one people act on **without** checking, so it's the one that must be true.

- Before writing a property claim, verify it in source (or by experiment) — the same standard you'd apply to the code.
- When reviewing, treat property-claiming comments as **assertions to test**, not prose to skim.
- The danger is not a comment being wrong; it's a comment being **confidently wrong in a file good enough that nobody re-checks it.** "I already approved that text" is not grounds to keep it. If you notice it's wrong, fix it or raise it.

## 6. Security flags must be verified against the deploy toolchain, not just the code
When an env var gates a security fallback (dev-only auth stubs, debug bypasses, `SKIP_AUTH`-style switches), reviewing the gate answers the wrong question. The gate can be perfect while something else in the pipeline sets the flag.

**Grep every mechanism that can populate the deployed environment** and confirm the flag is on none of them: dotenv plugins, IaC `environment:` blocks, CI/CD env, Docker `ARG`/`ENV`, Helm values, platform console settings.

Verified example: a `dotenv` bundling plugin defaulting to `include: '*'` ships **every** var from a developer's local `.env` into the deployed function's environment — so a stray `IS_OFFLINE=true` could disable a fail-closed auth gate in production. Fix: an **explicit allowlist** (`include: []`), which inverts the failure mode to *loudly missing* instead of *quietly over-shared*. Read the plugin's source for its default before trusting it — defaults are usually permissive. **A kill-switch is only as safe as the narrowest path that can set it.**

## The through-line
Aliases, `satisfies`/`extends` assertions, prose comments, and a green type-check are all **evidence that looks like proof.** When two independently-compiled or independently-deployed sides must agree, enforce the agreement with a mechanism that **fails the build (or the deploy) on drift**, and prove the mechanism bites before trusting it.
