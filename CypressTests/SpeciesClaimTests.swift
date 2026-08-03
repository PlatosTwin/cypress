import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// A species the contributor states — the add flow's newest field, and the one with the most ways to
/// go quietly wrong.
///
/// `VisitAddTreeModel.add()` deliberately sent **no** species for as long as the screen existed, and
/// the comment saying why was right about the case it was written for: BUILD-PLAN §15 forbids
/// fabricated botany, and a species this app inferred from a photograph would be exactly that. The
/// change this suite holds down is that a species a *person* states is a different fact with a
/// different author, and that it must arrive on the screen as a claim rather than as an
/// identification.
///
/// ── Every load-bearing assertion here reads the column or the rendered sentence ────────────────
/// `TreePlacementTests` records the reason and it applies verbatim: a test that asks the object it
/// just configured whether it holds the right value proves nothing about the write. So the two tests
/// that matter most go through the real screen, the real `addTree` and the real
/// `CommunityTreeStore.insert`, then read `species_current` back out of `community_trees` with SQL —
/// and the negative case is asserted as hard as the positive one, because a field that is always
/// written and a field that is never written both pass a suite that only checks one arm.
@Suite("Species claim")
struct SpeciesClaimTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD04")!
    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    /// `PinAdjustTests`' corner of the Mission. The seed is not attached in these tests, so the only
    /// trees inside any dedupe radius are the ones a test adds.
    private static let fix = Coordinate(latitude: 37.7599, longitude: -122.4148)

    private static let londonPlaneID = UUID(uuidString: "5EC10000-0000-4000-8000-00000000000A")!
    private static let coastLiveOakID = UUID(uuidString: "5EC10000-0000-4000-8000-00000000000B")!

    private static func londonPlane() throws -> Species {
        try Species(
            id: londonPlaneID,
            scientificName: "Platanus × acerifolia",
            commonName: "London Plane",
            leafRetention: .deciduous
        )
    }

    private static func coastLiveOak() throws -> Species {
        try Species(
            id: coastLiveOakID,
            scientificName: "Quercus agrifolia",
            commonName: "Coast Live Oak",
            leafRetention: .evergreen
        )
    }

    @MainActor
    private static func model(api: any CypressAPI) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(fix, accuracyM: 24)),
            attribution: attribution
        )
    }

    /// A real 1×1 JPEG: the model decodes the frame before it accepts it, so a fixture that is not an
    /// image never reaches the path that ships.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    /// The stored string, exactly as SQLite holds it — not `Tree.speciesCurrentID`, which is a decode
    /// of it, and not the resolved `Species`, which needs a seed this store does not attach.
    private static func storedSpecies(of id: UUID, in store: CypressStore) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT species_current FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind(id.uuidString, forName: ":id")
            return try statement.fetchOne { try $0.stringIfPresent("species_current") } ?? nil
        }
    }

    // MARK: - What actually lands in the column

    /// **The assertion this round exists for.**
    ///
    /// A named species, through the screen, through `TreeDraft`, through `addTree`, through
    /// `CommunityTreeStore.insert` — and then read back with SQL. Every one of those layers existed
    /// already and every one of them could have dropped the claim on the floor, leaving a model that
    /// says the right thing about a row that says nothing.
    @MainActor
    @Test("a species the contributor named is on the row, read back out of the column")
    func theStoredSpeciesIsTheOneNamed() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        subject.beginPickingSpecies()
        subject.chooseSpecies(try Self.londonPlane())
        #expect(subject.phase == .composing, "picking a species left the screen on the picker")

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await Self.storedSpecies(of: id, in: store)

        let expected = Self.londonPlaneID.uuidString
        #expect(
            stored?.caseInsensitiveCompare(expected) == .orderedSame,
            "community_trees.species_current holds \(stored ?? "NULL"), not \(expected)"
        )
        // And the decode agrees with the column, which is what every reader downstream actually uses.
        let decoded = try await api.treeProfile(id: id).tree.speciesCurrentID
        #expect(decoded == Self.londonPlaneID, "the row decoded to \(String(describing: decoded))")
    }

    /// The other arm, and it is not a formality: the change under test made `add()` start sending a
    /// field it had always omitted, and a field bound from the wrong place — or bound to a stale
    /// draft — writes *something* for everybody. The fast path has to still write NULL.
    @MainActor
    @Test("a tree added without naming a species stores no species at all")
    func noSpeciesNamedStoresNull() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        #expect(subject.species == nil, "the draft started with a species nobody chose")

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await Self.storedSpecies(of: id, in: store)

        #expect(stored == nil, "an unnamed tree stored the species \(stored ?? "")")
        #expect(try await api.treeProfile(id: id).tree.speciesCurrentID == nil)
    }

    /// A retraction has to reach the column too, and this is the case that would survive a naive
    /// implementation: the reader names a species, thinks better of it, and the row must not keep the
    /// statement its author withdrew.
    @MainActor
    @Test("naming a species and then saying I'm not sure stores no species")
    func aRetractedClaimIsNotStored() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        subject.beginPickingSpecies()
        subject.chooseSpecies(try Self.coastLiveOak())
        subject.beginPickingSpecies()
        subject.skipSpecies()
        #expect(subject.species == nil, "the withdrawn claim is still on the draft")

        let id = try #require(await subject.add(), "the add returned no tree")
        #expect(try await Self.storedSpecies(of: id, in: store) == nil, "the retracted species was stored")
    }

    // MARK: - The screen's own state machine

    /// Backing out of the picker is not an answer, and saying "I'm not sure" is. The two controls sit
    /// on the same screen and a model that ran them through one path would silently turn a mistaken
    /// tap on the back chevron into a retraction.
    @MainActor
    @Test("leaving the picker by the back control keeps the species; I'm not sure clears it")
    func backAndNotSureAreDifferentAnswers() async throws {
        let subject = Self.model(api: LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID))
        let oak = try Self.coastLiveOak()

        subject.chooseSpecies(oak)
        subject.beginPickingSpecies()
        subject.cancelPickingSpecies()
        #expect(subject.species?.id == oak.id, "backing out of the picker discarded the species")
        #expect(subject.phase == .composing)

        subject.beginPickingSpecies()
        subject.skipSpecies()
        #expect(subject.species == nil, "I'm not sure left the claim on the draft")
    }

    /// The CTA must not be live while the picker is up, for `canAdd`'s existing reason: one model,
    /// one draft, and a stale reference to the footer could otherwise write the tree while the reader
    /// is in the middle of deciding what it is.
    @MainActor
    @Test("the add is refused while the picker is up")
    func theCTAIsDeadDuringThePick() async throws {
        let subject = Self.model(api: LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID))
        subject.useLibraryImage(try Self.jpeg())
        #expect(subject.canAdd, "the screen was not ready before the picker opened")

        subject.beginPickingSpecies()
        #expect(!subject.canAdd, "the CTA stayed live with the species picker on screen")

        subject.cancelPickingSpecies()
        #expect(subject.canAdd, "the CTA did not come back after the picker closed")
    }

    /// A species is never a gate. This is the whole "optional, and deliberately so" decision stated
    /// as an assertion, so that a later round that makes it required has to delete a test that says
    /// why it was not.
    @MainActor
    @Test("no species is not a blocking reason and never disables the add")
    func theSpeciesIsNeverAGate() async throws {
        let subject = Self.model(api: LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID))
        subject.useLibraryImage(try Self.jpeg())

        #expect(subject.species == nil)
        #expect(subject.canAdd, "an unnamed tree could not be added")
        let reason = subject.blockingReason
        #expect(reason == nil, "an unnamed tree was blocked with: \(reason ?? "")")
    }

    // MARK: - The words on the add screen

    /// The composer's sentence has to attribute before it names, and it has to say what the app is
    /// *not* doing. A sentence that only named the species would read as the app agreeing.
    @Test("the add screen states the species as the contributor's claim, not as an identification")
    func theAddScreenSentenceAttributes() throws {
        let named = VisitAddTreeCopy.species(try Self.londonPlane())

        #expect(named.contains("your claim"), "the sentence does not say whose claim it is: \(named)")
        #expect(named.contains("London Plane"), "the sentence does not name the species: \(named)")
        #expect(
            named.contains("not as a confirmed identification"),
            "the sentence does not say what it is refusing to claim: \(named)"
        )
        // Attribution before botany. See `VisitAddTreeCopy.species` for why the word order is the
        // design and not an accident.
        let claimAt = try #require(named.range(of: "your claim")).lowerBound
        let speciesAt = try #require(named.range(of: "London Plane")).lowerBound
        #expect(claimAt < speciesAt, "the species is named before the attribution: \(named)")

        // And the empty form does not apologize for being empty.
        let unnamed = VisitAddTreeCopy.species(nil)
        for word in ["missing", "required", "should", "incomplete", "please"] {
            let sentence = unnamed
            #expect(
                !sentence.lowercased().contains(word),
                "the no-species sentence pressures the contributor with “\(word)”: \(sentence)"
            )
        }
    }

    // MARK: - The claim, on the tree profile

    private static func profile(source: TreeSource, species: Species?) -> TreeProfile {
        TreeProfile(
            tree: Tree(
                source: source,
                coordinate: fix,
                speciesCurrentID: species?.id,
                verificationState: source == .cityImport ? .cityRecord : .unverified
            ),
            species: species
        )
    }

    private static func presentation(source: TreeSource, species: Species?) -> TreeProfilePresentation {
        TreeProfilePresentation(profile: profile(source: source, species: species))
    }

    /// **The end of the path.** A claim that reaches the column and then renders as a plain species
    /// name is a claim the app has quietly promoted to an identification, which is the single failure
    /// this whole change had to avoid.
    @Test("a contributor's species is attributed on the profile's provenance line")
    func theProfileSaysWhoNamedIt() throws {
        let subject = Self.presentation(source: .community, species: try Self.londonPlane())

        #expect(subject.speciesClaimNote == "species named by a contributor")
        let subtitle = subject.subtitle
        #expect(
            subtitle.contains("species named by a contributor"),
            "the subtitle does not attribute the species: \(subtitle)"
        )
        // It is on the same line as the rest of the provenance, not a badge somewhere else.
        #expect(subtitle.contains("community-added, unverified"), "the subtitle lost its provenance: \(subtitle)")
        // Coarse to fine: record, then species, then coordinate.
        let provenanceAt = try #require(subtitle.range(of: "community-added, unverified")).lowerBound
        let claimAt = try #require(subtitle.range(of: "species named by a contributor")).lowerBound
        let placementAt = try #require(subtitle.range(of: "position from GPS")).lowerBound
        #expect(provenanceAt < claimAt && claimAt < placementAt, "the provenance line is out of order: \(subtitle)")
    }

    /// The two states that must print nothing, for opposite reasons: the city's species is the
    /// city's and `provenance` already says so, and a community row with no species has nobody to
    /// attribute. Both matter — a note that appeared on a city tree would be a lie about the seed.
    @Test("the claim note is printed for nothing else")
    func nothingElseIsAttributed() throws {
        let cityWithSpecies = Self.presentation(source: .cityImport, species: try Self.coastLiveOak())
        #expect(cityWithSpecies.speciesClaimNote == nil, "an inventory row was attributed to a contributor")
        let citySubtitle = cityWithSpecies.subtitle
        #expect(!citySubtitle.contains("named by"), "an inventory row's subtitle attributes: \(citySubtitle)")

        let communityNoSpecies = Self.presentation(source: .community, species: nil)
        #expect(communityNoSpecies.speciesClaimNote == nil, "a tree with no species attributed one")
        let bareSubtitle = communityNoSpecies.subtitle
        #expect(!bareSubtitle.contains("named by"), "a tree with no species attributes one: \(bareSubtitle)")
    }

    // MARK: - "After", not only "at the same time"

    /// A store with the real catalog attached. `claimSpecies` resolves the species before it writes
    /// it — `community_trees.species_current` can carry no foreign key, because the `species` table is
    /// in an ATTACHed database — so these cases need the seed the add-flow cases do not.
    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Where the seeded cases stand.
    ///
    /// **Not `fix`.** The other tests here run against a store with no seed attached, so the Mission
    /// corner is empty and anything may be added there. With the real catalog attached the seed's
    /// 195,309 street trees come with it, and that corner has several inside the 10 m dedupe —
    /// `addTree` correctly refuses, and the first version of these tests failed with `add() → nil`,
    /// which is the API doing its job rather than a defect. This is a point in the Pacific west of
    /// Ocean Beach: the seed is the city's *street*-tree inventory, so there is nothing within any
    /// dedupe radius of it and the only trees these tests contend with are their own.
    private static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    /// Adds a tree with no species, the way the fast path does.
    @MainActor
    private static func addUnnamedTree(through api: LocalAPI, at spot: Coordinate) async throws -> UUID {
        let subject = VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(spot, accuracyM: 24)),
            attribution: attribution
        )
        subject.useLibraryImage(try Self.jpeg())
        return try #require(await subject.add(), "the add returned no tree: \(subject.phase)")
    }

    /// **The "after" half of the request, end to end**, and it goes through the same species search
    /// the picker uses rather than a hand-written uuid — so a catalog that stopped answering would
    /// fail this test rather than leaving it green against a constant.
    @MainActor
    @Test("a species named after the tree was added lands on the row and reads as a claim")
    func aSpeciesCanBeNamedAfterTheAdd() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let id = try await Self.addUnnamedTree(through: api, at: Self.offshore)
        #expect(try await Self.storedSpecies(of: id, in: store) == nil, "the tree was added with a species")

        let matches = try await api.searchSpecies(query: "Platanus", limit: SpeciesPickModel.resultLimit)
        let chosen = try #require(matches.first, "the catalog answered no Platanus")

        let updated = try await api.claimSpecies(treeID: id, speciesID: chosen.id)
        #expect(updated.speciesCurrentID == chosen.id)

        let stored = try await Self.storedSpecies(of: id, in: store)
        let expected = chosen.id.uuidString
        #expect(
            stored?.caseInsensitiveCompare(expected) == .orderedSame,
            "community_trees.species_current holds \(stored ?? "NULL"), not \(expected)"
        )

        // And it arrives on the screen attributed, by the same line the at-the-same-time path uses.
        let presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        let subtitle = presentation.subtitle
        #expect(subtitle.contains("species named by a contributor"), "the claim is unattributed: \(subtitle)")
        // The offer is gone: a species is claimed once, and correcting it needs the assertion chain.
        #expect(!presentation.offersSpeciesClaim, "the screen still offers to name a species it has")
    }

    /// First claim wins, and the second is refused rather than swallowed. This is the rule
    /// `species_assertions` would otherwise carry, kept honestly at the one place that can keep it.
    @MainActor
    @Test("a second species claim is refused and the first one survives")
    func theFirstClaimWins() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let id = try await Self.addUnnamedTree(through: api, at: VisitPinAdjust.offset(Self.offshore, northM: 300, eastM: 0))

        let plane = try #require(await api.searchSpecies(query: "Platanus", limit: 5).first)
        let oak = try #require(
            await api.searchSpecies(query: "Quercus", limit: 5).first { $0.id != plane.id },
            "the catalog answered no second species"
        )

        _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)
        await #expect(throws: APIError.conflict) {
            _ = try await api.claimSpecies(treeID: id, speciesID: oak.id)
        }

        let stored = try await Self.storedSpecies(of: id, in: store)
        let kept = plane.id.uuidString
        #expect(
            stored?.caseInsensitiveCompare(kept) == .orderedSame,
            "the second claim overwrote the first: the row holds \(stored ?? "NULL")"
        )
    }

    /// A city row's species is the city's, in a read-only database. `.forbidden` and not `.notFound`:
    /// the tree is real, and the two refusals say different things on screen.
    @Test("naming the species on a city inventory tree is refused as forbidden, not as missing")
    func aCityTreeRefusesTheClaim() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let cityTreeID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare(
                "SELECT uuid FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NULL LIMIT 1"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuidIfPresent("uuid") } ?? nil
        }
        let target = try #require(cityTreeID, "the seed has no trees")
        let species = try #require(await api.searchSpecies(query: "Quercus", limit: 5).first)

        await #expect(throws: APIError.forbidden) {
            _ = try await api.claimSpecies(treeID: target, speciesID: species.id)
        }
        // And a tree that is in neither table is a different answer.
        await #expect(throws: APIError.notFound) {
            _ = try await api.claimSpecies(treeID: UUID(), speciesID: species.id)
        }
    }

    /// The offer and the boundary agree about who may do this. A control that appeared where
    /// `claimSpecies` would refuse is the defect `VisitAddTreeModel.canAdd` exists to avoid.
    @Test("the profile offers the claim exactly where the boundary would accept one")
    func theOfferMatchesTheRefusals() throws {
        #expect(Self.presentation(source: .community, species: nil).offersSpeciesClaim)
        #expect(!Self.presentation(source: .cityImport, species: nil).offersSpeciesClaim)
        #expect(!Self.presentation(source: .community, species: try Self.londonPlane()).offersSpeciesClaim)

        // A memorial and a vacant site refuse every other write on this screen (E95); naming the
        // species of a tree that is not there is the same kind of claim.
        for status in [TreeStatus.removed, .vacantSite] {
            let gone = TreeProfilePresentation(
                profile: TreeProfile(
                    tree: Tree(source: .community, coordinate: Self.fix, status: status)
                )
            )
            #expect(!gone.offersSpeciesClaim, "a \(status.rawValue) record offered a species claim")
        }
    }

    /// Three refusals, three sentences. One message for all of them would tell somebody their
    /// contribution failed when in fact somebody else's succeeded.
    @Test("each refusal says which refusal it was")
    func theRefusalsAreDistinguishable() {
        let conflict = TreeProfileCopy.speciesClaimFailure(.conflict)
        let forbidden = TreeProfileCopy.speciesClaimFailure(.forbidden)
        let missing = TreeProfileCopy.speciesClaimFailure(.notFound)

        #expect(Set([conflict, forbidden, missing]).count == 3, "two refusals share a sentence")
        #expect(conflict.contains("already"), "\(conflict)")
        #expect(forbidden.contains("city"), "\(forbidden)")
        // The conflict names whose claim stands rather than the app's own limit. It used to end on
        // "which this app cannot record yet", which stopped being true at AppSchema v14: a
        // correction is recordable, and what a second claimant may not do is make one over somebody
        // else's statement without asking (#86/#124).
        #expect(conflict.contains("corrected"), "\(conflict)")
        #expect(!conflict.contains("cannot"), "the refusal still pleads a limit that is gone: \(conflict)")
    }

    // MARK: - On real pixels

    /// Renders screen 03 over a real community tree and writes the PNGs, so the claim can be
    /// *looked at* rather than only asserted on.
    ///
    /// **This exists because the simulator could not be used for it.** The deep-link harness case
    /// (`CYPRESS_SCREEN=speciesClaim`) builds the right record and pushes the right screen, and the
    /// system location alert lands on top of the identity block and cannot be dismissed by injected
    /// input. `ScreenSweepShots.capture` renders the same `TreeProfileView` through a real
    /// `UIHostingController` in a real off-screen window, over a real `LocalAPI` reading a real
    /// store, with no SpringBoard in the way.
    ///
    /// Both states are drawn, because the pair is the point: one profile carrying a claim and one
    /// offering to take one.
    @MainActor
    @Test("the claim and the offer are drawn, and the files are written to be looked at")
    func theClaimIsDrawn() async throws {
        let store = try await Self.seededStore()
        // An explicit photo directory: an in-memory store's database URL is `:memory:`, so the
        // default lands on `/Photos` and the write fails on a read-only volume. The other tests here
        // never noticed because none of them stages a file.
        let photos = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-species-shots-\(UUID().uuidString)", isDirectory: true)
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photos)

        let claimed = try await api.debugAddCommunityTree(near: Self.offshore, speciesQuery: "Platanus")
        let unclaimed = try await api.debugAddCommunityTree(
            near: VisitPinAdjust.offset(Self.offshore, northM: 300, eastM: 0),
            speciesQuery: nil
        )
        print("SHOT DIR \(ScreenSweepShots.outputDirectory.path)")

        #expect(await ScreenSweepShots.sweep("e141-species-claimed") {
            NavigationStack { TreeProfileView(treeID: claimed, api: api) }.environment(AppRouter())
        })
        #expect(await ScreenSweepShots.sweep("e141-species-unclaimed") {
            NavigationStack { TreeProfileView(treeID: unclaimed, api: api) }.environment(AppRouter())
        })

        // The pixels are the point, but a shot test that only wrote files would pass over a blank
        // screen. These are the two sentences the images have to contain.
        let claimedSubtitle = TreeProfilePresentation(profile: try await api.treeProfile(id: claimed)).subtitle
        #expect(claimedSubtitle.contains("species named by a contributor"), "\(claimedSubtitle)")
        let offer = TreeProfilePresentation(profile: try await api.treeProfile(id: unclaimed))
        #expect(offer.offersSpeciesClaim)
    }

    /// The property `placementNote`'s own suite asserts by name — "neither placement line evaluates
    /// the coordinate it describes" — applied to this line, because it is the property the whole
    /// design rests on. Naming an author is provenance. Grading them is a warning, and a warning on
    /// the one arm that can be marked is what turns a contribution into a suspect contribution.
    @Test("the claim line names an author and does not judge one")
    func theClaimLineDoesNotEvaluate() {
        let line = TreeProfilePresentation.speciesNamedByContributor.lowercased()
        for word in [
            "unconfirmed", "unverified", "guess", "maybe", "possibly", "may be", "claimed",
            "not confirmed", "uncertain", "doubtful", "alleged", "?"
        ] {
            #expect(!line.contains(word), "the species claim line evaluates the claim with “\(word)”: \(line)")
        }
        // It does name the author, which is the entire point of printing it.
        #expect(line.contains("contributor"))
        // "a contributor", not "the contributor": `community_trees` records no author, so the line
        // must not imply which person is meant.
        #expect(!line.contains("the contributor"), "the line implies an author the row does not record")
    }
}
