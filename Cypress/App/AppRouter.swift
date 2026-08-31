import Foundation
import Observation
import SwiftUI

/// Where the app can go.
///
/// Screen numbers refer to `docs/distilled/SCREENS.md`. Only routes with a mocked screen or a
/// BUILD-PLAN §9 entry belong here — per DECISIONS constraint 21, an unmocked destination is a
/// question for the design, not a case to invent.
enum Route: Hashable {
    /// 03, and 14 when the tree is cold — one view, whose variant `TreeProfilePresentation.isCold`
    /// picks internally. **Not** a vacant site: that record leaves for `.site` on load and cannot be
    /// drawn here at all (ERRATA E113). A removed tree does open it, deliberately — see
    /// `TreeProfileDestination`.
    case treeProfile(UUID)      // 03 / 14
    /// The visit flow, and where it is entered. `nil` opens screen 02 and asks which tree this is;
    /// a tree id skips 02 and opens screen 04's camera for that tree, which is what the profile's own
    /// photo CTA means — the reader named the tree by being on its page (ERRATA E127). `Route` still
    /// has no case *for* the camera (DECISIONS constraint 21): this names the flow, and the flow
    /// decides which of its screens it opens on.
    case identify(UUID?)        // 02 what tree is this → 04
    case species(UUID)          // 07
    case careLog(UUID)          // 09
    case share(UUID)            // 10
    case growthHistory(UUID)    // 11
    case checkIn(UUID)          // 05
    case report(UUID)           // 06
    case almanac                // 12
    case activity(UUID)         // 13
    /// 19. Separate from `treeProfile` rather than a variant of it: 14 is a *cold* profile, whose
    /// variant the view picks internally, but a memorial is a different screen — different copy,
    /// and deliberately nothing to press.
    case memorial(UUID)         // 19
    /// 16, and **which measurement it opens on**.
    ///
    /// The kind is carried rather than defaulted because every entrance to this screen names one:
    /// an empty `Height` stat card on 03 means this tree has no height, and a form that opened on
    /// trunk diameter under it was a route with a correct entrance and a wrong argument (RULINGS
    /// R15). `MeasureDraft.kind` still defaults to `.dbh` — SCREENS.md 16 §2's drawn selection —
    /// for the entrance that genuinely names no measure, which is screen 11's.
    case measure(UUID, MeasurementKind)     // 16
    case outbox                 // 17
    /// The Cities screen — city inventory downloads (#157). No mock; its surface is ruled
    /// (RULINGS R43), and its door is on the You tab like the outbox's.
    case cityDownloads
    /// The vacant planting site. **No mocked screen** — decided in ERRATA E107, which closes E11.
    ///
    /// Separate from `treeProfile` for the reason `.memorial` is, and more strongly: 14 is a *cold*
    /// tree, whose variant the profile picks internally, but a site is not a tree with fields
    /// missing. A tree profile with fields missing still asserts a tree, and 12,518 of these records
    /// have no tree in them.
    case site(UUID)
    /// A group of records the almanac counted, shown together on a map. **No mocked screen** —
    /// decided in ERRATA E129, which is the entry for why screen 12's two counted rows could not keep
    /// opening one record each.
    ///
    /// The only route that carries a payload rather than an id, and it has to: the almanac's row has
    /// already printed a count, and a destination that re-read the group could disagree with the
    /// sentence the reader tapped. See `PinSet`.
    case pinSet(PinSet)
    /// The photographs of one tree, with a thumb on each. **No mocked screen** — DECISIONS 21 says
    /// an unmocked destination is a question for the design, and this is that question answered
    /// (ERRATA E125): A3 has always ended "a manual pin by any org member overrides", and until
    /// there was somewhere to look at a tree's photographs there was nowhere to pin one.
    case photos(UUID)
    /// One photograph, whole, over everything else. **No mocked screen** — see `PhotoViewerView`,
    /// which carries the argument for it.
    ///
    /// **Carries its caption rather than an id to read one from**, which makes it the second route
    /// after `pinSet` to carry more than an identifier, and for the same reason that one does: the
    /// caption is already drawn on the surface the reader tapped — under the card on screen 20, in
    /// the hero's eyebrow on 03 — and a viewer that re-read the record could name the photograph
    /// differently from the words that were on screen a frame earlier. There is nothing here worth
    /// a database read; the caption is one line of text that the caller has already formed.
    ///
    /// **The tree id is not decoration, and it is the whole of ERRATA E173.** Ownership is a fact
    /// about a tree's photographs (`TreeProfile.deletablePhotoIDs`), so a viewer that carries only a
    /// photograph's id cannot ask whether the person looking at it may delete it — which is why the
    /// one surface in the app that shows a single, named photograph full-frame was the one surface
    /// with no delete on it. The caption argument above does not apply: this is not a word that could
    /// disagree with what was on screen, it is the key the answer is read under.
    case photoViewer(id: UUID, caption: String, treeID: UUID)
    /// 15, the account ask. **Mocked**, so this is not an invented destination — and `sheet`'s own
    /// comment below has always named 15 among the three screens drawn as sheets, which is what this
    /// case finally lets it mean.
    ///
    /// Presented, never pushed. It has no entrance of its own until now: D9 puts the ask on the
    /// third visit save, where `VisitSavedView` covers it directly, and no route was needed. The You
    /// tab needs one because it can sign you *out* (ERRATA E131), and a sign-out with no way back
    /// short of three more field visits is a door that locks behind you.
    case accountAsk             // 15
    /// The Journal's area picker — which neighborhood, or which city, the stats segments are about.
    ///
    /// **Presented, never pushed, and through this enum rather than as a layer inside the tab**, for
    /// the reason `RootView`'s single `fullScreenCover` gives: a card over a scrim that the controls
    /// behind it can still be tapped through is not the C17 the app draws four times. The first
    /// version of this picker was a `ZStack` inside the tab content, and the PR #132 review switched
    /// segments *through* the scrim, which cancelled the sheet with no dismissal at all.
    ///
    /// It carries which of the two lists to show and nothing else. `Route` is `Hashable` and cannot
    /// hold a closure, which is why the selection it writes lives on `AppRouter` beside
    /// `journalSegment` rather than in either feature's own `@State` — see `journalArea`.
    case journalAreaPicker(JournalPicker)
}

/// Which of the Journal's two stats segments the picker is for.
enum JournalPicker: Hashable {
    case neighborhood
    case city
}

/// The four root destinations of the bottom bar (C16 / screen 01).
enum Tab: Hashable {
    case map, grove, journal, you
}

/// Navigation state, owned by the composition root and read through the environment.
///
/// Features push routes; they do not construct each other's views. That keeps a feature folder from
/// importing its siblings and keeps every destination resolvable in one place.
@MainActor
@Observable
final class AppRouter {
    /// **Written directly as well as through `goToTab`**, and the `didSet` is what makes that safe
    /// for `pendingMapFilter` (PR #130 review, F1).
    ///
    /// `bottomTabSelection`'s setter assigns this field — it is C16's binding, and it deliberately
    /// does *not* go through `goToTab`, so the four tab roots' bars move the tab without clearing
    /// anything. `DebugDeepLink` assigns it too. Disarming in `goToTab` alone therefore covered the
    /// one path a finger never takes: the reviewer's probe armed a narrowing, drove
    /// `bottomTabSelection`, and found it still armed, with a control on `goToTab` that cleared.
    ///
    /// So the disarm lives with the *event* rather than with one of the functions that raise it.
    /// Any change of tab, by any road, drops a narrowing nobody consumed. Guarded on an actual
    /// change so that `goToMap(showing:)`'s own `tab = .map` — which may be a no-op when the map is
    /// already the tab on screen — cannot disarm the value it is in the middle of arming.
    var tab: Tab = .map {
        didSet { if tab != oldValue { pendingMapFilter = nil } }
    }
    var path: [Route] = []

    /// Which segment the `Journal` tab is showing.
    ///
    /// **Navigation state rather than view state, because it is addressable.** The Journal tab holds
    /// two screens — this contributor's journal and screen 12 — and the almanac has no other entrance
    /// in the app, so "the Journal tab" is not by itself a destination any more. Anything that means
    /// to open the almanac has to be able to say which half it means, and a `@State` private to
    /// `JournalTabView` cannot be told.
    ///
    /// That is not hypothetical: `DebugDeepLink.Screen.journal` is documented as *screen 12*, and
    /// when this segment lived in the view the two `AlmanacGroupTapTests` cases landed on the journal
    /// and failed with "the Journal tab did not draw the almanac". The deep link had stopped meaning
    /// what its own comment said.
    var journalSegment: JournalSegment = .journal

    /// Which area each of the Journal's two stats segments is about — the reader's own, or one they
    /// picked (`AreaSelection` / `CitySelection`).
    ///
    /// **Here for `journalSegment`'s reason, one step further in.** That property is navigation state
    /// because the *segment* is addressable; these are here because the picker that writes them is
    /// presented from the composition root through `sheet` below, and a `Route` cannot carry a
    /// closure back to a feature's own `@State`. The selection has to live somewhere both `RootView`
    /// and the segment can see, and this is the object that already exists for exactly that.
    ///
    /// **It does not persist, and that is ruled** (D7, ratified by the owner 2026-08-30): a stats
    /// screen whose default silently stopped being "here" is its own version of F17. This router is
    /// `@State` on `RootView`, which `CypressApp` keys on `ObjectIdentifier(data.store)` — so an
    /// inventory change (`AppModel.reboot()`, which a background download triggers) destroys it along
    /// with everything else built on the old layer. A pick therefore cannot outlive the inventory it
    /// was made against, which is the stale-selection hazard closed by construction rather than by a
    /// check.
    var journalArea: AreaSelection = .here
    var journalCity: CitySelection = .here

    /// Sheets are modal over the current tab rather than pushed — screens 09, 10 and 15 are drawn
    /// as bottom sheets over a dimmed profile, not as full screens.
    var sheet: Route?

    /// **The narrowing screen 01 should arrive already showing** (tester report F23).
    ///
    /// ── Why a value on the router rather than an argument to the map ─────────────────────────
    /// `RootView` builds tab roots on a `switch`, so `MapHomeView` — and the `@State MapModel` that
    /// holds `MapFilter` — is remade on every tab switch (the view's own `position` comment records
    /// the same fact for the camera). A filter chosen on another tab therefore has nowhere to live
    /// between the tap and the map existing, and the router is the one object that spans them.
    ///
    /// **One-shot, and it has to be.** A filter that persisted here would re-narrow the map on every
    /// later return to the tab, so a reader who cleared the chips would find them back the next time
    /// they pressed `Map` — with nothing on screen explaining why. `takePendingMapFilter()` is the
    /// only read and it clears as it answers.
    ///
    /// **The other half of that is on `tab`'s `didSet`, and the difference is not cosmetic** (PR
    /// #130 review, F1). This sentence used to say `goToTab` clears it, "so that arriving at the map
    /// any *other* way cannot pick up a narrowing somebody armed and abandoned" — and the way a
    /// reader actually arrives at the map is C16's bar, whose binding writes `tab` directly and
    /// never calls `goToTab`. The claim was false for the only path a finger takes. Disarming on the
    /// tab change itself makes it true for every path, including the ones nobody has written yet.
    ///
    /// `nil` is the ordinary state and means "open the map as it always did".
    private(set) var pendingMapFilter: MapFilter?

    func push(_ route: Route) { push(route, unlessAlreadyOnTop: false) }

    /// Pushes, optionally declining to stack a second copy of the screen already in front.
    ///
    /// The visit flow needs the second form (ERRATA E151). Screen 18's back-to-this-tree control
    /// is reached from two entrances, and one of them — the profile's own photo CTA — is *already on that
    /// tree's profile*. Pushing unconditionally put a second, identical profile of the same tree on the
    /// stack, so the way out got one chevron longer every time somebody photographed a tree from its own
    /// page and then looked at what they had just added.
    func push(_ route: Route, unlessAlreadyOnTop: Bool) {
        if unlessAlreadyOnTop, path.last == route { return }
        path.append(route)
    }

    func present(_ route: Route) { sheet = route }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// Back to the map, from wherever the app is — the one **absolute** destination in this router.
    ///
    /// ── Why this had to exist (ERRATA E151) ───────────────────────────────────────────────────
    /// Every other way out of the capture flow is *relative*. `onExit` dismisses the cover to whatever
    /// happened to be underneath it and `onSaved` pops one level, so "where does the app go when I have
    /// finished" had no answer of its own — it was however many screens deep the person happened to be.
    /// From the map's FAB that lands on the map and looks correct; from a tree's own photo CTA, which is
    /// the app's own primary call to action on screen 03, it lands back on the tree profile, and from
    /// there the map is another chevron away with nothing on screen naming it. The owner's report is
    /// exactly that: "need a back to map button/functionality after taking photo/checking in".
    ///
    /// `popToRoot()` had been sitting in this file with **no caller anywhere in the app** — the operation
    /// that means "back to the map" existed and nothing asked for it.
    ///
    /// All three fields, and the order matters. `sheet` first so the cover is on its way out before the
    /// stack under it changes; `path` because a tab root is invisible beneath a pushed destination (see
    /// `goToTab`); `tab` last because it is the thing being asked for.
    func goToMap() { goToMap(showing: nil) }

    /// Back to the map, **narrowed to something the reader asked for on another screen** (F23).
    ///
    /// The order is load-bearing: reaching the map clears `pendingMapFilter` twice over — `goToTab`
    /// clears it outright, and `tab`'s own `didSet` clears it on the change — so arming first would
    /// arm and immediately disarm. Everything else about the destination is `goToMap()`'s, unchanged.
    ///
    /// `showing: nil` is exactly `goToMap()` — a caller that has no narrowing to ask for is asking
    /// for the plain map, and this must not become a second way to reach it with different
    /// behavior.
    func goToMap(showing filter: MapFilter?) {
        goToTab(.map)
        pendingMapFilter = filter
    }

    /// The narrowing screen 01 has not applied yet, cleared by the asking.
    ///
    /// Screen 01 reads this once on appearance and once on every later change, so an arming that
    /// lands while the map is already on screen is applied there and then rather than waiting for a
    /// tab switch that may never come. Clearing on read is what keeps the second channel from
    /// re-applying what the first one already did.
    func takePendingMapFilter() -> MapFilter? {
        defer { pendingMapFilter = nil }
        return pendingMapFilter
    }

    /// The same, for any tab root.
    ///
    /// **Clearing `path` is not optional here**, and that was a live defect: this router keeps *one*
    /// `path` for all four tabs, so setting `tab` while something is pushed swaps the root underneath a
    /// screen that stays on top of it. Screen 18's "Route done · see your grove" did exactly that — from
    /// the profile entrance it dismissed the cover onto the tree profile, with the grove it had just been
    /// asked for hidden beneath, and the only sign anything had happened was that Back went somewhere new.
    ///
    /// It also drops any `pendingMapFilter` (F23): this is the operation that means "arrive at a tab
    /// root plainly", and a narrowing armed for a map nobody went to would otherwise sit here and
    /// fire at whatever reached screen 01 next. **`tab`'s `didSet` is what covers the paths that do
    /// not come through here** — C16's bar and the debug deep links both assign `tab` directly — and
    /// this line is what covers `goToTab(.map)` called while the map is already the tab, where the
    /// assignment changes nothing and the `didSet` therefore does not fire.
    func goToTab(_ destination: Tab) {
        sheet = nil
        path.removeAll()
        pendingMapFilter = nil
        tab = destination
    }

    /// Swaps a pushed route for another one, in place.
    ///
    /// For the case where a screen discovers *on load* that the record it was pushed for belongs to
    /// a different screen — a vacant planting site reached from the almanac, the visit flow or a
    /// stale link, which has its own screen since E107 and cannot be drawn as a tree profile since
    /// E113. The status arrives with the payload, one read after the push, so the entrance could not
    /// have known.
    ///
    /// **In place rather than push-then-pop**, for two reasons. `Back` from the site must return to
    /// the entrance, not to the profile that should never have opened; and a `push` would leave the
    /// wrong screen sitting under the right one, where a swipe-back lands on it.
    ///
    /// Targeted rather than "replace the top": by the time an `async` load returns, the top may no
    /// longer be the screen that asked. If the route being replaced is not on the path at all — a
    /// preview, a tab root, a screen already popped — this pushes, which is the same destination by
    /// a longer road rather than a silent no-op.
    func replace(_ route: Route, with replacement: Route) {
        guard let index = path.lastIndex(of: route) else {
            push(replacement)
            return
        }
        path[index] = replacement
    }
}

// MARK: - C16

extension AppRouter {

    /// The bottom bar's selection, translated.
    ///
    /// C16 speaks `Map / My Grove / Journal / You` (its labels are verbatim from SCREENS.md §2) and
    /// this router speaks `map / grove / journal / you`. Every tab root has to do that translation,
    /// and there are four of them now that `Journal` and `You` are built — `MapHomeView` and
    /// `GroveView` each wrote their own before there was a third. One copy here means a fifth tab
    /// root cannot get it subtly wrong in a way that only shows up as a bar highlighting the wrong
    /// icon.
    var bottomTabSelection: Binding<BottomTabBar.Tab> {
        Binding(
            get: {
                switch self.tab {
                case .map: return .map
                case .grove: return .myGrove
                case .journal: return .journal
                case .you: return .you
                }
            },
            set: { selection in
                switch selection {
                case .map: self.tab = .map
                case .myGrove: self.tab = .grove
                case .journal: self.tab = .journal
                case .you: self.tab = .you
                }
            }
        )
    }
}
