import XCTest

/// Waiting for an element to become *reachable*, and saying which half failed when it does not.
///
/// WHY THIS EXISTS. Several tests did this:
///
///     XCTAssertTrue(element.waitForExistence(timeout: 10), "… is not in the accessibility tree")
///     XCTAssertTrue(element.isHittable, "… is present but cannot be activated")
///
/// The second line is a race by construction. `waitForExistence` returns the moment the element
/// enters the tree; hittability arrives later — after layout, after the launch animation, after
/// whatever is still drawing. On a quiet Mac the gap is invisible. On a three-core CI runner it is
/// not: `AccessibilityTreeTests.testTheFourTabsAreReachable` failed run 30871836674 with "the Map
/// tab is present but cannot be activated by an assistive technology", which reads like a genuine
/// accessibility defect and was a runner that had not finished laying out a tab bar.
///
/// That run is also what makes the case: the run before it was green on this test and red on
/// `SheetExitUITests` instead. Same tree, different victim — the signature of contention rather
/// than a defect, and a whole family of these assertions was waiting its turn to be the victim.
///
/// WHAT IS AND IS NOT WEAKENED. The element must still become hittable; nothing here accepts an
/// unreachable control. What stops being asserted is *how soon*, which no test here ever meant to
/// claim — the requirement is that a screen reader can activate the thing, not that it can do so
/// within one runloop turn of the element appearing.
///
/// NEGATIVE assertions are deliberately NOT routed through this. `XCTAssertFalse(tab.isHittable)`
/// — a tab behind a modal cover that must stay unreachable — is a different claim, and waiting for
/// something to *stop* being hittable would let a slow runner satisfy it by never having drawn.
extension XCTestCase {

    /// Waits for `element` to be both present and hittable, and fails naming which one it never
    /// managed.
    ///
    /// 30 seconds because the alternative to waiting is the flake this replaces: the ceiling is a
    /// liveness bound, and it costs nothing when the element is reachable — the wait returns as
    /// soon as the predicate holds.
    func assertReachable(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let reachable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        guard XCTWaiter.wait(for: [reachable], timeout: timeout) != .completed else { return }

        // Which half failed decides where to look, so the message says it rather than making the
        // reader guess from a single sentence that fits both.
        XCTFail(
            element.exists
                ? "\(description) is in the accessibility tree but never became hittable within "
                    + "\(Int(timeout))s — it is present and cannot be activated"
                : "\(description) never appeared in the accessibility tree at all within "
                    + "\(Int(timeout))s",
            file: file, line: line
        )
    }

    /// The element's frame once it has stopped moving.
    ///
    /// **A frame read mid-animation is a coordinate for somewhere the element no longer is.**
    /// `waitForExistence` returns as soon as a sheet's title enters the tree — which is while the
    /// card is still sliding up. A test that reads `title.frame.minY` at that instant and then
    /// starts a drag there begins the gesture wherever the card *was*: on the scrim above it, or
    /// on content below the handle band, neither of which dismisses anything. The sheet then
    /// stands there and the failure says the gesture was not read as a drag — true, and about the
    /// start point rather than the gesture.
    ///
    /// That is what run 30873340010 reported for `testCareLogDragDownDismisses` after the gesture
    /// itself had already been slowed down (#200): a runner slow enough to stretch the
    /// presentation animation past the moment the frame was read.
    ///
    /// Settled means two consecutive samples agree — see `frameHasSettled` for the finiteness half
    /// of that decision. The element must be hittable first by default, so this never reports the
    /// stable frame of something not yet presented.
    ///
    /// - Parameter requireHittable: whether the element must be *reachable* before its frame is
    ///   read, or merely present. Default `true`, which is every caller that reads a frame in order
    ///   to touch it.
    ///
    ///   **Pass `false` only when the assertion that follows is about the rectangle itself**, and
    ///   that is a correctness requirement rather than a convenience — found the hard way by task
    ///   #252. That ticket's defect was a control **covered** by a neighbor, and hittability is
    ///   exactly what an occlusion takes away: gating the measurement on it makes the frame
    ///   unreadable in precisely the state the assertion exists to catch, and the run then dies 30 s
    ///   later reporting the symptom instead of the geometry. Watched twice — a red-proof that went
    ///   red on "the recenter control … never became hittable" rather than on the overlap below it
    ///   (PR #51), and a full-suite run of #252's own guard reporting that same sentence where it
    ///   should have printed two rectangles.
    ///
    ///   It is **not** a way to make a flaky reachability wait go away. Nothing is weakened by it
    ///   only because the claim changes with it: "these two rectangles do not intersect" is a
    ///   different sentence from "a reader can press this", and a file that wants the second must
    ///   assert it separately — `assertReachable`, or this helper's default.
    func settledFrame(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 30,
        requireHittable: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect {
        if requireHittable {
            assertReachable(element, description, timeout: timeout, file: file, line: line)
        } else {
            let present = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"),
                object: element
            )
            if XCTWaiter.wait(for: [present], timeout: timeout) != .completed {
                XCTFail(
                    "\(description) never appeared in the accessibility tree at all within "
                        + "\(Int(timeout))s",
                    file: file, line: line
                )
            }
        }
        guard element.exists else { return .zero }

        var previous = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(150_000)
            let current = element.frame
            if frameHasSettled(previous: previous, current: current) { return current }
            previous = current
        }
        XCTFail(
            isFiniteFrame(previous)
                ? "\(description) never stopped moving within \(Int(timeout))s — its frame is "
                    + "still changing, so any coordinate taken from it is already stale"
                : "\(description)'s frame reads \(previous) — hittable, but XCUITest could not "
                    + "resolve a real position for it. A non-finite frame reads as \"stable\" to a "
                    + "plain equality check (see `frameHasSettled`), which is why that is not the "
                    + "whole test; any coordinate taken from this frame is not a position at all",
            file: file, line: line
        )
        return previous
    }
}

/// Whether every component of `rect` is a real, finite number.
///
/// A free function rather than a method, so a test can call it directly against a literal
/// `CGRect` — no live element, no simulator. See `frameHasSettled` for why this exists.
func isFiniteFrame(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite
        && rect.size.width.isFinite && rect.size.height.isFinite
}

/// Whether `current` counts as a settled read of an element, given the previous read: equal AND
/// finite.
///
/// **Why finiteness is checked separately from equality.** `settledFrame`'s loop decides "has
/// this stopped moving" by comparing two consecutive reads with `CGRect.equalTo`, and that
/// comparison treats `.infinity == .infinity` as `true`. An element XCUITest could not resolve a
/// real position for — a frame of `{{inf, inf}, {inf, inf}}`, read mid-transition on a contended
/// runner rather than raised as an error — therefore looks exactly like a frame that has settled
/// on the very first two samples: `equalTo` alone would hand a caller a coordinate for nowhere.
///
/// Split out to a free function, deliberately: the decision is pure `CGRect` arithmetic, and
/// `FrameFinitenessGateTests` proves it directly, with no live element and no simulator, the same
/// way `DragGestureGateTests` proves `deliberateDrag` is the suite's only spelling of a drag.
func frameHasSettled(previous: CGRect, current: CGRect) -> Bool {
    current.equalTo(previous) && isFiniteFrame(current)
}

/// Whether a rectangle is one `XCUIElement.isHittable` can be *asked about* without raising.
///
/// Three conditions, and **each one was measured rather than reasoned about** — the first draft of
/// this function had only the first two, and the raise it was written to stop went straight through
/// it on a watched run:
///
/// - **Finite.** `{{inf, inf}, {0.0, 0.0}}` is the frame CI run 31300530216 printed when
///   `DeepLinkSweepTests.testNothingIsAnnouncedTwice` died.
/// - **With an interior.** An activation point cannot be computed inside a rectangle with no
///   inside, and `{{10, 10}, {0, 0}}` is finite.
/// - **Somewhere on the screen.** `(-31.0, 850.0, 30.0, 30.0)` — finite, 30 × 30, a real rectangle
///   in every respect, and every point of it off the left edge of a 402 pt device. That is the
///   frame of the `"City tree, Southern Magnolia"` annotation that raised in
///   `DeepLinkVoiceOverTests.testPinAdjust`, read out of the element immediately before the read
///   that raised. XCUITest's fallback is to sample points *inside the frame*; when none of them is
///   on the screen there is nothing to sample, and the message says so — "no suggested hit points
///   based on element frame".
///
/// The third condition existed in `AccessibilityTreeTests` and this function was first written
/// without it, on the argument that a control scrolled off the glass has a perfectly good answer to
/// `isHittable`. **That argument is wrong for a map annotation**: a scrolled-away control is inside
/// its scroll view's window, while a MapKit annotation is placed in absolute screen coordinates and
/// can sit entirely outside them.
///
/// Pure `CGRect` arithmetic, so `FrameFinitenessGateTests` proves it against both measured
/// rectangles with no live element and no simulator, the same way `frameHasSettled` is proved.
/// Finiteness is tested first and `&&` short-circuits, so `intersects` is never handed an infinity.
func frameCanAnswerHittability(_ rect: CGRect, onScreen screen: CGRect) -> Bool {
    isFiniteFrame(rect) && rect.width > 0 && rect.height > 0 && rect.intersects(screen)
}

extension XCUIElement {

    /// `isHittable`, asked only when the element's frame can answer — `false` where the raw property
    /// would **raise**.
    ///
    /// **`isHittable` does not return `false` for an element XCUITest cannot compute an activation
    /// point for. It raises**, and the raise is the test failure:
    ///
    ///     Failed to determine hittability of StaticText at {{inf, inf}, {0.0, 0.0}}:
    ///     Activation point invalid and no suggested hit points based on element frame
    ///
    /// which is not a defect report about anything. That is CI run 31300530216's `ui (3)`, failing
    /// `DeepLinkSweepTests.testNothingIsAnnouncedTwice` — and the same sentence, on a Button rather
    /// than a StaticText, is what `DeepLinkVoiceOverTests.testPinAdjust` failed with on the run task
    /// #71 was written from.
    ///
    /// **Where it comes from.** Screen 01 is a full-bleed `Map` whose pins are SwiftUI annotations
    /// MapKit hosts and places itself, and a screen presented *over* the map tab root leaves those
    /// annotations in the accessibility tree behind it. An annotation the camera happens to place at
    /// or beyond the edge of the basemap can be in the tree with a frame XCUITest can resolve no
    /// activation point inside — and which annotations land in that state is a fact about where the
    /// camera is pointed, which is device state. So this failed on a device left pointed at one
    /// block and not on one left pointed at another.
    ///
    /// **The app frame is a parameter and not a convenience.** The two raises this suite has
    /// actually seen have *different* frames — `{{inf, inf}, {0.0, 0.0}}` and
    /// `(-31.0, 850.0, 30.0, 30.0)`, the second a perfectly ordinary 30 × 30 rectangle sitting off
    /// the left edge of the screen — and only the first is decidable from the element alone. A
    /// version of this without the screen was written, and watched to go through it unchanged on the
    /// run that produced the second.
    ///
    /// **Nothing is weakened, because it is the same judgment.** An element with no interior, one
    /// XCUITest could not resolve a position for, or one drawn entirely off the glass is not
    /// reachable by an assistive technology either — skipping it is exactly the answer `isHittable`
    /// was being asked for, expressed in a way that cannot raise. A test that means to *assert*
    /// reachability still says so: this is for the filter positions, where the property decides
    /// whether an element is examined at all, and `assertReachable` is for the claims.
    ///
    /// **This does not close the window, it narrows it.** `frame` and `isHittable` are two separate
    /// snapshots, so an element can still move between them on a contended runner. The pinned
    /// opening camera (`CYPRESS_MAP_CAMERA`, `DebugMapCamera`) is what stops the annotations getting
    /// into that state in the first place; this is the guard for everything that is not the map.
    func isHittableWithoutRaising(in app: XCUIApplication) -> Bool {
        guard frameCanAnswerHittability(frame, onScreen: app.frame) else { return false }
        return isHittable
    }
}

extension XCTestCase {

    /// A drag a thumb would actually produce, rather than the instantaneous sweep XCUITest defaults
    /// to.
    ///
    /// **Every synthesized drag in this suite goes through here, and that is the point** — #200 was
    /// diagnosed and fixed at one call site while an identical one sat two files away.
    /// `SheetExitUITests` got a slowed gesture; `MapPanTabSwitchUITests` kept
    /// `press(forDuration: 0.1, thenDragTo:)`, and
    /// `testADeliberatePanSurvivesLeavingForJournalAndBack` failed run 30884912660 on a CI runner
    /// with *"panning the map did not move the camera off the reader"* — the pan was never read as a
    /// pan. Two spellings of one gesture is how a fixed defect comes back under a different test's
    /// name, so there is now one spelling.
    ///
    /// The three numbers, none of them arbitrary:
    ///
    /// - **0.25 s of touch-down before any movement.** A recognizer needs to see a stationary touch
    ///   begin; 50–100 ms on a loaded three-core runner can be delivered as a single coalesced event
    ///   that never becomes a `began`.
    /// - **~500 pt/s instead of the default 1000.** Half the speed is twice the intermediate touch
    ///   events, which is what a recognizer actually integrates. A map pan and a sheet dismissal both
    ///   need the middle of the gesture, not just its endpoints.
    /// - **0.15 s held at the end.** So the release is unambiguously a release *at that position*
    ///   rather than the tail of a flick — which for a map is the difference between a pan and a
    ///   momentum scroll that drifts somewhere else.
    ///
    /// Roughly a second per drag. **Nothing asserted is weakened:** the gesture starts and ends at
    /// exactly the coordinates the caller asked for, and travels the same distance. What changes is
    /// only how convincingly the touch stream says "a finger did this".
    func deliberateDrag(from start: XCUICoordinate, to end: XCUICoordinate) {
        start.press(
            forDuration: 0.25,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(rawValue: 500),
            thenHoldForDuration: 0.15
        )
    }
}
