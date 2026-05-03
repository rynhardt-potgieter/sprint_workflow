---
name: architecture-drift-check
description: Detect architectural drift and erosion by comparing implemented or planned work against the project's Linear "Architecture & Roadmap" document. Use this skill in /sprint-plan and /sprint-enrich (planning-time drift), in /sprint-start Phase 3 QA and code review (implementation-time drift and erosion), and in /sprint-retro (sprint-level drift summary). Defines drift vs erosion, the reflexion-modeling comparison method, severity rules, the standard report format, and the conditions under which the check is skipped gracefully.
version: 1.0.0
---

# Architecture Drift Check

The sprint-workflow plugin treats the Linear **Project Document** named "Architecture & Roadmap" (created by `/sprint-architect`) as the **prescribed architecture**. The implemented or planned code is the **implemented architecture**. Drift detection compares the two and flags deviations.

This is the academic concept of **reflexion modeling** (Murphy et al., 1995; widely surveyed since): build an abstract model of the prescribed architecture, build a comparable model of the implementation, walk both, report convergences, divergences, and absences.

---

## 1. Drift vs Erosion (the two failure modes)

These terms come from the architecture research literature (see "Drift and Erosion in Software Architecture", Li et al. 2020). They are different and get reported with different severity.

| Concept | Definition | Example | Default Severity |
|---|---|---|---|
| **Drift** | Implementation introduces a component, integration, or data flow that the prescribed architecture **does not mention**. The doc isn't violated — it's silent on what was added. | Doc says "Orders → Inventory via REST". Code adds a new Redis cache between them. The doc is silent on caching. | **WARNING** |
| **Erosion** | Implementation **violates** an explicit decision, constraint, or quality attribute in the prescribed architecture. | Doc's ADR-3 says "Orders and Inventory communicate asynchronously via events". Code adds a synchronous HTTP call. | **BLOCKING** |

The split matters because drift is often *correct* — the doc was incomplete and reality has more nuance — but erosion is almost always a bug or a deliberate decision that needs to be re-recorded. Erosion blocks; drift warns.

---

## 2. When This Skill Is Used

| Caller | Stage | What gets compared |
|---|---|---|
| `/sprint-plan` (product-manager agent) | Planning, after Task breakdown | Proposed Tasks vs prescribed architecture. Erosion = "this Task list cannot be built without violating ADR-N" → flag before sprint starts. |
| `/sprint-enrich` (specialist agents: dba, security, backend-dev, frontend-dev) | Plan refinement | Each specialist looks for domain-specific drift in the proposed plan (DBA: storage decisions; security: auth/data flow; backend: service boundaries). |
| `/sprint-start` Phase 3 (Codex adversarial review OR qa-agent) and `pr-review-toolkit:code-reviewer` | After implementation | Actual diff vs prescribed architecture. This is where erosion surfaces in real code. |
| `/sprint-retro` | After sprint completes | Aggregate drift/erosion findings; recommend `/sprint-architect --update` if the doc is materially behind reality. |

---

## 3. Inputs (what to fetch before comparing)

### From Linear

1. The Task or Story under review → `get_issue({id, includeRelations: true})` to find its parent Project.
2. The parent Project → `list_documents({projectId})`. Find the Document titled `Architecture & Roadmap`.
3. The Document body → `get_document({id})`. This contains the prescribed model.

### From the codebase or plan

- **Planning-time check** (`/sprint-plan`, `/sprint-enrich`): the proposed Task list, including Technical Notes and Anti-patterns sections.
- **Implementation-time check** (`/sprint-start` Phase 3, `pr-review-toolkit:code-reviewer`): the diff (`git diff <base>..HEAD`) plus a directory tree to see new files.

---

## 4. Building The Prescribed Model

The "Architecture & Roadmap" Document follows a fixed structure (defined in `linear-sprint-planning` SKILL.md §12). Extract the prescribed model from these sections:

| Section | Element to extract |
|---|---|
| §1 Context | External systems, in/out of scope statement |
| §2 Quality Attributes | Each attribute is a constraint (e.g., "p99 < 200ms" is a perf constraint; "no PII in logs" is a compliance constraint) |
| §3 Containers (C4 Level 2) | Named services/components and their declared communication style (sync/async/shared-DB) |
| §4 Cross-Cutting Concerns | Auth model, multi-tenancy approach, secrets handling, logging |
| §6 Architectural Decisions (ADRs) | Each ADR is a decision with explicit Status / Context / Decision / Consequences. Status `Accepted` decisions are binding; `Proposed` and `Deprecated` are not. |

Build a normalized list:

```
Containers:    [Orders, Inventory, Catalog, OrdersDB, EventBus]
Edges:         [(Orders → Inventory, async/event), (Catalog → CatalogDB, sync/sql)]
Constraints:   [Q-1: p99 < 200ms, Q-2: PII never in logs, ADR-3: cross-context = events only]
Forbidden:     [sync HTTP between bounded contexts (from ADR-3), shared DB across contexts]
```

The Forbidden list is derived from the Consequences of each ADR — anything an ADR explicitly rules out becomes an erosion trigger if seen in code.

---

## 5. Building The Implemented Model

### Planning-time

Walk the proposed Task list. For each Task, extract from its Technical Notes:

- New components/services it would introduce
- New dependencies between existing components
- Data flow direction
- Storage decisions (new tables, new caches, new queues)
- Auth/security touchpoints

This is approximate but sufficient — the goal is "does the plan look feasible under the prescribed architecture?"

### Implementation-time

From `git diff` on the sprint branch:

- New files in `src/` → potential new components (especially under `services/`, `packages/`, `apps/`)
- New imports across module boundaries → potential new edges
- New `httpClient.GetAsync` / `fetch()` calls → potential sync edges
- New `publish()` / `MqttClient.Publish` / event-bus calls → async edges
- New SQL connection strings / `DbContext` registrations → storage additions
- Removed components → potential erosion of stated structure

Tools: `git diff --stat`, `grep` for import patterns, `scope` CLI when available (project-local).

---

## 6. The Comparison (Reflexion)

For each element in the implemented model, classify:

| Result | Meaning |
|---|---|
| **Convergence** | Implementation matches a prescribed element. No report entry. |
| **Divergence (Drift)** | Implementation has an element the prescribed model does not mention. Report as drift. |
| **Divergence (Erosion)** | Implementation has an element that the prescribed model **forbids**. Report as erosion. |
| **Absence** | Prescribed model has an element the implementation has not built yet. Not a finding (it's just unbuilt scope). |

Erosion triggers (by category):

- **Communication style erosion**: edge between two prescribed containers exists at runtime, but with the wrong style (sync where ADR mandates async, or vice versa).
- **Boundary erosion**: prescribed bounded context A directly accesses prescribed bounded context B's database/internal types.
- **Cross-cutting erosion**: code introduces secrets in source, logs PII, bypasses the auth model — anything that violates §4 or a stated quality attribute.
- **ADR-Decision erosion**: code does the exact thing an Accepted ADR's Decision section ruled out.

---

## 7. Report Format

Every caller of this skill MUST emit findings in this exact format, so downstream agents (and the user) parse it consistently:

```
## Architecture Drift Detected

### Drift (new, undocumented — WARNING)
- <component-or-edge>: <what it is>. <why it appeared if known>.
  Files: <comma-separated paths>
  Suggestion: document in Architecture & Roadmap §3 (Containers) or §6 (ADR).

### Erosion (violates prescribed architecture — BLOCKING)
- ADR-<N> "<title>": <what was decided> vs <what code/plan does>.
  Files: <comma-separated paths>
  Action: revert the violation, OR run `/sprint-architect --update <project-id>`
  to record the deliberate decision change.

### Skipped Checks
- <constraint that couldn't be evaluated>: <why> (e.g., "Q-1 p99 < 200ms — needs runtime data, not visible in static review")

Recommend: /sprint-architect --update <project-id>
```

If there are no findings of either kind, **do not emit the section at all**. Silence is signal.

---

## 8. Severity Rules

| Caller | Drift | Erosion |
|---|---|---|
| `/sprint-plan` | Informational (the plan can still proceed; doc may need updating) | **BLOCKING** the plan as proposed — present to user, ask whether to update doc first or revise the plan |
| `/sprint-enrich` | Informational, included in the enrichment notes | **BLOCKING** the plan — same handling as `/sprint-plan` |
| `/sprint-start` Phase 3 (Codex adversarial / qa-agent) | `WARNING` in the QA report | `BLOCKING` in the QA report — sprint cannot complete |
| `pr-review-toolkit:code-reviewer` | `WARNING` in the review | `BLOCKING` in the review |
| `/sprint-retro` | Counted in the retro summary | Counted; if any erosion was merged anyway, flag explicitly |

---

## 9. Skip Conditions (graceful degradation)

The check **must skip silently** (with a one-line note in agent output) when:

1. **No Linear MCP available** — there is no doc to compare against.
2. **No parent Project found for the Story/Task** — the work isn't tied to an architected initiative. Ad-hoc bug fixes from `/sprint-bug-triage` often fall here.
3. **Project has no `Architecture & Roadmap` document** — initiative was created without `/sprint-architect`.
4. **Document is missing §3 Containers OR §6 ADRs** — the doc exists but is too sparse to compare against. Recommend running `/sprint-architect --update <project-id>` to fill it in.
5. **Document is older than 90 days AND the codebase has changed substantially** (>500 commits since the doc was last updated) — the doc is too stale to trust as a baseline. Recommend `/sprint-architect --update <project-id>`.

In every skip case, emit:

```
## Architecture Drift Check: Skipped
Reason: <one of the conditions above>
```

Do NOT silently pass — the user needs to know the check didn't run.

---

## 10. What This Skill Is Not

- **Not a runtime conformance check.** It does not run the system. Performance, latency, and behavioural quality attributes (anything that needs traces or load tests) are flagged as "Skipped — needs runtime data".
- **Not a source-of-truth.** When erosion is found, the human (or `/sprint-architect --update`) decides whether code or doc is wrong. The skill flags; humans resolve.
- **Not Codex-runnable.** Codex doesn't have Linear MCP. When Phase 3 QA runs via Codex adversarial review, the orchestrator pre-fetches the doc and passes its prescribed-model summary inline. See `codex-delegation` SKILL.md §11.

---

## 11. Quick Reference For Agents

```
1. Find parent Project via get_issue includeRelations
2. list_documents({projectId}) → find "Architecture & Roadmap"
3. get_document({id}) → extract Containers, Edges, ADRs, Forbidden list
4. Walk plan or diff → build implemented model
5. Compare → emit "## Architecture Drift Detected" section if any findings
6. Severity: drift=WARNING, erosion=BLOCKING (per §8 caller table)
7. If any skip condition (§9) hits → emit "## Architecture Drift Check: Skipped"
```

The check is meant to be cheap (one Linear fetch, one diff scan, no LLM round-trip beyond the agent already running). If you find yourself spending more than 30s on it, you are over-engineering — emit what you have and continue.
