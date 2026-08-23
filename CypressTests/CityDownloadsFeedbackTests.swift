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
/// because a `file://` fixture cannot observe download progress at all, measured; no port is opened
/// and no packet leaves the machine either way. Every other fact is a pure value.
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
        isActive: Bool = false
    ) -> CityDownloadRow {
        .published(
            city: city, state: state, isActive: isActive,
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

    /// A city that is installed, not in use, and has an update waiting must still offer `Use`.
    ///
    /// R43 §3's table gave this state `Update` and `Remove` only, which strands a complete,
    /// attachable copy the moment the catalog moves ahead of it — the tester reached that state by
    /// using Manhattan, switching back to the built-in inventory, and finding no way back.
    @Test("an installed city with an update waiting can still be used")
    func updateAvailableStillOffersUse() {
        let manhattan = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")
        let state = CityInstallState.updateAvailable(installedVersion: "s17-r2026-08-01-1111aaaa")

        let notInUse = Self.row(manhattan, state: state)
        #expect(notInUse.affordances.contains(.use))
        #expect(notInUse.affordances == [.use, .update, .remove])

        // In use, the label replaces the button — the same substitution every other state makes.
        let inUse = Self.row(manhattan, state: state, isActive: true)
        #expect(inUse.affordances == [.inUseLabel, .update, .remove])
        #expect(!inUse.affordances.contains(.use))
    }

    /// The affordance and the action agree: `Use` is drawn for a state whose copy is on the device,
    /// so the button it draws has something to attach.
    @Test("every state that offers Use has a copy on the device to attach")
    func useIsOnlyOfferedForAnOnDeviceCopy() {
        let city = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")
        let states: [CityInstallState] = [
            .notInstalled,
            .installedCurrent(installedVersion: "s17-r2026-08-22-ac7b1ccc"),
            .updateAvailable(installedVersion: "s17-r2026-08-01-1111aaaa"),
            .needsNewerApp(installedVersion: nil),
            .needsNewerApp(installedVersion: "s17-r2026-08-01-1111aaaa"),
            .bundled(contentRev: "2026-07-31"),
            .bundledOutdated(bundledContentRev: "2026-07-31")
        ]
        for state in states {
            let row = Self.row(city, state: state)
            if row.affordances.contains(.use) {
                #expect(state.isOnDevice, "Use drawn for \(state), which is not on the device")
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
    @discardableResult
    static func installBoroughPack(
        in library: CityLibrary,
        packID: String = "us-ny-nyc-manhattan",
        idSpace: String = "us-ny-nyc",
        version: String = "s17-r2026-08-22-4f6ebaaa",
        contentRev: String = "2026-08-22",
        schemaVersion: Int = 17
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
        // The name in the file is the CITY's. A borough keeps its id rather than five rows all
        // reading `New York City` — see `CityLibrary.installedCities()`.
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
                bundledCities: [],
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
        #expect(manhattan.affordances == [.use, .remove])

        // A genuinely newer record still flags — the fix withholds nothing it should offer.
        let newer = await rows(
            publishedContentRev: "2026-09-01", publishedVersion: "s17-r2026-09-01-ac7b1ccc"
        )
        let updated = try #require(newer.first { $0.id == "us-ny-nyc-manhattan" })
        #expect(updated.stateLine == "Update available · s17-r2026-08-22-4f6ebaaa installed")
        #expect(updated.affordances == [.use, .update, .remove])
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
        #expect(row.detailLine == "A newer record is available to download.")
        #expect(row.affordances == [.download])
        #expect(row.isOnDevice)
        // The date is stated once, not once per line.
        #expect(row.detailLine?.contains("2026-07-31") == false)
    }

    // MARK: - Report: "we should say WHAT CITIES ship in the pre-built seed"

    /// The built-in card names what is inside it, from names the seed itself states.
    @Test("the built-in card names the cities it ships")
    func builtInCardNamesItsCities() {
        #expect(
            CityDownloadRow.builtIn(isActive: true, cityNames: ["San Francisco", "San Jose"])
                .detailLine == "Includes San Francisco and San Jose"
        )
        #expect(
            CityDownloadRow.builtIn(isActive: true, cityNames: ["San Francisco"])
                .detailLine == "Includes San Francisco"
        )
        #expect(
            CityDownloadsCopy.builtInCitiesLine(["A", "B", "C"]) == "Includes A, B, and C"
        )
        // A bundle that names nothing says nothing extra, rather than an empty sentence.
        #expect(CityDownloadRow.builtIn(isActive: true, cityNames: []).detailLine == nil)
        // The ruled subtitle is untouched (R43 §3).
        #expect(
            CityDownloadRow.builtIn(isActive: true).stateLine
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
            .builtIn(isActive: true, cityNames: ["San Francisco", "San Jose"]),
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
                    ("On this phone", false, ["built-in", "sf"]),
                    // Los Angeles has one pack, so it stays under the umbrella rather than earning
                    // a heading of its own — and the umbrella is drawn because it has that row.
                    ("Available to download", false, ["us-ca-la"]),
                    ("New York City", true, [
                        "us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens"
                    ])
                ].map(String.init(describing:))
        )
    }

    /// **The production shape today, and it used to draw an empty heading.** Every available pack in
    /// the live catalog is a New York borough, so they all group — and `Available to download` was
    /// drawn with nothing under it, immediately above `New York City`. A heading whose entire
    /// content is another heading is furniture by this file's own rule, so it is dropped and the
    /// city group heads the run.
    @Test("an umbrella heading with nothing of its own is not drawn")
    func emptyUmbrellaHeadingIsNotDrawn() {
        let cities = [Self.borough("manhattan", "Manhattan"), Self.borough("brooklyn", "Brooklyn")]
        let rows: [CityDownloadRow] = [
            .builtIn(isActive: true, cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .notInstalled),
            Self.row(cities[1], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.map(\.title) == ["On this phone", "New York City"])
        // Not nested: there is no heading above it in its own run, so it takes the section break.
        #expect(sections.map(\.isCityGroup) == [false, false])
        #expect(sections.flatMap { $0.rows.map(\.id) }.count == 3)
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
            .builtIn(isActive: false, cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v"), isActive: true),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .installedCurrent(installedVersion: "v"))
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.map(\.title) == ["On this phone", "New York City"])
        #expect(
            sections.last?.rows.map(\.id)
                == ["us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens"]
        )
        // Nested under `On this phone`, which is drawn above it because the built-in card is there.
        #expect(sections.last?.isCityGroup == true)
    }

    /// A city can now head a group in **both** runs at once — three boroughs downloaded, two not —
    /// and a section id that was just the title would give one `ForEach` two identical ids, which
    /// SwiftUI resolves by dropping rows.
    @Test("two groups for one city, in different runs, keep distinct identities")
    func sectionIdentitiesAreUniqueAcrossRuns() {
        let cities = (1...4).map { Self.borough("b\($0)", "Borough \($0)") }
        let rows: [CityDownloadRow] = [
            .builtIn(isActive: true, cityNames: []),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[1], state: .installedCurrent(installedVersion: "v")),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled)
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        #expect(sections.map(\.title) == ["On this phone", "New York City", "New York City"])
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
            .builtIn(isActive: false, cityNames: ["San Francisco"]),
            Self.row(cities[0], state: .installedCurrent(installedVersion: "v"), isActive: true),
            Self.row(cities[1], state: .notInstalled),
            Self.row(cities[2], state: .updateAvailable(installedVersion: "old"))
        ]

        let sections = CityDownloadSection.sections(
            from: rows, parentCity: Self.parentCity(in: cities)
        )
        let flattened = sections.flatMap(\.rows)
        #expect(flattened.count == rows.count)
        #expect(Set(flattened.map(\.id)) == Set(rows.map(\.id)))
        // Brooklyn has an update waiting, so it is on the phone and leads rather than being grouped.
        #expect(
            sections.first(where: { $0.title == "On this phone" })?.rows.map(\.id)
                == ["built-in", "sf", "us-ny-nyc-brooklyn"]
        )
    }

    /// An in-flight first download stays under `Available`; an in-flight *update* does not leave the
    /// top section. Both follow from asking the install state rather than the buttons.
    @Test("a download in flight keeps the section its state already earned")
    func downloadInFlightDoesNotJumpSections() {
        let city = Self.entry(version: "s17-r2026-08-22-ac7b1ccc", contentRev: "2026-08-22")

        let firstDownload = CityDownloadRow.published(
            city: city, state: .notInstalled, isActive: false,
            downloadingFraction: 0.4, lastAttemptFailed: false
        )
        #expect(!firstDownload.isOnDevice)

        let updating = CityDownloadRow.published(
            city: city, state: .updateAvailable(installedVersion: "old"), isActive: false,
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
    /// simulator, the per-byte control takes **0.280 s** and the download task **0.0059 s**, so any
    /// bound loose enough to be stable (say six seconds) sits far above *both* and would certify the
    /// defect as fixed. That is this project's signature failure — a guard that is green while the
    /// defect is present.
    ///
    /// So the test measures the defect itself, here, on whatever machine is running: it walks the
    /// same fixture with `URLSession.AsyncBytes` exactly as the old body did, and then requires the
    /// real download to beat that by 10×. Machine speed cancels, and the assertion can only pass
    /// if the two code paths are genuinely different in kind.
    ///
    /// **The margin is real but not enormous, and it is stated rather than implied.** The 10× factor
    /// is not headroom: it is spent on the comparison. From the pair above the bound is
    /// `0.0059 × 10 = 0.059 s` against a `0.280 s` control, so the slack between the committed
    /// assertion and the measurement is about **4.7×** — not the two orders of magnitude the ratio's
    /// name suggests, and worth knowing before reading a red here as a performance regression. It
    /// has not been observed to flake; the number to revisit if it ever does is this factor, not the
    /// fixture size.
    ///
    /// Byte count and sha256 are asserted alongside, because a fast download that verified nothing
    /// would satisfy a timing test perfectly.
    @Test("the transfer beats a per-byte walk of the same bytes by an order of magnitude",
          .timeLimit(.minutes(1)))
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

        let staging = dir.appendingPathComponent("staging", isDirectory: true)
        let started = Date()
        let verified = try await CityDownloader(baseURL: dir).downloadCity(city, to: staging)
        let elapsed = Date().timeIntervalSince(started)

        #expect(
            elapsed * 10 < control,
            "download took \(elapsed)s against a \(control)s per-byte control — the per-byte loop is back"
        )

        let landed = try Data(contentsOf: verified)
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
    /// **A `file://` fixture cannot guard this.** Measured: a file URL reports 0 progress callbacks
    /// through the healthy path too, so a test built on one would be green either way — the house
    /// failure mode. The bucket here is an in-process `URLProtocol` serving http in 64 KiB chunks;
    /// nothing leaves the machine.
    @Test("the download ring is told how far along the transfer is", .timeLimit(.minutes(1)))
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
        let (downloader, session) = Self.httpBucket(payload: payload, for: city)
        defer { session.finishTasksAndInvalidate() }

        let reported = FractionLog()
        let verified = try await downloader.downloadCity(
            city, to: dir.appendingPathComponent("staging", isDirectory: true),
            progress: { reported.record($0) }
        )

        let fractions = reported.all
        #expect(!fractions.isEmpty, "the ring was told \(fractions.count) times — it draws 0% throughout")
        #expect(fractions.last == 1.0, "the last report was \(String(describing: fractions.last))")
        #expect(fractions == fractions.sorted(), "progress went backwards: \(fractions)")
        // A fast download that verified nothing would satisfy the assertions above perfectly.
        #expect(try Data(contentsOf: verified).count == payload.count)
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
        let (downloader, session) = Self.httpBucket(payload: payload, for: city)
        defer { session.finishTasksAndInvalidate() }

        let staging = dir.appendingPathComponent("staging", isDirectory: true)
        await #expect(throws: CityDownloader.DownloadError.self) {
            _ = try await downloader.downloadCity(city, to: staging)
        }
        #expect(
            (try? FileManager.default.contentsOfDirectory(atPath: staging.path))?.isEmpty == true
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

    /// **Cancel on the running screen leaves no failure line.** Driven through the model, over a
    /// transport that stays open until it is cancelled, so the error really is the one URLSession
    /// produces rather than one the test constructed.
    /// What a cancelled transfer actually throws out of `downloadCity`, measured rather than
    /// assumed — the fixture reports `.networkConnectionLost` when the loader is stopped, so a
    /// `.cancelled` here is URLSession's own translation of the cancelled task state.
    @Test("a cancelled transfer surfaces as a cancellation, not as a transport failure",
          .timeLimit(.minutes(1)))
    func cancelledTransferSurfacesAsCancellation() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cities-cancel-raw-\(UUID().uuidString)", isDirectory: true)
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
        let (downloader, session) = Self.httpBucket(payload: payload, for: city, stalls: true)
        defer { session.finishTasksAndInvalidate() }

        let staging = dir.appendingPathComponent("staging", isDirectory: true)
        let transfer = Task { try await downloader.downloadCity(city, to: staging) }
        try await Task.sleep(nanoseconds: 100_000_000)
        transfer.cancel()

        do {
            _ = try await transfer.value
            Issue.record("a cancelled transfer returned a file")
        } catch {
            #expect(
                CityDownloader.isCancellation(error),
                "a cancelled download threw \(error), which the screen reads as a failure"
            )
        }
    }

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
        let (downloader, session) = Self.httpBucket(payload: payload, for: city, stalls: true)
        defer { session.finishTasksAndInvalidate() }

        let model = CityDownloadsModel(
            library: CityLibrary(rootURL: dir.appendingPathComponent("lib", isDirectory: true)),
            downloader: downloader,
            bundledCities: [],
            onInventoryChange: {}
        )
        model.download(city)
        #expect(model.downloading?.id == city.id, "the download never started, so nothing was cancelled")

        model.cancelDownload()
        // A bounded foreground wait, and `break` rather than a `where` clause: `for … where` filters
        // iterations, it does not stop the loop, so a settled download would still have been slept
        // over 250 times.
        for _ in 0..<250 {
            if model.downloading == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(model.downloading == nil, "the download never settled after Cancel")
        #expect(
            model.failedCityID == nil,
            "Cancel drew R43 §3's failure line — failedCityID is \(String(describing: model.failedCityID))"
        )
    }
}

/// A thread-safe list of the fractions the progress ring was told, because the delegate reports
/// from URLSession's own queue.
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

/// An in-process http bucket: the one transport that can observe download progress.
///
/// **A `file://` fixture reports zero `didWriteData` callbacks even through a healthy
/// implementation** (measured on iPhone 16 Pro), so the suite's existing file fixtures cannot guard
/// the Cities screen's progress ring — they are green either way. This serves a parked body over
/// `https` in 64 KiB chunks, entirely inside the process; nothing leaves the machine and no port is
/// opened.
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
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var objects: [String: Object] = [:]

    static func park(_ url: URL, body: Data, stalls: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if objects[url.absoluteString] != nil {
            Issue.record("\(url.absoluteString) was already parked; give this fixture its own UUID.")
        }
        objects[url.absoluteString] = Object(body: body, stalls: stalls)
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
