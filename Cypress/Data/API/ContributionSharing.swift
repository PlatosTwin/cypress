import Foundation

/// Whether this phone's contributions go out under the open database license, read from the two
/// facts the phone stores: who is signed in, and what that account agreed to (`AccountLinkRecord`).
///
/// The four cases follow the You tab's license line (`AccountCopy.licenseLine(for:)`) exactly:
/// the "did not agree" line shows when, and only when, this type says `.notSharing`, and the
/// "agreed" line when, and only when, it says `.sharing`. `ContributionSharingTests` pins that.
///
/// **A signed-out phone is `.signedOut`, whatever record it still holds.** `LocalAPI.signOut()`
/// keeps the consent record on disk, because the record is the account's and comes back with it.
/// So the user id is read first, and an old stored answer never speaks for a phone with nobody
/// signed in. (`LocalAPI.accountLink()` already returns nil when nobody is signed in; this type
/// does not rely on that.)
public enum ContributionSharing: Sendable, Hashable {
    /// Signed in, and the account agreed to the license.
    case sharing
    /// Nobody is signed in on this phone.
    case signedOut
    /// Signed in, and the account did not agree to the license.
    case notSharing
    /// Signed in, but the phone holds no answer: no record, or an account not linked through
    /// screen 15 (`provider == nil`), which is every account linked before the record existed.
    case unknown

    public init(userID: UUID?, link: AccountLinkRecord?) {
        guard userID != nil else {
            self = .signedOut
            return
        }
        guard let link, link.provider != nil else {
            self = .unknown
            return
        }
        self = link.acceptsLicense ? .sharing : .notSharing
    }
}
