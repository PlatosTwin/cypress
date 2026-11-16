#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// The community tree mark is the map's community pin, drawn small. These tests tie its numbers to
/// the pin's, so a change to the pin moves the mark with it, and render the mark in `ActivityRow`
/// beside its neighbors for a person to look at.
@MainActor
@Suite("Community tree mark · the map's community pin, drawn small")
struct CommunityTreeMarkTests {

    @Test("the mark draws the community pin's fill and ring color")
    func colorsAreThePins() {
        #expect(CommunityTreeMark.pin == .community)
        #expect(CommunityTreeMark.pin.fill == MapPin.Kind.community.fill)
        #expect(CommunityTreeMark.pin.ring?.color == MapPin.Kind.community.ring?.color)
        #expect(CommunityTreeMark.pin.ring?.dashed == true)
    }

    @Test("at the map pin's size, the ring width and dashes are the map pin's")
    func atPinSizeTheRingIsThePins() {
        let side = CypressSpacing.Component.pinStandard
        #expect(MapPin.Kind.community.diameter == side)
        #expect(CommunityTreeMark.ringWidth(for: side) == CypressSpacing.Component.pinRingCommunity)
        #expect(CommunityTreeMark.dash(for: side) == CypressDash.pinRing)
    }

    @Test("at half the pin's size, the ring width and dashes are half the pin's")
    func smallerKeepsTheProportion() {
        let half = CypressSpacing.Component.pinStandard / 2
        #expect(CommunityTreeMark.ringWidth(for: half) == CypressSpacing.Component.pinRingCommunity / 2)
        #expect(CommunityTreeMark.dash(for: half) == CypressDash.pinRing.map { $0 / 2 })
    }

    /// Not a snapshot comparison (ARCHITECTURE §7 sets none up). It asserts that an image was made;
    /// the PNGs are for a person to look at, written to `CYPRESS_SHOT_DIR` when it is set.
    @Test("the new leading square renders beside Care and SYNC, default and AX5, light and dark")
    func rowsRender() async {
        let shots: [(name: String, size: DynamicTypeSize, scheme: ColorScheme)] = [
            ("c9-community-tree-large-light", .large, .light),
            ("c9-community-tree-ax5-light", .accessibility5, .light),
            ("c9-community-tree-large-dark", .large, .dark),
            ("c9-community-tree-ax5-dark", .accessibility5, .dark),
        ]
        for shot in shots {
            let rendered = await DynamicTypeScreenshotTests.render(shot.name, shot.size, scheme: shot.scheme) {
                VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                    ActivityRow(leading: .care, label: "Care", detail: " · Watered", timestamp: "Mar 20")
                    ActivityRow(leading: .sync, label: "City sync", detail: " · 2 changes", timestamp: "Mar 19")
                    ActivityRow(
                        leading: .communityTree, label: "Pin moved", detail: " · 12 m north",
                        timestamp: "Mar 18"
                    )
                    ActivityRow(leading: .communityTree, label: "Added", detail: "", timestamp: "Mar 2")
                    HStack(spacing: CypressSpacing.gapRows) {
                        // The map's pin, for comparison, and the tile at C10's 34pt size.
                        MapPin(.community)
                        CommunityTreeTile()
                            .frame(
                                width: CypressSpacing.Component.iconRowTile,
                                height: CypressSpacing.Component.iconRowTile
                            )
                            .cypressCornerRadius(CypressRadius.thumbSmAlt)
                    }
                    Spacer(minLength: 0)
                }
                .padding(CypressSpacing.gapRows)
            }
            #expect(rendered != nil, "\(shot.name) produced no image")
        }
    }
}
#endif
