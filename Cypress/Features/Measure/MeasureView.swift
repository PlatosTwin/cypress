//
//  MeasureView.swift
//  Cypress — Features/Measure
//
//  Screen 16 · Measure. SCREENS.md lines 1212–1237.
//
//  A pushed screen, not a sheet: it is a whole 812pt frame with its own C1 header and a back circle,
//  which is what every pushed screen in the app draws and what no sheet in it does.
//
//  Composed from C1 (header + trailing pill), C5 (both segmented controls — `SegmentedControl
//  .method` was already written against `MeasurementMethod` for this screen), C4's sanity-check
//  pill, C12 (the previous reading's method badge) and C6. The keypad has no C-number: SCREENS.md
//  §2's catalogue does not carry one and §5 describes it inline, so it is built here from tokens,
//  the same way 13's photo strip was.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 16's own margins, named in `MeasureMetrics`.
//
//  Everything about *whether* a block appears is decided in `MeasurePresentation`. This file draws
//  what it is given, which is what makes the D6 notice and the anomaly line testable without a
//  renderer.
//

import SwiftUI

struct MeasureView: View {

    @State private var model: MeasureModel
    @Environment(AppRouter.self) private var router: AppRouter?

    init(
        treeID: UUID,
        /// Which of 16 §2's two segments this screen opens on — the measurement whichever control
        /// pushed it was a control *for* (RULINGS R15). `.dbh` is the drawn selection and stays the
        /// default, for the one entrance that names no measure: screen 11's general link.
        kind: MeasurementKind = .dbh,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        // A closure, because `@State` runs its initialiser exactly once and a `Double?` passed
        // through it is frozen at the first frame — on a cold launch, `nil`, which D6 treats as
        // unusable (ERRATA E158). The model asks
        // this at the moment it needs an answer; see `MeasureModel.gpsAccuracyM`.
        gpsAccuracyM: @escaping @MainActor () -> Double? = { nil },
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        onSaved: @escaping (MeasureSaveReceipt) -> Void = { _ in }
    ) {
        _model = State(
            wrappedValue: MeasureModel(
                treeID: treeID,
                api: api,
                outbox: outbox,
                attribution: attribution,
                gpsAccuracyM: gpsAccuracyM,
                // Through `MeasureDraft(kind:)` rather than by setting `kind` alone, because the
                // unit under the keypad is a function of the kind — a height drafted in centimetres
                // is the same class of silent error this parameter exists to close.
                initialDraft: MeasureDraft(kind: kind),
                now: now,
                calendar: calendar,
                onSaved: onSaved
            )
        )
    }

    var body: some View {
        MeasureScreen(
            presentation: model.presentation,
            saveFailed: model.saveFailed,
            isSaving: model.isSaving,
            onBack: { router?.pop() },
            onSelectKind: { model.select(kind: $0) },
            onSelectMethod: { model.select(method: $0) },
            onSwitchUnit: { model.switchUnit() },
            onKey: { model.press($0) },
            onSave: { Task { await model.save() } }
        )
        .task { await model.load() }
    }
}

// MARK: - The screen itself

/// Screen 16's layout, given a finished derivation.
///
/// Split from `MeasureView` for the reason `ActivityScreen` is split from `ActivityView`: a layout
/// whose content only exists after an `async` read cannot be photographed offscreen at all, and this
/// screen's states — a poor fix, a shrinking trunk, a first-ever reading — are exactly the ones
/// worth looking at.
struct MeasureScreen: View {

    let presentation: MeasurePresentation
    var saveFailed = false
    var isSaving = false
    var onBack: (() -> Void)?
    var onSelectKind: ((MeasurementKind) -> Void)?
    var onSelectMethod: ((MeasurementMethod) -> Void)?
    var onSwitchUnit: (() -> Void)?
    var onKey: ((MeasureKey) -> Void)?
    var onSave: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    kindSection
                    readoutSection
                    methodSection
                    keypad

                    // §6's CTA carries `margin-top:auto`, so everything below it is pinned to the
                    // bottom of the frame on a screen taller than its content (SCREENS.md §5 gap 11).
                    Spacer(minLength: 0)

                    // Both of these sit *above* the CTA, because both are things to read before the
                    // tap rather than after it, and neither is a gate (DECISIONS §2.5).
                    if let anomaly = presentation.anomaly { anomalyLine(anomaly) }
                    if let notice = presentation.chartNotice { chartNotice(notice) }
                    if saveFailed { failureLine }
                    ctaBlock
                    footnote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - §1 Header (C1)

    /// `title: Measure`, trailing pill `Grandmother Cypress`.
    ///
    /// No pill until the read lands, and none after it fails: an empty pill is a claim that this
    /// tree has no name. Same rule as 11's and 13's.
    @ViewBuilder
    private var header: some View {
        if let name = presentation.treeDisplayName {
            ScreenHeader(title: MeasureCopy.screenTitle, trailingPill: name, onBack: onBack)
        } else {
            ScreenHeader(title: MeasureCopy.screenTitle, onBack: onBack)
        }
    }

    // MARK: - §2 What are you measuring? (C5)

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: MeasureMetrics.labelBottom) {
            Text(MeasureCopy.kindLabel).cypressMicroLabel()
            SegmentedControl(
                options: [.dbh, .height],
                selection: Binding(
                    get: { presentation.draft.kind },
                    set: { onSelectKind?($0) }
                ),
                label: MeasureCopy.kindSegment,
                size: .large
            )
        }
        .padding(.top, MeasureMetrics.firstSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - §3 Readout

    private var readoutSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // 56 pt is past the width of the display before AX5, and the unit suffix beside
                // it goes off the edge first. One line with a floor lets the readout grow until it
                // stops fitting and then stop — the same number is on the keypad above it, and a
                // readout whose unit has been pushed off the screen is a `Quantity` missing half
                // of itself (D7).
                Text(presentation.readout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .cypressMonoReadout(
                        // A dimmed placeholder, so "nothing entered" cannot be mistaken for
                        // somebody having typed a zero. See `MeasureCopy.readoutPlaceholder`.
                        color: presentation.hasEntry ? CypressColor.textInk : CypressColor.textFaint
                    )
                Text(presentation.unitSuffix)
                    .font(CypressFont.body20SemiBold)
                    .foregroundStyle(CypressColor.textMuted)
            }
            .accessibilityElement(children: .combine)

            Button { onSwitchUnit?() } label: {
                Text(presentation.unitSwitchLabel)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textFaint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cypressHitArea()
            .padding(.top, MeasureMetrics.unitSwitchTop)

            if let sanity = presentation.sanity { sanityPill(sanity) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MeasureMetrics.readoutTop)
        .padding(.bottom, MeasureMetrics.readoutBottom)
    }

    /// C4's sanity-check pill, with the previous reading's C12 badge beside it.
    ///
    /// The badge is not decoration. D7 is that every number carries how it was obtained, and the
    /// previous value is a number on this screen like any other — a `62 cm` that turns out to have
    /// been an estimate is a different sanity check from one that was taped.
    private func sanityPill(_ sanity: MeasurePresentation.Sanity) -> some View {
        HStack(spacing: CypressSpacing.gapVitality) {
            Chip(sanity.previousText + (sanity.verdict.map { " · " + $0 } ?? ""), style: .sanityCheck)
            MethodBadge(sanity.previousQuantity)
        }
        .padding(.top, MeasureMetrics.sanityTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - §4 Method · required (C5)

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: MeasureMetrics.labelBottom) {
            Text(MeasureCopy.methodLabel).cypressMicroLabel()
            // `SegmentedControl.method` is typed on `MeasurementMethod`, so this control cannot
            // emit "no method" and `Quantity` cannot be built without one (D7).
            SegmentedControl.method(
                selection: Binding(
                    get: { presentation.draft.method },
                    set: { onSelectMethod?($0) }
                )
            )
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - §5 Keypad

    private var keypad: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: MeasureMetrics.keypadGap),
                count: 3
            ),
            spacing: MeasureMetrics.keypadGap
        ) {
            ForEach(MeasureKey.pad) { key in
                KeypadKey(key: key) { onKey?(key) }
            }
        }
        .padding(.top, MeasureMetrics.keypadTop)
        .padding(.horizontal, MeasureMetrics.keypadGutter)
    }

    // MARK: - §6 CTA (C6)

    private var ctaBlock: some View {
        PrimaryButton(MeasureCopy.saveCTA, isEnabled: presentation.canSave && !isSaving) {
            onSave?()
        }
        .padding(.top, MeasureMetrics.ctaTop)
        .padding(.horizontal, MeasureMetrics.ctaGutter)
        .padding(.bottom, MeasureMetrics.ctaBottom)
    }

    // MARK: - §7 Footnote

    private var footnote: some View {
        Text(presentation.footnote)
            .cypressBody135(color: CypressColor.textFaintAlt)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MeasureMetrics.footnoteGutter)
            .padding(.bottom, CypressSpacing.bottomFootnote)
    }

    // MARK: - The states SCREENS.md does not draw

    /// D6's exclusion, said out loud before the save rather than discovered as an empty chart.
    /// See `MeasureCopy.chartNoticeTooImprecise` and ERRATA.
    private func chartNotice(_ text: String) -> some View {
        Text(text)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MeasureMetrics.ctaGutter)
            .padding(.top, MeasureMetrics.ctaBottom)
    }

    /// The "sure about that?" of §7, as a line rather than a dialog. Signal Amber is reserved for
    /// "this tree needs something" (§1.1), and an anomalous reading is the screen asking about one.
    private func anomalyLine(_ text: String) -> some View {
        Text(text)
            .cypressBody135(color: CypressColor.amberChipSelectedText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MeasureMetrics.ctaGutter)
    }

    /// **NOT SPECIFIED** by SCREENS.md 16. It sits above the CTA so the retry is the same control
    /// that failed, and it says only what is true: nothing was written.
    private var failureLine: some View {
        Text(MeasureCopy.saveFailed)
            .cypressBody135(color: CypressColor.amberChipSelectedText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MeasureMetrics.ctaGutter)
    }
}

// MARK: - §5's key

/// One keypad key: `padding:14px 0`, white fill, cool hairline, radius 12, Spline Sans Mono 19/600.
///
/// Already well past the 44pt minimum at that padding, so it needs no hit-area growth.
struct KeypadKey: View {

    let key: MeasureKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key.label)
                .font(CypressFont.monoKeypad)
                .foregroundStyle(CypressColor.textInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MeasureMetrics.keyPaddingV)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                        .fill(CypressColor.surfaceCard)
                }
                .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityLabel)
    }
}
