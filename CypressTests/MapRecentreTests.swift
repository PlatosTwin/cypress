import Foundation
import Testing
@testable import Cypress

/// **The control that must never be silent.**
///
/// Screen 01's recentre button is the one control on the map whose whole reason for existing is that
/// every press produces something the reader can see — the owner's standing complaint all week has
/// been controls that do nothing when tapped. `MapRecentre.press(availability:camera:)` is where that
/// promise is kept or broken, so this suite asserts it exhaustively: there is a case here for every
/// case of `MapLocationProvider.Availability`, and the enum being total is checked rather than
/// assumed.
///
/// The zoom rule is the other half. First press centres and keeps the reader's scale; a press that is
/// already centred goes to the screen's own opening scale; a camera already inside that scale is not
/// dragged back out by a control that says it zooms in. See `MapRecentre`'s header for the argument.
@MainActor
@Suite("Map recentre control")
struct MapRecentreTests {

    /// Somewhere in the Mission, a coordinate this test suite does not otherwise care about.
    private static let user = Coordinate(latitude: 37.7601, longitude: -122.4270)

    /// A camera `metres` across, centred `offsetDegrees` of latitude away from the user.
    ///
    /// The span is built the way `MapLayout.region(around:metres:)` builds it — metres divided by the
    /// degree — so the numbers here mean the same thing they mean on screen.
    private static func camera(
        metres: Double,
        offsetLatitude: Double = 0,
        offsetLongitude: Double = 0
    ) -> MapRecentre.Camera {
        let span = metres / MapRecentre.metresPerDegreeLatitude
        return MapRecentre.Camera(
            centre: Coordinate(
                latitude: user.latitude + offsetLatitude,
                longitude: user.longitude + offsetLongitude
            ),
            latitudeSpan: span,
            longitudeSpan: span
        )
    }

    // MARK: - The three permission states

    @Test("permission never asked: the press asks")
    func notAskedAsks() {
        #expect(MapRecentre.press(availability: .notAsked, camera: Self.camera(metres: 400)) == .ask)
    }

    /// The case the ask is really about. A denied permission is permanent from the app's side — iOS
    /// never re-presents the sheet — so a press that quietly failed would fail forever and look
    /// identical to a broken button.
    @Test("permission refused: the press explains, in both refusal states")
    func refusedExplains() {
        for availability in [MapLocationProvider.Availability.denied, .servicesOff] {
            #expect(
                MapRecentre.press(availability: availability, camera: Self.camera(metres: 400))
                    == .explainRefusal,
                "\(availability) must produce an explanation, not a no-op"
            )
        }
    }

    @Test("granted but no fix yet: the press says it is waiting")
    func waitingSaysSo() {
        #expect(
            MapRecentre.press(availability: .waitingForFix, camera: Self.camera(metres: 400))
                == .waitForFix
        )
    }

    /// The structural half of the claim: no availability the provider can report falls through to
    /// nothing. If a sixth case is ever added, this fails rather than the map going quietly inert in
    /// it.
    @Test("every availability the provider can report produces a visible press")
    func everyAvailabilityAnswers() {
        let all: [MapLocationProvider.Availability] = [
            .notAsked,
            .waitingForFix,
            .denied,
            .servicesOff,
            .located(Self.user, accuracyM: 8)
        ]
        for availability in all {
            let press = MapRecentre.press(availability: availability, camera: Self.camera(metres: 400))
            switch press {
            case .ask, .explainRefusal, .waitForFix, .centre, .centreAndZoomIn:
                continue
            }
        }
        #expect(all.count == 5, "a new Availability case needs a decision here")
    }

    // MARK: - The zoom rule

    @Test("panned away: the press centres and keeps the reader's scale")
    func offCentreKeepsZoom() {
        // 600 m across, and the camera is a third of that off centre — plainly not on the user.
        let press = MapRecentre.press(
            availability: .located(Self.user, accuracyM: 8),
            camera: Self.camera(metres: 600, offsetLatitude: 0.0018)
        )
        #expect(press == .centre(Self.user))
    }

    /// The second step. Already on the dot, still looking at half a kilometre: the only question left
    /// is "closer".
    @Test("already centred and zoomed out: the press goes to the opening scale")
    func centredZoomsIn() {
        let press = MapRecentre.press(
            availability: .located(Self.user, accuracyM: 8),
            camera: Self.camera(metres: 600)
        )
        #expect(press == .centreAndZoomIn(Self.user))
    }

    /// The guard that keeps "zoom in" from being a zoom *out*. A reader pinched to 60 m is closer
    /// than the opening 120, and driving them to 120 would pull the camera back.
    @Test("already centred and closer than the opening scale: the press does not pull back out")
    func centredAndCloseDoesNotZoomOut() {
        let press = MapRecentre.press(
            availability: .located(Self.user, accuracyM: 8),
            camera: Self.camera(metres: 60)
        )
        #expect(press == .centre(Self.user))
    }

    /// The threshold itself, from both sides. 1.5 × 120 m = 180 m.
    @Test("the zoom-in step waits until the camera is half again the opening scale")
    func zoomInThreshold() {
        let opening = MapLayout.defaultSpanMetres
        let below = MapRecentre.press(
            availability: .located(Self.user, accuracyM: 8),
            camera: Self.camera(metres: opening * MapRecentre.zoomInThreshold - 1)
        )
        let above = MapRecentre.press(
            availability: .located(Self.user, accuracyM: 8),
            camera: Self.camera(metres: opening * MapRecentre.zoomInThreshold + 1)
        )
        #expect(below == .centre(Self.user))
        #expect(above == .centreAndZoomIn(Self.user))
    }

    // MARK: - What counts as centred

    /// A fraction of the span, not a distance — the same offset in metres is dead centre on a
    /// city-wide camera and off screen at 120 m, and the button is about the picture.
    @Test("centred is a fraction of the visible span, not a distance on the ground")
    func centredScalesWithTheSpan() {
        // 20 m north of the user. At 120 m across that is a sixth of the screen — not centred.
        let offset = 20 / MapRecentre.metresPerDegreeLatitude
        #expect(Self.camera(metres: 120, offsetLatitude: offset).isCentred(on: Self.user) == false)
        // The same 20 m on a 2 km camera is 1 % of the span.
        #expect(Self.camera(metres: 2_000, offsetLatitude: offset).isCentred(on: Self.user))
    }

    /// Before MapKit settles once there is no span, and a camera with no span is not centred on
    /// anything — otherwise the very first press would be read as the second one and would zoom.
    @Test("a camera with no span is not centred")
    func zeroSpanIsNotCentred() {
        let camera = MapRecentre.Camera(centre: Self.user, latitudeSpan: 0, longitudeSpan: 0)
        #expect(camera.isCentred(on: Self.user) == false)
        #expect(
            MapRecentre.press(availability: .located(Self.user, accuracyM: 8), camera: camera)
                == .centre(Self.user)
        )
    }

    @Test("longitude drift counts as much as latitude drift")
    func longitudeCountsToo() {
        let camera = Self.camera(metres: 400, offsetLongitude: 400 * 0.2 / MapRecentre.metresPerDegreeLatitude)
        #expect(camera.isCentred(on: Self.user) == false)
    }

    // MARK: - What the button draws

    @Test("the button reports its own state before anybody presses it")
    func engagementIsContinuous() {
        let located = MapLocationProvider.Availability.located(Self.user, accuracyM: 8)
        #expect(
            MapRecentre.engagement(availability: located, camera: Self.camera(metres: 400)) == .centred
        )
        #expect(
            MapRecentre.engagement(
                availability: located,
                camera: Self.camera(metres: 400, offsetLatitude: 0.002)
            ) == .away
        )
        // Refused is the one state drawn as struck through, because it is the only one where
        // pressing cannot ever move the camera without the reader going to Settings first.
        #expect(MapRecentre.engagement(availability: .denied, camera: Self.camera(metres: 400)) == .unavailable)
        #expect(MapRecentre.engagement(availability: .servicesOff, camera: Self.camera(metres: 400)) == .unavailable)
    }

    // MARK: - What the button says it is doing (#100)

    /// **The two states that used to borrow the word "centred" from a state they are not in.**
    ///
    /// `notAsked` and `waitingForFix` were both drawn — and both *spoken* — as `away`, so VoiceOver
    /// said `Not centred` over a map that had no reader to be centred on. A sighted reader gets that
    /// word as a caption on a picture; a VoiceOver reader gets it as the entire report, and in these
    /// two states it describes a relationship that does not exist.
    @Test("not-asked and still-looking are not reported as an off-centre map")
    func theTwoUnknownStatesAreNotJustOffCentre() {
        let camera = Self.camera(metres: 400)
        #expect(MapRecentre.engagement(availability: .notAsked, camera: camera) == .askable)
        #expect(MapRecentre.engagement(availability: .waitingForFix, camera: camera) == .searching)
        #expect(
            MapRecentreCopy.value(.askable) != MapRecentreCopy.value(.away),
            "an unanswered permission ask is still spoken as an off-centre map"
        )
        #expect(
            MapRecentreCopy.value(.searching) != MapRecentreCopy.value(.away),
            "a phone that has not answered yet is still spoken as an off-centre map"
        )
    }

    /// The structural claim, so a sixth engagement cannot be added and left mute: every state the
    /// control can be in says something, no two of them say the same thing, and each is the state the
    /// *press* in that situation would produce.
    @Test("every engagement speaks, and no two speak alike")
    func everyEngagementSpeaksDistinctly() {
        let all: [MapRecentre.Engagement] = [.centred, .away, .askable, .searching, .unavailable]
        let spoken = all.map { MapRecentreCopy.value($0) }
        #expect(spoken.allSatisfy { !$0.isEmpty })
        #expect(
            Set(spoken).count == all.count,
            "two states of the recentre control tell a VoiceOver reader the same thing: \(spoken)"
        )
        // `away` is the one with nothing to add — the label and the value already say it all.
        for engagement in all where engagement != .away {
            #expect(MapRecentreCopy.hint(engagement) != nil, "\(engagement) promises nothing")
        }
    }

    /// The spoken state has to be a prediction of the press, or it is decoration. Every availability
    /// that produces a *different* press produces a different engagement, and the two that a press
    /// cannot distinguish — the only pair here is the two refusals — are the two the standing notice
    /// tells apart instead (`MapLocationCopy.title`).
    @Test("the spoken state predicts what pressing will do")
    func engagementTracksThePress() {
        let camera = Self.camera(metres: 400, offsetLatitude: 0.002)
        let cases: [(MapLocationProvider.Availability, MapRecentre.Press, MapRecentre.Engagement)] = [
            (.notAsked, .ask, .askable),
            (.waitingForFix, .waitForFix, .searching),
            (.denied, .explainRefusal, .unavailable),
            (.servicesOff, .explainRefusal, .unavailable),
            (.located(Self.user, accuracyM: 8), .centre(Self.user), .away)
        ]
        for (availability, press, engagement) in cases {
            #expect(MapRecentre.press(availability: availability, camera: camera) == press)
            #expect(
                MapRecentre.engagement(availability: availability, camera: camera) == engagement,
                "\(availability) presses as \(press) but describes itself as something else"
            )
        }
    }

    // MARK: - The words

    /// `AccessibilityTreeTests.testNoUnlabelledButtonsOnLaunch` fails on an unlabelled control on
    /// screen 01, and it should. This is the cheaper half of the same check: the label exists, says
    /// what the control does rather than what it looks like, and every state has a value to go with
    /// it.
    @Test("the control is labelled, and every state has something to say")
    func everyStateSpeaks() {
        #expect(!MapRecentreCopy.label.isEmpty)
        #expect(MapRecentreCopy.label.lowercased().contains("centre"))
        for engagement in [MapRecentre.Engagement.centred, .away, .askable, .searching, .unavailable] {
            #expect(!MapRecentreCopy.value(engagement).isEmpty, "\(engagement) has no spoken state")
        }
        #expect(MapRecentreCopy.hint(.centred) != nil)
        #expect(MapRecentreCopy.hint(.unavailable) != nil)
    }

    /// The refusal sentence is `VisitAddTreeCopy.noLocationDenied`'s shape — name the limit, say what
    /// it costs here, point at the one thing that undoes it — without being that sentence. Two
    /// screens saying the identical thing about different situations is how copy goes stale.
    @Test("the refusal matches the app's voice without being a copy of it")
    func refusalVoice() {
        let message = MapRecentreCopy.refusalMessage
        #expect(message.hasPrefix("Cypress cannot see where you are"))
        #expect(message.contains("Settings"))
        #expect(message != VisitAddTreeCopy.noLocationDenied)
        // It is about the map, which is the clause that makes it a different sentence.
        #expect(message.contains("map"))
    }

    @Test("the refusal titles tell the two refusals apart")
    func refusalTitles() {
        #expect(MapRecentreCopy.refusalTitle(.servicesOff) != MapRecentreCopy.refusalTitle(.denied))
        #expect(MapRecentreCopy.refusalTitle(.denied) == MapLocationCopy.title(.denied))
    }

    /// The waiting notice promises the map will move when a fix arrives, and `MapHomeView` keeps that
    /// promise with `recentreWhenFixArrives`. If the sentence ever stops making the promise, the
    /// held press becomes a surprise instead of a kept word.
    @Test("the waiting notice promises the move the view actually makes")
    func waitingPromise() {
        #expect(MapRecentreCopy.waitingMessage.contains("as soon as one arrives"))
        #expect(!MapRecentreCopy.waitingTitle.isEmpty)
    }
}

/// **The narrowing must survive a recentre (ERRATA E134).**
///
/// The search bar narrows the map to a species by putting the species ids on `MapViewport`. Moving
/// the camera builds a new viewport — that is the whole of what a recentre does — so if the rebuild
/// dropped the narrowing, pressing the control would silently widen the map back to every tree while
/// leaving the query in the field. The reader would be looking at a map that no longer matched what
/// they typed and nothing on screen would say so.
@MainActor
@Suite("Recentring through an active search")
struct MapRecentreSearchTests {

    private static func viewport(_ model: MapModel) throws -> MapViewport {
        try #require(model.viewport, "the model has no viewport")
    }

    /// Waits for the model to settle, the way `MapSearchTests` does.
    private static func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(20)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Drives the model exactly as a recentre does: the camera moves, `cameraDidChange` fires with a
    /// new box, and the viewport is rebuilt.
    @Test("moving the camera keeps the species the search narrowed to")
    func cameraMoveKeepsTheNarrowing() async throws {
        let api = RecordingSearchAPI()
        let model = MapModel(api: api)

        // A settled camera over the Mission at pin zoom.
        model.cameraDidChange(bounds: Self.mission, zoom: 18)
        #expect(try Self.viewport(model).speciesIDs == nil)

        // A query resolves. `searchText` debounces, so this waits for the model to settle rather
        // than for a fixed span — `MapSearchTests.waitUntil`'s argument, and the same reason: the
        // debounce is tuned for a thumb, and a test that pinned it would fail when it was retuned.
        model.searchText = "London plane"
        try await Self.waitUntil { model.search.isActive }
        let narrowed = try #require(Self.viewport(model).speciesIDs)
        #expect(narrowed == [RecordingSearchAPI.londonPlane])

        // Now recentre: the camera lands somewhere else, at the same zoom.
        model.cameraDidChange(bounds: Self.elsewhere, zoom: 18)
        let after = try Self.viewport(model)
        #expect(after.speciesIDs == narrowed, "the recentre widened the map back to every species")
        #expect(after.bounds.contains(Self.elsewhere), "the camera did not actually move")
        #expect(model.search.isActive, "the search stopped being active")
    }

    /// And the zoom step, which changes the zoom as well as the centre — the path most likely to
    /// rebuild the viewport from scratch and lose something.
    @Test("zooming in on the recentre's second step keeps the narrowing too")
    func zoomStepKeepsTheNarrowing() async throws {
        let api = RecordingSearchAPI()
        let model = MapModel(api: api)
        model.cameraDidChange(bounds: Self.mission, zoom: 16)
        model.searchText = "London plane"
        try await Self.waitUntil { model.search.isActive }
        let narrowed = try #require(Self.viewport(model).speciesIDs)

        model.cameraDidChange(bounds: Self.tight, zoom: 18)
        #expect(try Self.viewport(model).speciesIDs == narrowed)
    }

    private static let mission = BoundingBox(
        minLatitude: 37.7835, maxLatitude: 37.7862,
        minLongitude: -122.4232, maxLongitude: -122.4198
    )
    private static let elsewhere = BoundingBox(
        minLatitude: 37.7590, maxLatitude: 37.7617,
        minLongitude: -122.4290, maxLongitude: -122.4256
    )
    private static let tight = BoundingBox(
        minLatitude: 37.7845, maxLatitude: 37.7851,
        minLongitude: -122.4220, maxLongitude: -122.4212
    )
}

/// A `CypressAPI` that answers a species search and nothing else, so the narrowing can be driven
/// without the 95 MB seed. The subject here is `MapViewport.speciesIDs` surviving a camera move, and
/// that is decided entirely in `MapModel` — what comes back from the read cannot change it.
private struct RecordingSearchAPI: CypressAPI {

    static let londonPlane = UUID(uuidString: "7d22dcda-354d-5f7d-9be0-3739ea8c6688")!

    func searchSpecies(query: String, limit: Int) async throws -> [Species] {
        [
            try Species(
                id: Self.londonPlane,
                scientificName: "Platanus x hispanica",
                commonName: "London plane",
                leafRetention: .deciduous
            )
        ]
    }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}
