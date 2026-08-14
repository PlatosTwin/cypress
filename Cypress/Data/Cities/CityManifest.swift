import Foundation

/// The published city catalog — `manifest.json` at the bucket root, decoded.
///
/// The contract is R37's (see RULINGS R43 for the app side): versioned
/// per-city SQLite files at immutable paths `cities/<id>/<version>/<id>.sqlite`, described by one
/// manifest that is the only object ever rewritten in place. `Tools/publish_cities.py` writes it;
/// this type is the reader.
///
/// Decoding is strict about the one thing that can break a reader — `manifest_format` — and
/// tolerant of everything additive, because R37.4 explicitly reserves the right to add keys
/// (compression, for one) without bumping the format.
public struct CityManifest: Equatable, Sendable {

    /// The envelope format this reader understands. `Tools/publish_cities.py MANIFEST_FORMAT`.
    public static let knownFormat = 1

    public let format: Int
    /// Cities in manifest order — the publisher's order is the display order (RULINGS R43 §2).
    public let cities: [City]

    /// One published city file, as the manifest describes it.
    public struct City: Equatable, Sendable, Decodable {
        /// The id space (`sf`, `us-ca-sj`) — doubles as the path component and the install key.
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
        /// **ERRATA E209 shape B3, E213 and E214 each record that this manifest "carries no center
        /// or bbox to derive one from" and call the fix a wider ticket. That premise was false of
        /// the artifact and true only of this type** — `publish_cities.py` has emitted `bbox` and
        /// `centroid` since #156. The blocker was two `Decodable` properties.
        public let bbox: BoundingBox?
        /// The city file's centroid, as the publisher measured it. See `bbox`.
        public let centroid: Coordinate?
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
                return "manifest_format \(format), but this build reads format \(CityManifest.knownFormat)"
            case let .malformed(detail):
                return "manifest did not decode: \(detail)"
            }
        }
    }

    /// Decodes `manifest.json` bytes, refusing unknown formats before looking at anything else.
    public static func decode(_ data: Data) throws -> CityManifest {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw DecodeError.malformed(String(describing: error))
        }
        guard envelope.manifestFormat == knownFormat else {
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
