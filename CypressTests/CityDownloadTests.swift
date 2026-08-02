import CryptoKit
import Foundation
import Testing
@testable import Cypress

/// The app side of R36's base layer (#157, pending city-downloads ruling): manifest decode,
/// install-state comparison, byte verification before install, atomic replace, pre-attach
/// validation, and the per-inventory coverage sentence.
///
/// Nothing here touches the network: the downloader is exercised against `file://` fixtures on
/// disk, which is the point — the contract is bytes-and-hashes, not transport.
@Suite("City downloads")
struct CityDownloadTests {

    // MARK: - Fixtures

    /// A trimmed copy of the live manifest's shape (format 1, two cities), fields as
    /// `Tools/publish_cities.py` writes them.
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
        let object = dir.appendingPathComponent(city.path)
        try FileManager.default.createDirectory(
            at: object.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try payload.write(to: object)
        return CityDownloader(baseURL: dir)
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

    @Test("a manifest from the future is refused at the door")
    func manifestRefusesUnknownFormat() throws {
        let future = Self.manifestJSON.replacingOccurrences(
            of: "\"manifest_format\": 1", with: "\"manifest_format\": 2"
        )
        #expect(throws: CityManifest.DecodeError.unknownFormat(2)) {
            _ = try CityManifest.decode(Data(future.utf8))
        }
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

    @Test("a sha256 mismatch throws, deletes the temp file, and installs nothing")
    func checksumMismatchInstallsNothing() async throws {
        let dir = try Self.tempDir()
        let payload = Data("not the promised bytes".utf8)
        let promised = Self.entry(payload: payload, sha256: String(repeating: "ab", count: 32))
        let downloader = try Self.bucket(payload: payload, for: promised, in: dir)
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        await #expect(throws: CityDownloader.DownloadError.self) {
            _ = try await downloader.downloadCity(promised, to: library.stagingURL)
        }
        // The staging area holds nothing and the library never heard of the city.
        let staged = (try? FileManager.default.contentsOfDirectory(atPath: library.stagingURL.path)) ?? []
        #expect(staged.isEmpty, "a failed download left \(staged) in staging")
        #expect(library.installedVersion(of: promised.id) == nil)
    }

    @Test("a byte-count mismatch is refused before the hash is even compared")
    func sizeMismatchIsRefused() async throws {
        let dir = try Self.tempDir()
        let payload = Data("some bytes".utf8)
        var promised = Self.entry(payload: payload)
        promised = CityManifest.City(
            id: promised.id, displayName: promised.displayName, coverage: promised.coverage,
            treeCount: promised.treeCount, schemaVersion: promised.schemaVersion,
            version: promised.version, path: promised.path,
            bytes: promised.bytes + 1, sha256: promised.sha256
        )
        let downloader = try Self.bucket(payload: payload, for: promised, in: dir)

        await #expect(throws: CityDownloader.DownloadError.sizeMismatch(
            expected: Int64(payload.count) + 1, got: Int64(payload.count)
        )) {
            _ = try await downloader.downloadCity(promised, to: dir.appendingPathComponent("staging"))
        }
    }

    @Test("a verified download installs at the immutable path; an update prunes the old version")
    func verifiedInstallAndAtomicUpdate() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        let v1Payload = Data("version one".utf8)
        let v1 = Self.entry(version: "s14-r2026-06-01", payload: v1Payload)
        let downloaderV1 = try Self.bucket(payload: v1Payload, for: v1, in: dir)
        let stagedV1 = try await downloaderV1.downloadCity(v1, to: library.stagingURL)
        try library.install(verifiedFileAt: stagedV1, id: v1.id, version: v1.version)
        #expect(library.installedVersion(of: "sf") == "s14-r2026-06-01")

        // A failed update leaves the installed version byte-for-byte untouched.
        let badPayload = Data("version two, corrupted in flight".utf8)
        let promisedV2 = Self.entry(version: "s14-r2026-07-31", payload: Data("version two".utf8))
        let downloaderBad = try Self.bucket(payload: badPayload, for: promisedV2, in: dir)
        await #expect(throws: CityDownloader.DownloadError.self) {
            _ = try await downloaderBad.downloadCity(promisedV2, to: library.stagingURL)
        }
        #expect(library.installedVersion(of: "sf") == "s14-r2026-06-01")
        #expect(try Data(contentsOf: library.fileURL(id: "sf", version: "s14-r2026-06-01")) == v1Payload)

        // The real v2 lands, and only then is v1 pruned (new-then-prune, ruling §4).
        let v2Payload = Data("version two".utf8)
        let downloaderV2 = try Self.bucket(payload: v2Payload, for: promisedV2, in: dir)
        let stagedV2 = try await downloaderV2.downloadCity(promisedV2, to: library.stagingURL)
        try library.install(verifiedFileAt: stagedV2, id: promisedV2.id, version: promisedV2.version)
        #expect(library.installedVersion(of: "sf") == "s14-r2026-07-31")
        #expect(!FileManager.default.fileExists(
            atPath: library.fileURL(id: "sf", version: "s14-r2026-06-01").path
        ))
        #expect(library.installedCities().map(\.version) == ["s14-r2026-07-31"])
    }

    // MARK: - Activation and the pre-attach gate

    @Test("a schema generation from the future never attaches: the marker clears instead")
    func activationRefusesNewerSchema() async throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        // A shape-valid file claiming generation 99: validation must refuse it.
        let fossil = dir.appendingPathComponent("fossil.sqlite")
        try Self.miniSeed(at: fossil, publishSchemaVersion: 99)
        try library.install(verifiedFileAt: fossil, id: "sf", version: "s99-r2026-01-01")
        try library.activate(id: "sf")
        #expect(library.validatedActiveSeedURL() == nil)
        #expect(library.activeCityID() == nil, "a refused activation must clear the marker")

        // The same shape at generation 14 attaches.
        let current = dir.appendingPathComponent("current.sqlite")
        try Self.miniSeed(at: current, publishSchemaVersion: 14, totalRows: 1)
        try library.install(verifiedFileAt: current, id: "sf", version: "s14-r2026-07-31")
        try library.activate(id: "sf")
        let resolved = try #require(library.validatedActiveSeedURL())
        #expect(resolved == library.fileURL(id: "sf", version: "s14-r2026-07-31"))

        // And the resolved file really attaches through the same path the bundle uses.
        let store = try await CypressStore.inMemory(seedURL: resolved)
        #expect(store.seed != nil)
    }

    @Test("a dangling marker resolves to the bundle, not a crash; remove deactivates")
    func danglingAndRemovedMarkers() throws {
        let dir = try Self.tempDir()
        let library = CityLibrary(rootURL: dir.appendingPathComponent("library"))

        try library.activate(id: "ghost")
        #expect(library.validatedActiveSeedURL() == nil)
        #expect(library.activeCityID() == nil)

        let file = dir.appendingPathComponent("c.sqlite")
        try Self.miniSeed(at: file, publishSchemaVersion: 14)
        try library.install(verifiedFileAt: file, id: "sf", version: "s14-r2026-07-31")
        try library.activate(id: "sf")
        try library.remove(id: "sf")
        #expect(library.activeCityID() == nil)
        #expect(library.installedCities().isEmpty)
    }

    // MARK: - The measured coverage fact (ruling §5)

    @Test("the undated share is measured from the attached inventory, not remembered")
    func undatedShareIsMeasured() async throws {
        let dir = try Self.tempDir()
        let seed = dir.appendingPathComponent("mini.sqlite")
        // 4 of 5 rows undated — the fused bundle's own rounding, from a five-row file.
        try Self.miniSeed(at: seed, publishSchemaVersion: 14, totalRows: 5, datedRows: 1)
        let store = try await CypressStore.inMemory(seedURL: seed)
        let share = try #require(store.seedUndatedShare)
        #expect(abs(share - 0.8) < 0.0001)

        let none = try await CypressStore.inMemory(seedURL: nil)
        #expect(none.seedUndatedShare == nil)
    }

    @Test("the derived caveat reproduces the bundle's sentence verbatim, and moves per city")
    func setAsideDerivesFromTheShare() {
        // The fused bundle's measured share must yield today's sentence to the byte — this is a
        // generalization, not a copy change (mock fidelity §5 against the ruling).
        #expect(
            MapYearFilterCopy.setAside(undatedShare: MapYearFilterCopy.undatedShareOfSeed)
                == MapYearFilterCopy.setAside
        )
        // San Francisco alone — E175's original measurement.
        #expect(MapYearFilterCopy.setAside(undatedShare: 0.7397).contains("3 in 4"))
        // San Jose alone: 222 dated of 52,788 (E176).
        #expect(MapYearFilterCopy.setAside(undatedShare: 0.9958).contains("99 in 100"))
        // No measurement falls back to the recorded bundle constant, never to a guess.
        #expect(MapYearFilterCopy.setAside(undatedShare: nil) == MapYearFilterCopy.setAside)
    }

    // MARK: - Row presentation (ruling §3, every branch)

    @Test("row states: affordances follow the ruling's table exactly")
    func rowPresentation() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON.utf8))
        let sf = manifest.cities[0]
        let sj = manifest.cities[1]

        // Built-in: `Use` when a city is active, the `In use` label otherwise.
        #expect(CityDownloadRow.builtIn(isActive: true).affordances == [.inUseLabel])
        #expect(CityDownloadRow.builtIn(isActive: false).affordances == [.use])

        let fresh = CityDownloadRow.published(
            city: sf, state: .notInstalled, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(fresh.stateLine == "81 MB")
        #expect(fresh.affordances == [.download])
        #expect(fresh.coverageNote == nil)

        // Partial coverage is stated in the publisher's word, not invented.
        let partial = CityDownloadRow.published(
            city: sj, state: .notInstalled, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(partial.coverageNote == "Covers downtown only")

        let downloading = CityDownloadRow.published(
            city: sf, state: .notInstalled, isActive: false,
            downloadingFraction: 0.42, lastAttemptFailed: false
        )
        #expect(downloading.affordances == [.cancel])
        #expect(downloading.progress == 0.42)
        #expect(downloading.stateLine == "Downloading…")

        // Failure reverts the affordances and says exactly what happened.
        let failed = CityDownloadRow.published(
            city: sf, state: .notInstalled, isActive: false,
            downloadingFraction: nil, lastAttemptFailed: true
        )
        #expect(failed.stateLine == "Download failed. Nothing was changed.")
        #expect(failed.isFailure)
        #expect(failed.affordances == [.download])

        let inUse = CityDownloadRow.published(
            city: sf, state: .installedCurrent(installedVersion: sf.version), isActive: true,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(inUse.affordances == [.inUseLabel, .remove])
        #expect(inUse.stateLine == "Installed · s14-r2026-07-31")

        let updatable = CityDownloadRow.published(
            city: sf, state: .updateAvailable(installedVersion: "s14-r2026-06-01"), isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(updatable.affordances == [.update, .remove])
        #expect(updatable.stateLine == "Update available · s14-r2026-06-01 installed")

        // A promise no button can keep gets no button (ruling §3).
        let refused = CityDownloadRow.published(
            city: sf, state: .needsNewerApp(installedVersion: nil), isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(refused.affordances.isEmpty)
        #expect(refused.stateLine == "Needs a newer app")
        #expect(refused.detailLine == "This city's data is a newer format than this app can read.")

        // …but an older compatible install keeps its affordances; only the update is refused.
        let refusedButInstalled = CityDownloadRow.published(
            city: sf, state: .needsNewerApp(installedVersion: "s14-r2026-06-01"), isActive: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(refusedButInstalled.affordances == [.use, .remove])

        // Offline: disk facts alone, no-network affordances intact.
        let offline = CityDownloadRow.installedOffline(
            CityLibrary.InstalledCity(
                id: "sf", version: "s14-r2026-07-31",
                fileURL: URL(fileURLWithPath: "/x"), bytes: 1
            ),
            isActive: true
        )
        #expect(offline.affordances == [.inUseLabel, .remove])
    }
}
