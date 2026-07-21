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

        // Every remaining route has a mocked screen but no built feature yet. Naming them here
        // rather than defaulting means adding one is a compile error, not a silent no-op.
        case .identify, .species, .careLog, .share, .growthHistory, .report, .measure, .outbox:
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
