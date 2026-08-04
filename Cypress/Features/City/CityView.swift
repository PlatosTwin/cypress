//
//  CityView.swift
//  Cypress — Features/City
//
//  The Journal tab's `City` segment.
//
//  Composed from the same tokens and the same C-numbers `AlmanacView` draws screen 12 from — C1's
//  header, C10 rows for card 3, and card 1 & 2 built from tokens the way the almanac's own
//  composition card is (SCREENS.md carries no mock for this segment at all; ARCHITECTURE §5 rule 8
//  sends an unspecified screen to the nearest specified thing, and here that is screen 12).
//
//  Not a raw hex, font size or radius in this file (ARCHITECTURE §6).
//

import SwiftUI

struct CityView: View {

    @State private var model: CityModel

    private let onOpenTree: ((UUID) -> Void)?
    private let coordinate: Coordinate?
    private let onRequestLocation: (() -> Void)?

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        onOpenTree: ((UUID) -> Void)? = nil,
        onRequestLocation: (() -> Void)? = nil
    ) {
        _model = State(wrappedValue: CityModel(api: api, coordinate: coordinate))
        self.coordinate = coordinate
        self.onOpenTree = onOpenTree
        self.onRequestLocation = onRequestLocation
    }

    var body: some View {
        CityScreen(
            presentation: model.presentation,
            onOpenTree: onOpenTree,
            showsLocationPrompt: model.needsLocation,
            onRequestLocation: onRequestLocation,
            hasFailed: model.hasFailed,
            onRetry: { Task { await model.retry() } }
        )
        // Keyed on the coordinate, as `AlmanacView` keys its own read — the almanac's own fix for a
        // cold launch whose first frame has no fix at all (ERRATA E155).
        .task(id: coordinate) { await model.update(coordinate: coordinate) }
    }
}

// MARK: - The screen itself

/// The City segment's layout, given a finished derivation. Split from `CityView` for the reason
/// `AlmanacScreen` is split from `AlmanacView`: any state can be handed straight in and photographed,
/// with no API, no model and no view lifecycle behind it.
struct CityScreen: View {

    let presentation: CityPresentation?
    var onOpenTree: ((UUID) -> Void)?
    var showsLocationPrompt: Bool = false
    var onRequestLocation: (() -> Void)?

    var hasFailed: Bool = false
    var onRetry: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if showsLocationPrompt {
                        LocationPrompt(
                            title: CityCopy.locationPromptTitle,
                            subtitle: CityCopy.locationPromptSubtitle,
                            onRequest: { onRequestLocation?() }
                        )
                        .padding(.top, CypressSpacing.labelSectionTop)
                        .padding(.horizontal, CypressSpacing.gutter)
                    } else if let presentation, presentation.hasCity {
                        contrastBlock(presentation)
                        compositionBlock(presentation)
                        oldestBlock(presentation)
                    } else if presentation != nil {
                        outOfRange
                    } else if hasFailed {
                        failure
                    }

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

    // MARK: - Header (C1)

    /// No trailing pill, ever — the file header's whole reason: this screen has no city name to put
    /// in one.
    private var header: some View {
        ScreenHeader(title: CityCopy.segmentLabel)
    }

    // MARK: - Card 1 · Your streets, against the city

    @ViewBuilder
    private func contrastBlock(_ presentation: CityPresentation) -> some View {
        if let contrast = presentation.contrast {
            VStack(alignment: .leading, spacing: 0) {
                Text(contrast.label)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(alignment: .leading, spacing: CypressSpacing.Component.iconRowPaddingV) {
                    ForEach(contrast.rows) { row in
                        Text(row.sentence)
                            .font(CypressFont.body135Bold)
                            .foregroundStyle(CypressColor.textInk)
                            .lineSpacing(CypressFont.LineSpacing.body125)
                            .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Card 2 · Who lives here (shape shared with the almanac's own composition card)

    @ViewBuilder
    private func compositionBlock(_ presentation: CityPresentation) -> some View {
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

    // MARK: - Card 3 · The oldest on file (C10 × up to 5)

    @ViewBuilder
    private func oldestBlock(_ presentation: CityPresentation) -> some View {
        if let oldest = presentation.oldest {
            VStack(alignment: .leading, spacing: 0) {
                Text(oldest.label)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                Text(oldest.note)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineSpacing(CypressFont.LineSpacing.body125)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(spacing: AlmanacMetrics.seasonRowGap) {
                    ForEach(oldest.rows) { row in
                        IconTextRow(
                            accent: .elder,
                            title: row.title,
                            subtitle: row.subtitle,
                            photoID: row.heroPhotoID,
                            action: onOpenTree.map { open in { open(row.treeID) } }
                        )
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - Nowhere the record reaches

    private var outOfRange: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(CityCopy.outOfRangeTitle)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(CityCopy.outOfRangeBody)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - The read that did not arrive

    @ViewBuilder
    private var failure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(CityCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)

            if let onRetry {
                SecondaryOutlineButton(CityCopy.loadRetry, style: .compact, action: onRetry)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(CityCopy.footnote)
            .font(CypressFont.body12)
            .foregroundStyle(CypressColor.textFaintAlt)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, AlmanacMetrics.footnoteTop)
            .padding(.bottom, AlmanacMetrics.footnoteBottom)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }
}
