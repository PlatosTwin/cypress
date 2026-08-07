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

**Proved rather than argued.** With the fix below reverted by one line and everything else identical
(`fab2-redproof1.log`), the two geometric assertions go red naming the legend, and
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

#### The fix

`MapHomeView` measures the top block's real bottom edge in a named coordinate space both overlays
are children of, and `MapLayout.noticeMaxHeight` takes a second budget from it. The constant path is
unchanged and `min` takes whichever budget is tighter, so a `GeometryReader` that has not run yet
(reporting 0) cannot widen anything.

**The two budgets are computed separately on purpose, and this is the part that bit.** They are in
different coordinate spaces and neither converts to the other from inside `MapLayout`:
`availableHeight` is `GeometryReader`'s `size.height`, which is the safe area (781 pt here);
`topChromeReservedAX5` counts from the top of the *screen*, because `topInset` is one of its terms.
The pair has always been ~93 pt conservative on a notched phone, which was harmless while the number
being subtracted was 216. Subtracting a measured 492 from the wrong one of the two collapsed the
notice to **16 pt** — watched happen, in a first draft that used one formula for both. So the
measured budget is computed entirely in the chrome block's own space, where both terms are real
edges of one rectangle, and the block's height is measured too rather than reconstructed from
`availableHeight` plus insets.

`MapLayout.chipRowTop` (12 pt) is held back between the blocks. Without it they come to rest exactly
edge to edge — the cap and the stack's own layout are the same arithmetic — and a third of a point of
pixel rounding decides whether a non-intersection assertion holds.

Measured after, same device and state: legend bottom `492.67`, recenter top `504.67`, FAB
`(22, 560.67, 364.33, 83)`, nothing overlapping, and the screenshot shows the full `What tree is
this?`.

#### The cost, and the part that is not this ticket's to decide

The notice loses room: the `Location is off` card at AX5 goes from 290 pt to 100 pt and scrolls. That
is the mechanism #250 chose, applied where #250 stopped, and there is no more room on the screen —
the top chrome takes 493 pt of 874, the two controls 139, the tab bar and its gap 104. **The design
question this does not answer is whether the legend, rather than the notice, is the thing that
should give at AX5.** Capping or scrolling a four-species colour key is a product decision and the
owner's; nothing here invents one. What is no longer possible is the two blocks overlapping.

#### Also true, and not fixed here

`MapTreeCard` occupies the same bottom slot and is **not** given `noticeMaxHeight` — only the four
`MapLocationNotice` arms are. A tall enough card at AX5 would push the same stack up in the same way.
It was not reachable in this ticket's state (the card and the standing notice are different arms of
the same `switch`) and it is not guarded.

#### What the guard now asserts, and what it stopped asserting

`IdentifyFABReachabilityTests` keeps the hittability test — it fails differently and a reader wants
both sentences — and adds two geometric ones: the FAB clear of the legend and of the recenter
control, and the top chrome's bottom edge above the bottom chrome's top edge.

It **drops** PR #51's chip-row assertion. With the legend present, the legend's rectangle lies
strictly between the FAB and the chip row (chip row `y 158.33–218`, legend `y 230–492.67`), so that
assertion can never be the one that fires; and it cannot be red-proved for its own reason either,
because the 430 pt lift needed to put the FAB on the chip row puts the chip row *over* the FAB and
the run then dies on the FAB's own hittability. An assertion that cannot be driven red is not a
guard. PR #51's review had already flagged the same assertion as dominated, on weaker grounds.

#### The same mistake again, one layer down: the guard measured through a hittability gate

The first version of this ticket's own guard read every frame with `settledFrame`, which waits for
the element to be **hittable** before reporting its frame. That is right for its eleven existing
callers — they read a frame in order to touch something — and it is wrong here, for the reason this
whole entry is about. A full-suite run on a loaded machine (`fab2-full-16pro-2.log`, 96 tests, 1
failure) reported:

    testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied :
    the recenter control (“Center the map on you”) is in the accessibility tree but never
    became hittable within 30s

— one XCUITest button query in that test took **20 seconds** (`t = 7.08s` → `t = 27.03s`, three other
agents building on the machine) — where the two rectangles the test was about to compare were
readable throughout. The guard against occlusion had made itself depend on the thing an occlusion
removes.

`settledFrame` now takes `requireHittable:`, default `true`, and this file's geometric reads pass
`false`. Nothing is weakened, because the claim changes with it: "these two rectangles do not
intersect" is a different sentence from "a reader can press this", and the second is asserted on its
own, once, by `testTheFABIsReachableAtAX5WithLocationDenied`, where a 30 s wait is the point.

**What that run does not settle**, and this entry will not pretend otherwise: whether the recenter
control was genuinely covered at that moment or whether a heavily contended machine simply could not
resolve its hittability. The two are indistinguishable from the message the run produced, which is
the defect in the guard rather than a fact about the app — the run before it and the run after it
were green on the same tree and the same device, and the same class's first test, which reads the
same control 40 s earlier, passed. The change above is what makes the next occurrence answerable:
whatever it is, it will now print two rectangles.

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
