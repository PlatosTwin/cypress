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
//     pass; here a region is set only when the app makes a new request, which is what keeps a camera
//     write from becoming a rebuild. "New" is a ticket rather than a different-looking camera, and
//     ERRATA E140 is the record of why nothing weaker works: an update pass can arrive carrying
//     state from before the reader's last gesture, so a camera that merely *looks* new may be one
//     the reader has already moved away from. See `MapCameraRequest`.
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
    /// What VoiceOver says. Computed here rather than in the view because it depends on the palette,
    /// and the palette is a fact about the screenful rather than about this tree.
    ///
    /// **It is a `var`, and that is the fix rather than an affordance.** The species *name* arrives
    /// after the palette that ranked it — `MapModel.resolveSpeciesNamesForPalette` reads the catalogue
    /// asynchronously — and a name arriving does not change any pin's `kind`, so `Coordinator.sync`'s
    /// kind comparison correctly leaves every annotation in place. Stored once at init, the label
    /// would therefore have said `City tree` for the whole life of the pin and the spoken channel
    /// would never have named a species at all. `refreshSpokenLabel(palette:)` is called from the same
    /// pass that would have retired it.
    private(set) var spokenLabel: String
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(pin: TreePin, palette: MapSpeciesPalette = .empty) {
        self.pin = pin
        self.kind = MapPinKind.kind(for: pin, palette: palette)
        self.spokenLabel = MapPinKind.accessibilityLabel(for: pin, palette: palette)
        self.coordinate = pin.coordinate.clLocationCoordinate
    }

    /// Recomputes the spoken label against the palette that is live now.
    ///
    /// Returns whether it moved, so the caller can leave a marker view alone in the overwhelmingly
    /// common case where nothing was learnt about this tree's species since the last pass.
    @discardableResult
    func refreshSpokenLabel(palette: MapSpeciesPalette) -> Bool {
        let next = MapPinKind.accessibilityLabel(for: pin, palette: palette)
        guard next != spokenLabel else { return false }
        spokenLabel = next
        return true
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
/// ── The species colouring is a *bounded* addition to this, which is the whole design of it ────
/// Task #80 asks for a colour per species and the seed has 569 of them. Keying this cache on a
/// species would make "once per kind" into "once per species per appearance" — 1,138 rasterised
/// SwiftUI views, past the 256-entry ceiling below, so the cache would spend a long session
/// thrashing its own `removeAll` and re-rendering pins during pans. That is not a slower version of
/// the MapKit swap; it is the defect the swap was made to fix, reintroduced.
///
/// So the key is a **slot**, and there are four (`MapSpeciesSlot`). The fixed pin vocabulary is 8
/// kinds today and 12 after this change; in both appearances that is **16 cached bitmaps before,
/// 24 after**, and the number does not move with the species count, the pin count or the length of
/// the session. Cluster badges are still one per distinct count, unchanged, and selection adds none
/// at all — it is a `CALayer` (see `MapMarkerView.setSelectedAppearance`).
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

    /// A ceiling, because one of the keys is unbounded: a cluster badge is keyed on its **count**,
    /// and a long session of panning the whole city produces arbitrarily many distinct counts. Seven
    /// pin kinds in two appearances is fourteen entries before a single badge, and a screenful of
    /// badges is a few dozen more, so this is generous for the drawing and still a bound. When it is
    /// reached the cache is emptied rather than evicted one at a time: the working set on any one
    /// screen is small and re-rendering it costs a few milliseconds once, where an LRU here would be
    /// bookkeeping nobody has measured a need for.
    static let capacity = 256

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
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }

    /// How many bitmaps are held right now.
    ///
    /// Exposed for `MapSpeciesColourTests`, which asserts the number rather than the argument: "the
    /// species colouring is bounded" is a sentence, and this is the thing that makes it a test. It is
    /// the one property of this cache that a future change can quietly destroy.
    static var count: Int { cache.count }

    /// Dropped when the colour scheme flips, so the map does not keep drawing the light-mode ring
    /// on a dark basemap. Cluster counts are unbounded in principle, so this is also the only thing
    /// stopping the cache growing without limit over a long session of panning.
    static func flush() {
        cache.removeAll(keepingCapacity: true)
    }
}

// MARK: - The map view

/// An `MKMapView` that says when it first has an area to draw in.
///
/// **A `UIViewRepresentable` has no layout hook, and this one needs exactly one** (ERRATA E168).
/// `makeUIView` and the `updateUIView` passes around it can all run while the view is still
/// `bounds == .zero`, and a camera cannot be aimed at a map with no area — so the opening camera has
/// to wait for a size. Waiting is safe only if something wakes the layer when the size arrives:
/// screen 01 re-runs its body 240 times a second and would have produced another pass on its own,
/// but the two other screens that draw this basemap are quiet, and a quiet screen would have sat on
/// MapKit's default region forever.
///
/// One callback, fired once, then released. It is not a general layout observer and must not become
/// one — everything else this file does is driven by `updateUIView`, and it stays that way.
///
/// **The callback is delivered *after* the layout pass, not inside it — but not for the reason this
/// note used to give.** The first fix for E168 claimed that "a `setRegion` made from inside a layout
/// pass is performed but never reported", and that is false. Measured on a cold launch with the aim
/// arriving from `updateUIView`, `regionDidChangeAnimated` was delivered every time, in the same
/// millisecond as the `setRegion` that caused it, carrying exactly the right region. What was
/// actually losing the camera is where the *write* happened, not whether the callback arrived — see
/// `Coordinator.echo(_:)`, which is where E168's real mechanism is recorded.
///
/// The hop is kept anyway, on a narrower claim: driving a map's camera from inside its own
/// `layoutSubviews` is a re-entrant geometry change on a view that is mid-layout, and one runloop
/// turn costs a frame nobody can see.
///
/// **Be honest about what this hook does on screen 01: nothing.** Measured on every launch traced,
/// it loses the race to `updateUIView` and its `applyCameraIfChanged` is a `REJECT` of a ticket
/// already spent. Removing the hop, or the whole hook, changes no observable behaviour there and no
/// test — that was built and run, both ways. Do not read the paragraphs above as a description of
/// something that fires.
///
/// **What it is actually for, since `mapViewDidChangeVisibleRegion` was gated.** That callback now
/// refuses to report a camera until this layer has aimed the map once, because an unaimed map
/// reports MapKit's default and screen 16's pin follows it (see `Coordinator`'s note there, and the
/// 2,300 km pin). With that gate in place, a map that is never aimed never reports anything at all:
/// screen 01 would fetch no trees and the pin would never track. This hook is the guarantee that the
/// aim always arrives, on any screen, however quiet. That is a real job and it is the only one it
/// has — it is no longer speculative insurance, and it is no longer about the region echo.
final class AimableMapView: MKMapView {
    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard onFirstLayout != nil, !bounds.isEmpty else { return }
        let announce = onFirstLayout
        onFirstLayout = nil
        DispatchQueue.main.async { announce?() }
    }
}

/// The `MKMapView` that draws screen 01's basemap, pins, clusters, GPS dot and parchment wash.
///
/// The parameter list is `MapKitBasemap`'s, unchanged, because this is a swap behind C18's seam and
/// not a redesign of what screen 01 asks a basemap for.
struct MapAnnotationLayer: UIViewRepresentable {

    @Binding var position: MapCameraRequest
    @Binding var region: MKCoordinateRegion
    let clusters: [TreeCluster]
    let pins: [TreePin]
    /// The four colour slots, as `MapModel` ranked them over exactly these pins.
    var speciesPalette: MapSpeciesPalette = .empty
    let userCoordinate: Coordinate?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Whether this map view has an area to aim a camera at. See `AimableMapView` and E168.
    static func canAim(_ mapView: MKMapView) -> Bool { !mapView.bounds.isEmpty }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = AimableMapView()
        mapView.delegate = context.coordinator
        mapView.onFirstLayout = { [weak mapView] in
            guard let mapView else { return }
            // Whatever the app wants **now**, not whatever it wanted when the view was made. Between
            // those two moments the first GPS fix can land, and on a cold launch it usually does.
            context.coordinator.aimAtCurrentRequest(mapView)
        }

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
        // **The opening camera is *not* applied here any more, and this is ERRATA E168 — the whole
        // of why the app opened on Mission Dolores Park with a perfect GPS fix in hand.**
        //
        // A freshly constructed `MKMapView()` has `bounds == .zero`; SwiftUI lays it out afterwards.
        // `setRegion` on a map view with no area does not take — measured, on this screen, at launch:
        // the region set to 37.7596 read back as **37.3346**, MapKit's own default. What it does do
        // is leave MapKit holding the request, to be applied when the view finally has a size.
        //
        // Both halves of that were fatal. The ticket was recorded as applied when it had not been, so
        // the moment the first GPS fix minted the *next* request the layer had already burnt its
        // number and every later pass was dropped as stale — `REJECT seq=1 applied=1`, forever, with
        // no retry, because `MapHomeView.hasCentredOnUser` is a one-shot and had already fired. And
        // the region MapKit was holding was then applied *after* the fly-to that did get through, so
        // even the pass that reached the map was overwritten by an opening camera from before it.
        //
        // So nothing is applied until there is a map to apply it to. `applyCameraIfChanged` refuses a
        // view with no area without spending the ticket, and the first laid-out pass drives the
        // camera to whatever the app wants **by then** — the remembered opening camera if no fix has
        // landed, the reader's own location if one has. Either order arrives at the same place.
        return mapView
    }

    /// **An `MKMapView` has to be taken down, not just dropped.**
    ///
    /// It is a far heavier object than the SwiftUI `Map` it replaced looked like from the outside:
    /// its own tile cache, its own rendering stack, its own GPU resources. Screen 01 is stood up and
    /// discarded dozens of times in a row by the screenshot suites (`ScreenSweepShots`,
    /// `DynamicTypeScreenshotTests` — twenty-one screens in four appearances each), and without this
    /// the test process was **killed by the system partway through the sweep**: not an assertion
    /// failure, `signal kill`, which is what running out of memory looks like from the outside.
    ///
    /// Clearing the annotations and overlays and dropping the delegate is what lets each one go when
    /// the view that owned it does.
    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        (mapView as? AimableMapView)?.onFirstLayout = nil
        mapView.delegate = nil
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
        coordinator.forget()
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
        context.coordinator.sync(
            clusters: clusters,
            pins: pins,
            palette: speciesPalette,
            on: mapView
        )
        context.coordinator.syncUserDot(userCoordinate, on: mapView)
        context.coordinator.applySelection(selectedPinID, on: mapView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {

        var parent: MapAnnotationLayer
        var isDark = false

        /// The ticket of the last camera the app asked for **and this layer applied**.
        ///
        /// **The number, not the camera, is what makes this safe.** The check it feeds used to
        /// compare the incoming `MapCameraPosition` against the last one applied, and no comparison
        /// of camera *values* can work here: `updateUIView` arrives carrying state as it was when
        /// some earlier body pass ran, screen 01 runs 240 of those a second, and so a pan is always
        /// overtaken by an in-flight value holding the camera from before it. That value differs from
        /// anything the settle handler records, is taken for a fresh request, and drives the map back
        /// to where the reader just moved it away from. That is ERRATA E140, and it is why the map
        /// could not be moved off the reader's own location.
        ///
        /// A ticket cannot be faked by staleness. A stale value carries a number already applied and
        /// is dropped; only `MapCameraRequest.move(to:)` mints a higher one. See `MapCameraRequest`.
        var appliedSequence: Int?

        private var pinAnnotations: [UUID: TreePinAnnotation] = [:]
        private var clusterAnnotations: [String: TreeClusterAnnotation] = [:]
        private var userDot: UserDotAnnotation?

        /// The palette the annotations on the map were last labelled against.
        ///
        /// **The gate that keeps "an update that changes nothing costs nothing" true.** Refreshing a
        /// pin's spoken label means building a string per pin, and screen 01 runs 240 body passes a
        /// second at rest (E139) — so doing it unconditionally would be ~70,000 string constructions a
        /// second on a 292-pin screenful, in a file whose first promise is that an update whose pins are
        /// the same pins does no work at all. A palette that has not moved cannot have changed a label,
        /// and on the two other screens that draw this basemap the palette is always `.empty`, so the
        /// loop below never runs there at all.
        ///
        /// **This is not a precaution, it is a fix for a measured regression.** Written without the
        /// gate, the extra per-pass work on screen 16's basemap was enough to put
        /// `DeepLinkVoiceOverTests.testThePinSaysWhenItHasGoneAsFarAsItGoes` red three runs out of
        /// three — fifteen 5 m nudges landing the pin at 74 m instead of 75, because that screen reads
        /// the pin's position off the settled MapKit camera and the camera settles differently when the
        /// pass costs more. The same test is green two runs out of two with the gate, and green on
        /// `cc01e32`. A test about a *nudge* is what noticed; nothing about a species colour did.
        private var appliedPalette: MapSpeciesPalette = .empty
        private var wash: MKPolygon?
        private var selectedPinID: UUID?

        init(_ parent: MapAnnotationLayer) {
            self.parent = parent
        }

        /// Drops everything the coordinator is holding on behalf of a map view that is going away.
        /// See `dismantleUIView`.
        func forget() {
            pinAnnotations.removeAll()
            clusterAnnotations.removeAll()
            userDot = nil
            wash = nil
            appliedSequence = nil
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

        /// **Applies a camera the app asked for, once, and never a camera it did not ask for.**
        ///
        /// The whole check is the ticket. It is deliberately not a comparison of where the map is
        /// against where the app wants it: `updateUIView` can arrive holding state from before the
        /// reader's last gesture, and on screen 01 it reliably does, so any answer derived from the
        /// geometry of a stale request is the wrong answer. See `MapCameraRequest` for the
        /// measurement, and ERRATA E140 for what it cost.
        func applyCameraIfChanged(_ request: MapCameraRequest, to mapView: MKMapView) {
            // **A map with no area cannot be aimed, and pretending otherwise spends the ticket
            // (ERRATA E168).** This is the *only* condition under which a request is passed over
            // without being recorded: it has not been superseded, it has not been applied, and
            // `AimableMapView.onFirstLayout` will bring it back the moment there is a map for it.
            // Every other early return here is a camera the reader has already moved away from;
            // this one is a camera nobody has been shown yet.
            guard MapAnnotationLayer.canAim(mapView) else { return }
            if let applied = appliedSequence, request.sequence <= applied { return }
            appliedSequence = request.sequence
            // Reduce Motion snaps the camera instead of flying it. The zoom is the answer to a tap,
            // not the way the answer is delivered — `CypressMotion.resolved`'s rule, applied at the
            // one place on this screen where a camera actually moves.
            mapView.setRegion(request.region, animated: !UIAccessibility.isReduceMotionEnabled)
            // **What we just asked for, told to the screen out of band** (ERRATA E168).
            //
            // `regionDidChangeAnimated` is the authority on where the camera *ended up* and refines
            // this a moment later. This write exists because the settle is not guaranteed to be an
            // event the screen can hear — see `echo(_:)`, which is where the whole mechanism is
            // explained and why neither writer may assign `parent.region` directly.
            //
            // This drives nothing. `region` is read to size a cluster zoom, to answer "is the map on
            // the reader" and to remember where they left it — never to move the camera — so writing
            // it here cannot recreate E140.
            echo(request.region)
        }

        /// **Hands a camera back to the screen, one runloop turn later — never inline.**
        ///
        /// This is ERRATA E168, and the mechanism is not the one the first fix for it described.
        ///
        /// Both writers of `MapHomeView.region` — the line above and `regionDidChangeAnimated` —
        /// can run *inside a SwiftUI view-update pass*, because `applyCameraIfChanged` is called
        /// from `updateUIView` and `MKMapView.setRegion` delivers its settle **synchronously** from
        /// within that call. A `@State` write made during a view update is discarded by SwiftUI, so
        /// both of them were writing into a value that stayed exactly as it was.
        ///
        /// Measured on a cold launch, iPhone 16 Pro, static fix at 37.7599, −122.4148 — the probe
        /// trace this note is written from, timestamps in milliseconds:
        ///
        ///     .857  settle region=37.132840 span=97.992432   ← outside the pass. Lands.
        ///     .870  apply  ACCEPT seq=0 to=37.759600         ← from updateUIView
        ///     .870  settle region=37.759600 span=0.002084    ← same millisecond: synchronous
        ///     .871  apply  WROTE parent.region=37.759600 readback=37.132840
        ///     .909  apply  ACCEPT seq=1 to=37.759900         ← the fly-to-you, from updateUIView
        ///     .915  settle region=37.759900 span=0.002084    ← delivered
        ///     .916  apply  WROTE parent.region=37.759900 readback=37.132840
        ///
        /// Two things in that trace overturn what this file used to say. **The settle is delivered** —
        /// twice, carrying exactly the right region — so "a `setRegion` made from inside a layout
        /// pass is performed but never reported" was never the fault. And the one write that *did*
        /// land is the one at `.857`, the only one made outside an update pass. What the screen was
        /// left holding, 37.1328 −95.7856 at a span of 98°, is the continental United States: MapKit's
        /// own default, read back off a map that had not been aimed yet, sitting behind a map of
        /// Folsom Street with the reader's dot in the middle of it.
        ///
        /// One hop through the main queue makes the write an ordinary event again. It is used by
        /// **both** writers rather than only the one that is known to be unsafe today: the settle is
        /// synchronous under `setRegion` and asynchronous after a real flight, and a value whose
        /// safety depends on which of those happened is a value that will be wrong again.
        ///
        /// The lag is one turn, and nothing reads `region` on a deadline: a cluster tap sizes "two
        /// zoom levels in" from it, `MapRecentre` asks it whether the map is on the reader, and
        /// `MapCameraMemory` writes it down when the reader leaves.
        private func echo(_ region: MKCoordinateRegion) {
            DispatchQueue.main.async { [weak self] in self?.parent.region = region }
        }

        /// The map has just been given a size. Aim it at whatever the app is asking for now.
        ///
        /// Not at whatever it was asking for when `makeUIView` ran: the first GPS fix lands in that
        /// window on a cold launch, and the request it minted is the one the reader is owed. See
        /// `AimableMapView` and ERRATA E168.
        func aimAtCurrentRequest(_ mapView: MKMapView) {
            applyCameraIfChanged(parent.position, to: mapView)
        }

        /// Continuous, once per frame of a pan — the same cadence
        /// `.onMapCameraChange(frequency: .continuous)` had. `MapModel.cameraDidChange` is what
        /// decides whether any given one of these is worth a database read, and it already ignores
        /// a camera that is still inside the box it fetched.
        ///
        /// **Silent until this layer has aimed the map at least once, and that is not a nicety —
        /// it is a pin 2,300 km from the tree it belongs to** (ERRATA E168).
        ///
        /// The E168 fix stopped `makeUIView` setting a region and made `applyCameraIfChanged` refuse
        /// a map with no area. Both are right, and together they open a window that did not exist
        /// before: between construction and the first laid-out pass the map has never been aimed, and
        /// what it reports as its visible region in that window is **MapKit's own default** — 37.1328,
        /// −95.7856, a span of 98°, the continental United States.
        ///
        /// This callback fires in that window. On screen 01 it cost only a wasted fetch over a
        /// bounding box the size of North America. On screen 16 it is load-bearing in the worst way:
        /// `VisitPinAdjustView` follows this callback directly — `pin = VisitPinAdjust.centre(of:
        /// box)`, the midpoint of the reported region — so the pin the contributor is about to attach
        /// to a real tree was being dragged to the middle of Kansas before they touched anything.
        /// Measured: the pin read `2344980 m east of where you are standing`, against a great-circle
        /// distance of 2,343,915 m from the fix to MapKit's default centre. A 0.05 % match is an
        /// identification, not a coincidence.
        ///
        /// `appliedSequence` is exactly the question "has this layer ever aimed this map", so it is
        /// the honest gate. The contract of this callback is *the app moved the camera, here is where
        /// it is now*; a camera nobody asked for has no business being reported through it. Nothing is
        /// lost by waiting, because `AimableMapView.onFirstLayout` guarantees the aim arrives — which
        /// is the job that hook now has, and the only one it does.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard appliedSequence != nil else { return }
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
        ///
        /// **A settle says nothing about the camera any more, and that is the fix for E140.** This
        /// used to answer a reader's pan by clearing the record of the last camera the app asked for,
        /// so that pressing the recentre control a second time was not swallowed as a duplicate value
        /// (#66). Clearing it meant the next `updateUIView` — one of about 240 a second — found a
        /// position that did not match an empty record, took that for a fresh request, and drove the
        /// camera back to the reader's own location. The map could not be moved. A press now mints
        /// its own ticket whether or not it names the same place, so the second press works without
        /// this handler having any opinion about the camera at all.
        ///
        /// **Through `echo(_:)`, not by assignment.** MapKit delivers this synchronously from inside
        /// `setRegion`, which this file calls from `updateUIView`, so a direct write lands in the
        /// middle of a SwiftUI view update and is discarded. See `echo(_:)` and ERRATA E168.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            echo(mapView.region)
        }

        // MARK: The annotations

        /// Add and remove the difference, and nothing else.
        ///
        /// This is the method the whole file exists for. An update whose pins are the same pins does
        /// no work at all — no view is created, none is destroyed, and MapKit is not told anything.
        func sync(
            clusters: [TreeCluster],
            pins: [TreePin],
            palette: MapSpeciesPalette,
            on mapView: MKMapView
        ) {
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

            let paletteMoved = palette != appliedPalette
            appliedPalette = palette

            var stalePins: [MKAnnotation] = []
            var wanted: [UUID: TreePin] = [:]
            wanted.reserveCapacity(pins.count)
            for pin in pins { wanted[pin.id] = pin }
            for (id, annotation) in pinAnnotations {
                // A tree can also change *kind* under a stable id — a lead confirming a removal
                // turns a green pin grey without moving it — so an id that is still wanted but now
                // draws differently is retired here rather than left showing the old picture.
                // The palette is part of what a pin draws, so it is part of this comparison. A pan
                // that moves a species out of the top four changes that species' kind under a stable
                // id, which is the same shape of change as a lead confirming a removal — and it is
                // noticed here for the same reason, by the same test.
                guard let pin = wanted[id],
                      MapPinKind.kind(for: pin, palette: palette) == annotation.kind else {
                    stalePins.append(annotation)
                    pinAnnotations[id] = nil
                    continue
                }
                // The pin is staying, and its picture is right. Its *words* can still have changed
                // without its kind changing: a species name landing turns `City tree` into
                // `City tree, London Plane` on every pin of that species, and the kind comparison
                // above cannot see it because the fill and the glyph were already correct. Nothing
                // is added or removed for this — the label is read off the annotation.
                //
                // Only when the palette actually moved. See `appliedPalette`.
                if paletteMoved,
                   annotation.refreshSpokenLabel(palette: palette),
                   let view = mapView.view(for: annotation) {
                    view.accessibilityLabel = annotation.spokenLabel
                }
            }
            var freshPins: [MKAnnotation] = []
            for pin in pins where pinAnnotations[pin.id] == nil {
                let annotation = TreePinAnnotation(pin: pin, palette: palette)
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
                // `apply` resets `zPriority`, which selection now owns as well as the transform and
                // the reticle — so a colour-scheme flip would otherwise drop the selected pin back
                // behind its neighbours and leave a half-covered ring pointing at nothing.
                if let pin = annotation as? TreePinAnnotation {
                    view.setSelectedAppearance(pin.pin.id == selectedPinID)
                }
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
    /// The two rings of the selection reticle. See `setSelectedAppearance`.
    ///
    /// Readable rather than private so `MapSpeciesColourTests` can assert the size these end up on the
    /// glass at — the one number in the mark that a screenshot cannot check and a constant does not
    /// tell you, because the view is also carrying a scale transform.
    private(set) var reticleLayers: [CALayer] = []

    /// The 44 pt hit target every control in this app carries (ARCHITECTURE §6, SCREENS.md §5 gap
    /// 12). A drawn pin is 16–18 pt, so without this the tap target would shrink to the bitmap and
    /// the map would become the one screen in the app that does not meet its own rule.
    private static let hitTarget = CypressSpacing.minTapTarget

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = .zero
        // The selection reticle is achromatic in *both* halves, so it has to be redrawn when the
        // basemap flips. `MapPinImage.flush()` handles the bitmaps; a `CGColor` inside a `CALayer` is
        // the one thing on this view that cannot resolve itself off the trait collection.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MapMarkerView, _) in
            view.redrawReticleForCurrentAppearance()
        }
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
            // The annotation computed this against the palette that was live when it was made, and
            // it is remade whenever the palette changes it — so reading it here cannot go stale.
            accessibilityLabel = pin.spokenLabel
            accessibilityTraits = .button
        case let cluster as TreeClusterAnnotation:
            accessibilityLabel = cluster.kind.accessibilityLabel
            accessibilityTraits = .button
        default:
            accessibilityLabel = MapPin.Kind.gps.accessibilityLabel
            accessibilityTraits = .none
        }
    }

    /// **The tapped pin, findable among thirty.** Task #89.
    ///
    /// `MapLayout.selectedPinScale` on its own was 22.5 pt against 18 — the reader was being asked to
    /// find the marginally larger dot on a block that draws up to 288 of them. The scale stays,
    /// because it is what makes the pin and the card read as one selection, and a **reticle** is added
    /// around it: two achromatic rings outside the pin's own footprint. `MapLayout` carries the
    /// numbers and the argument for why this cannot be confused with a species colour.
    ///
    /// It is drawn with `CALayer`s rather than a new bitmap, for the reason the pulse is: the marker's
    /// image comes out of a cache that must stay countable, and a selected variant of every pin kind
    /// would double it. Selection therefore costs zero cache entries.
    ///
    /// The selected marker also comes to the front. Two pins 20 pt apart overlap inside 36 pt of
    /// reticle, and a reticle half-covered by the neighbour it is distinguishing itself from is not a
    /// mark.
    func setSelectedAppearance(_ isSelected: Bool) {
        let scale = isSelected ? MapLayout.selectedPinScale : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
        zPriority = isSelected ? .max : .defaultUnselected
        setReticle(isSelected)
    }

    private func setReticle(_ isSelected: Bool) {
        guard isSelected else {
            reticleLayers.forEach { $0.removeFromSuperlayer() }
            reticleLayers = []
            return
        }
        guard reticleLayers.isEmpty, let pin = annotation as? TreePinAnnotation else { return }
        let diameter = pin.kind.diameter
        // **Divided by the selection scale, because these layers are children of a view that is
        // wearing it.** `setSelectedAppearance` puts `selectedPinScale` on the whole view, so a layer
        // asked for 2.0 × 18 pt would land on the glass at 45 pt — past the 44 pt tap target, and not
        // the number `MapLayout` states or the test asserts. Compensating here is what makes the
        // documented geometry the drawn geometry.
        let compensation = 1 / MapLayout.selectedPinScale
        // Outer in ink, inner in the ring colour — so whichever end of the ramp the basemap is at,
        // one of the two rings is the opposite of it. `resolvedColor` because a `CALayer` holds a
        // `CGColor` and cannot resolve a dynamic one itself; the view's own traits are the map's.
        let rings: [(scale: CGFloat, colour: UIColor)] = [
            (MapLayout.selectedReticleOuterScale, UIColor(CypressColor.textInk)),
            (MapLayout.selectedReticleInnerScale, UIColor(CypressColor.pinRingStroke)),
        ]
        for ring in rings {
            let size = diameter * ring.scale * compensation
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            layer.cornerRadius = size / 2
            layer.borderWidth = MapLayout.selectedReticleStroke * compensation
            layer.borderColor = ring.colour.resolvedColor(with: traitCollection).cgColor
            layer.backgroundColor = UIColor.clear.cgColor
            // Under the pin's own bitmap, so a ring can never eat into the dot it is pointing at.
            layer.zPosition = -1
            self.layer.addSublayer(layer)
            reticleLayers.append(layer)
        }
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
        for layer in reticleLayers { layer.position = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    /// Registered in `init` against `UITraitUserInterfaceStyle`. A no-op unless this view is the one
    /// carrying the selection.
    private func redrawReticleForCurrentAppearance() {
        guard !reticleLayers.isEmpty else { return }
        setReticle(false)
        setReticle(true)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        zPriority = .defaultUnselected
        pulseLayer?.removeFromSuperlayer()
        pulseLayer = nil
        setReticle(false)
    }
}
