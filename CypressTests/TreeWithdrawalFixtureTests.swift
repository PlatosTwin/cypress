//
//  TreeWithdrawalFixtureTests.swift
//  CypressTests
//
//  The Swift half of `server/testdata/sync_tree_withdrawal.json`: a `POST /sync` body carrying one
//  `tree_withdrawal`. The Go half posts the same file to the service
//  (`TestTheTreeWithdrawalFixtureIsAccepted`). Encoded through the path the app ships,
//  `RemoteAPI.syncItemBody(for:)` with `RemoteCoding.encoder`, and compared structurally, for
//  `LocationCorrectionFixtureTests`' reasons.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Community trees · the withdrawal golden (server/testdata)")
struct TreeWithdrawalFixtureTests {

    private static let treeID = UUID(uuidString: "C3A1F7E2-5D4B-4E8A-9B6C-2F1E0D9C8B7A")!
    private static let key = UUID(uuidString: "5E7A9C1B-3D2F-4B6A-8C0E-1F3A5B7C9D02")!
    private static let deviceID = UUID(uuidString: "D1E2F3A4-B5C6-4D7E-8F90-A1B2C3D4E5F6")!

    private static func golden() throws -> Data {
        try Data(contentsOf: AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("server/testdata/sync_tree_withdrawal.json"))
    }

    private static func instant(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text), "\(text) is not an instant")
    }

    private static func ours() throws -> Data {
        let moment = try instant("2026-11-16T15:20:00Z")
        let payload = OutboxPayload.treeWithdrawal(
            TreeWithdrawal(
                clientUUID: key,
                treeID: treeID,
                attribution: Attribution(userID: nil, deviceID: deviceID),
                occurredAt: moment
            )
        )
        let item = try payload.makeItem(createdAt: moment)
        return try RemoteCoding.encoder.encode(
            SyncRequestBody(items: [try RemoteAPI.syncItemBody(for: item)])
        )
    }

    /// Parsed, with `null` members removed at every depth (`LocationCorrectionFixtureTests`' one
    /// normalization: Swift omits a nil optional and the service reads absent and `null` alike).
    private static func parsed(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(stripNulls(object) as? [String: Any])
    }

    private static func stripNulls(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var kept: [String: Any] = [:]
            for (key, member) in dictionary where !(member is NSNull) {
                kept[key] = stripNulls(member)
            }
            return kept
        }
        if let array = value as? [Any] { return array.map(stripNulls) }
        return value
    }

    /// Replaces the first item's payload with `change(payload)`.
    private static func mutated(_ change: (inout [String: Any]) -> Void) throws -> NSDictionary {
        var body = try parsed(try ours())
        var items = try #require(body["items"] as? [[String: Any]])
        var payload = try #require(items[0]["payload"] as? [String: Any])
        change(&payload)
        items[0]["payload"] = payload
        body["items"] = items
        return body as NSDictionary
    }

    /// The instrument against answers known before it ran: the golden parses, and the comparison
    /// sees a renamed `treeID` and an added `speciesID` (the field this payload must never carry,
    /// because the service reads it as a species the contributor has met).
    @Test("the golden is on disk, and the comparison sees a renamed key and an added speciesID")
    func theComparisonIsCalibrated() throws {
        let golden = try Self.parsed(try Self.golden()) as NSDictionary
        #expect(golden.count > 0, "sync_tree_withdrawal.json parsed as nothing")

        let renamed = try Self.mutated { $0["treeUUID"] = $0.removeValue(forKey: "treeID") }
        #expect(!renamed.isEqual(golden), "a renamed treeID compared equal; the comparison ignores the payload")
        let withSpecies = try Self.mutated { $0["speciesID"] = UUID().uuidString }
        #expect(!withSpecies.isEqual(golden), "an added speciesID compared equal")
    }

    /// Red-proof: rename `TreeWithdrawal.treeID` to `treeUUID` (with its init), and this goes red on
    /// "the phone's POST /sync body is not the golden".
    @Test("a queued tree withdrawal is sent exactly as the service's golden holds it")
    func theWithdrawalMatchesTheGolden() throws {
        let oursData = try Self.ours()
        let goldenData = try Self.golden()
        let ours = try Self.parsed(oursData) as NSDictionary
        let golden = try Self.parsed(goldenData) as NSDictionary
        #expect(
            ours.isEqual(golden),
            """
            the phone's POST /sync body is not the golden.
            ours:   \(String(decoding: oursData, as: UTF8.self))
            golden: \(String(decoding: goldenData, as: UTF8.self))
            """
        )
    }
}
