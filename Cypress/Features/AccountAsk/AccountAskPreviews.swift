//
//  AccountAskPreviews.swift
//  Cypress — Features/AccountAsk
//
//  Previews for screen 15, including the states SCREENS.md does not draw. Three of them matter more
//  than the drawn one:
//
//  - **accounts are not ready**, which is what a tap on any of the three buttons does on every build
//    today, because `CypressAPI` has no `/auth/*` and there is no auth server behind it;
//  - **the unchecked consent box**, which the spec calls out as NOT SPECIFIED;
//  - **the numberless headline**, which is what the sheet says when the visit count cannot be
//    proved — a client with no store behind it, or a device already claimed.
//
//  All three are previewed rather than described, so that what was chosen for them is visible.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Hands back a fixed device inventory and refuses everything else. Previews only.
struct AccountAskPreviewAPI: CypressAPI {
    var holdings: DeviceContributions = .none

    func deviceContributions() async throws -> DeviceContributions { holdings }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

private enum AccountAskFixtures {
    /// The state D9 puts this screen in: three saves on the phone and no account.
    static let thirdSave = DeviceContributions(visits: 3)

    /// The second offer (ERRATA E34 lets the ask return once on the next save), which is why the
    /// headline could never have come from a counter pinned at the threshold.
    static let fourthSave = DeviceContributions(visits: 4, careEvents: 1)
}

// MARK: - Previews

/// The drawn state. Checkbox checked, headline with its number, no notice.
#Preview("15 · the account ask") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: AccountAskFixtures.thirdSave,
            isConsentAccepted: true
        )
    )
}

/// **NOT SPECIFIED**, and what every tap does today. `CypressAPI`'s header states the reason in as
/// many words: there is no auth server, and a stub that minted an account locally would claim a
/// backup that does not exist.
#Preview("15 · accounts are not ready") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: AccountAskFixtures.thirdSave,
            isConsentAccepted: true,
            notice: .unavailable
        )
    )
}

/// **NOT SPECIFIED** — the unchecked box. The same box without the glyph; nothing else moves, and
/// the three buttons stay live because 15 states no rule that they should not.
#Preview("15 · consent unchecked") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: AccountAskFixtures.thirdSave,
            isConsentAccepted: false
        )
    )
}

/// The second offer, one save later — the case that makes the headline a read rather than a counter.
#Preview("15 · the second offer") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: AccountAskFixtures.fourthSave,
            isConsentAccepted: true
        )
    )
}

/// No provable count: the sentence drops its number rather than saying nought. This is what a
/// preview double, a fresh `RemoteAPI`, or a device whose visits are already on an account renders.
#Preview("15 · numberless headline") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: .none,
            isConsentAccepted: true
        )
    )
}

/// The whole feature, wired to a double, so the read and the tap are exercised rather than staged.
#Preview("15 · live, with no sign-in service") {
    AccountAskView(
        api: AccountAskPreviewAPI(holdings: AccountAskFixtures.thirdSave),
        onFinish: {}
    )
}

/// Dark. 15 has no specified dark screen (D1–D3 are the only ones, ERRATA E8), so this is evidence
/// of what the token layer resolves it to rather than a design — in particular the `Continue with
/// Apple` fill, which has to invert or vanish against the dark sheet.
#Preview("15 · dark") {
    AccountAskScreen(
        presentation: AccountAskPresentation(
            contributions: AccountAskFixtures.thirdSave,
            isConsentAccepted: true
        )
    )
    .preferredColorScheme(.dark)
}
#endif
