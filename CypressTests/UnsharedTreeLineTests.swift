//
//  UnsharedTreeLineTests.swift
//  CypressTests
//
//  Round C3: the one line that tells the adder of a community tree that only they can see it. The
//  owner's words of 2026-11-15 replaced the approved "This tree is only on this phone…" lines, and
//  the owner's answer of the same day ("Keep today's note") draws no line when the phone does not
//  know whether the reader agreed to share, unless the service says the tree is not public.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Only you can see this tree")
struct UnsharedTreeLineTests {

    static let signedOut = "Only you can see this tree. Everyone can see it after you sign in."
    static let notSharing = "Only you can see this tree. Everyone can see it after you agree to share your tree records."

    static let spot = Coordinate(latitude: 37.7600, longitude: -122.5400)

    static func note(
        sharing: ContributionSharing?,
        addedByYou: Bool = true,
        isPublished: Bool? = nil,
        source: TreeSource = .community
    ) -> String? {
        TreeProfilePresentation(profile: TreeProfile(
            tree: Tree(source: source, coordinate: spot),
            addedByYou: addedByYou,
            isAddedHere: addedByYou,
            readerSharing: sharing,
            isPublished: isPublished
        )).onlyYouCanSeeNote
    }

    // MARK: - The rule

    /// The owner's two strings, one per state, and no line for a reader who agreed.
    ///
    /// Red-proof: swap the `.signedOut` and `.notSharing` arms of `onlyYouCanSeeNote` — red on both.
    @Test("signed out and not sharing each get their line; sharing gets none")
    func theStates() {
        #expect(Self.note(sharing: .signedOut) == Self.signedOut)
        #expect(Self.note(sharing: .notSharing) == Self.notSharing)
        #expect(Self.note(sharing: .sharing) == nil)
        #expect(Self.note(sharing: .sharing, isPublished: false) == nil, "a reader who agreed was told only they can see it")
    }

    /// When the phone holds no answer, nothing is said, unless the service says this tree is not
    /// public: then the reader is signed in and held back, which is the not-sharing line.
    ///
    /// Red-proof: return `TreeProfileCopy.onlyYouNotSharing` for every `.unknown` — red on the
    /// first expectation.
    @Test("an unknown answer draws no line unless the service says the tree is not public")
    func theUnknownState() {
        #expect(Self.note(sharing: .unknown) == nil)
        #expect(Self.note(sharing: .unknown, isPublished: true) == nil)
        #expect(Self.note(sharing: .unknown, isPublished: false) == Self.notSharing)
    }

    /// A tree the service says is public, a tree the reader did not add, and a city tree: none.
    @Test("no line on a public tree, on somebody else's tree, or on a city tree")
    func noLine() {
        #expect(Self.note(sharing: .signedOut, isPublished: true) == nil)
        #expect(Self.note(sharing: .notSharing, isPublished: true) == nil)
        #expect(Self.note(sharing: .signedOut, addedByYou: false) == nil)
        #expect(Self.note(sharing: .notSharing, addedByYou: false, isPublished: false) == nil)
        #expect(Self.note(sharing: .signedOut, source: .cityImport) == nil)
    }

    // MARK: - What the phone reads

    static let device = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3B01")!
    static let account = UUID(uuidString: "0E000000-0000-4000-8000-0000000C3B02")!

    static func add(_ api: LocalAPI, attribution: Attribution, at coordinate: Coordinate) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: coordinate,
            photoLocalPath: LocationCorrectionTests.capture("unshared"),
            attribution: attribution
        ))
    }

    /// The phone reads the sharing state beside the tree, in each of the four states.
    ///
    /// Red-proof: pass `.sharing` for `readerSharing` in `LocalAPI.treeProfile` — red on every
    /// state but sharing.
    @Test("the profile carries the reader's sharing state, and the line follows it")
    func thePhoneReadsTheState() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.device)

        let signedOutTree = try await Self.add(api, attribution: .anonymous(deviceID: Self.device), at: Self.spot)
        var profile = try await api.treeProfile(id: signedOutTree.id)
        #expect(profile.readerSharing == .signedOut)
        #expect(presented(profile).onlyYouCanSeeNote == Self.signedOut)

        // Declined. The sign-in adopts the device's trees, so the signed-out tree is the account's.
        try await api.linkAccount(deviceUUID: Self.device, userID: Self.account, provider: "apple", acceptsLicense: false)
        let signedIn = Attribution(userID: Self.account, deviceID: Self.device)
        let declinedTree = try await Self.add(api, attribution: signedIn, at: VisitPinAdjust.offset(Self.spot, northM: 40, eastM: 0))
        profile = try await api.treeProfile(id: declinedTree.id)
        #expect(profile.readerSharing == .notSharing)
        #expect(presented(profile).onlyYouCanSeeNote == Self.notSharing)

        // Agreed.
        try await api.linkAccount(deviceUUID: Self.device, userID: Self.account, provider: "apple", acceptsLicense: true)
        profile = try await api.treeProfile(id: declinedTree.id)
        #expect(profile.readerSharing == .sharing)
        #expect(presented(profile).onlyYouCanSeeNote == nil)

        // A sign-in that was not screen 15's: no record of the answer.
        try await api.restoreAccount(deviceUUID: Self.device, userID: Self.account)
        profile = try await api.treeProfile(id: declinedTree.id)
        #expect(profile.readerSharing == .unknown)
        #expect(presented(profile).onlyYouCanSeeNote == nil)
    }

    // MARK: - What the service says

    static let base = URL(string: "https://service.invalid/api/v1")!

    static func body(_ id: UUID, addedByYou: Bool, isPublished: Bool, sendsTree: Bool) -> String {
        let tree = sendsTree ? """
            {"id":"\(id.uuidString.lowercased())","externalRef":null,"idSpace":null,"source":"community",
             "coordinate":{"latitude":37.76,"longitude":-122.54},"address":null,"siteType":null,
             "neighborhoodID":null,"status":"alive","speciesCurrentID":null,"plantedYear":null,
             "dbhCityCmRange":null,"siteLineage":null,"verificationState":"unverified","placement":"gps",
             "cityRecord":null,"statedLandContext":null,"createdAt":"2026-09-20T00:00:00Z",
             "updatedAt":"2026-09-20T00:00:00Z","deletedAt":null}
            """ : "null"
        return """
            {"added_by_you":\(addedByYou),"community_tree":\(tree),"deletable_photo_ids":[],
             "is_published":\(isPublished),"own_photo_ids":[],"photo_count":0,"photos":[],
             "tree_uuid":"\(id.uuidString.lowercased())","visit_count":0}
            """
    }

    static func merged(sharing: ContributionSharing, isPublished: Bool, sendsTree: Bool) async throws -> TreeProfile {
        let id = UUID()
        let local = LocalDouble(profile: TreeProfile(
            tree: Tree(id: id, source: .community, coordinate: spot),
            addedByYou: true,
            isAddedHere: true,
            readerSharing: sharing
        ))
        let transport = ScriptedTransport()
        transport.answer(
            "GET /trees/\(id.uuidString)",
            with: Self.body(id, addedByYou: true, isPublished: isPublished, sendsTree: sendsTree)
        )
        let router = RoutedAPI(local: local, remote: RemoteAPI(baseURL: base, transport: transport, session: .shared))
        return try await router.refreshedTreeProfile(id: id)
    }

    /// The service's `is_published` reaches the profile only beside the tree it describes.
    ///
    /// Red-proof: carry `response.isPublished` unconditionally in `RemoteAPI.treeCommunityHalf` —
    /// red on "a false with no tree drew the line".
    @Test("the service's answer settles the unknown state, and only when it sent the tree")
    func theServiceSettlesIt() async throws {
        let held = try await Self.merged(sharing: .unknown, isPublished: false, sendsTree: true)
        #expect(held.isPublished == false)
        #expect(presented(held).onlyYouCanSeeNote == Self.notSharing)

        let noTree = try await Self.merged(sharing: .unknown, isPublished: false, sendsTree: false)
        #expect(noTree.isPublished == nil)
        #expect(presented(noTree).onlyYouCanSeeNote == nil, "a false with no tree drew the line")

        let published = try await Self.merged(sharing: .notSharing, isPublished: true, sendsTree: true)
        #expect(presented(published).onlyYouCanSeeNote == nil, "a public tree drew the line")
        #expect(published.readerSharing == .notSharing, "the merge dropped the phone's sharing state")
        #expect(published.isAddedHere, "the merge dropped isAddedHere")
    }

    // MARK: - Agreeing later

    /// A declined account adds a tree, then agrees on the You tab ("Share my tree records"). The
    /// tree's line goes once the phone records the yes. Driven through `AccountModel.acceptLicense`,
    /// the You tab's own call, on `LicenseAcceptanceTests`'s rig, so the write is the one the tab
    /// makes and not a copy of it.
    ///
    /// Red-proof: read `.notSharing` for every signed-in account in `ContributionSharing.init` —
    /// red on "the line stayed after agreeing".
    @MainActor
    @Test("agreeing later on the You tab removes the line from a tree added while declined")
    func agreeingLaterRemovesTheLine() async throws {
        let rig = try await LicenseAcceptanceTests.declinedPhone(
            http: LicenseAcceptanceTests.scripted(LicenseAcceptanceTests.ClaimAnswer(200))
        )
        let signedIn = Attribution(userID: LicenseAcceptanceTests.userID, deviceID: LicenseAcceptanceTests.deviceID)
        let tree = try await Self.add(rig.api, attribution: signedIn, at: Self.spot)

        var profile = try await rig.api.treeProfile(id: tree.id)
        #expect(profile.readerSharing == .notSharing, "precondition: the account declined")
        #expect(presented(profile).onlyYouCanSeeNote == Self.notSharing, "precondition: the line shows")

        await rig.model.acceptLicense()
        #expect(rig.model.licenseAcceptanceFailed == false, "the You tab's yes did not go through")
        #expect(rig.model.link?.acceptsLicense == true, "calibration: the phone recorded the yes")

        profile = try await rig.api.treeProfile(id: tree.id)
        #expect(profile.readerSharing == .sharing)
        #expect(presented(profile).onlyYouCanSeeNote == nil, "the line stayed after agreeing")
    }
}

/// A presentation with the default clock, for the tests above.
private func presented(_ profile: TreeProfile) -> TreeProfilePresentation {
    TreeProfilePresentation(profile: profile)
}
