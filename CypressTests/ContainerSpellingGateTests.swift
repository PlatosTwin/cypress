import Foundation
import Testing

/// **One spelling of "resolve a labeled container to its element type", enforced from the unit
/// suite.**
///
/// The pattern this keeps to one site is three lines long, and existed three times:
///
///     let other = app.otherElements[label]
///     return other.exists ? other : app.scrollViews[label]
///
/// `IdentifyFABReachabilityTests.container(_:_:)`, `MapFilterAccessibilityTests.rowContainer(_:)`
/// and an inline copy inside `MapRecenterUITests
/// .testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied` — one helper written once
/// and then copied by hand, with the second and third copies citing the first in a comment. Every
/// copy decided which element type to bind to from **one un-waited read of a still-loading screen**,
/// and that is what failed `IdentifyFABReachabilityTests
/// .testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied` intermittently in CI: it
/// bound to the `Other` the legend renders while its species palette is still filling, and then
/// spent 30 s waiting for an element that had already been replaced by a `ScrollView`. The failure
/// says the legend "never appeared", which is the same sentence a genuinely absent legend produces —
/// which is how the two causes were confused for a round.
///
/// `ContainerSpellingResolution` and `XCTestCase.resolvedContainer` (`CypressUITests/UIWait.swift`)
/// carry the rule and the reason. This is `DragGestureGateTests`' argument applied a third time:
/// a fix copied by hand is a fix that comes back under a different test's name, so the careless
/// spelling is made unrepresentable instead of carefully re-fixed.
///
/// **The instrument is `scrollViews`, and it is blunt on purpose.** A UI test reaching for
/// `app.scrollViews` at all is a test resolving a container by element type by hand, which is the
/// whole of the pattern; `otherElements` is not usable as the tell, because naming an `Other`
/// directly is an ordinary, correct thing to do (`MapFilterAccessibilityTests` asserts that the
/// opened drawer is a named container that way). Comments are stripped before the check for
/// `DragGestureGateTests`' reason — the files that used to spell this now describe having done so.
///
/// Checked from the unit suite because it runs on every build and every shard, where a gate inside
/// the UI suite could be skipped by the very sharding it protects.
@Suite("Every labeled container is resolved through one helper")
struct ContainerSpellingGateTests {

    /// The file allowed to name the element types: the helper's own definition.
    static let helperFile = "UIWait.swift"

    /// The query no other UI test may spell. The `.` is part of it so that the prose-shaped
    /// mentions a gate cannot see anyway are not what this is matching on — this is a *call*.
    static let query = ".scrollViews"

    /// The helper every other file must call instead.
    static let helper = "resolvedContainer"

    @Test("no UI test resolves a labeled container by element type on its own")
    func onlyTheHelperNamesTheElementTypes() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let sources = try DragGestureGateTests.uiTestSources(root: root)

        // The scanner's own control, for `DragGestureGateTests`' reason: an empty read satisfies
        // every check below vacuously.
        #expect(
            sources.count >= 10,
            """
            found only \(sources.count) Swift files under CypressUITests/ — the scanner is not \
            reading the source, so this gate passes without checking anything
            """
        )

        // The helper must still exist, and must still be the thing that watches BOTH spellings.
        // Without this the gate goes green if `resolvedContainer` is deleted or gutted down to one
        // element type, which is the guess it was written to stop.
        let helperSource = sources.first { $0.name == Self.helperFile }
        #expect(
            helperSource?.code.contains("func \(Self.helper)(") == true
                && helperSource?.code.contains("app.scrollViews[label]") == true
                && helperSource?.code.contains("app.otherElements[label]") == true,
            """
            \(Self.helperFile) no longer defines `\(Self.helper)` over both element types. Either \
            the helper was removed — in which case every labeled container in the suite is resolved \
            by guess again — or it moved, and this gate needs to be told where to.
            """
        )

        let offenders = sources
            .filter { $0.name != Self.helperFile && $0.code.contains(Self.query) }
            .map(\.name)
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) name(s) `\(Self.query)` directly instead of \
            calling `\(Self.helper)(_:labeled:_:)`. Which element type XCUITest files a labeled \
            SwiftUI container under is decided by the app and can change during a launch — \
            `MapSpeciesLegend` renders a plain group until its species palette outgrows the screen \
            and a `ScrollView` after — so a read that picks one and holds it binds whichever \
            spelling the moment happened to offer. Use the helper, which waits for the container to \
            hold still before it decides.
            """
        )
    }
}
