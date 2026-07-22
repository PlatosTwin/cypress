import Foundation
import Testing
@testable import Cypress

/// `VisitSaveLedger` — D9's "the ask comes at the third save", and what happens when the third save
/// asks and nobody answers.
///
/// The guard was `saveCount == accountAskThreshold`, faithful to a prototype that was never
/// backgrounded. On a phone the save that earns the ask and the answer to it are separated by a
/// sheet, and if the app dies in between, the counter walks past the only value that could ever be
/// true again and D9's ask is gone for the life of the install (ERRATA E34).
///
/// Each test builds its ledger over a private `UserDefaults` suite, and "the app relaunched" is a
/// second `VisitSaveLedger` over that same suite — which is exactly what a relaunch is, since the
/// ledger holds nothing in memory.
@MainActor
@Suite("Account ask")
struct AccountAskTests {

    /// A private defaults suite, torn down with the test that owns it so the suites cannot see each
    /// other's counters.
    private struct Sandbox {
        let name: String
        let defaults: UserDefaults

        init() {
            name = "cypress.tests.accountAsk.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: name) ?? .standard
            defaults.removePersistentDomain(forName: name)
        }

        /// A ledger reading that storage. Calling this a second time models a relaunch: the ledger
        /// keeps nothing in memory, so a new instance over the same suite is the same ledger.
        @MainActor
        func ledger() -> VisitSaveLedger { VisitSaveLedger(defaults: defaults) }

        /// Torn down from a `defer` rather than a `deinit`, so the suite's lifetime is not what
        /// decides when the counters are wiped.
        func tearDown() { defaults.removePersistentDomain(forName: name) }
    }

    @Test("the first two saves are anonymous and silent, and the third asks")
    func asksOnTheThirdSave() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        #expect(ledger.recordSave() == false)
        #expect(ledger.recordSave() == false)
        #expect(ledger.recordSave() == true)
    }

    @Test("an answered ask never returns")
    func resolvedNeverReturns() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        _ = ledger.recordSave()
        _ = ledger.recordSave()
        #expect(ledger.recordSave() == true)
        ledger.resolveAccountAsk()

        for _ in 0..<10 {
            #expect(ledger.recordSave() == false)
        }
    }

    /// The regression. The ask is presented on save 3, the app is suspended and killed before the
    /// sheet is dismissed, and the next save happens on a fresh launch.
    @Test("an ask that was never answered is offered again after the app dies")
    func unresolvedAskSurvivesTermination() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }

        let beforeTermination = sandbox.ledger()
        _ = beforeTermination.recordSave()
        _ = beforeTermination.recordSave()
        #expect(beforeTermination.recordSave() == true)
        // No `resolveAccountAsk()`: the process ends here.

        let afterRelaunch = sandbox.ledger()
        #expect(afterRelaunch.recordSave() == true)
    }

    /// And the other half: the re-offer is bounded, because DECISIONS §3 forbids pressuring a
    /// contributor and a `>=` would return the ask on every save for ever.
    @Test("an unanswered ask is offered exactly twice and then stops")
    func reofferIsBounded() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        #expect(ledger.recordSave() == false)  // 1
        #expect(ledger.recordSave() == false)  // 2
        #expect(ledger.recordSave() == true)   // 3 — the ask
        #expect(ledger.recordSave() == true)   // 4 — the one second chance
        for _ in 0..<20 {
            #expect(ledger.recordSave() == false)
        }
        #expect(VisitSaveLedger.maxAccountAskPresentations == 2)
    }

    @Test("answering the second offer ends it there")
    func answeringTheSecondOfferEndsIt() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        _ = ledger.recordSave()
        _ = ledger.recordSave()
        _ = ledger.recordSave()
        #expect(ledger.recordSave() == true)
        ledger.resolveAccountAsk()
        #expect(ledger.recordSave() == false)
    }

    /// Silence is not a decline. Two unanswered asks bound the interruption, but they must not
    /// change what the screen tells somebody about where their visit lives.
    @Test("an unanswered ask does not flip the storage line to the resolved wording")
    func silenceIsNotADecline() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()
        let unresolvedLine = ledger.storageLine

        for _ in 0..<6 { _ = ledger.recordSave() }
        #expect(ledger.storageLine == unresolvedLine)

        ledger.resolveAccountAsk()
        #expect(ledger.storageLine != unresolvedLine)
    }

    /// Resolving early — an account linked from somewhere other than screen 15 — keeps the ask from
    /// ever being owed.
    @Test("an ask resolved before the threshold never fires")
    func resolvedEarlyNeverFires() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        _ = ledger.recordSave()
        ledger.resolveAccountAsk()
        for _ in 0..<10 {
            #expect(ledger.recordSave() == false)
        }
    }

    @Test("reset clears the presentation count as well as the counter")
    func resetClearsEverything() {
        let sandbox = Sandbox()
        defer { sandbox.tearDown() }
        let ledger = sandbox.ledger()

        _ = ledger.recordSave()
        _ = ledger.recordSave()
        _ = ledger.recordSave()
        ledger.reset()

        #expect(ledger.recordSave() == false)
        #expect(ledger.recordSave() == false)
        #expect(ledger.recordSave() == true)
    }
}
