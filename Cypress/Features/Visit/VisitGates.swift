//
//  VisitGates.swift
//  Cypress — Features/Visit
//
//  The M0 acceptance criterion, as a runnable gate:
//
//      "a visit round-trips through the outbox and appears on that tree's timeline
//       after relaunch."  — ARCHITECTURE §8
//
//  Written the way `Data/Tests/DataGates.swift` is written — framework-free, returning a list of
//  failure strings, empty meaning pass — for the same reason it gives: the *same code* has to be
//  runnable from a Swift Testing target when one exists and from a plain executable today, and
//  "a gate that has never run is not a gate."
//
//  Foundation only. No SwiftUI, no AVFoundation, nothing that needs a device.
//

import Foundation

public enum VisitGates {

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String, into failures: inout [String]) {
        if !condition { failures.append(message()) }
    }

    /// What one phase hands the next across a process boundary.
    ///
    /// Written next to the database, because a *real* termination proof cannot keep anything in
    /// memory between the two halves.
    public struct Manifest: Codable {
        public var visitID: UUID
        public var clientUUID: UUID
        public var treeID: UUID
        public var note: String
        public var photoPath: String
        /// The chip the contributor tapped. Deliberately not `full_tree` in this gate: the framing
        /// used to be invented at upload, and only a non-default value can prove it no longer is.
        public var shotType: ShotType
        public var gpsAccuracyM: Double

        public static func url(besides databaseURL: URL) -> URL {
            databaseURL.deletingLastPathComponent().appendingPathComponent("visit-round-trip.json")
        }
    }

    // MARK: - Phase A · capture, then die

    /// Opens the store, writes a visit to the outbox, and returns **without draining**.
    ///
    /// This is the field case the outbox exists for: the photo is taken, the row is written, and
    /// the process ends before anything has been synced anywhere.
    public static func captureAndAbandon(databaseURL: URL, seedURL: URL?) async throws -> [String] {
        var failures: [String] = []

        let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: seedURL)
        let deviceID = UUID()
        let api = LocalAPI(
            store: store,
            deviceID: deviceID,
            photoDirectory: databaseURL.deletingLastPathComponent().appendingPathComponent("Photos")
        )
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        guard let treeID = try await anyAliveTreeID(in: store) else {
            failures.append("no alive tree in the seed to attach a visit to")
            return failures
        }

        let draft = try makeDraft(treeID: treeID, besides: databaseURL)
        let (visit, item) = try await VisitOutboxWriter.enqueue(
            draft,
            attribution: Attribution.anonymous(deviceID: deviceID),
            outbox: outbox
        )

        expect(item.state == .pending, "a freshly enqueued item should be pending, was \(item.state)", into: &failures)
        expect(
            item.clientUUID == visit.clientUUID,
            "the outbox row must carry the visit's client-generated clientUUID",
            into: &failures
        )
        expect(
            item.photos == [draft.photo!],
            "the photo binary and its shot type must travel with the row, was \(item.photos)",
            into: &failures
        )
        expect(
            visit.gpsAccuracyM != nil,
            "D6: every contribution stores its GPS accuracy",
            into: &failures
        )

        // Nothing has been synced. Prove it, rather than assuming it.
        let timelineBefore = try await api.treeProfile(id: treeID).visits.items
        expect(
            timelineBefore.isEmpty,
            "nothing may reach the timeline before a drain; found \(timelineBefore.count)",
            into: &failures
        )

        let manifest = Manifest(
            visitID: visit.id,
            clientUUID: visit.clientUUID,
            treeID: treeID,
            note: visit.note ?? "",
            photoPath: draft.photoPath!,
            shotType: draft.photo!.shotType,
            gpsAccuracyM: visit.gpsAccuracyM ?? -1
        )
        try JSONEncoder().encode(manifest).write(to: Manifest.url(besides: databaseURL), options: .atomic)

        return failures
    }

    // MARK: - Phase B · relaunch, find it, drain it

    /// Opens the **same file** in a fresh process, asserts the visit is still queued, drains, and
    /// asserts it reached that tree's timeline.
    public static func relaunchAndDrain(databaseURL: URL, seedURL: URL?) async throws -> [String] {
        var failures: [String] = []

        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: Manifest.url(besides: databaseURL))
        )

        let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: seedURL)
        let api = LocalAPI(
            store: store,
            deviceID: UUID(),
            photoDirectory: databaseURL.deletingLastPathComponent().appendingPathComponent("Photos")
        )
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        // --- It survived.
        let queued = try await outbox.records()
        let mine = queued.filter { $0.item.clientUUID == manifest.clientUUID }
        expect(mine.count == 1, "expected exactly one queued row after relaunch, found \(mine.count)", into: &failures)
        guard let record = mine.first else { return failures }
        expect(
            record.item.state == .pending,
            "the surviving row should still be pending, was \(record.item.state)",
            into: &failures
        )
        expect(
            record.item.photos == [OutboxPhoto(path: manifest.photoPath, shotType: manifest.shotType)],
            "the photo reference and its shot type must survive termination too, was \(record.item.photos)",
            into: &failures
        )
        expect(
            FileManager.default.fileExists(atPath: manifest.photoPath),
            "the staged photo binary itself must survive termination (it is not in tmp)",
            into: &failures
        )

        // The payload has to survive intact, not just the row.
        let payload = try OutboxPayload.decode(kind: record.item.kind, from: record.item.payload)
        guard case let .visit(decoded) = payload else {
            failures.append("the surviving payload did not decode as a visit")
            return failures
        }
        expect(decoded.id == manifest.visitID, "visit id changed across relaunch", into: &failures)
        expect(decoded.note == manifest.note, "the note did not survive: \(decoded.note ?? "nil")", into: &failures)
        expect(
            decoded.gpsAccuracyM == manifest.gpsAccuracyM,
            "D6's gpsAccuracyM did not survive: \(String(describing: decoded.gpsAccuracyM))",
            into: &failures
        )

        // --- It drains.
        let report = try await outbox.drain()
        expect(report.synced == 1, "expected one item to sync, report was \(report)", into: &failures)

        // --- It is on the tree's timeline. This is the sentence M0 is graded on.
        let timeline = try await api.treeProfile(id: manifest.treeID).visits.items
        expect(
            timeline.contains { $0.id == manifest.visitID },
            "the visit did not reach tree \(manifest.treeID)'s timeline after the drain",
            into: &failures
        )
        expect(timeline.count == 1, "expected exactly one visit on the timeline, found \(timeline.count)", into: &failures)

        // --- The photo binary went where LocalAPI puts it, and the staging copy is gone.
        expect(
            !FileManager.default.fileExists(atPath: manifest.photoPath),
            "the staged binary should have been moved out of staging by the upload phase",
            into: &failures
        )
        let photos = try await api.treeProfile(id: manifest.treeID).photos.items
        expect(photos.count == 1, "expected one photo record, found \(photos.count)", into: &failures)
        expect(photos.first?.storageKey != nil, "the photo record should carry a storage key once uploaded", into: &failures)
        // The sentence this gate was extended for: what the contributor framed is what got stored.
        // `photos.shot_type` is append-only, so a wrong value here is permanent.
        expect(
            photos.first?.shotType == manifest.shotType,
            "the photo was stored as \(String(describing: photos.first?.shotType)), expected \(manifest.shotType)",
            into: &failures
        )
        expect(
            photos.first?.shotType.supportsGhostOverlay == false,
            "a \(manifest.shotType.rawValue) shot must not become the next visit's framing reference",
            into: &failures
        )

        return failures
    }

    // MARK: - Phase C · relaunch again

    /// Opens the same file a third time and asserts the visit is still on the timeline, and that a
    /// replay of the same `clientUUID` is a no-op.
    public static func relaunchAndVerify(databaseURL: URL, seedURL: URL?) async throws -> [String] {
        var failures: [String] = []

        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: Manifest.url(besides: databaseURL))
        )
        let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: seedURL)
        let api = LocalAPI(
            store: store,
            deviceID: UUID(),
            photoDirectory: databaseURL.deletingLastPathComponent().appendingPathComponent("Photos")
        )

        let profile = try await api.treeProfile(id: manifest.treeID)
        expect(
            profile.visits.items.contains { $0.id == manifest.visitID },
            "the visit is not on the timeline after a second relaunch",
            into: &failures
        )
        expect(profile.visits.items.count == 1, "expected one visit, found \(profile.visits.items.count)", into: &failures)
        expect(
            profile.visits.items.first?.note == manifest.note,
            "the note did not survive the round trip",
            into: &failures
        )
        expect(
            profile.visits.items.first?.gpsAccuracyM == manifest.gpsAccuracyM,
            "D6's gpsAccuracyM did not survive the round trip",
            into: &failures
        )

        // Idempotency on the client-generated key: replaying the identical item must come back a
        // duplicate and must not create a second row.
        let replay = try await api.sync([
            OutboxPayload.visit(profile.visits.items[0]).makeItem(photos: [])
        ])
        expect(replay.first?.status == .duplicate, "a replay should be a duplicate, was \(String(describing: replay.first?.status))", into: &failures)
        let after = try await api.treeProfile(id: manifest.treeID).visits.items
        expect(after.count == 1, "a replay created a second row: \(after.count)", into: &failures)

        // The outbox row settled rather than lingering.
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let states = try await outbox.records()
            .filter { $0.item.clientUUID == manifest.clientUUID }
            .map(\.item.state)
        expect(states == [.done], "expected the row to be done, was \(states)", into: &failures)

        return failures
    }

    // MARK: - All three, in one process

    /// The whole round trip with the store closed and reopened between phases.
    ///
    /// Weaker than running the three phases as three processes — the same address space is reused —
    /// so the harness does both. This one is what a Swift Testing target will call.
    public static func roundTrip(seedURL: URL?) async throws -> [String] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-visit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("cypress.sqlite")
        var failures: [String] = []
        failures += try await captureAndAbandon(databaseURL: databaseURL, seedURL: seedURL)
        failures += try await relaunchAndDrain(databaseURL: databaseURL, seedURL: seedURL)
        failures += try await relaunchAndVerify(databaseURL: databaseURL, seedURL: seedURL)
        return failures
    }

    // MARK: - The pure rules of screen 02

    /// D6's ranking rules, checked without a simulator: they are the difference between a correct
    /// attribution and a permanent, silent one on an append-only record.
    public static func shortlistRules() async throws -> [String] {
        var failures: [String] = []

        func tree(_ latitude: Double, _ longitude: Double) -> Tree {
            Tree(
                source: .cityImport,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                status: .alive
            )
        }
        func row(_ distance: Double, name: String = "Monterey Cypress") -> NearbyTree {
            NearbyTree(
                tree: tree(37.7596 + distance / 111_320, -122.4269),
                distanceM: distance,
                speciesScientificName: "Hesperocyparis macrocarpa",
                speciesCommonName: name,
                tell: nil
            )
        }

        // --- Two trees 2 m apart under a ±9 m fix cannot be told apart: confirm.
        let ambiguous = VisitShortlist.rank([row(6), row(8, name: "Ginkgo")], accuracyM: 9)
        expect(ambiguous.requiresConfirmation, "D6: 2 m apart under ±9 m must require confirmation", into: &failures)
        expect(!ambiguous.highlightsTopCandidate, "an ambiguous list must not pre-select a card", into: &failures)

        // --- The same two trees under a ±1 m fix are separable: no confirmation.
        let separable = VisitShortlist.rank([row(6), row(8, name: "Ginkgo")], accuracyM: 1)
        expect(!separable.requiresConfirmation, "±1 m separates trees 2 m apart", into: &failures)

        // --- The documented auto-highlight rule: top ≤ 3 m, runner-up ≥ 10 m.
        let confident = VisitShortlist.rank([row(3), row(14, name: "Ginkgo")], accuracyM: 4)
        expect(confident.highlightsTopCandidate, "top 3 m / next 14 m at ±4 m should highlight", into: &failures)
        expect(!confident.requiresConfirmation, "an unambiguous list needs no confirmation tap", into: &failures)

        // --- A fix wider than the gap between street trees is the low-GPS state, and it always
        //     asks, whatever the geometry says.
        let coarse = VisitShortlist.rank([row(3), row(40, name: "Ginkgo")], accuracyM: 45)
        expect(coarse.state == .lowAccuracy, "±45 m is the low-GPS state", into: &failures)
        expect(coarse.requiresConfirmation, "a low-GPS list always requires confirmation", into: &failures)
        expect(!coarse.highlightsTopCandidate, "a low-GPS list must not pre-select", into: &failures)

        // --- No accuracy reported is treated as the pessimistic case, never as certainty.
        let unknown = VisitShortlist.rank([row(3), row(14, name: "Ginkgo")], accuracyM: nil)
        expect(unknown.requiresConfirmation, "an unknown error circle must not unlock the fast path", into: &failures)

        // --- No fix at all, and nothing nearby.
        expect(VisitShortlist.rank([row(3)], accuracyM: 5, hasFix: false).state == .noLocation,
               "no fix is its own state", into: &failures)
        expect(VisitShortlist.rank([], accuracyM: 5).state == .empty, "no candidates is its own state", into: &failures)

        // --- The list is nearest-first and capped at eight.
        let many = VisitShortlist.rank((1...20).map { row(Double($0) * 3) }, accuracyM: 5)
        expect(many.candidates.count == VisitShortlist.maximumCandidates,
               "the shortlist caps at 8, was \(many.candidates.count)", into: &failures)
        expect(many.candidates.map(\.distanceM) == many.candidates.map(\.distanceM).sorted(),
               "the shortlist must be nearest-first", into: &failures)

        // --- The confidence bar lands where the mock draws it on the mock's own numbers.
        let drawn = VisitShortlist.confidence(topDistanceM: 3, runnerUpDistanceM: 14, accuracyM: 9)
        expect((0.85...0.90).contains(drawn), "the drawn card's confidence should read ~88 %, was \(drawn)", into: &failures)

        // --- D6's distinguishing trait falls back to inventory facts, never to invented botany.
        var a = tree(37.7596, -122.4269); a.address = "1200 Judah St"
        var b = tree(37.7597, -122.4269); b.address = "1208 Judah St"
        let pair = VisitDistinguisher.traits(
            VisitCandidate(nearby: NearbyTree(tree: a, distanceM: 6, speciesScientificName: nil,
                                              speciesCommonName: nil, tell: nil)),
            VisitCandidate(nearby: NearbyTree(tree: b, distanceM: 8, speciesScientificName: nil,
                                              speciesCommonName: nil, tell: nil))
        )
        expect(pair?.first.value == "1200 Judah St", "two unnamed trees are told apart by address", into: &failures)
        expect(pair?.first.isCuratedTell == false, "no curated tell exists yet — it must not claim one", into: &failures)
        expect(pair?.first.isRedundantWithCard == false, "an address is not already on the card", into: &failures)

        // Two different species are told apart by their names, which the card already shows — the
        // trait must say so rather than printing the title twice.
        var c = tree(37.7596, -122.4269)
        var d = tree(37.7597, -122.4269)
        c.address = "1200 Judah St"; d.address = "1200 Judah St"
        let speciesPair = VisitDistinguisher.traits(
            VisitCandidate(nearby: NearbyTree(tree: c, distanceM: 6, speciesScientificName: "Ginkgo biloba",
                                              speciesCommonName: "Ginkgo", tell: nil)),
            VisitCandidate(nearby: NearbyTree(tree: d, distanceM: 8, speciesScientificName: "Platanus × hispanica",
                                              speciesCommonName: "London Plane", tell: nil))
        )
        expect(speciesPair?.first.isRedundantWithCard == true, "species is already the card's title", into: &failures)

        return failures
    }

    /// D5's rules for screen 04's chip row.
    public static func phenologyVocabulary() async throws -> [String] {
        var failures: [String] = []

        func species(
            _ name: String,
            _ retention: LeafRetention?,
            curated: Bool,
            fallColorMonths: [Int] = []
        ) throws -> Species {
            try Species(
                scientificName: name,
                commonName: name,
                leafRetention: retention,
                seasonal: SeasonalCalendar(fallColorMonths: fallColorMonths),
                curated: curated
            )
        }

        // --- No species record at all.
        expect(VisitPhenologyVocabulary.tags(for: nil).isEmpty, "no species, no chips", into: &failures)

        // --- Uncurated: the whole of today's seed. No phenology surface at all (BUILD-PLAN §8).
        let uncurated = try species("Liquidambar orientalis", .deciduous, curated: false)
        expect(
            VisitPhenologyVocabulary.tags(for: uncurated).isEmpty,
            "an uncurated species must offer no phenology chips",
            into: &failures
        )

        // --- D5, the headline: an evergreen is never offered fall colour or bare.
        let evergreen = try species("Hesperocyparis macrocarpa", .evergreen, curated: true)
        let evergreenTags = VisitPhenologyVocabulary.tags(for: evergreen)
        expect(!evergreenTags.contains(.fallColor), "D5: an evergreen is never asked about fall color", into: &failures)
        expect(!evergreenTags.contains(.bare), "D5: an evergreen is never asked about bare", into: &failures)
        expect(!evergreenTags.isEmpty, "a curated evergreen still has a vocabulary", into: &failures)

        // --- A deciduous species gets both, in seasonal order.
        let deciduous = try species("Ginkgo biloba", .deciduous, curated: true, fallColorMonths: [10, 11])
        let deciduousTags = VisitPhenologyVocabulary.tags(for: deciduous)
        expect(deciduousTags.contains(.fallColor), "a deciduous species is offered fall color", into: &failures)
        expect(
            deciduousTags == VisitPhenologyVocabulary.order.filter(deciduousTags.contains),
            "the chip row must read in seasonal order, was \(deciduousTags)",
            into: &failures
        )

        // --- Habit unknown: no chip at all, even though the entry is curated. 59 of the seed's
        // 569 species are in this state and every one of them is a species somebody authored
        // content for and nobody could source a leaf retention for (ERRATA E9).
        let unknownHabit = try species("Ficus laurel", nil, curated: true)
        expect(
            VisitPhenologyVocabulary.tags(for: unknownHabit).isEmpty,
            "a species whose habit no source states must offer no phenology chips",
            into: &failures
        )
        expect(
            PhenologyTag.validated(PhenologyTag.allCases, for: unknownHabit).isEmpty,
            "the outbox write must drop every phenology tag for a species with no habit",
            into: &failures
        )

        // --- The season strip clamps for an unknown habit exactly as it does for an evergreen:
        // drawing a bare month is a claim about the canopy, leaving it out is not.
        let bareWinter: [FoliageStrip.Density] = [.bare, .bare, .thin, .full, .full, .full,
                                                  .full, .full, .full, .thin, .bare, .bare]
        let unknownStrip = await FoliageStrip.enforcingD5(bareWinter, leafRetention: nil)
        let deciduousStrip = await FoliageStrip.enforcingD5(bareWinter, leafRetention: .deciduous)
        expect(
            !unknownStrip.contains(.bare),
            "the season strip must not render a bare month for a species with no habit",
            into: &failures
        )
        expect(
            deciduousStrip.contains(.bare),
            "a deciduous species must keep its bare months",
            into: &failures
        )

        // --- And the write path re-validates, so a stale UI cannot smuggle one through.
        expect(
            PhenologyTag.validated([.fallColor, .fullLeaf], for: evergreen) == [.fullLeaf],
            "the outbox write must drop a tag the species cannot carry",
            into: &failures
        )

        return failures
    }

    // MARK: - Helpers

    private static func anyAliveTreeID(in store: CypressStore) async throws -> UUID? {
        try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare(
                "SELECT uuid FROM \(SeedDatabase.schemaName).trees WHERE status = 'alive' LIMIT 1"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuid("uuid") }
        }
    }

    /// A draft with a real file behind it, so the photo phase of the drain is exercised for real.
    private static func makeDraft(treeID: UUID, besides databaseURL: URL) throws -> VisitDraft {
        let visitID = UUID()
        let staging = databaseURL.deletingLastPathComponent().appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let photo = staging.appendingPathComponent("\(visitID.uuidString).jpg")
        // Not a real JPEG — nothing in the write path decodes it, and the point is that the bytes
        // travel and land.
        try Data("cypress round-trip photo \(visitID)".utf8).write(to: photo, options: .atomic)

        return VisitDraft(
            visitID: visitID,
            treeID: treeID,
            note: "Fog dripping off the crown",
            phenologyTags: [],
            gpsAccuracyM: 9,
            // A trunk shot, because the bug this gate now guards was that every shot arrived
            // labelled `full_tree`, and the default would have passed either way.
            photo: OutboxPhoto(path: photo.path, shotType: .trunk),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
