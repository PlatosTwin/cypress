import Foundation
import Testing
@testable import Cypress

/// Screen 15 is not presented in the local beta (RULINGS **R4**), and the gate has to be the *cheap*
/// kind: it must stop the ask without spending anything the ask would have spent.
///
/// The gate deliberately does not live in `VisitSaveLedger`. That type implements D9 — the ask comes
/// at the third save, gets one second chance, and then stops — and D9 is true regardless of whether
/// this particular build has a server behind it. `AccountAskTests` pins that rule and keeps passing
/// unchanged, which is the point: a capability flag that had to rewrite six tests about a product
/// decision would have been sitting in the wrong place.
@MainActor
@Suite("Beta capability")
struct BetaCapabilityTests {

    /// The state of the build this suite describes. When accounts become available the two tests
    /// below stop describing anything, and they should be deleted along with the flag rather than
    /// adjusted to match.
    @Test("this build cannot sign anyone in")
    func accountsAreUnavailable() {
        #expect(BetaCapability.accountsAvailable == false)
    }

    /// Before R4 the third save returned `true` and `VisitSavedView` presented a screen that collects
    /// an email address with nowhere to send it.
    @Test("no number of saves earns an account ask when the build cannot honour one")
    func theAskIsNeverEarned() {
        let ledger = VisitSaveLedger(defaults: Self.emptyDefaults())
        for _ in 1...10 {
            #expect(ledger.recordSave(mayAsk: false) == false)
        }
    }

    /// **The half that is easy to get wrong, and invisible if you get it wrong.** A gate placed after
    /// the presentation counter would burn both of a person's two goes while the feature is switched
    /// off — so the day auth ships, they are never asked at all. Nothing in the current build can
    /// show that: the symptom only appears once the thing it breaks is turned on.
    ///
    /// Asserted through the defaults the ledger writes rather than through the ledger's own reads, so
    /// that a gate which stops the *reader* instead of the *writer* still fails here.
    @Test("a refused ask spends neither of the two presentations")
    func refusingCostsNothing() {
        let defaults = Self.emptyDefaults()
        let ledger = VisitSaveLedger(defaults: defaults)
        for _ in 1...10 { _ = ledger.recordSave(mayAsk: false) }

        // Mirrors a private constant on the ledger. Spelled out rather than reached for, because a
        // test that asks the ledger what key it uses cannot notice the ledger writing the wrong one.
        #expect(defaults.integer(forKey: "visit.accountAskPresentations") == 0)
        #expect(defaults.bool(forKey: "visit.accountAskResolved") == false)

        // And the goes are still there: the same ledger, asked by a build that can honour it, still
        // owes this person the ask D9 promises them.
        #expect(ledger.recordSave(mayAsk: true) == true)
    }

    /// The save itself is a fact about somebody's field work, not about this build's capabilities, so
    /// a refused ask must not stop the counter. If it did, a beta contributor's first ten visits
    /// would vanish from the count and the ask would arrive three saves after auth ships rather than
    /// immediately, which is D9 measured from the wrong zero.
    @Test("a refused ask still counts the save")
    func theSaveIsStillRecorded() {
        let defaults = Self.emptyDefaults()
        let ledger = VisitSaveLedger(defaults: defaults)
        _ = ledger.recordSave(mayAsk: false)
        _ = ledger.recordSave(mayAsk: false)
        #expect(ledger.recordSave(mayAsk: true) == true)
    }

    /// Suite-local `UserDefaults`: the ledger persists across launches by design, so a test sharing
    /// the app's suite would depend on whatever ran before it.
    private static func emptyDefaults() -> UserDefaults {
        let suite = "BetaCapabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
