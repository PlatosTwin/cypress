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

import PhotosUI
import SwiftUI

struct CareLogView: View {

    @State private var model: CareLogModel
    @State private var libraryItem: PhotosPickerItem?

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
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.attachPhoto(data)
                }
                libraryItem = nil
            }
        }
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

    // MARK: - 5 · Optional well (C15), opened (task #147)

    /// Drawn-but-inert until the owner reported it (2026-07-31): ERRATA E25 recorded the well with
    /// no editor behind it, and `CareLogDraft` has carried `note` and `photos` since it was
    /// written — this view was always the only file that had to change. The well is now the
    /// entrance: one tap opens it into the two fields its own copy has promised all along, in
    /// place, on the sheet that is already up. No new screen (DECISIONS constraint 21) — the note
    /// field is screen 04's, in this sheet's light register, and the photo control is the system
    /// picker.
    @ViewBuilder
    private var optionalWell: some View {
        if model.isEditingExtras {
            extras
        } else {
            OptionalWell(CareLogCopy.optionalWell, size: .large) { model.isEditingExtras = true }
                .padding(.bottom, CareLogMetrics.blockBottom)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(CareLogCopy.optionalWellHint)
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: CareLogMetrics.extrasGap) {
            noteField
            photoRow
            if let message = model.photoError {
                Text(message)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.amberChipSelectedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, CareLogMetrics.blockBottom)
    }

    /// Screen 04's note field, in this sheet's light register: same prompt, same 1–3 line growth,
    /// so the app has one vocabulary for "a sentence you may leave".
    private var noteField: some View {
        TextField(
            "",
            text: $model.note,
            prompt: Text(CareLogCopy.notePrompt).foregroundColor(CypressColor.textFaint),
            axis: .vertical
        )
        .font(CypressFont.body145)
        .foregroundStyle(CypressColor.textInk)
        .lineLimit(1...3)
        .padding(.vertical, CareLogMetrics.notePaddingV)
        .padding(.horizontal, CareLogMetrics.notePaddingH)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(
            CypressColor.borderCool,
            radius: CypressRadius.control,
            width: CypressSpacing.Component.hairline
        )
    }

    /// The photo half. A picker, then the fact of an attachment with its way back — every field on
    /// this sheet is reversible, the photo included.
    @ViewBuilder
    private var photoRow: some View {
        if model.hasPhoto {
            HStack(spacing: CypressSpacing.gapRows) {
                Text(CareLogCopy.photoAttached)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textBody)
                Spacer(minLength: 0)
                Button(CareLogCopy.removePhoto) { model.removePhoto() }
                    .buttonStyle(.plain)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.amberChipSelectedText)
            }
        } else {
            PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                Text(CareLogCopy.addPhoto)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.ctaFill)
            }
            .buttonStyle(.plain)
        }
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

    // The opened well (task #147). **Not spec values** — 09 draws the well closed. The note
    // field's padding is screen 04's (`VisitMetrics.Camera.notePaddingV/H`), so the one field
    // reads the same in both registers; the gap is the sheet's own row gap scale.
    static let extrasGap: CGFloat = 10
    static let notePaddingV: CGFloat = 12
    static let notePaddingH: CGFloat = 14
}
