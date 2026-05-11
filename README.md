# Sprint Workflow

```
   ███████╗██████╗ ██████╗ ██╗███╗   ██╗████████╗
   ██╔════╝██╔══██╗██╔══██╗██║████╗  ██║╚══██╔══╝
   ███████╗██████╔╝██████╔╝██║██╔██╗ ██║   ██║
   ╚════██║██╔═══╝ ██╔══██╗██║██║╚██╗██║   ██║
   ███████║██║     ██║  ██║██║██║ ╚████║   ██║
   ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝   ╚═╝
   ██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗███████╗██╗      ██████╗ ██╗    ██╗
   ██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝██╔════╝██║     ██╔═══██╗██║    ██║
   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ █████╗  ██║     ██║   ██║██║ █╗ ██║
   ██║███╗██║██║   ██║██╔══██╗██╔═██╗ ██╔══╝  ██║     ██║   ██║██║███╗██║
   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗██║     ███████╗╚██████╔╝╚███╔███╔╝
    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝
              ┄┄┄  plan · dispatch · build · ship · loop  ┄┄┄
```

A portable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin system for orchestrating software development through parallel specialist agents, enforced engineering standards, and automated quality gates.

> **One command to plan. Parallel agents to build. Automated gates to ship.**

---

## What This Is

Sprint Workflow is a Claude Code plugin that turns Claude into a full development team:

- **9 specialist agents** — backend, frontend, testing, QA, E2E/Playwright, docs, security, DBA, product management
- **23 engineering skills** — .NET, React, Rust, PostgreSQL, security, MQTT, BPMN, CQRS, Linear, Codex, plus diagnose/tdd/zoom-out
- **13 sprint commands** — architect, plan, enrich, start, continue, resume-task, handoff, bug-triage, grill, retro, rollback, review, status
- **Architecture-first workflow** (v3.3) — `/sprint-architect` produces a Linear Project Document containing a C4+ADR system design and feature roadmap, then loads Epics into Linear. Drift detection runs at every sprint stage to flag when implementation diverges
- **Automated hooks** — type-check reminders, push gates, plan update enforcement
- **[Linear](https://linear.app) integration** (opt-in) — single-track sprint management via [Linear MCP](https://linear.app/docs/mcp)
- **[Codex](https://github.com/openai/codex) delegation** (opt-in) — route eligible tasks to OpenAI Codex for ~4x token savings via the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc)

One install enforces a structured development lifecycle: **Plan → Dispatch → Build → QA → Review → Fix → Ship**.

### Why

Claude Code is powerful but undirected. Without structure, it writes code however it wants — inconsistent patterns, skipped tests, no security review. This plugin system solves that by:

1. **Specialist agents** that read engineering standards before writing a single line
2. **Auto-discovery** that finds project-local skills and global standards automatically
3. **Quality gates** that block shipping until builds pass, specs are met, and code is reviewed
4. **Retry loops** that send failed work back to agents with specific failures — no human babysitting

---

## Architecture-First Workflow (v3.3)

For non-trivial initiatives (features that span multiple phases, system rewrites, anything where the design matters), start with `/sprint-architect`. It produces the artifact every downstream sprint command consumes — and it lives in Linear, not in a markdown file that goes stale.

```
  /sprint-architect <context | --from-conversation | --update <project-id>>
  ┌──────────────────────────────────────────────────────────────────┐
  │  1. Confirm context (one-paragraph restatement, user approves)   │
  │  2. Ask ≤5 clarifying questions                                  │
  │     each: 2–4 options + "Choose for me" + "Skip / not sure"      │
  │  3. product-manager (architecture mode) → C4 + ADR + arc42 doc   │
  │  4. WRITE TO LINEAR:                                             │
  │     • Project (initiative container)                             │
  │     • Project Document "Architecture & Roadmap" (long-form)      │
  │     • Epic Issues (one per Phase, linked to the Document)        │
  └──────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
                         User picks an Epic to work on,
                         then runs /sprint-plan <epic-id>
                                     │
                                     ▼
                  /sprint-plan auto-fetches Architecture & Roadmap
                  from the Epic's parent Project. The plan is built
                  with full system context. Drift detection runs.
```

**Why Linear and not markdown**: a markdown architecture file in `docs/` goes stale within weeks because nobody opens it during day-to-day work. Linear's Project Document sits on the Project page where the team already looks, supports Markdown with the same editor as Issues, retains version history, and links bidirectionally with the Issues that implement it. The hard-no-MD rule is deliberate — it forces the artifact to live where it stays useful.

**Document structure** — the industry consensus for SaaS teams: **C4** for hierarchical clarity (Context → Container → Component), **ADRs** for decision history (Status / Context / Decision / Consequences), **arc42** section ordering for completeness without bloat. Sources at the bottom of this README.

**Drift detection** — every downstream command runs an [architectural reflexion-modeling](https://www.sciencedirect.com/science/article/pii/S0920548923000557) check against the Architecture & Roadmap doc:

| Stage | What gets compared | What gets flagged |
|---|---|---|
| `/sprint-plan` | Proposed Tasks vs prescribed model | Erosion blocks the plan; drift is informational |
| `/sprint-enrich` | Plan vs prescribed model, from each specialist's domain angle | Same severity rules |
| `/sprint-start` Phase 3 (QA + code review) | Actual diff vs prescribed model | Erosion = BLOCKING (fix loop); drift = WARNING |
| `/sprint-retro` | Aggregate findings across the sprint | Recommendation to run `/sprint-architect --update` if findings have piled up |

**Drift vs erosion** (the distinction matters):

- **Drift** = code introduces something the doc doesn't mention (new component, new edge). The doc is silent, not violated. Often correct — the doc is incomplete and reality has more nuance. **Severity: WARNING.**
- **Erosion** = code violates an explicit Accepted ADR or cross-cutting constraint. The doc said "do X", the code did "not X". Almost always a bug or a deliberate decision that needs to be re-recorded. **Severity: BLOCKING.**

When erosion is intentional, the fix is `/sprint-architect --update <project-id>` — record the new decision as an ADR, supersede the old one in the Change Log, and the next sprint's drift check passes.

**Hard requirement**: `/sprint-architect` requires Linear MCP. Drift checks in other commands degrade gracefully when Linear is absent — they skip with a one-line note rather than failing.

---

## The Lifecycle

```
  /sprint-grill (optional)         /sprint-plan                  /sprint-enrich (optional)
  ┌──────────────────────┐         ┌──────────────────┐          ┌──────────────────────┐
  │  Interrogate spec    │ locked  │  Product Manager │  plan    │  dba · security ·    │
  │  Lock decisions      ├────────▶│  reads specs     ├─────────▶│  test-writer ·       │
  │  Write open Qs       │ inputs  │  writes plan     │ enriched │  qa-playwright ·     │
  │                      │         │  assigns agents  │          │  backend · frontend  │
  └──────────────────────┘         └────────┬─────────┘          └──────────┬───────────┘
                                            │                                │
                                            └────────── user reviews ────────┘
                                                          │
  /sprint-start                                           ▼
  ┌──────────────────────────────────────┐    ◀─── /sprint-continue (resume any phase)
  │  Phase 1: Implementation (parallel)  │    ◀─── /sprint-resume-task <id>
  │  branches off LOCAL master           │         (single-task re-dispatch)
  │  backend-dev · frontend-dev · dba    │
  │  Codex-eligible → /codex:rescue      │
  │  prior comments injected as context  │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 1.5: Integrate (sequential)   │
  │  rebase + ff-merge each task branch  │
  │  into local master · run build/lint/ │
  │  test on master · revert+bounce on   │
  │  red · status → In Review on green   │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 2: Tests                      │
  │  test-writer · qa-playwright         │
  │  (TDD discipline · regression tests) │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 3: Quality Gates (parallel)   │
  │  reviews compare origin/master..HEAD │
  │  QA (Codex adversarial OR Claude)    │
  │       + pr-review-toolkit (Claude)   │
  └──────────────────┬───────────────────┘
                     │
                BLOCKING? ──┐
                     │      └──▶ Phase 4: Fix Loop
                     │           surgical (1 file) → /codex:rescue
                     │           architectural    → original Claude agent
                     │           fixes branch off local master, ff-merge back
                     ▼
  ┌──────────────────────────────────────┐
  │  Phase 5: Documentation              │
  │  docs-agent · changelog · ADRs       │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 6: Push                       │
  │  single git push origin master       │
  │  (all logical commits already on     │
  │   local master from earlier phases)  │
  │  finalize Linear/MD tracking → Done  │
  └──────────────────┬───────────────────┘
                     │
                     ▼
            ┌────────────────┐    ◀─── /sprint-retro (reflect)
            │  SPRINT DONE   │    ◀─── /sprint-bug-triage (file post-ship bugs)
            └────────────────┘    ◀─── /sprint-rollback  (safety-gated revert)

  Cross-cutting (any time):
    /sprint-handoff   write docs/SPRINT_HANDOFF.md before stopping
    /sprint-status    show current phase from Linear / plan doc
```

### Command Map

```
   /sprint-architect    ── creates Linear Project + Architecture & Roadmap doc + Epics
        │                  (run once per initiative; --update later)
        ▼
                            ┌──── plan + dispatch ─────┐
   /sprint-grill ──▶ /sprint-plan ──▶ /sprint-enrich ──▶ /sprint-start
   (optional)        (auto-loads      (specialists also     (Phase 3 QA + review
                      Architecture     check drift from     run drift check)
                      doc when given   their domain angle)
                      an Epic ID)
                                                              │
        ┌─────────────────────────────────────────────────────┤
        │                                                     │
        ▼                                                     ▼
   /sprint-handoff   ◀── interrupt? ──▶   /sprint-continue · /sprint-resume-task
        │                                                     │
        ▼                                                     ▼
   /sprint-status   ◀──── observe ────▶   /sprint-bug-triage  (files Linear/MD bugs)
                                                              │
                                          ┌───────────────────┘
                                          ▼
                                   /sprint-retro · /sprint-rollback · /sprint-review
                                   (retro emits drift summary;
                                    if findings pile up, suggests
                                    /sprint-architect --update)
```

---

## Installation

### Option A: Install from GitHub (recommended)

Add the marketplace and install the plugin directly in Claude Code:

```
/plugins marketplace add rynhardt-potgieter/sprint_workflow
/plugins install sprint-workflow
```

One plugin — batteries included. All 9 agents and 23 engineering skills in a single install.

### Option B: Install from local clone

```bash
git clone https://github.com/rynhardt-potgieter/sprint_workflow.git
```

Then in Claude Code:

```
/plugins marketplace add ./sprint_workflow
/plugins install sprint-workflow
```

### 3. Copy CLAUDE.md (optional but recommended)

Copy the included `CLAUDE.md` to your workspace root and customize it with project-specific conventions:

```bash
cp sprint_workflow/CLAUDE.md ~/repos/CLAUDE.md
```

### 4. Verify

Open Claude Code in your workspace and run:

```
/sprint-status
```

If the plugin is loaded, you'll see the skill discovery output and status report.

### Optional: Linear MCP Setup

[Linear](https://linear.app) integration replaces markdown plan files with Linear issues as the single source of truth. When configured, `/sprint-plan` creates issues directly in Linear, `/sprint-start` tracks status via Linear, and `/sprint-status` queries Linear instead of reading markdown files.

**How it works:** The plugin auto-detects Linear MCP tools at the start of every command. No configuration flag needed — if Linear MCP is available, it's used. If not, markdown tracking works exactly as before.

1. **Add Linear MCP to Claude Code** via [Linear's MCP documentation](https://linear.app/docs/mcp):
   - In Claude Code settings, add the Linear MCP server
   - Authenticate with your Linear account

2. **Verify Linear MCP is active:**
   ```
   /sprint-status
   ```
   The output should show `Tracking: Linear (project: ...)` instead of `Tracking: Markdown`.

3. **How the plugin uses Linear:**

   | Sprint Concept | Linear Mapping |
   |---------------|---------------|
   | Sprint | [Milestone](https://linear.app/docs/milestones) (date-based grouping) |
   | Story | Issue with `Epic` label (top-level feature) |
   | Task | Sub-issue with `Task` label (agent work item) |

   The plugin creates and manages labels automatically:
   - **Hierarchy:** Epic (green), Task (orange)
   - **Type:** Feature (purple), Bug (red), Improvement (blue), QA (yellow), tech-debt (orange), Decision (amber), Deferred (gray)

   Status lifecycle: `Backlog → Todo → In Progress → In Review → Done`

4. **Fallback:** If Linear MCP goes down mid-sprint, the plugin prompts you to approve a markdown fallback for the rest of the session. No data is lost.

### Optional: Codex CLI Setup

[OpenAI Codex](https://github.com/openai/codex) integration conserves Claude tokens by routing eligible tasks to Codex. The plugin uses Codex for two purposes:
- **Task execution** — well-scoped implementation tasks (CRUD, scaffolds, boilerplate) run on Codex at ~4x token efficiency
- **QA adversarial review** — cross-model code quality review catches bugs that Claude-reviewing-Claude misses

**How it works:** The plugin auto-detects the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc). If installed, eligible tasks route to Codex. If not, everything runs on Claude as before.

1. **Install the Codex CLI** — follow the [Codex README](https://github.com/openai/codex):
   ```bash
   npm install -g @openai/codex
   ```

2. **Install the Codex plugin for Claude Code:**
   ```
   /plugins marketplace add openai/codex-plugin-cc
   /plugins install codex@openai-codex
   /codex:setup
   ```

   > Do NOT run `/codex:setup --enable-review-gate` — this reviews every Claude turn and burns both rate limits fast.

3. **Configure Codex defaults** (optional):
   ```bash
   cat > ~/.codex/config.toml <<EOF
   model = "gpt-5.4-mini"
   model_reasoning_effort = "high"
   project_doc_fallback_filenames = ["CLAUDE.md"]
   EOF
   ```

4. **How the plugin routes work:**

   During `/sprint-plan`, the product-manager flags each task as `codex-eligible: true/false` based on:
   - **Codex-eligible:** Well-scoped CRUD, migration scaffolds, boilerplate, test generation, single-concern features
   - **NOT eligible:** Cross-cutting architecture, design exploration, security-critical code, idiomatic .NET

   During `/sprint-start`:
   - **Phase 1:** Codex-eligible tasks → `/codex:rescue`. Others → Claude agents.
   - **Phase 3 QA:** Codex runs adversarial review (`/codex:adversarial-review`). PR review stays Claude.
   - **Phase 4 fixes:** Surgical fixes (single file, lint, null check) → Codex. Architectural → Claude.

5. **Verify:**
   ```
   /sprint-status
   ```
   Should show `Codex delegation: Available`.

---

## The Plugin

### 9 Specialist Agents

| Agent | Model | Role |
|-------|-------|------|
| `backend-dev` | opus | Server-side code — .NET, Rust, Go, Python, Node.js |
| `frontend-dev` | opus | Client-side UI — React, Vue, Svelte, Angular |
| `test-writer` | sonnet | Unit, integration, and snapshot tests |
| `qa-agent` | sonnet | Build verification, spec compliance, quality gates |
| `qa-playwright` | sonnet | E2E browser testing — Playwright, visual regression, accessibility |
| `docs-agent` | sonnet | README, changelogs, ADRs (MADR), API docs, architecture diagrams |
| `product-manager` | opus | Sprint planning, INVEST stories, MoSCoW prioritization, tech debt |
| `dba-agent` | opus | Schema review, zero-downtime migrations, index audit, PII compliance |
| `security-agent` | opus | OWASP 2025, Gitleaks/TruffleHog, supply chain, dependency audit |

Every agent follows a **3-step onboarding**:
1. Read bundled engineering skill files (via `${CLAUDE_PLUGIN_ROOT}/skills/`)
2. Read project CLAUDE.md
3. Execute the task

#### 13 Sprint Commands

##### Architecture-First (added v3.3)

| Command | Purpose |
|---------|---------|
| `/sprint-architect` | Produce a Linear Project + `Architecture & Roadmap` document (C4 + ADR + arc42) + Epic Issues from any context (session conversation, PRD, attached docs). Asks ≤5 clarifying questions, each with a "Choose for me" option. Use `--update <project-id>` to refresh the doc with a Change Log entry. **Hard requirement: Linear MCP** — refuses to write architecture artifacts to local markdown. |

##### Core Lifecycle

| Command | Purpose |
|---------|---------|
| `/sprint-plan` | `[--grill] <epic-id>` (Linear) or `[--grill] <spec-path>` (MD). Invokes product-manager to break an Epic into Tasks with agent assignments and parallel groups. Auto-loads the Architecture & Roadmap doc from the Epic's parent Project and runs a drift self-check. |
| `/sprint-enrich` | `[<epic-id>]` or `[<plan-path>]` — defaults to in-progress epic. Specialist agents review the plan and add gotchas, anti-patterns, test cases, security/DBA concerns, plus domain-specific drift against the Architecture & Roadmap. |
| `/sprint-start` | `<epic-id>` (Linear) or `<plan-path>` (MD) — required. Executes the approved plan through the 6-phase flow (build → test → QA + review → fix → docs → commit). Phase 3 runs the architecture drift check; erosion is BLOCKING, drift is WARNING. |
| `/sprint-review` | `[<epic-id>]` — defaults to most-recently-touched in-progress epic. Runs quality gates and code review on completed work (standalone, outside sprint flow). |
| `/sprint-status` | `[<epic-id>]` or `[<milestone-id>]` — defaults to most recently active sprint. Reports current task status from Linear or the plan document. |

##### Recovery & Resumption

| Command | Purpose |
|---------|---------|
| `/sprint-continue` | `[<epic-id>]` — defaults to the most-recently-touched in-progress Epic. Auto-detects the current phase and resumes without re-doing completed work. Idempotent. |
| `/sprint-resume-task` | `<task-id>` — re-runs a single failed or stuck task with the same agent + spec section, without re-entering the full sprint flow. |
| `/sprint-handoff` | `[<output-path>]` — defaults to `docs/SPRINT_HANDOFF.md`. Generates a snapshot of current phase, in-flight tasks, blockers, and next action so a fresh session can resume cleanly. |

##### Quality & Reflection

| Command | Purpose |
|---------|---------|
| `/sprint-bug-triage` | `[<target-paths>]` with optional `--branch` or `--epic <epic-id>`. Multi-agent bug review (code-reviewer + security-agent + qa-agent + Codex adversarial). Dedups, presents to user, files Linear sub-issues under an Epic OR appends to `docs/BUG_BACKLOG.md`. |
| `/sprint-grill` | `<topic>` or `<spec-path>` — the product-manager agent grills the user against the project's domain model until sprint inputs are unambiguous. Adapts a pattern from [mattpocock/skills](https://github.com/mattpocock/skills). |
| `/sprint-retro` | `[<milestone-id>]` or `[<epic-id>]` — defaults to most recently completed sprint. Data-driven retro: analyses commits, QA cycles, fix-loop counts, codex-vs-claude split, drift findings. Emits a retro doc + Architecture Drift Summary; recommends `/sprint-architect --update` when needed. |
| `/sprint-rollback` | `<milestone-id>` or `<epic-id>` — safety-gated revert of a sprint's commits + Linear/MD status reset. Never force-pushes, always uses revert branches. |

#### Automated Hooks

| Event | Action | Cost |
|-------|--------|------|
| After Edit/Write | Reminds you to run type-checks for the edited language (matched by extension) | <50ms bash, silent for unmatched files |
| After Edit/Write (sprint reminder) | If a sprint is active, injects a reconcile-tracking reminder into the agent's context (rate-limited) | <50ms bash, silent in non-sprint sessions |
| Before `git push` | Reminds you to verify builds before pushing | <50ms bash, silent for non-push Bash calls |
| Before Stop | If a sprint is active, emits a `systemMessage` to the user about reconciling tracking | <50ms bash, silent in non-sprint sessions |

##### Sprint tracking reminders: how they work

Both the PostToolUse sprint-reminder hook and the Stop hook are **gated on a sentinel file** (`.claude/.sprint-active`) so they cannot fire in ordinary sessions:

- **Activated** by `/sprint-start` after user approval, before Phase 1 dispatch. Sentinel records the active tracking source (`linear` or `md`).
- **Re-asserted** by `/sprint-continue` and `/sprint-resume-task` when resuming an interrupted sprint.
- **Cleared** by `/sprint-start` Phase 6 (after final commits and tracking finalized) and by `/sprint-rollback`.
- **Left in place** by `/sprint-handoff` — the sprint is paused, not done; the next session's hooks should still nag.

The split between the two hooks comes from the Claude Code hook schema:

- **Stop hooks** support `systemMessage` (visible to the user only) and `decision: "block"` (forces another agent turn — the historical loop ingredient). They do **not** support `hookSpecificOutput.additionalContext`. So a Stop hook can either nag the user or block the agent — there's no in-between option that injects context the agent itself reads.
- **PostToolUse hooks** *do* support `hookSpecificOutput.additionalContext`. The reminder is appended to the agent's conversation context as standing guidance, and the agent reads it on its next reasoning step.

To give the agent itself a visible reminder, sprint-workflow uses a **PostToolUse hook on Edit and Write** (`post-sprint-reminder.sh`) that:

1. Fires only when the sprint sentinel exists.
2. Is rate-limited by `SPRINT_STOP_HOOK_RATE_LIMIT_S` (default 600s = 10 min) via a shared `.sprint-active.last-fire` file. Same env var also governs the Stop hook, so a single project setting controls overall nag frequency.
3. New sessions always fire on first eligible edit, regardless of stale rate-limit state from prior sessions.
4. Outputs `additionalContext` per the PostToolUse schema — message lands in the agent's context, not just the UI.

The Stop hook (`stop-sprint-tracking.sh`) is kept as a `systemMessage` nudge to *you*, the user — useful when you want to verify the agent did the reconciliation before ending a turn. Since `systemMessage` is UI-only and never injected into agent context, it cannot loop and cannot ack-storm.

Override the rate limit per-project in `.claude/settings.local.json`:

```json
{ "env": { "SPRINT_STOP_HOOK_RATE_LIMIT_S": "1800" } }
```

`/sprint-start`, `/sprint-continue`, and `/sprint-resume-task` write the default value (`600`) into `settings.local.json` if it isn't already set, so users never have to configure it manually.

When the sentinel is absent (the common case for ad-hoc work, exploration, debugging, or any project where you use this plugin only for the skills/agents), both hooks are silent and exit in milliseconds.

If you find a stale sentinel from a sprint that was never finalized:
```bash
rm -f .claude/.sprint-active .claude/.sprint-active.last-nag .claude/.sprint-active.last-fire
```

#### Auto Skill Discovery

The `discover-skills.sh` script automatically finds:
1. **Project-local skills** (`.claude/skills/*/SKILL.md`) — highest priority
2. **Plugin-bundled skills** — fills gaps where no local skill exists

This means agents adapt to any project without manual configuration.

### 23 Engineering Skills

Bundled skill files that define how code should be written. Agents read these automatically via `${CLAUDE_PLUGIN_ROOT}/skills/`.

#### Full-Stack Standards

| Skill | Covers |
|-------|--------|
| `code-standards` | C#/TS naming, formatting, logging, git conventions, code review checklist |
| `dotnet-api` | .NET 8 Clean Architecture, EF Core, DI, async, controllers, JSON serialization |
| `react-typescript` | React 19, TypeScript 5.9, Vite 7, Zustand, React Query, Tailwind 4 |
| `postgresql-data` | Schema design, migrations, indexing, JSONB, Dapper, connection pooling |
| `api-design` | REST endpoints, HTTP methods, response wrappers, pagination, error handling (RFC 7807) |

#### Security & Compliance

| Skill | Covers |
|-------|--------|
| `security-compliance` | Auth0 JWT, OWASP Top 10, PCI DSS 4.0, PII/data protection, secrets management |

#### Architecture Patterns

| Skill | Covers |
|-------|--------|
| `cqrs-patterns` | MediatR commands/queries, domain events, pipeline behaviors |
| `event-mqtt` | MQTT (MQTTnet), SSE, pub/sub, topic design, outbox pattern, idempotency |
| `bpmn-workflow` | BPMN 2.0, gateways, human tasks, timer events, state machines |

#### Rust Ecosystem

| Skill | Covers |
|-------|--------|
| `rust-cli` | Clap integration, error handling (anyhow/thiserror), JSON output, CLI design |
| `rust-testing` | insta snapshots, tempdir isolation, fixture management, integration tests |

#### Specialized Domains

| Skill | Covers |
|-------|--------|
| `computational-geometry` | Bezier math, boolean ops (Clipper2), compositing, curve fitting, AABB |
| `git-flow` | Branch naming, commit format, PR templates, release process |
| `tfs-flow` | TFVC workspaces, checkins, shelvesets, branching, work item association |
| `cli-agent-patterns` | How LLM agents should use CLI tools efficiently — decision trees, anti-patterns |

#### Engineering Discipline (added v3.1)

| Skill | Covers |
|-------|--------|
| `diagnose` | Disciplined bug-investigation loop — reproduce → minimize → hypothesize → instrument → fix → verify. Required reading for every reviewer in `/sprint-bug-triage` and every fix in Phase 4 |
| `tdd` | Red-green-refactor loop, when to TDD vs not, mandatory regression tests for bug fixes |
| `zoom-out` | Recovery procedure when an agent is stuck — when grep/scope returns confusing results, when 3+ navigation attempts have failed |
| `worktree-handoff` | Subagent + orchestrator contract for getting code OUT of an isolated worktree (Claude `isolation: worktree` or Codex Handoff) without losing work or copying files by hand. Defines the mandatory exit-time HANDOFF block and the orchestrator's fetch/merge/cleanup sequence (added v3.2.0) |

#### Integration Skills

| Skill | Covers |
|-------|--------|
| `linear-sprint-planning` | [Linear](https://linear.app) issue taxonomy, Milestone-based sprints, label definitions, status lifecycle, MCP query/creation patterns. **v3.3**: §12 Project Documents (Architecture & Roadmap structure, save/get/update patterns, Epic linking convention) |
| `codex-delegation` | [Codex](https://github.com/openai/codex) eligibility criteria, adversarial review focus strings, fix routing, context passing. **v3.3**: §11 Architecture Drift Check — orchestrator pre-fetches the doc and passes the prescribed-model summary inline (Codex doesn't have Linear MCP) |

#### Architecture Governance (added v3.3)

| Skill | Covers |
|-------|--------|
| `architecture-drift-check` | Reflexion-modeling check that compares planned or implemented work against the Linear Architecture & Roadmap document. Distinguishes **drift** (new, undocumented — WARNING) from **erosion** (violates an Accepted ADR or quality attribute — BLOCKING). Defines the standard report format used by `/sprint-plan`, `/sprint-enrich`, Phase 3 QA + code review, and `/sprint-retro`. Skips gracefully when Linear is absent or no doc exists. |

---

## Key Design Decisions

### Sprint Lead Never Writes Code

The orchestrator dispatches work to specialist agents. It reads plans, writes prompts, and tracks progress. This separation ensures agents get the full context they need and work stays traceable.

### Spec-Driven Development

Every task ties to a spec. Agent prompts include verbatim spec sections, explicit acceptance criteria, and anti-patterns. Agents self-validate against the spec before reporting done.

### Vertical Slices Over Horizontal Layers

Implement one feature end-to-end (backend + frontend + tests) before starting the next. This avoids shallow implementations that miss the user experience.

### Two-Gate Quality System

1. **QA** — build, lint, test, spec compliance, adversarial code review (catches implementation bugs). Runs on [Codex](https://github.com/openai/codex) when available for cross-model review; falls back to Claude `qa-agent` otherwise.
2. **pr-review-toolkit:code-reviewer** — code quality, patterns, UX regressions (catches design issues). Always Claude.

Both gates run **after** task branches have been integrated to local `master` (Phase 1.5), and they review against `origin/master..HEAD` — the same diff that will eventually land remotely. Surgical fixes route to Codex (foreground only), architectural fixes go back to the original Claude agent. Either way, fixes branch off local `master`, fast-forward back, and re-review on local `master` until clean. The remote `origin/master` is only updated once at Phase 6, after every gate has passed.

### Integrate-Then-Review (Phase 1.5)

Implementation agents work on per-task branches off local `master`. As each agent finishes, the orchestrator rebases its branch onto current local `master`, fast-forwards it in, and runs build/lint/test on `master`. Failures revert the merge and bounce the task back to Phase 1 with the failure as context — other tasks proceed independently. By the time reviews run, `master` carries the integrated sprint state and reviewers see the same shape that will land on the remote. Codex's natural `origin/HEAD`-base orientation aligns with `origin/master..HEAD`, so its adversarial review reads the right diff without override flags.

### Sub-Agents See Prior User Context

Before dispatching any task, the orchestrator pulls comments from the Linear task and its parent Story (or the markdown plan's Carryover/Notes sections), filters for `[NOTE]`, `[USER]`, `[DEFERRED]`, `[CARRYOVER]`, `[FOLLOW-UP]` tags or non-bot authors, and injects them into the agent's prompt under `## Prior Context`. Combined with the Stop hook's reminder to *write* `[DEFERRED]` comments when items get pushed out, this closes the loop: nothing the user typed into Linear, and nothing earlier tasks deferred, gets dropped on the floor when the next sub-agent dispatches.

### Project-Local Skills Override Globals

If a project defines its own `.claude/skills/rust-cli/SKILL.md`, it takes priority over the plugin-bundled version. This lets projects customize patterns without forking the plugin.

---

## Adding Your Own Skills

Create a skill file at `.claude/skills/<skill-name>/SKILL.md` in your project:

```yaml
---
name: my-skill
description: When and why to use this skill
version: 1.0.0
---

## Patterns

Your patterns, conventions, and code examples here.
```

The `discover-skills.sh` script will find it automatically, and agents will read it when dispatched.

---

## Extending the Agent Team

Add a new agent by creating a `.md` file in `sprint-workflow/agents/`:

```yaml
---
name: my-agent
description: What this agent does and when to use it
tools: Glob, Grep, Read, Write, Edit, Bash
model: opus
color: green
---

Your agent prompt here. Follow the 3-step pattern:
1. Read skill files
2. Read project conventions
3. Do the work
```

Update the `/sprint-start` command to include the new agent in its dispatch options.

---

## Repo Structure

```
sprint_workflow/
├── .claude-plugin/
│   └── marketplace.json                   # Plugin marketplace (install source)
├── CLAUDE.md                              # Universal workflow conventions
├── README.md
├── docs/
│   └── AGENT_ENRICHMENT_PLAN.md           # Research plan for new agents
└── plugins/
    └── sprint-workflow/                   # Single plugin — batteries included
        ├── .claude-plugin/plugin.json
        ├── agents/                        # 9 specialist agents
        │   ├── backend-dev.md
        │   ├── frontend-dev.md
        │   ├── test-writer.md
        │   ├── qa-agent.md
        │   ├── qa-playwright.md
        │   ├── docs-agent.md
        │   ├── product-manager.md
        │   ├── dba-agent.md
        │   └── security-agent.md
        ├── commands/                      # Sprint lifecycle commands
        │   ├── sprint-plan.md
        │   ├── sprint-enrich.md
        │   ├── sprint-start.md
        │   ├── sprint-continue.md         # NEW v3.1 — resume interrupted sprint
        │   ├── sprint-resume-task.md      # NEW v3.1 — re-run a single task
        │   ├── sprint-handoff.md          # NEW v3.1 — handoff snapshot for next session
        │   ├── sprint-bug-triage.md       # NEW v3.1 — multi-agent bug review
        │   ├── sprint-grill.md            # NEW v3.1 — pre-plan interrogation
        │   ├── sprint-retro.md            # NEW v3.1 — data-driven retro
        │   ├── sprint-rollback.md         # NEW v3.1 — safety-gated sprint revert
        │   ├── sprint-review.md
        │   └── sprint-status.md
        ├── hooks/                         # Automated quality hooks
        │   ├── hooks.json
        │   └── scripts/
        ├── scripts/
        │   └── discover-skills.sh         # Auto skill discovery
        └── skills/                        # 23 engineering skills
            ├── api-design/
            ├── bpmn-workflow/
            ├── cli-agent-patterns/
            ├── code-standards/
            ├── codex-delegation/
            ├── computational-geometry/
            ├── cqrs-patterns/
            ├── diagnose/                  # NEW v3.1 — bug-investigation loop
            ├── dotnet-api/
            ├── event-mqtt/
            ├── git-flow/
            ├── linear-sprint-planning/
            ├── postgresql-data/
            ├── react-typescript/
            ├── rust-cli/
            ├── rust-testing/
            ├── security-compliance/
            ├── task-board-ops/
            ├── tdd/                       # NEW v3.1 — red-green-refactor
            ├── tfs-flow/
            └── zoom-out/                  # NEW v3.1 — navigation recovery
```

---

## Roadmap

### Completed

| Feature | Version | What Was Added |
|---------|---------|----------------|
| `qa-playwright` | 2.0 | New agent — Playwright E2E, Page Object Model, visual regression, accessibility (axe-core), CI integration |
| `security-agent` | 2.0 | OWASP Top 10 2025 update, Gitleaks + TruffleHog layered scanning, supply chain security (A03:2025), SBOM |
| `dba-agent` | 2.0 | Expand-contract pattern, zero-downtime migration checklist, `pg_stat_*` index analysis, pgroll/pg_osc tooling |
| `product-manager` | 2.0 | INVEST validation, MoSCoW prioritization, Given/When/Then acceptance criteria, tech debt quadrant, Definition of Done |
| `docs-agent` | 2.0 | MADR ADR format, changelog from conventional commits, OpenAPI derivation, Mermaid architecture diagrams |
| Linear MCP | 3.0 | Opt-in single-track sprint tracking via [Linear](https://linear.app) — Milestones, Epic/Task labels, status lifecycle, auto-detection |
| Codex delegation | 3.0 | Opt-in task routing to [OpenAI Codex](https://github.com/openai/codex) — codex-eligible flagging, adversarial QA review, surgical fix routing |
| Recovery commands | 3.1 | `/sprint-continue`, `/sprint-resume-task`, `/sprint-handoff` — resume interrupted sprints without re-doing work |
| Bug triage | 3.1 | `/sprint-bug-triage` — parallel multi-agent review → dedup → user-approved Linear/MD bug tickets |
| Grill, retro, rollback | 3.1 | `/sprint-grill` (pre-plan interrogation), `/sprint-retro` (data-driven retro), `/sprint-rollback` (safety-gated revert) |
| Engineering discipline skills | 3.1 | `diagnose`, `tdd`, `zoom-out` — adapted in part from [mattpocock/skills](https://github.com/mattpocock/skills) |
| Worktree handoff | 3.2 | `worktree-handoff` skill + agent contract for safe subagent/Codex worktree integration |
| Sentinel-gated Stop hook | 3.2.1 | Replaced prompt-type Stop hook with sentinel-gated bash hook — no false positives in non-sprint sessions, cannot loop |
| Architecture-first workflow | 3.3 | `/sprint-architect` (Linear-backed C4+ADR architecture & roadmap), `architecture-drift-check` skill, drift detection wired into `/sprint-plan`, `/sprint-enrich`, Phase 3 QA, code review, and `/sprint-retro` |
| Consistent argument convention | 3.4 | All 13 commands now use a unified `<epic-id>` / `<milestone-id>` / `<task-id>` / `<project-id>` argument scheme. `/sprint-start` requires an explicit `<epic-id>`; `/sprint-continue`, `/sprint-review`, `/sprint-status` accept it optionally and auto-detect the most-recently-touched in-progress Epic. Lets users run multiple sprints in parallel by scoping every command. |
| Phase 1.5 + integrate-then-review | 3.5 | New Phase 1.5 (Integrate) between implementation and tests: each task branch rebases + ff-merges to local `master`, runs build/lint/test, reverts and bounces on failure. Reviews compare against `origin/master..HEAD` on local master, not against task branches. Phase 6 becomes a single `git push origin master` after all gates pass. Implementation branches are created via manual `git switch -c` from local master (NOT `Agent(isolation:"worktree")`) to avoid the [origin/HEAD-base bug](https://github.com/anthropics/claude-code/issues/41680). |
| PostToolUse sprint-reminder hook | 3.5 | New hook (`post-sprint-reminder.sh`) on Edit/Write that injects sprint tracking reminders into the agent's context via `hookSpecificOutput.additionalContext` — the Stop hook schema does not support that field, so the agent-visible reminder lives on PostToolUse instead. Sentinel-gated, rate-limited via `SPRINT_STOP_HOOK_RATE_LIMIT_S` (default 600s, configurable in `.claude/settings.local.json`, first edit of new session always fires, shared `.sprint-active.last-fire` file with the Stop hook so one setting controls overall nag frequency). Auto-configured by `/sprint-start`, `/sprint-continue`, `/sprint-resume-task`. Stop hook stays as a `systemMessage` nudge to the user. |
| Linear comments ingestion | 3.5 | Before dispatching any task, the orchestrator pulls comments from the Linear task and parent Story (or markdown plan Carryover/Notes), filters for `[NOTE]`/`[USER]`/`[DEFERRED]`/`[CARRYOVER]`/`[FOLLOW-UP]` tags or non-bot authors, and injects them under `## Prior Context` in the agent prompt. Closes the loop with the Stop hook's reminder to *write* `[DEFERRED]` comments — items pushed out of one turn are picked up by the next dispatch. |
| Codex foreground-only | 3.5 | All Codex invocations (`/codex:rescue`, `/codex:adversarial-review`, `codex exec`) run foreground; never `run_in_background=true`. For parallelism, route to multiple Claude `Agent` calls in one message instead. Documented in `codex-delegation` SKILL.md §9b. |

### Future

| Enhancement | Notes |
|-------------|-------|
| Playwright MCP integration | Add `.mcp.json` config for `@playwright/mcp` — agents could drive real browsers |
| OWASP ZAP CLI scanning | Automated API security scanning in CI |
| OpenAPI auto-generation | Generate specs from code annotations, not just document existing ones |
| Migration CI gate | Pre-merge migration safety check as a CI step |

---

## Sources & Industry Patterns

The architecture-first workflow and drift detection in v3.3 are grounded in established practitioner and academic sources:

**Architecture documentation**
- C4 model — [c4model.com](https://c4model.com/) (Simon Brown)
- ADRs (Architecture Decision Records) — [adr.github.io](https://adr.github.io/)
- arc42 template — [arc42.org](https://arc42.org/)
- The C4 + ADR + arc42 hybrid for SaaS teams — [Working Software guide](https://www.workingsoftware.dev/software-architecture-documentation-the-ultimate-guide/), [arc42 + C4 example](https://github.com/bitsmuggler/arc42-c4-software-architecture-documentation-example)

**Architectural drift & erosion**
- Reflexion modeling (Murphy et al., 1995; widely surveyed since)
- "Drift and Erosion in Software Architecture" — [Li et al., 2020](https://www.researchgate.net/publication/339385701_Drift_and_Erosion_in_Software_Architecture_Summary_and_Prevention_Strategies)
- "Detecting deviations using architecture view-based drift analysis" — [ScienceDirect, 2023](https://www.sciencedirect.com/science/article/pii/S0920548923000557)
- "Assessing architectural drift in commercial software" — [Rosik 2011](https://onlinelibrary.wiley.com/doi/full/10.1002/spe.999)

**Epic decomposition**
- [Atlassian — Epics, Stories, Initiatives](https://www.atlassian.com/agile/project-management/epics-stories-themes)
- [Aha — Agile Epics Best Practices](https://www.aha.io/roadmapping/guide/agile/agile-epics-explained)

**Linear**
- [Linear Project Documents](https://linear.app/docs/project-documents)
- [Linear API](https://linear.app/developers)

---

## License

MIT
