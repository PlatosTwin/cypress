//
//  VisitSaveLedger.swift
//  Cypress — Features/Visit
//
//  D9's counter, and the seam screen 15 will hang off.
//
//  ── The precedence call ───────────────────────────────────────────────────────────────────
//  SPEC-PHASE1 puts the account ask on the **first** save. DESIGN v3 and D9 put it on the
//  **third**. D9 wins: DECISIONS.md is binding and sits above SPEC-PHASE1 in the precedence stack
//  (ARCHITECTURE, header), and its reasoning is the whole point — "the signup wall landed the
//  maximum-friction event on second 8 of a ten-second street-corner visit."
//
//  ── The D1 line this walks ────────────────────────────────────────────────────────────────
//  D1 forbids "streaks, points, ranks, badges, or public counts of user actions", and ARCHITECTURE
//  §5.1 spells out the trap: "If you find yourself writing `visitCount` into a user-visible string,
//  stop." So this number is **never rendered**. It exists to answer one boolean — has the ask
//  already earned its interruption — and it is deliberately not exposed as a string anywhere.
//

import Foundation

/// The device-local save count, and the account ask it gates.
///
/// `UserDefaults` rather than `app_state`: the counter is a UI funnel fact, not a contribution.
/// It does not sync, it does not appear in an export, and putting it in the store would give it a
/// permanence it should not have.
@MainActor
final class VisitSaveLedger {

    /// D9: "the ask comes at the third save."
    static let accountAskThreshold = 3

    private let defaults: UserDefaults
    private let saveCountKey = "visit.saveCount"
    private let askResolvedKey = "visit.accountAskResolved"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Never rendered. See the D1 note above.
    private var saveCount: Int {
        get { defaults.integer(forKey: saveCountKey) }
        set { defaults.set(newValue, forKey: saveCountKey) }
    }

    /// Set once the user has either linked an account or declined. The ask never fires twice —
    /// `logVisit`'s guard in the prototype is `saves + 1 == 3 && account == 'none'`
    /// (PROTOTYPE-FLOW §1.6.3), and "none" is exactly "not yet resolved".
    private var isAskResolved: Bool {
        get { defaults.bool(forKey: askResolvedKey) }
        set { defaults.set(newValue, forKey: askResolvedKey) }
    }

    /// Records a save and answers whether this is the one that earns the account ask.
    func recordSave() -> Bool {
        saveCount += 1
        return saveCount == Self.accountAskThreshold && !isAskResolved
    }

    /// Called when screen 15 is dismissed either way — linked or "not now".
    func resolveAccountAsk() {
        isAskResolved = true
    }

    /// The storage line under the success block on 18, from PROTOTYPE-FLOW §1.4 `storageLine`.
    ///
    /// Only the anonymous case exists today, because there is no auth server (`CypressAPI` says so
    /// in as many words) and therefore no linked state to be in. The other two strings are the
    /// seam's other half and land with screen 15.
    var storageLine: String {
        isAskResolved
            ? "Saving to this phone only. You can add an account any time."
            : "Saved to this phone. You can add an account later to back it up."
    }

    /// Test seam. Nothing in the shipping flow calls this.
    func reset() {
        defaults.removeObject(forKey: saveCountKey)
        defaults.removeObject(forKey: askResolvedKey)
    }
}
