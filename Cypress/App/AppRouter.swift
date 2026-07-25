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
    case measure(UUID)          // 16
    case outbox                 // 17
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
    /// 15, the account ask. **Mocked**, so this is not an invented destination — and `sheet`'s own
    /// comment below has always named 15 among the three screens drawn as sheets, which is what this
    /// case finally lets it mean.
    ///
    /// Presented, never pushed. It has no entrance of its own until now: D9 puts the ask on the
    /// third visit save, where `VisitSavedView` covers it directly, and no route was needed. The You
    /// tab needs one because it can sign you *out* (ERRATA E131), and a sign-out with no way back
    /// short of three more field visits is a door that locks behind you.
    case accountAsk             // 15
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
    var tab: Tab = .map
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

    /// Sheets are modal over the current tab rather than pushed — screens 09, 10 and 15 are drawn
    /// as bottom sheets over a dimmed profile, not as full screens.
    var sheet: Route?

    func push(_ route: Route) { path.append(route) }
    func present(_ route: Route) { sheet = route }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

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
