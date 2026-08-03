import Foundation
import Testing
@testable import Cypress

/// Screen 15 signs people in locally now (RULINGS **R4**, ERRATA **E124**): the composition root's
/// `onLink` mints a `userID` and `claimDevice`s this device's contributions onto it, so the ask no
/// longer dead-ends on a magic-link server this build does not have. `BetaCapability.accountsAvailable`
/// is the compile-time fact that turns the ask back on.
///
/// What this suite pins is the *seam*, not the product decision. D9 — the ask comes at the third save,
/// gets one second chance, then stops — is `VisitSaveLedger`'s and is pinned by `AccountAskTests`
/// unchanged. The `mayAsk:` parameter it exposes is the capability's half: a build that cannot honor
/// an ask (`onLink` nil, or this flag flipped off) must still *count* the save and must not *spend* a
/// presentation, so that the day it can honor one, the person is asked from the right zero rather
/// than never. That contract outlives the flag's current value, which is why it is still tested here.
@MainActor
@Suite("Beta capability")
struct BetaCapabilityTests {

    /// The state of the build this suite describes. It is `true` because sign-in completes on-device
    /// (E124); the ledger below is what earns the ask once it does.
    @Test("this build can sign someone in")
    func accountsAreAvailable() {
        #expect(BetaCapability.accountsAvailable == true)
    }

    /// The live wiring, end to end: the flag the app actually ships feeds the ledger, and by the
    /// third save it earns the ask. This is the test that would have caught the flag never being
    /// flipped — `accountsAreAvailable` pins the value, this pins that the value does something.
    @Test("with accounts available, the third save earns the ask")
    func theLiveFlagEarnsTheAsk() {
        let ledger = VisitSaveLedger(defaults: Self.emptyDefaults())
        #expect(ledger.recordSave(mayAsk: BetaCapability.accountsAvailable) == false)
        #expect(ledger.recordSave(mayAsk: BetaCapability.accountsAvailable) == false)
        #expect(ledger.recordSave(mayAsk: BetaCapability.accountsAvailable) == true)
    }

    /// The capability's other half, still reachable: a build that *cannot* honor an ask (`onLink`
    /// nil, or the flag off) earns none, however many saves it records.
    @Test("no number of saves earns an ask when the build cannot honor one")
    func theAskIsNeverEarnedWithoutCapability() {
        let ledger = VisitSaveLedger(defaults: Self.emptyDefaults())
        for _ in 1...10 {
            #expect(ledger.recordSave(mayAsk: false) == false)
        }
    }

    /// **The half that is easy to get wrong, and invisible if you get it wrong.** A gate placed after
    /// the presentation counter would burn both of a person's two goes while the feature is switched
    /// off — so the day it is switched on, they are never asked at all.
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

        // And the goes are still there: the same ledger, asked by a build that can honor it, still
        // owes this person the ask D9 promises them.
        #expect(ledger.recordSave(mayAsk: true) == true)
    }

    /// The save itself is a fact about somebody's field work, not about this build's capabilities, so
    /// a refused ask must not stop the counter. If it did, a contributor's first ten visits would
    /// vanish from the count and the ask would arrive three saves late rather than immediately, which
    /// is D9 measured from the wrong zero.
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
