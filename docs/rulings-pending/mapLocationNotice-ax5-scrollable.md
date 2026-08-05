### Unnumbered — MapLocationNotice scrolls at AX5 rather than growing off the screen (owner decision 2026-08-05, task #235)

**Answers the open question R53 §6 and ERRATA E183 §2 both left standing.** E183 §2 measured
`MapLocationNotice` at AX5 taller than a 390 pt phone: laid out from `bottomChrome`'s bottom edge,
it grows *upward past `y = 0`*, taking E126's own way out (a trailing button) off the top of the
screen with it. R53 §6 measured the same defect against its own new copy, kept the shipped copy
under the tallest card already in the slot so as not to deepen it, and said explicitly: "That
defect is a layout ruling nobody has taken and it is not fixed here — it is the same open question
R23 left." R14, R22 and R25 §6 each answered the analogous question for their own surface; screen
01's bottom card had no answer of its own until now.

**The owner ruled, 2026-08-05: the card scrolls once it runs out of room, rather than growing past
the top of the screen.**

**What was built.** `MapLocationNotice` (`Cypress/Features/Map/MapChrome.swift`) takes an optional
`maxHeight: CGFloat?`. `nil` is the card's old, unbounded shape, unchanged — every call site had
this until this ticket, and `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` still measures it
that way on purpose, to compare notices against each other rather than against a screen. When a
budget is given, the card is wrapped in a `ScrollView` capped with `.frame(maxHeight:)`, following
the same idiom `MapSuggestionList` already ships (`ScrollView { … }.frame(maxHeight:
availableHeight * share)`) — nothing new was invented for this.

`MapHomeView` is the one caller that passes a budget, computed by
`MapLayout.noticeMaxHeight(availableHeight:)`: the screen's own `GeometryReader`-measured height,
minus a reservation for everything `bottomChrome`'s `VStack` stacks above the notice slot at the
worst case either control ever measures — `MapRecenterButton` and `IdentifyFAB` at
`.accessibility5` (98 pt and 137 pt respectively, measured through `AX5ReflowTests.ax5Size`, not
assumed), plus their gaps and the gap to the tab bar. The reservation is deliberately
conservative — it is not a live measurement of the controls' actual height on every layout pass —
so at ordinary sizes the budget is far larger than any card ever needs and nothing about ordinary
rendering changes; at AX5 it keeps the notice from ever claiming more room than the slot has left
above the recenter control and the FAB.

**Not fixed as part of this ruling:** the exact copy budgets R53 §6 tuned against the shipped
`MapInventoryCopy` sentence, and E183 §2's own note that the row above the card (the filter chips)
is unaffected. Scrolling is the backstop for whatever copy any of the five call sites ever carries;
it does not change what any of them say.

**Tests**, `CypressTests/AX5ReflowTests.swift`:
- `bottomChromeControlsMatchTheReservedBudgetAtAX5` — pins the two measured constants
  (`MapLayout.locateButtonHeightAX5`, `.fabHeightAX5`) against a fresh measurement, so a change to
  either control's AX5 footprint fails loudly instead of quietly under-reserving the budget.
- `mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5` — offered half its own unbounded AX5
  height as a budget, the card must not measure taller than that budget (plus a 1 pt rounding
  tolerance for `ScrollView`'s own line-height quantization). Hosted bare (no window, no settle
  loop) rather than through `AX5ReflowTests.ax5Size`: that helper's window-plus-settle-loop
  sequence was watched reporting a `ScrollView`'s full unclamped content height instead of its
  frame's cap (a 200 pt-capped `ScrollView` measured 254 pt through `ax5Size`'s exact sequence and
  200 pt through a bare `UIHostingController` never mounted in a window), so it is not the
  instrument this claim can be measured with.
- `mapLocationNoticeUnchangedAtOrdinarySizeWithAMaxHeight` — at the default dynamic type size, a
  generous `maxHeight` (a full phone's height) produces the identical measured size to no
  `maxHeight` at all.

Red-proved: with the `ScrollView`/`.frame(maxHeight:)` wrapper removed from `MapLocationNotice.body`
(returning the plain `card` unconditionally), `mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5`
failed with `(bounded.height → 357.0) <= (budget + tolerance → 179.5)` — the card reported its full,
unbounded height regardless of the budget it was given — then the wrapper was restored.

To be spliced under the real next R-number at merge.
