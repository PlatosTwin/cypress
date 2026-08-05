## The almanac now reloads on a grant while it is open — and E155's own fix was the thing over-reloading it (task #223, closing E123's "left as-is")

E123 recorded, under "one known limitation, left as-is," that granting location while standing on
the almanac would not reactively reload it — the reader would see the filled screen only on the
next navigation. E155 (task #99) closed the adjacent "permanently blank" defect and, as a side
effect, also closed this one: `AlmanacView`'s `.task(id: coordinate)` re-runs `AlmanacModel.update(
coordinate:)` whenever the coordinate parameter changes, and a grant is one such change. So by the
time this ticket started, **E123's literal reproduction no longer reproduced** — the premise as
written was already false, and the first half of this round was confirming that rather than
fixing it.

### What E155's mechanism actually does, that E123 never claimed

`.task(id: coordinate)` fires on *any* different `Coordinate?`, not only on the nil → fix
transition. `MapLocationProvider` republishes `availability` on every fix CoreLocation judges worth
delivering — five meters of walking apart (`MapLocationProvider.publishDistanceM`) or a one-meter
accuracy change (`publishAccuracyM`) — and each one is a different `Coordinate`, so each one re-ran
`AlmanacModel.load()` and re-hit `CypressAPI.almanac(near:)`. Nobody had measured this before: E155's
own test suite (`AlmanacLateFixTests`) only ever drives a *single* nil → fix transition, so the
re-read-every-five-meters behavior was invisible to it. This round's `AlmanacLocationTransitionTests`
demonstrates it directly (see the second red-proof below) before fixing it.

### What changed

`AlmanacModel` now optionally holds the `MapLocationProvider` it was constructed against
(`location:`, defaulted `nil` so every existing unit test and preview is unaffected) and, when one is
supplied, follows it itself via `observeLocation()` — a poll loop in the shape
`VisitIdentifyModel.run()` already uses for the same kind of question, chosen over
`withObservationTracking`'s continuation recipe specifically because a continuation left unresumed
when its owning `Task` is cancelled does not resume itself and would leak the wait; `Task.sleep`
cancels cleanly. `AlmanacModel.isFixAvailabilityTransition(from:to:)` is the pure, `static` predicate
that decides whether a given `Availability` change is a fix boundary being crossed (coordinate
nil-ness flipping, in either direction) — the only kind of change this screen now reloads for.
`.located(A) → .located(B)` is deliberately `false`, even though `A != B`: neither side is a fix the
reader did not already have. `AlmanacView`'s original `.task(id: coordinate)` remains, gated to only
run when no `location` is supplied, so every caller that drives the view by coordinate alone (tests,
previews, and any future one) is unchanged.

`JournalTabView` and both `RootView` call sites (`.journal` tab root and the currently-uncalled
`.almanac` route) now thread the shared `MapLocationProvider` down alongside the coordinate they
already passed.

### Premises checked against the code

- **E123's own text, "granting location while standing on the almanac would not reactively reload
  it,"** was already false at the current base — refuted above, not assumed.
- **The ticket's warning about "no reload loops"** was not hypothetical: `.task(id: coordinate)`
  alone, still active in production wiring, would have kept reloading on every walking-distance GPS
  update. `AlmanacLocationTransitionTests.driftDoesNotReload` red-proves this was a real gap, not a
  defensive test against a bug that could not occur.
