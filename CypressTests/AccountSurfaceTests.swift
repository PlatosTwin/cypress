//
//  AccountSurfaceTests.swift
//  CypressTests
//
//  ERRATA **E131** — the account the app creates and then never mentions again, the consent it
//  collects and throws away, and the private reminder it saves into a drawer with no handle.
//
//  ── Why these tests are shaped the way they are ────────────────────────────────────────────
//  Every defect this suite covers is a *wiring* defect. The pieces underneath were all correct and
//  all tested: `AccountAskModel` assembled the right request, `claimDevice` moved the right rows,
//  `LocalAPI.deleteAccount()` implemented RULINGS R3 exactly, `privateReminders(limit:)` had the
//  right one-owner query. What was missing was a caller. So a test that asserts a piece works
//  passes on the broken app and proves nothing, which is the same trap `FailedReadTests` records.
//
//  Two rules follow, and each is used below:
//
//  1. **Assert where a value is read back, never where it is sent.** A test that watches the consent
//     flag reach `claimDevice` would pass on the broken build — the flag reached the *call site* and
//     died there. `consentSurvivesToTheAccount` reads it out of `app_state` afterwards instead, and
//     goes through `RootView.accountLink()` rather than around it, because the composition root is
//     where the discard was.
//  2. **Where a control's only symptom is what is drawn, compare the pictures.** The You tab's
//     account block cannot be checked by asking a model a question; the model was already answering
//     correctly to nobody. `theYouTabDrawsWhoIsSignedIn` renders the tab twice and requires the two
//     images to differ, which is `FailedReadTests`' method for exactly this reason.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("The account, and the records only it can read (E131)")
struct AccountSurfaceTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E1")!

    /// A `DataLayer` over an in-memory store, assembled the way `DataLayer.boot` assembles a real
    /// one — `AccountLinkTests` and `DeviceClaimTests` wire theirs identically. Throwaway by
    /// construction, which is what a suite that deletes accounts needs.
    private static func bootInMemory() async throws -> DataLayer {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        return DataLayer(store: store, api: api, outbox: outbox, deviceID: deviceID)
    }

    /// A community-added tree, so a reminder has something real to be about (`savePrivateReminder`
    /// refuses an unknown tree).
    private static func addTree(_ data: DataLayer) async throws -> Tree {
        try await data.api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-e130-\(UUID().uuidString).jpg",
            attribution: .anonymous(deviceID: deviceID)
        ))
    }

    // MARK: - 1. The consent screen 15 collects

    /// **The register this is written in matters.** The broken build's failure was invisible one
    /// layer up: `AccountAskModel` built an `AccountLinkRequest` carrying `acceptsLicense`, the
    /// composition root's handler read `_ = request`, and `claimDevice` was called with an id and
    /// nothing else. Watching the request arrive at the closure would have passed. This drives the
    /// same closure the visit flow is handed and then asks the *store* what it knows.
    @Test("the licence answer travels all the way to the account and can be read back")
    func consentSurvivesToTheAccount() async throws {
        let data = try await Self.bootInMemory()
        let link = RootView(data: data).accountLink()

        // Declined. `AccountAskModel` leaves the checkbox ungated on the explicit grounds that the
        // answer travels on the request; this is that sentence, checked.
        try await link(AccountLinkRequest(provider: .email, acceptsLicense: false))

        let declined = try #require(await data.api.accountLink())
        #expect(declined.provider == AccountAskProvider.email.rawValue, "the provider was discarded")
        #expect(declined.licenseVersion == nil, "a declined licence was recorded as agreed to")
        #expect(declined.acceptsLicense == false)

        // Accepted, on a second link by the same person. The record must move, not accumulate.
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))

        let accepted = try #require(await data.api.accountLink())
        #expect(accepted.provider == AccountAskProvider.apple.rawValue)
        #expect(accepted.licenseVersion == LicenseConsent.currentVersion, "the licence consent was discarded")
        #expect(accepted.acceptsLicense)

        // And it is on disk, not in the actor: `DataLayer.boot` reads `app_state` at launch, so a
        // consent that lived only in memory would be gone by the next run.
        #expect(try await data.store.appState(.accountLicenseVersion) == LicenseConsent.currentVersion)
        #expect(try await data.store.appState(.accountProvider) == AccountAskProvider.apple.rawValue)
    }

    /// Declining after accepting must clear the record rather than leave the old agreement standing.
    @Test("re-linking after a decline does not leave the previous agreement on the account")
    func decliningClearsAnEarlierConsent() async throws {
        let data = try await Self.bootInMemory()
        let link = RootView(data: data).accountLink()

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: false))

        let record = try #require(await data.api.accountLink())
        #expect(record.acceptsLicense == false, "the earlier consent outlived the tap that withdrew it")
        #expect(try await data.store.appState(.accountLicenseVersion) == nil)
    }

    // MARK: - 2. Signing out

    /// **The defect this guards is the one sign-out invites.** A local account has no credential:
    /// `accountLink` mints a `UUID` when it finds none. A sign-out that forgot the id would hand the
    /// next sign-in a *different* account, leaving every reminder and favourite the first one owned
    /// readable by no query and removable by no deletion — the unreachable litter RULINGS R3 refuses
    /// to create. So the assertion is not "signing out worked"; it is that the same person gets
    /// their own records back.
    @Test("signing out keeps every record, and signing in again returns to the same account")
    func signOutIsNotAQuietDeletion() async throws {
        let data = try await Self.bootInMemory()
        let tree = try await Self.addTree(data)
        let link = RootView(data: data).accountLink()

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        let signedInAs = try #require(await data.api.userID)

        // A reminder owned by the account, which is the record most at risk: nobody but its owner
        // can read one, so an orphaned one is invisible rather than merely wrong.
        _ = try await data.api.savePrivateReminder(PrivateReminder(
            owner: .user(signedInAs),
            treeID: tree.id,
            category: .uprooted
        ))
        #expect(try await data.api.privateReminders().count == 1)

        let account = AccountModel(api: data.api)
        await account.load()
        #expect(account.isSignedIn)
        #expect(account.reminders.count == 1)

        await account.signOut()
        #expect(account.isSignedIn == false)
        #expect(await data.api.userID == nil)
        // The row is still there; it is the *reader* that changed, because this device is no longer
        // that account. Nothing was deleted.
        #expect(account.reminders.isEmpty, "a signed-out device read the account's private reminders")
        #expect(try await Self.reminderRowCount(data.store) == 1, "signing out deleted a reminder")

        // Back in — and it has to be the same account, or the reminder above is stranded.
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        #expect(await data.api.userID == signedInAs, "signing back in minted a rival account and stranded the first")

        await account.load()
        #expect(account.reminders.count == 1, "the account's reminder did not come back with the account")
    }

    // MARK: - 3. Deleting

    /// R3's deletion, run from the surface that ships it rather than from `LocalAPI` directly —
    /// `AccountDeletionTests` already covers the rows, and what was missing was a caller.
    @Test("deleting the account from the You tab removes the reminders and the signed-in state")
    func deletionRunsFromTheShippingSurface() async throws {
        let data = try await Self.bootInMemory()
        let tree = try await Self.addTree(data)
        let link = RootView(data: data).accountLink()

        try await link(AccountLinkRequest(provider: .google, acceptsLicense: true))
        let signedInAs = try #require(await data.api.userID)
        _ = try await data.api.savePrivateReminder(PrivateReminder(
            owner: .user(signedInAs),
            treeID: tree.id,
            category: .hangingOrBrokenLimb
        ))

        let account = AccountModel(api: data.api)
        await account.load()
        let outcome = try #require(await account.deleteAccount(.default))

        #expect(outcome.deletedPrivateReminders == 1, "R3's half of the deletion did not run")
        #expect(account.isSignedIn == false)
        #expect(account.reminders.isEmpty)
        #expect(try await Self.reminderRowCount(data.store) == 0)
        #expect(try await data.store.appState(.accountLicenseVersion) == nil, "a deleted account's consent record survived")
    }

    /// A deleted account must not be resumable. `signedOutUserID` exists so a sign-out can be
    /// undone; if deletion left it behind, the next sign-in would resume an account whose rows
    /// `AccountDeletion` had already emptied — signed in as a ghost.
    @Test("a deleted account cannot be signed back into")
    func deletionIsNotResumable() async throws {
        let data = try await Self.bootInMemory()
        let link = RootView(data: data).accountLink()

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        let deleted = try #require(await data.api.userID)
        try await data.api.signOut()
        // Signed out, so the id is standing by to be resumed — exactly the state deletion has to
        // clear. Signing back in to delete it is how a person would actually reach this.
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        #expect(await data.api.userID == deleted)

        _ = try await data.api.deleteAccount(.eraseEverything)
        #expect(try await data.api.resumableUserID() == nil, "a deleted account was left resumable")

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        #expect(await data.api.userID != deleted, "signing in after a deletion resumed the deleted account")
    }

    // MARK: - 4. R3's copy, which is the defence

    /// R3: "deleting more than someone expected is the failure mode this ruling creates, and copy is
    /// the whole defence against it". With two doors the defence moves but does not weaken: each
    /// door states its own behaviour, and the clause about the records that go **either way** is
    /// hoisted out of both so it cannot be escaped by choosing.
    ///
    /// This test used to assert that `whatHappens` arrived whole inside one dialog message. That
    /// constant no longer exists and the assertion is deliberately not being reconstructed against
    /// its replacement — see `AccountDeletionCopy` for why welding the shared clause onto each door
    /// would bury the difference between them, which is now the thing a reader most needs.
    @Test("both doors state their own behaviour and the shared clause escapes neither")
    func bothDoorsAreStatedBeforeEitherIsChosen() {
        // What each door does to the contributions, in its own paragraph.
        #expect(AccountDeletionCopy.leaveRecordsBody.contains("stay on the trees"))
        #expect(AccountDeletionCopy.leaveRecordsBody.contains("photo votes"))
        #expect(AccountDeletionCopy.eraseEverythingBody.contains("deleted"))
        #expect(AccountDeletionCopy.eraseEverythingBody.contains("photographs are removed"))
        // The consequence a person would not think of, which R3's reasoning requires be told
        // rather than discovered: withdrawing a vote can change which photograph a stranger sees.
        #expect(AccountDeletionCopy.eraseEverythingBody.contains("different one"))

        // R3's other half, unconditional and outside both doors.
        #expect(AccountDeletionCopy.personalRecords.hasPrefix("Either way"))
        #expect(AccountDeletionCopy.personalRecords.contains("reminders"))
        #expect(AccountDeletionCopy.personalRecords.contains("favorites"))

        // The two doors must not read as the same promise, or the choice is decorative.
        #expect(AccountDeletionCopy.leaveRecordsBody != AccountDeletionCopy.eraseEverythingBody)
        #expect(AccountDeletionCopy.leaveRecordsTitle != AccountDeletionCopy.eraseEverythingTitle)
    }

    /// The last tap names the door it takes. This is the whole of the defence against reaching the
    /// destructive door by momentum, so it is asserted rather than left to a reading of the view.
    @Test("the confirming button's label differs by door and names erasure on the destructive one")
    func theConfirmingLabelNamesItsDoor() {
        let safe = AccountDeletionCopy.confirmAction(for: .leaveRecords)
        let destructive = AccountDeletionCopy.confirmAction(for: .eraseEverything)
        #expect(safe != destructive, "one label on both doors makes the choice a forgettable setting")
        #expect(destructive.lowercased().contains("erase"))
        #expect(!safe.lowercased().contains("erase"))
        // The safe door is the default, stated in one place and read from it everywhere.
        #expect(AccountDeletionChoice.default == .leaveRecords)
        #expect(AccountDeletionChoice.allCases.first == .leaveRecords, "the destructive door is drawn first")
    }

    /// An empty list and a failed read are different sentences, and drawing them the same way is a
    /// defect this app has shipped twice (ERRATA E126).
    @Test("a reminder list that could not be read does not say you saved nothing")
    func failedReadIsNotAnEmptyList() {
        #expect(PrivateReminderCopy.failedState != PrivateReminderCopy.emptyState)
        #expect(PrivateReminderCopy.failedState.contains("could not be read"))
        #expect(!PrivateReminderCopy.failedState.contains("Nothing saved"))
    }

    /// Screen 15's body copy, which promised a backup and a public timeline that a local account
    /// gives nobody. `User.publicAttribution` cannot be turned on anywhere (ERRATA E100) and the You
    /// tab says so on the same build, so the two screens contradicted each other.
    @Test("screen 15 no longer promises a backup or a public timeline it cannot deliver")
    func theAskDescribesALocalAccount() {
        let presentation = AccountAskPresentation(contributions: .none, isConsentAccepted: true)
        #expect(BetaCapability.accountsAreLocalOnly, "this test describes the local build")
        #expect(presentation.body == AccountAskCopy.bodyLocalAccount)
        #expect(!presentation.body.contains("backs them up"))
        #expect(!presentation.body.contains("public timeline"))
        // And it says the thing the three buttons do not: none of those services was contacted.
        #expect(presentation.body.contains("none of the services below has been contacted"))
    }

    // MARK: - 5. The pictures

    /// **The one test here that could not pass on the broken app for any reason other than the fix.**
    ///
    /// Every value in the account block was already available and already correct: `LocalAPI.userID`
    /// answered truthfully, `deleteAccount()` worked, `privateReminders()` returned the right rows.
    /// The bug was that no pixel anywhere depended on any of it. So this renders the You tab signed
    /// out and signed in and requires the two images to differ — which is false the moment
    /// `accountSection` stops drawing, and was false for every build before this one.
    @Test("the You tab looks different when somebody is signed in")
    func theYouTabDrawsWhoIsSignedIn() async throws {
        let data = try await Self.bootInMemory()
        let signedOutModel = AccountModel(api: data.api)
        await signedOutModel.load()

        let signedOut = try #require(await Self.render {
            YouTabView(
                outbox: data.makeOutboxViewState(),
                moderation: ModerationModel(api: nil),
                account: signedOutModel
            )
        })

        try await RootView(data: data).accountLink()(
            AccountLinkRequest(provider: .apple, acceptsLicense: true)
        )
        let signedInModel = AccountModel(api: data.api)
        await signedInModel.load()

        let signedIn = try #require(await Self.render {
            YouTabView(
                outbox: data.makeOutboxViewState(),
                moderation: ModerationModel(api: nil),
                account: signedInModel
            )
        })

        #expect(
            signedOut != signedIn,
            "the You tab draws the same thing signed in and signed out — the account block is not on screen"
        )
    }

    /// The other half of the same argument, one section down: a saved reminder has to be *visible*,
    /// not merely readable. The list is rendered with and without one and the images must differ.
    @Test("a saved private reminder is on the screen, not only in the database")
    func aSavedReminderIsDrawn() async throws {
        let empty = try #require(await Self.render {
            PrivateReminderList(items: [])
        })
        let withOne = try #require(await Self.render {
            PrivateReminderList(items: [
                PrivateReminderItem(
                    id: UUID(),
                    treeID: UUID(),
                    treeName: "Grandmother Cypress",
                    category: .hangingOrBrokenLimb,
                    createdAt: Date(timeIntervalSince1970: 1_784_505_600)
                )
            ])
        })
        #expect(empty != withOne, "a reminder that exists draws the empty state")

        // And a read that failed draws neither of those — the E126 rule, kept here from the start
        // rather than added after somebody reports it.
        let failed = try #require(await Self.render {
            PrivateReminderList(items: [], hasFailed: true)
        })
        #expect(failed != empty, "a failed read draws the empty state")
    }

    // MARK: - Helpers

    private static func reminderRowCount(_ store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT COUNT(*) AS n FROM private_reminders WHERE deleted_at IS NULL")
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
    }

    private static let width: CGFloat = 393
    private static let height: CGFloat = 852

    /// `FailedReadTests.render`, unchanged and for its reasons: a real `UIHostingController` in a
    /// real off-screen window, and short sleeps rather than a run-loop spin, because the `.task`
    /// doing the read is suspended on the cooperative executor.
    private static func render(@ViewBuilder _ content: () -> some View) async -> Data? {
        let host = UIHostingController(
            rootView: AnyView(
                content()
                    .frame(width: width, height: height)
                    .background(CypressColor.surfaceScreen)
                    .environment(AppRouter())
            )
        )
        host.overrideUserInterfaceStyle = .light
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = frame

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: height))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let image = UIGraphicsImageRenderer(bounds: frame).image { _ in
            host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image.pngData()
    }
}
#endif
