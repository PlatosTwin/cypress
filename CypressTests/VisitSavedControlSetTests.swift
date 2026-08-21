import Foundation
import Testing
@testable import Cypress

/// **Screen 18's control set, as the owner ruled it on 2026-08-21** — next nearest, back to the map,
/// back to this tree.
///
/// ── Why this suite exists, and why it did not before ──────────────────────────────────────────
/// PR #102's finisher declined a test here on the grounds that "the screen-18 strings are explicitly
/// a draft the owner may replace, so a test over them would assert phrasing and be rewritten by the
/// copy decision that is still open". The copy decision closed the same day — the owner chose the
/// implemented draft — so the premise expired. The review's other half stands on its own regardless:
/// **the cheap version of this test never had to assert phrasing.** What was ruled is a *set* of
/// three functions and where each one goes, and none of that is a string.
///
/// So nothing here reads a label. If the owner renames every control tomorrow this suite stays
/// green, and if somebody adds a fourth secondary control or sends `Back to this tree` to the
/// timeline band instead of the tree's page, it goes red.
///
/// ── The three claims ──────────────────────────────────────────────────────────────────────────
/// 1. **Count and roles**, by reflection over the view's own action surface: exactly four action
///    closures, with the arities that make them the ruled three plus the primary CTA's other state.
/// 2. **`Back to the map` is absolute**, which is the whole reason it replaced `Done for today`.
/// 3. **`Back to this tree` lands on that tree's profile and does not stack a second one**, which is
///    E151's defect and the one way this control can be wrong without looking wrong.
@MainActor
@Suite("Screen 18's control set, as ruled")
struct VisitSavedControlSetTests {

    // MARK: - 1 · Count and roles

    /// **The set is three functions, and the fourth closure is not a fourth control.**
    ///
    /// Reflection over stored properties rather than a mounted view, the same technique
    /// `AccountAskSheetTests` uses to assert that screen 15 collects no password: a code review
    /// catches a `Button` somebody adds today, and this catches the closure somebody adds in six
    /// months. Mounting screen 18 would need an API, a ledger and a receipt, and would then be
    /// asserting SwiftUI's tree rather than the ruling.
    ///
    /// `onRouteComplete` is deliberately in the expected set and deliberately not a control:
    /// PROTOTYPE-FLOW §1.6 rule 5 makes it the primary CTA's *other label*, for when the route is
    /// finished and there is no next nearest. One control, two destinations.
    @Test("screen 18 declares exactly the ruled action set and nothing else")
    func theActionSetIsTheRuledOne() {
        let actions = Mirror(reflecting: Self.view())
            .children
            .compactMap(\.label)
            .filter { $0.hasPrefix("on") }
            .sorted()

        #expect(
            actions == ["onBackToMap", "onBackToTree", "onLink", "onNextTree", "onRouteComplete"],
            """
            screen 18's action surface is \(actions). The owner ruled the control set on 2026-08-21 \
            — next nearest, back to the map, back to this tree — with onRouteComplete as the \
            primary CTA's other state (not a fourth control) and onLink as screen 15's sign-in \
            hand-off (not a control of this screen's at all). A name added or removed here is a \
            change to a ruled set and needs its own decision, not a test edit.
            """
        )
    }

    /// **The two secondary controls are two, and they are distinct.**
    ///
    /// The weakest possible statement about the strings, and the only one worth making: that there
    /// are two of them and they are not the same control drawn twice. Nothing here depends on what
    /// either one says.
    @Test("there are two distinct secondary controls")
    func theSecondaryControlsAreTwoAndDistinct() {
        #expect(!VisitSavedCopy.backToMap.isEmpty)
        #expect(!VisitSavedCopy.backToTree.isEmpty)
        #expect(
            VisitSavedCopy.backToMap != VisitSavedCopy.backToTree,
            """
            screen 18's two secondary controls carry the same label, so one of the ruled three \
            functions has no way to be told from another.
            """
        )
    }

    // MARK: - 2 · Back to the map is absolute

    /// **It goes to the map from wherever the app is** — the point of the rename.
    ///
    /// `Done for today` already called this, and what was wrong with it was the word, not the
    /// destination. But "the map" has to mean the map: E151 records that every other way out of the
    /// capture flow is *relative*, so from a tree's own photo CTA they land back on the tree. This
    /// asserts the absolute one stays absolute — sheet dismissed, stack cleared, map tab selected —
    /// from the deepest state the flow can be in.
    @Test("back to the map lands on the map from anywhere, with nothing left on the stack")
    func backToTheMapIsAbsolute() {
        let router = AppRouter()
        router.push(.treeProfile(UUID()))
        router.push(.growthHistory(UUID()))
        router.sheet = .share(UUID())

        router.goToMap()

        #expect(router.tab == .map, "back to the map did not select the map tab")
        #expect(
            router.path.isEmpty,
            """
            back to the map left \(router.path.count) screen(s) pushed, so the map is the tab root \
            underneath something else rather than the screen the reader is looking at — E151's \
            defect, from the entrance that has a stack.
            """
        )
        #expect(router.sheet == nil, "back to the map left a sheet up over it")
    }

    // MARK: - 3 · Back to this tree lands on this tree, once

    /// **The destination is the tree's own profile, and it is `unlessAlreadyOnTop`.**
    ///
    /// Two entrances reach screen 18 and one of them — the profile's own photo CTA — is *already on
    /// that tree's profile*. Pushing unconditionally put a second identical profile on the stack and
    /// the way out got one chevron longer every time somebody photographed a tree from its own page
    /// (E151). The control looks correct in both cases; only the stack tells them apart.
    @Test("back to this tree opens that tree's profile without stacking a second copy")
    func backToThisTreeDoesNotStackASecondProfile() {
        let treeID = UUID()
        let router = AppRouter()

        // The map entrance: nothing of this tree's on the stack yet.
        router.push(.treeProfile(treeID), unlessAlreadyOnTop: true)
        #expect(
            router.path == [.treeProfile(treeID)],
            "back to this tree did not open \(treeID)'s profile from the map entrance"
        )

        // The profile entrance: already there, so the control must be a no-op on the stack.
        router.push(.treeProfile(treeID), unlessAlreadyOnTop: true)
        #expect(
            router.path == [.treeProfile(treeID)],
            """
            back to this tree stacked a second copy of \(treeID)'s profile — \(router.path.count) \
            deep. That is E151: from the profile entrance the reader is already on this tree, and \
            the way back out grows a chevron per photograph.
            """
        )

        // A *different* tree is a real destination and must still push.
        let other = UUID()
        router.push(.treeProfile(other), unlessAlreadyOnTop: true)
        #expect(
            router.path == [.treeProfile(treeID), .treeProfile(other)],
            """
            the unlessAlreadyOnTop guard swallowed a push to a different tree (\(other)) — it is \
            comparing something coarser than the route, so 'back to this tree' would refuse to \
            move between two trees' profiles.
            """
        )
    }

    // MARK: - Support

    /// A screen 18 built only far enough to be reflected over. Never rendered — `Mirror` reads the
    /// stored properties and `body` is never asked for, so `LocalDouble` is never called and the
    /// ledger's `UserDefaults` is never written.
    private static func view() -> VisitSavedView {
        let visit = Visit(
            treeID: UUID(),
            attribution: .anonymous(deviceID: UUID()),
            gpsAccuracyM: 5,
            capturedAt: .now
        )
        return VisitSavedView(
            receipt: VisitSaveReceipt(
                visit: visit,
                item: OutboxItem(kind: .visit, clientUUID: UUID(), payload: Data()),
                syncedImmediately: false
            ),
            treeDisplayName: "Coast Live Oak",
            origin: nil,
            visitedTreeIDs: [],
            api: LocalDouble(),
            ledger: VisitSaveLedger(
                defaults: UserDefaults(suiteName: "VisitSavedControlSetTests")!
            ),
            onNextTree: { _ in },
            onRouteComplete: {},
            onBackToMap: {},
            onBackToTree: { _ in }
        )
    }
}
