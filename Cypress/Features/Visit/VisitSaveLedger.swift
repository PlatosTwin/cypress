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

    /// How many times an unanswered ask may be put in front of somebody, across the app's life.
    ///
    /// ── Why this exists, and why it is two ────────────────────────────────────────────────────
    /// The guard used to be `saveCount == threshold`, a faithful transcription of the prototype's
    /// `saves + 1 == 3`. The prototype was never backgrounded. On a phone, the save that earns the
    /// ask and the moment the ask is answered are separated by a sheet presentation, and anything
    /// can happen in between — the app is suspended and killed, the sheet is swiped away before its
    /// dismissal handler runs. Equality means the fourth save moves the counter past the only value
    /// that could ever be true again, and D9's ask is gone for the life of the install (ERRATA E34).
    ///
    /// A plain `>=` is the other failure. It re-asks on every save until answered, and DECISIONS §3
    /// is built end to end on not pressuring a contributor — D1 kills the leaderboard, D9 exists
    /// only to move the auth sheet off "second 8 of a ten-second street-corner visit". An ask that
    /// returns every time somebody saves a tree is that friction handed back in instalments.
    ///
    /// Two is the smallest bound that fixes the loss without becoming the nag: the ask gets one
    /// second chance, on the next save after one that went unanswered, and then stops for good.
    /// D9 places the ask *at* the third save, which is the earliest it may appear, not the only
    /// save it may appear on.
    static let maxAccountAskPresentations = 2

    private let defaults: UserDefaults
    private let saveCountKey = "visit.saveCount"
    private let askResolvedKey = "visit.accountAskResolved"
    private let askPresentationsKey = "visit.accountAskPresentations"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Never rendered. See the D1 note above.
    private var saveCount: Int {
        get { defaults.integer(forKey: saveCountKey) }
        set { defaults.set(newValue, forKey: saveCountKey) }
    }

    /// Set once the user has either linked an account or declined. This is the answer, not the
    /// showing: `logVisit`'s guard in the prototype is `saves + 1 == 3 && account == 'none'`
    /// (PROTOTYPE-FLOW §1.6.3), and "none" is exactly "not yet resolved". Once true the ask is
    /// over for good, whatever `askPresentationCount` says.
    private var isAskResolved: Bool {
        get { defaults.bool(forKey: askResolvedKey) }
        set { defaults.set(newValue, forKey: askResolvedKey) }
    }

    /// How many times the ask has actually been put on screen. Never rendered either; it bounds the
    /// retry above, and it is persisted because the case it exists for is the app not surviving to
    /// the next launch.
    private var askPresentationCount: Int {
        get { defaults.integer(forKey: askPresentationsKey) }
        set { defaults.set(newValue, forKey: askPresentationsKey) }
    }

    /// Records a save and answers whether this is a save that earns the account ask.
    ///
    /// Returning `true` counts as a presentation, because the caller's only reason to ask is to
    /// show the sheet. If it turns out to be shown and not answered, the next save gets one more
    /// go — see `maxAccountAskPresentations` for why exactly one more.
    /// - Parameter mayAsk: whether this build is *able* to honour an ask (RULINGS **R4**). Default
    ///   `true`, because D9's rule is the ledger's job and a capability is not — the caller knows
    ///   whether there is a server to send a magic link, and this type never should.
    ///
    ///   Passing `false` still counts the save, because the count is a fact about somebody's field
    ///   work rather than about this build's capabilities, and it must not spend a presentation:
    ///   a gate placed after `askPresentationCount` would silently burn both of a person's two goes
    ///   while the feature is switched off, so that the day auth ships they are never asked at all.
    ///   That is a bug which cannot be observed until the thing it breaks is turned on.
    func recordSave(mayAsk: Bool = true) -> Bool {
        saveCount += 1
        guard mayAsk else { return false }
        guard !isAskResolved else { return false }
        guard saveCount >= Self.accountAskThreshold else { return false }
        guard askPresentationCount < Self.maxAccountAskPresentations else { return false }
        askPresentationCount += 1
        return true
    }

    /// Called when screen 15 closes, however it closes — linked, "not now", or swiped away.
    ///
    /// Every dismissal path has to reach this, which is why `VisitSavedModel` hands the sheet a
    /// binding whose setter calls it rather than a raw flag: an interactive dismissal that never
    /// resolved is precisely the state ERRATA E34 is about. Silence is never read as a decline —
    /// `storageLine` keeps saying an account can be added later, because nobody said otherwise.
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
        defaults.removeObject(forKey: askPresentationsKey)
    }
}
