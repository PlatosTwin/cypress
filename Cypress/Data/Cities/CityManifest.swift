import Foundation

/// The published city catalog at the bucket root, decoded.
///
/// **Two objects in the bucket, only one of them still written.** `manifest-v2.json` is the
/// format-2 catalog this build asks for, the only one that lists sub-city packs, and since format
/// 1 retired on 2026-08-23 the only one any publish produces. `manifest.json` is frozen at the
/// bytes that publish left, so an install too old to know the new name keeps a working Cities
/// screen. `CityDownloader` picks between them; this type decodes either.
///
/// The contract is R37's (see RULINGS R43 for the app side): versioned
/// per-city SQLite files at immutable paths `cities/<id>/<version>/<id>.sqlite`, described by one
/// manifest that is the only object ever rewritten in place — `manifest-v2.json`, now that the
/// format-1 object is never rewritten at all. `Tools/publish_cities.py` writes it; this type is
/// the reader.
///
/// Decoding is strict about the one thing that can break a reader — `manifest_format` — and
/// tolerant of everything additive, because R37.4 explicitly reserves the right to add keys
/// (compression, for one) without bumping the format.
public struct CityManifest: Equatable, Sendable {

    /// The newest envelope format this build understands — the counterpart of
    /// `Tools/publish_cities.py MANIFEST_FORMAT`, which is the format the *publisher* writes.
    ///
    /// **The newest, not the only** — see `knownFormats`. Nothing on this side writes a manifest,
    /// so this is "the format this reader prefers and asks for first"
    /// (`CityDownloader.manifestName`), never "the format this build emits".
    public static let knownFormat = 2

    /// **Every** envelope format this build reads, which is more than one.
    ///
    /// **Retiring format 1 did not remove `1` from this set, and the distinction is the whole
    /// point.** What retired on 2026-08-23 is *writing* a format-1 manifest; *reading* one is a
    /// property of this reader, and the object it would read is still sitting in the bucket,
    /// frozen and permanent. A build that refused it would break against that object, against
    /// every archived mirror of it, and against every test fixture written before format 2 — in
    /// exchange for nothing.
    ///
    /// Format 1 is accepted as a deliberate softening of the original rule rather than a hole in
    /// it. **Note that R37.4 does not license this**: R37.4 reserves the right to add *keys*
    /// without bumping the format, which is why `region` needed no bump on top of the one the
    /// unit's changed meaning already required. Reading two formats is a separate decision, taken
    /// for the dual-publish window RULING D8 set. The rule that matters — *never guess at a format
    /// you do not know* — is unchanged: an unknown format is still refused outright, before
    /// anything else is read. What changed is that 1 is no longer unknown.
    ///
    /// What a format-1 manifest costs a format-2 reader is exactly one thing: `region` is absent,
    /// so `City.region` is nil and every entry is a whole city. That is the truth about a
    /// format-1 manifest — every one ever published listed `city`-level packs only — so the nil
    /// is not a missing value to be defaulted, it is the answer.
    public static let knownFormats: Set<Int> = [1, 2]

    public let format: Int
    /// Cities in manifest order — the publisher's order is the display order (RULINGS R43 §2).
    public let cities: [City]

    /// What kind of unit one published pack is, and which city it belongs to (`manifest_format`
    /// 2). Absent from a format-1 manifest, where every entry is a whole city by construction.
    public struct Region: Equatable, Sendable, Decodable {
        /// `city`, `borough`, or `extent`. **A string, deliberately not an enum**: this is the
        /// publisher's vocabulary, it may gain a member without a format bump (R37.4 covers an
        /// additive value the same way it covers an additive key), and a non-exhaustive Swift
        /// enum would turn that into a decode failure that takes the whole catalog offline. A
        /// reader that does not recognize a level shows the pack by the names it carries, which
        /// is the same thing it does today. (R37.4 reserves additive *keys*; reading an
        /// unrecognized *value* the same tolerant way is this layer's own choice, not R37.4's
        /// wording.)
        public let level: String
        /// The id space of the city this pack belongs to (`sf`, `us-ny-nyc`). Equal to the
        /// entry's own `id` for a one-region city; different for a borough, and that difference
        /// is the only way to ask which city a borough is part of.
        public let parentCity: String
        /// The parent city's reader-facing name — a civic fact entered at publish, never derived
        /// on device, the same rule as `City.displayName`.
        public let parentCityDisplayName: String

        public init(level: String, parentCity: String, parentCityDisplayName: String) {
            self.level = level
            self.parentCity = parentCity
            self.parentCityDisplayName = parentCityDisplayName
        }

        enum CodingKeys: String, CodingKey {
            case level
            case parentCity = "parent_city"
            case parentCityDisplayName = "parent_city_display_name"
        }
    }

    /// One published city file, as the manifest describes it.
    public struct City: Equatable, Sendable, Decodable {
        /// The published pack's id (`sf`, `us-ca-sj`, and a borough under format 2) — doubles as
        /// the path component and the install key.
        ///
        /// **Was the id space and now is the pack id**, which is the same string for every pack
        /// published so far and stops being so when a city publishes more than one region. The
        /// id space is still available, as `region?.parentCity`.
        public let id: String
        /// A civic fact entered by hand at publish (`DISPLAY_NAMES`), never derived on device.
        public let displayName: String
        /// `"full"`, or the shipped extent's name (San Jose ships `"downtown"`).
        public let coverage: String
        public let treeCount: Int
        /// The seed schema generation (R37.1). Compared against
        /// `SeedDatabase.newestKnownSchemaVersion` — see `CityInstallState`.
        public let schemaVersion: Int
        /// `s<schema_version>-r<content_rev>-<build_id>` (R37.2 as amended by `RULINGS R60`;
        /// `build_id` is the first 8 hex of the source seed's sha256).
        ///
        /// **Read as an opaque string — update detection is equality, and nothing here parses it.**
        /// That is what made R60's grammar change safe on this side, and it is the property to
        /// preserve: the day something splits this on `-`, a publisher change becomes a client bug.
        public let version: String
        /// The record date this city's data was snapshotted at — the `r` segment of `version`,
        /// carried as its own key so nothing has to parse the version string to get it.
        ///
        /// **This key is not new; decoding it is.** `Tools/publish_cities.py` has emitted
        /// `content_rev` for every city since #156, and it is in the live manifest right now. It is
        /// the one comparison a bundled city can make about itself (R60's `build_id` is a hash of
        /// the whole 108 MB source seed, so the bundle cannot compute a version string) — see
        /// `CityInstallState.bundled`.
        ///
        /// Optional because a reader that refuses to decode a manifest missing an additive key
        /// would take the whole Cities screen offline over it; R37.4's tolerance cuts both ways.
        public let contentRev: String?
        /// The city file's extent, as the publisher measured it. Decoded but not yet drawn:
        /// Stage 2's location-triggered offer is what needs it.
        ///
        /// **ERRATA E209 shape B3, E213 and E238 each record that this manifest "carries no center
        /// or bbox to derive one from" and call the fix a wider ticket. That premise was false of
        /// the artifact and true only of this type** — `publish_cities.py` has emitted `bbox` and
        /// `centroid` since #156. The blocker was two `Decodable` properties.
        public let bbox: BoundingBox?
        /// The city file's centroid, as the publisher measured it. See `bbox`.
        public let centroid: Coordinate?
        /// What kind of unit this pack is and which city it belongs to (`manifest_format` 2).
        ///
        /// Optional for the same reason `contentRev` is, and one more. A format-1 manifest does
        /// not carry the key at all — and *nil is the correct answer there*, not a gap: every
        /// format-1 manifest ever published listed whole-city packs only, so "no region stated"
        /// and "this is a whole city" are the same fact. That set is closed now that format 1 is
        /// retired. A caller that needs the distinction has `CityManifest.format`.
        public let region: Region?
        /// Relative to the app's configured base URL, never to `base_url_hint`.
        public let path: String
        public let bytes: Int64
        /// Lowercase hex sha256 of the file at `path`; verified before a byte of it is kept.
        public let sha256: String

        /// Spelled out rather than synthesized so the additive keys can carry defaults: a call site
        /// that does not care about `bbox` should not have to say so.
        public init(
            id: String,
            displayName: String,
            coverage: String,
            treeCount: Int,
            schemaVersion: Int,
            version: String,
            contentRev: String? = nil,
            bbox: BoundingBox? = nil,
            centroid: Coordinate? = nil,
            region: Region? = nil,
            path: String,
            bytes: Int64,
            sha256: String
        ) {
            self.id = id
            self.displayName = displayName
            self.coverage = coverage
            self.treeCount = treeCount
            self.schemaVersion = schemaVersion
            self.version = version
            self.contentRev = contentRev
            self.bbox = bbox
            self.centroid = centroid
            self.region = region
            self.path = path
            self.bytes = bytes
            self.sha256 = sha256
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(String.self, forKey: .id),
                displayName: try container.decode(String.self, forKey: .displayName),
                coverage: try container.decode(String.self, forKey: .coverage),
                treeCount: try container.decode(Int.self, forKey: .treeCount),
                schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
                version: try container.decode(String.self, forKey: .version),
                contentRev: try container.decodeIfPresent(String.self, forKey: .contentRev),
                bbox: try container.decodeIfPresent(BoundingBoxJSON.self, forKey: .bbox)?.value,
                centroid: try container.decodeIfPresent(CentroidJSON.self, forKey: .centroid)?.value,
                region: try container.decodeIfPresent(Region.self, forKey: .region),
                path: try container.decode(String.self, forKey: .path),
                bytes: try container.decode(Int64.self, forKey: .bytes),
                sha256: try container.decode(String.self, forKey: .sha256)
            )
        }

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case coverage
            case treeCount = "tree_count"
            case schemaVersion = "schema_version"
            case version
            case contentRev = "content_rev"
            case bbox
            case centroid
            case region
            case path
            case bytes
            case sha256
        }

        /// `{"min_lat": …, "max_lat": …, "min_lon": …, "max_lon": …}` — the publisher's spelling,
        /// mapped onto the `BoundingBox` the rest of the app already speaks.
        private struct BoundingBoxJSON: Decodable {
            let minLat: Double
            let maxLat: Double
            let minLon: Double
            let maxLon: Double

            enum CodingKeys: String, CodingKey {
                case minLat = "min_lat"
                case maxLat = "max_lat"
                case minLon = "min_lon"
                case maxLon = "max_lon"
            }

            var value: BoundingBox {
                BoundingBox(
                    minLatitude: minLat, maxLatitude: maxLat,
                    minLongitude: minLon, maxLongitude: maxLon
                )
            }
        }

        /// `{"lat": …, "lon": …}` — the publisher's spelling for a point.
        private struct CentroidJSON: Decodable {
            let lat: Double
            let lon: Double

            var value: Coordinate { Coordinate(latitude: lat, longitude: lon) }
        }
    }

    public enum DecodeError: Error, Equatable, CustomStringConvertible {
        /// The manifest says a format this build does not read. Refused outright — guessing at a
        /// future format's meaning is how a reader silently mis-installs a file.
        case unknownFormat(Int)
        case malformed(String)

        public var description: String {
            switch self {
            case let .unknownFormat(format):
                let known = CityManifest.knownFormats.sorted()
                    .map(String.init).joined(separator: ", ")
                return "manifest_format \(format), but this build reads format(s) \(known)"
            case let .malformed(detail):
                return "manifest did not decode: \(detail)"
            }
        }
    }

    /// Decodes a catalog's bytes — either published object — refusing unknown formats before
    /// looking at anything else.
    public static func decode(_ data: Data) throws -> CityManifest {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw DecodeError.malformed(String(describing: error))
        }
        guard knownFormats.contains(envelope.manifestFormat) else {
            throw DecodeError.unknownFormat(envelope.manifestFormat)
        }
        return CityManifest(format: envelope.manifestFormat, cities: envelope.cities)
    }

    /// The full envelope, private because `format` is checked once at the door and the rest of the
    /// file (source_seed, generated_at, base_url_hint) is deliberately not surfaced —
    /// `base_url_hint` in particular must never be read (R37.4).
    private struct Envelope: Decodable {
        let manifestFormat: Int
        let cities: [City]

        enum CodingKeys: String, CodingKey {
            case manifestFormat = "manifest_format"
            case cities
        }
    }
}
