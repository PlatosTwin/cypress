import Foundation

/// A favourite toggle as it travels through the outbox.
///
/// Favourites are the one non-append-only contribution: they sync as toggle events with tombstones
/// (BUILD-PLAN §4 and §6). The event therefore carries the resulting *state*, not a verb, so
/// replaying it is idempotent — applying "favourited" twice leaves one favourite.
public struct FavoriteToggle: Codable, Hashable, Sendable {
    public let userID: UUID
    public let treeID: UUID
    public let clientUUID: UUID
    public let isFavorite: Bool
    public let occurredAt: Date

    public init(userID: UUID, treeID: UUID, clientUUID: UUID = UUID(), isFavorite: Bool, occurredAt: Date = Date()) {
        self.userID = userID
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
public enum OutboxPayload: Sendable {
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
