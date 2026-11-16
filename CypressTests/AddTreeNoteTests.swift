//
//  AddTreeNoteTests.swift
//  CypressTests
//
//  Round C3, the note under the Add this tree button and the two empty-place texts.
//
//  The owner's rulings of 2026-11-15:
//  - The note under the button says who can see the tree, by the account's sharing state. Signed
//    out and not sharing say "Only you can see it", because the phone does send such a tree to the
//    service, which keeps it private. When the phone does not know, the note stays as it was.
//  - At the accessibility text sizes the note moves into the scrolling form; only the button stays
//    pinned ("move into the scroll").
//  - The map's "No trees on record here" card and the empty "What tree is this?" list name both
//    kinds of tree the app draws: the city inventory and the trees people have added.
//
//  The words are the owner's, so the tests hold them exactly. The tests also hold the facts the
//  words claim: the state is read each time the screen appears, and an added tree, this phone's or
//  someone else's, keeps both empty texts away.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("C3 · the note under Add this tree, and the two empty places", .timeLimit(.minutes(5)))
struct AddTreeNoteTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3B01")!
    private static let userID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3B02")!
    /// Inside `CommunityRefresherTests.tile`, where no seed is attached, so nothing but the trees
    /// these tests put there is on record.
    private static let spot = CommunityRefresherTests.spot

    // MARK: - The note, by sharing state

    /// Red-proof: swap the `.signedOut` and `.notSharing` arms of `VisitAddTreeCopy.footnote(for:)`
    /// — red on both of those two expectations.
    @Test("each sharing state has the owner's sentence")
    func eachStateHasItsSentence() {
        #expect(
            VisitAddTreeCopy.footnote(for: .sharing)
                == "Recorded as community-added and unverified. Everyone using Cypress can see it once it is sent."
        )
        #expect(
            VisitAddTreeCopy.footnote(for: .signedOut)
                == "Recorded as community-added and unverified. Only you can see it. "
                + "Everyone using Cypress can see it after you sign in."
        )
        #expect(
            VisitAddTreeCopy.footnote(for: .notSharing)
                == "Recorded as community-added and unverified. Only you can see it. "
                + "Everyone using Cypress can see it after you agree to share your tree records."
        )
        // The owner, 2026-11-15: "Keep today's note" when the phone holds no answer.
        #expect(
            VisitAddTreeCopy.footnote(for: .unknown)
                == "Recorded as community-added and unverified, on this phone."
        )
    }

    /// The ruling on private property: the note does not mention it, whatever the state. The land
    /// row above the button already says it when the reader chose it.
    @Test("no sharing state's note mentions private property")
    func theNoteDoesNotMentionPrivateProperty() {
        for sharing in [ContributionSharing.sharing, .signedOut, .notSharing, .unknown] {
            let note = VisitAddTreeCopy.footnote(for: sharing).lowercased()
            #expect(!note.contains("private"), "the \(sharing) note mentions private property: \(note)")
            #expect(!note.contains("property"), "the \(sharing) note mentions private property: \(note)")
        }
    }

    // MARK: - The state is read when the screen appears

    /// The reader opens the add screen signed out, leaves, signs in and agrees to share, and opens
    /// it again. The second appearance must say what the account is now. `load()` is what the
    /// screen's `.task` runs on each appearance, and the reader is the composition root's own
    /// (`ContributionSharing.reader(local:)`) over a real `LocalAPI`.
    ///
    /// Red-proof: take `await refreshSharing()` out of `VisitAddTreeModel.load()` — red on "the
    /// first appearance read no state" (the note is nil, so the screen draws none).
    @MainActor
    @Test("a sign-in between two appearances changes the note")
    func theStateIsReadOnEachAppearance() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let reader = ContributionSharing.reader(local: api)

        let first = Self.model(api: api, reader: reader)
        #expect(first.sharing == nil, "the note has a state before the screen appeared")
        await first.load()
        first.stop()
        #expect(first.sharing == .signedOut, "the first appearance read no state, or the wrong one")

        try await api.linkAccount(
            deviceUUID: Self.deviceID, userID: Self.userID, provider: "apple", acceptsLicense: true
        )

        // The flow builds a new screen each time it reaches the add step; `load()` runs again.
        let second = Self.model(api: api, reader: reader)
        await second.load()
        second.stop()
        #expect(second.sharing == .sharing, "the second appearance did not see the sign-in")

        // And the same screen reads again too: `closeListedTree` calls `load()` when a listed
        // tree's profile closes, which is the one way back to this screen without rebuilding it.
        try await api.signOut()
        await second.load()
        second.stop()
        #expect(second.sharing == .signedOut, "a later appearance of the same screen kept the old state")
    }

    /// A signed-in account that declined is `.notSharing`, through the same read.
    @MainActor
    @Test("a signed-in account that declined reads as not sharing")
    func aDeclinedAccountIsNotSharing() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        try await api.linkAccount(
            deviceUUID: Self.deviceID, userID: Self.userID, provider: "apple", acceptsLicense: false
        )
        let subject = Self.model(api: api, reader: ContributionSharing.reader(local: api))
        await subject.load()
        subject.stop()
        #expect(subject.sharing == .notSharing)
    }

    // MARK: - Where the note sits

    /// The ruling "move into the scroll": the note is pinned under the button below the
    /// accessibility sizes, and is the last row of the scrolling form at them. The decision is a
    /// function of the one fact it reads, like the other AX5 rules (`AX5ReflowTests`); the UI test
    /// `AddTreeNearbyUITests.testTheNoteMovesIntoTheFormAtTheLargestTextSize` checks the running
    /// screen.
    ///
    /// Red-proof: return `.footer` for both in `VisitAddTreeLayout.footnotePlace` — red on the
    /// accessibility sizes.
    @Test("the note is pinned below the accessibility sizes and in the form at them")
    func theNoteMovesIntoTheScrollAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            let place = VisitAddTreeLayout.footnotePlace(isAccessibilitySize: size.isAccessibilitySize)
            #expect(
                place == (size.isAccessibilitySize ? .scroll : .footer),
                "at \(size) the note is in the \(place)"
            )
        }
    }

    // MARK: - The two empty places

    /// The owner's body for the map card, exactly. `MapEmptyInventoryTests` holds the facts it must
    /// carry and its AX5 budget.
    @Test("the map card's body is the owner's two sentences")
    func theMapCardNamesBothKinds() {
        #expect(
            MapInventoryCopy.message
                == "Cypress draws a city street-tree inventory and trees people have added. Neither has a tree here."
        )
        #expect(MapInventoryCopy.title == "No trees on record here")
    }

    /// The owner's sentence, with the number taken from the radius the list is read at.
    ///
    /// Red-proof: write `50` in place of `\(Int(VisitShortlist.searchRadiusM))` in
    /// `VisitIdentifyCopy.emptyMessage` — red on "the sentence does not state the list's radius".
    @Test("the empty list names both kinds and states its own radius")
    func theEmptyListNamesBothKinds() {
        let radius = Int(VisitShortlist.searchRadiusM)
        #expect(
            VisitIdentifyCopy.emptyMessage.contains("within \(radius) m of you"),
            "the sentence does not state the list's radius (\(radius) m): \(VisitIdentifyCopy.emptyMessage)"
        )
        // The owner approved the words at today's radius. If the radius changes, this fails, and
        // the owner sees the new number before a reader does.
        #expect(radius == 60, "the list's radius is \(radius) m; the owner approved the sentence at 60 m")
        #expect(
            VisitIdentifyCopy.emptyMessage
                == "No city tree and no added tree is within 60 m of you. "
                + "If there is a tree in front of you, it is not on the map yet."
        )
        #expect(VisitIdentifyCopy.emptyTitle == MapInventoryCopy.title)
    }

    /// **The two texts say "neither has a tree here", so an added tree must keep both away.** The
    /// map card fires on `MapContent.markerCount == 0`, and the list is empty when `treesNear`
    /// returns nothing. This puts one tree on ground with no city inventory, first this phone's
    /// own and then someone else's from the cache, and checks that both reads see it.
    ///
    /// Red-proof: return `Array(fromSeed.prefix(limit))` without the community half in
    /// `LocalAPI.treesNear` — red on "the list is empty with a tree … within 60 m". (Not this
    /// round's file; the proof is that this test would catch it.)
    @MainActor
    @Test("an added tree, this phone's or someone else's, keeps both empty texts away")
    func anAddedTreeKeepsBothEmptyTextsAway() async throws {
        for whose in ["this phone's", "someone else's"] {
            let store = try await CypressStore.inMemory()
            let api = LocalAPI(store: store, deviceID: Self.deviceID)
            let box = BoundingBox(around: Self.spot, radiusM: 100)

            // Nothing on record yet: both texts are owed.
            #expect(try await api.mapContent(in: MapViewport(bounds: box, zoom: 18)).markerCount == 0)
            #expect(try await Self.shortlist(api).state == .empty)

            if whose == "this phone's" {
                _ = try await api.addTree(
                    TreeDraft(
                        coordinate: Self.spot,
                        photoLocalPath: try VisitPhotoStaging.write(
                            Self.jpeg(), for: UUID(), shotType: .fullTree
                        ),
                        attribution: .anonymous(deviceID: Self.deviceID)
                    )
                )
            } else {
                try await CommunityRefresherTests.cache(
                    UUID(), at: Self.spot, tile: CommunityRefresherTests.tile.path, store
                )
            }

            let markers = try await api.mapContent(in: MapViewport(bounds: box, zoom: 18)).markerCount
            #expect(
                !MapInventoryNotice.isOwed(
                    hasSettled: true, isNarrowed: false, readFailed: false, markerCount: markers
                ),
                "the map card is owed over \(whose) added tree"
            )
            #expect(
                try await Self.shortlist(api).state != .empty,
                "the list is empty with a tree (\(whose)) within \(Int(VisitShortlist.searchRadiusM)) m"
            )
        }
    }

    // MARK: - Pictures, for a person to look at

    /// The add screen with each of the four notes at the drawn size, the add screen at AX5 (at a
    /// phone's height, where the button is pinned and the note is further down the form, and tall,
    /// where the note shows as the form's last row), the map card at both sizes, and the empty list.
    /// Runs only when `CYPRESS_SHOT_DIR` is set (`Tools/run_tests.sh`'s header has the one
    /// spelling that sets it); it judges each capture with `ShotBlankGuard` and asserts nothing
    /// about the layout.
    @MainActor
    @Test(
        "photographs of the four notes, AX5, the map card and the empty list",
        .enabled(if: ScreenSweepShots.shotDirectory != nil)
    )
    func photographs() async {
        let states: [(String, ContributionSharing)] = [
            ("sharing", .sharing), ("signed-out", .signedOut),
            ("not-sharing", .notSharing), ("unknown", .unknown),
        ]
        for (name, sharing) in states {
            #expect(await ScreenSweepShots.capture("c3b-add-\(name)", size: .large, scheme: .light) {
                VisitPreviewFixtures.addTree(sharing: sharing)
            } != nil)
        }
        #expect(await ScreenSweepShots.capture("c3b-add-ax5", size: .accessibility5, scheme: .light) {
            VisitPreviewFixtures.addTree()
        } != nil)
        #expect(await ScreenSweepShots.capture(
            "c3b-add-ax5-tall", size: .accessibility5, scheme: .light,
            viewportHeight: ScreenSweepShots.tallestViewport
        ) {
            VisitPreviewFixtures.addTree()
        } != nil)
        for (suffix, size) in [("default", DynamicTypeSize.large), ("ax5", .accessibility5)] {
            #expect(await ScreenSweepShots.capture("c3b-map-card-\(suffix)", size: size, scheme: .light) {
                VStack {
                    Spacer()
                    MapLocationNotice(title: MapInventoryCopy.title, message: MapInventoryCopy.message)
                }
            } != nil)
        }
        #expect(await ScreenSweepShots.capture(
            "c3b-identify-empty", size: .large, scheme: .light, settleFloor: RenderSettle.legacyBudget
        ) {
            VisitPreviewFixtures.identify(rows: [])
        } != nil)
    }

    // MARK: - Helpers

    @MainActor
    private static func model(api: LocalAPI, reader: @escaping ContributionSharingReader) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(spot, accuracyM: 5)),
            attribution: .anonymous(deviceID: deviceID),
            readSharing: reader
        )
    }

    /// The list screen 02 draws for a reader standing at `spot`, read the way `VisitIdentifyModel`
    /// reads it.
    private static func shortlist(_ api: LocalAPI) async throws -> VisitShortlist {
        let rows = try await api.treesNear(
            spot, radiusM: VisitShortlist.searchRadiusM, limit: VisitShortlist.maximumCandidates
        )
        return VisitShortlist.rank(rows, accuracyM: 5)
    }

    /// A real JPEG, because staging rewrites the container and refuses bytes that are not one.
    @MainActor
    private static func jpeg() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }
}
#endif
