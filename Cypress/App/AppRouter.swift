import Foundation
import Observation
import SwiftUI

/// Where the app can go.
///
/// Screen numbers refer to `docs/distilled/SCREENS.md`. Only routes with a mocked screen or a
/// BUILD-PLAN §9 entry belong here — per DECISIONS constraint 21, an unmocked destination is a
/// question for the design, not a case to invent.
enum Route: Hashable {
    case treeProfile(UUID)      // 03 (14 when the tree is cold, 19 when removed)
    case identify               // 02 what tree is this
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

    /// Sheets are modal over the current tab rather than pushed — screens 09, 10 and 15 are drawn
    /// as bottom sheets over a dimmed profile, not as full screens.
    var sheet: Route?

    func push(_ route: Route) { path.append(route) }
    func present(_ route: Route) { sheet = route }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
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
