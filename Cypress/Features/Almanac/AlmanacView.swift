//
//  AlmanacView.swift
//  Cypress — Features/Almanac
//
//  Screen 12 · Neighborhood almanac. SCREENS.md lines 1053–1091.
//
//  Composed from C1 (ScreenHeader + HeaderPill), C10 (IconTextRow) ×3, C24 (AttentionCard) and
//  C6 compact. The composition card in §3 has no C-number — SCREENS.md §2's catalog does not
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

    /// Where both counted rows go: a screen that shows the group together (ERRATA E129).
    ///
    /// **One closure for two rows, replacing `onWalk(UUID)` and `onOpenSite(UUID)`.** Each of those
    /// handed out one id — §4's CTA opened the nearest young tree, `Where a tree could go` opened the
    /// nearest basin — so a row that said `Walk the nine` or `1,474 empty planting sites` answered
    /// with one record and left the question it raised, which is *where*, unanswered. They are one
    /// destination now because they are one kind of statement, and two would be two chances to answer
    /// it differently.
    ///
    /// Handed in rather than pushed here, so this folder does not construct another feature's view
    /// (ARCHITECTURE §3); the composition root resolves it to `Route.pinSet`.
    private let onShowGroup: ((PinSet) -> Void)?

    /// Tapping a season row opens the tree it is about. The elder and the first bloom are each a
    /// specific tree; SCREENS.md 12 states no affordance for either, so this is nil unless the
    /// composition root supplies one and the rows are inert without it (DECISIONS constraint 21).
    private let onOpenTree: ((UUID) -> Void)?

    private let onBack: (() -> Void)?

    /// The composition root's fix as of **this** pass through the parent's body.
    ///
    /// Stored, where it used to be consumed by the initializer and forgotten. `@State` runs its
    /// initializer exactly once, so the model below was built from whichever coordinate happened to
    /// exist at first construction and never heard about another — and on a cold launch that is
    /// `nil`, because CoreLocation has not answered yet. Keeping the parameter is what lets the
    /// `.task(id:)` notice it change (ERRATA E155).
    private let coordinate: Coordinate?

    /// The stated accuracy of that fix, in meters, and the reason this screen has one at all: a fix
    /// too coarse to place the reader must not be used to name a neighborhood (tester report F17,
    /// `AlmanacLimits.fixCanResolveAnArea(accuracyM:)`). `nil` in previews and tests driving a bare
    /// coordinate, which the rule permits.
    private let accuracyM: Double?

    /// The composition root's shared provider, held so the model can observe it directly (ERRATA
    /// E123's residual, #223) rather than waiting for a fix to arrive as a changed `coordinate`
    /// parameter on the next pass through the parent's body. `nil` in every preview and every test
    /// that drives this view by setting `coordinate` alone — `AlmanacModel.observeLocation()` is a
    /// no-op for them and the `.task(id: coordinate)` below is what still runs.
    private let location: MapLocationProvider?

    private let onRequestLocation: (() -> Void)?

    /// Whether the area picker is up. Owned here and handed to `AlmanacScreen` as a value with two
    /// closures, so the picker-open state can be handed straight in and photographed — the split
    /// this file's own header describes, applied to one more state (ERRATA E126).
    @State private var isPickingArea = false

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        accuracyM: Double? = nil,
        location: MapLocationProvider? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        onBack: (() -> Void)? = nil,
        onOpenTree: ((UUID) -> Void)? = nil,
        onShowGroup: ((PinSet) -> Void)? = nil,
        onRequestLocation: (() -> Void)? = nil
    ) {
        _model = State(wrappedValue: AlmanacModel(
            api: api,
            coordinate: coordinate,
            accuracyM: accuracyM,
            location: location,
            now: now
        ))
        self.coordinate = coordinate
        self.accuracyM = accuracyM
        self.location = location
        self.onBack = onBack
        self.onOpenTree = onOpenTree
        self.onShowGroup = onShowGroup
        self.onRequestLocation = onRequestLocation
    }

    var body: some View {
        AlmanacScreen(
            presentation: model.presentation,
            onBack: onBack,
            onOpenTree: onOpenTree,
            onShowGroup: onShowGroup,
            // E123's prompt condition, asked of the model rather than of the parameter. The
            // parameter answers "is there a fix"; the screen is asking "is this blank because there
            // is no fix", and between the fix arriving and the neighborhood being read those two
            // give opposite answers — which is how the prompt came to be withdrawn from a screen
            // that then had nothing on it. See `AlmanacModel.needsLocation`.
            showsLocationPrompt: model.needsLocation,
            onRequestLocation: onRequestLocation,
            // Handed down as a value and a closure rather than read off the model inside the screen,
            // for the same reason the presentation is: a state the screen cannot be *given* is a
            // state nobody can photograph (ERRATA E126).
            hasFailed: model.hasFailed,
            onRetry: { Task { await model.retry() } },
            // The fix is present and too rough to place the reader — F17's own mechanism. Asked of
            // the model, beside `showsLocationPrompt`, and for the identical reason: the question is
            // "is what is on screen blank because of this", not "is this true right now".
            needsAreaChoice: model.needsAreaChoice,
            areaOptions: Self.options(model.choices),
            selectedAreaID: Self.optionID(model.displayedSelection),
            isPickingArea: isPickingArea,
            onOpenPicker: { isPickingArea = true },
            onClosePicker: { isPickingArea = false },
            onPickArea: { option in
                isPickingArea = false
                Task { await model.choose(Self.selection(for: option)) }
            }
        )
        // The picker's list. Once per screen: the set changes only when a city pack is installed or
        // removed, which cannot happen while this segment is on screen.
        .task { await model.loadChoices() }
        // `id:` and not a bare `.task`. The bare form runs once at mount, which is the same
        // once-only that the `@State` initializer has, so the first frame's coordinate would still
        // be the only one this screen ever read from. Keyed on the coordinate, the read re-runs when
        // — and only when — the fix changes, which on a cold launch is `nil` → San Francisco a
        // second after the tab is pressed.
        //
        // **Only when there is no `location` to observe instead (ERRATA E123's residual, #223).**
        // With a live provider, `AlmanacModel.observeLocation()` below is authoritative — it performs
        // this exact mount-time read itself and then reloads only on a fix boundary, not on every
        // published coordinate. Leaving this task active for both would mean two triggers racing to
        // reload on the same transition, and — the defect this ticket is about — this task re-firing
        // on every walking-distance coordinate change even when `observeLocation()` correctly did not.
        .task(id: coordinate) {
            guard location == nil else { return }
            await model.update(coordinate: coordinate, accuracyM: accuracyM)
        }
        // The direct-observation path. A no-op for every caller above that left `location` `nil`.
        .task { await model.observeLocation() }
    }

    // MARK: - The picker's options, and the selection they map back to

    /// `AreaPickerCopy.here` first, then the record's own neighborhoods in the order the read
    /// returned them (largest first — `AreaQueries.neighborhoods`).
    ///
    /// **`here` is always offered, including while it is the one showing.** A picker that hid the
    /// way back would strand a reader who picked a neighborhood by mistake, and the chip's selected
    /// state is what says which one is live.
    static func options(_ choices: [NeighborhoodChoice]) -> [AreaPickerSheet.Option] {
        [AreaPickerSheet.Option(id: AreaPickerCopy.hereID, label: AreaPickerCopy.here)]
            + choices.map { AreaPickerSheet.Option(id: String($0.id), label: $0.name) }
    }

    static func optionID(_ selection: AreaSelection) -> String {
        switch selection {
        case .here: return AreaPickerCopy.hereID
        case let .neighborhood(id): return String(id)
        }
    }

    /// The inverse. An id that is not `here` and not an integer cannot be produced by `options(_:)`
    /// above, and resolves to `.here` rather than to a crash or a neighborhood 0.
    static func selection(for option: AreaPickerSheet.Option) -> AreaSelection {
        guard option.id != AreaPickerCopy.hereID, let id = Int(option.id) else { return .here }
        return .neighborhood(id: id)
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
    /// Both counted rows' one destination (ERRATA E129); see `AlmanacView.onShowGroup`.
    var onShowGroup: ((PinSet) -> Void)?
    var showsLocationPrompt: Bool = false
    var onRequestLocation: (() -> Void)?

    /// The read came back empty-handed. Distinct from `presentation == nil`, which is also true
    /// while the read is still in flight (ERRATA E126).
    var hasFailed: Bool = false
    /// Absent when nobody is listening — a button that looks pressable and does nothing is worse
    /// than no button, the judgment `GroveTabRow` already made about its two inert pills.
    var onRetry: (() -> Void)?

    /// Location is granted, a fix has arrived, and it is too coarse to say which neighborhood the
    /// reader is in (`AlmanacModel.needsAreaChoice`, tester report F17).
    ///
    /// **A fourth way of having nothing on the screen, and it means a fourth thing.** The other
    /// three are `showsLocationPrompt` (no fix), `outOfRange` (a good fix, outside every inventory)
    /// and `hasFailed` (the read did not arrive). This one is a good enough app and a rough enough
    /// phone, and the only one of the four the reader can fix from here.
    var needsAreaChoice: Bool = false

    /// What the picker offers, which choice is live, and whether it is up.
    ///
    /// Handed in as values with closures rather than owned here, so every state of the picker can be
    /// photographed with no model behind it (ERRATA E126) — including the one that matters most,
    /// the sheet open over a named area.
    var areaOptions: [AreaPickerSheet.Option] = []
    var selectedAreaID: String?
    var isPickingArea: Bool = false
    var onOpenPicker: (() -> Void)?
    var onClosePicker: (() -> Void)?
    var onPickArea: ((AreaPickerSheet.Option) -> Void)?

    /// Whether there is anything to pick from. An affordance over an empty list is the inert pill
    /// `GroveTabRow` ruled out.
    private var canPickArea: Bool { onPickArea != nil && areaOptions.count > 1 }

    var body: some View {
        ZStack {
            column
            if isPickingArea {
                AreaPickerSheet(
                    title: AreaPickerCopy.neighborhoodTitle,
                    subtitle: AreaPickerCopy.neighborhoodSubtitle,
                    options: areaOptions,
                    selectedID: selectedAreaID,
                    onSelect: { onPickArea?($0) },
                    onClose: { onClosePicker?() }
                )
            }
        }
    }

    private var column: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if showsLocationPrompt {
                        LocationPrompt(
                            title: AlmanacCopy.locationPromptTitle,
                            subtitle: AlmanacCopy.locationPromptSubtitle,
                            onRequest: { onRequestLocation?() }
                        )
                        .padding(.top, CypressSpacing.labelSectionTop)
                        .padding(.horizontal, CypressSpacing.gutter)
                    } else if needsAreaChoice {
                        coarseFix
                    } else if let presentation, presentation.hasArea {
                        provenance(presentation)
                        areaNote(presentation)
                        seasonBlock(presentation)
                        compositionBlock(presentation)
                        vacantSitesBlock(presentation)
                        coverageBlock(presentation)
                    } else if presentation != nil {
                        // A finished read that resolved no area — the reader is standing outside
                        // every inventory in the record (ERRATA E182). Ordered after the block above
                        // and before the failure arm because those three exhaust the loaded states:
                        // `presentation` is non-nil only when the read succeeded.
                        outOfRange
                    } else if hasFailed {
                        failure
                    }

                    // §5's `margin-top:auto` existed to bottom-pin the footnote, and the copy audit
                    // of 2026-08-23 removed the footnote (owner ruling). The spacer goes with it:
                    // there is nothing left to push down, and the column is already top-aligned by
                    // the `minHeight` frame below. Leaving it would be a flexible gap holding
                    // nothing open.
                    //
                    // **The 36pt below is not the footnote and stays.** It is the screen's closing
                    // space above the home indicator; it happened to be spelled as the footnote's
                    // bottom padding, and deleting it with the sentence would have run the last card
                    // into the edge.
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

    // MARK: - Where the area came from, and how to change it (tester report F17)

    /// One muted sentence saying who chose this area, and the button that lets the reader choose
    /// another. Drawn in `areaNote`'s type and color because it is doing `areaNote`'s job: saying
    /// out loud something the header alone is too quiet to say.
    ///
    /// **NOT SPECIFIED** — see `AreaPickerCopy.resolvedFromFix` for why the sentence exists at all.
    @ViewBuilder
    private func provenance(_ presentation: AlmanacPresentation) -> some View {
        if let note = presentation.provenanceNote {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Text(note)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineSpacing(CypressFont.LineSpacing.body125)
                    .fixedSize(horizontal: false, vertical: true)

                if canPickArea {
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

    /// A fix too rough to place the reader. Location is on; there is nothing to turn on, and the
    /// picker is the door that is open (`AreaPickerCopy.coarseFixTitle`).
    private var coarseFix: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(AreaPickerCopy.coarseFixTitle)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(AreaPickerCopy.coarseFixBody)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)

            if canPickArea {
                SecondaryOutlineButton(
                    AreaPickerCopy.pickAnArea,
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

    // MARK: - §1 Header (C1)

    /// `title: Almanac`, trailing pill `Outer Sunset`.
    ///
    /// The pill is the neighborhood's own name from the seed, so it reads `Sunset/Parkside` rather
    /// than the mock's colloquial `Outer Sunset` — SF's official polygon set carries no such
    /// neighborhood (A4, ERRATA E47). No pill at all when there is no fix: a header that named an
    /// area we could not determine would be the screen's first lie.
    @ViewBuilder
    private var header: some View {
        if let name = presentation?.neighborhoodName {
            ScreenHeader(title: AlmanacCopy.screenTitle, trailingPill: name, onBack: onBack)
        } else {
            ScreenHeader(title: AlmanacCopy.screenTitle, onBack: onBack)
        }
    }

    // MARK: - The area, when it is a distance rather than a place (RULINGS R29)

    /// One muted sentence under the header, present only for the fallback area.
    ///
    /// **NOT SPECIFIED** by SCREENS.md 12, which draws one area and names it. It is a sentence and
    /// not a card because it is not a state the reader has to act on — everything below it is real
    /// and correct — it is the qualifier that stops `Within a 15-minute walk` being read as the name
    /// of a neighborhood. Same treatment as `PinSetPresentation.coverage`'s second line, which
    /// exists for the same kind of reason: a claim above it is only honest with it there.
    @ViewBuilder
    private func areaNote(_ presentation: AlmanacPresentation) -> some View {
        if let note = presentation.areaNote {
            Text(note)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CypressSpacing.labelSectionTop)
                .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §2 This season (C10 ×3)

    /// Micro-label, the note that says what the heading is actually over, then up to three C10
    /// rows, `VStack(spacing:7)`.
    ///
    /// The label goes with the rows: a heading over nothing is a heading that promises something.
    /// The note goes with them for the same reason — it describes the rows that drew, so it cannot
    /// outlive them (task #177; `AlmanacCopy.seasonNote`). It is drawn in `areaNote`'s type and
    /// color because it is doing `areaNote`'s job on the same screen: saying which promise a
    /// heading is making, where the heading alone is too quiet to say it.
    @ViewBuilder
    private func seasonBlock(_ presentation: AlmanacPresentation) -> some View {
        if !presentation.seasonRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(AlmanacCopy.seasonLabel)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                if let note = presentation.seasonNote {
                    Text(note)
                        .font(CypressFont.body125)
                        .foregroundStyle(CypressColor.textMuted)
                        .lineSpacing(CypressFont.LineSpacing.body125)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, CypressSpacing.gapVitality)
                }

                VStack(spacing: AlmanacMetrics.seasonRowGap) {
                    ForEach(presentation.seasonRows) { row in
                        IconTextRow(
                            accent: row.accent,
                            title: row.title,
                            subtitle: row.subtitle,
                            photoID: row.heroPhotoID,
                            action: action(for: row)
                        )
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    /// Where a §2 row goes when it is pressed, or nil when it goes nowhere.
    ///
    /// **A row names one record or counts several, and those are two destinations** — a profile and
    /// a map. The elder and the first bloom are each one tree and open it; `Newest neighbors` counts
    /// this spring's plantings and opens the same map screen the coverage gap and the vacant sites
    /// open, because the question a count of trees raises is *where* and this app answers that in
    /// one place (ERRATA E129, E144, and E182 for this row).
    ///
    /// The owner's report was exactly this row: *"Clicking on newest neighbors on neighborhood
    /// almanac should show them on the map."* It was the last counted row on screen 12 with nothing
    /// behind it.
    ///
    /// Nil when nobody is listening, which keeps a row that cannot go anywhere from looking like one
    /// that can — the judgment `GroveTabRow` made about its two inert pills.
    private func action(for row: AlmanacPresentation.SeasonRow) -> (() -> Void)? {
        if let id = row.treeID, let onOpenTree {
            return { onOpenTree(id) }
        }
        if let group = row.group, let onShowGroup {
            return { onShowGroup(group) }
        }
        return nil
    }

    // MARK: - Where a tree could go (R10) — one C10 row, a statement between §3 and §4

    /// A single C10 row: the count of empty basins, tapping to a map of the nearest of them
    /// (ERRATA E129).
    ///
    /// Placed after §3 and before §4 on purpose. §3 says what lives in the neighborhood; this says
    /// where nothing does — two readings of the same canopy — while §4 stays the screen's one
    /// directed ask and the last block in the column, so it is what the reader is left with. A
    /// plain row before §4's amber card also reads as the statement it is rather than as a second
    /// ask.
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
                    action: onShowGroup.map { show in { show(block.group) } }
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

                        // Optional since the copy audit of 2026-08-23: the body's opening sentence
                        // was killed, and what is left renders only when it has been checked. On a
                        // card with no body the CTA takes the gap the body's own bottom margin held
                        // open, so the button does not move up against the title.
                        if let body = coverage.body {
                            Text(body)
                                .font(CypressFont.body125)
                                .foregroundStyle(CypressColor.textMuted)
                                .lineSpacing(CypressFont.LineSpacing.body125)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, AlmanacMetrics.coverageBodyTop)
                                .padding(.bottom, AlmanacMetrics.coverageBodyBottom)
                        }

                        PrimaryButton(coverage.ctaTitle, style: .compact) {
                            onShowGroup?(coverage.group)
                        }
                        .padding(.top, coverage.body == nil ? AlmanacMetrics.coverageBodyBottom : 0)
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - Nowhere the record reaches (ERRATA E182)

    /// The read finished, the fix is good, and no inventory in the file covers this ground.
    ///
    /// **NOT SPECIFIED** by SCREENS.md 12, which draws one city. Before this arm the state drew
    /// nothing at all — the same picture as a read still in flight, on the screen E126 calls the
    /// last place to conflate what is not there with what could not be asked. Every San Jose reader
    /// was in it, and after R29 a reader anywhere outside the record still is.
    ///
    /// No button. There is genuinely nothing to press: a retry would read the same file and get the
    /// same answer, and a control that cannot change the outcome is worse than no control (the same
    /// judgment `AlmanacCopy.loadFailed`'s retry is *not* an instance of, because that read really
    /// can succeed the second time).
    private var outOfRange: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(AlmanacCopy.outOfRangeTitle)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(AlmanacCopy.outOfRangeBody)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)

            // **The one door that is open from here.** The copy above is D16's shape — it says what
            // would change this, which is more cities joining the record — and until the picker
            // existed there was nothing on this screen a reader standing in Sacramento could do. A
            // reader who has downloaded Manhattan can read Manhattan from here now, which is the
            // owner's ask arriving at the state that needed it most.
            if canPickArea {
                SecondaryOutlineButton(
                    AreaPickerCopy.pickAnArea,
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

    /// **NOT SPECIFIED** by SCREENS.md 12, which draws no error state.
    ///
    /// `AlmanacModel.Phase` makes the argument for this arm and then had nowhere to make it: with no
    /// branch here, a failed read drew the almanac with every block withheld — which is this screen's
    /// way of saying the neighborhood is quiet. Five true blocks removed and one removed because we
    /// could not ask produced the same picture, on the one screen whose entire subject is what is and
    /// is not there (ERRATA E126).
    ///
    /// The header above it drops its neighborhood pill on its own, since there is no presentation to
    /// name one, so nothing on the screen claims an area it never resolved.
    @ViewBuilder
    private var failure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(AlmanacCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)

            if let onRetry {
                SecondaryOutlineButton(AlmanacCopy.loadRetry, style: .compact, action: onRetry)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // §5's footnote was removed by the copy audit of 2026-08-23 (owner ruling). SCREENS.md 12 §5 is
    // struck to match, so a future build cannot restore it from the mock.
}

// MARK: - §3's share row

/// One row of the composition card: swatch, name, track, value.
///
/// SCREENS.md 12 §3: `11×11 swatch (radius 3.5px) · name 13.5px/700 · a flex:1 9px track (radius
/// 5px) filled via linear-gradient(90deg, <color> 0 N%, #EDEFE3 N%) · mono 12px value`.
///
/// The gradient is drawn as two rectangles rather than as a `LinearGradient` with coincident stops:
/// the CSS is a hard-edged two-color stop, which is a bar, and a bar drawn as a gradient rounds its
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

    /// Never a color of its own: the presentation chose an index into the design system's own
    /// four-swatch series (ARCHITECTURE §6).
    private var swatch: Color {
        let swatches = CypressColor.compositionSwatches
        return swatches[min(max(row.swatchIndex, 0), swatches.count - 1)]
    }
}
