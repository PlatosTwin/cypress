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
/// Four things are guarded here, in order: that the bundle can be read at all, that a bundled city
/// is never offered for download **whether or not its record date derives**, that the three sources
/// keep one precedence and one row per city, and that what a row says comes out of a file.
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

    /// A seed-shaped file carrying one id space, its city dimension, and a build receipt — the
    /// shape `publish_cities.py` narrows a city file to, and the shape `build_seed.py` writes.
    ///
    /// `snapshotOn: ""` is not a contrivance: `build_seed.py` writes San Jose's date as
    /// `sj_meta.get("extracted_on", "")`, with no `die()` behind it.
    static func cityFile(
        at url: URL,
        idSpace: String,
        displayName: String,
        snapshotOn: String,
        shipExtentKey: String? = nil,
        shipExtent: String? = nil
    ) throws {
        try CityDownloadTests.miniSeed(at: url, publishSchemaVersion: 16)
        let connection = try SQLiteConnection(path: url.path)
        try connection.execute("""
            CREATE TABLE dim_city (id INTEGER PRIMARY KEY, display_name TEXT);
            INSERT INTO dim_city (id, display_name) VALUES (1, '\(displayName)');
            CREATE TABLE id_spaces (id TEXT PRIMARY KEY, city_id INTEGER);
            INSERT INTO id_spaces (id, city_id) VALUES ('\(idSpace)', 1);
            INSERT INTO seed_meta (key, value)
                VALUES ('inventory_probe_id_space', '\(idSpace)'),
                       ('inventory_probe_snapshot_on', '\(snapshotOn)');
            """)
        if let shipExtentKey, let shipExtent {
            try connection.execute(
                "INSERT INTO seed_meta (key, value) VALUES ('\(shipExtentKey)', '\(shipExtent)');"
            )
        }
    }

    // MARK: - Reading the bundle

    /// The shipped seed names its own cities, dates them by the publisher's rule, and states the
    /// coverage word the manifest gets from the same keys.
    ///
    /// **The expected cities are the seed's build receipt, not a preference**, and they are keyed by
    /// corpus in `SeedCorpus.bundledCities` rather than written out here. They are derived from
    /// `seed_meta` (each space's `inventory_*_snapshot_on` keys and its `coverage_<space>` key) and
    /// from `dim_city`, and each date is exactly the `r`-segment of that city's published version
    /// string. A seed rebuild that moves a snapshot date moves this assertion with it; that is the
    /// assertion doing its job — and it did it on seed `4f6ebaaa`, where all three dates moved to
    /// 2026-08-22 and `sf`'s coverage moved from `nil` to `full`, the latter because that publish is
    /// the first to write a `coverage_sf` key at all.
    ///
    /// **Why keyed and not hardcoded.** These four arrays were hardcoded, and that made this the one
    /// assertion in the file that a *correct* seed could fail: `--sj-extent none` and `--sj-extent
    /// downtown` without `--nyc-cache` are both supported, documented builds, and both produce a
    /// bundle this test called wrong. The corpus entry is what lets each build be judged against its
    /// own receipt — the same doctrine that keeps `cityWithSanJose`'s counts alive beside the
    /// three-city corpus. `nil` for a corpus nobody has measured, which skips rather than invents.
    @Test("the shipped bundle names its cities, dates them, and states their coverage")
    func bundledSeedNamesItsCities() async throws {
        let url = try #require(Self.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let cities = SeedCities.read(fileAt: url)
        let store = try await CypressStore.inMemory(seedURL: url)
        let corpus = try await SeedCorpus.current(store)

        guard let expected = corpus.bundledCities else { return }
        // Ordered by `id_spaces.id`, which is what `SeedCities.read` sorts on.
        #expect(
            cities == expected,
            """
            the bundle names \(cities.map(\.id)) with display names \(cities.map(\.displayName)), \
            record dates \(cities.map(\.contentRev)) and coverage \(cities.map(\.coverage)); the \
            \(corpus.source) corpus is pinned at \(expected.map(\.id)), \
            \(expected.map(\.displayName)), \(expected.map(\.contentRev)) and \
            \(expected.map(\.coverage))
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

    /// The coverage rule: the standardized key R37 plans, then the publisher's per-city shim, then
    /// full coverage. Preferring the standardized key is what makes the shim dead rather than wrong
    /// on the day `build_seed.py` starts writing `coverage_<id_space>`.
    @Test("coverage prefers the standardized key, falls back to the publisher's shim")
    func coverageReadsBothKeysInTheRightOrder() {
        #expect(SeedCities.coverage(forIDSpace: "sf", seedMeta: [:]) == nil)
        #expect(
            SeedCities.coverage(
                forIDSpace: "us-ca-sj", seedMeta: ["sj_ship_extent": "downtown"]
            ) == "downtown"
        )
        #expect(
            SeedCities.coverage(
                forIDSpace: "us-ca-sj",
                seedMeta: ["sj_ship_extent": "downtown", "coverage_us-ca-sj": "citywide"]
            ) == "citywide",
            "the standardized key must win, or the shim outlives its own retirement"
        )
        // An empty value is absence, the same reading `contentRev` gives an empty snapshot date.
        #expect(SeedCities.coverage(forIDSpace: "us-ca-sj", seedMeta: ["sj_ship_extent": ""]) == nil)
    }

    /// **The shim is a hand-entered table duplicated across two languages, so it is read out of the
    /// publisher rather than remembered.** A city added to `publish_cities.py`'s `COVERAGE_KEYS` and
    /// not to `SeedCities.legacyCoverageKeys` would make that city's bundled row silently claim full
    /// coverage; this is what says so instead.
    @Test("every COVERAGE_KEYS entry in the publisher is mirrored in the app")
    func everyPublisherCoverageKeyIsMirrored() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Tools/publish_cities.py"), encoding: .utf8
        )
        let opening = try #require(
            source.range(of: "COVERAGE_KEYS = {"),
            "publish_cities.py no longer declares COVERAGE_KEYS — this guard is reading nothing"
        )
        let closing = try #require(source.range(of: "}", range: opening.upperBound..<source.endIndex))
        let block = String(source[opening.upperBound..<closing.lowerBound])

        let pattern = try NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:\\s*\"([^\"]+)\"")
        var fromPublisher: [String: String] = [:]
        for match in pattern.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
            guard let key = Range(match.range(at: 1), in: block),
                  let value = Range(match.range(at: 2), in: block) else { continue }
            fromPublisher[String(block[key])] = String(block[value])
        }

        // Calibration: the parse must find the entry that is known to be in that file, or an empty
        // dictionary would equal an empty mirror and this test would pass by reading nothing.
        #expect(
            fromPublisher["us-ca-sj"] == "sj_ship_extent",
            """
            the COVERAGE_KEYS parse found \(fromPublisher), which does not include the entry known \
            to be in that file — this guard is measuring the wrong thing
            """
        )
        #expect(
            fromPublisher == SeedCities.legacyCoverageKeys,
            """
            publish_cities.py's COVERAGE_KEYS is \(fromPublisher) and SeedCities mirrors \
            \(SeedCities.legacyCoverageKeys); a city in one and not the other draws the wrong \
            coverage on its bundled row
            """
        )
    }

    // MARK: - The defect

    /// **The regression test for the owner's report.** At `origin/main` this assertion reads
    /// `81 MB` and `[.download]`, because nothing asked the bundle what it held.
    @Test("a bundled city at the published record date is not offered for download")
    func bundledCityIsNotOfferedForDownload() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        let state = CityInstallState(
            published: sf, installedVersion: nil,
            bundled: SeedCities.City(
                id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
            ),
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

    /// **A bundled city with no derivable record date is still bundled.** This is the shape that
    /// re-opened the defect: `contentRev` was non-optional on `.bundled`, so the caller's `nil` had
    /// to mean both "not in the bundle" and "in the bundle, dateless", and the second fell through
    /// to `.notInstalled` — `81 MB`, a `Download` button, and a transfer that started.
    ///
    /// Reachable: `build_seed.py` writes San Jose's snapshot date as `.get("extracted_on", "")`.
    /// The first half of this test proves the file really does produce a nil rev; the rest proves a
    /// nil rev never reaches a download.
    @MainActor
    @Test("a bundled city with no derivable record date is still bundled, on every path")
    func aDatelessBundledCityIsStillBundled() async throws {
        let dir = try Self.tempDir()

        // The file, exactly as build_seed.py's empty-string default would leave it.
        let file = dir.appendingPathComponent("dateless.sqlite")
        try Self.cityFile(
            at: file, idSpace: "us-ca-sj", displayName: "San Jose", snapshotOn: "",
            shipExtentKey: "sj_ship_extent", shipExtent: "downtown"
        )
        let read = SeedCities.read(fileAt: file)
        #expect(read.map(\.id) == ["us-ca-sj"])
        let dateless = try #require(read.first)
        #expect(dateless.contentRev == nil, "an empty snapshot date must not become a record date")
        #expect(dateless.displayName == "San Jose")
        #expect(dateless.coverage == "downtown")

        // The state: bundled, dateless, and refusing the download.
        let published = Self.entry(
            id: "us-ca-sj", displayName: "San Jose", contentRev: "2026-08-20", coverage: "downtown"
        )
        let state = CityInstallState(
            published: published, installedVersion: nil, bundled: dateless,
            newestKnownSchemaVersion: 16
        )
        #expect(state == .bundled(contentRev: nil))
        #expect(
            !state.allowsDownload,
            "a city in the bundle became downloadable because its record date did not derive"
        )

        // The row: D5's line without the clause the file cannot support, and no borrowed copy.
        let row = CityDownloadRow.published(
            city: published, state: state, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(row.affordances.isEmpty)
        #expect(row.stateLine == "Included in the app")
        #expect(row.stateLine != CityDownloadsCopy.builtInSubtitle)
        #expect(row.coverageNote == "Covers downtown only")

        // And the model: the two paths agree, and `download()` refuses.
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        try Data(Self.manifestJSON([published]).utf8)
            .write(to: dir.appendingPathComponent("manifest.json"))
        let model = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: [dateless], onInventoryChange: {}
        )

        #expect(model.rows.map(\.affordances) == [[.inUseLabel], []], "offline: \(model.rows)")
        await model.load()
        #expect(model.rows.map(\.affordances) == [[.inUseLabel], []], "loaded: \(model.rows)")
        model.download(published)
        #expect(
            model.downloading == nil,
            "download() started for a dateless city that ships inside the app"
        )
    }

    /// A published record that is genuinely newer buys something, so the button is honest again —
    /// and the row says which copy the reader is holding.
    @Test("a newer published record restores the download, and says what is held")
    func newerPublishedRecordRestoresTheDownload() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-08-20")
        let state = CityInstallState(
            published: sf, installedVersion: nil,
            bundled: SeedCities.City(
                id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
            ),
            newestKnownSchemaVersion: 16
        )

        #expect(state == .bundledOutdated(bundledContentRev: "2026-07-31"))
        #expect(state.allowsDownload)

        let row = CityDownloadRow.published(
            city: sf, state: state, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(row.affordances == [.download])
        // Both facts, possession first. The offer used to be this row's only line, which read as
        // the screen offering to sell a reader a city already inside the app they were holding —
        // filed as exactly that by a tester on build 49 (`CityDownloadsFeedbackTests`).
        #expect(row.stateLine == "Included in the app · record as of 2026-07-31")
        #expect(row.detailLine == "A newer record is available to download.")
        #expect(row.isOnDevice)
    }

    /// The ways "you already have this" is reached, each landing on `.bundled`: parity, a published
    /// record that is *older* (a publish skipped after a bundle build), a manifest entry with no
    /// `content_rev` at all, and a bundled city with no date of its own. In every one the safe
    /// direction is to withhold a download rather than offer 81 MB of bytes already held.
    @Test("older, equal, unknown and dateless revisions all resolve to bundled")
    func staleOrUnknownPublishedRevisionsStayBundled() {
        let publishedRevisions: [String?] = ["2026-07-31", "2026-06-01", nil]
        for publishedRev in publishedRevisions {
            let city = Self.entry(id: "sf", displayName: "San Francisco", contentRev: publishedRev)
            let state = CityInstallState(
                published: city, installedVersion: nil,
                bundled: SeedCities.City(
                    id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
                ),
                newestKnownSchemaVersion: 16
            )
            #expect(
                state == .bundled(contentRev: "2026-07-31"),
                "published content_rev \(publishedRev ?? "absent") resolved \(state)"
            )
        }

        // Bundled but dateless, against the newest published record there could be.
        let newest = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2099-01-01")
        let dateless = CityInstallState(
            published: newest, installedVersion: nil,
            bundled: SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: nil),
            newestKnownSchemaVersion: 16
        )
        #expect(dateless == .bundled(contentRev: nil))
        #expect(!dateless.allowsDownload)
    }

    /// A downloaded copy shadows the bundled one (the `active-city` marker points at it), so the
    /// row describes the copy that is actually attachable — not the bundle.
    @Test("a downloaded copy still wins over the bundled one")
    func downloadedCopyShadowsTheBundle() {
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-08-20")
        let state = CityInstallState(
            published: sf, installedVersion: sf.version,
            bundled: SeedCities.City(
                id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
            ),
            newestKnownSchemaVersion: 16
        )
        #expect(state == .installedCurrent(installedVersion: sf.version))
    }

    /// The schema gate still refuses the download; what changed is what the row says when there is
    /// nothing to refuse. A bundled city with no downloaded copy is on the reader's phone, and
    /// "Needs a newer app" for a city they are looking at is the falsehood this round removes.
    ///
    /// **Ruled by the owner, 2026-08-14** (review finding 8): when the published entry is *both* a
    /// newer generation and a newer record, this row keeps `Included in the app` and states neither
    /// the format refusal nor the newer record. Pinned here so the ruling is a test, not a memory.
    @Test("a future schema generation is still refused, bundled or not")
    func futureSchemaIsRefusedBothWays() {
        let future = Self.entry(
            id: "sf", displayName: "San Francisco", contentRev: "2026-09-01", schemaVersion: 99
        )
        let inBundle = SeedCities.City(
            id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
        )

        let bundled = CityInstallState(
            published: future, installedVersion: nil, bundled: inBundle,
            newestKnownSchemaVersion: 16
        )
        #expect(bundled == .bundled(contentRev: "2026-07-31"))
        #expect(!bundled.allowsDownload)

        // The owner's ruling, drawn: the record date the reader holds, no format detail, no
        // newer-record claim, and no button.
        let row = CityDownloadRow.published(
            city: future, state: bundled, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(row.stateLine == "Included in the app · record as of 2026-07-31")
        #expect(row.detailLine == nil)
        #expect(row.affordances.isEmpty)

        let notBundled = CityInstallState(
            published: future, installedVersion: nil, bundled: nil,
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
            .bundled(contentRev: nil),
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
    ///
    /// **The offline half only means something once `installed` is populated**, which happens in
    /// `load()` and nowhere else. An earlier version of this test read `model.rows` before any load,
    /// where `installed` is empty and the fold has nothing to drop: removing the deduplication left
    /// those two assertions green — the guard-green-when-the-defect-is-present shape, on the very
    /// path the fold exists for. So the catalog is made unreachable and `load()` is awaited: the
    /// disk facts land, the catalog does not, and the offline branch is exercised for real.
    ///
    /// It also pins the owner's ruling of **2026-08-14** (review finding 9): the offline screen
    /// shows the same cities as the online one — all three cards — rather than dropping the bundled
    /// rows when the network goes away.
    @MainActor
    @Test("no arrangement of catalog, library and bundle draws a city twice")
    func aCityCanNeverOccupyTwoRows() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        let bundled = [
            SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"),
            SeedCities.City(
                id: "us-ca-sj", displayName: "San Jose", contentRev: "2026-07-31",
                coverage: "downtown"
            )
        ]

        // A city file on disk, installed at the published version — the state that used to produce
        // `Built-in inventory` plus a second San Francisco.
        let file = dir.appendingPathComponent("sf.sqlite")
        try Self.cityFile(
            at: file, idSpace: "sf", displayName: "San Francisco", snapshotOn: "2026-07-31"
        )
        try library.install(verifiedFileAt: file, id: "sf", version: sf.version)

        // Offline, for real: no manifest.json at the base URL, so `load()` populates the disk facts
        // and then fails the fetch. Disk and bundle both name `sf` at this point.
        let offlineModel = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: bundled, onInventoryChange: {}
        )
        await offlineModel.load()
        #expect(
            offlineModel.catalog == .unavailable,
            "the catalog loaded, so this is not the offline path and the test proves nothing"
        )
        #expect(offlineModel.installed.map(\.id) == ["sf"], "the disk facts never landed")

        var ids = offlineModel.rows.map(\.id)
        #expect(Set(ids).count == ids.count, "offline rows repeat a city: \(ids)")
        #expect(ids == [CityDownloadRow.builtInID, "sf", "us-ca-sj"])
        // The owner's 2026-08-14 ruling: all three cards offline, the same cities as online.
        #expect(offlineModel.rows.count == 3)
        // Looked up by id, never by position: a break that drops a row should read as a missing
        // row, not as an index crash that takes the rest of the suite's output with it.
        let offlineSF = try #require(offlineModel.rows.first { $0.id == "sf" })
        let offlineSJ = try #require(offlineModel.rows.first { $0.id == "us-ca-sj" })
        // `sf` is the downloaded copy, not the bundled one — it is the copy that can be attached.
        #expect(offlineSF.stateLine == "Installed · \(sf.version)")
        #expect(offlineSJ.stateLine == "Included in the app · record as of 2026-07-31")
        #expect(offlineSJ.coverageNote == "Covers downtown only")

        // Then loaded, where the catalog names `sf` as well — three sources, one row.
        try Data(Self.manifestJSON([sf]).utf8).write(to: dir.appendingPathComponent("manifest.json"))
        let loadedModel = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: bundled, onInventoryChange: {}
        )
        await loadedModel.load()
        #expect(loadedModel.catalog != .unavailable, "the catalog never loaded")
        ids = loadedModel.rows.map(\.id)
        #expect(Set(ids).count == ids.count, "loaded rows repeat a city: \(ids)")
        #expect(ids == [CityDownloadRow.builtInID, "sf", "us-ca-sj"])
    }

    /// **A downloaded, attached city the catalog no longer lists keeps its affordances.** The loaded
    /// branch used to go catalog → bundle with the library left out, so this row described the
    /// *bundled* copy: `In use` and `Remove` disappeared from an 81 MB file that was attached at
    /// that moment, and `Built-in inventory` drew `Use` while something else was in use.
    ///
    /// The two paths must agree here, which is the whole reason they now share `diskRow(for:)`.
    @MainActor
    @Test("a delisted but installed city keeps In use and Remove, on both paths")
    func aDelistedInstalledCityKeepsItsAffordances() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let version = "s16-r2026-07-31-c9a440b2"
        let bundled = [
            SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"),
            SeedCities.City(
                id: "us-ca-sj", displayName: "San Jose", contentRev: "2026-07-31",
                coverage: "downtown"
            )
        ]

        let file = dir.appendingPathComponent("sj.sqlite")
        try Self.cityFile(
            at: file, idSpace: "us-ca-sj", displayName: "San Jose", snapshotOn: "2026-07-31",
            shipExtentKey: "sj_ship_extent", shipExtent: "downtown"
        )
        try library.install(verifiedFileAt: file, id: "us-ca-sj", version: version)
        try library.activate(id: "us-ca-sj")

        // A catalog listing only San Francisco — `us-ca-sj` delisted, or published later.
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        try Data(Self.manifestJSON([sf]).utf8).write(to: dir.appendingPathComponent("manifest.json"))

        let model = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: bundled, onInventoryChange: {}
        )
        await model.load()
        #expect(
            model.catalog != .unavailable,
            "the catalog never loaded, so this is the offline path and proves the wrong branch"
        )
        #expect(model.activeCityID == "us-ca-sj")

        let row = try #require(model.rows.first { $0.id == "us-ca-sj" })
        #expect(
            row.affordances == [.inUseLabel, .remove],
            "the attached downloaded copy lost its affordances to the bundled row: \(row)"
        )
        #expect(row.stateLine == "Installed · \(version)")
        // And exactly one card on the screen claims to be in use — the attached one.
        let builtIn = try #require(model.rows.first { $0.id == CityDownloadRow.builtInID })
        #expect(builtIn.affordances == [.use], "the bundle is not attached; `us-ca-sj` is")
        #expect(model.rows.filter { $0.affordances.contains(.inUseLabel) }.count == 1)
    }

    /// The download action refuses a bundled-current city outright, not merely by declining to draw
    /// a button. A stale view, a future affordance or a test cannot start the transfer.
    ///
    /// The control runs on its **own** model: `download()` also returns early when a transfer is
    /// already in flight, so a control sharing a model with the refused call would pass for the
    /// wrong reason — and fail with it under a red-proof, proving nothing.
    @MainActor
    @Test("download() refuses a city the bundle already holds")
    func downloadRefusesABundledCity() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let sf = Self.entry(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        let bundled = [
            SeedCities.City(id: "sf", displayName: "San Francisco", contentRev: "2026-07-31")
        ]

        let refusing = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: bundled, onInventoryChange: {}
        )
        refusing.download(sf)
        #expect(refusing.downloading == nil, "a download started for a city that ships in the app")

        // The control, on a model that has started nothing: the same call for a city the bundle
        // does not hold does start one.
        let permitting = CityDownloadsModel(
            library: library, downloader: CityDownloader(baseURL: dir),
            bundledCities: bundled, onInventoryChange: {}
        )
        let elsewhere = Self.entry(
            id: "us-ny-nyc", displayName: "New York", contentRev: "2026-08-20"
        )
        permitting.download(elsewhere)
        #expect(permitting.downloading?.id == "us-ny-nyc")
        permitting.cancelDownload()
    }

    // MARK: - Names and coverage the disk already knows (§3.4)

    /// An offline row used to be titled `us-ca-sj` and to state no coverage. Since s16 the installed
    /// file itself carries `dim_city.display_name` and its own `seed_meta`, so the disk knows both —
    /// and the id survives as the title fallback for a file too old to carry a name, never a
    /// prettier one this layer made up.
    @Test("an offline row takes its title and coverage from the file, falling back to the id")
    func offlineRowsAreNamedByTheirFile() {
        let named = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "us-ca-sj", version: "s16-r2026-07-31-c9a440b2",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1, displayName: "San Jose",
                coverage: "downtown"
            ),
            isActive: false
        )
        #expect(named.title == "San Jose")
        #expect(named.coverageNote == "Covers downtown only")
        #expect(named.affordances == [.use, .remove])

        let unnamed = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "us-ca-sj", version: "s14-r2026-01-01",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1, displayName: nil, coverage: nil
            ),
            isActive: false
        )
        #expect(unnamed.title == "us-ca-sj")
        #expect(unnamed.coverageNote == nil)
    }

    /// The library reads the name and the coverage out of the file it installed, so the offline
    /// screen never has to reach the manifest for either.
    @Test("the library reads an installed city's name and coverage from the installed file")
    func libraryReadsTheInstalledName() throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let file = dir.appendingPathComponent("sj.sqlite")
        try Self.cityFile(
            at: file, idSpace: "us-ca-sj", displayName: "San Jose", snapshotOn: "2026-07-31",
            shipExtentKey: "sj_ship_extent", shipExtent: "downtown"
        )

        try library.install(
            verifiedFileAt: file, id: "us-ca-sj", version: "s16-r2026-07-31-c9a440b2"
        )
        #expect(library.installedCities().map(\.displayName) == ["San Jose"])
        #expect(library.installedCities().map(\.coverage) == ["downtown"])
    }

    // MARK: - The manifest keys that were always there (E209 B3 / E213 / E238)

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

    private static func manifestJSON(_ cities: [CityManifest.City]) -> String {
        let entries = cities.map { city in
            """
            {"id": "\(city.id)", "display_name": "\(city.displayName)",
             "coverage": "\(city.coverage)", "tree_count": \(city.treeCount),
             "schema_version": \(city.schemaVersion),
             "content_rev": "\(city.contentRev ?? "")", "version": "\(city.version)",
             "path": "\(city.path)", "bytes": \(city.bytes), "sha256": "\(city.sha256)"}
            """
        }
        return """
        {"manifest_format": 1, "cities": [\(entries.joined(separator: ",\n"))]}
        """
    }
}
