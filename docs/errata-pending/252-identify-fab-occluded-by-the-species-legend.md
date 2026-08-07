### The identify FAB's flaky AX5 guard was reporting a real occlusion badly: the species legend is drawn over it, and `isHittable` routes around an occlusion it can find one free point in (task #252)

#### The premise this started from, and why it was wrong

PR #51 added `CypressUITests/IdentifyFABReachabilityTests` and it was intermittent: six runs at the
same commit, four green and two red, across an iPhone 16 Plus (430 pt) and an iPhone 16 Pro (402 pt).
The failing runs said

    … is in the accessibility tree but never became hittable within 30s — it is present and
    cannot be activated

while `MapRecenterUITests.testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied`
passed in the same suite run, on the same device, in the same AX5 + location-denied state. A
30-sample poll of the control's own `isHittable` printed `hit=true` at every sample with an
identical frame, and that run passed.

From that the standing hypothesis was that this is **not** an app layout defect — the frame is
stable and correct, the assertion is not reliably observing it — and that the cause is the several
hundred `MKAnnotationView`s the FAB's 364 pt pill overlays, in the documented family of E202/E216
pin-geometry failures.

**Both halves are wrong.** The frame was stable, and it was not correct. There is no annotation
involved.

#### What the screen actually looked like

Screen 01, AX5, `CYPRESS_LOCATION=denied`, iPhone 16 Pro, at `origin/main` `d84b7fc`:

| element | frame |
|---|---|
| filter chip row | `(16, 158.33, 370, 59.67)` → bottom `218` |
| species legend | `(16, 230, 344.33, 262.67)` → bottom **`492.67`** |
| — its `Southern Magnolia` row | `(16, 365.33, 340.33, 59.67)` |
| recenter control | `(342.33, 315, 44, 44)` |
| **identify FAB** | `(22, 371, 364.33, 83)` |

The legend's rectangle contains the recenter control entirely and contains all but the bottom 14 pt
of the FAB. `MapHomeView.chrome` applies the bottom block first *so that the top block draws over
it* — a deliberate ordering with its own note in that file — so this is not two rectangles sharing
an area, it is the FAB **covered**. A screenshot of the running app shows the words `What tree is
this?` behind an opaque `Southern Magnolia` legend chip, with only a `?` visible past its right
edge. The same screenshot on an iPhone 16 Plus (430 pt) shows the same overlap.

The one element that *did* overlap the FAB's own activation point in the accessibility dump was that
legend row — a `button`, ahead of the FAB in tree order. The `AnnotationContainer` MapKit publishes
is full-screen and `hittable=false`, and after the fix a tree pin (`City tree, Chinese Elm`,
`hittable=false`) sits directly under the FAB's centre with the FAB reporting `hittable=true`. The
annotations are behind the chrome and were never the mechanism.

#### Why the guard was intermittent rather than red

XCUITest resolves `isHittable` by hit-testing the element's activation point and then, when that
resolves to something that is not the element or a descendant, points sampled inside the element's
frame. A control covered everywhere except a 14 pt band therefore reports **reachable exactly when
the sampling happens to find the band**. The green runs were the luck. That is the whole of the
intermittency, and it explains every row of the tally without needing `camera-trees`, the device
width, or the volume of prior accessibility querying to explain anything:

- the failures clustered on runs with more prior AX traffic because more traffic is more chances,
  not because traffic degrades anything;
- the 30-sample poll that printed `hit=true` thirty times and then passed was thirty draws that all
  found the band, which is what a heavily-covered but not-quite-fully-covered control does.

**Proved rather than argued.** With the candidate fix below present and then disabled by one line,
everything else identical (`fab2-redproof1.log`), the two geometric assertions go red naming the
legend, and
`testTheFABIsReachableAtAX5WithLocationDenied` — the hittability one — **passes, in 4.6 s**. One run,
same launch, same device: the occlusion is present, the rectangles see it and the hittability check
does not.

#### The defect

`MapLayout.topChromeReservedAX5(topInset:)` is `topInset + searchTopInset + searchBarHeightAX5 +
chipRowTop + chipRowHeightAX5` — the search bar and the filter chip row. Its own doc says it is "the
y-coordinate … of the chip row's own bottom edge", and that is exactly what it is. **The chip row is
not the bottom of the top chrome.** Below it the same `VStack` also stacks the search status line,
the `Needs care` toast (#247), and `MapSpeciesLegend`, whose four chips wrap onto as many lines as
the species names need at the current type size — 262.67 pt of them at AX5. The reservation predicts
216; the block ends at 492.67.

This is #250's defect one child further down the same stack. #250 found the recenter control rising
*behind the chip row*, "present in the tree, `isHittable == false`", and reserved for the two
children a constant can bound. A third constant cannot fix the rest: the legend's height is a
function of how many species the visible camera has coloured (0–4) and how their names wrap, so a
worst case wide enough to be safe would be wrong by 260 pt whenever the legend is small and would
spend the notice's whole budget on a legend that is not there.

#### The fix that was tried, measured, and is **not** in this branch

The obvious repair is to stop reserving the chip row's bottom edge and start reserving the top
block's real one. It was built: `MapHomeView` measured that edge in a named coordinate space both
overlays are children of, and `MapLayout.noticeMaxHeight` took a second budget from it, `min` with
the constant path so a `GeometryReader` that had not run yet could not widen anything.

**It works, and it is not reliable, and the difference took four measured attempts to see.**

With it in place the standing occlusion is gone — legend bottom `492.67`, recenter top `504.67`, FAB
`(22, 560.67, 364.33, 83)`, nothing overlapping, screenshotted. Two full `CypressUITests` runs on a
430 pt iPhone 16 Plus were green (96 tests, 0 failures, twice) and one on the 402 pt iPhone 16 Pro
was too. The next 402 pt run was not: the top chrome ended at `492.67` and the bottom chrome began
at `437.0`, which is where it belongs for a **three**-row legend against a legend that had four.
`topChromeBottom` was stale.

A purpose-built diagnostic (`FABLagDiagTests`, sampling `legendBottom` against `recenterTop` every
250 ms for 26 s over repeated launches) turned that into a measurement:

| how the measurement was wired | launches overlapping, of those sampled |
|---|---|
| `.onChange(of: proxy.frame(…).maxY)` in a `.background`, read as `@State` | 1 of 4, for the whole 26 s |
| `PreferenceKey` in a `.background`, read on the ancestor, `@MainActor` hop | 1 of 4, for the whole 26 s |
| same, assigned directly with no hop | 2 of 4 — and they were *different* launches |
| same, read on the block that produces it rather than the ancestor | 1 of 4 |

It is not a lag. The stuck launches were stuck from the first sample to the last and never
converged, while a hand launch of the same build converged correctly within ten seconds — so the
value freezes at whatever the legend's height was on some early layout pass and the later passes,
which certainly happen (the legend visibly grows from two rows to four as the map's palette
arrives), do not reach it. Which launch froze moved when the `@MainActor` hop was removed, which is
the signature of a race rather than a missing invalidation.

**So the branch ships the diagnosis and not the repair.** A layout fix that is right three launches
in four is worse than none: it would close this ticket, and the fourth launch would come back as
somebody else's flaky test.

#### What the next attempt should probably do, and what it should not

**Not another measurement fed back through `@State`.** Four wirings of it were tried above. The
shape is a feedback loop — top block's height → notice's budget → bottom block's position — resolved
across two sibling `.overlay`s, and SwiftUI is under no obligation to run it to a fixed point on any
particular pass.

**A constant is available and it is the file's own idiom, with one real cost.** `searchBarHeightAX5`
and `chipRowHeightAX5` are both AX5 *bounds* guarded by `AX5ReflowTests`; a `legendReservedAX5`
measured the same way (four chips, the widest palette, through `ax5Size`) would need no measurement
at run time and could not go stale. The cost is that it must be reserved unconditionally, as the
other three are, and 262 pt of unconditional reservation would put the notice into a scroll at
*ordinary* type sizes, where it is nowhere near its budget today. Gating it on
`dynamicTypeSize.isAccessibilitySize` avoids that and buys a cliff at the AX1 boundary instead —
which is the same bargain `bottomSlotReservedAboveAX5` already makes, and is a judgement rather than
a fact.

**Or the two blocks stop being two overlays.** One `VStack { topBlock; Spacer(minLength:
chipRowTop); bottomBlock }` inside the same `Color.clear` has no feedback to resolve: the notice's
`ScrollView` is the compressible member and SwiftUI compresses it in the same pass, with no state,
no measurement and no staleness. This is the structurally correct answer. It also changes a decision
that was made deliberately — `MapHomeView.chrome`'s note on the block ordering, and R25/#143's
reading order — because the suggestion list would then push the bottom chrome instead of drawing
over it. That is a product call, not a refactor.

**While the arithmetic is being touched, one bug in it is worth carrying forward.** The existing
`noticeMaxHeight` mixes coordinate spaces: `availableHeight` is `GeometryReader`'s `size.height`
(the safe area, 781 pt on this device) while `topChromeReservedAX5` counts from the top of the
screen, because `topInset` is one of its terms. It has been ~93 pt conservative on a notched phone
the whole time. Harmless while the number subtracted was 216; it collapsed the notice to **16 pt**
the first time a measured 492 was subtracted from the wrong one of the two, which is how it was
found. The screen height is reconstructible with no measurement at all, as
`availableHeight + topInset + proxy.safeAreaInsets.bottom`.

#### Also true, and not fixed here

`MapTreeCard` occupies the same bottom slot and is **not** given `noticeMaxHeight` — only the four
`MapLocationNotice` arms are. A tall enough card at AX5 would push the same stack up in the same way.
It was not reachable in this ticket's state (the card and the standing notice are different arms of
the same `switch`) and it is not guarded.

#### The guard exists and is not in this branch either, for the same reason

`IdentifyFABReachabilityTests` was written, red-proved four ways, and removed before this branch was
opened. It is at commit `89f5001`/`5a2112f` and should be resurrected the moment screen 01 passes
it. What it asserts, and the proofs:

| assertion | red-proved by | the failure it produced |
|---|---|---|
| the FAB is reachable at AX5 | `IdentifyFAB.offset(x: 2000)` | *"is in the accessibility tree but never became hittable within 30s"* |
| the FAB's frame clears the species legend | the candidate fix disabled by one line | *"the identify control (22.0, 371.0, 364.33, 83.0) overlaps the species legend (16.0, 230.0, 344.33, 262.67)"* |
| the FAB's frame clears the recenter control | `locateToFabGap` → `-10` | *"the identify control (22.0, 560.67, …) overlaps the recenter control (342.33, 526.67, 44, 44)"* |
| the top chrome's bottom edge is above the bottom chrome's top edge | the candidate fix disabled | *"the top chrome ends at y 492.67 and the bottom chrome begins at y 315.0"* |

(`.allowsHitTesting(false)` does **not** make an element unhittable to XCUITest — confirmed
independently by PR #51's review, and the reason the first proof uses an offset.)

It **drops** PR #51's chip-row assertion. With the legend present, the legend's rectangle lies
strictly between the FAB and the chip row (chip row `y 158.33–218`, legend `y 230–492.67`), so that
assertion can never be the one that fires; and it cannot be red-proved for its own reason either,
because the 430 pt lift needed to put the FAB on the chip row puts the chip row *over* the FAB and
the run then dies on the FAB's own hittability. An assertion that cannot be driven red is not a
guard. PR #51's review had already flagged the same assertion as dominated, on weaker grounds.

#### The same mistake again, one layer down: the guard measured through a hittability gate

Worth carrying to whoever picks this up, because it cost a full-suite run to find. The guard's first
version read every frame with `settledFrame`, which waits for the element to be **hittable** before
reporting its frame. That is right for its eleven existing callers — they read a frame in order to
touch something — and it is wrong for a guard against occlusion, for the reason this whole entry is
about. A full-suite run on a loaded machine (`fab2-full-16pro-2.log`, 96 tests, 1 failure) reported:

    testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied :
    the recenter control (“Center the map on you”) is in the accessibility tree but never
    became hittable within 30s

— one XCUITest button query in that test took **20 seconds** (`t = 7.08s` → `t = 27.03s`, three other
agents building on the machine) — where the two rectangles the test was about to compare were
readable throughout. The guard against occlusion had made itself depend on the thing an occlusion
removes.

The repair, also at `5a2112f`: `settledFrame` gains `requireHittable:`, default `true` so all eleven
existing callers are untouched, and the geometric reads pass `false`. Nothing is weakened, because
the claim changes with it — "these two rectangles do not intersect" is a different sentence from "a
reader can press this", and the second is asserted on its own, once, where a 30 s wait is the point.
The very next run proved the change: the same test failed again and this time printed
`492.67 > 437.0`, which is the number that identified the stale measurement above. It is not in this
branch only because its one caller is not.

#### The rule worth keeping

**A hittability check is not an occlusion check.** `isHittable` is allowed to route around an
obstruction, and it will, which makes it a poor witness for exactly the defect it looks like it is
testing. Where the claim is "nothing is on top of this control", assert the rectangles. Where the
claim is "a finger can land on it", assert hittability — and understand that a green answer to the
second is not an answer to the first.

The corollary is the one this cost a night: **an intermittent UI test is a hypothesis about the
test, not a finding.** Four green runs out of six looked like a flaky assertion and were a
three-in-four chance of missing a defect that was on the screen the whole time, visible in a
screenshot nobody had taken.
