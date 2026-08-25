import Foundation
import SQLite3

/// Downloaded city files on disk: where they live, which of them the union attaches, and the
/// checks that stand between a byte-verified download and an `ATTACH`.
///
/// **Disk is the record, and now it is the whole record.** The layout mirrors the bucket's
/// immutable scheme (R37.2) under Application Support — `cities/<id>/<version>/<id>.sqlite` — and
/// "what is installed" is answered by looking, never by a parallel table that could disagree with
/// the files.
///
/// The one fact the layout could not carry used to be *which* inventory the reader had chosen, and
/// that was a marker file holding a city id. **RULING D9 deleted the question**: every installed
/// city is attached, so what is on disk is what is drawn and there is nothing left for a marker to
/// say. No schema, no migration, and now no marker either.
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

    /// The retired `active-city` marker.
    ///
    /// **RULING D9 removed the choice this file recorded**, not merely the file: a downloaded city
    /// is in the union the moment it lands, `Remove` is what takes it out, and there is no third
    /// state for a marker to name. It is still deleted on sight, because a device upgrading from a
    /// build that wrote one would otherwise carry a stray file at the library root forever —
    /// `installedCities()` already steps over it, but a leftover nothing reads is a thing the next
    /// reader has to work out the meaning of.
    private var retiredActiveMarkerURL: URL {
        rootURL.appendingPathComponent("active-city", isDirectory: false)
    }

    /// Deletes the retired marker if this device has one. Idempotent, and never fatal.
    public func discardRetiredActiveMarker() {
        try? FileManager.default.removeItem(at: retiredActiveMarkerURL)
    }

    // MARK: - What is installed

    public struct InstalledCity: Equatable, Sendable {
        public let id: String
        public let version: String
        public let fileURL: URL
        public let bytes: Int64
        /// **The name of this pack**, read out of the installed file: `dim_region.display_name`
        /// for the pack's own row (s17+), falling back to the city's `dim_city.display_name`
        /// (s16+) where the pack *is* its whole city. Nil for a file too old to carry either —
        /// the caller then falls back to the id, which is what every offline row said before this
        /// existed.
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
    /// **A borough pack names itself, and it does not need the manifest to.** `dim_city` answers a
    /// different question — `us-ny-nyc-manhattan.sqlite` carries the *city*'s row, which reads
    /// `New York City`, and titling five borough rows with it would say the same thing five times.
    /// The pack's own name is in the same file: `dim_region.display_name`, keyed by the `pack_id`
    /// this directory is named after (`SeedCities.City.packDisplayName`). That is one indexed
    /// lookup, no manifest persisted (R43 §3), and no name derived from an id (DECISIONS
    /// constraint 15) — the publisher refuses a run whose manifest name disagrees with it, so it
    /// is the same string the catalog would have shown had it been reachable.
    ///
    /// This corrects a claim that stood here in review round 2: that *nothing anywhere in the file
    /// says "Manhattan"* and that *only the manifest knows a pack's display name*. Both were
    /// false — `dim_region` shipped with the s17 generation and is in every published pack — and
    /// the reader was shown `us-ny-nyc-manhattan` offline on the strength of them.
    ///
    /// **The fallback is what a pre-s17 pack gets**, and it is the previous rule unchanged: the
    /// city's name, but only where the file's row describes this pack (`packID == id`, or an id
    /// space that equals it), so a borough published before `dim_region` still keeps its id rather
    /// than wearing its city's name.
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
                // The pack's own name first. `dim_city`'s name is the *city*'s, so it is only an
                // acceptable second choice for a pack that is its whole city — exactly the case
                // where the id space equals the pack id.
                let namesThisPack = named?.id == id
                let title = named?.packDisplayName
                    ?? (namesThisPack ? named?.displayName : nil)
                return InstalledCity(
                    id: id, version: version, fileURL: url, bytes: bytes,
                    displayName: title,
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

    /// Deletes a city entirely.
    ///
    /// The caller re-boots the data layer afterwards (RULING D8), which is what detaches the file
    /// before it stops existing — `CityDownloadsModel.remove` calls `onInventoryChange()`
    /// unconditionally for exactly that reason.
    public func remove(id: String) throws {
        let cityDir = rootURL.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: cityDir.path) {
            try FileManager.default.removeItem(at: cityDir)
        }
    }

    // MARK: - Boot resolution

    /// **Every installed city this build can actually read**, as inventory files for the union.
    ///
    /// RULING D9: downloaded means in the union. There is no active choice to resolve any more —
    /// what is on disk is what is attached, and this is the whole of that rule.
    ///
    /// A file that does not validate is **left out and left alone**. It is not deleted: the reader
    /// paid for those bytes, the reason may be that this build is older than the file (a downgrade,
    /// or a pack published for a newer generation), and a later build may read it perfectly well.
    /// The Cities screen still lists it from `installedCities()`, so it can be removed deliberately.
    ///
    /// Ordered by id, so two launches over the same disk build the same union with the same arm
    /// ordinals — which is what makes a tree's union-wide id stable across a relaunch.
    public func installedInventoryFiles() -> [InventoryFile] {
        installedCities()
            .sorted { $0.id < $1.id }
            .compactMap { city in
                guard (try? Self.validateCityFile(at: city.fileURL)) != nil else { return nil }
                return InventoryFile(id: city.id, url: city.fileURL, isBundled: false)
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
