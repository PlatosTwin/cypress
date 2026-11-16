//
//  OthersTreeControlsTests.swift
//  CypressTests
//
//  Round C3: the profile of a community tree somebody else added. The owner's answers: the same
//  controls as a city tree (visit, check-in, care, favorite, share, measure), Move pin never, and
//  in this build neither species control ("Hide species controls for now", 2026-11-15). The
//  reader's own tree keeps both species controls.
//
//  Also the DEBUG seam that puts such a tree into the community cache, which the UI tests use.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("Other people's community trees on the profile")
struct OthersTreeControlsTests {

    static let readerDevice = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3A01")!
    static let otherDevice = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3A02")!
    /// At sea, west of Ocean Beach, where the street inventory has no rows.
    static let spot = Coordinate(latitude: 37.7600, longitude: -122.5400)

    static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    static func plane(_ api: LocalAPI) async throws -> Species {
        try #require(await api.searchSpecies(query: "Platanus", limit: 1).first, "the catalog answered no Platanus")
    }

    /// A tree somebody else added, as a tile page would store it.
    static func cached(_ api: LocalAPI, species: UUID?, at coordinate: Coordinate = spot) async throws -> UUID {
        let id = UUID()
        try await api.debugSeedCommunityCache(
            Tree(id: id, source: .community, coordinate: coordinate, speciesCurrentID: species)
        )
        return id
    }

    static func add(_ api: LocalAPI, device: UUID, at coordinate: Coordinate, species: UUID? = nil) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: coordinate,
            speciesID: species,
            photoLocalPath: LocationCorrectionTests.capture("others-tree"),
            attribution: .anonymous(deviceID: device)
        ))
    }

    // MARK: - A cached tree

    /// A tree from the cache with a species: the city tree's controls, no Move pin, no species
    /// control, and the "Added" row.
    ///
    /// Red-proof: make `canMovePin` true in `LocalAPI.treeProfile` for any community row — red on
    /// "Move pin is offered".
    @Test("somebody else's named tree: the city tree's controls, no Move pin, no species control")
    func namedCachedTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let id = try await Self.cached(api, species: try await Self.plane(api).id)

        let profile = try await api.treeProfile(id: id)
        let presentation = TreeProfilePresentation(profile: profile)
        #expect(profile.species != nil, "calibration: the cached species resolved")
        #expect(!profile.isAddedHere)
        #expect(!profile.addedByYou)
        #expect(!presentation.offersMovePin, "Move pin is offered")
        #expect(presentation.speciesCorrection == .unavailable, "\(presentation.speciesCorrection)")
        #expect(!presentation.offersSpeciesClaim)
        #expect(presentation.quadActions == QuadActionRow.Action.allCases)
        #expect(presentation.offersCheckIn)
        #expect(presentation.activity.map(\.label) == ["Added"])
    }

    /// The live defect: on somebody else's unnamed tree the claim used to show, and its tap fails
    /// because `claimSpecies` acts only on this phone's own rows.
    ///
    /// Red-proof: restore `offersSpeciesClaim` to `source == .community && species == nil &&
    /// acceptsContributions` — red on "the claim is offered".
    @Test("somebody else's unnamed tree: the claim is not offered, and the tap it would make is refused")
    func unnamedCachedTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let plane = try await Self.plane(api)
        let id = try await Self.cached(api, species: nil)

        let presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(presentation.profile.species == nil, "calibration: the tree has no species")
        #expect(!presentation.offersSpeciesClaim, "the claim is offered")
        #expect(presentation.speciesCorrection == .unavailable)
        // The boundary's own answer, which is why the control must not be drawn.
        await #expect(throws: APIError.notFound) {
            _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)
        }
    }

    // MARK: - A tree on this phone that somebody else added

    /// The same rule on this phone's own table: a tree another person added here (another device
    /// id stands in for another account) offers the reader no species control.
    ///
    /// Red-proof: remove `guard isAdder else { return .unavailable }` from
    /// `LocalAPI.speciesCorrectionOffer` — red on "a report is offered".
    @Test("a tree another person added on this phone offers no species control")
    func anotherPersonsTreeHere() async throws {
        let store = try await Self.seededStore()
        let adder = LocalAPI(store: store, deviceID: Self.otherDevice)
        let named = try await Self.add(adder, device: Self.otherDevice, at: Self.spot, species: try await Self.plane(adder).id)
        let unnamed = try await Self.add(
            adder, device: Self.otherDevice, at: VisitPinAdjust.offset(Self.spot, northM: 40, eastM: 0)
        )

        let reader = LocalAPI(store: store, deviceID: Self.readerDevice)
        let onNamed = TreeProfilePresentation(profile: try await reader.treeProfile(id: named.id))
        #expect(onNamed.profile.isAddedHere, "calibration: the tree is in this phone's table")
        #expect(onNamed.speciesCorrection == .unavailable, "a report is offered: \(onNamed.speciesCorrection)")
        let onUnnamed = TreeProfilePresentation(profile: try await reader.treeProfile(id: unnamed.id))
        #expect(!onUnnamed.offersSpeciesClaim, "the claim is offered")
    }

    /// The reader's own tree keeps both controls: the claim while it has no species, and the
    /// correction once it has one.
    @Test("your own tree keeps the claim and the correction")
    func ownTreeKeepsBoth() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let plane = try await Self.plane(api)
        let tree = try await Self.add(api, device: Self.readerDevice, at: Self.spot)

        var presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: tree.id))
        #expect(presentation.offersSpeciesClaim)
        _ = try await api.claimSpecies(treeID: tree.id, speciesID: plane.id)
        presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: tree.id))
        #expect(presentation.speciesCorrection == .correctable)
        #expect(presentation.offersMovePin)
    }

    // MARK: - The seam

    /// The seam writes a tree the way a tile page does: it reads back as somebody else's tree,
    /// it is on the map, and seeding it again replaces the row.
    @Test("the debug cache seam writes a cached tree that the profile and the map both read")
    func theSeam() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let id = try await Self.cached(api, species: nil)

        let profile = try await api.treeProfile(id: id)
        #expect(profile.tree.source == .community)
        #expect(!profile.isAddedHere)
        let near = try await api.treesNear(Self.spot, radiusM: 5, limit: 5)
        #expect(near.map(\.tree.id) == [id])

        try await api.debugSeedCommunityCache(
            Tree(id: id, source: .community, coordinate: Self.spot, status: .alive)
        )
        #expect(try await api.treesNear(Self.spot, radiusM: 5, limit: 5).count == 1, "a re-seed added a second row")
    }

    /// `unsharedNotSharing` signs a debug account in, and the simulator keeps it. Any other deep
    /// link signs exactly that account out first; another account stays signed in.
    ///
    /// Red-proof: remove the sign-out at the top of `DebugDeepLink.open` — red on "the not-sharing
    /// debug account is still signed in".
    @MainActor
    @Test("a deep link after unsharedNotSharing starts signed out, and leaves other accounts alone")
    func theDebugAccountDoesNotLeak() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)

        let leaked = await DebugDeepLink.open(.unsharedNotSharing, api: api, router: AppRouter())
        #expect(leaked == nil, "unsharedNotSharing failed: \(String(describing: leaked))")
        #expect(await api.userID == DebugDeepLink.notSharingAccount, "calibration: the link signed its account in")

        let next = await DebugDeepLink.open(.othersTree, api: api, router: AppRouter())
        #expect(next == nil, "othersTree failed: \(String(describing: next))")
        #expect(await api.userID == nil, "the not-sharing debug account is still signed in")

        let someoneElse = UUID(uuidString: "0E000000-0000-4000-8000-0000000C3A03")!
        try await api.linkAccount(deviceUUID: Self.readerDevice, userID: someoneElse, provider: "apple", acceptsLicense: true)
        _ = await DebugDeepLink.open(.othersTree, api: api, router: AppRouter())
        #expect(await api.userID == someoneElse, "a deep link signed out an account that is not the debug one")
    }
}
#endif
