import MapKit
import SwiftUI
import Testing
@testable import Cypress

/// **Whoever moved the map last owns it, and after a pan that is the reader.**
///
/// The defect this suite exists for is ERRATA E140, reported by the owner from their own phone: "the
/// center me on the map button PREVENTS THE MAP FROM BEING MOVED OFF THE CURRENT LOCATION. Every time
/// I moved the map, in a second I got brought back to where I am centered and there was no way I
/// could figure out around this."
///
/// It was one line. `MapAnnotationLayer.Coordinator.mapView(_:regionDidChangeAnimated:)` answered a
/// real pan by clearing `lastRequestedPosition`, the record of what the app had last asked for.
/// Upstream, `MapHomeView.position` still held the one-shot centring on the first GPS fix — a pan
/// writes `region`, never `position`, and nobody had pressed anything. So the next `updateUIView`
/// compared a position that had not changed against a record that had been emptied, read that as a
/// fresh request, and drove the camera back to the fix. Measured on screen 01 with 161 markers, the
/// basemap body runs 240 times a second at rest, so "the next pass" was under a frame.
///
/// The assertion below is the sentence the owner is owed: **a reader who pans away stays panned
/// away.** It is written against the coordinator rather than through a UI test because the loop is
/// entirely inside the seam — a delegate callback, then a SwiftUI update pass — and both halves can
/// be driven directly and deterministically. What a UI test would add is the gesture, and the gesture
/// was never the doubtful part; it fired 44 region changes in the reproduction.
///
/// The second test is the other half of the promise. A fix that simply stopped the app writing the
/// camera would pass the first test and destroy the recentre control (#66), which is the feature this
/// screen just gained, so the ability of a press to move the camera *after* a pan is asserted too.
@MainActor
@Suite("The reader owns the map camera")
struct MapCameraOwnershipTests {

    /// The Mission, at screen 01's opening scale — the coordinate the defect was reproduced at.
    private static let fix = CLLocationCoordinate2D(latitude: 37.7599, longitude: -122.4148)

    /// Far enough that the coordinator's own quarter-of-a-span threshold calls it a pan, which is
    /// the branch the bug lived in. About 400 m north-east, or a couple of blocks.
    private static let pannedTo = CLLocationCoordinate2D(latitude: 37.7635, longitude: -122.4105)

    /// Metres between two coordinates, so an assertion can be written in a unit the reader has.
    private static func metres(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// The two pieces of `MapHomeView` state the basemap is given bindings to. A reference type so
    /// the bindings and the assertions read one copy.
    private final class CameraState: @unchecked Sendable {
        var position: MapCameraPosition
        var region: MKCoordinateRegion

        init(opening: MKCoordinateRegion) {
            position = .region(opening)
            region = opening
        }
    }

    /// One screen 01 basemap, its two bindings backed by storage this test can read, and the map view
    /// it draws into.
    ///
    /// The delegate is deliberately **not** attached. MapKit would otherwise post its own settle
    /// callbacks on its own schedule and the test would be asserting against a race; every callback
    /// the loop needs is invoked here by hand, in the order the running app invokes them.
    @MainActor
    private final class Screen {
        let state: CameraState
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        let coordinator: MapAnnotationLayer.Coordinator

        /// What `MapHomeView.position` currently holds.
        var position: MapCameraPosition {
            get { state.position }
            set { state.position = newValue }
        }

        init(opening: MKCoordinateRegion) {
            let state = CameraState(opening: opening)
            self.state = state
            let layer = MapAnnotationLayer(
                position: Binding(get: { state.position }, set: { state.position = $0 }),
                region: Binding(get: { state.region }, set: { state.region = $0 }),
                clusters: [],
                pins: [],
                userCoordinate: nil,
                selectedPinID: nil,
                onCameraChange: { _, _ in },
                onSelectPin: { _ in },
                onSelectCluster: { _ in }
            )
            coordinator = layer.makeCoordinator()
            mapView.setRegion(opening, animated: false)
            coordinator.lastRequestedPosition = position
        }

        /// One pass of `updateUIView`, in the only part of it this defect touches.
        func updatePass() {
            coordinator.applyCameraIfChanged(position, to: mapView)
        }

        /// The reader drags the map and lifts their finger. `setRegion` here is the gesture's own
        /// result, not an app-driven write — MapKit moves the map, then tells the delegate.
        func readerPans(to centre: CLLocationCoordinate2D) {
            mapView.setRegion(
                MKCoordinateRegion(center: centre, span: mapView.region.span),
                animated: false
            )
            coordinator.mapView(mapView, regionDidChangeAnimated: false)
        }
    }

    private static func opening() -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: fix,
            latitudinalMeters: MapLayout.defaultSpanMetres,
            longitudinalMeters: MapLayout.defaultSpanMetres
        )
    }

    // MARK: - The defect

    /// **The regression.** Pan, then let the screen update — which on the real screen it does 240
    /// times a second — and the map must still be where it was put.
    ///
    /// Before the fix this failed with the camera back at the fix, several hundred metres away.
    @Test("a pan is not undone by the update passes that follow it")
    func panSurvivesTheNextUpdatePass() {
        let screen = Screen(opening: Self.opening())

        screen.readerPans(to: Self.pannedTo)
        let afterGesture = screen.mapView.region.center
        #expect(
            Self.metres(afterGesture, Self.pannedTo) < 50,
            "the gesture itself must have moved the camera, or this test asserts nothing"
        )

        // Nothing above the basemap has changed: no press, no cluster tap, nobody wrote `position`.
        // These are the ordinary re-renders a live screen produces by the hundred.
        for _ in 0..<10 { screen.updatePass() }

        let centre = screen.mapView.region.center
        #expect(
            Self.metres(centre, Self.pannedTo) < 50,
            """
            the map was dragged to \(Self.pannedTo) and the app put it back at \(centre), \
            \(Int(Self.metres(centre, Self.pannedTo))) m away — this is E140, the map that cannot be \
            moved off the reader's own location
            """
        )
        #expect(
            Self.metres(centre, Self.fix) > 200,
            "the camera returned to the GPS fix the one-shot centred on"
        )
    }

    /// The same thing said about the state upstream, because that is where the stale request lived.
    /// After a pan the app's idea of the camera it is asking for has to be the reader's camera; any
    /// other value is a write waiting to happen.
    @Test("after a pan the app asks for the camera the reader chose")
    func panBecomesTheRequestedCamera() {
        let screen = Screen(opening: Self.opening())
        screen.readerPans(to: Self.pannedTo)

        let requested = screen.position.region?.center
        #expect(requested != nil, "the screen must still be asking for a region")
        #expect(
            Self.metres(requested ?? Self.fix, Self.pannedTo) < 50,
            "the app is still asking for a camera the reader has moved away from"
        )
    }

    // MARK: - The feature this must not destroy

    /// A press of the recentre control after a pan still moves the camera. This is the case the
    /// cleared record was protecting — #66's dead second press — and it has to survive the fix, or
    /// the map has been made movable by making the button useless.
    @Test("the recentre control still moves the camera after a pan")
    func recentreStillWorksAfterAPan() {
        let screen = Screen(opening: Self.opening())
        screen.readerPans(to: Self.pannedTo)
        for _ in 0..<10 { screen.updatePass() }

        // What `MapHomeView.flyTo(_:metres:)` writes for a `.centre` press: the fix, at whatever span
        // the reader has since zoomed to.
        screen.position = .region(
            MKCoordinateRegion(center: Self.fix, span: screen.mapView.region.span)
        )
        screen.updatePass()

        #expect(
            Self.metres(screen.mapView.region.center, Self.fix) < 50,
            "a press of the recentre control did not move the camera to the fix"
        )
    }

    /// And the second press, which is the one that zooms. Same mechanism, different span, and it has
    /// to be applied even though the camera is already centred where it is being asked to go.
    @Test("a second recentre press still zooms in")
    func secondRecentrePressStillZooms() {
        let screen = Screen(opening: Self.opening())
        screen.readerPans(to: Self.pannedTo)

        // Zoom out a long way first, so "zoomed in" is a change worth measuring.
        screen.position = .region(
            MKCoordinateRegion(center: Self.fix, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
        )
        screen.updatePass()
        let wide = screen.mapView.region.span.latitudeDelta

        // The `.centreAndZoomIn` press: the fix, at the screen's own opening scale.
        screen.position = .region(
            MKCoordinateRegion(
                center: Self.fix,
                latitudinalMeters: MapLayout.defaultSpanMetres,
                longitudinalMeters: MapLayout.defaultSpanMetres
            )
        )
        screen.updatePass()

        #expect(
            screen.mapView.region.span.latitudeDelta < wide / 2,
            "the second press did not zoom the camera in"
        )
    }
}
