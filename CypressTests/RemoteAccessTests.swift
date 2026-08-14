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

    /// **`DataLayer.boot()` as the app calls it wires no send sink and opens no socket.**
    ///
    /// This is the test the round exists for. It passes no `transport:` and no `remoteAccess:`, so
    /// it takes exactly the path `AppModel` takes — which is the path the UI suite takes, because
    /// the UI suite boots the real app.
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
