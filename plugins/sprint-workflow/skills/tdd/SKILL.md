---
name: tdd
description: Test-driven development loop — red, green, refactor. Use this skill when implementing any feature with clear acceptance criteria, when fixing bugs (regression test first), and inside /sprint-start Phase 1 + Phase 2. Defines cycle length, when NOT to TDD, and integration with sprint quality gates.
version: 1.0.0
---

# Test-Driven Development

The discipline of writing the test **before** the implementation. The test defines what success looks like and prevents over-engineering. The implementation is then the smallest change that makes the test pass.

This skill is read by `test-writer` (always) and by `backend-dev` / `frontend-dev` when a task's acceptance criteria are well-defined enough to test first.

---

## When to TDD

| Task type | TDD? | Rationale |
|---|---|---|
| Pure logic (calculations, parsing, state machines) | **Yes** | Tests are cheap, behaviour is precise |
| API endpoints with defined request/response | **Yes** | Spec tells you the test |
| Bug fixes | **Yes — always** | Regression test must fail without the fix |
| MediatR command/query handlers | **Yes** | Inputs and outputs are explicit |
| React components with defined props/output | **Yes** | Testing-Library makes this fast |
| Pure UI styling, layout, animation | **No** | Visual regression / Playwright instead |
| Exploratory spikes / prototypes | **No** | Throwaway code; tests slow exploration |
| Generated code (migrations, scaffolds) | **No** | Test the migration, not the generator |
| Pure plumbing (DI registration, wiring) | **No** | Integration tests cover this |

When in doubt, TDD. The cost of writing a test first is low; the cost of over-engineered untested code is high.

---

## The Loop

### Red — write a failing test

1. Read the acceptance criterion you're implementing. Pick **one** behaviour.
2. Write a test that asserts the behaviour. The test must:
   - Reference the function / endpoint / component you're about to write (it doesn't exist yet, or doesn't behave correctly yet)
   - Have a clear assertion (one concept per test — see `code-standards`)
   - Use the project's existing test framework and patterns
3. Run the test. Confirm it fails. **Read the failure message** — it must fail for the right reason (not "import error", "syntax error", "fixture not found"). If it fails for the wrong reason, fix that first.

A test that fails for the wrong reason is not a red test.

### Green — make it pass

1. Write the **smallest** code change that makes the test pass.
2. No extra features. No "while I'm here" fixes. No defensive code for cases the test doesn't cover.
3. Run the test. Confirm it passes.
4. Run the full test suite for the affected area. Confirm nothing else broke.

If you can't make it pass with a small change, the test was probably wrong. Stop and rewrite the test before the implementation.

### Refactor — clean up

With the test as a safety net:

1. Rename anything unclear
2. Extract obvious duplication
3. Improve naming, ordering, formatting
4. Run the tests after every refactor — they must stay green

Refactoring without tests is editing. Refactoring with tests is safe.

---

## Cycle Length

A red-green-refactor cycle should take **minutes, not hours**.

- If a single test takes more than 30 minutes to make pass, the test is probably testing too much. Split it.
- If you've been writing implementation for an hour without seeing green, you've left the loop. Stop, get back to a passing state (revert if needed), and write a smaller test.

Small cycles compound. Long cycles produce untested code with the test added at the end as theatre.

---

## Bug Fixes (Mandatory TDD)

For any bug fix:

1. Write a regression test that **reproduces the bug**
2. Run it. Confirm it fails — and fails with the same symptom the user reported
3. Apply the fix from the `diagnose` skill
4. Run the regression test. Confirm it passes.
5. Run the full suite. Confirm no other test broke.

The regression test is the artifact that prevents the bug from recurring. A bug fix without one is incomplete.

---

## Anti-Patterns

| Anti-pattern | Better |
|---|---|
| Writing 10 tests, then 10 implementations | One test, one implementation, one cycle |
| Asserting "no exception thrown" with no behaviour check | Assert the actual outcome (return value, side effect, state) |
| Testing the test framework or language internals | Test your code's behaviour |
| Mocking everything until the test asserts nothing real | Mock external boundaries only (DB, HTTP, time); use the real thing for internal collaborators |
| Writing the test after the implementation, then claiming TDD | Order matters. The test must fail before the code is written. |
| Skipping refactor because "tests pass, ship it" | Tests are the licence to refactor; using them to avoid refactoring is waste |
| TDD-ing UI styling | Use visual regression / Playwright; TDD doesn't fit pixel-level work |

---

## Integration with Sprint Workflow

### Phase 1: Implementation

When acceptance criteria are testable and the task is on the TDD list above:

- The implementing agent (`backend-dev` / `frontend-dev`) writes the test first, then the implementation
- The agent commits red and green together (or as a single logical unit) — not in separate commits, since the red test is incomplete

### Phase 2: Test Writer

`test-writer` augments TDD tests with:

- Edge cases not covered by the AC tests (empty collections, boundary values, error paths)
- Integration tests across module boundaries
- Snapshot tests where output format is a contract

`test-writer` does not duplicate the AC tests — it fills the gaps.

### Phase 3: QA

`qa-agent` (or Codex adversarial review) verifies:

- Every acceptance criterion has at least one test asserting it
- Bug fixes have regression tests
- Tests fail without the implementation (spot-check by reverting one change and running the test)

A task that passes all builds but has no test for its AC fails QA.

---

## Per-Stack Notes

The TDD loop is the same. The mechanics differ:

- **.NET (xUnit)**: `[Fact]`/`[Theory]`, in-memory `DbContext`, `Moq` for boundaries. See `dotnet-api`.
- **React (Vitest)**: `@testing-library/react`, `userEvent` for interactions, `vi.fn()` for mocks. See `react-typescript`.
- **Rust**: `#[test]` for unit, `tests/` for integration, `insta` for snapshots, `tempdir` for filesystem. See `rust-testing`.
- **API endpoints**: contract test via the response wrapper / status code / RFC 7807 shape. See `api-design`.

Read the relevant per-stack skill before writing the first test.
