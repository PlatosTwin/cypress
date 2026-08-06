### Correcting `MapLayout`'s AX5 reservations (task #246) measurably worsened the already-accepted top/bottom-chrome overlap — the recenter control lost hittability in the location-denied state

**Fixed in this same PR, task #250 — see "Fixed in the same PR" below.** The sections through
"Why this was not #246's fix to make" are the finding exactly as first written, kept unedited so
the record of what was discovered and why it was out of #246's scope stays intact.

#### What #246 asked for, and what it does not cover

Task #246 asked to correct `MapLayout.locateButtonHeightAX5` (98 → `CypressSpacing.minTapTarget`,
44) and `.fabHeightAX5` (137 → 83) to the bare AX5 footprints ERRATA E243 measured, per a direct
owner ruling superseding RULINGS R53 §6's conservative stance for these two constants. That
correction is in place and is fully covered by `AX5ReflowTests` and both suites. This entry
records a side effect the ticket did not ask about and this correction does not fix: on the
running screen, at AX5, with location denied, the corrected reservations push the recenter
control behind the top chrome, where it is present in the accessibility tree but not hittable.

#### The mechanism

`MapHomeView.chrome` composes two absolutely positioned blocks on one `Color.clear` base:

```swift
Color.clear
    .overlay(alignment: .bottom) { bottomChrome(availableHeight: availableHeight) ... }
    .overlay(alignment: .top) { /* search bar, filter chips, species legend */ ... }
```

Each `.overlay` draws on top of everything before it, so the top-anchored block (search bar,
filter chips, species legend) draws **over** the bottom-anchored block (recenter, FAB, notice)
wherever the two overlap vertically. The code already documents this as accepted, at
`MapHomeView.swift` around the reorder comment: "the two blocks only overlap at accessibility
sizes, where they already did... the top block hit-tests only where it draws — its stack has no
background and the empty width beside a chip has never taken a touch."

`bottomChrome`'s `VStack` stacks, top to bottom: `MapRecenterButton`, `IdentifyFAB`, then the
notice slot — anchored to the screen's bottom edge. `MapLayout.noticeMaxHeight(availableHeight:)`
caps the notice at `availableHeight - bottomSlotReservedAboveAX5`. Lowering
`bottomSlotReservedAboveAX5` (the direct effect of #246's correction) raises that cap, so a notice
whose content is long enough to need it renders taller — which is the intended effect, E243's "108
pt of scroll budget" the notice was not using. Because the `VStack` is bottom-anchored, a taller
notice pushes everything stacked above it — the FAB, then the recenter control — up by the same
amount. `MapRecenterButton` is first in the stack, so it moves the most.

#### Measured, not assumed

`CYPRESS_LOCATION=denied`, `-UIPreferredContentSizeCategoryName
UICTContentSizeCategoryAccessibilityXXXL`, iPhone 16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`,
screen 01's standing "Location is off" notice (the longest of the four `MapOpening.Standing`
sentences on this device). A temporary XCUITest probe (`app.buttons["Center the map on you"]`,
removed before this branch's final commit) read `.exists`, `.isHittable` and `.frame` with the old
and the corrected constants, same tree otherwise:

| constants | `recenter.frame` | `recenter.isHittable` | `fab.frame` | `fab.isHittable` |
|---|---|---|---|---|
| old (98 / 137) | `(380.3, 204.0, 44.0, 44.0)` | `true` | `(60.0, 260.0, 364.3, 83.0)` | `true` |
| corrected (44 / 83) | `(380.3, 96.0, 44.0, 44.0)` | **`false`** | `(60.0, 152.0, 364.3, 83.0)` | `true` |

The recenter control's frame moved up by exactly 108 pt — E243's own figure for the reservation
this correction gives back — landing it under the filter chip row's opaque pills instead of in the
clear band below them. It stays in the tree (`exists == true`) and its frame is still on-screen
(`y = 96`, not negative), so it is occluded rather than clipped: `isHittable` is false because
something else — the chip row above it — now draws over that point. The FAB, one step further down
the stack, still clears the chip row on this device and stays hittable.

Confirmed with a screenshot pair at the same launch state: with the old constants the recenter
control (the small crosshair circle) is visible in the gap below the filter chips; with the
corrected constants no crosshair circle is visible anywhere on screen — the region it used to
occupy shows only the chip row and, faintly, the FAB's label bleeding through underneath it.

#### Why this was not #246's fix to make

`MapHomeView`'s top/bottom overlap at accessibility sizes is an existing, named, accepted
tradeoff — not something #246 touched or was asked to touch. What #246's correction does is move
the point on that tradeoff's curve: giving the notice its full, uninflated scroll budget (the
ticket's actual goal) makes the overlap someone already decided to accept measurably worse for one
control, in one state (location denied, or any other standing notice whose text is long enough to
approach the new, larger `noticeMaxHeight`). Fixing that needed either a change to `availableHeight`
(so it accounts for the top chrome's own footprint rather than the full screen height) or a change
to the two blocks' z-order or hit-testing — both real design/layout decisions, neither of them
"correct two constants to what E243 measured."

#### Fixed in the same PR (task #250)

The orchestrator adjudicated this into the same pull request rather than a follow-up: task #250
took the first branch of the fork above — a change to what the notice's available height accounts
for, not a z-order or hit-testing change, and not a reopening of #246's two corrected constants,
which are untouched.

**The mechanism.** `MapLayout.noticeMaxHeight` gained a second reservation,
`topChromeReservedAX5(topInset:)`, alongside the existing `bottomSlotReservedAboveAX5`
(`Cypress/Features/Map/MapKitBasemap.swift`). Where `bottomSlotReservedAboveAX5` only ever named
what `bottomChrome`'s own `VStack` stacks above the notice (the recenter control, the FAB, their
gaps, the tab bar), the new term names what the *other*, top-anchored block needs: the search bar's
own AX5 footprint (`searchBarHeightAX5`, measured 76.67 pt, stored as `77`) plus the filter chip
row's (`chipRowHeightAX5`, measured 59.67 pt, stored as `60`), both through
`AX5ReflowTests.ax5Size` the same way `locateButtonHeightAX5`/`fabHeightAX5` were, plus the two
gaps the top block is itself laid out with (`searchTopInset`, `chipRowTop`) — the exact sum
`MapHomeView.chrome`'s top overlay uses to position the chip row's own bottom edge.

**`topInset` is read live, not baked into a constant.** It is `GeometryReader`'s own
`proxy.safeAreaInsets.top`, threaded from `MapHomeView.chrome` through `bottomChrome` to
`noticeMaxHeight(availableHeight:topInset:)`. Folding a safe-area figure into a `MapLayout`
constant is the exact shape of defect E243 already found once (`locateButtonHeightAX5`'s old `98`
silently carrying a 54 pt inset that varied by device); reading it live off the real
`GeometryReader` at the one call site that has it avoids repeating that mistake while still getting
the number right on every device, not only the one it was measured against.

**Scope held.** The species legend, below the chip row in the same top-anchored block, also grows
tall at AX5 and was visible bleeding into the FAB/notice area in a screenshot taken while
reproducing this fix — but it sits *below* the chip row (larger y, further down the screen) and
never reaches as high as the recenter control's problem position, so it needed no reservation of
its own for this control's reachability. Nothing about the legend's, the FAB's, or the notice's own
AX5 rendering changed.

**Measured, on the same device and launch state this entry's table used** (iPhone 16 Pro Max
`DE8E11AE-…`, AX5, `CYPRESS_LOCATION=denied`):

| | `recenter.frame` | `recenter.isHittable` |
|---|---|---|
| #246 alone (this entry's finding) | `(380.3, 96.0, 44.0, 44.0)` | `false` |
| #246 + #250's reservation | — (moved down, off the chip row) | `true` |

Confirmed on the running screen: the recenter crosshair is visible again in the clear band below
the chip row, and a tap on it produces `MapRecenterCopy.refusalMessage` exactly as
`MapRecenterUITests.testPressingItWithLocationDeniedExplainsRatherThanDoingNothing` already proved
it does outside AX5. The standing notice this entry's table was measured against
(`MapLocationCopy.message`, `.whereYouLeftOff`) now renders its **full, un-truncated 13-line
message with no scrolling required** — taller than both the pre-#246 figure (~7 lines) and the
post-#246, pre-#250 figure (~10-11 lines) this branch's ruling recorded, so #246's own point (the
notice gets its uninflated scroll budget back) still holds.

**Tests.** `CypressTests/AX5ReflowTests.topChromeFitsItsReservedBudgetAtAX5` guards
`searchBarHeightAX5`/`chipRowHeightAX5` the same `<=` way
`bottomChromeControlsFitTheReservedBudgetAtAX5` guards the other two reservation inputs.
`CypressUITests/MapRecenterUITests.testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied`
pins the fixed property end-to-end — recenter's frame must not intersect the chip row's own frame
at AX5 with location denied — and is the permanent replacement for the temporary XCUITest probe
this entry originally described. Red-proofed: with the `topChromeReservedAX5(topInset:)` term
temporarily removed from `noticeMaxHeight`, the UI test failed for the expected reason — "screen
01's control labeled "Center the map on you", at AX5 with location denied is in the accessibility
tree but never became hittable within 30s — it is present and cannot be activated" — then the term
was restored and the test went green again.

Full `CypressTests`: `Test run with 1257 tests in 124 suites passed`. Full `CypressUITests`, iPhone
16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`: `** TEST SUCCEEDED **`, `Executed 93 tests, with
0 failures`, `XCTest skipped=0`. Warnings certified on a fresh build-for-testing DerivedData
(`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`, `source=0` warnings,
`files-checked=4` (`MapKitBasemap.swift`, `MapHomeView.swift`, `AX5ReflowTests.swift`,
`MapRecenterUITests.swift`, all four actually compiled).
