//
//  GoldenWireFixtureTests.swift
//  CypressTests
//
//  The client half of the cross-language contract `server/testdata/README.md` describes.
//
//  ── Why these read files instead of literals ───────────────────────────────────────────────────
//
//  `server/internal/api/golden_test.go` serializes a fixed value and compares it byte-for-byte
//  against these same files. That catches a renamed key or a timestamp growing fractional seconds,
//  and it cannot catch the thing that matters most: **whether Swift can decode them.** A Go test
//  comparing Go output to a file a Go author wrote proves the handler agrees with that author's
//  transcription of `Tree`, not with `Tree` — which is exactly how `"placement":"unknown"` and
//  `{"lat":…,"lon":…}` shipped past a passing test.
//
//  So these tests read **those exact files off disk**. A copy pasted into a Swift string literal
//  would prove that this file agrees with itself, which is the shape of guard this project has
//  repeatedly caught going green while the defect it named was present.
//
//  ── What a failure here means ──────────────────────────────────────────────────────────────────
//
//  A real contract break, in one direction or the other, and it is not fixed by editing the
//  fixture: the fixture is what the service emits. `server/testdata/README.md` names the type each
//  file decodes into and this file holds it to exactly that.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Golden wire fixtures (server/testdata)")
struct GoldenWireFixtureTests {

    /// The decoder the contract names: plain, `.iso8601`, and **no key strategy at all**.
    ///
    /// The absence is the assertion. `.convertFromSnakeCase` maps `species_current_id` to
    /// `speciesCurrentId`, which is not `Tree`'s `speciesCurrentID`; the property is optional, so
    /// the mismatch decodes as nil **without throwing** and the tree arrives with no species while
    /// nothing reports it (`server/internal/api/wire.go` carries the full argument). Configuring
    /// this decoder any other way would make every test below pass while proving nothing.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func fixture(_ name: String) throws -> Data {
        let url = AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("server/testdata")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    // MARK: Calibration

    /// **Calibrate the instrument before trusting the reading.** Three answers known before any
    /// decode ran: both files exist where the contract says they do, they are not empty, and the
    /// decoder rejects a shape it should reject.
    ///
    /// Without the last of these, every gate below would pass on a decoder that accepted anything.
    @Test("the fixtures are on disk and the decoder is not permissive")
    func theFixturesAreOnDiskAndTheDecoderIsNotPermissive() throws {
        let grove = try Self.fixture("grove.json")
        let conflict = try Self.fixture("proximity_conflict.json")
        #expect(grove.count > 0, "server/testdata/grove.json is empty — every gate below is vacuous")
        #expect(conflict.count > 0, "server/testdata/proximity_conflict.json is empty")

        // The negative control, and it is the exact drift this contract exists to catch: the same
        // record written in snake_case must NOT decode, because a decoder that read it would be one
        // that also silently nils `speciesCurrentID`.
        let snakeCased = Data(#"{"visits":3,"check_ins":1,"measurements":2,"care_events":0}"#.utf8)
        #expect(
            (try? Self.decoder.decode(GroveRecord.self, from: snakeCased)) == nil,
            "a snake_case GroveRecord decoded — this decoder is not the one the contract names"
        )
    }

    // MARK: grove.json

    /// `server/testdata/README.md`: "`grove.json` | `entries[].record` is `GroveRecord`".
    ///
    /// The row around it is server-owned and snake_case; the record inside it is camelCase because
    /// it reconstructs a client type. Both halves are asserted here, because the non-uniformity is
    /// the contract and a test that only read one half would go green on a body that "fixed" it.
    @Test("grove.json's entries decode, record and all")
    func groveJSONEntriesDecode() throws {
        let response = try Self.decoder.decode(GroveDeltaResponse.self, from: try Self.fixture("grove.json"))

        #expect(response.total == 1)
        let row = try #require(response.entries.first)
        #expect(row.treeUUID == UUID(uuidString: "602aa4b1-1ab6-471a-89ef-c85f5e63a5e2"))
        #expect(row.isFavorite)
        #expect(row.heroPhotoID == UUID(uuidString: "8c1cc8a2-ded9-4bd5-ae4f-af2b0174bfb3"))

        // The date, second-precision UTC. `.iso8601` is `.withInternetDateTime` and rejects
        // fractional seconds; the service truncates for exactly that reason.
        let visited = try #require(row.lastVisitedAt)
        #expect(ISO8601DateFormatter().string(from: visited) == "2026-08-09T18:41:46Z")

        let record = try #require(row.record, "entries[].record did not decode into GroveRecord")
        #expect(record.visits == 3)
        // The one key the convention turns on: `checkIns`, named for the control rather than for the
        // `observations` table, and spelled the way `GroveRecord` spells it.
        #expect(record.checkIns == 1)
        #expect(record.measurements == 2)
        #expect(record.careEvents == 0)
    }

    // MARK: proximity_conflict.json

    /// `server/testdata/README.md`: "`proximity_conflict.json` | the whole error body;
    /// `detail.candidates` is `[NearbyTree]`".
    ///
    /// Two decodes of one file, because it carries two shapes that different code reads: the
    /// envelope `APIError.Envelope` already knows, and the candidate list beside it — a sibling of
    /// `error` rather than a child, because the envelope's nested container decodes exactly `code`,
    /// `message` and `retryable`.
    @Test("proximity_conflict.json decodes as an envelope and as candidates")
    func proximityConflictDecodes() throws {
        let data = try Self.fixture("proximity_conflict.json")

        let envelope = try Self.decoder.decode(APIError.Envelope.self, from: data)
        #expect(envelope.error == .conflict)
        #expect(!envelope.resolvedRetryable, "conflict must stay non-retryable — the user resolves it")

        let detail = try Self.decoder.decode(ProximityConflictDetail.self, from: data)
        let candidate = try #require(detail.detail.candidates.first)

        // `distanceM`, in `NearbyTree`'s own synthesized key.
        #expect(candidate.distanceM > 4.99 && candidate.distanceM < 5.0)
        #expect(candidate.speciesScientificName == nil)
        #expect(candidate.tell == nil)

        // The nested `Tree`, and the two properties that are the whole reason this wire is
        // camelCase: both are optional, so a key-strategy mismatch would leave them nil rather than
        // throw, and the tree would arrive with no species while nothing reported it.
        #expect(candidate.tree.speciesCurrentID == UUID(uuidString: "7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c"))
        #expect(candidate.tree.neighborhoodID == nil)

        // `placement` is non-optional on the client, so a value outside `TreePlacement`'s two raw
        // values throws the whole `Tree`, the whole array and the whole conflict.
        #expect(candidate.tree.placement == .contributorPlaced)
        #expect(candidate.tree.source == .community)
        #expect(candidate.tree.status == .alive)
        #expect(candidate.tree.verificationState == .unverified)
        #expect(candidate.tree.statedLandContext == .street)
        #expect(candidate.tree.coordinate.latitude == 37.7601)
        #expect(candidate.tree.coordinate.longitude == -122.505)
        #expect(candidate.tree.deletedAt == nil)
    }

    /// The candidates are what `ProximityConflict` is built from, so the last step of the contract
    /// is that they fit it.
    @Test("the candidates are a ProximityConflict")
    func theCandidatesAreAProximityConflict() throws {
        let detail = try Self.decoder.decode(
            ProximityConflictDetail.self,
            from: try Self.fixture("proximity_conflict.json")
        )
        let conflict = ProximityConflict(candidates: detail.detail.candidates)
        #expect(conflict.candidates.count == 1)
        #expect(conflict.candidates[0].id == conflict.candidates[0].tree.id)
    }
}
