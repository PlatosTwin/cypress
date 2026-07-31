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

    /// Initials for the regulars row (C26).
    ///
    /// `TreeProfile` carries caretakers as bare `UUID`s — there is no name, handle or initial in
    /// the payload — so this cannot be derived from a real read today, and deriving a letter from a
    /// UUID would be fabricating an identity. It is injected instead: when the API grows caretaker
    /// identities (ARCHITECTURE §4: "if a screen needs data, the protocol grows a method") this is
    /// the one line that changes. Empty against `LocalAPI`, which is why the row does not render.
    var caretakerInitials: [String]

    init(
        treeID: UUID,
        api: any CypressAPI,
        caretakerInitials: [String] = [],
        setFavorite: @escaping (UUID, Bool) async -> Void = { _, _ in }
    ) {
        self.treeID = treeID
        self.api = api
        self.caretakerInitials = caretakerInitials
        self.setFavorite = setFavorite
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
        do {
            _ = try await api.claimSpecies(treeID: treeID, speciesID: species.id)
        } catch let error as APIError {
            speciesClaimFailure = TreeProfileCopy.speciesClaimFailure(error)
        } catch {
            speciesClaimFailure = TreeProfileCopy.speciesClaimFailure(.serverError)
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
    }

    /// Whether the store holds this tree for whoever is contributing right now.
    ///
    /// Through `grove()`, which is `GET /me/grove` — "favorited and visited trees" — and which E89
    /// left correct and callerless. It reads both ownership arms (the device's rows and the
    /// account's), which is exactly the question the heart asks, and it is a read the protocol
    /// already has: growing `CypressAPI` a per-tree favorite read would be the tidier call and it
    /// is a change to the backend boundary, not to a screen. If this screen ever needs it to be
    /// cheaper than "the trees you have contributed to", that is the method to add.
    ///
    /// A failed read is `false`: the cell draws its idle state when nothing is known, rather than
    /// claiming a favorite it could not confirm.
    private func storedFavorite() async -> Bool {
        guard let grove = try? await api.grove() else { return false }
        return grove.first { $0.treeID == treeID }?.isFavorite ?? false
    }
}
