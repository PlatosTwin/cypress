//
//  JournalTabView.swift
//  Cypress — Features/Journal
//
//  The `Journal` tab of C16, which until now rendered `NotBuiltYetView`.
//
//  ── What this screen is, and how much of that is invented ─────────────────────────────────
//  BUILD-PLAN §9 lists "empty grove, journal, collections" as an M2 build requirement and gives the
//  tab no mock — no layout, no copy, no inventory of what belongs on it. What *is* specified is the
//  grouping: BUILD-PLAN §12's enthusiast layer is "collections, almanac, journal, share cards,
//  phenology notifications", and its M4 acceptance criteria name the almanac and the journal in one
//  breath. So the almanac belongs in this tab's territory by the plan's own arrangement.
//
//  **Making the almanac the tab's content is invented**, under the project owner's one-time
//  authorization to give screen 12 an entrance; see ERRATA (E57, E98). It is the smallest thing that
//  works: screen 12 is a finished, fully specified screen with no way in, and this tab is a finished
//  entrance with nothing behind it.
//
//  ── What is deliberately not here ─────────────────────────────────────────────────────────
//  The contributions journal itself. `CypressAPI.journal(cursor:limit:)` exists and returns a
//  `Page<JournalEntry>`, so the data is one call away — but a page is not a series, and this screen
//  has no drawn list, no row, no empty state and no copy anywhere in SCREENS.md. Building one would
//  be inventing a screen, and the authorization covers entrances, not screens. Recorded as
//  outstanding in ERRATA (E99) rather than guessed at.
//

import SwiftUI

struct JournalTabView: View {

    let api: any CypressAPI
    /// The caller's fix, from the composition root's shared provider (ARCHITECTURE §3). Screen 12
    /// resolves its neighbourhood from it and names no neighbourhood at all without one.
    let coordinate: Coordinate?

    /// Screen 12's own outbound affordances, resolved by the composition root so this folder does not
    /// construct another feature's view (ARCHITECTURE §3).
    ///
    /// There were three and there are two since ERRATA E129: the coverage CTA and the vacant-sites row
    /// used to hand out one id each and now hand out the group they counted, through one closure.
    var onOpenTree: ((UUID) -> Void)?
    var onShowGroup: ((PinSet) -> Void)?
    var onRequestLocation: (() -> Void)?

    @Environment(AppRouter.self) private var router: AppRouter?

    var body: some View {
        VStack(spacing: 0) {
            // No `onBack`: a tab root has nothing to go back to, and C1 draws no back circle when
            // it is handed none.
            AlmanacView(
                api: api,
                coordinate: coordinate,
                onOpenTree: onOpenTree,
                onShowGroup: onShowGroup,
                onRequestLocation: onRequestLocation
            )

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
}
