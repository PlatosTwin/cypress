import Foundation
import Testing
import UIKit
@testable import Cypress

/// The three screens that ask, show and act on `land_context` (ERRATA E146).
///
/// `CityRecordTests` already owns the data half: the CHECK, the nullable column, the mapping and its
/// distribution over all 195,309 seed rows. Nothing here re-derives any of that. This suite is about
/// the half E143 deliberately left unbuilt — the picker that writes the column, the card that reads
/// it back, and the safety handoff that the column makes reachable.
///
/// ── The assertion that matters most is the one about what did *not* change ────────────────────
/// `ReportPresentation` gained a reason to withhold the city's telephone number, and the failure mode
/// of getting that wrong is somebody with a hanging limb being told the city will not help. So the
/// report tests are weighted towards proving the number stays reachable: on every public context, on
/// an unknown context, on a failed read, and — demoted but present — on the one branch that
/// recommends against it.
@Suite("Land context on screen")
struct LandContextScreenTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AA01")!
    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-0000000000F1")!
    private static let spot = Coordinate(latitude: 37.7761, longitude: -122.4464)

    // MARK: - The composer

    @MainActor
    private static func addModel(api: any CypressAPI) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(spot, accuracyM: 8)),
            attribution: .anonymous(deviceID: deviceID)
        )
    }

    /// The whole optionality decision, as behaviour: the screen opens with no answer, the CTA does
    /// not wait for one, and the sentence above the chips says so without asking for anything.
    ///
    /// This is the assertion that would fail first if somebody later decided the field should be
    /// required. `VisitAddTreeModel.landContext` carries the argument in prose; this is the same
    /// argument in a form that breaks the build.
    @MainActor
    @Test("the composer opens with no answer and the CTA does not wait for one")
    func theQuestionIsOptional() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.addModel(api: api)
        subject.useLibraryImage(Self.photoData())

        #expect(subject.landContext == nil)
        #expect(subject.canAdd, "an unanswered land context must not block the add")
        #expect(subject.blockingReason == nil)
        #expect(
            VisitAddTreeCopy.land(nil)
                == "Where it stands will not be recorded. The tree goes on the map either way."
        )
    }

    /// Three chips, and the fourth permitted value is not among them. Both halves are the decision:
    /// the column keeps four so the 956 city rows that are neither street nor park stay storable, and
    /// the screen offers three because `.otherPublic` is a fact about which agency holds the parcel
    /// rather than something a person standing on it can see.
    @MainActor
    @Test("the picker offers three of the four the column permits, and never the fourth")
    func theFourthValueIsNotOffered() async throws {
        #expect(VisitAddTreeModel.offered == [.street, .cityPark, .privateProperty])
        #expect(!VisitAddTreeModel.offered.contains(.otherPublic))
        #expect(LandContext.allCases.count == 4, "the stored vocabulary must keep all four")

        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.addModel(api: api)
        // Not merely absent from a list the view reads — refused by the model, so a second call site
        // cannot store what this screen cannot offer.
        subject.chooseLandContext(.otherPublic)
        #expect(subject.landContext == nil)
    }

    /// Tapping the lit chip is the retraction. There is no separate "not sure" control on this row,
    /// because unlike the species picker there is no second screen to back out of.
    @MainActor
    @Test("choosing a chip sets it, and choosing the same one again clears it")
    func theChipTogglesTheAnswer() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.addModel(api: api)

        subject.chooseLandContext(.privateProperty)
        #expect(subject.landContext == .privateProperty)

        subject.chooseLandContext(.cityPark)
        #expect(subject.landContext == .cityPark, "a different chip replaces rather than adds")

        subject.chooseLandContext(.cityPark)
        #expect(subject.landContext == nil, "the lit chip is the retraction")
    }

    /// The write path from the chip to the column, through the screen rather than through a draft
    /// assembled by a test. `CityRecordTests.theDraftReachesTheColumn` proves the boundary carries
    /// it; this proves the *composer* puts it on the draft, which is the half that did not exist.
    @MainActor
    @Test("the chip reaches the column, and no answer writes no answer")
    func theComposerWritesWhatWasTapped() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let answered = Self.addModel(api: api)
        answered.useLibraryImage(Self.photoData())
        answered.chooseLandContext(.cityPark)
        let answeredID = try #require(await answered.add())
        let answeredTree = try await api.treeProfile(id: answeredID).tree
        #expect(answeredTree.statedLandContext == .cityPark)
        #expect(answeredTree.landContext?.source == .statedByContributor)

        // Far enough away that the 10 m dedupe does not refuse the second add.
        let silent = VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(
                pinnedFix: .located(
                    Coordinate(latitude: 37.7861, longitude: -122.4464),
                    accuracyM: 8
                )
            ),
            attribution: .anonymous(deviceID: Self.deviceID)
        )
        silent.useLibraryImage(Self.photoData())
        let silentID = try #require(await silent.add())
        let silentTree = try await api.treeProfile(id: silentID).tree
        #expect(silentTree.statedLandContext == nil, "no default may be written on the contributor's behalf")
        #expect(silentTree.landContext == nil)
    }

    // MARK: - The tree profile

    /// The card exists, on both variants, and names its source in the value rather than leaving a
    /// reader to guess whether somebody looked or Cypress read two columns.
    @Test("the profile shows the ground and says how it is known, on both arms")
    func theCardNamesItsSource() {
        let stated = Tree(
            id: Self.treeID,
            source: .community,
            coordinate: Self.spot,
            statedLandContext: .privateProperty
        )
        let statedCard = try? #require(
            TreeProfilePresentation(profile: TreeProfile(tree: stated)).landContextStat
        )
        #expect(statedCard?.label == "Where it stands")
        #expect(statedCard?.destination == nil, "nothing in the app corrects this, so it is not a door")
        #expect(cardText(statedCard) == "Private property · said by a contributor")

        let inferred = Tree(
            id: Self.treeID,
            source: .cityImport,
            coordinate: Self.spot,
            cityRecord: CityRecord(legalStatus: "DPW Maintained", caretaker: "Private")
        )
        let inferredCard = try? #require(
            TreeProfilePresentation(profile: TreeProfile(tree: inferred)).landContextStat
        )
        #expect(cardText(inferredCard) == "Street or sidewalk · read from the city record")
    }

    /// Nothing known, nothing drawn. A card headed `Where it stands` over an empty value would claim
    /// the record answers a question it has never been asked.
    @Test("an unanswered tree gets no card at all")
    func absentWhenNothingIsKnown() {
        let bare = Tree(id: Self.treeID, source: .community, coordinate: Self.spot)
        let presentation = TreeProfilePresentation(profile: TreeProfile(tree: bare))
        #expect(presentation.landContextStat == nil)
        #expect(!presentation.stats.contains { $0.id == "landContext" })
    }

    /// All four render, including the one the picker never offers — 956 city rows carry it, and a
    /// screen that could not draw a stored value would be a hole shaped exactly like the fourth case.
    @Test("every permitted value has words, including the one no picker offers")
    func allFourValuesRender() {
        for context in LandContext.allCases {
            let tree = Tree(
                id: UUID(),
                source: .community,
                coordinate: Self.spot,
                statedLandContext: context
            )
            let card = TreeProfilePresentation(profile: TreeProfile(tree: tree)).landContextStat
            let text = cardText(card) ?? ""
            #expect(!text.isEmpty, "no words for \(context.rawValue)")
            #expect(text.hasPrefix(LandContextCopy.noun(context)))
        }
        #expect(LandContextCopy.noun(.otherPublic) == "Other public land")
    }

    /// The reason this is a card and not a sixth `·`-joined fragment: the line it would have joined
    /// is already five elements long on a fully-described community tree.
    @Test("the provenance line was already full, which is why the card exists")
    func theSubtitleCouldNotCarryIt() throws {
        let tree = Tree(
            id: Self.treeID,
            source: .community,
            coordinate: Self.spot,
            placement: .contributorPlaced,
            statedLandContext: .privateProperty
        )
        let species = try Species(
            scientificName: "Hesperocyparis macrocarpa",
            commonName: "Monterey cypress",
            leafRetention: .evergreen
        )
        // A given name, so the H1 does not consume the common name and the line runs to its full
        // length — which is the state a well-described community tree actually reaches.
        let name = TreeName(treeID: Self.treeID, name: "Grandmother Cypress", givenBy: Self.deviceID)
        let subtitle = TreeProfilePresentation(
            profile: TreeProfile(tree: tree, activeName: name, species: species)
        ).subtitle

        #expect(subtitle.components(separatedBy: " · ").count == 5)
        #expect(
            !subtitle.contains(LandContextCopy.noun(.privateProperty)),
            "the ground belongs in the stat grid, not on a line that is already five elements long"
        )
    }

    // MARK: - The report · what a hazard on a private tree does

    private static func report(_ known: KnownLandContext?) -> ReportPresentation {
        ReportPresentation(selection: .hazard(.hangingOrBrokenLimb), landContext: known)
    }

    /// The default and the majority. Unknown is not private — it is unasked — and it draws screen 06
    /// exactly as every build before this one drew it.
    @Test("an unknown land context is the screen SCREENS.md draws, unchanged")
    func unknownIsTheStatusQuo() {
        let subject = Self.report(nil)
        #expect(subject.hazardHandoff == .city)
        #expect(subject.showsHazardBranch)
        #expect(subject.showsCallCTA)
        #expect(!subject.showsDemotedCall)
        #expect(subject.cityRecordPrivateNote == nil)
        #expect(subject.hazardPanelBody == ReportCopy.hazardPanelBody)
    }

    /// 311 is San Francisco's front door for city-owned anything, so all three public contexts answer
    /// the same way and the split is one bit rather than four cases.
    @Test("every public context keeps the city's number, however it is known")
    func publicLandKeepsTheCall() {
        for context in LandContext.allCases where context.isPublicLand {
            for source in KnownLandContext.Source.allCases {
                let subject = Self.report(KnownLandContext(context: context, source: source))
                #expect(subject.hazardHandoff == .city, "\(context.rawValue) via \(source.rawValue)")
                #expect(subject.showsCallCTA)
                #expect(subject.hazardPanelBody == ReportCopy.hazardPanelBody)
            }
        }
        #expect(
            LandContext.allCases.filter { !$0.isPublicLand } == [.privateProperty],
            "private property is the only value that is not the city's"
        )
    }

    /// The case the picker creates. A contributor stood at the tree and said it: an observation, so
    /// the panel changes what it recommends.
    @Test("a contributor's private property demotes the call and says who fixes it instead")
    func aStatedPrivateTreeChangesTheHandoff() {
        let subject = Self.report(
            KnownLandContext(context: .privateProperty, source: .statedByContributor)
        )
        #expect(subject.hazardHandoff == .notCityMaintained)
        #expect(subject.hazardPanelBody == ReportCopy.notCityMaintainedBody)
        #expect(!subject.showsCallCTA, "the amber CTA no longer leads")
        #expect(subject.showsDemotedCall, "but the number is still on the screen")
        #expect(subject.cityRecordPrivateNote == nil)

        // The body must say what Cypress cannot do rather than let a silence imply somebody is
        // handling it.
        #expect(ReportCopy.notCityMaintainedBody.contains("Cypress has no way to reach"))
        #expect(ReportCopy.callAnyway == "Call 311 anyway")
    }

    /// The rule that keeps a reading from acting like an observation. 11,153 of the 11,856 city rows
    /// that infer `.privateProperty` were decided by `caretaker` alone with no jurisdiction on file —
    /// the exact column E143 measured as the one that mislabels street trees — so the inference is
    /// shown and the call is left where it was.
    @Test("a city row read as private keeps the CTA and gains a line saying what was read")
    func anInferredPrivateTreeInformsButDoesNotRedirect() {
        let subject = Self.report(
            KnownLandContext(context: .privateProperty, source: .inferredFromCityRecord)
        )
        #expect(subject.hazardHandoff == .cityWithInferredPrivateLand)
        #expect(subject.showsCallCTA, "an inference may not withhold a safety call")
        #expect(!subject.showsDemotedCall)
        #expect(subject.hazardPanelBody == ReportCopy.hazardPanelBody, "the mocked body is unchanged")
        #expect(subject.cityRecordPrivateNote == ReportCopy.inferredPrivateLandNote)
        // Its grammar is the claim: a reading, not a fact about the world.
        #expect(ReportCopy.inferredPrivateLandNote.contains("reads as"))
        #expect(ReportCopy.inferredPrivateLandNote.contains("may not"))
    }

    /// **The property this whole change is designed around.** Shipping the picker must not make a
    /// safety report harder for any tree in the app: `Call 311` is reachable on every branch,
    /// including the one that recommends against it.
    @Test("the city's number is reachable on every branch there is")
    func theNumberIsNeverUnreachable() {
        var handoffs: Set<HazardHandoff> = []
        var candidates: [KnownLandContext?] = [nil]
        for context in LandContext.allCases {
            for source in KnownLandContext.Source.allCases {
                candidates.append(KnownLandContext(context: context, source: source))
            }
        }
        for candidate in candidates {
            let subject = Self.report(candidate)
            handoffs.insert(subject.hazardHandoff)
            #expect(
                subject.showsCallCTA || subject.showsDemotedCall,
                "no way to dial 311 for \(candidate?.context.rawValue ?? "unknown")"
            )
            #expect(subject.showsHazardBranch, "the branch itself never disappears")
        }
        #expect(handoffs.count == 3, "all three handoffs were exercised")
    }

    /// Whether the branch draws is still the chip alone. A hazard is a hazard on any ground, and a
    /// branch that vanished for a private tree would take the private reminder with it.
    @Test("no land context makes the hazard branch disappear")
    func theBranchStillTurnsOnTheChipAlone() {
        for candidate in [KnownLandContext(context: .privateProperty, source: .statedByContributor), nil] {
            #expect(!ReportPresentation(selection: .nothing, landContext: candidate).showsHazardBranch)
            #expect(!ReportPresentation(selection: .note(.needsWater), landContext: candidate).showsHazardBranch)
        }
    }

    /// End to end: a tree added through the composer with `Private property` tapped, read back by
    /// screen 06's own model through the real boundary. This is the one test that would have caught
    /// the defect E143 flagged, because it is the only one that goes chip → column → panel.
    @MainActor
    @Test("a tree marked private in the composer reaches screen 06's panel")
    func theChipReachesTheReportScreen() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let composer = Self.addModel(api: api)
        composer.useLibraryImage(Self.photoData())
        composer.chooseLandContext(.privateProperty)
        let id = try #require(await composer.add())

        let report = ReportModel(treeID: id, api: api)
        #expect(report.presentation.hazardHandoff == .city, "before the read, today's behaviour")
        await report.load()
        await report.select(hazard: .hangingOrBrokenLimb)

        #expect(report.landContext?.context == .privateProperty)
        #expect(report.presentation.hazardHandoff == .notCityMaintained)
        #expect(report.presentation.showsDemotedCall)
    }

    /// A read that fails falls back to the old screen, never to a suppressed call. The failure mode
    /// of the new code has to be the old code.
    @MainActor
    @Test("a tree the report cannot read draws the screen that shipped")
    func aFailedReadIsTheStatusQuo() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = ReportModel(treeID: UUID(), api: api)
        await subject.load()

        #expect(subject.landContext == nil)
        await subject.select(hazard: .uprooted)
        #expect(subject.presentation.hazardHandoff == .city)
        #expect(subject.presentation.showsCallCTA)
    }

    // MARK: - Helpers

    private func cardText(_ item: TreeProfilePresentation.StatItem?) -> String? {
        guard case let .prose(text)? = item?.value else { return nil }
        return text
    }

    /// A real JPEG header, which is what `VisitAddTreeModel.useLibraryImage` decodes before it stages
    /// anything. A 1×1 PNG is the smallest thing `UIImage` will actually accept.
    private static func photoData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
