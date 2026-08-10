### An unwaited `exists` selected a query branch that could never resolve, and the failure blamed the device

*Found on branch `fix/158-fab-container-race`, 2026-08-09, investigating a CI-only red on PR #71
(`feat/158-outbox-split`). Not caused by that ticket; two green CI runs of the same branch, at
commits carrying the whole of its diff, are the control.*

---

#### The symptom

`ui (1)` red on GitHub, twice on the same commit — original and rerun, two fresh runners — always
the same one test out of 36:

    CypressUITests/IdentifyFABReachabilityTests.swift:205: error:
    -[…IdentifyFABReachabilityTests testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied]
    : failed - the species legend (“Species shown in color on this map”) — absent only when the
    opening camera is showing no trees at all, which is a device-state question (E216) and not a
    layout one never appeared in the accessibility tree at all within 30s

Three full local UI runs of the same code, on three devices at 390, 402 and 440 pt, were green.
The CI device was 402 pt and the failure names a legend whose height is a function of layout, so
the obvious reading was a width-specific layout defect that only CI's geometry reached. That
reading is wrong in every part: the width is irrelevant, the legend was present, and the diff
under suspicion never touched the map.

#### What was actually happening

`IdentifyFABReachabilityTests.container(_:_:)` chose between the two element types XCUITest can
file a labeled SwiftUI group under:

```swift
private func container(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    let other = app.otherElements[label]
    return other.exists ? other : app.scrollViews[label]
}
```

`exists` is an **unwaited snapshot**. The legend enters the tree asynchronously after launch — it
draws only once the opening camera has colored a species — so when that one snapshot fired before
the legend arrived, the helper returned `app.scrollViews[label]`, a query that this legend never
satisfies. The 30 s wait inside `settledFrame` then could not succeed for any amount of waiting,
and reported the element as never having appeared.

Two of the class's three tests call `container` after a `settledFrame`/`assertReachable` on the FAB
has already spent ~1.5 s, which absorbs the delay. `testTheTopChromeStaysClearOfTheBottomChrome…`
is the only one where `container` is the **first** query after launch. It is not a flaky test; it
is the one test positioned to lose.

#### The measurement that settles it

Same test, same branch, same runner class, one CI job apart:

| run | commit | first `Checking existence of … Other` | outcome |
| --- | --- | --- | --- |
| 31350573192 | `d47b16f` | `t = 4.25s` | present → passed in 7.4 s |
| 31352885209 | `8a5f178` | `t = 4.26s` | absent → fell to `ScrollView` → failed in 35.5 s |

Ten milliseconds decided it. In the red run's own log the sibling test found the legend as `Other`
at `t = 5.89s` on that same device, which is the direct proof that the legend was in the tree and
the query was wrong. Local runs made the same snapshot at `t ≈ 3.2s` and won every time, which is
the whole of why three widths looked like three passes.

The two CI runs that were **green** on this branch already carried the entire suspect diff —
`AppSchema` v15 and the `apply:` wiring were present at both `8e70f1b` and `d47b16f`. The only
app-code delta between the last green commit and the red one is a loop-order change in
`OutboxQueue`'s photo phase that executes solely for outbox rows carrying photos, of which the UI
suite creates none.

#### The red-proof

A temporary probe inside the class, on a clean install (`app not installed`), iPhone 16 Pro at
402 pt. It binds the old helper's branch at a moment when the legend is provably absent — before
`app.launch()` — and then measures both helpers:

    PROBE-RESULT newExists=true newTypeRaw=1 newHelperCost=0.31s
                 oldBranchResolvesWithin30s=false newHelperCostOnGenuineAbsence=30.2s

`oldBranchResolvesWithin30s=false` is the dead branch, produced deterministically rather than
waited for. `newTypeRaw=1` is `XCUIElement.ElementType.other` — the spelling the legend does use.
`newHelperCostOnGenuineAbsence=30.2s` shows the replacement polls rather than snapshots.

The run also caught the race live, which was luck worth recording: the trace shows the first
`Other` check at `t = 4.44s` returning false and the second poll at `t = 4.76s` finding it. The old
helper would have failed that exact launch; the new one recovered in 0.31 s.

**Two earlier readings from this investigation were instrument error and are recorded because both
looked like findings.** A first probe run reported `newExists=false`, which read as the fix not
working; the trace showed the helper polling both spellings correctly for the full budget while the
legend was genuinely absent all 95 s — the device carried a `map.lastCamera` with
`viewport-trees=0` from a previous run, so that run was E216, cause 1, and could not judge the fix
at all. The same probe also reported `newIsOther=false` from `newPicked == app.otherElements[label]`;
two such calls are distinct `XCUIElement` objects that compare unequal by identity, so the field was
a fact about XCUIElement and not about the tree. Uninstalling first and comparing `elementType`
fixed both.

#### The rule

**An unwaited `exists` must never be what selects a query branch.** Waiting on the *result* of the
choice cannot repair a choice that was made too early: the wait is spent on an element the screen
will never produce, and the timeout it eventually reports names an absence that is not the one that
occurred. Where two spellings are both acceptable, poll for either and let whichever arrives decide
— one shared budget, not one wait after another.

The neighbouring copy of the same pattern, `MapFilterAccessibilityTests.rowContainer`, is safe and
is deliberately left alone: its single call site re-evaluates the helper inside
`wait(timeout: 25) { self.rowContainer(app).exists }`, so the snapshot is retried rather than
committed to. That is safety by call site rather than by construction, and it is worth knowing it
is the call site doing the work if that line ever moves.

#### The second defect, in the failure text

The message asserted that an absent legend has exactly one cause and that the cause is device
state (E216). That claim sent this investigation at an unrelated diff, and at a screen width, for
most of a day. An absent legend has **two** causes — the device-state one and the query one — and
the query one is the likelier of the two on a loaded or slow machine. The text now names both, in
that order, and tells the reader to check which element type the run's log waited on before
reaching for E216. A failure message that names one cause is read as ruling out the others.
