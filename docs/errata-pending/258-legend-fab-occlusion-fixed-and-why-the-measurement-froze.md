### The species legend stops covering the identify FAB, and the reason the measured repair froze: `onChange` out of a `GeometryReader` is edge-triggered over a value SwiftUI is free to change without an edge (task #258)

This closes the defect the previous round diagnosed and could not land. That round's entry is the
diagnosis; this one is the mechanism it left open, the repair, and what the repair costs.

#### The defect, re-measured on this branch before anything was changed

`Tools/run_tests.sh EA0AD796-… fab258-repro-16pro.log -only-testing:CypressUITests/IdentifyFABReachabilityTests`,
iPhone 16 Pro (402 pt), AX5, `CYPRESS_LOCATION=denied`, at this branch's merge-base with `main`:

    the identify control (22.0, 371.0, 364.33, 83.0) overlaps the species legend
    (16.0, 230.0, 344.33, 262.67)

    the top chrome ends at y 492.67 and the bottom chrome begins at y 315.0

and, in the same run, `testTheFABIsReachableAtAX5WithLocationDenied` **passed in 4.596 s**. One
launch, one device: the occlusion is there, the rectangles see it, `isHittable` does not. Every
frame matches the previous round's to the hundredth of a point, so the diagnosis is confirmed rather
than assumed.

#### Why the measured repair froze — established, with numbers

The repair that was built and not landed measured the top block's real bottom edge in a
`GeometryReader` inside a `.background`, and handed it to `@State` through
`.onChange(of: proxy.frame(in:).maxY, initial: true)`. It froze on some launches, at whatever the
legend's height had been on an early pass, for the whole life of the process. Which launch froze
moved with the wiring, and four wirings were tried.

It was instrumented rather than reasoned about. The branch `diag/258-freeze` carries the abandoned
repair plus three probes published into the accessibility tree behind `CYPRESS_MAP_PROBE=1`:

| probe | what it renders | where it renders |
|---|---|---|
| `chrome-live` | `proxy.frame(in:).maxY` | inside the measuring `GeometryReader`'s own closure |
| `chrome-written` | the last value the `onChange` **action** was given | same closure, from plain non-observed storage |
| `chrome-state` | what reached `@State` | outside the `GeometryReader` entirely |

Two runs of 16 launches each on the iPhone 16 Pro, sampling at 3 s and again at 11 s after launch
(`fab258-freeze-16pro.log`, `fab258-freeze2-16pro.log`). Three launches of the 32 froze, and they
all say the same thing:

    launch=4  live=492.667  written=425.0  state=425.0  writes=6  legendMaxY=492.667  overlap=true
    launch=11 live=492.667                 state=357.33            legendMaxY=492.667  overlap=true

against a healthy launch:

    launch=5  live=492.667  written=492.667 state=492.667 writes=7 legendMaxY=492.667 overlap=false

Three facts, each measured rather than inferred:

1. **No `@State` write was ever lost.** `state == written` on every launch, frozen or not. The
   "SwiftUI discarded the write" hypothesis — E168's shape, and the obvious one to reach for in this
   view — is **wrong**.
2. **The `onChange` action was never called with the final value.** On the frozen launches its last
   argument was a stale *intermediate*: 425.0 is the top block with a three-row legend, 357.33 with
   a two-row one, against the four rows the legend actually had.
3. **The closure it lives in did re-render with the final value**, because `chrome-live` — computed
   from the same `proxy`, inside the same closure — reads 492.667 at both samples.

So the geometry reached the `GeometryReader` and the transition did not reach `onChange`. The
observed value was silently advanced without the action running. The `writes` count varies from
launch to launch (5, 6, 7 across the healthy ones), which is the same thing seen from the other
side: how many of the legend's growth passes SwiftUI coalesces is not fixed, and a coalesced last
pass is a transition nobody is told about.

**It never converges because `onChange` is edge-triggered and the value has no further edges.** Once
the last transition is absorbed, the legend's height never changes again, so there is nothing left
to re-deliver it. That is why the stuck launches were stuck from the first sample to the last, and
why a longer settle would not have helped.

**This generalizes past `onChange`, which is why all four wirings flaked.** A `PreferenceKey` is
delivered on change too. Any channel that carries a layout measurement back into state as a
*difference* has this failure mode; the only question between wirings is which pass gets coalesced,
which is what "which launch freezes moved with the wiring" was reporting.

**The rule worth keeping: do not close a layout loop through an edge-triggered channel.** If a
number is needed before layout, take it from something that is known before layout.

#### The repair

The palette is known before layout. `MapSpeciesPalette` is model state `MapHomeView` already
observes, so the number of chips the legend will draw is available without asking the layout system
anything, and there is no channel to drop anything.

`MapLayout` now splits the room below the filter chip row between the two things that grow into it:

- `chromeSlackBelowChipRow(screenHeight:topInset:)` — the whole of that room, once.
- `legendNaturalHeight(namedSpecies:isAccessibilitySize:)` — `count` chips and `count − 1` gaps. An
  **upper bound by construction**: `FlowRow` puts at most one chip per line and every chip is one
  line tall (`.lineLimit(1)`), so `count` chips take at most `count` lines. A legend whose names pair
  up on a line is over-reserved, never under-reserved.
- `legendReserved(…)` / `noticeMaxHeight(…)` — complementary halves of the slack, so no arrangement
  of them hands the same point to both blocks.

Three constants changed or arrived, each guarded:

- **`legendChipHeightAX5 = 60`** and **`legendChipHeightLarge = 36`**, bounds on one chip at
  `.accessibility5` and at `.xxxLarge`. Two buckets rather than one because this is the only
  reservation on the screen that is multiplied by up to four: the AX5 figure applied unconditionally
  would take 276 pt off the notice's budget at the default content size, where the legend is nowhere
  near that tall. `AX5ReflowTests.theSpeciesLegendFitsItsReservationAtAX5` measures the legend at
  both sizes and all four counts.
- **`searchBarHeightAX5` 77 → 85.** The old value was **7.33 pt short of the running screen**, and
  #250's reservation had been short by that much since it landed. `AX5ReflowTests.ax5Size` hosts
  `SearchBar` alone in an off-screen window and reports ≤ 77; on screen 01 the bar occupies 84.33
  (chip row at `(16, 158.33, …)`, top block starting at `topInset + searchTopInset` = 62, `chipRowTop`
  = 12 between them). **The synthetic window is the optimistic one**, and its guard is `<=`, so it
  cannot see the shortfall in either direction — raising the constant leaves it just as green. This
  is the E243 family from the opposite end: that ticket found the measuring window adding a term that
  was not in the view; this finds it missing one that is. Nothing in the unit suite can verify this
  number. The geometric UI guard can, and does.
- **`noticeMaxHeight` subtracts from the screen's height, not the safe area's.** Every other term in
  it counts from the top of the screen — `topChromeReservedAX5` contains `topInset`, and
  `bottomSlotReservedAboveAX5` ends at `tabBarHeight`, which is padding from the bottom of
  `MapCanvas`'s `.ignoresSafeArea()` overlay. It had been ~93 pt conservative on a notched phone the
  whole time. Harmless while the number subtracted was 211; with the legend's 276 joining it the
  budget goes *negative* out of the safe area's 781 pt and comes to a workable 98 out of the screen's
  874. No measurement is needed: the screen's height is the safe area plus the two insets bounding
  it, and `MapHomeView`'s root `GeometryReader` has all three.

#### What it costs, said plainly

On a 402 pt phone at AX5 with location denied and four colored species, `MapLocationNotice` renders
**90 pt tall instead of 251**, and scrolls. That is R53 §6's own ruling applied where it bites — the
notice scrolls rather than growing into something else — and it partly spends the budget #246 gave
back, in this one state. The alternative is the FAB covered, and the FAB is screen 01's only
entrance to the visit flow. It is a trade rather than a free fix and the owner may want to look at
it.

#### The short-phone squeeze, and the one behavioral change

On a 667 pt screen at AX5 the chrome wants more than the glass has: `topChromeReservedAX5` plus four
AX5 chips is 461 pt against 398 pt of room once the bottom block is reserved. Arithmetic cannot
resolve that — something has to yield. `MapSpeciesLegend` gains a `maxHeight:` and scrolls when it
binds, on the same argument R53 §6 made for the notice: a scrolled chip is reachable and a covered
control is not, and the legend is also the species filter (#116), so its chips must stay pressable.

**`MapLayout.legendMaxHeight` returns `nil` unless the ceiling actually binds**, and that `nil` is
load-bearing rather than tidy. A non-nil ceiling puts the legend inside a `ScrollView`, and a
`ScrollView` over a map takes touches across its whole frame where the bare `FlowRow` takes them only
on the chips — `MapHomeView.chrome`'s own note, "the empty width beside a chip has never taken a
touch". On every device this suite runs (402 pt, 430 pt, default size and AX5) the legend is inside
its ceiling, this returns `nil`, and the view is the one that shipped.
`AX5ReflowTests.theLegendCeilingDoesNotBindOnTestedDevices` asserts that, so the day it stops being
true somebody is told rather than finding a new scroller on the map.

#### Still not reserved, and now named rather than denied

- **The `Needs care` toast.** `MapToast`'s doc claimed it "cannot cover the chips, the legend, the
  recenter control, the FAB or the bottom card at any Dynamic Type size". The first two are true and
  the rest never were — being in the flow of the top block says nothing about the *other* block, and
  the card pushes everything below it in its own stack down by its own height. For the three seconds
  it shows, at AX5, with a full palette, it can push the legend past its reservation and onto the
  bottom chrome. Reserving for it would cost the notice that room in every second the toast is not
  on screen, which is almost all of them. The comment is corrected; the gap is open.
- **`MapSearchStatus`**, on the same reasoning, and with the additional one that it only exists while
  a search is running — the state R25/#143 deliberately lets the top block draw over the bottom in.
- **`MapTreeCard`** shares the bottom slot and is still not given `noticeMaxHeight` — only the four
  `MapLocationNotice` arms are. Carried forward unchanged from the previous round's entry.

#### The guard

`CypressUITests/IdentifyFABReachabilityTests` is the previous round's file, restored from
`89f5001`/`5a2112f`, together with `settledFrame(requireHittable:)` — a guard against occlusion must
not gate its measurements on the thing an occlusion removes. Red-proved three ways on an iPhone 16
Pro, each fired for its own reason:

| break | what went red |
|---|---|
| `legendReserved` returns 0 | *"the identify control (22.0, 295.0, 364.33, 83.0) overlaps the species legend (16.0, 230.0, 344.33, 262.67)"* — and `testTheFABIsReachableAtAX5WithLocationDenied` **passed in 4.636 s** in the same run |
| the recenter control's bottom padding → `-10` | *"the identify control (22.0, 571.0, …) overlaps the recenter control (342.33, 537.0, 44, 44)"* |
| `IdentifyFAB.offset(x: 2000)` | *"is in the accessibility tree but never became hittable within 30s"* (33.2 s) |

`.allowsHitTesting(false)` does **not** make an element unhittable to XCUITest, which is why the
third proof uses an offset (measured independently in PR #51's review).

#### Why three launches of a guard were not enough evidence, and what was

The abandoned repair passed this same guard. A defect at one launch in eight is invisible to three
launches. So the fix was run through a temporary 40-launch check on each device
(`fab258-repeat-16pro.log`, `fab258-repeat-16plus.log`): **80 launches, 0 overlaps**, and every
launch on a device reported *byte-identical* geometry — 402 pt: legend bottom 492.667, recenter top
515.0; 430 pt: legend bottom 489.667, recenter top 512.0, FAB top 568.0. The abandoned repair could
not do that: its frozen launches reported 425.0 and 357.33 where its healthy ones reported 492.667.
A per-launch race does not produce one number 40 times.

At the freeze rate actually measured (3 of 32, ≈ 9.4 %), 80 clean launches would happen by luck with
probability 0.906⁸⁰ ≈ 3.6 × 10⁻⁴; at the ~1-in-4 rate the previous round reported, ≈ 10⁻¹⁰. The
arithmetic is worth stating and it is the weaker half of the argument: the stronger half is that the
channel which dropped the value no longer exists.
