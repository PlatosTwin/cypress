//
//  RemoteGateComplaintUITests.swift
//  CypressUITests
//
//  A mistyped `CYPRESS_REMOTE` draws itself (#158 round 5).
//

import XCTest

/// **The one thing the gate must never do quietly: fail.**
///
/// `RemoteAccess` states the rule it inherits from `DebugLocationOverride` — a typo must not be
/// indistinguishable from a decision — and then round-4 review found the rule unkept. `.misconfigured`
/// behaved exactly like `.disabled`, `DataLayer` said "the composition root can draw the complaint",
/// and the precedent that sentence cited (`DebugLocationOverride`'s failure banner) really was drawn
/// twenty lines away while this one was not. A promise in a doc comment is the shape this project
/// keeps paying for.
///
/// ── Why this is a UI test and not a unit test ─────────────────────────────────────────────────
///
/// `RemoteAccessTests.aTypoIsOffAndComplains` already pins that `.misconfigured` produces a
/// non-nil `complaint` naming the raw value. That is the *string*. What review found missing was the
/// **surface** — nothing rendered it — and no unit test can tell the two apart, because the string
/// existed the whole time. So the assertion has to be made against the running app, which is the
/// only place "drawn" means anything.
///
/// It costs one launch and it stays hermetic: `.misconfigured` answers `false` to `allowsNetwork`,
/// so this test opens no socket either.
final class RemoteGateComplaintUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A value the gate does not understand is drawn over the app, quoting what was set.
    ///
    /// `nonsense` rather than a near-miss like `liv`, so the failure this test would report can
    /// never be read as "the parser was nearly right". The assertion is on the raw value appearing
    /// in the banner, because a complaint that did not quote what was actually set would leave
    /// somebody hunting for which of several launch variables was wrong.
    func testAMistypedRemoteGateDrawsItself() {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_REMOTE"] = "nonsense"
        app.launch()

        let banner = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "CYPRESS_REMOTE=nonsense"))
            .firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 20),
            """
            a CYPRESS_REMOTE value this build does not understand drew nothing. It is switched off, \
            which is the fail-safe half — and indistinguishable from somebody having switched it off \
            on purpose, which is exactly what RemoteAccess's own rule forbids.
            """
        )
    }

    /// The control, and the half that makes the assertion above a measurement.
    ///
    /// With **no** `CYPRESS_REMOTE` set — the ordinary state of every other test in this suite — the
    /// gate resolves `.disabled` and there must be no banner at all. Without this, a banner drawn
    /// unconditionally would pass the test above while covering the app in every run.
    func testTheDefaultDrawsNoComplaint() {
        let app = XCUIApplication()
        app.launch()

        let banner = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "CYPRESS_REMOTE"))
            .firstMatch
        XCTAssertFalse(
            banner.waitForExistence(timeout: 5),
            "the gate complained with nothing set, so every ordinary run draws a banner over the app"
        )
    }
}
