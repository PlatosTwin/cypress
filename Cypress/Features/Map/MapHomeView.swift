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
//  environment. It pushes `.treeProfile` and `.identify` and constructs no other feature's views.
//

import MapKit
import SwiftUI
import UIKit

struct MapHomeView: View {

    let api: any CypressAPI

    @Environment(AppRouter.self) private var router
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
        .task {
            location.start()
            await model.fetch()
        }
        .onChange(of: location.availability) { _, availability in
            guard !hasCentredOnUser, let coordinate = availability.coordinate else { return }
            hasCentredOnUser = true
            withAnimation(.easeInOut(duration: 0.4)) {
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
                    IdentifyFAB { router.push(.identify) }
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
                // Screen 01's own caption: "gray dash-marked pins are removed trees—memorials,
                // tappable to screen 19". A memorial is a different screen from the profile, not a
                // variant of it, so the branch belongs here rather than inside TreeProfileView.
                router.push(
                    subject.pin.status.isMemorial
                        ? .memorial(subject.pin.id)
                        : .treeProfile(subject.pin.id)
                )
            }
        } else if location.availability.isRefused {
            MapLocationNotice(availability: location.availability) {
                if let url = location.settingsURL { UIApplication.shared.open(url) }
            }
        }
    }

    // MARK: - Behaviour

    /// Tapping a cluster zooms in, which is what the badge means (`TreeCluster`'s own note).
    private func zoom(into cluster: TreeCluster) {
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(MapLayout.zoomedIn(on: cluster, from: region))
        }
    }

    /// C16 is `Map / My Grove / Journal / You`; `AppRouter` names the same four `map / grove /
    /// journal / you`. The bar is the design system's vocabulary and the router is the app's, so
    /// the translation lives here rather than in either of them.
    private var tabBinding: Binding<BottomTabBar.Tab> {
        Binding(
            get: {
                switch router.tab {
                case .map: return .map
                case .grove: return .myGrove
                case .journal: return .journal
                case .you: return .you
                }
            },
            set: { tab in
                switch tab {
                case .map: router.tab = .map
                case .myGrove: router.tab = .grove
                case .journal: router.tab = .journal
                case .you: router.tab = .you
                }
            }
        )
    }
}

// MARK: - Previews
//
// Real seed data, not fixtures: the whole point of screen 01 is that the map is full of the city on
// day one, and a preview drawn from a handful of fake pins would prove nothing. `DataLayer.boot()`
// opens the same bundled 195,309-tree seed the app does.

/// Boots the real data layer, then hands it to whatever the preview wants to draw.
private struct SeededPreview<Content: View>: View {
    @State private var data: DataLayer?
    @State private var failure: String?
    @State private var router = AppRouter()
    @ViewBuilder var content: (DataLayer) -> Content

    var body: some View {
        Group {
            if let data {
                content(data).environment(router)
            } else if let failure {
                Text(failure).font(CypressFont.mono12).padding()
            } else {
                ProgressView()
            }
        }
        .task {
            do { data = try await DataLayer.boot() } catch { failure = String(describing: error) }
        }
    }
}

#Preview("01 · Map home") {
    SeededPreview { data in
        MapHomeView(api: data.api)
    }
}

#Preview("D1 · Map home, dark") {
    SeededPreview { data in
        MapHomeView(api: data.api)
    }
    .preferredColorScheme(.dark)
}

#Preview("01 · Location denied") {
    MapLocationNotice(availability: .denied, onOpenSettings: {})
        .padding(MapLayout.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(CypressColor.surfaceMapPaper)
}

#Preview("01 · Chrome") {
    VStack(alignment: .leading, spacing: CypressSpacing.gapCandidates) {
        MapFilterChips(filter: .constant(.all))
        MapFilterChips(filter: .constant(.inBloom))
        IdentifyFAB {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CypressColor.surfaceMapPaper)
}
