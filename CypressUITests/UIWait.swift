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
    /// Settled means two consecutive samples agree. The element must be hittable first, so this
    /// never reports the stable frame of something not yet presented.
    func settledFrame(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect {
        assertReachable(element, description, timeout: timeout, file: file, line: line)
        guard element.exists else { return .zero }

        var previous = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(150_000)
            let current = element.frame
            if current.equalTo(previous) { return current }
            previous = current
        }
        XCTFail(
            "\(description) never stopped moving within \(Int(timeout))s — its frame is still "
                + "changing, so any coordinate taken from it is already stale",
            file: file, line: line
        )
        return previous
    }
}
