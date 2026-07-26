import Foundation

/// `photos.shot_type` (BUILD-PLAN §4), verbatim.
///
/// PRODUCT §3 lists a longer set (`trunk_dbh`, `canopy_up`, `leaf_closeup`, `site`); BUILD-PLAN
/// wins on data (ARCHITECTURE §1), so the four below are the stored vocabulary.
public enum ShotType: String, Codable, Sendable, Hashable, CaseIterable {
    case fullTree = "full_tree"
    case trunk = "trunk"
    case leaf = "leaf"
    case other = "other"

    /// The ghost overlay reuses the last full-tree photo at 30 % opacity (PRODUCT §5 M4).
    public var supportsGhostOverlay: Bool { self == .fullTree }
}

/// `photos.moderation_state` (BUILD-PLAN §4).
public enum ModerationState: String, Codable, Sendable, Hashable, CaseIterable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"

    /// Only approved photos reach a public surface (BUILD-PLAN §10, A3).
    ///
    /// **This is not the predicate a screen on the contributor's own device asks.** Nothing in the
    /// shipping app can set `.approved` — there is no moderation service, both `beginPhotoUpload`
    /// and `addTree` construct photos as `.pending`, and the schema's default is `'pending'` — so a
    /// surface gated on this shows nothing at all. Which is right for a *public* surface, and wrong
    /// for showing somebody the photograph they just took. See `Photo.isPubliclyVisible` and
    /// `Photo.isVisibleToItsContributor` for the two halves, kept apart on purpose (ERRATA E37).
    public var isPubliclyVisible: Bool { self == .approved }
}

/// A photo (BUILD-PLAN §4 `photos`).
///
/// EXIF, including GPS, is stripped on ingest; the capture timestamp and the app's own fuzzed
/// coordinates live in columns, never in the file (BUILD-PLAN §3, DECISIONS §3.10). There is
/// therefore no `exifGPS` property here, and `publicCoordinate` is pre-snapped to the 25 m grid.
///
/// This paragraph used to say "server-side", and it was a description of a thing nobody did: there
/// is no server, and the local ingest path moved the camera's file across untouched. It is
/// `PhotoBinary` that makes the sentence true (ERRATA E40), and the sentence stayed half-false until
/// E148: the strip was on `LocalAPI.uploadPhoto`, and a community add's photograph never goes through
/// an upload. It is stripped at the shutter now — `VisitPhotoStaging.write`, the funnel both capture
/// screens use — with `uploadPhoto` and `addTree` both re-checking on the way into a record.
/// `publicCoordinate` is deliberately left nil by everything that ships — not storing a location is
/// the privacy-safe direction, and E42 says why.
public struct Photo: CoreEntity, SoftDeletable {
    public let id: UUID
    public let treeID: UUID
    /// Nil when the photo was attached outside a visit (e.g. a care event or an observation).
    public let visitID: UUID?
    public var storageKey: String?
    public var shotType: ShotType
    public var moderationState: ModerationState
    /// Face and licence-plate blurring runs at upload (BUILD-PLAN §10).
    public var blurApplied: Bool
    public var width: Int?
    public var height: Int?
    public let capturedAt: Date
    /// The app's own coordinate for this photo, already snapped to the universal 25 m grid
    /// (A7, BUILD-PLAN §10). Nil when no location was captured.
    public var publicCoordinate: Coordinate?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        visitID: UUID? = nil,
        storageKey: String? = nil,
        shotType: ShotType,
        moderationState: ModerationState = .pending,
        blurApplied: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        capturedAt: Date,
        publicCoordinate: Coordinate? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.visitID = visitID
        self.storageKey = storageKey
        self.shotType = shotType
        self.moderationState = moderationState
        self.blurApplied = blurApplied
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
        self.publicCoordinate = publicCoordinate.map { $0.snappedToPublicPhotoGrid() }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Pixel count, the tie-breaker for "best photo" (A3).
    public var resolution: Int { (width ?? 0) * (height ?? 0) }

    // MARK: - Who may see it
    //
    // Two questions, deliberately two names. "The world can see this" is moderation's answer and it
    // gates every public surface. "I can see this" is a different question with a different answer:
    // moderation is a gate on publication, not a gate between a contributor and the photograph they
    // took on the device they took it with. DECISIONS §3 puts moderation on public timelines,
    // published locations and the open export, and says nothing about a person's own screen.
    //
    // A predicate that meant both would have to pick one, and picking the public one is what left
    // the app with no photograph anywhere: no hero, no season strip, no best photo, on every tree
    // (ERRATA E37).

    /// Whether this photo may be shown on a **public** surface — the shared tree page, the share
    /// card, anything a stranger can reach (BUILD-PLAN §10, A3).
    ///
    /// Nothing in the app today can make this true, because nothing moderates. That is honest: a
    /// `.pending` photo has in fact not been moderated, and marking it `.approved` to make a screen
    /// render would be a claim about a review that never happened.
    public var isPubliclyVisible: Bool {
        moderationState.isPubliclyVisible && deletedAt == nil
    }

    /// Whether the person who contributed this photo may see it on their own device.
    ///
    /// Moderation does not enter into it. What does is deletion: a removed photo is removed for
    /// everybody. The caller is responsible for having established that the photo is in fact this
    /// contributor's — `TreeProfile.ownPhotoIDs` is where that fact is carried.
    public var isVisibleToItsContributor: Bool { deletedAt == nil }

    /// A3's eligibility half for the **public** best photo: most recent approved `full_tree`, ties
    /// broken by resolution; a manual pin by any org member overrides.
    public var isPublicBestPhotoCandidate: Bool {
        shotType == .fullTree && isPubliclyVisible
    }

    /// A3's framing half alone, for choosing the best photo out of a set whose visibility the
    /// caller has already decided. Applying this to an unfiltered series would publish a photo
    /// nobody approved; applying `isPublicBestPhotoCandidate` to a device-local set would show the
    /// contributor nothing.
    public var isBestPhotoShot: Bool {
        shotType == .fullTree && deletedAt == nil
    }
}

// MARK: - Ownership

/// Whose photograph this is (`photos.user_id` / `photos.device_id`, `AppSchema` v12).
///
/// **Three cases, where `FavoriteOwner` and `ReminderOwner` have two**, and the third is the whole
/// reason this is a separate type rather than a fourth use of `FavoriteOwner`. Those two live under
/// `CHECK ((user_id IS NULL) <> (device_id IS NULL))` — exactly one owner, no other state
/// representable — because a reminder and a favourite are *deleted* with the account that owns them
/// under both doors of `AccountDeletionChoice`. A photograph is not: the default door's promise is
/// that the work stays on the tree and the name comes off it, so a photograph owned by nobody is
/// not a hole in the rule, it is where the rule ends up. v12's CHECK is at most one owner for
/// exactly that reason, and this enum is that CHECK in Swift.
///
/// E89 said the same thing about `FavoriteOwner` and `ReminderOwner`: same shape, different
/// invariants, kept apart on purpose so that neither one's rules leak onto the other.
public enum PhotoOwner: Hashable, Sendable {
    case user(UUID)
    case device(UUID)
    /// Anonymized: the account that took it was deleted through the door that leaves contributions
    /// where they are. The photograph is on its tree and belongs to nobody, which means nobody can
    /// delete it either — you do not get to reach back through a deletion you already made.
    case nobody

    /// D9's rule, the same one `FavoriteOwner` applies: a contribution belongs to the signed-in user
    /// when there is one and to this device otherwise. A write always has one of those, so this
    /// initializer never produces `.nobody` — only a deletion can.
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

    /// Whether this photograph is one *this* installation may act on — the predicate behind
    /// "delete your own photograph".
    ///
    /// Both arms, deliberately, exactly as `ContributionStore.privateReminders` and
    /// `GroveQueries.groveTreeIDs` read both: a photograph taken before sign-in is owned by the
    /// device and is still the same person's, and on this phone `claimDevice` is what eventually
    /// moves it. `.nobody` is false for everybody, which is the correct answer for a photograph
    /// whose contributor deleted their account and asked for their records to be left where they
    /// are — it is on the tree, and it is nobody's to take back.
    public func isOwned(by attribution: Attribution) -> Bool {
        switch self {
        case let .user(id): return attribution.userID == id
        case let .device(id): return attribution.deviceID == id
        case .nobody: return false
        }
    }

    /// What `POST /devices/claim` does to a photograph (D9): a device-owned one moves onto the
    /// account, an account-owned one is left alone so claiming twice cannot move a record between
    /// accounts, and an anonymized one stays anonymized — adoption is for work that has never been
    /// attributed, not for work somebody has already asked to be unlinked from.
    public func adopted(by userID: UUID) -> PhotoOwner {
        switch self {
        case .user, .nobody: return self
        case .device: return .user(userID)
        }
    }
}

// MARK: - Voting

/// A thumb, up or down, on one photograph (`photo_votes`, `AppSchema` v8).
///
/// The raw values are the summands: a tally is the arithmetic sum of the votes cast, so the type
/// and the column agree by construction rather than by a mapping somebody has to keep in step.
public enum PhotoVote: Int, Codable, Sendable, Hashable, CaseIterable {
    case down = -1
    case up = 1
}

/// What a photograph's voters have said about it, and what this viewer said.
///
/// `score` is across everybody who voted; `ownVote` is this viewer's row, which is what the browser
/// draws as a filled thumb. On a device with no account and no sync those two are the same person,
/// and they are still two facts: the hero is decided by the first and the control is drawn from the
/// second.
public struct PhotoTally: Sendable, Hashable, Codable {
    public let score: Int
    public let ownVote: PhotoVote?

    public init(score: Int = 0, ownVote: PhotoVote? = nil) {
        self.score = score
        self.ownVote = ownVote
    }

    public static let none = PhotoTally()
}

/// Which photograph a tree leads with.
///
/// **A3, with its own escape clause finally implemented.** A3 reads: "best photo = most recent
/// `full_tree`, ties broken by resolution; **a manual pin by any org member overrides**." Nothing
/// in the app could pin one, so the override half was dead text and the heuristic was the whole
/// rule. A thumbs-up is that pin (ERRATA E125): a person looking at the photographs and saying
/// *this one*, which is better evidence about a photograph than its shot type and its timestamp.
///
/// The order, therefore:
///
/// 1. **A down-voted photograph is never the hero.** Not a tie-break — an exclusion. Somebody
///    looked at it and said no.
/// 2. **An up-voted photograph wins**, highest score first; the most recent breaks a tie, then
///    resolution. Shot type does not enter into it, because the pin overrides the heuristic rather
///    than being ranked inside it.
/// 3. **Otherwise A3**: the most recent `full_tree`, ties by resolution.
/// 4. **Otherwise the most recent photograph of any kind.** A tree photographed only in close-up
///    has no A3 candidate, and drawing a gradient over a tree that has photographs would be the
///    same emptiness E37 left behind. The eyebrow that names the choice is the caller's to omit.
///
/// Deliberately free of any visibility judgement: the caller passes the set it may show, exactly as
/// `Photo.isBestPhotoShot` requires, and this ranks it.
public enum PhotoHero {

    public static func choose(from photos: [Photo], tallies: [UUID: PhotoTally] = [:]) -> Photo? {
        func score(_ photo: Photo) -> Int { tallies[photo.id]?.score ?? 0 }

        let eligible = photos.filter { $0.deletedAt == nil && score($0) >= 0 }
        guard !eligible.isEmpty else { return nil }

        /// Most recent, then most pixels — A3's ordering, reused by every tier below.
        func mostRecent(_ candidates: [Photo]) -> Photo? {
            candidates.max {
                ($0.capturedAt, $0.resolution) < ($1.capturedAt, $1.resolution)
            }
        }

        let pinned = eligible.filter { score($0) > 0 }
        if !pinned.isEmpty {
            let best = pinned.map(score).max() ?? 0
            return mostRecent(pinned.filter { score($0) == best })
        }

        return mostRecent(eligible.filter(\.isBestPhotoShot)) ?? mostRecent(eligible)
    }
}
