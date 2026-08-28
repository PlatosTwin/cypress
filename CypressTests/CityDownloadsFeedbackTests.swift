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

    /// The transfer no longer walks the response one byte at a time.
    ///
    /// **A ratio against a control, not a wall-clock bound**, and the difference is the whole
    /// design of this test. A fixed bound has to be slower than the defect on the slowest machine
    /// and faster than the fix on that same machine, and at the payload sizes a unit suite can
    /// afford there is no such number: on the 4 MB fixture below, measured on the assigned
    /// simulator, the per-byte control takes **0.283 s** and the download task **0.0078 s**, so any
    /// bound loose enough to be stable (say six seconds) sits far above *both* and would certify the
    /// defect as fixed. That is this project's signature failure — a guard that is green while the
    /// defect is present.
    ///
    /// So the test measures the defect itself, here, on whatever machine is running: it walks the
    /// same fixture with `URLSession.AsyncBytes` exactly as the old body did, and then requires the
    /// real download to beat that by **6×**. Machine speed cancels, and the assertion can only pass
    /// if the two code paths are genuinely different in kind.
    ///
    /// **Six, and the arithmetic below is the committed assertion's own** — corrected by review
    /// finding F5, which caught three sentences still arguing for a 10× threshold above a line that
    /// says 6, and a display name promising an order of magnitude the assertion does not require.
    /// A reader debugging a red here was being handed a bound that is not the one that fired.
    ///
    /// **The margin is real but not enormous, and it is stated rather than implied.** The factor is
    /// not headroom; it is spent on the comparison. Re-measured on iPhone 16e for this correction,
    /// through the narrowed window below: `elapsed 0.007778 s`, `control 0.282818 s`, ratio
    /// **36.4** — so the committed bound is `0.007778 × 6 = 0.0467 s` against that control, and the
    /// slack between the assertion and the measurement is about **6.1×**. Worth knowing before
    /// reading a red here as a performance regression: the number to revisit if it ever flakes is
    /// this factor, not the fixture size.
    ///
    /// Byte count and sha256 are asserted alongside, because a fast download that verified nothing
    /// would satisfy a timing test perfectly.
    @Test("the transfer beats a per-byte walk of the same bytes by a wide margin",
          .timeLimit(.minutes(3)))
    func downloadIsNotPerByte() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 4 MB of non-uniform bytes — a compressible payload would let a transport cheat the clock.
        let byteCount = 4 * 1024 * 1024
        var payload = Data()
        payload.reserveCapacity(byteCount)
        var seed: UInt64 = 0x2026_0823
        for _ in 0..<byteCount {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            payload.append(UInt8(truncatingIfNeeded: seed >> 33))
        }

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

        // The control: the loop this fix removed, run against the same file on this machine.
        let controlStarted = Date()
        var walked = 0
        let (bytes, _) = try await URLSession.shared.bytes(from: object)
        for try await _ in bytes { walked += 1 }
        let control = Date().timeIntervalSince(controlStarted)
        #expect(walked == byteCount, "the control did not read the fixture it was calibrating on")

        // ── What is inside the measured window, and why ───────────────────────────────────────
        //
        // **Only what scales with the size of the file.** The transfer moved onto a service that
        // owns its own `URLSession`, so this measurement acquired two fixed costs the old one did
        // not have: constructing the session, and the first use of URLSession in the process. Both
        // are a constant number of milliseconds however big the pack is, and neither is the thing
        // this test guards against — the defect is a loop that runs once per BYTE, which is pure
        // slope and no intercept.
        //
        // So the session is built before the clock starts, and a tiny transfer is run through it
        // first. **The warm-up is not a fudge, and it was added after a measurement**: on a fresh
        // DerivedData — a cold process, first URLSession use — the 4 MB transfer measured 0.333 s
        // against a 1.749 s control, a ratio of 5.2, where the same code on a warm process cleared
        // 10 comfortably. The intercept was most of the cold reading.
        let library = CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true))
        let progress = await CityDownloadProgress()
        let service = CityDownloadService(
            library: library, baseURL: dir, configuration: .ephemeral, progress: progress
        )

        let warmUpPayload = Data("warm".utf8)
        let warmUp = CityDownloadTests.entry(id: "warmup", payload: warmUpPayload)
        try CityDownloadTests.park(payload: warmUpPayload, for: warmUp, in: dir)
        _ = await MainActor.run { service.start(warmUp) }
        await service.waitUntilIdle()
        // The warm-up is a real transfer and installs a real file, so the count below is measured
        // as a delta rather than against zero.
        let installsBefore = await progress.installCount

        // ── Neither endpoint is a main-actor hop, which is review finding F6 ──────────────────
        //
        // The window used to open on `Date()` in this task and close on `waitUntilIdle()`, and both
        // ends crossed the main actor: `start` is `@MainActor`, and `waitUntilIdle` is resumed from
        // inside `settle`'s `Task { @MainActor … }`. The control — a cooperative-pool loop over
        // `URLSession.AsyncBytes` — crosses it at neither end, so those two hops were pure
        // asymmetry inside a window whose whole budget is tens of milliseconds, on a main actor
        // this suite's own comments document as contended.
        //
        // **The clock now starts after the hop in** — inside the main-actor closure, so the wait to
        // get there is not the transfer's time — **and stops on the file rather than on idle.** The
        // install is synchronous inside `didFinishDownloadingTo`, on URLSession's delegate queue and
        // off the main actor, so the instant the file exists at its immutable path is the instant
        // the bytes finished being transferred, verified and moved: exactly the work that scales
        // with the size of the file, which is what the paragraph above says belongs in here. The
        // poll runs on the cooperative pool, the same place the control's loop runs, so the two are
        // starved and recovered alike.
        //
        // This narrows the window rather than loosening the assertion, and it cannot hide the
        // defect: restoring the per-byte loop puts 4.2 million iterations *inside* these same two
        // endpoints, so `elapsed` still converges on `control`.
        //
        // The deadline is a hang guard, not a bound the assertion leans on — without it a transfer
        // that never lands spins here until the test's own time limit instead of failing with a
        // number in the message.
        let installedURL = library.fileURL(id: city.id, version: city.version)
        let started = await MainActor.run { () -> Date in
            let started = Date()
            service.start(city)
            return started
        }
        let deadline = started.addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: installedURL.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000)
        }
        let elapsed = Date().timeIntervalSince(started)
        await service.waitUntilIdle()

        // **Six, not ten, and the number is not the point.** Restoring the per-byte loop makes
        // `elapsed` and `control` the same measurement — both walk 4.2 million bytes one at a time
        // — so the ratio collapses to about 1 and any threshold above 2 catches it. Six is far
        // enough above the noise of a loaded CI machine to not flake, and far enough below what a
        // working implementation achieves to still be a guard.
        #expect(
            elapsed * 6 < control,
            "download took \(elapsed)s against a \(control)s per-byte control — the per-byte loop is back"
        )

        // A fast transfer that verified and installed nothing would satisfy the clock perfectly.
        #expect(await progress.installCount == installsBefore + 1)
        let landed = try Data(contentsOf: library.fileURL(id: city.id, version: city.version))
        #expect(landed.count == payload.count)
        #expect(SHA256.hash(data: landed).map { String(format: "%02x", $0) }.joined() == city.sha256)
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
        // 2. **The count of distinct fractions is not a strong assertion and is not treated as
        //    one.** The sampler runs on the main actor, Swift Testing runs suites in parallel, and
        //    a neighbouring `@MainActor` test can starve it — measured, on a cold fresh-DerivedData
        //    run, at 2 distinct samples where a warm run saw many. So the load-bearing assertion is
        //    the one below it: **a fraction at or past half way**, which no amount of starvation
        //    produces if `didWriteData` is not publishing. Red-proved by deleting the publish: the
        //    sampler then sees exactly one value, `0.0`, which is what `start` put there.
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
        // **The fix is cancellation rather than counting, and it is not a widened number.** The
        // sampler runs until the transfer is over — the `cancel()` below sits after
        // `waitUntilIdle()` — so a slower machine does not shorten the observation, it lengthens
        // it. There is no duration in this test for a load to exceed.
        //
        // It also cannot be starved out from under the thing it is watching, because **the sampler
        // and the publisher share the main actor**: `CityDownloadProgress` is `@MainActor`, so a
        // main actor too busy to run this loop is one too busy to publish the fractions the loop
        // would have read. They stall and recover together. That is what makes the observation
        // load-*independent* rather than merely load-tolerant, and it is why consequence 2 above
        // is a note about precision rather than a hazard to the assertion.
        //
        // ── Calibrated, because an instrument nobody checked is a coincidence ────────────────
        //
        // CI's failure was reproduced on this machine before the fix was believed, by making the
        // transfer outlast the old sampler the way the runner's load did: pacing raised to **0.4 s
        // a chunk**, a 12.8 s transfer against a 3 s observation window. Both bodies were run over
        // that same fixture on iPhone 16e, and the sampler was instrumented to report what it saw.
        //
        //   shipped body (`for _ in 0..<600`)   samples 599   distinct 10 of 32   max **0.3125**
        //     → red: `((fractions.max() ?? 0) → 0.3125) >= 0.5`, the same expectation and the same
        //       shape as the runner's `→ 0.0625`. 599 is the budget, not a measurement of anything.
        //   this body (`while !Task.isCancelled`) samples 2157  distinct **32 of 32**  max **1.0**
        //     → green, having watched the whole transfer rather than the first quarter of it.
        //
        // The pacing was restored to 0.05 afterwards and the instrument removed. Note what the
        // first row is *not*: at 0.2 s a chunk the shipped body stopped at 19 of 32 and still
        // scraped past the assertion at 0.59375 — it was already failing to watch the transfer two
        // pacings before it started failing the test, which is why the count of chunks it covers,
        // rather than the color of the run, is the thing that was measured here.
        let reported = FractionLog()
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                if let fraction = progress.inFlight?.fraction { reported.record(fraction) }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        _ = await MainActor.run { service.start(city) }
        await service.waitUntilIdle()
        sampler.cancel()

        let fractions = reported.all
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
