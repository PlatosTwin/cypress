import Foundation

/// A favorite toggle as it travels through the outbox.
///
/// Favorites are the one non-append-only contribution: they sync as toggle events with tombstones
/// (BUILD-PLAN §4 and §6). The event therefore carries the resulting *state*, not a verb, so
/// replaying it is idempotent — applying "favorited" twice leaves one favorite.
///
/// It carries a `FavoriteOwner` rather than a `userID` because the heart is tapped on a device that
/// D9 keeps anonymous until the third save, so requiring an account made the record unwritable on
/// every device the app runs on (ERRATA E89). Ownership moves to the account at
/// `POST /devices/claim`, which is the mechanism D9 already relies on for every other first save.
///
/// **Changing the payload's shape was free**, which is worth stating once because it will not be
/// free again: no build has ever enqueued one of these. `RootView` no-opped the heart precisely
/// because there was nowhere to write it, so there are no `favorite_toggle` rows on any disk to
/// decode under the old key.
public struct FavoriteToggle: Codable, Hashable, Sendable {
    public let owner: FavoriteOwner
    public let treeID: UUID
    public let clientUUID: UUID
    public let isFavorite: Bool
    public let occurredAt: Date

    public init(
        owner: FavoriteOwner,
        treeID: UUID,
        clientUUID: UUID = UUID(),
        isFavorite: Bool,
        occurredAt: Date = Date()
    ) {
        self.owner = owner
        self.treeID = treeID
        self.clientUUID = clientUUID
        self.isFavorite = isFavorite
        self.occurredAt = occurredAt
    }
}

/// The decoded body of an outbox row.
///
/// `outbox.kind` is the discriminator and `outbox.payload` is the bare mutation, rather than the
/// payload carrying its own `type` field. That mirrors the table as BUILD-PLAN §4 defines it and
/// keeps the discriminator queryable — screen 17 groups by kind, and a JSON field cannot be indexed
/// as cheaply as a column.
/// `Hashable` because screen 17 renders what is *in* an item, not only that one exists: the mock's
/// third row reads `DBH 31 cm, tape`, and a measurement's method badge (C12) is the one place D7's
/// provenance shows on that screen. `OutboxItemSnapshot` is `Hashable`, so carrying the decoded
/// mutation there needs this. Every associated value is already `Hashable` through `CoreEntity`.
public enum OutboxPayload: Sendable, Hashable {
    case visit(Visit)
    case observation(TreeObservation)
    case measurement(TreeMeasurement)
    case careEvent(CareEvent)
    case favoriteToggle(FavoriteToggle)
    /// D4's private reminder (ERRATA E23). It queues like every other mutation: durable first,
    /// attempted after. Its payload carries a `ReminderOwner`, so a reminder written before sign-in
    /// arrives at the API owned by the device rather than by nobody.
    case privateReminder(PrivateReminder)

    public var kind: OutboxItem.Kind {
        switch self {
        case .visit: return .visit
        case .observation: return .observation
        case .measurement: return .measurement
        case .careEvent: return .careEvent
        case .favoriteToggle: return .favoriteToggle
        case .privateReminder: return .privateReminder
        }
    }

    /// The idempotency key the server, and `LocalAPI`, dedupe on.
    public var clientUUID: UUID {
        switch self {
        case let .visit(value): return value.clientUUID
        case let .observation(value): return value.clientUUID
        case let .measurement(value): return value.clientUUID
        case let .careEvent(value): return value.clientUUID
        case let .favoriteToggle(value): return value.clientUUID
        // The reminder's own id. Minted on device before the save and never reused, which is what
        // an idempotency key has to be; see `PrivateReminder`.
        case let .privateReminder(value): return value.id
        }
    }

    /// The tree this mutation is about, for the outbox screen's subtitle.
    public var treeID: UUID {
        switch self {
        case let .visit(value): return value.treeID
        case let .observation(value): return value.treeID
        case let .measurement(value): return value.treeID
        case let .careEvent(value): return value.treeID
        case let .favoriteToggle(value): return value.treeID
        case let .privateReminder(value): return value.treeID
        }
    }

    /// When the mutation happened, as the person did it.
    ///
    /// **The contribution's own capture time, never the queue row's `createdAt`.** They are usually
    /// within milliseconds of each other and they are not the same fact: a visit staged offline and
    /// enqueued on a later launch has a capture time from yesterday and a row written today, and
    /// `POST /sync`'s `occurred_at` is the first of those — the service falls back to *its* clock
    /// only when the field is absent (`server/internal/api/sync.go`), which would date a day-old
    /// visit to the moment the network came back. `PrivateReminder` has no capture time of its own:
    /// a reminder is written the moment it is made, so `createdAt` there is not a substitute for the
    /// fact but is the fact.
    public var occurredAt: Date {
        switch self {
        case let .visit(value): return value.capturedAt
        case let .observation(value): return value.capturedAt
        case let .measurement(value): return value.capturedAt
        case let .careEvent(value): return value.capturedAt
        case let .favoriteToggle(value): return value.occurredAt
        case let .privateReminder(value): return value.createdAt
        }
    }

    /// The account the mutation says it belongs to, or nil when it belongs to a device (D9).
    ///
    /// Read by `RemoteAPI.sync` to fill `POST /sync`'s `user_id`, which the service checks against
    /// the authenticated caller and never trusts. Resolved here rather than at the call site so the
    /// six kinds cannot answer it differently.
    ///
    /// **Two properties rather than an `Attribution`**, because `Attribution.deviceID` is
    /// non-optional and `FavoriteOwner`/`ReminderOwner` are an either: an account-owned favorite
    /// carries no device id at all, and inventing one to satisfy a type is how a row ends up
    /// claiming a device that never touched it.
    public var ownerUserID: UUID? {
        switch self {
        case let .visit(value): return value.attribution.userID
        case let .observation(value): return value.attribution.userID
        case let .measurement(value): return value.attribution.userID
        case let .careEvent(value): return value.attribution.userID
        case let .favoriteToggle(value): return value.owner.userID
        case let .privateReminder(value): return value.owner.userID
        }
    }

    /// The device the mutation says it belongs to, or nil when it belongs to an account. See
    /// `ownerUserID`.
    public var ownerDeviceID: UUID? {
        switch self {
        case let .visit(value): return value.attribution.deviceID
        case let .observation(value): return value.attribution.deviceID
        case let .measurement(value): return value.attribution.deviceID
        case let .careEvent(value): return value.attribution.deviceID
        case let .favoriteToggle(value): return value.owner.deviceID
        case let .privateReminder(value): return value.owner.deviceID
        }
    }

    /// The resulting favorite state, for the one kind that has one.
    ///
    /// Nil for the other five, and that is not the same as `false`: `POST /sync` reads a present
    /// `is_favorite` as a **decision** and its own comment records what a defaulted `false` did —
    /// "the heart went off, the client was told it worked, and nothing anywhere errored".
    public var isFavorite: Bool? {
        guard case let .favoriteToggle(value) = self else { return nil }
        return value.isFavorite
    }

    // MARK: - Coding

    /// Dates as ISO-8601, matching every other timestamp in the store; keys stay the Swift property
    /// names, per the `Core` convention. The outbox payload is read only by this app, so the wire
    /// mapping to §6's snake_case belongs in `RemoteAPI`, not here.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func encoded() throws -> Data {
        let encoder = Self.encoder()
        switch self {
        case let .visit(value): return try encoder.encode(value)
        case let .observation(value): return try encoder.encode(value)
        case let .measurement(value): return try encoder.encode(value)
        case let .careEvent(value): return try encoder.encode(value)
        case let .favoriteToggle(value): return try encoder.encode(value)
        case let .privateReminder(value): return try encoder.encode(value)
        }
    }

    public static func decode(kind: OutboxItem.Kind, from data: Data) throws -> OutboxPayload {
        let decoder = decoder()
        switch kind {
        case .visit: return .visit(try decoder.decode(Visit.self, from: data))
        case .observation: return .observation(try decoder.decode(TreeObservation.self, from: data))
        case .measurement: return .measurement(try decoder.decode(TreeMeasurement.self, from: data))
        case .careEvent: return .careEvent(try decoder.decode(CareEvent.self, from: data))
        case .favoriteToggle: return .favoriteToggle(try decoder.decode(FavoriteToggle.self, from: data))
        case .privateReminder: return .privateReminder(try decoder.decode(PrivateReminder.self, from: data))
        }
    }

    /// Builds the outbox row for this mutation.
    ///
    /// `photos` are binaries that have not been uploaded, each carrying the shot type it was framed
    /// as. The wifi-only toggle gates these and nothing else (BUILD-PLAN §4).
    public func makeItem(photos: [OutboxPhoto] = [], createdAt: Date = Date()) throws -> OutboxItem {
        OutboxItem(
            kind: kind,
            clientUUID: clientUUID,
            payload: try encoded(),
            photos: photos,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
