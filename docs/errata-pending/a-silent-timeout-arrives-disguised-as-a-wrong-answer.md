# A silent timeout arrives disguised as a wrong answer

**Found:** 2026-08-03, on CI run 30850154829 (main, `d14d43b`).
**Class:** a red that named the wrong defect eleven times.

## What it looked like

The unit suite failed with eighteen issues across three suites, and every one of them read like a
logic defect in the map's search:

```
speciesIDs → nil → nil
(before → 0) > 0
(rows.count → 0) >= 2
rows.contains { $0.commonName == "Monterey Cypress" }
“cypress” left the model at .off
```

Eleven separate tests, three separate suites, all claiming the search narrowed to nothing.

## What it was

A slow machine. The previous run — run 30846300488, commit `017e0d7` — was **green on a tree that
differed by five lines of workflow YAML and not one byte of Swift**. That is as clean a control as
this project has ever had for an intermittent, and it says the code was never in question.

The red runner took **327s** over the same 1137 unit tests the green runner finished in **233s**,
and 1926s vs 1701s on the UI suite. No `SQLITE_IOERR`, no fd storm, nothing in the log but slower
wall clock. All three suites poll a `waitUntil` with a fixed **20-second** ceiling against the
debounce-plus-query path over the 103 MB seed, and on that runner 20 seconds was not enough.

## Why it cost so much to diagnose

Two of the three waiters **returned silently** when the ceiling ran out:

```swift
while ContinuousClock.now < deadline {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(50))
}
// ← falls out here and returns, saying nothing
```

So a timeout never reported itself. It reported as whatever assertion happened to run next, against
a model that had simply not finished. `speciesIDs → nil` is a true statement about a model that was
still working; it is not the failure, it is the shadow of the failure.

The third waiter did assert, but from inside the helper — so every one of that suite's timeouts
pointed at `MapSuggestionTests.swift:355`, the same line, regardless of which of its four call sites
had been waiting.

**Nothing in eighteen issues contained the word "timeout".**

## Fix

`CypressTests/TestWait.swift`: one ceiling, one reporter.

- The ceiling is **90s**, and it is a *liveness bound, not an assertion*. No test here claims how
  fast search settles — the debounces are tuned for a thumb, and a test that pinned them would fail
  the day they were retuned. It costs nothing when a test passes: the waiter returns on the poll
  that sees the condition, never on the deadline.
- Every waiter now records `the model never settled: waited <elapsed>` before the downstream
  assertion can misreport, and threads `#_sourceLocation` so the issue names **the waiting test's
  line**, not the helper's.
- `MapEmptyInventoryTests` keeps its own 5s waiter: it drives a fake API with no seed, and was not
  among the failures.

Red-proved by forcing the ceiling to 1 ms: the suite goes red with
`the model never settled: waited 0.085413625 seconds` at `MapSearchTests.swift:423`, ahead of the
`.off` assertion that used to be the only thing anyone saw.

## What this does not settle

One sample cannot distinguish *"needed more than 20 seconds"* from *"would never have settled on
that runner"*. If a wait ever times out at 90 seconds, believe the message and not the ceiling: the
next question is whether the model settles at all, not whether the number should go up again.

## The general rule

**A guard that stays quiet when it fires is worse than no guard**, because it moves the blame to
the innocent line downstream. Any waiter, retry or poll loop in this codebase must say so when it
gives up — and must say it at the caller's line, or a suite with four call sites reports one.

_Verified 2026-08-03: a docs-only commit under the graphify hook triggers no deploy._
