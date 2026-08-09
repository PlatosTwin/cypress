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

    // MARK: - Whether the frame can answer a hittability question at all

    /// A 402 pt device, portrait — the width both CI and this project's own 16 Pro run at, and the
    /// one the second measured rectangle below was read on.
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    /// **The first frame that actually raised**, verbatim from CI run 31300530216's `ui (3)`, where
    /// `DeepLinkSweepTests.testNothingIsAnnouncedTwice` died: `{{inf, inf}, {0.0, 0.0}}`.
    func testTheFrameFromTheSweepFailureCannotAnswerHittability() {
        XCTAssertFalse(
            frameCanAnswerHittability(
                CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0),
                onScreen: screen
            ),
            "the exact frame that raised in run 31300530216 must be filtered out before "
                + "`isHittable` is asked about it"
        )
    }

    /// **The second frame that actually raised, and the one that makes the case for the screen
    /// argument.** `(-31.0, 850.0, 30.0, 30.0)` — the `"City tree, Southern Magnolia"` annotation in
    /// `DeepLinkVoiceOverTests.testPinAdjust`, read out of the element immediately before the read
    /// that raised, on a 402 pt device.
    ///
    /// It is finite. It is 30 × 30. Every condition a frame check without the screen would ask, it
    /// satisfies — which is not a deduction: a version of this guard without the screen was written,
    /// and the raise went straight through it on a watched run. What is wrong with it is that
    /// x −31 to −1 is entirely off the left edge, so XCUITest's fallback — sampling points inside
    /// the frame — has nothing on the glass to sample. Its message says exactly that: "no suggested
    /// hit points based on element frame".
    func testTheFrameFromThePinAdjustFailureCannotAnswerHittability() {
        XCTAssertFalse(
            frameCanAnswerHittability(CGRect(x: -31, y: 850, width: 30, height: 30), onScreen: screen),
            "a finite 30×30 rectangle lying wholly off the left edge of the screen must be "
                + "filtered out — this is the frame that raised in testPinAdjust, and a guard that "
                + "only asks about finiteness and area lets it through"
        )
    }

    /// The finiteness half, on its own. The sweep's frame fails two conditions at once, so it cannot
    /// show either one carrying weight by itself — a rectangle that is non-finite and has an
    /// interior can.
    func testANonFiniteFrameWithAnInteriorCannotAnswerHittability() {
        XCTAssertFalse(
            frameCanAnswerHittability(
                CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 44, height: 44),
                onScreen: screen
            ),
            "a rectangle XCUITest could not resolve a position for is not one to ask about "
                + "hittability, however large it claims to be"
        )
    }

    /// Emptiness on its own: a finite rectangle on the screen with no interior has no point to
    /// compute an activation point inside either.
    func testAFiniteFrameWithNoInteriorCannotAnswerHittability() {
        XCTAssertFalse(frameCanAnswerHittability(CGRect(x: 10, y: 10, width: 0, height: 44), onScreen: screen))
        XCTAssertFalse(frameCanAnswerHittability(CGRect(x: 10, y: 10, width: 44, height: 0), onScreen: screen))
        XCTAssertFalse(frameCanAnswerHittability(.zero, onScreen: screen))
    }

    /// The half that keeps the guard from being a filter that refuses everything. An ordinary
    /// control must still be asked, or every reachability filter in the suite would silently skip
    /// every element and the tests standing on them would check nothing.
    ///
    /// **Partly on the glass counts.** A control whose top is above the screen still has points
    /// inside the frame for XCUITest to sample, and whether it is *hittable* is then XCUITest's
    /// question to answer rather than a raise. The rule is "somewhere on the screen", not "wholly
    /// on it" — `PrimaryCTAReachabilityTests.isWhollyOnTheGlass` is the stronger claim, and it is a
    /// claim rather than a filter.
    func testAnOrdinaryFrameCanAnswerHittability() {
        XCTAssertTrue(
            frameCanAnswerHittability(CGRect(x: 18, y: 69, width: 44, height: 44), onScreen: screen)
        )
        XCTAssertTrue(
            frameCanAnswerHittability(CGRect(x: 18, y: -20, width: 44, height: 44), onScreen: screen),
            "a control half off the top of the screen has points to sample and must still be asked"
        )
    }
}
