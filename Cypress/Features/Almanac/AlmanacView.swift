//
//  AlmanacView.swift
//  Cypress — Features/Almanac
//
//  Screen 12 · Neighborhood almanac. SCREENS.md lines 1053–1091.
//
//  Composed from C1 (ScreenHeader + HeaderPill), C10 (IconTextRow) ×3, C24 (AttentionCard) and
//  C6 compact. The composition card in §3 has no C-number — SCREENS.md §2's catalogue does not
//  carry it and §3 describes it inline — so it is built here from tokens, the same way screen 08's
//  three-pill row was (ERRATA E46).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 12's own margins, named in `AlmanacMetrics`.
//
//  Everything about *whether* a block appears is decided in `AlmanacPresentation`. This file draws
//  what it is given and nothing else, which is what makes §5.6 testable without a renderer.
//

import SwiftUI

struct AlmanacView: View {

    @State private var model: AlmanacModel

    /// Where §4's CTA goes. Handed in rather than pushed here, so this folder does not construct
    /// another feature's view (ARCHITECTURE §3); the composition root resolves it to screen 14 —
    /// which is `Route.treeProfile` in its cold-start form, and which screen 14's own footnote calls
    /// "the almanac's 'walk the nine' list, one tree at a time".
    private let onWalk: ((UUID) -> Void)?

    /// Tapping the `Where a tree could go` row opens the nearest vacant site — a `Route.site`
    /// (RULINGS R10). Handed in for the same reason `onWalk` is: this folder does not build another
    /// feature's view, and the composition root owns the routing.
    private let onOpenSite: ((UUID) -> Void)?

    /// Tapping a season row opens the tree it is about. The elder and the first bloom are each a
    /// specific tree; SCREENS.md 12 states no affordance for either, so this is nil unless the
    /// composition root supplies one and the rows are inert without it (DECISIONS constraint 21).
    private let onOpenTree: ((UUID) -> Void)?

    private let onBack: (() -> Void)?

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        now: @escaping @Sendable () -> Date = { Date() },
        onBack: (() -> Void)? = nil,
        onOpenTree: ((UUID) -> Void)? = nil,
        onWalk: ((UUID) -> Void)? = nil,
        onOpenSite: ((UUID) -> Void)? = nil
    ) {
        _model = State(wrappedValue: AlmanacModel(api: api, coordinate: coordinate, now: now))
        self.onBack = onBack
        self.onOpenTree = onOpenTree
        self.onWalk = onWalk
        self.onOpenSite = onOpenSite
    }

    var body: some View {
        AlmanacScreen(
            presentation: model.presentation,
            onBack: onBack,
            onOpenTree: onOpenTree,
            onWalk: onWalk,
            onOpenSite: onOpenSite
        )
        .task { await model.load() }
    }
}

// MARK: - The screen itself

/// Screen 12's layout, given a finished derivation.
///
/// Split from `AlmanacView` so the screen can be drawn from an `AlmanacPresentation` alone — no API,
/// no model, no view lifecycle. Screen 12's whole subject is which blocks are and are not there, and
/// a layout whose content only exists after an `async` read cannot be rendered offscreen at all: the
/// view's `.task` never runs in a detached window, so every state photographs as the loading one.
/// With the split, any state can be handed straight in and looked at.
struct AlmanacScreen: View {

    let presentation: AlmanacPresentation?
    var onBack: (() -> Void)?
    var onOpenTree: ((UUID) -> Void)?
    var onWalk: ((UUID) -> Void)?
    var onOpenSite: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let presentation {
                        seasonBlock(presentation)
                        compositionBlock(presentation)
                        vacantSitesBlock(presentation)
                        coverageBlock(presentation)
                    }

                    // §5's `margin-top:auto`. The footnote sits at the bottom of the column whether
                    // the column is full or empty, which is the whole layout of an almanac with
                    // nothing in it.
                    Spacer(minLength: 0)
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

    /// `title: Almanac`, trailing pill `Outer Sunset`.
    ///
    /// The pill is the neighbourhood's own name from the seed, so it reads `Sunset/Parkside` rather
    /// than the mock's colloquial `Outer Sunset` — SF's official polygon set carries no such
    /// neighbourhood (A4, ERRATA E47). No pill at all when there is no fix: a header that named an
    /// area we could not determine would be the screen's first lie.
    @ViewBuilder
    private var header: some View {
        if let name = presentation?.neighborhoodName {
            ScreenHeader(title: AlmanacCopy.screenTitle, trailingPill: name, onBack: onBack)
        } else {
            ScreenHeader(title: AlmanacCopy.screenTitle, onBack: onBack)
        }
    }

    // MARK: - §2 This season (C10 ×3)

    /// Micro-label plus up to three C10 rows, `VStack(spacing:7)`.
    ///
    /// The label goes with the rows: a heading over nothing is a heading that promises something.
    @ViewBuilder
    private func seasonBlock(_ presentation: AlmanacPresentation) -> some View {
        if !presentation.seasonRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(AlmanacCopy.seasonLabel)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(spacing: AlmanacMetrics.seasonRowGap) {
                    ForEach(presentation.seasonRows) { row in
                        IconTextRow(
                            accent: row.accent,
                            title: row.title,
                            subtitle: row.subtitle,
                            action: row.treeID.flatMap { id in onOpenTree.map { open in { open(id) } } }
                        )
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - Where a tree could go (R10) — one C10 row, a statement between §3 and §4

    /// A single C10 row: the count of empty basins, tapping to the nearest.
    ///
    /// Placed after §3 and before §4 on purpose. §3 says what lives in the neighbourhood; this says
    /// where nothing does — two readings of the same canopy — while §4 stays the screen's one
    /// directed ask, the last thing the reader is left with before the footnote. A plain row before
    /// §4's amber card also reads as the statement it is rather than as a second ask.
    @ViewBuilder
    private func vacantSitesBlock(_ presentation: AlmanacPresentation) -> some View {
        if let block = presentation.vacantSites {
            VStack(alignment: .leading, spacing: 0) {
                Text(block.label)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                IconTextRow(
                    accent: .vacantSite,
                    title: block.title,
                    subtitle: block.subtitle,
                    action: block.nearestID.flatMap { id in onOpenSite.map { open in { open(id) } } }
                )
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §3 Who lives here

    @ViewBuilder
    private func compositionBlock(_ presentation: AlmanacPresentation) -> some View {
        if let composition = presentation.composition {
            VStack(alignment: .leading, spacing: 0) {
                Text(composition.label)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(spacing: AlmanacMetrics.compositionRowGap) {
                    ForEach(composition.rows) { row in
                        CompositionShareRow(row: row)
                    }
                }
                .padding(.vertical, AlmanacMetrics.compositionPaddingV)
                .padding(.horizontal, AlmanacMetrics.compositionPaddingH)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardMd, style: .continuous)
                        .fill(CypressColor.surfaceCard)
                }
                .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardMd)
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §4 Where eyes are needed (C24)

    @ViewBuilder
    private func coverageBlock(_ presentation: AlmanacPresentation) -> some View {
        if let coverage = presentation.coverage {
            VStack(alignment: .leading, spacing: 0) {
                // Amber, not faint. Signal Amber is reserved for "this tree needs something"
                // (§1.1), and this is the one section on the screen that is asking for anything.
                AttentionCard<EmptyView>.sectionLabel(AlmanacCopy.coverageLabel)
                    .padding(.bottom, CypressSpacing.gapVitality)

                AttentionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(coverage.title)
                            .font(CypressFont.body145Bold)
                            .foregroundStyle(CypressColor.textInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(coverage.body)
                            .font(CypressFont.body125)
                            .foregroundStyle(CypressColor.textMuted)
                            .lineSpacing(CypressFont.LineSpacing.body125)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, AlmanacMetrics.coverageBodyTop)
                            .padding(.bottom, AlmanacMetrics.coverageBodyBottom)

                        PrimaryButton(coverage.ctaTitle, style: .compact) {
                            onWalk?(coverage.firstTreeID)
                        }
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §5 Footnote

    private var footnote: some View {
        Text(AlmanacCopy.footnote)
            .font(CypressFont.body12)
            .foregroundStyle(CypressColor.textFaintAlt)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, AlmanacMetrics.footnoteTop)
            .padding(.bottom, AlmanacMetrics.footnoteBottom)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }
}

// MARK: - §3's share row

/// One row of the composition card: swatch, name, track, value.
///
/// SCREENS.md 12 §3: `11×11 swatch (radius 3.5px) · name 13.5px/700 · a flex:1 9px track (radius
/// 5px) filled via linear-gradient(90deg, <color> 0 N%, #EDEFE3 N%) · mono 12px value`.
///
/// The gradient is drawn as two rectangles rather than as a `LinearGradient` with coincident stops:
/// the CSS is a hard-edged two-colour stop, which is a bar, and a bar drawn as a gradient rounds its
/// own edge at fractional widths.
struct CompositionShareRow: View {

    let row: AlmanacPresentation.CompositionRow

    var body: some View {
        HStack(spacing: AlmanacMetrics.compositionRowSpacing) {
            RoundedRectangle(cornerRadius: CypressRadius.compositionSwatch, style: .continuous)
                .fill(swatch)
                .frame(
                    width: AlmanacMetrics.compositionSwatch,
                    height: AlmanacMetrics.compositionSwatch
                )
                .accessibilityHidden(true)

            Text(row.name)
                // §3 draws `Everyone else` in `#66735F` — the remainder is a category rather than a
                // species, and it says so by not being ink.
                .foregroundStyle(row.isRemainder ? CypressColor.textMuted : CypressColor.textInk)
                .font(CypressFont.body135Bold)
                .lineLimit(1)

            track
                .frame(height: AlmanacMetrics.compositionTrackHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text(row.value)
                .font(CypressFont.mono12)
                .foregroundStyle(CypressColor.textMuted)
                .monospacedDigit()
        }
        // Swatch, name, bar and number are one sentence; four elements read as four.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.value)")
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CypressColor.compositionTrack)
                Capsule()
                    .fill(swatch)
                    .frame(width: max(proxy.size.width * row.share, 0))
            }
        }
    }

    /// Never a colour of its own: the presentation chose an index into the design system's own
    /// four-swatch series (ARCHITECTURE §6).
    private var swatch: Color {
        let swatches = CypressColor.compositionSwatches
        return swatches[min(max(row.swatchIndex, 0), swatches.count - 1)]
    }
}
