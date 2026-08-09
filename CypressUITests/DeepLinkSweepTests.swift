import XCTest

/// The two deep-link tests that sweep EVERY screen, rather than examining one.
///
/// **Why they are their own class (#204).** Both launch the app once per screen — six screens and
/// nine — where every other test in `DeepLinkVoiceOverTests` launches once and looks at one. That
/// made them 148 of that class's 462.8 seconds (run 30874574621), and the class the longest CI job
/// at 18 minutes: it set the release gate's pace by itself, because a shard can be no faster than
/// its slowest class.
///
/// Splitting by CLASS rather than by method is the point. `Tools/ui-test-shards.txt` balances
/// classes and `UITestShardCoverageTests` proves every class is assigned exactly once; a per-method
/// shard list would be a list of names that a rename breaks, guarding nothing the compiler already
/// guards. A class is a unit both the shard file and the compiler understand.
///
/// Nothing about what they assert has changed — the harness they use is the same one, now in
/// `DeepLinkHarness.swift`.
final class DeepLinkSweepTests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Every pushed screen says where it is before it says anything else.
    ///
    /// A VoiceOver user meets a screen from the top of its element tree. If the first control is not
    /// the way out, or the first words are content rather than the screen's name, they are told what
    /// is here before they are told where here is — and nine screens deep that is the difference
    /// between navigating and guessing.
    ///
    /// **The order comes from `debugDescription`, and that choice is the whole lesson of E118.** The
    /// obvious API, `allElementsBoundByIndex`, returns the query engine's match order: on screen 05 it
    /// puts the pinned `Save check-in` at y=710 ahead of the `Back` at y=69, and a test built on it
    /// reported a defect that does not exist. `debugDescription` is a depth-first rendering of the
    /// actual element tree — the same artifact E117's screen dumps were read from — and one call gets
    /// all of it, which matters because recursing `children(matching:)` is one IPC round trip per node.
    ///
    /// The cost is that this parses a debugging format that Apple does not version. That failure is at
    /// least loud rather than silent: a format change yields no parsed elements and the count assertion
    /// fails, rather than the test quietly passing on an empty list.
    ///
    /// **`arrive`'s existence check is satisfied while the push is still animating in, and that is
    /// the window this method has to close itself (ERRATA E245, family of
    /// E242).** A `NavigationStack` push keeps the outgoing screen in the accessibility tree for the
    /// length of the slide transition, so `waitForExistence` on the pushed screen's anchor text
    /// returns the instant the incoming view enters the hierarchy — which is early in the animation,
    /// not after it settles — while the outgoing screen (its tab bar, its own rows) is still present
    /// and still ahead of the incoming screen in `debugDescription`'s depth-first order. Outbox is
    /// the arm that actually flaked (CI runs 31074532263, 31082691131): it pushes from the You tab,
    /// whose `IconTextRow` rows carry combined labels like "Outbox, What is waiting to send, and
    /// what has gone" and "Sign in, Gather what you save under one name on this phone" — exactly the
    /// two "first controls" both runs reported — and whose own tab bar item is the "You" both runs
    /// reported as the first static text. But the transition-overlap window is a property of every
    /// push, not of the You tab specifically, so every arm below waits the same way.
    func testEveryPushedScreenSaysWhereItIsFirst() {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        let screens: [(screen: String, anchor: String, title: String)] = [
            ("treeProfile", "Tree", "Tree"),
            ("site", "No tree at this site", "Site"),
            ("species", "Field guide", "Field guide"),
            ("checkIn", "Check-in", "Check-in"),
            ("report", "Report an issue", "Report an issue"),
            ("growthHistory", "Growth", "Growth"),
            ("activity", "Activity", "Activity"),
            ("measure", "Measure", "Measure"),
            ("outbox", "Outbox", "Outbox"),
        ]

        for case let (screen, anchor, title) in screens {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: anchor) else { continue }

            // Wait for the PUSHED screen's own identity before reading order — not its title text.
            // A title lookup was tried first and broke on `site`: `SiteCopy.headerTitle` and
            // `SiteCopy.siteLabel` are both literally "Site" — one the header, one a stat-grid row
            // that is ALSO on screen once loaded — so a label match is permanently ambiguous there,
            // not just mid-transition, and XCUITest raises "Multiple matching elements" rather than
            // ever settling. `check()` (`DeepLinkHarness.swift`) already treats the tab bar's
            // disappearance as the identity signal for "this is the pushed screen, not the tab
            // root it came from" — every screen this sweep visits covers the tab bar once actually
            // pushed, deep link or not.
            //
            // `waitForPushedScreenToArrive` (`DeepLinkHarness.swift`) is the one definition of this
            // wait — task #243 hoisted it out of this method and into the harness so `check()`'s own
            // tab-bar assertion, previously one-shot and reading the identical signal, shares it
            // rather than growing a second dialect.
            //
            // This establishes only that the tab root is gone — never that `Back` is first, and
            // never anything about the title's position — so the order assertions immediately below
            // stay capable of failing on a fully settled screen whose reading order is genuinely
            // wrong.
            guard waitForPushedScreenToArrive(app, screen: screen) else {
                app.terminate()
                continue
            }

            let ordered = Self.treeOrder(app.debugDescription)
            XCTAssertGreaterThan(
                ordered.count, 3,
                "\(screen): the element tree could not be parsed — `debugDescription`'s format has "
                    + "probably changed, and this test is no longer reading an order at all"
            )

            XCTAssertEqual(
                ordered.first(where: { $0.kind == "Button" })?.label, "Back",
                "\(screen): the first control in the element tree is "
                    + "'\(ordered.first(where: { $0.kind == "Button" })?.label ?? "nothing")' rather "
                    + "than Back, so the way out is not the first thing offered"
            )
            XCTAssertEqual(
                ordered.first(where: { $0.kind == "StaticText" })?.label, title,
                "\(screen): the first words read are "
                    + "'\(ordered.first(where: { $0.kind == "StaticText" })?.label ?? "nothing")' "
                    + "rather than the screen's own name"
            )

            app.terminate()
        }
    }

    /// Nothing may be announced twice.
    ///
    /// The E104 failure mode as a rule rather than a component: a container that carries a label *and*
    /// exposes a child carrying the same one is two stops on the same words, and a screen full of them
    /// is a screen that takes twice as long to hear. Checked as containment rather than adjacency,
    /// because that is the shape the defect actually takes — a labeled wrapper around a labeled leaf.
    ///
    /// **The enumeration is a set, never an order, and that restriction is load-bearing (ERRATA
    /// E118).** Whichever `allElements…` spelling produces it, the sequence is the query engine's
    /// match order, which is neither the accessibility hierarchy's nor the screen's geometry: on
    /// screen 05 it returns the pinned `Save check-in` at y=710 *before* the `Back` at y=69, while
    /// the hierarchy has Back nine positions earlier. A reading-order assertion built on it reports
    /// defects that do not exist. If VoiceOver's order is ever tested here, it has to come from
    /// recursing the element tree. The containment comparison below therefore asks about **both**
    /// orientations of every pair — see the comment on it.
    ///
    /// **Bound by accessibility element rather than by index, and every value read out of a proxy
    /// exactly once.** `allElementsBoundByIndex` hands back proxies bound to an *ordinal*: every
    /// later `.frame`, `.isHittable` or `.label` re-resolves the query by that number against a live
    /// tree, and when the tree changes under the walk the number stops resolving and XCUITest raises
    ///
    ///     Failed to get matching snapshot: No matches found for Element at index 25
    ///
    /// which is a report about the walk rather than about the app. This method walks every static
    /// text in the app six times per run, on a screen that is still settling, so it met that raise
    /// three times on PR #66 — at index 25, index 3 and index 17, the last of them on a tree
    /// byte-identical to one the same shard had passed. `allElementsBoundByAccessibilityElement`
    /// binds each proxy to the underlying accessibility element instead, so a later read resolves by
    /// identity and a change in the *count* costs the walk nothing.
    ///
    /// **The hazard that spelling carries, ruled out on the device rather than argued about.** It
    /// de-duplicates by accessibility element, and this method exists to catch a labeled container
    /// that also exposes a labeled child saying the same words — if those ever collapsed to one
    /// entry the test would stop being able to find its own defect and stay green. Measured on
    /// iPhone 16 Pro at 402 pt, on all six screens, and with a duplicate deliberately planted on
    /// screen 11: the two spellings return the same count, the same labels and the same frames every
    /// time, and the planted pair — two `Text`s carrying one label, the larger rectangle strictly
    /// containing the smaller — comes back as two entries under both. What survives *neither*
    /// spelling is a labeled container XCUITest files as an `Other`: `app.staticTexts` does not
    /// return it, so the E104 shape is only visible here when the wrapper is itself a `StaticText`.
    /// That is a limit on this method's reach which predates the binding, and it is recorded in
    /// `docs/errata-pending/` rather than left implied.
    ///
    /// **This narrows the window rather than closing it.** An element that leaves the tree between
    /// the snapshot and a later read is still gone; what changes is that a *neighbor* leaving no
    /// longer takes this element's identity with it. `.exists` is asked first for the same reason
    /// `assertEveryControlIsLabeled` asks it, so a vanished element is skipped rather than raised on.
    ///
    /// **Every frame compared here goes through `settledFrame`, not a raw `.frame` read — this was
    /// the one call site in the suite that compared geometry with no settle-or-finite wait at all.**
    /// This method launches six times, each launch racing the seed attach and the screen's own
    /// layout against whatever else a shared CI runner is doing; a containment check built on a
    /// frame read mid-layout can both miss a real overlap (the not-yet-settled child has not
    /// reached its final, overlapping position) and manufacture one that is not there. `settledFrame`
    /// also refuses a non-finite read (`{{inf, inf}, {inf, inf}}`) rather than accepting it as
    /// "stable" — see `frameHasSettled` in `UIWait.swift`. Read once per element and cached, not
    /// once per pair compared, so the nested loop below does not re-wait for the same element's
    /// frame on every label it happens to share.
    ///
    /// **The per-element budget matches every other hittability wait in the suite (30s), not the 5s
    /// this shipped with (task #244).** The settle-or-finite treatment above was already correct —
    /// it is not what failed. Main run 31096120555's `ui (3)` attempt 1 (tree 73b4850) failed exactly
    /// here: `treeProfile`'s static text #5 ("DBH, 30–35 cm, from the city record") sat in the tree,
    /// present, for longer than 5s without becoming hittable, on a runner sharing load across four
    /// classes in the same shard. `assertReachable`'s own doc comment gives the reason every other
    /// call site in the suite already uses the generous ceiling: it "costs nothing when the element
    /// is reachable" and only extends how long a genuine defect takes to report. Nothing this method
    /// asserts is weakened by the larger ceiling — a static text that never becomes hittable still
    /// fails, just not on a budget this method's own six-launches-per-run cost was never sized against.
    func testNothingIsAnnouncedTwice() {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        for (screen, anchor) in [
            ("treeProfile", "Tree"), ("site", "No tree at this site"), ("species", "Field guide"),
            ("growthHistory", "Growth"), ("activity", "Activity"), ("outbox", "Outbox"),
        ] {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: anchor) else { continue }

            // `isHittableWithoutRaising`, not the raw property (`UIWait.swift`). This filters every
            // static text in the app, and CI run 31300530216's `ui (3)` died right here: "Failed to
            // determine hittability of StaticText at {{inf, inf}, {0.0, 0.0}}". A frame with no
            // interior is not an unreachable element being reported, it is `isHittable` raising.
            //
            // **The app's rectangle is hoisted out of the closure**, and `appFrame` rather than
            // `screen` because `screen` is already this loop's screen *name*, which every failure
            // message below interpolates. `app.frame` is a query: reading it once per element put a
            // `Find the Target Application` round trip between every pair of element queries, and on
            // PR #66's first CI run this loop died on "No matches found for Element at index 25" —
            // the index having stopped resolving while the enumeration walked it. The hoist narrowed
            // that window and did not close it (index 3, then index 17); binding by accessibility
            // element rather than by index is what removed the ordinal there was to lose.
            let appFrame = app.frame
            let texts = app.staticTexts.allElementsBoundByAccessibilityElement
                .filter { $0.exists && $0.isHittableWithoutRaising(onScreen: appFrame) }

            // **Each element's label and settled frame read once, into plain values.** Everything
            // below is arithmetic over `String` and `CGRect` and touches no proxy at all. The
            // version this replaces read `.label` once per element in the outer loop and again for
            // every pair in the inner one — O(n²) re-resolutions of a query against a tree that is
            // still settling, for a screen with twenty to thirty reachable static texts on it.
            let announced: [(label: String, frame: CGRect)] = texts.enumerated()
                .map { index, element in
                    let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (
                        label,
                        settledFrame(
                            element, "\(screen)'s static text #\(index) (“\(label)”)", timeout: 30
                        )
                    )
                }

            // A screen this method read nothing from is not a screen it checked. Without this an
            // enumeration that returned an empty array — a query spelling that stopped matching,
            // a screen that had not finished arriving — is indistinguishable from a clean screen.
            XCTAssertGreaterThan(
                announced.count, 0,
                "\(screen): not one static text was reachable, so no pair was compared and this "
                    + "screen was not actually examined"
            )

            for (index, outer) in announced.enumerated() where !outer.label.isEmpty {
                for inner in announced[(index + 1)...] where inner.label == outer.label {
                    // Containment, not mere repetition: two different rows may legitimately say the
                    // same words. One element drawn inside another saying them is the defect.
                    //
                    // **Both orientations, because the enumeration is a set (E118).** The version
                    // this replaces asked only whether the EARLIER entry contained the later one,
                    // which reads the sequence as if the query engine returned wrappers before
                    // leaves. It does not promise that.
                    //
                    // **What was actually measured, rather than what would be convenient to claim.**
                    // In the one specimen this could be planted on — two `Text`s with one label, the
                    // larger strictly containing the smaller — the query engine did return the
                    // container first, so the single-direction version caught it too. The reverse
                    // orientation could not be synthesized: declaring the small one first puts it
                    // *under* its twin, whereupon it stops being hittable and the filter above
                    // correctly drops it, and the pair the comparison would have seen is gone. So
                    // this is a guard against an order nobody here has observed — kept because it
                    // costs one `contains` and because reading an order out of this sequence is
                    // exactly what E118 was filed for, not because a run went red without it.
                    guard let nested = Self.nesting(outer.frame, inner.frame) else { continue }
                    XCTFail(
                        "\(screen): '\(outer.label)' is announced by an element at "
                            + "\(nested.container) and again by one inside it at "
                            + "\(nested.contained), so it is heard twice"
                    )
                }
            }
            app.terminate()
        }
    }

    /// Which of two rectangles contains the other, if either does.
    ///
    /// Pure `CGRect` arithmetic and a static function so it can be reasoned about — and, if it ever
    /// earns one, tested — without a live element. `CGRect.contains` is true of two equal
    /// rectangles, which is deliberate: two elements saying the same words in the same place are
    /// heard twice as surely as a wrapper and its leaf are.
    static func nesting(_ a: CGRect, _ b: CGRect) -> (container: CGRect, contained: CGRect)? {
        if a.contains(b) { return (a, b) }
        if b.contains(a) { return (b, a) }
        return nil
    }
}
