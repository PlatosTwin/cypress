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
/// **The instrument is the element type's name in a query position, and it is blunt on purpose.**
/// A UI test naming `scrollView` inside a query at all is a test resolving a container by element
/// type by hand, which is the whole of the pattern; `otherElements` is not usable as the tell,
/// because naming an `Other` directly is an ordinary, correct thing to do
/// (`MapFilterAccessibilityTests` asserts that the opened drawer is a named container that way).
/// Comments are stripped before the check for `DragGestureGateTests`' reason — the files that used
/// to spell this now describe having done so.
///
/// **Why it is not just the literal `.scrollViews`.** It was, for one round, and PR #66's reviewer
/// red-proved the hole with a probe and a control at one insertion point:
/// `app.descendants(matching: .scrollView).firstMatch` walked straight past a green gate, while
/// `app.scrollViews.firstMatch` on the same line failed it. `XCUIElementQuery` offers at least four
/// spellings of the same idea — the property, `descendants(matching:)`, `children(matching:)` and
/// `element(matching:)` — so the forbidden three-line guess was one query spelling away from being
/// representable again.
///
/// **The residual hole, written down rather than papered over.** This matches per line: the type
/// name and a query word have to appear on the same one. An element type bound to a `let` first —
///
///     let type: XCUIElement.ElementType = .scrollView
///     _ = app.descendants(matching: type).firstMatch
///
/// — is invisible to it, and so is a call broken across lines so that `scrollView` lands alone.
/// Neither exists in the suite today. The alternative is a parser with its own bugs standing
/// between a red gate and a fix, which `DragGestureGateTests` already declined once.
///
/// Checked from the unit suite because it runs on every build and every shard, where a gate inside
/// the UI suite could be skipped by the very sharding it protects.
@Suite("Every labeled container is resolved through one helper")
struct ContainerSpellingGateTests {

    /// The file allowed to name the element types: the helper's own definition.
    static let helperFile = "UIWait.swift"

    /// The element type no other UI test may name in a query. Case-sensitive on the leading `s`,
    /// which is what separates the *query* spellings (`scrollViews`, `.scrollView`) from the
    /// SwiftUI view a dozen comments and failure messages talk about (`ScrollView`).
    static let elementType = "scrollView"

    /// The words that make an occurrence of `elementType` a query rather than a value.
    ///
    /// `ContainerSpelling` is an enum whose cases are named for the element types, and
    /// `FrameFinitenessGateTests` drives the resolver with `[.scrollView: frame]` dictionaries —
    /// legitimate, and it names the case a dozen times. What is forbidden is putting the type into
    /// something that *queries the tree*, and every spelling of that carries one of these.
    static let queryContext = ["app.", "matching", "descendants", "children", "element("]

    /// The helper every other file must call instead.
    static let helper = "resolvedContainer"

    /// The lines of `code` that name the element type in a query position.
    ///
    /// A free function of a string so the scanner can be run against cases whose answers are
    /// already known, which is the only thing separating this measurement from a coincidence.
    static func elementTypeQueries(in code: String) -> [Int] {
        code.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .filter { _, line in
                line.contains(elementType) && queryContext.contains(where: { line.contains($0) })
            }
            .map { index, _ in index + 1 }
    }

    /// **The calibration.** A gate that reported nothing would look identical to a clean suite, and
    /// this suite has filed a defect for exactly that shape. Both directions are checked.
    @Test("the scanner catches every query spelling and leaves the enum's own cases alone")
    func scannerIsCalibrated() {
        let mustCatch = """
        _ = app.scrollViews.firstMatch
        return other.exists ? other : app.scrollViews[label]
        _ = app.descendants(matching: .scrollView).firstMatch
        let legend = app.children(matching: .scrollView).element(boundBy: 0)
        _ = app.otherElements.element(matching: .scrollView, identifier: label)
        """
        #expect(
            Self.elementTypeQueries(in: mustCatch) == Array(1...5),
            """
            the scanner missed a query spelling it must catch: it found \
            \(Self.elementTypeQueries(in: mustCatch)) where all five of those lines resolve a \
            container by element type by hand — line 3 is the one PR #66's reviewer red-proved \
            against the previous instrument
            """
        )

        let mustNotCatch = """
        return [.scrollView: self.clampedLegend]
        XCTAssertEqual(resolved?.spelling, .scrollView)
        let resolved = drive(until: 12) { _ in [.scrollView: self.clampedLegend] }
        let other = app.otherElements[label]
        + "between a plain group and a `ScrollView` as its species palette fills"
        """
        #expect(
            Self.elementTypeQueries(in: mustNotCatch).isEmpty,
            """
            the scanner flagged a line it must leave alone: \
            \(Self.elementTypeQueries(in: mustNotCatch)). `ContainerSpelling.scrollView` is a value \
            and `FrameFinitenessGateTests` is entitled to name it; `ScrollView` with a capital S is \
            the SwiftUI view this suite's prose is about; and naming an `Other` directly is the \
            ordinary correct thing this gate must never make unrepresentable
            """
        )
    }

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
            .filter { $0.name != Self.helperFile }
            .map { (name: $0.name, lines: Self.elementTypeQueries(in: $0.code)) }
            .filter { !$0.lines.isEmpty }
            .map { "\($0.name) \($0.lines)" }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) name(s) `\(Self.elementType)` in a query instead \
            of calling `\(Self.helper)(_:labeled:_:)`. Which element type XCUITest files a labeled \
            SwiftUI container under is decided by the app and can change during a launch — \
            `MapSpeciesLegend` renders a plain group until its species palette outgrows the screen \
            and a `ScrollView` after — so a read that picks one and holds it binds whichever \
            spelling the moment happened to offer. Use the helper, which waits for the container to \
            hold still before it decides.
            """
        )
    }
}
