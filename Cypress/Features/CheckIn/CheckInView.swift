//
//  CheckInView.swift
//  Cypress — Features/CheckIn
//
//  Screen 05 · Light check-in. SCREENS.md lines 805–839. Dark appearance D3, lines 1427–1449.
//
//  Composed from C1 (header), C5 (the two segmented controls), C4 (structure chips), C15 (the
//  optional well) and C6 (the sticky CTA). The five anchored vitality rows are screen-05-only —
//  SCREENS.md §2 gives them no C-number — so they are built here from tokens.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). The numbers that remain are SCREENS.md 05's own margins, named in `CheckInMetrics`.
//
//  **Every word in the vitality rows comes from `Core`.** This file contains no class label, no
//  class number and no anchor sentence; see `CheckInPresentation`'s header for why.
//

import SwiftUI

struct CheckInView: View {

    @State private var model: CheckInModel
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.colorScheme) private var colorScheme

    init(
        treeID: UUID,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        gpsAccuracyM: Double? = nil,
        species: Species? = nil,
        initialDraft: CheckInDraft = CheckInDraft(),
        now: @escaping () -> Date = { Date() },
        onSaved: @escaping (CheckInSaveReceipt) -> Void = { _ in }
    ) {
        _model = State(
            wrappedValue: CheckInModel(
                treeID: treeID,
                api: api,
                outbox: outbox,
                attribution: attribution,
                gpsAccuracyM: gpsAccuracyM,
                species: species,
                initialDraft: initialDraft,
                now: now,
                onSaved: onSaved
            )
        )
    }

    var body: some View {
        let presentation = model.presentation

        // The card scrolls; the CTA and the footnote do not. SCREENS.md 05 §7 gives the CTA block
        // `margin-top:auto`, which in a fixed 812pt mock is the same thing as pinning it — on a real
        // device with real safe areas, pinning is what that means.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(
                        title: CheckInCopy.screenTitle,
                        trailingPill: CheckInCopy.headerPill,
                        onBack: { router?.pop() }
                    )

                    statusSection(presentation)
                    vitalitySection(presentation)
                    foliageSection(presentation)
                    structureSection(presentation)
                    optionalWell
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, CypressSpacing.labelSectionTop)
            }
            .scrollBounceBehavior(.basedOnSize)

            ctaBlock
            footnote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C1 carries the back affordance and the mock's `padding-top:62px` is the status-bar inset,
        // so the screen owns its whole chrome (SCREENS.md 05 "Frame").
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadSpecies() }
    }

    // MARK: - 1 · Status

    private func statusSection(_ presentation: CheckInPresentation) -> some View {
        section(label: CheckInCopy.statusLabel, top: CheckInMetrics.firstSectionTop) {
            // Deliberately not C5's `SegmentedControl.status` convenience: that one is typed on
            // `TreeStatus`, and a check-in reports an `ObservationStatus`. The two vocabularies are
            // separate types precisely so no code path can assign what a person saw onto the tree's
            // own record (DECISIONS §3.7, Core/Models/TreeObservation.swift). See ERRATA (E29).
            SegmentedControl(
                options: presentation.statusOptions,
                selection: statusBinding,
                label: ObservationStatusLabel.text(for:)
            )
        }
    }

    private var statusBinding: Binding<ObservationStatus> {
        Binding(
            get: { model.draft.status },
            set: { model.select(status: $0) }
        )
    }

    // MARK: - 2 · Vitality

    private func vitalitySection(_ presentation: CheckInPresentation) -> some View {
        section(
            label: presentation.showsVitality
                ? CheckInCopy.vitalityLabel
                : CheckInCopy.vitalityLabelSuppressed
        ) {
            if presentation.showsVitality {
                VStack(spacing: CypressSpacing.gapVitality) {
                    ForEach(presentation.vitalityRows) { row in
                        vitalityRow(row)
                    }
                }
            } else {
                // PRODUCT §3's seasonality rule. The section keeps its label and says why it is
                // empty, rather than the rows silently disappearing (BUILD-PLAN §9 M2).
                Callout(CheckInCopy.vitalitySuppressed, style: .dashed)
            }
        }
    }

    private func vitalityRow(_ row: VitalityRow) -> some View {
        Button {
            model.select(vitality: row.vitality)
        } label: {
            HStack(spacing: CheckInMetrics.rowSpacing) {
                referenceSwatch(row.vitality)

                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(titleColor(isSelected: row.isSelected))
                    Text(row.anchor)
                        .font(CypressFont.body115)
                        .lineSpacing(CypressFont.LineSpacing.body115)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if row.isSelected { checkCircle }
            }
            .padding(.vertical, CheckInMetrics.rowPaddingV)
            .padding(.leading, CheckInMetrics.rowPaddingLeading)
            .padding(.trailing, CheckInMetrics.rowPaddingTrailing)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(
                row.isSelected ? CypressColor.selectionFill : CypressColor.borderCool,
                radius: CypressRadius.control,
                width: row.isSelected
                    ? CheckInMetrics.rowBorderSelected
                    : CypressSpacing.Component.hairline
            )
            // D3: the selected row carries no shadow in dark, only the mint border.
            .cypressShadow(light: row.isSelected ? CypressShadow.selectedSm : nil, dark: nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The 44×30 reference swatch. Colour is secondary coding only (D3) — the label and the anchor
    /// sentence beside it carry the meaning, and both are always visible.
    ///
    /// The five anchor *photographs* BUILD-PLAN §8 makes an M2 entry gate do not exist yet; this is
    /// SCREENS.md §1.2's own `linear-gradient(140deg, …)` placeholder, which is what the design
    /// export draws. See ERRATA (E30).
    private func referenceSwatch(_ vitality: Vitality) -> some View {
        RoundedRectangle(cornerRadius: CypressRadius.vitalitySwatch, style: .continuous)
            .fill((CypressColor.Vitality(rawValue: vitality.classNumber) ?? .fair).gradient)
            .frame(width: CheckInMetrics.swatchWidth, height: CheckInMetrics.swatchHeight)
            .accessibilityHidden(true)
    }

    /// The trailing 20×20 check circle on the selected row.
    ///
    /// czPop, keyed on which row is selected: the prototype puts `czPop .4s` on 05's selected
    /// rows, and the check is the part of the row that actually arrives. Moving the *selection*
    /// rather than the row means tapping a second row pops the new check rather than re-running
    /// the whole list. `CypressMotion.pop`.
    private var checkCircle: some View {
        Circle()
            .fill(CypressColor.selectionFill)
            .overlay {
                // `CypressCheckmark`, not `Text("✓")`. The circle is 20 pt by SCREENS.md and does
                // not grow, so a scaling glyph inside it outgrew its own dot at AX sizes and was
                // clipped to a stub. The shape is the same mark the 18 success circle and the
                // route-done pin already draw, and being a `Shape` it is sized by its frame rather
                // than by the type ramp — which is right here, because the row's *title* and its
                // anchor sentence are what a reader is meant to grow, and they do.
                CypressCheckmark()
                    .stroke(
                        CypressColor.onSelectionFill,
                        style: StrokeStyle(
                            lineWidth: CheckInMetrics.checkGlyphStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: CheckInMetrics.checkGlyphWidth,
                        height: CheckInMetrics.checkGlyphHeight
                    )
            }
            .frame(width: CheckInMetrics.checkCircle, height: CheckInMetrics.checkCircle)
            .accessibilityHidden(true)
            .cypressPop(on: model.draft.vitality)
    }

    /// D3 lifts unselected row titles to `dark.text.strong` and leaves the selected one at
    /// `dark.text.primary`; in light both are `text.ink`.
    private func titleColor(isSelected: Bool) -> Color {
        colorScheme == .dark && !isSelected ? CypressColor.Dark.textStrong : CypressColor.textInk
    }

    // MARK: - 3 · Foliage

    private func foliageSection(_ presentation: CheckInPresentation) -> some View {
        section(label: CheckInCopy.foliageLabel) {
            // The option type is `FoliageDensity?` so the control can start with nothing selected:
            // foliage is skippable and SCREENS.md draws no "not answered" segment. The four options
            // are all non-nil, so the setter never receives one.
            SegmentedControl(
                options: presentation.foliageOptions.map { Optional($0) },
                selection: foliageBinding,
                label: { $0.map(FoliageDensityLabel.text(for:)) ?? "" }
            )
        }
    }

    private var foliageBinding: Binding<FoliageDensity?> {
        Binding(
            get: { model.draft.foliageDensity },
            set: { value in
                guard let value else { return }
                model.select(foliageDensity: value)
            }
        )
    }

    // MARK: - 4 · Structure

    private func structureSection(_ presentation: CheckInPresentation) -> some View {
        section(label: CheckInCopy.structureLabel) {
            // C4's wrapping chip row, shared with screen 06. One `Layout` rather than a second copy
            // of the same flex-wrap arithmetic; it belongs in `DesignSystem/Components` and should
            // move there when a third screen needs it.
            CypressChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(presentation.structureOptions, id: \.self) { flag in
                    let isOn = presentation.isFlagged(flag)
                    // D3 gives the dark chips their own C4 rows, including the weight-800 on-state,
                    // which the light `structureFlag*` pair does not carry.
                    Chip(
                        StructureFlagLabel.text(for: flag),
                        style: chipStyle(isOn: isOn)
                    ) {
                        model.toggle(flag)
                    }
                }
            }
        }
    }

    private func chipStyle(isOn: Bool) -> Chip.Style {
        switch (isOn, colorScheme == .dark) {
        case (true, false): return .structureFlagOn
        case (true, true): return .darkFlagOn
        case (false, false): return .structureFlagIdle
        case (false, true): return .darkFlagOff
        }
    }

    // MARK: - 5 · The optional well

    /// C15. SCREENS.md 05 §6 draws the well and specifies nothing behind it — no picker, no editor,
    /// no sheet — so it is drawn and nothing is invented to sit under it (DECISIONS constraint 21).
    /// `CheckInDraft` already carries the note and the photos it would fill in. See ERRATA (E25).
    private var optionalWell: some View {
        OptionalWell(CheckInCopy.optionalWell)
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - 6 · Sticky CTA and footnote

    private var ctaBlock: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            if model.saveFailed {
                Text(CheckInCopy.saveFailed)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PrimaryButton(CheckInCopy.saveCTA) {
                Task { await model.save() }
            }
        }
        .padding(.top, CheckInMetrics.ctaTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.bottom, CypressSpacing.bottomStickyCTAGap)
    }

    private var footnote: some View {
        Text(CheckInCopy.footnote)
            .font(CypressFont.body12)
            .foregroundStyle(CypressColor.textFaintAlt)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CypressSpacing.gutterLabel)
            .padding(.bottom, CheckInMetrics.footnoteBottom)
    }

    // MARK: - Section chrome

    /// `padding:14px 18px 0` with a `margin-bottom:6px` under the label — §1.6's rhythm for a block
    /// headed by an uppercase micro-label, which is every block on this screen.
    private func section<Content: View>(
        label: String,
        top: CGFloat = CypressSpacing.labelSectionTop,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CheckInMetrics.labelToControl) {
            Text(label).cypressMicroLabel()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, top)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }
}
