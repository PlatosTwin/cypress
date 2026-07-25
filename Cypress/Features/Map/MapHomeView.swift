//
//  MapHomeView.swift
//  Cypress — Features/Map
//
//  Screen 01 · Map home. "The default screen — look around a map that is already full of the
//  city's trees."
//
//  Composition, back to front, exactly as SCREENS.md 01 lists it:
//
//      MapCanvas
//        ├── basemap: MapKitBasemap   — MapKit, the parchment wash, pins, clusters, the GPS dot
//        └── overlay: the chrome      — search bar, filter chips, FAB, tree card
//      BottomTabBar (C16), Map active
//
//  The frame is full-bleed: "no 62px status padding — content is absolutely positioned below the
//  notch". So the canvas ignores the safe area and the chrome is inset by the real one, measured
//  once at the root rather than assumed.
//
//  This view owns one `@Observable MapModel` (ARCHITECTURE §3) and reads `AppRouter` from the
//  environment. It pushes `.treeProfile`, presents `.identify`, and constructs no other feature's
//  views.
//

import MapKit
import SwiftUI
import UIKit

struct MapHomeView: View {

    let api: any CypressAPI

    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: MapModel
    @State private var location = MapLocationProvider()
    @State private var position: MapCameraPosition = .region(MapLayout.region(around: MapLayout.defaultCentre))
    /// The last region MapKit reported, so a cluster tap knows what "two zoom levels in" means.
    @State private var region = MapLayout.region(around: MapLayout.defaultCentre)
    /// One-shot: the first fix recentres the map, later ones must not yank it out from under a pan.
    @State private var hasCentredOnUser = false

    init(api: any CypressAPI) {
        self.api = api
        _model = State(initialValue: MapModel(api: api))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MapCanvas(
                    basemap: { basemap },
                    overlay: { chrome(topInset: proxy.safeAreaInsets.top) }
                )
                BottomTabBar(selection: tabBinding)
            }
            .ignoresSafeArea()
        }
        .background(CypressColor.surfaceScreen)
        // **01 is full-bleed and was not.** `RootView` wraps every tab root in a `NavigationStack`,
        // so a root that does not opt out inherits an empty navigation bar — here an opaque 44pt
        // band under a 47pt status area, 91pt of nothing above a screen whose own spec says "no
        // 62px status padding — content is absolutely positioned below the notch". Sixteen other
        // screens carry this modifier; this one, the app's default screen, did not, and it built
        // green and passed the whole suite that way (ERRATA E110).
        //
        // It is load-bearing twice over: with the bar present `proxy.safeAreaInsets.top` reads **0**
        // — measured on device, not assumed — so `topInset + searchTopInset` put the search bar 8pt
        // below the *bar* instead of 8pt below the status bar, which is what `searchTopInset`'s own
        // note says it is for. Hiding the bar restores the inset the arithmetic was written for
        // rather than adding to a number that was compensating for anything.
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            location.start()
            #if DEBUG
            // Off unless `CYPRESS_MAP_PROBE=1` is in the environment. See `MapFrameProbe`.
            MapFrameProbe.shared.start()
            #endif
            await model.fetch()
        }
        #if DEBUG
        .onChange(of: model.content) { _, content in
            MapFrameProbe.shared.note(markers: content.markerCount, zoom: model.viewport?.zoom ?? 0)
        }
        #endif
        .onChange(of: location.availability) { _, availability in
            guard !hasCentredOnUser, let coordinate = availability.coordinate else { return }
            hasCentredOnUser = true
            withAnimation(CypressMotion.resolved(CypressMotion.camera, reduceMotion: reduceMotion)) {
                position = .region(MapLayout.region(around: coordinate))
            }
        }
        .onDisappear { location.stop() }
    }

    // MARK: - Basemap

    private var basemap: some View {
        MapKitBasemap(
            position: $position,
            region: $region,
            clusters: model.clusters,
            pins: model.pins,
            userCoordinate: location.availability.coordinate,
            selectedPinID: model.selectedPinID,
            onCameraChange: { bounds, zoom in
                model.cameraDidChange(bounds: bounds, zoom: zoom)
            },
            onSelectPin: { model.select($0) },
            onSelectCluster: zoom(into:)
        )
    }

    // MARK: - Overlay

    @ViewBuilder
    private func chrome(topInset: CGFloat) -> some View {
        @Bindable var model = model

        // Two absolutely positioned blocks, exactly as 01 describes them — a `Spacer` between them
        // would make the whole overlay one greedy stack, and a greedy stack inside `MapCanvas`'s
        // ZStack sizes against the map rather than against the screen.
        Color.clear
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: MapLayout.chipRowTop) {
                    SearchBar(text: $model.searchText)
                    MapFilterChips(filter: $model.filter)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MapLayout.sideInset)
                .padding(.top, topInset + MapLayout.searchTopInset)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .trailing, spacing: 0) {
                    // `present`, not `push` (ERRATA E127). The visit flow is a `fullScreenCover` off
                    // `AppRouter.sheet` — `RootView.destination(for:)` answers a *pushed* `.identify`
                    // with `NotBuiltYetView`, because a pushed one is a programming error the way a
                    // pushed `.share` is. So the app's one specified entrance to screen 02 landed on
                    // "Not built yet", which is also the only way to reach "add this tree".
                    IdentifyFAB { router.present(.identify(nil)) }
                        .padding(.horizontal, MapLayout.sideInset - MapLayout.cardInset)
                        .padding(.bottom, MapLayout.fabToCardGap)
                    bottomSlot
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, MapLayout.cardInset)
                .padding(.bottom, MapLayout.tabBarHeight + MapLayout.cardToTabBarGap)
            }
    }

    /// One slot, three possible occupants, in priority order: the selected tree, the location
    /// refusal, or nothing at all. Only one of them can be true at a time and only one is drawn.
    ///
    /// The card arrives with no transition on purpose. SCREENS.md 01 documents none, and the
    /// slide-and-fade this had first left the card stranded at half opacity below the tab bar —
    /// SwiftUI will not settle an insertion transition inside an overlay that the `Map` behind it
    /// keeps invalidating. A tap that answers instantly is better than one that answers prettily.
    @ViewBuilder
    private var bottomSlot: some View {
        if let subject = model.selection {
            MapTreeCard(subject: subject, userCoordinate: location.availability.coordinate) {
                router.push(MapHomeView.route(for: subject.pin))
            }
        } else if location.availability.isRefused {
            MapLocationNotice(availability: location.availability) {
                if let url = location.settingsURL { UIApplication.shared.open(url) }
            }
        }
    }

    // MARK: - Behaviour

    /// What a tap on the bottom card opens.
    ///
    /// Three destinations, and the branch belongs here rather than inside `TreeProfileView` because
    /// two of the three are different screens rather than variants of the profile:
    ///
    /// - **A removed tree opens 19.** Screen 01's own caption draws this entrance: "gray
    ///   dash-marked pins are removed trees—memorials, tappable to screen 19".
    /// - **A vacant site opens the site screen.** No mock draws it; ERRATA E107 decides it, closing
    ///   E11. This is the same reasoning one step further — a memorial is a tree that is gone, and a
    ///   site never had one, so it is not a profile with fields missing either. `TreePin.status` is
    ///   known the instant the pin is drawn, so the branch costs no read.
    /// - **Everything else opens 03**, which picks its own cold variant.
    ///
    /// A `static` function on the view rather than a property on `MapCardSubject`: the subject is
    /// what the card *draws*, and `Route` is the app's navigation vocabulary — keeping them apart is
    /// what lets the presentation type stay free of the router.
    static func route(for pin: TreePin) -> Route {
        if pin.status == .vacantSite { return .site(pin.id) }
        if pin.status.isMemorial { return .memorial(pin.id) }
        return .treeProfile(pin.id)
    }

    /// Tapping a cluster zooms in, which is what the badge means (`TreeCluster`'s own note).
    private func zoom(into cluster: TreeCluster) {
        // Reduce Motion snaps the camera instead of flying it. The zoom is the answer to the tap,
        // not the way the answer is delivered.
        withAnimation(CypressMotion.resolved(CypressMotion.camera, reduceMotion: reduceMotion)) {
            position = .region(MapLayout.zoomedIn(on: cluster, from: region))
        }
    }

    /// C16 speaks `Map / My Grove / Journal / You` and `AppRouter` speaks `map / grove / journal /
    /// you`. The translation is `AppRouter.bottomTabSelection`, shared by all four tab roots — it
    /// used to be written out once per root, which is three copies of one mapping.
    private var tabBinding: Binding<BottomTabBar.Tab> { router.bottomTabSelection }
}
