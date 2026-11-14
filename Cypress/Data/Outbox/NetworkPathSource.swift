import Foundation
import Network

/// Whether the phone's current connection is unmetered, whether it has one at all, and when either
/// changes.
///
/// This is the reachability source ERRATA **E81** found missing. It answers two questions for
/// screen 17. The second is the header pill's `offline` clause (`connectedNow()`). The first is the
/// question the toggle asks: "Sync photos on wifi only" holds photo binaries back on a
/// connection that may cost the volunteer money, and nothing in the app could tell which connection
/// that was. Without an answer, every drain passed `photoUploadsAllowed: true`, and photographs went
/// over cellular with the switch on (beta feedback F35).
///
/// **"Unmetered" is the question, and it is not the same as "wi-fi".** A path counts as unmetered
/// when it is satisfied, not expensive (cellular, or a phone's personal hotspot), and not
/// constrained (Low Data Mode). That is what the toggle exists to protect, and it is what
/// `NWPath.isExpensive` and `NWPath.isConstrained` were made to say.
///
/// `Data` imports no UI framework; `Network` is not one (ARCHITECTURE §2). `Data` already imports
/// `Security`, `CryptoKit` and `ImageIO` on the same terms.
public protocol NetworkPathSource: Sendable {
    /// Whether the current path is unmetered.
    ///
    /// Before the first reading arrives a source may wait briefly for it. If none comes, the answer
    /// is `false`: a photograph that waits one drain too long costs nothing, and one sent over
    /// cellular is the defect.
    func isUnmetered() async -> Bool

    /// Every change of the answer above, in order, as it happens. Each call returns a new stream.
    ///
    /// The first reading counts as a change, so a listener that subscribes before the system has
    /// answered still hears it.
    func unmeteredChanges() -> AsyncStream<Bool>

    /// Whether the phone has any usable path right now (`NWPath.status == .satisfied`), or nil
    /// before the first reading. Screen 17's header pill reads this to say `offline` (ERRATA E???).
    ///
    /// **Not the same question as `isUnmetered`.** A phone on cellular is connected and metered.
    /// "Offline" means no satisfied path at all, so a metered connection with the wi-fi toggle on is
    /// never offline.
    ///
    /// Never waits, and never guesses: nil means nothing has been read, and a caller that would
    /// claim `offline` must not claim it from nil.
    func connectedNow() -> Bool?

    /// Every change of `connectedNow()`, in order. Each call returns a new stream. The first reading
    /// counts as a change, the same rule as `unmeteredChanges()`.
    func connectedChanges() -> AsyncStream<Bool>
}

/// The state behind a changing `NetworkPathSource`: the latest reading, the listeners waiting for
/// changes, and the callers waiting for a first reading.
///
/// One type for the real source and the test double (`OutboxTestSupport.ManualNetworkPath`), so the
/// double cannot drift from the real source's rules about first readings and changes.
public final class NetworkPathState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Bool?
    private var listeners: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var firstReadingWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    public init(initial: Bool? = nil) {
        current = initial
    }

    /// Records a reading. Listeners hear it only when the answer changed.
    public func publish(_ unmetered: Bool) {
        lock.lock()
        let changed = current != unmetered
        current = unmetered
        let waiters = Array(firstReadingWaiters.values)
        firstReadingWaiters.removeAll()
        let toNotify = changed ? Array(listeners.values) : []
        lock.unlock()

        for waiter in waiters { waiter.resume(returning: unmetered) }
        for listener in toNotify { listener.yield(unmetered) }
    }

    /// The latest reading, waiting up to `timeout` for the first one.
    public func value(waitingUpTo timeout: Duration) async -> Bool {
        if let known = currentValue() { return known }

        let id = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            // A reading may have landed between the check above and this registration.
            if let current {
                lock.unlock()
                continuation.resume(returning: current)
                return
            }
            firstReadingWaiters[id] = continuation
            lock.unlock()

            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expireWaiter(id)
            }
        }
    }

    /// The latest reading, or nil when there has been none. Does not wait.
    public var latest: Bool? { currentValue() }

    private func currentValue() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// No reading in time: answer metered, which holds a photograph back rather than sending it
    /// over a connection nothing has vouched for.
    private func expireWaiter(_ id: UUID) {
        lock.lock()
        let waiter = firstReadingWaiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.resume(returning: false)
    }

    /// A new stream of changes. The listener is dropped when the stream ends or its task is
    /// cancelled.
    public func changes() -> AsyncStream<Bool> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuation.onTermination = { [weak self] _ in
            self?.removeListener(id)
        }
        lock.lock()
        listeners[id] = continuation
        lock.unlock()
        return stream
    }

    private func removeListener(_ id: UUID) {
        lock.lock()
        listeners[id] = nil
        lock.unlock()
    }
}

/// The real source: one `NWPathMonitor` for the whole process.
///
/// **Shared, not one per `DataLayer`.** `AppModel.reboot()` builds a new layer every time a city
/// installs, and the suite boots dozens. A monitor per boot would be a monitor per boot left
/// running; one per process is all the question needs.
public final class SystemNetworkPath: NetworkPathSource, @unchecked Sendable {
    public static let shared = SystemNetworkPath()

    /// How long a caller waits for the system's first answer. It normally lands within
    /// milliseconds of `start`; this only bounds the case where it does not.
    static let firstReadingTimeout: Duration = .seconds(2)

    private let monitor = NWPathMonitor()
    private let state = NetworkPathState()
    private let connection = NetworkPathState()

    private init() {
        monitor.pathUpdateHandler = { [state, connection] path in
            state.publish(Self.isUnmetered(path))
            connection.publish(Self.isConnected(path))
        }
        monitor.start(queue: DispatchQueue(label: "app.cypress.network-path", qos: .utility))
    }

    /// The definition, in one place: satisfied, and neither expensive nor constrained.
    static func isUnmetered(_ path: NWPath) -> Bool {
        path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }

    /// Connected means satisfied, on any interface and at any price. The opposite is what screen
    /// 17 calls `offline`.
    static func isConnected(_ path: NWPath) -> Bool {
        path.status == .satisfied
    }

    public func isUnmetered() async -> Bool {
        await state.value(waitingUpTo: Self.firstReadingTimeout)
    }

    public func unmeteredChanges() -> AsyncStream<Bool> {
        state.changes()
    }

    public func connectedNow() -> Bool? {
        connection.latest
    }

    public func connectedChanges() -> AsyncStream<Bool> {
        connection.changes()
    }
}

/// A path that says one thing and never changes. What a DEBUG launch that pins the connection
/// (`DebugNetworkPathOverride`) wires.
public struct PinnedNetworkPath: NetworkPathSource {
    public let unmetered: Bool
    public let connected: Bool

    /// A path with no connection is never unmetered, so `connected: false` forces `unmetered` off.
    public init(unmetered: Bool, connected: Bool = true) {
        self.unmetered = unmetered && connected
        self.connected = connected
    }

    public func isUnmetered() async -> Bool { unmetered }

    public func unmeteredChanges() -> AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }

    public func connectedNow() -> Bool? { connected }

    public func connectedChanges() -> AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}
