import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// **The heart comes off where it went on** — C8's first cell, given the state RULINGS R2 rules it
/// must have (ERRATA E112, closing E101).
///
/// `FavoriteTests` proves the store: the tombstone, the replay guard, the two ownership arms, the
/// sign-in merge. None of that was ever in doubt here. What this suite holds is the half above it,
/// which is the half E101 recorded as missing — a control that can say "off", a screen that knows
/// which state it is in, and a state that comes from the store rather than from the last tap.
///
/// The five sentences, in the order a regression would break them:
///
/// 1. **The on-state is read, not remembered.** Opening a tree this device already holds draws the
///    selected cell, because the screen asks.
/// 2. **A second tap is a second statement.** It writes `false`, and it writes it under its own key.
/// 3. **A write that does not land is visible.** The cell goes back to where it was, which is the
///    state E101 said the screen did not have and therefore could not report an error in.
/// 4. **The label never changes, and the state is not carried by colour.** `Favorite` in both
///    states, an accent *and* a heavier border *and* a spoken value.
/// 5. **A memorial keeps the heart and loses the two cells that write.** E89's argument, which is
///    the whole reason the favourite is not gated on `acceptsNewContributions`.
@MainActor
@Suite("Screen 03 · the favourite toggle (R2)")
struct FavoriteToggleTests {

    // MARK: - Doubles and fixtures

    private static let treeID = UUID(uuidString: "F0000000-0000-4000-8000-0000000003A1")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000003A2")!

    private static func tree(status: TreeStatus = .alive) -> Tree {
        Tree(
            id: treeID,
            externalRef: "13284",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.799, longitude: -122.443),
            address: "2576 Lombard St",
            status: status,
            plantedYear: 1993,
            verificationState: .cityRecord,
            createdAt: Date(timeIntervalSince1970: 1_784_505_600),
            updatedAt: Date(timeIntervalSince1970: 1_784_505_600)
        )
    }

    /// A profile with one visit on it, so the screen is the **warm** variant — the quad row is drawn
    /// only there (SCREENS.md 14 drops it), which is where the heart lives.
    private static func profile(status: TreeStatus = .alive) -> TreeProfile {
        TreeProfile(
            tree: tree(status: status),
            visits: Series(complete: [
                Visit(
                    treeID: treeID,
                    attribution: Attribution.anonymous(deviceID: deviceID),
                    note: "Fog dripping off the crown",
                    capturedAt: Date(timeIntervalSince1970: 1_784_419_200)
                ),
            ])
        )
    }

    /// A store that answers `grove()` from a box the test can also write to, which is what makes
    /// "the cell shows what is stored" a testable sentence rather than a comment.
    private final class Favorites: @unchecked Sendable {
        var held: Set<UUID> = []
        /// Whether `grove()` can be read at all. A device whose store will not answer is a real
        /// state, and the cell has to draw *something* in it.
        var readFails = false
    }

    private struct Records: CypressAPI {
        var profile: TreeProfile
        let favorites: Favorites

        func treeProfile(id: UUID) async throws -> TreeProfile {
            guard id == profile.tree.id else { throw APIError.notFound }
            return profile
        }

        func grove() async throws -> [GroveEntry] {
            if favorites.readFails { throw APIError.serverError }
            return favorites.held.map { id in
                GroveEntry(
                    treeID: id,
                    displayName: "",
                    coordinate: profile.tree.coordinate,
                    lastVisitedAt: nil,
                    isFavorite: true
                )
            }
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    /// What the composition root's write did, recorded in order.
    private final class Writes: @unchecked Sendable {
        var states: [Bool] = []
    }

    /// A model wired the way `RootView` wires it, with the write pointed at the same box `grove()`
    /// reads — which is what a working store does, and what a broken one does not (`landing: false`).
    private static func model(
        _ api: Records,
        favorites: Favorites,
        writes: Writes,
        landing: Bool = true
    ) -> TreeProfileModel {
        TreeProfileModel(
            treeID: treeID,
            api: api,
            setFavorite: { treeID, isFavorite in
                writes.states.append(isFavorite)
                guard landing else { return }
                if isFavorite { favorites.held.insert(treeID) } else { favorites.held.remove(treeID) }
            }
        )
    }

    // MARK: - 1. The on-state is read, not remembered

    @Test("a tree the store already holds opens with the cell selected")
    func theStateIsReadOnLoad() async {
        let favorites = Favorites()
        favorites.held = [Self.treeID]
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: Writes()
        )

        await model.load()

        #expect(model.isFavorite, "the screen never asked the store whether this tree is a favourite")
        #expect(model.presentation != nil)
    }

    @Test("a tree the store does not hold opens idle")
    func theIdleStateIsAlsoRead() async {
        let favorites = Favorites()
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: Writes()
        )

        await model.load()
        #expect(!model.isFavorite)
    }

    @Test("a store that cannot be read draws the idle cell and still draws the profile")
    func anUnreadableStoreDoesNotTakeTheScreenDown() async {
        let favorites = Favorites()
        favorites.held = [Self.treeID]
        favorites.readFails = true
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: Writes()
        )

        await model.load()

        // "Not known to be yours" and "not yours" draw the same way, and the drawn way is the state
        // the cell has always had. What must not happen is the profile failing over a read that is
        // one cell's worth of the screen.
        #expect(!model.isFavorite)
        #expect(model.presentation != nil, "a failed favourite read took the whole profile down")
    }

    // MARK: - 2. A second tap is a second statement

    @Test("the second tap writes false, which is the write that could not be made")
    func aSecondTapTakesTheHeartOff() async {
        let favorites = Favorites()
        let writes = Writes()
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: writes
        )
        await model.load()

        await model.toggleFavorite().value
        #expect(model.isFavorite)
        #expect(writes.states == [true])
        #expect(favorites.held == [Self.treeID])

        await model.toggleFavorite().value
        #expect(!model.isFavorite, "the heart could be put on and not taken off")
        #expect(writes.states == [true, false])
        #expect(favorites.held.isEmpty)
    }

    @Test("two taps in the same run land in the order they were made")
    func tapsAreSerialized() async {
        let favorites = Favorites()
        let writes = Writes()
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: writes
        )
        await model.load()

        // Both taps before either write has been awaited — an impatient double tap, which is the
        // exact gesture E101's replayed client uuid existed to absorb.
        let first = model.toggleFavorite()
        let second = model.toggleFavorite()
        await first.value
        await second.value

        #expect(writes.states == [true, false], "the two taps raced: \(writes.states)")
        #expect(!model.isFavorite)
        #expect(favorites.held.isEmpty)
    }

    // MARK: - 3. A write that does not land is visible

    @Test("a write the store refuses puts the cell back where it was")
    func aFailedWriteReverts() async {
        let favorites = Favorites()
        let writes = Writes()
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: writes,
            landing: false
        )
        await model.load()

        await model.toggleFavorite().value

        // The tap was made and the write was attempted; nothing was stored, so nothing on screen may
        // claim otherwise. This is the state E101 said did not exist, which is why it dropped the
        // error.
        #expect(writes.states == [true])
        #expect(!model.isFavorite, "the cell claimed a favourite the store does not hold")
    }

    @Test("taking the heart off, when that write does not land, leaves it on")
    func aFailedRemovalReverts() async {
        let favorites = Favorites()
        favorites.held = [Self.treeID]
        let model = Self.model(
            Records(profile: Self.profile(), favorites: favorites),
            favorites: favorites,
            writes: Writes(),
            landing: false
        )
        await model.load()
        #expect(model.isFavorite)

        await model.toggleFavorite().value
        #expect(model.isFavorite, "the cell showed an un-favourite the store never took")
    }

    // MARK: - 4. What the cell says, and how it says it

    @Test("the label does not change, so the state rides on the spoken value instead")
    func theLabelIsFixedAndTheStateIsSpoken() {
        // R2, verbatim: the label is a noun naming the thing rather than a verb naming the next tap.
        // `Unfavorite` appearing under the same cell is how a control starts lying about what it is.
        #expect(QuadActionRow.Action.favorite.label == "Favorite")
        #expect(QuadActionRow.Action.allCases.map(\.label) == ["Favorite", "Care", "Share", "Report"])

        // Which is exactly why the state has to be somewhere else. A listener given only the label
        // is given the same string twice.
        #expect(QuadActionRow.spokenValue(for: .favorite, isSelected: true) == "On")
        #expect(QuadActionRow.spokenValue(for: .favorite, isSelected: false) == "Off")

        // Off is announced too. A VoiceOver user who hears only "Favorite, button" has been told
        // nothing about whether this tree is already one of theirs — which is the same failure as a
        // sighted user looking at two cells drawn identically.
        #expect(QuadActionRow.spokenValue(for: .favorite, isSelected: false) != nil)

        // And the three that open something have no state to announce.
        for action in [QuadActionRow.Action.care, .share, .report] {
            #expect(!action.hasOnState)
            #expect(QuadActionRow.spokenValue(for: action, isSelected: true) == nil)
        }
    }

    @Test("the selected cell differs in more than colour")
    func theSelectedAppearanceIsNotOnlyAHue() {
        let on = QuadActionRow.appearance(isSelected: true)
        let off = QuadActionRow.appearance(isSelected: false)

        #expect(on != off)
        // The colour channels. Since task #153 the selected cell takes the selected filter chip's
        // own pair — the accent fill under the accent's label colour — because E112's tinted
        // surface read as no state at all on a phone in daylight. The facts asserted: the two
        // fills differ, the two labels differ, and the selected pair is the accent pair.
        #expect(on.label == CypressColor.ctaLabel)
        #expect(on.fill == CypressColor.ctaFill)
        #expect(off.fill == CypressColor.surfaceCard)
        #expect(off.label == CypressColor.textBody)
        #expect(on.fill != off.fill)
        #expect(on.label != off.label)
        // The two that survive greyscale. ERRATA E103 is this app's record of a state that reached
        // nobody, and a toggle whose on-state is a hue fails the same way for anyone who cannot see
        // the hue.
        #expect(on.borderWidth > off.borderWidth)
        #expect(on.font != off.font)
    }

    @Test("the selected label is legible on the selected fill, in both appearances")
    func theSelectedPairClearsAA() {
        // Measured off what the component draws rather than off the tokens this test remembers it
        // drawing — a pair swapped in `appearance` has to come through here.
        let selected = QuadActionRow.appearance(isSelected: true)
        let pair = ContrastTests.Pair(
            what: "C8 selected cell label on its fill (03, R2)",
            foreground: selected.label,
            background: selected.fill,
            floor: 4.5
        )
        for traits in [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(userInterfaceStyle: .dark),
        ] {
            let ratio = ContrastTests.ratio(pair, traits)
            #expect(ratio >= pair.floor, "\(pair.what) reads \(ratio) at \(traits.userInterfaceStyle.rawValue)")
        }
    }

    // MARK: - 5. What a memorial keeps

    @Test("a record that takes no contribution keeps the heart and offers no write at all")
    func aMemorialKeepsTheHeartAndNothingElse() {
        let live = TreeProfilePresentation(profile: Self.profile())
        #expect(live.quadActions == QuadActionRow.Action.allCases)

        let memorial = TreeProfilePresentation(profile: Self.profile(status: .removed))
        // The argument is E89's and R2 restates it: gating the favourite would make the toggle
        // one-way for anyone whose favourite tree is later removed, because the gate that refuses
        // the heart also refuses taking it off.
        #expect(memorial.quadActions.contains(.favorite))
        #expect(memorial.quadActions.contains(.share))
        // `Care` writes a care event and `Report` asks for a hazard category about a standing tree.
        // These two cells were the last controls on this screen offering a write to a record that
        // cannot take one.
        #expect(!memorial.quadActions.contains(.care))
        #expect(!memorial.quadActions.contains(.report))

        // The rest of the screen was already withholding, and stays that way: the visit CTA and the
        // check-in button are gated on `acceptsContributions`, and the empty measurement slot — the
        // door to screen 16 — is not offered either.
        #expect(!memorial.acceptsContributions)
        #expect(!memorial.offersCheckIn)
        #expect(!memorial.stats.contains { $0.destination?.isMeasure == true })
    }

    // MARK: - The composition root's write

    /// **One tap, one key.** The trick E101 recorded as deliberate, retired.
    ///
    /// This drives `ProfileFavoriteWriter` — the exact call `RootView` makes — against a real store
    /// and a real outbox, twice, with the two states screen 03 now produces. Against the old
    /// composition root it cannot pass in two separate ways: that code wrote `isFavorite: true` and
    /// never `false`, and it replayed one client uuid per tree, which `applyFavoriteToggle`'s
    /// `WHERE client_uuid <> excluded.client_uuid` guard turns into a no-op.
    @Test("each tap of the heart is its own statement, under its own key")
    func eachTapGetsItsOwnKey() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-favorite-toggle-test.jpg",
                attribution: Attribution.anonymous(deviceID: Self.deviceID)
            )
        )
        let write = ProfileFavoriteWriter(api: api, outbox: outbox)

        await write(treeID: tree.id, isFavorite: true)
        #expect(try await api.grove().first { $0.treeID == tree.id }?.isFavorite == true)

        await write(treeID: tree.id, isFavorite: false)

        // The store took the second statement: the row is tombstoned rather than live, and the grove
        // no longer lists it.
        #expect(try await api.grove().isEmpty, "the un-favourite was swallowed as a replay")
        #expect(try await api.deviceContributions().favorites == 0)

        // Two outbox rows, two keys. One key would have been one row — durable, correct, and the
        // wrong statement.
        let records = try await outbox.records().filter { $0.item.kind == .favoriteToggle }
        #expect(records.count == 2)
        #expect(Set(records.map(\.item.clientUUID)).count == 2)
        #expect(records.allSatisfy { $0.item.state == .done })
    }
}
