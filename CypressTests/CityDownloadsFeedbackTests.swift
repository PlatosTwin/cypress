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
/// Nothing here touches the network: the downloader is exercised against `file://` fixtures, and
/// every other fact is a pure value.
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
            Self.borough("manhattan", "Manhattan"),
            Self.borough("brooklyn", "Brooklyn"),
            Self.borough("queens", "Queens")
        ]
        let rows: [CityDownloadRow] = [
            .builtIn(isActive: true, cityNames: ["San Francisco", "San Jose"]),
            Self.row(cities[0], state: .bundledOutdated(bundledContentRev: "2026-07-31")),
            Self.row(cities[1], state: .notInstalled),
            Self.row(cities[2], state: .notInstalled),
            Self.row(cities[3], state: .notInstalled)
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
                    // Nothing stranded in the ungrouped run — all three boroughs went to the group.
                    ("Available to download", false, []),
                    ("New York City", true, [
                        "us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens"
                    ])
                ].map(String.init(describing:))
        )
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
    /// afford there is no such number: measured on this machine, 6 MB took **0.858 s** through the
    /// per-byte loop and **0.012 s** through the download task, so any bound loose enough to be
    /// stable (say six seconds) sits far above *both* and would certify the defect as fixed. That
    /// is this project's signature failure — a guard that is green while the defect is present.
    ///
    /// So the test measures the defect itself, here, on whatever machine is running: it walks the
    /// same fixture with `URLSession.AsyncBytes` exactly as the old body did, and then requires the
    /// real download to beat that by 10×. Machine speed cancels, and the assertion can only pass
    /// if the two code paths are genuinely different in kind.
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
}
