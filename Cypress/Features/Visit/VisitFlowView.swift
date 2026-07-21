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

import SwiftUI

struct VisitFlowView: View {

    private enum Step: Equatable {
        case identify
        case camera(VisitCandidate)
        case saved(receipt: VisitSaveReceipt, tree: VisitCandidate)

        static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.identify, .identify): return true
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

    /// Leaving the flow entirely — the shortlist's back chevron and "Done for today".
    var onExit: () -> Void = {}
    /// "None of these? Add this tree" (screen 20) and "See it on the tree's timeline" (screen 03)
    /// both live outside this feature.
    var onAddTree: () -> Void = {}
    var onOpenTree: (UUID) -> Void = { _ in }
    /// "Route done · see your grove" (screen 08).
    var onOpenGrove: () -> Void = {}

    @State private var location = VisitLocationProvider()
    @State private var ledger = VisitSaveLedger()
    @State private var step: Step = .identify
    @State private var visitedTreeIDs: [UUID] = []

    private var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }

    var body: some View {
        switch step {
        case .identify:
            VisitIdentifyView(
                api: api,
                location: location,
                onPick: { candidate in step = .camera(candidate) },
                onAddTree: onAddTree,
                onBack: onExit
            )

        case let .camera(candidate):
            VisitCameraView(
                treeID: candidate.id,
                treeDisplayName: candidate.displayName,
                gpsAccuracyM: location.fix.accuracyM,
                api: api,
                outbox: outbox,
                attribution: attribution,
                onSaved: { receipt in
                    if !visitedTreeIDs.contains(candidate.id) { visitedTreeIDs.append(candidate.id) }
                    step = .saved(receipt: receipt, tree: candidate)
                },
                onClose: {
                    // PROTOTYPE-FLOW §1.6.6: the camera's back target depends on progress —
                    // straight back to the shortlist on the first tree, and to the previous
                    // success screen once a route is under way. Without the previous receipt in
                    // hand the honest equivalent is the shortlist, which is where the next tree
                    // can also be picked by hand.
                    step = .identify
                }
            )
            // A fresh model per tree: advancing clears the shot, the note and the chips because
            // there is nothing left of the old draft to clear.
            .id(candidate.id)

        case let .saved(receipt, tree):
            VisitSavedView(
                receipt: receipt,
                treeDisplayName: tree.displayName,
                origin: location.fix.coordinate ?? tree.tree.coordinate,
                visitedTreeIDs: visitedTreeIDs,
                api: api,
                ledger: ledger,
                onNextTree: { next in step = .camera(next) },
                onRouteComplete: onOpenGrove,
                onDone: onExit,
                onOpenTimeline: onOpenTree
            )
            .id(receipt.visit.id)
        }
    }
}
