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

    /// The request for `<base>/<name>`, built so no cache anywhere can answer it.
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
    /// The object this build asks for first — the format-2 catalog, and since format 1 retired
    /// the only one that is published at all. `Tools/publish_cities.py MANIFEST_V2_NAME`.
    public static let manifestName = "manifest-v2.json"

    /// The format-1 catalog, and the name every build before this one hard-codes.
    /// **No longer published — frozen.** Format 1 retired on 2026-08-23; the publisher's
    /// `RETIRED_MANIFEST_V1_NAME` now names an object it only ever checks for the *absence* of.
    /// The copy in the bucket stays exactly as the 2026-08-23 publish left it, because deleting
    /// it would take the Cities screen offline for every build that hard-codes this name. It is
    /// stale but true: the city packs it lists are immutable and still served.
    ///
    /// **Still fetched as a fallback, and retirement did not make that dead code.** D8 protected
    /// an old app against a new bucket; this is the other direction — a new app against a bucket
    /// carrying no format-2 object. That was the ordinary state between shipping this build and
    /// running the next publish, and it no longer arises on the live bucket, where
    /// `manifest-v2.json` has been present since 2026-08-23. What the fallback still covers is
    /// every base URL that is *not* the live bucket: an archived mirror, a fixture directory, a
    /// future bucket populated in some other order. It costs one request on a path that already
    /// failed, and dropping it would buy nothing while risking a dead Cities screen in exactly
    /// the cases nobody watches.
    ///
    /// `CityManifest.knownFormats` keeps `1` for the same reason: what retired is *writing* a
    /// format-1 manifest, never *reading* one.
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
    /// `<base>/manifest.json` when that base serves no format-2 object at all — see
    /// `legacyManifestName` for what that covers now that format 1 is retired and the live
    /// bucket always carries a format-2 catalog.
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
    /// Three shapes, because the transports report absence differently and all three are real.
    ///
    /// **`404`** is the ordinary answer.
    ///
    /// **`403` is the same fact on this bucket, and leaving it out made the fallback dead code on
    /// the only host the app actually talks to.** This file's own header records the measurement:
    /// *"Tigris has served HEAD 200 beside GET 403 on the same key"*. An S3-compatible store
    /// answers `403` rather than `404` for a key the caller may not enumerate, so on the public
    /// domain a manifest that has simply never been published can arrive as `403` — and a fallback
    /// that only watched for `404` would never fire, which is precisely the transition it exists
    /// to cover.
    ///
    /// **Why this does not mask a genuine authorization failure**, which is the real objection and
    /// deserves an answer rather than a shrug:
    ///
    /// 1. *There is nothing to authorize.* Every request from this type is anonymous — the app
    ///    holds no bucket credential and sends none (`defaultBaseURL` is the public domain, and
    ///    R37.4 forbids reading a host out of the manifest). For an unauthenticated reader `403`
    ///    and `404` carry the same information: you cannot have this object. There is no
    ///    credential that could be wrong, so there is no auth failure to mask.
    /// 2. *A real lockout still surfaces.* If the bucket were misconfigured to private, **every**
    ///    object would answer `403`, including the legacy manifest this falls back to — so the
    ///    second fetch fails too and its error propagates. The fallback retries once; it never
    ///    swallows. The failure a reader sees is the legacy path's, which is the correct and more
    ///    informative one, because that is the object every shipped build depends on.
    /// 3. *It is scoped to the manifest.* `downloadCity` does not consult this; a `403` on a city
    ///    file is a hard failure there, as it should be — that object's absence is not a
    ///    recoverable transitional state, it is a manifest that lied.
    ///
    /// **`URLError` / Cocoa file errors** cover the `file://` base every unit test serves fixtures
    /// from, which throws instead of producing a response to check.
    static func isNotFound(_ error: any Error) -> Bool {
        if case let DownloadError.unacceptableStatus(code) = error {
            return code == 404 || code == 403
        }
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
