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
    /// **Screen 19, the memorial, is not here, and that is a fact about the data rather than an
    /// omission.** The shipped seed holds two statuses and only two — 182,791 `alive` and 12,518
    /// `vacant_site`. There is no `removed` tree in it, so there is no record on this device that
    /// `MemorialView` could honestly be opened with. Resolving one against a living tree would draw a
    /// memorial over a tree that is standing, which is a lie in the exact place this suite exists to
    /// catch lies. It is recorded in ERRATA E117 as unreachable-until-the-data-changes.
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
        // Presented over the tab root.
        case careLog            // 09
        case share              // 10
        // Tab roots other than the map, which needs no deep link.
        case grove              // 08
        case journal            // 12
        case you                // 18
    }

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
    /// Wide enough to hold both statuses (of the 500 nearest to the centre, 456 are standing and 44
    /// are vacant sites) and narrow enough to stay one index scan.
    private static let radiusM: Double = 3_000
    private static let candidateLimit = 500

    /// Opens `screen`, resolving whatever record it needs out of the seed.
    ///
    /// Ordering is `nearest`'s — by distance from a fixed point — so the same tree is chosen on every
    /// launch and a failing test names a record somebody can go and look at.
    @MainActor
    static func open(_ screen: Screen, api: LocalAPI, router: AppRouter) async -> Failure? {
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
                router.push(.measure(try await standingTree(api)))
            case .species:
                router.push(.species(try await anySpecies(api)))
            case .outbox:
                router.tab = .you
                router.push(.outbox)
            case .careLog:
                router.present(.careLog(try await standingTree(api)))
            case .share:
                router.present(.share(try await standingTree(api)))
            case .grove:
                router.tab = .grove
            case .journal:
                router.tab = .journal
            case .you:
                router.tab = .you
            }
            return nil
        } catch let failure as Failure {
            return failure
        } catch {
            return Failure(screen: screen.rawValue, reason: "\(error)")
        }
    }

    /// The nearest tree to the map's opening centre that is actually standing.
    ///
    /// `acceptsNewContributions` rather than `status == .alive`, because that is the property the
    /// screens behind this actually require: 05, 06, 09 and 16 all write, and `TreeStatus` already
    /// owns the question of which states may be written to (E95).
    private static func standingTree(_ api: LocalAPI) async throws -> UUID {
        try await firstTree(matching: { $0.status.acceptsNewContributions }, api: api, wanted: "a standing tree")
    }

    /// The nearest vacant planting site — the 12,518 records with no tree in them (E107).
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
