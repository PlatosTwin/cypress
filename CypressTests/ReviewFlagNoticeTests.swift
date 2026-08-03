import Foundation
import Testing
@testable import Cypress

/// Screen 05's half of ERRATA **E170**: the confirmation step `ObservationStatus.opensReviewFlag` was
/// written for and never had, and the sentence that says where a flagged status actually goes.
///
/// Both were absent for the same reason the queue was one kind wide — nobody followed the two
/// segments past the tap. `Appears dead` and `Removed?` sat beside `Alive` and `Declining` with
/// identical affordances and no copy, while being the only two on the card that put a review in front
/// of another person.
@MainActor
@Suite("Screen 05 · reporting a status")
struct ReviewFlagNoticeTests {

    private static let treeID = UUID(uuidString: "7EE00000-0000-4000-8000-00000000E170")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E2")!

    private static func model() async throws -> CheckInModel {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        return CheckInModel(
            treeID: treeID,
            api: api,
            outbox: OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api)),
            attribution: .anonymous(deviceID: deviceID)
        )
    }

    /// The two flagging statuses, taken off the property rather than hand-listed, so a third one
    /// added to the card cannot slip past this suite.
    /// `nonisolated` because `@Test(arguments:)` evaluates these while building the test plan, off
    /// the main actor, and this suite is `@MainActor`.
    nonisolated static let flagging: [ObservationStatus] =
        ObservationStatus.allCases.filter(\.opensReviewFlag)

    nonisolated static let plain: [ObservationStatus] =
        ObservationStatus.allCases.filter { !$0.opensReviewFlag }

    // MARK: - The confirmation step

    /// **Before E170 this failed.** `select(status:)` was `draft.status = status`, so a tap on
    /// `Appears dead` made the claim immediately and `opensReviewFlag` had no caller in shipping code
    /// at all.
    @Test("a flagging segment asks before it is set", arguments: ReviewFlagNoticeTests.flagging)
    func flaggingSegmentAsksFirst(_ status: ObservationStatus) async throws {
        let model = try await Self.model()
        #expect(model.draft.status == .alive, "the card opens on the one default PRODUCT §5 M6 gives")

        model.select(status: status)

        #expect(model.pendingStatus == status, "the tap is held, not applied")
        #expect(model.draft.status == .alive, "nothing is claimed until it is confirmed")
    }

    @Test("confirming applies it", arguments: ReviewFlagNoticeTests.flagging)
    func confirmingApplies(_ status: ObservationStatus) async throws {
        let model = try await Self.model()
        model.select(status: status)
        model.confirmPendingStatus()

        #expect(model.draft.status == status)
        #expect(model.pendingStatus == nil)
        #expect(model.draft.status.reviewFlagKind == status.reviewFlagKind)
    }

    /// Cancelling leaves the card exactly as it was. A dialog that backed out onto the segment it had
    /// proposed would be worse than no dialog: it would ask a question and record the answer it wanted.
    @Test("cancelling leaves the card untouched", arguments: ReviewFlagNoticeTests.flagging)
    func cancelingLeavesItAlone(_ status: ObservationStatus) async throws {
        let model = try await Self.model()
        model.select(status: .declining)
        model.select(status: status)
        model.cancelPendingStatus()

        #expect(model.pendingStatus == nil)
        #expect(model.draft.status == .declining, "the previous selection survives a cancel")
    }

    /// The other two segments are observations, not reports, and must stay one tap. The check-in card
    /// is a 60-second card and PRODUCT §5 M6 defaults it to `alive`; a dialog on `Declining` would be
    /// a tax on the common path for no consequence at all.
    @Test("a non-flagging segment is set on the tap", arguments: ReviewFlagNoticeTests.plain)
    func plainSegmentIsImmediate(_ status: ObservationStatus) async throws {
        let model = try await Self.model()
        model.select(status: status)

        #expect(model.pendingStatus == nil, "\(status.rawValue) opens no review and must not ask")
        #expect(model.draft.status == status)
    }

    /// Re-tapping the segment already selected asks nothing: no new claim is being made.
    @Test("re-tapping a flagging segment already selected asks nothing")
    func reTapDoesNotAsk() async throws {
        let model = try await Self.model()
        model.select(status: .appearsDead)
        model.confirmPendingStatus()

        model.select(status: .appearsDead)
        #expect(model.pendingStatus == nil)
        #expect(model.draft.status == .appearsDead)
    }

    // MARK: - Where it goes

    /// Ruling (4): the honest sentence names a community reviewer, and **not** the city.
    ///
    /// Asserted as a property of the words rather than as an equality, because the failure mode this
    /// guards is somebody rewriting the copy warmly — "we'll let the city know" is the sentence
    /// DECISIONS §3.3 forbids and RULINGS R12 exists because the gap was noticed once already.
    @Test("screen 05 says a flagged status goes to a reviewer, not to the city")
    func noticeNamesAReviewerAndNotTheCity() {
        let notice = CheckInCopy.reviewNotice.lowercased()
        #expect(notice.contains("community reviewer"))
        #expect(notice.contains("the city is not notified"))
        #expect(!notice.contains("sent to the city"))
        #expect(!notice.contains("reported to the city"))
        #expect(!notice.contains("311"))
    }

    @Test("the dialog says the same thing before the claim is made")
    func dialogSaysTheSame() {
        let message = CheckInCopy.reviewConfirmMessage.lowercased()
        #expect(message.contains("community reviewer"))
        #expect(message.contains("nothing is sent to the city"))

        // And it names which of the two reports is being made.
        #expect(CheckInCopy.reviewConfirmTitle(for: .appearsDead).lowercased().contains("dead"))
        #expect(CheckInCopy.reviewConfirmTitle(for: .appearsRemoved).lowercased().contains("gone"))
    }

    /// The moderation surface must not undo it from the other end. Its removal message used to close
    /// on "This is how the city record is corrected", which is the same claim in the passive voice on
    /// the screen where a lead is most likely to believe it.
    @Test("the moderation queue never claims the city was told", arguments: ReviewFlag.Kind.statusReviewKinds)
    func moderationCopyNeverClaimsTheCity(_ kind: ReviewFlag.Kind) {
        let message = ModerationCopy.confirmMessage(treeName: "This tree", kind: kind).lowercased()
        #expect(message.contains("the city is not notified"))
        #expect(!message.contains("city record is corrected"))

        let dismissal = ModerationCopy.dismissMessage(treeName: "This tree").lowercased()
        #expect(dismissal.contains("nothing about the tree changes"))
    }

    /// The two rows must not say the same word. One queue with one vocabulary is the shape the defect
    /// hid inside.
    @Test("the queue's two kinds read differently")
    func theTwoKindsReadDifferently() {
        let dates = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(
            ModerationCopy.raisedLine(kind: .appearsDead, at: dates)
                != ModerationCopy.raisedLine(kind: .appearsRemoved, at: dates)
        )
        #expect(ModerationCopy.confirmAction(kind: .appearsDead) != ModerationCopy.confirmAction(kind: .appearsRemoved))
        #expect(ModerationCopy.confirmTitle(kind: .appearsDead) != ModerationCopy.confirmTitle(kind: .appearsRemoved))
        #expect(ModerationCopy.raisedLine(kind: .appearsDead, at: dates).contains("Reported dead"))
    }

    // MARK: - The badge

    /// Ruling (2): the profile says the status was confirmed, and does not say "removed".
    @Test("a confirmed-dead tree badges as dead, not as removed")
    func deadBadge() {
        let badge = StatusBadge.kind(status: .deadReported, vitality: nil, plantedYear: nil)
        #expect(badge == .deadReported)
        #expect(badge?.text == "Dead")
        #expect(badge?.text != StatusBadge.Kind.removed.text)
    }

    /// A stale `thriving` rating from before the tree died must not outrank the confirmed status.
    @Test("a stale thriving rating does not outrank a confirmed death")
    func statusOutranksVitality() {
        #expect(StatusBadge.kind(status: .deadReported, vitality: .thriving, plantedYear: 2019) == .deadReported)
        #expect(StatusBadge.kind(status: .deadReported, vitality: nil, plantedYear: 2019) == .deadReported)
        // The live tree beside it is unchanged.
        #expect(StatusBadge.kind(status: .alive, vitality: .thriving, plantedYear: nil) == .thriving)
        #expect(StatusBadge.kind(status: .alive, vitality: nil, plantedYear: 2019) == .planted(year: 2019))
    }
}
