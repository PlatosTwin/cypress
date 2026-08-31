//
//  MapHomeView.swift
//  Cypress — Features/Map
//
//  Screen 01 · Map home. "The default screen — look around a map that is already full of the
//  city's trees."
//
//  Composition, back to front, exactly as SCREENS.md 01 lists it:
//
//      MapCanvas
//        ├── basemap: MapKitBasemap   — MapKit, the parchment wash, pins, clusters, the GPS dot
//        └── overlay: the chrome      — search bar, filter chips, FAB, tree card
//      BottomTabBar (C16), Map active
//
//  The frame is full-bleed: "no 62px status padding — content is absolutely positioned below the
//  notch". So the canvas ignores the safe area and the chrome is inset by the real one, measured
//  once at the root rather than assumed.
//
//  This view owns one `@Observable MapModel` (ARCHITECTURE §3) and reads `AppRouter` from the
//  environment. It pushes `.treeProfile`, presents `.identify`, and constructs no other feature's
//  views.
//

import MapKit
import SwiftUI
import UIKit

struct MapHomeView: View {

    let api: any CypressAPI

    /// **The composition root's provider, passed in — not one of this screen's own.**
    ///
    /// It was `@State private var location = MapLocationProvider()`, and that one line is the
    /// single largest thing wrong with this screen's frame rate. A SwiftUI `@State` default
    /// expression is re-evaluated every time the view struct is initialized, and `RootView.body`
    /// initializes this one on every pass; `MapLocationProvider.init` used to open a
    /// `CLLocationManager` session there and then, so screen 01 was standing up and discarding
    /// around **fifty GPS sessions a second** — measured, 336 provider instances in seven seconds —
    /// each of which delivered a cached fix and rewrote observable state on its way out.
    ///
    /// Two things were wrong and both are fixed: the provider no longer starts on construction
    /// (`MapLocationProvider.hasStarted`), and this screen no longer constructs one. ARCHITECTURE §3
    /// already said so — "shared services (`CypressAPI`, `Outbox`, `LocationProvider`) are passed
    /// through the SwiftUI environment from a single composition root" — and the app was running two
    /// providers, two managers and two GPS sessions against that sentence.
    let location: MapLocationProvider

    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// **Read here so `MapLayout` can reserve for the legend without measuring it** (task #258).
    /// The legend's chips are Dynamic-Type text and there are up to four of them, so what they
    /// occupy is the one reservation on this screen that a single AX5 constant would be wildly
    /// wrong about at the default size. See `MapLayout.legendChipHeight(isAccessibilitySize:)`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: MapModel
    /// **Where the map opens: the camera this install was last left on** (#115).
    ///
    /// It was `MapLayout.defaultCenter` — Mission Dolores Park — unconditionally, for everyone,
    /// forever. See `MapOpeningCamera` for why a place the reader has actually been beats a
    /// stranger's park, and ERRATA E168 for the separate defect that stopped even the *fix* from
    /// reaching the camera once it arrived.
    ///
    /// `MapCameraMemory.openingSnapshot` reads values this process holds in memory, so the
    /// re-evaluation of this default expression on every one of `RootView`'s body passes costs a
    /// struct copy and no I/O — which is the constraint the whole of #84 was about.
    ///
    /// **`openingSnapshot`, not `remembered`** (task #128). `RootView` builds tab roots on a
    /// `switch`, so Map → Journal → Map remakes this view and re-runs this initializer — and a
    /// screen that reopened on the *last launch's* camera would throw away the pan the reader made
    /// a second ago. The session snapshot is noted by `rememberCamera()` on the same `onDisappear`
    /// the tab switch fires, so it is always written before this can be read.
    @State private var position: MapCameraRequest
    /// The last region MapKit reported, so a cluster tap knows what "two zoom levels in" means.
    @State private var region: MKCoordinateRegion
    /// One-shot: the first fix recenters the map, later ones must not yank it out from under a pan.
    ///
    /// **Kept, deliberately.** Task #85 was "the map snaps back to your location and cannot be panned
    /// away" and this flag is what closed it; #115 is about the map arriving on the reader in the
    /// first place, which is a different sentence. What changed is that it is now consulted from two
    /// places rather than one — see `centerOnUserIfNeeded()`.
    ///
    /// **And it is no longer the only gate** (task #128). It is `@State` on a view `RootView`
    /// remakes on every tab switch, so by itself it re-arms on every return to this screen — which
    /// re-ran the one-shot and re-centered a camera the reader had deliberately panned away: #85's
    /// defect arriving through the tab bar. `centerOnUserIfNeeded()` therefore also consults
    /// `MapCameraMemory.shared.readerMovedCamera`, which survives the identity reset.
    @State private var hasCenteredOnUser = false
    /// Whether the current wait for a location has gone on long enough to owe the reader a sentence.
    /// Driven by the task below; the decision it feeds is `MapOpening.standing`.
    @State private var waited = false
    /// The answer to a press of the recenter control that could not move the camera. See
    /// `MapRecenter` — the whole point of the control is that no press is ever silent.
    @State private var recenterAnswer: RecenterAnswer?
    /// A press made while waiting for the first fix. The notice promises the map will move when one
    /// arrives; this is the promise, held.
    @State private var recenterWhenFixArrives = false
    /// Whether C20 is being typed into, which is the whole condition for the suggestion dropdown
    /// existing (task #109, ruling R25).
    ///
    /// `SearchBar` still owns a focus of its own for every other caller — R16's argument for that is
    /// untouched — and takes this one only because this screen has something that has to *read* it.
    @FocusState private var searchFocused: Bool

    /// The two presses that produce words instead of a camera move.
    private enum RecenterAnswer: Equatable {
        case waitingForFix
        case refused(MapLocationProvider.Availability)
    }

    // This view used to take a `yearCaveat` string, threaded from the composition root out of the
    // store's measured undated share, and hand it to `MapFilterStatus`. R41 removed the sentence
    // and the view that drew it (task #180), so the parameter, the property and the whole
    // measurement behind them are gone — an unread property carried "just in case" is the #62/E126
    // shape. See `ERRATA E205`.
    /// - Parameter downloadedCityCenter: where to open when there is no remembered camera and no
    ///   fix — the middle of the largest downloaded inventory, the last thing tried, or nil
    ///   when nothing has been downloaded, in which case the map opens exactly where it always did.
    ///   Passed in from the composition root rather than read from a global, because it is a fact
    ///   about the attached inventories and `Features` does not hold those.
    init(
        api: any CypressAPI,
        location: MapLocationProvider,
        downloadedCityCenter: Coordinate? = nil
    ) {
        self.api = api
        self.location = location
        _model = State(initialValue: MapModel(api: api))
        let opening = MapOpening.openingRegion(
            remembered: MapCameraMemory.shared.openingSnapshot,
            downloadedCityCenter: downloadedCityCenter
        )
        _position = State(initialValue: .opening(opening))
        _region = State(initialValue: opening)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MapCanvas(
                    basemap: {
                        basemap(
                            topInset: proxy.safeAreaInsets.top,
                            // The same reconstruction `chrome` is handed below, and for the same
                            // reason: every term the compass's affordability is computed from
                            // counts from the top of the display rather than of the safe area.
                            screenHeight: proxy.size.height
                                + proxy.safeAreaInsets.top
                                + proxy.safeAreaInsets.bottom
                        )
                    },
                    overlay: {
                        chrome(
                            topInset: proxy.safeAreaInsets.top,
                            // For the suggestion dropdown's cap. It takes a share of the display
                            // rather than a fixed number of points, because the thing it must not
                            // swallow — the map, the FAB, the tree card — is measured in shares of
                            // the display too. See `MapSuggestionList.share`.
                            availableHeight: proxy.size.height,
                            // **The whole screen, reconstructed rather than measured** (task #258).
                            // The chrome is `MapCanvas`'s `.ignoresSafeArea()` overlay, so both its
                            // blocks are positioned in a rectangle the height of the display, and
                            // `MapLayout.noticeMaxHeight`'s other terms count from the top of that
                            // rectangle. This proxy's own `size.height` is the safe area. Nothing
                            // here needs a second `GeometryReader` — the three numbers that make
                            // the screen's height are all on this one.
                            screenHeight: proxy.size.height
                                + proxy.safeAreaInsets.top
                                + proxy.safeAreaInsets.bottom
                        )
                    }
                )
                // The map and everything typed into it come before the tab bar in the swipe order
                // (task #143, R25 §1 as amended; the measurement is E183 §3: the four tabs arrived
                // before the search field's own ✕). Priority on the canvas rather than a negative
                // one on the bar, so the bar keeps default order against anything else a screen
                // composes it with.
                .accessibilitySortPriority(1)
                BottomTabBar(selection: tabBinding)
                #if DEBUG
                // Diagnostic-only, and only in the accessibility tree of a run that asked for it
                // (task #241) — see `MapPanProbe`. Zero size and not hit-testable so it cannot
                // steal a touch or a layout inch from anything real; lowest sort priority so it
                // cannot move ahead of a screen's actual reading order in the one suite where it
                // ever exists at all.
                if MapPanProbe.isEnabled {
                    Text(MapPanProbe.shared.summary)
                        .accessibilityIdentifier(MapPanProbe.accessibilityIdentifier)
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilitySortPriority(-1000)
                }
                #endif
            }
            .ignoresSafeArea()
        }
        .background(CypressColor.surfaceScreen)
        // **01 is full-bleed and was not.** `RootView` wraps every tab root in a `NavigationStack`,
        // so a root that does not opt out inherits an empty navigation bar — here an opaque 44pt
        // band under a 47pt status area, 91pt of nothing above a screen whose own spec says "no
        // 62px status padding — content is absolutely positioned below the notch". Sixteen other
        // screens carry this modifier; this one, the app's default screen, did not, and it built
        // green and passed the whole suite that way (ERRATA E110).
        //
        // It is load-bearing twice over: with the bar present `proxy.safeAreaInsets.top` reads **0**
        // — measured on device, not assumed — so `topInset + searchTopInset` put the search bar 8pt
        // below the *bar* instead of 8pt below the status bar, which is what `searchTopInset`'s own
        // note says it is for. Hiding the bar restores the inset the arithmetic was written for
        // rather than adding to a number that was compensating for anything.
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // **Arriving already narrowed** (tester report F23). Two channels, one function, because the
        // link that arms this is on another tab *today* and need not stay there: `onAppear` catches
        // the ordinary case, where this view is built by the tab switch the arming performed, and
        // `onChange` catches an arming made while screen 01 is already the screen on glass — which
        // `onAppear` cannot see, there being no appearance. `takePendingMapFilter()` clears as it
        // answers, so whichever fires first is the only one that applies anything.
        .onAppear { applyPendingFilter() }
        .onChange(of: router.pendingMapFilter) { _, _ in applyPendingFilter() }
        .task {
            location.start()
            // **The magnetometer is this screen's alone, and it is switched off below.** The GPS
            // session deliberately outlives this view (see the note at the end of this block); the
            // heading has exactly one consumer — the cone on the dot, drawn here and nowhere else —
            // so it is scoped to the screen that draws it (task #155).
            location.startHeading()
            // **The fix may already be here, and `.onChange` cannot see a value that never changes.**
            //
            // `MapLocationProvider` is the composition root's, shared with screens 09, 12, 16 and the
            // whole visit flow, and any of them can have started it — `RootView` wires
            // `onRequestLocation: { location.start() }` in three places. Arrive on screen 01 after one
            // of those and `availability` is *already* `.located`, so the `.onChange` below never
            // fires, the one-shot never runs, and the map sits on its opening camera with a perfect
            // fix in hand. That is #115 by a second road, and it is the one no amount of camera
            // correctness would have fixed.
            centerOnUserIfNeeded()
            #if DEBUG
            // Off unless `CYPRESS_MAP_PROBE=1` is in the environment. See `MapFrameProbe`.
            MapFrameProbe.shared.start()
            #endif
            await model.fetch()
        }
        // The wait, timed. Restarted whenever *what* is being waited for changes, and canceled
        // outright when there is nothing to wait for — `MapOpening.Wait` collapses every `.located`
        // to the same value, so a reader walking down a street does not restart this on every fix.
        .task(id: MapOpening.wait(for: location.availability)) {
            waited = false
            guard MapOpening.wait(for: location.availability) != .none else { return }
            try? await Task.sleep(for: MapOpening.patience)
            guard !Task.isCancelled else { return }
            waited = true
        }
        // Remembering where the reader left the map, at the two moments they stop looking at it.
        //
        // **The camera is read here rather than watched.** This began as an
        // `.onChange(of: cameraSnapshot)` feeding an in-memory note, which is the obvious shape and
        // was wrong twice over. It put a struct comparison on a body that, at the time, ran 240 times
        // a second (#84's hot path) to collect a value that is wanted at most twice per visit to the
        // screen. (That rate is zero at rest since E140; see `MapCameraRequest`. The reasoning below
        // does not depend on it — a watcher for a value wanted twice per visit is the wrong shape at
        // any rate — which is why the shape did not go back when the rate went away.)
        // And, measured on the device, it did not work: nothing was ever written, and the screen went
        // on saying "The map is over the middle of the city" to somebody who had been looking at
        // Folsom Street a second earlier.
        //
        // **That second reason was misdiagnosed and the real cause was E168.** `region` was not
        // carrying an intermediate value the modifier missed; it was carrying MapKit's default —
        // span 98°, which `isWorthRemembering` correctly refuses — because every write that would
        // have replaced it was being discarded by SwiftUI. No shape of watcher would have helped. The
        // memory works now because `MapAnnotationLayer.Coordinator.echo(_:)` was fixed, and it is
        // verified: one granted launch, backgrounded, leaves `map.lastCamera` holding
        // `(37.759899, −122.414803, 0.001081, 0.001362)`.
        //
        // The first reason stands on its own, so the shape does not go back. Asking `region` what it
        // holds at the moment of leaving needs no watching and costs nothing while the reader pans.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { rememberCamera() }
        }
        .onDisappear {
            rememberCamera()
            // The other half of `startHeading()`. Nothing off this screen draws a cone, so nothing
            // off this screen needs the sensor spinning — and `stopHeading()` also forgets the last
            // bearing, so a return to the map cannot open on a stale one (task #155).
            location.stopHeading()
        }
        #if DEBUG
        .onChange(of: model.content) { _, content in
            MapFrameProbe.shared.note(markers: content.markerCount, zoom: model.viewport?.zoom ?? 0)
        }
        #endif
        // **The toast, spoken** (task #247). A card that appears for three seconds in the chrome is
        // a thing you have to be looking at; an announcement is the one mechanism that reports it
        // without stealing focus, which is `speak`'s whole argument below and
        // `VisitPinAdjustView`'s for its nudge pad. The card stays in the element tree as well, so
        // a reader sweeping the chrome inside that window still finds it — this is the channel for
        // the reader who is not.
        .onChange(of: model.needsCareToastIsShowing) { _, isShowing in
            if isShowing { speak(MapNeedsCareToastCopy.message) }
        }
        .onChange(of: location.availability) { _, availability in
            // Any change in what the app knows about the user answers whatever the last press was
            // told to wait for — a grant arriving from Settings, or the first fix landing.
            recenterAnswer = nil
            guard availability.coordinate != nil else { return }
            // Two reasons to move on a fix, and they want different cameras. The one-shot opening
            // recenter goes to the screen's own opening scale, because there is no scale the reader
            // chose yet. A press that was held for this fix keeps whatever they have since zoomed to.
            if !centerOnUserIfNeeded(), recenterWhenFixArrives, let coordinate = availability.coordinate {
                recenterWhenFixArrives = false
                flyTo(coordinate, meters: nil)
                speak(MapRecenterCopy.spokenCentered)
            }
        }
        // **No `stop()` on disappear any more, and that is not an oversight.** It used to stop *this
        // screen's own* provider while the composition root's kept running, which meant the stop
        // bought nothing and the app held two GPS sessions regardless. There is one provider now, and
        // screens 09, 12, 16 and the visit flow all read fixes from it — a map that switched it off
        // on its way to a tree profile would take the accuracy out from under the record being
        // written on the screen it opened.
    }

    // MARK: - Basemap

    /// - Parameter topInset: the safe area above this map, which is the first term of the compass's
    ///   own inset. Handed in rather than read off the `MKMapView`, for the reason
    ///   `MapLayout.topChromeReserved` gives about baked-in safe areas: the live number is the only
    ///   correct one, and this proxy is where the screen already reads it.
    /// - Parameter screenHeight: the whole display, reconstructed the same way `chrome` reconstructs
    ///   it. The compass needs it because whether this screen can afford one at all is a property of
    ///   the screen — see `MapLayout.compassIsAffordable`.
    private func basemap(topInset: CGFloat, screenHeight: CGFloat) -> some View {
        MapKitBasemap(
            position: $position,
            region: $region,
            clusters: model.clusters,
            pins: model.pins,
            speciesPalette: model.speciesPalette,
            userCoordinate: location.availability.coordinate,
            userHeadingDegrees: location.headingDegrees,
            selectedPinID: model.selectedPinID,
            // MapKit's compass takes the top-trailing ornament slot, which on this screen is under
            // the search bar (the owner's compass ruling of 2026-08-21, RULINGS R80 item 6b; see
            // `MapAnnotationLayer.makeUIView`). This is the y of the chip row's own bottom edge, in
            // **screen** coordinates — `MapAnnotationLayer.applyCompass` converts it to the map's
            // layout margin, which is not the same number because `insetsLayoutMarginsFromSafeArea`
            // adds the safe area back.
            //
            // The legend hangs below the chip row on this same side and is kept out of the
            // compass's column by `MapSpeciesLegend.trailingReserve` below, rather than by stepping
            // the compass over it — there is no vertical room to step into. See `MapLayout`'s
            // compass block for the sweep that establishes that.
            // **The margin to write, not the compass's screen y** — UIKit adds the map's own safe
            // area to it, and `MapLayout.compassTop` is that sum. `nil` where the screen cannot
            // seat the control without eating the location notice's floor.
            compassTopInset: MapLayout.compassTop(
                screenHeight: screenHeight,
                topInset: topInset,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ) == nil ? nil : MapLayout.compassLayoutMargin(
                topInset: topInset,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ),
            onCameraChange: { bounds, zoom in
                model.cameraDidChange(bounds: bounds, zoom: zoom)
            },
            onSelectPin: { pin in
                // A pin tap is a new question. Whatever the recenter control was explaining is no
                // longer what the reader is asking about, and the card needs the slot.
                recenterAnswer = nil
                model.select(pin)
            },
            onSelectCluster: zoom(into:),
            onReaderGesture: {
                // The camera is the reader's from the first touch (task #128). The flag outlives
                // this view's identity, which is the point — see `centerOnUserIfNeeded()`.
                MapCameraMemory.shared.noteReaderMovedCamera()
            }
        )
    }

    // MARK: - Overlay

    @ViewBuilder
    private func chrome(topInset: CGFloat, availableHeight: CGFloat, screenHeight: CGFloat) -> some View {
        @Bindable var model = model

        // Two absolutely positioned blocks, exactly as 01 describes them — a `Spacer` between them
        // would make the whole overlay one greedy stack, and a greedy stack inside `MapCanvas`'s
        // ZStack sizes against the map rather than against the screen.
        //
        // **The bottom block is applied first, so the top block draws over it** — and that ordering
        // is now load-bearing rather than incidental. It was the other way round, which is the order
        // `.overlay` was written in rather than an order anyone chose, and at AX5 with the suggestion
        // list open the FAB sat *on top of* the sentence that says the list is a page: `Showing 6 of
        // at least 100 match……. Keep ty…… it.` Seen on the running app, not reasoned about. The
        // chrome the reader is currently typing into outranks the control they are not.
        //
        // Nothing moves as a result. The two blocks only overlap at accessibility sizes, where they
        // already did, and the top block hit-tests only where it draws — its stack has no background
        // and the empty width beside a chip has never taken a touch.
        // ── The swipe order is declared, not inherited (task #143) ────────────────────────────
        // R25 §1 claimed "field → suggestions → chips → status line" and E183 §3 measured the tree
        // exposing something else: the suggestion rows after the chips, and the bottom chrome plus
        // the tab bar before the field's own ✕ — partly a consequence of R25's own block reorder
        // (bottom applied first so the top draws over it). Drawing order and reading order want
        // opposite arrangements, so the reading order is now said explicitly: the top block (the
        // thing the reader is typing into) outranks the bottom block, and inside the top block the
        // field, the list, the chips and the status lines carry descending priorities. Higher
        // sorts first; priorities compare among siblings, which each of these sets is.
        Color.clear
            .overlay(alignment: .bottom) {
                bottomChrome(topInset: topInset, screenHeight: screenHeight)
                    .accessibilitySortPriority(1)
            }
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: MapLayout.chipRowTop) {
                    SearchBar(text: $model.searchText, focus: $searchFocused)
                        .accessibilitySortPriority(6)
                    // **Between the bar and the chips, in the flow** — task #109, ruling R25. Not an
                    // overlay: an overlay would leave the chips underneath reachable by an assistive
                    // technology while invisible to everyone else, and would put the rows somewhere
                    // other than immediately after the field in the element tree. See
                    // `MapSuggestionList`.
                    //
                    // Gated on focus, because a dropdown belongs to the act of typing. Pressing
                    // R16's `Done` puts the keyboard away to look at the map, and a list still
                    // sitting over that map would be the same complaint one layer up.
                    if searchFocused {
                        MapSuggestionList(
                            suggestions: model.suggestions,
                            availableHeight: availableHeight
                        ) { species in
                            model.chooseSuggestion(species)
                            // Choosing is the end of a query, so the keyboard goes — the deliberate
                            // opposite of the ✕, which clears and keeps focus because clearing is
                            // the start of the next one (R16).
                            searchFocused = false
                        }
                        // Before the chips, which is where a reader who has just typed goes
                        // looking (R25 §1 as amended by #143 — geometry already said this and the
                        // tree did not, E183 §3).
                        .accessibilitySortPriority(5)
                    }
                    MapFilterChips(filter: $model.filter)
                        .accessibilitySortPriority(4)
                    // **The one transient sentence on this screen** (task #247, the owner's
                    // instruction of 2026-08-06, quoted in `MapNeedsCareToast`). Directly under
                    // the chip that caused it and in the flow, so it cannot cover the chips above
                    // it, the legend below it, or the FAB and the card in the bottom block — the
                    // collision `chrome`'s own reorder note records seeing at AX5.
                    //
                    // 3.5 rather than a renumbering of its neighbors: the reading order this must
                    // take is "after the chips, before the search status", and the four priorities
                    // either side are walked by name by `CypressUITests/AccessibilityTreeTests`
                    // and `DeepLinkVoiceOverTests`. A fraction changes nothing that is asserted.
                    if model.needsCareToastIsShowing {
                        MapToast(message: MapNeedsCareToastCopy.message)
                            .accessibilitySortPriority(3.5)
                            .transition(.opacity)
                    }
                    // Below the chips, so the C20 → chips order the accessibility tests walk is
                    // exactly as it was. Draws nothing unless the search has something to say.
                    MapSearchStatus(search: model.search)
                        .accessibilitySortPriority(3)
                    // **Nothing is drawn here any more** (RULINGS R41, task #180). `MapFilterStatus`
                    // sat between the search status and the legend and drew the filter's result
                    // count and the year caveat over the map. A filter's entire voice is its chip;
                    // the chips are above and the legend is below, and between them the map is the
                    // map. The sort priorities either side are unchanged, so the reading order a
                    // listener walks — field → suggestions → chips → search status → legend — is
                    // the same order with one stop removed.
                    // And below that, for the same reason. The key to the species coloring — which
                    // names the four species the map has colored, and draws nothing when it has
                    // colored none. **It is also the species filter** (#116) — see
                    // `MapSpeciesLegend` for why the filter and the legend had to be one control.
                    MapSpeciesLegend(
                        palette: model.speciesPalette,
                        selection: $model.filter.speciesID,
                        // **The one thing between the chip row and the identify FAB** (task #258).
                        // `nil` wherever the screen has room for the legend the palette asks for —
                        // every device at every ordinary type size, where the view is exactly the
                        // one that shipped with no scroller over the map. It is a number at AX5
                        // with a full palette on the phones at or below 402 pt, where the chrome
                        // wants more room than the glass has: 181 pt on a 16e, measured on the
                        // device. **This comment said "every device at every type size" and that
                        // was stale from the round that added the ceiling** (PR #63 review N4) —
                        // the same sentence was corrected in `legendMaxHeight`'s own doc and its
                        // twin was left here. See `MapLayout.legendMaxHeight`, and
                        // `.quantizedLegendCeiling` for why the number lands mid-chip (task #72).
                        maxHeight: MapLayout.legendMaxHeight(
                            screenHeight: screenHeight,
                            topInset: topInset,
                            namedSpecies: MapSpeciesLegend.named(in: model.speciesPalette).count,
                            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                        ),
                        // MapKit draws its compass in this same trailing column, underneath this
                        // chrome, so a chip that reaches the trailing edge covers it and takes its
                        // taps (PR #102's blocking finding). The room is bought sideways because
                        // there is none vertically — `MapLayout`'s compass block has the sweep.
                        trailingReserve: MapLayout.compassColumnReserved
                    )
                    .accessibilitySortPriority(1)
                }
                // The whole block the reader is typing into outranks the bottom chrome beside it.
                .accessibilitySortPriority(2)
                // Scoped to the toast's own value, so nothing else in this stack — the suggestion
                // list arriving, the legend re-deriving — is animated by it. Reduce Motion turns
                // it off rather than shortening it: the toast is the answer, not the way the
                // answer is delivered, which is `flyTo`'s argument in this same file.
                .cypressAnimation(CypressMotion.fade, value: model.needsCareToastIsShowing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MapLayout.sideInset)
                .padding(.top, topInset + MapLayout.searchTopInset)
            }
            // The frame readout, when it is armed. Its own `#if DEBUG` and its own environment gate;
            // a separate `.overlay` rather than a member of either stack, so it cannot move anything
            // the mock positions. See `MapProbeOverlay`.
            #if DEBUG
            .overlay(alignment: .topTrailing) {
                if MapFrameProbe.isEnabled {
                    MapProbeOverlay()
                        .padding(.horizontal, MapLayout.sideInset)
                        .padding(.top, topInset + MapProbeLayout.topOffset)
                }
            }
            #endif
    }

    /// The recenter control, the FAB and the one bottom slot, as one absolutely positioned block.
    ///
    /// Lifted out of `chrome` unchanged so the two blocks could be reordered without the diff
    /// pretending anything inside either of them moved. See the comment at the reorder.
    ///
    /// **`topInset` (task #250).** This block's own layout does not use it — it is
    /// passed through to `MapLayout.noticeMaxHeight(screenHeight:topInset:namedSpecies:isAccessibilitySize:)`
    /// alone, so the notice's AX5 scroll budget stays small enough that the recenter control, first
    /// in the `VStack` below, cannot rise into the top chrome no matter how tall the notice grows.
    /// See `MapLayout`'s "top chrome's own reservation" section for the mechanism, and the section
    /// after it (task #258) for why the chip row is not the bottom of that chrome.
    private func bottomChrome(topInset: CGFloat, screenHeight: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Above the FAB and right-aligned with it, inside the same absolutely positioned
            // block — which is the position MapKit's own `MapUserLocationButton` could not
            // have been given (`MapRecenter`, and ERRATA E110 for why the arithmetic here is
            // not something a system control can be dropped into).
            MapRecenterButton(engagement: recenterEngagement) { recenter() }
                .padding(.horizontal, MapLayout.sideInset - MapLayout.cardInset)
                .padding(.bottom, MapLayout.locateToFabGap)
            // `present`, not `push` (ERRATA E127). The visit flow is a `fullScreenCover` off
            // `AppRouter.sheet` — `RootView.destination(for:)` answers a *pushed* `.identify`
            // with `NotBuiltYetView`, because a pushed one is a programming error the way a
            // pushed `.share` is. So the app's one specified entrance to screen 02 landed on
            // "Not built yet", which is also the only way to reach "add this tree".
            IdentifyFAB { router.present(.identify(nil)) }
                .padding(.horizontal, MapLayout.sideInset - MapLayout.cardInset)
                .padding(.bottom, MapLayout.fabToCardGap)
            bottomSlot(
                noticeMaxHeight: MapLayout.noticeMaxHeight(
                    screenHeight: screenHeight,
                    topInset: topInset,
                    // The chips the legend will actually draw, counted through the legend's own
                    // definition of that so the two cannot drift apart.
                    namedSpecies: MapSpeciesLegend.named(in: model.speciesPalette).count,
                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, MapLayout.cardInset)
        .padding(.bottom, MapLayout.tabBarHeight + MapLayout.cardToTabBarGap)
    }

    /// One slot, four possible occupants, in priority order: the answer to a recenter press, the
    /// selected tree, the standing location refusal, or nothing at all.
    ///
    /// **The recenter answer outranks the card**, which is the only ordering that keeps the control's
    /// promise. A reader with a tree card open who presses the control and cannot be found has asked
    /// a question, and leaving the card in place would be the silent no-op the control exists to
    /// abolish. The card comes back the moment they touch a pin again.
    ///
    /// The card arrives with no transition on purpose. SCREENS.md 01 documents none, and the
    /// slide-and-fade this had first left the card stranded at half opacity below the tab bar —
    /// SwiftUI will not settle an insertion transition inside an overlay that the `Map` behind it
    /// keeps invalidating. A tap that answers instantly is better than one that answers prettily.
    @ViewBuilder
    private func bottomSlot(noticeMaxHeight: CGFloat) -> some View {
        switch recenterAnswer {
        case .waitingForFix:
            MapLocationNotice(
                title: MapRecenterCopy.waitingTitle,
                message: MapRecenterCopy.waitingMessage,
                maxHeight: noticeMaxHeight
            )
        case let .refused(availability):
            MapLocationNotice(
                title: MapRecenterCopy.refusalTitle(availability),
                message: MapRecenterCopy.refusalMessage,
                onOpenSettings: openSettings,
                maxHeight: noticeMaxHeight
            )
        case nil:
            if let subject = model.selection {
                MapTreeCard(subject: subject, userCoordinate: location.availability.coordinate) {
                    router.push(MapHomeView.route(for: subject.pin))
                }
            } else {
                // A filter that matches nothing draws **nothing extra** here, on the owner's
                // direct instruction (task #165): "if nothing matches, fine." The E126-shaped
                // card this slot used to draw for an emptied filter — title, reason, its own
                // `Clear filters` button — is exactly the message box the owner struck. The empty
                // map is the answer, and the way out stays in the row: the `Clear filters` chip
                // is on screen whenever any dimension is set.
                standingNotice(noticeMaxHeight: noticeMaxHeight)
            }
        }
    }

    /// **What the map says, unprompted, about the place it is showing instead of you.**
    ///
    /// It used to be one notice in one state: refused. Everything else drew nothing at all, so a map
    /// that had opened somewhere the reader had never been and was still waiting on CoreLocation —
    /// or had never been given permission in the first place — simply sat there, silent, looking
    /// exactly like a map that had decided this was where they were.
    ///
    /// ERRATA E126 is the rule ("a screen showing something other than what you asked for must say
    /// why") and E158 is the warning: screen 11 spent its whole life telling people their GPS fix was
    /// "too weak" when their phone had merely not answered yet, and the cold-launch population was
    /// the *entire* population of that message. Four states, four sentences, and the two that are
    /// waits are told apart from each other as well as from the two that are refusals — see
    /// `MapOpening.Standing`.
    @ViewBuilder
    private func standingNotice(noticeMaxHeight: CGFloat) -> some View {
        switch MapOpening.standing(
            availability: location.availability,
            waited: waited,
            showing: showing
        ) {
        case .nothing:
            // **The map is the reader's, and it drew nothing** (task #190). Golden Gate Park at
            // street zoom: no pins, only the basemap's canopy artwork, which reads as a failed load
            // rather than as an empty record. E126 is the rule; `MapInventoryNotice` carries the
            // whole argument, including why the trigger is the emptiness rather than a park, and
            // why RULINGS R41 is what keeps a filter out of it.
            //
            // **Below the four location states, deliberately.** E126's own precedent on screen 12
            // is that a missing fix wins over a failed read — "the prompt is the one that has an
            // action behind it" — and the same holds here: the location notices are about the
            // reader's own device and two of them carry a Settings button, while this one is a
            // standing fact about the record with nothing to press. They are barely rivals in
            // practice: a located reader gets `.nothing` from `MapOpening.standing`, which is this
            // arm.
            if model.inventoryIsEmptyHere {
                MapLocationNotice(
                    title: MapInventoryCopy.title,
                    message: MapInventoryCopy.message,
                    maxHeight: noticeMaxHeight
                )
            } else {
                EmptyView()
            }
        case let .notAsked(showing):
            // No Settings button: this is not a state Settings fixes. The way out is the permission
            // sheet, which the recenter control raises — and says so, in its hint.
            MapLocationNotice(
                title: MapOpeningCopy.notAskedTitle,
                message: MapOpeningCopy.notAskedMessage(showing),
                maxHeight: noticeMaxHeight
            )
        case let .searching(showing):
            MapLocationNotice(
                title: MapOpeningCopy.searchingTitle,
                message: MapOpeningCopy.searchingMessage(showing),
                maxHeight: noticeMaxHeight
            )
        case let .refused(availability, showing):
            MapLocationNotice(
                title: MapLocationCopy.title(availability),
                message: MapLocationCopy.message(showing),
                onOpenSettings: openSettings,
                maxHeight: noticeMaxHeight
            )
        }
    }

    private func openSettings() {
        if let url = location.settingsURL { UIApplication.shared.open(url) }
    }

    // MARK: - Arriving narrowed (F23)

    /// Applies the narrowing another screen asked this one to open under, if there is one.
    ///
    /// **Through `model.filter`'s setter, not around it.** Seeding the value inside `MapModel.init`
    /// would skip the `didSet` that reads the membership set (`membershipDidChange`), so the map
    /// would arrive with the chip drawn on and every tree in the city under it — the wrong answer,
    /// shown confidently. Assigning here is the same path a press of the chip takes, so it is the
    /// same code that has to be right.
    ///
    /// **What this does not promise, stated rather than implied:** the membership read is a `Task`,
    /// and the camera settles on its own schedule, so a fetch can go out before the id set lands and
    /// draw the unnarrowed city for a frame. That window is not new — it is the one
    /// `MapModel.filterDidChange` describes for an ordinary chip press — and it closes the moment
    /// the read answers, which is a `main`-table query of tens of rows.
    ///
    /// The reader is never stuck in what this applies: `MapFilterChips` draws `Yours` in its
    /// selected state and puts `Clear filters` in the row for as long as any dimension is set
    /// (`MapFilter.isActive`).
    ///
    /// **That sentence used to end "so the way out is on screen from the first frame", and the
    /// device said otherwise** (PR #130 review, F2). What is on screen from the first frame is the
    /// *cause* — the `Yours` chip, drawn selected at the leading edge. `Clear filters` is the fifth
    /// chip of a one-line horizontal scroller (#166) and on a 390 pt phone it sits past the trailing
    /// edge: in the row, one drag away, **not visible**. `SeeAllOnMapUITests` measures both frames
    /// against the window rather than tapping them, because XCUITest scrolls an element into view
    /// before it answers `isHittable` — which is why the first version of that test could not tell.
    ///
    /// **Making the way out visible was tried and is a worse trade, measured rather than argued.**
    /// Pinning `Clear filters` beside the scroller costs it 88 pt (its own measured frame is
    /// `(356.0, 103.3, 87.7, 44.0)` at 390 pt), which leaves ~294 pt for four chips that need 356,
    /// so `More filters` goes off the trailing edge instead — permanently, and at every text size.
    /// That is the strictly worse half to hide: it is the control R23.1 §2 gives three channels to
    /// precisely so a reader can see that *something is narrowing the map from inside it*, where
    /// `Clear filters` only exists when a narrowing is already announced by a filled chip beside it.
    /// `MapFilterAccessibilityTests.testAnOpenSuggestionListLeavesTheWholeFilterRowOrderedAndHittable`
    /// failed on exactly that ("the `Yours` chip is in the tree and cannot be activated" — the row
    /// had been left scrolled by a drawer that no longer fits).
    ///
    /// **So five chips do not fit at 390 pt, and the owner ruled which one loses** (2026-08-30,
    /// recorded via the orchestrator): `Clear filters` scrolls — the way out is one drag away, and
    /// the filled chip at the leading edge is the always-visible second escape. The pin (option b)
    /// was measured and refused; the arithmetic above is why.
    private func applyPendingFilter() {
        guard let pending = router.takePendingMapFilter() else { return }
        model.filter = pending
    }

    // MARK: - Opening on the reader

    /// The one-shot, in one place, callable from both the moment the screen appears and the moment a
    /// fix lands — whichever happens second is the one that finds a coordinate (#115).
    ///
    /// Returns whether it moved the camera, so the fix handler can tell "the opening centering just
    /// used this fix" from "the opening centering already happened and this fix is for a held press".
    /// Those wanted different cameras before and still do.
    @discardableResult
    private func centerOnUserIfNeeded() -> Bool {
        // **A camera the reader deliberately moved is theirs** (task #128). The `@State` one-shot
        // resets every time `RootView`'s tab switch remakes this view, so on its own it re-centered
        // the map on every return — #85's defect verbatim, through a different door. The memory's
        // flag is set by a real gesture on the glass (never by comparing cameras, E140) and lives
        // for the process, so a pan survives Journal-and-back. A camera the reader never touched
        // still centers on them here, which is #115's promise kept.
        guard !hasCenteredOnUser,
              !MapCameraMemory.shared.readerMovedCamera,
              let coordinate = location.availability.coordinate else { return false }
        hasCenteredOnUser = true
        recenterWhenFixArrives = false
        flyTo(coordinate, meters: MapLayout.defaultSpanMeters)
        return true
    }

    /// Hands the camera the reader is leaving behind to `MapCameraMemory`, and writes it down.
    ///
    /// Called on exactly two edges — the app leaving the foreground, and this screen going away —
    /// which between them cover every way somebody stops looking at the map.
    private func rememberCamera() {
        MapCameraMemory.shared.note(cameraSnapshot)
        MapCameraMemory.shared.flush()
    }

    /// The settled camera, in the form `MapCameraMemory` stores.
    private var cameraSnapshot: MapCameraMemory.Snapshot {
        MapCameraMemory.Snapshot(
            center: Coordinate(region.center),
            latitudeSpan: region.span.latitudeDelta,
            longitudeSpan: region.span.longitudeDelta
        )
    }

    /// Which of the two things the map is showing while it cannot show the reader.
    private var showing: MapOpening.Showing {
        MapOpening.showing(remembered: MapCameraMemory.shared.hasRememberedCamera)
    }

    // MARK: - Recenter

    /// Where the camera is, in the terms `MapRecenter` decides in.
    ///
    /// `region` is what MapKit last reported *when it settled*, which before the first settle is the
    /// opening region rather than a zero span — so `isCentered` is asked an honest question from the
    /// first frame.
    private var camera: MapRecenter.Camera {
        MapRecenter.Camera(
            center: Coordinate(region.center),
            latitudeSpan: region.span.latitudeDelta,
            longitudeSpan: region.span.longitudeDelta
        )
    }

    private var recenterEngagement: MapRecenter.Engagement {
        MapRecenter.engagement(availability: location.availability, camera: camera)
    }

    /// A press. Every branch is visible: two move the camera, one raises the system sheet, and two
    /// put a sentence in the bottom slot.
    private func recenter() {
        switch MapRecenter.press(availability: location.availability, camera: camera) {
        case .ask:
            // `start()` is the same call `.task` makes on appear, and it is the *only* one that can
            // produce the sheet — iOS presents it once per undetermined status and silently ignores
            // a request in any other. The press is held so the fix this grants recenters the map.
            recenterAnswer = nil
            recenterWhenFixArrives = true
            location.start()

        case .explainRefusal:
            recenterAnswer = .refused(location.availability)
            speak(MapRecenterCopy.refusalMessage)

        case .waitForFix:
            recenterAnswer = .waitingForFix
            recenterWhenFixArrives = true
            speak(MapRecenterCopy.waitingMessage)

        case let .center(coordinate):
            recenterAnswer = nil
            flyTo(coordinate, meters: nil)
            speak(MapRecenterCopy.spokenCentered)

        case let .centerAndZoomIn(coordinate):
            recenterAnswer = nil
            flyTo(coordinate, meters: MapLayout.defaultSpanMeters)
            speak(MapRecenterCopy.spokenZoomedIn)
        }
    }

    /// Moves the camera to `coordinate`. A `nil` span keeps whatever the reader is looking at, which
    /// is the recenter control's first step and the same rule `VisitPinAdjustView.move(to:)` follows.
    ///
    /// The search narrowing is untouched on purpose and by construction: the species live on
    /// `MapViewport`, which `MapModel` rebuilds from `MapModel.search` on every camera change, so a
    /// recenter refetches *through* the narrowing rather than around it. Clearing the field here
    /// would be a second, hidden meaning for a button that says it centers the map.
    private func flyTo(_ coordinate: Coordinate, meters: CLLocationDistance?) {
        // **No `withAnimation`, and the camera still flies.** The basemap is a `UIViewRepresentable`
        // over `MKMapView` now, so the thing that animates is `setRegion(_:animated:)` on the far
        // side of the seam; a SwiftUI transaction wrapped around this write cannot interpolate a
        // UIKit map's camera, and while it tries it holds a transaction open over the whole view
        // tree. Reduce Motion snaps rather than flies for the reason a cluster tap does — the new
        // camera is the answer to the press, not the way the answer is delivered — and that decision
        // is made in `MapAnnotationLayer.applyCameraIfChanged`, where the animation actually is.
        // `.move(to:)`, which takes a fresh ticket every time. That is what makes a second press of
        // the recenter control work even when it asks for the camera the first press already gave —
        // and it is why the annotation layer no longer has to guess, from how far the map has
        // drifted, whether the reader moved it. See `MapCameraRequest` and ERRATA E140.
        if let meters {
            position = .move(to: MapLayout.region(around: coordinate, meters: meters))
        } else {
            // The span MapKit last reported, not a zoom recomputed from one — a round trip
            // through `MapZoom` would quantise to an integer level and move a camera the reader
            // did not ask to have moved.
            position = .move(
                to: MKCoordinateRegion(center: coordinate.clLocationCoordinate, span: region.span)
            )
        }
    }

    /// Says what just happened. The map has changed under a VoiceOver reader's finger and nothing
    /// else reports it; an announcement is the one mechanism that does so without stealing focus, so
    /// the reader can press again and hear the second step. `VisitPinAdjustView` makes the same
    /// argument for its nudge pad.
    private func speak(_ sentence: String) {
        AccessibilityNotification.Announcement(sentence).post()
    }

    // MARK: - Behavior

    /// What a tap on the bottom card opens.
    ///
    /// Three destinations, and the branch belongs here rather than inside `TreeProfileView` because
    /// two of the three are different screens rather than variants of the profile:
    ///
    /// - **A removed tree opens 19.** Screen 01's own caption draws this entrance: "gray
    ///   dash-marked pins are removed trees—memorials, tappable to screen 19".
    /// - **A vacant site opens the site screen.** No mock draws it; ERRATA E107 decides it, closing
    ///   E11. This is the same reasoning one step further — a memorial is a tree that is gone, and a
    ///   site never had one, so it is not a profile with fields missing either. `TreePin.status` is
    ///   known the instant the pin is drawn, so the branch costs no read.
    /// - **Everything else opens 03**, which picks its own cold variant.
    ///
    /// A `static` function on the view rather than a property on `MapCardSubject`: the subject is
    /// what the card *draws*, and `Route` is the app's navigation vocabulary — keeping them apart is
    /// what lets the presentation type stay free of the router.
    static func route(for pin: TreePin) -> Route {
        if pin.status == .vacantSite { return .site(pin.id) }
        if pin.status.isMemorial { return .memorial(pin.id) }
        return .treeProfile(pin.id)
    }

    /// Tapping a cluster zooms in, which is what the badge means (`TreeCluster`'s own note).
    private func zoom(into cluster: TreeCluster) {
        // Reduce Motion snaps the camera instead of flying it, and `MapAnnotationLayer` is where
        // that decision is now made — see the note on the first-fix centering above.
        position = .move(to: MapLayout.zoomedIn(on: cluster, from: region))
    }

    /// C16 speaks `Map / My Grove / Journal / You` and `AppRouter` speaks `map / grove / journal /
    /// you`. The translation is `AppRouter.bottomTabSelection`, shared by all four tab roots — it
    /// used to be written out once per root, which is three copies of one mapping.
    private var tabBinding: Binding<BottomTabBar.Tab> { router.bottomTabSelection }
}
