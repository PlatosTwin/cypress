//
//  Chip.swift
//  Cypress — DesignSystem/Components
//
//  C4 · `Chip` (pill) — SCREENS.md §2. Seventeen rows in the variant table; the method-legend row
//  draws in two forms (filled dot = taped, hollow dot = estimated), which is the eighteenth
//  documented rendering. All of it is one `Chip.Style` enum — never a pile of booleans.
//
//  ── Tap targets ───────────────────────────────────────────────────────────────────────────
//  Most chips are 25–35pt tall as drawn. Every interactive chip keeps its exact drawn size and
//  gets a ≥44pt hit area via `.cypressHitArea()` (ARCHITECTURE §6). Non-interactive chips (meta,
//  sanity check, method legend) are labels and take none.
//

import SwiftUI

struct Chip: View {

    /// The eighteen documented renderings of §2's C4 table.
    enum Style: String, CaseIterable, Identifiable {
        /// Filter chip, selected (01) — `#1D4634` / `#fff` / 700, `shadow.chipActive`.
        case filterSelected
        /// Filter chip, idle (01) — `rgba(255,255,255,.92)` / `1px rgba(29,70,52,.12)` / `#3C4A3E`.
        case filterIdle
        /// Meta chip (02, 07) — `#fff` / `1px #E3E8D9` / `#3C4A3E`, 12.5px.
        case meta
        /// Structure flag, idle (05).
        case structureFlagIdle
        /// Structure flag, on (05) — `#2F6B4F` / `#fff` / 700.
        case structureFlagOn
        /// Hazard, on (06) — `#F8EFDF` / `1.5px #D9A05B` / `#8A5A17` / 700.
        case hazardOn
        /// Hazard, off (06) — `#fff` / `1px #EBD3A8` / `#8A5A17`.
        case hazardOff
        /// Care toggle, on (09) — `#2F6B4F` / `#fff` / 700, 14.5px. The `✓` is part of the label.
        case careOn
        /// Care toggle, off (09).
        case careOff
        /// Phenology, on (04) — `#2F6B4F` / `#fff` / 700.
        case phenologyOn
        /// Phenology, off (04) — `#1B241B` / `1px #2A362B` / `#AEBBAB`. Screen 04 is dark always.
        case phenologyOff
        /// Shot type, on (04) — `rgba(233,240,226,.94)` / `#22301F` / 700.
        case shotTypeOn
        /// Shot type, off (04) — `rgba(6,10,7,.55)` / `#CFDAC6`.
        case shotTypeOff
        /// Dark flag, on (D3) — `#8EC3A5` / `#0E1712` / 800.
        case darkFlagOn
        /// Dark flag, off (D3) — `#18251D` / `1px #27352B` / `#AEBBAB`.
        case darkFlagOff
        /// Sanity-check pill (16) — `#EFF3E3` / `1px #DFE6CD` / `#41522F`.
        case sanityCheck
        /// Method legend (11), filled dot — `taped`.
        case methodLegendTaped
        /// Method legend (11), hollow dot — `estimated`.
        case methodLegendEstimated

        var id: String { rawValue }

        // MARK: Fill

        var fill: Color {
            switch self {
            case .filterSelected: return CypressColor.ctaFill
            case .filterIdle: return CypressColor.chipGlassFill
            case .meta, .hazardOff, .careOff, .structureFlagIdle,
                 .methodLegendTaped, .methodLegendEstimated:
                return CypressColor.surfaceCard
            case .structureFlagOn, .careOn: return CypressColor.selectionFill
            // 04 is dark always, yet §2 gives this chip the light Canopy fill — literal, not paired.
            case .phenologyOn: return CypressColor.canopy
            case .hazardOn: return CypressColor.amberChipSelectedFill
            case .phenologyOff: return CypressColor.Dark.surfaceCardAlt
            case .shotTypeOn: return CypressColor.shotTypeOnFill
            case .shotTypeOff: return CypressColor.shotTypeOffFill
            case .darkFlagOn: return CypressColor.Dark.accentMint
            case .darkFlagOff: return CypressColor.Dark.surfaceCard
            case .sanityCheck: return CypressColor.calloutGreenFill
            }
        }

        // MARK: Border

        var border: (color: Color, width: CGFloat)? {
            switch self {
            case .filterIdle:
                return (CypressColor.borderGlassChip, CypressSpacing.Component.hairline)
            case .meta, .careOff, .structureFlagIdle,
                 .methodLegendTaped, .methodLegendEstimated:
                return (CypressColor.borderCool, CypressSpacing.Component.hairline)
            case .hazardOn:
                return (CypressColor.amberChipSelectedBorder, CypressSpacing.Component.hairlineStrong)
            case .hazardOff:
                return (CypressColor.borderAmberSoft, CypressSpacing.Component.hairline)
            case .phenologyOff:
                return (CypressColor.Dark.borderCamera, CypressSpacing.Component.hairline)
            case .darkFlagOff:
                return (CypressColor.Dark.border, CypressSpacing.Component.hairline)
            case .sanityCheck:
                return (CypressColor.calloutGreenBorder, CypressSpacing.Component.hairline)
            case .filterSelected, .structureFlagOn, .careOn, .phenologyOn,
                 .shotTypeOn, .shotTypeOff, .darkFlagOn:
                return nil
            }
        }

        // MARK: Label

        var textColor: Color {
            switch self {
            case .filterSelected: return CypressColor.ctaLabel
            case .filterIdle, .meta, .structureFlagIdle, .careOff:
                return CypressColor.textBody
            case .structureFlagOn, .careOn: return CypressColor.onSelectionFill
            case .phenologyOn: return CypressColor.textOnDark
            case .hazardOn, .hazardOff: return CypressColor.amberChipSelectedText
            case .phenologyOff, .darkFlagOff: return CypressColor.Dark.textSecondary
            case .shotTypeOn: return CypressColor.shotTypeOnText
            case .shotTypeOff: return CypressColor.shotTypeOffText
            case .darkFlagOn: return CypressColor.Dark.bgScreen
            case .sanityCheck: return CypressColor.calloutGreenText
            case .methodLegendTaped, .methodLegendEstimated: return CypressColor.textBody
            }
        }

        var font: Font {
            switch self {
            case .filterSelected: return CypressFont.body13Bold
            case .filterIdle, .structureFlagIdle, .phenologyOff: return CypressFont.body13
            case .structureFlagOn, .hazardOn, .phenologyOn: return CypressFont.body13Bold
            case .hazardOff: return CypressFont.body13
            case .careOn: return CypressFont.body145Bold
            case .careOff: return CypressFont.body145
            case .meta, .sanityCheck: return CypressFont.body125
            case .shotTypeOn: return CypressFont.body125Bold
            case .shotTypeOff: return CypressFont.body125
            case .darkFlagOn: return CypressFont.body13ExtraBold
            case .darkFlagOff: return CypressFont.body13
            case .methodLegendTaped, .methodLegendEstimated: return CypressFont.body12
            }
        }

        // MARK: Padding

        var paddingV: CGFloat {
            switch self {
            case .filterSelected, .filterIdle, .phenologyOn, .phenologyOff:
                return CypressSpacing.Component.chipPaddingVFilter
            case .meta, .shotTypeOn, .shotTypeOff, .sanityCheck,
                 .methodLegendTaped, .methodLegendEstimated:
                return CypressSpacing.Component.chipPaddingVMeta
            case .structureFlagIdle, .structureFlagOn, .hazardOn, .hazardOff,
                 .darkFlagOn, .darkFlagOff:
                return CypressSpacing.Component.chipPaddingVFlag
            case .careOn, .careOff:
                return CypressSpacing.Component.chipPaddingVCare
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .filterSelected, .filterIdle, .phenologyOn, .phenologyOff:
                return CypressSpacing.Component.chipPaddingHFilter
            case .meta, .methodLegendTaped, .methodLegendEstimated:
                return CypressSpacing.Component.chipPaddingHMeta
            case .shotTypeOn, .shotTypeOff, .sanityCheck:
                return CypressSpacing.Component.chipPaddingHMetaWide
            case .structureFlagIdle, .structureFlagOn, .hazardOn, .hazardOff,
                 .darkFlagOn, .darkFlagOff:
                return CypressSpacing.Component.chipPaddingHFlag
            case .careOn, .careOff:
                return CypressSpacing.Component.chipPaddingHCare
            }
        }

        /// Only the selected filter chip carries an elevation (`shadow.chipActive`).
        var shadow: CypressShadowStyle? {
            self == .filterSelected ? CypressShadow.chipActive : nil
        }

        /// A legend pill is a caption, not a control — no hit-area growth, no button.
        var isStatic: Bool {
            switch self {
            case .meta, .sanityCheck, .methodLegendTaped, .methodLegendEstimated: return true
            default: return false
            }
        }

        /// The `gap:7px` dot that only the method-legend row carries.
        var legendDot: LegendDot? {
            switch self {
            case .methodLegendTaped: return .filled
            case .methodLegendEstimated: return .hollow
            default: return nil
            }
        }
    }

    /// C4's method-legend accessory — `taped` is a 10×10 filled dot, `estimated` a 5×5 hollow one
    /// with a 2.5pt Canopy edge (11).
    enum LegendDot {
        case filled
        case hollow
    }

    let label: String
    let style: Style
    /// A leading dot of an arbitrary tint — 02's `GPS ±9 m` chip carries an 8×8 `#3577C9` dot.
    var leadingDot: Color?
    var action: (() -> Void)?

    init(
        _ label: String,
        style: Style,
        leadingDot: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.style = style
        self.leadingDot = leadingDot
        self.action = action
    }

    var body: some View {
        if let action, !style.isStatic {
            Button(action: action) { pill }
                .buttonStyle(.plain)
                .cypressHitArea()
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            pill
        }
    }

    private var isSelected: Bool {
        switch style {
        case .filterSelected, .structureFlagOn, .hazardOn, .careOn,
             .phenologyOn, .shotTypeOn, .darkFlagOn:
            return true
        default:
            return false
        }
    }

    private var pill: some View {
        HStack(spacing: CypressSpacing.Component.chipLegendGap) {
            if let leadingDot {
                Circle()
                    .fill(leadingDot)
                    .frame(
                        width: CypressSpacing.Component.chipLeadingDot,
                        height: CypressSpacing.Component.chipLeadingDot
                    )
            }
            if let dot = style.legendDot {
                legendDotView(dot)
            }
            Text(label)
                .font(style.font)
                .foregroundStyle(style.textColor)
        }
        .padding(.vertical, style.paddingV)
        .padding(.horizontal, style.paddingH)
        .background { Capsule().fill(style.fill) }
        .overlay {
            if let border = style.border {
                Capsule().strokeBorder(border.color, lineWidth: border.width)
            }
        }
        .cypressShadow(style.shadow)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func legendDotView(_ dot: LegendDot) -> some View {
        switch dot {
        case .filled:
            Circle()
                .fill(CypressColor.canopy)
                .frame(
                    width: CypressSpacing.Component.chipLegendDot,
                    height: CypressSpacing.Component.chipLegendDot
                )
        case .hollow:
            Circle()
                .fill(CypressColor.surfaceCard)
                .overlay {
                    Circle().strokeBorder(
                        CypressColor.canopy,
                        lineWidth: CypressSpacing.Component.chipLegendDotStroke
                    )
                }
                .frame(
                    width: CypressSpacing.Component.chipLegendDotHollow
                        + CypressSpacing.Component.chipLegendDotStroke * 2,
                    height: CypressSpacing.Component.chipLegendDotHollow
                        + CypressSpacing.Component.chipLegendDotStroke * 2
                )
        }
    }
}

// MARK: - Domain-typed chips

extension Chip {
    /// A phenology chip for screen 04.
    ///
    /// Takes a `PhenologyTag` and the `Species` it is being offered for, and renders nothing when
    /// the tag is not in that species' vocabulary — an evergreen is never asked about fall colour
    /// (D5). The check cannot be skipped by a caller because there is no `String` initializer here.
    @ViewBuilder
    static func phenology(
        _ tag: PhenologyTag,
        for species: Species,
        isOn: Bool,
        action: (() -> Void)? = nil
    ) -> some View {
        if tag.isAvailable(for: species) {
            Chip(
                PhenologyTagLabel.text(for: tag),
                style: isOn ? .phenologyOn : .phenologyOff,
                action: action
            )
        }
    }

    /// A care-log toggle chip (09). The `✓` is part of the on-state label string, per §2.
    static func care(
        _ action: CareAction,
        isOn: Bool,
        onTap: (() -> Void)? = nil
    ) -> Chip {
        Chip(
            isOn ? "\(CareActionLabel.text(for: action)) ✓" : CareActionLabel.text(for: action),
            style: isOn ? .careOn : .careOff,
            action: onTap
        )
    }
}

/// Display copy for the `PhenologyTag` vocabulary. Sentence case, per ARCHITECTURE §5.7.
enum PhenologyTagLabel {
    static func text(for tag: PhenologyTag) -> String {
        switch tag {
        case .leafOut: return "Leaf out"
        case .fullLeaf: return "Full leaf"
        case .fallColor: return "Fall color"
        case .bare: return "Bare"
        case .flowering: return "Flowering"
        case .fruiting: return "Fruiting"
        }
    }
}

/// Display copy for the `CareAction` vocabulary. `Weeded basin` and `Litter cleared` are verbatim
/// from screen 09.
enum CareActionLabel {
    static func text(for action: CareAction) -> String {
        switch action {
        case .watered: return "Watered"
        case .mulched: return "Mulched"
        case .weeded: return "Weeded basin"
        case .litterCleared: return "Litter cleared"
        case .staked: return "Staked"
        }
    }
}
