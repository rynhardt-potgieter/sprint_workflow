---
description: Pre-planning interrogation — product-manager agent grills the user against the project's domain model and existing code until sprint inputs are unambiguous. Run before /sprint-plan when the spec is loose or the request is high-level
argument-hint: "[topic | spec-file-path]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Your Task

Drive a **grilling session** with the user. The goal is to surface ambiguities, missing requirements, and unstated decisions **before** sprint planning. A loose request like "let's add notifications" should leave this command as a structured set of decisions and open questions that `/sprint-plan` can act on.

You delegate the actual interrogation to the `product-manager` agent — they own user-story authorship and have the codebase awareness to ask sharp questions.

### 1. Frame The Topic

`$ARGUMENTS` may be:
- A topic name ("notifications", "auth refactor")
- A spec file path
- Empty — ask the user "What are we grilling on today?"

Capture the topic. Read any referenced spec file fully.

### 2. Read Project Context

- `CLAUDE.md` if present
- Any spec documents the project CLAUDE.md references (e.g., `docs/`, `specs/`)
- Existing `.claude/skills/*/SKILL.md` for project-specific domain language

### 3. Dispatch product-manager In Grill Mode

Dispatch `product-manager` with this prompt structure:

```
You are running a GRILLING SESSION, not writing a plan. Your job is to interrogate
the user until the topic is fully specified, then return a structured "ready for
sprint-plan" summary.

## Topic
<topic from step 1>

## Spec / Initial Brief
<spec contents or user's high-level request>

## Required Skills To Read
- ${CLAUDE_PLUGIN_ROOT}/skills/code-standards/SKILL.md
- All other skills in ${CLAUDE_PLUGIN_ROOT}/skills/ — scan and read every relevant one
- Project-local skills at .claude/skills/*/SKILL.md
- ${CLAUDE_PLUGIN_ROOT}/skills/diagnose/SKILL.md (for failure-mode questions)

## Procedure

1. **Map the domain.** Read enough of the codebase to understand what the topic touches.
   Identify: existing modules, naming conventions, related entities, integration points.

2. **Build a question list, ranked by load-bearing weight.**
   - Decisions that change architecture (storage, sync vs async, push vs pull)
   - Decisions that change scope (what's in / out of this slice)
   - Decisions that change API contracts (request/response shape, breaking change)
   - Decisions that change UX (who sees what, when, how)
   - Failure modes (what happens when X breaks, partial failures, retries)
   - Compliance / security (PII, audit trail, auth boundaries)

3. **Grill the user iteratively.**
   Ask 2-4 questions at a time, never a wall of 20.
   Wait for answers. Use answers to refine subsequent questions.
   Push back when answers are vague: "you said 'eventually' — is that hours, days, weeks?"
   Surface contradictions: "Earlier you said all users see notifications;
   now you said admin-only. Which is it?"

4. **Reference the existing code constantly.**
   "There's already a `NotificationService` at `src/services/NotificationService.cs:42`.
   Are we extending it or replacing it?"
   "The audit-trail pattern in `events/AuditLog.cs` would imply X. Apply that here too?"

5. **Stop when:**
   - All architectural questions are answered
   - All scope questions are answered (in-scope list is closed)
   - All API contract decisions are made
   - All failure modes have a defined behaviour
   - No "we'll figure it out later" answers remain

6. **Return a structured summary.**

## Output Format (when grilling is complete)

```markdown
# Grilling Summary — <topic> — <date>

## Locked Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | <decision>| <why> |

## Scope

### In
- <bullet>

### Out
- <bullet>

### Deferred (explicitly NOT this sprint)
- <bullet>

## API Contracts (if applicable)

<endpoint shapes, event schemas, message formats — exact, not paraphrased>

## Failure Modes

| Scenario | Expected Behaviour |
|----------|-------------------|
| <e.g. notification service down> | <e.g. queue + retry with exponential backoff, max 5 retries> |

## Compliance / Security

- <PII handling decisions>
- <auth boundary decisions>
- <audit trail decisions>

## Existing Code Touched

- `<path>` — <what changes>

## Open Questions (if any)

These should be near-zero by the end of grilling. If non-empty, the user explicitly
chose to defer them.

- <question> — deferred to: <when>

## Suggested Sprint Plan Inputs

- Suggested user stories: <count>
- Suggested agent split: backend-dev=N, frontend-dev=N, ...
- Codex-eligibility hint: <high/medium/low based on scope shape>
- Estimated complexity: small/medium/large

## Anti-Patterns Identified

- <patterns to avoid based on prior code or spec analysis>
```

If the user wants to stop grilling early (some questions remain open), accept that
but record the open questions explicitly so `/sprint-plan` knows what's not nailed
down.
```

### 4. Receive Grilling Summary

The `product-manager` will return the structured summary.

### 5. Save Output

Write the summary to `docs/grilling/<topic-slug>-<YYYY-MM-DD>.md`. Create the directory if missing.

If a Linear team is set up, also offer to create a Linear `Document` (via `save_document`) attached to the team for visibility — ask the user before doing this.

### 6. Hand Off

```
✓ Grilling complete — saved to docs/grilling/<topic-slug>-<YYYY-MM-DD>.md

Locked decisions: <N>
Open questions: <N>

Next step: /sprint-plan <path-to-grilling-summary>

The product-manager can now produce a precise plan from the locked decisions.
```

---

## When To Use

- The user's request is high-level and you sense ambiguity ("let's add X", "make Y better")
- The spec doc has gaps you noticed during a previous sprint
- A topic spans multiple subsystems and you want decisions locked before parallel agents diverge
- After a previous sprint failed because of late-discovered ambiguity

When the spec is already detailed (full PRD, locked design doc, finished issue list), skip grilling and go straight to `/sprint-plan`. Grilling is for loose inputs — not a ceremony.

## Relationship To `/sprint-plan --grill`

`/sprint-plan` accepts an optional `--grill` flag that triggers this same grilling step inline before producing the plan. Use the standalone `/sprint-grill` when you want grilling separated from planning (e.g., grill today, plan tomorrow). Use `--grill` for one-shot grill+plan in the same session.
