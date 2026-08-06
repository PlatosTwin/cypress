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

#if DEBUG
/// Diagnostic-only trace of the reader's hand on the glass (task #241).
///
/// **Why this exists.** `MapPanTabSwitchUITests.panUntilMoved` failed its precondition twice on a
/// loaded CI runner after #230's retry landed (runs 31067670540, 31074532263) — "panning the map
/// did not move the camera off the reader" — and that one sentence cannot tell "the synthesized
/// drag never reached the map" from "it reached the map and something moved the camera back". Both
/// read identically from outside the app: the recenter control still says `Centered on you`.
///
/// **Not a log line — an accessibility value, read directly by the test that needs it.** A log
/// was tried first and measured wrong: `NSLog` writes to the unified log, which `xcodebuild
/// test`'s own captured text (what `Tools/run_tests.sh` writes and `Tools/verify_test_log.sh`
/// reads) does not contain; a plain `print` from the *app* process fares no better, because the
/// app under a UI test is a separate process from the one whose stdout `xcodebuild` captures —
/// only the *test-runner* process's own `print` calls land in that text (confirmed: a `print`
/// added to `MapPanTabSwitchUITests` itself did show up; the identical call in the app did not).
/// An accessibility element has neither problem: the UI test that already knows how to read the
/// recenter control's `accessibilityValue` can read this one the same way, and it works
/// identically on a Mac and on a CI runner because it never depends on how either one captures a
/// process's console.
///
/// Armed by `CYPRESS_PAN_PROBE=1`, the same seam `MapFrameProbe` uses for `CYPRESS_MAP_PROBE` — off
/// unless asked for, `#if DEBUG` on top of that, so it is compiled out of a release binary exactly
/// as that one is, and invisible in the accessibility tree of every test that does not arm it.
@MainActor
@Observable
final class MapPanProbe {
    static let environmentKey = "CYPRESS_PAN_PROBE"
    static let isEnabled = ProcessInfo.processInfo.environment[environmentKey] == "1"
    static let shared = MapPanProbe()

    /// `MapHomeView` reads this through `accessibilityIdentifier` — task #241.
    static let accessibilityIdentifier = "CypressPanProbe"

    /// How many times *our own* pan recognizer (added in `makeUIView`, `cancelsTouchesInView =
    /// false`) reached each state. This recognizer does not drive the camera — MapKit's own
    /// internal one does that — so `panBegan > 0` answers "did a touch stream reach the map view
    /// and get read as a pan at all", independent of whether MapKit's recognizer agreed.
    private(set) var panBegan = 0
    private(set) var panEnded = 0
    private(set) var panCancelled = 0
    private(set) var panFailed = 0
    /// The translation `UIPanGestureRecognizer` itself measured at `.ended`, in points. `nil`
    /// until a pan has ended at least once.
    private(set) var lastEndedTranslation: CGPoint?

    /// How many times MapKit reported a settled camera (`mapView(_:regionDidChangeAnimated:)`),
    /// and where the most recent one landed. If a drag's own recognizer reaches `.ended` with a
    /// real translation but no settle follows (or the settle lands back near the opening center),
    /// that is "landed, then snapped back" rather than "never landed" — the distinction this
    /// probe exists to make.
    private(set) var settles = 0
    private(set) var lastSettleCenter: Coordinate?
    private(set) var lastSettleSpanDegrees: Double?

    func noteGesture(_ recognizer: UIGestureRecognizer) {
        guard recognizer is UIPanGestureRecognizer else { return }
        switch recognizer.state {
        case .began:
            panBegan += 1
        case .ended:
            panEnded += 1
            lastEndedTranslation = (recognizer as? UIPanGestureRecognizer)?.translation(in: recognizer.view)
        case .cancelled:
            panCancelled += 1
        case .failed:
            panFailed += 1
        default:
            break
        }
    }

    func noteSettle(_ region: MKCoordinateRegion) {
        settles += 1
        lastSettleCenter = Coordinate(region.center)
        lastSettleSpanDegrees = region.span.latitudeDelta
    }

    /// One line, read by `MapPanTabSwitchUITests` through the hidden element's
    /// `accessibilityValue`.
    var summary: String {
        let translation = lastEndedTranslation.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none"
        let center = lastSettleCenter.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        let span = lastSettleSpanDegrees.map(String.init(describing:)) ?? "none"
        return "panBegan=\(panBegan) panEnded=\(panEnded) panCancelled=\(panCancelled) "
            + "panFailed=\(panFailed) lastEndedTranslation=\(translation) settles=\(settles) "
            + "lastSettleCenter=\(center) lastSettleSpan=\(span)"
    }
}
#endif

// MARK: - The annotations

/// One tree. `MKAnnotation` rather than a SwiftUI view, so MapKit can recycle the view drawing it.
final class TreePinAnnotation: NSObject, MKAnnotation {
    let pin: TreePin
    let kind: MapPin.Kind
    /// What VoiceOver says. Computed here rather than in the view because it depends on the palette,
    /// and the palette is a fact about the screenful rather than about this tree.
    ///
    /// **It is a `var`, and that is the fix rather than an affordance.** The species *name* arrives
    /// after the palette that ranked it — `MapModel.resolveSpeciesNamesForPalette` reads the catalog
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
    /// common case where nothing was learned about this tree's species since the last pass.
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

    /// Which way the reader is facing, in degrees clockwise from true north, or `nil` for "do not
    /// draw a direction" (task #155).
    ///
    /// **Deliberately not `@objc dynamic`.** MapKit observes `coordinate` and moves the view for
    /// us; nothing in MapKit knows what a heading is, so KVO here would buy an observer nobody has.
    /// `Coordinator.applyUserHeading` hands the angle to the marker view instead — which is also
    /// where the map's own rotation is subtracted, and that cannot be done from the annotation.
    var headingDegrees: Double?

    init(coordinate: CLLocationCoordinate2D, headingDegrees: Double? = nil) {
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
    }
}

// MARK: - The pin bitmaps

/// C19's pins, rasterised once per kind and reused by every marker of that kind.
///
/// ── The species coloring is a *bounded* addition to this, which is the whole design of it ────
/// Task #80 asks for a color per species and the seed has 569 of them. Keying this cache on a
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
/// that could drift from the first. The cache key carries the color scheme because
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
    /// Exposed for `MapSpeciesColorTests`, which asserts the number rather than the argument: "the
    /// species coloring is bounded" is a sentence, and this is the thing that makes it a test. It is
    /// the one property of this cache that a future change can quietly destroy.
    static var count: Int { cache.count }

    /// Dropped when the color scheme flips, so the map does not keep drawing the light-mode ring
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
/// to wait for a size. Waiting is safe only if something wakes the layer when the size arrives; this
/// hook is that guarantee, and what it is actually worth is set out at the end of this comment.
///
/// **Do not reason about it from the body's evaluation rate.** This note used to argue that screen 01
/// "re-runs its body 240 times a second and would have produced another pass on its own", leaving the
/// hook to serve the two quieter screens. The rate was the wrong quantity to look at, which is worth
/// recording because a later round reasoned from it and got the opposite answer. E140 has since taken
/// screen 01's *at-rest* rate to zero (re-measured under task #226 — see `MapCameraRequest`), and it
/// changed nothing here: **a screen being mounted is not a screen at rest.** The mount delivers
/// `updateUIView` passes whatever the resting rate is, and that is where the aim arrives from. The
/// race below is structural, so no change in the resting rate can decide it either way.
///
/// Re-ablated under #226 on all three screens, with the callback removed and a fix granted: screen 01
/// still opens on Folsom St with its 87 markers, the pin-adjust map on its anchor in Dolores Park, and
/// the pin-set map framed on its thirteen — indistinguishable from the build that has it.
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
/// already spent. Removing the hop, or the whole hook, changes no observable behavior there and no
/// test — that was built and run, both ways, and #226 re-ran the ablation after E140 and found the
/// same on the pin-adjust and pin-set maps too. Do not read the paragraphs above as a description of
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
    /// The four color slots, as `MapModel` ranked them over exactly these pins.
    var speciesPalette: MapSpeciesPalette = .empty
    let userCoordinate: Coordinate?
    /// Which way the reader is facing, in degrees clockwise from true north (task #155). `nil` on
    /// the two one-tree screens, and `nil` whenever the magnetometer cannot be trusted — in both
    /// cases the dot draws bare, which is the whole fallback.
    var userHeadingDegrees: Double?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void
    /// Fired when a pan or pinch **begins on the glass** — a reader's own hand, never the app's
    /// camera writes (task #128). Optional and nil on the two quiet screens that draw this
    /// basemap; screen 01 uses it to mark the camera as the reader's.
    ///
    /// A gesture, not a camera comparison: E140 established that no comparison of camera values
    /// can tell a reader's move from a stale update pass, so the one honest signal is the touch
    /// itself. The recognizers are additive observers (`cancelsTouchesInView = false`, recognizing
    /// simultaneously) and steal nothing from MapKit's own handling.
    var onReaderGesture: (() -> Void)?

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

        // The reader's own hand on the glass, observed without being interfered with (#128). One
        // recognizer per gesture family that moves a camera; `.rotation` is left out because a
        // rotation does not change where the camera is looking, and the flag this feeds gates a
        // *re-center*.
        for recognizer in [
            UIPanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.readerGesture(_:))
            ),
            UIPinchGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.readerGesture(_:))
            ),
        ] {
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = context.coordinator
            mapView.addGestureRecognizer(recognizer)
        }

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
        // the moment the first GPS fix minted the *next* request the layer had already burned its
        // number and every later pass was dropped as stale — `REJECT seq=1 applied=1`, forever, with
        // no retry, because `MapHomeView.hasCenteredOnUser` is a one-shot and had already fired. And
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
        context.coordinator.syncUserDot(userCoordinate, heading: userHeadingDegrees, on: mapView)
        context.coordinator.applySelection(selectedPinID, on: mapView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        /// The observers added in `makeUIView` must not fight MapKit's own recognizers — theirs do
        /// the panning; ours only report that a pan happened (#128).
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

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

        /// The palette the annotations on the map were last labeled against.
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
        /// `cc01e32`. A test about a *nudge* is what noticed; nothing about a species color did.
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
            appliedHeadingAngle = nil
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
            let color = isDark ? CypressColor.Dark.bgMap : CypressColor.surfaceMapPaper
            let alpha = isDark ? MapLayout.washOpacityDark : MapLayout.washOpacityLight
            renderer.fillColor = UIColor(color).withAlphaComponent(alpha)
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
        /// zoom levels in" from it, `MapRecenter` asks it whether the map is on the reader, and
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
        /// `VisitPinAdjustView` follows this callback directly — `pin = VisitPinAdjust.center(of:
        /// box)`, the midpoint of the reported region — so the pin the contributor is about to attach
        /// to a real tree was being dragged to the middle of Kansas before they touched anything.
        /// Measured: the pin read `2344980 m east of where you are standing`, against a great-circle
        /// distance of 2,343,915 m from the fix to MapKit's default center. A 0.05 % match is an
        /// identification, not a coincidence.
        ///
        /// `appliedSequence` is exactly the question "has this layer ever aimed this map", so it is
        /// the honest gate. The contract of this callback is *the app moved the camera, here is where
        /// it is now*; a camera nobody asked for has no business being reported through it. Nothing is
        /// lost by waiting, because `AimableMapView.onFirstLayout` guarantees the aim arrives — which
        /// is the job that hook now has, and the only one it does.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // The cone is drawn relative to the screen and the reader can rotate the basemap under
            // it, so a camera that turns has to move the cone the other way or it stops pointing at
            // the same piece of the world (task #155). Not animated: this arrives once per frame of
            // the reader's own gesture, and a quarter-second sweep chasing a live rotation would
            // drag behind the fingers doing it. `applyUserHeading` compares before it does anything,
            // so a pan that only translates costs one subtraction.
            //
            // Above the gate below rather than under it, because it is not about reporting a camera:
            // this runs whether or not the layer has ever aimed the map.
            applyUserHeading(on: mapView, animated: false)
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
        /// so that pressing the recenter control a second time was not swallowed as a duplicate value
        /// (#66). Clearing it meant the next `updateUIView` — one of about 240 a second, as the rate
        /// then was — found a
        /// position that did not match an empty record, took that for a fresh request, and drove the
        /// camera back to the reader's own location. The map could not be moved. A press now mints
        /// its own ticket whether or not it names the same place, so the second press works without
        /// this handler having any opinion about the camera at all.
        ///
        /// **Through `echo(_:)`, not by assignment.** MapKit delivers this synchronously from inside
        /// `setRegion`, which this file calls from `updateUIView`, so a direct write lands in the
        /// middle of a SwiftUI view update and is discarded. See `echo(_:)` and ERRATA E168.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // The settled camera is the authority on the map's rotation as well as its region, and a
            // flown camera settles without `mapViewDidChangeVisibleRegion` necessarily having seen
            // the last frame of it.
            applyUserHeading(on: mapView, animated: false)
            #if DEBUG
            if MapPanProbe.isEnabled { MapPanProbe.shared.noteSettle(mapView.region) }
            #endif
            echo(mapView.region)
        }

        // MARK: The reader's hand (#128)

        /// A pan or pinch began on the glass. Reported once per gesture, at `.began`, so the
        /// callback costs nothing per frame of the drag.
        ///
        /// **Logs every state, not just `.began` — task #241.** The early return below still gates
        /// `onReaderGesture` at exactly one state, unchanged; the probe is a separate read of the
        /// same callback, which UIKit already calls on every transition (`.began`, `.changed` per
        /// frame of the drag, then `.ended`/`.cancelled`/`.failed`) because the recognizer was wired
        /// with a single `#selector` covering all of them. Between a run with the probe armed and
        /// one without, nothing about which state fires `onReaderGesture` changes.
        @objc func readerGesture(_ recognizer: UIGestureRecognizer) {
            #if DEBUG
            if MapPanProbe.isEnabled { MapPanProbe.shared.noteGesture(recognizer) }
            #endif
            guard recognizer.state == .began else { return }
            parent.onReaderGesture?()
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
            // **A cluster id that is still wanted but now stands for a different answer is retired
            // here** — the same rule the pin loop below applies to a pin whose *kind* changed, and
            // it was missing (task #240).
            //
            // `TreeCluster.id` is `z<zoom>:<cellY>:<cellX>`, deliberately stable across a pan so a
            // badge does not flicker and re-animate under the reader's thumb — and the count and the
            // centroid are *not* in it, because the grid is a fact about the ground rather than
            // about the answer. A membership test against the id alone therefore keeps a badge that
            // is still in the right cell and no longer says the right number, and
            // `TreeClusterAnnotation` freezes its `kind` — the count included — at init.
            //
            // A pan exposes it at the perimeter: `clustersSQL` clips each cell to the fetched box,
            // so a cell straddling the box's edge is aggregated over its clipped part only, and its
            // count and centroid move under the stable id (measured in PR #39 review — one 150 pt
            // drag took an edge badge 156 → 181 while every interior badge held; the old
            // membership-by-id test left exactly those badges stale too). A **narrowing** exposes it
            // everywhere at once, because the same cell holds a different set — and this is the
            // second half of what the owner saw in #240. With the condition chips
            // reaching the query, pressing `In bloom` over a clustered map removed the cells that
            // emptied out and left every surviving badge showing its un-narrowed count. It is not
            // new: a species typed into C20 has narrowed clustered counts since #116 and had the
            // same stale badges.
            //
            // Comparing the whole `TreeCluster` keeps E130's promise intact — an update whose
            // clusters are the same clusters compares equal and does no work at all.
            var staleClusters: [MKAnnotation] = []
            var wantedClusters: [String: TreeCluster] = [:]
            wantedClusters.reserveCapacity(clusters.count)
            for cluster in clusters { wantedClusters[cluster.id] = cluster }
            for (id, annotation) in clusterAnnotations where wantedClusters[id] != annotation.cluster {
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
                // turns a green pin gray without moving it — so an id that is still wanted but now
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
        ///
        /// **And it glides** (task #149). A bare write to the KVO'd coordinate moves the view in
        /// one frame, so a walking reader's dot jumped a few meters once a second — position as a
        /// slideshow. Wrapping the write in a `UIView` animation is `MKMapView`'s own mechanism
        /// for animating an annotation between coordinates: one object, one view, interpolated on
        /// the render server, no SwiftUI pass anywhere (the E139 class this file exists to keep
        /// out). Linear, because a dot that eases is a dot that stops walking twice a second.
        ///
        /// Three cases do not glide, each for its own reason: the first fix (there is nothing to
        /// glide *from*), Reduce Motion (the new position is the answer, not the delivery — the
        /// same rule `applyCameraIfChanged` follows), and a teleport past
        /// `MapLayout.userDotSnapDegrees` (an animation would claim a journey that never
        /// happened).
        func syncUserDot(_ coordinate: Coordinate?, heading: Double?, on mapView: MKMapView) {
            guard let coordinate else {
                if let userDot { mapView.removeAnnotation(userDot) }
                userDot = nil
                appliedHeadingAngle = nil
                return
            }
            let next = coordinate.clLocationCoordinate
            if let userDot {
                // **Before the coordinate comparison below, not after it.** That comparison returns
                // early for a reader standing still, which is exactly the reader who is turning on
                // the spot — put the heading after it and the cone would move only when the dot did.
                userDot.headingDegrees = heading
                applyUserHeading(on: mapView, animated: true)
                let current = userDot.coordinate
                guard current.latitude != next.latitude
                        || current.longitude != next.longitude else { return }
                let jump = max(
                    abs(current.latitude - next.latitude),
                    abs(current.longitude - next.longitude)
                )
                if UIAccessibility.isReduceMotionEnabled || jump > MapLayout.userDotSnapDegrees {
                    userDot.coordinate = next
                } else {
                    UIView.animate(
                        withDuration: MapLayout.userDotGlideSeconds,
                        delay: 0,
                        options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]
                    ) {
                        userDot.coordinate = next
                    }
                }
                return
            }
            let dot = UserDotAnnotation(coordinate: next, headingDegrees: heading)
            userDot = dot
            appliedHeadingAngle = nil
            mapView.addAnnotation(dot)
            // No `applyUserHeading` here: MapKit has not built a view for this annotation yet.
            // `mapView(_:viewFor:)` puts the cone on at the right angle the moment it does.
        }

        // MARK: The direction cone (task #155)

        /// The screen angle the cone was last set to, so a pan that changes nothing does nothing.
        ///
        /// It is the *screen* angle rather than the reader's heading because both inputs move: the
        /// reader turns, and the reader can turn the map. Recording the answer is what makes both
        /// of the callers below — one per frame of a rotation gesture — cost a comparison.
        private var appliedHeadingAngle: Double?

        /// Hands the marker view the angle to draw the cone at, if it has changed.
        ///
        /// **The map's own rotation is subtracted here** (`MapHeading.screenAngleDegrees`), because
        /// this is the only place that knows both numbers. An `MKAnnotationView` stays square to the
        /// screen while the basemap turns under it, so a cone drawn at the raw compass bearing would
        /// be correct only on a north-up map and would quietly lie on any other.
        func applyUserHeading(on mapView: MKMapView, animated: Bool) {
            guard let userDot, let view = mapView.view(for: userDot) as? MapMarkerView else { return }
            let angle = userDot.headingDegrees.map {
                MapHeading.screenAngleDegrees(heading: $0, cameraHeading: mapView.camera.heading)
            }
            guard angle != appliedHeadingAngle else { return }
            appliedHeadingAngle = angle
            view.setHeading(angle, animated: animated)
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
                // the reticle — so a color-scheme flip would otherwise drop the selected pin back
                // behind its neighbors and leave a half-covered ring pointing at nothing.
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
            // A dot arriving on the map, or a recycled view taking the dot back on, starts at the
            // angle the reader is facing **now** — never animated, because there is nothing to turn
            // from. Same rule the dot's own first fix follows in `syncUserDot`.
            if let dot = annotation as? UserDotAnnotation {
                let angle = dot.headingDegrees.map {
                    MapHeading.screenAngleDegrees(heading: $0, cameraHeading: mapView.camera.heading)
                }
                appliedHeadingAngle = angle
                view?.setHeading(angle, animated: false)
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
    /// The direction cone on the reader's own dot, and nothing else's (task #155).
    ///
    /// Readable for the reason `reticleLayers` is: the cone is never rasterised through
    /// `MapPinImage`, it is only ever composited on the render server, and no simulator can produce
    /// the heading that would draw it. Its geometry — that it points the way the reader faces rather
    /// than the opposite way, that it is not a zero-sized layer, that the fade starts opaque enough
    /// to see — is checkable **only** through the layer itself.
    private(set) var headingConeLayer: CALayer?
    /// The angle the cone is turned to, **unwrapped** — it accumulates past 360° and below 0°
    /// rather than being brought back into a circle.
    ///
    /// `transform.rotation.z` is a number, not a bearing: animating it from 350 to 10 spins the cone
    /// 340° backwards through south, which is what a reader wobbling past north would see on every
    /// other reading. Adding `MapHeading.shortestDelta` to a running total keeps this value free of
    /// that.
    ///
    /// **This being right is not the same as the cone turning the short way, and #207 is the
    /// difference.** For a round after #155 shipped, this accumulator was correct and the cone still
    /// took a full revolution on every reading, because `setHeading` animated *to* it *from* an angle
    /// read back out of the presentation layer — which normalizes. The two numbers were in different
    /// spaces and only one of them was ever asserted.
    ///
    /// So: read this to check the accumulator, and **never** to conclude anything about which way the
    /// cone went round. The only thing that answers that is the animation the layer was handed, which
    /// is what `MapHeadingTests` reads now.
    private(set) var headingRotationDegrees: Double?
    /// The two rings of the selection reticle. See `setSelectedAppearance`.
    ///
    /// Readable rather than private so `MapSpeciesColorTests` can assert the size these end up on the
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
            // The cone is a `CGColor` in a layer too, and `refreshAllMarkerImages` cannot help it:
            // that pass replaces bitmaps, and the cone is not one.
            if let cone = view.headingConeLayer { view.applyConeColors(to: cone) }
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
        // **The reader's dot is topmost — above tree pins, above the selected pin's emphasis**
        // (task #150; the ordering and its argument live on `MapLayout`). It was `.min`, and the
        // running screen showed the dot vanishing under any dense block's pins — the one mark
        // every other mark is relative to, hidden by them.
        zPriority = annotation is UserDotAnnotation
            ? MapLayout.userDotZPriority
            : MapLayout.pinZPriority
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
    /// numbers and the argument for why this cannot be confused with a species color.
    ///
    /// It is drawn with `CALayer`s rather than a new bitmap, for the reason the pulse is: the marker's
    /// image comes out of a cache that must stay countable, and a selected variant of every pin kind
    /// would double it. Selection therefore costs zero cache entries.
    ///
    /// The selected marker also comes to the front. Two pins 20 pt apart overlap inside 36 pt of
    /// reticle, and a reticle half-covered by the neighbor it is distinguishing itself from is not a
    /// mark.
    func setSelectedAppearance(_ isSelected: Bool) {
        let scale = isSelected ? MapLayout.selectedPinScale : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
        // Above its neighbors, below the reader's dot (task #150; see `MapLayout`'s z-order
        // block). `.max` belongs to the dot now, so selection takes the tier under it.
        zPriority = isSelected ? MapLayout.selectedPinZPriority : MapLayout.pinZPriority
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
        // Outer in ink, inner in the ring color — so whichever end of the ramp the basemap is at,
        // one of the two rings is the opposite of it. `resolvedColor` because a `CALayer` holds a
        // `CGColor` and cannot resolve a dynamic one itself; the view's own traits are the map's.
        let rings: [(scale: CGFloat, color: UIColor)] = [
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
            layer.borderColor = ring.color.resolvedColor(with: traitCollection).cgColor
            layer.backgroundColor = UIColor.clear.cgColor
            // Under the pin's own bitmap, so a ring can never eat into the dot it is pointing at.
            layer.zPosition = -1
            self.layer.addSublayer(layer)
            reticleLayers.append(layer)
        }
    }

    // MARK: The direction cone (task #155)

    /// Points the cone at `degrees` on the glass, or takes it off entirely for `nil`.
    ///
    /// `nil` is the fallback the whole feature turns on: no magnetometer, a `headingAccuracy` below
    /// zero, a provider that has been stopped, or a screen that never asked. In every one of those
    /// the reader gets the bare dot they had before this task, which is the one honest thing to draw
    /// when nobody knows which way they are facing.
    ///
    /// **It rotates on the render server, like everything else on this view.** A `CABasicAnimation`
    /// on one sublayer's `transform.rotation.z` costs the main thread nothing per frame and costs
    /// SwiftUI nothing at all — the E139 class this file exists to keep out, and the reason #149's
    /// glide was built the same way. The cone is a layer for the same reason the pulse and the
    /// reticle are: it adds no entry to `MapPinImage`'s countable cache.
    ///
    /// Not animated on the first heading (there is nothing to turn *from*) or under Reduce Motion
    /// (the direction is the answer, not the way it is delivered) — the two exemptions `syncUserDot`
    /// already makes for the dot's own movement.
    func setHeading(_ degrees: Double?, animated: Bool) {
        guard let degrees else {
            headingConeLayer?.removeFromSuperlayer()
            headingConeLayer = nil
            headingRotationDegrees = nil
            return
        }
        let cone = headingConeLayer ?? makeConeLayer()
        let previous = headingRotationDegrees
        let target = (previous ?? degrees)
            + MapHeading.shortestDelta(from: previous ?? degrees, to: degrees)
        headingRotationDegrees = target

        let radians = MapHeading.radians(target)
        // Where the cone is *drawn* right now, which during a swing is not where the model layer
        // says it is. Retargeting mid-turn has to start from what the reader can see.
        //
        // **It is brought into `target`'s space before it is used, and that is the whole of #207** —
        // `MapHeading.swingStartDegrees` carries the argument, and carries it there because a
        // detached layer has no presentation layer and this line cannot be reached from a test.
        //
        // The fallback is the previous *accumulated* angle rather than the drawn one, for the case
        // where nothing has been committed to the render server yet; it goes through the same
        // function so there is one rule and not two.
        let drawn = (cone.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double)
            .map(MapHeading.degrees) ?? previous
        let from = drawn.map {
            MapHeading.radians(MapHeading.swingStartDegrees(drawnAt: $0, target: target))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cone.setValue(radians, forKeyPath: "transform.rotation.z")
        CATransaction.commit()

        guard animated, previous != nil, !UIAccessibility.isReduceMotionEnabled,
              let from, from != radians else { return }
        let swing = CABasicAnimation(keyPath: "transform.rotation.z")
        swing.fromValue = from
        swing.toValue = radians
        swing.duration = MapLayout.userHeadingRotationSeconds
        swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cone.add(swing, forKey: "cypressHeading")
    }

    /// The cone itself: a wedge of the dot's own blue, fading out along its length.
    ///
    /// Drawn pointing **up** and turned by the layer's rotation, so the geometry is written once and
    /// the only thing that ever changes is one angle. Up is `-90°` in UIKit's y-down coordinates.
    ///
    /// A `CAGradientLayer` under a wedge-shaped mask rather than a filled `CAShapeLayer`: a hard
    /// arc at the far end would read as a fact about how far the reader can see, which it is not.
    /// The mask turns with the layer, so the fade stays anchored to the dot.
    private func makeConeLayer() -> CALayer {
        let radius = MapLayout.userHeadingConeRadius
        let box = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)

        let wedge = CAShapeLayer()
        wedge.bounds = box
        wedge.position = CGPoint(x: radius, y: radius)
        let center = CGPoint(x: radius, y: radius)
        let half = MapLayout.userHeadingConeDegrees / 2
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(
            withCenter: center,
            radius: radius,
            startAngle: CGFloat(MapHeading.radians(-90 - half)),
            endAngle: CGFloat(MapHeading.radians(-90 + half)),
            clockwise: true
        )
        path.close()
        wedge.path = path.cgPath
        wedge.fillColor = UIColor.black.cgColor

        let cone = CAGradientLayer()
        cone.type = .radial
        cone.bounds = box
        cone.position = CGPoint(x: bounds.midX, y: bounds.midY)
        cone.startPoint = CGPoint(x: 0.5, y: 0.5)
        cone.endPoint = CGPoint(x: 1, y: 1)
        cone.mask = wedge
        // Under the dot's own bitmap, the way the pulse and the reticle sit under theirs.
        cone.zPosition = -1
        layer.addSublayer(cone)
        headingConeLayer = cone
        applyConeColors(to: cone)
        return cone
    }

    /// `CypressColor.gpsDot`, at the cone's opacity where it meets the dot and at nothing where it
    /// ends. `resolvedColor` because a `CALayer` holds `CGColor`s and cannot resolve a dynamic one
    /// itself — the same reason the reticle redraws on a trait change rather than being told a color.
    private func applyConeColors(to cone: CALayer) {
        guard let gradient = cone as? CAGradientLayer else { return }
        let blue = UIColor(CypressColor.gpsDot).resolvedColor(with: traitCollection)
        gradient.colors = [
            blue.withAlphaComponent(MapLayout.userHeadingConeOpacity).cgColor,
            blue.withAlphaComponent(0).cgColor,
        ]
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
        headingConeLayer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
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
        zPriority = MapLayout.pinZPriority
        pulseLayer?.removeFromSuperlayer()
        pulseLayer = nil
        setReticle(false)
        // A view that carried the reader's dot is handed to a tree next. A cone left on it would be
        // a direction pointer on a pin, which is not a mark this app has.
        setHeading(nil, animated: false)
    }
}
