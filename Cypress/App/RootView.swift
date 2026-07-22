import SwiftUI

/// The composition root's view. The only place that knows how features connect.
///
/// Features push `Route`s and hand out closures for the things that are not navigations (a visit is
/// a camera, a favorite is a mutation). Resolving those in one file is what keeps a feature folder
/// from importing its siblings.
struct RootView: View {

    let data: DataLayer

    @State private var router = AppRouter()

    /// The one shared location provider (ARCHITECTURE §3: "Shared services (`CypressAPI`, `Outbox`,
    /// `LocationProvider`) are passed through the SwiftUI environment from a single composition
    /// root").
    ///
    /// It is never `start()`ed here, and that is deliberate: starting is what shows the system
    /// sheet, and screen 01 is the one screen the design gives a reason to ask on. Once the map has
    /// asked and been allowed, this provider receives the authorisation callback like any other and
    /// begins reporting fixes; until then it stays `.notAsked` and the screens that read it draw
    /// without a location.
    @State private var location = MapLocationProvider()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            tabRoot
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .environment(router)
        .fullScreenCover(isPresented: presentingVisitFlow) {
            VisitFlowView(
                api: data.api,
                outbox: data.outbox,
                deviceID: data.deviceID,
                onExit: { router.sheet = nil },
                onAddTree: { router.sheet = nil },
                onOpenTree: { id in
                    router.sheet = nil
                    router.push(.treeProfile(id))
                },
                // PROTOTYPE-FLOW §1.6 rule 5: after the third tree the next-tree CTA reads
                // `Route done · see your grove` and goes to the grove. It closes the camera flow
                // and moves the bottom bar rather than pushing, because the grove is a tab root.
                onOpenGrove: {
                    router.sheet = nil
                    router.tab = .grove
                }
            )
        }
    }

    /// What the bottom bar (C16) selects between.
    ///
    /// A `switch` on `router.tab` rather than a `TabView`, because C16 is a drawn component with its
    /// own hand-made icons and paddings (SCREENS.md §2) and every screen that carries it draws it
    /// itself — screen 01 already did, and 08's variant differs from 01's (no backdrop blur). The
    /// bar was already flipping `router.tab` before this; nothing was reading it, so the two built
    /// tabs are now wired and the two unbuilt ones say so.
    ///
    /// `Journal` and `You` are BUILD-PLAN §9 M2 build requirements with no mock — "empty grove,
    /// journal, collections" and "the You tab (profile, settings, outbox entry point, privacy
    /// toggles)". They get the same plain placeholder every unbuilt destination in this file gets
    /// rather than an invented screen (DECISIONS constraint 21).
    @ViewBuilder
    private var tabRoot: some View {
        switch router.tab {
        case .map:
            MapHomeView(api: data.api)
        case .grove:
            // Screen 08. The species tile's destination is 07, which is the one entrance
            // SCREENS.md draws for it: "Tapping a tile opens the species page."
            GroveView(
                api: data.api,
                onOpenSpecies: { id in router.push(.species(id)) }
            )
        case .journal:
            NotBuiltYetView(label: "journal")
        case .you:
            NotBuiltYetView(label: "you")
        }
    }

    // Screen 04 is a camera, so it is presented rather than pushed — and `Route` has no camera case
    // by design (DECISIONS constraint 21). `.identify` is the flow's entry point.
    private var presentingVisitFlow: Binding<Bool> {
        Binding(
            get: { router.sheet == .identify },
            set: { if !$0 { router.sheet = nil } }
        )
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .treeProfile(let id):
            TreeProfileView(
                treeID: id,
                api: data.api,
                onVisit: { _ in router.present(.identify) },
                onFavorite: { _ in /* outbox mutation — wired with the grove, M2 */ }
            )

        case .checkIn(let id):
            // Screen 05. Anonymous under the device id until the account ask ships (D9); the
            // composition root owns that choice, not the feature.
            //
            // **Nothing pushes this route yet.** No mocked screen carries an affordance that opens
            // the check-in: 03's quad row is Favorite / Care / Share / Report, its one primary CTA
            // is the visit, and the prototype never reaches 05 at all. Screen 18's success block
            // reads `Check-in saved`, so 05's *exit* is drawn while its entrance is not. Inventing
            // the button is exactly what DECISIONS constraint 21 forbids, so the destination is
            // wired and the affordance is a question for design. See ERRATA (E24).
            CheckInView(
                treeID: id,
                api: data.api,
                outbox: data.outbox,
                attribution: .anonymous(deviceID: data.deviceID),
                onSaved: { _ in router.pop() }
            )

        case .report(let id):
            // Screen 06. D4's private reminder is device-owned until an account exists, so the save
            // works on a device that has never seen the account sheet — which is every device the
            // app currently runs on (D9, ERRATA E23). The owner comes from `LocalAPI.attribution`
            // and never from the screen: the reminder belongs to the signed-in user when there is
            // one, and to this installation otherwise. When screen 15 lands, `claimDevice` moves
            // these reminders onto the account and this line does not change.
            ReportView(
                treeID: id,
                api: data.api,
                onSaveReminder: { draft in
                    try await ReminderOutboxWriter.save(
                        draft,
                        attribution: await data.api.attribution,
                        outbox: data.outbox
                    )
                }
            )

        case .species(let id):
            // Screen 07. The fix comes from the composition root, which ARCHITECTURE §3 names as
            // where a `LocationProvider` belongs; the screen never asks for permission itself,
            // because nothing in SCREENS.md 07 says it should. Without one, 07's `Near you` card
            // and its nearby list simply have no subject and do not draw.
            //
            // **07's one drawn entrance is a tile on screen 08** ("Tapping a tile opens the species
            // page"), and `tabRoot` now wires it. 03's affordance list ends at `Report` → 06 and
            // `DBH/Height` → 11, and the clickable prototype has no species screen in its `screen`
            // enum at all, so no other button was invented on a screen that has one (DECISIONS
            // constraint 21). See ERRATA (E43).
            SpeciesView(
                speciesID: id,
                api: data.api,
                coordinate: location.availability.coordinate
            )

        // Every remaining route has a mocked screen but no built feature yet. Naming them here
        // rather than defaulting means adding one is a compile error, not a silent no-op.
        case .identify, .careLog, .share, .growthHistory, .measure, .outbox:
            NotBuiltYetView(route: route)
        }
    }
}

/// Deliberately plain. A pretty placeholder is a placeholder that ships.
private struct NotBuiltYetView: View {
    let label: String

    init(route: Route) { self.label = String(describing: route) }
    init(label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 8) {
            Text("Not built yet").font(CypressFont.screenTitle)
            Text(label).cypressMonoSectionLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
    }
}
