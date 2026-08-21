import Foundation
import Testing
@testable import Cypress

/// Screen 01's bottom card, and the one word it must not say before it knows.
///
/// ── **The report (build 37)** ─────────────────────────────────────────────────────────────────
/// > first tree tapped after app open shows "Unidentified · 25 m N" for about a second, then
/// > corrects to the right species
///
/// `MapModel.select(_:)` builds the card from the pin — synchronously, so the tap is answered — and
/// starts `treeProfile(id:)` beside it. Between those two moments `MapCardSubject.profile` is nil,
/// and `title` used to fall through every profile-reading clause to the literal `"Unidentified"`.
/// That word is a claim about the species, so for as long as it was drawn the card was wrong rather
/// than merely incomplete. It reads as a cold-launch defect because the first read of a launch is
/// the slow one; the race is present on every tap.
///
/// These tests are about the *state*, not about the timing. `MapCardSubject` is a value, so the
/// unresolved card is a value that can be built.
@Suite("The map card never names a tree it has not read")
struct MapCardIdentityTests {

    private static let treeID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000001")!
    private static let speciesID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000002")!

    private static func pin(status: TreeStatus = .alive) -> TreePin {
        TreePin(
            id: treeID,
            coordinate: Coordinate(latitude: 37.7599, longitude: -122.4148),
            status: status,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: speciesID
        )
    }

    private static func species(commonName: String) throws -> Species {
        try Species(
            id: speciesID,
            scientificName: "Platanus × acerifolia",
            commonName: commonName,
            leafRetention: .deciduous
        )
    }

    private static func tree(speciesCurrentID: UUID?, status: TreeStatus = .alive) -> Tree {
        Tree(
            id: treeID,
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.7599, longitude: -122.4148),
            status: status,
            speciesCurrentID: speciesCurrentID,
            verificationState: .cityRecord
        )
    }

    // MARK: - The defect

    @Test("a card whose profile has not landed says nothing about the species")
    func anUnreadCardNamesNothing() {
        let subject = MapCardSubject(pin: Self.pin())

        #expect(subject.title == nil, "the card named a tree it had not read: \(subject.title ?? "")")
        #expect(subject.isAwaitingIdentity)
        // Named specifically, because this is the word the report saw and the only one that is a
        // claim rather than an absence.
        #expect(subject.title != "Unidentified")
        // The clauses that *are* facts about the pin are untouched: the card still appears at once
        // with its distance on it, which is what makes the tap feel answered.
        #expect(subject.badge == nil)
        #expect(subject.scientificName == nil)
    }

    @Test("the same card names the species the moment the profile lands")
    func aReadCardNamesTheSpecies() throws {
        let profile = TreeProfile(
            tree: Self.tree(speciesCurrentID: Self.speciesID),
            species: try Self.species(commonName: "London Plane")
        )
        let subject = MapCardSubject(pin: Self.pin(), profile: profile)

        #expect(subject.title == "London Plane")
        #expect(subject.isAwaitingIdentity == false)
    }

    /// The word is still the right answer, and this is the case that makes the change a *narrowing*
    /// rather than a deletion: a tree the database has read and has no species for really is
    /// unidentified, and the card still says so.
    @Test("a tree that was read and has no species is still called unidentified")
    func aReadTreeWithNoSpeciesIsStillUnidentified() {
        let profile = TreeProfile(tree: Self.tree(speciesCurrentID: nil), species: nil)
        let subject = MapCardSubject(pin: Self.pin(), profile: profile)

        #expect(subject.title == "Unidentified")
        #expect(subject.isAwaitingIdentity == false)
    }

    /// **`title`'s first clause, which nothing covered** (PR #102 review).
    ///
    /// This suite reached the species-common-name branch and the read-with-no-species branch and
    /// skipped the one a *named* tree takes — the clause that runs before either of them. A named
    /// tree is the case D15 exists for: the tree's own name wins over the species' common name.
    ///
    /// The second half is the guard on the guard. `activeName` is only an answer while it
    /// `isDisplayable`, and a retired or moderated-away name must fall through to the species
    /// rather than being drawn on the card — the same `status == .active && deletedAt == nil` rule
    /// `TreeProfilePresentation` and `MemorialPresentation` read it by.
    @Test("a named tree is called by its name, unless that name has been retired")
    func aNamedTreeUsesItsOwnName() throws {
        let species = try Self.species(commonName: "London Plane")
        func subject(nameStatus: TreeName.Status) -> MapCardSubject {
            MapCardSubject(
                pin: Self.pin(),
                profile: TreeProfile(
                    tree: Self.tree(speciesCurrentID: Self.speciesID),
                    activeName: TreeName(
                        treeID: Self.treeID,
                        name: "The Tea Tree at 46th",
                        givenBy: nil,
                        status: nameStatus
                    ),
                    species: species
                )
            )
        }

        #expect(
            subject(nameStatus: .active).title == "The Tea Tree at 46th",
            "a named tree fell through to its species' common name — D15 has it the other way round"
        )
        #expect(
            subject(nameStatus: .retired).title == "London Plane",
            """
            a retired name was still drawn on the card. `TreeName.isDisplayable` is what stops a \
            name a moderator removed from surviving on screen 01, and the card must fall through \
            to the species the way every other screen does.
            """
        )
    }

    /// ERRATA E107's rule, re-asserted here because it is the one identity that must survive an
    /// unresolved profile: a vacant site is read off the *pin*, so it is answered from the instant
    /// the card appears and never waits on anything.
    @Test("a vacant site is named from the pin, with no profile at all")
    func aVacantSiteNeedsNoRead() {
        let subject = MapCardSubject(pin: Self.pin(status: .vacantSite))

        #expect(subject.title == SiteCopy.cardTitle)
        #expect(subject.isAwaitingIdentity == false, "a site must not wait on a read it does not need")
    }
}
