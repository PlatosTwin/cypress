import XCTest

/// **Every deep-linkable screen's primary CTA, at AX5, asserted rather than photographed** (task
/// #173; ruling `docs/rulings-pending/ax5-primary-cta-probe.md`).
///
/// ── Why this is a UI test and not a unit test ─────────────────────────────────────────────────
/// It was tried in-process first and it cannot work. ERRATA E196 records the dead end and
/// `CypressTests/AccessibilityTests`' header records it at length: **SwiftUI builds no UIKit
/// accessibility tree in-process.** A `UIHostingController` in a key window, laid out, drawn and
/// given a run-loop turn reports `accessibilityElements` as an empty array and
/// `accessibilityElementCount()` as 0 for a plain labeled `Text`, with VoiceOver running or not,
/// because SwiftUI serves the accessibility server over its own bridge rather than through
/// `NSObject`'s container protocol. A structural "the primary CTA is in the AX5 accessibility tree"
/// assertion was built for #144, watched fail on every screen, and removed. E196's own closing line
/// is that asserting it needs XCUITest, and that this is a next-round ticket. This is that ticket.
///
/// ── What this adds to the sweep ───────────────────────────────────────────────────────────────
/// #144 made every shot suite render four appearances including `light-ax5` and `dark-ax5`, and its
/// inventory of AX5 defects (E196) was read off those pictures by a person. **The sweep
/// photographs; this asserts.** A picture is evidence only while somebody is looking at it; the nine
/// defects E196 lists were each found by eye and any of them could have arrived unseen in the round
/// before. What is mechanized here is the one property the pictures were being read *for*: on every
/// screen a reader can deep link to, at the top of the type ramp, the control that screen exists to
/// have pressed is present, reachable, and on the glass.
///
/// ── What it checks, and what it cannot ────────────────────────────────────────────────────────
/// Per screen, at `UICTContentSizeCategoryAccessibilityXXXL` on this device's own width:
///
/// 1. **exists** — the CTA is in the accessibility tree at all.
/// 2. **reachable** — hittable where it is, or hittable after at most `scrollBudget` swipes. A CTA
///    below the fold is not a defect; a CTA that never becomes hittable is.
/// 3. **enabled** — after the screen's own arming step, where it has one. A control drawn in its
///    disabled fill is a control a reader cannot press, and `PrimaryButton(isEnabled: false)` stays
///    in the tree, so `exists` alone would pass over it.
/// 4. **on the glass** — the frame lies inside the app's own frame. This is the assertion that
///    catches the E196 family directly: at AX5 the ramp pushes content wider and taller than the
///    layout budgeted for it, and screens 02 and 11 were found with their chrome clipped off both
///    edges.
/// 5. **big enough to press** — at least `CypressSpacing.minTapTarget` (44 pt) tall.
/// 6. **no ellipsis inside the label** — see the honesty note below.
///
/// **The honesty note, because a probe that claims more than it checks is worse than one that states
/// its limits.** `XCUIElement.label` is the accessibility label — the string SwiftUI was *handed* —
/// and not the glyphs that were *drawn*. A `Text` that truncates to `Continue with Goo…` on the
/// glass still reports its whole string to XCUITest. So check 6 catches only truncation that
/// happened before rendering: a presentation layer that shortened its own copy, or a label built
/// from an already-elided string. **It does not catch visual mid-word clipping inside a button whose
/// frame is on screen**, which is exactly what E196 items 5, 6 and 7 are, and no XCUITest API on this
/// platform exposes it. Those stay the sweep's job, and the ruling says so rather than letting this
/// file imply otherwise. What check 4 *does* catch that a picture makes easy to miss is a CTA pushed
/// off the edge of the glass entirely — E196 items 1 and 3.
///
/// The trailing-position exemption in check 6 is not a loophole. `Share…` is a real CTA on screen 10
/// and its ellipsis is copy, not damage; an ellipsis anywhere *else* in a label is a string that was
/// cut. That is the only distinction the API leaves room for.
///
/// ── Scope ─────────────────────────────────────────────────────────────────────────────────────
/// The deep-linkable screens **that have a primary CTA**. `DebugDeepLink.Screen` also opens screens
/// that have none — `outbox`, `activity`, `journalList` and `grove` are readers and lists whose only
/// controls are navigation chrome, and `species`' content forks on whether there is a fix. Naming
/// them here rather than quietly omitting them is the point: a table with a hole in it and no note
/// beside the hole is how a probe comes to be believed about screens it never visited. `journal`'s
/// CTA is real but conditional on a coverage gap existing in the resolved neighborhood, which is a
/// property of the seed and the fix rather than of the screen, so it is asserted by
/// `AlmanacGroupTapTests` instead — which since task #121 pins its own fix and no longer skips.
///
/// **Black-box like the rest of `CypressUITests`**: nothing imports `Cypress`, every anchor is a
/// word the app says out loud, and every literal below is a copy constant repeated by hand. If a CTA
/// is renamed this fails, which is correct — the control a reader presses just changed its name.
final class PrimaryCTAReachabilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The table

    /// One screen, and the control it exists to have pressed.
    private struct Target {
        /// `DebugDeepLink.Screen`'s raw value.
        let screen: String
        /// A static text that proves the screen arrived, matched by prefix.
        let anchor: String
        /// The CTA's accessibility label(s). More than one where the app legitimately draws either.
        let ctaLabels: [String]
        /// Controls to press before the CTA can be judged, in order. Each must exist.
        ///
        /// **Not a workaround — the state being tested.** Screen 16's save is disabled until a
        /// reading is entered and screen 09's `Done` until a care chip is on; those are specified
        /// states (PROTOTYPE-FLOW §1.3/§1.4), and a probe that read the disabled control and called
        /// it reachable would be asserting the opposite of what it says. Screen 06 draws no CTA at
        /// all until a hazard is chosen, which is the same shape one step further.
        var arm: [String] = []
        /// Why this screen is here, for whoever reads a failure.
        let note: String
    }

    /// Every deep-linkable screen with a primary CTA. See the type comment for the ones without.
    ///
    /// The literals are `PrimaryButton`/`SecondaryOutlineButton` titles resolved from their copy
    /// enums: `CheckInCopy.saveCTA`, `MeasureCopy.saveCTA`, `CareLogCopy.doneCTA`,
    /// `VisitPinAdjustCopy.confirm`, `TreeProfilePresentation.ctaTitle` (two-valued),
    /// `PinSetPresentation.showWhere`, `GrowthHistoryCopy.addReading`, `ReportCopy.saveReminder`,
    /// and `ShareDestination.copyLink.label`.
    private static let targets: [Target] = [
        Target(
            screen: "treeProfile",
            anchor: "Tree",
            ctaLabels: ["Be the first to photograph this tree", "Visit · say hello with a photo"],
            note: "screen 03 cold — the CTA is inside the scroll, so at AX5 it is the one most "
                + "likely to need scrolling to reach"
        ),
        Target(
            screen: "photoHero",
            anchor: "Best photo",
            ctaLabels: ["Visit · say hello with a photo", "Be the first to photograph this tree"],
            note: "screen 03 warm — a hero photograph above the CTA changes the scroll length "
                + "entirely, which is a different geometry from the cold profile"
        ),
        Target(
            screen: "checkIn",
            anchor: "Check-in",
            ctaLabels: ["Save check-in"],
            note: "screen 05 — the CTA is pinned below the scroll, so at AX5 it is the ramp "
                + "squeezing the scroll rather than the button"
        ),
        Target(
            screen: "measure",
            anchor: "Measure",
            ctaLabels: ["Save measurement"],
            arm: ["3"],
            note: "screen 16 — a keypad above a pinned CTA is the tightest vertical budget in the app"
        ),
        Target(
            screen: "careLog",
            anchor: "Care log",
            ctaLabels: ["Done"],
            arm: ["Watered"],
            note: "screen 09 — a cover rather than a push, and E196 already found its optional-well "
                + "placeholder ellipsizing at AX5"
        ),
        Target(
            screen: "report",
            anchor: "Report an issue",
            ctaLabels: ["Save a private reminder for yourself"],
            arm: ["Hanging limb"],
            note: "screen 06 — the longest CTA label in the app, and it only appears once a hazard "
                + "is chosen"
        ),
        Target(
            screen: "site",
            anchor: "No tree at this site",
            ctaLabels: ["Show me where this is"],
            note: "the vacant planting site (E107) — its one affordance"
        ),
        Target(
            screen: "memorial",
            anchor: "Removed by the city",
            ctaLabels: ["Show me where this is"],
            note: "screen 19 — the one thing there is to press, and E196 found the name column "
                + "beside its badge collapsing at AX5"
        ),
        Target(
            screen: "growthHistory",
            anchor: "Growth",
            ctaLabels: ["Add a reading"],
            note: "screen 11 — E196 found this screen overflowing the glass horizontally at AX5, so "
                + "its CTA's frame is the check that matters here"
        ),
        Target(
            screen: "share",
            anchor: "Share this tree",
            ctaLabels: ["Copy link"],
            note: "screen 10 — E196 found its action captions fragmenting to nonsense at AX5. "
                + "`Copy link` rather than `Share…`, whose own trailing ellipsis is copy"
        ),
        Target(
            screen: "pinAdjust",
            anchor: "Move the pin",
            ctaLabels: ["Use this spot"],
            note: "the community add's pin step — a CTA over a full-bleed map, which is the one "
                + "layout on this list with nothing behind it to push against"
        ),
    ]

    // MARK: - The probe

    /// Each screen gets its own case, so a failure names the screen in the test name and one broken
    /// screen does not hide the ten behind it.
    func testTreeProfileCTA()    { probe("treeProfile") }
    func testPhotoHeroCTA()      { probe("photoHero") }
    func testCheckInCTA()        { probe("checkIn") }
    func testMeasureCTA()        { probe("measure") }
    func testCareLogCTA()        { probe("careLog") }
    func testReportCTA()         { probe("report") }
    func testSiteCTA()           { probe("site") }
    func testMemorialCTA()       { probe("memorial") }
    func testGrowthHistoryCTA()  { probe("growthHistory") }
    func testShareCTA()          { probe("share") }
    func testPinAdjustCTA()      { probe("pinAdjust") }

    /// A guard on the table itself.
    ///
    /// **Because the loop above is hand-written and the table is data**, and the failure mode of that
    /// arrangement is a screen quietly added to the table with no `test…` method calling it — a
    /// target that is never probed and a suite that reports nothing missing. This is the same shape
    /// as `Test run with 0 tests passed`: a green line over work that did not happen.
    func testEveryTargetInTheTableIsProbed() {
        XCTAssertEqual(
            Self.targets.count, 11,
            "the target table changed size and the per-screen test methods above did not — a target "
                + "with no method is a screen this suite reports on and never visits"
        )
        XCTAssertEqual(
            Set(Self.targets.map(\.screen)).count, Self.targets.count,
            "two targets name the same screen, so one of them is shadowed"
        )
    }

    // MARK: - Harness

    private static let screenKey = "CYPRESS_SCREEN"

    /// AX5 — `accessibilityExtraExtraExtraLarge`, the top of the ramp. Same mechanism
    /// `MapFilterAccessibilityTests.launchAtAX5` uses, which is the launch argument iOS itself reads.
    private func launchAtAX5(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.screenKey] = screen
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    /// How many swipes a CTA below the fold may cost before it counts as unreachable.
    ///
    /// Eight, which at AX5 is far more than any screen on the list needs and few enough that a CTA
    /// that never arrives fails in under a minute rather than hanging. The number of swipes actually
    /// spent is printed on every screen, so a screen creeping toward the budget is visible before it
    /// crosses it.
    private static let scrollBudget = 8

    private func target(_ screen: String) -> Target {
        guard let match = Self.targets.first(where: { $0.screen == screen }) else {
            XCTFail("no target in the table for '\(screen)'")
            return Target(screen: screen, anchor: "", ctaLabels: [], note: "")
        }
        return match
    }

    private func probe(_ screen: String) {
        let target = target(screen)
        guard !target.ctaLabels.isEmpty else { return }
        let app = launchAtAX5(screen)

        // The harness draws its own failures rather than logging them, so a resolution that found no
        // record cannot masquerade as a screen that opened (`DebugDeepLink.Failure`). Read first,
        // because "none among the 500 records nearest …" is an answer and "'Done' is not in the
        // tree" is a riddle.
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        let arrived = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", target.anchor))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches a 195,309-row
        // seed before the first screen can resolve a record.
        guard arrived.waitForExistence(timeout: 30) else {
            if banner.exists {
                XCTFail("\(screen): \(banner.label)")
            } else {
                XCTFail(
                    "\(screen): the app launched at AX5 but '\(target.anchor)' never appeared, so "
                        + "the screen this probe reports on did not open — \(target.note)"
                )
            }
            return
        }

        for label in target.arm {
            let control = app.buttons[label]
            XCTAssertTrue(
                control.waitForExistence(timeout: 15),
                "\(screen): the arming control '\(label)' is not on this screen at AX5, so the CTA "
                    + "was never brought into the state this probe judges it in"
            )
            guard control.exists else { return }
            scrollIntoReach(control, in: app, screen: screen, what: "the arming control '\(label)'")
            control.tap()
        }

        let predicate = NSPredicate(format: "label IN %@", target.ctaLabels)
        let cta = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(
            cta.waitForExistence(timeout: 20),
            "\(screen): no button labeled \(target.ctaLabels.map { "“\($0)”" }.joined(separator: " or ")) "
                + "is in the accessibility tree at AX5 — \(target.note)"
        )
        guard cta.exists else { return }

        let swipes = scrollIntoReach(cta, in: app, screen: screen, what: "the primary CTA")
        XCTAssertTrue(
            cta.isHittable,
            "\(screen): the primary CTA “\(cta.label)” is in the tree but never became hittable "
                + "after \(Self.scrollBudget) swipes at AX5, so a reader cannot press it"
        )
        XCTAssertTrue(
            cta.isEnabled,
            "\(screen): the primary CTA “\(cta.label)” is drawn disabled at AX5"
                + (target.arm.isEmpty ? "" : " even after \(target.arm.joined(separator: ", "))")
        )

        assertOnTheGlass(cta, in: app, screen: screen)
        assertPressable(cta, screen: screen)
        assertNotElided(cta, screen: screen)

        print(
            "AX5 CTA \(screen) · label=“\(cta.label)” · frame=\(cta.frame) · "
                + "app=\(app.frame) · swipes=\(swipes)"
        )
        app.terminate()
    }

    /// Swipes up until `element` is hittable, or the budget runs out. Returns the swipes spent.
    ///
    /// Swipes on the app rather than on a named scroll view, because the screens on this list use
    /// several different containers and naming one per screen would be a second table to keep in
    /// step with the first.
    @discardableResult
    private func scrollIntoReach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        screen: String,
        what: String
    ) -> Int {
        var swipes = 0
        while !element.isHittable && swipes < Self.scrollBudget {
            app.swipeUp()
            swipes += 1
        }
        return swipes
    }

    /// The frame lies inside the app's own frame.
    ///
    /// **This is the check E196's inventory is about.** Items 1 and 3 are screens whose content is
    /// wider than 393 pt and centered rather than wrapped, so the chrome runs off both edges; a
    /// control in that state has part of itself outside the glass whether or not its center is still
    /// hit-testable. `isHittable` only asks about the center point and would pass a button with half
    /// of it off screen, which is why this is a separate assertion rather than an implication of the
    /// one above.
    ///
    /// A half-point tolerance, because frames arrive in device points off a 3× screen and an exact
    /// comparison would fail on a rounding nobody can see.
    private func assertOnTheGlass(_ element: XCUIElement, in app: XCUIApplication, screen: String) {
        let glass = app.frame
        let frame = element.frame
        let slack: CGFloat = 0.5
        let outside = frame.minX < glass.minX - slack
            || frame.minY < glass.minY - slack
            || frame.maxX > glass.maxX + slack
            || frame.maxY > glass.maxY + slack
        XCTAssertFalse(
            outside,
            "\(screen): the primary CTA “\(element.label)” is not entirely on the glass at AX5 — "
                + "its frame is \(frame) and the screen is \(glass), so part of the control a reader "
                + "is meant to press is drawn off the edge"
        )
    }

    /// 44 pt, which is `CypressSpacing.minTapTarget` — the number `MapRecenterButton` is drawn at
    /// exactly and the one #183's hit-area assertions compare against with a tolerance.
    ///
    /// A CTA can only get *taller* as the ramp grows, so this is not the assertion most likely to
    /// fail; it is here because a control squeezed by a `.frame(maxHeight:)` somebody added to make
    /// a layout fit at AX5 would fail nothing else on this list.
    private func assertPressable(_ element: XCUIElement, screen: String) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(
            frame.height, 44 - 0.5,
            "\(screen): the primary CTA “\(element.label)” is \(frame.height) pt tall at AX5, under "
                + "the 44 pt minimum tap target"
        )
        XCTAssertGreaterThan(
            frame.width, 0,
            "\(screen): the primary CTA “\(element.label)” has no width at AX5"
        )
    }

    /// No ellipsis inside the label. See the type comment for what this can and cannot mean.
    private func assertNotElided(_ element: XCUIElement, screen: String) {
        let label = element.label
        let trimmed = label.hasSuffix("…") ? String(label.dropLast()) : label
        XCTAssertFalse(
            trimmed.contains("…") || trimmed.contains("..."),
            "\(screen): the primary CTA's label is “\(label)”, which carries an ellipsis inside it — "
                + "the string handed to the control was already cut before it was ever drawn"
        )
    }
}
