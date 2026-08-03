//
//  QuadActionRow.swift
//  Cypress — DesignSystem/Components
//
//  C8 · `QuadActionRow` — SCREENS.md §2. The quiet row under the profile CTA (03, D2).
//
//  **NOT SPECIFIED** (§2 C8, §5 gap 3): icons for the four actions. The spec shows text only, and
//  no icon is invented here. That sentence is load-bearing for the selected state below — see
//  `Appearance`.
//
//  ── The first cell has two states (RULINGS R2, ERRATA E112) ───────────────────────────────
//  R2 rules that `Favorite` gets a selected appearance and that a second tap takes the favorite
//  off. The two things R2 fixes about it, restated where they are built:
//
//  - **The label does not change.** `Favorite` in both states, because it is a noun naming the
//    thing rather than a verb naming the next tap. `Unfavorite` under the same cell is how a
//    control starts lying about what it is.
//  - **The state is not carried by color alone.** The selected cell inverts to the accent fill
//    under the accent's own label color (task #153) *and* takes a heavier border *and* a heavier
//    weight, and it announces itself through `.isSelected` and a spoken value. A toggle whose
//    on-state is a hue fails for anyone who cannot see the hue, and ERRATA E103 is this app's own
//    record of a state that reached nobody.
//
//  Tap targets: a cell is ~31pt tall as drawn (`padding:9px 2px` + a 12pt label). The cell keeps
//  that size; `.cypressHitArea()` gives it 44pt.
//

import SwiftUI

struct QuadActionRow: View {

    /// The four actions, labels verbatim from screen 03.
    enum Action: String, CaseIterable, Identifiable {
        case favorite
        case care
        case share
        case report

        var id: String { rawValue }

        /// Verbatim from 03, and the same string in every state (R2).
        var label: String {
            switch self {
            case .favorite: return "Favorite"
            case .care: return "Care"
            case .share: return "Share"
            case .report: return "Report"
            }
        }

        /// Whether this cell is a control with an on-state at all.
        ///
        /// Only the favorite is. `Care`, `Share` and `Report` open something and come back, so a
        /// cell that changed nothing on the screen is the right drawing for them (ERRATA E101); a
        /// favorite changes only itself, which is why it is the one that needed a state.
        ///
        /// Exhaustive, so a fifth action cannot be added without answering the question.
        var hasOnState: Bool {
            switch self {
            case .favorite: return true
            case .care, .share, .report: return false
            }
        }
    }

    var actions: [Action] = Action.allCases
    /// The cells drawn in their selected appearance. Only a cell whose `hasOnState` is true can be
    /// in it; anything else in this set draws idle and announces nothing, because a `Share` that
    /// says "on" is a claim about a state that does not exist.
    var selected: Set<Action> = []
    var onTap: (Action) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How the cells share the width: one row of four at the drawn sizes, two rows of two at the
    /// accessibility sizes.
    ///
    /// Four across at AX5 leaves each label about 80 pt, and `lineLimit(1)` with a 0.8 floor met
    /// the ramp as `Favo…` / `Rep…` (ERRATA E196 §8) — an ellipsis inside a control. Exposed as a
    /// value for the reason `appearance(isSelected:)` is: SwiftUI builds no in-process render tree
    /// a test can walk, so the reflow decision has to be a function a test can call.
    static func rows(of actions: [Action], isAccessibilitySize: Bool) -> [[Action]] {
        guard isAccessibilitySize else { return [actions] }
        return stride(from: 0, to: actions.count, by: 2).map {
            Array(actions[$0..<min($0 + 2, actions.count)])
        }
    }

    var body: some View {
        VStack(spacing: CypressSpacing.Component.quadSpacing) {
            ForEach(
                Self.rows(of: actions, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize),
                id: \.first?.id
            ) { row in
                HStack(spacing: CypressSpacing.Component.quadSpacing) {
                    ForEach(row) { action in
                        cell(action)
                    }
                }
            }
        }
        .padding(.vertical, CypressSpacing.Component.quadRowPaddingV)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    @ViewBuilder
    private func cell(_ action: Action) -> some View {
        let isOn = isSelected(action)
        let appearance = QuadActionRow.appearance(isSelected: isOn)
        let button = Button {
            onTap(action)
        } label: {
            Text(action.label)
                .font(appearance.font)
                .foregroundStyle(appearance.label)
                // One line and a 0.8 floor at the drawn sizes, where the four labels are short and
                // the row is the mock's. At the accessibility sizes the cell is half a row (see
                // `rows(of:isAccessibilitySize:)`) and the label keeps its whole word instead of
                // an ellipsis — the control is its word here (ERRATA E196 §8).
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CypressSpacing.Component.quadCellPaddingV)
                .padding(.horizontal, CypressSpacing.Component.quadCellPaddingH)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                        .fill(appearance.fill)
                }
                .cypressBorder(
                    appearance.border,
                    radius: CypressRadius.control,
                    width: appearance.borderWidth
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .accessibilityLabel(action.label)

        // The three cells with no on-state get no spoken value and no trait: a `Share` that
        // announced "Off" would be describing a state it does not have.
        if let spoken = QuadActionRow.spokenValue(for: action, isSelected: isOn) {
            button
                .accessibilityValue(spoken)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
        } else {
            button
        }
    }

    private func isSelected(_ action: Action) -> Bool {
        action.hasOnState && selected.contains(action)
    }

    // MARK: - Appearance

    /// One cell's drawn appearance, in either state.
    ///
    /// Exposed as a value rather than buried in the body for the reason `AccessibilityTests`'
    /// preamble gives: SwiftUI builds no in-process accessibility tree and no in-process render
    /// tree a test can walk, so the only honest way to pin "these two states are different, and
    /// different in more than one channel" is to make the decision a value.
    struct Appearance: Equatable {
        let fill: Color
        let label: Color
        let border: Color
        let borderWidth: CGFloat
        let font: Font
    }

    /// The idle cell is SCREENS.md §2 C8 verbatim: white card, `border.cool` hairline, 12/600
    /// `text.body`.
    ///
    /// The selected cell is RULINGS R2, minus one clause it could not have. R2 says the label and
    /// border take `accent` and the label does not change. **There is no heart glyph to fill**:
    /// §2 C8 marks the four icons NOT SPECIFIED and §5 gap 3 repeats it, so this row has never
    /// drawn one, and inventing a heart for one of four text cells is a drawn decision (DECISIONS
    /// constraint 21) on the very component R2 is careful to treat as already-drawn. The day
    /// design lands the four icons, the filled/outline pair is one line here. See ERRATA (E112).
    ///
    /// **The fill inverts, since task #153.** E112 built R2's "tinted surface" clause as
    /// `callout.green.fill`, and the owner reported the result from a device walk as no state at
    /// all: pale green against the idle white, with the label moving between two dark greens, is a
    /// difference a screen indoors can show and a phone in daylight cannot. The selected cell now
    /// takes the treatment the app's other selected text control already has — C4's selected
    /// filter chip: `cta.fill` under `cta.label` — so "this tree is yours" reads at the same
    /// strength as "this filter is on". Tokens only, no glyph; see
    /// R33.
    ///
    /// The state still carries in more channels than hue:
    ///
    /// - **fill and label** — `cta.fill` under `cta.label`, the selected-filter-chip pair, which
    ///   inverts the cell's luminance in both schemes. That inversion is itself a channel that
    ///   survives grayscale, which the old tinted surface was not.
    /// - **border width and weight** — `hairlineStrong` and 12/800 against `hairline` and 12/600,
    ///   unchanged from E112. These are why this state does not fail the way E103's did.
    static func appearance(isSelected: Bool) -> Appearance {
        isSelected
            ? Appearance(
                fill: CypressColor.ctaFill,
                label: CypressColor.ctaLabel,
                border: CypressColor.ctaFill,
                borderWidth: CypressSpacing.Component.hairlineStrong,
                font: CypressFont.body12ExtraBold
            )
            : Appearance(
                fill: CypressColor.surfaceCard,
                label: CypressColor.textBody,
                border: CypressColor.borderCool,
                borderWidth: CypressSpacing.Component.hairline,
                font: CypressFont.body12SemiBold
            )
    }

    // MARK: - What a cell announces

    /// The spoken state of a cell, or `nil` for the three cells that have none.
    ///
    /// The label is *not* where this goes: R2 fixes the label as `Favorite` in both states, so a
    /// VoiceOver user who only heard the label would hear no difference at all. The value is spoken
    /// after the label — `Favorite, On, selected, button` — and it is spoken in **both** states, so
    /// "this tree is not one of yours" is as audible as the reverse. The `.isSelected` trait rides
    /// beside it because that is what every other selected control in this app already sets (C4).
    static func spokenValue(for action: Action, isSelected: Bool) -> String? {
        guard action.hasOnState else { return nil }
        return isSelected ? "On" : "Off"
    }
}
