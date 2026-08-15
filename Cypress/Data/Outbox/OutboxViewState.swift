import Foundation
import Observation

/// The "says why" line on screen 17.
///
/// Screen 17's footnote is the contract this type implements: "Nothing here disappears silently. An
/// item that cannot sync says so, says why, and waits for you." Every failure path produces a
/// sentence a volunteer standing on a pavement can act on.
///
/// Copy rules (ARCHITECTURE §5.7): prose is sentence case, and there are no spaces around em
/// dashes — which is easiest to honor by not reaching for one.
public enum OutboxFailureReason {
    /// The 48 h cap, reached (BUILD-PLAN §4).
    public static let expired = "Tried for 48 hours without getting through. Tap retry when you have a connection."

    /// The service refused this item with a code the taxonomy says will not change, and the item
    /// never landed — `forbidden`, `validation_failed`, `conflict`, `not_found`, `unauthorized`.
    ///
    /// **The owner ruled this sentence on 2026-08-14** (rulings 1 and 3 of that round), replacing
    /// the composed `"<cause> This one will not go through on its own."`. Two things it is required
    /// to do and does: it is the *whole* sentence for a terminally refused row, and it is
    /// distinguishable from the retryable `sentence(for:)` fallback below — a row that lost its
    /// connection still reads "No connection." and is still trying.
    ///
    /// What it deliberately stops doing is naming the code. Screen 17's footnote asks an item that
    /// cannot sync to "say why", and eight per-code sentences were the answer while every one of
    /// them was drawn; they are still drawn for a row that is *retrying*, and no longer for one the
    /// service has finished with. That narrowing is the ruling's, recorded rather than inferred —
    /// see the errata entry for this round.
    ///
    /// **`moderation_rejected` is not in this class and the review of PR #88 is why (F2).** It is
    /// the one non-retryable code whose item *did* leave the phone: it reached `cypress-sync`, the
    /// service took the request, and a person read the content and declined it. Telling that
    /// volunteer their work could not be sent is a false claim about where their field work is —
    /// ARCHITECTURE §5.4, the rule this whole round exists to enforce. It has its own sentence
    /// below, ruled by the owner on **2026-08-15**.
    public static let refusedTerminally = "This couldn't be sent."

    /// `moderation_rejected`: the item arrived, a person read it, and it will not be published.
    ///
    /// **Ruled verbatim by the owner on 2026-08-15**, correcting the widening that rulings 1 and 3
    /// were implemented with. What it has to get right is the tense of two different verbs: the
    /// sending happened, and the sharing will not — which is exactly the pair `refusedTerminally`
    /// gets wrong for this code and right for the other five.
    ///
    /// "shared" and not "published": D4 and R12's vocabulary. Nothing in this app tells an
    /// authority anything (ARCHITECTURE §5.4), and this sentence says what the app can actually
    /// answer for — whether the record joins the tree's public timeline.
    public static let moderationDeclined = "This was reviewed and won't be shared."

    public static func awaitingWifi(photoCount: Int) -> String {
        photoCount == 1
            ? "The note is saved. One photo is waiting for wi-fi."
            : "The note is saved. \(photoCount) photos are waiting for wi-fi."
    }

    /// Narrows any thrown error to the §6 taxonomy, or `nil` when it did not come from the API at
    /// all (a dropped connection, a file that vanished).
    public static func apiError(from error: Error) -> APIError? {
        if let apiError = error as? APIError { return apiError }
        if let sqliteError = error as? SQLiteError { return sqliteError.asAPIError }
        // `APIError.Envelope` is the decoded `{error: {code, message, retryable}}` body, not an
        // `Error` — `RemoteAPI` will decode it and throw its `.error` member, which the first line
        // above catches.
        // The 10 m proximity dedupe on `POST /trees` carries its candidate list in a dedicated
        // error type, but its taxonomy code is `conflict` — and `conflict` is not retryable, so the
        // item fails immediately instead of spending 48 h on an answer only the user can give.
        if error is ProximityConflict { return .conflict }
        return nil
    }

    /// The sentence shown under an item.
    public static func describe(error: Error, failCount: Int, state: OutboxItem.State) -> String {
        let cause = sentence(for: error)
        guard state != .failed else {
            if let apiError = apiError(from: error), !apiError.retryable {
                // Two terminal sentences, split on the one thing they disagree about: whether the
                // item left the phone. See both constants.
                return apiError == .moderationRejected ? moderationDeclined : refusedTerminally
            }
            return expired
        }
        switch failCount {
        case 1: return cause
        case 2: return "\(cause) Tried twice."
        default: return "\(cause) Tried \(failCount) times."
        }
    }

    /// One sentence per taxonomy code (BUILD-PLAN §6).
    ///
    /// ── **Which of these screen 17 still draws, since the owner's rulings of 2026-08-14** ───────
    ///
    /// Three, and the six-code list is now a map of the taxonomy rather than a list of drawn copy.
    /// `describe` reaches this function on the *retrying* path only, and `OutboxRetryPolicy` sends
    /// every non-retryable code straight to `.failed` on its first attempt — so the six sentences
    /// for `unauthorized`, `forbidden`, `not_found`, `validation_failed`, `conflict` and
    /// `moderation_rejected` are unreachable from an outbox row. What a person reads instead is
    /// `refusedTerminally`, or `moderationDeclined` for the last of them.
    ///
    /// Still drawn, and drawn often: the `nil` fallback ("No connection.") for anything outside the
    /// taxonomy, and `rate_limited` / `server_error`, which are the two retryable codes.
    ///
    /// **They are kept rather than deleted**, and the reason is not sentiment. `retryable` is a
    /// property of the code and it can move: the day one of the six becomes retryable — or the day
    /// something other than an outbox row wants a sentence for a code — this switch is where the
    /// answer already is, and a `switch` over a `CaseIterable` enum with cases removed is a compile
    /// error rather than a gap. What is *not* allowed is a comment elsewhere claiming screen 17
    /// prints one of the six; PR #88's review found five such sites and swept them (F5).
    static func sentence(for error: Error) -> String {
        guard let apiError = apiError(from: error) else {
            return "No connection."
        }
        switch apiError {
        case .unauthorized:
            return "Sign in to send this."
        case .forbidden:
            return "This account is not allowed to send that."
        case .notFound:
            return "That tree is no longer in the inventory."
        case .validationFailed:
            return "Something in this entry did not pass validation."
        case .conflict:
            return "This looks like something already recorded."
        case .moderationRejected:
            return "A moderator declined this."
        case .rateLimited:
            return "The server asked us to slow down."
        case .serverError:
            return "The server could not take it just now."
        }
    }
}

/// One row of screen 17.
public struct OutboxItemSnapshot: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let kind: OutboxItem.Kind
    public let state: OutboxItem.State
    /// How many attempts have failed. Screen 17 renders this as "upload failed twice".
    public let failCount: Int
    /// The human-readable reason, or `nil` when there is nothing to explain.
    public let reason: String?
    /// The BUILD-PLAN §6 code behind `reason`, when the failure came from the API.
    public let errorCode: APIError?
    public let treeID: UUID
    /// The tree's active name, or its species common name, resolved by the caller. `nil` renders as
    /// the species fallback in the view; this layer does not author display copy for a tree.
    public let treeName: String?
    /// The mutation itself, already decoded, or `nil` when the row's JSON could not be read.
    ///
    /// SCREENS.md 17 draws what each queued item *says* — `2 photos`, `vitality 3, thinning`,
    /// `DBH 31 cm, tape` — and none of that is recoverable from a kind and a timestamp. It costs
    /// nothing to carry: `OutboxSnapshot.init` already decodes the payload to find `treeID`, so
    /// this is the same decode kept instead of thrown away. The *copy* is still authored in the
    /// feature, as `treeName` is; this layer only hands over the facts.
    public let payload: OutboxPayload?
    /// Binaries still on device for this item.
    public let photoCount: Int
    public let createdAt: Date
    /// When the row last changed state. For a `done` row this is when it went, which is what
    /// screen 17's `✓ 9:56 am` receipt is a stamp of — the capture time is a different fact and on
    /// an item that waited out a dead zone it is a different hour.
    public let updatedAt: Date
    /// When the backoff will let it try again. `nil` when it is not waiting on a timer.
    public let nextAttemptAt: Date?

    /// Screen 17 draws the `retry` state as an amber attention card. That is exactly the terminal
    /// `failed` state, which is the only one with a retry affordance.
    ///
    /// It agrees with `OutboxPresentation.Row.showsRetryButton` again as of the owner's ruling 3 of
    /// 2026-08-14: a terminally refused item folds into the same failed row rather than drawing a
    /// fourth state of its own, so every `failed` row carries the control.
    public var showsRetryAffordance: Bool { state == .failed }
}

/// Everything screen 17 renders, in one value.
public struct OutboxSnapshot: Sendable, Equatable {
    public let items: [OutboxItemSnapshot]
    /// Items not yet sent. The header pill reads "3 waiting".
    public let waitingCount: Int
    /// Items that gave up and are asking for a tap.
    public let failedCount: Int
    /// Receipts from the last day. The "Synced earlier today" section.
    public let syncedRecentlyCount: Int
    /// Items whose JSON went and whose photos are queued behind the wi-fi toggle.
    public let awaitingWifiCount: Int
    /// Binaries across those items, which is a different number from the one above.
    ///
    /// The sentence these feed is `OutboxFailureReason.awaitingWifi(photoCount:)` — "The note is
    /// saved. N photos are waiting for wi-fi." Per item, `OutboxQueue.drain` already passes that
    /// item's own photo count, so the per-row sentence was right. The screen also says it once for
    /// the whole queue, and there `awaitingWifiCount` is a count of *items*: two visits carrying two
    /// photographs each would have said "2 photos" with four on the device. Every clause of that
    /// sentence has to be true (ERRATA E32), and "photos" is a clause.
    public let awaitingWifiPhotoCount: Int
    /// Always zero, and that is the claim screen 17's summary line makes. It is computed rather
    /// than hard-coded so that if the invariant ever broke, the screen would say so.
    public let lostCount: Int

    /// - Parameter syncPhotosOnWifiOnly: screen 17's toggle, as it currently stands.
    ///
    /// The toggle is a parameter rather than an assumption because nothing is "queued behind the
    /// wi-fi toggle" while the toggle is off — with it off the binaries go on whatever connection
    /// there is, exactly as notes and numbers do (BUILD-PLAN §4). It deliberately has no default:
    /// a caller that does not know the toggle's state cannot answer this question, and a default
    /// would let it answer anyway (ERRATA E32).
    public init(
        records: [OutboxStore.Record],
        treeNames: [UUID: String],
        now: Date,
        syncPhotosOnWifiOnly: Bool
    ) {
        let dayAgo = now.addingTimeInterval(-OutboxQueue.completedRetention)

        items = records.map { record in
            let payload = try? OutboxPayload.decode(kind: record.item.kind, from: record.item.payload)
            let treeID = payload?.treeID ?? UUID()
            return OutboxItemSnapshot(
                id: record.id,
                kind: record.item.kind,
                state: record.item.state,
                failCount: record.item.failCount,
                reason: record.item.lastError,
                errorCode: record.item.lastErrorCode,
                treeID: treeID,
                treeName: treeNames[treeID],
                payload: payload,
                photoCount: record.item.photos.count,
                createdAt: record.item.createdAt,
                updatedAt: record.item.updatedAt,
                nextAttemptAt: record.nextAttemptAt
            )
        }

        waitingCount = records.filter { $0.item.state == .pending || $0.item.state == .uploading }.count
        failedCount = records.filter { $0.item.state == .failed }.count
        syncedRecentlyCount = records.filter { $0.item.state == .done && $0.item.updatedAt >= dayAgo }.count
        // The sentence this count drives is `awaitingWifi(photoCount:)` — "The note is saved. N
        // photos are waiting for wi-fi." Screen 17's footnote makes that sentence a promise, so
        // every clause of it has to be true before the count claims it: the note really is saved
        // (`locallyApplied`), binaries really are still on the device, the row is still trying rather
        // than given up on, and the toggle really is what is holding them. The old predicate
        // asserted none of the four and swept up a visit enqueued a moment ago, and a
        // `validation_failed` row that happened to carry a photo, into a sentence that told the
        // contributor the opposite of what had happened (ERRATA E32).
        let awaitingWifi = syncPhotosOnWifiOnly
            ? records.filter {
                $0.locallyApplied
                    && !$0.item.photos.isEmpty
                    && ($0.item.state == .pending || $0.item.state == .uploading)
            }
            : []
        awaitingWifiCount = awaitingWifi.count
        awaitingWifiPhotoCount = awaitingWifi.reduce(0) { $0 + $1.item.photos.count }
        // A row that is neither waiting, failed, nor done has no state left to be in. The outbox's
        // four states are exhaustive, so this is structurally zero; it is here because the screen
        // claims it out loud.
        lostCount = records.filter {
            $0.item.state != .pending && $0.item.state != .uploading
                && $0.item.state != .failed && $0.item.state != .done
        }.count
    }
}

/// Screen 17's model.
///
/// TreeObservation-framework observable, not `ObservableObject` (ARCHITECTURE §3), and `@MainActor`
/// because it is UI state. It owns no database handle: every read goes through `OutboxQueue`, which
/// is the actor that owns the connection.
///
/// # Why the conformance is written out instead of using `@Observable`
///
/// `Core` defines `TreeObservation` — the domain type for a light check-in (BUILD-PLAN §4
/// `observations`). Inside this module that type name shadows the *module* named `TreeObservation`, and
/// the `@Observable` macro expands to fully qualified references (`TreeObservation.ObservationRegistrar`,
/// `TreeObservation.Observable`) which then resolve to `Cypress.TreeObservation` and fail to compile:
///
/// ```
/// error: 'Observable' is not a member type of struct 'Cypress.TreeObservation'
/// error: type 'TreeObservation' has no member 'ObservationRegistrar'
/// ```
///
/// There is no import that fixes this — a type in the current module always wins over a module of
/// the same name. Renaming `Core.TreeObservation` would be worse: it is the correct domain word and it
/// is what §4 calls the table. So the three lines the macro would have written are written here
/// instead. The observable behavior is identical; `@State`, `@Bindable`, and SwiftUI's dependency
/// tracking all work exactly as they would have.
///
/// **This applies to every `@Observable` in the app, not just this one.** Any feature model in this
/// module needs the same treatment.
@MainActor
public final class OutboxViewState: Observable {
    private let registrar = ObservationRegistrar()

    private var storedSnapshot: OutboxSnapshot
    public private(set) var snapshot: OutboxSnapshot {
        get {
            registrar.access(self, keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            registrar.withMutation(of: self, keyPath: \.snapshot) { storedSnapshot = newValue }
        }
    }

    private var storedIsRefreshing = false
    public private(set) var isRefreshing: Bool {
        get {
            registrar.access(self, keyPath: \.isRefreshing)
            return storedIsRefreshing
        }
        set {
            registrar.withMutation(of: self, keyPath: \.isRefreshing) { storedIsRefreshing = newValue }
        }
    }

    private var storedRefreshError: String?
    /// The last error refreshing itself hit. Failing to *read* the outbox is a different problem
    /// from failing to *send* it, and the screen should not confuse the two.
    public private(set) var refreshError: String? {
        get {
            registrar.access(self, keyPath: \.refreshError)
            return storedRefreshError
        }
        set {
            registrar.withMutation(of: self, keyPath: \.refreshError) { storedRefreshError = newValue }
        }
    }

    private var storedSyncPhotosOnWifiOnly: Bool
    /// Screen 17's toggle: "Sync photos on wifi only". Applies to photo binaries only; notes and
    /// numbers sync on any connection (BUILD-PLAN §4).
    public var syncPhotosOnWifiOnly: Bool {
        get {
            registrar.access(self, keyPath: \.syncPhotosOnWifiOnly)
            return storedSyncPhotosOnWifiOnly
        }
        set {
            guard newValue != storedSyncPhotosOnWifiOnly else { return }
            registrar.withMutation(of: self, keyPath: \.syncPhotosOnWifiOnly) {
                storedSyncPhotosOnWifiOnly = newValue
            }
            // The snapshot is recomputed as well as persisted, because `awaitingWifiCount` is now a
            // statement about the toggle as much as about the rows: turning it off means no photo
            // is waiting on wi-fi any more, and the screen has to stop saying so in the same
            // gesture that made it untrue (ERRATA E32).
            Task {
                await self.persistWifiPreference(newValue)
                await self.refresh()
            }
        }
    }

    private let queue: OutboxQueue
    private let store: CypressStore?
    /// Resolves a tree id to the name a row should show. Supplied by the composition root so this
    /// type does not reach into the API itself.
    private let treeNameResolver: @Sendable ([UUID]) async -> [UUID: String]
    private var observerToken: UUID?

    public init(
        queue: OutboxQueue,
        store: CypressStore? = nil,
        syncPhotosOnWifiOnly: Bool = true,
        treeNameResolver: @escaping @Sendable ([UUID]) async -> [UUID: String] = { _ in [:] }
    ) {
        self.queue = queue
        self.store = store
        self.storedSyncPhotosOnWifiOnly = syncPhotosOnWifiOnly
        self.treeNameResolver = treeNameResolver
        self.storedSnapshot = OutboxSnapshot(
            records: [],
            treeNames: [:],
            now: Date(),
            syncPhotosOnWifiOnly: syncPhotosOnWifiOnly
        )
    }

    /// Subscribes to the queue so the screen follows a drain without polling.
    public func start() async {
        guard observerToken == nil else { return }
        observerToken = await queue.addObserver { [weak self] in
            await self?.refresh()
        }
        if let stored = try? await store?.appState(.syncPhotosOnWifiOnly) {
            syncPhotosOnWifiOnly = (stored as NSString).boolValue
        }
        await refresh()
    }

    public func stop() async {
        if let observerToken { await queue.removeObserver(observerToken) }
        observerToken = nil
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let records = try await queue.records()
            let treeIDs = records.compactMap {
                (try? OutboxPayload.decode(kind: $0.item.kind, from: $0.item.payload))?.treeID
            }
            let names = await treeNameResolver(Array(Set(treeIDs)))
            snapshot = OutboxSnapshot(
                records: records,
                treeNames: names,
                now: Date(),
                syncPhotosOnWifiOnly: syncPhotosOnWifiOnly
            )
            refreshError = nil
        } catch {
            refreshError = "Could not read the outbox."
        }
    }

    /// The retry button on an amber attention card.
    ///
    /// ── **Why this drains, and what it drew before it did (PR #88 review, F1)** ────────────────
    ///
    /// `OutboxStore.retry` moves the row to `pending` and **NULLs `last_error` and
    /// `last_error_code`**. That is right for a row that is about to be attempted again and it is a
    /// lie for a row that is not: until this line drained, the only drains in the app were the six
    /// feature writers, which fire when somebody saves *other* work, and `syncNow(isOnWifi:)` had
    /// no call site at all. So one tap on a terminally refused item left it reading `waiting` —
    /// SCREENS.md 17's word for "still trying" — counted in the header's `N waiting` pill, with its
    /// sentence and its taxonomy code both erased, and it stayed there until an unrelated save
    /// happened along. Measured, before and after, on a `forbidden` item:
    ///
    /// ```
    /// BEFORE TAP:    state=retry    isTerminal=true   showsRetryButton=true  reason=This couldn't be sent.
    /// AFTER TAP:     state=waiting  isTerminal=false  showsRetryButton=false reason=nil  errorCode=nil
    /// AFTER A DRAIN: state=retry                                             reason=This couldn't be sent.
    /// ```
    ///
    /// Screen 17 §6 is the promise that breaks in the middle line: "an item that cannot sync says
    /// so, says why, and waits for you". After a tap it said neither. The owner's ruling 3 of
    /// 2026-08-14 put the whole stopped-versus-will-retry distinction into that sentence, so a
    /// control that erases it for an unbounded stretch is the ruling's own failure mode.
    ///
    /// Draining closes it: the row is `waiting` only while it really is being attempted, and the
    /// service's answer puts a refused item straight back to `failed` with its sentence — on the
    /// first attempt, because a non-retryable code does not spend 48 h of backoff (ERRATA E83).
    /// `OutboxQueueRetryTests` walks that exact sequence.
    ///
    /// **Preserving `last_error_code` across the retry instead was the other candidate and is not
    /// enough on its own**: nothing draws the code (`OutboxPresentation.state(for:)` stopped reading
    /// it under ruling 3), so keeping it would leave every drawn moment exactly as wrong.
    ///
    /// `drain()` and not `syncNow(isOnWifi:)`: the toggle's parameter is a question about the
    /// connection and nothing in this app can answer it (ERRATA **E81** — there is no reachability
    /// monitor), which is why `syncNow` never acquired a caller. The bare `drain()` is the same call
    /// all six feature writers make.
    public func retry(id: UUID) async {
        guard (try? await queue.retry(id: id)) == true else { return }
        _ = try? await queue.drain()
    }

    /// Every terminal row at once, and the same argument as `retry(id:)` applies to each of them.
    public func retryAll() async {
        _ = try? await queue.retryAllFailed()
        _ = try? await queue.drain()
    }

    /// Drains, honoring the wi-fi toggle.
    ///
    /// - Parameter isOnWifi: whether the current connection is unmetered. The toggle only bites
    ///   when it is off.
    public func syncNow(isOnWifi: Bool) async {
        _ = try? await queue.drain(photoUploadsAllowed: isOnWifi || !syncPhotosOnWifiOnly)
    }

    private func persistWifiPreference(_ value: Bool) async {
        try? await store?.setAppState(.syncPhotosOnWifiOnly, to: value ? "true" : "false")
    }
}
