# Sprint Workflow

A portable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin system for orchestrating software development through parallel specialist agents, enforced engineering standards, and automated quality gates.

> **One command to plan. Parallel agents to build. Automated gates to ship.**

---

## What This Is

Sprint Workflow is a Claude Code plugin that turns Claude into a full development team:

- **9 specialist agents** — backend, frontend, testing, QA, E2E/Playwright, docs, security, DBA, product management
- **15 engineering skills** — .NET, React, Rust, PostgreSQL, security, MQTT, BPMN, CQRS, and more
- **5 sprint commands** — plan, enrich, start, review, status
- **Automated hooks** — type-check reminders, push gates, plan update enforcement

One install enforces a structured development lifecycle: **Plan → Dispatch → Build → QA → Review → Fix → Ship**.

### Why

Claude Code is powerful but undirected. Without structure, it writes code however it wants — inconsistent patterns, skipped tests, no security review. This plugin system solves that by:

1. **Specialist agents** that read engineering standards before writing a single line
2. **Auto-discovery** that finds project-local skills and global standards automatically
3. **Quality gates** that block shipping until builds pass, specs are met, and code is reviewed
4. **Retry loops** that send failed work back to agents with specific failures — no human babysitting

---

## The Lifecycle

```
  /sprint-plan                /sprint-enrich (optional)
  ┌──────────────────┐        ┌──────────────────────┐
  │  Product Manager │        │  dba · security ·    │
  │  reads specs     │───────▶│  test-writer ·       │
  │  writes plan     │  plan  │  qa-playwright ·     │
  │  assigns agents  │        │  backend · frontend  │
  └────────┬─────────┘        └──────────┬───────────┘
           │                             │
           └──────── user reviews ───────┘
                         │
  /sprint-start          ▼
  ┌──────────────────────────────────────┐
  │  Phase 1: Implementation (parallel)  │
  │  backend-dev · frontend-dev · dba    │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 2: Tests                      │
  │  test-writer · qa-playwright         │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 3: Quality Gates (parallel)   │
  │  qa-agent + pr-review-toolkit        │
  └──────────────────┬───────────────────┘
                     │
                BLOCKING? ──→ Phase 4: Fix Loop
                     │        (original agents
                     │         fix own work)
                     ▼
  ┌──────────────────────────────────────┐
  │  Phase 5: Documentation              │
  │  docs-agent · changelog · ADRs       │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │  Phase 6: Commit & Push              │
  │  logical units via git-flow skill    │
  └──────────────────────────────────────┘
```

---

## Installation

### Option A: Install from GitHub (recommended)

Add the marketplace and install the plugin directly in Claude Code:

```
/plugins marketplace add rynhardt-potgieter/sprint_workflow
/plugins install sprint-workflow
```

One plugin — batteries included. All 8 agents and 15 engineering skills in a single install.

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

#### 5 Sprint Commands

| Command | Purpose |
|---------|---------|
| `/sprint-plan` | Invoke product-manager to create a structured plan with agent assignments and parallel groups |
| `/sprint-enrich` | Specialist agents review the plan — add gotchas, anti-patterns, test cases, security/DBA concerns |
| `/sprint-start` | Execute the approved plan through the 6-phase flow (build → test → QA+review → fix → docs → commit) |
| `/sprint-review` | Run quality gates and code review on completed work (standalone, outside sprint flow) |
| `/sprint-status` | Report current sprint/task status from plan documents |

#### Automated Hooks

| Event | Action |
|-------|--------|
| After Edit/Write | Reminds you to run type-checks for the edited language |
| Before `git push` | Enforces build verification |
| Before Stop | Checks that sprint plan document is up to date |

#### Auto Skill Discovery

The `discover-skills.sh` script automatically finds:
1. **Project-local skills** (`.claude/skills/*/SKILL.md`) — highest priority
2. **Plugin-bundled skills** — fills gaps where no local skill exists

This means agents adapt to any project without manual configuration.

### 15 Engineering Skills

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
| `cli-agent-patterns` | How LLM agents should use CLI tools efficiently — decision trees, anti-patterns |

---

## Key Design Decisions

### Sprint Lead Never Writes Code

The orchestrator dispatches work to specialist agents. It reads plans, writes prompts, and tracks progress. This separation ensures agents get the full context they need and work stays traceable.

### Spec-Driven Development

Every task ties to a spec. Agent prompts include verbatim spec sections, explicit acceptance criteria, and anti-patterns. Agents self-validate against the spec before reporting done.

### Vertical Slices Over Horizontal Layers

Implement one feature end-to-end (backend + frontend + tests) before starting the next. This avoids shallow implementations that miss the user experience.

### Two-Gate Quality System

1. **QA Agent** — build, lint, test, spec compliance (catches implementation bugs)
2. **pr-review-toolkit:code-reviewer** — code quality, patterns, UX regressions (catches design issues)

Both gates have retry loops. Failed work goes back to the implementation agent with specific failures.

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
        │   ├── sprint-review.md
        │   └── sprint-status.md
        ├── hooks/                         # Automated quality hooks
        │   ├── hooks.json
        │   └── scripts/
        ├── scripts/
        │   └── discover-skills.sh         # Auto skill discovery
        └── skills/                        # 15 engineering skills
            ├── api-design/
            ├── bpmn-workflow/
            ├── cli-agent-patterns/
            ├── code-standards/
            ├── computational-geometry/
            ├── cqrs-patterns/
            ├── dotnet-api/
            ├── event-mqtt/
            ├── git-flow/
            ├── postgresql-data/
            ├── react-typescript/
            ├── rust-cli/
            ├── rust-testing/
            ├── security-compliance/
            └── task-board-ops/
```

---

## Roadmap

### Completed

| Agent | Status | What Was Added |
|-------|--------|----------------|
| `qa-playwright` | Done | New agent — Playwright E2E, Page Object Model, visual regression, accessibility (axe-core), CI integration |
| `security-agent` | Done | OWASP Top 10 2025 update, Gitleaks + TruffleHog layered scanning, supply chain security (A03:2025), SBOM |
| `dba-agent` | Done | Expand-contract pattern, zero-downtime migration checklist, `pg_stat_*` index analysis, pgroll/pg_osc tooling |
| `product-manager` | Done | INVEST validation, MoSCoW prioritization, Given/When/Then acceptance criteria, tech debt quadrant, Definition of Done |
| `docs-agent` | Done | MADR ADR format, changelog from conventional commits, OpenAPI derivation, Mermaid architecture diagrams |

### Future

| Enhancement | Notes |
|-------------|-------|
| Playwright MCP integration | Add `.mcp.json` config for `@playwright/mcp` — agents could drive real browsers |
| OWASP ZAP CLI scanning | Automated API security scanning in CI |
| OpenAPI auto-generation | Generate specs from code annotations, not just document existing ones |
| Migration CI gate | Pre-merge migration safety check as a CI step |

---

## License

MIT
