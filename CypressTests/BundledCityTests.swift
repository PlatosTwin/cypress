import Foundation
import Testing
@testable import Cypress

/// Stage 0 of the 2026-08-14 city-data-distribution design: **the app reads its own bundle.**
///
/// The defect these tests exist for is the owner's own report — the Cities screen offered an 81 MB
/// download of San Francisco while San Francisco's trees were on the map. Nothing in the app asked
/// the bundled seed which cities it held, so `CityInstallState` resolved `.notInstalled` from
/// `CityLibrary`'s downloaded-only record and `CityDownloadsPresentation` drew a `Download` button.
///
/// Three things are guarded here, in order: that the bundle can be read at all, that a bundled city
/// is never offered for download, and that a city can never occupy two rows.
@Suite("Bundle truth · the app reads its own bundle")
struct BundledCityTests {

    // MARK: - Harness

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundled-city-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A manifest entry for one city, with the record date the publisher would have stamped.
    static func entry(
        id: String,
        displayName: String,
        contentRev: String?,
        schemaVersion: Int = 16,
        coverage: String = "full"
    ) -> CityManifest.City {
        let version = "s\(schemaVersion)-r\(contentRev ?? "none")-c9a440b2"
        return CityManifest.City(
            id: id, displayName: displayName, coverage: coverage, treeCount: 1,
            schemaVersion: schemaVersion, version: version, contentRev: contentRev,
            path: "cities/\(id)/\(version)/\(id).sqlite", bytes: 80_855_040, sha256: "ab"
        )
    }

    // MARK: - Reading the bundle

    /// The shipped seed names its own cities, and the record date the app derives for each one is
    /// the publisher's own `content_rev_for` answer.
    ///
    /// **The literals are the shipped seed's build receipt, not a preference.** They come from
    /// `seed_meta` (`inventory_sf_city_snapshot_on` 2026-07-31, `inventory_sf_datasf_snapshot_on`
    /// 2026-07-20, `inventory_sj_street_tree_snapshot_on` 2026-07-31) and from `dim_city`, and they
    /// are exactly the `r2026-07-31` in both published version strings. A seed rebuild that moves a
    /// snapshot date moves this assertion with it; that is the assertion doing its job.
    @Test("the shipped bundle names its cities and dates them by the publisher's rule")
    func bundledSeedNamesItsCities() throws {
        let url = try #require(Self.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let cities = SeedCities.read(fileAt: url)

        #expect(cities.map(\.id) == ["sf", "us-ca-sj"])
        #expect(cities.map(\.displayName) == ["San Francisco", "San Jose"])
        #expect(
            cities.map(\.contentRev) == ["2026-07-31", "2026-07-31"],
            """
            the bundle's derived record dates are \(cities.map(\.contentRev)); the publisher's rule \
            over this seed's seed_meta says 2026-07-31 for both spaces, which is the r-segment of \
            both published version strings
            """
        )
    }

    /// The rule itself, on a receipt built for the purpose: the newest snapshot among **this
    /// space's** inventories, paired by tag, ignoring every other space's dates.
    @Test("content_rev is the newest snapshot of the city's own inventories")
    func contentRevIsTheNewestOfItsOwnInventories() {
        let meta = [
            "inventory_a_city_id_space": "sf",
            "inventory_a_city_snapshot_on": "2026-07-31",
            "inventory_b_export_id_space": "sf",
            "inventory_b_export_snapshot_on": "2026-07-20",
            "inventory_c_other_id_space": "us-ca-sj",
            "inventory_c_other_snapshot_on": "2026-12-31",
            // A tag with no snapshot date contributes nothing rather than crashing the rule.
            "inventory_d_dateless_id_space": "sf",
            "trees_snapshot_on": "2099-01-01"
        ]

        #expect(SeedCities.contentRev(forIDSpace: "sf", seedMeta: meta) == "2026-07-31")
        #expect(SeedCities.contentRev(forIDSpace: "us-ca-sj", seedMeta: meta) == "2026-12-31")
        #expect(SeedCities.contentRev(forIDSpace: "nowhere", seedMeta: meta) == nil)
    }

    // MARK: - The defect

    /// **The regression test for the owner's report.** At `origin/main` this assertion reads
    /// `81 MB` and `[.download]`, because nothing asked the bundle what it held.
    @Test("a bundled city at the published record date is not offered for download")
    func bundledCityIsNotOfferedForDownload() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        let state = CityInstallState(
            published: sf, installedVersion: nil, bundledContentRev: "2026-07-31",
            newestKnownSchemaVersion: 16
        )

        #expect(state == .bundled(contentRev: "2026-07-31"))
        #expect(!state.allowsDownload)

        let row = CityDownloadRow.published(
            city: sf, state: state, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(
            row.affordances.isEmpty,
            "the screen offers \(row.affordances) for a city that ships inside the app"
        )
        #expect(row.stateLine == "Included in the app · record as of 2026-07-31")
        #expect(row.title == "San Francisco")
    }

    /// A published record that is genuinely newer buys something, so the button is honest again —
    /// and the row says which copy the reader is holding.
    @Test("a newer published record restores the download, and says what is held")
    func newerPublishedRecordRestoresTheDownload() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-08-20")
        let state = CityInstallState(
            published: sf, installedVersion: nil, bundledContentRev: "2026-07-31",
            newestKnownSchemaVersion: 16
        )

        #expect(state == .bundledOutdated(bundledContentRev: "2026-07-31"))
        #expect(state.allowsDownload)

        let row = CityDownloadRow.published(
            city: sf, state: state, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(row.affordances == [.download])
        #expect(row.stateLine == "Newer record available · included copy is 2026-07-31")
    }

    /// The three ways "you already have this" is reached, each landing on `.bundled`: parity, a
    /// published record that is *older* (a publish skipped after a bundle build), and a manifest
    /// entry with no `content_rev` at all — where the safe direction is to withhold a download
    /// rather than offer 81 MB of bytes the device may already hold.
    @Test("older, equal and unknown published revisions all resolve to bundled")
    func staleOrUnknownPublishedRevisionsStayBundled() {
        let publishedRevisions: [String?] = ["2026-07-31", "2026-06-01", nil]
        for publishedRev in publishedRevisions {
            let city = Self.entry(id: "sf", displayName: "San Francisco", contentRev: publishedRev)
            let state = CityInstallState(
                published: city, installedVersion: nil, bundledContentRev: "2026-07-31",
                newestKnownSchemaVersion: 16
            )
            #expect(
                state == .bundled(contentRev: "2026-07-31"),
                "published content_rev \(publishedRev ?? "absent") resolved \(state)"
            )
        }
    }

    /// A downloaded copy shadows the bundled one (the `active-city` marker points at it), so the
    /// row describes the copy that is actually attachable — not the bundle.
    @Test("a downloaded copy still wins over the bundled one")
    func downloadedCopyShadowsTheBundle() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-08-20")
        let state = CityInstallState(
            published: sf, installedVersion: sf.version, bundledContentRev: "2026-07-31",
            newestKnownSchemaVersion: 16
        )
        #expect(state == .installedCurrent(installedVersion: sf.version))
    }

    /// The schema gate still refuses the download; what changed is what the row says when there is
    /// nothing to refuse. A bundled city with no downloaded copy is on the reader's phone, and
    /// "Needs a newer app" for a city they are looking at is the falsehood this round removes.
    /// Neither branch draws a button.
    @Test("a future schema generation is still refused, bundled or not")
    func futureSchemaIsRefusedBothWays() {
        let future = Self.entry(
            id: "sf", displayName: "San Francisco", contentRev: "2026-08-20", schemaVersion: 99
        )

        let bundled = CityInstallState(
            published: future, installedVersion: nil, bundledContentRev: "2026-07-31",
            newestKnownSchemaVersion: 16
        )
        #expect(bundled == .bundled(contentRev: "2026-07-31"))
        #expect(!bundled.allowsDownload)

        let notBundled = CityInstallState(
            published: future, installedVersion: nil, bundledContentRev: nil,
            newestKnownSchemaVersion: 16
        )
        #expect(notBundled == .needsNewerApp(installedVersion: nil))
        #expect(!notBundled.allowsDownload)
    }

    // MARK: - One rule, one row

    /// **`allowsDownload` is the only statement of "may this be fetched", and every row obeys it.**
    /// The row draws its button from it and `CityDownloadsModel.download` refuses on it, so the
    /// button and the transfer cannot drift apart. Exhaustive over the enum: a new case that
    /// forgets to answer this question fails to compile in `allowsDownload` and fails here.
    @Test("every install state's affordances agree with allowsDownload")
    func everyStateAgreesWithAllowsDownload() {
        let city = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        let states: [CityInstallState] = [
            .notInstalled,
            .installedCurrent(installedVersion: city.version),
            .updateAvailable(installedVersion: "s16-r2026-06-01-c9a440b2"),
            .needsNewerApp(installedVersion: nil),
            .needsNewerApp(installedVersion: "s16-r2026-06-01-c9a440b2"),
            .bundled(contentRev: "2026-07-31"),
            .bundledOutdated(bundledContentRev: "2026-07-31")
        ]

        for state in states {
            for isActive in [false, true] {
                let row = CityDownloadRow.published(
                    city: city, state: state, isActive: isActive,
                    downloadingFraction: nil, lastAttemptFailed: false
                )
                let fetches = row.affordances.contains(.download)
                    || row.affordances.contains(.update)
                #expect(
                    fetches == state.allowsDownload,
                    "\(state) draws \(row.affordances) but allowsDownload is \(state.allowsDownload)"
                )
            }
        }
    }

    /// The second consequence in the design's §3.2, which needed a reader to press the button:
    /// downloading a city the bundle already holds leaves two rows for San Francisco and a `Use`
    /// that switches between two indistinguishable copies. The ids are folded to a unique sequence
    /// before any row is made, so **no arrangement of catalog, library and bundle produces two rows
    /// for one city** — including the one where all three name it.
    @MainActor
    @Test("no arrangement of catalog, library and bundle draws a city twice")
    func aCityCanNeverOccupyTwoRows() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")

        // A city file on disk, installed at the published version — the state that used to produce
        // `Built-in inventory` plus a second San Francisco.
        let file = dir.appendingPathComponent("sf.sqlite")
        try CityDownloadTests.miniSeed(at: file, publishSchemaVersion: 16)
        try library.install(verifiedFileAt: file, id: "sf", version: sf.version)

        let manifestURL = dir.appendingPathComponent("manifest.json")
        try Data(Self.manifestJSON(sf).utf8).write(to: manifestURL)

        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(baseURL: dir),
            bundledCities: [
                SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"),
                SeedCities.City(id: "us-ca-sj", displayName: "San Jose", contentRev: "2026-07-31")
            ],
            onInventoryChange: {}
        )

        // Offline first: the catalog has never loaded, and disk plus bundle both name `sf`.
        var ids = model.rows.map(\.id)
        #expect(Set(ids).count == ids.count, "offline rows repeat a city: \(ids)")
        #expect(ids == [CityDownloadRow.builtInID, "sf", "us-ca-sj"])
        // San Jose is bundled and not downloaded: the offline screen says so without a network.
        #expect(model.rows[2].stateLine == "Included in the app · record as of 2026-07-31")

        // Then loaded, where the catalog names `sf` as well — three sources, one row.
        await model.load()
        ids = model.rows.map(\.id)
        #expect(Set(ids).count == ids.count, "loaded rows repeat a city: \(ids)")
        #expect(ids == [CityDownloadRow.builtInID, "sf", "us-ca-sj"])
    }

    /// The download action refuses a bundled-current city outright, not merely by declining to draw
    /// a button. A stale view, a future affordance or a test cannot start the transfer.
    @MainActor
    @Test("download() refuses a city the bundle already holds")
    func downloadRefusesABundledCity() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")

        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(baseURL: dir),
            bundledCities: [
                SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
            ],
            onInventoryChange: {}
        )

        model.download(sf)
        #expect(model.downloading == nil, "a download started for a city that ships in the app")

        // The control: the same call for a city the bundle does not hold does start one.
        let elsewhere = Self.entry(id: "us-ny-nyc", displayName: "New York", contentRev: "2026-08-20")
        model.download(elsewhere)
        #expect(model.downloading?.id == "us-ny-nyc")
        model.cancelDownload()
    }

    // MARK: - Names the disk already knows (§3.4)

    /// An offline row used to be titled `us-ca-sj`. Since s16 the installed file itself carries
    /// `dim_city.display_name`, so the disk does know the name — and the id survives as the
    /// fallback for a file too old to carry one, never a prettier name this layer made up.
    @Test("an offline row takes its title from the file, falling back to the id")
    func offlineRowsAreNamedByTheirFile() {
        let named = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "us-ca-sj", version: "s16-r2026-07-31-c9a440b2",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1, displayName: "San Jose"
            ),
            isActive: false
        )
        #expect(named.title == "San Jose")
        #expect(named.affordances == [.use, .remove])

        let unnamed = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "us-ca-sj", version: "s14-r2026-01-01",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1, displayName: nil
            ),
            isActive: false
        )
        #expect(unnamed.title == "us-ca-sj")
    }

    /// The library reads the name out of the file it installed, so the offline screen never has to
    /// reach the manifest for it.
    @Test("the library reads an installed city's name from the installed file")
    func libraryReadsTheInstalledName() throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let file = dir.appendingPathComponent("sj.sqlite")
        try CityDownloadTests.miniSeed(at: file, publishSchemaVersion: 16)
        // The city dimension exactly as `publish_cities.py` narrows it into a city file. Scoped so
        // the handle is closed before the file is renamed into the library.
        do {
            let connection = try SQLiteConnection(path: file.path)
            try connection.execute("""
                CREATE TABLE dim_city (id INTEGER PRIMARY KEY, display_name TEXT);
                INSERT INTO dim_city (id, display_name) VALUES (2, 'San Jose');
                CREATE TABLE id_spaces (id TEXT PRIMARY KEY, city_id INTEGER);
                INSERT INTO id_spaces (id, city_id) VALUES ('us-ca-sj', 2);
                """)
        }

        try library.install(verifiedFileAt: file, id: "us-ca-sj", version: "s16-r2026-07-31-c9a440b2")
        #expect(library.installedCities().map(\.displayName) == ["San Jose"])
    }

    // MARK: - The manifest keys that were always there (E209 B3 / E213 / E214)

    /// `publish_cities.py` has emitted `content_rev`, `bbox` and `centroid` for every city since
    /// #156, and all three are in the live manifest. Three errata entries record the opposite as a
    /// blocker; the blocker was two `Decodable` properties, and a third this round needed anyway.
    @Test("the manifest's content_rev, bbox and centroid decode")
    func additiveManifestKeysDecode() throws {
        let manifest = try CityManifest.decode(Data(CityDownloadTests.manifestJSON.utf8))
        let sf = manifest.cities[0]

        #expect(sf.contentRev == "2026-07-31")
        #expect(sf.bbox?.minLatitude == 37.7)
        #expect(sf.bbox?.maxLongitude == -122.3)
        #expect(sf.centroid == Coordinate(latitude: 37.76, longitude: -122.43))
    }

    /// R37.4's tolerance for additive keys cuts both ways: a manifest that predates them still
    /// decodes rather than taking the whole screen offline.
    @Test("a manifest without the additive keys still decodes")
    func manifestWithoutAdditiveKeysDecodes() throws {
        let json = """
        {
          "manifest_format": 1,
          "cities": [
            {"id": "sf", "display_name": "San Francisco", "coverage": "full", "tree_count": 1,
             "schema_version": 16, "version": "s16-r2026-07-31-c9a440b2",
             "path": "cities/sf/x/sf.sqlite", "bytes": 1, "sha256": "ab"}
          ]
        }
        """
        let manifest = try CityManifest.decode(Data(json.utf8))
        #expect(manifest.cities[0].contentRev == nil)
        #expect(manifest.cities[0].bbox == nil)
        #expect(manifest.cities[0].centroid == nil)
    }

    // MARK: - Fixtures

    private static func manifestJSON(_ city: CityManifest.City) -> String {
        """
        {
          "manifest_format": 1,
          "cities": [
            {"id": "\(city.id)", "display_name": "\(city.displayName)", "coverage": "full",
             "tree_count": \(city.treeCount), "schema_version": \(city.schemaVersion),
             "content_rev": "\(city.contentRev ?? "")", "version": "\(city.version)",
             "path": "\(city.path)", "bytes": \(city.bytes), "sha256": "\(city.sha256)"}
          ]
        }
        """
    }
}
