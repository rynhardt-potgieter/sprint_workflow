---
name: nextjs-app-router
description: "Next.js App Router + React 19 + Tailwind v4 + shadcn-on-Base-UI + TanStack Table/Query frontend standards. Use this skill when writing or reviewing any App Router web code — pages, layouts, server/client components, server-side auth guards, data tables, forms, styling, or data fetching. Covers the server-side auth-boundary pattern, shadcn-first component selection, design-token alignment, and the persistent-surface rule for compliance/assurance messages."
---

# Next.js App Router Web Standards

Authoritative front-end patterns for a Next.js **App Router** web app (`app/` dir, no `src/`). Use this instead of the Vite/Zustand/React-Router `react-typescript` skill when the project is App Router — the two stacks share almost no idioms.

## Stack shape (verify against `package.json`)
- **Next.js App Router** — React Server Components by default; `"use client"` only where you need interactivity.
- **React 19**, function components only, named exports.
- **TypeScript strict** + `noUncheckedIndexedAccess` (array/record access yields `T | undefined` — guard it).
- **Tailwind v4** (CSS-first, no `tailwind.config.*`). Theme tokens live in `app/globals.css`.
- **shadcn/ui on Base UI** (`@base-ui/react`), NOT Radix. Use Base UI's `render={<X/>}` prop, never Radix `asChild`.
- **TanStack Query** for server state, **TanStack Table** for tables.
- **react-hook-form + Zod** for interactive forms (`@hookform/resolvers`).

## Routing & the auth boundary — guard in the layout, not client-side
Group routes by trust level and enforce auth **server-side in the protected layout**, not in a client effect or middleware you can bypass:
- `app/(auth)/*` — guest pages (login, forgot/reset password). `(auth)/layout.tsx` calls `requireGuest()`.
- `app/(protected)/*` — authed pages. `(protected)/layout.tsx` calls `requireAuth()` — a **server-side** redirect to `/login` before any protected content renders.

```tsx
// app/(protected)/layout.tsx  — the gate. Runs on the server.
export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const session = await requireAuth();          // redirects server-side if unauthenticated
  return <AppShell user={session.user} org={session.org}>{children}</AppShell>;
}
```
- `requireAuth()` reads the session from an HTTP-only cookie/token on the server (e.g. an Amplify/Cognito server adapter, NextAuth, or your own). **A client-only `useEffect` redirect is not a guard** — the protected HTML has already shipped.
- Keep auth logic in the layout. `AppShell` and everything below it receives the resolved user/org as **plain props** — no auth calls in the client chrome.

## Server vs Client components
- **Default to Server Components.** Fetch data server-side, pass plain serializable props down.
- Add `"use client"` only for state, effects, event handlers, auth-provider client calls, or TanStack Table/Query hooks.
- Server data-fetching goes through a small `fetchWithAuth` helper that injects the caller's token. **Never** call your API with raw `fetch` from a server component without auth.
- Any client subtree that calls the auth SDK must be wrapped in the auth provider — hoist the provider to the smallest boundary that needs it, not the whole app.

## The layout shell — centralize navigation, don't prop-thread it
Mount the authed chrome **once** at `(protected)/layout.tsx`. Put navigation in a single `NAV_ITEMS` array consumed by the sidebar; a link added there appears on every authed route. Derive active state from `usePathname()`. Do NOT thread `navLinks`/`pageTitles` props through every page — pages render as plain `children` inside the shell.

## The data-table kit — reuse, don't rebuild per screen
Prefer a **declarative `ColumnConfig[]` over TanStack Table** wrapped in a provider, so each list screen is config, not bespoke table code:
```tsx
"use client";
const columns: ColumnConfig[] = [
  { accessorKey: "name", label: "Name", sortable: true },
  { accessorKey: "status", label: "Status", enableFiltering: true },
  { accessorKey: "createdOn", label: "Created", type: "date", sortable: true },
];

export function RecordsTable({ rows }: { rows: Record[] }) {
  return (
    <TableProvider initialState={{ queryKey: "records", data: rows, columnConfig: columns,
        excludeFields: ["id"], enablePagination: true,
        rowAction: { type: "navigate", path: "/records/:id" } }}>
      <Toolbar><TableSearch /><TableFacetedFilter columnKey="status" title="Status" /><TableExport fileName="records.csv" /></Toolbar>
      <TableContent />
    </TableProvider>
  );
}
```
- **Sharp edge:** if the provider reads `data`/`columnConfig` into `useState` **once**, it will NOT react to a refetch. When rows come from TanStack Query, push new data via an effect (`setAllData`) or `key` the provider on a query hash.
- Keep the kit **domain-neutral** — never hardcode one feature's enum values (e.g. status labels) inside the shared table code. That leakage propagates into every screen that reuses it.

## Styling & theme tokens
- Define semantic tokens (shadcn oklch, light + dark) in `app/globals.css` and use semantic utilities (`bg-background`, `text-muted-foreground`, `bg-primary`, `border-border`). Never hardcode hex colors in components.
- A custom property resolves against the element it's declared on — declare every token in **both** `:root` and `.dark`; a `:root`-only token breaks under a nested `.dark` subtree.

### ⚠ Tailwind v4 fails SILENTLY — three traps, all recur
None of these throw a build error. The class is accepted and simply does nothing, so it fails **visually**, at runtime, in whatever component you weren't looking at.
1. **A `:root` custom property produces NO utility unless its key is registered in a `@theme` block.** Without a matching `@theme inline { --color-*: var(--*) }`, `bg-background` and friends silently no-op repo-wide. Any new token must be added there, not just to `:root`.
2. **Arbitrary values cannot contain literal spaces — use `_`.** `h-[calc(100svh - var(--x))]` never generates; it must be `h-[calc(100svh_-_var(--x))]`.
3. **`dark:` utilities need `@custom-variant dark`** when there is no theme provider — otherwise an OS-dark user gets `dark:` firing while your `.dark` tokens never apply (a half-dark UI).

**Never assume a class works — verify it EMITS.** Grep the compiled stylesheet (`.next/static/css/*.css`) for the escaped selector before trusting it. "It type-checks" proves nothing about CSS.

## The persistent-surface rule (compliance / assurance messages)
A message that conveys a **legal, compliance, or audit assurance** — "captured locally, nothing was transmitted", "your declaration was submitted", a data-protection notice — must render as a **durable** element (an `Alert`, a status panel, or a terminal success card), NOT a transient toast alone.
- Toasts (`sonner`) are for **transient** success/error cues that the user does not need to re-read.
- An assurance the user may need to **see, re-read, or screenshot** has to persist on screen. Keep the toast as the transient cue if you like, but always add a durable surface alongside it.

## Tabbed multi-section forms — surface a cross-tab error summary
When a multi-section form uses a **tabbed** layout, inactive tab panels are unmounted, so per-field validation errors on other tabs are **invisible** — the submit button silently no-ops with no indication of which tab is incomplete. Every tabbed form MUST add a handler that surfaces a **persistent** destructive `Alert` naming the incomplete **section titles**, plus a transient toast. Do NOT "fix" the silent no-op by weakening validation. (The RJSF-specific version of this rule lives in the `zod-rjsf-forms` skill — cross-reference it for schema-driven forms.)

## Verification (run after every web change)
```bash
pnpm --filter <web-pkg> check-types   # next typegen && tsc --noEmit
pnpm --filter <web-pkg> lint           # eslint (warnings ok if configured, errors block)
```
