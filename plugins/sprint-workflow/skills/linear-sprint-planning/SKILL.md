---
name: linear-sprint-planning
description: Linear MCP integration patterns — issue taxonomy (Epic/Task labels), Milestone-based sprint grouping, status lifecycle, label definitions, query patterns, creation patterns, retry handling, and team/project discovery. Use this skill when sprint tracking is routed through Linear instead of markdown files.
version: 1.0.0
---

# Linear Sprint Planning

This skill defines how the sprint-workflow plugin interacts with Linear as a tracking backend. Linear mode is **single-track** — when active, Linear is the sole source of truth. No markdown plan files are created alongside Linear issues. MD mode serves as the fallback if Linear MCP is unavailable at detection time or fails mid-sprint (with user approval).

---

## 1. Detection Logic

Detect Linear MCP availability at the start of every sprint command:

1. Look for available MCP tools matching **either** prefix:
   - `mcp__linear__*` (direct Linear MCP)
   - `mcp__claude_ai_Linear__*` (Claude.ai hosted Linear MCP)
2. Try calling `list_teams` with the first matching prefix
3. If the call succeeds → **Linear mode is active**. Use this prefix for all subsequent calls.
4. If the call fails and the **other prefix also exists** → try `list_teams` with the second prefix. If it succeeds → Linear mode using this prefix.
5. If the call returns error code `-32600` on both prefixes → **retry each once**. If any retry succeeds → Linear mode. If all fail → MD mode.
6. If no Linear MCP tools exist at all → **MD mode** (default, no further action)

**Mid-sprint failure:** If a Linear MCP call fails during an active sprint (after detection succeeded), prompt the user:

```
Linear MCP returned an error. Options:
1. Retry the operation
2. Approve fallback to markdown tracking for the rest of this session
```

If the user approves MD fallback, switch to MD mode for the remainder of the session. Note this in any output: `⚠ Tracking fell back to markdown due to Linear MCP error.`

---

## 2. Taxonomy

| Sprint Concept | Linear Mapping | Label | Notes |
|---------------|---------------|-------|-------|
| **Sprint** | Milestone | — | Date-based grouping. Stories are assigned to a Milestone via `milestoneId`. |
| **Story** | Issue (top-level, no `parentId`) | Epic | Represents a user-facing feature or goal. Assigned to the Sprint Milestone. |
| **Task** | Sub-issue (`parentId` → Story) | Task | Agent-assigned work item. Contains codex-eligible flag in description. |

### Structured Fields in Issue Descriptions

Linear has no custom fields on all plans. Encode agent metadata as structured markdown in the issue description:

```markdown
**Agent:** backend-dev
**Skills:** dotnet-api, api-design, postgresql-data
**Codex-eligible:** true
**Codex rationale:** Well-scoped CRUD endpoint with clear spec
**Phase:** 1 (parallel)
```

These fields are parsed by the sprint-start orchestrator when loading the plan from Linear.

---

## 3. Label Definitions

### Hierarchy Labels (mutually exclusive — every issue gets exactly one)

| Label | Hex Color | Meaning |
|-------|-----------|---------|
| **Epic** | `#4cb782` | Top-level story — user-facing feature, sprint goal, initiative |
| **Task** | `#f2994a` | Actionable sub-issue under an Epic — assigned to a specific agent |

### Type Labels (applied alongside the hierarchy label)

| Label | Hex Color | Meaning |
|-------|-----------|---------|
| **Feature** | `#BB87FC` | New capability or user-facing functionality |
| **Bug** | `#EB5757` | Defect in existing functionality |
| **Improvement** | `#4EA7FC` | Enhancement — better DX, performance, UX polish |
| **QA** | `#f5ec20` | Manual verification, browser test, E2E not covered by automated tests |
| **tech-debt** | `#F97316` | Code cleanup, deprecated features, test gaps, build hygiene |
| **Decision** | `#F59E0B` | Locked or pending architectural/product decision |
| **Deferred** | `#64748B` | Parked pending prerequisite — not cancelled, not active |

### Label Assignment Rules

| Issue Type | Hierarchy Label | Type Labels |
|-----------|----------------|-------------|
| Sprint story (user feature) | Epic | + Feature |
| Bug fix story | Epic | + Bug |
| Enhancement story | Epic | + Improvement |
| Tech debt story | Epic | + tech-debt |
| Implementation task under story | Task | + Feature / Bug / Improvement (match parent) |
| Test task under story | Task | + QA |
| Decision record | Epic | + Decision |
| Deferred item | Epic | + Deferred |

### Label Setup

Before creating issues, ensure labels exist on the target team:

```
1. Call list_issue_labels({ team: "<team-name>" })
2. For each required label NOT in the response:
   Call create_issue_label({ team: "<team-name>", name: "<label>", color: "<hex>" })
```

**Note:** `create_issue_label` is a confirmed Linear MCP tool. If it fails or is unavailable on a particular setup, ask the user to create the missing labels manually in Linear's UI, then re-run label discovery.

---

## 4. Status Lifecycle

```
Backlog → Todo → In Progress → In Review → Done
                                    ↓
                              Canceled
```

| Status | Type | When Used |
|--------|------|-----------|
| **Backlog** | backlog | Default — unplanned, not in active sprint |
| **Todo** | unstarted | Sprint-ready — moved when sprint starts |
| **In Progress** | started | Agent dispatched and working |
| **In Review** | started | QA/code-reviewer checking |
| **Done** | completed | Passed all gates |
| **Canceled** | canceled | Won't do — descoped during enrichment or sprint |

### Status Discovery

Teams may name statuses differently. Before transitioning:

```
1. Call list_issue_statuses({ team: "<team-name>" })
2. Map sprint-workflow status names to the closest match in the response
3. Use the matched status ID for save_issue calls
```

### Phase-to-Status Mapping

| Sprint Phase | Task Status Transition |
|-------------|----------------------|
| Sprint start (bulk) | Backlog → Todo |
| Phase 1: Agent dispatched | Todo → In Progress |
| Phase 1: Agent completes | In Progress → In Review |
| Phase 3: QA/review pass | In Review → Done |
| Phase 3: QA/review fail (blocking) | In Review → In Progress (back for fixes) |
| Phase 4: Fix complete + re-validated | In Progress → Done |
| Phase 6: All gates pass | Verify all → Done |
| Descoped during enrichment | Any → Canceled |

---

## 5. Sprint Milestones

Sprints are represented as **Linear Milestones**, providing date-based grouping.

### Creating a Sprint Milestone

```
save_milestone({
  name: "Sprint 7 — Feature MVP",
  team: "<team-name>",
  targetDate: "2026-05-01"   // optional — sprint end date
})
```

### Assigning Stories to a Sprint

When creating Story issues, include the Milestone ID:

```
save_issue({
  title: "US-01: Package scaffold + types",
  team: "<team-name>",
  project: "<project-name>",
  labels: ["Epic", "Feature"],
  milestoneId: "<milestone-id>",
  ...
})
```

### Querying Sprint Status

```
list_milestones({ team: "<team-name>" })        // find active sprints
get_milestone({ id: "<milestone-id>" })          // check sprint completion
list_issues({ milestoneId: "<milestone-id>" })   // all stories in sprint
```

---

## 6. Team & Project Discovery

On first use in a session, discover the target team and project:

```
1. Call list_teams() → present team list to user
2. User confirms team (or specify in prompt)
3. Call list_projects({ team: "<confirmed-team>" }) → present project list
4. User confirms project

Cache teamId and projectId for all subsequent calls in this session.
```

If the user specifies team/project in the sprint-plan arguments, skip the discovery prompts.

---

## 7. Issue Creation Patterns

### Creating a Story (Epic)

```
save_issue({
  title: "US-01: Package scaffold + types + schemas",
  team: "<team-name>",
  project: "<project-name>",
  milestoneId: "<sprint-milestone-id>",
  labels: ["Epic", "Feature"],
  priority: 1,               // 1=Urgent, 2=High, 3=Normal, 4=Low
  estimate: 5,               // story points or complexity
  description: "**Agent:** backend-dev\n**Skills:** dotnet-api, code-standards\n**Codex-eligible:** true\n**Codex rationale:** Well-scoped scaffold with clear spec\n**Phase:** 1\n\n## User Story\n\n**As a** developer,\n**I want** a package with typed schemas,\n**So that** I can build features on a solid foundation.\n\n## Acceptance Criteria\n\n- [ ] Package created with correct structure\n- [ ] TypeScript types exported\n- [ ] Schema validation working\n\n## Anti-patterns\n\n- Do NOT use `any` types\n- Do NOT skip schema validation\n\n## Technical Notes\n\n- Follow patterns in existing packages\n- Reference: docs/architecture.md Section 3\n\n## Dependencies\n\nNone"
})
```

### Creating a Task Under a Story

Tasks inherit project association from their parent Story, but **do NOT automatically inherit the Milestone**. Include `milestoneId` on Tasks if you want them visible in the Milestone/sprint view.

```
save_issue({
  title: "Implement REST endpoint for user profile",
  team: "<team-name>",
  project: "<project-name>",
  parentId: "<story-issue-id>",
  milestoneId: "<sprint-milestone-id>",
  labels: ["Task", "Feature"],
  priority: 2,
  estimate: 3,
  description: "**Agent:** backend-dev\n**Skills:** dotnet-api, api-design\n**Codex-eligible:** false\n**Codex rationale:** Complex auth logic requiring idiomatic .NET patterns\n\n## Acceptance Criteria\n\n- [ ] GET /api/users/{id}/profile returns 200 with profile data\n- [ ] Returns 401 for unauthenticated requests\n- [ ] Returns 403 when user requests another user's profile\n\n## Dependencies\n\nBlocked by: US-01 (package scaffold)"
})
```

### Setting Dependencies

```
save_issue({
  id: "<task-id>",
  blockedBy: ["<blocking-task-id-1>", "<blocking-task-id-2>"]
})
```

Note: `blockedBy` is append-only — it adds to existing relations, does not replace.

### Transitioning Status

```
save_issue({
  id: "<issue-id>",
  state: "In Progress"       // must match exact status name from list_issue_statuses
})
```

---

## 8. Query Patterns

### All Stories in a Project

```
list_issues({ project: "<project-name>", label: "Epic", limit: 250 })
```

### All Stories in a Sprint (Milestone)

```
list_issues({ milestoneId: "<milestone-id>", label: "Epic" })
```

### All Tasks Under a Story

```
list_issues({ parentId: "<story-id>", limit: 50 })
```

### Tasks by Status

```
list_issues({ project: "<project-name>", state: "In Progress" })
```

### Full Issue Detail with Relations

```
get_issue({ id: "<issue-id>", includeRelations: true })
```

### Available Statuses and Labels

```
list_issue_statuses({ team: "<team-name>" })
list_issue_labels({ team: "<team-name>" })
```

---

## 9. Comment Patterns

Use `save_comment` for structured updates that create an audit trail:

### Decision Lock

```
save_comment({
  issueId: "<issue-id>",
  body: "## Decision Locked — 2026-04-24\n\n**Decision:** Strategy A (detach-on-edit)\n**Rationale:** Simpler implementation, matches user mental model\n**Alternatives considered:** Strategy B (copy-on-edit) — rejected due to complexity\n**Decided by:** [user/team]"
})
```

### Agent Completion Note

```
save_comment({
  issueId: "<task-id>",
  body: "## Implementation Complete — backend-dev\n\n**Files changed:**\n- src/api/controllers/UserController.cs (new)\n- src/api/models/UserProfile.cs (new)\n- src/api/startup/ServiceRegistration.cs (modified)\n\n**Build:** ✅ passing\n**Tests:** 3 unit tests added, all passing\n\n**Notes:** Used existing `BaseController` pattern. Auth middleware handles 401/403."
})
```

### QA Finding

```
save_comment({
  issueId: "<task-id>",
  body: "## QA Report — Phase 3\n\n**Verdict:** BLOCKING\n\n### Issues\n- [BLOCKING] Missing CancellationToken propagation in UserController.GetProfile (line 42)\n- [WARNING] No integration test for 403 case\n- [INFO] Consider adding response caching header\n\n**Build:** ✅ | **Lint:** ✅ | **Tests:** ✅ (but missing coverage)"
})
```

### Enrichment Addition

```
save_comment({
  issueId: "<story-id>",
  body: "## Enrichment — security-agent\n\n**Findings:**\n- AC-SEC-1: Endpoint must validate JWT audience claim\n- AC-SEC-2: Profile response must not include email unless requester owns the profile\n- AC-SEC-3: Add rate limiting (100 req/min per user)\n\n**Severity:** HIGH — auth gaps in acceptance criteria\n\n**Recommended additions to AC:**\n- [ ] JWT audience validation on all profile endpoints\n- [ ] Email field redacted for non-owner requests\n- [ ] Rate limiting configured"
})
```

### Sprint Completion

```
save_comment({
  issueId: "<story-id>",
  body: "## Sprint Complete — 2026-04-24\n\n**Commits:**\n- `abc1234` feat(api): add user profile endpoint\n- `def5678` test(api): add profile endpoint tests\n- `ghi9012` docs(api): update API documentation\n\n**Quality Gates:** All passed\n**Follow-up:** Rate limiting deferred to Sprint 8"
})
```

---

## 10. Error Handling

### Transient Errors

Linear MCP occasionally returns error code `-32600`. On any `-32600` error:

1. **Retry once** with the exact same call
2. If the retry succeeds → continue normally
3. If the retry fails → prompt the user for MD fallback (see Detection Logic section)

### Tool Availability

- `create_document` tool does **NOT exist** in Linear MCP — never attempt to call it
- `save_issue` handles both creation (no `id` field) and updates (`id` field present)
- `save_milestone` handles both creation and updates similarly

### Rate Limiting

When making bulk operations (e.g., creating 10+ issues during sprint-plan), add brief pauses between calls to avoid overwhelming the API. If you get rate-limited, wait and retry.

---

## 11. Reconstructing a Sprint Plan from Linear

When `/sprint-start` or `/sprint-enrich` loads a plan from Linear:

1. Query Stories: `list_issues({ milestoneId: "<sprint-milestone>", label: "Epic" })`
2. For each Story, query Tasks: `list_issues({ parentId: "<story-id>" })`
3. Parse structured fields from each issue description:
   - `**Agent:**` → agent assignment
   - `**Skills:**` → skill file list
   - `**Codex-eligible:**` → delegation flag
   - `**Phase:**` → execution group
   - Acceptance Criteria → `- [ ]` checklist items
   - Anti-patterns → bullet list under `## Anti-patterns`
4. Group Tasks by Phase number for parallel/sequential dispatch
5. Check current status of each Task — skip tasks already Done
6. Reconstruct the execution plan structure matching the markdown format

Use tolerant parsing — regex match field patterns rather than exact string matching, since users may edit descriptions manually.
