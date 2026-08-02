//
//  ContributionExtras.swift
//  Cypress — Features/Visit
//
//  The optional photo-and-note block the care log (09, task #168) and the check-in (05, task
//  #169) both carry. One component so the two screens are one design: the same note field, the
//  same two photo sources, the same removable thumbnails, in both places.
//
//  ── The pattern (pending ruling, task #168) ──────────────────────────────────────────────
//  **The extras are the fields.** No reveal step: the note field and the photo affordances are
//  directly visible where the C15 well used to sit. Tapping "Photo or note" to be shown a text
//  box was the owner-reported awkwardness (#168); the well survives only as the block's caption,
//  which is where "optional" keeps being said.
//
//  Two photo sources, side by side, each doing what its label says (R39's rule): `Take a photo`
//  opens the in-app camera (`ContributionCameraView` — the same session screen 04 runs), `Add
//  from library` is the system picker, multi-select. Attachments accumulate; each thumbnail
//  carries its own removal. Every field here is optional and reversible.
//
//  It lives beside the camera it presents because `Features` may import anything but this block
//  must exist exactly once (ARCHITECTURE §2).
//

import PhotosUI
import SwiftUI
import UIKit

struct ContributionExtras: View {

    @Binding var note: String
    var notePrompt: String = ContributionExtrasCopy.notePrompt
    /// The staged attachments, in the order they were added. Owned by the screen's model — this
    /// block draws them and forwards taps; it stages nothing itself.
    let photos: [OutboxPhoto]
    var photoError: String?
    /// One captured or picked frame's bytes; the model stages them (`VisitPhotoStaging`).
    let attach: (Data) -> Void
    let removePhoto: (Int) -> Void

    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var showsCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: ContributionExtrasMetrics.gap) {
            noteField
            if !photos.isEmpty { thumbnails }
            photoSources
            if let photoError {
                Text(photoError)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.amberChipSelectedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            ContributionCameraView(onCapture: attach, onDone: { showsCamera = false })
        }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attach(data)
                    }
                }
                libraryItems = []
            }
        }
    }

    /// Screen 04's note field in the light register — same prompt, same 1–3 line growth, same
    /// padding, so the app has one vocabulary for "a sentence you may leave".
    private var noteField: some View {
        TextField(
            "",
            text: $note,
            prompt: Text(notePrompt).foregroundColor(CypressColor.textFaint),
            axis: .vertical
        )
        .font(CypressFont.body145)
        .foregroundStyle(CypressColor.textInk)
        // An empty-titled TextField has no accessibility label — VoiceOver announces "text
        // field" and nothing else. The prompt is not the label (DeepLinkVoiceOverTests).
        .accessibilityLabel(ContributionExtrasCopy.noteAccessibilityLabel)
        .lineLimit(1...3)
        .padding(.vertical, VisitMetrics.Camera.notePaddingV)
        .padding(.horizontal, VisitMetrics.Camera.notePaddingH)
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

    // MARK: - Photos

    /// The two sources, each named for exactly what it does (R39). Text affordances in the link
    /// register the sheet's old `Add a photo` already used — not buttons competing with the
    /// screen's one CTA.
    private var photoSources: some View {
        HStack(spacing: ContributionExtrasMetrics.sourceGap) {
            Button(ContributionExtrasCopy.takePhoto) { showsCamera = true }
                .buttonStyle(.plain)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.ctaFill)

            PhotosPicker(selection: $libraryItems, matching: .images, photoLibrary: .shared()) {
                Text(ContributionExtrasCopy.addFromLibrary)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.ctaFill)
            }
            .buttonStyle(.plain)
        }
    }

    /// What is attached, each with its own way back — a control you can see is a fact you can
    /// check, which "Photo attached" as a sentence never was.
    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ContributionExtrasMetrics.gap) {
                ForEach(Array(photos.enumerated()), id: \.element.path) { index, photo in
                    thumbnail(photo, index: index)
                }
            }
        }
    }

    private func thumbnail(_ photo: OutboxPhoto, index: Int) -> some View {
        Group {
            if let image = UIImage(contentsOfFile: photo.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // The staged file could not be read back — never blank, always a surface.
                RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                    .fill(CypressColor.surfaceSkeleton)
            }
        }
        .frame(width: ContributionExtrasMetrics.thumb, height: ContributionExtrasMetrics.thumb)
        .clipShape(RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous))
        .cypressBorder(
            CypressColor.borderCool,
            radius: CypressRadius.control,
            width: CypressSpacing.Component.hairline
        )
        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
        .overlay(alignment: .topTrailing) { removeButton(index: index) }
    }

    /// The ✕ on a thumbnail. The camera's own close furniture, at thumbnail scale, so removal
    /// reads the same everywhere a photograph can be let go of.
    private func removeButton(index: Int) -> some View {
        Button {
            removePhoto(index)
        } label: {
            ZStack {
                Circle().fill(VisitColor.cameraCloseFill)
                VisitCloseGlyph()
                    .stroke(
                        CypressColor.Dark.textSecondary,
                        style: StrokeStyle(
                            lineWidth: ContributionExtrasMetrics.removeStroke,
                            lineCap: .round
                        )
                    )
                    .frame(
                        width: ContributionExtrasMetrics.removeGlyph,
                        height: ContributionExtrasMetrics.removeGlyph
                    )
            }
            .frame(
                width: ContributionExtrasMetrics.removeButton,
                height: ContributionExtrasMetrics.removeButton
            )
        }
        .buttonStyle(.plain)
        .padding(ContributionExtrasMetrics.removeInset)
        .accessibilityLabel("Remove photo \(index + 1)")
    }
}

// MARK: - Copy

/// **NOT SPECIFIED** — the mocks draw the C15 well closed on both screens, so these strings are
/// designed here (pending ruling, task #168). Each names exactly what the control does and stops.
enum ContributionExtrasCopy {
    /// Screen 04's own prompt, verbatim — one vocabulary on every contribution surface.
    static let notePrompt = "Anything worth remembering?"
    /// What VoiceOver calls the note field. A prompt disappears the moment text arrives; the
    /// label is the field's name and stays.
    static let noteAccessibilityLabel = "Note"
    /// Opens the in-app camera. Not "Camera": the label is the promise, and the promise is a
    /// photograph (R39's rule for destination buttons).
    static let takePhoto = "Take a photo"
    /// The system picker, multi-select.
    static let addFromLibrary = "Add from library"
}

// MARK: - Metrics

/// The block's own geometry. **Not spec values** — no mock draws the opened state; the note
/// padding is screen 04's (`VisitMetrics.Camera.notePaddingV/H`, read directly above).
enum ContributionExtrasMetrics {
    /// Row gap inside the block — the care log's own extras gap (#147), kept.
    static let gap: CGFloat = 10
    /// Between the two source links: the sheet's grid gap scale.
    static let sourceGap: CGFloat = 14
    /// Thumbnail side. Big enough to recognize, small enough that a row of three fits any phone.
    static let thumb: CGFloat = 64
    /// The removal ✕ — same proportions as the camera's close furniture, at thumbnail scale.
    static let removeButton: CGFloat = 22
    static let removeGlyph: CGFloat = 8
    static let removeStroke: CGFloat = 2
    static let removeInset: CGFloat = 3
}
