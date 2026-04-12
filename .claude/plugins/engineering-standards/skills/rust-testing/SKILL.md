---
name: rust-testing
description: Use this skill when writing any test in a Rust project — unit tests, integration tests, snapshot tests, or fixture setup. Trigger on any task involving test files, the tests/ directory, fixture projects, or cargo test commands.
---

# Rust Testing

## Testing Philosophy

- Every new command or feature gets an integration test
- Every bug fix gets a regression test written BEFORE the fix
- Output format is a contract — always snapshot test it
- Never test against real user data — always use controlled fixtures
- Test names describe the scenario, not the function

## Unit Tests

Unit tests live in the same file as the code, in a `#[cfg(test)]` module at the bottom:

```rust
// src/core/store.rs
impl Store {
    pub fn find_item(&self, name: &str) -> Result<Option<Item>> {
        // ... production code ...
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn setup_test_store() -> (Store, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let store = Store::open(&db_path).unwrap();
        (store, dir)  // return dir to keep it alive
    }

    #[test]
    fn find_item_returns_none_for_unknown_name() {
        let (store, _dir) = setup_test_store();
        let result = store.find_item("NonExistent").unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn find_item_finds_by_qualified_name() {
        let (mut store, _dir) = setup_test_store();

        // Insert test data
        store.upsert_item(&Item {
            id: "test::MyClass::myMethod".into(),
            name: "myMethod".into(),
            kind: ItemKind::Method,
            // ...
        }).unwrap();

        let result = store.find_item("MyClass.myMethod").unwrap();
        assert!(result.is_some());
        assert_eq!(result.unwrap().name, "myMethod");
    }

    #[test]
    fn transitive_lookup_finds_deep_dependencies() {
        let (mut store, _dir) = setup_test_store();

        // A depends on B, B depends on C — lookup from A should find C
        insert_test_chain(&mut store, vec![
            ("A", "B"),
            ("B", "C"),
        ]);

        let result = store.find_transitive("C", 3).unwrap();

        assert!(result.contains_at_depth("B", 1));
        assert!(result.contains_at_depth("A", 2));
    }
}
```

### Unit Test Rules

- Use `tempfile::tempdir()` for any test that needs filesystem state
- Always return the `TempDir` handle from setup functions to keep it alive for the test's duration
- Use `unwrap()` freely in tests — panics produce clear test failures
- Name tests after the scenario: `find_item_returns_none_for_unknown_name` not `test_find`

## Integration Tests

Integration tests live in `tests/integration/` and test commands end-to-end against fixture projects:

```rust
// tests/integration/test_show.rs
use assert_cmd::Command;
use predicates::str::contains;

// Fixture path — small project with known structure
const FIXTURE: &str = "tests/fixtures/simple-project";

#[test]
fn show_displays_name_and_file() {
    Command::cargo_bin("mytool")
        .unwrap()
        .args(["show", "MyClass"])
        .current_dir(FIXTURE)
        .assert()
        .success()
        .stdout(contains("MyClass"))
        .stdout(contains("src/service.ts"));
}

#[test]
fn show_returns_error_for_unknown_target() {
    Command::cargo_bin("mytool")
        .unwrap()
        .args(["show", "NonExistentClass"])
        .current_dir(FIXTURE)
        .assert()
        .failure()
        .stderr(contains("not found"));
}

#[test]
fn json_output_is_valid_json() {
    let output = Command::cargo_bin("mytool")
        .unwrap()
        .args(["show", "MyClass", "--json"])
        .current_dir(FIXTURE)
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let json: serde_json::Value = serde_json::from_slice(&output)
        .expect("Output should be valid JSON");

    assert_eq!(json["command"], "show");
    assert!(json["data"]["name"].as_str().is_some());
}
```

### Integration Test Rules

- Use `assert_cmd` for running the binary and asserting on output
- Use `predicates` for flexible stdout/stderr assertions
- Each test should be self-contained — no shared mutable state between tests
- Test both success and error paths

## Snapshot Tests (insta)

Use `insta` for output format tests. Output format is a contract — changes must be explicit:

```rust
// tests/integration/test_output_format.rs
use insta::assert_snapshot;
use assert_cmd::Command;

#[test]
fn show_output_format_matches_snapshot() {
    let output = Command::cargo_bin("mytool")
        .unwrap()
        .args(["show", "MyClass"])
        .current_dir("tests/fixtures/simple-project")
        .output()
        .unwrap();

    let stdout = String::from_utf8(output.stdout).unwrap();

    // On first run: creates a snapshot file in tests/snapshots/
    // On subsequent runs: compares against saved snapshot
    assert_snapshot!("show_my_class", stdout);
}
```

**Snapshot workflow:**
```bash
# First run — creates snapshot files
cargo test

# Review new/changed snapshots
cargo insta review

# Accept all changes (be intentional about this)
cargo insta accept
```

Snapshot files live in `tests/snapshots/` and are committed to git. Any change to output format shows up as a snapshot diff in PR review.

## Test Fixtures

### Fixture Design

Test fixtures are small, controlled projects with known, deterministic structure:

```
tests/fixtures/simple-project/
  src/
    service.ts        # A class with known methods
    types.ts          # Type definitions
    controller.ts     # Consumes the service
  config.json
```

The fixture has known, deterministic properties that serve as ground truth:
- Exact counts (e.g., "MyClass has exactly 3 methods")
- Exact relationships (e.g., "Controller calls processPayment 4 times")
- Known structure (e.g., "Logger has exactly 2 consumers")

These numbers are the ground truth for correctness tests.

### Fixture Management

If fixtures include pre-built indexes or databases, they must be committed to git and re-generated when the schema changes:

```bash
# Rebuild fixture data after schema change
cd tests/fixtures/simple-project && mytool init --full

# Commit the rebuilt data
git add tests/fixtures/
git commit -m "test(fixtures): rebuild data after schema change"
```

## Common Test Patterns

### Testing data layer queries directly

```rust
fn insert_item(store: &mut Store, name: &str, kind: ItemKind) -> String {
    let id = format!("test::{name}");
    store.upsert_item(&Item {
        id: id.clone(),
        name: name.to_string(),
        kind,
        file_path: "test.ts".to_string(),
        line_start: 1,
        line_end: 10,
        ..Default::default()
    }).unwrap();
    id
}

fn insert_edge(store: &mut Store, from: &str, to: &str, kind: EdgeKind) {
    store.upsert_edge(&Edge {
        from_id: format!("test::{from}"),
        to_id: format!("test::{to}"),
        kind,
        file_path: "test.ts".to_string(),
        line: Some(5),
    }).unwrap();
}
```

### Testing that error messages are helpful

```rust
#[test]
fn missing_setup_gives_helpful_error() {
    let dir = tempdir().unwrap();  // empty dir, no setup

    Command::cargo_bin("mytool")
        .unwrap()
        .args(["show", "anything"])
        .current_dir(dir.path())
        .assert()
        .failure()
        .stderr(contains("Run"));  // error should suggest the fix
}
```

### Testing incremental updates

```rust
#[test]
fn incremental_update_detects_file_change() {
    let dir = tempdir().unwrap();

    // Write initial file
    std::fs::write(dir.path().join("test.ts"), "function foo() {}").unwrap();

    // Build initial state
    Command::cargo_bin("mytool").unwrap()
        .args(["init"]).current_dir(dir.path())
        .assert().success();

    // Modify file
    std::fs::write(dir.path().join("test.ts"), "function foo() {} function bar() {}").unwrap();

    // Re-process
    Command::cargo_bin("mytool").unwrap()
        .args(["update"]).current_dir(dir.path())
        .assert().success()
        .stderr(contains("1 files changed"));

    // Verify new content is available
    Command::cargo_bin("mytool").unwrap()
        .args(["show", "bar"]).current_dir(dir.path())
        .assert().success();
}
```

## Running Tests

```bash
# All tests
cargo test

# Specific test file
cargo test --test test_show

# Specific test by name
cargo test show_displays_name

# With output (useful for debugging)
cargo test -- --nocapture

# Snapshot review
cargo insta review

# Integration tests only
cargo test --test '*'

# Unit tests only
cargo test --lib
```

## Key Dependencies

| Crate | Purpose |
|-------|---------|
| `insta` | Snapshot testing — output format is a contract |
| `tempfile` | Isolated temp directories for filesystem tests |
| `assert_cmd` | Run the binary and assert on output/exit code |
| `predicates` | Flexible assertions on stdout/stderr content |
| `serde_json` | Validate JSON output in integration tests |
