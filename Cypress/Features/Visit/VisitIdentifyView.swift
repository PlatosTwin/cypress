//
//  VisitIdentifyView.swift
//  Cypress — Features/Visit
//
//  Screen 02 · What tree is this?
//  "GPS narrows the seeded catalog to a shortlist. When two candidates fall inside the error
//  circle, each card shows what to look for so you can confirm by eye."
//

import SwiftUI

struct VisitIdentifyView: View {

    @State private var model: VisitIdentifyModel

    /// Chosen a tree — open the camera for it.
    let onPick: (VisitCandidate) -> Void
    /// "None of these? Add this tree." Screen 20 (community add) is not this feature's; the button
    /// exists because SCREENS 02 draws it, and the destination is the container's to supply.
    let onAddTree: () -> Void
    let onBack: () -> Void

    init(
        api: any CypressAPI,
        location: VisitLocationProvider,
        onPick: @escaping (VisitCandidate) -> Void,
        onAddTree: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _model = State(wrappedValue: VisitIdentifyModel(api: api, location: location))
        self.onPick = onPick
        self.onAddTree = onAddTree
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "What tree is this?", bottomInset: .wide, onBack: onBack)

            statusChips

            content

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        .task { await model.run() }
    }

    // MARK: - Status chips

    @ViewBuilder
    private var statusChips: some View {
        if model.gpsChipLabel != nil || model.confirmChipLabel != nil {
            HStack(spacing: VisitMetrics.Identify.statusRowGap) {
                if let gps = model.gpsChipLabel {
                    Chip(gps, style: .meta, leadingDot: CypressColor.gpsDot)
                }
                if let confirm = model.confirmChipLabel {
                    VisitAmberStatusChip(confirm)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CypressSpacing.gutterLabel)
            .padding(.top, VisitMetrics.Identify.statusRowTop)
            .padding(.bottom, VisitMetrics.Identify.statusRowBottom)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.shortlist.state {
        case .noLocation:
            if model.isLoading {
                VisitIdentifyNotice(
                    title: "Finding you",
                    message: "The shortlist is ranked by how close each tree is, so it waits for a fix."
                )
            } else {
                // BUILD-PLAN §9: "location permission ask with purpose copy and denied state".
                VisitIdentifyNotice(
                    title: "Cypress cannot see where you are",
                    message: "Without a location there is no shortlist to rank. Turn location on in "
                        + "Settings, or add the tree you are standing at and give it a spot."
                )
            }

        case .empty:
            // BUILD-PLAN §9 empty state.
            VisitIdentifyNotice(
                title: "No trees on record here",
                message: "Nothing in the city inventory is within "
                    + "\(Int(VisitShortlist.searchRadiusM)) m of you. If there is a tree in front "
                    + "of you, it is not on the map yet."
            )

        case .ranked, .lowAccuracy:
            ScrollView {
                VStack(spacing: CypressSpacing.gapCandidates) {
                    if model.shortlist.state == .lowAccuracy {
                        // BUILD-PLAN §9: "low-GPS state of what-tree-is-this".
                        VisitLowAccuracyPanel(accuracyM: model.shortlist.accuracyM)
                    }

                    if let traits = model.distinguishingTraits {
                        VisitDistinguishBanner(
                            dimension: traits.first.dimension,
                            isCuratedTell: traits.first.isCuratedTell
                        )
                    } else if model.confirmationPair != nil {
                        VisitDistinguishBanner(
                            dimension: VisitDistinguisher.indistinguishableCopy,
                            isCuratedTell: false
                        )
                    }

                    ForEach(Array(model.shortlist.candidates.enumerated()), id: \.element.id) { index, candidate in
                        VisitCandidateCard(
                            candidate: candidate,
                            rank: index,
                            origin: model.origin,
                            isHighlighted: model.highlightedID == candidate.id,
                            // C28 belongs to the *auto*-highlighted top card only. When D6 has
                            // taken over, the honest reading of the bar is near zero — which is
                            // what the amber chip already says in words — so the bar stays off
                            // rather than drawing an empty track next to "confirm by eye".
                            confidence: index == 0 && model.shortlist.highlightsTopCandidate
                                ? model.shortlist.topConfidence : nil,
                            distinguishingValue: distinguishingValue(at: index),
                            action: { pick(candidate) }
                        )
                    }

                    if let error = model.loadError {
                        Text(error)
                            .cypressMonoSectionLabel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.bottom, CypressSpacing.gapCandidates)
            }
        }
    }

    /// D6 shows the trait on the two nearest only — those are the two the error circle cannot
    /// separate. Rows 3 and beyond are already distinguished by distance.
    private func distinguishingValue(at index: Int) -> String? {
        guard let traits = model.distinguishingTraits, !traits.first.isRedundantWithCard else { return nil }
        switch index {
        case 0: return traits.first.value
        case 1: return traits.second.value
        default: return nil
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: VisitMetrics.Identify.confirmBarTop) {
            if model.shortlist.requiresConfirmation, let selected = model.selectedCandidate {
                // D6's explicit confirmation tap. Naming the tree in the button is the point: the
                // user is committing an attribution to an append-only record, and the button says
                // which one.
                PrimaryButton("Yes—this is \(selected.displayName)") {
                    if let candidate = model.confirm() { onPick(candidate) }
                }
            }

            SecondaryOutlineButton("None of these? Add this tree", action: onAddTree)
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Identify.footerTop)
        .padding(.bottom, CypressSpacing.bottomCTA)
    }

    private func pick(_ candidate: VisitCandidate) {
        if let confirmed = model.tap(candidate) { onPick(confirmed) }
    }
}

// MARK: - Candidate card

/// The two drawn treatments of SCREENS 02 §3: the selected top card and the idle rows.
///
/// One view rather than two, because the difference is border width, thumb size, an eyebrow and a
/// confidence bar — and because which row is selected is a runtime fact, not a layout one.
struct VisitCandidateCard: View {

    let candidate: VisitCandidate
    let rank: Int
    let origin: Coordinate?
    let isHighlighted: Bool
    /// C28's fraction, top card only.
    let confidence: Double?
    /// D6's per-candidate trait, on the two nearest only.
    let distinguishingValue: String?
    let action: () -> Void

    private var isTop: Bool { rank == 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VisitMetrics.Identify.cardSpacing) {
                ThumbnailGradient(
                    VisitThumbnail.placeholder(for: candidate),
                    size: isTop ? .candidate : .candidateRow
                )

                VStack(alignment: .leading, spacing: 0) {
                    if isHighlighted && isTop {
                        Text("Closest · is it this one?")
                            .cypressMicroLabel10(color: CypressColor.canopy)
                    }

                    Text(candidate.displayName)
                        .font(isTop ? CypressFont.cardTitleSerif : CypressFont.listNameSerif)
                        .foregroundStyle(CypressColor.textInk)
                        .padding(.top, isHighlighted && isTop ? VisitMetrics.Identify.nameTop : 0)

                    if let latin = candidate.latinName {
                        Text(latin)
                            .cypressLatinName(isTop ? CypressFont.latinName135 : CypressFont.latinName13)
                            .padding(.top, VisitMetrics.Identify.cardTextSpacing)
                    }

                    if let confidence, isHighlighted && isTop {
                        ConfidenceBar(fraction: confidence)
                    }

                    // "each row carrying one id_tip as its tell" — rendered only when the record
                    // has one. `NearbyTree.tell` is nil until the curated pipeline lands, and the
                    // row renders without a tell rather than inventing one (BUILD-PLAN §15).
                    if let tell = candidate.tell {
                        Text("Its tell: \(tell.text)")
                            .cypressBody135(color: CypressColor.textMuted)
                            .padding(.top, isTop ? VisitMetrics.Identify.tellTopSelected
                                                 : VisitMetrics.Identify.tellTopIdle)
                    } else if let distinguishingValue {
                        Text(distinguishingValue)
                            .cypressBody135(color: CypressColor.textMuted)
                            .padding(.top, isTop ? VisitMetrics.Identify.tellTopSelected
                                                 : VisitMetrics.Identify.tellTopIdle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(candidate.distanceLabel(from: origin))
                    .font(CypressFont.mono12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize()
            }
            .padding(VisitMetrics.Identify.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? CypressColor.canopy : CypressColor.borderCool,
                        lineWidth: isHighlighted
                            ? VisitMetrics.Identify.selectedBorderWidth
                            : CypressSpacing.Component.hairline
                    )
            }
            .cypressShadow(light: isHighlighted ? CypressShadow.selected : CypressShadow.rest, dark: nil)
            .contentShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Supporting pieces

/// SCREENS 02's second status chip: `Two trees in range · confirm by eye`.
///
/// C4's amber styles (`hazardOn` / `hazardOff`) are the 06 hazard chip's geometry, not this one's;
/// this is the amber *pill* at the meta chip's size. Every value comes from a token.
struct VisitAmberStatusChip: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(CypressFont.body125)
            .foregroundStyle(CypressColor.amberPillText)
            .padding(.vertical, CypressSpacing.Component.chipPaddingVMeta)
            .padding(.horizontal, CypressSpacing.Component.chipPaddingHMeta)
            .background { Capsule().fill(CypressColor.amberPillFill) }
            .cypressPillBorder(CypressColor.amberPillBorder)
            .fixedSize()
    }
}

/// The banner over the two ambiguous candidates, naming the dimension they differ on.
struct VisitDistinguishBanner: View {
    let dimension: String
    let isCuratedTell: Bool

    private var leadIn: String {
        let text = isCuratedTell ? "Confirm by eye" : dimension
        return text.hasSuffix(".") ? text : "\(text)."
    }

    var body: some View {
        Callout(
            " Both are inside the GPS error circle, so the phone cannot tell them apart. You can.",
            style: .green,
            leadIn: leadIn
        )
    }
}

/// BUILD-PLAN §9's low-GPS state.
///
/// C24, not C14: Signal Amber is reserved for "this tree needs something" (§1.1), and a fix too
/// coarse to attribute a contribution is precisely a thing that needs attention before it is
/// written down.
struct VisitLowAccuracyPanel: View {
    let accuracyM: Double?

    private var leadIn: String {
        accuracyM.map { "GPS is off by up to \(Int($0.rounded())) m here." } ?? "GPS is coarse here."
    }

    var body: some View {
        AttentionCard {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                // `sectionLabel` is a static on the generic component; the witness type is
                // irrelevant, it just has to be named.
                AttentionCard<EmptyView>.sectionLabel("CONFIRM BY EYE")
                cypressLeadInText(
                    leadIn,
                    " That is wider than the gap between street trees, so nothing below is ranked "
                        + "with any confidence.",
                    leadInFont: CypressFont.body135Bold,
                    restFont: CypressFont.body135,
                    leadInColor: CypressColor.textInk,
                    restColor: CypressColor.textBody
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The full-screen notices: no fix, and nothing nearby.
struct VisitIdentifyNotice: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(title)
                .font(CypressFont.cardTitleSerif)
                .foregroundStyle(CypressColor.textInk)
                .multilineTextAlignment(.center)
            Text(message)
                .cypressBody135(color: CypressColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, CypressSpacing.gutterSheet)
    }
}

/// Which placeholder gradient a candidate's thumbnail draws.
///
/// These are the four canonical §2 C22 placeholders, not species artwork — there is no photograph
/// on a seed row, and drawing a Monterey Cypress silhouette next to an unidentified elm would be
/// exactly the fabricated content BUILD-PLAN §15 rules out. The pick is stable per tree so a row
/// does not change colour as the list re-ranks.
enum VisitThumbnail {
    static func placeholder(for candidate: VisitCandidate) -> CypressGradient.Thumbnail {
        let options: [CypressGradient.Thumbnail] = [.cypress, .ginkgo, .londonPlane, .victorianBox]
        let key = candidate.tree.speciesCurrentID ?? candidate.tree.id
        // The UUID's own bytes, not `hashValue`: Swift's String hashing is seeded per process, so a
        // relaunch would repaint every thumbnail a different colour.
        let index = Int(key.uuid.15) % options.count
        return options[index]
    }
}
