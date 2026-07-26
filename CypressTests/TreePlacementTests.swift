import Foundation
import Testing
import UIKit
@testable import Cypress

/// `community_trees.placement` — the record's own answer to "where did this coordinate come from".
///
/// The movable pin shipped without it: the screen modelled the distinction and stated it, and the row
/// kept only `lat` and `lon`, so a coordinate somebody had placed by hand was indistinguishable on
/// disk from one the phone had guessed. AppSchema v10 gives it a column and this suite is what holds
/// the whole path down.
///
/// ── Every assertion here reads the column, not the model ──────────────────────────────────────
/// `PinAdjustTests` records why, and the reason is a defect this project has produced twice: a test
/// that asks the object it just configured whether it holds the right value proves nothing about the
/// write. So the two load-bearing cases below go through the real screen, the real `addTree` and the
/// real store, and then read `placement` out of `community_trees` with SQL. The negative case matters
/// as much as the positive one — a column with a `DEFAULT` is very easy to get backwards, and a
/// suite that only ever checks the hand-placed arm would pass with the value hard-coded.
@Suite("Tree placement")
struct TreePlacementTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD03")!
    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    /// `PinAdjustTests`' corner of the Mission. The seed is not attached here, so the only trees
    /// inside any dedupe radius are the ones a test adds.
    private static let fix = Coordinate(latitude: 37.7599, longitude: -122.4148)

    @MainActor
    private static func model(api: any CypressAPI) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(fix, accuracyM: 24)),
            attribution: attribution
        )
    }

    /// A real 1×1 JPEG: the model decodes the frame before it accepts it, so a fixture that is not an
    /// image never reaches the path that ships.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    /// The stored string, exactly as SQLite holds it — not `Tree.placement`, which is a decode of it.
    private static func storedPlacement(of id: UUID, in store: CypressStore) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT placement FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind(id.uuidString, forName: ":id")
            return try statement.fetchOne { try $0.stringIfPresent("placement") } ?? nil
        }
    }

    // MARK: - What actually lands in the column

    /// **The assertion this round exists for.**
    ///
    /// A moved pin, through the screen, through `TreeDraft`, through `addTree`, through
    /// `CommunityTreeStore.insert` — and then read back with SQL. Any of those layers could drop the
    /// provenance and leave a model that says the right thing about a row that says `gps`.
    @MainActor
    @Test("a tree added with a moved pin is stored as placed by hand")
    func aMovedPinIsStoredAsPlaced() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(Self.fix, northM: 45, eastM: 20))
        #expect(subject.treePlacement == .contributorPlaced)

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await Self.storedPlacement(of: id, in: store)
        #expect(stored == "contributor_placed", "the column says \(String(describing: stored))")
        // And the decode agrees with the column, which is what every screen actually reads.
        let decoded = try await api.treeProfile(id: id).tree.placement
        #expect(decoded == .contributorPlaced)
    }

    /// The other direction, and the one a `DEFAULT` makes easy to get backwards: stand-shoot-save
    /// writes `gps`, and must never be recorded as a judgement nobody made.
    @MainActor
    @Test("a tree added without touching the map does not claim to have been placed by hand")
    func theFastPathIsStoredAsGPS() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())
        #expect(subject.treePlacement == .gps)

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await Self.storedPlacement(of: id, in: store)
        #expect(stored == "gps", "the column says \(String(describing: stored))")
        let decoded = try await api.treeProfile(id: id).tree.placement
        #expect(decoded == .gps)
    }

    /// Opening the map, looking around and confirming without moving anything is not a placement.
    /// `confirmPin` already folds that back to `.gps`; this is the assertion that it reaches the
    /// column that way too, because "the reader saw the map" is not the fact being recorded.
    @MainActor
    @Test("a pin put back where it started is stored as GPS, not as a placement of the same point")
    func aPinLeftAtTheFixIsStoredAsGPS() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(Self.fix, northM: 40, eastM: 0))
        subject.beginPlacingPin()
        subject.confirmPin(Self.fix)
        #expect(subject.treePlacement == .gps)

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await Self.storedPlacement(of: id, in: store)
        #expect(stored == "gps", "the column says \(String(describing: stored))")
    }

    // MARK: - The engine holds the vocabulary

    /// The vocabulary is a CHECK, not a convention, so it holds against a hand-written `INSERT` the
    /// way this schema's other closed vocabularies do. Without it the engine would accept `'GPS'` and
    /// `CommunityTreeStore.decode` would throw on a row the database had blessed.
    @Test("the column refuses a value that is not one of the two")
    func theVocabularyIsEnforcedByTheEngine() async throws {
        let store = try await CypressStore.inMemory()
        let moment = SQLiteTimestamp.string(from: Date())
        await #expect(throws: SQLiteError.self) {
            try await store.queue.write { connection in
                try connection.execute("""
                    INSERT INTO community_trees
                        (id, client_uuid, source, lat, lon, status, verification_state,
                         placement, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','community',
                            37.76,-122.41,'alive','unverified','GPS','\(moment)','\(moment)')
                    """)
            }
        }
    }

    // MARK: - The upgrade

    /// A database written by the previous build, migrated. This is the path that can destroy
    /// somebody's data, and the only one a fresh install never exercises.
    ///
    /// The row goes in against the v9 schema — no `placement` column exists to write, which is the
    /// point — and has to come out the other side intact and reading `gps`, because that is what the
    /// old add screen actually did. `gps` is not a guess about these rows; it is their history.
    @Test("a community tree written before the column survives the upgrade and reads as GPS")
    func theUpgradePreservesExistingTrees() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 9 }, on: connection)
        let columnsBefore = try connection.columnNames(ofTable: "community_trees")
        #expect(!columnsBefore.contains("placement"), "a v9 database already had the column")

        let id = UUID()
        let moment = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        try connection.execute("""
            INSERT INTO community_trees
                (id, client_uuid, source, lat, lon, address, status, verification_state,
                 created_at, updated_at)
            VALUES ('\(id.uuidString)','\(UUID().uuidString)','community',
                    37.7599,-122.4148,'1 Folsom St','alive','unverified','\(moment)','\(moment)')
            """)

        // Every step above 9, not literally `[10]`: this gate is about an existing row surviving, and
        // it must not fail the day an unrelated migration is added.
        let expected = AppSchema.migrations.map(\.version).filter { $0 > 9 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected, "migrating a v9 database applied \(applied), expected \(expected)")
        let version = try connection.userVersion
        #expect(version == AppSchema.currentVersion)

        let store = CommunityTreeStore()
        let survivor = try #require(
            try store.tree(id: id, connection: connection),
            "the community tree did not survive the migration"
        )
        #expect(survivor.placement == .gps)
        #expect(survivor.address == "1 Folsom St", "the migration disturbed a column it does not own")
        #expect(survivor.coordinate.distance(to: Coordinate(latitude: 37.7599, longitude: -122.4148)) < 0.01)

        // Replaying the step must be a no-op rather than "duplicate column name", because a run
        // interrupted between the DDL and the version bump replays.
        try AppSchema.migrations.first(where: { $0.version == 10 })?.migrate(connection)
        let afterReplay = try store.tree(id: id, connection: connection)?.placement
        #expect(afterReplay == .gps, "replaying the step left the row at \(String(describing: afterReplay))")

        // And the CHECK the upgraded database gained is the CHECK a fresh one has.
        #expect(throws: SQLiteError.self) {
            try connection.execute("""
                INSERT INTO community_trees
                    (id, client_uuid, source, lat, lon, status, verification_state,
                     placement, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','community',
                        37.76,-122.41,'alive','unverified','manual','\(moment)','\(moment)')
                """)
        }
    }

    // MARK: - Screen 03

    private static func tree(source: TreeSource, placement: TreePlacement) -> Tree {
        Tree(
            source: source,
            coordinate: fix,
            address: "1 Folsom St",
            status: .alive,
            verificationState: source == .cityImport ? .cityRecord : .unverified,
            placement: placement
        )
    }

    private static func subtitle(source: TreeSource, placement: TreePlacement) -> String {
        TreeProfilePresentation(profile: TreeProfile(tree: tree(source: source, placement: placement)))
            .subtitle
    }

    /// The half of the owner's ruling that is easiest to skip: it has to be *on screen*.
    @Test("a hand-placed community tree says so on its provenance line")
    func theProfileStatesAHandPlacedPosition() {
        let line = Self.subtitle(source: .community, placement: .contributorPlaced)
        #expect(line.contains(TreeProfilePresentation.placementByHand), "the subtitle reads: \(line)")
        // Beside the provenance already there, not instead of it.
        #expect(line.contains("community-added, unverified"))
    }

    /// **The reason both arms are printed.** A label that appears only on the hand-placed tree makes
    /// that tree the exceptional one, and an exceptional coordinate reads as a suspect coordinate.
    /// This is the assertion that the unmarked case does not exist.
    @Test("a GPS community tree states its provenance too, so neither case is the marked one")
    func theProfileStatesAGPSPositionAsWell() {
        let line = Self.subtitle(source: .community, placement: .gps)
        #expect(line.contains(TreeProfilePresentation.placementFromGPS), "the subtitle reads: \(line)")
        #expect(!line.contains(TreeProfilePresentation.placementByHand))
    }

    /// A city row's coordinate came from neither of these, and has no column behind it.
    @Test("a city record claims neither placement")
    func aCityTreeClaimsNoPlacement() {
        let line = Self.subtitle(source: .cityImport, placement: .gps)
        #expect(line.contains("SF city inventory"))
        #expect(!line.contains("position"), "the subtitle reads: \(line)")
        let note = TreeProfilePresentation(
            profile: TreeProfile(tree: Self.tree(source: .cityImport, placement: .gps))
        ).placementNote
        #expect(note == nil)
    }

    /// The copy is provenance rather than a verdict. Held bluntly, because the failure mode is a
    /// later edit that "clarifies" it into a warning — which is the one thing the owner's ruling and
    /// `TreePlacement` both refuse.
    @Test("neither placement line evaluates the coordinate it describes")
    func thePlacementCopyPassesNoJudgement() {
        let judgements = [
            "approx", "unverified position", "estimate", "estimated", "inaccurate", "accuracy",
            "warning", "caution", "may be", "might be", "unreliable", "unconfirmed", "rough"
        ]
        for line in [TreeProfilePresentation.placementFromGPS, TreeProfilePresentation.placementByHand] {
            let lowered = line.lowercased()
            for word in judgements {
                #expect(!lowered.contains(word), "\"\(line)\" reads as a verdict on the coordinate")
            }
            // Both name the instrument and nothing else, in the same shape, so neither is the
            // exception on the line.
            #expect(lowered.hasPrefix("position "), "\"\(line)\" is not parallel with its counterpart")
        }
    }
}
