# Sprint Workflow — Development Conventions

These rules govern how Claude Code orchestrates development work across any project using this plugin system.

## Plugin

| Plugin | Version | Purpose |
|--------|---------|---------|
| `sprint-workflow` | 3.5.1 | 9 specialist agents, 23 engineering skills (incl. `architecture-drift-check`), 13 commands (incl. `/sprint-architect`). v3.5: Phase 1.5 integrate-to-local-master before review, PostToolUse sprint-reminder hook (additionalContext is injected into agent context — `Stop` hooks cannot do this per Claude Code schema, so the agent-visible reminder lives on PostToolUse), shared rate limit via `SPRINT_STOP_HOOK_RATE_LIMIT_S` (default 600s), Linear comments ingestion in dispatch, Codex foreground-only constraint. Plus all v3.4 features: consistent `<epic-id>`/`<milestone-id>`/`<task-id>`/`<project-id>` argument convention, drift detection across plan/enrich/QA/review/retro, auto skill discovery, Linear MCP (opt-in for sprints, required for `/sprint-architect`), Codex delegation (opt-in) |

## Architecture Is In Linear, Not In Markdown

The architecture & roadmap artifact for any non-trivial initiative lives in Linear as a **Project Document** titled `Architecture & Roadmap` — created by `/sprint-architect`, updated by `/sprint-architect --update`. Local markdown architecture files are explicitly forbidden because they go stale and nobody opens them.

Agents fetch the doc via Linear MCP when their task references a Linear Epic or Task; they do not duplicate it into the repo. The chain is: Linear Project → Project Document → Epic Issue → Task Issue → implementation. Every level resolves back up to the doc.

When the implementation diverges from the doc, agents report it via the standard `## Architecture Drift Detected` block defined in `architecture-drift-check` SKILL.md — drift is a `WARNING`, erosion (violating an Accepted ADR) is `BLOCKING`. The fix is either to revise the work or to run `/sprint-architect --update <project-id>` to record the deliberate decision change.

Install via: `/plugins marketplace add rynhardt-potgieter/sprint_workflow` then `/plugins install sprint-workflow`

All engineering-standards skills are bundled inside the plugin. Agents access them via `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`.

### Optional Integrations

| Integration | Detection | Purpose |
|-------------|-----------|---------|
| **Linear MCP** | Auto-detected via `mcp__linear__*` or `mcp__claude_ai_Linear__*` tools | Single-track sprint management in Linear (replaces markdown plan files) |
| **Codex CLI** | Auto-detected via `/codex:rescue` + `/codex:adversarial-review` skills | Token-efficient task execution and cross-model QA |

Both are opt-in. When unavailable, the plugin operates identically to v2.x (markdown tracking, Claude-only agents).

---

## Command Surface (12 total)

### Architecture-first
- `/sprint-architect` — produce a Linear Project + `Architecture & Roadmap` document + Epic issues from any context (session conversation, PRD, attached docs). Hard requirement: Linear MCP. Use `--update <project-id>` to refresh the doc when reality has shifted.

### Core lifecycle
- `/sprint-plan` — produce a sprint plan (accepts `--grill` for spec interrogation first; auto-loads parent Project's `Architecture & Roadmap` when given an Epic ID)
- `/sprint-enrich` — specialist enrichment of the plan; specialists also flag domain-specific drift against the Architecture & Roadmap
- `/sprint-start` — execute the 6-phase flow; Phase 3 includes architecture drift check
- `/sprint-review` — quality gates on completed work outside sprint flow
- `/sprint-status` — current sprint status from Linear or MD

### Recovery & resumption
- `/sprint-continue` — resume an interrupted sprint, idempotent
- `/sprint-resume-task <id>` — re-run a single task without re-entering the full flow
- `/sprint-handoff` — write `docs/SPRINT_HANDOFF.md` snapshot for the next session

### Quality & reflection
- `/sprint-bug-triage` — multi-agent bug review → user triage → Linear sub-issues OR `docs/BUG_BACKLOG.md`
- `/sprint-grill` — pre-plan interrogation against the domain model
- `/sprint-retro` — data-driven retrospective at sprint end
- `/sprint-rollback` — safety-gated sprint revert

## The Sprint Lifecycle

### `/sprint-plan` — Plan

The orchestrator feeds user context to the `product-manager` agent, which produces a structured sprint plan:

1. **Read the spec** — PRD, design doc, roadmap, or issue list
2. **Analyze the codebase** — understand what's built vs what's planned
3. **Write user stories** (INVEST criteria) with MoSCoW prioritization
4. **Define acceptance criteria** — testable, specific, Given/When/Then where complex
5. **Assign agents and skills** to each story
6. **Group stories** — parallel groups (no dependencies) vs sequential groups
7. **Flag codex-eligible tasks** — when Codex is available, each task gets a delegation flag
8. **Output** — Linear issues (if Linear MCP available) OR `docs/SPRINT_PLAN.md` (default)

The plan returns to the main session for user review before proceeding.

### `/sprint-enrich` — Enrich (Optional)

Specialist agents review the plan and add domain expertise:

- `dba-agent` — migration safety, index recommendations, PII flags
- `security-agent` — OWASP concerns, auth gaps, dependency vetting
- `test-writer` — test cases per story (unit, integration, mocks)
- `qa-playwright` — E2E scenarios, accessibility checks, visual baselines
- `backend-dev` / `frontend-dev` — technical risks, anti-patterns, complexity flags

Enrichments are consolidated and merged into the plan before execution. When Codex is available, enrichment also confirms/overrides codex-eligible flags based on complexity findings.

### `/sprint-start` — Execute

The orchestrator dispatches agents in a strict 6-phase flow:

**The sprint lead NEVER writes code.** It only dispatches, tracks, and updates the plan.

| Agent | Role | Model | Skills (Always) | Skills (Conditional) |
|-------|------|-------|-----------------|---------------------|
| `backend-dev` | Server-side code | opus | `code-standards` | `dotnet-api`, `rust-cli`, `api-design`, `postgresql-data`, `security-compliance`, `cqrs-patterns`, `event-mqtt`, `bpmn-workflow`, `cli-agent-patterns`, `rust-testing` |
| `frontend-dev` | Client-side UI | opus | `code-standards` | `react-typescript`, `api-design`, `event-mqtt`, `security-compliance`, `computational-geometry` |
| `test-writer` | Tests | sonnet | `code-standards` | `dotnet-api`, `react-typescript`, `rust-testing`, `api-design` |
| `qa-agent` | Quality gates | sonnet | `code-standards` | All skills relevant to work being validated |
| `qa-playwright` | E2E browser testing | sonnet | `code-standards`, `react-typescript` | `api-design`, `security-compliance` |
| `docs-agent` | Documentation | sonnet | `code-standards`, `api-design` | All domain-relevant skills |
| `dba-agent` | Database & compliance | opus | `postgresql-data`, `security-compliance`, `code-standards` | `dotnet-api` |
| `security-agent` | Security audits | opus | `security-compliance`, `code-standards`, `api-design` | All domain-relevant skills |
| `product-manager` | Sprint planning & specs | opus | All available skills | — |

**Every agent follows a 3-step onboarding:**
1. Read skill files (project-local priority, then plugin-bundled standards)
2. Read project CLAUDE.md
3. Execute the task

#### Phase 1: Implementation Agents
Dispatch agents per the plan's parallel groups. Tasks flagged `codex-eligible` route to `/codex:rescue` (main session invokes directly). Non-eligible tasks dispatch Claude opus agents as before. Launch independent tasks in parallel. **Update tracking** (Linear or MD) after each agent completes.

#### Phase 2: Test Writer
Dispatch `test-writer` (and `qa-playwright` for E2E) after implementation completes. Include acceptance criteria and test cases from the enrichment. **Update the plan** after tests are written.

#### Phase 3: Quality Gates (parallel)
Dispatch BOTH simultaneously:
- **QA (Codex-first)**: When Codex available, main session runs build/lint/test + `/codex:adversarial-review` with skill-driven focus strings. When unavailable, dispatches `qa-agent` (Claude sonnet) as fallback.
- `pr-review-toolkit:code-reviewer` — code quality, patterns, UX regressions (always Claude)

#### Phase 4: Fix Loop
For each BLOCKING issue from Phase 3, classify the fix:
- **Surgical** (single file, lint, null check, test) → `/codex:rescue` (when available)
- **Architectural** (multi-file, design, interface) → re-dispatch original Claude agent
Re-validate after each fix. Loop until PASS — no task completes with known violations.

**Update tracking** (Linear or MD) with issues found and resolved.

#### Phase 5: Documentation
Dispatch `docs-agent` for: technical docs, CHANGELOG, README updates, version bumps, ADRs.

#### Phase 6: Commit & Push
The orchestrator (main session) commits directly using `git-flow` or `tfs-flow` skill (auto-detected):
1. **Logical commit/checkin separation** — one per feature, tests separate, docs separate
2. **Message format**: `<type>(<scope>): <summary>` (same for both Git and TFVC)
3. **Finalize tracking** — Linear: set all tasks/stories to "Done". MD: mark all stories `completed` in plan document.
4. **Push** — only after all gates pass

---

## Spec-Driven Development

Every implementation task MUST be tied to a source specification. Agents do not decide what to build — the spec does.

### Agent Self-Validation

Before marking a task complete, agents MUST:
1. Re-read the spec section quoted in their prompt
2. Verify every element exists in their implementation
3. Confirm user-facing strings match the spec exactly
4. Fix any deviation before reporting done

### Sprint-Lead Coordination

The sprint lead MUST:
1. Read the project's spec documents
2. Extract verbatim spec sections for each task
3. Write explicit acceptance criteria (verifiable by reading code)
4. Include anti-patterns from spec "What We Avoid" sections
5. Include the user test scenario
6. Reference spec file paths so agents can find full context
7. Verify agent output against spec after completion

---

## Breaking Change Safety

When removing, renaming, or changing the signature of any exported function, type, component, API endpoint, or interface:

1. **Before touching the declaration**, grep for the old name across the ENTIRE codebase
2. **Update every consumer** in the same change
3. **Applies to**: TS/JS exports, C# public methods, API routes, store actions, hooks, types, CSS classes
4. **Why**: Type checkers may pass if the broken file isn't in the active compilation path, but the app crashes at runtime

---

## Post-Task Workflow

After completing every implementation task:

1. **Build check** — run the project's build/type-check commands
2. **Consumer search** — if exports were renamed/removed, grep for old names across full codebase
3. **Code Review** — spin up `pr-review-toolkit:code-reviewer`
4. **Documentation** — spin up `docs-agent` (background) to update docs if needed

---

## Execution Order Summary

```
/sprint-plan    → detect Linear/Codex → product-manager creates plan
                  (flags codex-eligible tasks) → user reviews
                                                      ↓
/sprint-enrich  → specialist agents review plan (optional)
                  confirm/override codex-eligible flags → user approves
                                                      ↓
/sprint-start   → load plan from Linear OR markdown
                  Phase 1: implementation (codex-eligible → Codex, else → Claude agents)
                      ↓ update tracking (Linear or MD)
                  Phase 2: test-writer + qa-playwright
                      ↓ update tracking
                  Phase 3: QA (Codex adversarial review) + pr-review-toolkit (Claude)
                      ↓ BLOCKING issues?
                  Phase 4: fix loop (surgical → Codex, architectural → Claude)
                      ↓ re-validate → loop until clean
                  Phase 5: docs-agent (docs, changelog, version)
                      ↓ update tracking
                  Phase 6: commit/checkin → finalize tracking (Linear → Done, MD → completed)
```

---

## Bundled Engineering Skills (23)

All skills live at `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` inside the plugin.

| Skill | Domain | When to Use |
|-------|--------|-------------|
| `code-standards` | Universal | Always — naming, git, logging, formatting |
| `dotnet-api` | .NET 8 | Any C#/.NET backend work |
| `react-typescript` | React 19 | Any React/TS/Vite frontend work |
| `postgresql-data` | PostgreSQL | Schema design, migrations, indexing |
| `api-design` | REST APIs | New endpoints, response wrappers, error handling |
| `security-compliance` | Security | Auth, OWASP, PII, data protection, secrets |
| `event-mqtt` | Events | MQTT, SSE, pub/sub, outbox pattern |
| `bpmn-workflow` | Workflows | BPMN 2.0, gateways, state machines |
| `cqrs-patterns` | CQRS | MediatR, commands/queries, domain events |
| `rust-cli` | Rust CLI | Clap, error handling, JSON output, CLI design |
| `rust-testing` | Rust Tests | insta snapshots, fixtures, integration tests |
| `computational-geometry` | 2D Math | Bezier, boolean ops, compositing, curve fitting |
| `git-flow` | Git Workflow | Branching, commits, PRs, releases |
| `tfs-flow` | TFVC Workflow | Workspaces, checkins, shelvesets, branching, work items |
| `cli-agent-patterns` | Agent UX | How LLM agents should use CLI tools efficiently |
| `task-board-ops` | Sprint Ops | Task tracking, status flow, board format |
| `linear-sprint-planning` | Linear MCP | Issue taxonomy, Milestones, labels, status lifecycle, query/creation patterns, Bug Backlog Epic |
| `codex-delegation` | Codex CLI | Eligibility criteria, adversarial review, fix routing, context passing |
| `diagnose` | Engineering discipline | Reproduce → minimize → hypothesize → instrument → fix → verify; required reading for `/sprint-bug-triage` reviewers and Phase 4 fix loop |
| `tdd` | Engineering discipline | Red-green-refactor; mandatory regression tests for bug fixes; integration with `/sprint-start` Phase 1/2 |
| `zoom-out` | Engineering discipline | Recovery procedure when 3+ navigation attempts have failed or code is unfamiliar |
| `worktree-handoff` | Engineering discipline | Subagent + orchestrator contract for getting code out of an isolated worktree (Claude or Codex) without losing work or copying files by hand |
| `architecture-drift-check` | Architecture governance | Reflexion-modeling check that compares planned or implemented work against the Linear Architecture & Roadmap doc. Distinguishes drift (warning) from erosion (blocking). Used by `/sprint-plan`, `/sprint-enrich`, Phase 3 QA, code review, and `/sprint-retro` |

---

## Hooks (Automated)

| Event | Trigger | Action |
|-------|---------|--------|
| `PostToolUse` | Edit/Write | Language-specific type-check reminder |
| `PreToolUse` | Bash (git push) | Build verification gate |
| `Stop` | Session end | If `.claude/.sprint-active` sentinel exists, emit a one-shot reminder to update tracking. Silent in non-sprint sessions. Cannot loop (command-type hook, not prompt-type). |

---

## Linear MCP Integration (v3.0)

When Linear MCP is detected, sprint tracking uses Linear as the **sole source of truth** (no markdown plan files):

| Concept | Linear Mapping | Label |
|---------|---------------|-------|
| Sprint | Milestone | — |
| Story | Issue (top-level) | Epic (#4cb782) |
| Task | Sub-issue (parentId → Story) | Task (#f2994a) |

- **Single-track**: Either Linear OR markdown, never both
- **Auto-detected**: presence of `mcp__linear__*` or `mcp__claude_ai_Linear__*` tools
- **Mid-sprint fallback**: if Linear goes down, prompt user to approve MD fallback
- **Status lifecycle**: Backlog → Todo → In Progress → In Review → Done / Canceled

## Codex Delegation (v3.0)

When Codex CLI is detected, eligible tasks route to Codex for token conservation:

- **QA is Codex-first**: Main session runs build/lint/test + `/codex:adversarial-review` instead of dispatching Claude qa-agent
- **PR review stays Claude**: `pr-review-toolkit:code-reviewer` is always Claude
- **Task delegation**: Sprint-plan flags tasks as `codex-eligible`. Phase 1 routes eligible tasks to `/codex:rescue`
- **Fix routing**: Surgical fixes (single file, lint, null check) → Codex. Architectural fixes → original Claude agent
- **Model**: Always best available Codex model unless user overrides
- **Auto-detected**: presence of `/codex:rescue` + `/codex:adversarial-review` skills

## Key Principles

- **Sprint lead never writes code** — only orchestrates agents
- **Vertical slices** — one feature end-to-end before the next
- **Never skip QA** — manual build checks are not a substitute
- **Spec is truth** — agents implement what the spec says, not what they think is better
- **Retry until clean** — no task is complete with known violations
- **Minimal fixes** — prefer targeted fixes over structural redesigns
- **Single-track tracking** — Linear OR markdown, never both simultaneously
- **Codex for execution, Claude for review** — conserve tokens by routing scoped work to Codex
- **Always set `name:` in docker-compose.yml** — prevents container collisions
- **Update CLAUDE.md** — when establishing new patterns or fixing recurring mistakes
