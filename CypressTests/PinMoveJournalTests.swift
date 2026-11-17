import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// A pin move in the Journal: "Moved the pin of Grandmother Cypress" (the app owner's decision of
/// 2026-11-14), with the community tree mark in its square (the decision of 2026-11-15).
///
/// The row comes from `ContributionStore.journalSQL`'s fifth arm, over `tree_locations`. The
/// sentences this suite makes true:
///
/// 1. a move by this phone's person is a row, with the tree, the moment of the move, and the
///    owner's title;
/// 2. the root row (where the tree was first put) is not a move and is not a row;
/// 3. a move by another device on the same phone is not this person's row;
/// 4. a move on a withdrawn tree is not a row, because the row opens a profile that no longer opens;
/// 5. pages across a pin move and a visit that share one moment lose and repeat nothing;
/// 6. the row's square is the community tree mark, and no other row's square changed;
/// 7. a move made on this phone stays in the Journal and the export after sign-out, signed in or
///    not when it was made, as the visits beside it do (the owner's decision of 2026-11-16); and a
///    keep-records account deletion takes the account's moves off this phone's Journal.
@Suite("Journal · a pin move")
struct PinMoveJournalTests {

    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3C01")!
    static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3C02")!

    /// West of Ocean Beach, where the street-tree inventory has nothing (`LocationCorrectionTests`).
    static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    /// Whole seconds, so the stored millisecond timestamp reads back as the same `Date`.
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func capture() -> String {
        let path = NSTemporaryDirectory() + "cypress-c3-journal-\(UUID().uuidString).jpg"
        FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        return path
    }

    static func add(_ api: LocalAPI, device: UUID, at coordinate: Coordinate) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: coordinate,
                photoLocalPath: capture(),
                attribution: .anonymous(deviceID: device)
            )
        )
    }

    static func move(_ api: LocalAPI, _ tree: Tree, meters: Double) async throws {
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: ProximityDedupeTests.diagonal(from: tree.coordinate, meters: meters),
            placement: .contributorPlaced,
            locationAccuracyM: 5
        )
    }

    static func visit(
        _ store: CypressStore,
        _ tree: Tree,
        device: UUID,
        at moment: Date,
        id: UUID = UUID()
    ) async throws {
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(id: id, treeID: tree.id, attribution: .anonymous(deviceID: device), capturedAt: moment),
                connection: connection
            )
        }
    }

    static func wholeJournal(_ api: LocalAPI, limit: Int = 25) async throws -> [JournalEntry] {
        var entries: [JournalEntry] = []
        var cursor: String?
        repeat {
            let page = try await api.journal(cursor: cursor, limit: limit)
            entries += page.items
            cursor = page.nextCursor
        } while cursor != nil
        return entries
    }

    // MARK: - 1. The row

    /// Red-proof: delete the fifth arm's `UNION ALL` from `journalSQL`, and this goes red on "the
    /// journal holds no pin move".
    @Test("a move by this phone is a row with its tree, its moment, and the owner's title")
    func aMoveIsARow() async throws {
        let store = try await CypressStore.inMemory()
        let clock = OutboxTestSupport.Clock(Self.start)
        let api = LocalAPI(store: store, deviceID: Self.deviceID, now: clock.closure)
        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        clock.advance(by: 3_600)
        let movedAt = clock.now
        try await Self.move(api, tree, meters: 30)

        let entries = try await Self.wholeJournal(api)
        let moves = entries.filter { $0.kind == .pinMoved }
        #expect(moves.count == 1, "the journal holds \(moves.count) pin moves, not 1: \(entries)")
        let move = try #require(moves.first, "the journal holds no pin move")
        #expect(move.treeID == tree.id)
        #expect(move.capturedAt == movedAt, "the row is dated \(move.capturedAt), not the move's \(movedAt)")
        #expect(move.summary == "", "a pin move carries no second line, but read \(move.summary)")
        // The chain row's own id, never the tree's: that one belongs to the root.
        #expect(move.id != tree.id)

        let row = try #require(JournalPresentation(entries: [move], nextCursor: nil).rows.first)
        // The tree was added with no species and no name: the app owner's words of 2026-11-16.
        #expect(move.treeDisplayName == "", "fixture: the added tree has a name: \(move.treeDisplayName)")
        #expect(row.title == "Moved a tree’s pin", "the row reads \(row.title)")
        #expect(row.subtitle == "")
        #expect(row.treeID == tree.id)
    }

    @Test("the title is the owner's words, verb first")
    func theTitleIsTheOwnersWords() {
        #expect(JournalCopy.verb(for: .pinMoved) == "Moved the pin of")
        #expect(
            JournalCopy.rowTitle(kind: .pinMoved, treeName: "Grandmother Cypress")
                == "Moved the pin of Grandmother Cypress"
        )
    }

    /// **End to end: a pin move on an added tree that has a species**, read back through the Journal
    /// and the Outbox (the owner's answer of 2026-11-16, "Use the species"). The tree is added
    /// with the seed's first `Platanus` match, as the `movePin` debug screen adds it, and moved
    /// through `correctLocation`. The Journal row comes from `journal()`, and the Outbox row from
    /// the queue's own records named through `displayNames(for:)`, the resolver `DataLayer` hands
    /// `OutboxViewState`. Red-proof: in `LocalAPI.resolvedDisplayNames`, make the community arm
    /// return early — red on "the Journal row read Moved a tree’s pin".
    @Test("a pin move on an added tree with a species names the species in the Journal and the Outbox")
    func aPinMoveOnATreeWithASpeciesNamesIt() async throws {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let clock = OutboxTestSupport.Clock(Self.start)
        let api = LocalAPI(store: store, deviceID: Self.deviceID, now: clock.closure)
        let species = try #require(
            try await api.searchSpecies(query: "Platanus", limit: 1).first,
            "the seed has no Platanus species"
        )
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Self.offshore,
                speciesID: species.id,
                photoLocalPath: Self.capture(),
                attribution: .anonymous(deviceID: Self.deviceID)
            )
        )
        clock.advance(by: 3_600)
        try await Self.move(api, tree, meters: 30)

        let move = try #require(
            try await Self.wholeJournal(api).first { $0.kind == .pinMoved },
            "the journal holds no pin move"
        )
        let journalRow = try #require(JournalPresentation(entries: [move], nextCursor: nil).rows.first)
        #expect(
            journalRow.title == "Moved the pin of \(species.commonName)",
            "the Journal row read \(journalRow.title)"
        )

        let records = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        let names = await api.displayNames(for: [tree.id])
        let snapshot = OutboxSnapshot(
            records: records, treeNames: names, now: clock.now, syncPhotosOnWifiOnly: true
        )
        let titles = OutboxPresentation(snapshot: snapshot, now: clock.now).queue.map(\.title)
        #expect(
            titles.contains("Pin moved · \(species.commonName)"),
            "the Outbox rows read \(titles)"
        )
        #expect(
            titles.contains("New tree · \(species.commonName)"),
            "the Outbox rows read \(titles)"
        )
    }

    /// The app owner's words of 2026-11-16 for a tree with no name, over "Moved the pin of Tree".
    /// Only the pin move changes: every other kind keeps the fallback title. Red-proof: drop the
    /// `.pinMoved` early return from `JournalCopy.rowTitle` — red on "an unnamed tree's pin move
    /// reads Moved the pin of Tree".
    @Test("a pin move on a tree with no name reads \"Moved a tree’s pin\"; a named tree and other kinds are unchanged")
    func anUnnamedTreesPinMoveReadsMovedATreesPin() {
        let unnamed = JournalCopy.rowTitle(kind: .pinMoved, treeName: nil)
        #expect(unnamed == "Moved a tree’s pin", "an unnamed tree's pin move reads \(unnamed)")
        #expect(JournalCopy.rowTitle(kind: .pinMoved, treeName: "London plane")
                == "Moved the pin of London plane")
        #expect(JournalCopy.rowTitle(kind: .visit, treeName: nil)
                == "Visited \(TreeProfilePresentation.fallbackTitle)")
    }

    // MARK: - 2-4. What is not a row

    /// Red-proof: drop `id <> tree_id COLLATE NOCASE` from the fifth arm, and this goes red on the
    /// root row read as a move.
    @Test("the root row records the add, and is not a move")
    func theRootIsNotAMove() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)

        let moves = try await Self.wholeJournal(api).filter { $0.kind == .pinMoved }
        #expect(
            moves.isEmpty,
            "a tree with no move reads as \(moves.count) pin moves; ids \(moves.map(\.id)), tree \(tree.id)"
        )
    }

    /// Red-proof: drop the owner predicate from the fifth arm, and this goes red on the other
    /// device's move.
    @Test("another device's move on this phone is not this person's row")
    func anotherDevicesMoveIsNotARow() async throws {
        let store = try await CypressStore.inMemory()
        let mine = LocalAPI(store: store, deviceID: Self.deviceID)
        let theirs = LocalAPI(store: store, deviceID: Self.otherDeviceID)

        let myTree = try await Self.add(mine, device: Self.deviceID, at: Self.offshore)
        let theirTree = try await Self.add(
            theirs,
            device: Self.otherDeviceID,
            at: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 200)
        )
        try await Self.move(mine, myTree, meters: 30)
        try await Self.move(theirs, theirTree, meters: 30)

        let myMoves = try await Self.wholeJournal(mine).filter { $0.kind == .pinMoved }
        #expect(myMoves.map(\.treeID) == [myTree.id], "this person's journal reads moves on \(myMoves.map(\.treeID))")
        let theirMoves = try await Self.wholeJournal(theirs).filter { $0.kind == .pinMoved }
        #expect(theirMoves.map(\.treeID) == [theirTree.id])
    }

    /// Red-proof: drop the `withdrawn` clause from the fifth arm, and this goes red on the move
    /// that is still read.
    @Test("a move on a withdrawn tree is not a row")
    func aWithdrawnTreesMoveIsNotARow() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let kept = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        let withdrawn = try await Self.add(
            api,
            device: Self.deviceID,
            at: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 200)
        )
        try await Self.move(api, kept, meters: 30)
        try await Self.move(api, withdrawn, meters: 30)

        let before = try await Self.wholeJournal(api).filter { $0.kind == .pinMoved }
        #expect(Set(before.map(\.treeID)) == [kept.id, withdrawn.id], "both moves read before the withdrawal")

        let didWithdraw = try await store.queue.write { connection in
            try CommunityTreeStore().withdraw(treeID: withdrawn.id, at: Self.start, connection: connection)
        }
        #expect(didWithdraw)

        let after = try await Self.wholeJournal(api).filter { $0.kind == .pinMoved }
        #expect(
            after.map(\.treeID) == [kept.id],
            "after the withdrawal the journal reads moves on \(after.map(\.treeID)), not only \(kept.id)"
        )
    }

    // MARK: - 5. Paging

    /// The highest id a `UUID` can have, so this visit sorts above every move at its moment. With
    /// `lowestID` below every move, the two moves' random ids fall between two fixed ids, and the
    /// order of the tie no longer depends on chance.
    static let highestID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!
    static let lowestID = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!

    /// Two pin moves and two visits at one moment, and an older visit, read at page sizes 1, 2, 3,
    /// 4, 5 and 7. Every paged read must equal the whole read: the cursor is `(captured_at, id)`,
    /// and the fifth arm takes it as the other four do.
    ///
    /// One tied visit has the highest possible id and the other the lowest, so the two moves sit
    /// between them in every run. A page that ends on the high visit leaves both moves after the
    /// cursor at the same moment, which is the case the id half of the cursor exists for.
    ///
    /// Red-proof: make the fifth arm compare `occurred_at` alone (`occurred_at < COALESCE(:cursorAt,
    /// …)`), and this goes red on every run, on the moves the tie loses.
    @Test("pages across pin moves and visits that share one moment lose and repeat nothing")
    func pagesAcrossATie() async throws {
        let store = try await CypressStore.inMemory()
        let clock = OutboxTestSupport.Clock(Self.start)
        let api = LocalAPI(store: store, deviceID: Self.deviceID, now: clock.closure)
        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        clock.advance(by: 60)
        let moment = clock.now
        try await Self.move(api, tree, meters: 30)
        try await Self.move(api, tree, meters: 60)
        try await Self.visit(store, tree, device: Self.deviceID, at: moment, id: Self.highestID)
        try await Self.visit(store, tree, device: Self.deviceID, at: moment, id: Self.lowestID)
        try await Self.visit(store, tree, device: Self.deviceID, at: moment.addingTimeInterval(-60))

        let all = try await Self.wholeJournal(api, limit: 25)
        #expect(all.count == 5, "the whole journal holds \(all.count) rows, not two moves and three visits")
        #expect(all.filter { $0.kind == .pinMoved }.count == 2)
        #expect(all.filter { $0.capturedAt == moment }.count == 4, "the whole read lost a row of the tie")
        #expect(all.first?.id == Self.highestID, "the tie is not ordered by id: \(all.map(\.kind))")

        for limit in [1, 2, 3, 4, 5, 7] {
            let paged = try await Self.wholeJournal(api, limit: limit)
            #expect(
                paged.map(\.id) == all.map(\.id),
                "at \(limit) a page the read is \(paged.map(\.kind)), the whole read \(all.map(\.kind))"
            )
        }
    }

    // MARK: - 7. Sign-in and sign-out (the owner's decision of 2026-11-16, ROADMAP chip 152)

    static let accountID = UUID(uuidString: "0E000000-0000-4000-8000-0000000C3C03")!

    /// A visit written as `apply` writes one, under the attribution the phone has right now.
    static func visit(_ store: CypressStore, _ tree: Tree, as attribution: Attribution, at moment: Date) async throws {
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: tree.id, attribution: attribution, capturedAt: moment),
                connection: connection
            )
        }
    }

    /// The reviewer's probe. Signed out: add a tree, move it, visit it. Signed in: move it and
    /// visit it again. Then sign out. The Journal holds both moves and both visits.
    ///
    /// On main this read 0 moves: sign-in gives both moves to the account and clears their
    /// `device_id`, while the visits keep theirs.
    static func signInAndOut() async throws -> (LocalAPI, Tree) {
        let store = try await CypressStore.inMemory()
        let clock = OutboxTestSupport.Clock(Self.start)
        let api = LocalAPI(store: store, deviceID: Self.deviceID, now: clock.closure)

        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        clock.advance(by: 60)
        try await Self.move(api, tree, meters: 30)
        clock.advance(by: 60)
        let anonymous = await api.attribution
        #expect(anonymous.userID == nil, "fixture: the phone starts signed in")
        try await Self.visit(store, tree, as: anonymous, at: clock.now)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountID)
        clock.advance(by: 60)
        try await Self.move(api, tree, meters: 60)
        clock.advance(by: 60)
        let signedIn = await api.attribution
        #expect(signedIn.userID == Self.accountID, "fixture: the phone is not signed in")
        try await Self.visit(store, tree, as: signedIn, at: clock.now)

        try await api.signOut()
        let signedOut = await api.attribution
        #expect(signedOut.userID == nil, "fixture: the phone is still signed in")
        return (api, tree)
    }

    /// Red-proof: remove `OR set_on_device = :device COLLATE NOCASE` from the fifth arm, and this
    /// goes red on "the signed-out journal holds 0 pin moves".
    @Test("after sign-out the Journal still holds the moves and visits made on this phone, signed in or not")
    func signOutKeepsThePinMoves() async throws {
        let (api, tree) = try await Self.signInAndOut()
        let entries = try await Self.wholeJournal(api)
        let moves = entries.filter { $0.kind == .pinMoved }
        let visits = entries.filter { $0.kind == .visit }
        #expect(moves.count == 2, "the signed-out journal holds \(moves.count) pin moves, not 2: \(entries.map(\.kind))")
        #expect(visits.count == 2, "the signed-out journal holds \(visits.count) visits, not 2")
        #expect(Set(moves.map(\.treeID)) == [tree.id])
    }

    /// Red-proof: the same break as above; this goes red on the export's pin-move rows.
    @Test("after sign-out the export still holds both pin moves")
    func signOutKeepsThePinMovesInTheExport() async throws {
        let (api, tree) = try await Self.signInAndOut()
        let csv = String(decoding: try await api.exportLatest(.csv), as: UTF8.self)
        let lines = csv.split(separator: "\n").map(String.init)
        let moves = lines.filter { $0.hasPrefix("pinMoved,") }
        #expect(moves.count == 2, "the export holds \(moves.count) pinMoved rows, not 2:\n\(csv)")
        #expect(moves.allSatisfy { $0.contains(tree.id.uuidString) })
        #expect(lines.filter { $0.hasPrefix("visit,") }.count == 2, "the export lost a visit:\n\(csv)")
    }

    /// Red-proofs: drop `setOnDevice: mine.deviceID` from `LocalAPI.correctLocation` — red on the
    /// move's provenance; drop `setOnDevice: attribution.deviceID` from `LocalAPI.addTree` — red on
    /// the root's.
    @Test("a move made signed in is the account's, and records this phone as where it was set")
    func aSignedInMoveRecordsThisPhone() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountID)
        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        try await Self.move(api, tree, meters: 30)

        let chain = try await store.queue.read {
            try TreeLocationStore().chain(treeID: tree.id, connection: $0)
        }
        #expect(chain.count == 2, "fixture: the chain holds \(chain.count) positions")
        let root = try #require(chain.first)
        let move = try #require(chain.last)
        #expect(root.isRoot && !move.isRoot)
        #expect(move.owner == .user(Self.accountID), "the move's owner is \(move.owner)")
        #expect(move.movedByDevice == nil, "the move holds two owners")
        #expect(move.setOnDevice == Self.deviceID, "the move records \(String(describing: move.setOnDevice)) as where it was set")
        #expect(root.owner == .user(Self.accountID), "the root's owner is \(root.owner)")
        #expect(root.setOnDevice == Self.deviceID, "the root records \(String(describing: root.setOnDevice)) as where it was set")
    }

    /// Red-proof: drop `set_on_device = NULL` from the keep-records door's `tree_locations`
    /// statement in `AccountDeletion.forgetCommunityTrees`, and this goes red on the deleted
    /// account's moves, which read back in the signed-out Journal.
    @Test("after the keep-records deletion, the deleted account's moves leave the Journal and lose this phone")
    func theKeepRecordsDeletionTakesTheMovesOffThisPhone() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(api, device: Self.deviceID, at: Self.offshore)
        try await Self.move(api, tree, meters: 30)
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountID)
        try await Self.move(api, tree, meters: 60)
        let before = try await Self.wholeJournal(api).filter { $0.kind == .pinMoved }
        #expect(before.count == 2, "fixture: the signed-in journal holds \(before.count) moves")

        _ = try await api.deleteAccount(.leaveRecords)
        let signedOut = await api.attribution
        #expect(signedOut.userID == nil, "fixture: the phone is still signed in after the deletion")

        let after = try await Self.wholeJournal(api).filter { $0.kind == .pinMoved }
        #expect(after.isEmpty, "the deleted account's \(after.count) moves are still in this phone's journal")
        let chain = try await store.queue.read {
            try TreeLocationStore().chain(treeID: tree.id, connection: $0)
        }
        #expect(chain.count == 3, "the keep-records door removed positions: \(chain.count) left")
        for row in chain {
            #expect(row.owner == .nobody, "a position still has the owner \(row.owner)")
            #expect(row.setOnDevice == nil, "a position still records \(String(describing: row.setOnDevice))")
        }
    }

    // MARK: - 6. The square

    /// Red-proof: return `false` from `JournalCopy.drawsCommunityTreeMark`, and this goes red on the
    /// pin-move row.
    @Test("a pin-move row draws the community tree mark, and no other kind does")
    func onlyAPinMoveDrawsTheMark() {
        let kinds: [JournalEntry.Kind] = [.visit, .observation, .measurement, .careEvent, .pinMoved]
        let rows = JournalPresentation(
            entries: kinds.enumerated().map { index, kind in
                JournalEntry(
                    id: UUID(),
                    kind: kind,
                    treeID: UUID(),
                    treeDisplayName: "Grandmother Cypress",
                    capturedAt: Self.start.addingTimeInterval(TimeInterval(-index)),
                    summary: "",
                    heroPhotoID: UUID()
                )
            },
            nextCursor: nil
        ).rows

        for (kind, row) in zip(kinds, rows) {
            #expect(row.drawsCommunityTreeMark == (kind == .pinMoved), "the \(kind) row's square is wrong")
        }
        // A pin-move row whose tree has a photograph still draws the mark, not the photograph.
        let pinMove = rows[4]
        #expect(
            IconTextRow.tileDrawing(
                accent: pinMove.accent,
                photoID: pinMove.heroPhotoID,
                drawsCommunityTreeMark: pinMove.drawsCommunityTreeMark
            ) == .communityTreeMark
        )
    }

    /// Every row that does not ask for the mark draws what it drew before the mark existed: the
    /// empty well for a vacant site, else the photograph, else the accent.
    ///
    /// Red-proof: move the `drawsCommunityTreeMark` check below the photograph's in
    /// `IconTextRow.tileDrawing`, and the first assertion goes red.
    @Test("the mark changes no other row's square")
    func theMarkChangesNoOtherSquare() {
        let photo = UUID()
        #expect(
            IconTextRow.tileDrawing(accent: .elder, photoID: photo, drawsCommunityTreeMark: true)
                == .communityTreeMark
        )
        for accent in CypressColor.TileAccent.allCases {
            let withPhoto = IconTextRow.tileDrawing(accent: accent, photoID: photo, drawsCommunityTreeMark: false)
            let without = IconTextRow.tileDrawing(accent: accent, photoID: nil, drawsCommunityTreeMark: false)
            if accent == .vacantSite {
                #expect(withPhoto == .emptyWell)
                #expect(without == .emptyWell)
            } else {
                #expect(withPhoto == .photo(photo), "the \(accent.rawValue) row with a photograph draws \(withPhoto)")
                #expect(without == .accent, "the \(accent.rawValue) row draws \(without)")
            }
        }
    }
}

#if DEBUG
/// The pin-move rows, photographed: the Journal with a pin-move row between a visit and a care row,
/// and the Outbox with a queued move, a refused move, and a visit. Light and dark, at the default
/// size and the largest accessibility size. The images are the output; the test asserts only that
/// each capture produced pixels (`ScreenSweepShots`' rule). Set `TEST_RUNNER_CYPRESS_SHOT_DIR` to
/// keep the PNGs.
@MainActor
@Suite("Journal and Outbox · a pin move, photographed")
struct PinMoveShots {

    static let treeID = UUID(uuidString: "C3C00000-0000-4000-8000-000000000F01")!

    static func entry(_ index: Int, _ kind: JournalEntry.Kind, _ summary: String) -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: String(format: "C3C00000-0000-4000-8000-%012d", index))!,
            kind: kind,
            treeID: treeID,
            treeDisplayName: "Grandmother Cypress",
            capturedAt: PinMoveJournalTests.start.addingTimeInterval(TimeInterval(-index * 60)),
            summary: summary
        )
    }

    @Test("the Journal draws the pin-move row between a visit and a care row")
    func theJournal() async {
        let entries = [
            Self.entry(1, .visit, "Fog on the crown"),
            Self.entry(2, .pinMoved, ""),
            Self.entry(3, .careEvent, "watering, weeding")
        ]
        for variant in ScreenSweepShots.variants {
            let image = await ScreenSweepShots.capture(
                "c3-journal-pin-move-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                viewportHeight: 900
            ) {
                ScrollView {
                    JournalListView(
                        presentation: JournalPresentation(
                            entries: entries,
                            nextCursor: nil,
                            now: PinMoveJournalTests.start
                        ),
                        onOpenTree: { _ in }
                    )
                }
            }
            #expect(image != nil, "the \(variant.suffix) Journal photographed as a blank image")
        }
    }

    @Test("the Outbox draws a queued pin move and a refused one beside a visit")
    func theOutbox() async throws {
        let clock = OutboxTestSupport.Clock(PinMoveJournalTests.start)
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .allFail(.forbidden))
        let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)
        let attribution = Attribution.anonymous(deviceID: PinMoveJournalTests.deviceID)

        func move() -> OutboxPayload {
            .locationCorrection(TreeLocationCorrection(
                id: UUID(),
                clientUUID: UUID(),
                treeID: Self.treeID,
                coordinate: PinMoveJournalTests.offshore,
                placement: .contributorPlaced,
                locationAccuracyM: 5,
                attribution: attribution,
                occurredAt: clock.now
            ))
        }
        // The first move is refused; the visit and the second move wait behind a dead connection.
        _ = try await queue.enqueue(move())
        _ = try await queue.drain()
        await transport.setScript(.connectionDropped)
        clock.advance(by: 60)
        _ = try await queue.enqueue(.visit(Visit(treeID: Self.treeID, attribution: attribution, capturedAt: clock.now)))
        clock.advance(by: 60)
        _ = try await queue.enqueue(move())

        let snapshot = try await queue.snapshot(
            treeNames: [Self.treeID: "Grandmother Cypress"],
            syncPhotosOnWifiOnly: true
        )
        let presentation = OutboxPresentation(snapshot: snapshot, now: clock.now)
        #expect(presentation.queue.map(\.title).filter { $0 == "Pin moved · Grandmother Cypress" }.count == 2)

        for variant in ScreenSweepShots.variants {
            let image = await ScreenSweepShots.capture(
                "c3-outbox-pin-move-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                viewportHeight: 1_100
            ) {
                NavigationStack {
                    OutboxScreen(presentation: presentation, syncPhotosOnWifiOnly: .constant(true))
                }
                .environment(AppRouter())
            }
            #expect(image != nil, "the \(variant.suffix) Outbox photographed as a blank image")
        }
    }
}
#endif
