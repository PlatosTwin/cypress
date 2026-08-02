//
//  LandContextShots.swift
//  Cypress — CypressTests
//
//  The states `land_context` created, photographed (ERRATA E146).
//
//  Three of these five cannot be reached from the shipped seed by any deep link. A contributor's
//  stated context only exists on a tree somebody added on the device, and screen 06's two changed
//  branches need a tree the seed does not carry at the fixed coordinate the harness resolves. The
//  live walk on the simulator covered the stated arm end to end — add a tree, tap `Private property`,
//  save, open the profile, open the report — and this covers the rest, in both appearances, so the
//  branch nobody can reach by hand is still something a person has looked at.
//
//  `ScreenSweepShots.pair` rather than `sweep`: the question here is what these panels *say* in light
//  and in dark, not whether they hold together at AX5, which the report screen's own sweep entry
//  already asks.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Land context · photographed")
struct LandContextShots {

    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-0000000000F2")!
    private static let coordinate = Coordinate(latitude: 37.7601, longitude: -122.5094)

    /// A community tree whose contributor tapped `Private property` — an observation.
    private static let statedPrivate = Tree(
        id: treeID,
        source: .community,
        coordinate: coordinate,
        statedLandContext: .privateProperty
    )

    /// A city row Cypress *reads* as private: `Undocumented` with a private caretaker, which is the
    /// commonest shape of it at 8,126 seed rows and the weak arm that keeps the 311 CTA.
    private static let inferredPrivate = Tree(
        id: treeID,
        externalRef: "229291",
        source: .cityImport,
        coordinate: coordinate,
        cityRecord: CityRecord(legalStatus: "Undocumented", caretaker: "Private")
    )

    /// An ordinary street tree — the control, and 93.35% of the inventory.
    private static let street = Tree(
        id: treeID,
        externalRef: "13284",
        source: .cityImport,
        coordinate: coordinate,
        cityRecord: CityRecord(legalStatus: "DPW Maintained", caretaker: "Private")
    )

    @Test("the three hazard handoffs and the two profile arms, light and dark, default and AX5")
    func photograph() async {
        print("SHOT DIR \(ScreenSweepShots.outputDirectory.path)")

        #expect(await ScreenSweepShots.sweep("e146-1-report-stated-private") { Self.report(Self.statedPrivate) })
        #expect(await ScreenSweepShots.sweep("e146-2-report-inferred-private") { Self.report(Self.inferredPrivate) })
        #expect(await ScreenSweepShots.sweep("e146-3-report-street") { Self.report(Self.street) })
        // A 1,500 pt window for the two profiles, `cityRecordStates`' own reason: the ground under the
        // tree is a sentence in §9b, the last block on screen 03, and an off-screen `ScrollView`
        // cannot be scrolled. At phone height these two photographed the stat grid and stopped above
        // the sentence — which is what they were for when the fact was a card up in that grid.
        #expect(
            await ScreenSweepShots.sweep(
                "e146-4-profile-stated-private",
                viewportHeight: ScreenSweepShots.tallViewport,
                ax5ViewportHeight: ScreenSweepShots.tallestViewport
            ) { Self.profile(Self.statedPrivate) }
        )
        #expect(
            await ScreenSweepShots.sweep(
                "e146-5-profile-inferred-street",
                viewportHeight: ScreenSweepShots.tallViewport,
                ax5ViewportHeight: ScreenSweepShots.tallestViewport
            ) { Self.profile(Self.street) }
        )
    }

    private static func report(_ tree: Tree) -> some View {
        NavigationStack {
            ReportView(
                treeID: tree.id,
                api: ReportPreviewAPI(tree: tree),
                dialer: ReportPreviewDialer(),
                initialSelection: .hazard(.hangingOrBrokenLimb)
            )
        }
        .environment(AppRouter())
    }

    private static func profile(_ tree: Tree) -> some View {
        NavigationStack {
            TreeProfileView(
                treeID: tree.id,
                api: TreeProfilePreviewAPI(profile: TreeProfile(tree: tree))
            )
        }
        .environment(AppRouter())
    }
}
#endif
