//
//  ReportView.swift
//  Cypress — Features/Report
//
//  Screen 06 · Report an issue. SCREENS.md lines 843–873.
//
//  Composed from C1 (header), C4 (chips), C7 (secondary button) and C14 (dashed disclosure). The
//  311 panel is screen-06-only — SCREENS.md §2 gives it no C-number — so it is built here from
//  tokens, including the 22×22 phone glyph the spec states as an SVG path.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). The numbers that remain are SCREENS.md 06's own margins, named in `ReportMetrics`.
//

import SwiftUI

struct ReportView: View {

    @State private var model: ReportModel
    @Environment(AppRouter.self) private var router: AppRouter?

    init(
        treeID: UUID,
        api: any CypressAPI,
        dialer: any TelephoneDialing = SystemTelephoneDialer(),
        initialSelection: ReportSelection = .nothing,
        onSaveReminder: ((PrivateReminderDraft) async throws -> Void)? = nil
    ) {
        _model = State(
            wrappedValue: ReportModel(
                treeID: treeID,
                api: api,
                dialer: dialer,
                initialSelection: initialSelection,
                onSaveReminder: onSaveReminder
            )
        )
    }

    var body: some View {
        @Bindable var model = model
        let presentation = model.presentation

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: ReportCopy.screenTitle, onBack: { router?.pop() })

                hazardPicker(presentation)
                notePicker(presentation)

                // One branch, not three blocks: the panel, the reminder and the disclosure all
                // depend on a hazard being selected. See `ReportPresentation.showsHazardBranch`.
                if presentation.showsHazardBranch {
                    hazardPanel
                    reminderButton
                    disclosure
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ReportMetrics.bottomInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C1 carries the back affordance and the `padding-top:62px` is the status-bar inset, so the
        // screen owns its whole chrome (SCREENS.md 06 "Frame").
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            ReportCopy.callUnavailableTitle,
            isPresented: $model.isShowingCallUnavailable
        ) {
            Button(ReportCopy.callUnavailableDismiss, role: .cancel) {}
        } message: {
            Text(ReportCopy.callUnavailableMessage)
        }
    }

    // MARK: - The two pickers

    private func hazardPicker(_ presentation: ReportPresentation) -> some View {
        section(label: ReportCopy.hazardSectionLabel, color: CypressColor.signalAmber) {
            ReportChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(presentation.hazardCategories, id: \.self) { category in
                    Chip(
                        HazardCategoryLabel.text(for: category),
                        style: presentation.selectedHazard == category ? .hazardOn : .hazardOff
                    ) {
                        Task { await model.select(hazard: category) }
                    }
                }
            }
        }
    }

    private func notePicker(_ presentation: ReportPresentation) -> some View {
        section(label: ReportCopy.noteSectionLabel, color: CypressColor.textFaint) {
            ReportChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(presentation.noteCategories, id: \.self) { category in
                    // Idle is C4's "structure flag, idle" row, which is exactly the fill, border,
                    // text and padding SCREENS.md 06 §3 states for these chips. Its `on` twin is the
                    // selected appearance, which 06 never draws — the least invented answer to an
                    // unspecified state is the variant the catalogue already pairs with this one.
                    Chip(
                        CommunityNoteCategoryLabel.text(for: category),
                        style: presentation.selectedNote == category ? .structureFlagOn : .structureFlagIdle
                    ) {
                        model.select(note: category)
                    }
                }
            }
        }
    }

    /// `padding:14px 18px 0` — §1.6's rhythm for a block headed by an uppercase micro-label.
    private func section<Content: View>(
        label: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ReportMetrics.labelToChips) {
            Text(label).cypressMicroLabel(color: color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - The 311 panel

    private var hazardPanel: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(CypressColor.signalAmber)
                .overlay {
                    HazardPhoneGlyph()
                        .fill(CypressColor.hazardPanelGlyph)
                        .frame(width: ReportMetrics.panelGlyph, height: ReportMetrics.panelGlyph)
                }
                .frame(width: ReportMetrics.panelCircle, height: ReportMetrics.panelCircle)
                .padding(.bottom, ReportMetrics.panelCircleBottom)
                .accessibilityHidden(true)

            Text(ReportCopy.hazardPanelTitle)
                .font(CypressFont.hazardTitle)
                .foregroundStyle(CypressColor.textInk)
                .multilineTextAlignment(.center)
                .padding(.bottom, ReportMetrics.panelTitleBottom)

            Text(ReportCopy.hazardPanelBody)
                .font(CypressFont.body135)
                .lineSpacing(CypressFont.LineSpacing.body135)
                .foregroundStyle(CypressColor.hazardPanelText)
                .multilineTextAlignment(.center)
                .padding(.bottom, ReportMetrics.panelBodyBottom)

            callButton
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, ReportMetrics.panelPaddingV)
        .padding(.horizontal, ReportMetrics.panelPaddingH)
        .background {
            RoundedRectangle(cornerRadius: ReportMetrics.panelRadius, style: .continuous)
                .fill(CypressColor.hazardPanelFill)
        }
        .cypressBorder(
            CypressColor.hazardPanelBorder,
            radius: ReportMetrics.panelRadius,
            width: CypressSpacing.Component.hairlineStrong
        )
        .padding(.top, ReportMetrics.panelTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    /// C6's geometry with the panel's own amber fill — SCREENS.md §2 lists no hazard variant of C6,
    /// so this stays local to 06 rather than widening a shared component for one screen.
    private var callButton: some View {
        Button {
            Task { await model.callCity() }
        } label: {
            Text(ReportCopy.callCTA)
                .font(CypressFont.body16ExtraBold)
                .foregroundStyle(CypressColor.hazardCTAText)
                .frame(maxWidth: .infinity)
                .padding(CypressSpacing.Component.buttonPadding)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(CypressColor.hazardCTAFill)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressShadow(light: CypressShadow.hazard, dark: nil)
    }

    // MARK: - Reminder and disclosure

    /// The button, and the one line that answers a tap on it.
    ///
    /// Once the reminder is saved the button is gone rather than disabled: the work is done, there
    /// is nothing to press, and SCREENS.md §5 gap 2 leaves disabled styling **NOT SPECIFIED**, so
    /// there is no drawn state to fall back on. A failure keeps the button — the reminder is not on
    /// disk and pressing again is the honest next move.
    @ViewBuilder
    private var reminderButton: some View {
        VStack(spacing: ReportMetrics.reminderNoteTop) {
            if model.reminderSaveState == .saved {
                reminderNote(ReportCopy.reminderSaved)
            } else {
                SecondaryOutlineButton(ReportCopy.saveReminder, style: .compact) {
                    Task { await model.saveReminder() }
                }
                if model.reminderSaveState == .failed {
                    reminderNote(ReportCopy.reminderFailed)
                }
            }
        }
        .padding(.top, ReportMetrics.secondaryTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    private func reminderNote(_ text: String) -> some View {
        Text(text)
            .font(CypressFont.body125)
            .foregroundStyle(CypressColor.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var disclosure: some View {
        Callout(
            ReportCopy.disclosureOpening,
            style: .dashed,
            emphasis: " " + ReportCopy.disclosureEmphasis,
            continuation: ReportCopy.disclosureContinuation
        )
        .padding(.top, ReportMetrics.disclosureTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }
}

// MARK: - The phone glyph

/// SCREENS.md 06 §4's 22×22 phone, transcribed from the SVG path it states verbatim:
/// `M5 2c1.5 0 3 2.5 3 4 0 1.2-1.4 1.8-1.4 2.8 0 1.6 4 6 5.6 6 1 0 1.6-1.4 2.8-1.4 1.5 0 4 1.5 4 3
/// s-1.8 3.6-4 3.6C9 20 2 13 2 6c0-2.2 1.8-4 3-4z`
///
/// Relative curves are resolved to absolute control points against the source's 22×22 viewBox and
/// then scaled, so the shape is the spec's own geometry rather than a redrawn approximation.
struct HazardPhoneGlyph: Shape {

    private static let viewBox: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.viewBox
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        path.move(to: point(5, 2))
        path.addCurve(to: point(8, 6), control1: point(6.5, 2), control2: point(8, 4.5))
        path.addCurve(to: point(6.6, 8.8), control1: point(8, 7.2), control2: point(6.6, 7.8))
        path.addCurve(to: point(12.2, 14.8), control1: point(6.6, 10.4), control2: point(10.6, 14.8))
        path.addCurve(to: point(15, 13.4), control1: point(13.2, 14.8), control2: point(13.8, 13.4))
        path.addCurve(to: point(19, 16.4), control1: point(16.5, 13.4), control2: point(19, 14.9))
        // `s` — the first control point is the reflection of the previous one about (19, 16.4).
        path.addCurve(to: point(15, 20), control1: point(19, 17.9), control2: point(17.2, 20))
        path.addCurve(to: point(2, 6), control1: point(9, 20), control2: point(2, 13))
        path.addCurve(to: point(5, 2), control1: point(2, 3.8), control2: point(3.8, 2))
        path.closeSubpath()
        return path
    }
}

// MARK: - Chip wrapping

/// The `flex-wrap` the chip rows of SCREENS.md 06 §2–3 declare, with its `gap:7px`.
///
/// SwiftUI has no wrapping stack, and the alternative — pre-splitting the chips into fixed rows —
/// would bake in a line break that the spec expresses as a flow property and that Dynamic Type
/// invalidates at AX1 (ARCHITECTURE §6). One gap value, applied on both axes, as CSS `gap` does.
struct ReportChipFlow: Layout {

    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let candidate = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, candidate > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
