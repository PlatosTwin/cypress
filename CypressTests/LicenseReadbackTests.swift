//
//  LicenseReadbackTests.swift
//  CypressTests
//
//  The account's license answer, read back from the service (ROADMAP chips 148 and 155).
//
//  Both session answers carry `license_version`. The phone keeps it in the stored session, adopts
//  it at launch with no request, and adopts each refresh's answer in the same run. A person who
//  declined, then reinstalled, sees "You did not agree…" and the "Share my tree records" row again.
//
//  A reinstall is staged the way `SessionRestoreTests` stages it: a new database directory beside a
//  credential store that was carried over.
//

import Foundation
import Testing
@testable import Cypress

private enum ReadbackFixture {

    static let accountID = UUID(uuidString: "5E12E12E-0000-4000-8000-00000000AB01")!
    static let otherAccountID = UUID(uuidString: "5E12E12E-0000-4000-8000-00000000AB02")!
    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AB03")!

    static let agreedLine = "You agreed to share your tree records under the open database license."
    static let declinedLine = "You did not agree to share your tree records under the open database license."

    /// A session answer as the service writes it. `license` is the raw JSON value of the key, or nil
    /// to leave the key out (an older service).
    static func sessionJSON(
        userID: UUID,
        license: String?,
        accessLifetime: TimeInterval = 15 * 60,
        refreshLifetime: TimeInterval = 60 * 24 * 60 * 60
    ) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let licenseField = license.map { #","license_version":\#($0)"# } ?? ""
        return Data("""
        {"access_token":"access-\(UUID().uuidString)","refresh_token":"refresh-\(UUID().uuidString)",\
        "expires_at":"\(formatter.string(from: now.addingTimeInterval(accessLifetime)))",\
        "refresh_expires_at":"\(formatter.string(from: now.addingTimeInterval(refreshLifetime)))",\
        "user_id":"\(userID.uuidString)"\(licenseField)}
        """.utf8)
    }

    /// Store a session the way `AppSession.persist` does: decoded off the wire, encoded into the
    /// credential store.
    static func seedSession(
        _ credentials: InMemoryCredentialStore,
        userID: UUID = accountID,
        license: String?,
        accessLifetime: TimeInterval = 15 * 60
    ) throws {
        let session = try AuthCoding.decoder.decode(
            SessionCredentials.self,
            from: sessionJSON(userID: userID, license: license, accessLifetime: accessLifetime)
        )
        try credentials.setData(try AuthCoding.encoder.encode(session), forKey: CredentialKey.session)
    }

    static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-license-readback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    static func boot(
        databaseURL: URL,
        credentials: InMemoryCredentialStore,
        http: ScriptedAuthHTTP
    ) async throws -> DataLayer {
        try await DataLayer.boot(
            databaseURL: databaseURL,
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            authHTTP: http,
            remoteAccess: .disabled,
            credentials: credentials
        )
    }

    static func silentHTTP() -> ScriptedAuthHTTP {
        ScriptedAuthHTTP { _ in (500, Data("{}".utf8)) }
    }

    /// What the phone would draw: the sharing state, from the two facts it stores.
    static func sharing(_ local: LocalAPI) async throws -> ContributionSharing {
        ContributionSharing(userID: await local.userID, link: try await local.accountLink())
    }
}

// MARK: - 1. The stored session keeps all three states

@Suite("The session answer's license_version: three states, kept through the Keychain")
struct SessionLicenseCodingTests {

    @Test("a missing key, a null and a string decode to three different answers",
          arguments: [(nil as String?, AuthClient.LicenseAnswer.unstated),
                      ("null", .declined),
                      (#""odbl-1.0""#, .accepted("odbl-1.0"))])
    func threeStates(_ raw: String?, _ expected: AuthClient.LicenseAnswer) throws {
        let decoded = try AuthCoding.decoder.decode(
            SessionCredentials.self,
            from: ReadbackFixture.sessionJSON(userID: ReadbackFixture.accountID, license: raw)
        )
        #expect(decoded.licenseVersion == expected, "license_version \(raw ?? "(missing)") decoded as \(decoded.licenseVersion)")

        // And the stored form keeps it: encode as `AppSession.persist` does, decode as
        // `storedSession` does.
        let stored = try AuthCoding.encoder.encode(decoded)
        let restored = try AuthCoding.decoder.decode(SessionCredentials.self, from: stored)
        #expect(restored == decoded, "the Keychain round trip changed the session")
        #expect(restored.licenseVersion == expected, "the Keychain round trip read back \(restored.licenseVersion)")
        let object = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(
            object.keys.contains("license_version") == (raw != nil),
            "the stored form \(raw == nil ? "wrote" : "dropped") the license_version key"
        )
    }

    /// A session stored by an older build has no `license_version`. It is still a usable session, so
    /// it must decode, as "not stated"; failing would sign the person out.
    @Test("a session stored before the field existed still decodes, as not stated")
    func anOldStoredSessionDecodes() throws {
        let old = Data("""
        {"access_token":"a","refresh_token":"r","expires_at":"2027-01-15T08:00:00Z",\
        "refresh_expires_at":"2027-03-15T08:00:00Z","user_id":"\(ReadbackFixture.accountID.uuidString)"}
        """.utf8)
        let decoded = try AuthCoding.decoder.decode(SessionCredentials.self, from: old)
        #expect(decoded.userID == ReadbackFixture.accountID)
        #expect(decoded.licenseVersion == .unstated)
    }
}

// MARK: - 2. Launch, refresh, and the guard

@MainActor
@Suite("The phone adopts the service's license answer")
struct LicenseReadbackTests {

    @Test("a reinstall over a declined session reads did-not-agree and offers the row, with no request")
    func restoreDeclined() async throws {
        let credentials = InMemoryCredentialStore()
        try ReadbackFixture.seedSession(credentials, license: "null")
        let http = ReadbackFixture.silentHTTP()

        let data = try await ReadbackFixture.boot(
            databaseURL: try ReadbackFixture.databaseURL(), credentials: credentials, http: http
        )

        #expect(await data.local.userID == ReadbackFixture.accountID, "the session was not restored")
        #expect(try await ReadbackFixture.sharing(data.local) == .notSharing)
        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        #expect(AccountCopy.licenseLine(for: account.link) == ReadbackFixture.declinedLine)
        #expect(
            AccountCopy.offersLicenseAcceptance(isSignedIn: account.isSignedIn, link: account.link),
            "the restored phone does not offer \"Share my tree records\""
        )
        let calls = await http.requests
        #expect(calls.isEmpty, "the launch made \(calls.count) request(s): \(calls.compactMap { $0.url?.path })")
    }

    @Test("a reinstall over an accepted session reads agreed, and offers no row")
    func restoreAccepted() async throws {
        let credentials = InMemoryCredentialStore()
        try ReadbackFixture.seedSession(credentials, license: #""odbl-1.0""#)
        let http = ReadbackFixture.silentHTTP()

        let data = try await ReadbackFixture.boot(
            databaseURL: try ReadbackFixture.databaseURL(), credentials: credentials, http: http
        )

        #expect(try await ReadbackFixture.sharing(data.local) == .sharing)
        #expect(try await data.local.accountLink()?.licenseVersion == "odbl-1.0")
        let link = try await data.local.accountLink()
        #expect(AccountCopy.licenseLine(for: link) == ReadbackFixture.agreedLine)
        #expect(!AccountCopy.offersLicenseAcceptance(isSignedIn: true, link: link))
        #expect(await http.requests.isEmpty)
    }

    /// The restore's other arm: the database names another account, whose answer is still on it.
    /// The incoming account reads its own answer from the service, never the outgoing one's.
    @Test("a restore over another account's stored answer reads the incoming account's answer")
    func restoreOverAnotherAccount() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try ReadbackFixture.databaseURL()

        try ReadbackFixture.seedSession(credentials, userID: ReadbackFixture.otherAccountID, license: nil)
        let asOther = try await ReadbackFixture.boot(
            databaseURL: databaseURL, credentials: credentials, http: ReadbackFixture.silentHTTP()
        )
        try await asOther.store.setAppState(.accountProvider, to: "apple")
        try await asOther.store.setAppState(.accountLicenseVersion, to: LicenseConsent.currentVersion)
        #expect(try await ReadbackFixture.sharing(asOther.local) == .sharing, "calibration: the other account was not staged as agreed")

        try ReadbackFixture.seedSession(credentials, userID: ReadbackFixture.accountID, license: "null")
        let asAccount = try await ReadbackFixture.boot(
            databaseURL: databaseURL, credentials: credentials, http: ReadbackFixture.silentHTTP()
        )

        #expect(await asAccount.local.userID == ReadbackFixture.accountID)
        #expect(
            try await ReadbackFixture.sharing(asAccount.local) == .notSharing,
            "the incoming account read the outgoing account's agreement"
        )
    }

    /// The refresh seam, through `DataLayer.boot`'s own wiring: an agreement the service recorded
    /// elsewhere arrives with the next refresh and shows in the same run.
    @Test("a refresh that carries an acceptance makes the phone read agreed in the same run")
    func refreshCarriesTheAnswer() async throws {
        let credentials = InMemoryCredentialStore()
        // An older build's session: no answer, and an access token that has already expired, so the
        // first credential asked for is a refresh.
        try ReadbackFixture.seedSession(credentials, license: nil, accessLifetime: -60)
        let http = ScriptedAuthHTTP { request in
            guard request.url?.path.hasSuffix("/auth/refresh") == true else {
                return (404, ScriptedAuthHTTP.refusal("not_found", "no"))
            }
            return (200, ReadbackFixture.sessionJSON(userID: ReadbackFixture.accountID, license: #""odbl-1.0""#))
        }
        let data = try await ReadbackFixture.boot(
            databaseURL: try ReadbackFixture.databaseURL(), credentials: credentials, http: http
        )
        #expect(try await ReadbackFixture.sharing(data.local) == .unknown, "calibration: the old session carried an answer")

        _ = try await data.session.authorization()

        #expect(await http.bodies(to: "/auth/refresh").count == 1, "no refresh was sent")
        #expect(try await ReadbackFixture.sharing(data.local) == .sharing, "the refresh's answer did not reach the phone")
        #expect(await data.session.storedSession?.licenseVersion == .accepted("odbl-1.0"))
    }

    @Test("an answer for an account that is not the one signed in writes nothing")
    func anotherAccountsAnswerWritesNothing() async throws {
        let store = try await CypressStore.inMemory()
        let local = LocalAPI(store: store, deviceID: ReadbackFixture.deviceID)
        try await local.linkAccount(
            deviceUUID: ReadbackFixture.deviceID, userID: ReadbackFixture.accountID,
            provider: "apple", acceptsLicense: false
        )

        try await local.adoptLicenseAnswer(.accepted("odbl-1.0"), for: ReadbackFixture.otherAccountID)
        #expect(try await ReadbackFixture.sharing(local) == .notSharing, "another account's answer was written")

        try await local.adoptLicenseAnswer(.unstated, for: ReadbackFixture.accountID)
        #expect(try await ReadbackFixture.sharing(local) == .notSharing, "an unstated answer was written")

        // The control: the same answer for the account signed in is written.
        try await local.adoptLicenseAnswer(.accepted("odbl-1.0"), for: ReadbackFixture.accountID)
        #expect(try await ReadbackFixture.sharing(local) == .sharing)
    }

    /// The two choices the orchestrator made, pinned so that flipping either is a visible change.
    @Test("the service's answer wins over the phone's, and its null reads as did-not-agree")
    func theTwoChoices() async throws {
        #expect(LocalAPI.serviceLicenseAnswerWins)
        #expect(LocalAPI.serviceNoAcceptanceReadsAsDeclined)
        #expect(LocalAPI.serviceSessionProvider == AccountAskProvider.apple.rawValue)

        let store = try await CypressStore.inMemory()
        let local = LocalAPI(store: store, deviceID: ReadbackFixture.deviceID)
        try await local.linkAccount(
            deviceUUID: ReadbackFixture.deviceID, userID: ReadbackFixture.accountID,
            provider: "apple", acceptsLicense: true
        )
        try await local.adoptLicenseAnswer(.declined, for: ReadbackFixture.accountID)
        #expect(try await ReadbackFixture.sharing(local) == .notSharing, "the phone's answer won over the service's")
    }

    /// The whole path for the person chip 148 is about: declined, reinstalled, agrees from the row,
    /// relaunches. The relaunch adopts the stored session's answer, so the agreement must be in it.
    @Test("agreeing from the restored declined state still reads agreed after a relaunch")
    func agreeThenRelaunch() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try ReadbackFixture.databaseURL()
        try ReadbackFixture.seedSession(credentials, license: "null")
        let http = ScriptedAuthHTTP { request in
            guard request.url?.path.hasSuffix("/devices/claim") == true else {
                return (404, ScriptedAuthHTTP.refusal("not_found", "no"))
            }
            return (200, Data(#"{"claimed":true}"#.utf8))
        }

        let first = try await ReadbackFixture.boot(databaseURL: databaseURL, credentials: credentials, http: http)
        let account = AccountModel(api: first.local, session: first.session)
        await account.load()
        #expect(AccountCopy.offersLicenseAcceptance(isSignedIn: account.isSignedIn, link: account.link), "calibration: no row to tap")
        await account.acceptLicense()
        #expect(!account.licenseAcceptanceFailed, "the agreement failed")
        #expect(try await ReadbackFixture.sharing(first.local) == .sharing, "the agreement did not reach the phone")

        let relaunched = try await ReadbackFixture.boot(databaseURL: databaseURL, credentials: credentials, http: http)
        #expect(
            try await ReadbackFixture.sharing(relaunched.local) == .sharing,
            "the relaunch brought back the declined answer the session was minted with"
        )
        #expect(await http.bodies(to: "/devices/claim").count == 1)
    }
}

// MARK: - 3. A bare claim leaves no stale answer (chip 155)

@Suite("A claim clears the previous answer")
struct ClaimClearsTheAnswerTests {

    @Test("a bare claim after signing out reads unknown, for the same account or another",
          arguments: [true, false])
    func bareClaimAfterSignOut(sameAccount: Bool) async throws {
        let store = try await CypressStore.inMemory()
        let local = LocalAPI(store: store, deviceID: ReadbackFixture.deviceID)
        try await local.linkAccount(
            deviceUUID: ReadbackFixture.deviceID, userID: ReadbackFixture.accountID,
            provider: "apple", acceptsLicense: false
        )
        #expect(try await ReadbackFixture.sharing(local) == .notSharing, "calibration: not staged as declined")
        try await local.signOut()

        let next = sameAccount ? ReadbackFixture.accountID : ReadbackFixture.otherAccountID
        try await local.claimDevice(deviceUUID: ReadbackFixture.deviceID, userID: next)

        #expect(
            try await ReadbackFixture.sharing(local) == .unknown,
            "a claim with no answer of its own read the earlier sign-in's answer"
        )
    }

    @Test("screen 15's link still records its answer, because it writes after the claim")
    func linkAfterClaimKeepsItsAnswer() async throws {
        let store = try await CypressStore.inMemory()
        let local = LocalAPI(store: store, deviceID: ReadbackFixture.deviceID)
        try await local.linkAccount(
            deviceUUID: ReadbackFixture.deviceID, userID: ReadbackFixture.accountID,
            provider: "apple", acceptsLicense: true
        )
        #expect(try await ReadbackFixture.sharing(local) == .sharing)
    }
}
