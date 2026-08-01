# The swipe order is declared with sort priorities, and the instrument that "measured" it cannot see them (task #143)

**Unnumbered — pending. The orchestrator assigns the E number at merge.**

## The fix

Screen 01's chrome now carries explicit `accessibilitySortPriority` values (the ticket's named
mechanism): the top block over the bottom block over the tab bar; within the top block the field
(6), the suggestion list (5), the chips (4), the search status (3), the filter status (2), the
legend (1). R25 §1's text is amended in place on the same branch. The row the priorities pin is
#145's (`Yours · In bloom · Needs care · More filters`).

## The finding: `app.buttons` order is XCUITest's, not a listener's

The swipe-order test the ticket asked for was written against E183 §3's own instrument — the order
`app.buttons.allElementsBoundByIndex` returns — and proved red against the pre-fix tree. Against
the fixed tree it returned the **identical 24-element order**. Two further instrumented runs:

- Wrapping the sorted siblings in `.accessibilityElement(children: .contain)` *does* change the
  enumeration (the channel sees structure), but not to the priority order — and the contained
  block's children enumerated ✕ → chips → suggestions against both declaration order and
  priorities.
- Forcing the container to rebuild when the list appears (`.id` keyed on focus) hangs
  `typeText`'s run loop for 30 s. Reverted.

The enumeration also violates the view hierarchy (elements of one VStack enumerate on both sides
of a different ZStack sibling), geometry, and creation order — it is an XCTest-internal traversal,
insensitive to `accessibilitySortPriority`, and therefore not a proxy for VoiceOver's reading
order in either direction.

Two consequences worth recording:

1. **E183 §3 should be read as a fact about XCUITest enumeration, not about the swipe order.** Its
   own listing contradicts its prose — `Clear search` precedes the four tabs in the measured
   array quoted there. The defect it pointed at was real in kind (nothing declared the reading
   order), but the specific sequence it printed is the instrument's.
2. **No test in `CypressUITests` may assert reading order through `app.buttons` indices.** The
   comment block left in `MapFilterAccessibilityTests` (where the deleted test stood) says so, on
   E183 §4's precedent: a sentence about XCUITest must not ship as a sentence about the app.

## The debt

`accessibilitySortPriority` ships on Apple's documented contract ("higher priorities are sorted
first", relative to same-level elements). **Verification is owed on the physical phone with
VoiceOver on** — swipe forward from the search field with the list open and confirm field → ✕ →
suggestions → chips → status → legend → bottom chrome → tabs. Flag for the owner's device pass
alongside #149's glide.
