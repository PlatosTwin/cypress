### the almanac went permanently blank if it was opened before the fix arrived (#99)

Screen 12 has one input that is not the database: a coordinate. Everything on it — the pill, the
three season rows, the composition card, the vacant-site count, the coverage ask — hangs off
resolving a neighbourhood from that coordinate, and `LocalAPI.almanac(near:)` answers `.empty` for a
`nil` one, which is right: without a fix there is no area and the almanac has no subject (A4, E44).

`AlmanacView` built its model in a `@State` initialiser. `@State` runs its initialiser exactly once
for the lifetime of the view's identity, so the coordinate the almanac was derived from was whichever
one existed in the first frame, permanently. On a cold launch that is `nil` — the composition root's
`MapLocationProvider` is inert until screen 01 asks it to start, and CoreLocation then takes its own
time. The almanac read `almanac(near: nil)`, got `.empty`, and stopped.

That much was known. E123 recorded it, under "one known limitation, left as-is": granting location
while standing on the almanac would not reload it, "and the prompt is honest either way… the reader
reaches the filled screen by the next navigation".

**The second half of that sentence is false, and this is the case that disproves it.**
`showsLocationPrompt` was `coordinate == nil` computed in the same initialiser — but as a plain `let`
on a struct, which SwiftUI recomputes on every pass the parent makes through its body, unlike the
`@State` beside it. The two therefore came apart the instant the fix landed: the model still held the
empty almanac it had read from `nil`, and the prompt that explained it evaluated to `false` and
disappeared. What the reader is left with is a header with no pill, a footnote, and eleven hundred
points of nothing, until the view is torn down and rebuilt.

So the prompt is not honest either way. It is honest for about a second, and then it removes itself
from precisely the screen that most needs it. This is the state E126 built screen 12's failure
sentence for — "a screen that draws its five blocks away and leaves a footnote is reporting a quiet
neighbourhood" — and it walks past both of that entry's guards, because the read did not fail
(`hasFailed` is correctly `false`) and the coordinate is no longer `nil`.

It is reachable in the shipping app: cold launch, tap `Journal`, tap `Neighborhood` before the fix
lands. Indoors on a real phone that window is seconds. Through the DEBUG `CYPRESS_SCREEN=journal`
deep link it happens every single time — `RootView` opens the link from a `.task`, which runs after
the first frame, so screen 01 mounts, `MapHomeView.task` calls `start()`, and the router then swaps
in the journal tab well before the provider has published anything. That is how it was found (E153),
and it is the reliable reproduction.

**The invariant, restated, because the fix is shaped by it rather than by the symptom.** A screen
with nothing on it must always say why. Not "must eventually say why", and not "must say why at the
moment it becomes empty" — at *every* moment, an empty screen 12 carries either the prompt or the
failure sentence.

**What changed.** Two things, and the second is the one that holds the invariant.

1. `AlmanacModel.coordinate` is a `var` the model can be told about again, and `AlmanacView` reads
   with `.task(id: coordinate)` rather than a bare `.task`. A bare `.task` runs once at mount, which
   is the same once-only the `@State` initialiser has, so it would have moved the bug rather than
   fixed it. Keyed on the coordinate, the read re-runs when — and only when — the fix changes.
   `AlmanacModel.update(coordinate:)` is the entry point and returns without a read when the value
   has not moved, so a provider republishing the same fix does not re-read the whole almanac.

2. **The prompt is decided by the coordinate the picture on screen was derived from, not by the one
   the parent is holding.** `AlmanacModel` keeps `displayedCoordinate` alongside `coordinate`; they
   differ for exactly as long as a re-read is in flight, and `needsLocation` — which `AlmanacView`
   now hands to `AlmanacScreen` in place of E123's view-layer `let` — reads the first. The re-read
   also deliberately does **not** reset the phase to `.loading`: the empty almanac and its prompt
   stay on the glass until the replacement has actually been read. Without that pairing the fix
   would still leave a window, one database read wide, in which the prompt has gone and the
   neighbourhood has not arrived — the same blank, made brief instead of made impossible.

A read that is superseded by a newer fix while it is in flight drops its own answer rather than
writing it. Two fixes in quick succession is ordinary on a phone that is still settling, and the
stale one landing last would put a neighbourhood on screen that `displayedCoordinate` no longer
describes — which would break the invariant in the other direction, by making the prompt's condition
answer for a picture nobody is looking at.

**Where E123 went wrong, precisely.** Not in showing the prompt — that ruling stands and the copy is
unchanged. It went wrong in the sentence "because it is a view decision rather than a derived value,
it carries no presentation test; it was verified by **looking**". The looking was done on a device
whose fix was already settled, where `coordinate == nil` is a constant for the whole life of the
screen and the view-layer computation is indistinguishable from the right one. The condition is a
statement about the *state on screen*, and a statement about the state on screen belongs with the
thing that owns the state. E123 put it one layer above, where it is recomputed on a different
schedule from the thing it describes — and a condition that updates on a different schedule from its
subject is not a condition, it is a race that happens to usually win.

**Verification.** `AlmanacLateFixTests`. The model half asserts the sequence rather than the values,
because every individual value was already correct on the broken app: `almanac(near: nil)` is
`.empty` and should be, `coordinate == nil` was `false` and should have been, nothing failed. What is
only true on the fixed app is that a second coordinate is read at all, and that the prompt outlives
the read that replaces it. The mid-read assertion needs the read held open — a guessed sleep would
make the test's subject a timing assumption instead of the ordering it is about — so `Held` parks
inside `almanac(near:)` on two latches until the test lets it go, and the half-way state is looked at
rather than raced against.

The render half is the end-to-end statement, and it is the one that would have caught this without
knowing where to look: screen 12 rendered through a host whose coordinate is `nil` at mount and
becomes a fix after the first pass, against the same host with the fix there from the start, asserted
**equal**. A fix that arrives late must leave the reader looking at the same screen as a fix that was
always there; the blank, the prompt still standing, and a half-drawn column are all different
pictures. It is driven through `AlmanacView` rather than by handing `AlmanacScreen` a flag, for the
reason E126 gives about its own render test — the wiring between the model and the screen is half of
what was broken. The control render proves the harness byte-stable first, without which an equality
assertion is as void as an inequality one.

Each test was made to fail on purpose before it was believed. Deleting the `guard` from
`update(coordinate:)` so the coordinate is taken but the read is never re-run reddens the model tests
at the second coordinate and reddens the render comparison with unequal PNGs; restoring
`needsLocation` to E123's `coordinate == nil` leaves the plain re-read tests green and reddens
exactly the mid-read assertion, which is the entry's whole point.

And it was looked at, running, on the entrance it was reported from: `CYPRESS_SCREEN=journal` on a
simulator with a fix over San Francisco. Before, screen 12 is a bare `Almanac` header and a footnote
and stays that way; after, it draws Western Addition with its season rows, its composition card, its
vacant sites and its coverage ask.

**One consequence worth stating.** The deep-link entrance to screen 12 is viable again — it now
produces a populated almanac on a simulator with a fix. `AlmanacGroupTapTests` (E153) still reaches
the almanac by the app's own front door, and is left that way deliberately: its subject is the two
counted rows and the screens behind them, not this defect, and the front door is the sequence in
which the app is actually used. Rewriting it to use the deep link would trade a test of the product
for a test of the seam.

**Not addressed here.** Screen 12 still draws nothing while its first read is in flight on a device
that *has* a fix. That is the ordinary loading blank, it is measured in milliseconds against a local
SQLite read, it predates this entry, and it is the same on every screen in the app; giving screen 12
alone a spinner would be a design change, not a repair. It is named so it is a known boundary rather
than an oversight.

The same `@State`-built-from-a-parameter shape exists at four other sites, all of them carrying
`gpsAccuracyM: location.availability.accuracyM` into a once-only model — `CareLogView`,
`CheckInView`, `MeasureView` and `VisitCameraView`. There the snapshot is arguably right (a
contribution should carry the accuracy of the fix it was taken on, not a later better one), but the
cold-launch case is the same: a form opened before the first fix records `nil` accuracy even though a
fix arrives while it is being filled in, and D6 treats a missing accuracy as unusable rather than as
good. Filed, not fixed here.
