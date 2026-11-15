//
//  LicenseAcceptanceTests.swift
//  CypressTests
//
//  "Share my tree records" on the You tab (the owner's decision of 2026-11-15): a signed-in person
//  who declined the license at sign-in agrees to it later.
//
//  What is pinned here, in the order the feature runs:
//  - the row shows exactly when "You did not agree…" shows;
//  - "Share" asks the service once, on `POST /devices/claim`, with the account's token and a body
//    of exactly `device_uuid` and `license_version`; "Cancel" asks nothing;
//  - only a yes from the service writes the phone, and then the line says "You agreed…";
//  - every failure writes nothing and shows "That did not go through.", and a later success
//    clears it;
//  - a second tap while the first request is in flight sends nothing.
//
//  The phone is set up in the declined state directly (a session in the credential store, and
//  `LocalAPI.linkAccount(acceptsLicense: false)`), rather than through `RootView.accountLink()`,
//  so the offline case can hold a session whose wire refuses everything.
//

import Foundation
import Testing
@testable import Cypress

@MainActor
@Suite("Share my tree records: agreeing to the license after declining it")
struct LicenseAcceptanceTests {

    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000005A1")!
    static let userID = AppleSignInFixture.serverUserID

    /// The clock the session reads. `ScriptedAuthHTTP.session` mints a token that is live for 900 s
    /// from this instant, so a fixed clock keeps the token live whatever day the suite runs.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let agreedLine = "You agreed to share your tree records under the open database license."
    static let declinedLine = "You did not agree to share your tree records under the open database license."

    // MARK: - Rig

    /// What `/devices/claim` answers. Changeable between taps, so one test can fail and then retry.
    final class ClaimAnswer: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: (Int, Data)
        init(_ status: Int, _ body: Data = Data(#"{"claimed":true}"#.utf8)) { answer = (status, body) }
        var current: (Int, Data) {
            lock.lock(); defer { lock.unlock() }
            return answer
        }
        func set(_ status: Int, _ body: Data = Data(#"{"claimed":true}"#.utf8)) {
            lock.lock(); defer { lock.unlock() }
            answer = (status, body)
        }
    }

    /// The far side: `/devices/claim` answers what `claim` says; anything else is a 404, so a request
    /// to a route this feature should not touch shows up as a failure rather than a silent pass.
    static func scripted(_ claim: ClaimAnswer) -> ScriptedAuthHTTP {
        ScriptedAuthHTTP { request in
            guard request.url?.path.hasSuffix("/devices/claim") == true else {
                return (404, Data(#"{"error":{"code":"not_found","message":"no"}}"#.utf8))
            }
            return claim.current
        }
    }

    /// A service refusal in the taxonomy's own shape.
    static func refusal(_ code: String) -> Data {
        Data(#"{"error":{"code":"\#(code)","message":"refused"}}"#.utf8)
    }

    struct Rig {
        let store: CypressStore
        let api: LocalAPI
        let session: AppSession
        let model: AccountModel
    }

    /// A phone signed in as `userID` that declined the license at sign-in.
    ///
    /// - Parameter withSession: false leaves the credential store empty while the database says
    ///   signed in, the shape of a session the service has already ended.
    static func declinedPhone(http: any AuthHTTP, withSession: Bool = true) async throws -> Rig {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let credentials = InMemoryCredentialStore()
        if withSession {
            let minted = try AuthCoding.decoder.decode(
                SessionCredentials.self,
                from: ScriptedAuthHTTP.session(userID: userID, now: now)
            )
            try credentials.setData(try AuthCoding.encoder.encode(minted), forKey: CredentialKey.session)
        }
        let session = AppSession(
            deviceUUID: deviceID,
            client: AuthClient(baseURL: ScriptedAuthHTTP.baseURL, http: http),
            credentials: credentials,
            now: { now }
        )
        try await api.linkAccount(
            deviceUUID: deviceID,
            userID: userID,
            provider: AccountAskProvider.apple.rawValue,
            acceptsLicense: false
        )
        let model = AccountModel(api: api, session: session)
        await model.load()
        return Rig(store: store, api: api, session: session, model: model)
    }

    /// The declined state, read back from the model, as a precondition every test states.
    static func expectDeclined(_ rig: Rig, _ comment: Comment) async throws {
        #expect(rig.model.isSignedIn, comment)
        #expect(rig.model.link?.acceptsLicense == false, comment)
        #expect(AccountCopy.licenseLine(for: rig.model.link) == declinedLine, comment)
        #expect(AccountCopy.offersLicenseAcceptance(isSignedIn: rig.model.isSignedIn, link: rig.model.link), comment)
        #expect(try await rig.store.appState(.accountLicenseVersion) == nil, comment)
    }

    // MARK: - 1. When the row shows

    @Test("the row shows only for a signed-in account whose stored answer is declined")
    func rowShowsOnlyWhenDeclined() {
        let declined = AccountLinkRecord(provider: "apple", licenseVersion: nil)
        let agreed = AccountLinkRecord(provider: "apple", licenseVersion: LicenseConsent.currentVersion)
        let unknown = AccountLinkRecord(provider: nil, licenseVersion: nil)

        #expect(AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: declined))
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: agreed), "shown to an account that agreed")
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: unknown), "shown when the answer is unknown")
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: nil), "shown with no record")
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: false, link: declined), "shown while signed out")
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: false, link: nil), "shown while signed out")

        // And it tracks the line it sits under: the row is offered exactly when the line says
        // "did not agree".
        for link in [declined, agreed, unknown, nil] as [AccountLinkRecord?] {
            #expect(
                AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: link)
                    == (AccountCopy.licenseLine(for: link) == Self.declinedLine)
            )
        }
    }

    @Test("the row, the confirmation and the failure line say the owner's exact words")
    func ownerCopy() {
        #expect(AccountCopy.shareRecordsTitle == "Share my tree records")
        #expect(AccountCopy.shareRecordsSubtitle == "Under the open database license. Anyone may use the data")
        #expect(AccountCopy.shareRecordsConfirmTitle == "Share my tree records?")
        #expect(
            AccountCopy.shareRecordsConfirmMessage
                == "Everyone using Cypress will see the trees you have added. This cannot be undone."
        )
        #expect(AccountCopy.shareRecordsConfirmAction == "Share")
        #expect(AccountCopy.shareRecordsConfirmCancel == "Cancel")
        #expect(AccountCopy.shareRecordsFailed == "That did not go through.")
    }

    // MARK: - 2. The confirmation's two buttons

    @Test("\"Share\" agrees once and \"Cancel\" does nothing")
    func confirmationButtons() {
        var calls = 0
        ShareRecordsConfirmation.respond(to: .cancel) { calls += 1 }
        #expect(calls == 0, "Cancel started an agreement")
        ShareRecordsConfirmation.respond(to: .share) { calls += 1 }
        #expect(calls == 1, "Share did not start exactly one agreement")
    }

    // MARK: - 3. The request

    @Test("Share sends one POST /devices/claim with the account's token and exactly two keys")
    func theRequest() async throws {
        let http = Self.scripted(ClaimAnswer(200))
        let rig = try await Self.declinedPhone(http: http)

        await rig.model.acceptLicense()

        let requests = await http.requests
        try #require(requests.count == 1, "expected one request, saw \(requests.map { $0.url?.path ?? "?" })")
        let request = requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == ScriptedAuthHTTP.baseURL.path + "/devices/claim")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1",
                "not sent with the account's access token")

        let body = try #require(await http.bodies(to: "/devices/claim").first)
        #expect(Set(body.keys) == ["device_uuid", "license_version"], "the service refuses any other key")
        #expect(body["license_version"] as? String == LicenseConsent.currentVersion)
        #expect((body["device_uuid"] as? String)?.uppercased() == Self.deviceID.uuidString)
    }

    @Test("with no account session, nothing is sent and the call throws noCredential")
    func noSessionSendsNothing() async throws {
        let http = Self.scripted(ClaimAnswer(200))
        let rig = try await Self.declinedPhone(http: http, withSession: false)

        await #expect(throws: SessionError.noCredential) { try await rig.session.acceptLicense() }
        #expect(await http.requests.isEmpty, "a request went out with no account behind it")
    }

    // MARK: - 4. Success

    @Test("a yes from the service writes the phone, and the line then says the person agreed")
    func successWritesThePhone() async throws {
        let http = Self.scripted(ClaimAnswer(200))
        let rig = try await Self.declinedPhone(http: http)
        try await Self.expectDeclined(rig, "precondition")

        await rig.model.acceptLicense()

        #expect(rig.model.licenseAcceptanceFailed == false)
        #expect(rig.model.isBusy == false)
        #expect(rig.model.isSignedIn)
        #expect(rig.model.link?.acceptsLicense == true, "the phone was not written")
        #expect(try await rig.store.appState(.accountLicenseVersion) == LicenseConsent.currentVersion)
        #expect(AccountCopy.licenseLine(for: rig.model.link) == Self.agreedLine)
        #expect(
            !AccountCopy.offersLicenseAcceptance(isSignedIn: rig.model.isSignedIn, link: rig.model.link),
            "the row is still offered after agreeing"
        )
        #expect(rig.model.link?.provider == AccountAskProvider.apple.rawValue, "the provider was lost")
        #expect(await http.requests.count == 1)
    }

    // MARK: - 5. Failure

    enum Failure: String, CaseIterable, CustomTestStringConvertible {
        case offline
        case serverError
        case forbidden
        case conflict
        var testDescription: String { rawValue }
    }

    /// The wire for each failure. `offline` is `OfflineSession.make()`, which is also exactly what a
    /// shut remote gate hands `AppSession` (`DataLayer.boot`).
    static func wire(for failure: Failure) -> any AuthHTTP {
        switch failure {
        case .offline: return OfflineSession.make()
        case .serverError: return scripted(ClaimAnswer(503, refusal("server_error")))
        case .forbidden: return scripted(ClaimAnswer(403, refusal("forbidden")))
        case .conflict: return scripted(ClaimAnswer(409, refusal("conflict")))
        }
    }

    @Test("every failure writes nothing on the phone and says it did not go through",
          arguments: Failure.allCases)
    func failureWritesNothing(_ failure: Failure) async throws {
        let rig = try await Self.declinedPhone(http: Self.wire(for: failure))

        await rig.model.acceptLicense()

        #expect(rig.model.licenseAcceptanceFailed, "\(failure): the failure was not reported")
        #expect(rig.model.isBusy == false)
        try await Self.expectDeclined(rig, "\(failure): the phone changed after a failure")
    }

    @Test("a session the service already ended fails the same way and sends nothing")
    func endedSessionFails() async throws {
        let http = Self.scripted(ClaimAnswer(200))
        let rig = try await Self.declinedPhone(http: http, withSession: false)

        await rig.model.acceptLicense()

        #expect(rig.model.licenseAcceptanceFailed)
        try await Self.expectDeclined(rig, "the phone changed with no session")
        #expect(await http.requests.isEmpty)
    }

    @Test("a later success clears the failure line")
    func retryClearsTheFailure() async throws {
        let claim = ClaimAnswer(503, Self.refusal("server_error"))
        let http = Self.scripted(claim)
        let rig = try await Self.declinedPhone(http: http)

        await rig.model.acceptLicense()
        #expect(rig.model.licenseAcceptanceFailed)
        try await Self.expectDeclined(rig, "after the first, failed try")

        claim.set(200)
        await rig.model.acceptLicense()

        #expect(rig.model.licenseAcceptanceFailed == false, "the failure line outlived a success")
        #expect(rig.model.link?.acceptsLicense == true)
        #expect(await http.requests.count == 2)
    }

    // MARK: - 6. In flight

    /// A wire that holds every `/devices/claim` until `open()`, so a test can tap again while the
    /// first request is in flight.
    actor HeldClaimHTTP: AuthHTTP {
        private(set) var claims = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            claims += 1
            if !isOpen {
                await withCheckedContinuation { waiting.append($0) }
            }
            let response = HTTPURLResponse(
                url: request.url ?? ScriptedAuthHTTP.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(#"{"claimed":true}"#.utf8), response)
        }

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    @Test("a second tap while the first request is in flight sends no second request")
    func secondTapInFlight() async throws {
        let http = HeldClaimHTTP()
        let rig = try await Self.declinedPhone(http: http)

        let first = Task { await rig.model.acceptLicense() }
        // Bounded: wait for the first request to reach the wire.
        for _ in 0..<500 {
            if await http.claims > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await http.claims == 1, "the first tap never reached the wire")
        #expect(rig.model.isBusy, "the row would still take taps while the request is in flight")

        let second = Task { await rig.model.acceptLicense() }
        // Give a second request every chance to reach the wire before the first is released.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))

        await http.open()
        await first.value
        await second.value

        #expect(await http.claims == 1, "a second tap sent a second request")
        #expect(rig.model.link?.acceptsLicense == true)
        #expect(rig.model.licenseAcceptanceFailed == false)
    }

    // MARK: - 7. The contract with the service, read from its source

    /// The `json:` tags of a Go struct, read from source text.
    static func jsonTags(ofStruct name: String, in source: String) -> Set<String>? {
        guard let start = source.range(of: "type \(name) struct {") else { return nil }
        guard let end = source.range(of: "\n}", range: start.upperBound..<source.endIndex) else { return nil }
        let block = source[start.upperBound..<end.lowerBound]
        let pattern = try! NSRegularExpression(pattern: #"json:"([a-z_]+)"#)
        let text = String(block)
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    @Test("the body's keys are the json tags of the service's claimRequest")
    func bodyMatchesTheServer() throws {
        // Calibrate the reader on a specimen whose answer is known, including a field after a
        // comment line, before believing what it says about the real file.
        let specimen = """
        type specimen struct {
        \tA string `json:"alpha"`
        \t// a comment
        \tB json.RawMessage `json:"beta_gamma"`
        }
        type other struct {
        \tC string `json:"not_this"`
        }
        """
        #expect(Self.jsonTags(ofStruct: "specimen", in: specimen) == ["alpha", "beta_gamma"])

        let url = AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("server/internal/api/auth.go")
        let source = try String(contentsOf: url, encoding: .utf8)
        let serverKeys = try #require(Self.jsonTags(ofStruct: "claimRequest", in: source))

        let request = try AuthClient(baseURL: ScriptedAuthHTTP.baseURL, http: OfflineSession.make())
            .licenseAcceptanceRequest(deviceUUID: Self.deviceID, version: LicenseConsent.currentVersion)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(Set(body.keys) == serverKeys, "the phone's body and the service's claimRequest disagree")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil,
                "the builder attached a credential; SessionTransport owns that")
    }
}
