//
//  DebugDeepLink.swift
//  Cypress — App
//
//  A launch-time door into any screen, for the UI test target and nothing else (ERRATA E117).
//
//  ── Why this exists ───────────────────────────────────────────────────────────────────────
//  `AccessibilityTreeTests` (E116) checks the accessibility tree as a tree, and reaches exactly one
//  screen: 01, plus its chrome. Everything past the map is behind a tap on a pin, which is behind a
//  MapKit basemap that renders asynchronously and places its annotations wherever the camera happens
//  to settle. A UI test that drives the app by tapping map pixels is a test that fails for reasons
//  that have nothing to do with accessibility, and the sixteen screens behind that tap have never had
//  their tree read by anything.
//
//  So the test says which screen it wants and the app opens it. What is then asserted is the same
//  thing E116 asserts — that the elements a VoiceOver user needs are in the tree, labelled, and
//  reachable — on screens that could not otherwise be reached at all.
//
//  ── What it deliberately is not ───────────────────────────────────────────────────────────
//  **Not a URL scheme.** A registered scheme is product surface: it appears in `Info.plist`, it ships,
//  and any app on the phone can then drive this one. A test seam should not be a public entrance. An
//  environment variable is readable only by whoever launched the process.
//
//  **Not a fixture loader.** It resolves real records out of the real seed, so the trees these tests
//  read are the trees the app draws. A screen populated from a fixture would prove that the fixture is
//  accessible. `ScreenSweepShots` already photographs the fixtures; this is the other half.
//
//  **Not compiled into Release.** The whole file is `#if DEBUG`, and `RootView`'s call site is too.
//
//  ── The one thing it must never do quietly ────────────────────────────────────────────────
//  Fail. If resolution finds no record, the obvious behaviour is to leave the app on screen 01 — and
//  then every test in the suite passes while asserting nothing, because screen 01 is accessible and
//  the assertions never noticed they were on it. So a failure draws itself, in words, on top of the
//  app. See `DebugDeepLink.Failure`.
//

#if DEBUG
import Foundation

/// The test-only entrance. `#if DEBUG`; see the file comment.
enum DebugDeepLink {

    /// Read from the environment rather than `launchArguments`, for two reasons: an argument of the
    /// form `-name value` is also consumed by `NSUserDefaults` as a registered default, which means a
    /// test seam would be writing to the user's preferences; and `CYPRESS_SEED_PATH` and
    /// `CYPRESS_SHOT_DIR` already establish the convention in this codebase.
    static let environmentKey = "CYPRESS_SCREEN"

    /// The screens the harness can open, named as the UI test names them.
    ///
    /// **Screen 19, the memorial, is reachable now — the data changed (ERRATA E124-B).** The shipped
    /// seed still holds only `alive` and `vacant_site`, so there is no `removed` row to resolve. But
    /// the local moderation route can *make* one: a lead confirms an `appears_removed` review and the
    /// tree gains a device-side `removed` override. The `memorial` case below writes that override on a
    /// real standing seed tree (`debugMarkRemoved`) and opens 19 over it — a memorial over a record
    /// that this device really does now hold as removed, not a lie over a living tree. E117's
    /// "unreachable-until-the-data-changes" is discharged.
    ///
    /// Screen 04 (the camera) is absent for a different reason: presenting it raises a system
    /// permission alert, and what the test would then read is Springboard's tree, not Cypress's.
    ///
    /// Screen 15 (the account ask) is absent because it is not a `Route`: it is presented from inside
    /// the visit-save flow on the third save (`VisitSavedView`), the same reason screen 18 is not
    /// here. The harness drives `AppRouter`, which has no case that opens it. It signs in locally now
    /// (ERRATA E124), but through that flow, not a deep link.
    enum Screen: String, CaseIterable {
        // Pushed destinations.
        case treeProfile        // 03
        case site               // the vacant planting site (E107)
        case species            // 07
        case checkIn            // 05
        case report             // 06
        case growthHistory      // 11
        case activity           // 13
        case measure            // 16
        case outbox             // 17
        case memorial           // 19 — reachable now via a local removal override (ERRATA E124-B)
        case photos             // 20 — the photo browser (ERRATA E125)
        case photoHero          // 03 with photographs on it, which the seed alone cannot produce
        /// 03 over a **community** tree carrying a contributor's species (ERRATA E141) — the state
        /// this project has no seed record for, because every one of them is added on the device.
        case speciesClaim
        /// The same, with no species: the state that offers to be named.
        case speciesUnclaimed
        /// Screen 20 over a **community add** — one tree, one photograph, the photograph that
        /// BUILD-PLAN §6 required in order to add it (ERRATA E147). The one state where deleting a
        /// photograph leaves a record its own creation rule forbids, and the only way to look at
        /// what the app says about that before the tap.
        case communityPhotos
        // Presented over the tab root.
        case careLog            // 09
        case share              // 10
        // Tab roots other than the map, which needs no deep link.
        case grove              // 08
        case journal            // 12 — the Journal tab's `Neighborhood` segment
        /// The contributor's own journal — the Journal tab's other segment. It draws from this
        /// device's contributions, so on a device that has made none it is the empty state, which is
        /// the state worth photographing anyway.
        case journalList
        case you                // 18
        case moderationReview   // the You tab with a lead's open review (ERRATA E124-B)
        /// The community add's pin step — a map with a movable pin, opened on its own.
        ///
        /// It is not a `Route` and never will be: it is a *phase* of `VisitAddTreeModel`, the same
        /// way screen 04 and screen 18 are steps of `VisitFlowView` rather than destinations
        /// (DECISIONS constraint 21). What makes it deep-linkable anyway is that the view takes a
        /// coordinate and two closures and owns no data — see `Standalone`.
        case pinAdjust
    }

    /// A screen the harness presents directly, because it is not on any router.
    ///
    /// **The narrow exception to "not a fixture loader".** Every other case resolves a real record
    /// out of the real seed, and this one has no record to resolve: its whole input is a GPS fix, and
    /// the test host has no phone. `VisitLocationProvider(pinnedFix:)` is already this codebase's
    /// answer to that exact problem, for the same reason, on the screen next door — an offscreen
    /// renderer reports `notDetermined` and stays there. So the fix is pinned to the map's own
    /// opening centre, which is a real place with real streets under it.
    ///
    /// **It writes nothing**, which is the other half of the rule `photographedTree(_:)` encodes: a
    /// case that writes persistent state must not write it onto a tree another case reads. This case
    /// touches no tree, no photograph and no row — it presents a view and takes a coordinate back.
    /// There is nothing for a later run, or a neighbouring case, to find.
    enum Standalone: Equatable {
        case pinAdjust(anchor: Coordinate, accuracyM: Double)
    }

    /// The fix the pin screen opens on, and a plausible street-canyon accuracy to draw beside it.
    /// The centre is `MapLayout.defaultCentre` for `centre`'s own reason: what the tests see is what a
    /// tester sees on launch.
    static let pinAdjustFix = Standalone.pinAdjust(anchor: centre, accuracyM: 24)

    /// Why a requested screen did not open. Rendered on top of the app, in words, by `RootView` —
    /// never swallowed. A silent failure here turns the whole suite into a suite that passes on
    /// screen 01.
    struct Failure: Error {
        let screen: String
        let reason: String

        var message: String { "DEEP LINK FAILED · \(screen) · \(reason)" }
    }

    /// What the launching process asked for, if anything.
    ///
    /// An unrecognised value is deliberately distinguishable from no value at all: `.some(.failure)`
    /// so a typo in a test's screen name fails loudly instead of silently testing the map.
    static func requested(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Result<Screen, Failure>? {
        guard let raw = environment[environmentKey], !raw.isEmpty else { return nil }
        guard let screen = Screen(rawValue: raw) else {
            return .failure(Failure(screen: raw, reason: "no screen by that name"))
        }
        return .success(screen)
    }

    // MARK: - Resolution

    /// Where records are looked for: the map's own opening camera, so the trees these tests read are
    /// the trees a tester sees on launch.
    private static let centre = MapLayout.defaultCentre
    /// Wide enough to hold every status the cases below ask for, and narrow enough to stay one index
    /// scan.
    ///
    /// **4,000, raised from 500 by #91.** Under the DataSF export 44 of the 500 records nearest the
    /// map's opening centre were vacant planting sites, so 500 was ample. The seed is now built from
    /// SF Public Works' own inventory, which has no vacant-site category at all — 153 sites in the
    /// whole city against 12,518 — and the nearest one to the centre is the **1,181st** record by
    /// distance. `site` therefore failed to resolve, loudly and correctly (E117): the harness said
    /// `none among the 500 records nearest 37.7596, -122.4269` rather than quietly opening some other
    /// screen, which is exactly what that failure message was written for.
    ///
    /// The fix is the window, not the assertion. 4,000 holds the nearest site with room to spare and
    /// still resolves in a few milliseconds; if the number of sites falls further, this fails again
    /// and says so, which is the property worth keeping.
    private static let radiusM: Double = 3_000
    private static let candidateLimit = 4_000

    /// Opens `screen`, resolving whatever record it needs out of the seed.
    ///
    /// Ordering is `nearest`'s — by distance from a fixed point — so the same tree is chosen on every
    /// launch and a failing test names a record somebody can go and look at.
    /// - Parameter present: how the composition root shows a screen that is on no router. Defaults to
    ///   discarding, so a caller that only cares about routed screens does not have to supply one.
    @MainActor
    static func open(
        _ screen: Screen,
        api: LocalAPI,
        router: AppRouter,
        present: (Standalone) -> Void = { _ in }
    ) async -> Failure? {
        do {
            switch screen {
            case .treeProfile:
                router.push(.treeProfile(try await standingTree(api)))
            case .site:
                router.push(.site(try await vacantSite(api)))
            case .checkIn:
                router.push(.checkIn(try await standingTree(api)))
            case .report:
                router.push(.report(try await standingTree(api)))
            case .growthHistory:
                router.push(.growthHistory(try await standingTree(api)))
            case .activity:
                router.push(.activity(try await standingTree(api)))
            case .measure:
                // **`measuredTree`, not `standingTree`** — see that function. This case does not
                // write, but the test behind it does, and a saved reading outlives the launch
                // (ERRATA E133).
                router.push(.measure(try await measuredTree(api)))
            case .species:
                router.push(.species(try await anySpecies(api)))
            case .outbox:
                router.tab = .you
                router.push(.outbox)
            case .memorial:
                // The data changes here (ERRATA E124-B): mark the nearest standing tree removed, then
                // open its memorial. The tree is a real seed record, and after the override this device
                // genuinely holds it as removed — so 19 draws over a memorial, not over a living tree.
                let id = try await standingTree(api)
                try await api.debugMarkRemoved(treeID: id)
                router.push(.memorial(id))
            case .photos, .photoHero:
                // The data changes here too (ERRATA E125), and for the same reason as `.memorial`:
                // the shipped seed holds no photographs at all, because every photograph in this app
                // is one somebody took. `debugSeedPhotos` writes three, through the same rows and
                // the same files the shutter writes, so screen 20 lists real records and screen 03's
                // hero draws real bytes rather than the gradient placeholder.
                //
                // **`photographedTree`, not `standingTree`** — see that function. Seeding is
                // persistent, and a tree with photographs on it is a different tree.
                let id = try await photographedTree(api)
                try await api.debugSeedPhotos(treeID: id)
                router.push(screen == .photos ? .photos(id) : .treeProfile(id))
            case .speciesClaim, .speciesUnclaimed:
                // The data changes here, like `.memorial` and `.photos`, and for the strongest form
                // of the same reason: the seed contains no community trees at all, so there is no
                // record to resolve and the only honest harness is one that adds one the way the app
                // does. `debugAddCommunityTree` goes through `addTree`.
                //
                // Each case gets its **own** coordinate, well outside the other's 10 m dedupe circle
                // and outside the seed's own trees, because the rule this file already keeps —
                // a case that writes persistent state must not write it onto a record another case
                // reads — applies twice over to a table whose write is refused by proximity.
                let spot = screen == .speciesClaim ? claimedSpot : unclaimedSpot
                let id = try await api.debugAddCommunityTree(
                    near: spot,
                    speciesQuery: screen == .speciesClaim ? "Platanus" : nil
                )
                router.push(.treeProfile(id))
            case .communityPhotos:
                // A community add with the one photograph that made it addable, opened on screen 20
                // — the surface where it can be deleted, and the only place in the app where a
                // delete can leave a record violating its own creation rule (ERRATA E147).
                //
                // Resolved before it is added, unlike `.speciesClaim`, because this case exists to
                // have its photograph *deleted*: a second run would otherwise trip the 10 m
                // proximity dedupe against the tree the first run left standing, and the harness
                // would draw its failure instead of the screen. One photograph, not three, because
                // "the only photograph of a community add" is the state being looked at.
                let existing = try await api.treesNear(
                    communityPhotoSpot, radiusM: TreeDraft.proximityDedupeRadiusM, limit: 1
                ).first?.tree.id
                // Spelled out rather than with `??`, which is an autoclosure and cannot be `await`ed.
                let id: UUID
                if let existing {
                    id = existing
                } else {
                    id = try await api.debugAddCommunityTree(near: communityPhotoSpot, speciesQuery: nil)
                }
                try await api.debugSeedPhotos(treeID: id, count: 1)
                // The **profile**, not screen 20, even though the photo browser is what this case is
                // about. Pushing both at once was tried and is a worse harness than it looks: a
                // destination that is covered before it has ever been on screen gets no appearance
                // event, so `TreeProfileView`'s E127 reload-on-reappear never arms, and coming back
                // from a deletion draws a stale `1 photo · since 2026` over a tree that no longer has
                // one. That is the harness lying about the app — the real path (03, tap the pill,
                // delete, back) refreshes correctly — and a screenshot of it would have been read as
                // a defect. So the deep link ends where a person starts, and the pill is a tap away.
                router.push(.treeProfile(id))
            case .moderationReview:
                // Put the lead's review queue in front of a screenshot: open a removal review on a real
                // tree, promote this account to a lead, and show the You tab, where the section draws.
                let id = try await standingTree(api)
                try await api.debugSeedRemovalReview(treeID: id)
                try await api.setRole(.coordinator)
                router.tab = .you
            case .careLog:
                router.present(.careLog(try await standingTree(api)))
            case .share:
                router.present(.share(try await standingTree(api)))
            case .grove:
                router.tab = .grove
            case .journal:
                // **Screen 12, which is now one of the tab's two segments rather than the whole of
                // it.** Selecting the segment is what keeps this case meaning what its own
                // declaration says: without the second line the two `AlmanacGroupTapTests` cases land
                // on the contributor's journal and fail with "the Journal tab did not draw the
                // almanac" — the deep link having quietly stopped opening the screen it names.
                router.tab = .journal
                router.journalSegment = .almanac
            case .journalList:
                router.tab = .journal
                router.journalSegment = .journal
            case .you:
                router.tab = .you
            case .pinAdjust:
                // No record, no write, no route. See `Standalone`.
                present(pinAdjustFix)
            }
            return nil
        } catch let failure as Failure {
            return failure
        } catch {
            return Failure(screen: screen.rawValue, reason: "\(error)")
        }
    }

    /// Where the two community-tree cases put their trees.
    ///
    /// Ocean, west of Ocean Beach: the seed is the city's street-tree inventory, so nothing of the
    /// city's is out here and neither case can trip the 10 m dedupe against a record it did not
    /// write. They are ~200 m apart, which is well outside each other's circle, so running one case
    /// after the other on one simulator does not refuse the second tree. A re-run of the *same* case
    /// does refuse — the first tree is still there, 0 m away — which is correct behaviour and shows
    /// as the deep link reporting a failure rather than as a screen quietly showing the wrong tree.
    /// Its own coordinate, well outside the other two's 10 m dedupe circles, for the reason
    /// `.speciesClaim` gives: a case that writes persistent state must not write it onto a record
    /// another case reads.
    private static let communityPhotoSpot = Coordinate(latitude: 37.7636, longitude: -122.5300)
    private static let claimedSpot = Coordinate(latitude: 37.7600, longitude: -122.5300)
    private static let unclaimedSpot = Coordinate(latitude: 37.7618, longitude: -122.5300)

    /// The nearest tree to the map's opening centre that is actually standing.
    ///
    /// `acceptsNewContributions` rather than `status == .alive`, because that is the property the
    /// screens behind this actually require: 05, 06, 09 and 16 all write, and `TreeStatus` already
    /// owns the question of which states may be written to (E95).
    private static func standingTree(_ api: LocalAPI) async throws -> UUID {
        try await firstTree(matching: { $0.status.acceptsNewContributions }, api: api, wanted: "a standing tree")
    }

    /// The *farthest* standing tree among the candidates — the one the photo screens seed onto.
    ///
    /// ── Why this is not `standingTree` (ERRATA E125) ──────────────────────────────────────
    /// Both photo cases write, and **what they write outlives the launch**: `debugSeedPhotos` inserts
    /// `photos` rows and JPEGs into the device container, which the next launch reads back. Point them
    /// at `standingTree` and they photograph the one tree nine other cases open — and screen 03 stops
    /// being cold. `testTreeProfile` anchors on `TreeProfilePresentation.fallbackTitle`, the title a
    /// tree with nothing on it shows; a warm hero has a species name instead, so four tests in
    /// `DeepLinkVoiceOverTests` failed with "'Tree' never appeared in the accessibility tree" — and
    /// failed only in the whole-suite run, in an order no single-test run reproduces.
    ///
    /// `.last` rather than `.first` because `.memorial` mutates from the near end (it marks the nearest
    /// standing tree removed, so `standingTree` steps one outward each time it runs) and this mutates
    /// from the far end. They march away from each other, with 456 standing records between them.
    ///
    /// The rule this encodes, for whoever adds the next case: **a case that writes persistent state
    /// must not write it onto a tree another case reads.**
    private static func photographedTree(_ api: LocalAPI) async throws -> UUID {
        let candidates = try await api.treesNear(centre, radiusM: radiusM, limit: candidateLimit)
        guard let match = candidates.last(where: { $0.tree.status.acceptsNewContributions }) else {
            throw Failure(
                screen: "a standing tree to photograph",
                reason: "none among the \(candidates.count) records nearest \(centre.latitude), \(centre.longitude)"
            )
        }
        return match.tree.id
    }

    /// The *middle* standing tree among the candidates — the one screen 16 measures.
    ///
    /// ── Why this is not `standingTree` either (ERRATA E133) ────────────────────────────────
    /// `.measure` writes nothing, which is exactly why it sat on `standingTree` and looked safe.
    /// **The test writes.** `testSavingAMeasurementLeavesTheScreen` taps a digit and the save, and a
    /// saved reading is a row in the device container that outlives the launch — so from the first
    /// full suite run onward, the one tree nine other cases open has a measurement on it.
    ///
    /// What then failed was not the measure test. Screen 03's DBH card prefers a reading over the
    /// city's bucket, and a card holding a reading has somewhere to go — screen 11 — so it is wrapped
    /// in a `Button`. `StatCard` combines its children either way, so the joint label E118 asked for
    /// is still there; it has simply moved out of `staticTexts` and into `buttons`, where
    /// `testAStatCardIsOneStop` was not looking. The suite then failed on *every* subsequent run and
    /// passed the instant the app was uninstalled — the signature of persistent pollution, and
    /// indistinguishable from a flake until you clear the container and watch it go green.
    ///
    /// `.memorial` marches from the near end and the photo cases from the far end (see
    /// `photographedTree`), so this takes the middle — the one place neither reaches, with hundreds of
    /// standing records between them.
    ///
    /// The rule, restated because it needed restating: **a case that writes persistent state must not
    /// write it onto a tree another case reads** — and "the case" includes the test driving it.
    private static func measuredTree(_ api: LocalAPI) async throws -> UUID {
        let candidates = try await api.treesNear(centre, radiusM: radiusM, limit: candidateLimit)
        let standing = candidates.filter { $0.tree.status.acceptsNewContributions }
        guard !standing.isEmpty else {
            throw Failure(
                screen: "a standing tree to measure",
                reason: "none among the \(candidates.count) records nearest \(centre.latitude), \(centre.longitude)"
            )
        }
        return standing[standing.count / 2].tree.id
    }

    /// The nearest vacant planting site — a record with no tree in it (E107). 153 of them in the
    /// city-sourced seed, 12,518 in a DataSF-sourced one; see `candidateLimit`.
    private static func vacantSite(_ api: LocalAPI) async throws -> UUID {
        try await firstTree(matching: { $0.status == .vacantSite }, api: api, wanted: "a vacant planting site")
    }

    private static func firstTree(
        matching predicate: (Tree) -> Bool,
        api: LocalAPI,
        wanted: String
    ) async throws -> UUID {
        let candidates = try await api.treesNear(centre, radiusM: radiusM, limit: candidateLimit)
        guard let match = candidates.first(where: { predicate($0.tree) }) else {
            throw Failure(
                screen: wanted,
                reason: "none among the \(candidates.count) records nearest \(centre.latitude), \(centre.longitude)"
            )
        }
        return match.tree.id
    }

    /// Screen 07 wants a species, and the curated list is the one screen 08 draws tiles from — so the
    /// species this opens is a species the app can actually reach by tapping.
    private static func anySpecies(_ api: LocalAPI) async throws -> UUID {
        guard let first = try await api.curatedSpecies(limit: 1).first else {
            throw Failure(screen: "species", reason: "the seed returned no curated species")
        }
        return first.id
    }
}
#endif
