---
name: diagnose
description: Disciplined bug diagnosis loop — reproduce, minimize, hypothesize, instrument, fix, verify. Use this skill before attempting to fix any non-trivial bug, during Phase 4 fix loops, and inside /sprint-bug-triage. Prevents the "fix the symptom, miss the cause" failure mode.
version: 1.0.0
---

# Diagnose

A disciplined loop for diagnosing bugs. The goal is to **understand the cause before changing code**. Skipping steps produces fragile fixes that paper over symptoms — they pass review, ship, and recur.

This skill is read by `qa-agent`, `backend-dev`, `frontend-dev` when a task involves debugging, by the `/sprint-bug-triage` command, and by the Phase 4 fix loop in `/sprint-start`.

---

## When to Use This Skill

Use it for:
- Any bug whose cause is not obvious from a 30-second read
- Flaky tests
- Phase 3 QA failures where the BLOCKING issue is "wrong behaviour" rather than a lint/type error
- Production incidents
- Any time you catch yourself about to "try something and see"

Skip it for:
- Lint errors, type errors, missing imports — these have one obvious fix
- Bugs where the stack trace points directly at a single line you wrote in the last 5 minutes
- Surgical fixes routed to Codex (the eligibility criteria already require an obvious fix)

---

## The Loop

### 1. Reproduce

**Do not write code until you can reproduce the bug reliably.**

Goals:
- A reliable repro (works every time, not "sometimes")
- Recorded inputs, environment, and expected vs actual output
- The minimum number of steps to trigger it

Tactics:
- Capture exact inputs (request body, file contents, command line, click sequence)
- Note environment: branch, commit, OS, runtime version, env vars, feature flags
- For UI bugs: record screenshot, console log, network tab, and exact click sequence
- For flaky tests: run them N times (`for i in {1..50}; do cargo test foo; done`) until you see the failure rate

If you cannot reliably reproduce, **stop**. Either get more information from the user (logs, repro steps, screenshots) or set up instrumentation (add logging, capture state) and wait for it to happen again. Guessing at fixes for unreproducible bugs is the fastest way to make things worse.

### 2. Minimize

Strip the reproduction down to the smallest possible case.

- Remove unrelated code, data, dependencies
- Replace complex inputs with the simplest input that still triggers the bug
- For test failures, isolate the smallest test that fails
- For UI bugs, identify which prop/state combination triggers it

A minimal repro is its own diagnosis: when you can't strip something away, that something is involved in the bug.

### 3. Hypothesize

List candidate causes, ranked by likelihood. **Write them down.**

- "The cache is returning stale data" — likelihood high, easy to test
- "The auth middleware is rejecting the request silently" — likelihood medium
- "There's a race condition in the listener" — likelihood low, hard to test

Write the hypotheses before instrumenting — otherwise you'll confirm whatever you're already looking at.

### 4. Instrument

For the top hypothesis, add **just enough** instrumentation to confirm or refute it.

- Logs at the suspected boundary
- Asserts that fail loudly if invariants are violated
- Breakpoints with conditional triggers
- Snapshot the relevant state at key points

Run the minimal repro. Read the output **before** changing code.

If the instrumentation refutes the hypothesis, move to the next one. If it confirms, you have the cause — proceed to fix.

### 5. Fix

The fix is the smallest change that resolves the cause you confirmed in step 4.

- Do not refactor at the same time
- Do not "while I'm here" fix unrelated issues
- Do not change patterns or interfaces unless the bug requires it
- If the fix touches multiple files, the bug was probably architectural — escalate to a Claude agent rather than routing to Codex

### 6. Verify

- Run the original reliable repro from step 1 — it must now pass
- Run the minimized repro from step 2 — it must pass
- Add a regression test (per `Test Quality` rules in CLAUDE.md). The regression test must fail without the fix and pass with it.
- Run the full test suite for the affected area
- For UI fixes: re-run the click sequence in a real browser

A bug fix without a regression test is a recurring bug.

### 7. Remove Instrumentation

Delete logs, asserts, and debug prints added in step 4. Keep only instrumentation that improves observability long-term.

---

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| Editing code before reproducing | You'll fix something unrelated and convince yourself the bug is gone |
| "Try a thing and re-run" loop | Each attempt teaches nothing; you'll burn an hour without converging |
| Refactoring during diagnosis | Mixes the fix with unrelated changes; review can't tell what fixed what |
| Skipping the regression test | The same bug ships again next sprint |
| Wrapping in try/catch to make the symptom disappear | The cause is still there; now it's silent |
| Adding a fallback that hides the failure | The user sees stale data instead of an error; worse than failing loudly |
| Diagnosing two bugs at once | Each masks the other's symptoms; fix them one at a time |

---

## Reporting Format

When the orchestrator or `/sprint-bug-triage` asks for a diagnosis, return this:

```
## Diagnosis: <one-line bug summary>

### Reproduction
- Steps: <numbered list>
- Frequency: <every time / N% of runs>
- Environment: <branch, commit, runtime>

### Minimal Repro
<smallest possible case>

### Hypotheses Considered
| # | Hypothesis | Result |
|---|-----------|--------|
| 1 | ...        | confirmed / refuted by <evidence> |

### Root Cause
<one paragraph — the actual cause, not the symptom>

### Proposed Fix
- Files: <paths>
- Change: <one sentence>
- Risk: <low/medium/high — what else this could affect>

### Regression Test Plan
- File: <test path>
- Asserts: <what must be true post-fix>
```

---

## Integration with Sprint Workflow

- **`/sprint-bug-triage`** — every reviewer agent reads this skill before reporting findings, so bug reports come back with a hypothesis (not just "this looks wrong")
- **Phase 4 fix loop in `/sprint-start`** — agents handed a BLOCKING issue must produce at least the Reproduction + Root Cause sections before proposing a fix
- **`qa-agent`** — when validating a bug-fix task, verify the regression test exists and fails without the fix

If a fix is proposed without a confirmed root cause, reject it and require a diagnosis first.
