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
        /// Relative to the app's configured base URL, never to `base_url_hint`.
        public let path: String
        public let bytes: Int64
        /// Lowercase hex sha256 of the file at `path`; verified before a byte of it is kept.
        public let sha256: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case coverage
            case treeCount = "tree_count"
            case schemaVersion = "schema_version"
            case version
            case path
            case bytes
            case sha256
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
