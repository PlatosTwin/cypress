//
//  RemoteAccess.swift
//  Cypress — Data
//
//  Whether this process is allowed to reach `cypress-sync` at all (#158, the wiring round's
//  round-4 repair). A launch-environment gate in `DebugLocationOverride`'s mold — the house
//  pattern, RULINGS **R58** — with **the opposite default, on purpose**. That inversion is the
//  whole point of the file and it is argued below.
//
//  ── What went wrong, which is the only reason this exists ─────────────────────────────────────
//
//  #158 wired `DataLayer.boot` to a live `RemoteAPI` at `SyncService.defaultBaseURL`. The UI suite
//  boots the **real app**, so from that commit every UI test on a runner with a network was reading
//  Class R data from production, over production latency, against a service that was refusing
//  everything it sent (the `applyOne` defect). Three consecutive CI runs failed on three different
//  jobs and every one of them was a photo or content screen — the screens whose reads the router
//  had just put on a network. `fly logs` showed the production machine being autostarted and stopped
//  through the CI windows: the test loop was waking a live backend.
//
//  Nothing was wrong with any individual test. **The absence of a decision pointed the whole suite
//  at production**, and that is the shape this file is designed against.
//
//  ── Why the default is off in DEBUG, rather than "set an env var to turn it off" ──────────────
//
//  The tempting design is `CYPRESS_NO_REMOTE=1`, matching `CYPRESS_LOCATION`'s "absent means the
//  real thing". It is wrong here, for three reasons, and the third is the one that decides it:
//
//  1. **It is a deny-list over launch sites, and the list cannot be maintained.** Seventeen files in
//     `CypressUITests` construct their own `XCUIApplication()`; there is no shared launch helper to
//     put the variable in. Every future test file, every preview, every debug harness would have to
//     remember. ERRATA **E260** made exactly this repair to the camera guard — stop enumerating the
//     bad states and certifying the rest, admit one known state and rewrite everything else — and
//     the argument transfers unchanged.
//  2. **`CYPRESS_LOCATION`'s default is safe and this one would not be.** Absent, that gate falls
//     back to the real `CoreLocation` provider, which is local, free and hermetic. Absent, this gate
//     would fall back to *a network*. Copying the default because the mechanism matches would be
//     copying the shape and dropping the reason.
//  3. **The two failure modes are not comparable.** A DEBUG build that silently does not sync is a
//     local puzzle a developer solves in a minute. A test build that silently *does* sync writes
//     rows into a production database from CI, on somebody else's schedule. When one direction is
//     recoverable and the other is not, the default belongs on the recoverable side — the same
//     argument that put `LocalAPI` in `APIOutboxTransport`'s signature one round ago.
//
//  **Release builds are always live**, so nothing here can affect what ships. The gate exists
//  entirely inside `#if DEBUG`, and a release build resolves `.live` without reading the
//  environment at all.
//
//  ── The one thing it must never do quietly ────────────────────────────────────────────────────
//
//  Fail. `DebugLocationOverride`'s rule: a typo must not be indistinguishable from a decision. An
//  unrecognized value resolves to `.misconfigured`, which **behaves as `.disabled`** — fail-safe,
//  because a misspelled gate must not be a live one — and carries the raw string so the composition
//  root can say so out loud rather than leaving somebody to wonder why nothing syncs.
//

import Foundation

/// Whether this process may reach the service.
public enum RemoteAccess: Sendable, Equatable {

    /// The shipping answer: `RemoteAPI` over `SessionTransport`, and a send sink on the outbox.
    case live

    /// No socket is opened. The router is still in place — `RoutedAPI` over a refusing transport —
    /// so the code path under test is the one that ships, and every Class R read takes its
    /// documented local fallback instead of a network round trip. The outbox gets **no send sink**,
    /// which is the wiring every build before #158 shipped.
    case disabled

    /// `CYPRESS_REMOTE` held something this type does not recognize.
    ///
    /// Behaves exactly as `.disabled`. It is a separate case rather than a silent fallback so the
    /// difference between "somebody turned this off" and "somebody mistyped it" survives to a
    /// surface that can complain — the distinction `DebugLocationOverride.Request.invalid` exists
    /// for, made for the same reason.
    case misconfigured(raw: String)

    /// Whether a socket may be opened. `.misconfigured` answers `false`, which is the fail-safe
    /// reading and the only one that makes a typo harmless.
    public var allowsNetwork: Bool { self == .live }

    /// The environment key. Read from the process environment and not from `launchArguments`, for
    /// `DebugDeepLink.environmentKey`'s reason: `UserDefaults` also consumes launch arguments, so a
    /// test seam spelled that way would be writing into the reader's preferences.
    public static let environmentKey = "CYPRESS_REMOTE"

    /// What this process resolves to, with no argument passed.
    ///
    /// **This is the value the app's own `DataLayer.boot()` uses**, which is what makes the default
    /// the thing worth testing: `RemoteAccessTests` pins it, because a test that asserted the
    /// behaviour of an explicitly-passed `.disabled` would be asserting the case nobody forgets.
    public static var resolved: RemoteAccess {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment[environmentKey],
              !raw.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            // Absent. The fail-safe answer, and the reason this file exists.
            return .disabled
        }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "live": return .live
        case "off", "none", "disabled": return .disabled
        default: return .misconfigured(raw: raw)
        }
        #else
        // A shipping build talks to the service and does not consult the environment to decide it.
        return .live
        #endif
    }

    /// A sentence for a surface to draw when somebody mistyped the gate, or nil when nothing is
    /// wrong. Mirrors `DebugLocationOverride`'s banner rather than inventing a second idiom.
    public var complaint: String? {
        guard case let .misconfigured(raw) = self else { return nil }
        return """
            \(Self.environmentKey)=\(raw) is not a value this build understands, so the service is \
            switched off. Use `live`, or `off`.
            """
    }
}

/// The `AuthorizedTransport` for `.disabled`: it refuses without opening a socket.
///
/// **Why a refusing transport rather than no `RemoteAPI` at all.** Handing the router a `RemoteAPI`
/// that cannot answer keeps the shipping *shape* under test — `RoutedAPI` really is what every
/// screen holds, and every Class R read really does take its `.fellBackToLocal` path — while
/// guaranteeing no packet leaves the process. Replacing the router with a bare `LocalAPI` would
/// test a composition the app does not have.
///
/// **It throws `SessionError.noCredential` and deliberately not an `APIError`.** A taxonomy code
/// here would be a statement about a record, and there is no record involved; `noCredential` is
/// already the file's word for "this process cannot present a credential", which is exactly true.
/// It is also outside the taxonomy, so an outbox item that met one would stay alive on the backoff
/// rather than fail terminally (ERRATA **E261** §3) — and with no send sink wired under this case,
/// no outbox item ever meets it.
///
/// **`RemoteAPI.session` is unreachable under this transport**, and that is a property of the two
/// methods that use it rather than of this type: `photoData(id:)` calls `transport.send` before it
/// touches `session`, and `uploadPhoto(at:ticket:)` is reached only from the apply sink, which is
/// `LocalAPI`. Stated here because it is the reason gating the transport is sufficient.
public struct RefusingTransport: AuthorizedTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> Data {
        throw SessionError.noCredential
    }
}

/// A `URLSession` that cannot reach anything, for the seams that hold a session rather than a
/// transport.
///
/// `RefusingTransport` covers `RemoteAPI`, which is the seam #158 added. It is not the only one:
/// `CityDownloader` fetches a manifest from `cypress-cities.t3.tigrisbucket.io` with its own
/// `URLSession`, and `CityDownloadsModel` constructs one by default — so a UI test that opened the
/// Cities screen has always been able to reach a live host. That predates this ticket and is not
/// what broke CI, but it is the same defect, and a round that makes the app-under-test hermetic and
/// leaves one live socket open has not made it hermetic.
///
/// A refusing `URLProtocol` rather than a bad base URL, because a bad URL still resolves DNS and
/// still takes a timeout; this fails in-process, immediately, and cannot be defeated by a caller
/// that builds its own request.
public enum OfflineSession {

    /// Fails every request with `URLError(.notConnectedToInternet)` — the error a caller offline
    /// would really see, so the code under test takes the path it takes in a park.
    public final class Refuser: URLProtocol {
        override public class func canInit(with request: URLRequest) -> Bool { true }
        override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override public func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override public func stopLoading() {}
    }

    public static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Refuser.self]
        return URLSession(configuration: configuration)
    }
}
