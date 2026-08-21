//
//  RemoteAccessTests.swift
//  CypressTests
//
//  The gate that keeps the app-under-test off the network (#158 round 4).
//
//  ── What these are actually pinning ────────────────────────────────────────────────────────────
//
//  Not "`.disabled` disables things" — that is the case nobody forgets. **The default**, because the
//  defect was that `DataLayer.boot()` with no arguments reached production, and the UI suite calls
//  exactly that. Every test here that matters calls `boot` the way `AppModel` calls it, with the
//  gate left to resolve itself.
//

import Foundation
import Testing
@testable import Cypress

@Suite("RemoteAccess — the gate")
struct RemoteAccessTests {

    // MARK: - 1. The default, which is the whole finding

    /// **With nothing set, this build does not reach the service.**
    ///
    /// The unit and UI targets are DEBUG and neither sets `CYPRESS_REMOTE`, so this is the value
    /// every test in this repository runs under. It is asserted rather than assumed because the
    /// alternative reading — "absent means live", which is what `CYPRESS_LOCATION` means and what
    /// this gate deliberately does not — is what pointed three CI runs at production.
    @Test("with no environment set, a DEBUG build does not reach the service")
    func theDefaultIsOff() {
        #expect(
            RemoteAccess.resolved == .disabled,
            """
            CYPRESS_REMOTE is unset in this process and the gate resolved \(RemoteAccess.resolved). \
            A missing environment variable must never be the thing that puts the suite on a network.
            """
        )
        #expect(!RemoteAccess.resolved.allowsNetwork)
    }

    /// A typo is not a decision, and it fails **safe** rather than loud-and-live.
    ///
    /// `DebugLocationOverride`'s rule with one difference argued in `RemoteAccess`: an unparseable
    /// location falls back to a banner and the real provider, which is harmless because the real
    /// provider is local. Here the analogous fallback would be a network, so `.misconfigured`
    /// answers `false` to `allowsNetwork` and carries the raw string for a surface to complain with.
    @Test("an unrecognized value is off, and says so")
    func aTypoIsOffAndComplains() throws {
        let typo = RemoteAccess.misconfigured(raw: "liv")
        #expect(!typo.allowsNetwork, "a mistyped gate resolved to a live one")
        let complaint = try #require(typo.complaint)
        #expect(complaint.contains("liv"), "the complaint does not quote what was actually set")
        #expect(RemoteAccess.live.complaint == nil)
        #expect(RemoteAccess.disabled.complaint == nil)
    }

    @Test("only `live` opens the gate")
    func onlyLiveIsLive() {
        #expect(RemoteAccess.live.allowsNetwork)
        #expect(!RemoteAccess.disabled.allowsNetwork)
        #expect(!RemoteAccess.misconfigured(raw: "true").allowsNetwork)
        // `true`, `1` and `yes` are the values somebody reaches for by habit, and none of them is
        // this gate's vocabulary. They must not open it by accident.
        for guess in ["true", "1", "yes", "YES", "on"] {
            #expect(
                !RemoteAccess.misconfigured(raw: guess).allowsNetwork,
                "\(guess) opened the gate"
            )
        }
    }

    // MARK: - 2. What the default does to the composition root

    private static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-remote-access-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// **`DataLayer.boot()` as the app calls it wires no send sink**, and the drain below is the
    /// observable end of that.
    ///
    /// This is the test the round exists for. It passes no `transport:` and no `remoteAccess:`, so
    /// it takes exactly the path `AppModel` takes — which is the path the UI suite takes, because
    /// the UI suite boots the real app.
    ///
    /// **Its headline used to read "wires no send sink and opens no socket", and the second half was
    /// not this test's to claim** (review of PR #84, F1). What this observes is the *outbox*. The
    /// process had another socket the whole time — `AppSession`'s, built on `AuthClient()`'s live
    /// defaults outside this gate — and nothing here could have seen it, which is precisely why it
    /// went unnoticed until a caller appeared. `RemoteAccessSignInTests` makes the process-level
    /// claim, with a `URLProtocol` and a control request.
    ///
    /// The drain is the observable end of it: with the gate off there is no send sink, so a queued
    /// visit settles `done` on the apply half alone and `report.sent` is zero. Before this gate the
    /// same call reached `cypress-sync` and the item's fate depended on a deployed service.
    @Test("boot with no arguments wires no send sink, and a drain settles without a network")
    func theAppsOwnBootIsOffline() async throws {
        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil)

        #expect(data.remoteAccess == .disabled, "the app's own boot resolved \(data.remoteAccess)")

        let tree = try await data.local.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-remote-access.jpg",
                attribution: Attribution.anonymous(deviceID: data.deviceID)
            )
        )
        // `addTree` is one of spec §3.4's nine and now queues an `add_tree` row of its own,
        // in the transaction that adds the tree. This test is not about that row, and the
        // counts below would otherwise be counting the fixture.
        try await OutboxTestSupport.discardFixtureRows(in: data.store)

        _ = try await data.outbox.enqueue(
            .visit(Visit(
                treeID: tree.id,
                attribution: Attribution.anonymous(deviceID: data.deviceID),
                capturedAt: Date()
            ))
        )
        let report = try await data.outbox.drain()

        #expect(report.sent == 0, "\(report.sent) items were sent by a build with the gate off")
        #expect(report.synced == 1, "the local commit did not happen with the gate off")

        let record = try #require(try await data.outbox.records().first)
        #expect(record.locallyApplied, "the gate took the local write with it")
        #expect(!record.remoteSent)
        #expect(record.item.state == .done, "an offline drain did not settle the item")
    }

    /// The router is still the router, and its remote half refuses in-process.
    ///
    /// `.disabled` deliberately does **not** collapse `api` to a bare `LocalAPI`: the shape under
    /// test stays the shape that ships, so a Class R read exercises its documented fallback instead
    /// of a composition the app does not have. What it must not do is open a socket, and the proof
    /// of that is the error — `SessionError.noCredential` is thrown by `RefusingTransport` before
    /// any request is formed, where a real attempt against an unreachable host would surface a
    /// `URLError` after a DNS timeout.
    @Test("the gate keeps the router and refuses in-process rather than over a socket")
    func theRouterSurvivesTheGate() async throws {
        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil)
        let router = try #require(data.api as? RoutedAPI, "the gate replaced the router")

        await #expect(throws: SessionError.noCredential) {
            _ = try await router.remote.groveDelta()
        }

        // And the fallback the router documents really is what a screen gets: `grove()` answers
        // from the phone and marks itself rather than throwing.
        _ = try await data.api.grove()
        #expect(await data.readLog.degradedReads.contains(.grove), "a refused read was not marked")
    }

    /// A Class L read is unchanged by the gate, which is the other half of §4.3's invariant: "no
    /// Class L read is allowed to acquire a remote failure mode" — and none may acquire a
    /// *gate*-shaped one either.
    @Test("a Class L read answers the same with the gate off")
    func classLIsUntouched() async throws {
        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil)
        _ = try await data.local.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-remote-access-l.jpg",
                attribution: Attribution.anonymous(deviceID: data.deviceID)
            )
        )
        let content = try await data.api.mapContent(
            in: MapViewport(
                bounds: BoundingBox(around: Coordinate(latitude: 37.77, longitude: -122.44), radiusM: 200),
                zoom: 17
            )
        )
        #expect(content.pinCount == 1, "the map read answered \(content.pinCount), expected 1")
    }

    /// `OfflineSession` refuses in-process, which is what makes the *second* socket safe.
    ///
    /// `RefusingTransport` covers `RemoteAPI`. `CityDownloader` holds its own `URLSession` and has
    /// always been able to reach a live manifest host from the Cities screen; the composition root
    /// hands it this session when the gate is off. Asserted through `CityDownloader` itself rather
    /// than through the protocol class, because what matters is that the seam the app wires cannot
    /// reach anything.
    ///
    /// ── This test was vacuous, and the way it was vacuous is the point ─────────────────────────
    ///
    /// The first version asserted `throws: (any Error).self` against a `.invalid` host. Review of
    /// round 4 replaced `OfflineSession.make()` with `URLSession.shared` — the Tigris socket wide
    /// open — **and it still passed**, because a reserved-TLD hostname fails DNS on a live session
    /// too. "Something threw" cannot tell an offline session from an online one when the URL is
    /// unreachable either way, so the test asserted nothing about the thing it was named for.
    ///
    /// The repair is a discriminator, which is what the sibling gates in this target already do
    /// (`aMissingStagedFileIsNeitherATaxonomyCodeNorARemoteSurface` asserts
    /// `SessionError.malformedResponse` and not "an error"). `OfflineSession.Refuser` fails with
    /// **`.notConnectedToInternet` (−1009)**; a live `URLSession` against this host fails with
    /// `.cannotFindHost` (−1003), and a stub with nothing parked would give `.unsupportedURL`
    /// (−1002). Three different codes, so the assertion now separates the three cases it has to.
    ///
    /// The observed code is quoted in the failure message rather than only compared, because the
    /// number is the whole diagnosis: −1003 in that message says "this ran against a real network".
    @Test("the offline session refuses in-process, and not merely because the host is unreachable")
    func theOfflineSessionRefuses() async throws {
        let downloader = CityDownloader(
            baseURL: URL(string: "https://cypress-cities.invalid")!,
            session: OfflineSession.make()
        )
        do {
            _ = try await downloader.fetchManifest()
            Issue.record("the manifest fetch succeeded; this session is not offline at all")
        } catch let error as URLError {
            #expect(
                error.code == .notConnectedToInternet,
                """
                the offline session failed with \(error.code.rawValue) \(error.code), not −1009 \
                notConnectedToInternet. −1003 cannotFindHost means the request left the process and \
                resolved DNS, so the seam under test is a live URLSession.
                """
            )
        } catch {
            Issue.record("failed with \(type(of: error)) rather than a URLError: \(error)")
        }
    }

}

/// The sign-in path's own gate proofs, in a suite of their own and **serialized**.
///
/// `RecordingProtocol` is registered globally — it has to be, because the subject is
/// `URLSession.shared` — so it is one recorder shared by every test that installs it. Swift Testing
/// runs tests in parallel by default, and the first cut of these two ran concurrently and each saw
/// the other's control request. `.serialized` is what makes each reading its own.
///
/// The assertions are also written to survive unrelated traffic: the calibration asks whether its
/// own control was *seen*, and the measurement asks whether anything reached the **service**, rather
/// than either one requiring the recording to be empty of everything.
@Suite("RemoteAccess — the sign-in path", .serialized)
struct RemoteAccessSignInTests {

    private static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-remote-signin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// Every URL recorded that names the service. The one question these tests ask.
    private static func serviceCalls() -> [String] {
        RecordingProtocol.observed().filter {
            $0.contains("cypress-sync") || $0.contains("/auth/") || $0.contains("/devices/")
        }
    }

    /// **`DataLayer.boot()` as the app calls it opens no socket for a sign-in either** (review of
    /// PR #84, F1).
    ///
    /// The gate covered `RemoteAPI`'s wire and nothing else. `boot` built its `AppSession` as
    /// `AppSession(deviceUUID:)` — the default `AuthClient()`, which is `SyncService.defaultBaseURL`
    /// over `URLSession.shared` — and `boot`'s own `baseURL:` never reached it. `signInWithApple`
    /// goes through neither `SessionTransport` nor `RefusingTransport`, so with the gate `.disabled`
    /// a tap on screen 15 still dialled `https://cypress-sync.fly.dev/api/v1/auth/oidc`. The
    /// reviewer measured exactly that, and this is their probe kept as a test.
    ///
    /// **`theAppsOwnBootIsOffline` above could never have caught it**: that test observes the
    /// *outbox*, and the new socket is not the outbox's. This one observes the process.
    ///
    /// ── Calibration, which is the half that makes it a measurement ─────────────────────────────
    ///
    /// A recorder that intercepts nothing reports an empty list, and an empty list is what "no
    /// socket was opened" looks like — the two are indistinguishable without a control. So the
    /// control runs **first**: a deliberate request to a `.invalid` host must be *recorded*, proving
    /// the protocol is in front of `URLSession.shared`, before the measured call is believed. That
    /// is CLAUDE.md's "calibrate the instrument before you trust the reading", and the reviewer used
    /// the same order.
    ///
    /// Nothing leaves the machine either way: `URLProtocol.startLoading` fails every request
    /// in-process, and the control's host does not resolve.
    @Test("the app's own boot cannot reach the service for a sign-in either")
    func theAppsOwnBootDoesNotDialTheSignIn() async throws {
        URLProtocol.registerClass(RecordingProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingProtocol.self) }
        RecordingProtocol.reset()

        // ── Control: prove the recorder sees a request through `URLSession.shared` at all. ──────
        let control = URL(string: "https://cypress-remote-access-control.invalid/probe")!
        _ = try? await URLSession.shared.data(from: control)
        let calibration = RecordingProtocol.observed()
        #expect(
            calibration.contains(control.absoluteString),
            """
            the recorder saw \(calibration) and not the control request it was pointed at, so it is \
            not in front of URLSession.shared and the measurement below would report "no socket" no \
            matter what the app did. Nothing is proved until this line passes.
            """
        )
        RecordingProtocol.reset()

        // ── The measurement. `boot` exactly as `AppModel` calls it. ────────────────────────────
        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil)
        #expect(data.remoteAccess == .disabled, "the app's own boot resolved \(data.remoteAccess)")

        _ = try? await data.session.signInWithApple(
            AppleIdentityCredential(
                identityToken: "not-a-token",
                authorizationCode: "not-a-code",
                rawNonce: "not-a-nonce"
            ),
            licenseVersion: .declined
        )

        let reached = Self.serviceCalls()
        #expect(
            reached.isEmpty,
            """
            with RemoteAccess == .disabled a sign-in opened \(reached). The gate covers RemoteAPI's \
            wire and this path goes through neither transport, so a DEBUG build — which is every UI \
            test on every runner — posts a real credential at production the moment somebody taps \
            screen 15's Apple button.
            """
        )
    }

    /// The other half of the same gate, at the type rather than through `boot`: a device
    /// registration is the *first* thing `AppSession` does on a fresh install, and it must not dial
    /// either.
    @Test("a device registration under the gate refuses in-process rather than over a socket")
    func theGateStopsDeviceRegistrationToo() async throws {
        URLProtocol.registerClass(RecordingProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingProtocol.self) }
        RecordingProtocol.reset()

        let control = URL(string: "https://cypress-remote-access-control2.invalid/probe")!
        _ = try? await URLSession.shared.data(from: control)
        #expect(
            RecordingProtocol.observed().contains(control.absoluteString),
            "the recorder is not in front of URLSession.shared; nothing below is a measurement"
        )
        RecordingProtocol.reset()

        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil)
        _ = try? await data.session.authorization()

        #expect(
            Self.serviceCalls().isEmpty,
            "a device registration under the gate opened \(Self.serviceCalls())"
        )
    }
}

/// Records every URL a request is made for, and intercepts **only the hosts these tests are about**.
///
/// Registered globally rather than on one `URLSessionConfiguration`, because the subject is
/// `URLSession.shared` — the session `AuthClient()` uses by default, and the one the defect ran on.
/// A scoped protocol could not see it.
///
/// ── Why `canInit` is narrow, which is a regression this suite caused and a reviewer caught ──────
///
/// The first version returned `true` for **every** request in the process and failed all of them
/// with `-1009`. `URLProtocol.registerClass` is process-wide, and `.serialized` only serializes
/// tests *within* a suite — Swift Testing runs other suites in parallel with this one, so anything
/// making a request during the window got the refusal. `CityDownloadTests` was in the blast radius:
/// `CityDownloader(baseURL: dir)` reads a `file://` directory over `URLSession.shared`, and `canInit`
/// did not exempt `file://` either. Three of its tests failed with `NSURLErrorDomain Code=-1009`,
/// naming a defect that did not exist, in a suite with nothing to do with this one.
///
/// **It was scheduling-dependent, which is what made it worth blocking on rather than tolerating.**
/// The author's own full run was green and the reviewer's was red three times out of three; a gate
/// that fails on thread timing meets CI eventually rather than reliably. Diagnosed by controlled
/// experiment rather than by inspection: `CityDownloadTests` alone passes 11/11, and
/// `CityDownloadTests` **plus** this suite reproduces all three failures.
///
/// So: **record everything, intercept only ours.** The recording is what makes a failure
/// diagnosable — an unexpected host still shows up in `observed()` — while `canInit` claims only
/// `cypress-sync` (the service these tests are about) and the `.invalid` control hosts (a reserved
/// TLD that can never resolve, so claiming it costs nothing). Every other request in the process is
/// left exactly as it would be with this protocol unregistered.
///
/// What is *claimed* never leaves: `startLoading` reports `notConnectedToInternet`, the same failure
/// `OfflineSession.Refuser` reports, so a code path that reaches it takes the offline branch rather
/// than hanging on a real timeout.
final class RecordingProtocol: URLProtocol {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var urls: [String] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        urls = []
    }

    static func observed() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        urls.append(request.url?.absoluteString ?? "<no url>")
        lock.unlock()
        return isOurs(request.url)
    }

    /// The hosts this protocol is entitled to answer for. Everything else is recorded and passed
    /// straight through — see the type's header for what happened when it was not.
    private static func isOurs(_ url: URL?) -> Bool {
        guard let host = url?.host else { return false }
        return host.contains("cypress-sync") || host.hasSuffix(".invalid")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
