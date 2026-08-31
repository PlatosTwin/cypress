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
    /// The stated accuracy of that fix, in meters — see `AlmanacView.accuracyM`, which carries the
    /// same value into the same rule (`AlmanacLimits.fixCanResolveAnArea(accuracyM:)`, F17).
    private let accuracyM: Double?
    private let onRequestLocation: (() -> Void)?

    /// Which city this segment is about, from the composition root (`AppRouter.journalCity`), plus
    /// whether there is anything to pick and how to raise the picker — `AlmanacView`'s three, for the
    /// same reason. The sheet is presented by `RootView`, not here.
    private let selection: CitySelection
    private let canPickCity: Bool
    private let onPickCity: (() -> Void)?

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        accuracyM: Double? = nil,
        selection: CitySelection = .here,
        canPickCity: Bool = false,
        onOpenTree: ((UUID) -> Void)? = nil,
        onRequestLocation: (() -> Void)? = nil,
        onPickCity: (() -> Void)? = nil
    ) {
        _model = State(wrappedValue: CityModel(
            api: api,
            coordinate: coordinate,
            accuracyM: accuracyM,
            selection: selection
        ))
        self.coordinate = coordinate
        self.accuracyM = accuracyM
        self.selection = selection
        self.canPickCity = canPickCity
        self.onPickCity = onPickCity
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
            onRetry: { Task { await model.retry() } },
            needsAreaChoice: model.needsAreaChoice,
            canPickCity: canPickCity,
            onOpenPicker: onPickCity
        )
        // Keyed on the coordinate, as `AlmanacView` keys its own read — the almanac's own fix for a
        // cold launch whose first frame has no fix at all (ERRATA E155).
        //
        // **On the accuracy as well as the coordinate**, and the pair is why `Fix` exists at all.
        // `MapLocationProvider.publish` rewrites `availability` when the position moves *or* when
        // the accuracy changes by a meter (`publishAccuracyM`), so a reader standing still while
        // Precise Location is switched on gets a new accuracy at the same coordinate. Keyed on the
        // coordinate alone this segment would never hear about it, and would go on saying it cannot
        // tell which city you are in on a phone that now can. `AlmanacView` reaches the same fact by
        // a different road — it observes the provider directly (`AlmanacModel.observeLocation`),
        // whose `isFixAvailabilityTransition` gained the same second boundary — and this segment has
        // no provider to observe.
        .task(id: Fix(coordinate: coordinate, accuracyM: accuracyM)) {
            await model.update(coordinate: coordinate, accuracyM: accuracyM)
        }
        .task(id: selection) { await model.update(selection: selection) }
    }

    /// The two halves of a fix, together, so `.task(id:)` can key on both. `Coordinate` is
    /// `Hashable` and a tuple is not.
    private struct Fix: Hashable {
        let coordinate: Coordinate?
        let accuracyM: Double?
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

    /// Location is granted, a fix has arrived, and it is too coarse to say which city the reader is
    /// in (`CityModel.needsAreaChoice`, tester report F17) — `AlmanacScreen.needsAreaChoice`'s twin.
    var needsAreaChoice: Bool = false

    /// Whether there is anything to pick from, and how to raise the picker. The sheet itself is
    /// presented by the composition root — `AlmanacScreen`'s pair, for the same reason.
    ///
    /// False for a record with no `dim_city`: a city with no name on file is not offered under an
    /// invented one (`AreaQueries`), and the affordance goes with the list.
    var canPickCity: Bool = false
    var onOpenPicker: (() -> Void)?

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
                    } else if needsAreaChoice {
                        coarseFix
                    } else if let presentation, presentation.hasCity {
                        provenance(presentation)
                        contrastBlock(presentation)
                        compositionBlock(presentation)
                        oldestBlock(presentation)
                    } else if presentation != nil {
                        outOfRange
                    } else if hasFailed {
                        failure
                    }

                    // The spacer bottom-pinned the footnote and went with it (copy audit,
                    // 2026-08-23). The `minHeight` frame below still top-aligns a short column, and
                    // the 36pt is the screen's closing space rather than part of the footnote.
                }
                .padding(.bottom, CypressSpacing.bottomFootnote)
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

    /// `title: City`, trailing pill the city's own name.
    ///
    /// **This used to say "no trailing pill, ever", on the grounds that the screen had no city name
    /// to put in one.** That was true and stopped being true at seed schema 16, which put
    /// `dim_city.display_name` on disk in the file this screen already reads — see
    /// `CityPresentation`'s header for the whole of it. The pill draws the name the record carries
    /// and draws nothing when the record carries none, which is the same rule screen 12's own pill
    /// follows for a neighborhood it cannot name.
    @ViewBuilder
    private var header: some View {
        if let name = presentation?.cityName {
            ScreenHeader(title: CityCopy.segmentLabel, trailingPill: name)
        } else {
            ScreenHeader(title: CityCopy.segmentLabel)
        }
    }

    // MARK: - Where the city came from, and how to change it (tester report F17)

    /// `AlmanacScreen.provenance(_:)`'s twin, in the same type and color, saying who chose this city
    /// and offering the way to choose another. **NOT SPECIFIED** — see `AreaPickerCopy`.
    @ViewBuilder
    private func provenance(_ presentation: CityPresentation) -> some View {
        if let note = presentation.provenanceNote {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Text(note)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineSpacing(CypressFont.LineSpacing.body125)
                    .fixedSize(horizontal: false, vertical: true)

                if canPickCity, onOpenPicker != nil {
                    SecondaryOutlineButton(
                        AreaPickerCopy.change,
                        style: .compact,
                        action: { onOpenPicker?() }
                    )
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    /// A fix too rough to place the reader. Location is on and there is nothing to turn on; the
    /// picker is the door that is open (`AreaPickerCopy.coarseFixTitle`).
    private var coarseFix: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(AreaPickerCopy.coarseFixTitle)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(AreaPickerCopy.coarseFixCityBody)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)

            if canPickCity, onOpenPicker != nil {
                SecondaryOutlineButton(
                    AreaPickerCopy.pickACity,
                    style: .compact,
                    action: { onOpenPicker?() }
                )
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
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

            // The one door open from here — `AlmanacScreen.outOfRange`'s own addition, for the same
            // reason: a reader whose ground no inventory covers can still read a city they have.
            if canPickCity, onOpenPicker != nil {
                SecondaryOutlineButton(
                    AreaPickerCopy.pickACity,
                    style: .compact,
                    action: { onOpenPicker?() }
                )
                .fixedSize()
            }
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

    // The footnote was removed by the copy audit of 2026-08-23 (owner ruling), along with the
    // `AlmanacMetrics` footnote paddings it borrowed.
}
