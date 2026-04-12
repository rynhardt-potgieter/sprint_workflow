# Agent Enrichment Plan

Research plan for building and enriching the new specialist agents. Each section defines what to search for, why, and how to integrate findings into the agent prompts and skill files.

---

## 1. Documentation Agent (`docs-agent`)

### Current State
Skeleton agent with README, CHANGELOG (Keep a Changelog), ADR, and API doc generation.

### Research Queries

| # | Search Query | Why |
|---|-------------|-----|
| 1 | `"architecture decision record" template format best practices 2025` | ADR format varies — find the most adopted template (MADR? Nygard? Lightweight?) |
| 2 | `"keep a changelog" automation conventional commits tool` | Tools that auto-generate changelogs from git history |
| 3 | `openapi spec generation from code annotations dotnet react` | Auto-generating OpenAPI/Swagger from controller attributes and TypeScript API clients |
| 4 | `"docs as code" best practices developer documentation` | Patterns for treating docs like code — linting, CI, freshness checks |
| 5 | `readme best practices open source template sections` | What sections a great README should have (badges, quickstart, API reference, etc.) |
| 6 | `mermaid diagrams architecture documentation generation` | Using Mermaid for auto-generated architecture diagrams in docs |
| 7 | `api documentation best practices developer experience DX` | What makes API docs actually useful — examples, error codes, rate limits |

### Integration
- Update `docs-agent.md` with specific templates and format rules
- Consider creating an `engineering-standards/skills/documentation/SKILL.md` if patterns are substantial enough

---

## 2. QA Agent with Playwright / Chrome CLI

### Current State
QA agent handles builds, linting, type-checks, and spec compliance. No E2E or browser testing.

### Research Queries

| # | Search Query | Why |
|---|-------------|-----|
| 1 | `playwright MCP server claude code integration 2025` | Check if an official or community Playwright MCP server exists for Claude Code |
| 2 | `playwright test automation best practices page object model` | Page Object Model, test fixtures, selectors strategy |
| 3 | `playwright cli headless testing command line` | Running Playwright from CLI without a GUI — headless mode, CI patterns |
| 4 | `chrome devtools protocol CDP automation testing headless` | Using CDP directly for lightweight browser testing without full Playwright |
| 5 | `"chrome for testing" CLI screenshot accessibility audit` | Chrome's built-in testing mode for screenshots and Lighthouse audits |
| 6 | `playwright accessibility testing axe-core integration` | Accessibility auditing with axe-core via Playwright |
| 7 | `playwright visual regression testing screenshot comparison` | Visual regression testing — snapshot comparison, threshold tuning |
| 8 | `playwright network mocking api testing intercept` | Intercepting API calls for isolated frontend testing |
| 9 | `puppeteer vs playwright 2025 comparison headless` | Current state of the art — which tool is better for agent-driven testing |

### Integration
- Create new agent `qa-playwright.md` or extend `qa-agent.md` with E2E capabilities
- Consider creating `engineering-standards/skills/e2e-testing/SKILL.md`
- Add Playwright config patterns, selector strategies, and CI setup

---

## 3. Product Manager Agent (`product-manager`)

### Current State
Skeleton agent with codebase analysis, user story writing, sprint plan output.

### Research Queries

| # | Search Query | Why |
|---|-------------|-----|
| 1 | `user story writing best practices acceptance criteria INVEST` | INVEST criteria (Independent, Negotiable, Valuable, Estimable, Small, Testable) |
| 2 | `sprint planning techniques prioritization MoSCoW WSJF` | Prioritization frameworks — MoSCoW, Weighted Shortest Job First |
| 3 | `product requirements document PRD template 2025 AI` | Modern PRD templates optimized for AI-assisted development |
| 4 | `codebase analysis automated gap detection existing vs planned` | Techniques for detecting what's built vs what's missing from a spec |
| 5 | `vertical slice architecture feature slicing techniques` | How to slice features vertically (end-to-end) vs horizontally |
| 6 | `dependency mapping task ordering topological sort sprint` | Algorithms for ordering tasks with dependencies |
| 7 | `"definition of done" checklist software development` | Standard DoD checklists that the PM agent should enforce |
| 8 | `technical debt identification prioritization quadrant` | How to identify and categorize tech debt for sprint planning |

### Integration
- Update `product-manager.md` with structured frameworks (INVEST, MoSCoW, vertical slicing)
- Add PRD template to `task-board-ops/references/` or a new skill file
- Define output format for sprint plan documents

---

## 4. Database Administrator Agent (`dba-agent`)

### Current State
Skeleton agent with schema review, migration safety, index audit, PII compliance.

### Research Queries

| # | Search Query | Why |
|---|-------------|-----|
| 1 | `postgresql migration safety checklist production zero downtime` | Zero-downtime migration patterns — expand/contract, shadow columns |
| 2 | `postgresql index advisor missing index detection pg_stat` | Using `pg_stat_user_tables` and `pg_stat_user_indexes` for index recommendations |
| 3 | `database schema review checklist best practices` | Comprehensive schema review checklist beyond what we have |
| 4 | `postgresql performance anti-patterns N+1 missing indexes bloat` | Common PostgreSQL performance issues and how to detect them |
| 5 | `GDPR POPIA data compliance database design encryption at rest` | Data protection patterns — column-level encryption, pseudonymization, right to erasure |
| 6 | `ef core migration best practices production safety backward compatible` | EF Core-specific migration patterns — idempotent, backward-compatible |
| 7 | `postgresql partitioning strategy time series data` | When and how to partition tables (TimescaleDB, native partitioning) |
| 8 | `database naming conventions postgresql enterprise standards` | Industry-standard naming beyond our current snake_case rules |
| 9 | `postgresql connection pooling pgbouncer npgsql best practices` | Connection pooling tuning — pool size, timeout, transaction mode |
| 10 | `database backup verification restore testing strategy` | Backup/restore verification patterns |

### Integration
- Enrich `dba-agent.md` with zero-downtime migration checklist, index advisor queries, partitioning guidelines
- Update `postgresql-data` skill with new patterns discovered
- Add migration safety references to `task-board-ops/references/`

---

## 5. Security Specialist Agent (`security-agent`)

### Current State
Skeleton agent with OWASP Top 10 audit, secret scanning, dependency audit, auth review.

### Research Queries

| # | Search Query | Why |
|---|-------------|-----|
| 1 | `gitleaks configuration secret detection CI pipeline 2025` | Gitleaks setup for detecting secrets in git history and staged files |
| 2 | `OWASP ZAP CLI automated security scanning API` | OWASP ZAP command-line scanning for API security testing |
| 3 | `npm audit dotnet list package vulnerable cargo audit security` | Dependency vulnerability scanning across ecosystems |
| 4 | `snyk vs dependabot vs renovate security scanning comparison` | Best tool for automated dependency security |
| 5 | `content security policy CSP header best practices 2025` | Modern CSP configurations — nonce-based, strict-dynamic |
| 6 | `CORS configuration security best practices common mistakes` | CORS misconfigurations and how to detect them |
| 7 | `JWT security best practices token rotation refresh token` | JWT implementation patterns — rotation, short-lived access, refresh flow |
| 8 | `OWASP top 10 2025 changes update` | Latest OWASP changes to keep the security-compliance skill current |
| 9 | `rate limiting API security brute force protection` | Rate limiting patterns — fixed window, sliding window, token bucket |
| 10 | `supply chain security software bill of materials SBOM` | SBOM generation and supply chain security verification |
| 11 | `trufflehog vs gitleaks secret scanning comparison 2025` | Which secret scanner is more effective and easier to automate |
| 12 | `auth0 security best practices tenant configuration 2025` | Auth0-specific security hardening |

### Integration
- Enrich `security-agent.md` with specific tool commands and patterns
- Update `security-compliance` skill with new OWASP findings
- Add secret scanning regex patterns and CSP templates
- Consider creating `engineering-standards/skills/ci-security/SKILL.md` for CI pipeline security

---

## Execution Strategy

### Phase 1: Research (1 session)
Run all search queries using WebSearch, collect findings, organize by agent.

### Phase 2: Enrich Agents (1 session per agent)
For each agent:
1. Read the current skeleton
2. Apply research findings
3. Write comprehensive prompts with specific patterns, checklists, and output formats
4. Update related engineering-standards skills if new patterns emerge

### Phase 3: Test (1 session per agent)
Deploy to a test project and run each agent on real tasks:
- Does it read the right skills?
- Does it follow the patterns?
- Does its output format work for the QA agent?
- Does it integrate with the retry loop?

### Phase 4: Create New Skills (as needed)
Based on research, create new engineering-standards skills:
- `e2e-testing` — Playwright patterns, selectors, CI setup
- `documentation` — ADR format, changelog, API docs
- `ci-security` — Secret scanning, dependency audit, SBOM
