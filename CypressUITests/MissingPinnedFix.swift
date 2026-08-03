import Foundation

/// **No fix is a failure here, not a skip (task #121).** These tests used to `XCTSkip` when the
/// simulator had given Cypress no location — an honest report of an environment fact, and invisible
/// in `Test run with N tests passed`, which counts a test that declined to run exactly the same as
/// one that ran and passed. The launch now *pins* the fix (`DebugLocationOverride`, ruling
/// `docs/rulings-pending/location-state-launch-seam.md`), so a screen 01 that still reports itself
/// fixless is a defect in the seam or in the wiring rather than a fact about this machine.
struct MissingPinnedFix: Error, CustomStringConvertible {
    let seen: String
    let pinned: String
    var description: String {
        "screen 01's recenter control reads “\(seen)” on a launch that pinned a fix at \(pinned), "
            + "so CYPRESS_LOCATION did not reach MapLocationProvider — this is not a machine "
            + "without a fix, it is a fix that did not arrive"
    }
}
