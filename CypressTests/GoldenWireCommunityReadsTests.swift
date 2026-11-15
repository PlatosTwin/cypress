//
//  GoldenWireCommunityReadsTests.swift
//  CypressTests
//
//  `GoldenWireFixtureTests` over the community-tree reads (round C2): the tile, its delta, the
//  history, and the profile's new keys. Each file is read off `server/testdata/` and decoded through
//  `RemoteAPI`'s own accessor, over a transport that answers with the file's bytes, for the reason
//  `GoldenWireFixtureTests`' header gives: a copy in a Swift literal would prove only that this file
//  agrees with itself.
//

import Foundation
import Testing
@testable import Cypress

extension GoldenWireFixtureTests {

    // MARK: Fixtures

    static let tileFixture = CommunityTile(x: 2616, y: 6333)!
    static let speciesTree = UUID(uuidString: "5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d01")!
    static let unnamedTree = UUID(uuidString: "5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d02")!
    static let erasedTree = UUID(uuidString: "5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d03")!
    static let newTree = UUID(uuidString: "5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d04")!

    /// A `RemoteAPI` whose transport answers `route` with the named fixture's bytes.
    static func remote(answering route: String, withFixture name: String) throws -> (RemoteAPI, ScriptedTransport) {
        let data = try fixture(name)
        #expect(data.count > 0, "server/testdata/\(name) is empty")
        let transport = ScriptedTransport()
        transport.answer(route, with: String(decoding: data, as: UTF8.self))
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared
        )
        return (remote, transport)
    }

    static func day(_ iso: String) throws -> CalendarDay {
        try #require(CalendarDay(isoDate: iso))
    }

    // MARK: community_trees_tile.json

    /// `server/testdata/README.md`: the tile's trees are `[Tree]`, the envelope is snake_case.
    /// Tree `…5d01` carries a species, so a key drift would decode it as a silent nil; it is found
    /// by id, not by position.
    ///
    /// Red-proof: rename `withdrawnTreeIDs`' coding key — red on the decode, which throws.
    @Test("community_trees_tile.json decodes through RemoteAPI, species and all")
    func tileSnapshotDecodes() async throws {
        let (remote, transport) = try Self.remote(
            answering: "GET /community-trees", withFixture: "community_trees_tile.json"
        )

        let page = try await remote.communityTile(Self.tileFixture, cursor: nil)

        // The request: the tile in the route's spelling, and no cursor on a snapshot.
        let call = try #require(transport.call("GET /community-trees"))
        let query = URLComponents(string: "x:/?" + (call.query ?? ""))?.queryItems ?? []
        #expect(query.first { $0.name == "tile" }?.value == "14/2616/6333")
        #expect(!query.contains { $0.name == "cursor" }, "a snapshot sent a cursor: \(query)")

        #expect(page.tile == "14/2616/6333")
        #expect(Set(page.trees.map(\.id)) == [Self.speciesTree, Self.unnamedTree])
        #expect(page.withdrawnTreeIDs.isEmpty)
        #expect(!page.hasMore)
        #expect(page.nextCursor.hasPrefix("Xl5eXl5e"), "the cursor did not arrive verbatim: \(page.nextCursor)")

        let named = try #require(page.trees.first { $0.id == Self.speciesTree })
        #expect(named.speciesCurrentID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c"))
        #expect(named.source == .community)
        #expect(named.placement == .contributorPlaced)
        #expect(named.statedLandContext == .street)
        #expect(named.address == nil)
        // Went live on the 21st: the day, whatever zone reads it.
        #expect(CalendarDay(utcDayOf: named.createdAt) == (try Self.day("2026-09-21")))

        // Calibration of `CommunityTile` against the service's own fixture: both trees stand in the
        // tile the file names.
        for tree in page.trees {
            #expect(CommunityTile(containing: tree.coordinate) == Self.tileFixture, "\(tree.id) is not in 14/2616/6333")
        }
    }

    // MARK: community_trees_tile_delta.json

    /// The delta: one tree moved and renamed, one new, one withdrawn, one erased. The cursor is sent
    /// back unchanged, and both removal ids arrive by value.
    @Test("community_trees_tile_delta.json decodes, removals and all, and the cursor goes back verbatim")
    func tileDeltaDecodes() async throws {
        let (remote, transport) = try Self.remote(
            answering: "GET /community-trees", withFixture: "community_trees_tile_delta.json"
        )
        let cursor = "Xl5eXl5eXl5eXl5eIPawJTsL84dawF9H4PrL-CZXlm-j47Ea6c4ka5U2zKV4hCEEwaLkeoiPNOzK5356-8M"

        let page = try await remote.communityTile(Self.tileFixture, cursor: cursor)

        let call = try #require(transport.call("GET /community-trees"))
        let query = URLComponents(string: "x:/?" + (call.query ?? ""))?.queryItems ?? []
        #expect(query.first { $0.name == "cursor" }?.value == cursor, "the cursor was not sent back unchanged")

        #expect(page.withdrawnTreeIDs == [Self.unnamedTree, Self.erasedTree])
        let moved = try #require(page.trees.first { $0.id == Self.speciesTree })
        #expect(moved.coordinate == Coordinate(latitude: 37.76021, longitude: -122.50497))
        #expect(moved.speciesCurrentID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7d"))
        #expect(CalendarDay(utcDayOf: moved.updatedAt) == (try Self.day("2026-09-27")))
        let added = try #require(page.trees.first { $0.id == Self.newTree })
        #expect(added.placement == .gps)
        #expect(added.statedLandContext == .cityPark)
        #expect(added.speciesCurrentID == nil)
        #expect(page.nextCursor != cursor)
    }

    // MARK: tree_history.json

    /// Newest first, three events, no actor. Each date is a calendar day.
    ///
    /// Red-proof: map `occurred_at` through the reader's zone in `RemoteAPI.treeHistory` — red at
    /// UTC−7, where every day is one early.
    @Test("tree_history.json decodes through RemoteAPI as calendar days")
    func historyDecodes() async throws {
        let (remote, _) = try Self.remote(
            answering: "GET /trees/\(Self.speciesTree.uuidString)/history", withFixture: "tree_history.json"
        )

        let history = try #require(try await remote.treeHistory(id: Self.speciesTree))

        #expect(history.treeID == Self.speciesTree)
        #expect(history.isComplete)
        #expect(history.events.map(\.kind) == [.speciesCorrected, .locationCorrected, .added])
        #expect(history.events.map(\.day) == [
            try Self.day("2026-09-27"), try Self.day("2026-09-26"), try Self.day("2026-09-21"),
        ])

        let renamed = history.events[0]
        #expect(renamed.fromSpeciesID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c"))
        #expect(renamed.toSpeciesID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7d"))
        #expect(renamed.placement == nil)

        let moved = history.events[1]
        #expect(moved.fromCoordinate == Coordinate(latitude: 37.7601, longitude: -122.505))
        #expect(moved.toCoordinate == Coordinate(latitude: 37.76021, longitude: -122.50497))
        #expect(moved.placement == .known(.contributorPlaced))

        let wentLive = history.events[2]
        #expect(wentLive.fromCoordinate == nil)
        #expect(wentLive.toCoordinate == Coordinate(latitude: 37.7601, longitude: -122.505))
    }

    /// The vocabulary is an allow-list that can widen: an unknown `kind` or `placement` is kept as
    /// unrecognized, and the rest of the history still decodes. A Swift-side body, because the
    /// service's fixture has no unknown case to show (`server/` is not this round's to change).
    ///
    /// Red-proof: decode `kind` as a closed enum — red on the throw.
    @Test("a history kind or placement this build does not know is kept, not fatal")
    func anUnknownHistoryKindIsTolerated() async throws {
        let transport = ScriptedTransport()
        let id = Self.speciesTree
        transport.answer("GET /trees/\(id.uuidString)/history", with: """
            {"tree_uuid":"\(id.uuidString.lowercased())","events":[
              {"id":"a0d4e5f6-1111-4c2d-8e3f-000000000009","kind":"photo_featured",
               "occurred_at":"2026-10-01T00:00:00Z","from_coordinate":null,"to_coordinate":null,
               "from_species_id":null,"to_species_id":null,"placement":"surveyed"},
              {"id":"a0d4e5f6-1111-4c2d-8e3f-000000000001","kind":"added",
               "occurred_at":"2026-09-21T00:00:00Z","from_coordinate":null,
               "to_coordinate":{"latitude":37.7601,"longitude":-122.505},
               "from_species_id":null,"to_species_id":null,"placement":"gps"}
            ],"complete":true}
            """)
        let remote = RemoteAPI(baseURL: URL(string: "https://service.invalid/api/v1")!, transport: transport, session: .shared)

        let history = try #require(try await remote.treeHistory(id: id))

        #expect(history.events.map(\.kind) == [.unrecognized("photo_featured"), .added])
        #expect(history.events[0].placement == .unrecognized("surveyed"))
        #expect(history.events[1].placement == .known(.gps))
    }

    /// The history's 404 means "no history", not an error (`server/testdata/README.md`).
    ///
    /// Red-proof: remove the `catch APIError.notFound` in `RemoteAPI.treeHistory` — red on the throw.
    @Test("the history's not_found is no history, and any other failure still throws")
    func historyNotFoundIsNoHistory() async throws {
        let transport = ScriptedTransport()
        let id = UUID()
        transport.answer("GET /trees/\(id.uuidString)/history", throwing: APIError.notFound)
        let remote = RemoteAPI(baseURL: URL(string: "https://service.invalid/api/v1")!, transport: transport, session: .shared)
        #expect(try await remote.treeHistory(id: id) == nil)

        transport.answer("GET /trees/\(id.uuidString)/history", throwing: APIError.serverError)
        await #expect(throws: APIError.serverError) { _ = try await remote.treeHistory(id: id) }
    }

    // MARK: The profile's community keys

    /// The profile answer as the wire type decodes it, for the two keys `RemoteAPI` does not carry
    /// further (`community_tree` and `is_published`; `TreeCommunityHalfResponse.communityTree`
    /// says why).
    static func profileResponse(_ name: String) throws -> TreeCommunityHalfResponse {
        try RemoteCoding.decoder.decode(TreeCommunityHalfResponse.self, from: try fixture(name))
    }

    /// `tree_profile_community.json`: a stranger's view of a published community tree. The tree
    /// arrives with its species, `added_by_you` is false, and the photograph's `captured_on` arrives
    /// as a calendar day beside the noon-UTC instant.
    ///
    /// Red-proof: rename `capturedOn`'s coding key — red on the missing `captured_on`.
    @Test("tree_profile_community.json carries the tree, added_by_you, and captured_on")
    func profileCommunityKeysDecode() async throws {
        let (remote, _) = try Self.remote(
            answering: "GET /trees/\(Self.speciesTree.uuidString)", withFixture: "tree_profile_community.json"
        )

        let half = try await remote.treeCommunityHalf(id: Self.speciesTree)

        #expect(!half.addedByYou)
        let wire = try Self.profileResponse("tree_profile_community.json")
        let tree = try #require(wire.communityTree, "community_tree did not decode into Tree")
        #expect(tree.id == Self.speciesTree)
        #expect(tree.speciesCurrentID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c"))
        #expect(wire.isPublished == true)

        let photo = try #require(UUID(uuidString: "8c1cc8a2-ded9-4bd5-ae4f-af2b0174bf01"))
        #expect(half.capturedOn[photo] == (try Self.day("2026-09-22")), "captured_on was lost: \(half.capturedOn)")
        #expect(ISO8601DateFormatter().string(from: try #require(half.photos.first).capturedAt) == "2026-09-22T12:00:00Z")
    }

    /// The hidden and the unknown answers carry no tree, and say nothing else either. A null
    /// `community_tree` is never "deleted"; it is only "not one this caller may see".
    @Test("tree_profile_hidden.json and tree_profile_unknown.json carry no tree")
    func hiddenAndUnknownCarryNoTree() async throws {
        for (name, id) in [
            ("tree_profile_hidden.json", "3c1e7a90-2b4d-4f6e-8a1c-0d9e8f7a6b03"),
            ("tree_profile_unknown.json", "3c1e7a90-2b4d-4f6e-8a1c-0d9e8f7a6b02"),
        ] {
            let treeID = try #require(UUID(uuidString: id))
            let (remote, _) = try Self.remote(answering: "GET /trees/\(treeID.uuidString)", withFixture: name)
            let half = try await remote.treeCommunityHalf(id: treeID)
            let wire = try Self.profileResponse(name)
            #expect(wire.communityTree == nil, "\(name) decoded a tree")
            #expect(wire.isPublished == false, "\(name) said is_published")
            #expect(!half.addedByYou, "\(name) said added_by_you")
            #expect(half.photos.isEmpty)
            #expect(half.capturedOn.isEmpty)
        }
    }

    /// `tree_profile_city.json` pins the absence of `captured_on`, and `tree_profile.json` its
    /// presence on two rows of three. An absent date stays absent, so the row falls back to
    /// `captured_at` in the reader's zone.
    @Test("captured_on is present where the service sent it and absent elsewhere")
    func capturedOnPresenceAndAbsence() async throws {
        let cityTree = try #require(UUID(uuidString: "3c1e7a90-2b4d-4f6e-8a1c-0d9e8f7a6b01"))
        let (cityRemote, _) = try Self.remote(answering: "GET /trees/\(cityTree.uuidString)", withFixture: "tree_profile_city.json")
        let city = try await cityRemote.treeCommunityHalf(id: cityTree)
        #expect(city.photos.count == 1)
        #expect(city.capturedOn.isEmpty, "a photograph with no captured_on gained one: \(city.capturedOn)")
        #expect(try Self.profileResponse("tree_profile_city.json").communityTree == nil)

        let ownTree = try #require(UUID(uuidString: "5a1e7c0d-0000-4000-8000-00000000f030"))
        let (remote, _) = try Self.remote(answering: "GET /trees/\(ownTree.uuidString)", withFixture: "tree_profile.json")
        let half = try await remote.treeCommunityHalf(id: ownTree)
        let day = try Self.day("2026-09-24")
        #expect(half.capturedOn == [
            try #require(UUID(uuidString: "11111111-0000-4000-8000-0000000000a1")): day,
            try #require(UUID(uuidString: "33333333-0000-4000-8000-0000000000c3")): day,
        ])
    }
}
