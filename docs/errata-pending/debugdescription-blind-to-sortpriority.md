## `debugDescription`'s element order does not move under `accessibilitySortPriority` (task #221)

**Found while building the map's reading-order test for `CypressUITests/ReadingOrderAccessibilityTests`,
and worth flagging because it touches a load-bearing claim in `MapHomeView.swift`'s own comments and
in RULINGS R25/task #143's fix for ERRATA E183 §3.**

### What was being verified

E183 §3 found that R25 §1's claimed swipe order ("field → suggestions → chips → status line") was
not what the running app produced, measured with `app.buttons` (the query-engine order — already
known unreliable for this purpose per E118). Task #143's fix was to give `MapHomeView.chrome`'s
chrome blocks explicit `accessibilitySortPriority` values (field 6 > suggestions 5 > chips 4 > status
3 > legend 1, top block 2 > bottom chrome 1), and its own comment states the resulting reading order
as settled fact: "the reading order a listener walks … is the same order with one stop removed,"
citing `AccessibilityTreeTests` and `DeepLinkVoiceOverTests` as the tests that "walk that order."

Building a `treeOrder`-based (`debugDescription`-based) test for this order was the natural next
step — and it does not work.

### What was measured

With `SearchBar`'s `accessibilitySortPriority` temporarily lowered from 6 to 2 (below the filter
chips' 4) — a red-proof mutation that should invert the field-before-chips claim if `debugDescription`
reflects sort priority — the parsed element order was **completely unchanged**, confirmed on a fresh,
from-scratch 430-file build (not a reused DerivedData, ruling out a stale-cache explanation): the
search field still read before the suggestion list, still before the filter chips, exactly as before
the mutation. Reverting the mutation and instead reordering the actual `VStack` children in source
(moving `MapFilterChips` above `SearchBar`) **did** change `debugDescription`'s order.

The conclusion these two experiments together support: `debugDescription`'s depth-first dump reflects
the raw view-composition (document) order, not the `accessibilitySortPriority`-adjusted order
VoiceOver is documented to honor. This is consistent with — and may be the same root cause as —
`CypressTests/AccessibilityTests`' standing finding (cited by ERRATA E196) that SwiftUI serves
accessibility over its own bridge rather than through `NSObject`'s container protocol UIKit's
`accessibilitySortPriority` handling is normally documented against.

### What this means for what is and is not tested

- **Nothing in this suite — before this ticket or after it — has ever verified that
  `accessibilitySortPriority` actually reorders what VoiceOver announces on this app.** The map's own
  file comment overstates what `AccessibilityTreeTests`/`DeepLinkVoiceOverTests` prove; neither reads
  order via a mechanism sensitive to sort priority (`AccessibilityTreeTests` does not assert order on
  the map's chrome at all beyond field reachability, and nothing in `DeepLinkVoiceOverTests` touches
  screen 01's suggestion/chips ordering).
- `ReadingOrderAccessibilityTests.testMapFieldPrecedesSuggestionsPrecedesFilterChipsInComposition`
  (this ticket) asserts the one thing that *is* verifiable this way: the three blocks stay composed,
  in source, in the intended order. That is real coverage — nothing before this test would have
  caught a `VStack` reorder — but it is not a proof that `accessibilitySortPriority`'s numbers are
  doing anything, because the same `debugDescription` read would look identical whether those
  modifiers were present, absent, or reversed.
- **Verifying the sort-priority mechanism itself needs VoiceOver running on a real device**, which is
  out of reach for a black-box XCUITest here (the standing limitation this whole target works within
  — E116's header). This is a real, currently-open gap, not a defect in anything shipped: the map's
  actual on-device behavior was not re-measured by this ticket and may well be correct; what changed
  is that the claim is now known to be *unverified by any automated test*, where the file comment
  reads as if it were.

### Suggested follow-up, not done here

If this is worth closing rather than living with, the options are: a manual on-device VoiceOver pass
recorded against `MapHomeView.chrome` (the shape `docs/RULINGS.md`'s physical-phone notes already use
for camera/heading claims this project's own tooling cannot see), or filing whether any lower-level
XCUITest API exposes `accessibilityElements`-array order directly rather than through
`debugDescription`'s dump — not investigated here for lack of time, and worth fifteen minutes before
assuming it does not exist.
