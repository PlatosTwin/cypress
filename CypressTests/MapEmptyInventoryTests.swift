//
//  MapEmptyInventoryTests.swift
//  CypressTests
//
//  Task #190 — screen 01's fifth standing state: the map drew nothing and nothing narrowed it.
//
//  ── What each of these can decide, and what it cannot ─────────────────────────────────────
//  `MapInventoryNotice.isOwed` is a pure function of four facts, so the gates are decidable
//  outright. The *words* are decidable as facts about the string rather than as its phrasing:
//  CLAUDE.md's rule is "assert facts, not phrasing", and the facts this copy must carry are that
//  it says the trees may exist, that it makes no promise, and that it is not any other notice on
//  this screen. What no test here decides is that the sentence is *legible* on a phone — that is
//  the AX5 measurement at the bottom and the screenshots in the branch report.
//

#if DEBUG
import SwiftUI
import Testing
@testable import Cypress

@Suite("The empty-inventory notice (#190)")
struct MapEmptyInventoryTests {

    // MARK: - The four gates

    /// The state the ticket is about: a settled, un-narrowed, successful read that came back with
    /// nothing to draw. Golden Gate Park at street zoom, and every other stretch of ground the
    /// city's street-tree list has never listed.
    @Test("a settled, unnarrowed, successful read with nothing to draw owes the reader a sentence")
    func anEmptyAnswerIsOwedASentence() {
        #expect(
            MapInventoryNotice.isOwed(
                hasSettled: true,
                isNarrowed: false,
                readFailed: false,
                markerCount: 0
            )
        )
    }

    /// **RULINGS R41.** "No message ever accompanies a filter", and its test is "does text appear
    /// because a filter did something?" A species chip that matches nothing empties the map exactly
    /// as standing in the park does, and a sentence posted then would be the fourth
    /// filter-adjacent message ruled out — the state task #165 settled the other way ("if nothing
    /// matches, fine") and `ERRATA E205` re-audited as clean.
    @Test("a narrowed map is never owed the sentence, however empty it is (R41)")
    func aNarrowedMapSaysNothing() {
        #expect(
            !MapInventoryNotice.isOwed(
                hasSettled: true,
                isNarrowed: true,
                readFailed: false,
                markerCount: 0
            ),
            """
            an emptied filter drew the empty-inventory notice. RULINGS R41 is categorical: a \
            filter's entire voice is its chip, and this is the fourth mechanism a companion \
            message has tried to survive under.
            """
        )
    }

    /// **ERRATA E126's own defect, which was exactly this.** Both tab roots drew their cold-start
    /// screen for a read that had failed, because nil content and empty content were the same
    /// value. "Nothing is on record here" is a claim about the record; a read that threw has
    /// learned nothing about the record.
    @Test("a failed read is not an empty record (E126)")
    func aFailedReadIsNotAnEmptyRecord() {
        #expect(
            !MapInventoryNotice.isOwed(
                hasSettled: true,
                isNarrowed: false,
                readFailed: true,
                markerCount: 0
            ),
            "a read that threw was reported to the reader as an empty inventory (E126)"
        )
    }

    /// `MapModel.content` opens at `.pins([])` — the same value an answered-and-empty viewport
    /// produces. Without the settle gate the notice would be posted for the opening publish of
    /// every launch, over any street in the city. `MapOpening.patience` exists for the same
    /// hazard in a different currency.
    @Test("nothing is claimed about a viewport nothing has answered yet")
    func anUnansweredViewportSaysNothing() {
        #expect(
            !MapInventoryNotice.isOwed(
                hasSettled: false,
                isNarrowed: false,
                readFailed: false,
                markerCount: 0
            ),
            "the notice was posted off the model's opening content, before any read had answered"
        )
    }

    /// A map with anything on it explains nothing. One cluster badge standing for 29,390 trees is
    /// emphatically not an empty screen, which is why the gate reads `markerCount` — what the map
    /// has to *draw* — rather than a count of trees.
    @Test("a map with anything drawn on it says nothing")
    func aDrawnMapSaysNothing() {
        for drawn in [1, 2, 400] {
            #expect(
                !MapInventoryNotice.isOwed(
                    hasSettled: true,
                    isNarrowed: false,
                    readFailed: false,
                    markerCount: drawn
                ),
                "a map drawing \(drawn) markers was told it had nothing on record"
            )
        }
    }

    // MARK: - What the sentence has to be true about

    /// **The half of the ticket that is not the drafting.** Golden Gate Park has upwards of a
    /// hundred thousand trees in it and the app knows about none of them (`ERRATA E214`). A notice
    /// a reader could take as "there are no trees here" would be a worse screen than the silent
    /// one it replaces.
    @Test("the notice says the trees may exist, and puts the absence on the record")
    func theTreesAreNotDeniedOnlyTheRecordsAre() {
        let words = MapInventoryCopy.title + " " + MapInventoryCopy.message
        #expect(
            MapInventoryCopy.message.contains("may well stand here"),
            """
            the notice does not say the trees may be standing here; without that clause it reads \
            as "this ground has no trees", which is false of every park in the city
            """
        )
        // The subject of both sentences is the record, so neither can be read as a claim about
        // the ground. Both halves say so in their own words.
        #expect(MapInventoryCopy.title.contains("on record"))
        #expect(words.contains("inventory"))
    }

    /// **`ERRATA E212`'s mistake in another costume.** EveryTreeSF excluded park trees by design,
    /// SF Rec & Park publishes no tree inventory at any status, and no parks phase of the Urban
    /// Forest Plan has ever published data (E214). There is no date to give and no work to
    /// promise, so the sentence gives neither — and it must not grow one later.
    @Test("the notice promises nothing about data arriving")
    func theNoticePromisesNothing() {
        let lowered = MapInventoryCopy.message.lowercased() + " " + MapInventoryCopy.title.lowercased()
        for promise in ["yet", "soon", "coming", "working on", "will be", "we plan", "future", "shortly"] {
            #expect(
                !lowered.contains(promise),
                """
                the empty-inventory notice contains “\(promise)”, which reads as a promise that \
                park trees are on their way. Rec & Park publishes no tree inventory at any status \
                (E214) and a destination claim with nothing behind it is E212.
                """
            )
        }
    }

    /// **It is a boundary of a published dataset, not a failure.** The reader has done nothing
    /// wrong, nothing is loading, and there is nothing to retry — so none of the vocabulary that
    /// would make it read as an error may appear.
    @Test("the notice does not read as an error or as a wait")
    func theNoticeIsNotAnError() {
        let lowered = MapInventoryCopy.message.lowercased() + " " + MapInventoryCopy.title.lowercased()
        for alarm in ["error", "failed", "could not", "unable", "try again", "loading", "problem"] {
            #expect(
                !lowered.contains(alarm),
                """
                the empty-inventory notice contains "\(alarm)", which makes a known boundary of a \
                municipal dataset read as a fault
                """
            )
        }
    }

    /// The assertion `MapOpeningCameraTests.everyStateSaysSomethingDifferent` makes about the four
    /// location states, extended to the fifth occupant of the same slot. E158 is what it costs to
    /// let two different facts about the world reach the reader in the same words.
    @Test("no location state says what the empty-inventory notice says")
    func theFifthStateIsItsOwnSentence() {
        let showing = MapOpening.Showing.whereYouLeftOff
        let others = [
            MapOpeningCopy.notAskedTitle + " " + MapOpeningCopy.notAskedMessage(showing),
            MapOpeningCopy.searchingTitle + " " + MapOpeningCopy.searchingMessage(showing),
            MapLocationCopy.title(.denied) + " " + MapLocationCopy.message(showing),
            MapLocationCopy.title(.servicesOff) + " " + MapLocationCopy.message(showing)
        ]
        let mine = MapInventoryCopy.title + " " + MapInventoryCopy.message
        #expect(!mine.isEmpty)
        #expect(
            !others.contains(mine),
            """
            the empty-inventory notice reads as one of screen 01's location notices; they are \
            different facts about the world (E126, E158)
            """
        )
        // And it must not borrow the *title* of one either — the title is what a reader scanning
        // the card actually reads.
        for title in [
            MapOpeningCopy.notAskedTitle, MapOpeningCopy.searchingTitle,
            MapLocationCopy.title(.denied), MapLocationCopy.title(.servicesOff)
        ] {
            #expect(MapInventoryCopy.title != title)
        }
    }

    /// **The three titles task #165 struck**, which `CypressUITests/MapFilterAccessibilityTests`
    /// also watches for by name. This notice is not that message box coming back under a new
    /// mechanism, and the cheapest way to keep it honest is to refuse the words it wore.
    @Test("the notice is not the struck filter-empty message box under a new name")
    func theNoticeIsNotTheStruckMessageBox() {
        for struck in ["No trees of yours here", "No favorites here", "Nothing matches here"] {
            #expect(MapInventoryCopy.title != struck)
        }
    }

    // MARK: - AX5

    /// **This project has a whole errata family about text growing off the phone**, and the notice
    /// this one reuses is in it: `ERRATA E183 §2` measured `MapLocationNotice` at AX5 taller than
    /// a 390 pt display, laid out from its bottom edge, growing up past `y = 0` with E126's way
    /// out above the top of the screen. That defect is a layout ruling nobody has taken, and it is
    /// not this ticket's to take — but this ticket must not make it worse.
    ///
    /// So the guard is a *comparison against the shipped precedent* rather than a budget invented
    /// here: on the narrowest phone the sweep photographs, the empty-inventory card must be no
    /// taller than the tallest location notice already shipping in the same slot. A copy edit that
    /// pushes it past them will fail this, and the number in the message says by how much.
    ///
    /// It also asserts the width, which is the half `ax5Size` can decide outright (E196 §1).
    @MainActor
    @Test("the notice is no taller at AX5 than the location notices already in its slot")
    func theNoticeFitsTheSlotAtAX5() async {
        let width = AX5ReflowTests.phoneWidth
        let mine = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapInventoryCopy.title,
                message: MapInventoryCopy.message
            ),
            width: width
        )
        let searching = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapOpeningCopy.searchingTitle,
                message: MapOpeningCopy.searchingMessage(.whereYouLeftOff)
            ),
            width: width
        )
        let notAsked = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapOpeningCopy.notAskedTitle,
                message: MapOpeningCopy.notAskedMessage(.theCityFallback)
            ),
            width: width
        )
        let tallestShipped = max(searching.height, notAsked.height)

        #expect(
            mine.width <= width,
            "the empty-inventory notice measured \(mine.width) pt on a \(width) pt phone at AX5"
        )
        #expect(
            mine.height <= tallestShipped,
            """
            the empty-inventory notice is \(mine.height) pt tall at AX5 on a \(width) pt phone, \
            against \(tallestShipped) pt for the tallest location notice already in this slot. \
            E183 §2 is the unfixed defect this must not deepen: the card lays out from its bottom \
            edge and grows off the top of the display.
            """
        )
    }

    // MARK: - The wiring, which is the half a copy test cannot see

    /// **ERRATA E126's own warning, applied to this ticket.** "A test asserting `hasFailed == true`
    /// passes on the broken app — the property was always correct — and so does a test asserting
    /// the copy string exists." Every test above passes with `MapInventoryNotice` written and
    /// nothing calling it. This one drives the real `MapModel` through the real fetch path and
    /// asserts the flag screen 01 reads.
    ///
    /// What it still cannot decide is the last `if` in `MapHomeView.standingNotice`. That is
    /// verified by looking at the running screen — the notice in Golden Gate Park, gone one pan
    /// north across Fulton where the pins start, and drawn again at AX5 — which is the evidence
    /// CLAUDE.md asks for and the screenshots in the branch report.
    @MainActor
    @Test("the model raises the flag for an empty answer and drops it for a drawn one")
    func theModelPublishesTheEmptiness() async throws {
        let api = AnswersOnDemand()
        let model = MapModel(api: api)

        // Nothing has been asked yet: the model's opening `content` is `.pins([])` and must not be
        // mistaken for an answer.
        //
        // **This line documents the state; it does not prove the settle gate.** Watched during the
        // red-proof: with `hasSettled` removed from `isOwed` this expectation stayed green, because
        // nothing has been *assigned* yet and so no `didSet` has run the recompute. The gate itself
        // is proved by `anUnansweredViewportSaysNothing` above, which asks the function directly.
        #expect(!model.inventoryIsEmptyHere, "the flag was up before any read had answered")

        // A screenful the inventory has nothing for — Golden Gate Park.
        await api.answer(with: .pins(PinAnswer([])))
        model.cameraDidChange(bounds: Self.park, zoom: 18)
        try await Self.waitUntil { model.inventoryIsEmptyHere }
        #expect(
            model.inventoryIsEmptyHere,
            "a completed read that drew nothing left screen 01 with nothing to say about it"
        )

        // One pan north, onto a street the inventory does list.
        await api.answer(with: .clusters([TreeCluster(id: "fulton-1", coordinate: Self.fultonCenter, count: 27)]))
        model.cameraDidChange(bounds: Self.fulton, zoom: 18)
        try await Self.waitUntil { !model.inventoryIsEmptyHere }
        #expect(
            !model.inventoryIsEmptyHere,
            "the notice survived onto a map that is drawing markers"
        )
    }

    /// Golden Gate Park, around Stow Lake — the coordinates the survey looked at on the phone.
    private static let park = BoundingBox(
        minLatitude: 37.7680, maxLatitude: 37.7708,
        minLongitude: -122.4878, maxLongitude: -122.4846
    )
    /// One screenful north, across Fulton Street into the Richmond.
    private static let fulton = BoundingBox(
        minLatitude: 37.7740, maxLatitude: 37.7768,
        minLongitude: -122.4878, maxLongitude: -122.4846
    )
    private static let fultonCenter = Coordinate(latitude: 37.7754, longitude: -122.4862)

    /// Polls rather than sleeping a fixed span: the map debounces the camera, and a test that
    /// pinned the debounce would fail the day it is retuned (`MapRecenterTests.waitUntil`).
    ///
    /// **This kept its own 5-second ceiling through #202 and should not have.** The judgment then
    /// was that a suite driving a fake API with no seed could not be starved the way the
    /// seed-backed map suites were. Run 30873340010 refuted it: `inventoryIsEmptyHere → false` at
    /// line 301, on a runner busy enough that five seconds was not enough for a debounce and a
    /// recompute. A fake API removes the I/O, not the scheduler — the wait is wall-clock either
    /// way. It now shares `TestWait.ceiling` with everything else, and reports a timeout as a
    /// timeout instead of returning silently into whichever assertion came next.
    private static func waitUntil(
        timeout: Duration = TestWait.ceiling,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let started = ContinuousClock.now
        let deadline = started + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        let settled = await condition()
        TestWait.timedOut(
            after: started.duration(to: .now), sourceLocation: sourceLocation, { settled }
        )
    }
}

/// A `CypressAPI` that answers `mapContent` with whatever it was last handed, so a viewport the
/// inventory has nothing for and one it has plenty for can both be driven without the 103 MB seed.
/// The subject is `MapModel`'s bookkeeping, and what the read returns is the only input to it.
private actor AnswersOnDemand: CypressAPI {
    private var content: MapContent = .pins(PinAnswer([]))

    func answer(with content: MapContent) { self.content = content }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { content }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
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
#endif
