//
//  AnonymizedPhotoNoticeTests.swift
//  CypressTests
//
//  Task #131 · the gate behind the sentence both photo surfaces draw when a photograph is shown and
//  has no delete on it.
//
//  **What this file does not do is assert the words**, and that is deliberate. The copy is a design
//  decision recorded in `docs/rulings-pending/anonymized-photo-has-no-delete.md`; a test spelling it
//  back would pin the phrasing rather than the fact and would go red on every edit that improved it.
//  What can be wrong here is *which photograph the sentence lands on*, and that is what is pinned:
//  a photograph nobody owns gets it, an owned one does not, and a photograph nobody owns that
//  somehow still carries a delete does not get it either — because a sentence saying a record is
//  nobody's, drawn beside a button offering to remove it, is worse than either alone.
//
//  The reachability half — that the sentence is on the running screen and that the delete really is
//  absent beside it — is `CypressUITests/AnonymizedPhotoNoticeUITests`, for the reason ERRATA E173
//  and RULINGS R21 both land on: this project has twice shipped something correct that nobody could
//  reach, and a value-level test cannot tell the difference.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@MainActor
@Suite("A photograph nobody owns says so")
struct AnonymizedPhotoNoticeTests {

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000131")!

    private static func photo(daysAgo: Int) -> Photo {
        Photo(
            treeID: treeID,
            shotType: .fullTree,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000 - Double(daysAgo) * 86_400)
        )
    }

    /// One photograph this device may delete and one the leaving door left behind, on one tree —
    /// the state screen 20 actually draws, where the two rows sit one above the other and the whole
    /// point is that they differ.
    @Test("the sentence lands on the ownerless photograph and on no other")
    func onlyTheOwnerlessRow() {
        let mine = Self.photo(daysAgo: 1)
        let ownerless = Self.photo(daysAgo: 2)
        let model = TreePhotosModel(
            treeID: Self.treeID,
            photos: [mine, ownerless],
            deletableIDs: [mine.id],
            anonymizedIDs: [ownerless.id]
        )

        #expect(model.isNobodysToRemove(ownerless))
        #expect(model.isDeletable(mine))
        #expect(
            !model.isNobodysToRemove(mine),
            "a photograph this device may delete was told it belongs to nobody"
        )
    }

    /// The first read has not landed yet, so nothing is known about anybody's photograph. A screen
    /// that spoke here would be stating a fact it has not read — the same reason `deletableIDs`
    /// starts empty and hides the control rather than offering one.
    @Test("nothing is said about a photograph before the read that would know")
    func silentUntilTheReadLands() {
        let unread = Self.photo(daysAgo: 1)
        let model = TreePhotosModel(treeID: Self.treeID, photos: [unread])
        #expect(!model.isNobodysToRemove(unread))
        #expect(!model.isDeletable(unread))
    }

    /// The disagreement case. If a row ever arrives ownerless *and* deletable, the control wins and
    /// the sentence is not drawn: a surface must not tell somebody a record is nobody's while
    /// offering them the button that removes it.
    @Test("a control beside the sentence means the control, not the sentence")
    func theControlWins() {
        let contradictory = Self.photo(daysAgo: 1)
        let model = TreePhotosModel(
            treeID: Self.treeID,
            photos: [contradictory],
            deletableIDs: [contradictory.id],
            anonymizedIDs: [contradictory.id]
        )
        #expect(model.isDeletable(contradictory))
        #expect(
            !model.isNobodysToRemove(contradictory),
            "the screen would have drawn 'nobody's to remove' beside a live delete control"
        )
    }
}
#endif
