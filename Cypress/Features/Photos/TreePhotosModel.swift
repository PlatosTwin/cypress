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

    init(treeID: UUID, api: (any CypressAPI)? = nil) {
        self.treeID = treeID
        self.api = api
    }

    /// Fixture initialiser — a finished state, for previews and the screen sweep.
    init(treeID: UUID, photos: [Photo], tallies: [UUID: PhotoTally] = [:], treeName: String? = nil) {
        self.treeID = treeID
        self.api = nil
        self.photos = photos
        self.tallies = tallies
        self.treeName = treeName
        self.isLoading = false
    }

    /// The photograph screen 03 leads with, by the one rule in `Core`.
    var heroID: UUID? { PhotoHero.choose(from: photos, tallies: tallies)?.id }

    var isEmpty: Bool { !isLoading && photos.isEmpty }

    func tally(_ photoID: UUID) -> PhotoTally { tallies[photoID] ?? .none }

    func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        guard let profile = try? await api.treeProfile(id: treeID) else { return }
        // The set this device may show — moderation gates publication, not a person's own screen
        // (E37). `TreeProfile.photos` is already only what this installation wrote.
        photos = profile.photos.items.filter(\.isVisibleToItsContributor)
        tallies = profile.photoTallies
        treeName = profile.activeName?.name ?? profile.species?.commonName
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
