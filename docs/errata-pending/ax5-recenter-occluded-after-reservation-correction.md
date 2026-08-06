### Correcting `MapLayout`'s AX5 reservations (task #246) measurably worsens the already-accepted top/bottom-chrome overlap — the recenter control loses hittability in the location-denied state

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

#### Why this is not #246's fix to make

`MapHomeView`'s top/bottom overlap at accessibility sizes is an existing, named, accepted
tradeoff — not something #246 touched or was asked to touch. What #246's correction does is move
the point on that tradeoff's curve: giving the notice its full, uninflated scroll budget (the
ticket's actual goal) makes the overlap someone already decided to accept measurably worse for one
control, in one state (location denied, or any other standing notice whose text is long enough to
approach the new, larger `noticeMaxHeight`). Fixing that needs either a change to `availableHeight`
(so it accounts for the top chrome's own footprint rather than the full screen height) or a change
to the two blocks' z-order or hit-testing — both real design/layout decisions, neither of them
"correct two constants to what E243 measured."

#### For the next person

If `MapRecenterButton` needs to stay reachable at AX5 whenever the standing notice is long, that is
a new ticket, not a reopening of #246 — the two constants are now doing exactly what
`AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5` and the owner's 2026-08-06 ruling
say they should. What ticket #246 verified and what this entry adds are two different claims: the
reservation constants match the controls' measured footprints (true, and tested); the recenter
control stays reachable at AX5 across every state that can occupy the notice slot (not true, and
not tested by anything in this branch — `MapRecenterUITests` does not launch at AX5).
