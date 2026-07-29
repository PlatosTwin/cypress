//
//  CareLogView.swift
//  Cypress — Features/CareLog
//
//  Screen 09 · Care log. SCREENS.md lines 961–981.
//
//  A bottom sheet over a dimmed profile, not a pushed screen — and specifically over a *skeleton* of
//  the profile, which is what §2's C17 says is drawn behind 09 and 10 ("Background behind the sheet
//  on 09/10 is a **skeleton** of the profile, not the live profile"). Three 52pt blocks on 09.
//
//  Composed from C17 (sheet + skeleton), C4's care-toggle variant, C15 (the optional well) and C6.
//  Nothing new is drawn here.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). The numbers that remain are SCREENS.md 09's own margins, named in `CareLogMetrics`.
//

import SwiftUI

struct CareLogView: View {

    @State private var model: CareLogModel

    /// Dismissal is the composition root's, not the sheet's: 09 is presented over whatever pushed
    /// it, and the scrim tap and the CTA both end at the same place (PROTOTYPE-FLOW §1.3,
    /// `closeCare` / `logCare`).
    private let onClose: () -> Void

    init(
        treeID: UUID,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        // A closure, not a number: `@State` runs its initialiser once, so a value handed in here is
        // frozen at the sheet's first frame (ERRATA E158).
        gpsAccuracyM: @escaping @MainActor () -> Double? = { nil },
        treeDisplayName: String? = nil,
        initialDraft: CareLogDraft = CareLogDraft(),
        now: @escaping () -> Date = { Date() },
        onClose: @escaping () -> Void = {},
        onSaved: @escaping (CareLogSaveReceipt) -> Void = { _ in }
    ) {
        _model = State(
            wrappedValue: CareLogModel(
                treeID: treeID,
                api: api,
                outbox: outbox,
                attribution: attribution,
                gpsAccuracyM: gpsAccuracyM,
                treeDisplayName: treeDisplayName,
                initialDraft: initialDraft,
                now: now,
                onSaved: onSaved
            )
        )
        self.onClose = onClose
    }

    var body: some View {
        let presentation = model.presentation

        ZStack {
            // Three blocks, per C17. The skeleton is `accessibilityHidden` inside the component:
            // it is a drawing of a screen, and VoiceOver has no business reading it out.
            ProfileSkeleton(blockCount: CareLogMetrics.skeletonBlocks)

            BottomSheet(style: .standard, onScrimTap: onClose) {
                VStack(alignment: .leading, spacing: 0) {
                    title(presentation)
                    subtitle
                    chips(presentation)
                    optionalWell
                    if model.saveFailed { failureLine }
                    doneCTA(presentation)
                    footnote
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // The skeleton and the scrim are the whole display, status bar included — SCREENS.md 09's
        // frame is the device, and a strip of unscrimmed screen at the top would read as the live
        // profile showing through. `ProfileSkeleton` carries its own 62pt status-bar inset.
        .ignoresSafeArea()
        .task { await model.loadName() }
    }

    // MARK: - 2 · Title

    private func title(_ presentation: CareLogPresentation) -> some View {
        Text(presentation.title)
            .font(CypressFont.sheetTitle)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, CareLogMetrics.titleBottom)
    }

    // MARK: - 3 · Sub

    private var subtitle: some View {
        Text(CareLogCopy.subtitle)
            .font(CypressFont.body125)
            .foregroundStyle(CypressColor.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, CareLogMetrics.blockBottom)
    }

    // MARK: - 4 · Care toggles (C4)

    private func chips(_ presentation: CareLogPresentation) -> some View {
        CypressChipFlow(spacing: CypressSpacing.gapGrid) {
            ForEach(presentation.chips) { chip in
                Chip.care(chip.action, isOn: chip.isOn) { model.toggle(chip.action) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CareLogMetrics.blockBottom)
    }

    // MARK: - 5 · Optional well (C15)

    /// Drawn and inert. No picker and no note editor is specified behind it on 05 or 09, and
    /// inventing two would be inventing two screens (ERRATA E25, DECISIONS constraint 21).
    /// `CareLogDraft` carries `note` and `photos` regardless, so when the editor is designed this
    /// view is the only file that changes.
    private var optionalWell: some View {
        OptionalWell(CareLogCopy.optionalWell, size: .large)
            .padding(.bottom, CareLogMetrics.blockBottom)
    }

    // MARK: - 6 · CTA (C6)

    private func doneCTA(_ presentation: CareLogPresentation) -> some View {
        PrimaryButton(CareLogCopy.doneCTA, isEnabled: presentation.canSave) {
            Task { await model.save() }
        }
    }

    // MARK: - 7 · Footnote

    private var footnote: some View {
        Text(CareLogCopy.footnote)
            .font(CypressFont.body12)
            .foregroundStyle(CypressColor.textFaintAlt)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, CareLogMetrics.footnoteTop)
    }

    // MARK: - Failure

    /// **NOT SPECIFIED** by SCREENS.md 09. It sits above the CTA so the retry is the same control
    /// that failed, and it says only what is true: nothing was written.
    private var failureLine: some View {
        Text(CareLogCopy.saveFailed)
            .font(CypressFont.body125)
            .foregroundStyle(CypressColor.amberChipSelectedText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, CareLogMetrics.blockBottom)
    }
}

// MARK: - Screen metrics

/// The margins SCREENS.md 09 gives this sheet that `CypressSpacing` does not already name.
enum CareLogMetrics {
    /// 09 §2: `margin-bottom:4px` under the title.
    static let titleBottom: CGFloat = 4
    /// 09 §3–5: `margin-bottom:14px` under the sub, the chip row and the well.
    static let blockBottom: CGFloat = 14
    /// 09 §7: `margin-top:10px` above the footnote.
    static let footnoteTop: CGFloat = 10
    /// C17: three 52pt blocks behind 09 (two behind 10).
    static let skeletonBlocks = 3
}
