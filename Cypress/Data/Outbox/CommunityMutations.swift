//
//  CommunityMutations.swift
//  Cypress — Data/Outbox
//
//  The payloads for spec §3.4's nine mutations, which until this round were written to this
//  device's tables and to nowhere else.
//
//  ── What was wrong, and who it was wrong for ───────────────────────────────────────────────────
//
//  `RoutedAPI` routes all of them to `local` and says why in as many words: "they have no queue
//  behind them at all". That sentence was a scope statement while nothing had a server to reach;
//  since #158's wiring round it is a loss. A signed-in contributor who adds a tree, names a
//  species, corrects one, reports a wrong name, reports a record that never held a tree, votes on
//  a photograph, deletes one, closes a report, or is redirected away from a hazard has that work
//  committed to their phone and to no account — and nothing anywhere says so, because from every
//  layer's point of view the write succeeded.
//
//  ── Why these are payload types and not the domain objects ─────────────────────────────────────
//
//  Three of the nine mutate a row that already exists (`correctSpecies`, the two dismissals) and
//  three name something that is not a tree (a photograph, a flag, a hazard category). None of them
//  has a domain object that is the mutation — `ReviewFlag` is the *result* of raising one, and a
//  dismissal produces no row at all. So the queue carries the act, in the smallest shape that lets
//  a server replay it, and each type says which act it is by being its own type rather than by
//  carrying a verb field.
//
//  Every one of them carries an `Attribution` for D9's reason: the act is performed on a device
//  that is anonymous until the third save, so requiring an account would make the record
//  unwritable on every device the app runs on (ERRATA E89's finding, on a different record). The
//  device-owned row is adopted by the account at `POST /devices/claim` exactly as a favorite is,
//  and `POST /sync`'s ownership gate accepts a device credential for an item that names a device
//  and no user (`server/internal/api/sync.go`).
//
//  **These carry no photo binaries and must not grow any.** `OutboxSendSink` has no photo method,
//  and the one of the nine that involves a photograph on disk — `addTree` — ingests it in the same
//  transaction that writes the row here, so by the time a drain runs there is nothing staged left
//  to send. See the send sink's own header for the argument.
//
//  Foundation only.
//

import Foundation

/// A community tree as it travels through the outbox.
///
/// **`treeID` is this device's tree id and it is not `clientUUID`.** They are separate fields
/// because they are separate facts on this side: `LocalAPI.addTree` mints a `Tree` with its own id
/// and stores `TreeDraft.clientUUID` beside it in `community_trees.client_uuid`, and every later
/// record about the tree — a visit, a photograph, a species assertion — keys on the *tree id*. A
/// server that keyed the row on the idempotency key instead would hold the tree under an id that
/// names nothing in any other table, which is the two-identity defect `community_trees` in
/// `server/migrations/001_initial.sql` records having already been fixed once.
///
/// The photograph is deliberately absent. `addTree` requires one and ingests it locally in the same
/// breath; sending binaries is the send sink's stated non-feature and its own ticket.
public struct TreeAddition: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    /// The id the tree has on this device and will have on the service.
    public let treeID: UUID
    public let attribution: Attribution
    public let coordinate: Coordinate
    public let address: String?
    /// How the coordinate was arrived at (`community_trees.placement`, `AppSchema` v10).
    public let placement: TreePlacement
    /// Optional for BUILD-PLAN §6's reason: "a required field does not collect better answers, it
    /// collects guesses."
    public let speciesID: UUID?
    /// Nil means "they did not say" and never one of the four (`TreeDraft.landContext`).
    public let landContext: LandContext?
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        treeID: UUID,
        attribution: Attribution,
        coordinate: Coordinate,
        address: String? = nil,
        placement: TreePlacement,
        speciesID: UUID? = nil,
        landContext: LandContext? = nil,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.treeID = treeID
        self.attribution = attribution
        self.coordinate = coordinate
        self.address = address
        self.placement = placement
        self.speciesID = speciesID
        self.landContext = landContext
        self.occurredAt = occurredAt
    }
}

/// Naming the species on a community tree, or correcting the name in force.
///
/// One type for both verbs and **two `OutboxItem.Kind`s**, which is not a contradiction: the two
/// acts carry identical facts and mean different things. A claim is a first statement about a tree
/// nobody has named; a correction supersedes somebody's statement, under the two-armed rule
/// `RULINGS R45` carries. Collapsing them into one kind with a boolean would put that distinction
/// inside a JSON field, where `outbox.kind` — which screen 17 groups by and a server dispatches on
/// — could not see it.
public struct SpeciesStatement: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let treeID: UUID
    public let speciesID: UUID
    public let attribution: Attribution
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        treeID: UUID,
        speciesID: UUID,
        attribution: Attribution,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.treeID = treeID
        self.speciesID = speciesID
        self.attribution = attribution
        self.occurredAt = occurredAt
    }
}

/// A report raised against a tree: the species is wrong, or the record never held a tree.
///
/// `flagID` is the row `LocalAPI` wrote, carried so that a dismissal arriving later names something
/// the service has seen. It is deliberately **not** reused as `clientUUID`: the flag's id is the
/// identity of a row and the client uuid is the identity of an *act*, and the dismissal of this
/// flag is a second act about the same row.
public struct ReviewReport: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let flagID: UUID
    public let treeID: UUID
    public let kind: ReviewFlag.Kind
    public let attribution: Attribution
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        flagID: UUID,
        treeID: UUID,
        kind: ReviewFlag.Kind,
        attribution: Attribution,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.flagID = flagID
        self.treeID = treeID
        self.kind = kind
        self.attribution = attribution
        self.occurredAt = occurredAt
    }
}

/// Closing a report without changing what it was about — the species seam's dismissal and the
/// record seam's, which are two kinds for the reason `SpeciesStatement` gives.
///
/// **Who was allowed to do it is decided on the device and stated here, not re-decided.** The
/// species dismissal has an author's arm (`LocalAPI.dismissSpeciesReview`) that depends on the
/// assertion chain, and the record dismissal is lead-only; neither rule is one this service can
/// evaluate, because it holds no assertion chain and no role. The item records who dismissed what;
/// a moderation surface that can adjudicate it is ARCHITECTURE §8's web deliverable.
public struct ReviewDismissal: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let flagID: UUID
    public let treeID: UUID
    public let attribution: Attribution
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        flagID: UUID,
        treeID: UUID,
        attribution: Attribution,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.flagID = flagID
        self.treeID = treeID
        self.attribution = attribution
        self.occurredAt = occurredAt
    }
}

/// A thumb up or down on a photograph, or taking one back.
///
/// **`vote` is optional and nil is a decision, not an absence.** It is the withdrawal —
/// `CypressAPI.setPhotoVote(photoID:vote:)` takes `PhotoVote?` and nil clears the row. The lesson is
/// already paid for on this exact seam: `POST /sync`'s `is_favorite` was a plain `bool` and an item
/// that omitted it recorded `false`, so "the heart went off, the client was told it worked, and
/// nothing anywhere errored". A decoder that reads a missing `vote` as "no change" and a present
/// null as "cleared" is the same trap, so this key is **always written**, null included.
///
/// `treeID` is the tree the photograph is on, resolved on device before the row is written. Every
/// `POST /sync` item names a tree and this one has no other way to.
public struct PhotoVoteCast: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let photoID: UUID
    public let treeID: UUID
    /// The resulting vote, or nil for "taken back". Encoded explicitly as null — see the header.
    public let vote: PhotoVote?
    public let attribution: Attribution
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        photoID: UUID,
        treeID: UUID,
        vote: PhotoVote?,
        attribution: Attribution,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.photoID = photoID
        self.treeID = treeID
        self.vote = vote
        self.attribution = attribution
        self.occurredAt = occurredAt
    }

    private enum CodingKeys: String, CodingKey {
        case clientUUID, photoID, treeID, vote, attribution, occurredAt
    }

    /// `encodeIfPresent` is what the synthesized encoder would use, and it would drop the key on the
    /// one value that means something. See the header.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientUUID, forKey: .clientUUID)
        try container.encode(photoID, forKey: .photoID)
        try container.encode(treeID, forKey: .treeID)
        try container.encode(vote, forKey: .vote)
        try container.encode(attribution, forKey: .attribution)
        try container.encode(occurredAt, forKey: .occurredAt)
    }
}

/// Withdrawing a photograph.
///
/// **The act, and not its report.** `PhotoDeletion` — the value `deletePhoto` returns — carries four
/// counts, and every one of them "is a claim the app makes to a person about something
/// irreversible" about *this device's* files. None of them describes what a server holds, so none of
/// them is sent: what travels is which photograph was withdrawn, by whom, and when.
///
/// The ordering PR #94 established is upstream of this type and is not weakened by it: the row is
/// enqueued **inside** the transaction that tombstones the photograph, behind
/// `PhotoOwner.permitsRemoval(by:takenOnDevice:)` and the SQL gate that repeats it
/// (`ContributionStore.removalPredicate`). A queued withdrawal therefore exists only for a deletion
/// that both gates already allowed and that committed.
public struct PhotoWithdrawal: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let photoID: UUID
    public let treeID: UUID
    public let attribution: Attribution
    public let occurredAt: Date

    public init(
        clientUUID: UUID,
        photoID: UUID,
        treeID: UUID,
        attribution: Attribution,
        occurredAt: Date
    ) {
        self.clientUUID = clientUUID
        self.photoID = photoID
        self.treeID = treeID
        self.attribution = attribution
        self.occurredAt = occurredAt
    }
}

/// The hazard-redirect log line (BUILD-PLAN §6's `POST /reports/hazard-redirect`).
///
/// It wraps `HazardRedirectEvent` rather than restating it: the event is a `Core` model with a tree,
/// a category and the moment the sheet was shown, and those are exactly the facts the report is. The
/// wrapper adds the two the queue needs and the event has no business carrying — an idempotency key
/// and who was redirected.
public struct HazardRedirectReport: Codable, Hashable, Sendable {
    public let clientUUID: UUID
    public let event: HazardRedirectEvent
    public let attribution: Attribution

    public init(clientUUID: UUID, event: HazardRedirectEvent, attribution: Attribution) {
        self.clientUUID = clientUUID
        self.event = event
        self.attribution = attribution
    }
}
