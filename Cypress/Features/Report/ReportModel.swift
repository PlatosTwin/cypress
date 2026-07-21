//
//  ReportModel.swift
//  Cypress — Features/Report
//
//  Screen 06's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to the
//  telephone, and to nothing else — no store, no network (ARCHITECTURE §4).
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Telephone

/// Placing the call, behind a protocol so the model stays testable and previewable.
///
/// SCREENS.md 06's CTA is the whole point of the screen: the city has not been notified until the
/// contributor actually dials, so this is the one action on the screen with a real consequence.
/// Both calls are `async` and the protocol carries no global actor, so a dialer can be a default
/// argument (Swift evaluates those outside the caller's isolation) while the UIKit work still hops
/// to the main actor where it belongs.
protocol TelephoneDialing: Sendable {
    /// Whether this device can place a call at all. An iPad, a Mac and the simulator cannot.
    func canPlaceCall(to url: URL) async -> Bool
    /// Hands the number to the system dialer. `false` if the hand-off was refused.
    func placeCall(to url: URL) async -> Bool
}

/// The shipping dialer.
struct SystemTelephoneDialer: TelephoneDialing {

    func canPlaceCall(to url: URL) async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run { UIApplication.shared.canOpenURL(url) }
        #else
        return false
        #endif
    }

    func placeCall(to url: URL) async -> Bool {
        #if canImport(UIKit)
        return await UIApplication.shared.open(url)
        #else
        return false
        #endif
    }
}

// MARK: - The private reminder

/// What screen 06 knows about a reminder it cannot yet save.
///
/// A `Core.PrivateReminder` needs a `userID`, and there is no signed-in user on a device that has
/// never seen the account sheet (screen 15, unbuilt) — D9 makes the first saves anonymous under a
/// device id, while `private_reminders.user_id` is `NOT NULL` by D4's own reasoning. The two
/// decisions disagree, and this draft is the part the screen can honestly assemble. See ERRATA
/// (E23) and `ReportModel.saveReminder()`.
struct PrivateReminderDraft: Hashable, Sendable {
    let treeID: UUID
    /// A `HazardCategory`, never a `CommunityNote.Category`. D4 at the type level.
    let category: HazardCategory
}

// MARK: - Model

@MainActor
@Observable
final class ReportModel {

    /// The one selection. Picking a hazard clears any neighborly note and the reverse, because
    /// `ReportSelection` cannot hold both — which is D4 enforced by the type, not by a guard.
    private(set) var selection: ReportSelection = .nothing

    /// Raised when the CTA is tapped on a device with no dialer. **NOT SPECIFIED** by SCREENS.md;
    /// see `ReportCopy.callUnavailableTitle`.
    var isShowingCallUnavailable = false

    let treeID: UUID
    private let api: any CypressAPI
    private let dialer: any TelephoneDialing
    private let onSaveReminder: ((PrivateReminderDraft) async -> Void)?

    /// `POST /reports/hazard-redirect` is "logs that a 311 redirect was *shown*" (BUILD-PLAN §6), so
    /// it fires when the panel appears, not when the call is placed. One log per category per visit
    /// to the screen: re-tapping the same chip is the same showing.
    private var loggedCategories: Set<HazardCategory> = []

    /// `initialSelection` exists so the previews can stand up each of the three states — including
    /// the two SCREENS.md marks NOT SPECIFIED — without driving taps. The screen itself always
    /// opens on `.nothing`: nothing is preselected for a contributor.
    init(
        treeID: UUID,
        api: any CypressAPI,
        dialer: any TelephoneDialing = SystemTelephoneDialer(),
        initialSelection: ReportSelection = .nothing,
        onSaveReminder: ((PrivateReminderDraft) async -> Void)? = nil
    ) {
        self.selection = initialSelection
        self.treeID = treeID
        self.api = api
        self.dialer = dialer
        self.onSaveReminder = onSaveReminder
    }

    var presentation: ReportPresentation {
        ReportPresentation(selection: selection)
    }

    /// Whether a reminder can be written at all. The button is drawn either way — SCREENS.md 06 §5
    /// draws it — but nothing pretends a save happened when none can (DECISIONS constraint 3's
    /// principle: never claim a thing the app did not do).
    var canSaveReminder: Bool { onSaveReminder != nil }

    // MARK: - Picking

    func select(hazard: HazardCategory) async {
        selection = selection.hazard == hazard ? .nothing : .hazard(hazard)
        if let shown = selection.hazard {
            await logRedirectShown(shown)
        }
    }

    func select(note: CommunityNote.Category) {
        selection = selection.note == note ? .nothing : .note(note)
    }

    // MARK: - The call

    func callCity() async {
        guard let url = ReportCopy.telephoneURL else {
            isShowingCallUnavailable = true
            return
        }
        guard await dialer.canPlaceCall(to: url) else {
            isShowingCallUnavailable = true
            return
        }
        if await dialer.placeCall(to: url) == false {
            isShowingCallUnavailable = true
        }
    }

    // MARK: - The reminder

    /// D4: "after the 311 handoff only a private reminder on your own record remains, never public,
    /// never auto-staled."
    ///
    /// The draft is handed out rather than written here, for the same reason the profile hands out
    /// its visit action: the composition root owns which service performs a mutation. Today no
    /// service can — `CypressAPI` has no reminder write, the outbox has no kind for one, and
    /// `PrivateReminder` needs a user this app cannot yet have. Rather than fake a confirmation,
    /// this does nothing when nothing is wired. See ERRATA (E23).
    func saveReminder() async {
        guard let category = selection.hazard, let onSaveReminder else { return }
        await onSaveReminder(PrivateReminderDraft(treeID: treeID, category: category))
    }

    // MARK: - Analytics

    private func logRedirectShown(_ category: HazardCategory) async {
        guard !loggedCategories.contains(category) else { return }
        loggedCategories.insert(category)
        // Analytics only, no public record (BUILD-PLAN §6). A failure here must never stand between
        // a contributor and a safety call, so it is not surfaced and not retried.
        try? await api.logHazardRedirect(
            HazardRedirectEvent(treeID: treeID, category: category)
        )
    }
}
