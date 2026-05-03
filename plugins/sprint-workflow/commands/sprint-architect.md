---
description: Produce a feature roadmap and full system architectural design from any context (current conversation, PRD, attached docs), then load the result into Linear as a Project + "Architecture & Roadmap" Document + Epic issues. Use --update <project-id> to refresh the doc when the system has materially changed. Hard requirement — Linear MCP must be detected.
argument-hint: "[--update <project-id>] [path-to-spec | URL | --from-conversation]"
allowed-tools: Bash, Glob, Grep, Read, Edit, Agent, AskUserQuestion
---

## Context

Arguments: $ARGUMENTS
Current directory: !`pwd`
Project: !`basename $(pwd)`
Branch: !`git branch --show-current 2>/dev/null || echo "n/a"`

## Available Skills (auto-discovered)

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/discover-skills.sh" 2>/dev/null || echo "Skill discovery failed — search for .claude/skills/*/SKILL.md (project-local) and ${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md (plugin-bundled)"`

## Hard Requirement: Linear MCP

This command writes its output to Linear and refuses to fall back to markdown — local MD architecture docs go stale and nobody reads them. Detect Linear MCP **before** any other work:

1. Look for `mcp__linear__*` or `mcp__claude_ai_Linear__*` tools
2. Try `list_teams` with whichever prefix exists
3. On `-32600` retry once
4. If both fail OR no Linear MCP tools exist → **refuse and exit** with this message:

```
/sprint-architect requires Linear MCP. The architecture & roadmap artifact lives in
Linear so it stays close to the work and visible to the team. Local markdown is not
supported — those files go stale.

Set up Linear MCP:
  https://linear.app/docs/mcp
  https://github.com/anthropics/claude-code (see plugin marketplace for the linear plugin)

Then re-run /sprint-architect.
```

If Linear is detected, **read `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md`** for taxonomy and §12 (Project Documents) before proceeding.

## Codex Note

Codex availability is irrelevant for this command. Architecture work requires deep reasoning over context; always run via Claude opus (the `product-manager` agent in architecture mode).

## Argument Resolution

Resolve `$ARGUMENTS` in this order:

1. **Starts with `--update <project-id>`** → drift-update mode. Skip to "Update Mode" section.
2. **`--from-conversation`** → use the current session conversation as primary context.
3. **Looks like a file path** (`.md`, `.txt`, `.pdf` extension or matches an existing path) → read the file as primary context.
4. **Looks like a URL** → fetch via WebFetch as primary context.
5. **Empty** → default to using the current session conversation as primary context (same as `--from-conversation`).
6. **Free text** → treat as a brief description; ask the user if they want to attach a longer spec or use the current conversation.

In all cases, the user can also reference @-attached files which Claude Code will surface in this session — include those.

---

## Mode A: Create (default)

### Step 1 — Confirm Context

Before doing anything else, restate what you understood from the input as a one-paragraph summary, then ask the user to confirm or correct. This guards against over-interpreting tangents in conversation context.

```
Here's what I understood:

<one paragraph: the product/feature, the users, the problem it solves, the
broad shape of the system being built or extended, any constraints I picked
up from context>

Is this the right framing? (y / correct it / cancel)
```

If the user corrects it, restate and ask again. If they cancel, exit cleanly.

### Step 2 — Clarifying Questions (≤ 5)

Identify decisions that **materially shape the architecture** and ask them one at a time using the `AskUserQuestion` tool.

A "material" decision is one where picking the wrong option would force a significant redesign later. Examples:

- Sequencing — "Build the API surface first, or the data layer first?"
- Communication style — "Sync calls between bounded contexts, or events?"
- Persistence — "Reuse the existing PostgreSQL, or introduce a separate store?"
- Auth model — "Reuse the current Auth0 tenant, or new tenant for isolation?"
- Scope cut — "Include reporting in v1, or defer to a later phase?"
- Tech swap — "Stay on the current queue, or migrate as part of this work?"

**Rules for question framing:**

- **Cap at 5 questions.** If more decisions are needed, batch the rest as "Choose for me" defaults and list them in the doc for review later.
- **Plain English.** "Should orders and inventory talk synchronously or via events?" — not "Synchronous coupling vs eventual consistency between bounded contexts."
- **Each question gets 2–4 concrete options + "Choose for me (recommend the best fit)" + "Skip / not sure"**.
- **For every "Choose for me" branch, you must include your recommendation + a one-line reason in the question's description so the user sees it before delegating.**
- **No leading questions.** Don't bias toward your preferred option.

When the user picks "Choose for me", record `(auto-selected)` next to the decision in the doc. When they pick "Skip / not sure", pick the safest default and tag `(deferred)`.

### Step 3 — Generate Artifacts

You produce three things in Linear, in this order. Read `linear-sprint-planning` SKILL.md §12 for the exact creation patterns.

#### 3a. Discover Team & Project Target

If the user has not already specified, call `list_teams` and ask which team to create under. Then ask whether to create a **new** Linear Project for this initiative, or attach to an **existing** Project.

#### 3b. Create the Linear Project (if new)

```
save_project({
  name: "<concise initiative name>",
  team: "<team-name>",
  description: "<one-paragraph elevator pitch — the same framing the user confirmed in Step 1, polished>",
  targetDate: "<YYYY-MM-DD if implied by context, else omit>"
})
```

Capture the returned `projectId`.

#### 3c. Dispatch product-manager Agent (architecture mode)

Launch `product-manager` with a prompt that includes:

1. **The confirmed context** (Step 1 paragraph)
2. **All clarifying-question answers** (including which were "Choose for me" / "Skip")
3. **The full primary-context input** (file contents, URL contents, or conversation transcript)
4. **Project conventions** — read `CLAUDE.md` if present and pass key sections
5. **Available skills list** — paste the auto-discovery output
6. **Instruction**: produce the **Architecture & Roadmap** document body following the structure in `linear-sprint-planning` SKILL.md §12. The document MUST follow C4 + ADR + arc42 hybrid structure (industry standard for SaaS teams). The agent reads `${CLAUDE_PLUGIN_ROOT}/skills/linear-sprint-planning/SKILL.md` §12 for the exact section ordering and content.
7. **Output requirements**:
   - Markdown body for the Document
   - A **list of Epics** to create — one per Phase in §5 of the doc, each with: title, one-paragraph scope summary, dependencies on prior Epics, suggested labels
8. The agent does **NOT** call any Linear tools itself — it returns the markdown body and the Epic list. The orchestrator (this command) does the writes.

#### 3d. Save the Architecture & Roadmap Document

```
save_document({
  projectId: "<projectId from 3b>",
  title: "Architecture & Roadmap",
  content: "<markdown body returned by product-manager>"
})
```

Capture the returned `documentId` and the document URL for inclusion in Epic descriptions.

#### 3e. Ensure Labels Exist

Per `linear-sprint-planning` §3, ensure `Epic`, `Feature`, `Improvement`, `Decision` labels exist on the team. Create any that are missing.

#### 3f. Create Epic Issues (one per Phase)

For each Epic returned by the product-manager:

```
save_issue({
  title: "<Phase N: short title>",
  team: "<team-name>",
  project: "<project-name from 3b>",
  labels: ["Epic", "Feature"],   // or "Improvement" if it's a refactor phase
  priority: <1-4 based on phase order — phase 1 = high>,
  description: "<see template below>"
})
```

Epic description template:

```
## Scope

<one-paragraph scope summary from product-manager output>

## Dependencies

- <List of prior Epics that must complete first, with Linear IDs once known>
- "None" if this is Phase 1

## Architecture Context

This Epic is part of the [<Project Name>](<project URL>) initiative.
Full architecture and roadmap: [Architecture & Roadmap](<document URL>)

Read the document before breaking this Epic into Tasks via /sprint-plan.

## Phase

<N>

## Status

Pending — run `/sprint-plan <epic-id>` to break into Tasks.
```

Note: do **not** create Tasks here — that is `/sprint-plan`'s job. `/sprint-architect` only creates the architectural skeleton.

### Step 4 — Final Report

```
✓ Architecture & Roadmap created.

Linear Project: <project URL>
Document:       <document URL>

Epics created:
  <id> — Phase 1: <title>
  <id> — Phase 2: <title>
  ...

Decisions recorded:
  ✓ <decision> — <user choice>
  ⚙ <decision> — auto-selected (<recommendation>)
  ⏸ <decision> — deferred (<safe default chosen>)

Next steps:
  1. Review the Architecture & Roadmap document in Linear.
  2. When ready, run /sprint-plan <epic-id> to break the next Phase into Tasks.
  3. /sprint-plan will auto-load the Architecture & Roadmap as context.
```

---

## Mode B: Update (`--update <project-id>`)

This mode refreshes the existing Architecture & Roadmap document when the system has materially changed (drift findings have piled up, a Phase shipped and revealed unforeseen needs, or the user explicitly says "the architecture has shifted").

### Step 1 — Load Current Document

1. `get_project({id: "<project-id>"})` — confirm the Project exists.
2. `list_documents({projectId})` → find `Architecture & Roadmap`.
3. `get_document({id})` — pull the current body.
4. `list_issues({project, label: "Epic"})` — list current Epics and their status.
5. Optional: pull recent commits via `git log --oneline --since="<doc-creation-date>"` for context.

### Step 2 — Identify What Changed

Ask the user (single AskUserQuestion call with multi-choice):

```
What's prompting this update?
  1. Drift findings from a recent sprint
  2. A Phase shipped and revealed gaps
  3. New requirements / scope addition
  4. Tech choice change (e.g., DB swap, auth provider change)
  5. Cleanup pass — multiple small accumulated changes
  6. Other (describe)
```

If the user can paste specific drift findings (from a `/sprint-start` Phase 3 report or a `/sprint-retro` summary), incorporate them.

### Step 3 — Re-Ask Only Invalidated Questions

You do **NOT** re-ask every clarifying question — only those whose answers the new context has invalidated. Identify these by reading the existing §6 ADRs:

- For each ADR, ask "does the new context contradict this decision?"
- If yes → re-ask with the same options + "Choose for me" + "Skip"
- If no → keep the existing answer

Cap at 3 questions for `--update` (lower than create-mode's 5 — you're refining, not designing from scratch).

### Step 4 — Dispatch product-manager (architecture-update mode)

Launch `product-manager` with:

1. The **current document body**
2. The **new context** (drift findings, new requirements, etc.)
3. The **answers from Step 3**
4. Instruction: rewrite the document, prepending a **Change Log** entry to §7 with: date, summary of what changed, which ADRs were added/superseded/deprecated, what motivated the update.
5. Mark superseded ADRs with `Status: Superseded by ADR-<N>` rather than deleting them — Linear documents have history, but in-document continuity helps readers.

### Step 5 — Save the Updated Document

```
save_document({
  id: "<document-id>",
  content: "<updated markdown body>"
})
```

Linear retains version history on documents, so the previous version is recoverable.

### Step 6 — Create New Epics If Needed

If the update introduces new Phases (e.g., scope addition), create new Epic issues per Step 3f of Create mode. Existing Epics whose scope changed get a comment via `save_comment` noting the architectural shift.

### Step 7 — Final Report

```
✓ Architecture & Roadmap updated.

Document: <document URL>
Change Log entry: <date> — <one-line summary>

ADRs:
  + Added: <count>
  ↺ Superseded: <count>
  - Deprecated: <count>

New Epics: <list, or "none">

Sprint impact:
  Active sprint? <yes/no — if yes, recommend running /sprint-plan again on
  in-progress Epics to validate Tasks against the updated architecture>
```

---

## Anti-Patterns

- **Asking 10+ clarifying questions.** The cap is 5 (Create) / 3 (Update). Beyond that, batch into "Choose for me" defaults and let the user override later.
- **Skipping context confirmation.** Always restate before generating. Otherwise users who said "auth flow" get a full payment-system design.
- **Writing the doc without an ADR section.** Decisions without recorded rationale are how architectural drift starts.
- **Creating Tasks under Epics.** This command stops at Epics. `/sprint-plan` creates Tasks.
- **Falling back to markdown.** No. The whole point is no MD. Refuse if Linear is unavailable.
- **Re-asking every question in Update mode.** Update is incremental; only re-ask what the new context invalidates.
- **Auto-applying "Choose for me" without showing the recommendation.** Every "Choose for me" branch must show what the agent picked and why before the user delegates.
