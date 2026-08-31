import CryptoKit
import Foundation
import Testing
@testable import Cypress

/// The Cities screen's answers to the tester reports filed against build 49 on 2026-08-23.
///
/// Each test below names the report it guards. They are grouped here rather than folded into
/// `CityDownloadTests` because that suite asserts RULINGS R43's table *as ruled*, and three of
/// these assert where this round amended it — keeping the two apart means a future reader can see
/// which expectations are the ruling's and which are the amendments', without diffing.
///
/// Nothing here touches the network. The downloader is exercised against `file://` fixtures and
/// against an in-process `URLProtocol` serving http (`CityBucketFixtureProtocol`) — the second
/// because it lets a test choose the transfer's pacing, which a file URL does not
/// (`progressIsReportedDuringTheTransfer` says what was measured, and corrects the claim that a
/// file URL reports no progress at all). No port is opened and no packet leaves the machine either
/// way. Every other fact is a pure value.
@Suite("Cities screen — tester feedback")
struct CityDownloadsFeedbackTests {

    // MARK: - Fixtures

    /// A published entry, with the two keys update detection now reads spelled out.
    static func entry(
        id: String = "us-ny-nyc-manhattan",
        displayName: String = "Manhattan",
        coverage: String = "full",
        schemaVersion: Int = 17,
        version: String,
        contentRev: String?,
        region: CityManifest.Region? = nil,
        bytes: Int64 = 66_891_776
    ) -> CityManifest.City {
        CityManifest.City(
            id: id,
            displayName: displayName,
            coverage: coverage,
            treeCount: 1,
            schemaVersion: schemaVersion,
            version: version,
            contentRev: contentRev,
            region: region,
            path: "cities/\(id)/\(version)/\(id).sqlite",
            bytes: bytes,
            sha256: "ab"
        )
    }

    static func borough(_ id: String, _ name: String) -> CityManifest.City {
        entry(
            id: "us-ny-nyc-\(id)",
            displayName: name,
            version: "s17-r2026-08-22-ac7b1ccc",
            contentRev: "2026-08-22",
            region: CityManifest.Region(
                level: "borough", parentCity: "us-ny-nyc", parentCityDisplayName: "New York City"
            )
        )
    }

    static func row(
        _ city: CityManifest.City,
        state: CityInstallState,
        hasInstallHeadroom: Bool = true
    ) -> CityDownloadRow {
        .published(
            city: city, state: state, hasInstallHeadroom: hasInstallHeadroom,
            downloadingFraction: nil, lastAttemptFailed: false
        )
    }

    /// The manifest's own region lookup, as `CityDownloadsModel.sections` supplies it.
    static func parentCity(
        in cities: [CityManifest.City]
    ) -> (CityDownloadRow) -> (id: String, displayName: String)? {
        { row in
            guard let region = cities.first(where: { $0.id == row.id })?.region else { return nil }
            return (id: region.parentCity, displayName: region.parentCityDisplayName)
        }
    }

    // MARK: - Report: "I can't seem to use manhattan even though it's on my phone"

    /// **The report is answered by the union rather than by a third button**.
    ///
    /// The tester reached a dead end by using Manhattan, switching back to the built-in inventory,
    /// and finding no way back — *"I can't seem to use manhattan even though it's on my phone"*.
    /// The round that received that report added `Use` to this row. This round removes the state
    /// that made it necessary: a downloaded city is in the union the moment it lands, so there is
    /// no click that can put it out of use and nothing to offer a way back from.
    ///
    /// What is asserted is the stronger property — **no state can reach a row that is on the
    /// device and undrawable**, because being on the device is what being drawn means now.
    @Test("an installed city with an update waiting is drawn, with no verb for being drawn")
    func anInstalledCityIsAlwaysInTheUnion() {
        let manhattan = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")
        let state = CityInstallState.updateAvailable(installedVersion: "s17-r2026-08-01-1111aaaa")

        let row = Self.row(manhattan, state: state)
        #expect(row.affordances == [.update, .remove])
        #expect(row.isOnDevice, "an installed city is not on the device, so it is not in the union")
    }

    /// Every state that says a copy is on the device draws only verbs that make sense for a copy
    /// that is **already being drawn**: take a newer record, or give it up.
    ///
    /// This replaces a gate that checked `Use` was never offered for a city with nothing to attach.
    /// The vocabulary it policed is gone, so the gate polices the vocabulary itself: an affordance
    /// meaning "make this the one the map draws" would be the exclusive switch returning, and it
    /// would have to get past this.
    @Test("an on-device state draws only verbs that suit a city already being drawn")
    func onDeviceStatesDrawOnlyKeepingVerbs() {
        let city = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")
        let states: [CityInstallState] = [
            .notInstalled,
            .installedCurrent(installedVersion: "s17-r2026-08-22-ac7b1ccc"),
            .updateAvailable(installedVersion: "s17-r2026-08-01-1111aaaa"),
            .needsNewerApp(installedVersion: nil),
            .needsNewerApp(installedVersion: "s17-r2026-08-01-1111aaaa"),
            .bundled(contentRev: "2026-07-31"),
            .bundledOutdated(bundledContentRev: "2026-07-31"),
            .bundledUpdated(installedContentRev: "2026-08-22", updateAvailable: false),
            .bundledUpdated(installedContentRev: "2026-08-22", updateAvailable: true)
        ]
        let permitted: Set<CityDownloadRow.Affordance> = [.download, .update, .remove, .revert]
        for state in states {
            let row = Self.row(city, state: state)
            #expect(
                Set(row.affordances).isSubset(of: permitted),
                "\(state) draws \(row.affordances), which is outside the screen's vocabulary"
            )
            // `Download` is the one verb that may not appear for a city already held.
            if state.isOnDevice {
                #expect(
                    !row.affordances.contains(.download),
                    "\(state) offers Download for a city already on the device"
                )
            }
        }
    }

    // MARK: - Report: "I just downloaded nyc a minute ago and already I'm told there's an update"

    /// A re-publish that changes only R60's `build_id` is not an update, and must not be offered as
    /// one. Same generation, same record date, different source seed.
    ///
    /// The two version strings are the real ones: the tester's installed copy read
    /// `s17-r2026-08-22-4f6ebaaa`, and the live manifest that evening said
    /// `s17-r2026-08-22-ac7b1ccc`.
    @Test("a re-publish that changed only the source seed's hash is not an update")
    func rePublishWithSameRecordIsNotAnUpdate() {
        let published = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")

        let state = CityInstallState(
            published: published,
            installedVersion: "s17-r2026-08-22-4f6ebaaa",
            installedContentRev: "2026-08-22",
            installedSchemaVersion: 17
        )
        #expect(state == .installedCurrent(installedVersion: "s17-r2026-08-22-4f6ebaaa"))
        #expect(!state.allowsDownload)
    }

    /// The other direction, which is what stops the fix above from being "never offer an update":
    /// a genuinely newer record, and a newer generation at the same record, are both updates.
    @Test("a newer record, or a newer generation, is still an update")
    func genuineUpdatesSurvive() {
        let published = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")

        // Newer record date.
        let staleRecord = CityInstallState(
            published: published,
            installedVersion: "s17-r2026-08-01-4f6ebaaa",
            installedContentRev: "2026-08-01",
            installedSchemaVersion: 17
        )
        #expect(staleRecord == .updateAvailable(installedVersion: "s17-r2026-08-01-4f6ebaaa"))

        // Same record date, older generation — the data is the same vintage, the file is not.
        let olderGeneration = CityInstallState(
            published: published,
            installedVersion: "s16-r2026-08-22-4f6ebaaa",
            installedContentRev: "2026-08-22",
            installedSchemaVersion: 16
        )
        #expect(olderGeneration == .updateAvailable(installedVersion: "s16-r2026-08-22-4f6ebaaa"))
    }

    /// A copy whose receipt cannot answer falls back to the version-string comparison — the
    /// behavior every build before this one had. Withholding an update on a missing fact would be
    /// the expensive direction.
    @Test("an unreadable receipt falls back to comparing version strings")
    func missingReceiptFallsBackToStringEquality() {
        let published = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")

        let noRev = CityInstallState(
            published: published,
            installedVersion: "s17-r2026-08-22-4f6ebaaa",
            installedContentRev: nil,
            installedSchemaVersion: 17
        )
        #expect(noRev == .updateAvailable(installedVersion: "s17-r2026-08-22-4f6ebaaa"))

        let noSchema = CityInstallState(
            published: published,
            installedVersion: "s17-r2026-08-22-4f6ebaaa",
            installedContentRev: "2026-08-22",
            installedSchemaVersion: nil
        )
        #expect(noSchema == .updateAvailable(installedVersion: "s17-r2026-08-22-4f6ebaaa"))

        // …and an identical version string is current without needing either, as it always was.
        let identical = CityInstallState(
            published: published,
            installedVersion: "s17-r2026-08-22-ac7b1ccc"
        )
        #expect(identical == .installedCurrent(installedVersion: "s17-r2026-08-22-ac7b1ccc"))
    }

    /// The record date an installed copy reports comes from the publisher's own stamp, read back
    /// out of the file — not re-derived from the fused build receipt that survives inside it.
    ///
    /// This is the read the fix above depends on, so it is asserted against a real SQLite file
    /// rather than a hand-made dictionary.
    @Test("an installed pack reports the record date its publisher stamped into it")
    func installedPackReadsItsStampedRecordDate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-feedback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("pack.sqlite")
        let connection = try SQLiteConnection(path: file.path)
        try connection.execute("""
            CREATE TABLE id_spaces (id TEXT PRIMARY KEY, city_id INTEGER, short_name TEXT);
            CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO id_spaces VALUES ('us-ny-nyc', 1, 'NYC');
            INSERT INTO seed_meta VALUES ('publish_content_rev', '2026-08-22');
            INSERT INTO seed_meta VALUES ('publish_schema_version', '17');
            -- The fused receipt the split leaves behind, naming an older snapshot. Re-deriving
            -- from these is what the stamped key exists to avoid.
            INSERT INTO seed_meta VALUES ('inventory_nyc_points_id_space', 'us-ny-nyc');
            INSERT INTO seed_meta VALUES ('inventory_nyc_points_snapshot_on', '2026-06-01');
            """)

        let cities = SeedCities.read(fileAt: file)
        let nyc = try #require(cities.first { $0.id == "us-ny-nyc" })
        #expect(nyc.contentRev == "2026-08-22")
        #expect(nyc.publishedSchemaVersion == 17)
    }

    // MARK: - The same read, through the caller the screen actually uses

    /// Writes a published **borough** pack into a library at `version`: one `id_spaces` row keyed by
    /// the ID SPACE (`us-ny-nyc`), a `publish_pack_id` naming the PACK (`us-ny-nyc-manhattan`), and
    /// the fused receipt the split leaves behind, disagreeing on purpose.
    ///
    /// The divergence between those two keys is the whole fixture: it is what
    /// `Tools/publish_cities.py` writes for every borough, and it is what a lookup keyed on the id
    /// space silently missed.
    ///
    /// **`regionName` is the s17 `dim_region` row, and it defaults to absent on purpose** — the
    /// default fixture is a pre-s17 pack, which is what the fallback tests need. A caller that
    /// passes one gets the table `Tools/build_seed.py` creates and `publish_cities.py` narrows to
    /// a single row: the pack's own name, keyed by the pack id.
    @discardableResult
    static func installBoroughPack(
        in library: CityLibrary,
        packID: String = "us-ny-nyc-manhattan",
        idSpace: String = "us-ny-nyc",
        version: String = "s17-r2026-08-22-4f6ebaaa",
        contentRev: String = "2026-08-22",
        schemaVersion: Int = 17,
        regionName: String? = nil
    ) throws -> URL {
        let file = library.fileURL(id: packID, version: version)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let connection = try SQLiteConnection(path: file.path)
        try connection.execute("""
            CREATE TABLE id_spaces (id TEXT PRIMARY KEY, city_id INTEGER, short_name TEXT);
            CREATE TABLE dim_city (id INTEGER PRIMARY KEY, display_name TEXT);
            CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO dim_city VALUES (1, 'New York City');
            INSERT INTO id_spaces VALUES ('\(idSpace)', 1, 'NYC');
            INSERT INTO seed_meta VALUES ('publish_pack_id', '\(packID)');
            INSERT INTO seed_meta VALUES ('publish_city_id', '\(idSpace)');
            INSERT INTO seed_meta VALUES ('publish_content_rev', '\(contentRev)');
            INSERT INTO seed_meta VALUES ('publish_schema_version', '\(schemaVersion)');
            -- The fused receipt the split leaves behind, naming an older snapshot.
            INSERT INTO seed_meta VALUES ('inventory_nyc_points_id_space', '\(idSpace)');
            INSERT INTO seed_meta VALUES ('inventory_nyc_points_snapshot_on', '2026-06-01');
            """)
        if let regionName {
            // `pack_id` UNIQUE and one surviving row, exactly as `publish_cities.py` leaves it
            // (`DELETE FROM dim_region WHERE id != ?`, then a count check that fails the publish
            // if anything else survived).
            try connection.execute("""
                CREATE TABLE dim_region (
                    id INTEGER PRIMARY KEY, pack_id TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL, level TEXT NOT NULL, city_id INTEGER NOT NULL
                );
                INSERT INTO dim_region VALUES (3, '\(packID)', '\(regionName)', 'borough', 1);
                """)
        }
        return file
    }

    /// A borough pack's receipt reaches `CityLibrary.installedCities()` — **the only read the Cities
    /// screen performs**, and the one the earlier version of this suite stepped around.
    ///
    /// The test above asserts `SeedCities.read` by looking a row up by *id space*, which is not the
    /// key the library has: the library knows a pack by its install directory, which is the *pack*
    /// id. For `sf` the two strings are equal and everything worked; for `us-ny-nyc-manhattan` they
    /// are not, so the match found nothing, `contentRev` came back nil, and D7b's whole fix
    /// disengaged for every New York borough — the city the report was filed about.
    @Test("a borough pack's stamped receipt survives the library's own lookup")
    func libraryResolvesABoroughPacksReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-lib-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CityLibrary(rootURL: root)
        try Self.installBoroughPack(in: library)

        let installed = try #require(library.installedCities().first)
        #expect(installed.id == "us-ny-nyc-manhattan")
        #expect(installed.contentRev == "2026-08-22")
        #expect(installed.publishedSchemaVersion == 17)
        // This fixture is a PRE-s17 pack: no `dim_region`, so nothing in it names the pack. The
        // only name it holds is the CITY's, and a borough does not wear it — see
        // `CityLibrary.installedCities()`. The s17 case is `boroughTitlesItselfFromItsOwnPack`.
        #expect(installed.displayName == nil)
    }

    /// A whole-city pack is unaffected: id space and pack id are one string, and the file's name is
    /// this pack's name. The control that says the fix above did not simply stop reading.
    @Test("a whole-city pack still reports both its receipt and its name")
    func libraryResolvesAWholeCityPack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-lib-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CityLibrary(rootURL: root)
        try Self.installBoroughPack(
            in: library, packID: "sf", idSpace: "sf", version: "s17-r2026-08-22-4f6ebaaa"
        )

        let installed = try #require(library.installedCities().first)
        #expect(installed.contentRev == "2026-08-22")
        #expect(installed.publishedSchemaVersion == 17)
        #expect(installed.displayName == "New York City")  // the fixture's dim_city row
    }

    // MARK: - Review round 2, F4: a borough names itself, offline, out of its own pack

    /// **A downloaded borough is titled `Manhattan`, from the file, with no manifest anywhere.**
    ///
    /// The claim this replaces was that nothing in `us-ny-nyc-manhattan.sqlite` says "Manhattan"
    /// and that only the manifest knows a pack's display name. `dim_region` shipped with the s17
    /// generation and is in every published pack; `publish_cities.py` narrows it to the pack's own
    /// row and refuses a publish whose manifest name disagrees with it.
    ///
    /// The `dim_city` row in this fixture still reads `New York City`, which is what makes the
    /// assertion discriminating: a lookup that fell back to the city's name would produce that
    /// string, and this test would fail rather than quietly agree.
    @Test("a downloaded borough titles itself from its own pack, not from its city")
    func boroughTitlesItselfFromItsOwnPack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-region-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CityLibrary(rootURL: root)
        try Self.installBoroughPack(in: library, regionName: "Manhattan")

        let installed = try #require(library.installedCities().first)
        #expect(installed.id == "us-ny-nyc-manhattan")
        #expect(
            installed.displayName == "Manhattan",
            "the pack's own dim_region row was not read: \(String(describing: installed.displayName))"
        )
        // The receipt is unaffected — this read is beside it, not instead of it.
        #expect(installed.contentRev == "2026-08-22")
    }

    /// The same fact through **the whole screen, with the catalog unreachable** — which is the only
    /// configuration where this matters, because a reachable manifest supplies the name anyway.
    ///
    /// The bucket URL points at a directory that does not exist, so `load()` lands on
    /// `.unavailable` and every row is disk facts alone.
    @MainActor
    @Test("offline, the borough's card reads Manhattan rather than its id")
    func offlineBoroughCardReadsItsPackName() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-region-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = CityLibrary(rootURL: root.appendingPathComponent("lib", isDirectory: true))
        try Self.installBoroughPack(in: library, regionName: "Manhattan")

        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(
                baseURL: root.appendingPathComponent("no-such-bucket", isDirectory: true)
            ),
            bundledCities: [],
            installableCityLimit: 9, onInventoryChange: {}
        )
        await model.load()

        #expect(model.catalog == .unavailable, "the manifest was reachable, so this proves nothing")
        let manhattan = try #require(model.rows.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(manhattan.title == "Manhattan", "the offline card is titled \(manhattan.title)")
        #expect(manhattan.isOnDevice)
    }

    /// **A downloaded file the read layer refused says so, and keeps the button that fixes it.**
    ///
    /// The row used to read `Installed · <version>` for a file the map was not reading, which was
    /// the quiet half of the boot defect: once a bad pack stopped taking the launch down, it stopped
    /// being visible at all. `liveInventoryIDs` is what the screen is told — the arms the union
    /// actually opened — and a city on disk that is not among them is one the app declined.
    ///
    /// **Both directions, in one test.** A model told the pack is live draws the ordinary row; the
    /// same model, same disk, told it is not, draws the failure. Asserting only the second would be
    /// green over a screen that marked every city unreadable.
    @MainActor
    @Test("a downloaded file the read layer refused reads as unreadable, not as installed")
    func aRefusedInventorySaysSoOnItsRow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-refused-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = CityLibrary(rootURL: root.appendingPathComponent("lib", isDirectory: true))
        try Self.installBoroughPack(in: library, regionName: "Manhattan")
        let offline = CityDownloader(
            baseURL: root.appendingPathComponent("no-such-bucket", isDirectory: true)
        )

        let opened = CityDownloadsModel(
            library: library, downloader: offline, bundledCities: [],
            installableCityLimit: 9,
            liveInventoryIDs: [InventoryFile.bundledID, "us-ny-nyc-manhattan"],
            onInventoryChange: {}
        )
        await opened.load()
        let healthy = try #require(opened.rows.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(!healthy.isFailure, "a pack the union opened is drawn as a failure")
        #expect(healthy.stateLine != "Couldn't be read")
        #expect(healthy.affordances == [.remove])

        // The same library and the same disk, with the read layer reporting that it did not open
        // the file — the state a malformed pack leaves behind.
        let refused = CityDownloadsModel(
            library: library, downloader: offline, bundledCities: [],
            installableCityLimit: 9,
            liveInventoryIDs: [InventoryFile.bundledID],
            onInventoryChange: {}
        )
        await refused.load()
        let broken = try #require(refused.rows.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(broken.stateLine == "Couldn't be read", "the row reads \(broken.stateLine)")
        #expect(
            broken.detailLine
                == "The downloaded file couldn't be opened, so its trees are not on the map."
        )
        #expect(broken.isFailure, "the line is not drawn in the attention color")
        // **The remedy survives**, which is the whole reason this is surfaced rather than hidden:
        // the reader can still delete the file that the boot could not read.
        #expect(broken.affordances == [.remove], "the failed row offers \(broken.affordances)")
        #expect(broken.isOnDevice, "the failed row left the On this phone run")
        #expect(broken.title == "Manhattan", "the failed row lost its name: \(broken.title)")
    }

    /// A whole-city pack reads its name from `dim_region` too, and the fixture's `dim_city` says
    /// something else on purpose — so this pins *which* table answered, not merely that a name
    /// arrived. The pack is its own region (`REGIONS` gives San Francisco one `city`-level row),
    /// and `dim_region.display_name` repeats the city's name there by construction.
    @Test("a whole-city pack is titled by its own region row as well")
    func wholeCityPackIsTitledByItsRegionRow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-region-city-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CityLibrary(rootURL: root)
        // `dim_city` in this fixture reads `New York City` whatever the pack is called.
        try Self.installBoroughPack(
            in: library, packID: "sf", idSpace: "sf", regionName: "San Francisco"
        )

        let installed = try #require(library.installedCities().first)
        #expect(installed.displayName == "San Francisco")
    }

    /// **The fallback, and the reason the lookup is keyed rather than "the one row there".** A file
    /// whose `dim_region` names some *other* pack must not lend its name to this one; the pack then
    /// has no name of its own and the id survives, exactly as for a pre-s17 pack.
    @Test("a region row naming another pack is not borrowed")
    func aForeignRegionRowIsNotBorrowed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-region-foreign-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CityLibrary(rootURL: root)
        let file = try Self.installBoroughPack(in: library, regionName: "Manhattan")
        // Re-key the one row onto a different pack, leaving everything else alone.
        let connection = try SQLiteConnection(path: file.path)
        try connection.execute("UPDATE dim_region SET pack_id = 'us-ny-nyc-queens'")

        let installed = try #require(library.installedCities().first)
        #expect(
            installed.displayName == nil,
            "Queens's name was worn by Manhattan: \(String(describing: installed.displayName))"
        )
    }

    /// **The tester's exact case, end to end through the screen's model.**
    ///
    /// Manhattan installed at `s17-r2026-08-22-4f6ebaaa`; the catalog offering
    /// `s17-r2026-08-22-ac7b1ccc` — same record date, same generation, different source-seed hash.
    /// The row must read `Installed`, not `Update available · s17-r2026-08-22-4f6ebaaa installed`,
    /// which is what the reviewer photographed on the running screen with the fix in place.
    ///
    /// Driven through `CityDownloadsModel.load()` rather than through `CityInstallState` directly,
    /// because the defect lived in neither of those — it lived in the read between them.
    @MainActor
    @Test("a re-published borough is not offered as an update, through the whole screen")
    func boroughRePublishIsNotAnUpdateOnScreen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = CityLibrary(rootURL: root.appendingPathComponent("lib", isDirectory: true))
        try Self.installBoroughPack(in: library)

        func rows(publishedContentRev: String, publishedVersion: String) async -> [CityDownloadRow] {
            let bucket = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
            try? Data(Self.manifestJSON(
                contentRev: publishedContentRev, version: publishedVersion
            ).utf8).write(to: bucket.appendingPathComponent("manifest-v2.json"))

            let model = CityDownloadsModel(
                library: library,
                downloader: CityDownloader(baseURL: bucket),
                bundledCities: [], installableCityLimit: 9,
                onInventoryChange: {}
            )
            await model.load()
            return model.rows
        }

        // The tester's evening: a re-publish that changed only the source seed's hash.
        let unchanged = await rows(
            publishedContentRev: "2026-08-22", publishedVersion: "s17-r2026-08-22-ac7b1ccc"
        )
        let manhattan = try #require(unchanged.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(manhattan.stateLine == "Installed · s17-r2026-08-22-4f6ebaaa")
        #expect(manhattan.affordances == [.remove])

        // A genuinely newer record still flags — the fix withholds nothing it should offer.
        let newer = await rows(
            publishedContentRev: "2026-09-01", publishedVersion: "s17-r2026-09-01-ac7b1ccc"
        )
        let updated = try #require(newer.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(updated.stateLine == "Update available · s17-r2026-08-22-4f6ebaaa installed")
        #expect(updated.affordances == [.update, .remove])
    }

    /// A one-entry format-2 catalog listing the Manhattan pack, as the publisher writes it.
    static func manifestJSON(contentRev: String, version: String) -> String {
        """
        {
          "manifest_format": 2,
          "generated_at": "2026-08-22T01:23:36+00:00",
          "generator": "Tools/publish_cities.py",
          "source_seed": {"generated_at": "2026-08-22T00:00:00+00:00", "tree_count": 1, "sha256": "aa"},
          "cities": [
            {
              "id": "us-ny-nyc-manhattan",
              "display_name": "Manhattan",
              "coverage": "full",
              "region": {
                "level": "borough",
                "parent_city": "us-ny-nyc",
                "parent_city_display_name": "New York City"
              },
              "bbox": {"min_lat": 40.7, "max_lat": 40.9, "min_lon": -74.02, "max_lon": -73.9},
              "centroid": {"lat": 40.78, "lon": -73.97},
              "tree_count": 1,
              "schema_version": 17,
              "content_rev": "\(contentRev)",
              "version": "\(version)",
              "path": "cities/us-ny-nyc-manhattan/\(version)/us-ny-nyc-manhattan.sqlite",
              "bytes": 66891776,
              "sha256": "ab",
              "attribution": [{"inventory": "nyc_points", "name": "NYC Parks", "url": "x"}]
            }
          ]
        }
        """
    }

    /// A file holding more than one id space has no single pack to attribute a stamp to, so the
    /// per-inventory rule answers — which is the only thing the fused bundled seed can do.
    @Test("a multi-city file falls back to the per-inventory rule")
    func multiCityFileIgnoresTheStamp() {
        let meta = [
            "publish_content_rev": "2026-08-22",
            "inventory_sf_city_id_space": "sf",
            "inventory_sf_city_snapshot_on": "2026-07-31"
        ]
        #expect(
            SeedCities.contentRev(forIDSpace: "sf", seedMeta: meta, idSpaceCount: 2) == "2026-07-31"
        )
        #expect(
            SeedCities.contentRev(forIDSpace: "sf", seedMeta: meta, idSpaceCount: 1) == "2026-08-22"
        )
    }

    // MARK: - Report: "why do I see download for sf and San Jose when those cities SHIP WITH THE APP"

    /// A bundled city with a newer record published says it is in the app **first**, and offers the
    /// newer record underneath. Before this the card said only that something newer existed.
    @Test("a bundled city says it is included in the app before it offers an update")
    func bundledOutdatedStatesPossessionFirst() {
        let sf = Self.entry(
            id: "sf", displayName: "San Francisco",
            version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22"
        )
        let row = Self.row(sf, state: .bundledOutdated(bundledContentRev: "2026-07-31"))

        #expect(row.stateLine == "Included in the app · record as of 2026-07-31")
        // **Both halves of this row changed with the screen.** The sentence no longer names the
        // transfer, and the verb is `Update` rather than `Download`, because a newer copy of a
        // bundled city is an update to that city rather than a second inventory.
        #expect(row.detailLine == "A newer record is available.")
        #expect(row.affordances == [.update])
        #expect(row.isOnDevice)
        // The date is stated once, not once per line.
        #expect(row.detailLine?.contains("2026-07-31") == false)
    }

    // MARK: - Report: "we should say WHAT CITIES ship in the pre-built seed"

    /// The built-in card names what is inside it, from names the seed itself states.
    @Test("the built-in card names the cities it ships")
    func builtInCardNamesItsCities() {
        #expect(
            CityDownloadRow.builtIn(cityNames: ["San Francisco", "San Jose"])
                .detailLine == "Includes San Francisco and San Jose"
        )
        #expect(
            CityDownloadRow.builtIn(cityNames: ["San Francisco"])
                .detailLine == "Includes San Francisco"
        )
        #expect(
            CityDownloadsCopy.builtInCitiesLine(["A", "B", "C"]) == "Includes A, B, and C"
        )
        // A bundle that names nothing says nothing extra, rather than an empty sentence.
        #expect(CityDownloadRow.builtIn(cityNames: []).detailLine == nil)
        // The ruled subtitle is untouched (R43 §3).
        #expect(
            CityDownloadRow.builtIn().stateLine
                == "Ships with the app and cannot be removed"
        )
    }

    // MARK: - Reports: "the NYC ones should be visually grouped" / "downloaded should be at top"

    /// The screen splits into `On this phone` and `Available to download`, with a city's several
    /// packs gathered under that city's own name.
    @Test("sections put what you have first, and group a city's packs under its name")
    func sectionsGroupTheScreen() {
        let cities = [
            Self.entry(
                id: "sf", displayName: "San Francisco",
                version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22"
            ),
            Self.entry(
                id: "us-ca-la", displayName: "Los Angeles",
                version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22",
                region: CityManifest.Region(
                    level: "city", parentCity: "us-ca-la", parentCityDisplayName: "Los Angeles"
                )
            ),
            Self.borough("manhattan", "Manhattan"),
            Self.borough("brooklyn", "Brooklyn"),
            Self.borough("queens", "Queens")
        ]
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco", "San Jose"]),
            Self.row(cities[0], state: .bundledOutdated(bundledContentRev: "2026-07-31")),
            Self.row(cities[1], state: .notInstalled),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled),
            Self.row(cities[4], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )

        // The whole shape in one expectation, deliberately: subscripting section by section reads
        // more clearly and **crashes the test process** the first time a break leaves the array
        // shorter than the assertions expect, which takes down every test scheduled behind it. A
        // red-proof of this file did exactly that. Comparing the shape can only fail.
        #expect(
            sections.map { ($0.title, $0.isCityGroup, $0.rows.map(\.id)) }.map(String.init(describing:))
                == [
                    // **The built-in card opens the run, and San Francisco is in it.** The bundle
                    // holds that city, so it is not a row beside the built-in card — it is drawn
                    // inside that card, which is what the pair below asserts.
                    ("On this phone", false, ["built-in", "sf"]),
                    // Los Angeles has one pack, so it stays under the umbrella rather than earning
                    // a heading of its own — and the umbrella is drawn because it has that row.
                    ("Available to download", false, ["us-ca-la"]),
                    ("New York City", true, [
                        "us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens"
                    ])
                ].map(String.init(describing:))
        )

        // **The arrangement, not a flag about it.** `cards` is the only thing `CityDownloadsView`
        // draws from, so a card list with San Francisco inside the built-in card is a screen with
        // San Francisco inside the built-in card. The previous version of this assertion read
        // `isCityGroup == true && title.isEmpty` on a separate section — the exact pair that
        // guaranteed the flag could not reach the view, since the only modifier it fed sat inside
        // `if !section.title.isEmpty`.
        #expect(
            sections.map { $0.cards.map { ($0.row.id, $0.contained.map(\.id)) } }
                .map(String.init(describing:))
                == [
                    [("built-in", ["sf"])],
                    [("us-ca-la", [] as [String])],
                    [
                        ("us-ny-nyc-manhattan", [] as [String]),
                        ("us-ny-nyc-brooklyn", [] as [String]),
                        ("us-ny-nyc-queens", [] as [String])
                    ]
                ].map(String.init(describing:))
        )
    }

    /// **The production shape today: `Available to download` heads a run whose every row grouped.**
    /// Every available pack in the live catalog is a New York borough, so the umbrella carries no
    /// cards of its own and sits immediately above `New York City`.
    ///
    /// **This was built the other way first, and the running screen reversed it.** Suppressing an
    /// empty heading is the tidier rule right up to the moment a reader downloads one borough: the
    /// city then has a group in both runs, and with no umbrella between them the screen draws
    /// `New York City` twice in a row with nothing saying which is which. Photographed at 402 pt
    /// with Manhattan and Staten Island installed. So the heading stays, and the test that asserted
    /// its absence now asserts its presence — deliberately, with the reason on the record.
    @Test("a run keeps its own heading even when every row of it grouped")
    func umbrellaHeadingSurvivesAFullyGroupedRun() {
        let cities = [Self.borough("manhattan", "Manhattan"), Self.borough("brooklyn", "Brooklyn")]
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .notInstalled),
            Self.row(cities[1], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.map(\.title) == ["On this phone", "Available to download", "New York City"])
        #expect(sections.map(\.isCityGroup) == [false, false, true])
        // The umbrella is empty, and the group under it holds both boroughs.
        #expect(sections.map { $0.rows.count } == [1, 0, 2])
    }

    /// **The mixed state that decided the rule above**, asserted as a shape rather than described.
    /// One borough installed, two not: the two `New York City` groups are separated by the
    /// `Available to download` heading, which is the whole of what that heading is for here.
    @Test("a city grouped in both runs keeps a heading between the two")
    func groupsInBothRunsAreSeparated() {
        let cities = [
            Self.borough("manhattan", "Manhattan"),
            Self.borough("staten-island", "Staten Island"),
            Self.borough("brooklyn", "Brooklyn"),
            Self.borough("queens", "Queens")
        ]
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(
            sections.map(\.title)
                == ["On this phone", "", "New York City", "Available to download", "New York City"]
        )
        // No two identical headings are ever adjacent.
        #expect(!zip(sections, sections.dropFirst()).contains { $0.title == $1.title })
    }

    /// **The grouping D5 asked for survives the reader acting on it.** Pack counting used to look at
    /// the available rows only, so downloading the boroughs moved them into `On this phone` and the
    /// `New York City` heading vanished — the report was answered right up until the moment it
    /// mattered. Counting per run gives each run its own groups.
    @Test("downloading a city's packs does not destroy its grouping")
    func groupingSurvivesDownloading() {
        let cities = [
            Self.borough("manhattan", "Manhattan"),
            Self.borough("brooklyn", "Brooklyn"),
            Self.borough("queens", "Queens")
        ]
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .installedCurrent(installedVersion: "v"))
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.map(\.title) == ["On this phone", "", "New York City"])
        #expect(
            sections.last?.rows.map(\.id)
                == ["us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens"]
        )
        // Nested under `On this phone`, which is drawn above it because the built-in card is there.
        #expect(sections.last?.isCityGroup == true)
    }

    /// The whole shape, at the state the live catalog actually produces once a borough is on the
    /// phone — the case the two rules above have to agree about.
    @Test("nothing is dropped when a city groups in both runs")
    func bothRunsKeepEveryRow() {
        let cities = (1...4).map { Self.borough("b\($0)", "Borough \($0)") }
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: []),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled)
        ]
        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.flatMap(\.rows).count == rows.count)
        #expect(Set(sections.flatMap { $0.rows.map(\.id) }) == Set(rows.map(\.id)))
    }

    /// A city can now head a group in **both** runs at once — three boroughs downloaded, two not —
    /// and a section id that was just the title would give one `ForEach` two identical ids, which
    /// SwiftUI resolves by dropping rows.
    @Test("two groups for one city, in different runs, keep distinct identities")
    func sectionIdentitiesAreUniqueAcrossRuns() {
        let cities = (1...4).map { Self.borough("b\($0)", "Borough \($0)") }
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: []),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(
            sections.map(\.title)
                == ["On this phone", "", "New York City", "Available to download", "New York City"]
        )
        // The identity, not the title, is what `ForEach` uses — two `New York City` sections in one
        // pass must not collide, or SwiftUI resolves the duplicate by dropping rows.
        #expect(Set(sections.map(\.id)).count == sections.count)
    }

    /// A city with one pack gets no heading of its own — a heading over a single row is furniture.
    @Test("a city with a single pack is not given its own heading")
    func loneCityIsNotGrouped() {
        let sf = Self.entry(
            id: "sf", displayName: "San Francisco",
            version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22",
            region: CityManifest.Region(
                level: "city", parentCity: "sf", parentCityDisplayName: "San Francisco"
            )
        )
        let manhattan = Self.borough("manhattan", "Manhattan")
        let rows = [Self.row(sf, state: .notInstalled), Self.row(manhattan, state: .notInstalled)]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: [sf, manhattan])
        )
        #expect(sections.map(\.title) == ["Available to download"])
        #expect(sections.flatMap { $0.rows.map(\.id) } == ["sf", "us-ny-nyc-manhattan"])
    }

    /// Sectioning arranges; it never drops. Asserted against the flattening rather than by counting
    /// twice in the same way.
    @Test("every row survives sectioning, exactly once")
    func everyRowSurvivesSectioning() {
        let cities = [
            Self.entry(
                id: "sf", displayName: "San Francisco",
                version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22"
            ),
            Self.borough("manhattan", "Manhattan"),
            Self.borough("brooklyn", "Brooklyn")
        ]
        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .notInstalled),
            Self.row(cities[2], state: .updateAvailable(installedVersion: "old"))
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        let flattened = sections.flatMap(\.rows)
        #expect(flattened.count == rows.count)
        #expect(Set(flattened.map(\.id)) == Set(rows.map(\.id)))
        // The `On this phone` heading now sits over the built-in card alone; the bundled city
        // nests under it and the downloaded pack follows in the untitled run below.
        // What this test is about is that nothing is dropped or duplicated on the way, which the
        // two assertions above check against the flattening.
        #expect(
            sections.first(where: { $0.title == "On this phone" })?.rows.map(\.id) == ["built-in"]
        )
        // Brooklyn has an update waiting, so it is on the phone — before `Available to download`
        // and after the bundled cities.
        let onDeviceIDs = sections
            .prefix { $0.title != CityDownloadsCopy.availableSection }
            .flatMap(\.rows).map(\.id)
        #expect(onDeviceIDs == ["built-in", "sf", "us-ny-nyc-brooklyn"], "\(onDeviceIDs)")
    }

    /// An in-flight first download stays under `Available`; an in-flight *update* does not leave the
    /// top section. Both follow from asking the install state rather than the buttons.
    @Test("a download in flight keeps the section its state already earned")
    func downloadInFlightDoesNotJumpSections() {
        let city = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")

        let firstDownload = CityDownloadRow.published(
            city: city, state: .notInstalled,
            downloadingFraction: 0.4, lastAttemptFailed: false
        )
        #expect(!firstDownload.isOnDevice)

        let updating = CityDownloadRow.published(
            city: city, state: .updateAvailable(installedVersion: "old"),
            downloadingFraction: 0.4, lastAttemptFailed: false
        )
        #expect(updating.isOnDevice)
    }

    // MARK: - Report: "Download is super slow"

    /// **The smallest average read the download path may perform over a transferred payload.**
    ///
    /// 64 KiB. The real path reads in `CityDownloader.chunkSize` — 512 KiB — so this sits eight
    /// times below what the working implementation does and 65,536 times above what the defect
    /// does. There is a great deal of room between those two and nothing to tune.
    ///
    /// **Stated here rather than derived from `CityDownloader.chunkSize`, and that is the whole
    /// reason this is a constant of the suite's own.** A bound computed from the production
    /// constant would move with a regression that set the chunk size to one byte — expected
    /// `bytes + 1` reads, observed `bytes + 1` reads, green — which is this project's dominant
    /// test-suite defect exactly: a guard that passes while the defect it names is present. The
    /// chunk size is still *reported* in the failure messages below, because a reader debugging a
    /// red wants to know what produced the count; it is never what the count is judged against.
    static let smallestHonestRead = 64 * 1024

    /// The transfer hands over a finished file, and this app never walks the bytes one at a time.
    ///
    /// ── What replaced a stopwatch, and why ────────────────────────────────────────────────────
    ///
    /// This test used to race two wall-clock measurements: it walked the same fixture with
    /// `URLSession.AsyncBytes` exactly as the defect had, and required the real transfer to beat
    /// that control by 6×. The reasoning was that machine speed cancels in a ratio. It does not,
    /// because the two measurements are not taken at the same instant on a shared runner, and the
    /// guard went red three times on code nobody had changed:
    ///
    ///   * 2026-08-23 — 8.5× against the then-10× threshold.
    ///   * PR #123's fix round narrowed a sibling window the same way, and the review flagged the
    ///     class rather than the instance.
    ///   * 2026-08-31, run 33430972054, the build-65 main run — `elapsed × 6 = 37.698` against a
    ///     control of `11.744`. A plain rerun went green, which proves it was intermittent and says
    ///     nothing whatever about why.
    ///
    /// **The margin was always a proxy for a count.** A per-byte walk performs one operation per
    /// byte; a chunked path performs one per 512 KiB. So the count is what is asserted, through
    /// `CityTransferCensus` — see that type for what it can and cannot see. Nothing here reads a
    /// clock, and no assertion below can be moved by what else the machine is doing.
    ///
    /// ── The two counts, and why neither is sufficient alone ───────────────────────────────────
    ///
    /// **`fileHandoffs`** says the bytes arrived as a *file*. This is the one that catches the
    /// original defect: a transfer that accumulates the response byte by byte in memory and then
    /// writes it out is verified in perfectly tidy 512 KiB chunks, so a read count alone would be
    /// green while 4.2 million appends ran.
    ///
    /// **`payloadReads`** says this app's own reading of those bytes is chunked. This is the one
    /// that catches the same defect a layer down, where the transport is untouched and the
    /// verification walks the file a byte at a time.
    ///
    /// **`payloadBytesRead` is the anti-vacuity assertion and is load-bearing.** A read count of
    /// zero satisfies any ceiling; it is what a verification that never ran reports, and it is what
    /// a census wired to nothing reports. Requiring the whole payload to have been read is what
    /// separates "read in big pieces" from "not read".
    ///
    /// The install, byte count and sha256 are asserted alongside, because a transfer that counted
    /// beautifully and verified nothing would satisfy every count above perfectly.
    ///
    /// **What this does not cover, corrected by review finding F2.** This used to say the hole was
    /// `FileManager`. The hole is wider and simpler: **the census counts its two wired sites and a
    /// new read site anywhere counts as zero.** The reviewer proved it — a `FileHandle` opened in
    /// `didFinishDownloadingTo` and walked with `read(upToCount: 1)`, 4.2 million single-byte reads
    /// on every transfer, a ~10× slowdown of the originally reported shape, and all four guards
    /// here green. `FileManager` copying is one case of that, not the boundary.
    ///
    /// `nothingInTheDownloadPathConsumesAByteStream` is what closes it, and why that gate now
    /// *bounds* the verification's `FileHandle` loop to one occurrence rather than only forbidding
    /// the streaming APIs. A second read site in this directory is a red there.
    @Test("the transfer hands over a finished file and the app reads it in chunks",
          .timeLimit(.minutes(3)))
    func downloadIsNotPerByte() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 4 MiB of non-uniform bytes. The non-uniformity is inherited from when this was a timing
        // test — a compressible payload let a transport cheat the clock — and is kept because it
        // costs nothing and a realistic pack is not a run of zeroes either.
        let byteCount = 4 * 1024 * 1024
        let payload = Self.payload(bytes: byteCount)

        let city = CityManifest.City(
            id: "perf", displayName: "Perf", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-ac7b1ccc",
            path: "cities/perf/v/perf.sqlite",
            bytes: Int64(payload.count),
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
        let object = dir.appendingPathComponent(city.path)
        try FileManager.default.createDirectory(
            at: object.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try payload.write(to: object)

        // **No warm-up, and no measured window.** Both existed to keep a fixed cost out of a
        // stopwatch reading — constructing the session, the process's first use of URLSession. A
        // count does not have an intercept, so there is nothing left for either to protect.
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let progress = await CityDownloadProgress()
        let census = CityTransferCensus()
        let service = CityDownloadService(
            library: library, baseURL: dir, configuration: .ephemeral,
            progress: progress, census: census
        )

        await MainActor.run { _ = service.start(city) }
        await service.waitUntilIdle()

        let counts = census.counts

        // The bytes arrived as a finished file this app was handed, never as a stream it consumed.
        #expect(
            counts.fileHandoffs == 1,
            """
            URLSession handed this app \(counts.fileHandoffs) finished file(s) for a transfer that \
            installed — the transport is no longer a download task, so the response body is passing \
            through this app as a stream. That is the shape of the 2026-08-23 defect: \
            `for try await byte in session.bytes(…)`.
            """
        )

        // Anti-vacuity. Every ceiling below is satisfied by a read that never happened.
        #expect(
            counts.payloadBytesRead == Int64(byteCount),
            """
            the verification read \(counts.payloadBytesRead) of \(byteCount) bytes, so the read \
            count below describes something other than a full pass over the payload
            """
        )

        // The whole of the guard, in one line: every read took at least 64 KiB on average. A
        // per-byte walk of this fixture reports 4,194,304 reads against a ceiling of 64.
        let ceiling = byteCount / Self.smallestHonestRead
        #expect(
            counts.payloadReads <= ceiling,
            """
            the app performed \(counts.payloadReads) reads over \(byteCount) bytes — an average of \
            \(counts.payloadBytesRead / Int64(max(counts.payloadReads, 1))) bytes a read, against a \
            floor of \(Self.smallestHonestRead). The download path is walking the transferred bytes \
            in pieces far smaller than it should. `CityDownloader.chunkSize` currently reads \
            \(CityDownloader.chunkSize) bytes at a time; at its intended 512 KiB this fixture \
            reports 8 reads. (The count is judged against the floor, never against that constant — \
            see `smallestHonestRead`.)
            """
        )

        // A transfer that counted beautifully and verified nothing satisfies all of the above.
        #expect(await progress.installCount == 1)
        let landed = try Data(contentsOf: library.fileURL(id: city.id, version: city.version))
        #expect(landed.count == payload.count)
        #expect(SHA256.hash(data: landed).map { String(format: "%02x", $0) }.joined() == city.sha256)
    }

    /// The verification's read count follows the **chunks**, not the bytes.
    ///
    /// The test above bounds the count at one payload size, which a fixed-size buffer that happens
    /// to be generous at 4 MiB would also satisfy. This is the slope: the same verification is run
    /// over 1 MiB and over 4 MiB, and what is asserted is the *marginal* cost — the reads spent on
    /// the three extra mebibytes, against the bytes they carried.
    ///
    /// **A marginal rate rather than a ratio, because it survives any intercept.** A path with a
    /// fixed setup cost, or one that reads a header separately, shifts both counts equally and does
    /// not move the difference. A per-byte walk cannot hide in it: 3 MiB of extra payload costs
    /// 3,145,728 extra reads, one byte a read, against a floor of 64 KiB.
    ///
    /// **The rule is `marginalReadIsHonest`, and it is a pure function on purpose** — review
    /// finding F1. The assertion here used to be `extraBytes / extraReads >= floor`, an integer
    /// division with nothing guarding `extraReads == 0`. `#expect` does not halt, so the
    /// anti-vacuity assertions above fired and control reached the division anyway: the process
    /// trapped with `Fatal error: Division by zero` and every test scheduled behind it in that
    /// process lost its result. Two inputs reached it, and the second is the one that matters —
    /// **a chunk size of 4 MiB**, which is strictly *better* by this guard's own metric, gives one
    /// read at both sizes and `extraReads == 0`. Someone improving the chunk size got a crashed
    /// runner. The rule is cross-multiplied now, so there is no division to trap, and it is stated
    /// once as a function that `marginalRuleIsCalibrated` runs against cases whose answers are
    /// known.
    ///
    /// Run against `CityDownloader.verify` directly rather than through a transfer. That is
    /// deliberate: a red here names the verification loop, where a red in the test above could be
    /// either half of the path. `sabotagedByteIsRefusedOverHTTP` is what proves this same function
    /// is the one a real transfer goes through.
    @Test("the verification's reads follow the chunks, not the bytes")
    func verificationReadsScaleWithChunksNotBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-slope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func reads(overBytes byteCount: Int) throws -> CityTransferCensus.Counts {
            let payload = Self.payload(bytes: byteCount)
            let file = dir.appendingPathComponent("\(byteCount).bin")
            try payload.write(to: file)
            let record = CityDownloadRecord(
                CityManifest.City(
                    id: "slope", displayName: "Slope", coverage: "full", treeCount: 1,
                    schemaVersion: 17, version: "v", path: "p",
                    bytes: Int64(payload.count),
                    sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
                )
            )
            let census = CityTransferCensus()
            try CityDownloader.verify(fileAt: file, against: record, census: census)
            return census.counts
        }

        let small = 1024 * 1024
        let large = 4 * 1024 * 1024
        let smallCounts = try reads(overBytes: small)
        let largeCounts = try reads(overBytes: large)

        // **Anti-vacuity, and these two carry it alone now.** There used to be a third —
        // `largeCounts.payloadReads > smallCounts.payloadReads` — as the "the instrument responds
        // to size" control. It is gone, because it is false for a legitimately *larger* chunk
        // (1 read at both sizes is not greater than itself), which is the same benign change F1
        // showed trapping the process one line below. These two are what an unwired census fails:
        // it reports 0 bytes read at both sizes, and 0 is not 1 MiB.
        #expect(
            smallCounts.payloadBytesRead == Int64(small),
            """
            the verification read \(smallCounts.payloadBytesRead) of \(small) bytes, so the rate \
            below describes something other than a full pass over the payload
            """
        )
        #expect(
            largeCounts.payloadBytesRead == Int64(large),
            """
            the verification read \(largeCounts.payloadBytesRead) of \(large) bytes, so the rate \
            below describes something other than a full pass over the payload
            """
        )

        let extraBytes = large - small
        let extraReads = largeCounts.payloadReads - smallCounts.payloadReads
        #expect(
            Self.marginalReadIsHonest(extraBytes: extraBytes, extraReads: extraReads),
            """
            the extra \(extraBytes) bytes cost \(extraReads) extra reads — \
            \(extraBytes / max(extraReads, 1)) bytes a read, against a floor of \
            \(Self.smallestHonestRead). The verification's cost is following the byte count rather \
            than the chunk count, which is the per-byte walk one layer below the transport.
            """
        )
    }

    /// **The marginal rule, cross-multiplied so there is no division to trap** (review finding F1).
    ///
    /// `extraReads == 0` is the *best* possible outcome, not a failure: it means the extra payload
    /// cost no extra reads at all, which is what a chunk larger than the whole fixture produces. It
    /// is deliberately not treated as an anti-vacuity signal either — an unwired census also
    /// reports zero, and what catches that is `payloadBytesRead`, which knows the difference
    /// between "read in one piece" and "not read".
    ///
    /// Otherwise: the extra bytes must have paid for themselves at `smallestHonestRead` apiece,
    /// written as a multiplication rather than `extraBytes / extraReads >= floor` because the
    /// division is the trap F1 filed.
    static func marginalReadIsHonest(extraBytes: Int, extraReads: Int) -> Bool {
        extraReads == 0 || extraBytes >= extraReads * smallestHonestRead
    }

    /// **The rule, run against cases whose answers are already known** — CLAUDE.md's calibration
    /// rule, and the explicit green case review finding F1 asked for: a *larger* chunk must pass,
    /// not crash.
    @Test("the marginal-read rule admits a bigger chunk and refuses a per-byte walk")
    func marginalRuleIsCalibrated() {
        let threeMiB = 3 * 1024 * 1024

        // The shipping 512 KiB chunk: 3 MiB of extra payload costs six extra reads.
        #expect(Self.marginalReadIsHonest(extraBytes: threeMiB, extraReads: 6))

        // **The case that used to trap the runner.** `chunkSize = 4 * 1024 * 1024` reads each
        // fixture whole, so both sizes report one read and the extra 3 MiB costs none. That is
        // better than what ships, and it must be green — F1's second input.
        #expect(
            Self.marginalReadIsHonest(extraBytes: threeMiB, extraReads: 0),
            """
            a chunk large enough to read each fixture in one go reports zero extra reads, which is \
            the best outcome this rule can observe — it must not be read as a failure, and before \
            F1 it was not read at all because the division trapped first
            """
        )

        // The defect: one byte a read.
        #expect(!Self.marginalReadIsHonest(extraBytes: threeMiB, extraReads: threeMiB))

        // The boundary, both sides of it. 3 MiB / 64 KiB is exactly 48.
        #expect(Self.marginalReadIsHonest(extraBytes: threeMiB, extraReads: 48))
        #expect(!Self.marginalReadIsHonest(extraBytes: threeMiB, extraReads: 49))
    }

    // MARK: - The source gate over the download path

    /// Every `.swift` file under `Cypress/Data/Cities`, **including subdirectories**.
    ///
    /// `FileManager.enumerator` rather than `contentsOfDirectory`, which is review finding F3(a):
    /// the non-recursive read never saw `Data/Cities/Transport/`, so moving transport code one
    /// folder down turned the gate off for it silently — the reviewer planted an unhidden byte
    /// stream there and every assertion stayed green. URLs are resolved for
    /// `AppSourceLiterals.sourceFiles`' reason (#229).
    static func downloadPathSources(root: URL) -> [URL] {
        let directory = root.appendingPathComponent("Cypress/Data/Cities", isDirectory: true)
            .resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }
            .map { $0.resolvingSymlinksInPath() }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    /// One occurrence of a watched spelling: which token, and the line it starts on.
    struct ByteReadUse: Equatable, CustomStringConvertible {
        let token: String
        let line: Int
        var description: String { "\(token)@\(line)" }
    }

    /// **The APIs that put this app in contact with a transferred file's bytes**, and the reason
    /// each is on the list. Two families, judged differently below.
    ///
    /// **Family 1, forbidden outright — reading a payload as a stream.**
    ///
    ///   * `.bytes(` — `URLSession.bytes(from:)` / `.bytes(for:)`, whose element is one byte. This
    ///     is the 2026-08-23 defect's own API. Matched on the open paren alone rather than on
    ///     `(from:`/`(for:`, which is review finding F3(b): the argument label can be on the next
    ///     line, and the old tokens required both halves to share one. The paren is what keeps
    ///     `record.bytes` and `payloadBytesRead` out.
    ///   * `AsyncBytes` — the type those return, named directly.
    ///   * `InputStream` — Foundation's other byte-at-a-time reader.
    ///   * `readData(ofLength:`, `readDataToEndOfFile`, `availableData` — `FileHandle`'s remaining
    ///     read surface. None is used here; a payload read that arrived through one of them would
    ///     be uncounted by the census exactly as `read(upToCount:)` would.
    ///   * `Data(contentsOf:` — reads a whole file into memory in one uncounted operation. Not a
    ///     per-byte walk, but on a 199 MB pack it is both a memory event and contact with the
    ///     payload that no counter sees.
    ///
    /// **Family 2, allowed exactly once — the verification's own loop.** `FileHandle(forReadingFrom:`
    /// and `read(upToCount:` are how `CityDownloader.verifiableFacts` hashes a staged file, so they
    /// cannot be banned. They are *bounded* instead: exactly one of each, in `CityDownloader.swift`.
    /// That is what makes the sentence at `CityDownloader.swift:267` — *"this loop is the app's only
    /// contact with a transferred file's bytes"* — a test rather than a comment, which is review
    /// finding F2's ruling. The census's whole design leans on that invariant, and it was load-bearing
    /// prose. The reviewer's planted regression (a `FileHandle` opened in `didFinishDownloadingTo`
    /// and walked with `read(upToCount: 1)`, 4.2 million single-byte reads, all four guards green)
    /// adds a second of each and is named here.
    static let forbiddenByteReads = [
        ".bytes(", "AsyncBytes", "InputStream",
        "readData(ofLength:", "readDataToEndOfFile", "availableData", "Data(contentsOf:"
    ]

    /// Family 2's spellings, and the one file entitled to one of each.
    static let boundedByteReads = ["FileHandle(forReadingFrom:", "read(upToCount:"]
    static let verificationFile = "CityDownloader.swift"

    /// Where each watched spelling occurs in `source`, by line.
    ///
    /// **Whitespace is removed before matching, which is review finding F3(b).** The tokens used to
    /// be matched against one line at a time, so an ordinary wrapped call —
    ///
    ///     let (stream, _) = try await session.bytes(
    ///         from: url
    ///     )
    ///
    /// — put no forbidden spelling on any single line and walked straight through. Packing the
    /// source down to its non-whitespace characters, with each character remembering the line it
    /// came from, makes the match indifferent to how a call is wrapped while still reporting the
    /// line the token starts on.
    ///
    /// **Comments are stripped first** (`BorrowedGlyphAPI.codeOnly`, calibrated by its own suite),
    /// and unlike in the first version of this gate that is *not* hypothetical — review finding F4
    /// caught the previous justification naming two comments that contained no forbidden token.
    /// With the token set above, two real comments in this directory now do spell watched APIs:
    /// `CityTransferCensus.swift`'s header quotes ``session.bytes(…)``, which `.bytes(` matches,
    /// and `CityDownloader.swift:211` writes ``Data(contentsOf:)`` while explaining how a missing
    /// file surfaces. Both are correct prose about the code, and without the strip this gate would
    /// be fixed by deleting them.
    static func byteReadUses(in source: String, tokens: [String]) -> [ByteReadUse] {
        var packed: [Character] = []
        var lines: [Int] = []
        var line = 1
        for character in BorrowedGlyphAPI.codeOnly(in: source) {
            if character == "\n" { line += 1 }
            guard !character.isWhitespace else { continue }
            packed.append(character)
            lines.append(line)
        }

        var uses: [ByteReadUse] = []
        for token in tokens {
            let needle = Array(token.filter { !$0.isWhitespace })
            guard !needle.isEmpty, packed.count >= needle.count else { continue }
            for start in 0...(packed.count - needle.count)
            where Array(packed[start..<(start + needle.count)]) == needle {
                uses.append(ByteReadUse(token: token, line: lines[start]))
            }
        }
        return uses.sorted { ($0.line, $0.token) < ($1.line, $1.token) }
    }

    /// **Nothing under `Data/Cities/` reads a transferred payload except the one loop that is
    /// counted.**
    ///
    /// The counting guards above run a transfer and observe it; this one needs no transfer, so it
    /// sees `adopt`, the resume path and any code a fixture never reaches. It carries two rules —
    /// see `forbiddenByteReads` for the token-by-token reasoning:
    ///
    /// 1. the streaming APIs must not appear at all;
    /// 2. the verification's own `FileHandle` loop must appear **exactly once, in one file**, which
    ///    is how the census's load-bearing invariant stops being a comment (review finding F2).
    @Test("the download path reads a payload only through the loop the census counts")
    func nothingInTheDownloadPathConsumesAByteStream() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let sources = Self.downloadPathSources(root: root)
        let scanned = try sources.map {
            (name: $0.lastPathComponent, code: try String(contentsOf: $0, encoding: .utf8))
        }

        // ── Rule 1: no streaming reads anywhere ───────────────────────────────────────────────
        let offenders = scanned
            .map { (name: $0.name, uses: Self.byteReadUses(in: $0.code, tokens: Self.forbiddenByteReads)) }
            .filter { !$0.uses.isEmpty }
            .map { "\($0.name) \($0.uses.map(\.description))" }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) read a payload through an API the census cannot \
            see. `.bytes(`/`AsyncBytes` is the 2026-08-23 defect verbatim — the response arrives as \
            a sequence of `UInt8` and the path walks a 199 MB pack one element at a time. The \
            transfer is a download task and is handed a finished file; see \
            `CityDownloadService.urlSession(_:downloadTask:didFinishDownloadingTo:)`.
            """
        )

        // ── Rule 2: the counted loop is the only file read, and it is where it says it is ──────
        //
        // This is also the scan's anti-vacuity control, and a far better one than a file count: a
        // scan that read nothing reports zero occurrences and fails these two assertions, where
        // `files.count >= 5` passed happily while a whole subdirectory went unread (F3(a)).
        for token in Self.boundedByteReads {
            let sites = scanned
                .flatMap { file in
                    Self.byteReadUses(in: file.code, tokens: [token])
                        .map { "\(file.name):\($0.line)" }
                }
            #expect(
                sites.count == 1 && sites[0].hasPrefix("\(Self.verificationFile):"),
                """
                `\(token)` occurs at \(sites) — it must occur exactly once, in \
                \(Self.verificationFile), because `CityTransferCensus` is built on that loop being \
                the app's ONLY contact with a transferred file's bytes. A second site is a read the \
                census does not count and no guard here would otherwise see: the reviewer's planted \
                shape (a `FileHandle` opened in `didFinishDownloadingTo` and walked one byte at a \
                time) is 4.2 million uncounted reads with every other assertion green. If this is a \
                deliberate new read site, it needs a census counter of its own before it needs an \
                entry here. Zero sites means this scan read nothing at all.
                """
            )
        }
    }

    /// **The calibration.** A scanner that found nothing looks exactly like a clean directory, and
    /// this repository has filed that defect. Both directions are checked, and the wrapped-call
    /// case is here because review finding F3(b) walked the previous line-at-a-time matcher.
    @Test("the byte-read scanner catches the defect's spellings and leaves the ordinary ones")
    func byteStreamScannerIsCalibrated() {
        let mustCatch = """
        let (bytes, _) = try await session.bytes(from: url)
        let (stream, response) = try await session.bytes(for: request)
        func walk(_ stream: URLSession.AsyncBytes) async throws { }
        let payload = try Data(contentsOf: staged)
        while let b = try probe.readData(ofLength: 1), !b.isEmpty { walked += 1 }
        let stream = InputStream(url: staged)
        """
        #expect(
            Self.byteReadUses(in: mustCatch, tokens: Self.forbiddenByteReads).map(\.line)
                == [1, 2, 3, 4, 5, 6],
            """
            the scanner missed a spelling it must catch: it found \
            \(Self.byteReadUses(in: mustCatch, tokens: Self.forbiddenByteReads)) where all six of \
            those lines read a payload through an API the census cannot see
            """
        )

        // **F3(b): the same call, wrapped.** No single line holds `.bytes(from:`, and `AsyncBytes`
        // is inferred rather than written, so the previous per-line matcher reported nothing. The
        // token starts on line 1, which is where the report must point.
        let wrapped = """
        let (stream, _) = try await session.bytes(
            from: url
        )
        """
        #expect(
            Self.byteReadUses(in: wrapped, tokens: Self.forbiddenByteReads)
                == [ByteReadUse(token: ".bytes(", line: 1)],
            """
            a wrapped call evaded the scanner: it found \
            \(Self.byteReadUses(in: wrapped, tokens: Self.forbiddenByteReads)). This is F3(b), and \
            it is an ordinary way to write a call at this indentation, not an obfuscation.
            """
        )

        // The reviewer's planted per-byte walk, as it would appear in `didFinishDownloadingTo`.
        // Both bounded tokens must be seen, which is what makes the count-of-one rule bite.
        let plantedWalk = """
        if let probe = try? FileHandle(forReadingFrom: staged) {
            var walked = 0
            while let b = try? probe.read(upToCount: 1), !b.isEmpty { walked += 1 }
        }
        """
        #expect(
            Self.byteReadUses(in: plantedWalk, tokens: Self.boundedByteReads) == [
                ByteReadUse(token: "FileHandle(forReadingFrom:", line: 1),
                ByteReadUse(token: "read(upToCount:", line: 3)
            ],
            """
            the scanner did not see F2's planted walk: \
            \(Self.byteReadUses(in: plantedWalk, tokens: Self.boundedByteReads))
            """
        )

        let mustNotCatch = """
        bytes: Int64(payload.count),
        record: record, fraction: Self.fraction(task.countOfBytesReceived, record)
        didWriteData bytesWritten: Int64,
        var payloadBytesRead: Int64 = 0
        guard bytes == record.bytes else { throw DownloadError.sizeMismatch(expected: record.bytes) }
        // the body was `session.bytes(from:)` and walked a URLSession.AsyncBytes per byte
        /// `for try await byte in session.bytes(…)`, one iteration per byte of a 199 MB pack.
        /// `Data(contentsOf:)`-style absence on a file URL surfaces as a plain Cocoa error.
        """
        #expect(
            Self.byteReadUses(in: mustNotCatch, tokens: Self.forbiddenByteReads).isEmpty,
            """
            the scanner flagged a line it must leave alone: \
            \(Self.byteReadUses(in: mustNotCatch, tokens: Self.forbiddenByteReads)). Lines 1–5 are \
            the ordinary byte *counts* and `record.bytes` reads these files are full of — the open \
            paren in `.bytes(` is what keeps them out. Lines 6–8 are comments, and unlike in this \
            gate's first version they are not hypothetical: 7 and 8 are copied from \
            `CityTransferCensus.swift` and `CityDownloader.swift:211` as they stand, and both spell \
            a watched token. Stripping comments is what lets those files keep describing the code.
            """
        )
    }

    // MARK: - The progress ring R43 §3 rules determinate

    /// Non-uniform bytes, so a transport cannot compress its way out of the measurement.
    static func payload(bytes byteCount: Int) -> Data {
        var payload = Data()
        payload.reserveCapacity(byteCount)
        var seed: UInt64 = 0x2026_0823
        for _ in 0..<byteCount {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            payload.append(UInt8(truncatingIfNeeded: seed >> 33))
        }
        return payload
    }

    /// A **service** pointed at an in-process http bucket, with `city` parked at its path.
    ///
    /// The twin of `httpBucket` for the half that moved: the transfer is `CityDownloadService`'s
    /// now, and it owns its own session rather than being handed one, so what a test can inject is
    /// the configuration. A background configuration ignores `protocolClasses` outright, which is
    /// why every test here runs the service over an ephemeral one — see `CityDownloadTests.transfer`
    /// for what that does and does not prove.
    @MainActor
    static func httpService(
        payload: Data,
        for city: CityManifest.City,
        library: CityLibrary,
        stalls: Bool = false,
        pacing: TimeInterval = 0
    ) -> (CityDownloadProgress, CityDownloadService) {
        let base = URL(string: "https://cities-fixture.invalid/\(UUID().uuidString)")!
        CityBucketFixtureProtocol.park(
            base.appendingPathComponent(city.path), body: payload, stalls: stalls, pacing: pacing
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CityBucketFixtureProtocol.self]
        let progress = CityDownloadProgress()
        let service = CityDownloadService(
            library: library, baseURL: base, configuration: configuration, progress: progress
        )
        return (progress, service)
    }

    /// A downloader pointed at an in-process http bucket, with `city` parked at its path.
    static func httpBucket(
        payload: Data,
        for city: CityManifest.City,
        stalls: Bool = false
    ) -> (CityDownloader, URLSession) {
        let base = URL(string: "https://cities-fixture.invalid/\(UUID().uuidString)")!
        CityBucketFixtureProtocol.park(
            base.appendingPathComponent(city.path), body: payload, stalls: stalls
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CityBucketFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        return (CityDownloader(baseURL: base, session: session), session)
    }

    /// **The ring is told, and this is measured over http because nothing else can see it.**
    ///
    /// R43 §3 rules `downloading` as *"`Downloading…` with a determinate progress bar"*. The
    /// previous body used `session.download(from:delegate:)`, whose task-specific delegate **never
    /// receives `didWriteData`** — measured at 0 calls against 4 through a classic
    /// `downloadTask` with the same delegate, session and body — so the ring sat at 0 % for the
    /// whole of a 199 MB transfer, which is exactly what makes a reader conclude a download is
    /// stuck.
    ///
    /// **The harness is http, and the reason is pacing rather than the scheme.** A `file://`
    /// fixture does report progress through this path — measured on iPhone 16 Pro over this same
    /// 2 MB body: 8 `didWriteData` calls to a bare delegate, and 9 fractions out of `downloadCity`
    /// over a `file://` base. So the "0 callbacks over `file://`" this comment claimed in review
    /// round 2 was false; that 0 was the async convenience's, which reports nothing over either
    /// scheme. What a file URL will not do is let the *test* choose the pacing. The bucket here is an in-process `URLProtocol` handing over 64 KiB at a
    /// time, so the monotone run of fractions asserted below describes a transfer whose shape is
    /// known, rather than whatever the filesystem happened to do that morning. Nothing leaves the
    /// machine either way.
    ///
    /// **Three minutes, not one.** The budget is not a margin the assertions lean on — nothing here
    /// is bounded by wall clock any more (see the sampler below) — but the whole test took **53.2 s**
    /// on the GitHub runner that filed review finding F1, against a nominal 1.6 s here. A one-minute
    /// limit would have turned the next slightly slower runner into a timeout instead of a pass.
    @Test("the download ring is told how far along the transfer is", .timeLimit(.minutes(3)))
    func progressIsReportedDuringTheTransfer() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Self.payload(bytes: 2 * 1024 * 1024)
        let city = CityManifest.City(
            id: "us-ny-nyc-manhattan", displayName: "Manhattan", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-ac7b1ccc",
            path: "cities/us-ny-nyc-manhattan/v/us-ny-nyc-manhattan.sqlite",
            bytes: Int64(payload.count),
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
        // ── How this is observed, and what that costs in precision ────────────────────────────
        //
        // **The ring is no longer fed through a callback the test holds.** It reads
        // `CityDownloadProgress`, which the composition root owns, so a test *samples* it rather
        // than receiving every report. Two consequences, and both are honest limits rather than
        // things to hide:
        //
        // 1. **The fixture is paced**, at 50 ms a chunk. Sampling a transfer that completes in four
        //    milliseconds measures the sampler.
        // 2. **The values are observed, not sampled, so starvation cannot thin them.** This used
        //    to read as a caveat about a sampler that a neighbouring `@MainActor` test could starve
        //    — and the caveat turned out to be the defect (see `FractionObserver`, and the note at
        //    the sampler's grave below). What is recorded now is every value the box is given,
        //    from inside the turn that gives it. The load-bearing assertion is still the one at the
        //    bottom — **a fraction at or past half way** — and deleting the publish still produces
        //    exactly one value, `0.0`, the one `start` put there.
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let (progress, service) = await Self.httpService(
            payload: payload, for: city, library: library, pacing: 0.05
        )

        // ── The sampler's lifetime is the transfer's, and that is review finding F1 ───────────
        //
        // **This test was red on CI, and the failure was structural rather than a flake.** The body
        // that shipped sampled `for _ in 0..<600` at 5 ms — about three seconds, always — while the
        // transfer's duration is set by the fixture's pacing and by whatever else the machine is
        // doing. The two quantities were unrelated: 32 chunks × 50 ms is 1.6 s nominal, so on this
        // simulator the sampler beat the transfer by under 2×, and on the GitHub runner (run
        // 32952106597) the same test took 53.2 s and the sampler expired after 2 chunks of 32 —
        // `max` 0.0625, against an assertion of 0.5, on a transfer that was working perfectly.
        // That is the wall-clock-margin defect class this repo has now filed twice.
        //
        // **The first fix was to make the sampler's lifetime the transfer's** — `while
        // !Task.isCancelled`, cancelled after `waitUntilIdle()` — on the argument that the sampler
        // and the publisher share the main actor and therefore stall and recover together. It was
        // calibrated before it was believed, by making the transfer outlast the old window the way
        // the runner's load did (pacing 0.4 s a chunk, a 12.8 s transfer against a 3 s budget):
        // the shipped body took 599 samples, covered **10 of 32** chunks and went red at `max`
        // 0.3125 — the runner's failure, reproduced — while the cancel-driven one took 2157,
        // covered **32 of 32** and reached 1.0.
        //
        // **And it was still wrong, which run 33197196976 said and this machine could not.** The
        // shared-main-actor argument is false: `didWriteData` enqueues a *separate*
        // `Task { @MainActor }` per whole percent, and `settle` enqueues one more that clears the
        // box. A sampler resumed by `Task.sleep` is just another job in that queue with no claim on
        // any particular position in it, and on the runner it got no turn at all between `start`
        // and the end of the transfer: **one** recorded value, `0.0`, which is bit-for-bit the
        // output of deleting the publish. Both the calibration above and this simulator's 32
        // distinct samples were true and neither was evidence, because the thing that varies is not
        // the transfer's length — it is whether the observer is scheduled inside it.
        //
        // **So the sampler is gone.** `FractionObserver` records from inside the mutation itself
        // (`withObservationTracking`'s `onChange`), which is not a turn anything can be denied. See
        // its header. There is no duration and no scheduling left in this observation to lose.
        let observer = await MainActor.run { () -> FractionObserver in
            let observer = FractionObserver(progress)
            // Started first, so the observer's first registration sees the box already holding this
            // transfer's own 0 — and every value after it is one `didWriteData` put there.
            service.start(city)
            observer.begin()
            return observer
        }
        await service.waitUntilIdle()

        // `observer` is held by this local until here on purpose: `onChange` captures it weakly, so
        // an observer nothing keeps alive stops re-registering and the recording quietly stops.
        let fractions = observer.log.all
        let distinct = Set(fractions)
        #expect(!fractions.isEmpty, "the ring was told nothing at all — it draws 0% throughout")
        #expect(
            distinct.count >= 2,
            "the ring saw \(distinct.count) distinct fraction(s) across the transfer: \(fractions)"
        )
        #expect(fractions == fractions.sorted(), "progress went backwards: \(fractions)")
        #expect(
            (fractions.max() ?? 0) >= 0.5,
            "the ring never got past \(fractions.max() ?? 0) — it is not being told during the transfer"
        )
        // A transfer that reported beautifully and verified nothing would satisfy all of the above.
        #expect(await progress.installCount == 1)
        #expect(
            try Data(contentsOf: library.fileURL(id: city.id, version: city.version)).count
                == payload.count
        )
    }

    /// The new transport keeps the old one's refusal: one sabotaged byte and the file is gone.
    ///
    /// Asserted over http as well as over the `file://` fixtures `CityDownloadTests` already uses,
    /// because the transport is what changed — the verification reads the finished file, and a
    /// finished file is now assembled by URLSession rather than by this app.
    @Test("a sabotaged byte is still refused, and staging is left empty")
    func sabotagedByteIsRefusedOverHTTP() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-sabotage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var payload = Self.payload(bytes: 256 * 1024)
        let honest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        payload[payload.count / 2] ^= 0x01  // one byte, same length: only sha256 can catch it

        let city = CityManifest.City(
            id: "us-ny-nyc-manhattan", displayName: "Manhattan", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-ac7b1ccc",
            path: "cities/us-ny-nyc-manhattan/v/us-ny-nyc-manhattan.sqlite",
            bytes: Int64(payload.count), sha256: honest
        )
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let (progress, service) = await Self.httpService(
            payload: payload, for: city, library: library
        )
        _ = await MainActor.run { service.start(city) }
        await service.waitUntilIdle()

        #expect(await progress.failedCityID == city.id)
        #expect(await progress.installCount == 0)
        #expect(library.installedVersion(of: city.id) == nil)
        #expect(
            (try? FileManager.default.contentsOfDirectory(atPath: library.stagingURL.path))?
                .isEmpty != false,
            "a refused file was left in staging"
        )
    }

    // MARK: - Report path: Cancel is not a failure

    /// Both spellings of "the reader pressed Cancel" are recognised.
    ///
    /// `session.bytes` threw Swift's `CancellationError`; a cancelled `URLSessionDownloadTask`
    /// completes with `URLError(.cancelled)`. Only the first was handled, so the transport change
    /// silently turned every Cancel into `Download failed. Nothing was changed.`
    @Test("cancellation is recognised in both of the spellings this path produces")
    func bothCancellationSpellingsAreRecognised() {
        #expect(CityDownloader.isCancellation(CancellationError()))
        #expect(CityDownloader.isCancellation(URLError(.cancelled)))
        // Not everything is a cancellation — a real failure must still reach the failure line.
        #expect(!CityDownloader.isCancellation(URLError(.timedOut)))
        #expect(!CityDownloader.isCancellation(CityDownloader.DownloadError.unacceptableStatus(500)))
    }

    /// **Cancel on the running screen leaves no failure line**, driven through the model, over a
    /// transport that stays open until it is cancelled — so the error really is the one URLSession
    /// produces rather than one the test constructed.
    ///
    /// **The fixture reports the wrong error on purpose.** `stopLoading` answers
    /// `.networkConnectionLost`, never `.cancelled`, so a `failedCityID` that stays nil here is
    /// URLSession's own translation of the cancelled task state being recognised — not the test
    /// handing the code the answer. That distinction is what the deleted
    /// `cancelledTransferSurfacesAsCancellation` existed to make, and it is made here now that the
    /// transfer no longer throws to a caller who could inspect it: the service publishes one of two
    /// outcomes, and this asserts which one.
    ///
    /// Both spellings still matter — `CityDownloader.isCancellation` is what
    /// `bothCancellationSpellingsAreRecognised` pins directly.
    @MainActor
    @Test("cancelling a download does not draw the failure line", .timeLimit(.minutes(1)))
    func cancelDoesNotRenderFailure() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Self.payload(bytes: 64 * 1024)
        let city = CityManifest.City(
            id: "us-ny-nyc-manhattan", displayName: "Manhattan", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-ac7b1ccc",
            path: "cities/us-ny-nyc-manhattan/v/us-ny-nyc-manhattan.sqlite",
            bytes: Int64(payload.count),
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
        // Serves the body and then never finishes: the transfer is live until it is cancelled.
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let (progress, service) = Self.httpService(
            payload: payload, for: city, library: library, stalls: true
        )

        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(baseURL: dir),
            service: service,
            downloads: progress,
            bundledCities: [],
            installableCityLimit: 9, onInventoryChange: {}
        )
        model.download(city)
        #expect(model.downloading?.id == city.id, "the download never started, so nothing was cancelled")

        model.cancelDownload()
        await service.waitUntilIdle()

        #expect(model.downloading == nil, "the download never settled after Cancel")
        #expect(
            model.failedCityID == nil,
            "Cancel drew R43 §3's failure line — failedCityID is \(String(describing: model.failedCityID))"
        )
        #expect(progress.installCount == 0)
    }

    /// **A transfer cancelled in the same turn it was started still settles**, rather than parking
    /// forever on a task nobody will ever hear about again.
    ///
    /// This is the ordering the old `downloadFile` handshake existed for — a Swift task cancelled
    /// before `task.resume()` — and it survives the move to a background session in a different
    /// shape: there is no continuation to park now, but there is a `current` transfer whose
    /// clearing every waiter depends on, and a `Cancel` that raced `start` could have left it set.
    ///
    /// **The bucket stalls, and that is load-bearing.** A 64 KiB body over a bucket that completes
    /// would finish in microseconds whatever this code did, so "it settled quickly" would be true
    /// of anything. This body is served and then never finished: the only way out is cancellation.
    ///
    /// The five-second bound is a hang detector, not a performance assertion.
    @MainActor
    @Test("a download cancelled in the same turn it started settles rather than hanging",
          .timeLimit(.minutes(1)))
    func immediateCancelSettlesPromptly() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-precancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Self.payload(bytes: 64 * 1024)
        let city = CityManifest.City(
            id: "us-ny-nyc-manhattan", displayName: "Manhattan", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-ac7b1ccc",
            path: "cities/us-ny-nyc-manhattan/v/us-ny-nyc-manhattan.sqlite",
            bytes: Int64(payload.count),
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let (progress, service) = Self.httpService(
            payload: payload, for: city, library: library, stalls: true
        )

        // No await between the two: the cancel is issued before the transport can have got
        // anywhere. If `current` were left set by that race, the wait below would never return and
        // the test's own time limit is what would report it.
        _ = service.start(city)
        service.cancel()
        await service.waitUntilIdle()

        #expect(progress.inFlight == nil)
        #expect(progress.failedCityID == nil, "an immediate Cancel drew the failure line")
        #expect(progress.installCount == 0)
    }
}

/// A thread-safe list of the fractions the progress ring was told, because the sampler that reads
/// them runs on the main actor while the transfer reports from URLSession's own queue.
final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double] = []

    func record(_ fraction: Double) {
        lock.lock()
        fractions.append(fraction)
        lock.unlock()
    }

    var all: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return fractions
    }
}

/// Every value the download box is given, recorded **synchronously in the turn that changes it**.
///
/// **Not a sampler, and review finding F1's second round is why.** The first fix made the
/// sampler's lifetime the transfer's instead of a fixed 600 × 5 ms budget, which removed one
/// failure mode and left the real one standing: a sampler resumed by `Task.sleep` is a main-actor
/// job competing with the ~100 `Task { @MainActor }` jobs `didWriteData` enqueues, one per whole
/// percent, and with `settle`'s job that clears the box at the end. On the GitHub runner it lost
/// that race outright — run 33197196976 recorded **one** value, `0.0`, the read it took
/// immediately after `start`, and then never got another turn until `inFlight` was already nil.
/// `(distinct.count → 1) >= 2` and `((fractions.max() ?? 0) → 0.0) >= 0.5`, which is the same
/// output as deleting the publish. A test that cannot tell a starved observer from the defect it
/// guards is not guarding anything.
///
/// `withObservationTracking`'s `onChange` runs **inside the mutation**, on the actor doing it, so
/// there is no turn to be denied and no ordering to lose: if the box is told, this hears it. The
/// value read is the one being left behind (the callback fires before the store), so the sequence
/// recorded is every value the box held except its last — which is exactly the run of fractions
/// this test asserts over, since the last one is the `nil` that `settle` writes.
///
/// This is not the continuation recipe `AlmanacModel`'s header rejects: nothing here awaits a
/// change, so there is no continuation to leak when the owner goes away.
@MainActor
final class FractionObserver {
    let log = FractionLog()
    private let progress: CityDownloadProgress

    init(_ progress: CityDownloadProgress) { self.progress = progress }

    /// Begins recording. Call **after** `start`, so the first value seen is the transfer's own 0.
    func begin() { track() }

    private func track() {
        withObservationTracking {
            _ = progress.inFlight
        } onChange: { [weak self] in
            // `CityDownloadProgress` is `@MainActor`, so every mutation of it is a main-actor one.
            MainActor.assumeIsolated {
                guard let self else { return }
                if let fraction = self.progress.inFlight?.fraction { self.log.record(fraction) }
                // Re-registered here rather than from a scheduled job: a deferred re-registration
                // is a window, and a window is the thing this type exists to not have.
                self.track()
            }
        }
    }
}

/// An in-process http bucket: a transfer whose pacing the test chooses.
///
/// **A `file://` fixture does deliver `didWriteData` through the classic download task** — 8 calls
/// for a 2 MB body, measured. The claim that it reports zero was a measurement of the async
/// convenience, which reports zero over every scheme; `progressIsReportedDuringTheTransfer` carries
/// the correction and the numbers. What a file URL will not do is hand the bytes over at a rate the
/// test picked. This serves a parked body over `https` in
/// 64 KiB chunks, entirely inside the process; nothing leaves the machine and no port is opened.
///
/// **It also serves a transfer that never ends** (`stalls`), which is the only way to hold a
/// download open long enough to cancel one deliberately.
///
/// **Nothing clears the table between tests, deliberately.** `URLProtocol` state is process-wide
/// and Swift Testing runs suites in parallel; a `reset()` here is what once wiped another suite's
/// parked answer mid-fetch (`StubStorageProtocol`'s own note records it). Every parked URL carries
/// a fresh `UUID` instead, so no two tests can collide.
final class CityBucketFixtureProtocol: URLProtocol {

    private struct Object {
        let body: Data
        /// Emits the body and then never finishes, so a test can cancel a live transfer.
        let stalls: Bool
        /// Seconds to wait between chunks. **Zero is the default and a paced fixture is the
        /// exception**, because a transfer that finishes in microseconds cannot be *observed*
        /// mid-flight — and observing it is the whole of what the progress ring's test now has to
        /// do. Progress used to arrive through a callback the test held, which caught every report
        /// however fast; the ring is fed through the composition root's box now
        /// (`CityDownloadProgress`), which a test reads by sampling, and sampling a 4 ms transfer
        /// measures the sampler.
        let pacing: TimeInterval
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var objects: [String: Object] = [:]

    static func park(_ url: URL, body: Data, stalls: Bool = false, pacing: TimeInterval = 0) {
        lock.lock()
        defer { lock.unlock() }
        if objects[url.absoluteString] != nil {
            Issue.record("\(url.absoluteString) was already parked; give this fixture its own UUID.")
        }
        objects[url.absoluteString] = Object(body: body, stalls: stalls, pacing: pacing)
    }

    private static func object(for url: URL?) -> Object? {
        guard let url else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return objects[url.absoluteString]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        object(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let object = Self.object(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(object.body.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let chunk = 64 * 1024
        var offset = 0
        while offset < object.body.count {
            let end = min(offset + chunk, object.body.count)
            client?.urlProtocol(self, didLoad: object.body.subdata(in: offset..<end))
            offset = end
            if object.pacing > 0 { Thread.sleep(forTimeInterval: object.pacing) }
        }
        // A stalling object never finishes; the task stays live until the reader cancels it.
        guard !object.stalls else { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// **Reports a deliberately WRONG error**, so the test above cannot be measuring the fixture's
    /// choice. A custom protocol has to complete its client somehow when the loader stops, and
    /// answering `.cancelled` here would hand `CityDownloader` the very error the assertion is
    /// about. `.networkConnectionLost` is a plain failure; if a cancelled download still surfaces
    /// as `.cancelled`, that is URLSession's own translation of the task state and it is the fact
    /// the model relies on.
    override func stopLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    }
}
