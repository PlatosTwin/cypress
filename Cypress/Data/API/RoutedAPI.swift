//
//  RoutedAPI.swift
//  Cypress — Data/API
//
//  Spec §3.1's router: "under §1(a) every method is implemented on both sides and the composition
//  root wires a router that decides which answer is authoritative."
//

import Foundation

/// Which reads went to the service and which fell back to the phone.
///
/// ── Why the router records this rather than returning it ───────────────────────────────────────
///
/// Spec §4.3 rules that "Class R reads fall back to the local answer **and mark it as such**", and
/// in the same breath rules that the *sentence* a screen draws about it is "a copy question and it
/// is **not in the mocks** — named, not invented (DECISIONS constraint 21)." Both halves are
/// binding, and they pull in opposite directions for anything that changes a return type: widening
/// `[GroveEntry]` into a pair would put the fact in front of every screen and every preview double,
/// and the first thing a screen would do with a fact it has no drawn copy for is invent some.
///
/// So the mark lands here, off the return path, where a later round can draw it once the copy
/// exists and where a test can assert it today. Nothing in `Features` reads this yet, on purpose.
public actor RemoteReadLog {

    /// The Class R reads of spec §3.1. `journal` is in the list and never reports `.live` — see
    /// `RoutedAPI.journal(cursor:limit:)`.
    public enum Read: String, Sendable, Hashable, CaseIterable {
        case grove, groveSpecies, journal, isFavorite, mapMembership, treeProfile, photoData
    }

    /// ── Three cases, because spec §4.3 names three ────────────────────────────────────────────
    ///
    /// "Under Class R, a read has three outcomes rather than two — answered,
    /// answered-from-the-local-fallback, and could-not-ask — and a screen that collapses the third
    /// into an empty state is telling somebody their work is gone."
    ///
    /// This enum shipped with two of them, and review of PR #78 found what the missing third cost:
    /// `photoData`'s failure path recorded `.fellBackToLocal` — "the value is what this phone knows"
    /// — and then **threw**, so there was no value, and a test pinned that. `degradedReads` is
    /// precisely the set a later round draws §4.3 copy from, and it would have said "showing what's
    /// on this phone" about a read that returned nothing.
    /// `CaseIterable` so `readsNotAnsweredLive` can be *asserted* as a complement rather than
    /// merely claimed to be one. Review of PR #79 swapped the complement for the hand-written union
    /// of the two named sets and the suite stayed green — which it would, because today the union
    /// and the complement are the same set. `theNotLiveAggregateIsAComplementAndNotAList` iterates
    /// these cases, so the day a fourth is added the two stop agreeing and the test says so.
    public enum Outcome: String, Sendable, Hashable, CaseIterable {
        /// The service answered and its half is in the value returned.
        case live
        /// The service could not be asked, or refused, and the value is what this phone knows.
        /// True for everything this device did, and missing other devices of the same account.
        case fellBackToLocal
        /// **Neither half answered and the read threw.** There is no value: the service refused or
        /// could not be reached, and the phone did not have it either.
        ///
        /// Only `photoData` can reach this today, and that is a property of the reads rather than of
        /// this enum — every other Class R read has a complete local answer to fall back to, and
        /// `photoData` is the one whose local half may genuinely be empty (`PhotoAccess.swift`: a
        /// zero-byte JPEG is a corrupt photograph, so there is nothing honest to return).
        case unanswered
    }

    private var outcomes: [Read: Outcome] = [:]

    public init() {}

    func record(_ read: Read, _ outcome: Outcome) {
        outcomes[read] = outcome
    }

    /// The last outcome for a read, or nil when the service was not asked.
    ///
    /// Nil is deliberately not `.fellBackToLocal`: "we did not ask" and "we asked and could not
    /// reach it" are different facts, and this project has drawn an empty state over the first of
    /// them before (`AccountModel.remindersFailed`, quoted in spec §4.3).
    ///
    /// **Nil covers two situations and that is deliberate**: a read nobody has performed since
    /// launch, and `photoData` answered off this disk without needing to ask. They are one fact to
    /// every consumer this log has — the service was not consulted, and nothing about the value
    /// returned is missing because of it — and separating them would add a case that no surface
    /// could draw differently.
    public func outcome(of read: Read) -> Outcome? { outcomes[read] }

    /// Every read that is currently answering **from the phone**: `.fellBackToLocal`, and only that.
    ///
    /// **It deliberately does not contain `.unanswered`, and on its own that was a defect** — round 2
    /// of PR #78's review found it. The name is right: a read that threw is not "answering from the
    /// phone", and folding it in here would offer a §4.3 copy round the sentence *"showing what's on
    /// this phone"* for a read that returned nothing, which is the exact mislabeling `.unanswered`
    /// was added to end. But this was the *only* aggregate the log had, so the third case §4.3 names
    /// went from mislabeled-and-visible to correctly-labeled-and-invisible: reachable only by asking
    /// `outcome(of:)` for a read by name, which no surface iterating degraded reads would do.
    ///
    /// `unansweredReads` is the companion, and `readsNotAnsweredLive` is the union — **that** is the
    /// one an aggregate consumer should reach for. This property stays narrow so the two sets keep
    /// meaning different things.
    public var degradedReads: Set<Read> {
        Set(outcomes.filter { $0.value == .fellBackToLocal }.keys)
    }

    /// Every read that **could not be answered at all**: §4.3's third outcome, "could-not-ask".
    ///
    /// Neither half had it and the read threw, so there is no value — see `Outcome.unanswered`.
    /// §4.3's ruling is that "a screen that collapses the third into an empty state is telling
    /// somebody their work is gone", and this is the set that has to exist for a screen to be able
    /// to avoid doing that.
    public var unansweredReads: Set<Read> {
        Set(outcomes.filter { $0.value == .unanswered }.keys)
    }

    /// Every read whose answer is **not** the service's — degraded or unanswered, in one set.
    ///
    /// The aggregate a §4.3 surface should reach for, and the reason the two sets above can stay
    /// narrow without the third case going missing.
    ///
    /// **Computed as the complement of `.live`, not as `degradedReads ∪ unansweredReads`**, so a
    /// fourth `Outcome` case is in this set the day it is added rather than the day somebody
    /// remembers to union it in. Those two expressions agree on every input this enum can currently
    /// produce, which is exactly why the difference needed pinning rather than stating: review of
    /// PR #79 substituted the union here and the whole suite stayed green.
    /// `RoutedAPITests.theNotLiveAggregateIsAComplementAndNotAList` iterates `Outcome.allCases`, so
    /// it is the arrival of the fourth case that makes them disagree and the test that notices.
    public var readsNotAnsweredLive: Set<Read> {
        Set(outcomes.filter { $0.value != .live }.keys)
    }
}

/// The §3.1 router: one `CypressAPI` over the phone's answer and the service's.
///
/// ── The three classes, and what this type does with each ───────────────────────────────────────
///
/// **Class L — local-authoritative.** `mapContent`, `treesNear`, `species`, `searchSpecies`,
/// `speciesGuide`, `almanac`, `city`, `exportLatest`. These reach `local` and nothing else, and the
/// invariant spec §4.3 states as a line of its own is what that is for: **"No Class L read is
/// allowed to acquire a remote failure mode."** The map's pan loop is a read every 200 ms
/// (`MapModel.cameraDebounce`) and two performance campaigns bought it where it is (§4.1). There is
/// nothing to fall back *from* here — this is not a fallback, it is the answer.
///
/// **Class R — remote, with a local fallback that says it fell back.** `grove`, `groveSpecies`,
/// `isFavorite`, `mapMembership` at the R-degraded grade; `treeProfile` and `photoData` at the
/// R-required grade. On a remote failure, five of the six answer from the phone and record
/// `.fellBackToLocal` in `log`. A read that could-not-ask must never surface as an empty state:
/// "an empty state is a claim, and this project has already drawn one over a failed read" (R72
/// ruling 1).
///
/// **`photoData` is the sixth and it is the exception**, because it is the one Class R read whose
/// local half may genuinely be empty: bytes this device never wrote are not on this disk, and
/// `PhotoAccess.swift` refuses to stand an empty `Data` in for them. When neither half has them it
/// throws and records `.unanswered`; when the phone has them it records nothing, because the service
/// was not asked. See that method for all three paths.
///
/// **Class D — device-only.** `deviceContributions`. Local, always, because the rows have not been
/// sent and their being unsent is what the question is about.
///
/// ── Reads are routed. Writes are not, and that is a scope statement ────────────────────────────
///
/// §3.1's last line is "**Writes** are their own path: outbox first, both sinks (§2.1, §6)." A write
/// does not choose between two answers; it is applied locally and *also* sent, and the sending half
/// is `OutboxSendSink` — which `DataLayer` now wires to `RemoteAPI`, one layer above this one. So
/// every mutating method here goes to `local`, including `sync` and the photo pair, and that is not
/// a gap: the router is the *read* path's answer, and a write's second half is the queue's, where
/// the retry schedule and the ordering live. A `sync` that reached `remote` from here would send
/// without the outbox having committed anything, which is the ordering RULINGS R72 §1 forbids and
/// `AppSchema` v15's second CHECK refuses to store.
/// `CypressTests/DataLayerWiringTests` is where the wiring is held honest.
///
/// The nine mutations of spec §3.4 are local for a second, independent reason: they have no queue
/// behind them at all, and "making them remote-routed without a queue is what stops community
/// add-a-tree working in a park."
///
/// ── What constructs this ───────────────────────────────────────────────────────────────────────
///
/// `DataLayer.boot`, since #158's wiring round: `DataLayer.api` **is** this type, and every screen
/// holds it. The session behind `remote` is an `AppSession` over the device credential (D9 makes
/// anonymous the normal case, not the exception), so the reads below work on an installation that
/// has never seen the account sheet. `CypressTests/RoutedAPITests` exercises the routing table and
/// the fallbacks; `CypressTests/DataLayerWiringTests` exercises the wiring.
public struct RoutedAPI: CypressAPI {

    /// The phone: the installed city file plus this device's own rows.
    public let local: any CypressAPI

    /// The service.
    public let remote: RemoteAPI

    /// Where a fallback is recorded. See `RemoteReadLog`.
    public let log: RemoteReadLog

    /// Who is signed in, for `deleteAccount` and nothing else.
    ///
    /// **Injected, nil by default, and nil means "route deletion local"** — the behavior every
    /// caller had before this seam existed.
    ///
    /// ── Three things produce a nil, and the third is not a test ────────────────────────────────
    ///
    /// 1. **A router constructed without the argument** — previews, screenshot fixtures, and the
    ///    tests that predate the seam. They keep the local path rather than acquiring a remote
    ///    failure mode they were never written for.
    /// 2. **`DataLayer.boot` with the gate explicitly off**, which is how the UI suite runs.
    /// 3. **`DataLayer.boot` in an ordinary DEBUG build with `CYPRESS_REMOTE` unset**, which is
    ///    every developer's default. `RemoteAccess.resolved` returns `.disabled` when the variable
    ///    is absent under `#if DEBUG`, `allowsNetwork` is `self == .live`, and `boot` fills this
    ///    only when `allowsNetwork` — so **a signed-in developer deleting their account on a debug
    ///    build takes the pure-local path and the service keeps the account.** That is the gate
    ///    working as designed rather than a defect, and it is written down here because the
    ///    behavior is invisible from this file and surprising from any other.
    ///
    /// **A release build is unconditionally `.live`** — the `#else` arm of `RemoteAccess.resolved`
    /// does not consult the environment — so shipping deletion is always remote-first. `DataLayer`
    /// carries the argument for why the gate is honored here at all; it is not repeated.
    ///
    /// It is a provider rather than a stored `Bool` because the answer changes underneath this
    /// struct: `RoutedAPI` is a value type held by every screen, and a session can end between the
    /// tap that opened the You tab and the tap that deletes. `AppSession.signedInUserID` is the one
    /// accessor whose answer matches what the *next request* would actually act on — it returns nil
    /// for a stored session whose refresh token has expired — so asking it here is asking the
    /// question the deletion is about to depend on.
    public let signedInUserID: (@Sendable () async -> UUID?)?

    /// A tree's name and position, which is all a grove row needs from the city file.
    ///
    /// It exists so `resolveGroveRows` can answer for a whole set at once. `TreeProfile` was what
    /// `entryFromCityFile` used to ask for per row, and it is two orders of magnitude more than the
    /// question: a profile carries photographs, observations, measurements, visits, care events and
    /// community notes, and this row draws a string and a pin.
    public struct CityFileRow: Sendable, Hashable {
        public let displayName: String
        public let coordinate: Coordinate

        public init(displayName: String, coordinate: Coordinate) {
            self.displayName = displayName
            self.coordinate = coordinate
        }
    }

    /// What the city file could say about a set of trees: the ones it named, and the ones it holds
    /// and **declines** to name.
    ///
    /// ── Why the second set exists, which is a correctness point and not bookkeeping ─────────────
    ///
    /// Two different things make a row not appear on screen, and collapsing them mislabels the read.
    /// A tree this installation's inventories do not carry at all is a piece of the service's answer
    /// that **did not make it** — under D16 an ordinary case, the other device was in another city —
    /// and `.fellBackToLocal` is the honest mark for it. A tree the inventories *do* carry, which
    /// D15 gives no name, is not a loss: it is the rule being applied, correctly, to a complete
    /// answer. Recording that as a degraded read would tell a §4.3 surface "showing what's on this
    /// phone" about a read where nothing was missing.
    ///
    /// PR #144's review is what separated them. The first cut had only the named dictionary, so an
    /// intended D15 refusal and a genuinely unresolvable row were the same absence and both marked
    /// the read degraded.
    public struct CityFileRows: Sendable {

        /// Trees the city file carries and D15 names.
        public let named: [UUID: CityFileRow]

        /// Trees the city file **carries** and D15 declines to name — a nickname-less community
        /// record, whose only species is one somebody asserted about it. Dropped from the grove, and
        /// not a reason to call the read degraded.
        public let unnamed: Set<UUID>

        public init(named: [UUID: CityFileRow], unnamed: Set<UUID>) {
            self.named = named
            self.unnamed = unnamed
        }
    }

    /// Names and positions for a set of trees at once, or nil to resolve them one at a time.
    ///
    /// **Injected, nil by default, and nil means the per-row form** — `signedInUserID`'s pattern
    /// above, for `signedInUserID`'s reason: every construction of this type that predates the seam
    /// keeps exactly the behavior it had. What fills it is `DataLayer.boot`, out of `LocalAPI`,
    /// which holds the batched statements (`TreeQueries.trees(ids:)` and the two beside it) that
    /// `CypressAPI` does not expose.
    ///
    /// ── Why the seam is here rather than on the protocol ───────────────────────────────────────
    ///
    /// `local` is an `any CypressAPI`, so the only tree read this file can reach is
    /// `treeProfile(id:)`, one tree at a time. That is the N+1 PR #131 removed one layer down and
    /// #176 removed the layer below that; it survived here because the router asks through the
    /// protocol. Widening `CypressAPI` would oblige fourteen preview doubles and every test double
    /// to answer a batched read they have no rows for, which is the tax `CypressAPI`'s own header
    /// records paying once already. A provider costs them nothing: they pass nothing and get the
    /// loop.
    ///
    /// It is only ever asked about rows the **service** named and the phone's own grove did not, so
    /// on a single-device installation it is never called at all.
    public let resolveGroveRows: (@Sendable ([UUID]) async -> CityFileRows)?

    /// The two names of a set of species at once, or nil to resolve them one at a time.
    ///
    /// `resolveGroveRows`' seam for `groveSpecies`' half of the same N+1: a species the account met
    /// on another device is looked up in the city file, and there is exactly one such lookup per row
    /// the service named that this phone has not met.
    public let resolveSpecies: (@Sendable ([UUID]) async -> [UUID: Species])?

    public init(
        local: any CypressAPI,
        remote: RemoteAPI,
        log: RemoteReadLog = RemoteReadLog(),
        signedInUserID: (@Sendable () async -> UUID?)? = nil,
        resolveGroveRows: (@Sendable ([UUID]) async -> CityFileRows)? = nil,
        resolveSpecies: (@Sendable ([UUID]) async -> [UUID: Species])? = nil
    ) {
        self.local = local
        self.remote = remote
        self.log = log
        self.signedInUserID = signedInUserID
        self.resolveGroveRows = resolveGroveRows
        self.resolveSpecies = resolveSpecies
    }

    // MARK: - Class L — the city layer, and no remote failure mode

    public func mapContent(in viewport: MapViewport) async throws -> MapContent {
        try await local.mapContent(in: viewport)
    }

    public func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        try await local.treesNear(coordinate, radiusM: radiusM, limit: limit)
    }

    public func species(id: UUID) async throws -> Species {
        try await local.species(id: id)
    }

    public func searchSpecies(query: String, limit: Int) async throws -> [Species] {
        try await local.searchSpecies(query: query, limit: limit)
    }

    public func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        try await local.speciesGuide(id: id, near: coordinate)
    }

    /// **Class L, and §4.2 is explicit that it is the one method that straddles**: the almanac's
    /// city aggregates gain nothing from a live query and its first-bloom sightings are community
    /// observations that go stale the moment somebody else records one. §4.2's own ruling is to
    /// route it L "with its community half arriving from the same delta that feeds `treeProfile`" —
    /// not R wholesale, "which would put the city aggregates on the network for the sake of the
    /// bloom line". The service exposes no almanac delta route, so the community half has nothing to
    /// arrive from yet and this is L in full.
    public func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac {
        try await local.almanac(near: coordinate, in: area)
    }

    /// Class L for `almanac`'s reason: the lists are aggregates over the *installed* inventories,
    /// which under D16 the service cannot know.
    public func areaChoices() async throws -> AreaChoices {
        try await local.areaChoices()
    }

    public func city(near coordinate: Coordinate?, in city: CitySelection) async throws -> CityAlmanac {
        try await local.city(near: coordinate, in: city)
    }

    public func exportLatest(_ format: ExportFormat) async throws -> Data {
        try await local.exportLatest(format)
    }

    // MARK: - Class D — device-only

    public func deviceContributions() async throws -> DeviceContributions {
        try await local.deviceContributions()
    }

    // MARK: - Writes: outbox first, and the send sink is not here

    public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        try await local.sync(items)
    }

    public func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        try await local.beginPhotoUpload(request)
    }

    public func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {
        try await local.uploadPhoto(at: localPath, ticket: ticket)
    }

    public func addTree(_ draft: TreeDraft) async throws -> Tree {
        try await local.addTree(draft)
    }

    public func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        try await local.claimSpecies(treeID: treeID, speciesID: speciesID)
    }

    public func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        try await local.correctSpecies(treeID: treeID, speciesID: speciesID)
    }

    public func flagWrongSpecies(treeID: UUID) async throws {
        try await local.flagWrongSpecies(treeID: treeID)
    }

    public func dismissSpeciesReview(flagID: UUID) async throws {
        try await local.dismissSpeciesReview(flagID: flagID)
    }

    public func flagNeverExisted(treeID: UUID) async throws {
        try await local.flagNeverExisted(treeID: treeID)
    }

    public func withdrawRecord(flagID: UUID) async throws {
        try await local.withdrawRecord(flagID: flagID)
    }

    public func dismissRecordReview(flagID: UUID) async throws {
        try await local.dismissRecordReview(flagID: flagID)
    }

    public func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {
        try await local.setPhotoVote(photoID: photoID, vote: vote)
    }

    public func deletePhoto(id: UUID) async throws -> PhotoDeletion {
        try await local.deletePhoto(id: id)
    }

    public func logHazardRedirect(_ event: HazardRedirectEvent) async throws {
        try await local.logHazardRedirect(event)
    }

    public func claimDevice(deviceUUID: UUID, userID: UUID) async throws {
        try await local.claimDevice(deviceUUID: deviceUUID, userID: userID)
    }

    /// **Remote first, and nothing local happens unless the service said yes** (the owner's ruling
    /// of 2026-08-23; ERRATA **E272** is the finding it closes).
    ///
    /// ── What this used to say, and why it stopped being true ───────────────────────────────────
    ///
    /// This method routed local, on the stated grounds that `DELETE /me` needs the client's
    /// still-queued `client_uuid`s, that this router holds no queue to read them from, and that
    /// `RemoteAPI.pendingOutboxKeys` "is the seam for that and the composition root is what fills
    /// it". **The composition root does fill it** — `DataLayer.boot` passes a provider that reads
    /// the outbox table — so the blocker expired in the wiring round and the routing did not follow.
    /// E272 recorded the gap: an account deleted in the You tab was deleted on the phone and left
    /// standing on the service, which is neither what R3 promises nor what Apple's account-deletion
    /// requirement asks of an app that offers Sign in with Apple (R72 ruling 2).
    ///
    /// ── The order, which is the whole of the ruling ────────────────────────────────────────────
    ///
    /// The service goes first and the phone follows it. On a remote failure this throws **before
    /// touching the local half**, so nothing is deleted anywhere and the person is still signed in
    /// on a phone holding everything they had — the state they were in before the tap. The
    /// alternative order was considered and refused by the owner: deleting locally first and letting
    /// the remote half fail would destroy someone's records on the phone while their account stood
    /// on the service with Apple never revoked, and it would do it silently, because there is
    /// nothing left on the phone that could ever retry.
    ///
    /// The person retries by tapping again. That is deliberate and there is no queue behind this: a
    /// deletion that retried itself in the background would be a destructive act happening at a
    /// moment nobody chose, and R3 puts every deletion behind copy that has just been read.
    ///
    /// **A signed-out installation keeps the pure-local path.** There is no account on the service
    /// to delete — `me.go` refuses a device credential with `forbidden`, "a device has no account to
    /// delete" — so asking would turn a working local deletion into a refusal. `signedInUserID` is
    /// how this method knows, and a nil provider means local, which is what every construction of
    /// this type that predates the seam gets.
    ///
    /// ── The one arm that is not transactional, stated rather than implied ──────────────────────
    ///
    /// If the service deletes and the *local* half then throws, the account is gone on the far side
    /// and intact on this phone. `AccountDeletion` runs in one transaction, so the phone is not left
    /// half-deleted — but it is left signed in to an account that no longer exists. That corrects
    /// itself in the direction of the deletion rather than away from it: the next request presenting
    /// that session is refused, which runs `AppSession`'s involuntary-discard path and ends the local
    /// session through `onSessionEnded` in the same run. It is the same self-correcting property
    /// E272's ruling relies on, seen from the other side.
    ///
    /// - Returns: the **local** outcome. The service's three counters describe rows on the service
    ///   and `RemoteAPI.deleteAccount` already declines to spread them across `Outcome`'s twenty
    ///   fields; merging them into the local tally here would double-count the same contribution
    ///   once for each side of the wire, and the tally's only consumer is a test asserting what this
    ///   phone did.
    /// - Throws: whatever the remote half threw — `APIError`, or a `SessionError` for a credential
    ///   that could not be refreshed — unchanged and unwrapped, so a caller can tell an offline
    ///   phone from a refusal. `AccountModel.deleteAccount` turns any of them into the one fact the
    ///   deletion sheet can draw: nothing was deleted.
    @discardableResult
    public func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        // ── What this guard reads, and what the screen above it reads ──────────────────────────
        //
        // Two different sources answer "is somebody signed in": this asks the **session**
        // (`AppSession.signedInUserID`, the Keychain), and the sheet that raised this call is drawn
        // from the **store** (`AccountModel.isSignedIn`, `app_state.currentUserID`). A person the
        // app draws as signed in, whose session is gone, therefore deletes locally — correctly,
        // since there is no credential left to delete on the service with.
        //
        // Two mechanisms keep that skew from persisting, and both were read rather than assumed:
        // `SessionRestore.reconcile` answers `.endSignedOut(userID: stored)` for `(.some, nil)` —
        // store says signed in, Keychain says nothing — so the next boot ends the local half; and
        // `DataLayer.boot` registers `onSessionEnded { try? await local.signOut() }`, so a session
        // the service refuses ends the local half in the same run without waiting for a launch.
        //
        // That is the extent of what is verified here: the two convergence paths exist and run in
        // the direction of signed-out. It is not a claim that no in-run window exists.
        guard let signedInUserID, await signedInUserID() != nil else {
            return try await local.deleteAccount(choice)
        }
        _ = try await remote.deleteAccount(choice)
        return try await local.deleteAccount(choice)
    }

    // MARK: - Class R, R-degraded: the account's own rows

    /// `GET /me/grove`, **joined** with the phone's grove.
    ///
    /// The service answers the account half — the favorite bit, the last visit, the `GroveRecord`,
    /// the hero photo — and no display name and no coordinate, because both are facts about the
    /// city's inventory (`reads.go`). So this is a join and not a switch, and the join is what makes
    /// the account mean something on a second device (§4.2: "these are this person's rows, and today
    /// they are this *device's* rows").
    ///
    /// **A row the service names and this phone has never seen is resolved through the city file**,
    /// which is where a name and a coordinate live. The rule for the name is
    /// `LocalAPI.displayNameIfPresent`'s, restated through the payload it already returns: the one
    /// active nickname (D15), else the species common name, and **never a fabricated label**. A tree
    /// this installation's city file does not carry at all — the other device was in another city,
    /// which D16 makes an ordinary case — is left out rather than drawn nameless at a coordinate
    /// this client would have to invent, and the read is marked degraded because part of the answer
    /// did not make it.
    ///
    /// ── This method is the **paint**, and it does not touch the wire ────────────────────────────
    ///
    /// The join above is what `refreshedGrove()` does. This returns the phone's answer and returns
    /// it now, because the owner ruled on 2026-09-01 that a tab paints from the phone and merges the
    /// account's half when it arrives: this read used to `await remote.groveDelta()` before it
    /// returned anything, so the first frame of My Grove cost a network round trip — a minute of it
    /// on an unreachable host, since nothing configured a timeout — and on a phone in a park it cost
    /// the whole of `URLSession`'s failure path before drawing rows that were on the disk the entire
    /// time.
    ///
    /// **It records nothing in `log`, and that is the honest mark.** `RemoteReadLog.outcome(of:)`
    /// reads nil as "the service was not consulted", which is exactly what happened here; recording
    /// `.fellBackToLocal` would say the service could not be reached, and it has not been asked yet.
    /// The outcome is written by the refresh, which is the call that does the asking.
    public func grove() async throws -> [GroveEntry] {
        try await local.grove()
    }

    /// `grove()`, one page — screen 08's read, forwarded to the phone for `grove()`'s reason above.
    ///
    /// **Overridden rather than left to the protocol default**, and the difference is the whole
    /// point of the page: the default builds the entire grove and cuts it, so on this route the
    /// pill would still pay for a thousand rows before drawing fifty. `LocalAPI`'s form asks the
    /// database for fifty.
    ///
    /// It does not touch the wire and records nothing in `log`, exactly as `grove()` does not. The
    /// account's half arrives through `refreshedGrove()`, behind the painted page.
    public func grovePage(cursor: String?, limit: Int) async throws -> Page<GroveEntry> {
        try await local.grovePage(cursor: cursor, limit: limit)
    }

    /// `grove()` again, with `GET /me/grove` merged in — the read that reaches the service.
    ///
    /// **What it is for**: it is delivered *behind* a painted screen. `DataLayer.boot` hands it to
    /// the composition root as a closure and `GroveModel` runs it in a background task once its
    /// local answer is on the glass, so a species or a tree the account met on another device
    /// appears a beat later rather than holding the first frame (the owner's ruling of 2026-09-01).
    ///
    /// **The join is unchanged.** Every semantic below — the later of the two visit dates,
    /// `record ?? existing.record` because a nil record is "this read did not answer that" and not
    /// zero (ERRATA E38), the re-sort on the joined dates — is the one this method carried when it
    /// was `grove()` itself.
    ///
    /// **Two things about the log did change, and both are corrections rather than side effects.**
    ///
    /// 1. *When* `.grove`'s outcome is written: after the paint rather than before it, so a surface
    ///    reading `log` is being told about the refresh. Same fact, arriving second.
    /// 2. *What counts as degraded.* `.live` used to mean "every row the service named reached the
    ///    screen", which folded an intended D15 refusal in with a genuinely unresolvable row. It now
    ///    means "nothing the service said was lost" — see `CityFileRows`, and PR #144's review, which
    ///    is where the two were separated.
    ///
    /// **A cancelled refresh records nothing at all.** `GroveModel` cancels an in-flight refresh when
    /// the tab is re-entered, and `try? await remote.groveDelta()` answers nil for a cancellation
    /// exactly as it does for an unreachable host — so without the check below, flipping tabs twice
    /// would leave `.fellBackToLocal` in the log against a service that was perfectly reachable.
    /// "We did not ask" is the truthful mark for a read we ourselves called off, and nil is how this
    /// log spells it (`RemoteReadLog.outcome(of:)`). PR #144's review found this.
    public func refreshedGrove() async throws -> [GroveEntry] {
        let mine = try await local.grove()
        guard let delta = try? await remote.groveDelta() else {
            // Nothing is recorded for a refresh we cancelled ourselves — see the note above.
            if !Task.isCancelled { await log.record(.grove, .fellBackToLocal) }
            return mine
        }

        var byTree = Dictionary(mine.map { ($0.treeID, $0) }, uniquingKeysWith: { first, _ in first })
        var everythingResolved = true

        // Every row the service named that this phone's own grove did not — the only rows the city
        // file has to be asked about. Resolved in **one** call rather than one per row: the per-row
        // form ran `LocalAPI.treeProfile(id:)` for each, and `TreeQueries`' own measurements put a
        // single-tree resolve at 221–327 ms over the bundled seed. On a single-device installation
        // this set is empty and nothing is asked at all.
        let unresolved = delta.map(\.treeID).filter { byTree[$0] == nil }
        let cityFileRows = await resolvedCityFileRows(for: unresolved)

        for row in delta {
            if let existing = byTree[row.treeID] {
                byTree[row.treeID] = GroveEntry(
                    treeID: existing.treeID,
                    displayName: existing.displayName,
                    coordinate: existing.coordinate,
                    // The later of the two: the account may have visited this tree from another
                    // phone since this one last did.
                    lastVisitedAt: [existing.lastVisitedAt, row.lastVisitedAt].compactMap { $0 }.max(),
                    isFavorite: row.isFavorite,
                    // The service counted the account's whole history; this phone counted its own.
                    // A nil record from the service is "this read did not answer that" (ERRATA E38),
                    // not zero, so the local tally stands rather than being erased by it.
                    record: row.record ?? existing.record,
                    heroPhotoID: row.heroPhotoID ?? existing.heroPhotoID
                )
                continue
            }
            guard let resolved = cityFileRows.named[row.treeID] else {
                // **Degraded only when the city file could not answer at all.** A tree it holds and
                // D15 declines to name (`CityFileRows.unnamed`) is the rule being applied to a
                // complete answer, not a piece of the answer going missing — see `CityFileRows`.
                if !cityFileRows.unnamed.contains(row.treeID) { everythingResolved = false }
                continue
            }
            byTree[row.treeID] = GroveEntry(
                treeID: row.treeID,
                displayName: resolved.displayName,
                coordinate: resolved.coordinate,
                lastVisitedAt: row.lastVisitedAt,
                isFavorite: row.isFavorite,
                record: row.record,
                heroPhotoID: row.heroPhotoID
            )
        }

        await log.record(.grove, everythingResolved ? .live : .fellBackToLocal)
        // The local read's order is `ContributionStore.groveOrderSQL` and `GroveRecord`'s header
        // pins that it is never an ordering by size. Re-sorting on the joined dates keeps that
        // ordering rather than appending the account's rows in whatever order the service listed
        // them.
        //
        // **It sorts by `GroveOrderKey` now, and the tie-break is the change.** This used to fall
        // back to `displayName` for two rows with no visit between them, which is a *different*
        // order from the one the query produces — and once screen 08 pages, two orders is two
        // answers to "which row comes after this one". A cursor derived from a list sorted one way
        // and handed to a query sorted the other lands in the wrong place, which shows a row twice
        // or not at all. `GroveOrderKey` is the query's own order, restated once and used by both.
        return byTree.values.sorted { $0.orderKey > $1.orderKey }
    }

    /// **The phone's `favorites` table — this read issues no request.**
    ///
    /// The endpoint it used to call is `GET /me/grove/{treeID}/favorite`, and that call now lives in
    /// `reconciledIsFavorite(treeID:)` below, which is the read that makes a favorite set on one
    /// phone show as set on another.
    ///
    /// ── This method is the **paint**, and the owner's ruling of 2026-09-02 is why ───────────────
    ///
    /// It used to ask the service *first* and fall back to the phone. The heart re-reads its own
    /// state after every write (RULINGS R2), so that round trip sat between a finger and the control
    /// answering it: `TreeProfileModel.write()` paints the tap optimistically, calls the writer, and
    /// then `await readFavorite()` — which is this read. On an unreachable host the heart therefore
    /// hung on `URLSession`'s failure path before settling, on a screen where the whole point of the
    /// re-read is that the control ends up agreeing with what is stored.
    ///
    /// **The owner ruled on 2026-09-02 that favorites answer from the phone.** The tap and the read
    /// are local and instant; the R2 re-read still reaches the service, in
    /// `reconciledIsFavorite(treeID:)` below, behind the painted control. This amends R2 in *where
    /// the answer comes from first* and in nothing else — R2's substance is that the heart is read
    /// rather than remembered, and that a write which did not land puts it back. Both still hold:
    /// the phone is the store R2 means, `OutboxQueue.pendingFavoriteState` still supplies the
    /// in-flight word ahead of it (#167), and a terminally failed toggle still reverts the control.
    ///
    /// **It records nothing in `log`** — `grove()`'s note, for the same reason.
    public func isFavorite(treeID: UUID) async throws -> Bool {
        try await local.isFavorite(treeID: treeID)
    }

    /// `isFavorite(treeID:)` again, asked of the service — the R2 re-read, moved off the tap.
    ///
    /// **What it is for**: a favorite set on another phone. It is delivered behind the painted
    /// heart, and it is the half that makes a favorite mean something on a second device, which is
    /// what this read was always for (§4.2). `DataLayer.boot` hands it over as a closure and it is
    /// nil when the gate is shut.
    ///
    /// **The service wins when it answers, and the phone answers otherwise** — the ordering the
    /// method had before the split, unchanged. What changed is only that nothing waits for it.
    ///
    /// **A cancelled reconcile records nothing**, for `refreshedGrove()`'s reason: the model cancels
    /// this when a tap overtakes it, and a cancellation must not be logged as a service that could
    /// not be reached.
    public func reconciledIsFavorite(treeID: UUID) async throws -> Bool {
        do {
            let answer = try await remote.isFavorite(treeID: treeID)
            await log.record(.isFavorite, .live)
            return answer
        } catch {
            if !Task.isCancelled { await log.record(.isFavorite, .fellBackToLocal) }
            return try await local.isFavorite(treeID: treeID)
        }
    }

    /// `GET /me/grove/species`, **joined** with the phone's.
    ///
    /// The service sends species ids and first-met dates and no names, and it declines to answer the
    /// ring's denominator at all — that is a fact about the *city's* inventory and under D16 a fact
    /// about which cities are installed, which the service does not know (`reads.go` says so in the
    /// same words). So the neighborhood half is always the phone's, and only the numerator is joined.
    ///
    /// A species the account met on another device is looked up in the city file for its two names.
    /// `firstMetAddress` is left nil for those rows, which drops the celebration callout's `on
    /// Noriega` clause — the address of a meeting that happened somewhere else is not a fact this
    /// phone holds, and `KnownSpecies` already reads nil as "the city recorded no address" rather
    /// than as an error.
    ///
    /// **This method is the paint and it does not touch the wire** — `grove()`'s note above, for the
    /// same ruling and the same reason. The join is `refreshedGroveSpecies()`, and this screen's
    /// Species pill is the one the owner reported as worst: it is the tab My Grove opens on, so its
    /// read was the one every visit waited through.
    public func groveSpecies() async throws -> GroveSpecies {
        try await local.groveSpecies()
    }

    /// `groveSpecies()` again, with `GET /me/grove/species` merged in — the read that reaches the
    /// service. See `refreshedGrove()` for what "refreshed" means here and what it does to `log`.
    public func refreshedGroveSpecies() async throws -> GroveSpecies {
        let mine = try await local.groveSpecies()
        guard let delta = try? await remote.groveSpeciesDelta() else {
            // `refreshedGrove()`'s cancellation note, for the same reason and the same reader.
            if !Task.isCancelled { await log.record(.groveSpecies, .fellBackToLocal) }
            return mine
        }

        var bySpecies = Dictionary(mine.known.items.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
        var everythingResolved = true

        // `refreshedGrove()`'s batching, over species rather than trees: one lookup for every row
        // the service named that this phone has not met, rather than one lookup per row.
        let unresolved = delta.map(\.speciesID).filter { bySpecies[$0] == nil }
        let resolvedSpecies = await resolvedSpecies(for: unresolved)

        for row in delta {
            if let existing = bySpecies[row.speciesID] {
                bySpecies[row.speciesID] = KnownSpecies(
                    speciesID: existing.speciesID,
                    scientificName: existing.scientificName,
                    commonName: existing.commonName,
                    // The *first* meeting, across every device. An account that met a species on an
                    // older phone met it then, not when this one caught up.
                    firstMetAt: min(existing.firstMetAt, row.firstMetAt),
                    firstMetAddress: existing.firstMetAddress
                )
                continue
            }
            guard let species = resolvedSpecies[row.speciesID] else {
                everythingResolved = false
                continue
            }
            bySpecies[row.speciesID] = KnownSpecies(
                speciesID: species.id,
                scientificName: species.scientificName,
                commonName: species.commonName,
                firstMetAt: row.firstMetAt,
                firstMetAddress: nil
            )
        }

        await log.record(.groveSpecies, everythingResolved ? .live : .fellBackToLocal)
        // `Series(complete:)` because both halves were whole reads: the service states a `total` over
        // the set rather than a page, and the local read is unpaged. Claiming completeness off a page
        // is the mistake `Series` exists to make unwritable (ERRATA E38).
        return GroveSpecies(
            neighborhood: mine.neighborhood,
            known: Series(complete: bySpecies.values.sorted { $0.firstMetAt < $1.firstMetAt })
        )
    }

    /// **The phone's membership table — this read issues no request.**
    ///
    /// The endpoint is `GET /me/map-membership` and the union with it is
    /// `refreshedMapMembership(_:)` below, which is where the both-sets rule is stated.
    /// ── This method is the **paint** ────────────────────────────────────────────────────────────
    ///
    /// `refreshedMapMembership(_:)` below is the union. This returns the phone's set and returns it
    /// now: pressing `Yours` or `Favorites` on screen 01 used to await the service before the map
    /// could narrow at all, so a filter chip over a table of tens of rows — already on this disk —
    /// cost a round trip before a single pin moved. `MapModel.membershipDidChange` deliberately
    /// resolves the narrow set *before* the wide query over 145,837 trees, which meant the wide
    /// query waited on the network too.
    ///
    /// **It records nothing in `log`** — `grove()`'s note, for the same reason.
    public func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        try await local.mapMembership(kind)
    }

    /// `mapMembership(_:)` again, unioned with `GET /me/map-membership`.
    ///
    /// **The two sets are unioned rather than replaced**, which is the semantic this read has always
    /// had and the reason it is a union: a tree hearted on this phone and not yet drained is in the
    /// local set and not the service's, and dropping it would take the heart off a tree the person
    /// just tapped — the same window `OutboxQueue.pendingFavorite` exists for.
    ///
    /// It is delivered behind a narrowed map, so a tree the account hearted on another device joins
    /// the filter a beat later rather than holding the chip. **A cancelled union records nothing**,
    /// for `refreshedGrove()`'s reason — `MapModel` cancels this whenever the chip changes again.
    public func refreshedMapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        let mine = try await local.mapMembership(kind)
        do {
            let theirs = try await remote.mapMembership(kind)
            await log.record(.mapMembership, .live)
            return mine.union(theirs)
        } catch {
            if !Task.isCancelled { await log.record(.mapMembership, .fellBackToLocal) }
            return mine
        }
    }

    /// **Local, because the geometry is local.** The set of ids is joinable and is joined above; a
    /// *coordinate* is not, because a coordinate comes from the attached inventory files and the
    /// service has no view of which of them this phone has installed. Reading it from anywhere else
    /// would put a pin on a map where the map has no tree.
    ///
    /// **And it is forwarded rather than inherited, which is the whole of why it is written out.**
    /// `CypressAPI` defaults `contributedPlaces()` to the empty array, so a `RoutedAPI` that did not
    /// name it would compile, satisfy the protocol, and answer `[]` for every reader in the shipping
    /// composition — the camera would never move. That is ERRATA E125's shape a second time.
    ///
    /// **The unit suite catches that, and this comment used to deny it** (PR #135 review, F1). The
    /// reviewer deleted this forward and ran the guard, which named the member exactly:
    /// `APIConformanceGuardTests.everyShippingConformanceDeclaresEveryRequirement` answered
    /// `missing → [contributedPlaces() -> [ContributedPlace]]`. That gate has covered `RoutedAPI`
    /// since #158 step 4, and this defect class is what it is for. Nothing here needs a second
    /// guard, and nobody should build one on the strength of this comment.
    ///
    /// What did happen on the branch is narrower, and is about *when* rather than about coverage:
    /// the requirement landed in one commit, the forward in a later one, and the **full** unit suite
    /// was not run in between — so `SeeAllOnMapUITests` caught the missing forward **first**, not
    /// **only**. A gate you have not run yet is not a gate you have.
    public func contributedPlaces() async throws -> [ContributedPlace] {
        try await local.contributedPlaces()
    }

    /// **Local, and this one cannot be joined — the reason is a sentence the service does not send.**
    ///
    /// `GET /me/journal` answers `{client_uuid, kind, tree_uuid, occurred_at, payload}`.
    /// `JournalEntry.summary` is built by the `UNION ALL` in `ContributionStore.journal` out of the
    /// local tables' own columns and then humanized by `LocalAPI.humanize`; rebuilding it here from
    /// the raw mutation would be a **second implementation of the same sentence**, in a second
    /// place, which is how two renderings of one fact drift apart. Writing a different sentence
    /// instead is inventing copy the mocks do not have (DECISIONS constraint 21).
    ///
    /// So the journal answers from the phone and **says that it did** — `.fellBackToLocal`, every
    /// time, which is the truthful mark for a read whose remote half is unreachable rather than
    /// merely unreached. Closing it is a server round that sends the summary, and it is written up in
    /// this round's errata entry.
    public func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        let page = try await local.journal(cursor: cursor, limit: limit)
        await log.record(.journal, .fellBackToLocal)
        return page
    }

    // MARK: - Class R, R-required: the community layer

    /// **The phone's profile — this read issues no request.**
    ///
    /// The merge it used to perform is `refreshedTreeProfile(id:)` below, whose head carries every
    /// rule of the join: what R-required means for the fallback, why the city half is never asked
    /// for, and how photographs and the two id sets combine.
    ///
    /// ── This method is the **paint**, and it does not touch the wire ────────────────────────────
    ///
    /// It returns the phone's profile and returns it now, on the owner's ruling of 2026-09-01
    /// extended to this read: every screen that opens a tree used to
    /// `await remote.treeCommunityHalf(id:)` before it drew anything, so opening *any* tree profile
    /// cost a network round trip. There are **fifteen** call sites through this router, not one — a
    /// sheet that only wanted the tree's name (`CareLogModel.loadName`) or its species
    /// (`CheckInModel.loadSpecies`) paid for a community half it never read.
    ///
    /// (`Features/Visit/VisitGates.swift` calls `treeProfile(id:)` five more times and is not one of
    /// the fifteen: it builds its own `LocalAPI` and has never gone through this router at all.)
    ///
    /// **It records nothing in `log`, and that is the honest mark** — `grove()`'s note above, for
    /// the same reason: nil is "the service was not consulted", which is what happened here.
    public func treeProfile(id: UUID) async throws -> TreeProfile {
        try await local.treeProfile(id: id)
    }

    /// `treeProfile(id:)` again, with `GET /trees/{id}`'s community half merged in.
    ///
    /// This is the acceptance criterion's last mile in one method: *"when I add a photo on my
    /// device, the photo propagates to all other users"* is this call returning a photograph the
    /// reading device never wrote. R-required means the local fallback "is not a degraded answer to
    /// the same question, it is a complete answer to a different one — this tree as this phone knows
    /// it — and it must say so rather than render as the tree" (§3.1). The saying-so is the log
    /// entry; the payload is the phone's, unchanged, so nothing on screen 03 breaks offline.
    ///
    /// **The city half is never asked of the service and the service never sends one.** The tree's
    /// position, its species and its inventory row are Class L, and a profile that fetched them
    /// would put the map's own data on the network for no gain.
    ///
    /// Photographs are merged by id, with the phone's row winning a collision: a photograph this
    /// device took has a `storageKey` and real pixel dimensions, and the service's row has neither.
    /// The own and deletable sets are unioned for the same reason they exist as separate sets —
    /// "own" is what this reader may *see* and "deletable" is what they may *unmake*, and the two
    /// differ on exactly the rows an account deletion anonymized.
    ///
    /// **What it is for**: it is delivered *behind* a painted profile, by the **six** surfaces that
    /// read `TreeProfile`'s photographs. `DataLayer.boot` hands it over as a closure on
    /// `refreshGrove`'s terms exactly, and it is nil when the gate is shut.
    ///
    ///   1. screen 03 (`TreeProfileModel`) — the hero;
    ///   2. the photo browser (`TreePhotosModel`) — the timeline itself;
    ///   3. the map's tree card (`MapModel.select`);
    ///   4. the memorial (`MemorialModel`) — hero, `First photo` milestone, the photo-count pill;
    ///   5. the activity screen (`ActivityModel`) — per-month counts and the first-photo date;
    ///   6. the share sheet (`ShareModel`) — and this one is the sharpest case in the app.
    ///
    /// **PR #147's review is why that list has six entries rather than three.** The first cut of
    /// this split reasoned that the community half is photographs, therefore only the surfaces that
    /// *draw* a photograph need it — and then named three of the six. The other three read
    /// `TreeProfile.visiblePhotos` too, and the phone can never supply the missing rows: nothing
    /// syncs anybody else's photographs down (`ContributionStore`), and the seed carries no photo
    /// table at all.
    ///
    /// Share is the sharpest because its predicate is different. `SharePresentation` takes
    /// `publiclyVisiblePhotos` — `moderationState == .approved` — and `.approved` is produced in
    /// exactly one place in the shipping app: this method's own decode
    /// (`RemoteAPI.treeCommunityHalf`). `moderation_state` defaults to `pending` and no local write
    /// path changes it, so a share card cut off from this closure carries **no** photograph
    /// unconditionally, rather than merely usually.
    ///
    /// The remaining **nine** router call sites are not handed this and lose nothing by it: they
    /// read a name, a species, a land context, a measurement, a visit list or a status, and the
    /// community half carries none of those (`TreeCommunityDelta` is photographs and two id sets).
    ///
    /// **The merge is unchanged** — every rule above is the one this method carried when it was
    /// `treeProfile(id:)` itself, including which halves are deliberately the phone's.
    ///
    /// **A cancelled refresh records nothing**, for `refreshedGrove()`'s reason and no other: these
    /// refreshes are cancelled when a profile is dismissed or a second pin is tapped, and
    /// `try? await remote.treeCommunityHalf(id:)` answers nil for a cancellation exactly as it does
    /// for an unreachable host.
    public func refreshedTreeProfile(id: UUID) async throws -> TreeProfile {
        let mine = try await local.treeProfile(id: id)
        guard let community = try? await remote.treeCommunityHalf(id: id) else {
            // Nothing is recorded for a refresh we cancelled ourselves — `refreshedGrove()`'s note.
            if !Task.isCancelled { await log.record(.treeProfile, .fellBackToLocal) }
            return mine
        }

        var photos = mine.photos.items
        let known = Set(photos.map(\.id))
        photos.append(contentsOf: community.photos.filter { !known.contains($0.id) })

        await log.record(.treeProfile, .live)
        return TreeProfile(
            tree: mine.tree,
            activeName: mine.activeName,
            species: mine.species,
            neighborhoodName: mine.neighborhoodName,
            cityShortName: mine.cityShortName,
            latestObservation: mine.latestObservation,
            observations: mine.observations,
            // Completeness is the *local* series', deliberately: the service's photo list is the
            // community half and this phone's is its own, so the union is whole only when the half
            // that could have been paged says it was whole. `Series` is the type that makes "a page
            // counted as a total" unwritable (ERRATA E38) and this is where that bites.
            photos: Series(
                items: photos.sorted { $0.capturedAt > $1.capturedAt },
                isComplete: mine.photos.isComplete
            ),
            measurements: mine.measurements,
            visits: mine.visits,
            careEvents: mine.careEvents,
            communityNotes: mine.communityNotes,
            siteLineageTreeID: mine.siteLineageTreeID,
            ownPhotoIDs: mine.ownPhotoIDs.union(community.ownPhotoIDs),
            deletablePhotoIDs: mine.deletablePhotoIDs.union(community.deletablePhotoIDs),
            anonymizedPhotoIDs: mine.anonymizedPhotoIDs,
            photoTallies: mine.photoTallies,
            inventorySource: mine.inventorySource,
            speciesCorrection: mine.speciesCorrection,
            recordDefect: mine.recordDefect,
            // The local answer, like `tree` itself: `tree_status_overrides` is this device's table
            // and the service has no view of it. Taking the remote half's value here would let a
            // merge quietly un-attribute a death this phone's reviewer confirmed.
            statusProvenance: mine.statusProvenance
        )
    }

    /// The bytes of a photograph, from the phone when it has them and from the service when it
    /// does not.
    ///
    /// **The phone is asked first, and that ordering is the whole design.** A photograph this device
    /// took is on this disk; fetching it over the network would spend a round trip and a presigned
    /// URL to get back bytes that are already here, and would fail in a park. The service is asked
    /// only for what this device never wrote — which is exactly the R-required case and exactly the
    /// photograph the acceptance criterion is about.
    ///
    /// A failure on *both* throws, and throws the remote error: at that point neither half has the
    /// bytes, and `PhotoAccess.swift` is explicit that empty `Data` is not an acceptable stand-in
    /// because "a zero-byte JPEG is a corrupt photograph".
    ///
    /// ── What each of the three paths records, and the two that were wrong ──────────────────────
    ///
    /// Review of PR #78 found this method recording outcomes its own enum forbids, so the mapping is
    /// written out here rather than left to be read off three one-line calls:
    ///
    /// - **Bytes off this disk: nothing is recorded.** It used to record `.live`, which
    ///   `Outcome.live` defines as "the service answered" — and the service was never asked. Nil
    ///   means the service was not consulted, which is precisely what happened and precisely what a
    ///   §4.3 surface needs to know: nothing about these bytes is missing.
    /// - **Bytes from the service: `.live`.** The acceptance criterion's last mile.
    /// - **Neither half has them: `.unanswered`, and it throws.** It used to record
    ///   `.fellBackToLocal`, whose own doc says "the value is what this phone knows" — there is no
    ///   value, and `degradedReads` would have offered a later round the copy "showing what's on
    ///   this phone" for a read that returned nothing.
    public func photoData(id: UUID) async throws -> Data {
        if let mine = try? await local.photoData(id: id), !mine.isEmpty {
            return mine
        }
        do {
            let bytes = try await remote.photoData(id: id)
            await log.record(.photoData, .live)
            return bytes
        } catch {
            await log.record(.photoData, .unanswered)
            throw error
        }
    }
}

// MARK: - Resolving a row the phone has never seen

/// **Internal rather than `private`, so the two arms can be compared against each other.**
///
/// `resolvedCityFileRows(for:)` has a provider arm and a loop arm that must answer identically, and
/// PR #144's review found them disagreeing on a row the fixture did not contain. The test that keeps
/// them honest has to be able to call *this* method with no provider — the real loop — rather than a
/// copy of it lifted into the test file, because a lifted copy is a third implementation and it
/// drifts silently, which is exactly how the disagreement stayed invisible. Nothing outside `Data`
/// calls either of these.
extension RoutedAPI {

    /// Names and positions for trees only the account knows about, from the city file.
    ///
    /// **Three outcomes per tree, and the difference between the last two is the whole of `CityFileRows`.**
    /// A tree is `named`; or it is `unnamed` — the inventories hold it and D15 gives it no name; or it
    /// is in neither, which means the inventories do not carry it at all. Under D16 the last is an
    /// ordinary case rather than an error (the other device may have been in a city this installation
    /// has not installed), and it is the only one of the three that marks the read degraded, because
    /// it is the only one where part of the service's answer did not make it.
    ///
    /// ── The name rule, which is D15's and which both arms now apply ────────────────────────────
    ///
    /// The one active nickname; else the **seed** species' common name; never a fabricated label. The
    /// second fallback deliberately does not consult a *community* record's species, and PR #144's
    /// review is why that sentence is here rather than merely implied: this loop used to read
    /// `profile.species?.commonName` unconditionally, and `LocalAPI.treeProfile` fills that field for
    /// a community record out of `tree.speciesCurrentID` — somebody's self-assertion about a tree they
    /// added. So a nickname-less community tree carrying a claimed species got named after it, which
    /// `LocalAPI.grove()` has always refused to do ("a self-asserted species is not a name the app
    /// puts on a tree", D15) and which this method's own comment already claimed it refused. The
    /// reviewer proved the two arms disagreed on exactly that row. The batch's rule is the ruled one;
    /// the loop was the drift, and the `source == .community` guard below is the correction.
    ///
    /// `GroveCityFileBatchTests` holds the two arms against each other row for row over a fixture
    /// that now carries that shape, because "the same answer, in one query" is exactly the kind of
    /// claim this project has been wrong about in a comment.
    func resolvedCityFileRows(for treeIDs: [UUID]) async -> CityFileRows {
        guard !treeIDs.isEmpty else { return CityFileRows(named: [:], unnamed: []) }
        if let resolveGroveRows { return await resolveGroveRows(treeIDs) }

        var named: [UUID: CityFileRow] = [:]
        var unnamed: Set<UUID> = []
        for treeID in treeIDs {
            guard let profile = try? await local.treeProfile(id: treeID) else { continue }
            // D15: a community record's species is a self-assertion, not a name. See the note above.
            let speciesName = profile.tree.source == .community ? nil : profile.species?.commonName
            guard let name = profile.activeName?.name ?? speciesName, !name.isEmpty else {
                unnamed.insert(treeID)
                continue
            }
            named[treeID] = CityFileRow(displayName: name, coordinate: profile.tree.coordinate)
        }
        return CityFileRows(named: named, unnamed: unnamed)
    }

    /// The two names of species only the account knows about, from the city file.
    ///
    /// `resolvedCityFileRows(for:)`'s shape over species: the provider when the composition root
    /// filled one, and otherwise the `local.species(id:)` loop this merge has always run. A species
    /// absent from the answer is one this installation's inventories do not carry, which the caller
    /// reads exactly as it read a throwing lookup.
    func resolvedSpecies(for speciesIDs: [UUID]) async -> [UUID: Species] {
        guard !speciesIDs.isEmpty else { return [:] }
        if let resolveSpecies { return await resolveSpecies(speciesIDs) }

        var found: [UUID: Species] = [:]
        for speciesID in speciesIDs {
            guard let species = try? await local.species(id: speciesID) else { continue }
            found[speciesID] = species
        }
        return found
    }
}
