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

/// What screen 06 knows about a reminder.
///
/// The screen assembles the two facts it can honestly know — which tree, which hazard — and an id.
/// It does **not** decide who the reminder belongs to: D9's answer to that (the signed-in user, else
/// this device) lives behind `CypressAPI`, and a view deciding an identity question is a view
/// deciding something it cannot see. `ReminderOutboxWriter` turns this into a `PrivateReminder`.
struct PrivateReminderDraft: Hashable, Sendable {
    /// Minted once per selection, not per tap. It is the mutation's idempotency key in the outbox,
    /// so two taps on the same selected hazard save one reminder rather than two (ARCHITECTURE §4).
    let reminderID: UUID
    let treeID: UUID
    /// A `HazardCategory`, never a `CommunityNote.Category`. D4 at the type level.
    let category: HazardCategory

    init(reminderID: UUID = UUID(), treeID: UUID, category: HazardCategory) {
        self.reminderID = reminderID
        self.treeID = treeID
        self.category = category
    }
}

/// Where the reminder button is, between taps.
///
/// **NOT SPECIFIED** by SCREENS.md 06, which draws the button and no state after it. The restrained
/// reading is that the button has to answer the tap somehow — a control that does something and says
/// nothing is the thing DECISIONS constraint 3 is about, in the other direction. Recorded in ERRATA
/// (E23).
enum ReminderSaveState: Hashable {
    case idle
    case saving
    case saved
    /// The enqueue itself failed — the reminder is not on disk and nothing may say it is.
    case failed
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

    /// Reset whenever the selection changes: a reminder is about one hazard, so a different hazard
    /// is a different reminder and the confirmation for the old one must not stand over it.
    private(set) var reminderSaveState: ReminderSaveState = .idle

    /// The id the next save will carry. Minted per selected hazard so a double tap is one reminder.
    private var reminderID = UUID()

    let treeID: UUID
    private let api: any CypressAPI
    private let dialer: any TelephoneDialing
    private let onSaveReminder: ((PrivateReminderDraft) async throws -> Void)?

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
        onSaveReminder: ((PrivateReminderDraft) async throws -> Void)? = nil
    ) {
        self.selection = initialSelection
        self.treeID = treeID
        self.api = api
        self.dialer = dialer
        self.onSaveReminder = onSaveReminder
    }

    /// What ground this tree stands on, once the tree has been read. `nil` until then, and `nil`
    /// forever if the read fails.
    ///
    /// **The screen draws before this arrives and must be correct while it is missing**, which it is:
    /// `nil` is `HazardHandoff.city`, which is what screen 06 has always drawn. A load that never
    /// returns leaves the screen exactly as it shipped rather than in a degraded state, and the
    /// panel cannot flicker from "not the city's" into a 311 CTA — only the other way, and only once.
    private(set) var landContext: KnownLandContext?

    var presentation: ReportPresentation {
        ReportPresentation(selection: selection, landContext: landContext)
    }

    /// Reads the tree this report is about — the read `ReportModel` conspicuously did not do, which
    /// is what let a private tree get the city's telephone number (E143's flag, E146's fix).
    ///
    /// **`treeProfile` rather than a new protocol requirement.** It is the requirement the tree page
    /// already calls, it is a local SQLite read, and `Tree.landContext` is on the payload it returns.
    /// A narrower `landContext(of:)` on `CypressAPI` would be a second door onto one row, and E141
    /// spent a paragraph on why anything added to that protocol has to be a real requirement with a
    /// witness — the bar for adding one should be that nothing existing answers the question. One
    /// does.
    ///
    /// Failures are swallowed on purpose and this is the important half. A thrown read leaves
    /// `landContext` nil, nil is `.city`, and `.city` is the behaviour every build before this one
    /// had. There is no error path on which this screen becomes *less* able to route a safety
    /// report than it was — the same rule `logHazardRedirect` keeps one method down, for the same
    /// reason: nothing may stand between a contributor and a safety call.
    func load() async {
        landContext = try? await api.treeProfile(id: treeID).tree.landContext
    }

    /// Whether a reminder can be written at all — false only in previews, which stand up the screen
    /// without a composition root. The button is drawn either way, because SCREENS.md 06 §5 draws
    /// it, but a tap with nothing wired stays `.idle` and therefore says nothing: the screen never
    /// claims a save it did not make (DECISIONS constraint 3's principle).
    var canSaveReminder: Bool { onSaveReminder != nil }

    // MARK: - Picking

    func select(hazard: HazardCategory) async {
        selection = selection.hazard == hazard ? .nothing : .hazard(hazard)
        resetReminder()
        if let shown = selection.hazard {
            await logRedirectShown(shown)
        }
    }

    // There is no `select(note:)` any more, and its absence is the point (ERRATA E131). Screen 06's
    // neighborly chips are drawn and not tappable, because a `.note` selection had no reader
    // anywhere: no outbox kind, no submit CTA (ERRATA E22), and a `community_notes` row that account
    // deletion could not honour (RULINGS R3, ERRATA E109). `ReportView.notePicker` carries the whole
    // argument. A mutator with no caller is the same shape as the control it used to serve — from
    // the outside it still looks like a write path — so it is gone rather than left behind a
    // comment.
    //
    // `ReportSelection.note` itself stays: it is what makes "a hazard or a note, never both" a fact
    // about the type rather than a guard (D4), and `initialSelection` still stands the state up for
    // `ReportPreviews`.

    /// A new selection is a new reminder: a fresh idempotency key, and no stale confirmation.
    private func resetReminder() {
        reminderSaveState = .idle
        reminderID = UUID()
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
    /// its visit action: the composition root owns which service performs a mutation. What it hands
    /// over is what the screen can honestly know — this tree, this hazard — and the owner is
    /// resolved behind the boundary (D9, `ReminderOwner`). See ERRATA (E23) for why this was inert
    /// until the reminder could be owned by a device.
    ///
    /// A failure leaves `.failed`, not `.saved`. The confirmation is drawn from the state and from
    /// nothing else, so the screen cannot claim a save that did not reach the disk.
    func saveReminder() async {
        guard let category = selection.hazard, let onSaveReminder else { return }
        guard reminderSaveState != .saved, reminderSaveState != .saving else { return }
        reminderSaveState = .saving
        do {
            try await onSaveReminder(
                PrivateReminderDraft(reminderID: reminderID, treeID: treeID, category: category)
            )
            reminderSaveState = .saved
        } catch {
            reminderSaveState = .failed
        }
    }

    // MARK: - Analytics

    /// **Still fires on the private branch, and that is a decision** (E146). The event is
    /// `HazardRedirectEvent(treeID:category:)`, and the tree is on it — so the one query anybody
    /// would want to run against this table, *how often does a hazard land on a tree the city does
    /// not maintain*, is a join and not a gap. Suppressing the event on that branch would delete
    /// exactly the rows that measure the feature this round shipped, and would do it silently.
    ///
    /// It is also not untrue there: the panel is shown, and the number remains one tap away as
    /// `Call 311 anyway`. What the event has never recorded is whether anybody dialled.
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
