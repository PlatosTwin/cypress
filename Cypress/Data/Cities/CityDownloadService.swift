import Foundation
import Observation

/// Everything the app has to remember about a transfer for it to survive the process that started
/// it: which city, at which version, and the two facts the bytes will be judged against.
///
/// **This travels in `URLSessionTask.taskDescription`, not in a file this app maintains.** The
/// transfer belongs to `nsurlsessiond` once it starts, and it is handed back — with this string
/// attached — to whichever process next creates a session with the same identifier. A ledger of our
/// own would be a second record of the same fact, and the two would disagree the first time a
/// process died between writing one and starting the other.
///
/// `sha256` and `bytes` are copied out of the manifest entry deliberately, and this is the only
/// thing from the catalog the app ever writes down. RULINGS R43 §3 forbids *persisting the
/// manifest* — it is re-fetched on every appearance so a delisted or republished city is never
/// served from a stale copy. What is kept here is not the catalog: it is the promise this
/// particular transfer was started against, and judging the finished bytes by a *later* manifest
/// would be judging them by a promise nobody made. It lives exactly as long as the transfer.
struct CityDownloadRecord: Codable, Equatable, Sendable {
    let id: String
    let version: String
    /// The catalog's own display name, carried so a transfer adopted from a previous launch can be
    /// named on screen before — or without — the catalog being reachable. From the publisher, never
    /// composed here (DECISIONS constraint 15).
    let displayName: String
    let bytes: Int64
    let sha256: String

    init(_ city: CityManifest.City) {
        self.id = city.id
        self.version = city.version
        self.displayName = city.displayName
        self.bytes = city.bytes
        self.sha256 = city.sha256.lowercased()
    }

    /// The `taskDescription` payload. JSON rather than a delimited string because a display name is
    /// a civic string from the publisher and may contain anything a separator could be.
    func encoded() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }

    static func decoded(_ description: String?) -> CityDownloadRecord? {
        guard let description, let data = description.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CityDownloadRecord.self, from: data)
    }
}

/// What the Cities screen reads about a transfer, wherever that transfer is running.
///
/// **Owned by the composition root and not by the screen**, which is the shape of this whole round.
/// `CityDownloadsModel` is rebuilt on every push — its catalog is deliberately never persisted
/// (R43 §3) — so a download that belonged to the model ended when the reader pressed Back, and
/// ended for good when the process did. This box outlives both, so a pushed screen *reads* a
/// transfer rather than owning one.
@MainActor
@Observable
final class CityDownloadProgress {

    struct InFlight: Equatable, Sendable {
        let record: CityDownloadRecord
        /// `0…1`, from the transport's byte count against the manifest's promised size.
        let fraction: Double
    }

    /// The one transfer that may be running. One at a time (R43 §3).
    private(set) var inFlight: InFlight?

    /// The most recent attempt that failed, until the next attempt or the next screen load clears
    /// it — the same lifetime this had when it was `CityDownloadsModel.failedCityID`.
    private(set) var failedCityID: String?

    /// Bumped once per file that lands.
    ///
    /// **A counter, not a flag.** Nothing here needs an acknowledgement: a screen compares the
    /// value it last drew against the value now and re-reads the disk if they differ, so two
    /// installs while the screen was away are distinguishable from one, and no reader of this has
    /// to remember to clear it.
    private(set) var installCount = 0

    /// Whether the transfers a previous launch left running have been asked about yet.
    ///
    /// **Not cosmetic.** Between launch and the answer, `inFlight` is nil and *means nothing*, so a
    /// screen drawing `Download` in that window would offer a second copy of a city already on its
    /// way. The Cities screen waits on this exactly as it waits on the catalog.
    private(set) var hasAdopted = false

    /// The composition root's reboot, called after a file has been verified and installed.
    ///
    /// **It lives here, beside the fact that triggers it, because this is the object the main actor
    /// owns.** `CityDownloadService` is not actor-isolated — it answers URLSession's delegate queue
    /// — so a mutable hook stored on it would be read off that queue and written from the app's
    /// launch, which is a race. Stored here it is read on the actor that will call it.
    ///
    /// `AppModel.reboot()` refuses unless the layer is `.ready`, so an install landing in a
    /// background relaunch — where no layer was ever booted — changes nothing and needs no guard of
    /// its own. The file is on disk either way, and the next boot attaches it, because
    /// `DataLayer.bootOverInstalledCities` reads the disk rather than a list.
    var onInstalled: (() -> Void)?

    func apply(inFlight: InFlight?) { self.inFlight = inFlight }
    func apply(failedCityID: String?) { self.failedCityID = failedCityID }
    func recordAdoption() { hasAdopted = true }

    func recordInstall() {
        installCount += 1
        onInstalled?()
    }
}

/// One city transfer at a time, on a session that outlives this process.
///
/// ── The mechanism, and why it is this one ─────────────────────────────────────────────────────
///
/// A tester reported it twice on the same evening (build 49, 2026-08-23): *"Download is super
/// slow"* and *"Download fails if app closes or phone screen sleeps"*. The first was a per-byte
/// `AsyncSequence` loop and is already fixed (`CityDownloader`'s own history records it). This is
/// the second, and it was never a bug in the transfer — it is what a transfer on an ordinary
/// `URLSession` *is*. iOS suspends the process seconds after the app leaves the screen and every
/// task on a default or ephemeral configuration is suspended with it; the 199 MB the reader was
/// 80 % of the way through is discarded, and they start again.
///
/// **`URLSessionConfiguration.background(withIdentifier:)` is the only mechanism the platform has
/// for that**, and it covers more than backgrounding: the transfer belongs to `nsurlsessiond`, a
/// separate process, so it continues while this app is suspended *and* while it does not exist.
/// `sessionSendsLaunchEvents` then relaunches the app — into the background, with no scene — to be
/// told the file has landed. Extra background execution time (`UIApplication.beginBackgroundTask`)
/// was the alternative and is not one: it buys about thirty seconds, a 199 MB pack does not finish
/// in thirty seconds, and it would convert one failure into a later one.
///
/// **It needs no `UIBackgroundModes` key and no entitlement.** That is worth stating because it is
/// the opposite of what the neighbouring background *task* APIs require, and it is checked rather
/// than assumed — `Tools/verify_entitlements.sh` guards the entitlements file, and this round adds
/// nothing to it or to `Info.plist`.
///
/// ── Three consequences that are not obvious ───────────────────────────────────────────────────
///
/// 1. **The delegate is the session's, never the task's.** `URLSessionTask.delegate` is documented
///    as unsupported on a background session, and it could not work in principle: the object a
///    previous process assigned did not survive that process. So `CityDownloader`'s per-task
///    delegate is gone and its state moved onto this object, keyed by the task identifier.
/// 2. **No continuation can span the transfer.** `downloadCity` was `async` and returned a URL;
///    there is no `await` that survives a process death. What replaces it is a state machine whose
///    record lives on the task (`CityDownloadRecord`) and whose visible state lives in
///    `CityDownloadProgress`.
/// 3. **The install is file work and needs no app.** Verifying and moving a finished file is
///    `FileManager` and `SHA256`, so it completes in a background relaunch with no `DataLayer`, no
///    scene and no screen. Which is why the file lands wherever the transfer finishes, and only the
///    *union* waits — see `CityDownloadProgress.onInstalled`.
///
/// ── What this deliberately does not do ────────────────────────────────────────────────────────
///
/// **`Cancel` keeps no resume data.** It could: `cancel(byProducingResumeData:)` would let a
/// cancelled transfer be picked up later. That is a fifth verb on a screen whose vocabulary the
/// owner ruled — `Download`, `Update`, `Remove`, `Cancel` (RULINGS R84 D9) — and a row state no
/// mock draws, which is DECISIONS constraint 21. Cancel means called off; the bytes go.
///
/// **An interruption the reader did not ask for resumes silently**, which is the same rule from the
/// other side: a transfer that lost its connection and got it back needs no new word, because
/// `Downloading…` was true throughout. See `resumeBudget`.
final class CityDownloadService: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// The session identifier. **Stable forever**: it is the name under which `nsurlsessiond` holds
    /// this app's transfers, so changing it in a later build would orphan every download in flight
    /// across that update — the bytes would keep arriving and no process would ever be handed them.
    static let backgroundSessionIdentifier = "app.cypress.city-downloads"

    /// How many times a transfer may be restarted from resume data before the reader is told it
    /// failed.
    ///
    /// **Neither zero nor unbounded.** A background session waits out ordinary connectivity gaps on
    /// its own — `waitsForConnectivity` is documented as always on for background sessions — so what
    /// reaches `didCompleteWithError` carrying resume data is a transfer the system gave up on.
    /// Restarting it a few times covers a walk out of wi-fi range. Restarting it forever would spend
    /// a reader's cellular allowance against a server that is answering wrong, with the row saying
    /// `Downloading…` the whole time.
    static let resumeBudget = 3

    private let library: CityLibrary
    private let baseURL: URL
    private let progress: CityDownloadProgress

    /// What `didFinishDownloadingTo` concluded, read and cleared by `didCompleteWithError`.
    ///
    /// The result of a transfer is published from **one** place, because a delegate callback has
    /// nowhere to throw to and a row told two things by two callbacks says the second one.
    private enum Outcome { case installed, failed }

    private let lock = NSLock()
    private var session: URLSession!
    /// The transfer this process believes is running.
    private var current: (taskIdentifier: Int, record: CityDownloadRecord)?
    private var lastReportedPercent = -1
    private var outcome: Outcome?
    /// Set while `cancel()` is tearing a transfer down, so the `URLError.cancelled` that follows
    /// reads as the reader's decision rather than as a failure to report.
    private var isCancelling = false
    private var resumesUsed = 0
    /// Resumed when nothing is in flight. A list, because more than one caller may wait.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// How many settled transfers have not finished *publishing* yet.
    ///
    /// **Idle is not "the task is over", it is "the task is over and the box says so".** Clearing
    /// `current` happens on URLSession's queue and publishing happens on the main actor, so between
    /// the two there is a window in which the transfer is done and `CityDownloadProgress` still
    /// describes it as running. A waiter woken in that window reads the state before the answer —
    /// which for `awaitBackgroundEvents` means telling the system it may suspend the app, and for a
    /// test means a flake that looks like a defect.
    private var settlingCount = 0
    /// Set by `urlSessionDidFinishEvents` when nobody was waiting yet, so the handshake below
    /// cannot park on an event that has already happened.
    private var backgroundEventsArrived = false
    private var backgroundEventsWaiter: CheckedContinuation<Void, Never>?

    /// - Parameter configuration: `backgroundConfiguration()` in a shipping launch. A build with the
    ///   network gate off, and every unit test, passes an ordinary one — **every line below is the
    ///   same on either**, which is the whole point of the seam. A background session refuses a
    ///   `file://` URL and ignores `protocolClasses` outright, so the fixtures this project's tests
    ///   are built on (`CityBucketFixtureProtocol`, the `file://` bucket mirror) can only reach the
    ///   code through an ordinary configuration. See `RemoteAccess`, and the PR body for what that
    ///   means the tests do and do not prove.
    init(
        library: CityLibrary,
        baseURL: URL = CityDownloader.defaultBaseURL,
        configuration: URLSessionConfiguration,
        progress: CityDownloadProgress
    ) {
        self.library = library
        self.baseURL = baseURL
        self.progress = progress
        super.init()
        let queue = OperationQueue()
        // **One at a time, and load-bearing rather than tidy.** The callbacks below read and write
        // `current`, `outcome` and `resumesUsed`; serializing the queue is what lets the
        // finish-then-complete pair be reasoned about as a sequence. The lock stays, because `start`
        // and `cancel` are called from the main actor.
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// The shipping configuration.
    ///
    /// `isDiscretionary = false` because the reader pressed a button and is watching a ring. A
    /// discretionary transfer is scheduled at the system's convenience — plugged in, on wi-fi,
    /// possibly hours later — which is the right default for a sync nobody asked for and the wrong
    /// one for the one they did.
    static func backgroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: backgroundSessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return configuration
    }

    // MARK: - Adopting what a previous launch left running

    /// Asks the session what it is still carrying, and republishes it.
    ///
    /// **This is what makes the feature visible.** Everything else here works with no screen at all
    /// — the bytes arrive, the file installs — and the reader would come back to an app that had
    /// silently forgotten it was downloading anything. `getAllTasks` is answered from
    /// `nsurlsessiond`'s own record, so what comes back is what is running, not what this process
    /// remembers starting.
    ///
    /// A task whose `taskDescription` this build cannot decode is **cancelled rather than adopted**:
    /// it is a transfer with no promise attached, so its bytes could never be verified, and leaving
    /// it running would spend a reader's data on a file nothing could accept.
    func adopt() async {
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        var adopted: CityDownloadProgress.InFlight?
        for task in tasks {
            guard adopted == nil,
                  let download = task as? URLSessionDownloadTask,
                  let record = CityDownloadRecord.decoded(task.taskDescription)
            else {
                task.cancel()
                continue
            }
            // Not inlined: `NSLock` is unavailable from an asynchronous context (an `await` while
            // holding it would park a thread nobody can unblock), so the mutation lives in a
            // synchronous method the compiler can see is safe.
            take(download.taskIdentifier, record)
            adopted = .init(
                record: record, fraction: Self.fraction(task.countOfBytesReceived, record)
            )
        }
        let result = adopted
        await MainActor.run {
            if let result { progress.apply(inFlight: result) }
            progress.recordAdoption()
        }
    }

    /// Makes `task` the transfer this process is tracking, and clears everything the previous one
    /// left behind. The one place `current` is set.
    private func take(_ taskIdentifier: Int, _ record: CityDownloadRecord) {
        lock.lock()
        current = (taskIdentifier, record)
        lastReportedPercent = -1
        isCancelling = false
        resumesUsed = 0
        outcome = nil
        lock.unlock()
    }

    // MARK: - Starting, cancelling

    /// Begins a transfer, unless one is already running.
    ///
    /// - Returns: false when it declined, so a caller can tell "started" from "there was already
    ///   one" — which is what stops a second tap on `Download` opening a second socket.
    @MainActor
    @discardableResult
    func start(_ city: CityManifest.City) -> Bool {
        guard progress.inFlight == nil else { return false }
        let record = CityDownloadRecord(city)
        guard let description = try? record.encoded() else { return false }

        let task = session.downloadTask(with: baseURL.appendingPathComponent(city.path))
        // **Set before `resume()`, always.** This is the only copy of the promise the finished bytes
        // will be judged by; a task that started without it is a transfer nothing can accept.
        task.taskDescription = description
        take(task.taskIdentifier, record)

        progress.apply(failedCityID: nil)
        progress.apply(inFlight: .init(record: record, fraction: 0))
        task.resume()
        return true
    }

    /// The reader pressed `Cancel`. The bytes go; see this type's header for why no resume data is
    /// kept.
    ///
    /// Asked of the session rather than of a task this object is holding, for `adopt`'s reason: the
    /// transfer being cancelled may have been started by a process that no longer exists.
    @MainActor
    func cancel() {
        lock.lock()
        isCancelling = true
        lock.unlock()
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        progress.apply(inFlight: nil)
    }

    /// Clears the failure line — the screen's own `load()` does this on every appearance, exactly as
    /// it did when the flag lived on the model.
    @MainActor
    func clearFailure() {
        progress.apply(failedCityID: nil)
    }

    // MARK: - Waiting

    /// Resumes once nothing is in flight.
    ///
    /// Two callers wanting the same thing for different reasons: the background-events handshake
    /// must not report finished while a file is still being hashed, and a test needs somewhere to
    /// await.
    func waitUntilIdle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if current == nil, settlingCount == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            idleWaiters.append(continuation)
            lock.unlock()
        }
    }

    /// The handshake `CypressApp`'s `.backgroundTask(.urlSession(_:))` performs.
    ///
    /// The system relaunched this app to be told about a background session and holds it awake only
    /// until this returns. So it waits for two things in order: the session saying it has delivered
    /// everything it had (`urlSessionDidFinishEvents`), and this service saying it has finished
    /// acting on it — the verify-and-install, which is where the reader's 199 MB becomes a city.
    ///
    /// **`backgroundEventsArrived` is not a nicety.** The delivery can complete before SwiftUI runs
    /// the closure that awaits it, and a continuation parked on an event that already happened is a
    /// background relaunch that never returns.
    func awaitBackgroundEvents() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if backgroundEventsArrived {
                backgroundEventsArrived = false
                lock.unlock()
                continuation.resume()
                return
            }
            backgroundEventsWaiter = continuation
            lock.unlock()
        }
        await waitUntilIdle()
    }

    // MARK: - Delegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        guard let current, current.taskIdentifier == downloadTask.taskIdentifier else {
            lock.unlock()
            return
        }
        let record = current.record
        let fraction = Self.fraction(totalBytesWritten, record)
        let percent = Int(fraction * 100)
        let isNew = percent != lastReportedPercent
        if isNew { lastReportedPercent = percent }
        lock.unlock()
        // Whole percents only: the delegate is called per transport chunk, and a main-actor hop per
        // call would put thousands of view updates behind one download. `CityDownloader`'s ring had
        // this rule and it is unchanged.
        guard isNew else { return }
        Task { @MainActor [progress] in
            // A cancel that has already cleared the box must not be undone by a chunk still in
            // flight behind it.
            guard progress.inFlight?.record == record else { return }
            progress.apply(inFlight: .init(record: record, fraction: fraction))
        }
    }

    /// **The move happens here, synchronously, because it has to** — URLSession deletes `location`
    /// the moment this returns. Everything after the move is this app's own file, and it is verified
    /// and installed here too rather than being scheduled: this callback may be running in a process
    /// the system relaunched purely to deliver it, and work handed to a detached `Task` at this
    /// point is work the app may be suspended before it does.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let record = current?.taskIdentifier == downloadTask.taskIdentifier ? current?.record : nil
        lock.unlock()
        // A finished transfer this process holds no promise for. It cannot be verified, so it is not
        // kept: `adopt` cancels such tasks, and this covers the one that finished before it could.
        guard let record else { return }

        let staged = library.stagingURL
            .appendingPathComponent("\(UUID().uuidString)-\(record.id).sqlite", isDirectory: false)
        do {
            // The status is checked before the bytes are: a bucket that answered `403` sends a body,
            // and that body would otherwise be refused as a checksum mismatch — the same outcome
            // reached by the least informative route.
            try CityDownloader.checkStatus(downloadTask.response)
            try FileManager.default.createDirectory(
                at: library.stagingURL, withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: location, to: staged)
            try CityDownloader.verify(fileAt: staged, against: record)
            try library.install(verifiedFileAt: staged, id: record.id, version: record.version)
            lock.lock(); outcome = .installed; lock.unlock()
        } catch {
            // Partial or impostor bytes never reach the library — `CityDownloader`'s contract, kept
            // here now that this is the code that keeps it.
            try? FileManager.default.removeItem(at: staged)
            lock.lock(); outcome = .failed; lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        guard let current, current.taskIdentifier == task.taskIdentifier else {
            lock.unlock()
            return
        }
        let record = current.record
        let outcome = self.outcome
        let wasCancelling = isCancelling
        self.outcome = nil
        lock.unlock()

        guard let error else {
            settle(record: record, failed: outcome != .installed, installed: outcome == .installed)
            return
        }

        if CityDownloader.isCancellation(error), wasCancelling {
            settle(record: record, failed: false)
            return
        }

        // **An interruption the reader did not ask for.** The system hands back the bytes it already
        // has; starting again from them is invisible to the reader and needs no word on the screen.
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        lock.lock()
        if let resumeData, resumesUsed < Self.resumeBudget {
            resumesUsed += 1
            let retry = session.downloadTask(withResumeData: resumeData)
            retry.taskDescription = task.taskDescription
            self.current = (retry.taskIdentifier, record)
            lock.unlock()
            retry.resume()
            return
        }
        lock.unlock()
        settle(record: record, failed: true)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let waiter = backgroundEventsWaiter
        backgroundEventsWaiter = nil
        if waiter == nil { backgroundEventsArrived = true }
        lock.unlock()
        waiter?.resume()
    }

    // MARK: - Publishing

    /// The one exit from a transfer: clear the in-flight state, say what happened, wake anyone
    /// waiting on idle. Every branch of `didCompleteWithError` ends here.
    private func settle(record: CityDownloadRecord, failed: Bool, installed: Bool = false) {
        lock.lock()
        current = nil
        lastReportedPercent = -1
        isCancelling = false
        resumesUsed = 0
        settlingCount += 1
        lock.unlock()

        Task { @MainActor [progress] in
            progress.apply(inFlight: nil)
            if failed { progress.apply(failedCityID: record.id) }
            // `recordInstall` is what calls the composition root's reboot, so it goes last: the
            // screen's own facts are true before the layer under it is torn down.
            if installed { progress.recordInstall() }

            // **Waiters are woken from here, not from the body above**, which is the whole of
            // `settlingCount`'s purpose: idle has to mean the box is telling the truth, not merely
            // that the socket closed.
            self.lock.lock()
            self.settlingCount -= 1
            let waiters = self.idleWaiters
            self.idleWaiters = []
            self.lock.unlock()
            waiters.forEach { $0.resume() }
        }
    }

    /// `0…1` against the **manifest's** promised size, never `totalBytesExpectedToWrite` — that is
    /// `NSURLSessionTransferSizeUnknown` (-1) whenever the response carries no `Content-Length`, and
    /// the manifest always states the size the file is about to be verified against anyway.
    private static func fraction(_ written: Int64, _ record: CityDownloadRecord) -> Double {
        guard record.bytes > 0 else { return 0 }
        return min(1, max(0, Double(written) / Double(record.bytes)))
    }
}
