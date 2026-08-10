import Foundation

/// Test doubles and fixtures for the outbox gates.
///
/// Deliberately **not** wrapped in `#if canImport(Testing)`: the scratchpad harness that runs these
/// gates on macOS today drives these same types without the Testing framework, and duplicating them
/// would let the harness and the eventual test target drift. Nothing here is referenced by shipping
/// code, so it costs a few kilobytes of dead code in the binary until a test target exists.
public enum OutboxTestSupport {

    /// A movable clock. `OutboxQueue` takes its `now` as a closure precisely so the 30 s / 2 m /
    /// 10 m / 1 h schedule can be asserted without sleeping for 48 hours.
    public final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date

        public init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
            current = start
        }

        public var now: Date {
            lock.lock(); defer { lock.unlock() }
            return current
        }

        public func advance(by interval: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            current = current.addingTimeInterval(interval)
        }

        public var closure: @Sendable () -> Date { { [self] in now } }
    }

    /// What the scripted transport should do on the next pass.
    public enum Script: Sendable, Equatable {
        /// Everything succeeds.
        case allSucceed
        /// The whole call throws — a dropped connection mid-batch, which is what "network flap"
        /// means for a batch endpoint.
        case connectionDropped
        /// The call returns, but every item comes back failed with this code.
        case allFail(APIError)
        /// The first `count` items fail with `code`; the rest succeed.
        case firstFail(count: Int, code: APIError)
        /// Named client UUIDs fail; everything else succeeds.
        case theseFail(Set<UUID>, APIError)
        /// Photo binaries fail, JSON succeeds.
        case photosFail
    }

    /// A transport that follows a script and, critically, **applies successful items into a set
    /// keyed by `clientUUID`**, the same way the server dedupes (BUILD-PLAN §6).
    ///
    /// That set is what makes "zero duplicates" a real assertion rather than a restatement of the
    /// unique index: an item re-sent after a flap must come back `duplicate`, and the applied set
    /// must still hold exactly one entry for it.
    public actor ScriptedTransport: OutboxTransport {
        public private(set) var script: Script
        /// Every `clientUUID` that was accepted, once each. Zero duplicates means this stays a set
        /// whose count equals the number of distinct mutations.
        public private(set) var applied: Set<UUID> = []
        /// How many times each `clientUUID` was *offered*. Retries make this greater than one; that
        /// is expected and is exactly why dedupe has to exist.
        public private(set) var offers: [UUID: Int] = [:]
        /// Every item that came back `applied` rather than `duplicate`. Must equal `applied`.
        public private(set) var appliedResponses: [UUID] = []
        /// Every binary the drain offered, with the shot type it was offered under. The shot type is
        /// recorded because that is the field the transport used to invent.
        public private(set) var uploadedPhotos: [OutboxPhoto] = []
        public var uploadedPhotoPaths: [String] { uploadedPhotos.map(\.path) }
        public private(set) var syncCallCount = 0

        public init(script: Script = .allSucceed) {
            self.script = script
        }

        public func setScript(_ script: Script) {
            self.script = script
        }

        public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            syncCallCount += 1
            for item in items { offers[item.clientUUID, default: 0] += 1 }

            switch script {
            case .connectionDropped:
                throw URLError(.notConnectedToInternet)

            case let .allFail(code):
                return items.map { SyncResult(clientUUID: $0.clientUUID, status: .failed, error: code) }

            case let .firstFail(count, code):
                return items.enumerated().map { index, item in
                    index < count
                        ? SyncResult(clientUUID: item.clientUUID, status: .failed, error: code)
                        : accept(item)
                }

            case let .theseFail(failing, code):
                return items.map { item in
                    failing.contains(item.clientUUID)
                        ? SyncResult(clientUUID: item.clientUUID, status: .failed, error: code)
                        : accept(item)
                }

            case .allSucceed, .photosFail:
                return items.map(accept)
            }
        }

        /// The server's dedupe, modeled exactly: a `clientUUID` already applied comes back
        /// `duplicate`, which `SyncResult.isSuccess` treats as a success.
        private func accept(_ item: OutboxItem) -> SyncResult {
            if applied.contains(item.clientUUID) {
                return SyncResult(clientUUID: item.clientUUID, status: .duplicate)
            }
            applied.insert(item.clientUUID)
            appliedResponses.append(item.clientUUID)
            return SyncResult(clientUUID: item.clientUUID, status: .applied)
        }

        public func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws {
            if script == .photosFail { throw URLError(.networkConnectionLost) }
            uploadedPhotos.append(photo)
        }
    }

    /// A scripted **send** sink, for the half of a drain that talks to a server (RULINGS R72 §1).
    ///
    /// Separate from `ScriptedTransport` rather than a second instance of it, because the two sides
    /// are not interchangeable and a test that could pass one value into both positions would not be
    /// testing the split. It records what it was *offered*, which is the assertion that matters most
    /// here: an item this device has not committed must never reach it.
    public actor ScriptedSendSink: OutboxSendSink {
        public private(set) var script: Script
        /// Every `clientUUID` the server accepted, once each — its dedupe, modeled.
        public private(set) var accepted: Set<UUID> = []
        /// Every `clientUUID` offered, in order, across every call. Retries repeat entries.
        public private(set) var offered: [UUID] = []
        public private(set) var syncCallCount = 0

        public init(script: Script = .allSucceed) {
            self.script = script
        }

        public func setScript(_ script: Script) {
            self.script = script
        }

        public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            syncCallCount += 1
            offered.append(contentsOf: items.map(\.clientUUID))

            switch script {
            case .connectionDropped:
                throw URLError(.notConnectedToInternet)

            case let .allFail(code):
                return items.map { SyncResult(clientUUID: $0.clientUUID, status: .failed, error: code) }

            case let .firstFail(count, code):
                return items.enumerated().map { index, item in
                    index < count
                        ? SyncResult(clientUUID: item.clientUUID, status: .failed, error: code)
                        : accept(item)
                }

            case let .theseFail(failing, code):
                return items.map { item in
                    failing.contains(item.clientUUID)
                        ? SyncResult(clientUUID: item.clientUUID, status: .failed, error: code)
                        : accept(item)
                }

            case .allSucceed, .photosFail:
                return items.map(accept)
            }
        }

        /// `duplicate` is a success on this side too: the server dedupes on `client_uuid` exactly as
        /// the local unique index does, which is what keeps the chaos gate's zero-duplicates
        /// assertion holding across a flap (spec §6.1).
        private func accept(_ item: OutboxItem) -> SyncResult {
            if accepted.contains(item.clientUUID) {
                return SyncResult(clientUUID: item.clientUUID, status: .duplicate)
            }
            accepted.insert(item.clientUUID)
            return SyncResult(clientUUID: item.clientUUID, status: .applied)
        }
    }

    // MARK: - Fixtures

    public static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
    public static let userID = UUID(uuidString: "0E000000-0000-4000-8000-000000000002")!

    public static var attribution: Attribution {
        Attribution(userID: userID, deviceID: deviceID)
    }

    /// Twenty mutations across all five outbox kinds, deterministic so a failure is reproducible.
    public static func twentyMutations(treeIDs: [UUID], capturedAt: Date) -> [(OutboxPayload, [OutboxPhoto])] {
        precondition(!treeIDs.isEmpty, "need at least one tree to attach contributions to")
        var result: [(OutboxPayload, [OutboxPhoto])] = []

        for index in 0..<20 {
            let treeID = treeIDs[index % treeIDs.count]
            let clientUUID = UUID(uuidString: String(format: "C0000000-0000-4000-8000-%012d", index))!
            let moment = capturedAt.addingTimeInterval(Double(index) * 60)

            switch index % 5 {
            case 0:
                result.append((
                    .visit(Visit(
                        treeID: treeID,
                        attribution: attribution,
                        clientUUID: clientUUID,
                        note: "note \(index)",
                        gpsAccuracyM: 6,
                        capturedAt: moment,
                        createdAt: moment,
                        updatedAt: moment
                    )),
                    // Every fourth visit carries a binary, so the wifi-only path is exercised. It is
                    // a trunk shot: the chaos gate should notice if the framing goes missing.
                    index % 20 == 0
                        ? [OutboxPhoto(path: "/tmp/cypress-test-photo-\(index).jpg", shotType: .trunk)]
                        : []
                ))
            case 1:
                result.append((
                    .observation(TreeObservation(
                        treeID: treeID,
                        attribution: attribution,
                        clientUUID: clientUUID,
                        capturedAt: moment,
                        gpsAccuracyM: 8,
                        status: .alive,
                        vitality: .good,
                        createdAt: moment,
                        updatedAt: moment
                    )),
                    []
                ))
            case 2:
                result.append((
                    .measurement(TreeMeasurement.dbh(
                        treeID: treeID,
                        attribution: attribution,
                        clientUUID: clientUUID,
                        capturedAt: moment,
                        gpsAccuracyM: 5,
                        quantity: Quantity(value: 31, unit: .centimeters, method: .tape),
                        createdAt: moment,
                        updatedAt: moment
                    )),
                    []
                ))
            case 3:
                result.append((
                    .careEvent(CareEvent(
                        treeID: treeID,
                        attribution: attribution,
                        clientUUID: clientUUID,
                        capturedAt: moment,
                        gpsAccuracyM: 9,
                        actions: [.watered, .mulched],
                        createdAt: moment,
                        updatedAt: moment
                    )),
                    []
                ))
            default:
                result.append((
                    .favoriteToggle(FavoriteToggle(
                        owner: .user(userID),
                        treeID: treeID,
                        clientUUID: clientUUID,
                        isFavorite: true,
                        occurredAt: moment
                    )),
                    []
                ))
            }
        }
        return result
    }
}
