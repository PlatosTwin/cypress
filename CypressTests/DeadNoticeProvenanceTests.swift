import Foundation
import Testing
@testable import Cypress

/// The tree profile's dead notice must say **who** says the tree is dead, and be right about it.
///
/// ── The defect this suite exists for (review finding F7 on PR #108) ────────────────────────────
/// `TreeProfilePresentation.deadNotice` guarded on `tree.status == .deadReported` and nothing else,
/// then returned one sentence: *"Reported dead, and a community reviewer confirmed it."* It asked
/// **what** the status is and never **who said so**. That was true of every row that had ever
/// shipped, because `dead_reported` could only ever come out of the review queue — and seed
/// generation s17 is what made it false: `build_seed.status_for_record` maps a source-stated `Dead`
/// condition onto the status, and NYC Parks publishes that condition on 10,635 rows. Every one of
/// them would have told a reader that a community reviewer confirmed a record no community member
/// has ever seen.
///
/// ── What is asserted here, and what deliberately is not ────────────────────────────────────────
/// **Provenance selection, not phrasing.** The sentences are `NOT SPECIFIED` — SCREENS.md draws no
/// dead profile in any of these three states — so the wording may still change on review. What may
/// not change is which claim goes with which row, so these tests assert that the community arm is
/// the *only* arm that mentions a reviewer, that the city arm names the row's own inventory, and
/// that the arm which can name nobody attributes the death to nobody. Two of those are assertions
/// about a **substring that must be absent**, which is normally the weaker kind — here the absent
/// substring *is* the defect, so it is the assertion the fix has to survive.
///
/// The inventory names below are invented for this suite precisely so that a passing city arm cannot
/// be a coincidence of the shipped seed: no literal in `Cypress` contains them, so the only way the
/// sentence can carry one is by reading it off the row.
@Suite("Tree profile · who says this tree is dead")
struct DeadNoticeProvenanceTests {

    // MARK: - Fixtures

    /// A name no source file in the app contains, so the city arm can only produce it by reading the
    /// payload. Deliberately not `NYC Parks Forestry Tree Points`: a test that used the real string
    /// would pass against a hardcoded literal for the very city this fix is about.
    private static let inventoryName = "Testburgh municipal tree register"

    private static func inventory(named name: String = inventoryName) -> InventorySource {
        InventorySource(id: "testburgh_register", name: name, url: "", snapshotDate: nil)
    }

    private static func tree(
        source: TreeSource,
        status: TreeStatus = .deadReported
    ) -> Tree {
        Tree(
            id: UUID(uuidString: "7EE00000-0000-4000-8000-0000000000F7")!,
            source: source,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            status: status
        )
    }

    private static func presentation(
        source: TreeSource,
        provenance: TreeStatusProvenance,
        status: TreeStatus = .deadReported,
        inventory named: InventorySource? = DeadNoticeProvenanceTests.inventory()
    ) -> TreeProfilePresentation {
        TreeProfilePresentation(
            profile: TreeProfile(
                tree: tree(source: source, status: status),
                inventorySource: named,
                statusProvenance: provenance
            )
        )
    }

    // MARK: - The three arms

    /// **The arm F7 is about.** A city-import row carrying the status its own publisher stated must
    /// name that publisher, and must not credit a reviewer.
    @Test("a city inventory's own dead row names the inventory and no reviewer")
    func cityRecordNamesItsInventory() throws {
        let notice = try #require(
            Self.presentation(source: .cityImport, provenance: .record).deadNotice
        )

        #expect(
            notice.text.contains(Self.inventoryName),
            "the sentence must name the inventory the row came from, read off the payload"
        )
        #expect(
            !notice.text.lowercased().contains("community reviewer"),
            "no community reviewer has seen this record — this is the falsehood F7 found"
        )
        #expect(!notice.text.lowercased().contains("confirmed"))
    }

    /// The same row, the same status, the other origin: a reviewer on this device confirmed a
    /// reported death on a row the inventory published as alive. `TreeSource` is identical to the
    /// case above, which is exactly why the notice cannot be derived from it.
    @Test("a review-confirmed death on a city row credits the reviewer, not the inventory")
    func reviewConfirmedNamesTheReviewer() throws {
        let notice = try #require(
            Self.presentation(source: .cityImport, provenance: .communityReview).deadNotice
        )

        #expect(notice.text.lowercased().contains("community reviewer"))
        #expect(
            !notice.text.contains(Self.inventoryName),
            "the inventory did not say this tree was dead and must not be quoted as though it had"
        )
    }

    /// `source` alone answers neither case — stated as its own assertion because "just switch on
    /// `TreeSource`" is the repair a later round is most likely to reach for.
    @Test("the same source produces different notices, so the notice is not a function of source")
    func sourceCannotAnswerTheQuestion() throws {
        let published = try #require(
            Self.presentation(source: .cityImport, provenance: .record).deadNotice
        )
        let confirmed = try #require(
            Self.presentation(source: .cityImport, provenance: .communityReview).deadNotice
        )
        #expect(published != confirmed)
        #expect(published.leadIn != confirmed.leadIn)
    }

    /// A record whose status came from neither an inventory nor a review here has nobody to
    /// attribute it to, and the notice says nothing about who. Unreachable in shipping code today —
    /// `addTree` writes `alive` and only an override moves a status — and asserted anyway, because
    /// an arm that has to invent an attributor is precisely what F7 was.
    @Test("a record with nobody to credit credits nobody")
    func unattributableCreditsNobody() throws {
        let notice = try #require(
            Self.presentation(source: .community, provenance: .record, inventory: nil).deadNotice
        )

        #expect(!notice.text.lowercased().contains("community reviewer"))
        #expect(!notice.text.lowercased().contains("inventory"))
        #expect(!notice.text.contains(Self.inventoryName))
    }

    /// A seed whose receipt cannot name the inventory still gets a true sentence: the category the
    /// row does support, never a city the app cannot derive. Same fallback the subtitle takes (R28).
    @Test("an unnameable inventory falls back to the category, not to a city")
    func unnameableInventoryFallsBack() throws {
        let notice = try #require(
            Self.presentation(source: .cityImport, provenance: .record, inventory: nil).deadNotice
        )

        #expect(notice.text.contains(CityRecordCopy.unnamedCityInventory))
        #expect(!notice.text.lowercased().contains("community reviewer"))
    }

    /// **An inventory whose receipt names it with an empty string is unnameable too**, and used not
    /// to be treated as such (review finding F2).
    ///
    /// `InventorySource.init?(seedMeta:)` built a value whose `name` was `""`, because it guarded the
    /// id for emptiness and not the name — where its per-inventory sibling has always guarded both.
    /// The value was not nil, so the `?? unnamedCityInventory` fallback below never fired and the
    /// sentence read *"Recorded dead in the ."*
    ///
    /// Driven through the real initializer rather than by handing the presentation an
    /// `InventorySource(name: "")`, because the defect was in the decode and a fixture would have
    /// asserted around it. The receipt below is the shape a build writes: a source id, a name key
    /// present and empty.
    @Test("a receipt naming the inventory with an empty string falls back too")
    func emptyInventoryNameFallsBack() throws {
        #expect(
            InventorySource(seedMeta: ["trees_source": "sf_city", "trees_source_name": ""]) == nil,
            "an inventory with no sayable name is not an answer"
        )
        // Calibration: the same receipt with a name really does build one, so the nil above is the
        // empty name being refused and not the receipt being unreadable.
        let named = try #require(
            InventorySource(seedMeta: ["trees_source": "sf_city", "trees_source_name": "Testburgh register"])
        )
        #expect(named.name == "Testburgh register")

        // And an absent key still yields the id, unchanged — this must not have widened into
        // "a receipt without the name key is unreadable".
        #expect(InventorySource(seedMeta: ["trees_source": "sf_city"])?.name == "sf_city")

        // The consequence on the surface F2 was raised about.
        let notice = try #require(
            Self.presentation(
                source: .cityImport,
                provenance: .record,
                inventory: InventorySource(seedMeta: ["trees_source": "sf_city", "trees_source_name": ""])
            ).deadNotice
        )
        #expect(notice.text.contains(CityRecordCopy.unnamedCityInventory))
        #expect(!notice.text.contains("the ."), "the sentence lost its object")
    }

    // MARK: - The pair cannot come apart

    /// The lead-in and the sentence travel as one value. A view that drew `Confirmed dead:` over the
    /// city sentence would be F7 again, reassembled one layer up.
    @Test("each arm's lead-in is its own")
    func leadInsAreDistinct() throws {
        let leadIns = try [
            Self.presentation(source: .cityImport, provenance: .record),
            Self.presentation(source: .cityImport, provenance: .communityReview),
            Self.presentation(source: .community, provenance: .record, inventory: nil)
        ].map { try #require($0.deadNotice).leadIn }

        #expect(Set(leadIns).count == leadIns.count, "three arms, three lead-ins")
        // The one that claims a confirmation belongs to the one arm where a person confirmed
        // something. Asserted on the community arm's own constant rather than on its spelling.
        #expect(leadIns[1] == TreeProfilePresentation.deadNoticeConfirmedLeadIn)
        #expect(leadIns[0] != TreeProfilePresentation.deadNoticeConfirmedLeadIn)
    }

    /// No arm may claim the city was told, on the surface where that temptation is strongest
    /// (DECISIONS §3.3, RULINGS R12). The city arm states that a file already records the death; it
    /// must not read as anybody acting on it.
    @Test("no arm claims the city was notified")
    func noArmClaimsTheCityWasTold() throws {
        let arms = [
            Self.presentation(source: .cityImport, provenance: .record),
            Self.presentation(source: .cityImport, provenance: .communityReview),
            Self.presentation(source: .community, provenance: .record, inventory: nil)
        ]

        for arm in arms {
            let text = try #require(arm.deadNotice).text.lowercased()
            #expect(!text.contains("notified"))
            #expect(!text.contains("reported to the city"))
            #expect(!text.contains("sent to the city"))
            #expect(!text.contains("311"))
            // And every arm keeps the half of the sentence that is the reason the notice exists at
            // all: the tree is standing and the buttons below are still meant for the reader (E170).
            #expect(text.contains("still worth reporting"))
        }
    }

    // MARK: - The guard on the guard

    /// The notice is a statement about `dead_reported` and nothing else. Without this, an arm that
    /// returned a sentence for every status would satisfy every assertion above.
    @Test(
        "no other status draws a dead notice",
        arguments: TreeStatus.allCases.filter { $0 != .deadReported }
    )
    func onlyDeadReportedDrawsIt(_ status: TreeStatus) {
        #expect(
            Self.presentation(source: .cityImport, provenance: .record, status: status).deadNotice == nil
        )
        #expect(
            Self.presentation(source: .cityImport, provenance: .communityReview, status: status)
                .deadNotice == nil
        )
    }

    /// No city's name is written into the copy. The round that fixes F7 is the round most likely to
    /// hardcode `NYC`, because NYC is the publish that forced it.
    ///
    /// **The lead-ins are scanned with the sentences (review finding N2).** They were not, and
    /// `Listed dead:` is the string most likely to acquire a city if the copy moves — it is the one
    /// piece of this notice that names the *act* of a publisher rather than the publisher, so
    /// "Listed dead in NYC:" is a plausible edit that the sentence-only scan would have waved past.
    @Test("the copy names no city of its own")
    func copyHardcodesNoCity() {
        let arms = [
            TreeProfilePresentation.deadNoticeConfirmed,
            TreeProfilePresentation.deadNoticeReported,
            TreeProfilePresentation.deadNoticeListed(inventory: Self.inventoryName),
            TreeProfilePresentation.deadNoticeConfirmedLeadIn,
            TreeProfilePresentation.deadNoticeReportedLeadIn,
            TreeProfilePresentation.deadNoticeListedLeadIn
        ]
        for arm in arms {
            let text = arm.lowercased()
            #expect(!text.contains("nyc"))
            #expect(!text.contains("new york"))
            #expect(!text.contains("san francisco"))
            #expect(!text.contains("san jose"))
            #expect(!text.contains("parks"))
        }
    }
}
