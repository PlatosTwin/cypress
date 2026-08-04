# `headingAvailable()` answers for the base class, and answers no on every simulator

**Found:** 2026-08-03, on branch `heading-155` (task #155), iPhone 16 Pro Max simulator
`DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`.
**Class:** a feature that can be fully wired, fully green, and switched off at runtime on every
machine in this repo.

## What it looked like

`MapLocationProvider.startHeading()` was written the way Apple's own snippets are:

```swift
guard CLLocationManager.headingAvailable() else { return }
manager.startUpdatingHeading()
```

The provider takes its `CLLocationManager` by injection — that seam exists precisely so a test can
watch what the provider *does to a manager* — and the test's stub overrode `headingAvailable()` to
answer `true`. The stub was never consulted. The test went red on
`(manager.headingStarts → 0) == 1`.

## What it was

Two facts, and the second is the one that matters off the test bench.

1. **`CLLocationManager.headingAvailable()` names the base class**, so it is dispatched on
   `CLLocationManager` itself. No subclass the provider was handed can answer it. The injected
   manager — the whole point of the seam — is not in the conversation.
2. **The base class answers `false` on a simulator.** There is no magnetometer to report, and
   `simctl` has no way to simulate one (it can set a location; it cannot set a heading). So on every
   device this repo's suites run on, `startUpdatingHeading` is never called, no `CLHeading` is ever
   delivered, and the direction cone can never be drawn.

Written as it was, the guard therefore did two things at once: it made the sensor check
untestable, and it silently disabled the feature everywhere a machine could look at it. A suite
green on that code says the arithmetic is right and says nothing whatsoever about the feature.

## The fix

Ask the manager the provider actually holds:

```swift
guard type(of: manager).headingAvailable() else { return }
```

This is not a change made to serve a test double — it is the more correct call. A type that takes
its manager by injection has no business asking a different object whether the hardware exists.

## What to carry forward

- **A capability check spelled with a class name is not covered by an injection seam.** Anything
  reached as `CLLocationManager.something()`, `UIScreen.main`, `Bundle.main` inside a type that
  takes its dependency by parameter is a second, hidden dependency the seam does not reach.
- **A magnetometer feature cannot be verified below the physical phone.** Not "is hard to" — the
  sensor gate is off, so the code path does not run. Any claim that a heading feature works, made
  from a simulator run, is a claim about code that did not execute.
