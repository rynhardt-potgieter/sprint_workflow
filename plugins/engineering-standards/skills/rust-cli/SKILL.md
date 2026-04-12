---
name: rust-cli
description: Use this skill when building any CLI application in Rust — formatting output, handling errors, writing clap argument definitions, or designing the user-facing interface of any subcommand. Trigger on any task involving a new command, a new flag, output formatting, error messages, or the main.rs entry point.
---

# Rust CLI Development

## Command Structure Pattern

Every command follows this pattern:

```rust
// src/commands/example.rs
use anyhow::Result;
use clap::Args;

#[derive(Args, Debug)]
pub struct ExampleArgs {
    /// Primary input — always a positional argument
    /// Examples: MyClass, src/main.rs
    pub target: String,

    /// Output as JSON instead of human-readable format
    #[arg(long, short = 'j')]
    pub json: bool,

    /// Maximum number of results to show (default: all)
    #[arg(long, default_value = "50")]
    pub limit: usize,
}

pub fn run(args: &ExampleArgs) -> Result<()> {
    let result = find_target(&args.target)?
        .ok_or_else(|| anyhow::anyhow!(
            "Target '{}' not found. Check the spelling or path.",
            args.target
        ))?;

    if args.json {
        let output = serde_json::to_string_pretty(&result)?;
        println!("{output}");
    } else {
        formatter::print_result(&result, args.limit);
    }

    Ok(())
}
```

## Clap Setup in main.rs

```rust
use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(
    name = "mytool",
    about = "Short description of what the tool does",
    long_about = "Longer explanation of purpose and usage. Write this \
                  as if explaining to a developer who has never seen \
                  the tool before.",
    version,
    propagate_version = true,
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,

    /// Enable verbose logging
    #[arg(long, global = true)]
    pub verbose: bool,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Brief verb-phrase description of each command
    Example(example::ExampleArgs),
    /// Another command
    Status(status::StatusArgs),
}
```

## Output Formatting

All human-readable output uses a consistent formatter pattern:

```rust
// src/output/formatter.rs
use console::{style, Term};

const SEPARATOR: &str = "─────────────────────────────────────────────────────────────────";

pub fn print_result(item: &Item, limit: usize) {
    // Header line — name, kind, location
    println!(
        "{:<48} {}  {}:{}",
        style(&item.name).bold(),
        style(item.kind.as_str()).dim(),
        item.file_path,
        item.line_range()
    );
    println!("{SEPARATOR}");

    // Body — varies by item kind
    for entry in item.entries().take(limit) {
        println!(
            "{:<48}  {}",
            format!("{}:{}", entry.file_path, entry.line),
            style(&entry.context).dim()
        );
    }
}

pub fn print_list(title: &str, items: &[Item], truncated: bool, total: usize) {
    println!(
        "{} — {} item{}",
        style(title).bold(),
        total,
        if total == 1 { "" } else { "s" }
    );
    println!("{SEPARATOR}");

    for item in items {
        println!(
            "{:<48}  {}",
            format!("{}:{}", item.file_path, item.line),
            style(&item.context).dim()
        );
    }

    if truncated {
        println!("{}", style(format!("... {} more (use --limit to show more)", total - items.len())).dim());
    }
}

// Progress output — always to stderr
pub fn print_progress(message: &str) {
    eprintln!("{message}");
}
```

## Error Handling Patterns

```rust
// User errors — clear, actionable messages
fn find_or_error(name: &str) -> Result<Item> {
    find_item(name)?.ok_or_else(|| {
        anyhow::anyhow!(
            "Item '{}' not found.\n\
             Tip: Check spelling, or try a different search term.",
            name
        )
    })
}

// Missing prerequisite — most common user error
fn require_setup(config: &Config) -> Result<()> {
    if !config.is_initialized() {
        anyhow::bail!(
            "Not initialized. Run '{} init' first.",
            env!("CARGO_BIN_NAME")
        );
    }
    Ok(())
}

// Propagate with context
fn load_data(path: &Path) -> Result<Data> {
    Data::open(path)
        .with_context(|| format!("Failed to open data at {}", path.display()))
}
```

### Error Handling Rules

- Use `anyhow::Result` for application-level error propagation
- Use `thiserror` for library-facing error types (e.g., `src/error.rs`)
- Never use `unwrap()` or `expect()` in production code paths (tests are fine)
- Prefer `?` over `match` unless the match arm adds meaningful context
- Error messages must be actionable: tell the user what went wrong AND what to do about it

## Help Text Guidelines

Help text is read by both humans and LLMs. Write it to be unambiguous:

```rust
/// Show structural overview of an item without reading full source.
///
/// Returns the name, type, dependencies, and related items.
/// Use this to understand structure before diving into source.
///
/// Examples:
///   mytool show MyClass              # show a class
///   mytool show MyClass.myMethod     # show a specific method
///   mytool show src/service.ts       # show a whole file
#[derive(Args)]
pub struct ShowArgs { ... }
```

## JSON Output Schema

Every command's JSON output follows a standard envelope:

```rust
#[derive(serde::Serialize)]
pub struct JsonOutput<T: serde::Serialize> {
    pub command: &'static str,
    pub target: Option<String>,
    pub data: T,
    pub truncated: bool,
    pub total: usize,
}
```

Example:
```json
{
  "command": "show",
  "target": "MyClass",
  "data": [...],
  "truncated": false,
  "total": 11
}
```

### JSON Output Rules

- Every command MUST support `--json` output
- Human-readable is the default; JSON is the programmatic interface
- Data output goes to stdout; progress/warnings go to stderr
- Never mix human-readable and JSON output in the same stream

## CLI Design Rules

1. **Subcommands are verbs.** `mytool show`, `mytool find` — never `mytool --show`
2. **Positional arguments for the primary input.** `mytool show MyClass` not `mytool show --name MyClass`
3. **Flags for modifiers.** `mytool list --kind calls --limit 20`
4. **Never prompt interactively.** CLI tools often run in agent sessions. Never use stdin for input. Use `--force` flags for destructive operations.
5. **Progress output goes to stderr.** Ensures stdout JSON is always clean and parseable.
6. **Sensible defaults.** Commands should work well without flags. Flags are for power users.
7. **Fail loudly and early.** Missing prerequisites get a clear error, not empty results.
8. **Truncate long lists gracefully.** Always show "... N more" when truncating, never silently cut off.

## Binary Size and Startup Time

- Default release profile is sufficient. Do not add LTO or other optimisations until binary size is actually a problem.
- Simple query commands must start in < 50ms. Profile if they don't.
- Heavy dependencies should only be initialised on first use, not at startup.

## Shell Completion

Generate completions for bash, zsh, fish:

```rust
// In a dedicated completions command
use clap_complete::{generate, Shell};

pub fn generate_completions(shell: Shell) {
    let mut cmd = Cli::command();
    let bin_name = env!("CARGO_BIN_NAME");
    generate(shell, &mut cmd, bin_name, &mut std::io::stdout());
}
```

## Exit Codes

- `0` — success
- `1` — user error (bad arguments, missing setup)
- `2` — internal error

## Code Style

- All public functions and structs must have doc comments
- Run `cargo fmt` before every commit
- Run `cargo clippy -- -D warnings` before every PR
- Naming: `snake_case` for modules/files, `PascalCase` for structs, `SCREAMING_SNAKE_CASE` for constants
