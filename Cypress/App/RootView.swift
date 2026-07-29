import SwiftUI

/// The composition root's view. The only place that knows how features connect.
///
/// Features push `Route`s and hand out closures for the things that are not navigations (a visit is
/// a camera, a favorite is a mutation). Resolving those in one file is what keeps a feature folder
/// from importing its siblings.
struct RootView: View {

    let data: DataLayer

    @State private var router = AppRouter()

    /// Screen 17's model, owned here because **two screens now show the same preference**.
    ///
    /// The You tab draws the wi-fi toggle beside the outbox row, and screen 17 draws it in its own
    /// §3. Each building its own `OutboxViewState` would give the app two copies of one setting,
    /// each reading the store when its screen appeared and neither hearing the other change it — so
    /// the toggle would agree with itself only until you used it. One instance, from the composition
    /// root, is ARCHITECTURE §3's answer to exactly this ("shared services are passed through the
    /// SwiftUI environment from a single composition root; no singletons").
    @State private var outbox: OutboxViewState

    /// The local moderation queue (ERRATA E124-B), owned here so the You tab and any future surface
    /// share one instance — the same reason `outbox` is owned here. It reads the account's role on
    /// appearance and draws nothing unless that role is a lead's.
    @State private var moderation: ModerationModel

    /// The You tab's account state and this contributor's own reminders (ERRATA E131), owned here
    /// for the reason `moderation` is: signing out has to be one fact, not one per surface.
    @State private var account: AccountModel

    /// One decoded-photograph cache for the whole app (ERRATA E125), owned here for the reason
    /// `outbox` and `moderation` are: the profile hero and the photo browser draw the same
    /// photographs, and two caches would decode each of them twice. Read through the environment,
    /// so a screen that shows a photograph does not have to be handed one.
    @State private var photoImages: PhotoImageStore

    /// `@MainActor` because `makeOutboxViewState()` is: the model is a `@MainActor @Observable`, and
    /// building it in `init` is what lets both screens receive the same one.
    @MainActor
    init(data: DataLayer) {
        self.data = data
        _outbox = State(wrappedValue: data.makeOutboxViewState())
        _moderation = State(wrappedValue: ModerationModel(api: data.api))
        _account = State(wrappedValue: AccountModel(api: data.api))
        _photoImages = State(wrappedValue: PhotoImageStore(api: data.api))
    }

    /// The one shared location provider (ARCHITECTURE §3: "Shared services (`CypressAPI`, `Outbox`,
    /// `LocationProvider`) are passed through the SwiftUI environment from a single composition
    /// root").
    ///
    /// It is never `start()`ed here, and that is deliberate: starting is what shows the system
    /// sheet, and screen 01 is the one screen the design gives a reason to ask on. Once the map has
    /// asked and been allowed, this provider receives the authorisation callback like any other and
    /// begins reporting fixes; until then it stays `.notAsked` and the screens that read it draw
    /// without a location.
    ///
    /// **That sentence was false until now, and worth reading as a warning.** Construction used to
    /// call `startUpdatingLocation()` by way of `apply(authorization:)`, so on a device that had
    /// already granted permission this provider opened a GPS session the instant the composition
    /// root was built — never mind that nothing had asked it to. It is inert until `start()` now,
    /// which is what makes the paragraph above true and what makes a stray construction harmless.
    @State private var location = MapLocationProvider()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            tabRoot
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .modifier(sharedEnvironment)
        // **One** cover, switching on `router.sheet`, not one modifier per route. Stacking several
        // `fullScreenCover`s on the same view is not a supported arrangement — SwiftUI keeps the
        // last one and the others become dead code, which is exactly the kind of wiring bug that
        // reads as "the Care button does nothing".
        //
        // Full-screen rather than `.sheet` because screens 09 and 10 draw their *own* scrim and
        // their own profile skeleton (SCREENS.md §2 C17: "Background behind the sheet on 09/10 is a
        // skeleton of the profile, not the live profile"). A system sheet would impose its own card,
        // its own dimming and the live screen behind it — none of which is what the mocks draw.
        // `AppRouter.sheet` already distinguishes these from `path` for exactly this reason.
        .fullScreenCover(isPresented: presentingSheet) {
            // ══════════════════════════════════════════════════════════════════════════════════
            // **The environment is handed over explicitly, and it has to be.**
            //
            // A cover is presented in its own hosting context, and the `.environment(_:)` calls
            // above are attached to the `NavigationStack` this modifier hangs off — they reach the
            // pushed destinations and they do not reach here. Every sheet before the photo viewer
            // took what it needed as an argument (`api`, `outbox`, `attribution`), so nothing had
            // ever asked, and the gap was invisible.
            //
            // `PhotoViewerView` asks, because `PhotoImageStore` is a cache with one instance and
            // threading it through as an argument is the thing the environment exists to avoid
            // (see `PhotoImage`). Found by looking: the viewer came up with its close button, its
            // caption and the sentence "That photograph could not be opened" across the middle,
            // because an absent store and a photograph whose bytes are gone are the same state to
            // a view that only has an optional. Every test passed. ERRATA E142.
            //
            // **It is the same modifier the stack gets, not a second copy of the same two lines.**
            // E142 fixed the values that were missing; what it left behind was a hand-maintained
            // duplicate, so a *third* shared value added to the stack would reach every pushed screen
            // and silently not reach any sheet — the identical defect, one environment value later,
            // and just as invisible. `sharedEnvironment` is the one list. See it for the rest.
            // ══════════════════════════════════════════════════════════════════════════════════
            presentedSheet
                .modifier(sharedEnvironment)
        }
        #if DEBUG
        // The UI test target's door into the screens behind the map (ERRATA E117). `#if DEBUG` here
        // as well as around `DebugDeepLink` itself, so the call site goes with the type rather than
        // referring to something that no longer exists in a Release build.
        //
        // A failure draws over everything rather than logging: a deep link that quietly did nothing
        // would leave every one of these tests asserting the accessibility of screen 01 while
        // reporting the name of some other screen. See `DebugDeepLink.Failure`.
        .task { await openDebugDeepLink() }
        .overlay {
            if let deepLinkFailure {
                Text(deepLinkFailure)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CypressColor.surfaceScreen)
            } else if let debugStandalone {
                debugStandaloneScreen(debugStandalone)
            }
        }
        #endif
    }

    #if DEBUG
    @State private var deepLinkFailure: String? = nil
    @State private var deepLinkAttempted = false
    /// A screen the harness asked for that lives on no router — today only the community add's pin
    /// step, which is a phase of `VisitAddTreeModel` rather than a `Route`. See
    /// `DebugDeepLink.Standalone`.
    @State private var debugStandalone: DebugDeepLink.Standalone? = nil

    @ViewBuilder
    private func debugStandaloneScreen(_ standalone: DebugDeepLink.Standalone) -> some View {
        switch standalone {
        case let .pinAdjust(anchor, accuracyM):
            // Both closures dismiss and nothing is written: on the shipping path the confirmed
            // coordinate goes back into the draft the add screen is holding, and there is no draft
            // here. What this entrance exists to expose is the screen's element tree.
            VisitPinAdjustView(
                anchor: anchor,
                accuracyM: accuracyM,
                onConfirm: { _ in debugStandalone = nil },
                onCancel: { debugStandalone = nil }
            )
        }
    }

    /// Applies the requested screen once per launch.
    ///
    /// Once, because `.task` runs again on every reappearance of the view it is attached to, and a
    /// deep link that re-fired would push a second copy of the screen under the first one — which
    /// looks exactly like a passing test until somebody presses Back.
    @MainActor
    private func openDebugDeepLink() async {
        guard !deepLinkAttempted, let request = DebugDeepLink.requested() else { return }
        deepLinkAttempted = true
        switch request {
        case let .success(screen):
            let failure = await DebugDeepLink.open(
                screen,
                api: data.api,
                router: router,
                present: { debugStandalone = $0 }
            )
            if let failure { deepLinkFailure = failure.message }
        case let .failure(failure):
            deepLinkFailure = failure.message
        }
    }
    #endif

    @ViewBuilder
    private var presentedSheet: some View {
        switch router.sheet {
        case let .careLog(id):
            // Screen 09.
            CareLogView(
                treeID: id,
                api: data.api,
                outbox: data.outbox,
                // Anonymous under the device id until the account ask ships (D9); the composition
                // root owns that choice, not the feature.
                attribution: .anonymous(deviceID: data.deviceID),
                // D6 wants the fix's accuracy stored with every field contribution, and the
                // provider now carries one (E65 is resolved).
                //
                // **Handed over as a question, not as an answer.** This used to read
                // `location.availability.accuracyM` here, which `@State` then froze for the life of
                // the sheet: open the care log before the first fix and the event recorded `nil`
                // for ever, and a `nil` accuracy is excluded rather than assumed good. The sheet
                // asks when it writes (ERRATA E158).
                //
                // The capture list is the point: the closure holds the **provider**, which is one
                // object for the life of the app, and reads `availability` off it when called. It
                // does not hold a view struct and it does not hold a number.
                gpsAccuracyM: { [location] in location.availability.accuracyM },
                onClose: { router.sheet = nil },
                onSaved: { _ in router.sheet = nil }
            )

        case let .share(id):
            // Screen 10.
            ShareView(
                treeID: id,
                api: data.api,
                onClose: { router.sheet = nil }
            )

        case .accountAsk:
            // Screen 15, from the You tab's account block (ERRATA E131). The same view, the same
            // `onLink`, and the same `fullScreenCover` reasoning `VisitSavedView` writes down: 15
            // draws its own scrim over its own backdrop, so a system sheet would impose a second
            // card over the top of it.
            AccountAskView(
                api: data.api,
                onLink: accountLink(),
                onFinish: { router.sheet = nil }
            )

        case let .identify(treeID):
            // Screen 04 is a camera, so it is presented rather than pushed — and `Route` has no
            // camera case by design (DECISIONS constraint 21). `.identify` is the flow's entry point.
            VisitFlowView(
                api: data.api,
                outbox: data.outbox,
                deviceID: data.deviceID,
                // Which screen the flow opens on. Screen 03's photo CTA passes the tree it is the
                // profile of, so the camera opens for that tree and nobody is asked to pick it out of
                // a shortlist they already left (ERRATA E127); the map's FAB passes nil and gets 02.
                startingTreeID: treeID,
                // Screen 15's sign-in, wired to complete on-device (E124). Owned here because
                // identity is the composition root's question, the same rule that puts `attribution`
                // resolution here rather than in a feature. See `accountLink` for what it does; formed
                // at the call site with an explicit capture list so the `@Sendable` closure carries
                // only its two `Sendable` captures across the isolation boundary, not this view.
                onLink: accountLink(),
                // Abandoning the flow — the shortlist's back chevron, and the camera's ✕ on the
                // profile entrance. Relative on purpose: nothing was contributed, so the honest place
                // to land is the screen that opened the camera. `onDone` is the one that is finished,
                // and it goes somewhere absolute (ERRATA E151).
                onExit: { router.sheet = nil },
                // "Done for today" — the end of a contribution rather than the abandoning of one, and
                // the control whose label already promises what the owner asked for. It is the map's
                // FAB that starts this flow and the map that a volunteer morning is conducted from, so
                // finishing goes there rather than to whichever screen happened to be underneath.
                onDone: { router.goToMap() },
                onOpenTree: { id in
                    router.sheet = nil
                    // Not a second copy of the profile this flow may have been opened from (E151).
                    router.push(.treeProfile(id), unlessAlreadyOnTop: true)
                },
                // PROTOTYPE-FLOW §1.6 rule 5: after the third tree the next-tree CTA reads
                // `Route done · see your grove` and goes to the grove. It closes the camera flow
                // and moves the bottom bar rather than pushing, because the grove is a tab root —
                // and it has to clear the stack to do it, or the grove arrives underneath whatever
                // is pushed and nothing appears to happen (`AppRouter.goToTab`).
                onOpenGrove: { router.goToTab(.grove) }
            )

        case let .photoViewer(id, caption):
            // One photograph, whole. Presented rather than pushed for the reason `PhotoViewerView`
            // sets out: it is a closer look at what is already on screen, not a place in the app.
            PhotoViewerView(
                photoID: id,
                caption: caption,
                onClose: { router.sheet = nil }
            )

        default:
            // Nothing else is presentable. `AppRouter.present` is only ever called with the four
            // above; anything else is a pushed destination and belongs on `path`.
            EmptyView()
        }
    }

    /// What the bottom bar (C16) selects between.
    ///
    /// A `switch` on `router.tab` rather than a `TabView`, because C16 is a drawn component with its
    /// own hand-made icons and paddings (SCREENS.md §2) and every screen that carries it draws it
    /// itself — screen 01 already did, and 08's variant differs from 01's (no backdrop blur). All
    /// four now translate through `AppRouter.bottomTabSelection` rather than each writing the
    /// mapping out again.
    ///
    /// `Journal` and `You` were BUILD-PLAN §9 M2 build requirements with no mock, and both rendered
    /// `NotBuiltYetView` until the entrances round. They are built now, minimally, because they are
    /// the last two doors: screen 12 had no entrance anywhere in the app (ERRATA E57) and screen
    /// 17's entrance was *named* by BUILD-PLAN §9 and sat on a screen that did not exist (E75).
    /// What each contains, and which parts of it are invented, is documented in the two feature
    /// files rather than restated here.
    @ViewBuilder
    private var tabRoot: some View {
        switch router.tab {
        case .map:
            // The provider is handed over rather than made there. Screen 01 used to declare its own
            // `@State` one, which SwiftUI re-initialises on every pass through this body — see
            // `MapHomeView.location`.
            MapHomeView(api: data.api, location: location)
        case .grove:
            // Screen 08. The species tile's destination is 07, which is the one entrance
            // SCREENS.md draws for it: "Tapping a tile opens the species page."
            //
            // Its other two pills work now. Both the `Trees` list and the `Journal` list are lists
            // of things that happened to a tree, so a row on either opens that tree's profile —
            // the same destination the almanac's season rows and the outbox's rows already use.
            GroveView(
                api: data.api,
                onOpenSpecies: { id in router.push(.species(id)) },
                onOpenTree: { id in router.push(.treeProfile(id)) }
            )
        case .journal:
            // Screen 12 lives here. The elder and first-bloom rows each name a specific tree, so they
            // open a profile. The two *counted* rows do not name one and never did: they hand over the
            // group they counted, for a map of it (ERRATA E129).
            JournalTabView(
                api: data.api,
                coordinate: location.availability.coordinate,
                onOpenTree: { id in router.push(.treeProfile(id)) },
                onShowGroup: { group in router.push(.pinSet(group)) },
                onRequestLocation: { location.start() }
            )
        case .you:
            // The export closure is resolved here rather than inside the tab, for the reason every
            // other boundary call is: the feature gets the one operation it needs, not the API.
            // `LocalAPI` is an actor and `ExportFormat` a value, so the `@Sendable` closure carries
            // nothing of this view across the isolation boundary.
            YouTabView(
                outbox: outbox,
                moderation: moderation,
                account: account,
                export: JournalExportBytes { [api = data.api] format in try await api.exportLatest(format) }
            )
        }
    }

    /// Everything this composition root puts into the SwiftUI environment, in one place.
    ///
    /// ── Why this is a modifier and not two lines written twice ─────────────────────────────────
    /// A `fullScreenCover` is presented in its own hosting context, so `.environment(_:)` applied to
    /// the `NavigationStack` reaches every *pushed* destination and reaches nothing presented over it.
    /// E142 is what that costs: `PhotoViewerView` came up saying "That photograph could not be opened"
    /// over a photograph that was perfectly fine, because the one cache in the app was not there to be
    /// read, and an absent store and absent bytes are the same `nil` to a view holding an optional.
    ///
    /// E142 supplied the two values by hand at the cover. That fixed the bug and left the shape of it:
    /// the list existed in two places and nothing made them agree, so the next shared value added to
    /// the stack would have reached the pushed screens and not the sheets — same defect, same silence,
    /// one value later. Adding to this list now reaches both, which is the only version of this that
    /// cannot rot.
    ///
    /// The environment is for **shared, long-lived services** (ARCHITECTURE §3). Everything else a
    /// screen needs is still handed to it as an argument, which is why most of the sheets in
    /// `presentedSheet` would work with no environment at all.
    private var sharedEnvironment: SharedEnvironment {
        SharedEnvironment(router: router, photoImages: photoImages)
    }

    private struct SharedEnvironment: ViewModifier {
        let router: AppRouter
        let photoImages: PhotoImageStore

        func body(content: Content) -> some View {
            content
                .environment(router)
                .environment(photoImages)
        }
    }

    /// Whether anything is presented over the tab root.
    ///
    /// Dismissing clears `sheet` itself rather than a separate flag, so a swipe-down, a tap on the
    /// scrim and a completed save all leave the router in the same state — a stale `sheet` would
    /// re-present on the next state change, which is the latent bug PROTOTYPE-FLOW §1.3 records
    /// in `reset`.
    private var presentingSheet: Binding<Bool> {
        Binding(
            get: { router.sheet != nil },
            set: { if !$0 { router.sheet = nil } }
        )
    }

    /// Screen 03's heart, as this app performs it (RULINGS R2, ERRATA E112).
    private var favoriteWriter: ProfileFavoriteWriter {
        ProfileFavoriteWriter(api: data.api, outbox: data.outbox)
    }

    /// Screen 15's sign-in, performed locally (ERRATA E124).
    ///
    /// A local account needs no server: this mints an account id and hands it to `claimDevice`, which
    /// moves this device's anonymous contributions onto it and persists it in `app_state`. The
    /// request's email address is neither read nor stored — there is nowhere local it could go, and
    /// DECISIONS §3.9 wants it nowhere — so the account is an *identity*, not a backup, and screen
    /// 18's "saving to this phone only" stays true after it.
    ///
    /// Idempotent on identity: if this device already carries a `userID` (the ask can return once
    /// under ERRATA E34), it is reused, so a second link sweeps any freshly-anonymous rows onto the
    /// same account rather than minting a rival one. When the magic-link service exists this closure
    /// becomes the client half of the token exchange and nothing on the call path above changes.
    ///
    /// `nonisolated` so the `@Sendable` closure is formed off `RootView`'s `@MainActor` isolation: it
    /// captures only two `Sendable` values (`LocalAPI` is an actor, `UUID` a value) read from the
    /// `Sendable` `data`, so it carries nothing of the view across the boundary it will be called on.
    /// **What the request carries, and why discarding it was a defect (ERRATA E131).** This closure
    /// read `_ = request` and threw away both fields screen 15 collects. `AccountAskModel` justifies
    /// leaving the licence checkbox ungated on the grounds that "the answer travels on the request
    /// instead, so the account records what was actually agreed to and `User.licenseVersion` stays
    /// honestly nil when nothing was" — a sentence the shipping handler made false. Unchecking the
    /// box changed nothing anywhere, and an account created by somebody who declined the open
    /// database licence was indistinguishable from one created by somebody who accepted it. Both
    /// fields now land in `app_state` through `LocalAPI.linkAccount`, where `accountLink()` reads
    /// them back and the You tab renders which answer was given.
    ///
    /// **The account resumed rather than re-minted.** `resumableUserID()` is the account this device
    /// signed out of. Without it, signing back in would mint a rival id and leave the first
    /// account's reminders, favourites and votes owned by an id no query asks for and no deletion
    /// can reach — see `LocalAPI.signOut()`.
    nonisolated func accountLink() -> AccountAskLink {
        let api = data.api
        let deviceID = data.deviceID
        return { request in
            // The account already on this device, else the one it signed out of, else a new one.
            let existing: UUID?
            if let current = await api.userID {
                existing = current
            } else {
                existing = try await api.resumableUserID()
            }
            try await api.linkAccount(
                deviceUUID: deviceID,
                userID: existing ?? UUID(),
                provider: request.provider.rawValue,
                acceptsLicense: request.acceptsLicense
            )
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .treeProfile(let id):
            TreeProfileView(
                treeID: id,
                api: data.api,
                // The tree is already named — this screen is its page — so the flow opens on the
                // camera for it rather than on the shortlist that asks which tree this is. The id
                // used to be discarded here, which is the whole of ERRATA E127's third defect.
                onVisit: { id in router.present(.identify(id)) },
                // Screen 03's quad row. The favourite is device-owned until an account exists, so
                // the heart works on a device that has never seen the account sheet — which is every
                // device the app currently runs on (D9, ERRATA E89). The owner comes from
                // `LocalAPI.attribution` and never from the screen. When screen 15 lands,
                // `claimDevice` moves these favourites onto the account and this line does not
                // change.
                //
                // It now writes both states. C8's first cell has a selected appearance under
                // RULINGS R2, so the control that means "off" exists and the tombstone path that
                // has been sitting in the store and the payload since E89 has a caller (E112).
                onFavorite: { treeID, isFavorite in
                    await favoriteWriter(treeID: treeID, isFavorite: isFavorite)
                }
            )

        case .checkIn(let id):
            // Screen 05. Anonymous under the device id until the account ask ships (D9); the
            // composition root owns that choice, not the feature.
            //
            // **Reached from the C7 outline button under screen 03's primary CTA**, which is
            // invented under the project owner's one-time authorization and marked as such where it
            // is built (`TreeProfilePresentation.checkInCTATitle`). No mocked screen carries an
            // affordance that opens the check-in — 03's quad row is drawn with exactly four cells
            // and its primary CTA with exactly one button — so E24 stood open until that
            // authorization existed. See ERRATA (E24, E98).
            CheckInView(
                treeID: id,
                api: data.api,
                outbox: data.outbox,
                attribution: .anonymous(deviceID: data.deviceID),
                // A check-in is a field contribution, so D6 wants the fix's accuracy on it. The
                // parameter defaults to nil and was being defaulted away here, which is the quiet
                // half of the same bug: a provider that drops the number and a composition root
                // that never asks for it look identical from inside the feature.
                //
                // A closure, so the answer is the one that is true when the check-in is saved
                // rather than when the screen was pushed
                // (ERRATA E158). The closure holds
                // the provider itself; see the care log's call above.
                gpsAccuracyM: { [location] in location.availability.accuracyM },
                onSaved: { _ in router.pop() }
            )

        case .report(let id):
            // Screen 06. D4's private reminder is device-owned until an account exists, so the save
            // works on a device that has never seen the account sheet — which is every device the
            // app currently runs on (D9, ERRATA E23). The owner comes from `LocalAPI.attribution`
            // and never from the screen: the reminder belongs to the signed-in user when there is
            // one, and to this installation otherwise. When screen 15 lands, `claimDevice` moves
            // these reminders onto the account and this line does not change.
            ReportView(
                treeID: id,
                api: data.api,
                onSaveReminder: { draft in
                    try await ReminderOutboxWriter.save(
                        draft,
                        attribution: await data.api.attribution,
                        outbox: data.outbox
                    )
                }
            )

        case .species(let id):
            // Screen 07. The fix comes from the composition root, which ARCHITECTURE §3 names as
            // where a `LocationProvider` belongs; the screen never asks for permission itself,
            // because nothing in SCREENS.md 07 says it should. Without one, 07's `Near you` card
            // and its nearby list simply have no subject and do not draw.
            //
            // **07's one drawn entrance is a tile on screen 08** ("Tapping a tile opens the species
            // page"), and `tabRoot` now wires it. 03's affordance list ends at `Report` → 06 and
            // `DBH/Height` → 11, and the clickable prototype has no species screen in its `screen`
            // enum at all, so no other button was invented on a screen that has one (DECISIONS
            // constraint 21). See ERRATA (E43).
            SpeciesView(
                speciesID: id,
                api: data.api,
                coordinate: location.availability.coordinate,
                onRequestLocation: { location.start() }
            )

        case .growthHistory(let id):
            // Screen 11. Its one drawn entrance is a measurement stat card on 03
            // (`StatDestination.growthHistory`), which exists only when a measurement does. That is
            // **specified** and was never invented; it simply could not fire, because until screen
            // 16 became reachable nothing in the app could write a measurement (ERRATA E63, E74).
            // Now that it can, the same card carries both directions: a reading opens its history,
            // an empty slot opens the sheet that writes one.
            GrowthHistoryView(treeID: id, api: data.api)

        case .activity(let id):
            // Screen 13. **Reached from the "see the whole year" link under screen 03's activity
            // feed** — E66's own first candidate, now built under the one-time authorization and
            // marked where it lives (`TreeProfilePresentation.activityLinkTitle`). E66's second
            // candidate, a tap on the foliage strip, stays rejected: the strip is a year of photo
            // coverage and 13 is a year of activity, and making one open the other asserts a
            // relationship nothing states. The link draws only where the feed does, so nobody is
            // routed to the empty state every tree in the shipped seed is in (E67). See ERRATA
            // (E66, E98).
            ActivityView(treeID: id, api: data.api)

        case .memorial(let id):
            // Screen 19, and the rare one whose entrance the design actually draws: screen 01's
            // caption says the gray dash-marked pins are "memorials, tappable to screen 19", so
            // `MapHomeView` branches on `pin.status.isMemorial` before pushing.
            //
            // Other paths still reach `.treeProfile` with a removed tree — the almanac's elder row,
            // the visit flow's open-tree — and they still do after E113, which redirects a vacant
            // site from the profile and deliberately leaves a memorial on it. Screen 19 has nothing
            // to press, so redirecting there would take away the last surface that can lift a
            // favourite off a felled tree, which is the one-way toggle E89 refused to create. The
            // profile withholds every write from it instead (`acceptsContributions`, `quadActions`).
            // See ERRATA (E95, E112, E113).
            MemorialView(
                treeID: id,
                api: data.api,
                onBack: { router.pop() },
                // ERRATA E144. The one control on 19, and it writes nothing — see
                // `MemorialPresentation.locateSet`.
                onShowWhere: { set in router.push(.pinSet(set)) }
            )

        case .site(let id):
            // The vacant planting site (ERRATA E107, closing E11). Its entrance is the map card,
            // beside the memorial branch, because the map is where 12,518 of these records are and
            // `TreePin.status` is the only thing in the app that knows a pin has no tree behind it.
            //
            // It hands out no write of any kind — a site takes no contribution — and the one thing
            // on it to press is a row naming the nearest tree that is actually standing, which
            // lands on that tree's profile. The filter that guarantees the target is standing is
            // `SiteModel.isStanding`, so this arm cannot be the thing that routes somebody from one
            // empty basin to another.
            SiteView(
                treeID: id,
                api: data.api,
                onBack: { router.pop() },
                onOpenTree: { treeID in router.push(.treeProfile(treeID)) },
                // ERRATA E144, and the strongest case for it: a basin's only subject is where it is.
                onShowWhere: { set in router.push(.pinSet(set)) }
            )

        case .photos(let id):
            // Screen 20 (ERRATA E125). Its entrance is the hero on screen 03: the photograph a tree
            // leads with is the control that opens the set it was chosen from, which is the only
            // place in the app where tapping a picture has an obvious meaning.
            TreePhotosView(treeID: id, api: data.api)

        case .almanac:
            // Screen 12, **pushed**. Its entrance is the Journal tab, which renders the almanac as
            // the tab's content rather than pushing this route (see `tabRoot`), so this arm has no
            // caller today. It stays because the route is the app's name for the screen and a push
            // is what a future entrance — a row on 01's map chrome, a link from somewhere else —
            // would use. Removing it would make adding that entrance a change to this file's
            // `Route` enum rather than one line at the call site. See ERRATA (E57, E98).
            AlmanacView(
                api: data.api,
                coordinate: location.availability.coordinate,
                onBack: { router.pop() },
                onOpenTree: { id in router.push(.treeProfile(id)) },
                onShowGroup: { group in router.push(.pinSet(group)) },
                onRequestLocation: { location.start() }
            )

        case .pinSet(let group):
            // Screen 12's two counted rows, answered together (ERRATA E129). **No mocked screen** —
            // the argument for what it is allowed to be is in `PinSetPresentation`.
            //
            // The pin tap routes through `MapHomeView.route(for:)` rather than through a branch of
            // its own. That mapping — a vacant site to the site screen, a removed tree to 19,
            // everything else to 03/14 — is E107's and E113's, and a second copy of it here is how
            // one of them comes to be right and the other stale.
            //
            // Since E144 the same route also carries a group of one — "show me where this is", from
            // the profile of any record. The neighbours closure is resolved here for the reason
            // every other boundary call is: the feature gets the one operation it needs, not the
            // API. It is `PinSetNeighbours.around`, and the screen only calls it for a group of one.
            PinSetMapView(
                set: group,
                userCoordinate: location.availability.coordinate,
                onBack: { router.pop() },
                onOpenPin: { pin in router.push(MapHomeView.route(for: pin)) },
                neighbours: .around(data.api)
            )

        case .measure(let id, let kind):
            // Screen 16. **Reached from an empty measurement stat card on screen 03** — the same
            // control that opens 11 when the card has a reading in it. Invented under the one-time
            // authorization and decided in `TreeProfilePresentation.StatDestination`, which is also
            // where the argument for putting it on the profile rather than on 11 (E74's own
            // candidate) is written down. The card is absent on a memorial and on a vacant site,
            // because neither takes a contribution. See ERRATA (E74, E98).
            //
            // The accuracy is the load-bearing argument here. D6 stores per-contribution GPS
            // accuracy and excludes readings worse than 15 m from growth charting, and
            // `isEligibleForGrowthCharting` treats a missing accuracy as unusable rather than good —
            // so a measure sheet handed `nil` would write measurements that can never be charted,
            // and screen 11 would look permanently empty on a tree somebody had just measured. That
            // is exactly the failure ERRATA E65 was recorded to prevent, and the provider now
            // carries the number it needs.
            MeasureView(
                treeID: id,
                // **Which measurement, from whichever control opened this** (RULINGS R15). The
                // empty `Height` card used to open a DBH form, because the route carried a tree and
                // nothing else and `MeasureDraft.kind` defaults to `.dbh`. A contributor who typed
                // the number off the tape without re-reading a segmented control further up the
                // screen wrote a trunk diameter in metres, and the sanity pill could not catch it:
                // it compares against previous readings *of the drafted kind*, of which there were
                // none.
                kind: kind,
                api: data.api,
                outbox: data.outbox,
                // Anonymous under the device id until the account ask ships (D9); the composition
                // root owns that choice, not the feature.
                attribution: .anonymous(deviceID: data.deviceID),
                // Asked at the tap rather than at the push, which is the whole of the argument
                // above rather than a refinement of it: `@State` froze this number at the first
                // frame, so a measure sheet opened before the fix landed wrote the very `nil` E65
                // was recorded to prevent, on a phone that had a good fix by the time the number
                // was typed (ERRATA E158).
                gpsAccuracyM: { [location] in location.availability.accuracyM },
                // **Saving used to acknowledge nothing and go nowhere (ERRATA E131).** This call
                // omitted `onSaved`, so `MeasureView`'s `{ _ in }` default applied: the screen has a
                // failure line and no success line, and the model clears `draft.entry` on the way
                // out — so the only visible consequence of a reading that reached the disk was
                // identical to the keypad clearing, which is also what a *failed* save looks like
                // for the instant before the amber line appears. Screen 05 was already wired this
                // way (`checkIn`'s `onSaved`), and 16 was the odd one out.
                //
                // Popping rather than drawing a confirmation, and this is why 16 does not need one:
                // the profile it returns to re-reads itself on appearance (ERRATA E127) and carries
                // a `See every reading` link, so the reading is on screen — in the stat card and one
                // tap from screen 11 — the moment the keypad leaves. A toast would say the same
                // thing less durably and leave the person on a screen with nothing further to do.
                onSaved: { _ in router.pop() }
            )

        case .outbox:
            // Screen 17. Its entrance is *specified*, not invented: BUILD-PLAN §9's M2 list is "the
            // You tab (profile, settings, **outbox entry point**, privacy toggles)". What did not
            // exist was the You tab, which is why the row could not be added (E75). It exists now,
            // and the row is on it.
            //
            // The state comes from this view rather than from a fresh `makeOutboxViewState()`
            // because the You tab shows the same wi-fi preference; see the `outbox` property.
            OutboxView(state: outbox)

        // 09, 10 and 15 are presented as sheets rather than pushed (see `fullScreenCover` above), so
        // a *pushed* care-log, share or account-ask route is a programming error rather than a
        // screen. They stay named here so that adding a `router.push(.share(id))` somewhere is
        // visible in review rather than silently pushing a scrim over the navigation stack.
        // 09, 10, 15 — and the photo viewer, which is presented for its own reason
        // (`PhotoViewerView`: it is a closer look at what is already on screen, not a place in the
        // app, and a pushed one would wear the navigation stack's light bar across its dark
        // backdrop).
        case .careLog, .share, .accountAsk, .photoViewer:
            NotBuiltYetView(route: route)

        // Every remaining route has a mocked screen but no built feature yet. Naming them here
        // rather than defaulting means adding one is a compile error, not a silent no-op.
        case .identify:
            NotBuiltYetView(route: route)
        }
    }
}

/// The composition root's favourite write — screen 03's heart, made durable (E89, E112).
///
/// A named type rather than a method on `RootView` because the rule it carries is a rule, and a rule
/// held privately by a view is a rule no test can state. That rule is **one tap, one key**:
///
/// E101 recorded the opposite as forced. `RootView` kept the client UUID it had minted for each tree
/// and replayed it, so an impatient double tap on a control with no visible on-state stored one
/// favourite instead of two identical ones — the trick screen 06 plays with
/// `PrivateReminderDraft.reminderID`. With an on-state that trick becomes the bug: the second tap is
/// a *different statement*, `applyFavoriteToggle`'s replay guard is `WHERE client_uuid <> excluded
/// .client_uuid`, and a reused key therefore makes un-favouriting a silent no-op. So every call
/// mints its own (`FavoriteOutboxWriter.save`'s default), and idempotency stays where ARCHITECTURE
/// §4 puts it: on the mutation, not on the control.
///
/// **What it does not do is report.** The error is still swallowed here, and that is not E101's
/// fire-and-forget: `FavoriteOutboxWriter` throws only if the row could not be made durable, and
/// what the cell shows next does not come from this call's return at all. `TreeProfileModel` re-reads
/// the store afterwards, so a write that did not land shows up as the heart going back to where it
/// was — which is the state R2 says the screen now has and E101 said it did not.
struct ProfileFavoriteWriter: Sendable {
    let api: LocalAPI
    let outbox: OutboxQueue

    /// - Parameter isFavorite: the resulting state, not a verb. A favourite syncs as a toggle event
    ///   with a tombstone (BUILD-PLAN §4), so the payload carries where the heart ended up.
    func callAsFunction(treeID: UUID, isFavorite: Bool) async {
        // `_ =` rather than a bare `try?`: `save` is `@discardableResult`, but `try?` wraps its
        // receipt in an `Optional` that is not, so the bare form warns. Discarding it is the
        // intent — see the type's doc comment for why the error is swallowed here.
        _ = try? await FavoriteOutboxWriter.save(
            treeID: treeID,
            isFavorite: isFavorite,
            // D9: the signed-in user when there is one, this device otherwise. Resolved here
            // because identity is not a view's question to answer.
            attribution: await api.attribution,
            outbox: outbox
        )
    }
}

/// Deliberately plain. A pretty placeholder is a placeholder that ships.
private struct NotBuiltYetView: View {
    let label: String

    init(route: Route) { self.label = String(describing: route) }
    init(label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 8) {
            Text("Not built yet").font(CypressFont.screenTitle)
            Text(label).cypressMonoSectionLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
    }
}
