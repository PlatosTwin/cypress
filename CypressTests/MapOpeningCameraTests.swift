import CoreLocation
import MapKit
import SwiftUI
import Testing
@testable import Cypress

/// **Where the map opens, and what it admits about that (#115).**
///
/// The owner's sentence is "opening the app should open on where you're located right now, 100% of
/// the time", and the honest reading of it has three parts. The camera has to actually arrive on the
/// reader (ERRATA E167, asserted in `MapOpeningCameraApplyTests` below). Until it can, it has to sit
/// somewhere defensible. And in the states where it never will, the screen has to say so — in
/// *different* words for different states, which is ERRATA E126 and the lesson of E158.
@MainActor
@Suite("The map's opening camera")
struct MapOpeningCameraTests {

    /// A camera over the Mission, in the shape `MKMapView` reports one.
    private static func snapshot(
        latitude: Double = 37.7599,
        longitude: Double = -122.4148,
        latitudeSpan: Double = 0.002341,
        longitudeSpan: Double = 0.001362
    ) -> MapCameraMemory.Snapshot {
        MapCameraMemory.Snapshot(
            centre: Coordinate(latitude: latitude, longitude: longitude),
            latitudeSpan: latitudeSpan,
            longitudeSpan: longitudeSpan
        )
    }

    /// A memory backed by its own suite, so one test cannot read another's camera — or the
    /// simulator's real one.
    private static func memory(_ name: String = UUID().uuidString) -> MapCameraMemory {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return MapCameraMemory(defaults: defaults)
    }

    // MARK: - Remembering

    /// The whole point, in one assertion: a camera noted, flushed, and read back by the next launch.
    @Test("the camera the reader left the map on survives to the next launch")
    func rememberedAcrossLaunches() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let firstRun = MapCameraMemory(defaults: defaults)
        firstRun.note(Self.snapshot())
        firstRun.flush()

        // A different instance reading the same store is exactly what the next launch is.
        let nextLaunch = MapCameraMemory(defaults: defaults)
        #expect(nextLaunch.remembered == Self.snapshot())
        #expect(nextLaunch.hasRememberedCamera)
    }

    /// **The cost model, asserted (#84).** A settle must not touch storage — screen 01 produces
    /// hundreds of them and the map's frame rate has been paid for three times already.
    @Test("noting a camera writes nothing until it is flushed")
    func noteDoesNotWrite() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let memory = MapCameraMemory(defaults: defaults)
        for i in 0..<50 {
            memory.note(Self.snapshot(latitude: 37.75 + Double(i) / 10_000))
        }
        #expect(
            defaults.array(forKey: MapCameraMemory.defaultsKey) == nil,
            "a pan wrote to storage — this is the cost model #84 bought back"
        )

        memory.flush()
        #expect(defaults.array(forKey: MapCameraMemory.defaultsKey) != nil, "the flush wrote nothing")
    }

    /// The opening camera and the sentence about it both mean "last time", and must not start meaning
    /// "a moment ago" the instant this screen settles its first region.
    @Test("what the map opened on does not change under it as the reader pans")
    func rememberedIsTheLaunchValue() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let opening = Self.snapshot()
        let lastLaunch = MapCameraMemory(defaults: defaults)
        lastLaunch.note(opening)
        lastLaunch.flush()

        let memory = MapCameraMemory(defaults: defaults)
        #expect(memory.remembered == opening)
        memory.note(Self.snapshot(latitude: 37.8000, longitude: -122.3900))
        #expect(memory.remembered == opening, "the opening camera moved under the screen")
    }

    // MARK: - What is not worth remembering

    /// A zero span is the camera before MapKit has settled once — the same case
    /// `MapRecentre.Camera.isCentred` guards — and 37.3346 is what a map view that was never aimed
    /// reads back as, which is the whole of E167. Neither is a place the reader has been.
    @Test("a camera that is not a place is neither stored nor restored")
    func rubbishIsRejected() {
        #expect(MapCameraMemory.isWorthRemembering(Self.snapshot(latitudeSpan: 0)) == false)
        #expect(MapCameraMemory.isWorthRemembering(Self.snapshot(longitudeSpan: 0)) == false)
        #expect(MapCameraMemory.isWorthRemembering(Self.snapshot(latitude: 91)) == false)
        #expect(MapCameraMemory.isWorthRemembering(Self.snapshot(longitude: -181)) == false)
        // Pinched out past a continent: a gesture on the way somewhere, not a view.
        #expect(
            MapCameraMemory.isWorthRemembering(
                Self.snapshot(latitudeSpan: MapCameraMemory.maximumSpanDegrees + 1)
            ) == false
        )
        #expect(MapCameraMemory.isWorthRemembering(Self.snapshot()))

        let memory = Self.memory()
        memory.note(Self.snapshot(latitudeSpan: 0))
        memory.flush()
        #expect(memory.remembered == nil, "a zero-span camera was stored")
    }

    /// `UserDefaults` is a file other versions of this app can have written, so the decoder trusts
    /// nothing — a half-written camera has to read as no camera rather than as a place near the
    /// equator.
    @Test("a stored value that is not four usable doubles is no camera at all")
    func decodeIsDefensive() {
        #expect(MapCameraMemory.decode(nil) == nil)
        #expect(MapCameraMemory.decode([]) == nil)
        #expect(MapCameraMemory.decode([37.76, -122.41]) == nil)
        #expect(MapCameraMemory.decode([37.76, -122.41, 0.002, 0.001, 9]) == nil)
        #expect(MapCameraMemory.decode([.nan, -122.41, 0.002, 0.001]) == nil)
        #expect(MapCameraMemory.decode([.infinity, -122.41, 0.002, 0.001]) == nil)
        #expect(MapCameraMemory.decode([37.76, -122.41, 0, 0.001]) == nil)
        // And the round trip, which is the only thing the app itself ever does.
        #expect(MapCameraMemory.decode(MapCameraMemory.encode(Self.snapshot())) == Self.snapshot())
    }

    // MARK: - Where it opens

    @Test("with a remembered camera the map opens on it, span and all")
    func opensOnTheRememberedCamera() {
        let region = MapOpening.openingRegion(remembered: Self.snapshot())
        #expect(abs(region.center.latitude - 37.7599) < 0.000_001)
        #expect(abs(region.center.longitude - -122.4148) < 0.000_001)
        // The span is restored too: reopening at the reader's own zoom is half of "where you left it".
        #expect(abs(region.span.latitudeDelta - 0.002341) < 0.000_001)
        #expect(abs(region.span.longitudeDelta - 0.001362) < 0.000_001)
    }

    /// The first launch, where there is no history and no fix. Dolores Park survives as the answer to
    /// that one question and to no other.
    @Test("with nothing remembered the map falls back to the city, at the opening scale")
    func fallsBackToTheCity() {
        let region = MapOpening.openingRegion(remembered: nil)
        #expect(abs(region.center.latitude - MapLayout.defaultCentre.latitude) < 0.000_001)
        #expect(abs(region.center.longitude - MapLayout.defaultCentre.longitude) < 0.000_001)
        #expect(region.span.latitudeDelta > 0)
    }

    // MARK: - What the screen says, and that no two states say it the same

    /// **ERRATA E126, and the E158 trap it is standing next to.**
    ///
    /// Four states in which the map is showing something other than the reader. Every one of them
    /// produces a sentence, and no two of them produce the same one — which is the assertion that
    /// would have caught screen 11 telling people their fix was "too weak" before their phone had
    /// answered at all.
    @Test("every state that is not the reader says something, and no two say the same thing")
    func everyStateSaysSomethingDifferent() {
        let showing = MapOpening.Showing.whereYouLeftOff
        let states: [MapLocationProvider.Availability] = [.notAsked, .waitingForFix, .denied, .servicesOff]

        var sentences: [String] = []
        for availability in states {
            let standing = MapOpening.standing(availability: availability, waited: true, showing: showing)
            let words: String
            switch standing {
            case .nothing:
                Issue.record("\(availability) draws a map that is not the reader and says nothing")
                continue
            case let .notAsked(place):
                words = MapOpeningCopy.notAskedTitle + " " + MapOpeningCopy.notAskedMessage(place)
            case let .searching(place):
                words = MapOpeningCopy.searchingTitle + " " + MapOpeningCopy.searchingMessage(place)
            case let .refused(availability, place):
                words = MapLocationCopy.title(availability) + " " + MapLocationCopy.message(place)
            }
            #expect(!words.isEmpty)
            sentences.append(words)
        }

        #expect(sentences.count == 4)
        #expect(
            Set(sentences).count == 4,
            """
            two of the four states the map can be in read identically. Denied, Location Services off, \
            never-asked and still-looking are different facts about the world (E126), and E158 is \
            what it costs to conflate the last of them with a failure.
            """
        )
    }

    /// The one that E158 is specifically about: "we have not heard yet" must not be dressed as a
    /// refusal, and must promise the move the view actually makes.
    @Test("waiting for a first fix reads as waiting, not as a refusal")
    func searchingIsNotARefusal() {
        let message = MapOpeningCopy.searchingMessage(.whereYouLeftOff)
        #expect(message.contains("permission"))
        #expect(message.contains("as soon as one arrives"), "the promise the view keeps is not stated")
        #expect(message.lowercased().contains("off") == false, "the waiting state reads as switched off")
        #expect(MapOpeningCopy.searchingTitle != MapLocationCopy.title(.denied))
        #expect(MapOpeningCopy.searchingTitle != MapLocationCopy.title(.servicesOff))
    }

    /// A refusal is not a wait: there is nothing coming, so nothing is gained by being patient about
    /// it and a reader is left staring at an unexplained map for three seconds if it is.
    @Test("a refusal is said at once; a wait is given a moment first")
    func onlyWaitsArePatient() {
        for availability in [MapLocationProvider.Availability.denied, .servicesOff] {
            #expect(
                MapOpening.standing(availability: availability, waited: false, showing: .theCityFallback)
                    == .refused(availability, .theCityFallback)
            )
        }
        // A launch that is about to succeed must not flash a notice on its way.
        #expect(
            MapOpening.standing(availability: .waitingForFix, waited: false, showing: .whereYouLeftOff)
                == .nothing
        )
        #expect(
            MapOpening.standing(availability: .notAsked, waited: false, showing: .whereYouLeftOff)
                == .nothing
        )
        // And the map on the reader explains nothing, however long it has been.
        #expect(
            MapOpening.standing(
                availability: .located(Coordinate(latitude: 37.76, longitude: -122.41), accuracyM: 5),
                waited: true,
                showing: .whereYouLeftOff
            ) == .nothing
        )
    }

    /// The clause E126 is actually about: not "I cannot find you" but "and *this* is what you are
    /// looking at instead". A reader who has never been to Dolores Park is owed the difference.
    @Test("the notice names the place the map is showing instead")
    func theNoticeNamesThePlace() {
        #expect(MapOpeningCopy.showing(.whereYouLeftOff) != MapOpeningCopy.showing(.theCityFallback))
        #expect(MapOpeningCopy.showing(.whereYouLeftOff).contains("left it"))
        #expect(MapOpeningCopy.showing(.theCityFallback).contains("city"))
        // Every sentence carries it, so no state explains the absence without explaining the presence.
        #expect(MapOpeningCopy.notAskedMessage(.theCityFallback).contains("city"))
        #expect(MapOpeningCopy.searchingMessage(.whereYouLeftOff).contains("left it"))
        #expect(MapLocationCopy.message(.whereYouLeftOff).contains("left it"))
        // `MapRecentreUITests` reads this prefix as its witness that location is denied.
        #expect(MapLocationCopy.message(.theCityFallback).hasPrefix("The map still works"))
    }

    @Test("the wait is only timed while there is something to wait for")
    func waitKinds() {
        #expect(MapOpening.wait(for: .notAsked) == .permission)
        #expect(MapOpening.wait(for: .waitingForFix) == .fix)
        #expect(MapOpening.wait(for: .denied) == .none)
        #expect(MapOpening.wait(for: .servicesOff) == .none)
        // Every fix collapses to the same value, so a reader walking down a street does not restart
        // the timer — and therefore the notice — on every publish.
        let a = MapOpening.wait(for: .located(Coordinate(latitude: 37.76, longitude: -122.41), accuracyM: 5))
        let b = MapOpening.wait(for: .located(Coordinate(latitude: 37.77, longitude: -122.42), accuracyM: 9))
        #expect(a == .none)
        #expect(a == b)
    }
}

/// **The camera that was applied to a map with no area (ERRATA E167).**
///
/// This is the defect underneath #115, and it is not a copy or a fallback problem: with location
/// granted and a fix already on the device, screen 01 opened on Mission Dolores Park and stayed
/// there. Measured on the simulator, from a probe in the layer itself:
///
///     MAKE  seq=0 bounds=(0.0, 0.0) to=37.7596    ← the opening camera, set on a zero-frame map view
///     MADE  region=37.3346                        ← MapKit did not take it; that is its own default
///     APPLY seq=1 bounds=(402.0, 874.0) to=37.7599 ← the fly-to-you, applied at full size
///     REJECT seq=1 applied=1 ×∞                   ← and then every pass after it, forever
///
/// `makeUIView` recorded the ticket as applied when the map had no area to apply it to, so the
/// request minted by the first GPS fix was already "stale" by the time there was a map to show it on
/// — and `MapHomeView.hasCentredOnUser` is a one-shot, so nothing ever asked again.
///
/// Written against the coordinator for `MapCameraOwnershipTests`' reason: the whole loop lives inside
/// the seam and both halves can be driven directly. The gesture was never the doubtful part.
@MainActor
@Suite("A camera cannot be aimed at a map with no area")
struct MapOpeningCameraApplyTests {

    private static let dolores = MapLayout.region(around: MapLayout.defaultCentre)
    private static let user = Coordinate(latitude: 37.7599, longitude: -122.4148)

    private static func metres(_ a: CLLocationCoordinate2D, _ b: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// One layer, its position binding backed by storage the test can drive, and a map view whose
    /// frame the test controls — which is the variable the whole defect turns on.
    @MainActor
    private final class Screen {
        final class Box: @unchecked Sendable {
            var position: MapCameraRequest
            var region = MKCoordinateRegion()
            init(_ position: MapCameraRequest) { self.position = position }
        }

        let box: Box
        let mapView = AimableMapView(frame: .zero)
        let coordinator: MapAnnotationLayer.Coordinator

        init(opening: MKCoordinateRegion) {
            let box = Box(.opening(opening))
            self.box = box
            let layer = MapAnnotationLayer(
                position: Binding(get: { box.position }, set: { box.position = $0 }),
                region: Binding(get: { box.region }, set: { box.region = $0 }),
                clusters: [],
                pins: [],
                userCoordinate: nil,
                selectedPinID: nil,
                onCameraChange: { _, _ in },
                onSelectPin: { _ in },
                onSelectCluster: { _ in }
            )
            coordinator = layer.makeCoordinator()
        }

        /// One `updateUIView` pass, in the part of it this defect touches.
        func updatePass() {
            coordinator.parent.position = box.position
            coordinator.applyCameraIfChanged(box.position, to: mapView)
        }

        /// SwiftUI gets round to laying the map out. `AimableMapView` reports it exactly once.
        func layOut() {
            mapView.onFirstLayout = { [weak self] in
                guard let self else { return }
                coordinator.aimAtCurrentRequest(mapView)
            }
            mapView.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            mapView.layoutIfNeeded()
        }
    }

    /// **The regression.** The fix arrives while the map still has no size — which on a cold launch
    /// is exactly when it arrives — and the camera has to end up on the reader anyway.
    ///
    /// Before the fix this failed with the map on MapKit's default region, some 47 km away.
    @Test("a fix that lands before the map is laid out still moves the camera")
    func fixBeforeLayoutStillArrives() {
        let screen = Screen(opening: Self.dolores)

        // Passes with no map to draw into. This is where the ticket used to be spent.
        for _ in 0..<5 { screen.updatePass() }

        // The first GPS fix: `MapHomeView.flyTo(_:metres:)` for the one-shot opening centring.
        screen.box.position = .move(
            to: MapLayout.region(around: Self.user, metres: MapLayout.defaultSpanMetres)
        )
        for _ in 0..<5 { screen.updatePass() }

        screen.layOut()

        let centre = screen.mapView.region.center
        #expect(
            Self.metres(centre, Self.user) < 60,
            """
            the app asked for the reader's own location before the map had a size and the camera \
            ended up \(Int(Self.metres(centre, Self.user))) m away — this is E167, the map that \
            opens on Dolores Park with a perfect fix in hand
            """
        )
    }

    /// The other order, which has to arrive at the same place: the map is laid out first, opens on
    /// the remembered camera, and the fix moves it afterwards.
    @Test("a fix that lands after the map is laid out moves the camera too")
    func fixAfterLayoutStillArrives() {
        let screen = Screen(opening: Self.dolores)
        screen.layOut()
        screen.updatePass()

        #expect(
            Self.metres(screen.mapView.region.center, MapLayout.defaultCentre) < 60,
            "the opening camera was never applied"
        )

        screen.box.position = .move(
            to: MapLayout.region(around: Self.user, metres: MapLayout.defaultSpanMetres)
        )
        screen.updatePass()

        #expect(Self.metres(screen.mapView.region.center, Self.user) < 60)
    }

    /// The ticket must not be spent on a map that could not be aimed — that is the whole mechanism.
    @Test("a pass with no map to draw into does not spend the ticket")
    func noAreaDoesNotSpendTheTicket() {
        let screen = Screen(opening: Self.dolores)
        for _ in 0..<5 { screen.updatePass() }
        #expect(
            screen.coordinator.appliedSequence == nil,
            "a camera was recorded as applied to a map with no area"
        )
        screen.layOut()
        #expect(screen.coordinator.appliedSequence != nil, "the laid-out map was never aimed")
    }

    /// **E140 must survive all of this.** The reader who pans away stays panned away: a map that has
    /// been laid out is never re-aimed, however many passes arrive carrying the opening camera.
    @Test("the first-layout hook fires once and cannot drag a panned reader back")
    func layoutHookIsOneShot() {
        let screen = Screen(opening: Self.dolores)
        screen.layOut()
        screen.updatePass()

        // The reader drags the map two blocks north-east.
        let pannedTo = CLLocationCoordinate2D(latitude: 37.7635, longitude: -122.4105)
        screen.mapView.setRegion(
            MKCoordinateRegion(center: pannedTo, span: screen.mapView.region.span),
            animated: false
        )
        screen.coordinator.mapView(screen.mapView, regionDidChangeAnimated: false)

        // Another layout — a rotation, a keyboard, a tab switch — and the ordinary storm of passes.
        screen.mapView.frame = CGRect(x: 0, y: 0, width: 402, height: 800)
        screen.mapView.layoutIfNeeded()
        for _ in 0..<10 { screen.updatePass() }

        #expect(
            Self.metres(screen.mapView.region.center, Coordinate(pannedTo)) < 60,
            "a later layout put the map back on the opening camera — this is E140 by another road"
        )
    }
}
