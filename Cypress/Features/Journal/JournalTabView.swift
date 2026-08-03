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
//  that was supposed to be closing E99. So there are two segments and the almanac is one of them.
//
//  ── Why C5, when screen 08's pill row exists ──────────────────────────────────────────────
//  ERRATA E46 settled that 08's three-pill row is **08's own drawn geometry** and deliberately not
//  C5: different radius, a gap between separate pills rather than dividers inside one container, and
//  08 is not among C5's listed users. That reasoning binds this screen in the opposite direction.
//  This tab has no drawn geometry at all, so rule 8 sends it to the nearest specified thing — and
//  the nearest specified thing to "pick which of these two views to show" is C5, the segmented
//  control the app already draws on 05, 16 and D3. Borrowing 08's row would mean copying a geometry
//  that SCREENS.md attaches to one specific screen onto a screen it never drew.
//

import SwiftUI

struct JournalTabView: View {

    let api: any CypressAPI
    /// The caller's fix, from the composition root's shared provider (ARCHITECTURE §3). Screen 12
    /// resolves its neighborhood from it and names no neighborhood at all without one.
    let coordinate: Coordinate?

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

    /// Which segment is showing, when there is no router to hold it (previews, screenshots).
    ///
    /// **It opens on the journal**, which is the one decision here that needed making. The tab is
    /// called Journal; a tab whose label names one of its two segments and opens on the other is the
    /// same small dishonesty E99 recorded, moved one level down. The almanac is one tap away and its
    /// entrance is what this screen exists to protect — see the file comment — but it is not what the
    /// bar promises when you press it.
    @State private var localSegment: JournalSegment = .journal

    @Environment(AppRouter.self) private var router: AppRouter?

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
                    onOpenTree: onOpenTree,
                    onShowGroup: onShowGroup,
                    onRequestLocation: onRequestLocation
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

    /// The contributions journal, and the footnote that governs it.
    ///
    /// The list brings no chrome of its own (`JournalListView`), so the scroll view and the footnote
    /// are this screen's. The footnote is screen 08's, verbatim: "Quiet collecting. There are no
    /// streaks and no leaderboards." It is on this screen for the reason it is on that one — it is
    /// the sentence that makes a list of a person's own contributions read as a record rather than a
    /// scoreboard, and this is the surface most able to break it (D1).
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

                    JournalSection(api: api, onOpenTree: onOpenTree)

                    Spacer(minLength: 0)

                    Text(JournalCopy.footnote)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textFaintAlt)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CypressSpacing.labelSectionTop)
                        .padding(.horizontal, CypressSpacing.gutterLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
