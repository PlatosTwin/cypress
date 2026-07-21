import Foundation

/// `users.role` (BUILD-PLAN §4). Roles are per organization in the product model (PRODUCT §2);
/// this is the global default role on the user record.
public enum UserRole: String, Codable, Sendable, Hashable, CaseIterable {
    case member = "member"
    case steward = "steward"
    case coordinator = "coordinator"
    case moderator = "moderator"
    case admin = "admin"

    /// Only a moderator or an org coordinator may confirm a review flag into a tree status
    /// transition (DECISIONS §3.7, BUILD-PLAN §6).
    public var canConfirmReviewFlag: Bool {
        switch self {
        case .moderator, .admin, .coordinator: return true
        case .member, .steward: return false
        }
    }

    /// Rows made or confirmed by a steward or coordinator of an org qualify for `org_verified`
    /// (D12, BUILD-PLAN §5).
    public var canProduceOrgVerifiedRows: Bool {
        switch self {
        case .steward, .coordinator: return true
        case .member, .moderator, .admin: return false
        }
    }
}

/// `users.birth_year_bucket` (BUILD-PLAN §4).
///
/// The age gate is a single over-or-under-18 choice; birthdates are never collected
/// (BUILD-PLAN §10, DECISIONS §3.9).
public enum BirthYearBucket: String, Codable, Sendable, Hashable, CaseIterable {
    case over18 = "over_18"
    case under18 = "under_18"
    case unknown = "unknown"
}

/// A registered account (BUILD-PLAN §4 `users`).
///
/// There is no password field anywhere in this type, by design: email auth is magic link only
/// (A10, DECISIONS §3.9). There is no birthdate field for the same reason.
public struct User: CoreEntity, SoftDeletable {
    public let id: UUID
    public var email: String
    public var displayName: String
    public var avatarURL: URL?
    public var role: UserRole
    public var birthYearBucket: BirthYearBucket
    /// Opt-in public attribution (D11). Default false.
    public var publicAttribution: Bool
    /// Consent is versioned; a license text change requires re-consent (BUILD-PLAN §4).
    public var licenseVersion: String?
    public var licenseAcceptedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    /// Account deletion anonymizes attributed rows and removes the profile (BUILD-PLAN §10).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        avatarURL: URL? = nil,
        role: UserRole = .member,
        birthYearBucket: BirthYearBucket = .unknown,
        publicAttribution: Bool = false,
        licenseVersion: String? = nil,
        licenseAcceptedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.role = role
        self.birthYearBucket = birthYearBucket
        self.publicAttribution = publicAttribution
        self.licenseVersion = licenseVersion
        self.licenseAcceptedAt = licenseAcceptedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Whether this user's contributions may carry their display name on a public timeline.
    ///
    /// Under-18 accounts are forced to anonymous public attribution regardless of the toggle
    /// (D11, BUILD-PLAN §4). Public timelines otherwise say "a visitor" (BUILD-PLAN §10).
    public var isPublicAttributionEffective: Bool {
        guard birthYearBucket != .under18 else { return false }
        return publicAttribution
    }

    /// Whether the stored consent is current for a given license version. A bump forces re-consent
    /// (BUILD-PLAN §4, M2 acceptance criterion in §12).
    public func hasAcceptedLicense(version: String) -> Bool {
        licenseVersion == version && licenseAcceptedAt != nil
    }
}

/// `devices` (BUILD-PLAN §4).
///
/// Anonymous contributions (D9) attach here and migrate to the user at `POST /devices/claim`.
public struct Device: CoreEntity {
    public let id: UUID
    /// `device_uuid unique` — the stable per-installation identifier.
    public let deviceUUID: UUID
    /// Nil until the device is claimed by a signed-in user (D9).
    public var userID: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        deviceUUID: UUID,
        userID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceUUID = deviceUUID
        self.userID = userID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
