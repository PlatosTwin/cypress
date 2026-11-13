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
    }

    /// - Parameter wifiOnly: what `app_state` holds for the toggle; `nil` leaves it unset, which is
    ///   every install that never opened screen 17.
    private static func rig(unmetered: Bool, wifiOnly: Bool?) async throws -> Rig {
        let store = try await CypressStore.inMemory()
        if let wifiOnly {
            try await store.setAppState(.syncPhotosOnWifiOnly, to: wifiOnly ? "true" : "false")
        }
        let transport = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let path = OutboxTestSupport.ManualNetworkPath(unmetered: unmetered)
        let queue = OutboxQueue(queue: store.queue, apply: transport, networkPath: path)
        return Rig(store: store, queue: queue, transport: transport, path: path)
    }

    /// One care event with one photograph, saved the way screen 10 saves it.
    private static func saveCareWithPhoto(_ rig: Rig) async throws -> CareLogSaveReceipt {
        var draft = CareLogDraft(actions: [.watered])
        draft.photos = [OutboxPhoto(path: "/tmp/cypress-f35-\(UUID().uuidString).jpg", shotType: .leaf)]
        return try await CareLogOutboxWriter.save(
            draft,
            treeID: UUID(),
            attribution: OutboxTestSupport.attribution,
            outbox: rig.queue
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

    // MARK: - 4. The composition root hands the queue its path

    /// `DataLayer.boot` is where a missing argument would quietly bring F35 back: `OutboxQueue`'s
    /// `networkPath` defaults to `nil`, and `nil` lets every photograph go.
    @Test("DataLayer.boot wires the network path into the outbox", arguments: [false, true])
    func bootWiresThePath(unmetered: Bool) async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-f35-boot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

    /// Each non-comment line under `Cypress/` that calls `drain(photoUploadsAllowed:`.
    /// `Cypress/Data/Tests/` is test support compiled into the app target, and pins the flag on
    /// purpose, so it is left out.
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

        let sanctioned = calls.filter { $0.hasPrefix("OutboxQueue.swift:") && $0.contains(Self.sanctionedCall) }
        #expect(sanctioned.count == 1, "the scanner did not find the queue's own call, so it saw nothing")

        let bypasses = calls.filter { !sanctioned.contains($0) }
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
