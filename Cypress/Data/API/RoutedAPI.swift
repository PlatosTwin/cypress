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

    public enum Outcome: String, Sendable, Hashable {
        /// The service answered and its half is in the value returned.
        case live
        /// The service could not be asked, or refused, and the value is what this phone knows.
        /// True for everything this device did, and missing other devices of the same account.
        case fellBackToLocal
    }

    private var outcomes: [Read: Outcome] = [:]

    public init() {}

    func record(_ read: Read, _ outcome: Outcome) {
        outcomes[read] = outcome
    }

    /// The last outcome for a read, or nil when it has not been performed since launch.
    ///
    /// Nil is deliberately not `.fellBackToLocal`: "we have not asked" and "we asked and could not
    /// reach it" are different facts, and this project has drawn an empty state over the first of
    /// them before (`AccountModel.remindersFailed`, quoted in spec §4.3).
    public func outcome(of read: Read) -> Outcome? { outcomes[read] }

    /// Every read that is currently answering from the phone.
    public var degradedReads: Set<Read> {
        Set(outcomes.filter { $0.value == .fellBackToLocal }.keys)
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
/// R-required grade. Every one of them, on any remote failure, answers from the phone and records
/// `.fellBackToLocal` in `log`. A read that could-not-ask must never surface as an empty state:
/// "an empty state is a claim, and this project has already drawn one over a failed read" (R72
/// ruling 1).
///
/// **Class D — device-only.** `deviceContributions`. Local, always, because the rows have not been
/// sent and their being unsent is what the question is about.
///
/// ── Reads are routed. Writes are not, and that is a scope statement ────────────────────────────
///
/// §3.1's last line is "**Writes** are their own path: outbox first, both sinks (§2.1, §6)." A write
/// does not choose between two answers; it is applied locally and *also* sent, and the sending half
/// is `OutboxSendSink`, which `DataLayer` deliberately leaves unwired (ERRATA **E261** §2 — moving
/// `LocalAPI` across "does not add a network to a local write, it removes the local write"). So
/// every mutating method here goes to `local`, including `sync` and the photo pair, and the send
/// sink stays 2c's conscious act. `CypressTests/OutboxApplySendSplitTests.dataLayerWiresNoSendSink`
/// is the test that keeps that honest, and this file does not change it.
///
/// The nine mutations of spec §3.4 are local for a second, independent reason: they have no queue
/// behind them at all, and "making them remote-routed without a queue is what stops community
/// add-a-tree working in a park."
///
/// ── Nothing constructs this yet ────────────────────────────────────────────────────────────────
///
/// `DataLayer.api` is still a `LocalAPI` and this round does not change it. Wiring the router is a
/// composition-root act with a session behind it (spec §10 step 5), and doing it here would put a
/// half-built account path in front of every screen. The type, its routing table and its fallback
/// behavior are what step 4 owes; `CypressTests/RoutedAPITests` is where they are exercised.
public struct RoutedAPI: CypressAPI {

    /// The phone: the installed city file plus this device's own rows.
    public let local: any CypressAPI

    /// The service.
    public let remote: RemoteAPI

    /// Where a fallback is recorded. See `RemoteReadLog`.
    public let log: RemoteReadLog

    public init(local: any CypressAPI, remote: RemoteAPI, log: RemoteReadLog = RemoteReadLog()) {
        self.local = local
        self.remote = remote
        self.log = log
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
    public func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        try await local.almanac(near: coordinate)
    }

    public func city(near coordinate: Coordinate?) async throws -> CityAlmanac {
        try await local.city(near: coordinate)
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

    /// **Local, and the remote half is the account step's** (spec §10 step 5).
    ///
    /// `DELETE /me` needs the client's still-queued `client_uuid`s so the service can tombstone work
    /// that has not arrived yet, and this router holds no queue to read them from —
    /// `RemoteAPI.pendingOutboxKeys` is the seam for that and the composition root is what fills it.
    /// Calling the remote half without it would send an empty array, which is the *claim* that
    /// nothing is queued; R3's stated failure mode is deleting differently from what was asked.
    @discardableResult
    public func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        try await local.deleteAccount(choice)
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
    public func grove() async throws -> [GroveEntry] {
        let mine = try await local.grove()
        guard let delta = try? await remote.groveDelta() else {
            await log.record(.grove, .fellBackToLocal)
            return mine
        }

        var byTree = Dictionary(mine.map { ($0.treeID, $0) }, uniquingKeysWith: { first, _ in first })
        var everythingResolved = true

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
            guard let entry = try? await entryFromCityFile(for: row) else {
                everythingResolved = false
                continue
            }
            byTree[row.treeID] = entry
        }

        await log.record(.grove, everythingResolved ? .live : .fellBackToLocal)
        // The local read's order is `last_visited DESC NULLS LAST` and `GroveRecord`'s header pins
        // that it is never an ordering by size. Re-sorting on the joined dates keeps that ordering
        // rather than appending the account's rows in whatever order the service listed them.
        return byTree.values.sorted { left, right in
            switch (left.lastVisitedAt, right.lastVisitedAt) {
            case let (leftDate?, rightDate?): return leftDate > rightDate
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return left.displayName < right.displayName
            }
        }
    }

    /// `GET /me/grove/{treeID}/favorite` — one of the two Class R reads the service can answer whole.
    ///
    /// The heart re-reads its own state after every write (RULINGS R2), so this is the read that
    /// makes a favorite set on one phone show as set on another.
    public func isFavorite(treeID: UUID) async throws -> Bool {
        do {
            let answer = try await remote.isFavorite(treeID: treeID)
            await log.record(.isFavorite, .live)
            return answer
        } catch {
            await log.record(.isFavorite, .fellBackToLocal)
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
    public func groveSpecies() async throws -> GroveSpecies {
        let mine = try await local.groveSpecies()
        guard let delta = try? await remote.groveSpeciesDelta() else {
            await log.record(.groveSpecies, .fellBackToLocal)
            return mine
        }

        var bySpecies = Dictionary(mine.known.items.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
        var everythingResolved = true

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
            guard let species = try? await local.species(id: row.speciesID) else {
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

    /// `GET /me/map-membership` — the other Class R read the service can answer whole.
    ///
    /// It returns ids and nothing else, deliberately (a count of one's own contributions is what D1
    /// forbids as a user-visible figure), and an id set needs no city fact to be complete.
    ///
    /// **The two sets are unioned rather than replaced.** A tree hearted on this phone and not yet
    /// drained is in the local set and not the service's, and dropping it would take the heart off a
    /// tree the person just tapped — the same window `OutboxQueue.pendingFavorite` exists for.
    public func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        let mine = try await local.mapMembership(kind)
        do {
            let theirs = try await remote.mapMembership(kind)
            await log.record(.mapMembership, .live)
            return mine.union(theirs)
        } catch {
            await log.record(.mapMembership, .fellBackToLocal)
            return mine
        }
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

    /// `GET /trees/{id}`'s community half, **merged onto** the phone's profile.
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
    public func treeProfile(id: UUID) async throws -> TreeProfile {
        let mine = try await local.treeProfile(id: id)
        guard let community = try? await remote.treeCommunityHalf(id: id) else {
            await log.record(.treeProfile, .fellBackToLocal)
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
            recordDefect: mine.recordDefect
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
    public func photoData(id: UUID) async throws -> Data {
        if let mine = try? await local.photoData(id: id), !mine.isEmpty {
            await log.record(.photoData, .live)
            return mine
        }
        do {
            let bytes = try await remote.photoData(id: id)
            await log.record(.photoData, .live)
            return bytes
        } catch {
            await log.record(.photoData, .fellBackToLocal)
            throw error
        }
    }
}

// MARK: - Resolving a row the phone has never seen

private extension RoutedAPI {

    /// A whole `GroveEntry` for a tree only the account knows about, built from the city file.
    ///
    /// Returns nil rather than a placeholder when the city file does not carry the tree. Under D16
    /// that is an ordinary case and not an error — the other device may have been in a city this
    /// installation has not installed — and the alternative is a row with no name at a coordinate
    /// this client invented, on a screen whose whole subject is trees the reader knows.
    func entryFromCityFile(for row: RemoteAPI.GroveDelta) async throws -> GroveEntry? {
        guard let profile = try? await local.treeProfile(id: row.treeID) else { return nil }
        // `LocalAPI.displayNameIfPresent`'s rule, restated over the payload that carries both parts:
        // the one active nickname (D15), else the species common name. Never a fabricated label —
        // a tree with neither is skipped by the caller rather than named by this function.
        guard let name = profile.activeName?.name ?? profile.species?.commonName, !name.isEmpty else {
            return nil
        }
        return GroveEntry(
            treeID: row.treeID,
            displayName: name,
            coordinate: profile.tree.coordinate,
            lastVisitedAt: row.lastVisitedAt,
            isFavorite: row.isFavorite,
            record: row.record,
            heroPhotoID: row.heroPhotoID
        )
    }
}
