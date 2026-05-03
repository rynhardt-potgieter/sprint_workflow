---
name: codex-delegation
description: Codex CLI delegation patterns — eligibility criteria, available commands (/codex:rescue, /codex:adversarial-review), context passing, focus string composition from skill tags, fix routing, and model selection. Use this skill when deciding whether to delegate a task to Codex or route it to a Claude agent.
version: 1.0.0
---

# Codex Delegation

This skill defines when and how to delegate work to OpenAI Codex from within the sprint-workflow orchestrator. The goal is **token conservation** — Codex is ~4x more token-efficient than Claude for scoped execution tasks.

**Core principle:** Claude plans, reviews, and orchestrates. Codex executes scoped work and provides cross-model QA.

---

## 1. Detection Logic

Detect Codex CLI availability at the start of every sprint command:

1. Check if the Codex plugin is installed by looking for `/codex:rescue` and `/codex:adversarial-review` in the session's available skills (these appear in the system-reminder skill listing)
2. Alternatively, run `codex --version` via Bash — if it returns a version string, the CLI is installed
3. If both skills are present OR the CLI responds → **Codex mode is active**
4. If neither skill is listed AND `codex --version` fails → **Codex unavailable**, all work routes to Claude agents (v2.2.2 behavior)

**Runtime failure:** If a Codex command fails during execution (e.g., Codex CLI not responding, auth error, rate limit), fall back to the equivalent Claude agent for that specific task. Log the failure but do not abort the sprint.

---

## 2. Eligibility Criteria

The product-manager agent flags each Task as `codex-eligible: true/false` during sprint planning. The sprint-enrich command can override these flags.

### Codex-Eligible (YES)

| Signal | Example |
|--------|---------|
| Well-scoped CRUD | "Create REST endpoint for listing orders with pagination" |
| Migration scaffold | "Add migration for new `audit_logs` table with 5 columns" |
| Boilerplate generation | "Create repository + service + controller for new entity" |
| Test generation | "Write unit tests for OrderService covering happy/error paths" |
| Single-concern feature | "Add email validation to registration form" |
| Clear spec, no ambiguity | Acceptance criteria are specific and complete |
| No local service deps | Task doesn't require running DB, Docker, VPN, or other local services |

### NOT Codex-Eligible (NO)

| Signal | Example |
|--------|---------|
| Cross-cutting architecture | "Redesign the middleware pipeline for multi-tenancy" |
| Design exploration | "Prototype three approaches for state management" |
| Local services needed | "Test against running PostgreSQL with seed data" |
| Security-critical | "Implement OAuth2 PKCE flow with token rotation" |
| Idiomatic .NET patterns | "Build Clean Architecture layer with DI, EF Core, MediatR" |
| Multi-file design change | "Refactor entity hierarchy across 8 domain models" |
| Heavy iteration expected | "Design the optimal UX for the configuration panel" |
| Complex state management | "Implement undo/redo with command pattern across components" |

### Edge Cases

- **Tests for complex logic:** Codex-eligible if the implementation already exists and tests are straightforward assertions. NOT eligible if tests require complex fixtures, mocking strategies, or design decisions.
- **API endpoints:** Codex-eligible for standard CRUD. NOT eligible if the endpoint has complex authorization rules or business logic.
- **Frontend components:** Codex-eligible for simple presentational components. NOT eligible for components with complex state, animations, or accessibility requirements.

---

## 3. Task Delegation (Phase 1)

When a Task is `codex-eligible: true` AND Codex is available, the **main session orchestrator** handles delegation directly (no subagent middleman):

### Step 1: Compose Context

Read the relevant skill files and compose a complete context string:

```
You are implementing a sprint task. Follow these conventions:

## Project Conventions
[Paste key sections from CLAUDE.md / AGENTS.md]

## Skill Standards
[Paste relevant sections from skill files — e.g., dotnet-api patterns, code-standards naming]

## Task
Title: [task title from plan]
Story: [parent story title]

## Acceptance Criteria
[Paste verbatim from plan/Linear]

## Anti-patterns (DO NOT)
[Paste from plan/Linear]

## Technical Notes
[File paths to create/modify, existing patterns to follow]

## Build Verification
After implementation, run: [build command]
```

### Step 2: Invoke Codex

```
/codex:rescue --effort high "<composed context>"
```

- Always use `--effort high` for implementation tasks
- Always use best available Codex model (do not pin specific versions)
- If the user has specified a model preference, honor it

### Step 3: Verify Result

After Codex completes:
1. Run the project's build/type-check command via Bash
2. Spot-check 2-3 key acceptance criteria by reading the created/modified files
3. If build fails or key ACs are not met → fall back to the original Claude agent:
   - Run `git diff --name-only` to identify files Codex modified
   - Read those files to capture the partial implementation
   - Dispatch the Claude agent with: the original acceptance criteria, the specific failure ("build error: ...", "AC not met: ..."), and the list of files Codex created/modified so the agent can inspect and fix rather than start from scratch

### Step 4: Report

Output a completion report for tracking:
```
Task: [title]
Executor: Codex
Status: Complete / Failed (fell back to Claude)
Files changed: [list]
Build: Pass / Fail
AC spot-check: [which ACs verified]
```

---

## 4. QA Delegation (Phase 3)

When Codex is available, the main session orchestrator handles QA **directly** instead of dispatching the Claude sonnet `qa-agent`. The `qa-agent` subagent is NOT dispatched separately — this Codex-based QA process is the **complete replacement** for the qa-agent gate in that sprint. This provides cross-model review — Codex catches issues that Claude-reviewing-Claude misses.

> **CLAUDE.md reconciliation:** The "never skip QA" principle still holds — QA is not skipped, it is performed via Codex instead of the Claude qa-agent. The same mechanical checks (build, lint, test, spec compliance) run identically. The adversarial review adds code quality analysis on top.

### Step 1: Mechanical Checks (Main Session via Bash)

Run the same checks the qa-agent would:
```bash
# Build
<project build command>

# Type-check
<project type-check command>

# Lint
<project lint command>

# Tests
<project test command>
```

### Step 2: Spec Compliance (Main Session via Read)

Read the implementation files and verify each acceptance criterion is met. Produce a checklist:
```
| Criterion | Met? | Notes |
|-----------|------|-------|
```

### Step 3: Adversarial Review (Codex)

Compose a focus string from the task's skill tags using the mapping table below, then invoke:

```
/codex:adversarial-review --base <branch> "focus: <composed focus string>"
```

### Step 4: Parse Result

Convert the Codex review output into the standard QA report format:

```
## QA Report — [task/story]

### Mechanical Checks
| Check | Result |
|-------|--------|

### Spec Compliance
| Criterion | Met? | Notes |
|-----------|------|-------|

### Codex Adversarial Review
[CRITICAL] count
  - file:line: issue
[MAJOR] count
  - file:line: issue
[MINOR] count
  - file:line: issue

### Issues Found
- [BLOCKING] ... (must fix)
- [WARNING] ... (should fix)
- [INFO] ... (nice-to-have)

### Verdict: PASS / FAIL
```

---

## 5. Focus String Mapping

Compose the `/codex:adversarial-review` focus string from the task's assigned skills:

| Skill | Focus String Fragment |
|-------|----------------------|
| `dotnet-api` | ".NET idioms, async/await patterns, CancellationToken propagation, middleware pipeline, DI registration" |
| `react-typescript` | "React hooks rules, TypeScript strict mode, component patterns, state management, no `any` types" |
| `postgresql-data` | "query performance, N+1 queries, index usage, migration safety, connection pooling" |
| `security-compliance` | "authentication, authorization, PII exposure, injection vulnerabilities, secrets in code/logs" |
| `api-design` | "REST conventions, HTTP method correctness, error handling (RFC 7807), pagination, response consistency" |
| `cqrs-patterns` | "command/query separation, handler design, pipeline behaviors, domain event handling" |
| `event-mqtt` | "topic design, QoS levels, message idempotency, connection lifecycle, error recovery" |
| `bpmn-workflow` | "gateway patterns, state transitions, compensation handling, process instance lifecycle" |
| `rust-cli` | "error handling with anyhow/thiserror, clap argument design, output formatting, exit codes" |
| `rust-testing` | "test organization, insta snapshot assertions, fixture management, integration test isolation" |
| `computational-geometry` | "numerical stability, edge cases (degenerate geometry), coordinate precision, winding order" |
| `code-standards` | "naming conventions, error handling patterns, logging (no PII), async correctness" |
| `git-flow` | "commit message format, branch naming, PR description quality" |
| `tfs-flow` | "checkin conventions, work item association, file tracking" |
| `cli-agent-patterns` | "tool call efficiency, command sequencing, token optimization" |
| `task-board-ops` | "status flow correctness, task tracking consistency" |

### Composition Rules

- Include fragments for ALL skills assigned to the task
- Concatenate with "; "
- Prepend with "correctness, " (always check correctness first)
- If the task touches auth/security: always append "; authentication, PII exposure, injection" even if `security-compliance` isn't in the skill list

**Example:** Task with skills `dotnet-api` + `api-design`:
```
"focus: correctness; .NET idioms, async/await patterns, CancellationToken propagation, middleware pipeline, DI registration; REST conventions, HTTP method correctness, error handling (RFC 7807), pagination, response consistency"
```

---

## 6. Fix Routing (Phase 4)

When QA or PR review reports BLOCKING issues, classify each fix before routing:

### Surgical Fix → Codex

Route to `/codex:rescue` when ALL of these are true:
- Single file affected
- Fix is mechanical (lint error, null check, missing import, typo, off-by-one)
- No design decision required
- No interface/API change

```
/codex:rescue --effort high "Fix BLOCKING issue in <file>:<line>: <specific error>. Do not change any other files. Run <build command> after fixing."
```

### Architectural Fix → Original Claude Agent

Re-dispatch the original Claude agent when ANY of these are true:
- Multiple files affected
- Interface or API signature change required
- Design pattern issue (wrong abstraction, missing layer)
- Cross-cutting concern (auth, middleware, state management)
- The fix contradicts the original acceptance criteria (needs PM input)

Include in the re-dispatch prompt:
1. Original acceptance criteria
2. Specific BLOCKING issues to fix
3. Instruction: "Fix ONLY these issues. Do not refactor or add features."

### Ambiguous Cases

If classification is unclear, default to the **Claude agent** — it's more expensive but safer for ambiguous fixes. Codex may introduce new issues when the fix scope isn't crystal clear.

---

## 7. Model Selection

- **Always use the best available Codex model** — do not hardcode or pin model versions
- Model names change over time; trust the Codex CLI to use its configured default
- If the user explicitly specifies a model preference (e.g., "use gpt-5.4-mini for cost savings"), honor it by passing the model flag
- For `--effort`, always use `high` for both implementation tasks and adversarial review

---

## 8. What Codex Never Does

These responsibilities ALWAYS stay with Claude agents regardless of Codex availability:

| Responsibility | Agent | Why |
|---------------|-------|-----|
| Sprint planning | product-manager (opus) | Requires deep spec analysis, taxonomy understanding, multi-stakeholder reasoning |
| PR code review | pr-review-toolkit:code-reviewer (Claude) | Claude's idiomatic pattern recognition is superior for review |
| Security audit | security-agent (opus) | OWASP, PII, compliance requires deep domain expertise |
| Documentation | docs-agent (sonnet) | Needs project context, changelog conventions, ADR format |
| Database design | dba-agent (opus) | Migration safety, compliance, performance requires expertise |
| E2E test design | qa-playwright (sonnet) | Playwright patterns, accessibility, visual regression expertise |

---

## 9. Context Passing Best Practices

### What to Include in Codex Prompts

1. **Acceptance criteria** — verbatim from the plan/Linear issue
2. **Skill standards** — key patterns from relevant skill files (paste the sections, don't just reference file paths — Codex can't read plugin skills)
3. **Anti-patterns** — what NOT to do
4. **File paths** — specific files to create or modify
5. **Build command** — so Codex can self-verify
6. **Existing patterns** — paste a short example from the codebase showing the pattern to follow

### What NOT to Include

- Full skill files (too many tokens — extract the relevant sections)
- Entire CLAUDE.md (extract project-specific conventions only)
- Unrelated acceptance criteria from other tasks
- Historical context about why decisions were made (Codex just needs the "what")

### Return Value Handling

- From `/codex:rescue`: Codex makes changes to the working directory. Verify via build + spot-check.
- From `/codex:adversarial-review`: Returns a structured review verdict. Parse into the QA report format.
- Capture Codex session IDs from output for potential `codex resume <id>` if follow-up is needed.

---

## 10. Worktree Handoff

If the Codex thread runs inside a Codex-managed worktree (Codex App's Worktree mode, or any flow that creates a separate working tree), the orchestrator MUST follow `worktree-handoff` SKILL.md to integrate the result. Codex-specific quirks covered there:

- Codex worktrees default to **detached HEAD** — the thread must create a named branch (`agent/<task-id>-<slug>`) and commit before exiting, otherwise the orchestrator cannot fetch the work.
- `.gitignored` files do **not** survive Codex Handoff — never include local-only config in the diff.
- Codex Handoff (Local ↔ Worktree) replaces the orchestrator's `git fetch` step, but all other integration steps (merge, conflict resolution in main tree, cleanup after merge) are unchanged.

Never copy files out of a Codex worktree by hand — that is the symptom of a missing commit. Re-invoke Codex with the exit contract instead.

---

## 11. Architecture Drift Check (Phase 3 with Codex)

When `/sprint-start` Phase 3 routes QA through Codex adversarial review and the sprint's parent Project has an `Architecture & Roadmap` document, the **main session orchestrator** must pre-fetch the document and pass its prescribed-model summary inline to Codex. Codex does not have Linear MCP — it cannot fetch the doc itself.

### Step 1: Pre-fetch (orchestrator, before invoking Codex)

```
1. Pick any Story from the sprint → get_issue({id, includeRelations: true}) → projectId
2. list_documents({projectId}) → find "Architecture & Roadmap"
3. get_document({id}) → capture body
4. Extract the prescribed-model summary: §3 Containers, §4 Cross-Cutting Concerns, §6 Accepted ADRs (skip Proposed/Deprecated)
```

If the document doesn't exist, skip the drift portion of the focus string (per `architecture-drift-check` SKILL.md §9 graceful skip).

### Step 2: Compose Focus String With Architecture Context

Append to the standard focus string from §5 of this skill:

```
"; architecture drift — compare the diff against this prescribed model:

CONTAINERS: <one-line each>
EDGES: <container A → container B [sync/async/shared-db]>
CROSS-CUTTING: <one-line each>
ACCEPTED ADRs:
- ADR-N: <decision> → forbids: <one-line>

Flag erosion (violates an ADR or cross-cutting constraint) as BLOCKING.
Flag drift (new component/edge not in this model) as WARNING."
```

This trades tokens for cross-model verification — Codex is now checking Claude's implementation against a doc Claude wrote. Cost is ~500–1500 extra tokens per Codex call; benefit is catching erosion that Claude-reviewing-Claude would rationalize away.

### Step 3: Parse Drift Findings From Codex Output

Codex returns its review in the standard format. Parse `## Architecture Drift Detected` sub-sections (per `architecture-drift-check` SKILL.md §7) and merge into the QA report:

- Erosion → joins the `BLOCKING` list (fix loop applies)
- Drift → joins the `WARNING` list (informational, recorded in retro)

The Claude-side `pr-review-toolkit:code-reviewer` ALSO runs the drift check (it has Linear MCP via the orchestrator's tools). When both Codex and Claude reviewers flag the same finding, dedupe by file path + ADR reference — same finding from two angles is one finding, not two.
