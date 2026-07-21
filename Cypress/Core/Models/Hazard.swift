import Foundation

/// The public-safety categories that route to 311 and nowhere else (D4, PRODUCT §5 M7).
///
/// **This type deliberately has no path into `CommunityNote`.** It shares no protocol, no raw-value
/// space, and no initializer with `CommunityNote.Category`; `CommunityNote.Category(rawValue:)`
/// returns nil for every string below. A hazard can therefore be carried by exactly two things: the
/// 311 interstitial (which stores nothing public) and a `PrivateReminder` on your own record.
///
/// D4, verbatim in effect: "The public community-note option disappears for hazard categories;
/// after the 311 handoff only a private reminder on your own record remains, never public, never
/// auto-staled." DECISIONS §3.4 adds: "No public surface query may be able to return a
/// hazard-category note."
///
/// The four categories are the ones enumerated in PRODUCT §5 M7; the raw-value spellings are ours,
/// since the source states them as prose.
public enum HazardCategory: String, Codable, Sendable, Hashable, CaseIterable {
    /// "hanging or broken limb over a path"
    case hangingOrBrokenLimb = "hanging_or_broken_limb"
    /// "uprooted"
    case uprooted = "uprooted"
    /// "struck by vehicle"
    case struckByVehicle = "struck_by_vehicle"
    /// "blocking a signal or sightline"
    case blockingSignalOrSightline = "blocking_signal_or_sightline"

    /// The full-screen interstitial title, verbatim (PRODUCT §9 copy table).
    public static let interstitialTitle = "This may be a public-safety hazard. Call 311."
    /// The secondary action on the hazard screen, verbatim (PRODUCT §9 copy table). It leads to a
    /// `PrivateReminder`, not to a `CommunityNote`.
    public static let secondaryActionTitle = "also pin a community note"
}

/// A private note to yourself about a tree (BUILD-PLAN §4 `private_reminders`, D4).
///
/// "Never public, never auto-staled" (BUILD-PLAN §4). Accordingly this type has no `staleAt`, no
/// moderation state, and no visibility flag that could be flipped: privacy is structural, not a
/// column that a query can get wrong.
///
/// Requires a `userID` (not an `Attribution`): a private reminder belongs to an account, so there
/// is no anonymous device-only variant that could later be attributed to the wrong person.
public struct PrivateReminder: CoreEntity, SoftDeletable {
    public let id: UUID
    public let userID: UUID
    public let treeID: UUID
    /// The hazard the 311 handoff was about (D4). Hazards live here and nowhere else public.
    public var category: HazardCategory
    public var note: String?
    public var photoID: UUID?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        treeID: UUID,
        category: HazardCategory,
        note: String? = nil,
        photoID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.treeID = treeID
        self.category = category
        self.note = note
        self.photoID = photoID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// A logged 311 redirect (`POST /reports/hazard-redirect`, BUILD-PLAN §6).
///
/// Analytics only, no public record. It stores no note, no photo, and no free text — only that the
/// interstitial was shown — so it cannot become a hazard record by accretion.
///
/// Never render "sent to the city" copy off the back of this (DECISIONS §3.3, ARCHITECTURE §5.4).
public struct HazardRedirectEvent: Hashable, Codable, Sendable {
    public let treeID: UUID
    public let category: HazardCategory
    public let shownAt: Date

    public init(treeID: UUID, category: HazardCategory, shownAt: Date = Date()) {
        self.treeID = treeID
        self.category = category
        self.shownAt = shownAt
    }
}
