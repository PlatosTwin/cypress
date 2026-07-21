import SwiftUI

/// The composition root's view. The only place that knows how features connect.
///
/// Features push `Route`s and hand out closures for the things that are not navigations (a visit is
/// a camera, a favorite is a mutation). Resolving those in one file is what keeps a feature folder
/// from importing its siblings.
struct RootView: View {

    let data: DataLayer

    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            MapHomeView(api: data.api)
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
                onOpenGrove: { router.sheet = nil }
            )
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

        // Every remaining route has a mocked screen but no built feature yet. Naming them here
        // rather than defaulting means adding one is a compile error, not a silent no-op.
        case .identify, .species, .careLog, .share, .growthHistory, .measure, .outbox:
            NotBuiltYetView(route: route)
        }
    }
}

/// Deliberately plain. A pretty placeholder is a placeholder that ships.
private struct NotBuiltYetView: View {
    let route: Route

    var body: some View {
        VStack(spacing: 8) {
            Text("Not built yet").font(CypressFont.screenTitle)
            Text(String(describing: route)).cypressMonoSectionLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
    }
}
