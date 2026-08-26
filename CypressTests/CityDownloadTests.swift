import CryptoKit
import Foundation
import Testing
@testable import Cypress

/// The app side of R36's base layer (#157, RULINGS R43): manifest decode,
/// install-state comparison, byte verification before install, atomic replace, pre-attach
/// validation, and the per-inventory coverage sentence.
///
/// Nothing here touches the network: the downloader is exercised against `file://` fixtures on
/// disk, which is the point — the contract is bytes-and-hashes, not transport.
@Suite("City downloads")
struct CityDownloadTests {

    // MARK: - Fixtures

    /// A trimmed copy of the frozen format-1 manifest's shape (two cities), fields as
    /// `Tools/publish_cities.py` wrote them before format 1 retired. Still the right specimen
    /// for this suite: that object is permanent in the bucket and this build still reads it.
    static let manifestJSON = """
    {
      "manifest_format": 1,
      "generated_at": "2026-08-02T01:23:36+00:00",
      "generator": "Tools/publish_cities.py",
      "base_url_hint": "https://example.invalid/should-never-be-read",
      "source_seed": {"generated_at": "2026-07-20T00:00:00+00:00", "tree_count": 198625, "sha256": "aa"},
      "cities": [
        {
          "id": "sf",
          "display_name": "San Francisco",
          "coverage": "full",
          "bbox": {"min_lat": 37.7, "max_lat": 37.8, "min_lon": -122.5, "max_lon": -122.3},
          "centroid": {"lat": 37.76, "lon": -122.43},
          "tree_count": 145837,
          "schema_version": 14,
          "content_rev": "2026-07-31",
          "version": "s14-r2026-07-31",
          "path": "cities/sf/s14-r2026-07-31/sf.sqlite",
          "bytes": 80613376,
          "sha256": "b63ad949a5ca61a7664d67ec13e9bfcfbc0e32eb3c5593e89fba85357e0c8f57",
          "attribution": [{"inventory": "sf_city", "name": "SF Public Works street tree inventory", "url": "x"}]
        },
        {
          "id": "us-ca-sj",
          "display_name": "San Jose",
          "coverage": "downtown",
          "bbox": {"min_lat": 37.3, "max_lat": 37.37, "min_lon": -121.93, "max_lon": -121.85},
          "centroid": {"lat": 37.33, "lon": -121.89},
          "tree_count": 52788,
          "schema_version": 14,
          "content_rev": "2026-07-31",
          "version": "s14-r2026-07-31",
          "path": "cities/us-ca-sj/s14-r2026-07-31/us-ca-sj.sqlite",
          "bytes": 27975680,
          "sha256": "c1ea8e0bfcf708af9d9d95e2df5552de18ccf085f1a6afacb109894224a3d667",
          "attribution": [{"inventory": "sj_street_tree", "name": "City of San Jose Street Tree inventory", "url": "x", "license": "CC-BY"}]
        }
      ]
    }
    """

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("city-download-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A manifest entry describing `payload` exactly — the honest entry a well-behaved publisher
    /// would have written for it.
    static func entry(
        id: String = "sf",
        version: String = "s14-r2026-07-31",
        schemaVersion: Int = 14,
        payload: Data,
        sha256: String? = nil
    ) -> CityManifest.City {
        CityManifest.City(
            id: id,
            displayName: "Fixture City",
            coverage: "full",
            treeCount: 1,
            schemaVersion: schemaVersion,
            version: version,
            path: "cities/\(id)/\(version)/\(id).sqlite",
            bytes: Int64(payload.count),
            sha256: sha256 ?? sha256Hex(payload)
        )
    }

    /// Writes `payload` into a `file://` mirror of the bucket layout and returns a downloader
    /// pointed at it. Local fixtures, never the live bucket (CLAUDE.md: CI must not need a network).
    static func bucket(payload: Data, for city: CityManifest.City, in dir: URL) throws -> CityDownloader {
        try park(payload: payload, for: city, in: dir)
        return CityDownloader(baseURL: dir)
    }

    /// The same `file://` mirror, with no downloader on the end of it — what a transfer needs.
    @discardableResult
    static func park(payload: Data, for city: CityManifest.City, in dir: URL) throws -> URL {
        let object = dir.appendingPathComponent(city.path)
        try FileManager.default.createDirectory(
            at: object.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try payload.write(to: object)
        return object
    }

    /// Runs one transfer through the shipping path, and returns once it has settled **and said so**.
    ///
    /// **An ordinary configuration, and that is a real limit rather than a shortcut.** A background
    /// session refuses a `file://` URL outright and ignores `protocolClasses` entirely, so neither
    /// of this project's two fixture mechanisms can reach `CityDownloadService` through one. What
    /// this therefore proves is every line of the service *except* which configuration carries the
    /// bytes — the record, the status rule, the verification, the install, the publish. That the
    /// shipping configuration is a background one is `shippingConfigurationIsBackground`; that a
    /// background transfer survives a suspend and a kill was watched on the device, and the PR body
    /// says which parts of that a simulator can and cannot show.
    static func transfer(
        _ city: CityManifest.City,
        from baseURL: URL,
        into library: CityLibrary
    ) async throws -> CityDownloadProgress {
        let progress = await CityDownloadProgress()
        let service = CityDownloadService(
            library: library, baseURL: baseURL,
            configuration: .ephemeral, progress: progress
        )
        let started = await MainActor.run { service.start(city) }
        #expect(started, "the service declined to start a transfer with nothing else running")
        await service.waitUntilIdle()
        return progress
    }

    /// A copy of `record` with one field replaced — for putting a deliberately *wrong* promise to
    /// the verifier without hand-building a whole manifest entry around it.
    static func record(
        _ record: CityDownloadRecord, bytes: Int64? = nil, sha256: String? = nil
    ) -> CityDownloadRecord {
        CityDownloadRecord(
            CityManifest.City(
                id: record.id, displayName: record.displayName, coverage: "full",
                treeCount: 1, schemaVersion: 14, version: record.version,
                path: "cities/\(record.id)/\(record.version)/\(record.id).sqlite",
                bytes: bytes ?? record.bytes, sha256: sha256 ?? record.sha256
            )
        )
    }

    /// A minimal file that passes `SeedSchema.introspect` — the four required tables, the three
    /// load-bearing `trees` columns — plus `seed_meta` claiming `publishSchemaVersion` and a
    /// planting-date distribution of `datedRows` out of `totalRows`.
    static func miniSeed(
        at url: URL,
        publishSchemaVersion: Int?,
        totalRows: Int = 0,
        datedRows: Int = 0
    ) throws {
        let connection = try SQLiteConnection(path: url.path)
        try connection.execute("""
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE, lat REAL, lon REAL,
                status TEXT, deleted_at TEXT, planted_year INTEGER
            );
            CREATE TABLE species (id INTEGER PRIMARY KEY, uuid TEXT);
            CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY);
            CREATE TABLE trees_rtree (id INTEGER PRIMARY KEY);
            CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        if let publishSchemaVersion {
            try connection.execute(
                "INSERT INTO seed_meta VALUES ('publish_schema_version', '\(publishSchemaVersion)')"
            )
        }
        for row in 0..<totalRows {
            let year = row < datedRows ? "1990" : "NULL"
            try connection.execute("""
                INSERT INTO trees (uuid, lat, lon, status, planted_year)
                VALUES ('u\(row)', 37.7, -122.4, 'alive', \(year))
                """)
        }
    }

    // MARK: - Manifest decode

    @Test("the live manifest shape decodes: both cities, every load-bearing field")
    func manifestDecodes() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON.utf8))
        #expect(manifest.format == 1)
        try #require(manifest.cities.count == 2)

        let sf = manifest.cities[0]
        #expect(sf.id == "sf")
        #expect(sf.displayName == "San Francisco")
        #expect(sf.coverage == "full")
        #expect(sf.schemaVersion == 14)
        #expect(sf.version == "s14-r2026-07-31")
        #expect(sf.path == "cities/sf/s14-r2026-07-31/sf.sqlite")
        #expect(sf.bytes == 80_613_376)
        #expect(sf.sha256 == "b63ad949a5ca61a7664d67ec13e9bfcfbc0e32eb3c5593e89fba85357e0c8f57")

        let sj = manifest.cities[1]
        #expect(sj.id == "us-ca-sj")
        #expect(sj.coverage == "downtown")
    }

    /// **The future moved, and this test moved with it.** Format 2 was the future when this was
    /// written; the s17 round shipped it, and `CityManifest.knownFormats` reads 1 and 2 — it
    /// keeps 1 because the retired format-1 object is frozen in the bucket rather than deleted.
    /// So the specimen is 3 — a format genuinely nobody has written — and the rule it pins is
    /// unchanged: an unknown format is refused at the door,
    /// before anything else is read, because guessing at a format's meaning is how a reader
    /// silently mis-installs a file.
    @Test("a manifest from the future is refused at the door")
    func manifestRefusesUnknownFormat() throws {
        let future = Self.manifestJSON.replacingOccurrences(
            of: "\"manifest_format\": 1", with: "\"manifest_format\": 3"
        )
        #expect(throws: CityManifest.DecodeError.unknownFormat(3)) {
            _ = try CityManifest.decode(Data(future.utf8))
        }
        // The control: the format this fixture actually carries is still accepted, so the test
        // above proves a refusal rather than a decoder that refuses everything.
        #expect(throws: Never.self) {
            _ = try CityManifest.decode(Data(Self.manifestJSON.utf8))
        }
    }

    // MARK: - The manifest is the one file a cache must not answer (#199)

    /// **Every other object in R37's design is immutable and hash-verified; the manifest is not.**
    /// A reader holding yesterday's manifest is internally consistent and wrong — it verifies the
    /// old city file perfectly, downloads nothing, and reports no error, so a republished city
    /// never arrives and nothing on the phone says why. Measured on the public domain on
    /// 2026-08-03: minutes after a republish a bare GET still returned the previous manifest while
    /// the same URL with a unique query returned the new one.
    ///
    /// This asserts the request, not the network. The network is not a test dependency here (see
    /// this suite's header) and a cache's behavior is not ours to assert anyway — what is ours is
    /// that we never ask a question a cache is allowed to answer.
    @Test("the manifest request carries a unique cache-buster, and no two are alike")
    func manifestRequestIsUncacheable() throws {
        let base = URL(string: "https://cypress-cities.t3.tigrisbucket.io")!
        let first = CityDownloader.manifestRequest(base: base)
        let second = CityDownloader.manifestRequest(base: base)

        let firstURL = try #require(first.url)
        let secondURL = try #require(second.url)

        #expect(
            firstURL.path == "/\(CityDownloader.manifestName)",
            "the request stopped naming the manifest: \(firstURL)"
        )

        let items = URLComponents(url: firstURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let buster = items.first { $0.name == "cb" }?.value
        #expect(
            (buster?.isEmpty == false),
            "the manifest URL carries no cache-buster, so an edge cache may answer it: \(firstURL)"
        )
        #expect(
            firstURL != secondURL,
            """
            two manifest requests share a URL, so the second can be served from the cache the \
            first filled — which is the whole defect: \(firstURL)
            """
        )
        #expect(first.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(first.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
    }

    /// A query string on a `file://` URL does not identify a file. Every test in this suite serves
    /// its fixtures from disk, so busting a cache that cannot exist there would break all of them.
    @Test("a file:// base is left exactly as it was")
    func manifestRequestLeavesFileURLsAlone() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fixtures")
        let request = CityDownloader.manifestRequest(base: base)
        let url = try #require(request.url)

        #expect(url == base.appendingPathComponent(CityDownloader.manifestName))
        #expect(url.query == nil, "a query was appended to a file URL, which names no file: \(url)")
    }

    // MARK: - Install-state comparison

    @Test("install state: every branch, including refuse-newer-schema")
    func installStateBranches() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON.utf8))
        let city = manifest.cities[0]

        #expect(
            CityInstallState(published: city, installedVersion: nil, newestKnownSchemaVersion: 14)
                == .notInstalled
        )
        #expect(
            CityInstallState(published: city, installedVersion: "s14-r2026-07-31", newestKnownSchemaVersion: 14)
                == .installedCurrent(installedVersion: "s14-r2026-07-31")
        )
        // R37.2: update detection is string equality, nothing cleverer.
        #expect(
            CityInstallState(published: city, installedVersion: "s14-r2026-06-01", newestKnownSchemaVersion: 14)
                == .updateAvailable(installedVersion: "s14-r2026-06-01")
        )
        // The fossil-install lesson pointed forward: a generation from the future is refused,
        // whether or not something older is installed — and the older install keeps its identity.
        #expect(
            CityInstallState(published: city, installedVersion: nil, newestKnownSchemaVersion: 13)
                == .needsNewerApp(installedVersion: nil)
        )
        #expect(
            CityInstallState(published: city, installedVersion: "s13-r2026-01-01", newestKnownSchemaVersion: 13)
                == .needsNewerApp(installedVersion: "s13-r2026-01-01")
        )
    }

    // MARK: - Download verification

    /// The two refusals, asked of the rule itself rather than of a transfer.
    ///
    /// **This used to run a download to get here, and asking directly is strictly better.** The
    /// transfer now lives on a background session (`CityDownloadService`) whose failures reach the
    /// screen as one sentence, so a test that drove the transfer could see only *that* a file was
    /// refused — never which of the two rules refused it, or in which order. `CityDownloader.verify`
    /// is where that order is decided, it throws the exact error, and it has no transport in it at
    /// all. What a transfer must still prove — that refused bytes install nothing and leave no
    /// staging behind — is `refusedBytesInstallNothing` below, over the shipping path.
    @Test("verification refuses on size before hash, and names which rule refused")
    func verificationRefusesWithTheExactError() throws {
        let dir = try Self.tempDir()
        let payload = Data("some bytes".utf8)
        let file = dir.appendingPathComponent("candidate.sqlite")
        try payload.write(to: file)
        let honest = CityDownloadRecord(Self.entry(payload: payload))

        // Size first: the promise is one byte longer than the file and its sha256 is honest, so
        // only an order that checks the count first can produce this error.
        #expect(throws: CityDownloader.DownloadError.sizeMismatch(
            expected: Int64(payload.count) + 1, got: Int64(payload.count)
        )) {
            try CityDownloader.verify(fileAt: file, against: Self.record(honest, bytes: honest.bytes + 1))
        }

        // The count agrees and the hash does not.
        let liar = String(repeating: "ab", count: 32)
        #expect(throws: CityDownloader.DownloadError.checksumMismatch(
            expected: liar, got: Self.sha256Hex(payload)
        )) {
            try CityDownloader.verify(fileAt: file, against: Self.record(honest, sha256: liar))
        }

        // The control, and it is the half that matters: an honest promise passes, so the two above
        // are refusals rather than a verifier that rejects everything put to it.
        #expect(throws: Never.self) {
            try CityDownloader.verify(fileAt: file, against: honest)
        }
    }

    @Test("bytes that fail verification install nothing and leave staging empty")
    func refusedBytesInstallNothing() async throws {
        let dir = try Self.tempDir()
        let payload = Data("not the promised bytes".utf8)
        let promised = Self.entry(payload: payload, sha256: String(repeating: "ab", count: 32))
        try Self.park(payload: payload, for: promised, in: dir)
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        let progress = try await Self.transfer(promised, from: dir, into: library)

        #expect(await progress.failedCityID == promised.id)
        #expect(await progress.installCount == 0)
        // The staging area holds nothing and the library never heard of the city.
        let staged = (try? FileManager.default.contentsOfDirectory(atPath: library.stagingURL.path)) ?? []
        #expect(staged.isEmpty, "a failed download left \(staged) in staging")
        #expect(library.installedVersion(of: promised.id) == nil)
    }

    @Test("a verified download installs at the immutable path; an update prunes the old version")
    func verifiedInstallAndAtomicUpdate() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        let v1Payload = Data("version one".utf8)
        let v1 = Self.entry(version: "s14-r2026-06-01", payload: v1Payload)
        try Self.park(payload: v1Payload, for: v1, in: dir)
        let afterV1 = try await Self.transfer(v1, from: dir, into: library)
        #expect(await afterV1.installCount == 1)
        #expect(library.installedVersion(of: "sf") == "s14-r2026-06-01")

        // A failed update leaves the installed version byte-for-byte untouched.
        let badPayload = Data("version two, corrupted in flight".utf8)
        let promisedV2 = Self.entry(version: "s14-r2026-07-31", payload: Data("version two".utf8))
        let badDir = try Self.tempDir()
        try Self.park(payload: badPayload, for: promisedV2, in: badDir)
        let afterBad = try await Self.transfer(promisedV2, from: badDir, into: library)
        #expect(await afterBad.failedCityID == promisedV2.id)
        #expect(await afterBad.installCount == 0)
        #expect(library.installedVersion(of: "sf") == "s14-r2026-06-01")
        #expect(try Data(contentsOf: library.fileURL(id: "sf", version: "s14-r2026-06-01")) == v1Payload)

        // The real v2 lands, and only then is v1 pruned (new-then-prune, ruling §4).
        let v2Payload = Data("version two".utf8)
        let goodDir = try Self.tempDir()
        try Self.park(payload: v2Payload, for: promisedV2, in: goodDir)
        let afterV2 = try await Self.transfer(promisedV2, from: goodDir, into: library)
        #expect(await afterV2.installCount == 1)
        #expect(library.installedVersion(of: "sf") == "s14-r2026-07-31")
        #expect(!FileManager.default.fileExists(
            atPath: library.fileURL(id: "sf", version: "s14-r2026-06-01").path
        ))
        #expect(library.installedCities().map(\.version) == ["s14-r2026-07-31"])
    }

    // MARK: - The background session's own state machine

    /// **The promise travels on the task, and a later process is what reads it.**
    ///
    /// This is what lets a transfer survive the app: `nsurlsessiond` hands a task back to whichever
    /// process next opens the session, and `taskDescription` is the only thing that comes with it.
    /// A record that did not round-trip would be a finished download nothing could verify.
    @Test("the download record round-trips through a task description")
    func recordRoundTrips() throws {
        let city = Self.entry(
            id: "us-ny-nyc-manhattan", version: "s17-r2026-08-22.02-ac7b1ccc",
            payload: Data("x".utf8)
        )
        let record = CityDownloadRecord(city)
        #expect(CityDownloadRecord.decoded(try record.encoded()) == record)
        // Junk decodes to nil rather than to a partly-filled record: a transfer with no promise is
        // cancelled (`CityDownloadService.adopt`), and a half-read one would be verified against
        // nonsense.
        #expect(CityDownloadRecord.decoded("not json") == nil)
        #expect(CityDownloadRecord.decoded(nil) == nil)
    }

    /// **The shipping configuration is a background one, and both flags on it are decisions.**
    ///
    /// `isDiscretionary = true` is the system scheduling the transfer at its own convenience —
    /// plugged in, on wi-fi, possibly hours later — underneath a ring the reader is watching.
    /// `sessionSendsLaunchEvents = false` means a transfer that finishes after the app has been
    /// terminated is never delivered to anybody at all. Neither default suits a button somebody
    /// just pressed.
    @Test("the shipping session is a background session that relaunches the app")
    func shippingConfigurationIsBackground() {
        let configuration = CityDownloadService.backgroundConfiguration()
        #expect(configuration.identifier == CityDownloadService.backgroundSessionIdentifier)
        #expect(configuration.sessionSendsLaunchEvents)
        #expect(!configuration.isDiscretionary)
        // The control: an ordinary configuration carries no identifier, so the line above is reading
        // a background session rather than a property every session happens to have.
        #expect(URLSessionConfiguration.ephemeral.identifier == nil)
    }

    /// **Asking an idle session what it is carrying still answers**, which is the half a screen
    /// waits on.
    ///
    /// `hasAdopted` is what stops the Cities screen drawing `Download` for a city already on its
    /// way; a launch with nothing outstanding has to set it too, or the screen waits for an answer
    /// that never comes.
    @Test("adoption answers even when there is nothing to adopt")
    func adoptionOfAnIdleSessionAnswers() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let progress = await CityDownloadProgress()
        let service = CityDownloadService(
            library: library, baseURL: dir,
            configuration: .ephemeral, progress: progress
        )

        #expect(await !progress.hasAdopted)
        await service.adopt()
        #expect(await progress.hasAdopted)
        #expect(await progress.inFlight == nil)
    }

    /// **A live transfer survives being asked about**, which is the rule `adopt` applies to whatever
    /// the session hands back.
    ///
    /// The transfer here was started by *this* process, because an ordinary `URLSession` cannot hand
    /// a task to another one — that is precisely what a background session's identifier is for. So
    /// what this pins is the decoding-and-republishing half: the promise `start` wrote onto the task
    /// is read back off it through `getAllTasks`, and the city is named again. The cross-process
    /// half is the simulator caveat recorded in the PR body.
    @Test("a live transfer is read back off its own task and re-published", .timeLimit(.minutes(1)))
    func adoptionRepublishesALiveTransfer() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))
        let payload = Data(repeating: 7, count: 64 * 1024)
        let base = URL(string: "https://cities-adopt.invalid/\(UUID().uuidString)")!
        let city = Self.entry(payload: payload)
        CityBucketFixtureProtocol.park(
            base.appendingPathComponent(city.path), body: payload, stalls: true
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CityBucketFixtureProtocol.self]

        let progress = await CityDownloadProgress()
        let service = CityDownloadService(
            library: library, baseURL: base, configuration: configuration, progress: progress
        )
        await MainActor.run { _ = service.start(city) }
        #expect(await progress.inFlight?.record.id == city.id)

        // The session is asked what it is carrying, exactly as a fresh launch asks.
        await service.adopt()
        #expect(await progress.hasAdopted)
        #expect(
            await progress.inFlight?.record == CityDownloadRecord(city),
            "the promise did not survive the round trip through the task"
        )

        await MainActor.run { service.cancel() }
        await service.waitUntilIdle()
    }

    // MARK: - What the union attaches, and the pre-attach gate

    /// **A schema generation from the future is left on disk and left out of the union.**
    ///
    /// The gate is the same one that used to clear the `active-city` marker; what changed is what
    /// it protects. There is no marker to clear now — `installedInventoryFiles()` is
    /// the whole of the answer, and a file it refuses is simply not among them.
    ///
    /// **Refused, not deleted.** The reader paid for those bytes and the reason may be that this
    /// build is older than the file; a later build may read it perfectly well. It stays on disk,
    /// `installedCities()` still lists it, and the Cities screen can still remove it deliberately.
    @Test("a schema generation from the future is refused by the union but kept on disk")
    func theUnionRefusesANewerSchema() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        let fossil = dir.appendingPathComponent("fossil.sqlite")
        try Self.miniSeed(at: fossil, publishSchemaVersion: 99)
        try library.install(verifiedFileAt: fossil, id: "sf", version: "s99-r2026-01-01")
        #expect(library.installedInventoryFiles().isEmpty, "a file from the future was attached")
        #expect(
            library.installedCities().map(\.id) == ["sf"],
            "a refused file was deleted; the reader paid for those bytes"
        )

        // The same shape at generation 14 is taken.
        let current = dir.appendingPathComponent("current.sqlite")
        try Self.miniSeed(at: current, publishSchemaVersion: 14, totalRows: 1)
        try library.install(verifiedFileAt: current, id: "sf", version: "s14-r2026-07-31")
        let files = library.installedInventoryFiles()
        #expect(files.map(\.id) == ["sf"])
        let resolved = try #require(files.first).url
        #expect(resolved == library.fileURL(id: "sf", version: "s14-r2026-07-31"))
        #expect(files.allSatisfy { !$0.isBundled }, "a downloaded pack claimed to be the bundle")

        // And the resolved file really attaches through the same path the bundle uses.
        let store = try await CypressStore.inMemory(seedURL: resolved)
        #expect(store.seed != nil)
    }

    /// Removing a city takes it out of what the union would attach, and leaves nothing behind.
    ///
    /// The retired `active-city` marker is deleted on sight, so a device upgrading from a build
    /// that wrote one does not carry a file nothing reads (`discardRetiredActiveMarker`).
    @Test("removal empties the library, and the retired marker is discarded")
    func removalAndTheRetiredMarker() throws {
        let dir = try Self.tempDir()
        let root = dir.appendingPathComponent("library")
        let library = CityLibrary(rootURL: root)

        let file = dir.appendingPathComponent("c.sqlite")
        try Self.miniSeed(at: file, publishSchemaVersion: 14)
        try library.install(verifiedFileAt: file, id: "sf", version: "s14-r2026-07-31")
        #expect(library.installedInventoryFiles().map(\.id) == ["sf"])

        // A marker written by an older build of the app.
        let marker = root.appendingPathComponent("active-city")
        try "sf".write(to: marker, atomically: true, encoding: .utf8)
        #expect(
            library.installedCities().map(\.id) == ["sf"],
            "the marker was read as an installed city"
        )
        library.discardRetiredActiveMarker()
        #expect(!FileManager.default.fileExists(atPath: marker.path))

        try library.remove(id: "sf")
        #expect(library.installedInventoryFiles().isEmpty)
        #expect(library.installedCities().isEmpty)
    }

    // MARK: - The measured coverage fact (R43 §5), withdrawn by RULINGS R41

    // Two tests stood here, both added by task #157 under R43 §5:
    //
    //   `undatedShareIsMeasured`      — `CypressStore.seedUndatedShare` is measured from whichever
    //                                   inventory is attached, not remembered as 0.8078.
    //   `setAsideDerivesFromTheShare` — the derived caveat reproduces the fused bundle's sentence
    //                                   verbatim, and moves to "3 in 4" / "99 in 100" per city.
    //
    // **R43 §5 and R41 collide, and R41 wins** (task #180). R43 §5 generalized the year filter's
    // caveat sentence from a bundle constant to a per-inventory measurement; it never decided
    // whether the sentence should exist, because that was not its question. R41 decides exactly
    // that — "No messages should appear alongside filters ever. for any reason. ever again." — it
    // is later, and it is the owner's direct instruction rather than delegated authority.
    //
    // So the sentence is gone, and `seedUndatedShare`, `measureUndatedShare` and
    // `MapYearFilterCopy.setAside(undatedShare:)` are gone with it: a measurement whose only
    // consumer is a forbidden sentence is dead code, and keeping the property unread is the
    // #62/E126 shape. These two tests are deleted rather than adapted because their subject no
    // longer exists — there is nothing left to assert that would not be an assertion about a
    // string nobody builds.
    //
    // **What was genuinely worth keeping was kept.** The seed fact these tests pinned — that most
    // rows carry no planting date, and that the share moves per city — is still asserted, in
    // `MapFilterTests.plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor`, where it now guards
    // the year control's *design* (decade buckets, and #178's vacant-site exclusion) rather than
    // the wording of a caveat. Nothing about city downloads is untested by this removal: R43 §5 is
    // the only clause of R43 affected, and the rest of this suite is untouched.
    //
    // Recorded for the orchestrator in `ERRATA E205`; R43 §5 needs
    // striking in `docs/RULINGS.md` at merge.

    // MARK: - Row presentation (ruling §3, every branch)

    @Test("row states: affordances follow the ruling's table exactly")
    func rowPresentation() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON.utf8))
        let sf = manifest.cities[0]
        let sj = manifest.cities[1]

        // **The built-in card draws no affordance at all**. It cannot be switched off,
        // so a control saying otherwise is the forbidden contradiction — an `In use` label
        // above a sibling `Use` was the screen the owner ruled out.
        #expect(CityDownloadRow.builtIn().affordances.isEmpty)

        let fresh = CityDownloadRow.published(
            city: sf, state: .notInstalled,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(fresh.stateLine == "81 MB")
        #expect(fresh.affordances == [.download])
        #expect(fresh.coverageNote == nil)

        // Partial coverage is stated in the publisher's word, not invented.
        let partial = CityDownloadRow.published(
            city: sj, state: .notInstalled,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(partial.coverageNote == "Covers downtown only")

        let downloading = CityDownloadRow.published(
            city: sf, state: .notInstalled,
            downloadingFraction: 0.42, lastAttemptFailed: false
        )
        #expect(downloading.affordances == [.cancel])
        #expect(downloading.progress == 0.42)
        #expect(downloading.stateLine == "Downloading…")

        // Failure reverts the affordances and says exactly what happened.
        let failed = CityDownloadRow.published(
            city: sf, state: .notInstalled,
            downloadingFraction: nil, lastAttemptFailed: true
        )
        #expect(failed.stateLine == "Download failed. Nothing was changed.")
        #expect(failed.isFailure)
        #expect(failed.affordances == [.download])

        // **No `In use` label and no `Use` button anywhere**: a downloaded city is in
        // the union, so the only question its row can put is whether to keep it.
        let installed = CityDownloadRow.published(
            city: sf, state: .installedCurrent(installedVersion: sf.version),
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(installed.affordances == [.remove])
        #expect(installed.stateLine == "Installed · s14-r2026-07-31")

        let updatable = CityDownloadRow.published(
            city: sf, state: .updateAvailable(installedVersion: "s14-r2026-06-01"),
            downloadingFraction: nil, lastAttemptFailed: false
        )
        // Back to R43 §3's ruled pair. `Use` was added to this row when an installed-but-unattached
        // copy needed a way back on screen; downloaded means in the union now, so that state does
        // not exist and the third button goes with it — and the row is inside §3's "never more
        // than two visible" again.
        #expect(updatable.affordances == [.update, .remove])
        #expect(updatable.stateLine == "Update available · s14-r2026-06-01 installed")

        // A promise no button can keep gets no button (ruling §3).
        let refused = CityDownloadRow.published(
            city: sf, state: .needsNewerApp(installedVersion: nil),
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(refused.affordances.isEmpty)
        #expect(refused.stateLine == "Needs a newer app")
        #expect(refused.detailLine == "This city's data is a newer format than this app can read.")

        // …but an older compatible install keeps its affordances; only the update is refused.
        let refusedButInstalled = CityDownloadRow.published(
            city: sf, state: .needsNewerApp(installedVersion: "s14-r2026-06-01"),
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(refusedButInstalled.affordances == [.remove])

        // Offline: disk facts alone, no-network affordances intact.
        let offline = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "sf", version: "s14-r2026-07-31",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1
            )
        )
        #expect(offline.affordances == [.remove])
    }
}
