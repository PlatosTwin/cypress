//
//  RemoteWire.swift
//  Cypress — Data/API
//
//  The bodies `RemoteAPI` sends and the bodies it reads back, and the one place this client states
//  what the service's key convention is.
//
//  ── The convention is not uniform, and the non-uniformity is load-bearing ──────────────────────
//
//  `server/internal/api/wire.go` and `server/README.md` both say it, and the reason is a defect
//  rather than a taste: a payload that **reconstructs a client-owned Swift type** speaks that type's
//  synthesized property names — `distanceM`, `speciesCurrentID`, `checkIns` — and everything else,
//  the error envelope and the request bodies and the server's own result shapes, is snake_case.
//
//  So there is **no key strategy on the decoder in this file**, ever. `.convertFromSnakeCase` maps
//  `species_current_id` to `speciesCurrentId`, which is not `Tree`'s `speciesCurrentID`; the
//  property is optional, so the mismatch decodes as **nil without throwing** and a tree arrives with
//  its species missing while nothing reports it. Server-owned keys are spelled out in `CodingKeys`
//  below, one at a time, which is the only mapping that cannot drift silently.
//
//  Dates are RFC3339 at second precision in UTC, decoded by `.iso8601` — `ISO8601DateFormatter`
//  with `.withInternetDateTime`, which **rejects fractional seconds**. The service truncates for
//  exactly that reason (`wire.go`), and this decoder is the client half of that agreement.
//

import Foundation

// MARK: - Coding

/// The coder pair for everything on `RemoteAPI`'s wire.
///
/// Deliberately identical in configuration to `AuthCoding` — `.iso8601`, no key strategy — because
/// the two halves talk to the same service and a second, differently-configured decoder is a second
/// place for the date contract to be wrong.
enum RemoteCoding {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - Raw JSON that has to travel untouched

/// A JSON document, decoded structurally so it can be re-encoded byte-equivalently.
///
/// It exists for one field: `POST /sync`'s per-item `payload`, which is the mutation the outbox
/// promised to send **verbatim** (`server/internal/api/sync.go`: "The payload is the authority").
/// `OutboxItem.payload` is `Data` that is already JSON, and `Encoder` has no way to splice raw bytes
/// into a container — so the bytes are parsed into this and written back out.
///
/// Numbers are kept as `Double` rather than as a discriminated int/double pair, and that is a
/// deliberate limit rather than an oversight: every numeric field any outbox payload carries is a
/// measurement value, a coordinate or a vitality score, all of which are already `Double` or small
/// enough to be exact in one. An identifier is a string on this wire, never a number.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// Parses a JSON document that is already bytes.
    ///
    /// Throws `SessionError.malformedResponse` rather than a decoding error because the one caller
    /// is sending a queued row: a payload this client wrote and cannot now read is not a fact about
    /// the service, and it must not reach an outbox item as a taxonomy code.
    static func parse(_ data: Data) throws -> JSONValue {
        // A bare fragment is legal JSON to this type but not to `JSONDecoder` without the option,
        // and an outbox payload is always an object. `.fragmentsAllowed` keeps the two agreeing
        // rather than making the object-ness an unstated assumption.
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SessionError.malformedResponse
        }
    }
}

// MARK: - What this transport cannot answer, and why

/// `RemoteAPI`'s refusals, each one a sentence about the **service** rather than about the record.
///
/// ── Why these are not `APIError` cases ─────────────────────────────────────────────────────────
///
/// Every code in the taxonomy is a statement about the thing that was asked for: `notFound` says the
/// row is not there, `forbidden` says it is not yours. None of these is that. They say the *service
/// does not hold this kind of fact at all*, which is a different sentence and one the taxonomy has
/// no word for — and picking the nearest word would be the exact failure `RemoteAPI`'s own header
/// and spec §3.3 are about: an implementation answering a question it never asked.
///
/// Being outside the taxonomy also has the property `SessionError` has and for the same reason
/// (ERRATA **E261** §3): `OutboxFailureReason.apiError(from:)` returns nil for an error it does not
/// recognize, so an outbox item that somehow reached one of these stays alive on the backoff rather
/// than being failed terminally with a sentence about the person's account.
///
/// ── The copy that would be wrong, and why it is not reachable ──────────────────────────────────
///
/// `OutboxFailureReason.sentence(for:)` answers **"No connection."** for any error outside the
/// taxonomy, which would be a false sentence about any of these three. It is not reachable, and the
/// reason is narrower than "nothing is wired": the only methods an `OutboxSendSink` can call are
/// `sync(_:)` and — were the send side ever given a photo method — `uploadPhoto(at:ticket:)`, and
/// **neither of those bodies can throw a `RemoteSurface`.** Both are real calls; their failures are
/// `APIError`, `SessionError`, or a coding error over this device's own queued bytes.
///
/// That is a property of those two bodies and not of the wiring, so it is the thing the round that
/// wires a send sink has to keep true. A `RemoteSurface` reaching an outbox item would print "No
/// connection." to somebody with four bars.
///
/// **This paragraph was a comment with nothing behind it, and review of PR #78 broke it without
/// turning anything red** — `uploadPhoto`'s staged-file `catch` was changed to throw
/// `RemoteSurface.noRouteOnThisService` and all 1,434 tests passed. It is now guarded, by the pair
/// in `CypressTests/RemoteAPITests`: `theSendSinkBodiesCannotThrowARemoteSurface` reads the bodies
/// off this target's source, and `aMissingStagedFileIsNeitherATaxonomyCodeNorARemoteSurface` covers
/// the one branch that had no test at all. Their doc comments argue why it takes both. CLAUDE.md:
/// "Never assert an invariant in a comment you have not verified; a comment is not a test."
public enum RemoteSurface: Error, Equatable, CustomStringConvertible {

    /// The city layer is answered on the phone and never reaches this service.
    ///
    /// RULINGS **R36**, unreopened by **R72** ruling 1, and stated in `server/README.md`'s own
    /// "What this service is not": the map's pan loop, species, the almanac and the city aggregates
    /// come out of the installed city file. There is no route to call — see `RemoteAPI`'s header for
    /// what was checked before this case was written.
    case cityLayerIsAnsweredLocally

    /// The service exposes no route for this act yet.
    ///
    /// **Nine of the eleven mutations spec §3.4 names** — the eleven minus `addTree` and
    /// `deletePhoto`, which are the two this service does expose a route for — and the nightly open
    /// export of D12. The nine include both review dismissals; `RemoteAPI`'s header enumerates all
    /// eleven and `RemoteAPITests.theUnqueuedMutationsRefuse` pins the nine.
    ///
    /// §3.4 is explicit that these "stay Class L until they are queued", which needs a widened
    /// `outbox.kind` `CHECK` and therefore its own ticket and its own migration author — not #158.
    case noRouteOnThisService

    /// The service answers the **community half** of this read and the whole client type needs the
    /// city file too.
    ///
    /// This is the finding of this round and this round's errata entry enumerates
    /// every instance. A `GroveEntry` carries a display name and a coordinate; `GET /me/grove` sends
    /// neither, because both are city-layer facts. Filling them in with a placeholder would put an
    /// unnamed tree at Null Island on a map, which is why this refuses instead. `RoutedAPI` is what
    /// joins the two halves, and the delta accessors on `RemoteAPI` are what it joins from.
    case communityHalfOnly

    public var description: String {
        switch self {
        case .cityLayerIsAnsweredLocally:
            return "the city layer is answered from the installed city file, not by this service"
        case .noRouteOnThisService:
            return "this service exposes no route for that yet"
        case .communityHalfOnly:
            return "this service answers only the community half of that read"
        }
    }
}

// MARK: - Request bodies

/// One outbox row as `POST /sync` takes it.
///
/// The service decodes items with `DisallowUnknownFields`, so this struct is **exact and not
/// approximate**: an extra key fails that one item with `validation_failed`, which is non-retryable.
struct SyncItemBody: Encodable {
    let clientUUID: UUID
    let kind: String
    let treeUUID: UUID
    let occurredAt: Date
    let payload: JSONValue
    let userID: UUID?
    let deviceID: UUID?
    /// Mirrors the payload's own `isFavorite` for a `favorite_toggle`, and is omitted for every
    /// other kind.
    ///
    /// **Sent even though the payload is the authority**, because the service reads the mirror when
    /// the payload has no opinion and rejects the item when the two disagree. Sending it is how this
    /// client says it agrees with itself; omitting it on the other five kinds is how it avoids
    /// asserting a `false` that would be read as a decision (`sync.go`: "the zero value of a `bool`
    /// is a *decision*").
    let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case clientUUID = "client_uuid"
        case kind
        case treeUUID = "tree_uuid"
        case occurredAt = "occurred_at"
        case payload
        case userID = "user_id"
        case deviceID = "device_id"
        case isFavorite = "is_favorite"
    }
}

struct SyncRequestBody: Encodable {
    let items: [SyncItemBody]
}

/// `POST /photos/begin`.
struct BeginPhotoBody: Encodable {
    let treeUUID: UUID
    let visitClientUUID: UUID?
    let shotType: String
    let capturedAt: Date
    let width: Int?
    let height: Int?
    let publicLat: Double?
    let publicLon: Double?

    enum CodingKeys: String, CodingKey {
        case treeUUID = "tree_uuid"
        case visitClientUUID = "visit_client_uuid"
        case shotType = "shot_type"
        case capturedAt = "captured_at"
        case width, height
        case publicLat = "public_lat"
        case publicLon = "public_lon"
    }
}

/// `POST /trees`.
struct AddTreeBody: Encodable {
    let clientUUID: UUID
    let lat: Double
    let lon: Double
    let address: String?
    let placement: String?
    let speciesID: UUID?
    let landContext: String?

    enum CodingKeys: String, CodingKey {
        case clientUUID = "client_uuid"
        case lat, lon, address, placement
        case speciesID = "species_id"
        case landContext = "land_context"
    }
}

/// `POST /devices/claim`.
struct ClaimDeviceBody: Encodable {
    let deviceUUID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case deviceUUID = "device_uuid"
        case userID = "user_id"
    }
}

/// `DELETE /me`.
///
/// `pendingClientUUIDs` is not optional and there is no empty default, which is the whole reason
/// `RemoteAPI` takes a provider for it: an empty array is the *claim* that nothing is queued, and a
/// queued item arriving after a deletion with no tombstone waiting for it is precisely the case
/// `me.go` says the field exists for.
struct DeleteAccountBody: Encodable {
    let choice: String
    let pendingClientUUIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case choice
        case pendingClientUUIDs = "pending_client_uuids"
    }
}

// MARK: - Response bodies

/// `POST /sync`'s per-item verdict.
struct SyncResultsResponse: Decodable {
    struct Row: Decodable {
        let clientUUID: UUID
        let status: SyncResult.Status
        let error: APIError?

        enum CodingKeys: String, CodingKey {
            case clientUUID = "client_uuid"
            case status
            case error
        }
    }

    let results: [Row]
}

/// `POST /photos/begin` — `{photo_id, presigned_put_url}` (BUILD-PLAN §6).
struct BeginPhotoResponse: Decodable {
    let photoID: UUID
    let presignedPutURL: URL

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case presignedPutURL = "presigned_put_url"
    }
}

/// `GET /photos/{id}` — a presigned **GET**, not the bytes (`photos.go` says why at length).
struct PhotoSourceResponse: Decodable {
    let photoID: UUID
    let url: URL

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case url
    }
}

/// `POST /trees` when the dedupe did not trip.
struct AddTreeResponse: Decodable {
    let id: UUID
    let status: String
}

/// The `conflict` body's sibling of `error` — `{detail: {candidates: [NearbyTree]}}`.
///
/// `NearbyTree` decodes directly, because the service emits it in that type's own synthesized keys.
/// The candidates travel beside the envelope rather than inside it because `APIError.Envelope`'s
/// nested container decodes exactly `code`, `message` and `retryable` (`sync.go`).
struct ProximityConflictDetail: Decodable {
    struct Detail: Decodable {
        let candidates: [NearbyTree]
    }

    let detail: Detail
}

/// `GET /me/grove` — the account's half of a grove row.
///
/// **Not a `GroveEntry`**, and the missing fields are the point: there is no `display_name` and no
/// coordinate here because both are facts about the city's inventory, which this service does not
/// hold. `RoutedAPI.grove()` is where the two halves meet.
struct GroveDeltaResponse: Decodable {
    struct Row: Decodable {
        let treeUUID: UUID
        let lastVisitedAt: Date?
        let isFavorite: Bool
        /// `GroveRecord`, in its own synthesized keys — camelCase inside a snake_case object, and
        /// the golden fixture `server/testdata/grove.json` is what pins that from this side.
        let record: GroveRecord?
        let heroPhotoID: UUID?

        enum CodingKeys: String, CodingKey {
            case treeUUID = "tree_uuid"
            case lastVisitedAt = "last_visited_at"
            case isFavorite = "is_favorite"
            case record
            case heroPhotoID = "hero_photo_id"
        }
    }

    let entries: [Row]
    let total: Int
}

/// `GET /me/grove/species` — species ids and first-met dates, and deliberately no names.
///
/// The names and the ring's denominator are city-inventory facts; `reads.go` declines to guess at
/// the denominator in the same words.
struct GroveSpeciesDeltaResponse: Decodable {
    struct Row: Decodable {
        let speciesID: UUID
        let firstMet: Date

        enum CodingKeys: String, CodingKey {
            case speciesID = "species_id"
            case firstMet = "first_met"
        }
    }

    let known: [Row]
    let total: Int
}

/// `GET /me/grove/{treeID}/favorite`.
struct IsFavoriteResponse: Decodable {
    let isFavorite: Bool

    enum CodingKeys: String, CodingKey {
        case isFavorite = "is_favorite"
    }
}

/// `GET /me/map-membership?kind=`.
struct MapMembershipResponse: Decodable {
    let kind: String
    let treeIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case kind
        case treeIDs = "tree_ids"
    }
}

/// `GET /trees/{id}` — the community half of a tree profile, and only that half.
///
/// There is no `Tree` on this payload. `reads.go` states the reason: the tree's position, its
/// species and its inventory row are Class L, and a route returning them as well "would put the
/// map's own data on the network for no gain".
struct TreeCommunityHalfResponse: Decodable {
    struct PhotoRow: Decodable {
        let photoID: UUID
        let shotType: ShotType
        let capturedAt: Date
        let isPubliclyVisible: Bool

        enum CodingKeys: String, CodingKey {
            case photoID = "photo_id"
            case shotType = "shot_type"
            case capturedAt = "captured_at"
            case isPubliclyVisible = "is_publicly_visible"
        }
    }

    let treeUUID: UUID
    let photos: [PhotoRow]
    let photoCount: Int

    /// **Decoded, and deliberately carried no further** — `RemoteAPI.TreeCommunityDelta` does not
    /// have this field and `RoutedAPI.treeProfile` never sees it.
    ///
    /// Two rules forbid every use a client could make of it. `TreeProfile.visits` is a
    /// `Series<Visit>` — rows, plus whether they are all the rows — so a bare number cannot enter
    /// one without becoming a count with nothing behind it presented as a counted total, which is
    /// the claim `Series` exists to make unwritable (ERRATA **E38**). And drawing it on its own is
    /// what ARCHITECTURE §5.1 forbids **by this identifier's own name**: "if you find yourself
    /// writing `visitCount` into a user-visible string, stop."
    ///
    /// It stays decoded here rather than being dropped from the struct because this type's job is
    /// to be a complete, checkable statement of what `GET /trees/{id}` sends. A field the service
    /// emits and this client refuses is a fact worth having written down; silence about it is not.
    let visitCount: Int

    let ownPhotoIDs: [UUID]
    let deletablePhotoIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case treeUUID = "tree_uuid"
        case photos
        case photoCount = "photo_count"
        case visitCount = "visit_count"
        case ownPhotoIDs = "own_photo_ids"
        case deletablePhotoIDs = "deletable_photo_ids"
    }
}

/// `DELETE /me`'s report.
///
/// Three counters, against `AccountDeletion.Outcome`'s twenty. The mapping is in
/// `RemoteAPI.deleteAccount`, and every field it cannot fill stays at its zero **with the reason
/// written down there** rather than being inferred from these three.
struct DeleteAccountResponse: Decodable {
    let deleted: Bool
    let choice: String
    let contributions: Int
    let photos: Int
    let tombstones: Int
}
