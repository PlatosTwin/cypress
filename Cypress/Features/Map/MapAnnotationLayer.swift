//
//  MapAnnotationLayer.swift
//  Cypress — Features/Map
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  THE ESCAPE HATCH, TAKEN
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  `MapCanvas` (C18) has always said the basemap is replaceable — "tomorrow a `Map { }` from
//  MapKit, or a MapLibre `UIViewRepresentable` if the abstract basemap ever becomes a hard
//  requirement". This is that parameter being used for the reason it was actually put there.
//
//  ── Why the SwiftUI `Map` had to go ──────────────────────────────────────────────────────────
//  Screen 01 drew its markers as SwiftUI `Annotation`s, which means SwiftUI creates and maintains a
//  hosted view hierarchy per marker. ERRATA E130 cut the count from 1,300 to under 300 and measured
//  the map back to 57–60 fps, and that measurement was taken with **location permission declined**,
//  which opens the camera over Mission Dolores Park — a park, in a *street* tree inventory, with
//  ten markers on screen. It was never a measurement of a full screen of pins sitting still.
//
//  With a fix granted, the same build opens over real streets. Measured on an iPhone 16e simulator,
//  nobody touching the glass, camera settled, no location updates arriving and no database read
//  outstanding:
//
//      194 markers, zoom 18, idle      1.2–1.8 fps    worst frame 873 ms    12–18 body passes/sec
//
//  Idle. Twelve to eighteen full rebuilds of the annotation layer per second, of an array that had
//  not changed, with no input of any kind. Three ablations, each built and run: removing the GPS dot
//  annotation changed nothing; disabling the amber pin's `repeatForever` pulse changed nothing;
//  denying location entirely (nine markers) held a flat 60 fps and **zero** body passes. The
//  variable is the number of hosted annotations, and past roughly two hundred of them the layer
//  re-enters itself and never settles.
//
//  ── What replaces it ─────────────────────────────────────────────────────────────────────────
//  An `MKMapView` behind a `UIViewRepresentable`, which is how Google Maps draws far more than we do
//  and stays smooth: markers are `MKAnnotationView`s recycled through
//  `dequeueReusableAnnotationView`, each showing a **bitmap of the C19 pin rendered once per kind**
//  and reused across every marker of that kind. There are seven pin kinds and a badge per distinct
//  cluster count, so a screenful of 280 markers is a handful of images and 280 recycled views.
//
//  Three properties follow, and they are the whole point:
//
//  1. **An update that changes nothing costs nothing.** `updateUIView` diffs the incoming pins
//     against what is on the map by id and adds and removes only the difference. A GPS fix, a
//     re-render of the chrome, a state change anywhere above — none of them touch the annotations.
//  2. **The design is still the design.** The images come from `MapPin` itself, through
//     `ImageRenderer`. Nothing is redrawn by hand in Core Graphics, so a change to C19's tokens
//     still changes the map, and there is no second copy of the pin vocabulary to keep in step.
//  3. **The camera is applied, not bound.** A `Map(position:)` re-applies its position on every
//     pass; here a region is set only when the value the app asked for actually changed, which is
//     what keeps a camera write from becoming a rebuild.
//
//  ── What was deliberately not taken from MapKit ──────────────────────────────────────────────
//  `MKMapView` has its own clustering (`clusteringIdentifier`) and it is not used. This app clusters
//  in SQL, over the whole city, on an absolute grid whose cell size snaps to a whole-degree latitude
//  band so that badges do not re-key on every pan (E130). MapKit's clustering works on the
//  annotations you have already handed it, which is the wrong end of a 195,309-row inventory, and
//  turning it on would put a second, screen-space grid on top of the one the database already
//  applied. The marker budget and its tests are untouched by any of this.
//

import MapKit
import SwiftUI
import UIKit

// MARK: - The annotations

/// One tree. `MKAnnotation` rather than a SwiftUI view, so MapKit can recycle the view drawing it.
final class TreePinAnnotation: NSObject, MKAnnotation {
    let pin: TreePin
    let kind: MapPin.Kind
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(pin: TreePin) {
        self.pin = pin
        self.kind = MapPinKind.kind(for: pin)
        self.coordinate = pin.coordinate.clLocationCoordinate
    }
}

/// One cluster badge. Its `id` is the absolute-grid cell id, which is what keeps a badge stable
/// across a pan (`TreeCluster.id`).
final class TreeClusterAnnotation: NSObject, MKAnnotation {
    let cluster: TreeCluster
    let kind: MapPin.Kind
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(cluster: TreeCluster) {
        self.cluster = cluster
        self.kind = .cluster(count: cluster.count, large: cluster.count >= 10)
        self.coordinate = cluster.coordinate.clLocationCoordinate
    }
}

/// The reader's own dot.
///
/// **It is one annotation whose coordinate is mutated in place**, never removed and re-added, which
/// is the concrete form of "get the GPS dot out of the pin layer": a fix moves this one object and
/// MapKit slides one view. It is `@objc dynamic` because MapKit observes `coordinate` by KVO, which
/// is the mechanism that makes moving it cheap.
final class UserDotAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

// MARK: - The pin bitmaps

/// C19's pins, rasterised once per kind and reused by every marker of that kind.
///
/// **`MapPin` renders itself.** `ImageRenderer` runs the real SwiftUI component, so the fill, the
/// ring, the dashes, the shadow and the 85 % opacity on a memorial all come from the same tokens
/// they always did (ARCHITECTURE §6) — there is no hand-drawn second copy of the pin vocabulary
/// that could drift from the first. The cache key carries the colour scheme because
/// `CypressColor.pinRingStroke` and friends are dynamic.
@MainActor
enum MapPinImage {

    private struct Key: Hashable {
        let kind: MapPin.Kind
        let isDark: Bool
    }

    private static var cache: [Key: UIImage] = [:]

    /// Room around the pin for the shadow C19 gives it. `ImageRenderer` sizes the bitmap to the
    /// view's own bounds and a shadow lives outside those, so without the padding every pin on the
    /// map would lose the soft edge that lifts it off the parchment.
    static let shadowPadding: CGFloat = 6

    static func image(for kind: MapPin.Kind, isDark: Bool) -> UIImage? {
        let key = Key(kind: kind, isDark: isDark)
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(
            content: MapPin(kind)
                .padding(shadowPadding)
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }

    /// Dropped when the colour scheme flips, so the map does not keep drawing the light-mode ring
    /// on a dark basemap. Cluster counts are unbounded in principle, so this is also the only thing
    /// stopping the cache growing without limit over a long session of panning.
    static func flush() {
        cache.removeAll(keepingCapacity: true)
    }
}

// MARK: - The map view

/// The `MKMapView` that draws screen 01's basemap, pins, clusters, GPS dot and parchment wash.
///
/// The parameter list is `MapKitBasemap`'s, unchanged, because this is a swap behind C18's seam and
/// not a redesign of what screen 01 asks a basemap for.
struct MapAnnotationLayer: UIViewRepresentable {

    @Binding var position: MapCameraPosition
    @Binding var region: MKCoordinateRegion
    let clusters: [TreeCluster]
    let pins: [TreePin]
    let userCoordinate: Coordinate?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // "the city reads as street geometry rather than a busy consumer map": no POI pins, no
        // traffic, no 3-D. What is left is the street network and the water, which is what the mock
        // draws. Same three decisions the SwiftUI `.mapStyle` carried, in `MKMapView`'s vocabulary.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration

        // The mock has no zoom, compass or scale control. SCREENS.md 01 lists zoom controls under
        // **NOT SPECIFIED**, so none are added.
        mapView.showsCompass = false
        mapView.showsScale = false
        // **Not `showsUserLocation`.** That would have `MKMapView` open a second `CLLocationManager`
        // of its own, beside `MapLocationProvider`'s — two GPS sessions for one dot, which is the
        // duplication this same round of work just finished removing from the app. The dot is drawn
        // from the coordinate the app already has.
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false

        mapView.register(
            MapMarkerView.self,
            forAnnotationViewWithReuseIdentifier: MapMarkerView.reuseIdentifier
        )

        context.coordinator.installWash(on: mapView, isDark: colorScheme == .dark)
        context.coordinator.lastRequestedPosition = position
        if let initial = position.region {
            mapView.setRegion(initial, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // The closures are re-made every pass and capture the current model, so the coordinator has
        // to be re-pointed at this value or a tap would call into a stale one.
        context.coordinator.parent = self

        let isDark = colorScheme == .dark
        if context.coordinator.isDark != isDark {
            context.coordinator.isDark = isDark
            MapPinImage.flush()
            context.coordinator.installWash(on: mapView, isDark: isDark)
            context.coordinator.refreshAllMarkerImages(on: mapView)
        }

        context.coordinator.applyCameraIfChanged(position, to: mapView)
        context.coordinator.sync(clusters: clusters, pins: pins, on: mapView)
        context.coordinator.syncUserDot(userCoordinate, on: mapView)
        context.coordinator.applySelection(selectedPinID, on: mapView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {

        var parent: MapAnnotationLayer
        var isDark = false

        /// The last camera position the **app asked for**, which is deliberately not the same thing
        /// as the region the map is currently showing.
        ///
        /// **This distinction is the loop.** Screen 01 writes `position` (centring on the first fix,
        /// or a cluster tap) and reads the settled region back out into `region` for the next cluster
        /// tap to measure against. If the applied-camera check compares against *where the map ended
        /// up*, then every settle is a mismatch with what was asked for — MapKit never lands on
        /// exactly the span it was given — so the settle callback writes state, the write re-runs the
        /// body, the body re-applies the camera, and the map re-settles. Forever.
        ///
        /// That is what the SwiftUI `Map(position:)` this replaced was doing: it re-applied its
        /// binding on every pass, and `.onMapCameraChange(frequency: .onEnd)` wrote `region` back.
        /// Measured, idle, camera settled, nothing arriving: 12–18 rebuilds a second that never
        /// stopped. It only ever started once *something* wrote `position`, which on screen 01 is the
        /// one-shot centring on the first GPS fix — so it never happened at all with location
        /// declined, which is how every previous round of measurement was taken.
        ///
        /// Comparing positions rather than regions is exact: a camera is re-applied when, and only
        /// when, the app asks for a different one.
        var lastRequestedPosition: MapCameraPosition?

        private var pinAnnotations: [UUID: TreePinAnnotation] = [:]
        private var clusterAnnotations: [String: TreeClusterAnnotation] = [:]
        private var userDot: UserDotAnnotation?
        private var wash: MKPolygon?
        private var selectedPinID: UUID?

        init(_ parent: MapAnnotationLayer) {
            self.parent = parent
        }

        // MARK: The wash

        /// The mock's `#E9E5D4` paper, as a world-scale polygon above the roads and below every
        /// marker. Everything about *why* it is an overlay rather than a view tint, and why the
        /// alpha is 0.18 and 0.35 rather than something closer to the hex, is unchanged and is
        /// recorded on `MapLayout.washOpacityLight`.
        func installWash(on mapView: MKMapView, isDark: Bool) {
            if let wash { mapView.removeOverlay(wash) }
            let polygon = MKPolygon(coordinates: MapLayout.washRing, count: MapLayout.washRing.count)
            wash = polygon
            mapView.addOverlay(polygon, level: .aboveRoads)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            let colour = isDark ? CypressColor.Dark.bgMap : CypressColor.surfaceMapPaper
            let alpha = isDark ? MapLayout.washOpacityDark : MapLayout.washOpacityLight
            renderer.fillColor = UIColor(colour).withAlphaComponent(alpha)
            renderer.strokeColor = .clear
            renderer.lineWidth = 0
            return renderer
        }

        // MARK: The camera

        func applyCameraIfChanged(_ position: MapCameraPosition, to mapView: MKMapView) {
            guard position != lastRequestedPosition else { return }
            lastRequestedPosition = position
            guard let requested = position.region else { return }
            // Reduce Motion snaps the camera instead of flying it. The zoom is the answer to a tap,
            // not the way the answer is delivered — `CypressMotion.resolved`'s rule, applied at the
            // one place on this screen where a camera actually moves.
            mapView.setRegion(requested, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        /// Continuous, once per frame of a pan — the same cadence
        /// `.onMapCameraChange(frequency: .continuous)` had. `MapModel.cameraDidChange` is what
        /// decides whether any given one of these is worth a database read, and it already ignores
        /// a camera that is still inside the box it fetched.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.onCameraChange(
                BoundingBox(mapView.region),
                MapZoom.level(
                    longitudeDelta: mapView.region.span.longitudeDelta,
                    viewWidth: mapView.bounds.width
                )
            )
        }

        /// The settled region, which is only needed when a cluster is tapped — a cluster cannot be
        /// tapped mid-gesture, so it is read once the camera stops rather than sixty times a second.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Only the echo. Nothing here touches `lastRequestedPosition` — see its note for what
            // happens when the settled region is allowed to stand in for the requested one.
            parent.region = mapView.region
        }

        // MARK: The annotations

        /// Add and remove the difference, and nothing else.
        ///
        /// This is the method the whole file exists for. An update whose pins are the same pins does
        /// no work at all — no view is created, none is destroyed, and MapKit is not told anything.
        func sync(clusters: [TreeCluster], pins: [TreePin], on mapView: MKMapView) {
            var staleClusters: [MKAnnotation] = []
            let wantedClusters = Set(clusters.map(\.id))
            for (id, annotation) in clusterAnnotations where !wantedClusters.contains(id) {
                staleClusters.append(annotation)
                clusterAnnotations[id] = nil
            }
            var freshClusters: [MKAnnotation] = []
            for cluster in clusters where clusterAnnotations[cluster.id] == nil {
                let annotation = TreeClusterAnnotation(cluster: cluster)
                clusterAnnotations[cluster.id] = annotation
                freshClusters.append(annotation)
            }

            var stalePins: [MKAnnotation] = []
            var wanted: [UUID: TreePin] = [:]
            wanted.reserveCapacity(pins.count)
            for pin in pins { wanted[pin.id] = pin }
            for (id, annotation) in pinAnnotations {
                // A tree can also change *kind* under a stable id — a lead confirming a removal
                // turns a green pin grey without moving it — so an id that is still wanted but now
                // draws differently is retired here rather than left showing the old picture.
                guard let pin = wanted[id], MapPinKind.kind(for: pin) == annotation.kind else {
                    stalePins.append(annotation)
                    pinAnnotations[id] = nil
                    continue
                }
            }
            var freshPins: [MKAnnotation] = []
            for pin in pins where pinAnnotations[pin.id] == nil {
                let annotation = TreePinAnnotation(pin: pin)
                pinAnnotations[pin.id] = annotation
                freshPins.append(annotation)
            }

            let stale = staleClusters + stalePins
            let fresh = freshClusters + freshPins
            if !stale.isEmpty { mapView.removeAnnotations(stale) }
            if !fresh.isEmpty { mapView.addAnnotations(fresh) }
        }

        /// The dot moves; it is not rebuilt. See `UserDotAnnotation`.
        func syncUserDot(_ coordinate: Coordinate?, on mapView: MKMapView) {
            guard let coordinate else {
                if let userDot { mapView.removeAnnotation(userDot) }
                userDot = nil
                return
            }
            let next = coordinate.clLocationCoordinate
            if let userDot {
                if userDot.coordinate.latitude != next.latitude
                    || userDot.coordinate.longitude != next.longitude {
                    userDot.coordinate = next
                }
                return
            }
            let dot = UserDotAnnotation(coordinate: next)
            userDot = dot
            mapView.addAnnotation(dot)
        }

        /// A tapped pin grows a little so the card and the pin read as one selection
        /// (`MapLayout.selectedPinScale`). Only the two views that change are touched — the one
        /// letting go of the selection and the one taking it — which is the point E130 made when it
        /// hoisted the selected pin out of the `ForEach` and is kept here.
        func applySelection(_ id: UUID?, on mapView: MKMapView) {
            guard id != selectedPinID else { return }
            let previous = selectedPinID
            selectedPinID = id
            for changed in [previous, id].compactMap({ $0 }) {
                guard let annotation = pinAnnotations[changed],
                      let view = mapView.view(for: annotation) as? MapMarkerView else { continue }
                view.setSelectedAppearance(changed == id)
            }
        }

        func refreshAllMarkerImages(on mapView: MKMapView) {
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) as? MapMarkerView else { continue }
                view.apply(annotation: annotation, isDark: isDark)
            }
        }

        // MARK: Views and taps

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is TreePinAnnotation
                    || annotation is TreeClusterAnnotation
                    || annotation is UserDotAnnotation
            else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MapMarkerView.reuseIdentifier,
                for: annotation
            ) as? MapMarkerView
            view?.apply(annotation: annotation, isDark: isDark)
            if let pin = annotation as? TreePinAnnotation {
                view?.setSelectedAppearance(pin.pin.id == selectedPinID)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // MapKit's own selection is used only as a tap signal. The app decides what a selected
            // pin looks like and holds that state in `MapModel`, so the map view is told to let go
            // immediately — otherwise two things would believe they own the selection and the
            // second tap that closes the card would not reach us.
            defer { mapView.deselectAnnotation(view.annotation, animated: false) }
            if let pin = view.annotation as? TreePinAnnotation {
                parent.onSelectPin(pin.pin)
            } else if let cluster = view.annotation as? TreeClusterAnnotation {
                parent.onSelectCluster(cluster.cluster)
            }
        }
    }
}

// MARK: - The marker view

/// One recycled marker. Carries a cached bitmap of a C19 pin and, for the amber one, the ring that
/// breathes.
final class MapMarkerView: MKAnnotationView {

    static let reuseIdentifier = "cypress.marker"

    private var pulseLayer: CALayer?

    /// The 44 pt hit target every control in this app carries (ARCHITECTURE §6, SCREENS.md §5 gap
    /// 12). A drawn pin is 16–18 pt, so without this the tap target would shrink to the bitmap and
    /// the map would become the one screen in the app that does not meet its own rule.
    private static let hitTarget = CypressSpacing.minTapTarget

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let target = Self.hitTarget
        let box = bounds.insetBy(
            dx: min(0, (bounds.width - target) / 2),
            dy: min(0, (bounds.height - target) / 2)
        )
        return box.contains(point)
    }

    @MainActor
    func apply(annotation: MKAnnotation, isDark: Bool) {
        let kind: MapPin.Kind
        switch annotation {
        case let pin as TreePinAnnotation: kind = pin.kind
        case let cluster as TreeClusterAnnotation: kind = cluster.kind
        case is UserDotAnnotation: kind = .gps
        default: return
        }
        image = MapPinImage.image(for: kind, isDark: isDark)
        // The reader's dot belongs under every tree, and a cluster badge over them. `MKAnnotation`
        // has no z-order of its own; `displayPriority` and `zPriority` are what MapKit reads.
        zPriority = annotation is UserDotAnnotation ? .min : .defaultUnselected
        displayPriority = .required
        isEnabled = !(annotation is UserDotAnnotation)
        applyAccessibility(for: annotation)
        setPulsing(kind == .needsCare)
    }

    private func applyAccessibility(for annotation: MKAnnotation) {
        isAccessibilityElement = true
        switch annotation {
        case let pin as TreePinAnnotation:
            // C19 has no pin for a vacant site and `MapPinKind` says the honest thing for one
            // instead of borrowing a memorial's words (ERRATA E107). Same override, same reason.
            accessibilityLabel = MapPinKind.accessibilityLabel(for: pin.pin)
            accessibilityTraits = .button
        case let cluster as TreeClusterAnnotation:
            accessibilityLabel = cluster.kind.accessibilityLabel
            accessibilityTraits = .button
        default:
            accessibilityLabel = MapPin.Kind.gps.accessibilityLabel
            accessibilityTraits = .none
        }
    }

    /// `MapLayout.selectedPinScale`, as a transform on one recycled view.
    func setSelectedAppearance(_ isSelected: Bool) {
        let scale = isSelected ? MapLayout.selectedPinScale : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    /// **czPulse**, on the amber pin and nothing else — "reserved solely for 'this tree needs
    /// something'" (SCREENS.md §1.1).
    ///
    /// A bitmap cannot breathe, so the ring is a `CALayer` with the same 2.4 s ease-in-out the
    /// SwiftUI modifier runs (`CypressMotion.Duration.pulse`) and the same spread and opacity
    /// tokens. It is a layer animation rather than a view one, which means it runs on the render
    /// server and costs the main thread nothing per frame — the opposite of the `repeatForever`
    /// SwiftUI transaction it replaces.
    private func setPulsing(_ isPulsing: Bool) {
        guard isPulsing else {
            pulseLayer?.removeFromSuperlayer()
            pulseLayer = nil
            return
        }
        guard pulseLayer == nil else { return }
        let diameter = MapPin.Kind.needsCare.diameter + CypressMotionOffset.pulseSpread * 2
        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.cornerRadius = diameter / 2
        ring.backgroundColor = UIColor(CypressColor.accentAmber).cgColor
        ring.opacity = 0
        ring.zPosition = -1

        if !UIAccessibility.isReduceMotionEnabled {
            let group = CAAnimationGroup()
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.55
            scale.toValue = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = CypressMotionOffset.pulseOpacity
            fade.toValue = 0
            group.animations = [scale, fade]
            group.duration = CypressMotion.Duration.pulse / 2
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(group, forKey: "cypressPulse")
        } else {
            // Reduce Motion gets the halfway state the SwiftUI modifier settles on, still rather
            // than breathing.
            ring.opacity = Float(CypressMotionOffset.pulseOpacity / 2)
        }

        layer.addSublayer(ring)
        pulseLayer = ring
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pulseLayer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        pulseLayer?.removeFromSuperlayer()
        pulseLayer = nil
    }
}
