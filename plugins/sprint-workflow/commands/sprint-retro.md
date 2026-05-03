---
description: Generate a sprint retrospective — analyzes commits, QA cycles, fix-loop counts, codex vs claude split, and emits a retro doc plus suggested CLAUDE.md updates. Run after /sprint-start completes
argument-hint: "[milestone-id | sprint-name]"
allowed-tools: Bash, Glob, Grep, Read, Write, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`
Recent commits: !`git log --oneline -20 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Tracking Mode Detection

### Linear MCP Check
1. Look for `mcp__linear__*` or `mcp__claude_ai_Linear__*`. Try `list_teams`. Success → **Linear mode**, read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`.

### Codex CLI Check
Detect Codex availability for noting it in the retro.

## Your Task

Produce a sprint retrospective. The retro is **data-driven** — it reads commits, QA cycles, fix-loop counts, and tracking data, not vibes. Then a senior agent reflects on what happened and what to change.

### 1. Identify The Sprint

`$ARGUMENTS` may be a milestone ID (Linear) or sprint name (MD). If empty:

- **Linear mode**: list recent milestones, ask the user to pick. Default to the most recently completed (all-tasks-Done) milestone.
- **MD mode**: list `docs/SPRINT_PLAN.md` and any `docs/SPRINT*.md` files, ask the user to pick. Default to the most recent.

Capture:
- Sprint name
- Start date (first commit on the sprint branch / earliest task created date)
- End date (last commit / last task moved to Done)
- Parent Epic ID (Linear) — used for the retro doc path

### 2. Gather Sprint Data

#### From tracking

**Linear mode:**
- All Stories under the milestone — title, status, time-in-status (parsed from comments / status change history if available)
- All Tasks — same, plus `Agent`, `Skills`, `Codex-eligible`, `Phase` fields
- All comments on each issue — these contain the orchestrator's per-phase notes
- Count: blocked tasks, re-dispatched tasks (look for "Re-dispatched by" comments)

**MD mode:**
- Parse the plan document for status fields, agent assignments, codex flags
- Read any embedded QA report sections

#### From git

```bash
git log --since="<start>" --until="<end>" --pretty=format:'%h|%an|%ae|%s|%ad' --date=iso
git diff --stat <start-commit>..<end-commit>
```

Capture:
- Total commits, lines added/removed, files touched
- Commits per agent (parse `feat(scope)`, `fix`, `test`, `docs` prefixes — see `code-standards`)
- Commits authored by Codex vs Claude (heuristic: Codex commits often have "Co-Authored-By: Codex" or `[codex]` prefix; otherwise check Linear comments mapping commits to executors)
- Reverts / amends (signal of churn)

#### From sprint-handoff history

If `docs/SPRINT_HANDOFF.md` exists, check git log for that file. Each modification is a checkpoint where a session ended — count them. High count = many interruptions.

### 3. Compute Metrics

| Metric | Source |
|---|---|
| Stories completed | Count of `Done` Stories |
| Stories deferred | Count of stories started but not Done |
| Tasks total / completed | Linear / MD task counts |
| Tasks delegated to Codex | Count of `codex-eligible: true` tasks that ran on Codex |
| Tasks re-dispatched | Count of "Re-dispatched by" comments |
| QA fix-loop iterations (avg per story) | Count of `In Review → In Progress` reversions per story (Linear); status field reversals (MD) |
| Phase 3 BLOCKING issues found | Sum from QA report comments |
| Phase 3 issues fixed by Codex (surgical) | Subset routed to `/codex:rescue` |
| Phase 3 issues fixed by Claude (architectural) | Remainder |
| Net diff size | `git diff --stat` summary |
| Sprint duration | end - start |
| Sessions / interruptions | Handoff file modification count |
| Architecture drift findings | Sum of `## Architecture Drift Detected` entries from `/sprint-plan`, `/sprint-enrich`, Phase 3 QA, code review (parsed from Linear comments and the local sprint output). 0 if no Architecture & Roadmap doc on the parent Project. |
| Architecture erosion findings | Subset of above flagged as `BLOCKING` per `architecture-drift-check` SKILL.md §8 |

Round percentages to whole numbers.

### 4. Dispatch Reflection Agent

After collecting data, dispatch `product-manager` (or `pr-review-toolkit:code-reviewer` if more code-focused — pick `product-manager` for default retro) with:

```
You are writing the qualitative section of a sprint retrospective. The metrics
have been collected. Your job is to look at the data, the commit history, and
any patterns visible in the code, and answer:

1. What went well? (data-grounded — cite metrics and specific commits)
2. What didn't? (data-grounded — flag long fix-loops, frequent re-dispatches,
   reverts, oversized commits, missing tests)
3. What's the biggest lever for the next sprint? (one or two concrete changes)
4. What CLAUDE.md updates does this sprint suggest? Apply the Scope Rule from
   global CLAUDE.md — global vs project. Cite specific patterns or recurring
   mistakes that justify each suggestion.
5. Skills that were missing or under-used — should any new skills be added or
   existing ones expanded?

Read these as input:
- The collected metrics: <paste metrics>
- The commit log: <paste git log>
- The Linear/MD task list: <paste>
- The QA reports from comments: <paste>

Return a markdown section: ## Reflection
```

### 5. Compose The Retro Document

Path:

- **Linear mode**: `docs/retros/<epic-id>_<YYYY-MM-DD>/<sprint-slug>_retro.md` where `<epic-id>` is the parent Epic of the milestone (or the milestone itself if no parent Epic), `<YYYY-MM-DD>` is the sprint end date, `<sprint-slug>` is the sprint name slugified.
- **MD mode**: `docs/retros/<sprint-slug>_<YYYY-MM-DD>/<sprint-slug>_retro.md` (no Epic ID available).

Create directories as needed.

Document template:

```markdown
# Sprint Retro — <sprint name>

- **Sprint**: <name> (<start> → <end>, <duration> days)
- **Epic**: <id / "none">
- **Retro generated**: <YYYY-MM-DD>
- **Tracking**: <Linear | Markdown>
- **Codex available**: <yes / no>

## Outcomes

| Outcome | Count | % |
|---------|-------|---|
| Stories completed | N | N% |
| Stories deferred | N | N% |
| Tasks completed | N | N% |
| Tasks blocked / cancelled | N | N% |

## Execution Metrics

| Metric | Value |
|--------|-------|
| Total commits | N |
| Lines added / removed | +N / -N |
| Files touched | N |
| Tasks delegated to Codex | N (X% of eligible) |
| Tasks re-dispatched | N |
| Avg fix-loop iterations / story | N.N |
| Phase 3 BLOCKING issues | N (X surgical via Codex / Y architectural via Claude) |
| Sessions (handoff checkpoints) | N |

## Quality Gates

- QA results: PASS / FAIL with iteration count
- Code review results: PASS / FAIL with issue count
- Reverts during sprint: N

## Architecture Drift Summary

(Only emit this section when Linear mode is active AND the sprint's parent Project has an Architecture & Roadmap document.)

| Source | Drift Findings | Erosion Findings |
|---|---|---|
| /sprint-plan (PM self-check) | N | N |
| /sprint-enrich (specialists) | N | N |
| Phase 3 QA (Codex / qa-agent) | N | N |
| Phase 3 code review | N | N |
| **Total** | **N** | **N** |

### Top Drift / Erosion Themes
- <e.g., "Catalog ↔ Inventory communication: 3 erosion findings — code keeps reaching for sync HTTP despite ADR-3">
- <e.g., "Caching: 4 drift findings — Redis keeps appearing without being in the doc">

### Recommendation
- **Drift > 5 OR any erosion merged**: schedule `/sprint-architect --update <project-id>` to align doc with reality
- **Drift 1–5, no erosion**: the doc is roughly accurate; capture in next planning cycle
- **Zero findings**: doc is healthy, no action

## Reflection

(from the dispatched product-manager — keep verbatim)

### What Went Well
...

### What Didn't
...

### Biggest Lever For Next Sprint
...

## Suggested CLAUDE.md Updates

| Scope | Suggestion | Rationale |
|-------|-----------|-----------|
| Global | <change> | <data point> |
| Project | <change> | <data point> |

## Suggested Skill Updates

- <new skill / existing skill expansion> — <rationale>

## Open Items Carried To Next Sprint

- <item> — <reason it's not done>

## Appendix: Commit Log

<truncated git log — first 30 commits with hashes>
```

### 6. Optional: Post Summary To Linear

If Linear mode and the sprint has a parent Epic, ask the user:

```
Post retro summary as a comment on Epic <id>? (y/n)
```

If yes, `save_comment` with a 10-line summary (Outcomes table + biggest lever).

### 7. Final Output

```
✓ Retro written to <path>

Stories completed: N/N
Tasks completed: N/N
Codex utilization: X%
Fix-loop avg: N.N

Suggested CLAUDE.md updates: <count>
Suggested skill changes: <count>

Apply CLAUDE.md updates now? (y/n)
```

If user says yes, dispatch a separate task or apply the changes inline (small) — **do NOT** auto-apply without confirmation.

---

## When To Run

- After `/sprint-start` completes successfully
- After a sprint that was rolled back (interesting failure data)
- Quarterly across multiple sprints — run once per sprint and aggregate yourself

Do NOT run mid-sprint — the data is incomplete and the conclusions are unsafe.
