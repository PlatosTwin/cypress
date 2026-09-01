//
//  JournalTabView.swift
//  Cypress — Features/Journal
//
//  The `Journal` tab of C16.
//
//  ── What this screen is, and how much of that is invented ─────────────────────────────────
//  BUILD-PLAN §9 lists "empty grove, journal, collections" as an M2 build requirement and gives the
//  tab no mock — no layout, no copy, no inventory of what belongs on it. What *is* specified is the
//  grouping: BUILD-PLAN §12's enthusiast layer is "collections, almanac, journal, share cards,
//  phenology notifications", and its M4 acceptance criteria name the almanac and the journal in one
//  breath. So both belong in this tab's territory by the plan's own arrangement, and now both are
//  in it.
//
//  ── What changed, and the trap that had to be avoided to change it ────────────────────────
//  This tab used to render screen 12 and nothing else. ERRATA E99 recorded that as a deliberate
//  shortfall — "the name of the tab promising something it does not yet contain is the honest cost"
//  of not inventing a journal — and the journal now exists (`JournalPresentation`), so the cost can
//  be paid off.
//
//  **What it must not do is pay it off by displacing the almanac.** `Route.almanac` is resolved in
//  `RootView` and has no `push` call site anywhere in the app; that arm's own comment says so. This
//  tab is screen 12's only entrance in the entire product. A journal that simply took the tab would
//  have deleted a finished, fully specified screen from the app without removing a line of its code,
//  and every test would still have passed — which is ERRATA E57 exactly, reintroduced by the round
//  that was supposed to be closing E99. So there are (now three) segments and the almanac is one of
//  them.
//
//  ── The third segment ──────────────────────────────────────────────────────────────────────
//  `City` is the owner's own ask — "similar but not identical stats and views to what's on the
//  neighborhood view" — and it sits after the almanac in `JournalSegment` for the same reason the
//  almanac sits after the journal: each segment is a wider ring than the one before it, your own
//  record first.
//
//  ── Why C5, when screen 08's pill row exists ──────────────────────────────────────────────
//  ERRATA E46 settled that 08's three-pill row is **08's own drawn geometry** and deliberately not
//  C5: different radius, a gap between separate pills rather than dividers inside one container, and
//  08 is not among C5's listed users. That reasoning binds this screen in the opposite direction.
//  This tab has no drawn geometry at all, so rule 8 sends it to the nearest specified thing — and
//  the nearest specified thing to "pick which of these views to show" is C5, the segmented control
//  the app already draws on 05, 16 and D3. Borrowing 08's row would mean copying a geometry that
//  SCREENS.md attaches to one specific screen onto a screen it never drew.
//

import SwiftUI

struct JournalTabView: View {

    let api: any CypressAPI
    /// The caller's fix, from the composition root's shared provider (ARCHITECTURE §3). Screen 12
    /// resolves its neighborhood from it and names no neighborhood at all without one.
    let coordinate: Coordinate?

    /// The stated accuracy of that fix, in meters. Both stats segments need it and neither used to
    /// get it: a fix too coarse to place the reader must not be used to name a neighborhood or a
    /// city (`AlmanacLimits.fixCanResolveAnArea(accuracyM:)`, tester report F17).
    var accuracyM: Double?

    /// Which area each stats segment is about, and how to raise the picker that changes it — all
    /// four from the composition root (`AppRouter.journalArea` / `.journalCity`, and
    /// `AppRouter.sheet` for the sheet itself). This tab passes them through and holds none of it:
    /// the picker is presented over the whole window, including this tab's own segmented control,
    /// which is the finding that put it there (PR #132 review, F2).
    var areaSelection: AreaSelection = .here
    var citySelection: CitySelection = .here
    ///
    /// **Two flags and not one**: the two lists are read separately and can be empty separately — a
    /// pre-s16 file carries neighborhoods and no `dim_city`, so the neighborhood picker has rows and
    /// the city picker has none. One flag would draw a button over an empty sheet on that record.
    var canPickArea: Bool = false
    var canPickCity: Bool = false
    var onPickArea: (() -> Void)?
    var onPickCity: (() -> Void)?

    /// The provider itself, handed down so the almanac segment can observe it directly rather than
    /// only ever seeing a fix that already changed (ERRATA E123's residual, #223). `nil` in previews
    /// and tests that supply `coordinate` alone — see `AlmanacView.location`.
    var location: MapLocationProvider?

    /// Screen 12's own outbound affordances, resolved by the composition root so this folder does not
    /// construct another feature's view (ARCHITECTURE §3).
    ///
    /// There were three and there are two since ERRATA E129: the coverage CTA and the vacant-sites row
    /// used to hand out one id each and now hand out the group they counted, through one closure.
    /// `onOpenTree` now serves both segments — an almanac season row and a journal row are both "a
    /// thing that happened to a particular tree", and both open that tree.
    var onOpenTree: ((UUID) -> Void)?
    var onShowGroup: ((PinSet) -> Void)?
    var onRequestLocation: (() -> Void)?
    /// Screen 01, narrowed to this contributor's trees — the `Yours` segment's one outbound link
    /// (tester report F23). Resolved by the composition root, like the three above it: this folder
    /// holds no `MapFilter` and constructs no map (ARCHITECTURE §2, §3).
    var onSeeAllOnMap: (() -> Void)?

    /// Which segment is showing, when there is no router to hold it (previews, screenshots).
    ///
    /// **It opens on the journal**, which is the one decision here that needed making. The tab is
    /// called Journal; a tab whose label names one of its two segments and opens on the other is the
    /// same small dishonesty E99 recorded, moved one level down. The almanac is one tap away and its
    /// entrance is what this screen exists to protect — see the file comment — but it is not what the
    /// bar promises when you press it.
    @State private var localSegment: JournalSegment = .journal

    /// **The journal's model, held here rather than inside the segment it draws.**
    ///
    /// `JournalSection` used to declare it as its own `@State`, and `JournalSection` is mounted from
    /// inside the `switch` below. SwiftUI ties `@State` to the identity of the view that declares
    /// it, and a `switch` arm that is not taken has no identity, so looking at Neighborhood for a
    /// second destroyed the model: the reader came back to page one, whatever `Show earlier` had
    /// fetched, and `JournalModel.load()`'s guard could not help — it met a brand new model in
    /// `.loading`. Owner ruling, 2026-09-01: a revisit paints what was there **and refreshes behind
    /// it**; `JournalModel.load()`'s `.loaded` arm is the second half.
    ///
    /// Here it is above the `switch`, so it lives as long as this tab view does, which is what makes
    /// that guard true across Yours ↔ Neighborhood ↔ City. Across the **bottom** tabs it lives as
    /// long as `RootView.tabRoot`'s own `switch` keeps this view, which is a separate question one
    /// level up and is not claimed here.
    ///
    /// The explicit initializer below exists for this property and for nothing else: `@State` has to
    /// be seeded with `api`, which is a parameter. Every other parameter keeps the name, the order
    /// and the default the synthesized memberwise initializer gave it, so no call site changes.
    @State private var model: JournalModel

    @Environment(AppRouter.self) private var router: AppRouter?

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        accuracyM: Double? = nil,
        areaSelection: AreaSelection = .here,
        citySelection: CitySelection = .here,
        canPickArea: Bool = false,
        canPickCity: Bool = false,
        onPickArea: (() -> Void)? = nil,
        onPickCity: (() -> Void)? = nil,
        location: MapLocationProvider? = nil,
        onOpenTree: ((UUID) -> Void)? = nil,
        onShowGroup: ((PinSet) -> Void)? = nil,
        onRequestLocation: (() -> Void)? = nil,
        onSeeAllOnMap: (() -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.coordinate = coordinate
        self.accuracyM = accuracyM
        self.areaSelection = areaSelection
        self.citySelection = citySelection
        self.canPickArea = canPickArea
        self.canPickCity = canPickCity
        self.onPickArea = onPickArea
        self.onPickCity = onPickCity
        self.location = location
        self.onOpenTree = onOpenTree
        self.onShowGroup = onShowGroup
        self.onRequestLocation = onRequestLocation
        self.onSeeAllOnMap = onSeeAllOnMap
        _model = State(wrappedValue: JournalModel(api: api, now: now))
    }

    /// The router's copy when there is one, this view's own otherwise.
    ///
    /// It lives on `AppRouter` because the segment is addressable — a deep link, and one day a link
    /// from elsewhere in the app, has to be able to ask for the almanac specifically. See
    /// `AppRouter.journalSegment` for the failure that proved it.
    private var segment: Binding<JournalSegment> {
        guard let router else { return $localSegment }
        return Binding(get: { router.journalSegment }, set: { router.journalSegment = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(
                options: JournalSegment.allCases,
                selection: segment,
                label: \.label
            )
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)

            switch segment.wrappedValue {
            case .journal:
                journal
            case .almanac:
                // No `onBack`: a tab root has nothing to go back to, and C1 draws no back circle when
                // it is handed none.
                AlmanacView(
                    api: api,
                    coordinate: coordinate,
                    accuracyM: accuracyM,
                    selection: areaSelection,
                    canPickArea: canPickArea,
                    location: location,
                    onOpenTree: onOpenTree,
                    onShowGroup: onShowGroup,
                    onRequestLocation: onRequestLocation,
                    onPickArea: onPickArea
                )
            case .city:
                // Screen 12's own outbound affordances minus `onShowGroup`: nothing on the City
                // segment counts a group of trees, only a species mix and a list of five, so there
                // is no map destination to hand down.
                CityView(
                    api: api,
                    coordinate: coordinate,
                    accuracyM: accuracyM,
                    selection: citySelection,
                    canPickCity: canPickCity,
                    onOpenTree: onOpenTree,
                    onRequestLocation: onRequestLocation,
                    onPickCity: onPickCity
                )
            }

            BottomTabBar(selection: router?.bottomTabSelection ?? .constant(.journal))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C16 absorbs the home indicator with its own 30pt bottom padding (SCREENS.md §1.6), so the
        // bar runs to the physical edge rather than floating above an inset — as on 01 and 08.
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The contributions journal.
    ///
    /// The list brings no chrome of its own (`JournalListView`), so the scroll view is this
    /// screen's. It used to close with screen 08's footnote, borrowed verbatim; the copy audit of
    /// 2026-08-23 removed that footnote from 08 and from here in the same commit (owner ruling).
    private var journal: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The owner's ask, and the reason it sits above the list rather than under the
                    // title: a reader arriving here from My Grove is deciding which of two lists he
                    // is looking at, and this is the sentence that answers him. Its opposite number
                    // is `GroveCopy.treesExplanation`. It is on this segment only — the almanac is
                    // not a thing anybody confuses with a journal.
                    Text(JournalCopy.explanation)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, CypressSpacing.labelSectionTop)
                        .padding(.horizontal, CypressSpacing.gutter)

                    JournalSection(
                        model: model,
                        onOpenTree: onOpenTree,
                        onSeeAllOnMap: onSeeAllOnMap
                    )

                    // The `Spacer(minLength: 0)` here bottom-pinned the footnote and went with it
                    // (copy audit, 2026-08-23). The `minHeight` frame below still top-aligns a
                    // short list, which is the only thing the spacer was doing besides that. The
                    // 14pt that closed the column was the footnote's bottom padding and is kept as
                    // itself, so the last row does not sit on the tab bar.
                }
                .padding(.bottom, CypressSpacing.labelSectionTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
