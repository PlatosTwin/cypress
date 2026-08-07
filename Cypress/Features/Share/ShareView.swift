//
//  ShareView.swift
//  Cypress — Features/Share
//
//  Screen 10 · Share. SCREENS.md lines 985–1011.
//
//  The same shell as 09 — C17's scrim and sheet over a *skeleton* of the profile — with two 52pt
//  blocks instead of three, per §2.
//
//  ── What the three destinations do, and why ───────────────────────────────────────────────
//  E59's design — every named button routed to the system share sheet — was overridden by the
//  owner on device (ticket #146): identical behavior behind different names made the names lies.
//  Now every button does what its label says, and the row is exactly the set of labels that can
//  keep that promise:
//
//  `Messages` presents `MFMessageComposeViewController` with the link as the body — Messages
//  composition directly, in-app. Where the composer cannot exist (`canSendText() == false`:
//  simulators always, devices without a messaging account) it falls back to the system share
//  sheet instead of going dead; `MessagesRoute` is that decision, made testable.
//
//  `Copy link` writes the public URL to the pasteboard, unchanged.
//
//  `Share…` is the system share sheet (`ShareLink`), which is where AirDrop lives — an "AirDrop"
//  button cannot be built honestly, because `excludedActivityTypes` cannot exclude third-party
//  share extensions and the trimmed sheet is still a general one. `Instagram` is gone entirely:
//  no link API, and the Stories scheme needs a Meta app registration (zero external dependencies,
//  and no API keys, bind). RULINGS R39 records the row.
//
//  **No "Link copied" confirmation.** SCREENS.md 10 says it outright: the prototype's copied state
//  is "**NOT SPECIFIED** in this spec file — no copied state is drawn". PROTOTYPE-FLOW does carry
//  one, but it is a full-width CTA turning green, and this layout has no CTA — transplanting it onto
//  a 52pt circle would be designing, not transcribing. See ERRATA (E59).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 10's own margins, named in `ShareMetrics`.
//

import MessageUI
import SwiftUI
import UIKit

struct ShareView: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: ShareModel

    /// The link the `Messages` button is currently presenting, `nil` when it is not.
    /// `sheet(item:)` rather than a Bool so the URL travels with the presentation.
    @State private var messagesLink: MessagesLink?

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
        // `.container` and never bare `.ignoresSafeArea()`: the bare form includes `.keyboard`,
        // which is how a keyboard once covered the field being typed into (BottomSheet's header).
        .ignoresSafeArea(.container)
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

    /// **The link is a row of its own, under the whole block.**
    ///
    /// E60 recorded that the mock's four-hex slug cannot name one of 195,309 trees, so the card
    /// renders the tree's UUID: `cypress.app/sf/tree/` plus 36 characters is **56**, and the card's
    /// *full inner width* holds about 48 at mono 10.5. No two-column arrangement makes it one line,
    /// so widening the text column is not the fix — giving two lines a place to live is. Row 1 is
    /// the thumb beside name + location + strip, exactly as drawn; row 2 is the link at the card's
    /// full inner width, starting at its left edge, so it reads as one address block rather than as
    /// overflow squeezed beside a picture.
    ///
    /// No new token and no new spacing: `ShareMetrics.urlTop` (6) is the gap SCREENS.md 10 §3
    /// already gives this string, and `ShareMetrics.cardPadding` (14) is the inset it already sits
    /// inside. Task #14, item 2.
    private func previewCard(_ presentation: SharePresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        // D5 is enforced inside the component; handing it the species attribute is
                        // the whole contract.
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(presentation.publicURLText)
                .font(CypressFont.mono105)
                .foregroundStyle(CypressColor.textFaint)
                // Wraps rather than truncating. SCREENS.md draws this on one line, and it fits
                // on one only because the mock's identifier is a four-character fixture; a real
                // tree id needs two. Half a link with an ellipsis on the end is worse than a
                // link on two lines — it is the one string on this card somebody might read
                // aloud or type. See ERRATA (E60).
                //
                // **And above the accessibility threshold the clamp comes off entirely.** At AX5
                // two lines of mono 10.5 scaled up hold barely a third of the string, so
                // `lineLimit(2)` rendered `cypress.app/sf/tree/0…` — the reader got *none* of the
                // identifier, which is precisely the outcome E60 says is worse than extra lines,
                // happening at the type size where it matters most. The cap exists to keep the
                // card's drawn proportions, and at AX5 the card has already given those up.
                .lineLimit(
                    ShareMetrics.urlLineLimit(
                        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ShareMetrics.urlTop)
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

    /// Three columns at the drawn sizes; one destination per row at the accessibility sizes.
    ///
    /// At AX5 three side-by-side columns leave each caption about a third of the sheet, and a
    /// one-word caption with nowhere to wrap breaks anywhere — `Mes sa…` in the four-button row
    /// the sweep photographed (ERRATA E196 §5), `Message / s` in this three-button one. A row per
    /// destination gives the caption the sheet's whole width beside its circle, so it reads as
    /// one word again.
    @ViewBuilder
    private func destinationRow(_ presentation: SharePresentation) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: ShareMetrics.destinationSpacing) {
                ForEach(ShareDestination.allCases) { destination in
                    target(destination, url: presentation.publicURL)
                }
            }
            .padding(.leading, ShareMetrics.destinationRowPaddingH)
            .padding(.trailing, ShareMetrics.destinationRowPaddingH)
            .padding(.bottom, ShareMetrics.destinationRowPaddingBottom)
        } else {
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
    }

    @ViewBuilder
    private func target(_ destination: ShareDestination, url: URL) -> some View {
        switch destination {
        case .copyLink:
            Button {
                UIPasteboard.general.url = url
            } label: {
                targetLabel(destination)
            }
            .buttonStyle(.plain)
            .accessibilityHint(destination.accessibilityHint)

        case .messages:
            Button {
                messagesLink = MessagesLink(url: url)
            } label: {
                targetLabel(destination)
            }
            .buttonStyle(.plain)
            .accessibilityHint(destination.accessibilityHint)
            .sheet(item: $messagesLink) { link in
                // The route is asked at presentation time, not at build time: whether Messages can
                // compose is a fact about the device's current accounts, not about this view.
                switch MessagesRoute(canSendText: MFMessageComposeViewController.canSendText()) {
                case .composer:
                    MessageComposer(body: link.url.absoluteString) { messagesLink = nil }
                        .ignoresSafeArea()
                case .systemShareSheet:
                    SystemShareSheet(url: link.url) { messagesLink = nil }
                        .ignoresSafeArea()
                }
            }

        case .system:
            ShareLink(item: url) {
                targetLabel(destination)
            }
            .buttonStyle(.plain)
            .accessibilityHint(destination.accessibilityHint)
        }
    }

    @ViewBuilder
    private func targetLabel(_ destination: ShareDestination) -> some View {
        // The caption under its circle at the drawn sizes, beside it at the accessibility sizes —
        // the geometry `destinationRow` chose, finished at the cell: a full-width row reads
        // circle-then-word, and the word wraps at word boundaries only because it finally has the
        // width to (ERRATA E196 §5).
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: ShareMetrics.destinationSpacing) {
                well(destination)
                Text(destination.label)
                    .font(CypressFont.body105)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityLabel(destination.label)
        } else {
            VStack(spacing: 0) {
                well(destination)
                    .padding(.bottom, ShareMetrics.wellLabelGap)

                Text(destination.label)
                    .font(CypressFont.body105)
                    .foregroundStyle(CypressColor.textMuted)
                    // "Copy link" already fills the mock's 58 pt column at the drawn size.
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .frame(width: ShareMetrics.targetWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(destination.label)
        }
    }

    /// The 52 pt circle and its glyph, shared by both arrangements of the cell.
    private func well(_ destination: ShareDestination) -> some View {
        ZStack {
            Circle().fill(CypressColor.shareTargetWellFill)
            Circle().strokeBorder(
                CypressColor.shareTargetWellBorder,
                lineWidth: CypressSpacing.Component.hairline
            )
            ShareDestinationGlyph(destination: destination)
        }
        .frame(width: ShareMetrics.wellSize, height: ShareMetrics.wellSize)
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

// MARK: - Messages

/// The one value the `Messages` presentation carries. `Identifiable` for `sheet(item:)`.
private struct MessagesLink: Identifiable {
    let url: URL
    var id: URL { url }
}

/// `MFMessageComposeViewController`, presented as-is — Apple requires the controller unmodified,
/// so this wrapper adds nothing but the delegate that dismisses it.
private struct MessageComposer: UIViewControllerRepresentable {
    let body: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish()
        }
    }
}

/// The system share sheet as a presentable view — the `Messages` button's fallback where the
/// composer cannot exist (`MessagesRoute`). `ShareLink` cannot be triggered from another button's
/// action, so the fallback needs `UIActivityViewController` directly.
private struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
        // relaunch would repaint the card a different color.
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
    static let urlLineLimit = 2

    /// **How many lines the link may take, which is a decision and therefore a value.**
    ///
    /// Two at the drawn sizes, where the cap keeps the card's proportions and the whole string
    /// still fits inside it. `nil` — no cap — above the accessibility threshold, where two lines of
    /// mono 10.5 scaled up hold about a third of the string and `lineLimit(2)` rendered
    /// `cypress.app/sf/tree/0…`: the reader got **none** of the identifier, which is exactly the
    /// truncation E60 refuses, happening at the type size where reading or typing the link matters
    /// most. The cap protects proportions the card has already given up by AX5.
    ///
    /// A value rather than an inline ternary for the reason `QuadActionRow.rows` is one: a reflow
    /// decision a test can read is a reflow decision that cannot regress quietly. Task #14, item 2.
    static func urlLineLimit(isAccessibilitySize: Bool) -> Int? {
        isAccessibilitySize ? nil : urlLineLimit
    }
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
