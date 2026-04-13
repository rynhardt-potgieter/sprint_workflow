# Sprint Workflow — Development Conventions

These rules govern how Claude Code orchestrates development work across any project using this plugin system.

## Plugin

| Plugin | Version | Purpose |
|--------|---------|---------|
| `sprint-workflow` | 2.0.0 | 9 specialist agents, 16 engineering skills, 5 commands, hooks, auto skill discovery |

Install via: `/plugins marketplace add rynhardt-potgieter/sprint_workflow` then `/plugins install sprint-workflow`

All engineering-standards skills are bundled inside the plugin. Agents access them via `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`.

---

## The Sprint Lifecycle

### `/sprint-plan` — Plan

The orchestrator feeds user context to the `product-manager` agent, which produces a structured sprint plan:

1. **Read the spec** — PRD, design doc, roadmap, or issue list
2. **Analyze the codebase** — understand what's built vs what's planned
3. **Write user stories** (INVEST criteria) with MoSCoW prioritization
4. **Define acceptance criteria** — testable, specific, Given/When/Then where complex
5. **Assign agents and skills** to each story
6. **Group stories** — parallel groups (no dependencies) vs sequential groups
7. **Output** — structured sprint plan document saved to `docs/SPRINT_PLAN.md`

The plan returns to the main session for user review before proceeding.

### `/sprint-enrich` — Enrich (Optional)

Specialist agents review the plan and add domain expertise:

- `dba-agent` — migration safety, index recommendations, PII flags
- `security-agent` — OWASP concerns, auth gaps, dependency vetting
- `test-writer` — test cases per story (unit, integration, mocks)
- `qa-playwright` — E2E scenarios, accessibility checks, visual baselines
- `backend-dev` / `frontend-dev` — technical risks, anti-patterns, complexity flags

Enrichments are consolidated and merged into the plan before execution.

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
Dispatch `backend-dev`, `frontend-dev`, `dba-agent`, etc. per the plan's parallel groups. Launch independent stories in parallel. **Update the plan** after each agent completes.

#### Phase 2: Test Writer
Dispatch `test-writer` (and `qa-playwright` for E2E) after implementation completes. Include acceptance criteria and test cases from the enrichment. **Update the plan** after tests are written.

#### Phase 3: Quality Gates (parallel)
Dispatch BOTH simultaneously:
- `qa-agent` — build, lint, test, spec compliance → structured report
- `pr-review-toolkit:code-reviewer` — code quality, patterns, UX regressions

#### Phase 4: Fix Loop
For each BLOCKING issue from Phase 3:
1. Re-dispatch the ORIGINAL agent that wrote the code (not a different one)
2. Include: original acceptance criteria + specific blocking issues
3. Instruction: "Fix ONLY these issues"
4. Re-validate with `qa-agent`
5. Loop until PASS — no task completes with known violations

**Update the plan** with issues found and resolved.

#### Phase 5: Documentation
Dispatch `docs-agent` for: technical docs, CHANGELOG, README updates, version bumps, ADRs.

#### Phase 6: Commit & Push
The orchestrator (main session) commits directly using `git-flow` or `tfs-flow` skill (auto-detected):
1. **Logical commit/checkin separation** — one per feature, tests separate, docs separate
2. **Message format**: `<type>(<scope>): <summary>` (same for both Git and TFVC)
3. **Update the plan document** — mark all stories `completed`
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
/sprint-plan    → product-manager creates plan → user reviews
                                                      ↓
/sprint-enrich  → specialist agents review plan (optional) → user approves
                                                      ↓
/sprint-start   → Phase 1: implementation agents (parallel groups)
                      ↓ update plan
                  Phase 2: test-writer + qa-playwright
                      ↓ update plan
                  Phase 3: qa-agent + pr-review-toolkit (parallel)
                      ↓ BLOCKING issues?
                  Phase 4: fix loop (original agents fix own work)
                      ↓ re-validate → loop until clean
                  Phase 5: docs-agent (docs, changelog, version)
                      ↓ update plan
                  Phase 6: commit/checkin (logical units via git-flow or tfs-flow) → push
```

---

## Bundled Engineering Skills (16)

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

---

## Hooks (Automated)

| Event | Trigger | Action |
|-------|---------|--------|
| `PostToolUse` | Edit/Write | Language-specific type-check reminder |
| `PreToolUse` | Bash (git push) | Build verification gate |
| `Stop` | Session end | Verify sprint plan document is updated |

---

## Key Principles

- **Sprint lead never writes code** — only orchestrates agents
- **Vertical slices** — one feature end-to-end before the next
- **Never skip QA** — manual build checks are not a substitute
- **Spec is truth** — agents implement what the spec says, not what they think is better
- **Retry until clean** — no task is complete with known violations
- **Minimal fixes** — prefer targeted fixes over structural redesigns
- **Always set `name:` in docker-compose.yml** — prevents container collisions
- **Update CLAUDE.md** — when establishing new patterns or fixing recurring mistakes
