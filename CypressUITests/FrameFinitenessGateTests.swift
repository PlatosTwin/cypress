import XCTest

/// **A settled frame must also be a real one.**
///
/// `settledFrame` (`UIWait.swift`) decides an element has stopped moving by comparing two
/// consecutive frame reads, and until this round that comparison was plain `CGRect.equalTo`.
/// `equalTo` treats `.infinity == .infinity` as `true` — so an element XCUITest could not resolve
/// a real position for, read mid-transition on a contended runner as `{{inf, inf}, {inf, inf}}`
/// rather than raised as an error, looked exactly like a frame that had settled on its very first
/// two samples. `settledFrame` would then hand a caller a coordinate for nowhere, and the caller
/// would synthesize a tap or a drag against it.
///
/// **What was and was not observed while writing this.** Investigating #239's six 2026-08-04 UI
/// flakes (PRs #13/#14/#15 — `test/e229-…`, `test/voiceover-reading-order`,
/// `fix/e217-deep-link-override-leak` — and same-day pushes to main), every downloaded shard log
/// showed a genuine settle-or-hittability race (`AccessibilityTreeTests`, `SheetExitUITests`,
/// `MapPanTabSwitchUITests` — all three already covered by `assertReachable`/`settledFrame`/
/// `deliberateDrag`/`panUntilMoved`). None showed a non-finite frame anywhere, and none of the CI
/// evidence available matched a `DeepLinkSweepTests` or `MapFilterAccessibilityTests` failure at
/// all — see the ticket write-up. This gate exists because the gap in `frameHasSettled` is real
/// and reachable from the code as written, independent of whether that specific incident happened
/// on any run this investigation could see.
///
/// **Pure `CGRect` arithmetic — no live element, no simulator, no app launch.** `frameHasSettled`
/// and `isFiniteFrame` are `UIWait.swift` functions and this is the target that declares them, so
/// unlike `DragGestureGateTests` (which checks a different suite's helper from the unit suite
/// because it can) this gate has to live here. It still costs nothing in whatever shard it lands
/// on: nothing here touches `XCUIApplication`.
final class FrameFinitenessGateTests: XCTestCase {

    func testAFiniteFrameThatHasNotMovedHasSettled() {
        let rect = CGRect(x: 12, y: 34, width: 100, height: 44)
        XCTAssertTrue(
            frameHasSettled(previous: rect, current: rect),
            "two identical, finite reads must count as settled — this is the ordinary case every "
                + "other call in the suite relies on"
        )
    }

    func testAFiniteFrameThatMovedHasNotSettled() {
        let previous = CGRect(x: 12, y: 34, width: 100, height: 44)
        let current = CGRect(x: 12, y: 40, width: 100, height: 44)
        XCTAssertFalse(
            frameHasSettled(previous: previous, current: current),
            "two different reads must not count as settled, regardless of finiteness"
        )
    }

    /// **The red-proof.** Two IDENTICAL infinite reads are exactly what `CGRect.equalTo` alone
    /// would call settled. If this assertion is ever false, `settledFrame` is back to handing out
    /// a coordinate for nowhere — silently, because the loop's equality check would have no reason
    /// to keep waiting.
    func testTwoEqualInfiniteFramesHaveNotSettled() {
        let inf = CGRect(
            x: CGFloat.infinity, y: CGFloat.infinity,
            width: CGFloat.infinity, height: CGFloat.infinity
        )

        // This test's own premise, checked before the thing it is a premise for: if CGRect stopped
        // treating two infinite rects as equal, there would be nothing left for `frameHasSettled`
        // to guard against, and a false pass below would mean the premise broke, not that the fix
        // held.
        XCTAssertTrue(
            inf.equalTo(inf),
            "CGRect.equalTo no longer treats two infinite rects as equal — frameHasSettled's "
                + "finiteness check may no longer be doing anything, because plain equality would "
                + "already refuse this case"
        )

        XCTAssertFalse(
            frameHasSettled(previous: inf, current: inf),
            "two equal but infinite frames must not count as settled — an element XCUITest could "
                + "not resolve a real position for must never be handed to a caller as a coordinate"
        )
    }

    func testANonFiniteFrameIsNotFinite() {
        XCTAssertFalse(isFiniteFrame(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)))
        XCTAssertFalse(isFiniteFrame(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)))
        XCTAssertFalse(isFiniteFrame(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)))
    }

    func testAnOrdinaryFrameIsFinite() {
        XCTAssertTrue(isFiniteFrame(CGRect(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertTrue(isFiniteFrame(.zero))
    }
}
