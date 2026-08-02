//
//  SpeciesView.swift
//  Cypress — Features/Species
//
//  Screen 07 · Species page. SCREENS.md lines 886–917.
//
//  Composed from C2 (hero, `.species` style — 190pt with 07's own scrim), C4 (meta chips),
//  C21 (the 10pt leaf glyphs on the recognize-it bullets), C14 (gradient callout), C11 (the large
//  count-card variant) and C22 (the 44pt nearby thumbnails).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). The numbers that remain are SCREENS.md 07's own margins, named in `SpeciesMetrics`.
//
//  Every block below is conditional, and each condition is a fact about the record rather than a
//  layout preference. See `SpeciesPresentation` for what each absence means.
//

import SwiftUI

struct SpeciesView: View {

    @State private var model: SpeciesModel
    @Environment(AppRouter.self) private var router: AppRouter?

    /// The caller's fix, when there is one. Nil is normal and is not an error state: the page's
    /// population half simply has no subject without it.
    private let coordinate: Coordinate?
    private let onRequestLocation: (() -> Void)?

    init(
        speciesID: UUID,
        api: any CypressAPI,
        coordinate: Coordinate? = nil,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        onRequestLocation: (() -> Void)? = nil
    ) {
        self.coordinate = coordinate
        self.onRequestLocation = onRequestLocation
        _model = State(
            wrappedValue: SpeciesModel(
                speciesID: speciesID,
                api: api,
                now: now,
                calendar: calendar
            )
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CypressColor.surfaceScreen)
            // C2 carries the back affordance and sits under the status bar, so the screen owns its
            // whole chrome (SCREENS.md 07 "Frame": `height:874px`, no `padding-top`).
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            // Keyed on *whether* there is a fix, not on the fix itself. The page opens before
            // CoreLocation has one, so it has to read again when the first one lands; keying on the
            // coordinate would instead re-read the whole guide every time the user walks 5 m, which
            // is what `MapLocationProvider`'s distance filter produces.
            .task(id: coordinate == nil) { await model.load(near: coordinate) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            // The hero is 190pt of gradient with nothing read yet; drawing it with an empty name
            // would flash a page that then changes its own title. A plain wait is quieter.
            ProgressView()
        case .failed:
            failure
        case let .loaded(presentation):
            page(presentation)
        }
    }

    // MARK: - The page

    private func page(_ presentation: SpeciesPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(presentation)
                taxonomyChips(presentation)

                if presentation.showsRecognizeCard {
                    recognizeCard(presentation)
                }
                if let note = presentation.seasonalNote {
                    seasonalCallout(note)
                }
                if presentation.showsCountCards {
                    countCards(presentation)
                }
                if presentation.showsNearby {
                    nearbyIndividuals(presentation)
                } else if coordinate == nil {
                    // The one empty state a tap can fill (R11 residual, E123): no fix means no
                    // `Near you`, and granting location is what fills it.
                    LocationPrompt(
                        title: SpeciesCopy.locationPromptTitle,
                        subtitle: SpeciesCopy.locationPromptSubtitle,
                        onRequest: { onRequestLocation?() }
                    )
                    .padding(.top, SpeciesMetrics.nearbyTop)
                    .padding(.horizontal, CypressSpacing.gutter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, SpeciesMetrics.nearbyBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - §1 · Hero

    /// C2's `.species` style: 190pt, 07's own radial stack, scrim from 42 % to .56.
    ///
    /// The name block replaces C2's plain eyebrow because 07 stacks three lines where 03 has one.
    /// It is passed as `bottomLeading` rather than built here, so the back button, the scrim and
    /// the gradient stay the component's.
    private func hero(_ presentation: SpeciesPresentation) -> some View {
        HeroPhotoHeader(
            style: .species,
            onBack: { router?.pop() }
        ) {
            VStack(alignment: .leading, spacing: SpeciesMetrics.heroTextSpacing) {
                Text(SpeciesCopy.heroEyebrow)
                    .font(CypressFont.body105Bold)
                    .tracking(CypressFont.ComponentTracking.speciesEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(CypressColor.textOnPhotoSpecies)
                    .opacity(SpeciesOpacity.heroEyebrow)

                Text(presentation.commonName)
                    .font(CypressFont.speciesHero)
                    .lineSpacing(CypressFont.LineSpacing.speciesHero)
                    .foregroundStyle(CypressColor.textOnPhotoSpecies)

                Text(presentation.scientificName)
                    .font(CypressFont.latinName14)
                    .foregroundStyle(CypressColor.textOnPhotoSpecies)
                    .opacity(SpeciesOpacity.heroLatin)
            }
            // 07 puts its text block 2pt further in and 2pt higher than C2's shared inset.
            .padding(.leading, SpeciesMetrics.heroTextLeading - CypressSpacing.Component.heroEyebrowLeading)
            .padding(.bottom, SpeciesMetrics.heroTextBottom - CypressSpacing.Component.heroBottomInset)
        }
    }

    // MARK: - §2 · Taxonomy chips

    /// The chips that have a fact behind them, and no others.
    ///
    /// A species whose habit nobody sourced draws one chip here instead of two, and that missing
    /// chip is the entire phenology surface of screen 07 (D5, ERRATA E9). There is no neutral chip
    /// and no grey one.
    @ViewBuilder
    private func taxonomyChips(_ presentation: SpeciesPresentation) -> some View {
        if !presentation.taxonomyChips.isEmpty {
            // One row while both chips fit whole; stacked once they cannot. A taxonomy chip's
            // label is one word — `Cupressaceae`, `Evergreen` — and a single word given half a
            // row at AX5 breaks mid-word (`Cupressac / eae`, ERRATA E196 §7). The measured row is
            // the chips unwrapped, so sharing only happens at widths where sharing is honest.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SpeciesMetrics.chipsGap) {
                    ForEach(presentation.taxonomyChips) { chip in
                        Chip(chip.label, style: .meta)
                    }
                }
                VStack(alignment: .leading, spacing: SpeciesMetrics.chipsGap) {
                    ForEach(presentation.taxonomyChips) { chip in
                        Chip(chip.label, style: .meta)
                    }
                }
            }
            .padding(.top, SpeciesMetrics.chipsTop)
            .padding(.horizontal, CypressSpacing.gutterLabel)
        }
    }

    // MARK: - §3 · How to recognize it

    private func recognizeCard(_ presentation: SpeciesPresentation) -> some View {
        VStack(alignment: .leading, spacing: SpeciesMetrics.cardSpacing) {
            Text(SpeciesCopy.recognizeLabel).cypressMicroLabel()

            ForEach(presentation.idTipRows) { row in
                HStack(alignment: .top, spacing: SpeciesMetrics.bulletGap) {
                    LeafGlyph(.bullet, tint: tint(row.tint))
                        .padding(.top, SpeciesMetrics.bulletGlyphTop)
                    Text(row.tip.text)
                        .cypressBody135()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SpeciesMetrics.cardPaddingV)
        .padding(.horizontal, SpeciesMetrics.cardPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardMd, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardMd)
        .cypressCardShadow()
        .padding(.top, SpeciesMetrics.cardTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    /// The three brand tints SCREENS.md 07 §3 names, resolved through the palette rather than
    /// written as hexes.
    private func tint(_ tint: SpeciesIDTipRow.Tint) -> Color {
        switch tint {
        case .canopy: return CypressColor.canopy
        case .newGrowth: return CypressColor.newGrowth
        case .bark: return CypressColor.bark
        }
    }

    // MARK: - §4 · What to look for this month

    private func seasonalCallout(_ note: SpeciesSeasonalNote) -> some View {
        Callout(
            " " + note.text,
            style: .gradient,
            leadIn: SpeciesCopy.seasonalLeadIn(month: note.month, calendar: model.monthCalendar)
        )
        .padding(.top, SpeciesMetrics.calloutTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - §5 · How many, and where

    /// C11's large variant in a 2-up `HStack(spacing:8)`.
    ///
    /// Each card draws only if its number exists. `Near you` has no subject without a fix, and an
    /// empty card labelled `Near you` reads as "none near you", which is a different claim.
    private func countCards(_ presentation: SpeciesPresentation) -> some View {
        HStack(spacing: CypressSpacing.Component.statGridGap) {
            if let city = presentation.cityTreeCountText {
                StatCard(label: SpeciesCopy.cityCountLabel, value: .text(city), size: .large)
            }
            if let near = presentation.nearYouCountText {
                StatCard(label: SpeciesCopy.nearYouLabel, value: .text(near), size: .large)
            }
        }
        .padding(.top, SpeciesMetrics.countsTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - §6 · Nearby individuals

    private func nearbyIndividuals(_ presentation: SpeciesPresentation) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(SpeciesCopy.nearbyLabel).cypressMicroLabel()
            ForEach(presentation.nearbyRows) { row in
                nearbyRow(row, species: presentation.species)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, SpeciesMetrics.nearbyTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    private func nearbyRow(_ row: NearbySpeciesTree, species: Species) -> some View {
        Button {
            router?.push(.treeProfile(row.treeID))
        } label: {
            HStack(spacing: SpeciesMetrics.rowGap) {
                ThumbnailGradient(SpeciesThumbnail.placeholder(for: species), size: .nearby)

                VStack(alignment: .leading, spacing: SpeciesMetrics.rowTextSpacing) {
                    if let title = row.title {
                        Text(title)
                            .font(CypressFont.body14)
                            .foregroundStyle(CypressColor.textInk)
                    }
                    if let subtitle = SpeciesCopy.nearbySubtitle(
                        photoCount: row.photoCount,
                        vitality: row.vitality
                    ) {
                        Text(subtitle)
                            .font(CypressFont.body12)
                            .foregroundStyle(CypressColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(SpeciesCopy.distance(row.distanceM))
                    .font(CypressFont.mono12)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineLimit(1)
            }
            .padding(.vertical, SpeciesMetrics.rowPaddingV)
            .padding(.horizontal, SpeciesMetrics.rowPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
            .cypressCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - The read failed

    /// **NOT SPECIFIED.** SCREENS.md 07 draws no error state. This says only what happened and
    /// offers the one action that can change it; it invents no copy about the species, because the
    /// whole point of the failure is that nothing about the species was read (DECISIONS constraint
    /// 21, recorded in ERRATA E43).
    private var failure: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(SpeciesCopy.loadFailed)
                .cypressBody135(color: CypressColor.textMuted)
                .multilineTextAlignment(.center)
            SecondaryOutlineButton(SpeciesCopy.loadRetry, style: .compact) {
                Task { await model.retry(near: coordinate) }
            }
            .fixedSize()
        }
        .padding(.horizontal, CypressSpacing.gutter)
    }
}

// MARK: - Opacities

/// The two opacities SCREENS.md 07 §1 states on the hero text block.
///
/// They are transparency on a token colour rather than colours of their own, which is how the spec
/// writes them (`opacity:.85`, `opacity:.9`) and why they are not in `CypressColor`.
enum SpeciesOpacity {
    static let heroEyebrow: Double = 0.85
    static let heroLatin: Double = 0.9
}

// MARK: - Thumbnails

/// Which of C22's four canonical placeholder gradients a nearby row draws.
///
/// These are the §2 C22 placeholders, not species artwork — there is no photograph on a seed row,
/// and drawing a Monterey Cypress silhouette next to a Ginkgo would be exactly the fabricated
/// content BUILD-PLAN §15 rules out. The pick is keyed on the species, so every row on one species
/// page shares a gradient, as the mock draws them.
enum SpeciesThumbnail {
    static func placeholder(for species: Species) -> CypressGradient.Thumbnail {
        let options: [CypressGradient.Thumbnail] = [.cypress, .ginkgo, .londonPlane, .victorianBox]
        // The UUID's own bytes, not `hashValue`: Swift's String hashing is seeded per process, so a
        // relaunch would repaint every thumbnail a different colour.
        return options[Int(species.id.uuid.15) % options.count]
    }
}
