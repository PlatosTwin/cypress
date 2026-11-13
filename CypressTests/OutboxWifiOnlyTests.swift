import Foundation
import Testing
@testable import Cypress

/// "Sync photos on wifi only" does what it says (beta feedback F35, ROADMAP 98).
///
/// The defect: `OutboxQueue.drain(photoUploadsAllowed:)` defaulted to `true`, every production
/// caller took the default, and the one call that resolved the toggle (`OutboxViewState.syncNow`)
/// had no caller. A tester on cellular saw photographs upload with the switch on. The fix moves
/// the decision into the queue: `drain()` reads the stored toggle and a `NetworkPathSource`.
///
/// These tests go through a real feature writer (`CareLogOutboxWriter.save`), because the defect
/// lived in the callers and a test that called `drain(photoUploadsAllowed:)` itself could not see it.
@Suite("Outbox honors Sync photos on wifi only (F35)")
struct OutboxWifiOnlyTests {

    private struct Rig {
        let store: CypressStore
        let queue: OutboxQueue
        let transport: OutboxTestSupport.ScriptedTransport
        let path: OutboxTestSupport.ManualNetworkPath
        let clock: OutboxTestSupport.Clock
        let send: OutboxTestSupport.ScriptedSendSink?
    }

    /// - Parameter wifiOnly: what `app_state` holds for the toggle; `nil` leaves it unset, which is
    ///   every install that never opened screen 17.
    ///   - send: a send sink, for the cases about a photograph applied here and not yet sent.
    private static func rig(
        unmetered: Bool,
        wifiOnly: Bool?,
        send: OutboxTestSupport.ScriptedSendSink? = nil
    ) async throws -> Rig {
        let store = try await CypressStore.inMemory()
        if let wifiOnly {
            try await store.setAppState(.syncPhotosOnWifiOnly, to: wifiOnly ? "true" : "false")
        }
        let transport = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let path = OutboxTestSupport.ManualNetworkPath(unmetered: unmetered)
        let clock = OutboxTestSupport.Clock()
        let queue = OutboxQueue(
            queue: store.queue, apply: transport, send: send, networkPath: path, now: clock.closure
        )
        return Rig(
            store: store, queue: queue, transport: transport, path: path, clock: clock, send: send
        )
    }

    /// One care event with one photograph, saved the way screen 10 saves it.
    private static func saveCareWithPhoto(_ rig: Rig) async throws -> CareLogSaveReceipt {
        var draft = CareLogDraft(actions: [.watered])
        draft.photos = [OutboxPhoto(path: "/tmp/cypress-f35-\(UUID().uuidString).jpg", shotType: .leaf)]
        return try await CareLogOutboxWriter.save(
            draft,
            treeID: UUID(),
            attribution: OutboxTestSupport.attribution,
            outbox: rig.queue,
            now: rig.clock.now
        )
    }

    private static func record(_ rig: Rig, id: UUID) async throws -> OutboxStore.Record {
        try #require(try await rig.queue.records().first { $0.id == id })
    }

    // MARK: - 1. Cellular, toggle on: the note goes, the photograph waits

    @Test(
        "on cellular with wifi-only on, a writer's save sends the note and holds the photo",
        arguments: [Bool?.none, true]
    )
    func cellularHoldsThePhoto(storedToggle: Bool?) async throws {
        let rig = try await Self.rig(unmetered: false, wifiOnly: storedToggle)

        let receipt = try await Self.saveCareWithPhoto(rig)

        let applied = await rig.transport.applied
        #expect(applied.contains(receipt.item.clientUUID), "the note did not sync on cellular")
        let uploaded = await rig.transport.uploadedPhotos
        #expect(uploaded.isEmpty, "a photo binary went over cellular with wifi-only on: \(uploaded.map(\.path))")

        let record = try await Self.record(rig, id: receipt.item.id)
        #expect(record.item.state == .pending)
        #expect(record.item.lastError == OutboxFailureReason.awaitingWifi(photoCount: 1))
        #expect(record.item.failCount == 0, "waiting for wi-fi was counted as a failure")
        let snapshot = try await rig.queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 1)
    }

    // MARK: - 2. Cellular, toggle off: everything goes

    @Test("with wifi-only off, the photo sends on cellular")
    func toggleOffSendsOnCellular() async throws {
        let rig = try await Self.rig(unmetered: false, wifiOnly: false)

        let receipt = try await Self.saveCareWithPhoto(rig)

        let uploaded = await rig.transport.uploadedPhotos
        #expect(uploaded.count == 1, "the toggle is off and the photo still waited")
        let record = try await Self.record(rig, id: receipt.item.id)
        #expect(record.item.state == .done)
    }

    // MARK: - 3. Wi-fi returns: the waiting photograph goes by itself

    @Test("a path change to unmetered drains the waiting photo with no user action")
    func wifiReturningDrains() async throws {
        let rig = try await Self.rig(unmetered: false, wifiOnly: true)
        let watcher = OutboxWifiWatcher(queue: rig.queue, networkPath: rig.path)

        let receipt = try await Self.saveCareWithPhoto(rig)
        #expect(await rig.transport.uploadedPhotos.isEmpty, "the photo did not wait for wi-fi")

        rig.path.set(unmetered: true)

        // The watcher drains on its own task. Bounded wait: 5 s in 10 ms steps.
        var state = try await Self.record(rig, id: receipt.item.id).item.state
        for _ in 0..<500 where state != .done {
            try await Task.sleep(for: .milliseconds(10))
            state = try await Self.record(rig, id: receipt.item.id).item.state
        }
        withExtendedLifetime(watcher) {}

        #expect(state == .done, "wi-fi returned and the waiting photo was never drained")
        #expect(await rig.transport.uploadedPhotos.count == 1)
    }

    // MARK: - 3b. A photo waiting for wi-fi does not expire

    /// The 48 h cap is for an item that keeps failing. A photograph held back by the toggle is not
    /// failing, and before F35 nothing ever held one back, so the cap never met this case. Without
    /// the exemption a two-day trip on cellular ends with "Tried for 48 hours without getting
    /// through" on a note that was saved the whole time.
    @Test("a photo waiting on cellular for more than 48 h is still waiting, and sends when wi-fi returns")
    func waitingPhotoDoesNotExpire() async throws {
        let rig = try await Self.rig(unmetered: false, wifiOnly: true)
        let receipt = try await Self.saveCareWithPhoto(rig)

        rig.clock.advance(by: 49 * 60 * 60)
        _ = try await rig.queue.drain()

        var record = try await Self.record(rig, id: receipt.item.id)
        #expect(record.item.state == .pending, "a photo waiting for wi-fi expired after 48 h: \(record.item.lastError ?? "nil")")
        #expect(record.item.lastError == OutboxFailureReason.awaitingWifi(photoCount: 1))
        #expect(await rig.transport.uploadedPhotos.isEmpty)

        rig.path.set(unmetered: true)
        _ = try await rig.queue.drain()

        record = try await Self.record(rig, id: receipt.item.id)
        #expect(record.item.state == .done, "the long-waiting photo did not send on wi-fi")
        #expect(await rig.transport.uploadedPhotos.count == 1)
    }

    // MARK: - 3c. After a long hold, one transient failure is not the end (review B1)

    /// The 48 h cap counts from the last hold, not from the save.
    ///
    /// **Why this fails with the defect present:** `reschedule` kept `window_started_at` at the
    /// save. The exemption covers a row only while its reason is still `awaitingWifi`; the first
    /// failure after wi-fi returns overwrites that reason, so the next drain measured the window
    /// from the save, found 49 h, and settled the row `failed` as "Tried for 48 hours".
    @Test("a photo held 49 h that fails once after wi-fi returns is still pending")
    func longHoldThenTransientFailureStaysPending() async throws {
        let rig = try await Self.rig(unmetered: false, wifiOnly: true)
        let receipt = try await Self.saveCareWithPhoto(rig)

        rig.clock.advance(by: 49 * 60 * 60)
        _ = try await rig.queue.drain()          // still on cellular: held again

        rig.path.set(unmetered: true)
        await rig.transport.setScript(.photosFail)
        _ = try await rig.queue.drain()          // wi-fi: the binary fails, retryably
        rig.clock.advance(by: 60 * 60)           // past the first backoff step
        _ = try await rig.queue.drain()          // and fails again

        let record = try await Self.record(rig, id: receipt.item.id)
        #expect(
            record.item.state == .pending,
            "one transient failure after a long wi-fi hold expired the row: \(record.item.lastError ?? "nil")"
        )
        #expect(record.item.lastError != OutboxFailureReason.expired)
    }

    // MARK: - 3d. A photograph applied here and waiting to be sent (review S1)

    /// A photograph applied on wi-fi whose send failed, then held when the phone moved to cellular.
    /// It has no staged file any more; it is an `outbox_photos` row in state `applied`.
    ///
    /// **Why this fails with the defect present:** the reason was built from `item.photos.count`,
    /// the staged files, which is 0 here, so the row read "0 photos are waiting for wi-fi". The
    /// snapshot's predicate required staged files too, so `awaitingWifiCount` was 0 and
    /// `drainIfPhotosAwaitWifi()` returned nil: the watcher never drained it.
    @Test("a photo applied but not yet sent counts as waiting for wi-fi, and the watcher's drain sends it")
    func appliedUnsentPhotoCountsAsWaiting() async throws {
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let rig = try await Self.rig(unmetered: true, wifiOnly: true, send: send)
        let receipt = try await Self.saveCareWithPhoto(rig)   // applied, note sent, binary send failed

        rig.path.set(unmetered: false)
        await send.setScript(.allSucceed)
        _ = try await rig.queue.drain()                        // cellular: the send is held

        let record = try await Self.record(rig, id: receipt.item.id)
        #expect(record.item.photos.isEmpty, "set-up: the binary should already be applied")
        #expect(record.unsentPhotoCount == 1)
        #expect(record.item.lastError == OutboxFailureReason.awaitingWifi(photoCount: 1))
        let snapshot = try await rig.queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 1)
        #expect(snapshot.awaitingWifiPhotoCount == 1)

        rig.path.set(unmetered: true)
        let report = try await rig.queue.drainIfPhotosAwaitWifi()
        #expect(report != nil, "wi-fi returned and the watcher's check found nothing waiting")
        #expect(await send.sentPhotoPaths.count == 1)
        #expect(try await Self.record(rig, id: receipt.item.id).item.state == .done)
    }

    // MARK: - 3e. Wi-fi returning during a drain (review S2)

    /// **Why this fails with the defect present:** a drain asked for while another runs returned an
    /// empty report and did nothing else. The running drain had decided "cellular" when it began,
    /// held the photograph, and returned; nothing drained again, so the photograph waited on wi-fi.
    @Test("a drain asked for while one is running is not lost")
    func drainDuringDrainIsNotLost() async throws {
        let store = try await CypressStore.inMemory()
        try await store.setAppState(.syncPhotosOnWifiOnly, to: "true")
        let transport = GatedTransport()
        let path = OutboxTestSupport.ManualNetworkPath(unmetered: false)
        let queue = OutboxQueue(queue: store.queue, apply: transport, networkPath: path)

        var draft = CareLogDraft(actions: [.watered])
        draft.photos = [OutboxPhoto(path: "/tmp/cypress-f35-\(UUID().uuidString).jpg", shotType: .leaf)]
        let (_, item) = try await CareLogOutboxWriter.enqueue(
            draft, treeID: UUID(), attribution: OutboxTestSupport.attribution, outbox: queue
        )

        let first = Task { try await queue.drain() }   // decides "cellular", then blocks in apply
        await transport.waitUntilBlocked()
        path.set(unmetered: true)
        let second = try await queue.drain()           // overlaps: returns at once
        #expect(second.attempted == 0, "set-up: the second drain did not overlap the first")
        await transport.open()
        _ = try await first.value

        let record = try #require(try await queue.records().first { $0.id == item.id })
        #expect(record.item.state == .done, "wi-fi returned during a drain and the photo was left waiting")
        #expect(await transport.inner.uploadedPhotos.count == 1)
    }

    /// An apply sink whose `sync` blocks until the test opens it, so a second drain can be asked
    /// for while the first is provably inside its pass.
    private actor GatedTransport: OutboxTransport {
        let inner = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        private var isOpen = false
        private var gate: CheckedContinuation<Void, Never>?
        private var blockedWaiter: CheckedContinuation<Void, Never>?

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            if !isOpen {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    blockedWaiter?.resume()
                    blockedWaiter = nil
                }
            }
            return try await inner.sync(items)
        }

        func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws -> AppliedPhoto {
            try await inner.uploadPhoto(photo, for: item)
        }

        func waitUntilBlocked() async {
            guard gate == nil else { return }
            await withCheckedContinuation { blockedWaiter = $0 }
        }

        func open() {
            isOpen = true
            gate?.resume()
            gate = nil
        }
    }

    // MARK: - 4. The composition root hands the queue its path

    /// `DataLayer.boot` is where a missing argument would quietly bring F35 back: `OutboxQueue`'s
    /// `networkPath` defaults to `nil`, and `nil` lets every photograph go.
    @Test("DataLayer.boot wires the network path into the outbox", arguments: [false, true])
    func bootWiresThePath(unmetered: Bool) async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-f35-boot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Removed after the layer is released, so the database is not unlinked under an open
        // handle (the hazard `DataLayerWiringTests.databaseURL()` describes).
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.checkBootWiring(directory: directory, unmetered: unmetered)
    }

    /// The layer lives only inside this call, so it is gone before the caller removes its folder.
    private static func checkBootWiring(directory: URL, unmetered: Bool) async throws {
        let data = try await DataLayer.boot(
            databaseURL: directory.appendingPathComponent("cypress.sqlite"),
            seedURL: nil,
            credentials: InMemoryCredentialStore(),
            networkPath: OutboxTestSupport.ManualNetworkPath(unmetered: unmetered)
        )
        // Unset toggle reads as on, so the answer is exactly the connection.
        #expect(await data.outbox.photoUploadsAllowedNow() == unmetered)
        #expect(data.outboxWifiWatcher != nil, "boot made no watcher, so wi-fi returning drains nothing")
    }

    // MARK: - 5. Nothing in the app bypasses the queue's decision

    /// The sanctioned call: `drain()` passing the queue's own answer. The scanner must find it, or
    /// it is not reading the source it claims to check.
    private static let sanctionedCall = "drain(photoUploadsAllowed: await photoUploadsAllowedNow())"

    /// The declaration, which the scanner must see and must not count as a call.
    private static let declaration = "func drain(photoUploadsAllowed: Bool)"

    /// Each non-comment line under `Cypress/` that names `drain(photoUploadsAllowed:`, the
    /// declaration included. `Cypress/Data/Tests/` is test support compiled into the app target,
    /// and pins the flag on purpose, so it is left out.
    private static func explicitDrains() throws -> (calls: [String], files: Int) {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)
            .filter { !$0.path.contains("/Cypress/Data/Tests/") }
        var calls: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                guard code.range(of: #"drain\(\s*photoUploadsAllowed\s*:"#, options: .regularExpression) != nil
                else { continue }
                calls.append("\(file.lastPathComponent):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        return (calls, files.count)
    }

    @Test("no app source passes its own photo decision to drain")
    func noCallerBypassesTheQueue() throws {
        let (calls, files) = try Self.explicitDrains()
        #expect(files >= AppSourceLiterals.swiftFileCountFloor, "the guard swept \(files) files")

        // Two controls, each a line the scanner must see: the queue's own call, and the
        // declaration. Neither is a bypass; everything else is.
        let sanctioned = calls.filter { $0.hasPrefix("OutboxQueue.swift:") && $0.contains(Self.sanctionedCall) }
        #expect(sanctioned.count == 1, "the scanner did not find the queue's own call, so it saw nothing")
        let declarations = calls.filter { $0.hasPrefix("OutboxQueue.swift:") && $0.contains(Self.declaration) }
        #expect(declarations.count == 1, "the scanner did not find the declaration, so it saw nothing")

        let bypasses = calls.filter { !sanctioned.contains($0) && !declarations.contains($0) }
        #expect(
            bypasses.isEmpty,
            """
            App code passes its own answer to `drain(photoUploadsAllowed:)`. That is how F35 \
            happened: the caller's answer ignored the wi-fi toggle. Call `drain()`, which decides \
            from the stored toggle and the network path.
            \(bypasses.joined(separator: "\n"))
            """
        )
    }

    @Test("DataLayer.boot builds its OutboxQueue with a network path")
    func dataLayerPassesThePath() throws {
        let file = AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("Cypress/Data/DataLayer.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let construction = try #require(source.range(of: "let outbox = OutboxQueue("))
        let closing = try #require(source.range(of: "\n        )", range: construction.upperBound..<source.endIndex))
        let arguments = source[construction.upperBound..<closing.lowerBound]
        #expect(arguments.contains("networkPath: networkPath"), "DataLayer.boot's outbox has no network path")
    }
}
