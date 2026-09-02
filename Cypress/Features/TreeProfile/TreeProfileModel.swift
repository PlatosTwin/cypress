//
//  TreeProfileModel.swift
//  Cypress — Features/TreeProfile
//
//  Screen 03 / 14's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`").
//
//  It talks to `CypressAPI` and to nothing else — no GRDB, no SQLite, no network (ARCHITECTURE §4).
//
//  Two things arrive here that used not to (ERRATA E112, E113):
//
//  - **The favorite has a state, and the state is the store's.** The heart's on-state is read on
//    load and re-read after every write, so what the cell shows is what is stored rather than what
//    the last tap said. A write that does not land is visible as the control going back.
//  - **A record that is not a tree does not become a profile.** `TreeProfileDestination` is asked
//    once, here, under every entrance, and a vacant site leaves as `.elsewhere`.
//

import Foundation
import Observation

@MainActor
@Observable
final class TreeProfileModel {

    enum Phase {
        case loading
        /// Carries the derivation, not the raw payload: everything the view draws is decided in
        /// `TreeProfilePresentation`, which has no SwiftUI in it and can be reasoned about alone.
        case loaded(TreeProfilePresentation)
        /// This record belongs to another screen (E113). The view hands the route to the router and
        /// draws nothing — there is no honest half-profile to show while it goes.
        case elsewhere(Route)
        case failed(APIError)
    }

    private(set) var phase: Phase = .loading

    /// Whether **this contributor** currently holds this tree — the on-state of C8's first cell
    /// (RULINGS R2).
    ///
    /// It is a fact about the store, not about the session: it is read on load, written through on
    /// a tap so the control answers the finger immediately, and then re-read so the control ends up
    /// agreeing with what is actually stored. `false` is also what an unread or failed read shows,
    /// which is the honest default — "not known to be yours" and "not yours" draw the same way,
    /// and the drawn way is the state the cell has always had.
    private(set) var isFavorite = false

    let treeID: UUID
    private let api: any CypressAPI

    /// Performs the favorite write. The composition root owns it, because the owner of a
    /// contribution (D9) and the outbox are not a view's to resolve — see `ProfileFavoriteWriter`.
    ///
    /// It returns nothing on purpose. Whether the write worked is not this closure's word against
    /// the store's; it is `storedFavorite()`, read afterwards.
    private let setFavorite: (UUID, Bool) async -> Void

    /// Answers `storedFavorite()` when the composition root supplies it (#167).
    ///
    /// The root's answer (`ProfileFavoriteWriter.storedState`) is the outbox's in-flight word when
    /// there is one, and the applied row otherwise — which is what "what is stored" means in an app
    /// whose writes are durable at enqueue and applied at drain. Without it the model falls back to
    /// the applied-rows-only read below, which is all a bare `CypressAPI` can see.
    private let readFavorite: ((UUID) async -> Bool)?

    /// Initials for the regulars row (C26).
    ///
    /// `TreeProfile` carries caretakers as bare `UUID`s — there is no name, handle or initial in
    /// the payload — so this cannot be derived from a real read today, and deriving a letter from a
    /// UUID would be fabricating an identity. It is injected instead: when the API grows caretaker
    /// identities (ARCHITECTURE §4: "if a screen needs data, the protocol grows a method") this is
    /// the one line that changes. Empty against `LocalAPI`, which is why the row does not render.
    var caretakerInitials: [String]

    /// The profile again, with the community half merged in — or nil when there is no service to
    /// merge from (`DataLayer.refreshTreeProfile`).
    ///
    /// Nil is the default and nil means *no background task at all*: every preview and every unit
    /// test that builds this model passes nothing and gets the pure-local model it has always had.
    private let refreshProfile: ((UUID) async -> TreeProfile?)?

    /// The heart's R2 re-read, asked of the service — nil when there is none
    /// (`DataLayer.reconcileFavorite`). The owner's ruling of 2026-09-02.
    private let reconcileFavorite: ((UUID) async -> Bool?)?

    /// The background merge currently in flight, or nil.
    ///
    /// Held so it can be awaited — the only way a test can assert what the refresh did without
    /// reading a clock. `GroveModel.speciesRefresh`'s reasoning exactly, including the
    /// `@ObservationIgnored`: nothing draws these, and a view that observed them would re-render on
    /// a task's creation as well as on the phase change it produces.
    @ObservationIgnored private(set) var profileRefresh: Task<Void, Never>?
    @ObservationIgnored private(set) var favoriteReconcile: Task<Void, Never>?

    init(
        treeID: UUID,
        api: any CypressAPI,
        caretakerInitials: [String] = [],
        setFavorite: @escaping (UUID, Bool) async -> Void = { _, _ in },
        readFavorite: ((UUID) async -> Bool)? = nil,
        refreshProfile: ((UUID) async -> TreeProfile?)? = nil,
        reconcileFavorite: ((UUID) async -> Bool?)? = nil
    ) {
        self.treeID = treeID
        self.api = api
        self.caretakerInitials = caretakerInitials
        self.setFavorite = setFavorite
        self.readFavorite = readFavorite
        self.refreshProfile = refreshProfile
        self.reconcileFavorite = reconcileFavorite
    }

    var presentation: TreeProfilePresentation? {
        if case let .loaded(presentation) = phase { return presentation }
        return nil
    }

    func load() async {
        do {
            let profile = try await api.treeProfile(id: treeID)

            // The one gate, asked of the record rather than of the caller (E113). It runs before
            // any derivation, so nothing about a vacant site is ever computed as a tree profile.
            switch TreeProfileDestination(record: profile.tree) {
            case let .elsewhere(route):
                phase = .elsewhere(route)
                return
            case .profile:
                break
            }

            await readFavorite()
            phase = .loaded(
                TreeProfilePresentation(profile: profile, caretakerInitials: caretakerInitials)
            )
            startProfileRefresh()
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// Re-reads after a contribution lands. The screen keeps what it has while the read runs, so a
    /// visit that just synced does not blank the profile it was made from.
    func reload() async {
        await load()
    }

    /// Merges the community half in behind the painted profile.
    ///
    /// Nothing here can blank the screen. The refresh answers nil when it could not reach the
    /// service, and a nil leaves the painted phase exactly as it is — "an empty state is a claim,
    /// and this project has already drawn one over a failed read" (R72 ruling 1).
    ///
    /// The guard on `.loaded` before assigning is not ceremony: `load()` can move the phase to
    /// `.failed` or `.elsewhere` while a merge is in flight, and a merge landing after that would
    /// paint a profile over a screen that has deliberately gone somewhere else (E113).
    private func startProfileRefresh() {
        guard let refreshProfile else { return }
        profileRefresh?.cancel()
        let treeID = self.treeID
        let initials = caretakerInitials
        profileRefresh = Task { [weak self] in
            let merged = await refreshProfile(treeID)
            guard !Task.isCancelled, let self, let merged, case .loaded = self.phase else { return }
            self.phase = .loaded(
                TreeProfilePresentation(profile: merged, caretakerInitials: initials)
            )
        }
    }

    // MARK: - Naming the species, after the fact

    /// Whether the picker is up.
    var isNamingSpecies = false

    /// Why the last claim did not land, or nil. A sentence rather than an `APIError`, because the
    /// three refusals `claimSpecies` can return mean three different things to a reader and the
    /// mapping is a decision worth reading in one place (`TreeProfileCopy.speciesClaimFailure`).
    private(set) var speciesClaimFailure: String?

    /// Names the species on this tree.
    ///
    /// It reloads rather than patching the presentation in place, for `write()`'s reason one section
    /// down: the screen's job is to show what is stored, and a model that edited its own copy would
    /// show a claim that had been refused. The failure sentence is cleared first so a retry that
    /// works does not leave the last refusal on screen.
    func claimSpecies(_ species: Species) async {
        speciesClaimFailure = nil
        isNamingSpecies = false
        let correcting = isCorrectingSpecies
        isCorrectingSpecies = false
        do {
            if correcting {
                _ = try await api.correctSpecies(treeID: treeID, speciesID: species.id)
            } else {
                _ = try await api.claimSpecies(treeID: treeID, speciesID: species.id)
            }
        } catch let error as APIError {
            speciesClaimFailure = correcting
                ? TreeProfileCopy.speciesCorrectionFailure(error)
                : TreeProfileCopy.speciesClaimFailure(error)
        } catch {
            speciesClaimFailure = correcting
                ? TreeProfileCopy.speciesCorrectionFailure(.serverError)
                : TreeProfileCopy.speciesClaimFailure(.serverError)
        }
        await reload()
    }

    // MARK: - Correcting a claim (#86, #124)

    /// Whether the picker that is up is correcting an existing claim rather than making a first one.
    ///
    /// One picker, two acts. The sheet is identical and the *write* is not: a first claim is
    /// `claimSpecies`, guarded in SQL on there being nothing to supersede, and a correction is
    /// `correctSpecies`, guarded on who is asking. A flag set when the sheet opens decides which
    /// call the pick makes, rather than the model inferring it from the presentation — inferring
    /// would decide at pick time from a payload read before the sheet went up, and the two verbs
    /// throw different refusals that need different sentences.
    private(set) var isCorrectingSpecies = false

    func beginCorrectingSpecies() {
        speciesClaimFailure = nil
        isCorrectingSpecies = true
        isNamingSpecies = true
    }

    /// Canceling the picker leaves neither flag set, so the next open starts from whatever the
    /// screen offers then.
    func cancelNamingSpecies() {
        isNamingSpecies = false
        isCorrectingSpecies = false
    }

    /// Reports the species as wrong (#124). A refusal becomes a sentence, exactly as a claim's does.
    func reportSpeciesAsWrong() async {
        speciesClaimFailure = nil
        do {
            try await api.flagWrongSpecies(treeID: treeID)
        } catch let error as APIError {
            speciesClaimFailure = TreeProfileCopy.speciesReportFailure(error)
        } catch {
            speciesClaimFailure = TreeProfileCopy.speciesReportFailure(.serverError)
        }
        await reload()
    }

    /// Answers an open report by leaving the species where it is.
    func keepSpecies(flagID: UUID) async {
        speciesClaimFailure = nil
        do {
            try await api.dismissSpeciesReview(flagID: flagID)
        } catch let error as APIError {
            speciesClaimFailure = TreeProfileCopy.speciesReportFailure(error)
        } catch {
            speciesClaimFailure = TreeProfileCopy.speciesReportFailure(.serverError)
        }
        await reload()
    }

    // MARK: - The record itself (task #125)

    /// Why the last record-defect write did not land, or nil.
    ///
    /// Its own property rather than a share of `speciesClaimFailure`, because the two controls sit
    /// in different blocks of the screen and a refusal has to appear under the one it belongs to. A
    /// shared sentence would print "this tree comes from the city inventory" under the species line
    /// after a tap two hundred points away.
    private(set) var recordDefectFailure: String?

    /// Whether the record this screen is about has just been withdrawn.
    ///
    /// The view watches it and pops. Not a phase: the read that follows already answers `.notFound`
    /// — `LocalAPI.treeProfile` refuses a withdrawn community row — so the screen is honest either
    /// way, and this only decides whether the reader is left looking at a failure sentence for a
    /// record they themselves just withdrew.
    private(set) var withdrewRecord = false

    /// Reports that this record never held a tree (#125).
    func reportNeverExisted() async {
        recordDefectFailure = nil
        do {
            try await api.flagNeverExisted(treeID: treeID)
        } catch let error as APIError {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(error)
        } catch {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(.serverError)
        }
        await reload()
    }

    /// Answers an open report by withdrawing the record. Lead only; the gate is on the write.
    func withdrawRecord(flagID: UUID) async {
        recordDefectFailure = nil
        do {
            try await api.withdrawRecord(flagID: flagID)
            withdrewRecord = true
        } catch let error as APIError {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(error)
        } catch {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(.serverError)
        }
        await reload()
    }

    /// Answers an open report by leaving the record where it is.
    func keepRecord(flagID: UUID) async {
        recordDefectFailure = nil
        do {
            try await api.dismissRecordReview(flagID: flagID)
        } catch let error as APIError {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(error)
        } catch {
            recordDefectFailure = TreeProfileCopy.recordDefectFailure(.serverError)
        }
        await reload()
    }

    // MARK: - The favorite (RULINGS R2)

    /// The taps, in the order they were made.
    ///
    /// Each tap is a separate statement with its own key now that the heart has an on-state, so two
    /// quick taps are "on" and then "off" rather than one replayed "on" (E101's trick, retired).
    /// That makes their *order* load-bearing: run concurrently, two writes and two re-reads can
    /// interleave and leave the cell showing whichever read happened to land last. Chaining them
    /// keeps the last tap the last word.
    private var writes: Task<Void, Never>?

    /// Toggles the favorite. Returns the task so a test can wait for it; the view does not.
    @discardableResult
    func toggleFavorite() -> Task<Void, Never> {
        let previous = writes
        let task = Task { [weak self] in
            await previous?.value
            await self?.write()
        }
        writes = task
        return task
    }

    /// How many taps this screen has performed.
    ///
    /// **A read that started before a tap does not get to answer for it** (ERRATA E184). Every
    /// favorite read here is `await`ed, which means it takes its snapshot, gives up the main actor,
    /// and assigns whenever it gets it back. The taps were ordered against each other by `writes`;
    /// the *reads* were ordered against nothing. `load()` is not only called on first appearance —
    /// `TreeProfileView` calls `reload()` when the screen comes back to the front and again when a
    /// sheet closes over it — so a refresh could be in flight, holding an answer taken a moment
    /// before the finger arrived, and land on top of a favorite that had just been stored.
    ///
    /// The row was in the database and the cell said off: "I tapped Favorite and nothing happened",
    /// which is the only shape that report can take on a control whose state is read rather than
    /// remembered (RULINGS R2). Stamping each read with the tap count it was taken under, and
    /// dropping it if that has moved, is what keeps the last tap the last word — the same sentence
    /// `writes` already makes about the writes, extended to the reads that answer them.
    private var taps = 0

    private func write() async {
        let desired = !isFavorite
        taps += 1
        // The control answers the finger immediately…
        isFavorite = desired
        await setFavorite(treeID, desired)
        // …and then answers the store. If the write did not land, this is where the heart goes
        // back to where it was, which is the state E101 recorded as unavailable and R2 requires.
        await readFavorite()
    }

    /// Reads the store's answer and assigns it, unless a tap happened while the read was in flight.
    ///
    /// Dropping the answer rather than re-reading is deliberate: the tap that overtook this read has
    /// its own re-read at the end of `write()`, so the store still gets the last word — one read
    /// later, and from a snapshot that includes the tap.
    private func readFavorite() async {
        let generation = taps
        let stored = await storedFavorite()
        guard generation == taps else { return }
        isFavorite = stored
        startFavoriteReconcile()
    }

    /// Asks the service what it holds, behind the painted heart — the R2 re-read, moved off the tap.
    ///
    /// ── What the owner's ruling of 2026-09-02 moved, and what it did not ────────────────────────
    ///
    /// `storedFavorite()` above used to reach the service *first* (`RoutedAPI.isFavorite` was
    /// remote-first), so the re-read at the end of `write()` put a network round trip between a
    /// finger and the control settling. The phone answers that now and this reconciles behind it.
    /// R2 is otherwise untouched: the heart is still read rather than remembered, and a write that
    /// did not land still puts it back — `storedFavorite()` is what does that, unchanged.
    ///
    /// **The tap still wins, by the same counter** (ERRATA E184). A reconcile is a read like any
    /// other, and it is a *slower* one, so it is exactly the read most likely to be holding a stale
    /// answer when a finger arrives. It is stamped with the tap count it was taken under and dropped
    /// if that has moved — and cancelled outright when the next read starts, so a reconcile cannot
    /// queue up behind its own predecessor.
    ///
    /// **A nil answer changes nothing.** Nil is "the service was not reached", and the phone's
    /// answer is already on the glass; replacing it with `false` would take the heart off a tree
    /// this device holds because a network failed (R72 ruling 1).
    private func startFavoriteReconcile() {
        guard let reconcileFavorite else { return }
        favoriteReconcile?.cancel()
        let generation = taps
        let treeID = self.treeID
        favoriteReconcile = Task { [weak self] in
            let answer = await reconcileFavorite(treeID)
            guard !Task.isCancelled, let self, let answer, generation == self.taps else { return }
            self.isFavorite = answer
        }
    }

    /// Whether the store holds this tree for whoever is contributing right now.
    ///
    /// Through `readFavorite` when the composition root supplied one — see its declaration, and
    /// #167 for why "the store" has to include the outbox's in-flight word: the write path is
    /// durable at enqueue and applied at drain, and a re-read that only saw applied rows put the
    /// heart back off over a favorite that was saved and simply had not been carried across yet
    /// (a busy drain, or a batch already full of older work).
    ///
    /// Without one, `isFavorite(treeID:)` — the per-tree arm of `GET /me/grove`, which reads both
    /// ownership arms (the device's rows and the account's, E89), the exact question the heart asks.
    ///
    /// A failed read is `false`: the cell draws its idle state when nothing is known, rather than
    /// claiming a favorite it could not confirm.
    private func storedFavorite() async -> Bool {
        if let readFavorite { return await readFavorite(treeID) }
        return (try? await api.isFavorite(treeID: treeID)) ?? false
    }
}
