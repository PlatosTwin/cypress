# `verify_test_log.sh` bound the first filename to `max-age-minutes`, silently unchecking that file and disabling the freshness guard

**Found:** 2026-08-03, while certifying the zero-warning line for the #202 waiter change.
**Class:** false green in the tooling that exists to prevent false greens.

## What happened

The command was

```
Tools/verify_test_log.sh --warnings <log> A.swift B.swift C.swift D.swift E.swift
```

and it answered

```
VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=412 files-checked=4
```

Five files named, four checked, and the line said `OK`. The discrepancy was visible only because
the count is printed — nothing failed, nothing warned.

## Why

The interface is `verify_test_log.sh [--warnings] <log> [max-age-minutes] [file…]`, and the age is
**positional**. `A.swift` therefore became `MAX_AGE_MIN`, and `shift 2` dropped it from the file
list. Two independent guards failed at once, both silently:

1. **The named file went unchecked** while the E203 certification still reported OK. E203 exists to
   refuse a warning count from a build that did not compile the files being claimed about — here it
   was simply never asked about one of them.

2. **The freshness guard was switched off entirely.** It ran

   ```
   find "$LOG" -mmin +"A.swift" 2>/dev/null
   ```

   which errors, has its stderr discarded, and returns nothing. Empty output is the same shape as
   "this log is not stale", so the check passed vacuously. That guard exists because a stale log at
   a reused path once reported a clean suite from an eight-hour-old run — the precise failure it
   was, at that moment, no longer able to catch.

There is no way to know how many past certifications used this argument order. Any judgment made
with `verify_test_log.sh <log> <file…>` and no explicit age checked one fewer file than it named
and did not test the log's age at all.

## Fix

- The age is now told from a path **by shape, not by position**: an age is all digits and a path
  never is. Every non-numeric argument after the log is a file. There is no longer an argument
  order that quietly checks less than it was asked to, and no caller has to remember one.
- `find`'s failure is now fatal. An empty result from a `find` that never ran is no longer read as
  a fresh log.

## Proved

Against the same build log, after the fix:

- five files named, `files-checked=5`;
- `<log> 600 A.swift` still parses 600 as the age (`files-checked=1`);
- a file with no `SwiftCompile` task → `VERIFY-FAIL … (E203)`;
- a log back-dated to 2025 → `VERIFY-FAIL: log is older than 60m`.

## The general lesson

Both halves failed by *discarding evidence of their own failure* — one by dropping an argument, one
by discarding stderr. A guard that cannot distinguish "I checked and found nothing" from "I did not
run" is not a guard. Prefer a shape test over a positional one, and never let a check's own error
be the thing that makes it pass.
