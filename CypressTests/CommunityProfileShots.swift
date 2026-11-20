//
//  CommunityProfileShots.swift
//  Cypress — CypressTests
//
//  Round C3's profile states, photographed: a community tree's history rows among a visit, the cold
//  profile of somebody else's tree with its "Added" row, and the line that tells the adder only they
//  can see the tree, in both of its states.
//
//  The UI suite runs with the remote gate shut, so no history row but "Added" can reach the running
//  app; these renders are where the other rows are looked at. `ScreenSweepShots.sweep` draws each
//  in light and dark, at the default size and at AX5. The PNGs are written only when
//  `CYPRESS_SHOT_DIR` reaches the test process (see `Tools/run_tests.sh`'s header).
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Community tree profile · photographed")
struct CommunityProfileShots {

    private static let treeID = UUID(uuidString: "C3000000-0000-4000-8000-0000000000E1")!
    private static let spot = Coordinate(latitude: 37.7708, longitude: -122.5300)
    private static let device = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3E01")!

    private static func day(_ iso: String) -> CalendarDay { CalendarDay(isoDate: iso)! }

    private static let addedMidnight = Date(timeIntervalSince1970: 1_789_948_800) // 2026-09-21T00:00:00Z

    private static let tree = Tree(
        id: treeID, source: .community, coordinate: spot, createdAt: addedMidnight, updatedAt: addedMidnight
    )

    /// Somebody else's tree with three history rows, and one visit the reader made.
    private static var historyAndVisit: TreeProfile {
        let visitAt = Date(timeIntervalSince1970: 1_790_337_600) // 2026-09-25T12:00:00Z
        let visit = Visit(
            treeID: treeID, attribution: .anonymous(deviceID: device), note: "Fog dripping off the crown",
            capturedAt: visitAt, createdAt: visitAt, updatedAt: visitAt
        )
        let moved = VisitPinAdjust.offset(spot, northM: 12, eastM: 0)
        return TreeProfile(
            tree: tree,
            visits: Series(items: [visit], isComplete: true),
            communityHistory: CommunityTreeHistory(treeID: treeID, events: [
                .init(id: UUID(), kind: .speciesNamed, day: day("2026-09-23")),
                .init(id: UUID(), kind: .locationCorrected, day: day("2026-09-22"), fromCoordinate: spot, toCoordinate: moved),
                .init(id: UUID(), kind: .added, day: day("2026-09-21")),
            ], isComplete: true),
            readerSharing: .sharing
        )
    }

    /// Somebody else's tree nobody here has visited: the cold profile, and its "Added" row.
    private static var othersCold: TreeProfile {
        TreeProfile(tree: tree, readerSharing: .sharing)
    }

    /// The reader's own tree, added on this phone, which only they can see.
    private static func onlyYou(_ sharing: ContributionSharing) -> TreeProfile {
        let added = Date(timeIntervalSince1970: 1_789_995_600) // 2026-09-21T13:00:00Z
        return TreeProfile(
            tree: Tree(id: treeID, source: .community, coordinate: spot, createdAt: added, updatedAt: added),
            canMovePin: true,
            addedByYou: true,
            isAddedHere: true,
            readerSharing: sharing
        )
    }

    @Test("history among a visit, the cold profile of somebody else's tree, and the only-you line")
    func photograph() async {
        print("SHOT DIR \(ScreenSweepShots.shotDirectory?.path ?? "not set: nothing is written")")
        #expect(await ScreenSweepShots.sweep(
            "c3-1-history-and-visit",
            viewportHeight: ScreenSweepShots.tallViewport,
            ax5ViewportHeight: ScreenSweepShots.tallestViewport
        ) { Self.profile(Self.historyAndVisit) })
        #expect(await ScreenSweepShots.sweep(
            "c3-2-others-tree-cold",
            viewportHeight: ScreenSweepShots.tallViewport,
            ax5ViewportHeight: ScreenSweepShots.tallestViewport
        ) { Self.profile(Self.othersCold) })
        #expect(await ScreenSweepShots.sweep("c3-3-only-you-signed-out") { Self.profile(Self.onlyYou(.signedOut)) })
        #expect(await ScreenSweepShots.sweep("c3-4-only-you-not-sharing") { Self.profile(Self.onlyYou(.notSharing)) })
    }

    private static func profile(_ profile: TreeProfile) -> some View {
        NavigationStack {
            TreeProfileView(treeID: profile.tree.id, api: TreeProfilePreviewAPI(profile: profile))
        }
        .environment(AppRouter())
    }
}
#endif
