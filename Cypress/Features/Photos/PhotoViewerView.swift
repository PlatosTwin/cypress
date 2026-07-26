//
//  PhotoViewerView.swift
//  Cypress — Features/Photos
//
//  One photograph, whole, over everything else.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────
//  SCREENS.md has no viewer. Its nearest word on the subject is 03's affordance line — "hero → photo
//  timeline (**NOT SPECIFIED**)" — which is the entry that produced screen 20 (ERRATA E125) and
//  stops there. So the whole of this screen is designed here under ARCHITECTURE §8 rule 8, and this
//  header is the reasoning rather than a stray comment on a view.
//
//  ── The defect it closes (ERRATA E142) ───────────────────────────────────────────────────
//  Reported from the field: *"clicking on photo from tree page should show full view, current is
//  horizontal which cuts off photos taken in vertical orientation."*
//
//  Until this file, tapping a photograph in this app never showed the photograph. The hero on 03 is
//  a 224 pt band, screen 20's rows are the same band repeated, and both are `PhotoFill` — a
//  deliberate crop to a fixed frame, which is right for a hero and right for a list and is the only
//  thing a tap could reach. A phone photograph held upright is 3:4; that band keeps 43% of it. So
//  every route through the app ended at a crop, and there was no *last* tap that produced the
//  picture. **Trees are tall and portrait is the correct way to photograph one**, so the orientation
//  being cut was the orientation the app should expect.
//
//  A viewer is the answer rather than "make the hero taller" because the two are different jobs. A
//  hero is a page's ground and has to be a known height or the page below it moves; a viewer has one
//  job and the whole display to do it in. Nothing is cropped here, in either orientation:
//  `PhotoFit` letterboxes, and the bars are the honest report that the picture is not the shape of
//  the phone.
//
//  ── Why it is presented, not pushed ──────────────────────────────────────────────────────
//  It is not a place in the app, it is a closer look at what is already on screen — the same
//  distinction `AppRouter.sheet` already draws, and the same one that puts 09, 10 and 15 in the
//  cover rather than on the path. Practically: a pushed viewer would inherit the navigation stack's
//  bar and its own dark backdrop would have a light bar across the top of it.
//
//  ── Why there is no pinch-to-zoom ────────────────────────────────────────────────────────
//  Deliberate, and worth writing down because it is the obvious next thing to reach for. The report
//  is that the photograph is *cut off*; showing it whole answers that completely. A zoom that had to
//  be built would bring a gesture that fights the cover's own dismiss drag, a set of bounds nobody
//  has specified, and a second reason for the image to be at the wrong scale. If somebody asks to
//  look closer, that is a second report and it can have its own entry.
//

import SwiftUI

struct PhotoViewerView: View {

    let photoID: UUID
    /// The words already on screen for this photograph — see `Route.photoViewer`.
    let caption: String
    let onClose: () -> Void

    @Environment(PhotoImageStore.self) private var store: PhotoImageStore?

    var body: some View {
        ZStack {
            // The backdrop the app already uses when a photograph is the subject and everything
            // else recedes: screen 04's camera ground. A token, not a black rectangle — and the one
            // token in the palette that means exactly this.
            CypressColor.Dark.bgCamera
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if let image = store?.viewerImage(photoID) {
                PhotoFit(image: image, label: PhotoViewerPresentation.imageLabel(caption))
                    .ignoresSafeArea()
            } else {
                // The bytes are still arriving, or they are gone. Either way the screen says so in
                // words rather than drawing a gradient that could be mistaken for a photograph —
                // this is the one screen where a placeholder standing in for the subject would be a
                // lie about what is in the file (ARCHITECTURE §5.7: state a fact and stop).
                Text(PhotoViewerCopy.unavailable)
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.Dark.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CypressSpacing.gutter)
            }
        }
        .overlay(alignment: .bottomLeading) { captionLine }
        .overlay(alignment: .topTrailing) { closeButton }
        // The photograph is the largest thing `PhotoImageStore` ever holds and it is decoded for
        // this screen alone, so it is loaded when this screen appears and dropped when it goes.
        .task(id: photoID) { await store?.loadViewer(photoID) }
        .onDisappear { store?.releaseViewer() }
    }

    // MARK: - Chrome

    /// The same sentence the card under the photograph carried, kept so the reader who tapped a
    /// caption to see the picture can still read the caption while looking at it.
    private var captionLine: some View {
        Text(caption)
            .font(CypressFont.mono105)
            .foregroundStyle(CypressColor.textOnPhoto)
            .padding(.vertical, CypressSpacing.Component.heroPillPaddingV)
            .padding(.horizontal, CypressSpacing.Component.heroPillPaddingH)
            .background { Capsule().fill(CypressColor.heroMetaPillFill) }
            .padding(.leading, CypressSpacing.Component.heroEyebrowLeading)
            .padding(.bottom, CypressSpacing.Component.heroBottomInset)
            // The caption is read as part of the image's own label, above. Left in the tree twice it
            // is announced twice, which is the `DeepLinkVoiceOverTests` complaint about doubled
            // labels in a different costume.
            .accessibilityHidden(true)
    }

    /// A cover with no navigation bar has no way out that the system provides, so it needs one drawn.
    /// The geometry is `HeroPhotoHeader`'s back circle — the control this app already uses for "off
    /// this photograph" — mirrored to the trailing edge, where a dismiss belongs and where it cannot
    /// be confused for the back button on the screen underneath.
    private var closeButton: some View {
        Button(action: onClose) {
            Circle()
                .fill(CypressColor.heroBackFill)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: PhotoViewerMetrics.closeGlyph, weight: .semibold))
                        .foregroundStyle(CypressColor.textBody)
                }
                .frame(
                    width: CypressSpacing.Component.backCircle,
                    height: CypressSpacing.Component.backCircle
                )
                .cypressShadow(CypressShadow.heroButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PhotoViewerCopy.close)
        .padding(.trailing, CypressSpacing.Component.heroBackLeading)
        .padding(.top, CypressSpacing.Component.heroBackTop)
    }
}

// MARK: - Presentation

/// The one string this screen derives, kept out of the view so it can be tested without rendering.
enum PhotoViewerPresentation {

    /// The photograph named as its subject, then what a listener cannot otherwise know: that this is
    /// the whole frame and nothing has been cropped away. That is the entire difference between this
    /// screen and the card the reader tapped to reach it, and it is invisible to somebody who cannot
    /// see either.
    static func imageLabel(_ caption: String) -> String {
        "\(caption). " + PhotoViewerCopy.wholeFrame
    }
}

// MARK: - Metrics

/// **Not spec values.** The circle, its inset and its shadow are all `HeroPhotoHeader`'s back
/// button, taken from `CypressSpacing.Component` at the call site; only the glyph inside it needs a
/// size of its own, and it follows screen 20's `thumbGlyph` — the app's other bare SF Symbol in a
/// tap target — rather than inventing a third scale.
enum PhotoViewerMetrics {
    static let closeGlyph: CGFloat = 17
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — there is no viewer in SCREENS.md.
enum PhotoViewerCopy {
    static let close = "Close"
    static let wholeFrame = "The whole photograph"
    static let unavailable = "That photograph could not be opened"
}
