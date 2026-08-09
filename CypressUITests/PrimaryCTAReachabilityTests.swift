import XCTest

/// **Every deep-linkable screen's primary CTA, at AX5, asserted rather than photographed** (task
/// #173; ruling `RULINGS R59`).
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
/// 4. **on the glass** — the whole frame can be brought inside the app's own frame. This is the
///    assertion that catches the E196 family directly: at AX5 the ramp pushes content wider and
///    taller than the layout budgeted for it, and screens 02 and 11 were found with their chrome
///    clipped off both edges. "Can be brought" rather than "is", because a CTA inside a scroll sits
///    wherever the scroll stopped and that is not a fact about the layout — see `reach`.
/// 5. **drawn** — the frame has a width and a height. Deliberately *not* a 44 pt tap-target
///    assertion; see `assertDrawn` for the false red that would have been.
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

    /// Once per class, before `testMemorialCTA` or any other test in it — see
    /// `DeepLinkOverrideReset` (ERRATA E217 "Still open"). This class does not conform to
    /// `DeepLinkHarness` (see that protocol's file comment), but `DeepLinkOverrideReset` is a free
    /// enum for exactly this reason.
    override class func setUp() {
        super.setUp()
        DeepLinkOverrideReset.performOnce()
    }

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
        // Screens 09 and 10 on this table are covers over the map tab root, and `buttonLabels`
        // reads every button in the app to compose its failure message. Same reason `DeepLinkHarness
        // .launch` pins the camera; the one spelling lives on `DebugMapCamera`.
        DebugMapCamera.pin(app)
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
            let spent = reach(control, in: app)
            XCTAssertTrue(
                control.exists && control.isHittable,
                "\(screen): the arming control '\(label)' never became reachable at AX5 after "
                    + "\(spent) swipes, so the CTA was never brought into the state this probe "
                    + "judges it in"
            )
            guard control.exists, control.isHittableWithoutRaising(in: app) else { return }
            control.tap()
        }

        let predicate = NSPredicate(format: "label IN %@", target.ctaLabels)
        let cta = app.buttons.matching(predicate).firstMatch
        let swipes = reach(cta, in: app, wholly: true)
        XCTAssertTrue(
            cta.exists,
            "\(screen): no button labeled \(target.ctaLabels.map { "“\($0)”" }.joined(separator: " or ")) "
                + "is in the accessibility tree at AX5, after \(swipes) swipes down the screen. "
                + "What is there instead: \(buttonLabels(app)). — " + target.note
        )
        guard cta.exists else { return }

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

        assertOnTheGlass(cta, in: app, screen: screen, swipes: swipes)
        assertDrawn(cta, screen: screen)
        assertNotElided(cta, screen: screen)

        print(
            "AX5 CTA \(screen) · label=“\(cta.label)” · frame=\(cta.frame) · "
                + "app=\(app.frame) · swipes=\(swipes)"
        )
        app.terminate()
    }

    /// Swipes up until `element` is hittable, or the budget runs out. Returns the swipes spent.
    ///
    /// **It swipes on absence as well as on presence, and the first draft did not — that is the
    /// whole reason this is a function rather than two lines.** The first version waited for the
    /// element to *exist* and only then scrolled it into view, on the reasonable-sounding premise
    /// that an off-screen element is still in the accessibility tree. On this app at AX5 that premise
    /// is false: screens 03 and 11 held their CTA in a scroll whose content the ramp made several
    /// screens long, and the control was not in the tree at all until the scroll had been dragged
    /// near it. Both screens failed with "no button labeled … is in the accessibility tree", which is
    /// a true sentence about the query and a false one about the app — the reader has that button,
    /// they just have to scroll. A probe that reported those as missing CTAs would have filed two
    /// defects that do not exist.
    ///
    /// So existence is polled inside the loop, and "reachable" means *reachable*: on screen where it
    /// is, or on screen within `scrollBudget` swipes. The caller asserts on `exists` and `isHittable`
    /// afterwards, and the swipe count it is handed goes into the failure message, so a screen that
    /// has crept from two swipes to seven says so before it crosses.
    ///
    /// Swipes on the app rather than on a named scroll view, because the screens on this list use
    /// several different containers and naming one per screen would be a second table to keep in
    /// step with the first.
    /// **`wholly` is the second thing this function got wrong, and the correction is the same shape
    /// as the first.** It stopped at `isHittable`, which asks only whether the element's *center*
    /// point receives the tap — so on screen 16, whose CTA is inside a `ScrollView` rather than
    /// pinned, the loop stopped with the button's bottom 56 pt below the glass and
    /// `assertOnTheGlass` failed on a state one more swipe would have fixed. That is a probe
    /// artifact reported as an AX5 defect, and filing it would have been worse than not looking.
    /// A CTA in a scroll is not "off the glass" because the scroll happens to be stopped short of
    /// it; it is off the glass when it **cannot be brought on**, which is what the budget now
    /// decides. Horizontal clipping — E196 items 1 and 3, content wider than the phone — no amount
    /// of vertical scrolling repairs, so it still spends the budget and still fails, correctly.
    ///
    /// The arming controls use the weaker `wholly: false`, because tapping needs a hittable center
    /// and nothing more; only the CTA under judgment is held to the whole rectangle.
    @discardableResult
    private func reach(_ element: XCUIElement, in app: XCUIApplication, wholly: Bool = false) -> Int {
        func satisfied() -> Bool {
            guard element.exists, element.isHittableWithoutRaising(in: app) else { return false }
            return wholly ? isWhollyOnTheGlass(element, in: app) : true
        }
        // One short wait first: a screen that has just been deep-linked is still settling, and every
        // CTA on the list that needs no scrolling at all is on the glass within this window.
        if element.waitForExistence(timeout: 6), satisfied() { return 0 }
        var swipes = 0
        while swipes < Self.scrollBudget {
            app.swipeUp()
            swipes += 1
            if satisfied() { return swipes }
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
    private func assertOnTheGlass(
        _ element: XCUIElement,
        in app: XCUIApplication,
        screen: String,
        swipes: Int
    ) {
        XCTAssertTrue(
            isWhollyOnTheGlass(element, in: app),
            "\(screen): the primary CTA “\(element.label)” could not be brought entirely onto the "
                + "glass at AX5 in \(swipes) swipes — its frame is \(element.frame) and the screen "
                + "is \(app.frame), so part of the control a reader is meant to press stays off the "
                + "edge. A frame wider than the screen is the E196 shape: content wider than the "
                + "phone, centered and clipped rather than wrapped"
        )
    }

    private func isWhollyOnTheGlass(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let glass = app.frame
        let frame = element.frame
        let slack: CGFloat = 0.5
        return frame.minX >= glass.minX - slack
            && frame.minY >= glass.minY - slack
            && frame.maxX <= glass.maxX + slack
            && frame.maxY <= glass.maxY + slack
    }

    /// Every button label on screen, for a failure message.
    ///
    /// **A missing CTA has two very different causes and the message has to tell them apart**: the
    /// control is genuinely absent, or the screen that arrived is not the screen the probe thinks it
    /// is. Without this list both read as "no button labeled X", which is a riddle — and this project
    /// has an errata entry for exactly that shape of report (E153: blaming the almanac for something
    /// else). Bounded, because a screen with sixty controls would drown the message it is in.
    private func buttonLabels(_ app: XCUIApplication) -> String {
        let appFrame = app.frame
        let labels = app.buttons.allElementsBoundByIndex
            .prefix(30)
            // The guarded spelling even here: this maps over EVERY button in the app, so on any
            // screen presented over the map tab root it reads screen 01's annotations. A failure
            // message that raises on its way to being composed replaces the diagnosis it was
            // written to give (`UIWait.swift`).
            .map { "“\($0.label)”\($0.isHittableWithoutRaising(onScreen: appFrame) ? "" : " (not hittable)")" }
        return labels.isEmpty ? "no buttons at all" : labels.joined(separator: ", ")
    }

    /// The control has a rectangle at all.
    ///
    /// **Deliberately not a 44 pt minimum-tap-target assertion, and the reason is a false red this
    /// probe would otherwise have filed.** `CypressSpacing.minTapTarget` is 44 and several controls
    /// on this list reach it through `cypressHitArea(_:)`, which puts a `Color.clear` of at least
    /// 44 × 44 in the *background* with its own `contentShape`. A SwiftUI background does not enlarge
    /// the view it sits behind, so the element's accessibility frame stays the size of the drawn
    /// label while the region that actually receives the tap is the larger one. Asserting 44 pt on
    /// the frame XCUITest reports would therefore measure the wrong rectangle and report a defect
    /// that does not exist — screen 11's `Add a reading` is a 13 pt bold link with exactly that
    /// arrangement. Tap targets are #183's question and are answered at the value level, with a
    /// tolerance, where the real geometry is in scope.
    private func assertDrawn(_ element: XCUIElement, screen: String) {
        let frame = element.frame
        XCTAssertGreaterThan(
            frame.width, 0,
            "\(screen): the primary CTA “\(element.label)” has no width at AX5"
        )
        XCTAssertGreaterThan(
            frame.height, 0,
            "\(screen): the primary CTA “\(element.label)” has no height at AX5"
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
