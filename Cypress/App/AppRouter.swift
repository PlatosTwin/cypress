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
    case measure(UUID)          // 16
    case outbox                 // 17
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
