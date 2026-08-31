//
//  ScreenHeader.swift
//  Cypress — DesignSystem/Components
//
//  C1 · `ScreenHeader` — SCREENS.md §2.
//  Back circle + serif title + optional trailing pill. Used by 02, 05, 06, 11, 12, 13, 14, 16, 17, D3.
//

import SwiftUI

struct ScreenHeader<Trailing: View>: View {

    /// `padding: 10px 18px 4px`; 02 uses `10px 18px 6px`.
    enum BottomInset {
        case standard
        case wide

        var value: CGFloat {
            switch self {
            case .standard: return CypressSpacing.headerPaddingBottom
            case .wide: return CypressSpacing.headerPaddingBottom02
            }
        }
    }

    let title: String
    var bottomInset: BottomInset = .standard
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // ══════════════════════════════════════════════════════════════════════════════════════
        // One row at the drawn sizes, two once the title cannot share one.
        //
        // This was the worst Dynamic Type failure in the app and it is worth describing, because
        // the symptom looks nothing like the cause. §2 C1 is `[back circle] [title] [pill]` on one
        // line, and `HeaderPill` ends in `.fixedSize()` so the pill always takes its intrinsic
        // width. At AX5 on a 393 pt phone the circle takes 44, the pill's "under a minute" takes
        // ~300, and the 22 pt serif title is left with about 60 pt — into which it wraps *one
        // letter per line*. Screen 05 rendered as a vertical column spelling C-h-e-c-k-–-i down
        // the whole viewport with the card pushed off the bottom.
        //
        // Two lines rather than a truncated pill or a scaled title: the pill is real information
        // on every screen that has one (`under a minute` on 05, `Outer Sunset` on 12, the tree's
        // name on 11 and 13, `3 waiting · offline` on 17) and the title is what the screen is. At
        // a size where both cannot fit across, the honest layout is one under the other.
        // ══════════════════════════════════════════════════════════════════════════════════════
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CypressSpacing.Component.headerSpacing) {
                    HStack(spacing: CypressSpacing.Component.headerSpacing) {
                        backButton
                        titleText
                        Spacer(minLength: 0)
                    }
                    trailing
                }
            } else {
                HStack(spacing: CypressSpacing.Component.headerSpacing) {
                    backButton
                    titleText
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.headerPaddingTop)
        .padding(.horizontal, CypressSpacing.headerPaddingHorizontal)
        .padding(.bottom, bottomInset.value)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button(action: onBack) { BackCircle() }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
        }
    }

    private var titleText: some View {
        Text(title)
            .font(CypressFont.screenTitle)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, bottomInset: BottomInset = .standard, onBack: (() -> Void)? = nil) {
        self.init(title: title, bottomInset: bottomInset, onBack: onBack) { EmptyView() }
    }
}

extension ScreenHeader where Trailing == HeaderPill {
    /// The common case: a plain trailing pill, e.g. `under a minute` (05) or `Outer Sunset` (12).
    init(
        title: String,
        trailingPill: String,
        pillStyle: HeaderPill.Style = .neutral,
        bottomInset: BottomInset = .standard,
        onBack: (() -> Void)? = nil
    ) {
        self.init(title: title, bottomInset: bottomInset, onBack: onBack) {
            HeaderPill(trailingPill, style: pillStyle)
        }
    }
}

extension ScreenHeader where Trailing == HeaderPillButton {
    /// The pill as the control — screens 12 and 16, where the name in the header *is* what the
    /// reader changes. See `HeaderPillButton`.
    init(
        title: String,
        trailingPill: String,
        pillHint: String,
        bottomInset: BottomInset = .standard,
        onBack: (() -> Void)? = nil,
        onTapPill: @escaping () -> Void
    ) {
        self.init(title: title, bottomInset: bottomInset, onBack: onBack) {
            HeaderPillButton(trailingPill, hint: pillHint, action: onTapPill)
        }
    }
}

// MARK: - Pieces

/// 44×44 circle, `1px` border, `shadow.restSoft`. Already at the 44pt minimum, so no hit-area
/// expansion is needed. Dark (D3): `#18251D` fill, `#27352B` border, `#AEBBAB` chevron, no shadow.
struct BackCircle: View {
    var body: some View {
        Circle()
            .fill(CypressColor.surfaceCard)
            .overlay { Circle().strokeBorder(CypressColor.borderCool, lineWidth: 1) }
            .overlay {
                CypressChevron()
                    .stroke(
                        CypressColor.textBody,
                        style: StrokeStyle(
                            lineWidth: CypressSpacing.Component.chevronStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: CypressSpacing.Component.chevronWidth,
                        height: CypressSpacing.Component.chevronHeight
                    )
            }
            .frame(
                width: CypressSpacing.Component.backCircle,
                height: CypressSpacing.Component.backCircle
            )
            .cypressShadow(light: CypressShadow.restSoft, dark: nil)
            .contentShape(Circle())
            .accessibilityHidden(true)
    }
}

/// C1's optional trailing pill. `neutral` is the documented default; `amber` is 17's
/// `3 waiting · offline`.
struct HeaderPill: View {
    enum Style {
        case neutral
        case amber
    }

    let text: String
    var style: Style = .neutral

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(style == .amber ? CypressFont.body12Bold : CypressFont.body12)
            .foregroundStyle(
                style == .amber ? CypressColor.amberPillText : CypressColor.textMuted
            )
            .padding(.vertical, CypressSpacing.Component.headerPillPaddingV)
            .padding(.horizontal, CypressSpacing.Component.headerPillPaddingH)
            .background {
                Capsule().fill(
                    style == .amber ? CypressColor.amberPillFill : CypressColor.surfaceCard
                )
            }
            .cypressPillBorder(
                style == .amber ? CypressColor.amberPillBorder : CypressColor.borderCool
            )
            // Intrinsic width while the pill shares a row with the title, so it never compresses to
            // an ellipsis beside it. Once C1 has moved it onto its own line there is no competition
            // and a long pill may wrap — `3 waiting · offline` at AX5 needs two lines and has one.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }
}

/// `HeaderPill` when the pill is *the way to change what the screen is about* — the Journal's two
/// stats segments, 12 and 16.
///
/// **The place name is the control.** The picker used to be a boxed `SecondaryOutlineButton`
/// reading `Change`, stacked under the provenance sentence; the owner's ruling retired it and moved
/// the affordance onto the name it changes. Three things were weighed and are recorded in the
/// picker-header ruling, pending — briefly: a `Change` box at the gutter sits directly above §2's
/// micro-label with nothing between them, so it crowded the section it was not part of; it carried
/// the visual weight of a primary action while §4's `Walk to it` (the screen's one directed ask) was
/// the actual primary; and it named an operation rather than a subject, so a reader had to look up
/// to find out what would change. The name plus a mark is the smaller, quieter, and more specific
/// of the two.
///
/// **Same capsule as `HeaderPill` and deliberately so.** It is the same element it always was,
/// still saying what the screen is about; the mark is what says it can be pressed. A filled or
/// outlined "button" pill would have re-imported the weight the ruling removed.
///
/// **NOT SPECIFIED** — SCREENS.md §2 draws C1's pill as a label only. The mark's base sizes live in
/// `CypressSpacing.Component` and the glyph is `CypressChevron`, drawn here like every other mark in
/// the app — there are no SF Symbols (RULINGS R57, `DrawnGlyphGuardTests`).
///
/// **The mark is drawn in `textMuted`, the pill's own label color, and that is a contrast
/// requirement rather than a preference.** It was `chevronDisclosure` — the token every other
/// disclosure chevron in the app uses — and measured off rendered pixels that came to **1.96:1**
/// against the capsule in light and **2.16:1** in dark. WCAG 2.1 SC 1.4.11 asks 3:1 of a graphical
/// object that alone identifies a control, and by this component's own account above, this mark is
/// exactly that. `chevronDisclosure` is fine where it lives: on a full-width row with a trailing
/// edge, the layout is also saying "this opens something", and the chevron is not carrying the
/// claim by itself. Here it is. Matching the label's own token measures **6.75:1** light and
/// **6.06:1** dark, and has the second virtue of making the name and the mark one object rather
/// than a name with a decoration attached. `chevronDisclosure` is untouched at its other sites.
///
/// **The mark scales with the label.** `@ScaledMetric(relativeTo: .caption)`, because `body12` — the
/// label beside it — is built `relativeTo: .caption`, so the two ride one curve and the ratio
/// between them holds at every setting. `AccountAskView.AccountProviderButton` is the precedent and
/// this follows its *reasoning* rather than its literal `.body`: that comment's point is to pick the
/// curve the paired font actually uses, and there the paired font is `body15Bold`. Fixed points
/// here left a 5pt speck beside a ~34pt name at AX5.
///
/// **Accessibility.** The visual is ~24pt tall at default type, so `cypressHitArea` gives it the
/// 44pt target without moving the drawn pill (ARCHITECTURE §6). The label is the place name and the
/// hint is what pressing it does, which is strictly more than the retired control offered:
/// `Change, button` named an operation without its subject, where this reads `Sunset/Parkside,
/// button` and then the caller's hint.
struct HeaderPillButton: View {

    let text: String
    /// What pressing it does, read after the label and the trait.
    let hint: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The mark's drawn size, following the label's own curve — see the note above.
    @ScaledMetric(relativeTo: .caption) private var chevronWidth =
        CypressSpacing.Component.headerPillChevronWidth
    @ScaledMetric(relativeTo: .caption) private var chevronHeight =
        CypressSpacing.Component.headerPillChevronHeight
    @ScaledMetric(relativeTo: .caption) private var chevronStroke =
        CypressSpacing.Component.headerPillChevronStroke

    init(_ text: String, hint: String, action: @escaping () -> Void) {
        self.text = text
        self.hint = hint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            // ── `.firstTextBaseline`, and the wrapped pill is the reason ────────────────────────
            //
            // Centered, the mark sits against the *whole* height of the label, which is right while
            // the label is one line and wrong the moment it is two. The radius fallback is the case
            // that shows it: at AX5 `Within a 15-minute walk` wraps, the pill grows to ~101pt tall,
            // and a centered mark floats in the white space beside the line break, touching neither
            // line and reading as attached to nothing. Aligned to the first baseline it rides the
            // first line, which is where a reader looks for it and where it stays at every size.
            //
            // A `Shape` has no baseline of its own, so its bottom edge is what SwiftUI aligns; the
            // guide below lifts it by the mark's own optical center instead, which puts the "v" on
            // the text's midline rather than hanging it off the baseline.
            HStack(alignment: .firstTextBaseline, spacing: CypressSpacing.Component.headerPillChevronGap) {
                Text(text)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)

                CypressChevron(direction: .down)
                    .stroke(
                        CypressColor.textMuted,
                        style: StrokeStyle(
                            lineWidth: chevronStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: chevronWidth, height: chevronHeight)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[.bottom] - (dimensions.height / 2)
                    }
            }
            .padding(.vertical, CypressSpacing.Component.headerPillPaddingV)
            .padding(.horizontal, CypressSpacing.Component.headerPillPaddingH)
            .background { Capsule().fill(CypressColor.surfaceCard) }
            .cypressPillBorder(CypressColor.borderCool)
            // `HeaderPill`'s rule, and for its reason: intrinsic width while the pill shares the
            // row with the title, free to wrap once C1 has moved it onto its own line.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .accessibilityLabel(text)
        .accessibilityHint(hint)
    }
}
