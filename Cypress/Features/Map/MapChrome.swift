//
//  MapChrome.swift
//  Cypress — Features/Map
//
//  The parts of screen 01 that float over the map in screen space: the filter chip row, the
//  "What tree is this?" FAB, and the two location states BUILD-PLAN §9 requires.
//
//  Everything here composes §2 components or draws from tokens. No hexes, no font sizes.
//

import SwiftUI

// MARK: - Filter chips

/// `All / In bloom / Needs care`, single-select, `All` default (SCREENS.md 01 §12).
struct MapFilterChips: View {
    @Binding var filter: MapModel.Filter

    var body: some View {
        HStack(spacing: MapLayout.chipGap) {
            ForEach(MapModel.Filter.allCases) { candidate in
                Chip(
                    candidate.label,
                    style: candidate == filter ? .filterSelected : .filterIdle
                ) {
                    filter = candidate
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter trees")
    }
}

// MARK: - FAB

/// SCREENS.md 01 §13. `HStack(spacing:9)`, `ctaFill`, pill, `padding:15px 20px`, `shadow.fab`,
/// with the 14pt leaf glyph leading the label.
///
/// The glyph inverts with the scheme: `#8EC3A5` on the deep green FAB in light, `#1D4634` on the
/// mint FAB in dark (D1). Those are the *other* scheme's `ctaFill`, which is why the tokens read
/// crossed over.
struct IdentifyFAB: View {
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Verbatim from SCREENS.md 01.
    private static let label = "What tree is this?"

    var body: some View {
        Button(action: action) {
            HStack(spacing: MapLayout.fabSpacing) {
                LeafGlyph(.fab, tint: glyphTint)
                Text(Self.label)
                    // D1 raises the FAB label to weight 800 in dark and leaves the size alone. §1.3
                    // had no 15.5/800 row, so the ramp grew one (`body155ExtraBold`) rather than
                    // this rounding to 16/800 and changing the size D1 did not ask to change.
                    .font(colorScheme == .dark ? CypressFont.body155ExtraBold : CypressFont.body155)
                    .foregroundStyle(CypressColor.ctaLabel)
            }
            .padding(.vertical, MapLayout.fabPaddingV)
            .padding(.horizontal, MapLayout.fabPaddingH)
            .background { Capsule().fill(CypressColor.ctaFill) }
            .cypressShadow(light: CypressShadow.fab, dark: CypressShadow.Dark.fab)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label)
    }

    private var glyphTint: Color {
        colorScheme == .dark ? CypressColor.cypressDeep : CypressColor.Dark.accentMint
    }
}

// MARK: - Location states

/// The two states BUILD-PLAN §9 asks for by name — "location permission ask with purpose copy and
/// denied state; map without location".
///
/// **NOT SPECIFIED** in SCREENS.md: 01 lists "empty/no-GPS state" among its unspecified states, so
/// nothing new is drawn for it. Instead it takes the bottom card's slot and the bottom card's
/// surface, which are both already documented, and says the honest thing.
///
/// "map without location" needs no view at all: no GPS dot draws, the map opens on the city instead
/// of on the user, and the tree card omits its distance clause. That absence *is* the state.
struct MapLocationNotice: View {
    let availability: MapLocationProvider.Availability
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MapLayout.cardSpacing) {
            VStack(alignment: .leading, spacing: MapLayout.cardMetaTop) {
                Text(title)
                    .font(CypressFont.body145Bold)
                    .foregroundStyle(CypressColor.textInk)
                Text(Self.message)
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onOpenSettings) {
                Text("Settings")
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.ctaLabel)
                    .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
                    .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
                    .background { Capsule().fill(CypressColor.ctaFill) }
            }
            .buttonStyle(.plain)
            .cypressHitArea()
        }
        .padding(.vertical, MapLayout.cardPaddingV)
        .padding(.horizontal, MapLayout.cardPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderPinRing, radius: CypressRadius.cardLg)
        .cypressShadow(light: CypressShadow.bottomCard, dark: nil)
    }

    /// No spaces around em dashes (ARCHITECTURE §5.7).
    private var title: String {
        availability == .servicesOff ? "Location Services are off" : "Location is off"
    }

    private static let message =
        "The map still works—it just cannot show where you are, or work out which tree you are "
        + "standing in front of."

}
