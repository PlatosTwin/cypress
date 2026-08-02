import Foundation

/// **The question 12 % of the map is the answer to: is this a tree, or somewhere a tree could go**
/// (task #179).
///
/// The seed distinguishes the two and the app has drawn the distinction since E107 — a vacant site
/// gets its own pin (`MapPin.Kind.vacantSite`), its own screen (`Route.site`), and is redirected off
/// the tree profile (#31). It had no way to be *searched for*, which is what this dimension is.
///
/// ── Why this exists at all, rather than vacant sites simply being hidden ──────────────────────
/// ROADMAP §1 settled it: the empty basins "are the single best answer to 'where could a tree go'",
/// which is close to the point of the app, and E115 established that hiding them is a status claim
/// the app is not entitled to make. Task #178 takes them out of the *year* filter, where they were
/// answering a question about planting dates they cannot honestly answer; this is what keeps that a
/// correction rather than a disappearance.
///
/// ── The count, measured rather than inherited ─────────────────────────────────────────────────
/// **24,200 of the seed's 198,625 rows — 12.2 % of the map.** The widely-quoted 12,518 / 6.4 %
/// (ROADMAP §1, RULINGS R7, `docs/investigations/`) is a San-Francisco-only figure from the
/// 195,309-row seed and has been stale since San Jose landed; see
/// `ERRATA E206`.
///
/// ── Why it lives in `Data/API` beside `MapMembership` ─────────────────────────────────────────
/// `MapViewport` carries it into the query layer, and `Data` may not import `Features`
/// (ARCHITECTURE §2). `MapMembership` is the same kind of value in the same position and is already
/// here. The *words* for it are `MapSiteKindFilterCopy`, which stays in `Features/Map`.
///
/// ── Why the two arms are defined against `TreeStatus` and not as a SQL string ─────────────────
/// The mapping from the five statuses to this binary is a fact about a tree, not about a screen, so
/// it is an exhaustive switch — the shape `TreeStatus.acceptsNewContributions` uses, and for the
/// same reason (E95): adding a status becomes a compile error rather than a silent assignment to
/// one arm. The seed carries only `alive` and `vacant_site` today, so every other case is a
/// decision about data that does not exist yet, taken once, in the open.
public enum MapSiteKind: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// A site with a tree standing on it, whatever condition it is in.
    case hasTree

    /// A planting basin with no tree in it — `trees.status = 'vacant_site'`.
    case emptySite

    public var id: String { rawValue }

    /// Which arm a status falls in.
    ///
    /// `removed` sits in `hasTree` and that is the one arm worth arguing. A removed tree is a
    /// *memorial* record (`TreeStatus.isMemorial`, DECISIONS §3.17) — a tree this app knows about
    /// and can still show you — and RULINGS R7 reserves the vacant-site presentation for a basin
    /// that never had one. Folding memorials into "empty planting site" would put them behind a
    /// filter whose label promises no tree was ever here, and would collide with R7 on the pin. So
    /// the binary is literally the one the seed draws: `vacant_site`, or not.
    public static func of(_ status: TreeStatus) -> MapSiteKind {
        switch status {
        case .alive, .declining, .deadReported, .removed:
            return .hasTree
        case .vacantSite:
            return .emptySite
        }
    }

    /// The `trees.status` values in this arm, for the query layer.
    ///
    /// Derived from `of(_:)` rather than written out a second time, so the SQL and the Swift cannot
    /// drift apart — the failure `TreeQueries.Narrowing`'s own comments describe as "a predicate
    /// that reached the pin query but not `markerCells`", one level down.
    public var statuses: [TreeStatus] {
        TreeStatus.allCases.filter { MapSiteKind.of($0) == self }
    }
}
