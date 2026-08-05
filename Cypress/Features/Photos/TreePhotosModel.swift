//
//  TreePhotosModel.swift
//  Cypress — Features/Photos
//
//  Screen 20's state: every photograph of one tree, what has been voted on each, and which one is
//  therefore the hero (ERRATA E125).
//
//  **The hero is derived, never stored.** `PhotoHero.choose` is asked again after every vote rather
//  than a `heroID` being kept and updated, because a stored answer is a second place for the rule to
//  live and the whole point of this screen is that it agrees with screen 03.
//

import Foundation
import Observation

@MainActor
@Observable
final class TreePhotosModel {

    private let api: (any CypressAPI)?
    let treeID: UUID

    private(set) var photos: [Photo] = []
    private(set) var tallies: [UUID: PhotoTally] = [:]
    private(set) var treeName: String?
    private(set) var isLoading = true
    /// A vote that could not be written. Shown rather than swallowed: the thumb springs back and the
    /// screen says why, because a control that silently does nothing reads as a broken control.
    private(set) var voteError: String?
    /// A deletion that could not be written, in the same register as `voteError` and for the same
    /// reason — with one difference that matters: this one must never be silent, because the person
    /// has just been told a photograph is about to be destroyed and has to know whether it was.
    private(set) var deleteError: String?
    /// Which of `photos` this person may delete (`TreeProfile.deletablePhotoIDs`). Empty until the
    /// first read completes, so the control cannot be drawn before the answer is known — and empty
    /// forever on an implementation that cannot answer, which hides the control rather than offering
    /// one that would fail.
    private(set) var deletableIDs: Set<UUID> = []
    /// Which of `photos` nobody owns (`TreeProfile.anonymizedPhotoIDs`). Empty until the first read
    /// completes and empty forever on an implementation that cannot answer, for `deletableIDs`'
    /// reason turned around: this one is read to *say* something about a photograph, and a screen
    /// that does not know had better say nothing.
    private(set) var anonymizedIDs: Set<UUID> = []
    /// Whether this tree exists because somebody photographed it (`Tree.source == .community`).
    /// Read once with the photographs so the confirmation can name the consequence of removing the
    /// last one — BUILD-PLAN §6, "Community add: requires photo".
    private(set) var isCommunityAdded = false
    /// The photograph a confirmation is currently open for. `nil` is the resting state, which is
    /// what makes one tap on the control destroy nothing.
    var pendingDeletion: Photo?

    init(treeID: UUID, api: (any CypressAPI)? = nil) {
        self.treeID = treeID
        self.api = api
    }

    /// Fixture initializer — a finished state, for previews and the screen sweep.
    init(
        treeID: UUID,
        photos: [Photo],
        tallies: [UUID: PhotoTally] = [:],
        treeName: String? = nil,
        deletableIDs: Set<UUID> = [],
        anonymizedIDs: Set<UUID> = [],
        isCommunityAdded: Bool = false
    ) {
        self.treeID = treeID
        self.api = nil
        self.photos = photos
        self.tallies = tallies
        self.treeName = treeName
        self.deletableIDs = deletableIDs
        self.anonymizedIDs = anonymizedIDs
        self.isCommunityAdded = isCommunityAdded
        self.isLoading = false
    }

    /// The photograph screen 03 leads with, by the one rule in `Core`.
    ///
    /// Over the **whole** timeline, never the filtered slice (task #154): the hero is a fact about
    /// the tree, and a browser narrowed to trunks must not start claiming a trunk leads the page.
    var heroID: UUID? { PhotoHero.choose(from: photos, tallies: tallies)?.id }

    var isEmpty: Bool { !isLoading && photos.isEmpty }

    // MARK: - The subject filter (task #154)

    /// The framing the list is narrowed to, or nil for the whole timeline. A view of the same
    /// series, not a different read: `photos` stays whole, so the hero, the deletion gate and the
    /// community-add sentence keep answering for the tree rather than for the slice.
    var subjectFilter: ShotType?

    /// What the list draws under the current filter.
    var filteredPhotos: [Photo] {
        guard let subjectFilter else { return photos }
        return photos.filter { $0.shotType == subjectFilter }
    }

    /// Whether the narrowing, not the tree, is why the list is empty — the state that gets its own
    /// sentence, because "no photos" would be false of a tree whose timeline is one tap away.
    var filterHasNoPhotos: Bool {
        !isLoading && !photos.isEmpty && filteredPhotos.isEmpty
    }

    func tally(_ photoID: UUID) -> PhotoTally { tallies[photoID] ?? .none }

    func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        guard let profile = try? await api.treeProfile(id: treeID) else { return }
        // The set this device may show — `TreeProfile.visiblePhotos` (ERRATA E215), the same
        // predicate screen 03's hero reads. Own photos stay visible pre-moderation
        // (`isVisibleToItsContributor`); moderation gates publication for everyone else's
        // (`isPubliclyVisible`, ERRATA E37). This used to filter every row on
        // `isVisibleToItsContributor` alone, which was silently correct only because nothing syncs
        // anybody else's photographs down yet — the day a read returns one, this screen would have
        // shown it, unmoderated, to a stranger.
        photos = profile.visiblePhotos.items
        tallies = profile.photoTallies
        treeName = profile.activeName?.name ?? profile.species?.commonName
        deletableIDs = profile.deletablePhotoIDs
        anonymizedIDs = profile.anonymizedPhotoIDs
        isCommunityAdded = profile.tree.source == .community
    }

    func isDeletable(_ photo: Photo) -> Bool { deletableIDs.contains(photo.id) }

    /// Whether this photograph is shown here and is nobody's to remove — the state both surfaces
    /// say out loud rather than drawing one fewer control (task #131).
    ///
    /// **Both halves are asked, and the second is not redundant.** A row with no owner should of
    /// course have no delete on it, but the two facts arrive from two different reads and the
    /// sentence is a claim about the *absence of the control*. If they ever disagree — an ownerless
    /// row that the deletion gate somehow admits — the honest surface is the control and no
    /// sentence, not a sentence contradicted by the button beside it.
    func isNobodysToRemove(_ photo: Photo) -> Bool {
        anonymizedIDs.contains(photo.id) && !isDeletable(photo)
    }

    /// Whether removing this photograph would leave a community-added tree with none — the one case
    /// where the confirmation says something extra, because it is the one case where the record ends
    /// up in a state its own creation rule forbids (see `LocalAPI.deletePhoto` for why that is
    /// allowed and not refused).
    func isLastPhotographOfACommunityAdd(_ photo: Photo) -> Bool {
        isCommunityAdded && photos.count == 1 && photos.first?.id == photo.id
    }

    /// Removes a photograph, having been asked twice.
    ///
    /// The re-read afterwards is `vote`'s pattern and is load-bearing for the same reason and one
    /// more: the hero is derived, so the screen above this one has to be recomputed from the
    /// surviving set rather than patched, and `deletableIDs` is a fact only the store holds.
    func delete(_ photoID: UUID, images: PhotoImageStore?) async {
        guard let api else { return }
        deleteError = nil
        do {
            _ = try await api.deletePhoto(id: photoID)
            // The decoded copy goes with the file. Without this the picture stays on screen — and
            // stays in memory — after the bytes it came from have been destroyed, which for this
            // feature is not a cache staleness bug but a failure to do the thing that was asked.
            images?.forget(photoID)
            await load()
        } catch {
            deleteError = TreePhotosCopy.deleteFailed
        }
    }

    /// Tapping a thumb that is already filled takes the vote back — a toggle, because the second tap
    /// on a control that is already on has one obvious meaning and "vote up harder" is not it.
    func vote(_ vote: PhotoVote, on photoID: UUID) async {
        guard let api else { return }
        let wanted: PhotoVote? = tally(photoID).ownVote == vote ? nil : vote
        voteError = nil
        do {
            try await api.setPhotoVote(photoID: photoID, vote: wanted)
            // Re-read rather than patching the dictionary: the score is a sum over everybody, and a
            // client that computed the new total itself would be guessing at what the other votes
            // are the moment there is more than one voter.
            await load()
        } catch {
            voteError = TreePhotosCopy.voteFailed
        }
    }
}
