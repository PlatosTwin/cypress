//
//  VisitSavedModel.swift
//  Cypress — Features/Visit
//
//  Screen 18's state: what was just saved, which tree is next, and the one moment in the whole
//  flow where an account is worth asking about.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class VisitSavedModel {

    private let api: any CypressAPI
    private let ledger: VisitSaveLedger

    let receipt: VisitSaveReceipt
    let treeDisplayName: String
    /// Where the phone was when the visit was saved — the origin for "next nearest".
    let origin: Coordinate?

    /// Today's list: the trees this session has already dealt with, in order, plus what is left.
    private(set) var route: [VisitCandidate] = []
    /// Ids already saved in this session. The route map draws these "quiet".
    private(set) var visitedTreeIDs: [UUID]

    /// A recency line about the *tree* — allowed by D1, which forbids counting the person, not the
    /// place. Rendered only when it is true; there is no placeholder.
    private(set) var recencyLine: String?

    /// D9's moment. See `VisitSaveLedger` for why the third save and not the first.
    private(set) var shouldPresentAccountAsk = false

    init(
        receipt: VisitSaveReceipt,
        treeDisplayName: String,
        origin: Coordinate?,
        visitedTreeIDs: [UUID],
        api: any CypressAPI,
        ledger: VisitSaveLedger
    ) {
        self.receipt = receipt
        self.treeDisplayName = treeDisplayName
        self.origin = origin
        self.visitedTreeIDs = visitedTreeIDs
        self.api = api
        self.ledger = ledger
    }

    /// "a ten-tree morning moves along on its own" — the list the route map draws.
    static let routeLength = 10
    /// Wide enough to always find a next tree on a street, narrow enough that "next nearest" means
    /// something you can walk to.
    static let routeRadiusM: Double = 250
    /// A visit within this window makes the tree's recency line true.
    static let recencyWindow: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Derived

    /// The tree the CTA advances to. `nil` when the route is done.
    var nextTree: VisitCandidate? {
        route.first { !visitedTreeIDs.contains($0.id) }
    }

    /// `Next nearest: The Tea Tree · 40 m`, or the route-done label (PROTOTYPE-FLOW §1.4).
    var nextLabel: String {
        guard let next = nextTree else { return "Route done · see your grove" }
        return "Next nearest: \(next.displayName) · \(Int(next.distanceM.rounded())) m"
    }

    /// `4 of 10 on today's list`.
    ///
    /// This is a **position in a route**, the same way a page number is — not a score, not a
    /// streak, and not attached to the person. D1 kills the prototype's `visitCount` ("N visits
    /// today"), which is why that string appears nowhere in this feature. It renders only when
    /// there is a route longer than the tree in front of you.
    var routePositionLine: String? {
        guard route.count > 1 else { return nil }
        let position = max(visitedTreeIDs.count, 1)
        return "\(position) of \(route.count) on today's list"
    }

    var storageLine: String { ledger.storageLine }

    // MARK: - Loading

    func load() async {
        // The ledger answers D9's question — has the ask earned its interruption. `mayAsk` answers a
        // different one the ledger has no business knowing: whether this build could honour it.
        // Screen 15 is built and cannot sign anyone in until a server exists to send a magic link
        // (RULINGS R4), so it is not presented, and no presentation is spent refusing.
        shouldPresentAccountAsk = ledger.recordSave(mayAsk: BetaCapability.accountsAvailable)
        await loadRoute()
        await loadRecency()
    }

    private func loadRoute() async {
        guard let origin else { return }
        guard let rows = try? await api.treesNear(origin, radiusM: Self.routeRadiusM, limit: Self.routeLength)
        else { return }

        var ordered = rows.sorted { $0.distanceM < $1.distanceM }.map(VisitCandidate.init(nearby:))
        // The tree just saved leads the list even if the phone has drifted a few metres since.
        if let index = ordered.firstIndex(where: { $0.id == receipt.visit.treeID }) {
            let current = ordered.remove(at: index)
            ordered.insert(current, at: 0)
        }
        route = ordered
    }

    private func loadRecency() async {
        guard let profile = try? await api.treeProfile(id: receipt.visit.treeID) else { return }
        let cutoff = Date().addingTimeInterval(-Self.recencyWindow)
        let others = profile.visits.items.filter {
            $0.id != receipt.visit.id && $0.capturedAt >= cutoff
        }
        // ARCHITECTURE §5.6: below its threshold, an aggregate surface does not render at all.
        // One other visit is the threshold — "someone else" needs a someone else.
        recencyLine = others.isEmpty ? nil : "Someone else was here this week."
    }

    /// Called when screen 15 closes, either way. The seam's other half.
    func resolveAccountAsk() {
        ledger.resolveAccountAsk()
        shouldPresentAccountAsk = false
    }

    /// The binding screen 15's sheet is presented from.
    ///
    /// It exists so that resolving is not something the sheet's author can forget. SwiftUI writes
    /// `false` through this binding for an interactive dismissal — a swipe down, a tap outside —
    /// exactly as it does for a programmatic one, so every way of closing the sheet lands on
    /// `resolveAccountAsk()`. A raw `Bool` flag would let a swipe-away leave the ask owed and
    /// unanswered, which is half of ERRATA E34; the ledger's re-offer is the other half, and
    /// neither is meant to carry it alone.
    var accountAskPresentation: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.shouldPresentAccountAsk ?? false },
            set: { [weak self] isPresented in
                guard !isPresented else { return }
                self?.resolveAccountAsk()
            }
        )
    }
}
