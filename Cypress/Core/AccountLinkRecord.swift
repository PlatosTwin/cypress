import Foundation

/// What a sign-in agreed to, kept where it can be read back (ERRATA **E131**).
///
/// **The defect this closes.** Screen 15 collects two things and exactly two — which of three
/// routes was tapped, and whether the open-database-license row was checked — and
/// `AccountAskModel` justifies its unchecked-box behaviour on the strength of the second one
/// travelling somewhere: "the answer travels on the request instead, so the account records what
/// was actually agreed to and `User.licenseVersion` stays honestly nil when nothing was". The
/// composition root's sign-in handler discarded the whole request (`_ = request`), so that sentence
/// was false: unchecking the box changed nothing anywhere, and an account created by a person who
/// declined the license was indistinguishable from one created by a person who accepted it. A
/// consent nobody can read back is not a consent, and D12 and BUILD-PLAN §5 make the licence a data
/// governance question rather than a cosmetic one.
///
/// **Why this is a record and not a `User` row.** There is no `users` table on device (ERRATA E86)
/// and no server to hold one, so an account is an id in `app_state` and nothing else. These two
/// facts are stored beside it, in the same table, for the same reason `currentUserRole` is
/// (ERRATA E124-B). When the magic-link service lands, `User.licenseVersion` and
/// `User.licenseAcceptedAt` are the columns this becomes and nothing about the screen changes.
///
/// **Absence is meaningful in both fields, and neither is a `Bool` on disk.** A missing
/// `licenseVersion` is the honest record of a declined consent — the same nil `User.hasAcceptedLicense`
/// tests for — rather than a `false` that could equally mean "never asked". A missing `provider` is
/// an account claimed by something other than screen 15, which is what every account on a device
/// that signed in before this record existed is.
public struct AccountLinkRecord: Hashable, Sendable {

    /// `AccountAskProvider`'s raw value: `apple`, `google` or `email`.
    ///
    /// A `String` rather than the enum, because the enum lives in `Features` and `Core` is imported
    /// by everything (ARCHITECTURE §2). The vocabulary is fixed by SCREENS.md 15's three buttons and
    /// pinned from the feature side, where the enum is.
    public let provider: String?

    /// The license text version consented to, or nil when the row was unchecked at the tap.
    /// `User.hasAcceptedLicense(version:)` is the shape this feeds when there is a `users` table.
    public let licenseVersion: String?

    public init(provider: String?, licenseVersion: String?) {
        self.provider = provider
        self.licenseVersion = licenseVersion
    }

    /// Whether the open-database-license row was checked when this account was linked.
    ///
    /// Derived rather than stored, so there is one fact on disk and no way for a `Bool` and a
    /// version string to disagree about the same tap.
    public var acceptsLicense: Bool { licenseVersion != nil }
}

/// The license consent screen 15's checkbox is about.
///
/// **The version string is NOT SPECIFIED.** PRODUCT §5 pins the license itself — "ODbL for the
/// database, CC-BY 4.0 for photos" — and BUILD-PLAN §4 requires the consent to be versioned so a
/// text change forces re-consent, but no document names a version. ODbL has had exactly one, so
/// this is its number rather than an invention; when legal review lands (PRODUCT §5 says the final
/// call awaits it) the constant moves and `User.hasAcceptedLicense(version:)` starts returning false
/// for everyone who agreed to this one, which is precisely what versioning it is for.
public enum LicenseConsent {
    public static let currentVersion = "odbl-1.0"
}
