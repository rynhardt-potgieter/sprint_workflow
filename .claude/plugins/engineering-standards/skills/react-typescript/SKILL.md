---
name: react-typescript
description: "React 19 + TypeScript 5.9 + Vite 7 + Tailwind 4 + Zustand + React Query frontend standards. Use this skill when writing or reviewing any frontend code — components, hooks, stores, API clients, routing, styling, or state management. Also use when debugging React rendering issues, TypeScript errors, or state management problems."
---

# React 19 + TypeScript Frontend Standards

This skill defines authoritative patterns for all React frontend work across projects. Agents MUST follow these standards.

## Project Stack
- **React 19** with function components only (no class components)
- **TypeScript 5.9** with `erasableSyntaxOnly: true` — no TS parameter properties
- **Vite 7** for bundling and dev server
- **Tailwind CSS 4** via `@tailwindcss/vite` plugin
- **Zustand 5** for client state
- **React Query (TanStack Query 5)** for server state
- **React Router 7** for routing
- **Lucide React** for icons
- **Zod 4** for runtime validation

## TypeScript Conventions

### Strict Mode Rules
- All types explicit on function signatures (params and return types for exported functions)
- No `any` — use `unknown` and narrow, or define proper types
- Use discriminated unions for state machines:
  ```typescript
  type AsyncState<T> =
    | { status: 'idle' }
    | { status: 'loading' }
    | { status: 'success'; data: T }
    | { status: 'error'; error: string }
  ```
- Use `satisfies` for type-safe object literals: `const config = { ... } satisfies Config`
- `erasableSyntaxOnly: true` means no `constructor(private foo: Bar)` — use explicit field assignments

### Naming Conventions
| Item | Convention | Example |
|------|-----------|---------|
| Components | PascalCase | `GoalCard.tsx` |
| Hooks | camelCase with `use` prefix | `usePortfolios.ts` |
| Stores | camelCase with `Store` suffix | `uiStore.ts` |
| Types/Interfaces | PascalCase | `GoalDto`, `UserProfile` |
| Constants | UPPER_SNAKE_CASE | `USE_MOCKS`, `API_BASE_URL` |
| Files | PascalCase for components, camelCase for utilities | `GoalCard.tsx`, `formatCurrency.ts` |

## Component Patterns

### Function Component Structure
```tsx
interface Props {
  goal: GoalDto
  onEdit: (id: string) => void
}

export function GoalCard({ goal, onEdit }: Props) {
  // 1. Hooks (state, refs, effects)
  const [expanded, setExpanded] = useState(false)

  // 2. Derived values
  const progress = goal.currentAmount / goal.targetAmount

  // 3. Handlers
  function handleClick() {
    onEdit(goal.id)
  }

  // 4. Render
  return (...)
}
```

### Rules
- One component per file (except small local helpers like `SectionLabel`, `Field`)
- Export components as named exports, never default
- Props interface at the top of the file, co-located with the component
- Destructure props in the function signature
- Use `function` declarations for components, not arrow functions

## State Management

### Zustand (Client State)
```typescript
interface UiStore {
  sidebarOpen: boolean
  toggleSidebar: () => void
  notifications: Notification[]
  addNotification: (n: Notification) => void
}

export const useUiStore = create<UiStore>((set) => ({
  sidebarOpen: false,
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  notifications: [],
  addNotification: (n) => set((s) => ({ notifications: [...s.notifications, n] })),
}))
```

**When to use Zustand**: UI state, user preferences, notification queue, selected items, sidebar/modal state — anything that isn't fetched from the server.

### React Query (Server State)
```typescript
export function useGoals() {
  if (USE_MOCKS) return { data: mockGoals, isLoading: false }
  return useQuery({
    queryKey: ['goals'],
    queryFn: () => apiFetch<GoalDto[]>('/api/goals'),
    staleTime: 30_000,
  })
}
```

**When to use React Query**: Any data fetched from the API. Handles caching, refetching, loading/error states.

### Rules
- NEVER store server data in Zustand — use React Query
- Always provide `queryKey` arrays that include all parameters
- Use `useMutation` for POST/PUT/DELETE with `onSuccess` invalidation
- Every data-fetching hook must support `USE_MOCKS` flag

## Mock-First Development

```typescript
// api/client.ts
export const USE_MOCKS = true  // Toggle for all hooks

// hooks/useGoals.ts
export function useGoals() {
  if (USE_MOCKS) return { data: mockGoals, isLoading: false, error: null }
  return useQuery({ queryKey: ['goals'], queryFn: fetchGoals })
}
```

- Mock data in `src/mocks/` mirrors exact API response shapes
- All hooks must work with `USE_MOCKS = true`
- Mock data must match backend DTO types

## API Client Pattern

```typescript
export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getAccessToken()
  const res = await fetch(path, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...init?.headers,
    },
  })
  if (!res.ok) throw new ApiError(res.status, await res.text())
  return res.json()
}
```

- Token injected via `setTokenAccessor()` from Auth0
- All API calls go through `apiFetch` — never raw `fetch`
- Vite proxy handles `/api` routing to backend in dev

## Styling Rules

### Spacing: Inline `style` for numeric values, Tailwind for everything else
- Padding, margin, gap with specific px: `style={{ padding: '20px 24px' }}`
- Colors, borders, flex, grid, text: Tailwind classes
- Never `p-[20px]` arbitrary values — use `style` for clarity
- Use project-specific design token prefixes defined in the project's CLAUDE.md

### Design Token Usage
- Always use project CSS variables, never hardcoded colors
- Reference token prefix conventions from the project's CLAUDE.md
- Combine shadows with borders for definition in light themes

## Routing (React Router 7)

```tsx
// Lazy-loaded routes
const GoalsPage = lazy(() => import('./pages/GoalsPage'))

<Routes>
  <Route element={<AuthGate />}>
    <Route element={<AppShell />}>
      <Route path="/" element={<DashboardPage />} />
      <Route path="/goals" element={<Suspense><GoalsPage /></Suspense>} />
    </Route>
  </Route>
</Routes>
```

## Forms (React Hook Form)

```tsx
const { register, handleSubmit, formState: { errors } } = useForm<CreateGoalRequest>()

const onSubmit = async (data: CreateGoalRequest) => {
  await createGoal.mutateAsync(data)
}
```

- Use React Hook Form for all forms with >2 fields
- Zod schemas for validation via `@hookform/resolvers/zod`
- Show inline errors, not toasts, for validation failures

## Performance Rules
- Use `React.memo` only for measured performance issues, not preemptively
- Use `useCallback` for handlers passed to memoized children
- Use `useMemo` for expensive computations, not for simple transformations
- Lazy-load route-level components with `React.lazy`
- Never create new objects/arrays in render that break memoization

## Build Verification
After ANY frontend change: `cd web && npx tsc --noEmit`
Before PR: `cd web && pnpm lint`
