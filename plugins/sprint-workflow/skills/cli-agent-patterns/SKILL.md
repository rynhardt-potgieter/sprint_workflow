---
name: cli-agent-patterns
description: Use this skill when building or guiding LLM agents that interact with CLI tools. Covers decision trees for matching tasks to commands, workflow patterns, anti-patterns (excessive tool calls, ignoring cached results), and token efficiency strategies. Trigger on any task involving agent-CLI integration, tool usage optimization, or agent workflow design.
---

# CLI Agent Patterns — Efficient Tool Usage for LLM Agents

LLM agents that use CLI tools for code intelligence, search, or project management need disciplined usage patterns. Every tool call consumes tokens and latency. This skill defines how agents should select, sequence, and limit CLI tool calls for maximum efficiency.

---

## Decision Tree — Match Task to ONE Command

**Start every complex task with an overview command** (e.g., project map, directory listing, status check). This gives you the full context in minimal tokens. Then use ONE specific command for your task:

| Task Type | Approach | When Done? |
|---|---|---|
| **Orientation / start of any task** | Overview/map command | One call. Shows architecture, entry points, key files. |
| Find callers/consumers of a function | Caller/reference lookup | One call. Output has file paths + line numbers + snippets. |
| Understand a class/module structure | Structural overview (sketch/outline) | One call. Shows methods, signatures, dependencies. |
| Find code by intent/description | Semantic or full-text search | One call. Searches names, signatures, descriptions. |
| Find entry points (controllers, handlers) | Entry point listing | One call. Groups by type: API, workers, handlers. |
| Blast radius / transitive impact | Deep caller/dependency lookup | One call with depth parameter. |
| Bug fix / trace call chain | Trace or call-path command | One call. Shows every path from entry point to symbol. |
| Refactor a method signature | Caller/reference lookup | One call. Gives you every call site to update. |
| PR triage / what changed | Diff or changed-files command | One call. Shows affected symbols in changed files. |
| Read actual source of a symbol | Source/cat command | One call. Prints full source for a specific symbol. |
| Find similar implementations | Similarity search | One call. Finds structurally similar code. |

---

## Workflows by Task Type

These workflows are optimal action sequences. Follow them exactly.

### Discovery — "Find X and modify it"

```
search "<description>"           # 1 command: locate the code
-> Read the target file          # 1 read: understand the implementation
-> EDIT                          # Act immediately
```

**Total: 1 tool command + 1-3 reads + edits. Do NOT run a structural overview after search.**

### Bug Fixing — "X is broken, find and fix it"

```
trace/call-path <symbol>         # 1 command: see how requests reach the code
-> Read the suspected file       # 1-2 reads: find the actual bug
-> EDIT                          # Fix it
```

**Total: 1 tool command + 2-3 reads + edit. Do NOT get a structural overview -- you need the source code, not a summary. If you don't know the symbol name, search first, then trace.**

### PR Review — "What changed and what's affected?"

```
diff command                     # 1 command: symbols in changed files
-> overview of changed class     # 1-2 overviews: understand affected symbols
-> Review / comment              # Act
```

**Total: 1 diff + 1-2 overviews. Do NOT read every changed file -- diff tells you what symbols were affected, overview tells you the structure.**

### Reading Source — "I need the actual code for this symbol"

```
source <symbol>                  # 1 command: prints the full source
-> EDIT                          # Modify directly
```

**Use source lookup when you've already navigated (via overview, search, or trace) and need the actual implementation. Skips the overhead of reading the entire file.**

### Refactoring — "Restructure X to pattern Y"

```
structural overview <class>      # 1 command: understand the current structure
-> Read the target file          # 1 read: see the code you'll change
-> Read related files            # 2-3 reads: understand consumers/dependencies
-> EDIT (multiple files)         # Restructure
```

**Total: 1 tool command + 3-5 reads + edits. Overview gives you the structure; then read files you'll actually modify.**

### New Feature — "Build something integrating X, Y, Z"

```
project overview                 # 1 command: understand the architecture
overview <ServiceA>              # 1 overview per API you need to integrate
overview <ServiceB>              # (typically 3-4 overviews)
overview <ServiceC>              #
-> Read 1-2 pattern files        # See how existing integrations work
-> EDIT / Write new files        # Build the feature
```

**Total: 1 project overview + 3-4 overviews + 1-2 reads + edits. This is the sweet spot -- 17-30% token savings. Overviews give you method signatures and constructor params without reading 100+ line files.**

### Exploration — "Document or explain the architecture"

```
project overview                 # 1 command: full architecture overview
entry point listing              # 1 command: all entry points grouped by type
-> Read 2-3 key files            # Only the files you need specific details from
-> Write documentation           # Act
```

**Total: 2 commands + 2-3 reads + write. Do NOT overview every class -- the project map already has the overview. Read files only for specific implementation details that the map doesn't cover.**

---

## Compounding Rules

### Good compounds (use these)
- Project overview -> specific class overview -- overview first, then drill into one class
- Search -> trace -- discover, then trace the call path
- Caller lookup -> caller class overview -- find callers, then understand one caller's context
- Project overview -> entry point listing -- for exploration tasks needing both overview and entry point detail
- Diff -> changed class overview -- PR triage: what changed, then understand affected structure
- Structural overview -> source lookup -- understand structure first, then get actual code when needed

### Bad compounds (never do these)
- Overview X -> Read X -- if you're going to read it, skip the overview
- Search X -> Grep X -- redundant; search already searched
- Callers X -> All-references X -- callers is a subset of references
- Overview A -> Overview B -> Overview C -> ... (5+) -- over-navigating; use project overview instead
- Trace X -> Callers X -> Overview X -- pick ONE, not three

### The 3-Command Limit

If you've run 3 tool commands and haven't edited a file yet, **stop navigating and start editing**. The output from your first command almost certainly had enough information. Agents that follow this rule use 30% fewer tokens.

---

## Anti-Patterns — What NOT to Do

1. **Don't run overlapping lookups** for the same symbol (e.g., callers AND all-references) -- one is a subset of the other.
2. **Don't use deep traversal** for simple "find and update" tasks -- shallow lookup is sufficient.
3. **Don't overview what you'll Read** -- overview is for understanding WITHOUT opening the file.
4. **Don't run 5+ tool commands** for any task -- if you need that many, you're exploring for its own sake.
5. **Don't ignore source snippets** in lookup output -- they show the usage pattern without needing to open the file.
6. **Don't search when you know the symbol name** -- use direct lookup instead.
7. **Don't skip the project overview** for complex tasks -- it replaces 5-17 individual overviews with one command.

---

## Token Efficiency Checklist

Before running a tool command, ask yourself:
1. Do I already have this information from a previous command? -> Don't run it.
2. Will my next action be reading the file anyway? -> Skip the overview.
3. Am I running this "just in case"? -> Don't. Run it when you need it.
4. Have I already run 2+ commands without editing? -> Start editing.
5. Could a project overview replace the 3+ individual overviews I'm about to run? -> Use the overview.

---

## Designing CLI Tools for Agent Consumption

When building CLI tools that agents will use:

1. **Include file paths and line numbers** in all output -- agents need these to navigate.
2. **Include source snippets** in reference/caller output -- avoids a second read.
3. **Support JSON output** on every command -- agents can parse structured data more reliably.
4. **Write help text for LLM readers** -- the `--help` text is how the agent learns to use the tool. Be specific about what the output looks like and when to use the command.
5. **Truncate with counts** -- show "... 15 more (use --limit)" not silent truncation.
6. **Keep output compact** -- overview commands should fit in ~500 tokens.
7. **Never require interactive input** -- agents run non-interactively.
8. **Separate data from progress** -- data to stdout, progress to stderr, so JSON output is always clean.
