//
//  CommunityTreeMark.swift
//  Cypress — DesignSystem/Components
//
//  The community tree mark: the map's community pin (C19 `MapPin.Kind.community`, the dashed
//  Canopy ring on its pale fill), drawn small for a row's leading square. The app owner's decision
//  of 2026-11-15 puts it on the tree profile's history rows and the Journal's pin-move row.
//
//  Every value comes from the pin itself, so the mark cannot drift from the map: the fill and the
//  ring are `MapPin.Kind.community`'s, and the ring width and dash pattern are the pin's, scaled by
//  `diameter / pinStandard`. At `pinStandard` the mark is the map's pin at the map's size, without
//  its shadow or its 44pt hit area. `CommunityTreeMarkTests` ties the numbers together.
//

import SwiftUI

struct CommunityTreeMark: View {

    /// The circle's diameter. Defaults to the map pin's own size.
    var diameter: CGFloat = CypressSpacing.Component.pinStandard

    /// The pin this mark draws.
    static let pin = MapPin.Kind.community

    /// How much smaller (or larger) than the map's pin this mark is drawn.
    static func scale(for diameter: CGFloat) -> CGFloat {
        diameter / pin.diameter
    }

    /// The ring's line width at `diameter`, in the map pin's proportion.
    static func ringWidth(for diameter: CGFloat) -> CGFloat {
        (pin.ring?.width ?? 0) * scale(for: diameter)
    }

    /// The ring's dash pattern at `diameter`, in the map pin's proportion.
    static func dash(for diameter: CGFloat) -> [CGFloat] {
        CypressDash.pinRing.map { $0 * scale(for: diameter) }
    }

    var body: some View {
        Circle()
            .fill(Self.pin.fill)
            .overlay {
                if let ring = Self.pin.ring {
                    Circle().strokeBorder(
                        ring.color,
                        style: StrokeStyle(
                            lineWidth: Self.ringWidth(for: diameter),
                            dash: Self.dash(for: diameter)
                        )
                    )
                }
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// The mark in its leading square, centered on the SYNC tile's neutral ground
/// (`memorialBannerFill`). A caller sets the square's size and corner, the same way it does for its
/// other tiles.
///
/// Not the pin's own pale fill as the ground: in dark appearance `pinCommunityFill` (#1B241B) is
/// within a shade of the card (#18251D), and the square vanished in the rendered check, so the row
/// lost the square its neighbors have. `memorialBannerFill` shows in both appearances, and the
/// pin's pale disc sits on it the way the pin sits on the map.
struct CommunityTreeTile: View {

    /// The mark's diameter inside the square. Defaults to the map pin's own size.
    var markDiameter: CGFloat = CypressSpacing.Component.pinStandard

    var body: some View {
        CypressColor.memorialBannerFill
            .overlay { CommunityTreeMark(diameter: markDiameter) }
            .accessibilityHidden(true)
    }
}
