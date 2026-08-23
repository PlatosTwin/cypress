import Foundation
import SQLite3

/// Downloaded city files on disk: where they live, how one becomes the attached inventory, and
/// the checks that stand between a byte-verified download and an `ATTACH`.
///
/// **Disk is the record.** The layout mirrors the bucket's immutable scheme (R37.2) under
/// Application Support — `cities/<id>/<version>/<id>.sqlite` — and "what is installed" is answered
/// by looking, never by a parallel table that could disagree with the files. The one fact the
/// layout cannot carry is *which* inventory the reader chose to attach, and that is a marker file
/// (`active-city`) holding a city id; absent means the built-in bundle. No schema, no migration.
///
/// A value type over a root URL rather than a service: every method is straight `FileManager`
/// work, and handing tests their own root in a temp directory is the whole test story.
public struct CityLibrary: Sendable {

    /// The library root. Default: `Application Support/Cypress/cities/`, beside the writable
    /// database `CypressStore.defaultDatabaseURL()` places — same volume, which is what makes the
    /// staging→final move an atomic rename.
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The app's library. Throws only if Application Support itself cannot be created, which is
    /// the same failure `CypressStore.defaultDatabaseURL()` would already have surfaced.
    public static func `default`() throws -> CityLibrary {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return CityLibrary(
            rootURL: base
                .appendingPathComponent("Cypress", isDirectory: true)
                .appendingPathComponent("cities", isDirectory: true)
        )
    }

    // MARK: - Layout

    /// `<root>/<id>/<version>/<id>.sqlite` — the bucket path, mirrored (R37.2).
    public func fileURL(id: String, version: String) -> URL {
        rootURL
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("\(id).sqlite", isDirectory: false)
    }

    /// Where verified downloads wait for their rename. Inside the root so the move never crosses
    /// a volume; dot-named so it can never read as an installed city.
    public var stagingURL: URL {
        rootURL.appendingPathComponent(".staging", isDirectory: true)
    }

    private var activeMarkerURL: URL {
        rootURL.appendingPathComponent("active-city", isDirectory: false)
    }

    // MARK: - What is installed

    public struct InstalledCity: Equatable, Sendable {
        public let id: String
        public let version: String
        public let fileURL: URL
        public let bytes: Int64
        /// The city's own name, read out of the installed file (`dim_city.display_name`, s16+).
        /// Nil for a file too old to carry one — the caller then falls back to the id, which is
        /// what every offline row said before this existed.
        public let displayName: String?
        /// The shipped extent's word, read out of the same file's `seed_meta`. Nil for full
        /// coverage — the same meaning the manifest's `coverage` field carries.
        public let coverage: String?
        /// The record date this copy actually holds (`seed_meta.publish_content_rev`), read from the
        /// file rather than parsed out of the directory name it sits in.
        ///
        /// **This is what makes "is there an update?" answerable without splitting a version
        /// string.** `CityManifest.City.version`'s own comment forbids the split, and R60 made the
        /// string end in a `build_id` that is a hash of the whole 108 MB *source seed* — so a
        /// re-publish changes every city's version while changing no city's data. See
        /// `CityInstallState`.
        public let contentRev: String?
        /// The seed generation stamped into this copy (`seed_meta.publish_schema_version`), for the
        /// half of the same comparison `contentRev` cannot make on its own.
        public let publishedSchemaVersion: Int?

        public init(
            id: String,
            version: String,
            fileURL: URL,
            bytes: Int64,
            displayName: String? = nil,
            coverage: String? = nil,
            contentRev: String? = nil,
            publishedSchemaVersion: Int? = nil
        ) {
            self.id = id
            self.version = version
            self.fileURL = fileURL
            self.bytes = bytes
            self.displayName = displayName
            self.coverage = coverage
            self.contentRev = contentRev
            self.publishedSchemaVersion = publishedSchemaVersion
        }
    }

    /// The installed version of one city, or nil. One version directory at most survives any
    /// completed operation; if an interrupted update ever leaves two, the newer version string
    /// wins deterministically (R37 versions sort correctly: same schema ⇒ date order, and a
    /// bigger schema number is the one this build was updated to want).
    public func installedVersion(of id: String) -> String? {
        installedVersions(of: id).last
    }

    private func installedVersions(of id: String) -> [String] {
        let cityDir = rootURL.appendingPathComponent(id, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cityDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { entry in
                FileManager.default.fileExists(
                    atPath: entry.appendingPathComponent("\(id).sqlite").path
                )
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// Every city on disk, by id. Rendered directly when the manifest is unreachable — the
    /// offline screen is disk facts alone.
    ///
    /// **The display name is one of those disk facts now, for a whole-city pack.** Since s16 every
    /// published city file carries `dim_city.display_name`, narrowed to that city's single row by
    /// `Tools/publish_cities.py`, so reading it here costs one read-only open per installed city
    /// and stops an offline reader being shown `us-ca-sj` where their own phone says `San Jose`.
    /// The open is bounded — this method is called on screen load and after an install or a
    /// remove, never per render — and a file that cannot answer simply has no name.
    ///
    /// **A borough pack is the exception, and it is stated rather than papered over.** The name
    /// inside `us-ny-nyc-manhattan.sqlite` is `New York City` — the *city*'s name, because the file
    /// carries the city's `dim_city` row and nothing anywhere in it says "Manhattan". Only the
    /// manifest knows a pack's own display name, and R43 §3 forbids persisting the manifest. So a
    /// borough keeps the id as its offline title: five rows all reading `New York City`, one per
    /// borough, would be a worse answer than five ids a reader can tell apart. `displayName` is
    /// therefore set only when the file's row describes this pack (`packID == id`, or an id space
    /// that equals it).
    public func installedCities() -> [InstalledCity] {
        guard let ids = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return ids
            .compactMap { dir -> InstalledCity? in
                // A stray file at the root (the marker itself) has no version directory under it
                // and falls out here; only real installs survive.
                let id = dir.lastPathComponent
                guard let version = installedVersion(of: id) else { return nil }
                let url = fileURL(id: id, version: version)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                // **`id` here is the PACK id — the install directory — and the rows a city file
                // holds are keyed by ID SPACE.** For a whole-city pack those are the same string
                // (`sf`), which is why matching on the id looked right and worked for a year; for a
                // borough they are not (`us-ny-nyc-manhattan` against `us-ny-nyc`), so that match
                // found nothing and every borough's receipt came back nil — see
                // `SeedCities.City.packID` for what that cost.
                //
                // Resolved in the order of what each answer is worth: the pack's own stamped id
                // first, then an id space that happens to equal it, then — since R37.3 narrows every
                // published file to exactly one id space — the single row a one-space file has,
                // which is what a pack published before `publish_pack_id` existed can offer. A file
                // holding two id spaces (the fused bundled seed) matches none of the three and is
                // left alone, because there is no single row to attribute the pack to.
                let cities = SeedCities.read(fileAt: url)
                let named = cities.first { $0.packID == id }
                    ?? cities.first { $0.id == id }
                    ?? (cities.count == 1 ? cities.first : nil)
                // The name is the *city*'s; only a pack that is its whole city may wear it, which is
                // exactly the case where the id space equals the pack id.
                let namesThisPack = named?.id == id
                return InstalledCity(
                    id: id, version: version, fileURL: url, bytes: bytes,
                    displayName: namesThisPack ? named?.displayName : nil,
                    coverage: named?.coverage,
                    contentRev: named?.contentRev,
                    publishedSchemaVersion: named?.publishedSchemaVersion
                )
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Install / remove

    /// Moves a **verified** temp file into the immutable layout and prunes other versions of the
    /// same city. The caller has already checked sha256 and byte count (`CityDownloader`); this
    /// method's contract is only atomicity: the file appears at its final path complete or not at
    /// all, because it arrives by rename, and the old version outlives the new one's arrival —
    /// the same new-then-prune discipline as the bucket's "files upload before the manifest".
    @discardableResult
    public func install(verifiedFileAt tempURL: URL, id: String, version: String) throws -> URL {
        let destination = fileURL(id: id, version: version)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            // R37.2: a version is immutable, and the caller verified this file against the same
            // manifest entry — replacing is idempotent, not destructive.
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Only now is any older version pruned.
        for stale in installedVersions(of: id) where stale != version {
            try? FileManager.default.removeItem(
                at: rootURL.appendingPathComponent(id, isDirectory: true)
                    .appendingPathComponent(stale, isDirectory: true)
            )
        }
        return destination
    }

    /// Deletes a city entirely. Deactivates it first, so a reader of the marker can never resolve
    /// to a path being deleted out from under it.
    public func remove(id: String) throws {
        if activeCityID() == id {
            try deactivate()
        }
        let cityDir = rootURL.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: cityDir.path) {
            try FileManager.default.removeItem(at: cityDir)
        }
    }

    // MARK: - The active choice

    /// The city the reader chose to attach, or nil for the built-in bundle.
    public func activeCityID() -> String? {
        guard let raw = try? String(contentsOf: activeMarkerURL, encoding: .utf8) else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    public func activate(id: String) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try id.write(to: activeMarkerURL, atomically: true, encoding: .utf8)
    }

    public func deactivate() throws {
        if FileManager.default.fileExists(atPath: activeMarkerURL.path) {
            try FileManager.default.removeItem(at: activeMarkerURL)
        }
    }

    // MARK: - Boot resolution

    /// Resolves the marker to a seed URL this build may attach, validating the file first. A
    /// dangling marker (removed city), an unreadable file, or a generation from the future all
    /// clear the marker and return nil — the caller attaches the bundle and the app launches;
    /// the Cities screen then shows the city as installed-but-not-in-use, which is the truth.
    public func validatedActiveSeedURL() -> URL? {
        guard let id = activeCityID() else { return nil }
        guard let version = installedVersion(of: id) else {
            try? deactivate()
            return nil
        }
        let url = fileURL(id: id, version: version)
        do {
            try Self.validateCityFile(at: url)
            return url
        } catch {
            try? deactivate()
            return nil
        }
    }

    public enum ValidationError: Error, CustomStringConvertible {
        case schemaTooNew(fileVersion: Int, buildKnows: Int)

        public var description: String {
            switch self {
            case let .schemaTooNew(fileVersion, buildKnows):
                // The fossil-install lesson, pointed forward: a generation from the future is
                // refused before ATTACH, never after.
                return "city file is schema generation \(fileVersion) but this build knows up to \(buildKnows)"
            }
        }
    }

    /// Opens the file read-only on a throwaway connection and asks it to testify for itself:
    /// the seed shape must introspect (`SeedSchema` — same check the attach path runs), and the
    /// file's own `publish_schema_version` must not exceed what this build reads. The manifest
    /// already claimed a generation, but the manifest is a rewritable object on a remote bucket;
    /// the file is what actually gets attached, so the file is what gets believed.
    public static func validateCityFile(at url: URL) throws {
        let connection = try SQLiteConnection(
            path: SeedDatabase.readOnlyURI(for: url),
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        )
        _ = try SeedSchema.introspect(connection, schema: "main")

        // `seed_meta` is optional in an old bundled seed but never in a published city file —
        // `publish_cities.py` always writes `publish_schema_version`. Its absence reads as
        // generation 0: an ancient file, attachable, just never preferable.
        let statement = try connection.prepare(
            "SELECT value FROM seed_meta WHERE key = 'publish_schema_version'"
        )
        defer { statement.finalize() }
        let published = try statement.fetchOne { try $0.string("value") }.flatMap(Int.init) ?? 0
        guard published <= SeedDatabase.newestKnownSchemaVersion else {
            throw ValidationError.schemaTooNew(
                fileVersion: published,
                buildKnows: SeedDatabase.newestKnownSchemaVersion
            )
        }
    }
}
