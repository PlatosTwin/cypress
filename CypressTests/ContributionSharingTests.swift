import Foundation
import Testing
@testable import Cypress

/// `ContributionSharing`'s four arms, and its agreement with the You tab's license line.
@Suite("Contribution sharing · read from the user id and the account link")
struct ContributionSharingTests {

    private static let user = UUID(uuidString: "6A0B1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D")!
    private static let agreed = AccountLinkRecord(
        provider: "apple", licenseVersion: LicenseConsent.currentVersion
    )
    private static let declined = AccountLinkRecord(provider: "email", licenseVersion: nil)

    @Test("a signed-in account that agreed to the license is sharing")
    func agreedIsSharing() {
        #expect(ContributionSharing(userID: Self.user, link: Self.agreed) == .sharing)
    }

    @Test("a signed-in account that did not agree is not sharing")
    func declinedIsNotSharing() {
        #expect(ContributionSharing(userID: Self.user, link: Self.declined) == .notSharing)
    }

    @Test("a phone with nobody signed in is signed out")
    func noUserIsSignedOut() {
        #expect(ContributionSharing(userID: nil, link: nil) == .signedOut)
    }

    /// `LocalAPI.signOut()` keeps the consent record on disk. A phone that signed out of an account
    /// that agreed (or declined) still holds that answer, and it must not speak for the phone.
    @Test("a signed-out phone that still holds an old answer is signed out", arguments: [
        ContributionSharingTests.agreed,
        ContributionSharingTests.declined,
        AccountLinkRecord(provider: nil, licenseVersion: LicenseConsent.currentVersion),
    ])
    func storedAnswerAfterSignOutIsSignedOut(link: AccountLinkRecord) {
        #expect(ContributionSharing(userID: nil, link: link) == .signedOut)
    }

    @Test("a signed-in account with no record is unknown")
    func noRecordIsUnknown() {
        #expect(ContributionSharing(userID: Self.user, link: nil) == .unknown)
    }

    /// An account linked before the record existed has no provider. Its license field means
    /// nothing, in either state, so the answer is unknown.
    @Test("a signed-in account with no provider is unknown, whatever its license field says",
          arguments: [nil, LicenseConsent.currentVersion] as [String?])
    func noProviderIsUnknown(licenseVersion: String?) {
        let link = AccountLinkRecord(provider: nil, licenseVersion: licenseVersion)
        #expect(ContributionSharing(userID: Self.user, link: link) == .unknown)
    }

    /// The You tab reads the same record through `AccountCopy.licenseLine(for:)`. The "did not
    /// agree" line shows exactly when this type says `.notSharing`, and the "agreed" line exactly
    /// when it says `.sharing`. The You tab's model reads `link` as nil when nobody is signed in
    /// (`LocalAPI.accountLink()`), so the signed-in records are the ones compared here.
    @Test("the You tab's license line agrees with every signed-in answer", arguments: [
        nil,
        AccountLinkRecord(provider: nil, licenseVersion: nil),
        AccountLinkRecord(provider: nil, licenseVersion: LicenseConsent.currentVersion),
        AccountLinkRecord(provider: "apple", licenseVersion: nil),
        AccountLinkRecord(provider: "google", licenseVersion: LicenseConsent.currentVersion),
        AccountLinkRecord(provider: "email", licenseVersion: nil),
    ] as [AccountLinkRecord?])
    func agreesWithTheYouTab(link: AccountLinkRecord?) {
        let sharing = ContributionSharing(userID: Self.user, link: link)
        let line = AccountCopy.licenseLine(for: link)
        let saysDidNotAgree = line?.hasPrefix("You did not agree") ?? false
        let saysAgreed = line?.hasPrefix("You agreed") ?? false
        #expect(saysDidNotAgree == (sharing == .notSharing), "line: \(line ?? "none"), sharing: \(sharing)")
        #expect(saysAgreed == (sharing == .sharing), "line: \(line ?? "none"), sharing: \(sharing)")
        #expect((line == nil) == (sharing == .unknown), "line: \(line ?? "none"), sharing: \(sharing)")
    }
}
