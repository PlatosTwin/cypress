//
//  GroveStatementCensusTests.swift
//  CypressTests
//
//  **Every other gate on this read compares answers, and a page and a whole grove cut to a page
//  have the same answer.** `GrovePaginationTests` proves the pages concatenate to the unbounded
//  read — which is exactly what a `grove()` followed by `Array(all.prefix(50))` would also do,
//  while still building a thousand `GroveEntry`s to hand back fifty. That implementation is not
//  hypothetical: it is the protocol-extension default in `CypressAPI`, it is correct, and it is
//  what this round exists to keep off screen 08.
//
//  So the question here is not "what does the page contain" but "which statements ran, and over
//  how many trees". `StatementCensus` (#143) answers the first from the inside. The second is
//  answered by the store read itself, whose result *is* the projection's input: `LocalAPI`'s
//  projection is a `for` over `rows`, so bounding `rows` bounds the entries, the four scoped
//  statements' id lists, and the array SwiftUI is handed.
//

import Foundation
import Testing
@testable import Cypress

@Suite("My Grove · the first page does not build the whole grove")
struct GroveStatementCensusTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-0000000002C0")!

    /// Big enough that a page is a small fraction of it — a fixture of sixty against a page of
    /// fifty would let a whole-grove read pass for a paged one.
    private static let groveSize = 180

    private static func seededGrove() async throws -> (api: LocalAPI, store: CypressStore, trees: Int) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(store: store, deviceID: deviceID)

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 1_600, limit: 400
        )
        try #require(
            candidates.count >= groveSize,
            "the seed gave \(candidates.count) trees near the fixture center; the grove needs \(groveSize)"
        )
        let ids = candidates.prefix(groveSize).map(\.tree.id)
        let attribution = await api.attribution
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for (offset, tree) in ids.enumerated() {
                try contributions.insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        capturedAt: start.addingTimeInterval(Double(60 * (offset + 1)))
                    ),
                    connection: connection
                )
            }
        }
        return (api, store, ids.count)
    }

    // MARK: - The control, which is the unbounded form

    /// **Calibration.** The census can see the unbounded statement, and does, when the unbounded
    /// read runs. Without this line the gate below — "the unbounded text did not run" — passes just
    /// as well against a census that records nothing at all.
    @Test("the census sees the unbounded id read when the unbounded read runs")
    func theCensusSeesTheUnboundedRead() async throws {
        let (api, store, trees) = try await Self.seededGrove()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let whole = try await api.grove()
        await store.queue.installCensus(nil)

        try #require(whole.count == trees, "the fixture built \(whole.count) entries, not \(trees)")
        #expect(
            census.statements.contains(ContributionStore.groveTreeIDsSQL),
            "the unbounded read did not run the unbounded statement — this census is not recording"
        )
        #expect(
            !census.statements.contains(ContributionStore.groveTreeIDsPageSQL),
            "the unbounded read ran the paged statement"
        )
    }

    // MARK: - The gate

    /// **The first page runs the bounded statement and never the unbounded one.**
    ///
    /// The two texts differ by a `WHERE` and a `LIMIT` and nothing else — they are built from one
    /// shared fragment (`ContributionStore.groveOwnedTreesSQL`) so that they cannot come to
    /// disagree about which trees are in a grove — which is what makes their *identity* a usable
    /// signal: seeing one and not the other says which read ran, and says nothing else.
    @Test("the first page runs the bounded id statement, and the unbounded one does not appear")
    func theFirstPageRunsTheBoundedStatement() async throws {
        let (api, store, trees) = try await Self.seededGrove()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let page = try await api.grove(cursor: nil, limit: GroveLimits.pageSize)
        await store.queue.installCensus(nil)

        try #require(
            trees > GroveLimits.pageSize * 3,
            "the fixture is only \(trees) trees; a page of \(GroveLimits.pageSize) is not a page of it"
        )
        #expect(
            page.items.count == GroveLimits.pageSize,
            "the first page returned \(page.items.count) of a \(trees)-tree grove"
        )
        #expect(
            !census.statements.contains(ContributionStore.groveTreeIDsSQL),
            """
            the first page ran the unbounded id read. Every projection statement is scoped to the \
            ids it returns, so the page would be built out of all \(trees) trees and cut afterwards \
            — which is the protocol default, not the paged read
            """
        )
        #expect(
            census.statements.contains(ContributionStore.groveTreeIDsPageSQL),
            "the first page did not run the paged id statement at all"
        )
        #expect(
            census.readCount == 2,
            """
            one page made \(census.readCount) hops onto the database queue, not 2. One hop per tree \
            is the N+1 task #250 removed from this read, and a paged read is where it would come \
            back
            """
        )
    }

    /// **And the bounded statement really is bounded**, which is the other half and the one the
    /// census cannot see: it records statement texts, not how many ids were bound to them.
    ///
    /// This reads the store directly, because the store's answer *is* the projection's input —
    /// `LocalAPI.groveEntries` is a `for` over exactly these rows and hands exactly these ids to
    /// `TreeQueries.trees(ids:)`, `activeNames(treeIDs:)` and `heroPhotoIDs(treeIDs:)`. Fifty rows
    /// out of a hundred and eighty is the claim "the first page does not build the full projection"
    /// with nothing left to infer.
    @Test("the bounded id read returns a page of ids, not a grove of them")
    func theBoundedReadReturnsAPageOfIDs() async throws {
        let (api, store, trees) = try await Self.seededGrove()
        _ = api

        let (paged, whole) = try await store.queue.read { connection in
            let contributions = ContributionStore()
            return (
                try contributions.groveTreeIDs(
                    userID: nil,
                    deviceID: Self.deviceID,
                    after: nil,
                    limit: GroveLimits.pageSize,
                    connection: connection
                ),
                try contributions.groveTreeIDs(
                    userID: nil, deviceID: Self.deviceID, connection: connection
                )
            )
        }

        #expect(
            whole.count == trees,
            "the control read \(whole.count) ids of \(trees) — the fixture is not what this test thinks"
        )
        #expect(
            paged.count == GroveLimits.pageSize,
            """
            the bounded read handed the projection \(paged.count) ids for a page of \
            \(GroveLimits.pageSize) out of \(trees) trees
            """
        )
        #expect(
            paged.map(\.treeID) == Array(whole.prefix(GroveLimits.pageSize)).map(\.treeID),
            "the bounded read's page is not the head of the unbounded read's answer"
        )
    }

    /// **A later page costs what the first one costs**, which is the half a first-paint-only gate
    /// would miss: a per-row read added to the paging path is paid on every press of `Show more`.
    /// `JournalStatementCensusTests.theSecondPageCostsTheSame` is the same assertion one screen
    /// over.
    @Test("Show more is also two hops and the bounded statement")
    func theSecondPageCostsTheSame() async throws {
        let (api, store, _) = try await Self.seededGrove()
        let first = try await api.grove(cursor: nil, limit: GroveLimits.pageSize)
        let cursor = try #require(first.nextCursor, "the fixture produced no second page to ask for")

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let second = try await api.grove(cursor: cursor, limit: GroveLimits.pageSize)
        await store.queue.installCensus(nil)

        #expect(second.items.count == GroveLimits.pageSize, "the second page came back short")
        #expect(census.readCount == 2, "a later page cost \(census.readCount) hops")
        #expect(!census.statements.contains(ContributionStore.groveTreeIDsSQL))
        #expect(census.statements.contains(ContributionStore.groveTreeIDsPageSQL))
    }
}
