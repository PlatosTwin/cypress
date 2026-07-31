### E183 — screen 01's filter row had no automated accessibility coverage at all; it has eleven tests now, and they found four things

**Task #135.** #116 (R23) shipped the filter row, the result line and the empty-state notice, and its
own report said plainly: *"No UI tests written — `CypressUITests` was not run at all."* Everything
about it had been verified by driving the simulator by hand. #109 (R25) shipped the suggestion list
under the search field with five UI tests, none of which touch the filter.

Mid-task the owner restructured the row — `Favorites` behind an expandable control, the visible chips
cut to their four, American spelling — which is **RULINGS R23.1**. Everything below is written against
that shape, because tests written against the old row would have been obsolete the day they landed.

---

#### 1 · What is covered now

`CypressUITests/MapFilterAccessibilityTests`, eleven tests, black-box like the rest of that target:

| test | the claim |
|---|---|
| `testTheFilterRowIsReachableAndEveryChipSaysItIsOff` | the row is a named container; every chip is in the tree, hittable, and **announces `Off`**; the year control announces `Any year`; `Favorites` is *not* in the row (R23.1); no `Clear filters` over an unfiltered map |
| `testTurningAChipOnIsAnnouncedInBothChannels` | on flips the value to `On` **and** adds the selected trait — two channels from two places in the code — and the chip toggles back off |
| `testTheHiddenFilterIsOnlyInTheTreeWhileTheControlIsOpen` | shut → the drawer's chip is **not in the tree**; open → it is, hittable, announcing `Off`, inside a named group; shut again → gone |
| `testAShutControlSaysWhatIsSetInsideIt` | `Collapsed` / `Expanded`, and `Collapsed, on: Favorites` when something is set behind it; the selected trait on the shut control; the membership swap crossing the two surfaces; `Clear filters` still reachable |
| `testClearFiltersAppearsWithTheFilterAndTakesAwayEvenTheHiddenOne` | the one clear-everything control reaches a filter set behind a shut drawer (R23.1 §3) |
| `testTheEmptyNoticeOffersASecondWayOutAndItWorks` | two controls labelled `Clear filters`, the notice's one hittable, on the card, and it clears |
| `testTheCountYieldsToTheNotice` | R23 §5's conditional: an empty map draws **no** count while the notice is speaking |
| `testTheResultLineIsOneCountingPhrase` | the count is one element matching `^[0-9]+ tree(s)?(—showing [0-9]+)?$`, and no fragment of it is a separate element |
| `testTheFilterRowWrapsAndStaysOnThePhoneAtAX5` | AX5 on a 390 pt phone: the size actually arrived, the row uses more than one line, every chip is inside the display and hittable, and so is the chip inside the opened drawer |
| `testTheEmptyNoticesWayOutIsUnreachableAtAX5` | a defect, pinned — see §2 |
| `testAnOpenSuggestionListLeavesTheWholeFilterRowOrderedAndHittable` | with a filter on and `Clear filters` present, the list pushes both down rather than covering them, both stay hittable, the row's own order is unchanged, and the `Menu`'s unlabelled leftover element stays unreachable |

Five unit tests were added to `CypressTests/MapFilterTests` for the channels a black-box test cannot
reach: the drawn `More filters (1)` label (the chip overrides its accessibility label, so XCUITest
never sees the count), `moreValue`'s two facts, `MapExtraFilter` driven entirely over `allCases`, the
owner's chip order, and the American spelling.

#### 2 · **Defect: at AX5 the empty notice grows off the top of the phone and takes E126's way out with it**

Found by running the AX5 test, then photographed to be sure. On a 390 pt phone at
`accessibilityExtraExtraExtraLarge`, `MapLocationNotice` is taller than the display and is laid out
from its bottom edge, so it grows *upwards past `y = 0`*. The message renders one word per line behind
the search bar and the chips; the title `Nothing matches here` and the trailing `Clear filters` button
are above the top of the screen entirely. E126 requires an emptied surface to say why **and** how to
leave, and at AX5 it does neither — the button is in the tree with a negative `minY` and is not
hittable.

This also produced a wrong diagnosis on the way in, worth recording on its own: the first version of
this file resolved the two `Clear filters` controls by sorting on `frame.minY` and taking the topmost
as "the chip in the row". At AX5 the *notice's* button has the smaller `minY` — it is off the top —
so the test failed with `at AX5 the “Clear filters” chip cannot be activated` about a control that was
not the chip. The lookup is scoped to the row's accessibility container now.

**Not fixed here, deliberately.** The fix is a layout ruling — what a bottom card does when it is
taller than the phone — which is the question R23 explicitly left open ("whether the chrome is now too
tall") and which R14 (screen 04), R22 (the add screen) and R25 §6 (the suggestion list) have each
answered separately for their own surface. Choosing it inside a testing ticket would be redesigning.
So it is pinned with a **strict `XCTExpectFailure`**: the test passes today *because* the defect is
there, and turns red the day somebody fixes it, at which point they delete the wrapper. The same test
asserts what keeps the screen from being a dead end — the `Clear filters` chip in the row is on the
phone at AX5, is hittable, and clears.

The row itself is fine at AX5: four lines, every chip inside the display, every chip hittable. The
drawn size is `Yours · In bloom · Needs care · Year` on one line and `More filters` on a second.

#### 3 · **Finding: R25 §1's stated swipe order is not what the tree exposes**

R25 §1 gives, as half its reason for putting the suggestion list in the flow rather than in an
overlay: *"the swipe order is field → suggestions → chips → status line, which is the order the words
are in."* Measured on the running app with the list open and a filter on, `app.buttons` comes back:

```
recentre · What tree is this? · Clear filters (the notice's) · Clear search · Map · My Grove ·
Journal · You · Yours · In bloom · Needs care · Year · More filters · Clear filters (the chip) ·
Cypress species · Monterey Cypress · Hinoki cypress · Leyland Cypress · Italian Cypress ·
Montezuma Cypress
```

The suggestion rows arrive **after** the chips, not before; and the bottom chrome and the whole tab
bar arrive before the search field's own ✕. R25's *other* half is delivered and is asserted — the
chips move down rather than being covered, and they stay hittable — but the ordering claim is not.

**Recorded, not fixed.** Making it true means giving screen 01's chrome explicit
`accessibilitySortPriority` values, which is a change to R25's surface rather than to this ticket's.
Note also that R25's block reorder (bottom applied first so the top draws over it, added for the FAB
that was covering the remainder sentence at AX5) is what puts the recentre control and the FAB at the
head of the order; that is a consequence nobody had looked at.

#### 4 · **Finding: a SwiftUI `Menu`'s items are in no element tree XCUITest hands back**

A test that the year control's caveat reaches the tree as one element was written and then deleted,
because it could not be driven honestly. `app.buttons["2010s"]` finds nothing;
`app.descendants(matching: .any)["2010s"]` finds nothing; the same query against
`com.apple.springboard` finds nothing. Forty-five seconds of waiting across three runs.

**The menu is opening.** Photographed on the simulator: tapping `Year` draws the platter with
`Any year · Before 1990 · 1990s · 2000s · 2010s · 2020s` on it. So the failing test's message — "the
year control opened no menu" — was a sentence about the app and was in fact a sentence about
XCUITest. That is the same class of mistake as tasks #101 and #104, caught this time before it was
committed as a finding.

What still covers the year control: its label, its value (`Any year`) and its hittability are asserted
at rest; `MapYearFilterCopy.setAside`'s text and the 80.78 % it quotes are pinned against the shipped
seed by the unit suite; and the *mechanism* that renders it as one element, `MapFilterStatus.line`, is
the same code path the result line uses, which `testTheResultLineIsOneCountingPhrase` proves against
the running app. What is genuinely uncovered is that particular sentence being rendered through it.

#### 5 · **Finding: `Needs care` matches nothing in the shipped seed either**

R23 records that `In bloom` "still matches nothing, because every `seasonal` in the shipped seed is
`{}`". Nobody had written down that the other condition chip is in the same position:
`MapPinKind.needsCare` is `status == .declining`, and the seed carries two statuses — `alive` 174,425
and `vacant_site` 24,200. So `Needs care` cannot match a tree anywhere in either city.

This is a fact about the data rather than a defect in the chip, and it is what lets these tests reach
the empty state without touching the simulator's location. It is recorded in R23.1's "deliberately not
decided" so that a chip guaranteed to produce an empty-state card is at least written down.

#### 6 · Two smaller things the first run corrected

- `XCTAssertGreaterThan(noticeButton.frame.minY, title.frame.minY)` failed at **660.0 against
  660.0000000000001**. `MapLocationNotice` is an `HStack` aligned `.top`, so the button's top edge is
  the title's top edge; the assertion was true-by-intent and false-by-arithmetic. It now asserts the
  thing that means something — that the control is below the filter row rather than in it.
- Filtering the element tree by *label* cannot tell the row's `Clear filters` from the notice's. The
  first row-order assertion read `["Clear filters", "Yours", …]` and was reporting the notice's button
  as the first element of the filter row. Scoped to the container.

---

#### 7 · The mutation sweep — every test broken on purpose, and the red it produced

MUTATION_TABLE_PLACEHOLDER

---

#### 8 · What was *not* done

- **The AX5 notice defect (§2) and the swipe-order finding (§3) are not fixed.** Both are recorded and
  one of them is machine-pinned. Both fixes are design decisions inside R23's and R25's territory.
- **No test drives the year menu** (§4), so no test proves the caveat sentence reaches the tree.
- **`testTheResultLineIsOneCountingPhrase` carries the only precondition in the file** and it is the
  legend, which needs a viewport where the map has coloured a species. It skips when there is none —
  and, unlike the two skips #121 is open about, it **prints a banner** naming itself and the `xcrun
  simctl location` that fixes it before it does. On this machine it did not fire: the map opened over
  the default centre and the legend was showing `Southern Magnolia`.
- **`testTheEmptyNoticesWayOutIsUnreachableAtAX5` is not mutation-proved**, because its failure mode is
  structural rather than behavioural: strict `XCTExpectFailure` turns it red exactly when the defect it
  records stops happening. Proving that would mean fixing the defect, which is §2's whole point.
- **No spelling sweep.** `favorites` was renamed in `MapMembership`, `MapFilterCopy`, `LocalAPI`'s one
  switch arm and `MapFilterTests`. The other 157 `favourite`, 422 `centre`, 189 `neighbourhood` and
  182 `colour` are somebody else's ticket.
- **No schema change.** `AppSchema` is untouched at v13.
