//
//  MapPin.swift
//  Cypress — DesignSystem/Components
//
//  C19 · `MapPin` — SCREENS.md §2. Every marker that sits on `MapCanvas`, plus the two route pins
//  on 18.
//
//  ── Tap targets ───────────────────────────────────────────────────────────────────────────
//  This is the worst offender the project's own critique flags: the drawn pins are **16–18pt**,
//  and a cluster badge is 30–32pt. Every one of them keeps its drawn size exactly and carries a
//  44pt hit area through `.cypressHitArea()` (ARCHITECTURE §6, SCREENS.md §5 gap 12). On the map
//  that also means two pins closer than ~44pt have overlapping targets, which is precisely what
//  clustering is for.
//

import SwiftUI

struct MapPin: View {

    enum Kind: Hashable {
        /// 18pt Canopy circle, `3px` ring, `shadow.pin`.
        case cityTree
        /// 18pt Signal Amber circle — "this tree needs something".
        case needsCare
        /// 18pt pale circle with a `2.5px` **dashed** Canopy ring — the community layer, which
        /// never reads as part of the official inventory (DECISIONS §3.16).
        case community
        /// 16pt gray circle at 85 % opacity with a centred bar — a removed tree's memorial.
        case removed
        /// A cluster badge carrying its count. 32pt at the large size, 30pt at the small.
        case cluster(count: Int, large: Bool = true)
        /// The blue GPS dot with its 8pt halo.
        case gps
        /// 18 route pin, done — 20pt `#AEBFA1` with a white check.
        case routeDone
        /// 18 route pin, active — 24pt amber with a 7pt halo.
        case routeActive

        var diameter: CGFloat {
            switch self {
            case .cityTree, .needsCare, .community, .gps:
                return CypressSpacing.Component.pinStandard
            case .removed:
                return CypressSpacing.Component.pinRemoved
            case let .cluster(_, large):
                return large
                    ? CypressSpacing.Component.pinClusterLarge
                    : CypressSpacing.Component.pinClusterSmall
            case .routeDone:
                return CypressSpacing.Component.pinRouteDone
            case .routeActive:
                return CypressSpacing.Component.pinRouteActive
            }
        }

        var fill: Color {
            switch self {
            case .cityTree: return CypressColor.pinFill
            case .needsCare, .routeActive: return CypressColor.accentAmber
            case .community: return CypressColor.pinCommunityFill
            case .removed: return CypressColor.pinRemovedFill
            case .cluster: return CypressColor.ctaFill
            case .gps: return CypressColor.gpsDot
            case .routeDone: return CypressColor.pinRouteDone
            }
        }

        /// The white (dark: `#0E1712`) ring every pin but the route-done one carries.
        var ring: (color: Color, width: CGFloat, dashed: Bool)? {
            switch self {
            case .cityTree, .needsCare, .removed, .cluster, .gps, .routeActive:
                return (CypressColor.pinRingStroke, CypressSpacing.Component.pinRing, false)
            case .community:
                return (CypressColor.pinFill, CypressSpacing.Component.pinRingCommunity, true)
            case .routeDone:
                return nil
            }
        }

        var shadow: CypressShadowStyle? {
            switch self {
            case .cityTree, .needsCare: return CypressShadow.pin
            case .removed: return CypressShadow.pinMuted
            case .community: return CypressShadow.pinMutedStrong
            case .cluster: return CypressShadow.cluster
            case .gps, .routeDone, .routeActive: return nil
            }
        }

        /// The outer glow ring on the GPS dot and the active route pin.
        var halo: (color: Color, width: CGFloat)? {
            switch self {
            case .gps:
                return (CypressColor.gpsDotHalo, CypressSpacing.Component.pinGPSHalo)
            case .routeActive:
                return (
                    CypressColor.accentAmber.opacity(0.22),
                    CypressSpacing.Component.pinRouteActiveHalo
                )
            default:
                return nil
            }
        }

        var opacity: Double {
            self == .removed ? 0.85 : 1
        }

        var accessibilityLabel: String {
            switch self {
            case .cityTree: return "City tree"
            case .needsCare: return "Tree that needs something"
            case .community: return "Community-added tree"
            case .removed: return "Removed tree, memorial"
            case let .cluster(count, _): return "\(count) trees"
            case .gps: return "Your location"
            case .routeDone: return "Visited"
            case .routeActive: return "Next tree"
            }
        }
    }

    let kind: Kind
    var action: (() -> Void)?

    init(_ kind: Kind, action: (() -> Void)? = nil) {
        self.kind = kind
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { pin }
                .buttonStyle(.plain)
                .cypressHitArea()
                .accessibilityLabel(kind.accessibilityLabel)
                .cypressTypographicFurniture()
        } else {
            pin
                .accessibilityLabel(kind.accessibilityLabel)
                .cypressTypographicFurniture()
        }
    }

    private var pin: some View {
        shape
            .frame(height: kind.diameter)
            .opacity(kind.opacity)
            // czPulse, on the amber pin and nothing else. The prototype loops it at 2.4 s on its
            // one `#B4711F` pin, and Signal Amber is "reserved solely for 'this tree needs
            // something'" (SCREENS.md §1.1) — so the pulse is the mark of that one meaning rather
            // than a decoration available to any pin.
            //
            // It lives on the component so screen 01's live MapKit layer gets it for free: unlike
            // a pin-drop, a continuous loop does not care that annotations are recycled during a
            // pan, because there is no "first appearance" for a recycle to re-fire.
            .cypressPulse(CypressColor.accentAmber, isActive: kind == .needsCare)
            .cypressShadow(kind.shadow)
            .background(alignment: .center) {
                if let halo = kind.halo {
                    Capsule()
                        .fill(halo.color)
                        .padding(-halo.width)
                }
            }
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case let .cluster(count, large):
            // `min-width` on the badge, so a three-digit cluster grows sideways and stays a pill.
            Text("\(count)")
                .font(large ? CypressFont.body13ExtraBold : CypressFont.body12ExtraBold)
                .foregroundStyle(CypressColor.ctaLabel)
                .padding(.horizontal, CypressSpacing.Component.chipLegendGap)
                .frame(minWidth: kind.diameter, minHeight: kind.diameter)
                .background { Capsule().fill(kind.fill) }
                .overlay { ringOverlay(Capsule()) }
                .fixedSize()
        case .removed:
            Circle()
                .fill(kind.fill)
                .overlay { ringOverlay(Circle()) }
                .overlay {
                    RoundedRectangle(cornerRadius: CypressRadius.pinRemovedBar, style: .continuous)
                        .fill(CypressColor.pinRemovedBar)
                        .frame(
                            width: CypressSpacing.Component.pinRemovedBarWidth,
                            height: CypressSpacing.Component.pinRemovedBarHeight
                        )
                }
                .frame(width: kind.diameter)
        case .routeDone:
            Circle()
                .fill(kind.fill)
                .overlay {
                    CypressCheckmark()
                        .stroke(
                            CypressColor.textOnDark,
                            style: StrokeStyle(
                                lineWidth: CypressSpacing.Component.pinRouteCheckStroke,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(
                            width: CypressSpacing.Component.pinRouteCheckWidth,
                            height: CypressSpacing.Component.pinRouteCheckHeight
                        )
                }
                .frame(width: kind.diameter)
        default:
            Circle()
                .fill(kind.fill)
                .overlay { ringOverlay(Circle()) }
                .frame(width: kind.diameter)
        }
    }

    @ViewBuilder
    private func ringOverlay<S: InsettableShape>(_ shape: S) -> some View {
        if let ring = kind.ring {
            if ring.dashed {
                shape.strokeBorder(
                    ring.color,
                    style: StrokeStyle(lineWidth: ring.width, dash: CypressDash.pinRing)
                )
            } else {
                shape.strokeBorder(ring.color, lineWidth: ring.width)
            }
        }
    }
}
