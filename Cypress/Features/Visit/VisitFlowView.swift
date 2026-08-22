//
//  VisitFlowView.swift
//  Cypress — Features/Visit
//
//  The ten-second loop: **02 → 04 → 18 → 04 → 18 → …**
//
//  Screen 18's "Next nearest" goes straight back to the *camera*, not to the shortlist — that is
//  PROTOTYPE-FLOW's `nextAction` (`{screen:'camera', treeIdx: treeIdx+1, snapped:false, note:'',
//  chips:{…}}`), and it is the whole reason a ten-tree morning moves along on its own. Advancing
//  clears the shot, the note and every chip; so does re-entering the camera from the shortlist
//  (§1.6.11 and §1.6.12). Here that is free, because each camera gets a fresh model keyed on the
//  tree it is for.
//
//  ── Two ways in, and one way to make a tree (ERRATA E127) ─────────────────────────────────
//  The loop above is what the map's FAB starts: nobody has said which tree this is, so 02 asks. The
//  profile's own photo CTA is the other entrance, and there the question is already answered — the
//  reader is standing on that tree's page. `startingTreeID` opens the camera for it directly.
//
//  "None of these? Add this tree" is the third step, and it is the one this flow could not take: the
//  button was drawn at full opacity and wired to dismiss the flow. See `VisitAddTreeView`.
//

import SwiftUI

struct VisitFlowView: View {

    /// The tree a camera is pointed at.
    ///
    /// `VisitCandidate` is screen 02's *row* — it carries a distance measured from a fix, a tell and
    /// a placeholder thumbnail, none of which the camera or the success screen reads. Two of this
    /// flow's three entrances have no shortlist behind them at all (the profile CTA, and a tree this
    /// flow has just created), so the row would have to be faked to carry them: a `distanceM` of 0
    /// asserts the reader is standing on top of the trunk. This is the three facts screens 04 and 18
    /// actually need, and nothing that would have to be invented to fill it.
    struct Subject: Equatable, Identifiable {
        let id: UUID
        let displayName: String
        /// Screen 18 ranks the next nearest tree from where this one is when there is no fix.
        let coordinate: Coordinate

        init(id: UUID, displayName: String, coordinate: Coordinate) {
            self.id = id
            self.displayName = displayName
            self.coordinate = coordinate
        }

        init(_ candidate: VisitCandidate) {
            self.init(
                id: candidate.id,
                displayName: candidate.displayName,
                coordinate: candidate.tree.coordinate
            )
        }

        init(_ profile: TreeProfile) {
            self.init(
                id: profile.tree.id,
                displayName: TreeProfilePresentation(profile: profile).title,
                coordinate: profile.tree.coordinate
            )
        }
    }

    private enum Step: Equatable {
        case identify
        /// Reading the record for a tree the caller named, so the camera can put its name in the
        /// header. One frame on a local database, and the honest thing to draw for it is a spinner.
        case resolving(UUID)
        case camera(Subject)
        case addTree
        case saved(receipt: VisitSaveReceipt, tree: Subject)

        static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.identify, .identify), (.addTree, .addTree): return true
            case let (.resolving(a), .resolving(b)): return a == b
            case let (.camera(a), .camera(b)): return a.id == b.id
            case let (.saved(a, at), .saved(b, bt)):
                return a.visit.id == b.visit.id && at.id == bt.id
            default: return false
            }
        }
    }

    let api: any CypressAPI
    let outbox: OutboxQueue
    let deviceID: UUID
    /// The signed-in user, when there is one. Nil is the normal Phase 1 case (D9).
    var userID: UUID?

    /// The tree this flow was opened *for*, when it was opened for one. Nil is the map's entrance:
    /// screen 02 asks. See the file comment.
    var startingTreeID: UUID?

    /// Screen 15's sign-in action, from the composition root (ERRATA E124). Nil is still a valid
    /// build — it renders 15's "not ready yet" notice — but the local build supplies one.
    var onLink: AccountAskLink?

    /// Abandoning the flow — the shortlist's back chevron, and the camera's ✕.
    ///
    /// Nothing has been contributed on either, so the container is free to land wherever it likes; in
    /// practice it dismisses the cover onto the screen that opened it.
    var onExit: () -> Void = {}

    /// **Leaving the flow for the map** — screen 18's second control (ERRATA E151).
    ///
    /// Separate from `onExit`, which it used to be wired to, because the two mean different things and
    /// the container can only act on the difference if it can see it. Abandoning is relative — go back
    /// where you were. This one is a destination: a contribution has been made, and "back where you
    /// were" is the tree profile they photographed from, which is the one place the person pressing
    /// this does *not* want to be. Defaults to `onExit` so a caller that has no opinion behaves as
    /// before rather than silently doing nothing.
    ///
    /// **It was `onDone`, for a control that said "Done for today".** The destination has not moved —
    /// it was `goToMap()` then and it is `goToMap()` now — and the owner's ruling of 2026-08-21
    /// (RULINGS R80, item 6a) is that the control names the map rather than the end of a morning.
    /// See `VisitSavedView`.
    var onBackToMap: (() -> Void)?
    /// Screen 18's "back to this tree" (screen 03), and where a tree this flow has just added goes.
    var onOpenTree: (UUID) -> Void = { _ in }
    /// "Route done · see your grove" (screen 08).
    var onOpenGrove: () -> Void = {}

    @State private var location = VisitLocationProvider()
    @State private var ledger = VisitSaveLedger()
    @State private var step: Step = .identify
    @State private var visitedTreeIDs: [UUID] = []

    private var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }

    var body: some View {
        content
            // `startingTreeID` is read here rather than in an initializer because `step` is
            // `@State`: a `State` default assigned in `init` is only used the first time the view's
            // storage is created, and this view is created fresh by the cover each time anyway. One
            // place decides which screen the flow opens on, and it is this.
            .task {
                if case .identify = step, let startingTreeID {
                    step = .resolving(startingTreeID)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .identify:
            VisitIdentifyView(
                api: api,
                location: location,
                onPick: { candidate in step = .camera(Subject(candidate)) },
                onAddTree: { step = .addTree },
                onBack: onExit
            )

        case let .resolving(treeID):
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CypressColor.surfaceScreen)
                .task {
                    // A record that will not load is a tree this flow cannot name, and 02 is the
                    // screen whose whole job is to establish which tree this is. Falling back to it
                    // is the honest recovery; falling back to the camera would open a viewfinder
                    // over a header with nothing in it.
                    guard let profile = try? await api.treeProfile(id: treeID) else {
                        step = .identify
                        return
                    }
                    step = .camera(Subject(profile))
                }

        case let .camera(subject):
            VisitCameraView(
                treeID: subject.id,
                treeDisplayName: subject.displayName,
                // The provider, asked at the shutter's end rather than read out here at the
                // camera's beginning. `VisitIdentifyView` above already takes the live object for
                // the same reason; this screen only needs one number, and only once, so it takes a
                // question instead (ERRATA E158).
                gpsAccuracyM: { [location] in location.fix.accuracyM },
                api: api,
                outbox: outbox,
                attribution: attribution,
                onSaved: { receipt in
                    if !visitedTreeIDs.contains(subject.id) { visitedTreeIDs.append(subject.id) }
                    step = .saved(receipt: receipt, tree: subject)
                },
                onClose: {
                    // PROTOTYPE-FLOW §1.6.6: the camera's back target depends on progress —
                    // straight back to the shortlist on the first tree, and to the previous
                    // success screen once a route is under way. Without the previous receipt in
                    // hand the honest equivalent is the shortlist, which is where the next tree
                    // can also be picked by hand.
                    //
                    // With `startingTreeID` there is no shortlist behind this camera — the flow
                    // opened on it from a tree's own page — so closing leaves the flow, which is
                    // where that page still is.
                    if startingTreeID == nil {
                        step = .identify
                    } else {
                        onExit()
                    }
                }
            )
            // A fresh model per tree: advancing clears the shot, the note and the chips because
            // there is nothing left of the old draft to clear.
            .id(subject.id)

        case .addTree:
            VisitAddTreeView(
                api: api,
                location: location,
                attribution: attribution,
                onAdded: onOpenTree,
                onOpenExisting: onOpenTree,
                onBack: { step = .identify }
            )

        case let .saved(receipt, tree):
            VisitSavedView(
                receipt: receipt,
                treeDisplayName: tree.displayName,
                origin: location.fix.coordinate ?? tree.coordinate,
                visitedTreeIDs: visitedTreeIDs,
                api: api,
                ledger: ledger,
                onLink: onLink,
                onNextTree: { next in step = .camera(Subject(next)) },
                onRouteComplete: onOpenGrove,
                onBackToMap: onBackToMap ?? onExit,
                onBackToTree: onOpenTree
            )
            .id(receipt.visit.id)
        }
    }
}
