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

/// Who a private reminder belongs to: an account, or the device that wrote it.
///
/// **Exactly one of the two, never neither.** That is the whole reason this is an enum rather than
/// two optional fields — an ownerless reminder is a reminder nobody can ever read back, and a
/// doubly-owned one is a reminder that has to be resolved by precedence somewhere. Neither state is
/// representable here, and `private_reminders`' CHECK constraint says the same thing to SQLite.
///
/// Device ownership exists because D9 keeps the device anonymous until the account ask at the third
/// save, and screen 06 sits inside a safety flow where a sign-in wall is the wrong answer. A
/// reminder scoped to a device is *narrower* than one scoped to an account — it never leaves this
/// installation until the account arrives — so it loosens nothing in DECISIONS §3. The device id
/// stays what D9 makes it, an anonymous handle for un-attributed contributions, and never becomes a
/// user identifier. See ERRATA E23 for the contradiction this resolves.
public enum ReminderOwner: Hashable, Sendable, Codable {
    case user(UUID)
    case device(UUID)

    /// The D9 rule in one place: a contribution belongs to the signed-in user when there is one and
    /// to this device otherwise. Every reminder written anywhere in the app resolves its owner here,
    /// so the answer cannot differ between two call sites.
    public init(_ attribution: Attribution) {
        if let userID = attribution.userID {
            self = .user(userID)
        } else {
            self = .device(attribution.deviceID)
        }
    }

    public var userID: UUID? {
        if case let .user(id) = self { return id }
        return nil
    }

    public var deviceID: UUID? {
        if case let .device(id) = self { return id }
        return nil
    }

    /// What `POST /devices/claim` does to a reminder (D9). A reminder already owned by a user is
    /// left alone: adoption happens once, and claiming twice must not move an account's record onto
    /// a different account.
    public func adopted(by userID: UUID) -> ReminderOwner {
        switch self {
        case .user: return self
        case .device: return .user(userID)
        }
    }

    // Encoded as `{"user": "…"}` or `{"device": "…"}` — one key, so the outbox payload carries the
    // same "exactly one owner" guarantee the type and the schema do. Written out rather than
    // synthesized because the synthesized form for an enum with associated values is
    // `{"user":{"_0":"…"}}`, and a payload shape that survives on disk should not be an artifact of
    // the compiler's naming.
    private enum CodingKeys: String, CodingKey {
        case user
        case device
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let userID = try container.decodeIfPresent(UUID.self, forKey: .user) {
            self = .user(userID)
        } else if let deviceID = try container.decodeIfPresent(UUID.self, forKey: .device) {
            self = .device(deviceID)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .user,
                in: container,
                debugDescription: "a private reminder carries exactly one owner, and this one carries none"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .user(id): try container.encode(id, forKey: .user)
        case let .device(id): try container.encode(id, forKey: .device)
        }
    }
}

/// A private note to yourself about a tree (BUILD-PLAN §4 `private_reminders`, D4).
///
/// "Never public, never auto-staled" (BUILD-PLAN §4). Accordingly this type has no `staleAt`, no
/// moderation state, and no visibility flag that could be flipped: privacy is structural, not a
/// column that a query can get wrong.
///
/// Carries a `ReminderOwner` rather than a `userID`: it is written from screen 06, which is a safety
/// flow on a device that D9 keeps anonymous until the third save, so requiring an account made the
/// record unwritable on every device the app runs on (ERRATA E23). Ownership moves to the account at
/// `POST /devices/claim`, which is the mechanism D9 already relies on for every other first save.
///
/// The id doubles as the mutation's idempotency key in the outbox: it is minted on device before the
/// save, so a replay of the same reminder is deduped by the same `ON CONFLICT` the other
/// contribution tables get from a separate `client_uuid`. A second UUID that would always equal the
/// first is a column that can drift.
public struct PrivateReminder: CoreEntity, SoftDeletable {
    public let id: UUID
    public var owner: ReminderOwner
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
        owner: ReminderOwner,
        treeID: UUID,
        category: HazardCategory,
        note: String? = nil,
        photoID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
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
