//
//  ShareView.swift
//  Cypress — Features/Share
//
//  Screen 10 · Share. SCREENS.md lines 985–1011.
//
//  The same shell as 09 — C17's scrim and sheet over a *skeleton* of the profile — with two 52pt
//  blocks instead of three, per §2.
//
//  ── What the four destinations do, and why ────────────────────────────────────────────────
//  `Copy link` writes the public URL to the pasteboard. That is exactly what its label says, and it
//  is the only one of the four iOS can perform as labelled.
//
//  `Messages`, `Instagram` and `AirDrop` open the system share sheet. On this platform those three
//  words *are* rows in that sheet: AirDrop and Messages have no direct API, and Instagram publishes
//  none for links. Hand-rolling three destinations would be inventing three flows SCREENS.md does
//  not draw (DECISIONS constraint 21); routing them to the sheet they live in is the platform
//  meaning of the button that was drawn. Recorded in ERRATA (E59).
//
//  **No "Link copied" confirmation.** SCREENS.md 10 says it outright: the prototype's copied state
//  is "**NOT SPECIFIED** in this spec file — no copied state is drawn". PROTOTYPE-FLOW does carry
//  one, but it is a full-width CTA turning green, and this layout has no CTA — transplanting it onto
//  a 52pt circle would be designing, not transcribing. See ERRATA (E59).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 10's own margins, named in `ShareMetrics`.
//

import SwiftUI
import UIKit

struct ShareView: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: ShareModel

    /// Dismissal is the composition root's, not the sheet's (PROTOTYPE-FLOW §1.3 `closeShare`).
    private let onClose: () -> Void

    init(
        treeID: UUID,
        api: any CypressAPI,
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(wrappedValue: ShareModel(treeID: treeID, api: api))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            // Two blocks, per C17.
            ProfileSkeleton(blockCount: ShareMetrics.skeletonBlocks)

            BottomSheet(style: .standard, onScrimTap: onClose) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // Same as 09: the skeleton and the scrim are the whole display. See `CareLogView`.
        .ignoresSafeArea()
        .task { if model.presentation == nil { await model.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, ShareMetrics.cardBottom)
        case .failed:
            failure
        case let .loaded(presentation):
            previewCard(presentation)
            destinationRow(presentation)
        }
    }

    // MARK: - 2 · Title

    private var title: some View {
        Text(ShareCopy.title)
            .font(CypressFont.sheetTitle)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ShareMetrics.titleBottom)
    }

    // MARK: - 3 · Preview card

    private func previewCard(_ presentation: SharePresentation) -> some View {
        HStack(alignment: .top, spacing: ShareMetrics.cardSpacing) {
            // C22. A photograph would go in this frame the day one is approved; until then the
            // gradient is what SCREENS.md 10 §3 draws anyway. See `SharePresentation`'s header.
            ThumbnailGradient(
                ShareThumbnail.placeholder(for: presentation.thumbnailSpeciesName),
                size: .share
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(presentation.treeDisplayName)
                    .font(CypressFont.shareName)
                    .foregroundStyle(CypressColor.textInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.locationLine)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                FoliageStrip(
                    // D5 is enforced inside the component; handing it the species attribute is the
                    // whole contract.
                    leafRetention: presentation.leafRetention,
                    densities: presentation.foliageDensities,
                    variant: .shareCard,
                    showsMonthRow: false,
                    showsEyebrow: false
                )
                .padding(.top, ShareMetrics.stripTop)
                // The component labels each cell as a canopy state; this strip encodes *public*
                // photo coverage (A5), so the honest label replaces them.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ShareMetrics.stripAccessibilityLabel)

                Text(presentation.publicURLText)
                    .font(CypressFont.mono105)
                    .foregroundStyle(CypressColor.textFaint)
                    // Wraps rather than truncating. SCREENS.md draws this on one line, and it fits
                    // on one only because the mock's identifier is a four-character fixture; a real
                    // tree id needs two. Half a link with an ellipsis on the end is worse than a
                    // link on two lines — it is the one string on this card somebody might read
                    // aloud or type. See ERRATA (E60).
                    .lineLimit(ShareMetrics.urlLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ShareMetrics.urlTop)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ShareMetrics.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                .fill(CypressColor.surfaceShareCard)
        }
        .cypressBorder(CypressColor.borderShareCard, radius: CypressRadius.cardLg)
        .cypressShadow(CypressShadow.shareCard)
        .padding(.bottom, ShareMetrics.cardBottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - 4 · Destination row

    private func destinationRow(_ presentation: SharePresentation) -> some View {
        HStack(spacing: ShareMetrics.destinationSpacing) {
            ForEach(ShareDestination.allCases) { destination in
                target(destination, url: presentation.publicURL)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, ShareMetrics.destinationRowPaddingH)
        .padding(.trailing, ShareMetrics.destinationRowPaddingH)
        .padding(.bottom, ShareMetrics.destinationRowPaddingBottom)
    }

    @ViewBuilder
    private func target(_ destination: ShareDestination, url: URL) -> some View {
        if destination.isPasteboard {
            Button {
                UIPasteboard.general.url = url
            } label: {
                targetLabel(destination)
            }
            .buttonStyle(.plain)
            .accessibilityHint(destination.accessibilityHint)
        } else {
            ShareLink(item: url) {
                targetLabel(destination)
            }
            .buttonStyle(.plain)
            .accessibilityHint(destination.accessibilityHint)
        }
    }

    private func targetLabel(_ destination: ShareDestination) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(CypressColor.shareTargetWellFill)
                Circle().strokeBorder(
                    CypressColor.shareTargetWellBorder,
                    lineWidth: CypressSpacing.Component.hairline
                )
                ShareDestinationGlyph(destination: destination)
            }
            .frame(width: ShareMetrics.wellSize, height: ShareMetrics.wellSize)
            .padding(.bottom, ShareMetrics.wellLabelGap)

            Text(destination.label)
                .font(CypressFont.body105)
                .foregroundStyle(CypressColor.textMuted)
                // "Copy link" already fills the mock's 58 pt column at the drawn size. Past the
                // point where one line will not hold it, the row stops being three fixed columns
                // and each label takes the width it needs: the destination *is* the content here,
                // and a truncated one is a destination you cannot read.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : ShareMetrics.targetWidth)
        .contentShape(Rectangle())
        .accessibilityLabel(destination.label)
    }

    // MARK: - Failure

    /// **NOT SPECIFIED** by SCREENS.md 10, which draws no error state. It never renders a link or a
    /// name it could not read.
    private var failure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(ShareMetrics.failureText)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)
            SecondaryOutlineButton(ShareMetrics.retryText, style: .compact) {
                Task { await model.retry() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ShareMetrics.cardBottom)
    }
}

// MARK: - Thumbnails

/// Which of C22's four canonical placeholder gradients the share card draws.
///
/// Genus decides where it can and a stable hash of the name decides the rest — the same tree always
/// gets the same gradient, and none of it claims to be a picture of that tree (BUILD-PLAN §15). The
/// same answer `MapModel.thumbnail` gives, because it is the same question.
enum ShareThumbnail {
    static func placeholder(for scientificName: String?) -> CypressGradient.Thumbnail {
        guard let scientificName, !scientificName.isEmpty else { return .cypress }
        let latin = scientificName.lowercased()
        if latin.hasPrefix("ginkgo") { return .ginkgo }
        if latin.hasPrefix("platanus") { return .londonPlane }
        if latin.hasPrefix("pittosporum") { return .victorianBox }
        if latin.hasPrefix("cupressus") || latin.hasPrefix("hesperocyparis") { return .cypress }
        let choices: [CypressGradient.Thumbnail] = [.cypress, .ginkgo, .londonPlane, .victorianBox]
        // The name's own bytes, not `hashValue`: Swift's String hashing is seeded per process, so a
        // relaunch would repaint the card a different colour.
        let bucket = abs(latin.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 9_973 })
        return choices[bucket % choices.count]
    }
}

// MARK: - Screen metrics

/// The margins SCREENS.md 10 gives this sheet that `CypressSpacing` does not already name.
enum ShareMetrics {
    /// 10 §2: `margin-bottom:12px` under the title.
    static let titleBottom: CGFloat = 12
    /// 10 §3: `padding:14px`, `HStack(spacing:14)`, `margin-bottom:16px`.
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 14
    static let cardBottom: CGFloat = 16
    /// 10 §3: the strip's `margin-top:7px` and the URL's `margin-top:6px`.
    static let stripTop: CGFloat = 7
    static let urlTop: CGFloat = 6
    /// A 36-character tree id in mono 10.5 does not fit the drawn card on one line, so it takes two.
    /// Two is the ceiling: at AX sizes the line count is capped and the card keeps its proportions
    /// rather than growing without limit.
    static let urlLineLimit = 2
    /// 10 §4: `HStack(spacing:18)`, `padding:0 2px 4px`; each target 58 wide; well 52 with
    /// `margin:0 auto 5px`.
    static let destinationSpacing: CGFloat = 18
    static let destinationRowPaddingH: CGFloat = 2
    static let destinationRowPaddingBottom: CGFloat = 4
    static let targetWidth: CGFloat = 58
    static let wellSize: CGFloat = 52
    static let wellLabelGap: CGFloat = 5
    /// C17: two 52pt blocks behind 10 (three behind 09).
    static let skeletonBlocks = 2

    /// The strip on this card is public photo coverage, not canopy. Nothing is public yet, and the
    /// label says so rather than describing twelve identical cells.
    static let stripAccessibilityLabel = "Season strip. No month has a public photo yet."

    /// **NOT SPECIFIED.** The failed-read state.
    static let failureText = "This tree’s record could not be read, so there is nothing to share yet."
    static let retryText = "Try again"
}
