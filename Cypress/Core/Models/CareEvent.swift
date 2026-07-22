import Foundation

/// `care_events.actions text[]` (BUILD-PLAN §4), verbatim.
///
/// PRODUCT §3 records two other wordings for this vocabulary ("weeded basin, litter cleared, other"
/// and "stake removed"); BUILD-PLAN wins on data (ARCHITECTURE §1). There is no free-text "other"
/// action in the BUILD-PLAN set — free text goes in `note`.
public enum CareAction: String, Codable, Sendable, Hashable, CaseIterable {
    case watered = "watered"
    case mulched = "mulched"
    case weeded = "weeded"
    case litterCleared = "litter_cleared"
    case staked = "staked"
}

/// A quick care log, ≤30 s (BUILD-PLAN §4 `care_events`, PRODUCT §5 M5).
///
/// "Never publicly counted or ranked" (D1, BUILD-PLAN §4). Nothing in this type exposes a count,
/// and nothing may aggregate it into a user-visible total (DECISIONS §3.1).
public struct CareEvent: FieldCaptured {
    public let id: UUID
    public let treeID: UUID
    public let userID: UUID?
    public let deviceID: UUID
    public let clientUUID: UUID
    public let capturedAt: Date
    /// Care events are not charted; accuracy is stored for consistency with the other field
    /// contributions (D6).
    public let gpsAccuracyM: Double?
    public var actions: [CareAction]
    public var note: String?
    /// Photo optional (BUILD-PLAN §4).
    public var photoID: UUID?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID = UUID(),
        capturedAt: Date,
        gpsAccuracyM: Double? = nil,
        actions: [CareAction],
        note: String? = nil,
        photoID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.userID = attribution.userID
        self.deviceID = attribution.deviceID
        self.clientUUID = clientUUID
        self.capturedAt = capturedAt
        self.gpsAccuracyM = gpsAccuracyM
        self.actions = actions
        self.note = note
        self.photoID = photoID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }
}

/// Who a favourite belongs to: an account, or the device that saved it.
///
/// **Exactly one of the two, never neither** — the same rule, and the same reason, as
/// `ReminderOwner` (ERRATA E23). An ownerless favourite is in nobody's grove, and a doubly-owned one
/// has to be resolved by precedence somewhere a query can get it wrong. Neither state is
/// representable here, and `favorites`' CHECK says the same thing to SQLite (`AppSchema` v5).
///
/// Device ownership exists because D9 keeps the device anonymous until the account ask at the third
/// save, and screen 15 is where that ask lives — so until it does, *every* device is anonymous and a
/// favourite that required an account could not be saved at all (ERRATA E89).
///
/// **Why this is not `ReminderOwner` under a wider name.** The two enums have the same shape and
/// carry different invariants. A reminder's owner is a privacy boundary: D4 says the record is never
/// public, and the owner is what keeps it that way. A favourite's owner is half of a uniqueness key,
/// and it has a merge rule at sign-in that a reminder does not have (see
/// `ContributionStore.claimDevice`). One type carrying both stories would have to document a rule
/// that is true of one of its users and not the other. If a third owner-bearing record appears, that
/// is the moment to generalise all three rather than the moment to have generalised two.
public enum FavoriteOwner: Hashable, Sendable, Codable {
    case user(UUID)
    case device(UUID)

    /// The D9 rule in one place: a contribution belongs to the signed-in user when there is one and
    /// to this device otherwise. Every favourite written anywhere in the app resolves its owner
    /// here, so the answer cannot differ between two call sites.
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

    /// What `POST /devices/claim` does to a favourite (D9). One already owned by a user is left
    /// alone: adoption happens once, and claiming twice must not move an account's record onto a
    /// different account.
    public func adopted(by userID: UUID) -> FavoriteOwner {
        switch self {
        case .user: return self
        case .device: return .user(userID)
        }
    }

    // Encoded as `{"user": "…"}` or `{"device": "…"}` — one key, so the outbox payload carries the
    // same "exactly one owner" guarantee the type and the schema do. Written out rather than
    // synthesized for the reason `ReminderOwner` gives: the synthesized form for an enum with
    // associated values is `{"user":{"_0":"…"}}`, and a payload shape that survives on disk should
    // not be an artifact of the compiler's naming.
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
                debugDescription: "a favourite carries exactly one owner, and this one carries none"
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

/// `favorites` (BUILD-PLAN §4).
///
/// The unique pair is (owner, treeID) — one account or one device may hold a tree once, and two
/// different owners may each hold the same tree (`AppSchema` v5, ERRATA E89). Deletion is a
/// tombstone, never a hard delete: sync needs the tombstone, and favorites are the one
/// non-append-only contribution — they sync as toggle events (BUILD-PLAN §4 and §6, DECISIONS §3.7).
public struct Favorite: CoreEntity, SoftDeletable, SyncableMutation {
    public let id: UUID
    public let owner: FavoriteOwner
    public let treeID: UUID
    public let clientUUID: UUID
    public let createdAt: Date
    public var updatedAt: Date
    /// Tombstone. An unfavorite sets this; the row stays (BUILD-PLAN §4).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        owner: FavoriteOwner,
        treeID: UUID,
        clientUUID: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.treeID = treeID
        self.clientUUID = clientUUID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The current state of the toggle.
    public var isActive: Bool { deletedAt == nil }
}
