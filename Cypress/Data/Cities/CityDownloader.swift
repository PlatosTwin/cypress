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
    /// **The fallback is on "the object is not there", and on nothing else.** That the object is
    /// absent is a fact about the *bucket* and is recoverable; a 500, a timeout, a truncated body
    /// or a manifest that does not decode are all facts about *this fetch*, and retrying them
    /// against a different path would turn one honest error into a second confusing one — and
    /// would quietly downgrade a reader to the whole-cities-only catalog on a transient blip.
    ///
    /// `isNotFound` is the exact predicate, and absence has **four** spellings here, not one:
    /// `.unacceptableStatus(404)`, `.unacceptableStatus(403)`, a `URLError` of
    /// `.fileDoesNotExist` or `.resourceUnavailable`, and a Cocoa `NSFileReadNoSuchFileError`
    /// (how `file://` fixtures report a missing file). Everything else propagates from the first
    /// attempt.
    ///
    /// **`403` is deliberate and is the one that looks like a bug.** An S3-compatible store
    /// answers `403` rather than `404` for a key the caller may not enumerate, and Tigris has
    /// served `HEAD 200` beside `GET 403` on the same key (server/README.md) — so on the public
    /// domain, an object that was simply never published can arrive as `403`. A fallback watching
    /// `404` alone was dead code exactly where it was needed. It cannot mask an authorization
    /// failure because there is nothing to authorize: every request from this type is anonymous,
    /// so `403` and `404` carry the same information. And a genuinely private bucket still
    /// surfaces, because the fallback fetch answers `403` too and *its* error propagates. Ruled
    /// in the s17 round; see `isNotFound`'s own documentation for the full argument.
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
            // **A download task, not `session.bytes`, and this is a performance fix with a receipt.**
            // The previous body was `for try await byte in bytes` — `URLSession.AsyncBytes` is an
            // `AsyncSequence` of `UInt8`, so that loop performed one asynchronous iteration, one
            // `Data.append`, and one buffer-length check **per byte of the file**. On the smallest
            // NYC borough — Manhattan, 66,891,776 bytes — that is 66.9 million suspensions; on
            // Queens, 199 million. The 512 KiB buffer underneath made the *writes* efficient and did
            // nothing about the loop that filled it, which is why the size of the chunk was never
            // the thing that mattered.
            //
            // A tester reported it as *"Download is super slow"* (build 49, 2026-08-23) and, minutes
            // later, as *"Download fails if app closes or phone screen sleeps"* — the second is a
            // separate defect (see the note on `downloadCity`'s own doc) but the first made it far
            // easier to hit, because a transfer that should take a minute was taking long enough for
            // the screen to sleep underneath it.
            //
            // `URLSessionDownloadTask` streams to its own temp file at the transport's pace, with no
            // per-byte round trip through Swift concurrency at all. The verification that follows is
            // unchanged in substance and now reads the finished file in 512 KiB chunks; a file this
            // method does not return still cannot exist on disk afterwards.
            let response = try await downloadFile(
                from: source, to: destination, expectedBytes: city.bytes, progress: progress
            )
            try Self.checkStatus(response)

            let (written, digest) = try Self.verifiableFacts(ofFileAt: destination)
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

    /// Runs one `URLSessionDownloadTask` to completion, landing its bytes at `destination` and
    /// reporting progress along the way. Returns the response, unchecked — the caller decides what
    /// a status code means.
    ///
    /// **Three things here are load-bearing, and the first two were measured rather than reasoned
    /// about** (probe on iPhone 16 Pro, 3 MB body served in 64 KiB chunks by an in-process
    /// `URLProtocol`):
    ///
    /// 1. **`session.downloadTask(with:)` with a task-specific delegate, never
    ///    `session.download(from:delegate:)`.** The async convenience **does not deliver
    ///    `didWriteData` at all** — 0 calls, against 4 calls reaching the full byte count through
    ///    the classic task with the same delegate object, the same session and the same body. This
    ///    is what made the Cities screen's determinate ring (R43 §3) sit at 0 % for a whole 199 MB
    ///    transfer, and it is invisible to a `file://` fixture, which reports 0 callbacks even
    ///    through the healthy path.
    ///    `CityDownloadsFeedbackTests.progressIsReportedDuringTheTransfer` serves http in-process
    ///    for exactly that reason.
    /// 2. **A delegate created with a completion handler is never consulted.** A task made by
    ///    `downloadTask(with:completionHandler:)` measured 0 progress calls even with a
    ///    *session*-level delegate, so the continuation below is resumed from
    ///    `didCompleteWithError` rather than from a handler.
    /// 3. **The finished file is moved inside `didFinishDownloadingTo`, synchronously.** URLSession
    ///    deletes its temp file the moment that method returns; staging is where an unverified file
    ///    is allowed to be, and nothing here moves it into the installed layout.
    ///
    /// Cancellation is bridged both ways: cancelling the Swift task cancels the transfer, which
    /// surfaces as `URLError(.cancelled)` — see `isCancellation`.
    private func downloadFile(
        from source: URL,
        to destination: URL,
        expectedBytes: Int64,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URLResponse {
        let delegate = DownloadProgressDelegate(
            destination: destination, expectedBytes: expectedBytes, onProgress: progress
        )
        let task = session.downloadTask(with: source)
        task.delegate = delegate
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation, resuming: task)
            }
        } onCancel: {
            // **Not `task.cancel()` directly, and the difference is a hang.** `onCancel` runs
            // immediately when the enclosing Swift task is *already* cancelled — before the
            // operation body, so before the transfer is resumed. Cancelling a URLSession task that
            // was never resumed produces no completion callback at all, and the continuation is
            // never resumed either: the download sits at `Downloading…` forever, which is the state
            // pressing `Cancel` puts it in on a slow screen. Measured, in
            // `cancelDoesNotRenderFailure`. The delegate owns the flag, so `start` can decline to
            // resume a transfer that has already been called off.
            delegate.cancel(task)
        }
    }

    /// Whether an error means *the reader pressed Cancel*, in either of the two spellings this
    /// path can produce.
    ///
    /// **Both are reachable and only one of them used to be handled.** `CityDownloadsModel.download`
    /// caught `CancellationError` alone, which was correct while the body was `session.bytes` —
    /// that path throws Swift's own cancellation error out of the `AsyncSequence`. A
    /// `URLSessionDownloadTask` does not: cancelling it completes the task with
    /// `URLError(.cancelled)`, which fell into the generic branch and drew R43 §3's
    /// `Download failed. Nothing was changed.` at the one moment nothing had failed.
    ///
    /// Kept here rather than in the model because it is a fact about what this type throws.
    public static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError { return urlError.code == .cancelled }
        return false
    }

    /// The byte count and sha256 of a finished file, read in chunks so an 199 MB pack is never
    /// resident in memory. The same two facts the streaming version computed as it wrote.
    private static func verifiableFacts(ofFileAt url: URL) throws -> (bytes: Int64, digest: String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return (total, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    /// 512 KiB: big enough that hashing dominates the per-chunk overhead, small enough that a read
    /// buffer is not a memory event.
    private static let chunkSize = 512 * 1024

    /// Drives one download task: lands the finished file, turns byte counts into the same `0…1`
    /// fraction the Cities screen's ring already draws, and resumes the caller's continuation
    /// exactly once.
    ///
    /// **Reports on whole percents only**, which is the rule the streaming version had and the
    /// reason this holds any progress state at all: the delegate is called per transport chunk, and
    /// a `@MainActor` hop per call would put thousands of view updates behind one download.
    ///
    /// `expectedBytes` is the manifest's count rather than
    /// `totalBytesExpectedToWrite`, which is `NSURLSessionTransferSizeUnknown` (-1) whenever the
    /// response carries no `Content-Length`. The manifest always states the size, and it is the
    /// number the file is about to be verified against anyway.
    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let expectedBytes: Int64
        private let onProgress: (@Sendable (Double) -> Void)?
        private let lock = NSLock()
        private var lastReportedPercent = -1
        private var continuation: CheckedContinuation<URLResponse, any Error>?
        private var moveError: (any Error)?
        private var isCancelled = false

        init(
            destination: URL,
            expectedBytes: Int64,
            onProgress: (@Sendable (Double) -> Void)?
        ) {
            self.destination = destination
            self.expectedBytes = expectedBytes
            self.onProgress = onProgress
        }

        /// Parks the continuation **before** the task is started, so a transfer that completes
        /// immediately (an in-process protocol, a `file://` fixture) cannot finish against a nil —
        /// and declines to start one that was called off first.
        ///
        /// `task.resume()` is called while the lock is held, so `cancel` below can only ever see
        /// "resumed" or "never resumed", never a transfer caught between the two.
        func start(
            _ continuation: CheckedContinuation<URLResponse, any Error>,
            resuming task: URLSessionDownloadTask
        ) {
            lock.lock()
            self.continuation = continuation
            if isCancelled {
                lock.unlock()
                finish(.failure(URLError(.cancelled)))
                return
            }
            task.resume()
            lock.unlock()
        }

        /// Cancels the transfer, and remembers that it was cancelled. A task that had already been
        /// resumed completes through `didCompleteWithError`; one that had not never calls back at
        /// all, and `start` answers for it.
        func cancel(_ task: URLSessionDownloadTask) {
            lock.lock()
            isCancelled = true
            lock.unlock()
            task.cancel()
        }

        /// Resumes at most once: the stored continuation is taken under the lock and cleared, so a
        /// second completion callback has nothing to resume.
        private func finish(_ result: Result<URLResponse, any Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }

        /// **The move happens here, synchronously, and it has to.** URLSession deletes `location`
        /// as soon as this method returns; a failure is carried to `didCompleteWithError` rather
        /// than thrown, because a delegate callback has nowhere to throw to.
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                lock.lock()
                moveError = error
                lock.unlock()
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: (any Error)?
        ) {
            if let error {
                finish(.failure(error))
                return
            }
            lock.lock()
            let moveError = self.moveError
            lock.unlock()
            if let moveError {
                finish(.failure(moveError))
            } else if let response = task.response {
                finish(.success(response))
            } else {
                finish(.failure(URLError(.badServerResponse)))
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard let onProgress, expectedBytes > 0 else { return }
            let fraction = min(1, Double(totalBytesWritten) / Double(expectedBytes))
            let percent = Int(fraction * 100)
            lock.lock()
            let isNew = percent != lastReportedPercent
            if isNew { lastReportedPercent = percent }
            lock.unlock()
            if isNew { onProgress(fraction) }
        }
    }

    /// `file://` fixtures return no HTTPURLResponse; only a real HTTP answer is status-checked.
    private static func checkStatus(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.unacceptableStatus(http.statusCode)
        }
    }
}
