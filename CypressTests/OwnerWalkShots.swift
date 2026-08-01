//
//  OwnerWalkShots.swift
//  CypressTests
//
//  Photographs the two drawn states the 2026-07-31 owner-walk tickets changed: screen 09's well
//  opened into its fields (task #147) and screen 20's subject filter (task #154). Rendered rather
//  than driven, for `FavoriteAppearanceShots`' reason: these are visual states and they have to be
//  looked at, and the fixture is the only place they can be stood up without a walk.
//
//  Asserts almost nothing, deliberately — ARCHITECTURE §7 says snapshot testing is not set up, so
//  what is asserted is that an image was produced; the images are the output and the paths are
//  printed for a reviewer.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
@testable import Cypress

@MainActor
@Suite("Owner-walk fixes, photographed")
struct OwnerWalkShots {

    @Test("09's well, opened into its two fields")
    func careLogExtras() async {
        var draft = CareLogDraft(actions: [.watered, .mulched])
        draft.note = "Watered two buckets"
        for scheme in [ColorScheme.light, .dark] {
            let name = "09-care-well-open-\(scheme == .light ? "light" : "dark")"
            let rendered = await DynamicTypeScreenshotTests.render(name, .large, scheme: scheme) {
                CareLogPreviewFixtures.view(draft: draft)
            }
            #expect(rendered != nil, "\(name) produced no image")
        }
    }

    @Test("20's subject filter, whole and narrowed")
    func photoBrowserFilter() async {
        let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000154")!
        func photo(_ shotType: ShotType, daysAgo: Int) -> Photo {
            Photo(
                treeID: treeID,
                shotType: shotType,
                capturedAt: Date(timeIntervalSince1970: 1_780_000_000 - Double(daysAgo) * 86_400)
            )
        }
        let shots: [(name: String, filter: ShotType?)] = [
            ("20-photos-all", nil),
            ("20-photos-trunk", .trunk),
            ("20-photos-leaf-empty", .leaf),
        ]
        for shot in shots {
            let model = TreePhotosModel(
                treeID: treeID,
                photos: [photo(.fullTree, daysAgo: 1), photo(.trunk, daysAgo: 2), photo(.other, daysAgo: 3)],
                treeName: "Grandmother Cypress"
            )
            model.subjectFilter = shot.filter
            let rendered = await DynamicTypeScreenshotTests.render(shot.name, .large, scheme: .light) {
                TreePhotosView(model: model)
            }
            #expect(rendered != nil, "\(shot.name) produced no image")
        }
    }
}
#endif
