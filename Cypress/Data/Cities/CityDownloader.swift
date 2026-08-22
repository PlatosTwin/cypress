import CryptoKit
import Foundation

/// Fetches the published manifest and downloads city files, verifying every byte before a file is
/// allowed anywhere near the installed layout.
///
/// `Data` imports CryptoKit here the way it imports ImageIO and SQLite3 elsewhere: a system
/// library the layer's own job is defined in terms of (ARCHITECTURE §2's direction rule is about
/// UI frameworks and `Features`, not about the platform). The job in question is R37's contract —
/// a downloaded file is *the manifest entry's* file only if its sha256 says so.
///
/// **The base URL is app configuration** (R37.4): the manifest's `base_url_hint` is never read,
/// because a rewritable remote object that named its own download host could redirect every
/// future download. And every probe of the bucket is a GET — Tigris has served HEAD 200 beside
/// GET 403 on the same key (server/README.md), so a HEAD is a false green by construction.
public struct CityDownloader: Sendable {

    /// The one host the app downloads from — the bucket's dedicated public domain, the only
    /// domain Tigris serves anonymous GETs on (server/README.md, measured 2026-08-01).
    public static let defaultBaseURL = URL(string: "https://cypress-cities.t3.tigrisbucket.io")!

    public let baseURL: URL
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: overridable so unit tests serve fixture files from disk (`file://` base);
    ///     the network is never a test dependency.
    ///   - session: `.shared` in the app; injectable for the same reason as `baseURL`.
    public init(baseURL: URL = CityDownloader.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public enum DownloadError: Error, Equatable, CustomStringConvertible {
        case unacceptableStatus(Int)
        /// The bytes on disk are not the bytes the manifest promised. The temp file is already
        /// gone by the time this is thrown; nothing else changed.
        case checksumMismatch(expected: String, got: String)
        case sizeMismatch(expected: Int64, got: Int64)

        public var description: String {
            switch self {
            case let .unacceptableStatus(code):
                return "the server answered \(code)"
            case let .checksumMismatch(expected, got):
                return "sha256 mismatch: manifest says \(expected), file is \(got)"
            case let .sizeMismatch(expected, got):
                return "size mismatch: manifest says \(expected) bytes, file is \(got)"
            }
        }
    }

    // MARK: - Manifest

    /// The request for `<base>/manifest.json`, built so no cache anywhere can answer it.
    ///
    /// **The manifest is the one file whose freshness is load-bearing** (#199). Every city file
    /// lives at an immutable versioned path and is verified by sha256, so a stale *city* is
    /// impossible — the manifest is the only mutable object in R37's design, and it is what says
    /// which versions exist. A reader holding yesterday's manifest is internally consistent and
    /// wrong: it verifies the old file perfectly, downloads nothing, and reports no error, so a
    /// republished city simply never arrives and nothing on the phone ever says why.
    ///
    /// Measured on the public domain, 2026-08-03: minutes after a republish a bare GET still
    /// returned the PREVIOUS manifest while the same URL with a unique query returned the new one.
    /// So the query is the part that is actually doing the work here; `cachePolicy` and the header
    /// address URLSession's own store and any well-behaved intermediary, and neither was enough on
    /// its own.
    ///
    /// A UUID rather than a timestamp: two calls in the same millisecond would share a
    /// cache-buster, and this needs no clock to be correct.
    ///
    /// **`file://` bases are left alone.** Unit tests serve fixture manifests from disk, and a
    /// query string on a file URL does not identify a file — appending one would break every test
    /// that uses this path, in the name of defeating a cache that cannot exist there.
    /// The object this build asks for first — the format-2 catalog, which is the only one that
    /// lists sub-city packs. `Tools/publish_cities.py MANIFEST_V2_NAME`.
    public static let manifestName = "manifest-v2.json"

    /// The format-1 catalog, still published beside it for RULING D8's transition window, and the
    /// name every build before this one hard-codes. `Tools/publish_cities.py MANIFEST_V1_NAME`.
    ///
    /// **Fetched only as a fallback, and the fallback is what makes the cutover safe in the other
    /// direction.** D8 protects an old app against a new bucket; nothing in it protects a new app
    /// against an *old* bucket, and that is the ordinary state of things between shipping a build
    /// and running the next publish. Without this, every install of this build would show
    /// "Couldn't check what's available" until someone remembered to republish.
    public static let legacyManifestName = "manifest.json"

    static func manifestRequest(base: URL, name: String = manifestName) -> URLRequest {
        let url = base.appendingPathComponent(name)
        var request = URLRequest(url: url)
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return request }
        components.queryItems = (components.queryItems ?? [])
            + [URLQueryItem(name: "cb", value: UUID().uuidString)]
        request = URLRequest(url: components.url ?? url)
        // `.reloadIgnoringLocalAndRemoteCacheData` is documented as unimplemented; this is the
        // strongest policy that is actually honored.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    /// `GET <base>/manifest-v2.json`, decoded strictly (`CityManifest.decode`), falling back to
    /// `<base>/manifest.json` when the bucket has not been republished since this build shipped.
    ///
    /// **The fallback is on "the object is not there", and on nothing else.** A 404 (or a missing
    /// `file://` fixture) means the publisher has not run since format 2 landed, which is a
    /// transitional fact about the bucket and is recoverable. A 500, a timeout, a truncated body
    /// or a manifest that does not decode are all facts about *this fetch*, and retrying them
    /// against a different path would turn one honest error into a second confusing one — and
    /// would quietly downgrade a reader to the whole-cities-only catalog on a transient blip. So
    /// only `.unacceptableStatus(404)` and a file-not-found `URLError` reach the second attempt;
    /// everything else propagates from the first.
    public func fetchManifest() async throws -> CityManifest {
        do {
            return try await fetchManifest(named: Self.manifestName)
        } catch let error where Self.isNotFound(error) {
            return try await fetchManifest(named: Self.legacyManifestName)
        }
    }

    private func fetchManifest(named name: String) async throws -> CityManifest {
        let (data, response) = try await session.data(
            for: Self.manifestRequest(base: baseURL, name: name))
        try Self.checkStatus(response)
        return try CityManifest.decode(data)
    }

    /// Whether an error means "that object is not published", the one condition the manifest
    /// fallback above acts on.
    ///
    /// Two shapes because the two transports report absence differently and both are real: the
    /// bucket answers `404`, and a `file://` base — which is how every unit test serves a fixture
    /// — throws `URLError` instead of producing a response to check.
    static func isNotFound(_ error: any Error) -> Bool {
        if case DownloadError.unacceptableStatus(404) = error { return true }
        if let urlError = error as? URLError {
            return urlError.code == .fileDoesNotExist || urlError.code == .resourceUnavailable
        }
        // `Data(contentsOf:)`-style absence on a file URL surfaces as a plain Cocoa error.
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSFileReadNoSuchFileError
    }

    // MARK: - City files

    /// Downloads one city file to a caller-owned staging directory and verifies it against the
    /// manifest entry. On any failure the partial or impostor file is deleted before the error
    /// propagates — a file that this method did not return cannot exist on disk afterwards.
    ///
    /// - Returns: the URL of the verified file inside `stagingDirectory`, ready for
    ///   `CityLibrary.install(verifiedFileAt:id:version:)`'s atomic rename.
    public func downloadCity(
        _ city: CityManifest.City,
        to stagingDirectory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let destination = stagingDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(city.id).sqlite", isDirectory: false)

        let source = baseURL.appendingPathComponent(city.path)
        do {
            let (bytes, response) = try await session.bytes(from: source)
            try Self.checkStatus(response)

            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }

            var hasher = SHA256()
            var written: Int64 = 0
            var buffer = Data(capacity: Self.chunkSize)
            var lastReportedPercent = -1

            func flush() throws {
                guard !buffer.isEmpty else { return }
                try handle.write(contentsOf: buffer)
                hasher.update(data: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if let progress, city.bytes > 0 {
                    let fraction = min(1, Double(written) / Double(city.bytes))
                    let percent = Int(fraction * 100)
                    if percent != lastReportedPercent {
                        lastReportedPercent = percent
                        progress(fraction)
                    }
                }
            }

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= Self.chunkSize { try flush() }
            }
            try flush()
            try handle.close()

            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard written == city.bytes else {
                throw DownloadError.sizeMismatch(expected: city.bytes, got: written)
            }
            guard digest == city.sha256.lowercased() else {
                throw DownloadError.checksumMismatch(expected: city.sha256.lowercased(), got: digest)
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// 512 KiB: big enough that hashing and writing dominate the per-chunk overhead, small enough
    /// that progress moves visibly on an 80 MB file.
    private static let chunkSize = 512 * 1024

    /// `file://` fixtures return no HTTPURLResponse; only a real HTTP answer is status-checked.
    private static func checkStatus(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.unacceptableStatus(http.statusCode)
        }
    }
}
