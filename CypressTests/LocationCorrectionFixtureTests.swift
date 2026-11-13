//
//  LocationCorrectionFixtureTests.swift
//  CypressTests
//
//  The Swift half of two request goldens the community-trees server rounds pinned:
//  `server/testdata/sync_location_correction.json` (a `POST /sync` body carrying one
//  `location_correction`) and `server/testdata/photos_begin.json` (a `POST /photos/begin` body with
//  `captured_on`, decision 14a).
//
//  `GoldenWireFixtureTests` decodes what the service *sends*; these encode what the phone *sends*
//  and compare it with the file the Go tests decode. Both are read off disk, never pasted, for that
//  file's reason. Both are encoded through the path the app ships — `RemoteAPI.syncItemBody(for:)`
//  and `RemoteAPI.beginPhotoBody(for:timeZone:)` with `RemoteCoding.encoder` — rather than through a
//  copy of it.
//
//  The comparison is structural (parsed JSON, not bytes): key order is not part of the contract,
//  and the Go side decodes rather than byte-compares these two. One normalization, stated: a JSON
//  `null` in a fixture is dropped before comparing, because Swift's synthesized encoder omits a nil
//  optional and the service reads an absent key and a `null` alike for every field involved.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Community trees · request goldens (server/testdata)")
struct LocationCorrectionFixtureTests {

    private static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("server/testdata")
            .appendingPathComponent(name))
    }

    /// Parsed, with `null` members removed at every depth.
    private static func object(_ data: Data) throws -> NSObject {
        let parsed = try JSONSerialization.jsonObject(with: data)
        return stripNulls(parsed) as! NSObject
    }

    private static func stripNulls(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var kept: [String: Any] = [:]
            for (key, member) in dictionary where !(member is NSNull) {
                kept[key] = stripNulls(member)
            }
            return kept as NSDictionary
        }
        if let array = value as? [Any] { return array.map(stripNulls) as NSArray }
        return value
    }

    private static func instant(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text), "\(text) is not an instant")
    }

    // MARK: - The values the goldens hold

    private static let treeID = UUID(uuidString: "C3A1F7E2-5D4B-4E8A-9B6C-2F1E0D9C8B7A")!
    private static let correctionKey = UUID(uuidString: "6F0D0C2E-3B1A-4C47-9E0B-7C9A5D2B1E01")!
    private static let correctionID = UUID(uuidString: "8B2E4D6F-1A3C-4E5B-9D7F-0C2A4B6D8E10")!
    private static let deviceID = UUID(uuidString: "D1E2F3A4-B5C6-4D7E-8F90-A1B2C3D4E5F6")!
    private static let binaryKey = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!

    private static func syncBody(id: UUID = correctionID) throws -> Data {
        let payload = OutboxPayload.locationCorrection(
            TreeLocationCorrection(
                id: id,
                clientUUID: correctionKey,
                treeID: treeID,
                coordinate: Coordinate(latitude: 37.76015, longitude: -122.50505),
                placement: .contributorPlaced,
                locationAccuracyM: 4.5,
                attribution: Attribution(userID: nil, deviceID: deviceID),
                occurredAt: try instant("2026-09-28T17:05:00Z")
            )
        )
        let item = try payload.makeItem(createdAt: try instant("2026-09-28T17:05:00Z"))
        return try RemoteCoding.encoder.encode(
            SyncRequestBody(items: [try RemoteAPI.syncItemBody(for: item)])
        )
    }

    private static func beginRequest() throws -> PhotoUploadRequest {
        PhotoUploadRequest(
            treeID: treeID,
            visitID: nil,
            shotType: .fullTree,
            localPath: "/staged/fixture.jpg",
            capturedAt: try instant("2026-09-28T23:30:00Z"),
            width: 3024,
            height: 4032,
            publicCoordinate: Coordinate(latitude: 37.76, longitude: -122.505),
            idempotencyKey: binaryKey
        )
    }

    // MARK: - Calibration

    /// The instrument, against answers known before it ran: both files are on disk and parse, and
    /// the comparison is sensitive to exactly the drift it is here for — the correction's `id`
    /// spelled some other way (the server's `payload.ID == payload.TreeID` refusal exists because
    /// that drift is easy), and the tree pointer spelled `id`.
    ///
    /// Without this, every gate below could be green on a comparison that ignored the payload.
    @Test("the goldens are on disk, and the comparison sees a renamed key")
    func theComparisonIsCalibrated() throws {
        let golden = try Self.object(try Self.fixture("sync_location_correction.json"))
        let begin = try Self.object(try Self.fixture("photos_begin.json"))
        #expect(golden.isEqual(NSDictionary()) == false, "sync_location_correction.json parsed as nothing")
        #expect(begin.isEqual(NSDictionary()) == false, "photos_begin.json parsed as nothing")

        // The ours-side, then broken on purpose: `id` renamed, and the tree's id sent as `id`.
        var mutated = try #require(
            try JSONSerialization.jsonObject(with: try Self.syncBody()) as? [String: Any]
        )
        var items = try #require(mutated["items"] as? [[String: Any]])
        var payload = try #require(items[0]["payload"] as? [String: Any])
        payload["correctionID"] = payload.removeValue(forKey: "id")
        items[0]["payload"] = payload
        mutated["items"] = items
        let renamed = Self.stripNulls(mutated) as! NSObject
        #expect(!renamed.isEqual(golden), "a renamed `id` compared equal — the comparison ignores the payload")

        let treeAsID = try Self.object(try Self.syncBody(id: Self.treeID))
        #expect(!treeAsID.isEqual(golden), "the tree's id sent as the correction's compared equal")
    }

    // MARK: - sync_location_correction.json

    /// Red-proof: rename `TreeLocationCorrection.locationAccuracyM` to `accuracyM` — red here, and
    /// on the service the field arrives as nil.
    @Test("a queued location correction is sent exactly as the service's golden holds it")
    func theCorrectionMatchesTheGolden() throws {
        let oursData = try Self.syncBody()
        let goldenData = try Self.fixture("sync_location_correction.json")
        let ours = try Self.object(oursData)
        let golden = try Self.object(goldenData)
        #expect(
            ours.isEqual(golden),
            """
            the phone's POST /sync body is not the golden.
            ours:   \(String(decoding: oursData, as: UTF8.self))
            golden: \(String(decoding: goldenData, as: UTF8.self))
            """
        )
    }

    // MARK: - photos_begin.json

    /// The golden pins the case where the phone's date and the UTC date differ: 23:30 UTC on the
    /// 28th is the 29th east of UTC. Read in Berlin (UTC+2 on that date).
    ///
    /// Red-proof: compute `captured_on` with `TimeZone(identifier: "UTC")` inside
    /// `beginPhotoBody` — red on the whole-body comparison and on the value ("2026-09-28").
    @Test("a begin sends captured_on as the phone's own date, exactly as the golden holds it")
    func theBeginMatchesTheGolden() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let body = RemoteAPI.beginPhotoBody(for: try Self.beginRequest(), timeZone: berlin)
        #expect(body.capturedOn == "2026-09-29", "captured_on is \(body.capturedOn ?? "nil") in Berlin")

        let encoded = try RemoteCoding.encoder.encode(body)
        let goldenData = try Self.fixture("photos_begin.json")
        let ours = try Self.object(encoded)
        let golden = try Self.object(goldenData)
        #expect(
            ours.isEqual(golden),
            """
            the phone's POST /photos/begin body is not the golden.
            ours:   \(String(decoding: encoded, as: UTF8.self))
            golden: \(String(decoding: goldenData, as: UTF8.self))
            """
        )
    }

    /// The same instant west of UTC is still the 28th — the date is the zone's, not a constant
    /// offset — and a phone on a non-Gregorian calendar still sends a Gregorian year.
    @Test("captured_on is the date in the phone's zone, in the Gregorian calendar")
    func capturedOnFollowsTheZone() throws {
        let instant = try Self.instant("2026-09-28T23:30:00Z")
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(RemoteAPI.localDate(of: instant, in: losAngeles) == "2026-09-28")
        #expect(RemoteAPI.localDate(of: instant, in: tokyo) == "2026-09-29")
        #expect(RemoteAPI.localDate(of: instant, in: TimeZone(secondsFromGMT: 0)!) == "2026-09-28")
    }
}
