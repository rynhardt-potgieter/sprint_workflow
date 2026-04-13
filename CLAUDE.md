# Sprint Workflow — Development Conventions

These rules govern how Claude Code orchestrates development work across any project using this plugin system.

## Plugin

| Plugin | Version | Purpose |
|--------|---------|---------|
| `sprint-workflow` | 2.0.0 | 9 specialist agents, 15 engineering skills, 3 commands, hooks, auto skill discovery |

Install via: `/plugins marketplace add rynhardt-potgieter/sprint_workflow` then `/plugins install sprint-workflow`

All engineering-standards skills are bundled inside the plugin. Agents access them via `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`.

---

## The Sprint Lifecycle

### Phase 1: Plan (Product Manager Agent)

1. **Read the spec** — PRD, design doc, roadmap, or issue list
2. **Analyze the codebase** — understand what's built vs what's planned
3. **Write user stories** — "As a [role], I want [feature], so that [value]"
4. **Define acceptance criteria** — testable, specific, derived from the spec
5. **Prioritize** — vertical slices, not horizontal layers
6. **Output** — structured sprint plan document with task list, dependencies, execution order

### Phase 2: Dispatch (Orchestrator — YOU)

The orchestrator (main Claude session or `/sprint-start` command) is the sprint lead.

**The sprint lead NEVER writes code.** It only:
- Reads the plan
- Dispatches specialist agents with detailed prompts
- Tracks completion
- Updates the plan document

**Agent dispatch rules:**
1. Each agent prompt MUST include:
   - **Skill file paths** — full paths to plugin-bundled skills the agent must read
   - **Verbatim spec sections** — exact text from the design document (never summarize)
   - **Explicit acceptance criteria** — checklist derived from the spec
   - **Anti-patterns** — what the agent must NOT do
   - **Build/lint/test commands** — how to verify work
2. Launch independent tasks **in parallel** (multiple Agent calls in one message)
3. Use vertical slices — implement one feature end-to-end before starting the next

### Phase 3: Build (Specialist Agents)

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

### Phase 4: QA Gate (QA Agent)

After implementation agents complete, dispatch the `qa-agent`:

1. **Build & type checks** — `dotnet build`, `npx tsc --noEmit`, `cargo check`, etc.
2. **Linting** — `pnpm lint`, `cargo clippy`, etc.
3. **Test suites** — run all tests
4. **Spec compliance** — re-read acceptance criteria, verify every element exists in code
5. **User-facing label audit** — grep for raw technical strings in UI code
6. **Consumer breakage** — grep for renamed/removed exports
7. **Consistency check** — same components show same data the same way

**QA outputs a structured report** with BLOCKING/WARNING/INFO items and a PASS/FAIL verdict.

### Phase 5: Fix Loop (Retry on Failure)

When QA rejects a task:
1. Re-launch the implementation agent with: (a) original spec, (b) specific failures, (c) "fix ONLY the failures"
2. QA re-validates the specific failures
3. Loop until PASS — no task is marked complete with known violations

### Phase 6: Code Review Gate (pr-review-toolkit)

**`pr-review-toolkit:code-reviewer` is the FINAL gate.** It runs AFTER QA passes.

The code reviewer must:
1. Verify code quality, patterns, and conventions
2. Cross-reference against spec/acceptance criteria
3. Flag UX regressions (wrong labels, missing UI elements, wrong interaction flow)
4. End with a "Patterns & CLAUDE.md suggestions" section

**If review fails**, the sprint lead re-launches the agent with specific failures. Same retry loop as QA.

### Phase 7: Commit & Push

After code review passes:
1. **Logical commit separation** — split by feature, not one giant commit
2. **Commit format**: `<type>(<scope>): <summary>` (see `code-standards` skill)
3. **Update the plan document** — mark completed tasks (`- [x]`)
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
product-manager (plan)
    ↓
sprint-lead dispatches agents (parallel where independent)
    ↓
specialist agents (backend-dev, frontend-dev, etc.)
    ↓
qa-agent (build + lint + test + spec compliance)
    ↓ fail? → re-launch agent → qa-agent (retry loop)
    ↓ pass
pr-review-toolkit:code-reviewer (final gate)
    ↓ fail? → re-launch agent → code-reviewer (retry loop)
    ↓ pass
commit (logical separation) → push
```

---

## Bundled Engineering Skills (15)

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
