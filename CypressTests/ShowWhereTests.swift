import Foundation
import Testing
@testable import Cypress

/// **"I have no idea where tree is"** (ERRATA E144).
///
/// The project owner, from their own iPhone: *"In almanac under this season need a way to find the
/// tree mentioned. Right now clicking just takes to tree page but I have no idea where tree is"*.
///
/// E129 answered the same sentence for the almanac's two *counted* rows and these assertions are
/// deliberately shaped like that suite's, because the failure mode is the same one: everything is
/// correct except the question being answered. A map that opens at city scale is a correct map. A
/// map that centres on the right block and draws thirty identical pins is a correct map. Neither one
/// gets a person to the tree, so the assertions are about the properties that do:
///
/// 1. **the record is on the map from the first frame** — it travels on the payload, so there is no
///    window in which the camera has arrived and the pin has not;
/// 2. **the camera lands at pin scale on the record itself**, not on whatever else came back;
/// 3. **the record is marked**, through the selection the map already has, so one of thirty pins is
///    the one that was asked about;
/// 4. **a basin and a memorial get the same answer**, because both are places and both are reachable
///    from the lists that lead here.
@Suite("Show me where this is")
struct ShowWhereTests {

    // MARK: - Fixtures

    private static let locale = Locale(identifier: "en_US")
    private static let coordinate = Coordinate(latitude: 37.7601, longitude: -122.4014)
    private static let treeID = UUID(uuidString: "E1440000-0000-4000-8000-000000000001")!

    private static func tree(
        status: TreeStatus = .alive,
        address: String? = "2576 Lombard St"
    ) -> Tree {
        Tree(
            id: treeID,
            source: .cityImport,
            coordinate: coordinate,
            address: address,
            status: status,
            verificationState: .cityRecord
        )
    }

    private static func profile(
        status: TreeStatus = .alive,
        address: String? = "2576 Lombard St",
        neighborhood: String? = "Marina"
    ) -> TreeProfile {
        TreeProfile(tree: tree(status: status, address: address), neighborhoodName: neighborhood)
    }

    /// A neighbour on the same block, `metres` north of the subject.
    private static func neighbor(_ index: Int, metersNorth: Double) -> TreePin {
        TreePin(
            id: UUID(uuidString: "E1440000-0000-4000-8000-00000000010\(index)")!,
            coordinate: Coordinate(
                latitude: coordinate.latitude + metersNorth / 111_320,
                longitude: coordinate.longitude
            ),
            status: .alive,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    private static func present(
        _ set: PinSet,
        context: [TreePin] = []
    ) -> PinSetPresentation {
        PinSetPresentation(set: set, context: context, locale: locale)
    }

    // MARK: - 1 · The record is on the map before anything is read

    /// **The failure this guards against is a camera that flies somewhere and shows nothing.**
    ///
    /// The block around the record is a database read and it has not returned when the screen
    /// appears. If the subject were part of that answer, the map would open on an empty street and
    /// fill in a beat later — and on a slow read, or a failed one, it would never fill in at all. It
    /// is on the payload instead, so the pin is in the drawn set with no read having happened.
    @Test("the record is drawn with no neighbours read, and stays first when they arrive")
    func subjectIsDrawnBeforeTheReadReturns() {
        let set = PinSet.locate(Self.profile(), name: "Lombard Elm")

        let cold = Self.present(set)
        #expect(cold.pins.map(\.id) == [Self.treeID])

        let warm = Self.present(set, context: [Self.neighbor(1, metersNorth: 12)])
        #expect(warm.pins.first?.id == Self.treeID)
        #expect(warm.pins.count == 2)
    }

    /// The read returns the subject too — it is a tree in its own box — and one record must not
    /// become two annotations with one id.
    @Test("a neighbour read that includes the subject does not draw it twice")
    func contextDoesNotDuplicateTheSubject() {
        let set = PinSet.locate(Self.profile(), name: "Lombard Elm")
        let subjectAgain = TreePin(
            id: Self.treeID,
            coordinate: Self.coordinate,
            status: .alive,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )

        let presentation = Self.present(
            set,
            context: [subjectAgain, Self.neighbor(1, metersNorth: 12)]
        )

        #expect(presentation.pins.count == 2)
        #expect(presentation.pins.filter { $0.id == Self.treeID }.count == 1)
    }

    // MARK: - 2 · The camera lands at pin scale, on the record

    /// **`MapLayout.defaultSpanMetres`, the scale ERRATA E12 measured** as the one where San
    /// Francisco's street trees stop fusing into a mat. A camera framed on the group would be the
    /// right answer for E129's nine and the wrong one here: with neighbours 200 m away the box would
    /// open at 400 m and the subject would be a dot among dots.
    @Test("the camera is the opening span, centred on the record and not on its neighbours")
    func cameraIsPinScaleOnTheRecord() {
        let set = PinSet.locate(Self.profile(), name: "Lombard Elm")
        let frame = Self.present(
            set,
            context: [Self.neighbor(1, metersNorth: 400), Self.neighbor(2, metersNorth: -400)]
        ).frame

        let centerLatitude = (frame.minLatitude + frame.maxLatitude) / 2
        let centerLongitude = (frame.minLongitude + frame.maxLongitude) / 2
        #expect(abs(centerLatitude - Self.coordinate.latitude) < 0.000_001)
        #expect(abs(centerLongitude - Self.coordinate.longitude) < 0.000_001)

        let metersTall = (frame.maxLatitude - frame.minLatitude) * 111_320
        #expect(abs(metersTall - MapLayout.defaultSpanMeters) < 1)
    }

    // MARK: - 3 · Which of the thirty it is

    /// The selection the map already has (`MapAnnotationLayer.applySelection`), pointed at the one
    /// record before the reader touches anything.
    @Test("the record is the focused pin, and a counted group has no focus at all")
    func theRecordIsFocused() {
        let one = PinSet.locate(Self.profile(), name: "Lombard Elm")
        #expect(one.focusPinID == Self.treeID)
        #expect(Self.present(one).focusPinID == Self.treeID)

        let nine = PinSet(
            subject: .coverageGap,
            pins: [Self.neighbor(1, metersNorth: 10), Self.neighbor(2, metersNorth: 20)],
            count: 9,
            neighborhoodName: "Marina"
        )
        #expect(nine.focusPinID == nil)
        #expect(Self.present(nine).focusPinID == nil)
    }

    /// The sentence says which pin, by the name at the top of the screen — and does not describe a
    /// block that is not drawn yet. ERRATA E38's rule applied to scenery: say what is on the map.
    @Test("the sentence names the marked pin, and mentions the block only once it is there")
    func theSentenceNamesTheMark() {
        let set = PinSet.locate(Self.profile(), name: "Lombard Elm")

        #expect(Self.present(set).coverage == "The larger pin is Lombard Elm.")
        #expect(
            Self.present(set, context: [Self.neighbor(1, metersNorth: 12)]).coverage
                == "The larger pin is Lombard Elm. The rest of the block is drawn around it."
        )
    }

    /// The two lines above the map are the name the reader tapped and the street they are walking
    /// to. Neither is re-derived here.
    @Test("the screen is titled with the record's name and headed with its street")
    func titleAndStreet() {
        let presentation = Self.present(PinSet.locate(Self.profile(), name: "Lombard Elm"))
        #expect(presentation.title == "Lombard Elm")
        #expect(presentation.subject == "2576 Lombard St")
        #expect(presentation.neighborhoodName == "Marina")
    }

    /// A vacant site's H1 *is* its address, and a city tree with no species falls back to the same
    /// string, so on those records the street line was the title printed twice. Seen on the
    /// simulator: `601 Dolores St` under `601 Dolores St`.
    @Test("the street line is absent when the title is already the street")
    func theStreetIsNotSaidTwice() {
        let site = SitePresentation(profile: Self.profile(status: .vacantSite, address: "601 Dolores St"))
        let presentation = Self.present(site.locateSet)
        #expect(presentation.title == "601 Dolores St")
        #expect(presentation.subject.isEmpty)
    }

    @Test("a record the city gave no address says so rather than borrowing the neighbourhood")
    func noAddressIsSaidPlainly() {
        let presentation = Self.present(
            PinSet.locate(Self.profile(address: nil), name: "Lombard Elm")
        )
        #expect(presentation.subject == PinSetCopy.noAddress)
        #expect(!presentation.subject.contains("Marina"))
    }

    // MARK: - 4 · A basin and a memorial are places too

    /// Both are reachable from My Grove, the journal and the map card, and both used to be dead ends
    /// for this question. The pin keeps its own status, so C19 draws each in its own vocabulary
    /// (RULINGS R7) and no copy on either screen has to mention it.
    @Test("a vacant site and a memorial travel as themselves")
    func siteAndMemorialKeepTheirKind() {
        let site = SitePresentation(profile: Self.profile(status: .vacantSite, address: "1 Main St"))
        #expect(site.locateSet.pins.first?.status == .vacantSite)
        #expect(site.locateSet.focusPinID == Self.treeID)

        let memorial = MemorialPresentation(profile: Self.profile(status: .removed))
        #expect(memorial.locateSet.pins.first?.status == .removed)
        #expect(memorial.locateSet.focusPinID == Self.treeID)

        let profile = TreeProfilePresentation(profile: Self.profile())
        #expect(profile.locateSet.pins.first?.status == .alive)
        #expect(profile.locateSet.focusPinID == Self.treeID)
    }

    /// Each of the three names the map with its own H1, which is the line the reader has just read.
    @Test("the map is titled with the name the screen it came from is showing")
    func eachScreenNamesItsOwnMap() {
        let site = SitePresentation(profile: Self.profile(status: .vacantSite, address: "1 Main St"))
        #expect(Self.present(site.locateSet).title == site.title)

        let profile = TreeProfilePresentation(profile: Self.profile())
        #expect(Self.present(profile.locateSet).title == profile.title)
    }

    // MARK: - 5 · The one read this screen makes

    private struct Block: CypressAPI {
        var content: MapContent
        let asked: Asked = Asked()

        final class Asked: @unchecked Sendable {
            var viewport: MapViewport?
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent {
            asked.viewport = viewport
            return content
        }

        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
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

    /// **It has to ask for pins, not for badges.** A1 clusters at zoom 15 and below, so a viewport
    /// built one level lower would come back as a single badge reading "31" — a picture of the block
    /// with the block taken out of it. And the box is the camera's own, so nothing is fetched that
    /// cannot be seen.
    @Test("the block is read un-clustered, over the box the camera opens on")
    func theReadAsksForPins() async {
        let api = Block(content: .pins(PinAnswer([Self.neighbor(1, metersNorth: 12)])))

        let pins = await PinSetNeighbors.around(api).read(Self.coordinate)

        #expect(pins.count == 1)
        let viewport = try! #require(api.asked.viewport)
        #expect(!viewport.shouldCluster)
        #expect(viewport.bounds.contains(Self.coordinate))
        let metersTall = (viewport.bounds.maxLatitude - viewport.bounds.minLatitude) * 111_320
        #expect(abs(metersTall - MapLayout.defaultSpanMeters) < 1)
    }

    /// A clustered answer is no answer to this question, and a failed read is not an error to show.
    /// Either way the screen is the one-pin map it would have been anyway.
    @Test("a clustered or failed read leaves the map alone")
    func aClusteredAnswerIsDiscarded() async {
        let clustered = Block(content: .clusters([
            TreeCluster(id: "c", coordinate: Self.coordinate, count: 31)
        ]))
        #expect(await PinSetNeighbors.around(clustered).read(Self.coordinate).isEmpty)
        #expect(await PinSetNeighbors.none.read(Self.coordinate).isEmpty)
    }

    // MARK: - 6 · E129's two rows are untouched

    /// The group of one shares this screen, and sharing it must not have changed what the counted
    /// groups say. `PinSet.count` is still a total and the sentence over the map is still E38's.
    @Test("a counted group still says how much of itself is on the map")
    func countedGroupsAreUnchanged() {
        let page = PinSet(
            subject: .vacantSites,
            pins: (1...3).map { Self.neighbor($0, metersNorth: Double($0) * 10) },
            count: 1_474,
            neighborhoodName: "Marina"
        )
        // Digits for a page and words for a whole group, which is `PinSetCopy.coverage`'s own
        // distinction and not a slip: a page size is a quantity and `All nine` is a sentence.
        #expect(Self.present(page).coverage == "The 3 nearest are on this map.")
        #expect(!page.isComplete)

        let whole = PinSet(
            subject: .coverageGap,
            pins: (1...3).map { Self.neighbor($0, metersNorth: Double($0) * 10) },
            count: 3,
            neighborhoodName: "Marina"
        )
        #expect(Self.present(whole).coverage == "All three are on this map.")
        #expect(whole.isComplete)
    }
}
