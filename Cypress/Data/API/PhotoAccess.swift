//
//  PhotoAccess.swift
//  Cypress — Data/API
//
//  The two things a screen has to be able to do with a photograph and could not: **see it**, and
//  **say what it thinks of it** (ERRATA E125).
//
//  ── Why "see it" was missing ──────────────────────────────────────────────────────────────
//  E37 fixed the wrong half. It established that a contributor may see their own photographs
//  whatever moderation has not yet done about them, and it gave `Photo` the two predicates that say
//  so. What it did not do is give anybody the **bytes**: `Photo.storageKey` is a filename inside
//  `LocalAPI`'s own container directory, and ARCHITECTURE §4 forbids a view reaching into it. So the
//  app has shipped with a photograph on exactly one screen — screen 04, which holds the image it
//  just captured in memory — and a gradient everywhere a photograph belongs.
//
//  On a server this is `GET /photos/{id}` returning a redirect to object storage. Locally it is a
//  file read, and it is on the API for the same reason every other read is: the boundary is the
//  boundary whether or not the thing behind it is a network.
//
//  ── Why voting is here rather than on a moderation surface ────────────────────────────────
//  A3 has always ended "a manual pin by any org member overrides", and nothing could pin one. This
//  is that pin, spelled as the thing a person actually does when looking at a set of photographs of
//  a tree: keep this one, not that one. `PhotoHero` in `Core` is the rule it feeds; `AppSchema` v8
//  is where it is written down.
//

import Foundation

// MARK: - Default implementations
//
// **Both methods are declared on the protocol as well**, and `CypressAPI` says at length why: a
// default that is *only* an extension member dispatches statically, so an implementation's override
// is unreachable through `any CypressAPI`. These are defaults for a requirement, not a substitute
// for declaring one.

public extension CypressAPI {

    /// The bytes of a photograph this device may show.
    ///
    /// A default rather than a bare requirement, on `speciesGuide`'s reasoning: an implementation
    /// with no binaries genuinely has none, and `RemoteAPI` and every preview double would otherwise
    /// each write this same throw. `notFound` and not an empty `Data` — a zero-byte JPEG is a
    /// corrupt photograph, and a screen that told the difference by decoding it would be deciding a
    /// question the API should answer.
    ///
    /// `LocalAPI` overrides it, because `LocalAPI` has the files.
    func photoData(id: UUID) async throws -> Data {
        throw APIError.notFound
    }

    /// Casts, changes or withdraws this viewer's vote on a photograph. `nil` withdraws it.
    ///
    /// Defaulted to `notFound` for the same reason: an implementation with no photographs has
    /// nothing to vote on, and the honest answer to voting on a photograph that is not there is
    /// that it is not there.
    func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {
        throw APIError.notFound
    }

    /// Removes one photograph this person contributed.
    ///
    /// `notFound` on the same argument again, and it is the safe direction twice over: an
    /// implementation with no photographs has none to remove, and a deletion default that quietly
    /// *succeeded* would be the worst possible shape for this particular method — a screen would
    /// tell somebody their photograph was gone while it sat on a disk somewhere.
    func deletePhoto(id: UUID) async throws -> PhotoDeletion {
        throw APIError.notFound
    }
}

// MARK: - What a deletion did

/// The result of removing one photograph, in the terms the caller has to be able to check.
///
/// Returned rather than logged for `AccountDeletion.Outcome`'s reason: every number here is a claim
/// the app makes to a person about something irreversible, and a claim nothing checks is a claim
/// that quietly stops being true. `removedFiles` in particular is the one a test can assert that a
/// green "the call did not throw" cannot — a delete that deleted nothing returns zero here.
public struct PhotoDeletion: Sendable, Equatable {
    /// The photograph that went.
    public let photoID: UUID
    /// The tree it was on, so a caller can reload the surface it was drawn on.
    public let treeID: UUID
    /// Files actually removed from disk: the confirmed binary, the staged one, or neither when the
    /// bytes had never arrived.
    public let removedFiles: Int
    /// Votes deleted with it — everybody's, not only this person's. They were judgments about a
    /// photograph that no longer exists.
    public let deletedVotes: Int
    /// Queued mutations that were still carrying this photograph's staged binary and no longer are.
    /// Non-zero means the deletion caught an upload that had not drained yet, which is the window in
    /// which a photograph could otherwise have been "deleted" and then published.
    public let dequeuedBinaries: Int
    /// Whether this was the last photograph on a tree that exists *because* somebody photographed it
    /// (BUILD-PLAN §6, "Community add: requires photo"). The deletion is allowed and this says it
    /// happened — see `LocalAPI.deletePhoto` for the argument.
    public let leftACommunityTreeWithoutAPhotograph: Bool

    public init(
        photoID: UUID,
        treeID: UUID,
        removedFiles: Int,
        deletedVotes: Int,
        dequeuedBinaries: Int,
        leftACommunityTreeWithoutAPhotograph: Bool
    ) {
        self.photoID = photoID
        self.treeID = treeID
        self.removedFiles = removedFiles
        self.deletedVotes = deletedVotes
        self.dequeuedBinaries = dequeuedBinaries
        self.leftACommunityTreeWithoutAPhotograph = leftACommunityTreeWithoutAPhotograph
    }
}
