//
//  SpeciesGuideNearbyPhotosTests.swift
//  CypressTests
//
//  ERRATA E204, closing the one item it left "found, and deliberately left alone": screen 07 §6's
//  `Nearby individuals` carried `NearbySpeciesTree.photoCount` but never *which* photograph, so a
//  row for a tree this device had actually photographed still drew the species placeholder.
//
//  Two claims, end to end through `LocalAPI.speciesGuide` rather than against the batched read in
//  isolation, because the wiring — `LocalAPI` handing the right id to `NearbySpeciesTree`, which
//  `SpeciesView.nearbyRow` then hands to `PhotoImage` — is exactly the part a unit test of
//  `ContributionStore.heroPhotoIDs(treeIDs:)` alone (see `PhotoHeroTests`) cannot see:
//
//  1. **Same rule as the profile.** The row's `heroPhotoID` agrees with
//     `TreeProfilePresentation.bestPhoto`, the tree's own hero, for the identical tree — proof
//     the batched read reuses `PhotoHero.choose` rather than a second "which photo" rule (E204's
//     own instruction).
//  2. **A tree with no photographs draws the placeholder path.** `heroPhotoID` is `nil`, not a
//     guess, and `PhotoImage(photoID: nil)` is already proven elsewhere (`PhotoHeroTests`,
//     `MapCardSubject` tests) to fall back to the gradient — this pins the fact this call site
//     hands it the right absence rather than that fallback itself.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Species page · Nearby individuals draw real photographs (ERRATA E204)")
struct SpeciesGuideNearbyPhotosTests {

    // MARK: - Harness

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static let seed = SeedDatabase.schemaName
    private static let deviceID = UUID(uuidString: "E2040000-0000-4000-8000-000000000204")!
    private static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    /// An in-memory database needs a real directory for `debugSeedPhotos`'s binaries: `:memory:`'s
    /// `databaseURL` resolves to the root of a read-only volume (`PhotoHeroTests`' own comment).
    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e204-photos-\(UUID().uuidString)", isDirectory: true)
    }

    private static func harness() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(
            store: store,
            deviceID: deviceID,
            photoDirectory: Self.photoDirectory(),
            now: { now }
        )
        return (api, store)
    }

    /// The `offset`th seeded tree that carries a species, by uuid order — resolved from the
    /// attached seed rather than pinned, the way `SecondCityGeographyTests`' probes are, so the
    /// test is about the read and not about one row surviving a re-ingest.
    private static func seedTree(
        offset: Int,
        on store: CypressStore
    ) async throws -> (treeID: UUID, speciesID: UUID, coordinate: Coordinate) {
        let found = try await store.queue.read { connection -> (UUID, UUID, Double, Double)? in
            let statement = try connection.prepare("""
                SELECT t.uuid AS tree_uuid, s.uuid AS species_uuid, t.lat, t.lon
                  FROM \(seed).trees t
                  JOIN \(seed).species s ON s.id = t.species_current
                 WHERE t.deleted_at IS NULL
                 ORDER BY t.uuid LIMIT 1 OFFSET \(offset)
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in
                (
                    try row.uuid("tree_uuid"),
                    try row.uuid("species_uuid"),
                    try row.double("lat"),
                    try row.double("lon")
                )
            }
        }
        let (treeID, speciesID, lat, lon) = try #require(found, "the seed has no species-bearing tree at offset \(offset)")
        return (treeID, speciesID, Coordinate(latitude: lat, longitude: lon))
    }

    // MARK: - 1 · The rule is reused, not reinvented

    @Test("a nearby row leads with the same photograph the tree's own profile hero would")
    func nearbyRowAgreesWithTheProfileHero() async throws {
        let (api, store) = try await Self.harness()
        let tree = try await Self.seedTree(offset: 0, on: store)

        // `debugSeedPhotos` writes straight into `main.photos`, keyed only by `tree_uuid` — it has
        // no dependency on the tree being one this device added, which is exactly what lets a
        // seeded city tree gain a photograph the way any tree a contributor visits does.
        let ids = try await api.debugSeedPhotos(treeID: tree.treeID, count: 3)

        // Querying at the tree's own coordinate puts it at distance 0, so it is certainly one of
        // the (at most two) rows the section draws.
        let guide = try await api.speciesGuide(id: tree.speciesID, near: tree.coordinate)
        let row = try #require(
            guide.nearby.items.first { $0.treeID == tree.treeID },
            "the seeded tree's own coordinate did not surface it in its own species' nearby list"
        )

        let profile = try await api.treeProfile(id: tree.treeID)
        let profileHero = TreeProfilePresentation(profile: profile).bestPhoto?.id

        #expect(row.heroPhotoID == ids[0], "did not agree with A3's own ordering (newest full-tree shot)")
        #expect(
            row.heroPhotoID == profileHero,
            "the nearby row's photo disagreed with the tree's own profile hero — a second 'which photo' rule"
        )
    }

    @Test("a thumbs-up moves the nearby row's photo exactly as it moves the profile hero's")
    func nearbyRowRespectsVotes() async throws {
        let (api, store) = try await Self.harness()
        let tree = try await Self.seedTree(offset: 1, on: store)
        let ids = try await api.debugSeedPhotos(treeID: tree.treeID, count: 3)

        try await api.setPhotoVote(photoID: ids[2], vote: .up)

        let guide = try await api.speciesGuide(id: tree.speciesID, near: tree.coordinate)
        let row = try #require(guide.nearby.items.first { $0.treeID == tree.treeID })

        let profile = try await api.treeProfile(id: tree.treeID)
        let profileHero = TreeProfilePresentation(profile: profile).bestPhoto?.id

        #expect(row.heroPhotoID == ids[2], "the pin overrode the heuristic for the profile but not the nearby row")
        #expect(row.heroPhotoID == profileHero)
    }

    // MARK: - 2 · A sparse section is the correct, honest output

    @Test("a tree nobody has photographed on this device still draws — no invented hero id")
    func nearbyRowWithNoPhotosHasNoHeroID() async throws {
        let (api, store) = try await Self.harness()
        // Offset 2: a fresh install, nothing has called `debugSeedPhotos` for this tree.
        let tree = try await Self.seedTree(offset: 2, on: store)

        let guide = try await api.speciesGuide(id: tree.speciesID, near: tree.coordinate)
        let row = try #require(guide.nearby.items.first { $0.treeID == tree.treeID })

        #expect(row.photoCount == 0, "a tree this device never photographed reported photos anyway")
        #expect(row.heroPhotoID == nil, "an untouched tree must fall through to the placeholder, not invent an id")
    }

    // MARK: - 3 · A stranger's photograph, end to end (ERRATA E215, review of #222/PR #16)
    //
    // The adversarial review of this PR constructed the failing case directly against
    // `ContributionStore.heroPhotoIDs(treeIDs:)`: a seeded `.pending` photograph not owned by the
    // caller still came back as the hero, because the batched read filtered only
    // `deleted_at IS NULL`. `PhotoHeroTests`' "4c" section pins the store method in isolation;
    // this pins the same fact through the real call path — `LocalAPI.speciesGuide` — against the
    // real seed, the way a defect here would actually reach the species page.

    private static let strangerID = UUID(uuidString: "57A4DE00-0000-4000-8000-00000000E216")!

    private static func insertStrangersPhoto(
        id: UUID = UUID(),
        treeID: UUID,
        moderationState: ModerationState,
        capturedAt: Date,
        connection: SQLiteConnection
    ) throws {
        let stamp = SQLiteTimestamp.string(from: capturedAt)
        try connection.execute("""
            INSERT INTO photos
                (id, tree_uuid, shot_type, moderation_state, captured_at, created_at, updated_at, user_id)
            VALUES ('\(id.uuidString)', '\(treeID.uuidString)', 'full_tree', '\(moderationState.rawValue)',
                    '\(stamp)', '\(stamp)', '\(stamp)', '\(Self.strangerID.uuidString)')
            """)
    }

    @Test("a stranger's unmoderated photo does not reach the species page as a nearby hero")
    func nearbyRowExcludesAStrangersPendingPhoto() async throws {
        let (api, store) = try await Self.harness()
        let tree = try await Self.seedTree(offset: 3, on: store)

        try await store.queue.write { connection in
            try Self.insertStrangersPhoto(
                treeID: tree.treeID, moderationState: .pending, capturedAt: Self.now, connection: connection
            )
        }

        let guide = try await api.speciesGuide(id: tree.speciesID, near: tree.coordinate)
        let row = try #require(guide.nearby.items.first { $0.treeID == tree.treeID })

        #expect(
            row.heroPhotoID == nil,
            "a stranger's unmoderated photograph reached the species page — the case the review named"
        )
    }

    @Test("a stranger's approved photo can reach the species page as a nearby hero")
    func nearbyRowAdmitsAStrangersApprovedPhoto() async throws {
        let (api, store) = try await Self.harness()
        let tree = try await Self.seedTree(offset: 4, on: store)
        let approved = UUID()

        try await store.queue.write { connection in
            // Same reasoning as `PhotoHeroTests`' "4c": an older pending row beside the approved
            // one tells "exclude an unmoderated stranger" apart from "exclude every stranger".
            try Self.insertStrangersPhoto(
                treeID: tree.treeID, moderationState: .pending,
                capturedAt: Self.now.addingTimeInterval(-86_400), connection: connection
            )
            try Self.insertStrangersPhoto(
                id: approved, treeID: tree.treeID, moderationState: .approved,
                capturedAt: Self.now, connection: connection
            )
        }

        let guide = try await api.speciesGuide(id: tree.speciesID, near: tree.coordinate)
        let row = try #require(guide.nearby.items.first { $0.treeID == tree.treeID })

        #expect(
            row.heroPhotoID == approved,
            "a stranger's approved photograph should have led — moderation, not ownership, is meant to gate this"
        )
    }
}
