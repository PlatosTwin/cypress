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

    // MARK: - Which element type a labeled container has settled into

    /// Drives `ContainerSpellingResolution` with synthetic rounds, 0.15 s apart — the interval
    /// `resolvedContainer`'s live loop uses — and reports what resolved and when.
    ///
    /// `rounds` is asked what exists at each sampled time, so a test writes the *history* of the
    /// tree rather than a list of calls. No live element, no simulator, no app launch.
    private func drive(
        until end: TimeInterval,
        window: TimeInterval = ContainerSpellingResolution.settlingWindow,
        rounds: (TimeInterval) -> [ContainerSpelling: CGRect]
    ) -> (spelling: ContainerSpelling, at: TimeInterval)? {
        var resolution = ContainerSpellingResolution(window: window)
        var time: TimeInterval = 0
        while time <= end {
            if let resolved = resolution.observe(rounds(time), at: time, onScreen: screen) {
                return (resolved, time)
            }
            time += 0.15
        }
        return nil
    }

    /// The legend as it is drawn while its species palette is still filling: a plain group, laid
    /// out, on the glass, with a perfectly measurable frame. Its only defect is that it is about to
    /// be replaced.
    private let unclampedLegend = CGRect(x: 16, y: 230, width: 370, height: 200)

    /// The legend once `MapLayout.legendMaxHeight` binds: the clamped `ScrollView`.
    private let clampedLegend = CGRect(x: 16, y: 230, width: 370, height: 262)

    /// **The red-proof, and the CI failure this whole helper exists for.**
    ///
    /// An `Other` that is present and still for the first two seconds of a launch and then gone,
    /// replaced by a `ScrollView`. Binding to the `Other` is exactly what the three hand-rolled
    /// copies did, and it is what made the test wait 30 s for an element that no longer existed.
    ///
    /// Note what is *not* enough to reject it: the frame is finite, has an interior, is on the
    /// screen, and does not move — so `frameCanAnswerHittability` and `frameHasSettled` both accept
    /// it. Only the duration does.
    func testATransientOtherIsNeverResolvedTo() {
        // The `Other` holds still for very nearly the whole window before it goes, which is the
        // boundary the rule actually has to hold at — not a transient so short that any duration
        // would have caught it.
        let goes = ContainerSpellingResolution.settlingWindow - 0.2
        let resolved = drive(until: 20) { time in
            if time < goes { return [.other: self.unclampedLegend] }
            if time < goes + 0.5 { return [:] }
            return [.scrollView: self.clampedLegend]
        }
        XCTAssertEqual(
            resolved?.spelling, .scrollView,
            "the resolver bound to \(resolved.map { "\($0.spelling)" } ?? "nothing") — an `Other` "
                + "that held still for the first \(goes) s of the launch and was then replaced by "
                + "a `ScrollView` must never be the answer, and the `ScrollView` must be"
        )
        XCTAssertGreaterThanOrEqual(
            resolved?.at ?? 0, goes + 0.5 + ContainerSpellingResolution.settlingWindow,
            "the `ScrollView` arrived at \(goes + 0.5) s and was resolved at \(resolved?.at ?? -1) "
                + "s, which is less than a full settling window after it appeared — the window is "
                + "not being counted from when the element actually arrived"
        )
    }

    /// The ordinary case, which is the half that stops this being a resolver that refuses
    /// everything: one spelling, present and still from the first sample, resolves as soon as the
    /// window has elapsed and not before.
    func testAStableSpellingResolvesOnceTheWindowHasElapsed() {
        let resolved = drive(until: 12) { _ in [.scrollView: self.clampedLegend] }
        XCTAssertEqual(resolved?.spelling, .scrollView)
        XCTAssertGreaterThanOrEqual(resolved?.at ?? 0, ContainerSpellingResolution.settlingWindow)
        XCTAssertLessThan(
            resolved?.at ?? .infinity, ContainerSpellingResolution.settlingWindow + 0.5,
            "a container that never moves must be resolved as soon as the window has passed; "
                + "waiting longer than that is a cost every caller pays for nothing"
        )
    }

    /// **A frame that keeps changing is a palette that is still arriving.** Each species that
    /// resolves its name adds a chip and grows the legend, and the height is the one channel that
    /// says so — so a container whose rectangle never repeats must never resolve, however long it
    /// has existed.
    func testAContainerWhoseFrameKeepsChangingNeverResolves() {
        let resolved = drive(until: 30) { time in
            [.other: CGRect(x: 16, y: 230, width: 370, height: 100 + time)]
        }
        XCTAssertNil(
            resolved,
            "a container whose frame changed on every sample for 30 s was resolved anyway, at "
                + "\(resolved?.at ?? -1) s — the settling half of the rule is not doing anything"
        )
    }

    /// Leaving the tree spends the credit. A spelling that was still for almost a full window,
    /// disappeared for one sample and came back must start its window again — otherwise a container
    /// being rebuilt could be resolved across the rebuild.
    func testLeavingTheTreeRestartsTheWindow() {
        let gap = ContainerSpellingResolution.settlingWindow - 0.2
        let resolved = drive(until: 20) { time in
            if (gap...(gap + 0.3)).contains(time) { return [:] }
            return [.scrollView: self.clampedLegend]
        }
        XCTAssertNotNil(resolved)
        XCTAssertGreaterThanOrEqual(
            resolved?.at ?? 0, gap + 0.3 + ContainerSpellingResolution.settlingWindow,
            "a container that vanished at \(gap) s and returned at \(gap + 0.3) s resolved at "
                + "\(resolved?.at ?? -1) s, which reuses credit it earned before the gap"
        )
    }

    /// A frame no coordinate can be taken from earns no credit either, however patiently it sits
    /// there — the same judgment `frameCanAnswerHittability` makes everywhere else in this file.
    func testAContainerWithAnUnusableFrameNeverResolves() {
        let offScreen = CGRect(x: -400, y: 850, width: 30, height: 30)
        XCTAssertNil(
            drive(until: 20) { _ in [.other: offScreen] },
            "a container lying wholly off the left edge of the screen was resolved as the "
                + "container to measure"
        )
    }
}
