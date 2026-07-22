import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// What the M4 accessibility pass would lose silently if nobody pinned it.
///
/// ── Why these tests are shaped the way they are ────────────────────────────────────────────
///
/// The obvious test to write is "render the component, walk `UIAccessibility`, assert the labels".
/// It does not work, and the reason is worth recording because the next person will try it too.
/// **SwiftUI does not build a UIKit accessibility tree in-process.** A `UIHostingController` in a
/// key window, laid out, drawn, and given a run-loop turn reports `accessibilityElements` as an
/// empty array and `accessibilityElementCount()` as 0 for a plain labelled `Text`. Enabling
/// VoiceOver on the simulator (`defaults write com.apple.Accessibility VoiceOverTouchEnabled 1`)
/// does not change it: `UIAccessibility.isVoiceOverRunning` flips to `true` and the tree is *still*
/// empty, because SwiftUI serves the accessibility server over its own bridge rather than through
/// `NSObject`'s container protocol. Inspecting the real tree needs an out-of-process client —
/// XCUITest or Accessibility Inspector — and a UI-test bundle is a project-file change.
///
/// So these tests assert the **strings the accessibility modifiers are handed**, which is the part
/// with logic in it: run-length collapsing in C3, the D5 clamp reaching the spoken form, the
/// per-series D7 summary in C23, the method wording in C12, and the empty case in C26. That is a
/// behavioural test of the thing that can be wrong, not a grep for a modifier.
///
/// The half these cannot cover — that the label reaches a focusable element at all — is exactly
/// what this pass found broken in three places, and the fix for all three was the same one line:
/// `.accessibilityElement(children: .ignore)` before the label, so it attaches to an element rather
/// than to a `Shape`. That structural rule is asserted below as far as a unit test can: every
/// component that owns a visual encoding exposes its label as a property, and a property is
/// something a reviewer can see is wired.
@Suite("Accessibility (M4)")
struct AccessibilityTests {

    // MARK: - C3 · The foliage strip speaks the shape of a year

    /// The strip is a picture of one sentence — when this tree carries leaves — so the spoken form
    /// is that sentence. Runs, not months: a listener who has to hold twelve month-and-state pairs
    /// in their head to notice that a tree thins in April has been handed the drawing.
    @Test("C3 · the strip collapses its twelve cells into runs")
    func foliageStripSpeaksRuns() {
        let spoken = FoliageStrip.accessibilityLabel(for: FoliageStrip.grandmotherCypress)

        #expect(spoken.hasPrefix("Foliage through the year: "))
        #expect(spoken.contains("full canopy January to February"))
        #expect(spoken.contains("partial canopy March"))
        #expect(spoken.contains("thin canopy April to May"))
        #expect(spoken.contains("partial canopy June to August"))
        #expect(spoken.contains("full canopy September to December"))
        // Five runs, not twelve months.
        #expect(spoken.components(separatedBy: ", ").count == 5, "spoke: \(spoken)")
    }

    /// A single-month run says the month rather than "March to March".
    @Test("C3 · a one-month run is one month")
    func foliageStripSingleMonthRun() {
        var densities = Array(repeating: FoliageStrip.Density.full, count: 12)
        densities[5] = .bare
        let spoken = FoliageStrip.accessibilityLabel(for: densities)
        #expect(spoken.contains("bare June"))
        #expect(!spoken.contains("June to June"))
    }

    /// D5 reaches the spoken form, not only the drawing.
    ///
    /// The clamp lives in `enforcingD5`, which runs in the initializer, so the label is built from
    /// clamped densities. A label built from the caller's raw input instead would announce a bare
    /// month for an evergreen — leaking, in words, the exact claim the clamp exists to prevent
    /// (ARCHITECTURE §5.5, ERRATA E9).
    @Test("C3 · an evergreen never announces a bare month (D5)")
    func evergreenNeverSpeaksBare() {
        for retention in [LeafRetention.evergreen, nil] {
            let clamped = FoliageStrip.enforcingD5(
                Array(repeating: .bare, count: 12),
                leafRetention: retention
            )
            let spoken = FoliageStrip.accessibilityLabel(for: clamped)
            #expect(!spoken.lowercased().contains("bare"), "\(String(describing: retention)) spoke: \(spoken)")
            #expect(spoken.contains("thin canopy January to December"))
        }
        // And a deciduous species, which may be bare, still is.
        let deciduous = FoliageStrip.enforcingD5(
            Array(repeating: .bare, count: 12),
            leafRetention: .deciduous
        )
        #expect(FoliageStrip.accessibilityLabel(for: deciduous).contains("bare January to December"))
    }

    /// The three ramp steps say what they stand for, not what colour they are. The strip's whole
    /// visual vocabulary is three greens; "densest" is a token name, "full canopy" is the thing.
    @Test("C3 · the ramp is spoken as leaf, not as colour")
    func foliageDensitiesSpeakLeafNotColour() {
        #expect(FoliageStrip.Density.full.spokenName == "full canopy")
        #expect(FoliageStrip.Density.partial.spokenName == "partial canopy")
        #expect(FoliageStrip.Density.thin.spokenName == "thin canopy")
        #expect(FoliageStrip.Density.bare.spokenName == "bare")
        for density in FoliageStrip.Density.allCases {
            #expect(!density.spokenName.contains("green"))
            #expect(!density.spokenName.contains("densest"), "a ramp-token name reached the listener")
            #expect(!density.spokenName.contains("sparsest"))
        }
        // `bare` is the one case whose token name is already the English word, so it is the one
        // case where the spoken form and the raw value coincide. The other three do not.
        #expect(FoliageStrip.Density.bare.spokenName == FoliageStrip.Density.bare.rawValue)
        for density in [FoliageStrip.Density.full, .partial, .thin] {
            #expect(density.spokenName != density.rawValue)
        }
    }

    // MARK: - C12 · D7 survives being spoken

    /// The badge is four letters wide and the difference it marks is the difference between a
    /// reading and a guess. `taped` read aloud as "taped" hands a listener the token and keeps the
    /// meaning; `est.` read aloud is "est period".
    @Test("C12 · a method badge speaks its meaning, not its abbreviation")
    func methodBadgeSpeaksItsMeaning() {
        let cases: [(MeasurementMethod, drawn: String, spoken: String)] = [
            (.tape, "taped", "measured with a tape"),
            (.caliper, "caliper", "measured with a caliper"),
            (.laser, "laser", "measured with a laser"),
            (.estimate, "est.", "estimated"),
        ]
        for (method, drawn, spoken) in cases {
            let badge = MethodBadge(Quantity(value: 64, unit: .centimetres, method: method))
            #expect(badge.label == drawn, "the drawn badge changed: \(badge.label)")
            #expect(
                badge.accessibilityLabel == spoken,
                "the \(method) badge speaks \"\(badge.accessibilityLabel)\" rather than \"\(spoken)\""
            )
        }

        let cityRecord = MethodBadge(.cityRecord)
        #expect(cityRecord.label == "city record")
        #expect(cityRecord.accessibilityLabel == "from the city record")
    }

    /// The two that carry D7's load are the two that must not sound alike. A listener who cannot
    /// tell "taped" from "estimated" has lost the distinction the whole `Quantity` type exists for.
    @Test("C12 · measured and estimated are audibly different")
    func measuredAndEstimatedDoNotSoundAlike() {
        let taped = MethodBadge(Quantity(value: 64, unit: .centimetres, method: .tape))
        let estimated = MethodBadge(Quantity(value: 64, unit: .centimetres, method: .estimate))
        #expect(taped.accessibilityLabel != estimated.accessibilityLabel)
        #expect(taped.accessibilityLabel.contains("measured"))
        #expect(!estimated.accessibilityLabel.contains("measured"))
    }

    /// The growth-log size draws `estimated` where the inline size draws `est.`, and both speak the
    /// same sentence — the abbreviation is a drawing decision and never reaches the listener.
    @Test("C12 · both drawn sizes speak the same meaning")
    func bothBadgeSizesSpeakTheSame() {
        let quantity = Quantity(value: 64, unit: .centimetres, method: .estimate)
        let inline = MethodBadge(quantity, size: .inline)
        let log = MethodBadge(quantity, size: .growthLog)
        #expect(inline.label != log.label, "the two drawn sizes stopped differing")
        #expect(inline.accessibilityLabel == log.accessibilityLabel)
    }

    // MARK: - C23 · The charts

    /// Each series speaks its own ends with its own method, and never one span across both.
    ///
    /// D7 is not only a drawing rule. "One connecting line across estimated + taped values
    /// manufactures a trend that is not there" is a statement about what a reader may conclude, and
    /// a summary running from the oldest estimate to the newest tape reading manufactures the same
    /// trend with words instead of a polyline.
    @Test("C23 · the growth plot speaks each series separately, with its method")
    func lineChartSpeaksSeriesSeparately() {
        let chart = LineChart(points: [
            ChartPoint(x: 0, y: 0.1, quantity: Quantity(value: 47, unit: .centimetres, method: .estimate)),
            ChartPoint(x: 0.3, y: 0.3, quantity: Quantity(value: 52, unit: .centimetres, method: .estimate)),
            ChartPoint(x: 0.7, y: 0.7, quantity: Quantity(value: 58, unit: .centimetres, method: .tape)),
            ChartPoint(x: 1, y: 0.9, quantity: Quantity(value: 64, unit: .centimetres, method: .tape)),
        ])
        let spoken = chart.accessibilityLabel

        #expect(spoken.contains("2 readings measured with a tape: 58 cm to 64 cm"))
        #expect(spoken.contains("2 readings estimated: 47 cm to 52 cm"))
        #expect(
            !spoken.contains("47 cm to 64 cm"),
            "the plot spoke one span across both series — \"\(spoken)\". That is the connecting line D7 forbids, in words."
        )
    }

    /// One reading is a reading, not a range from itself to itself.
    @Test("C23 · a one-point series speaks the point")
    func lineChartSingleReading() {
        let chart = LineChart(points: [
            ChartPoint(x: 0, y: 0.5, quantity: Quantity(value: 47, unit: .centimetres, method: .tape)),
        ])
        #expect(chart.accessibilityLabel.contains("1 reading measured with a tape: 47 cm"))
        #expect(!chart.accessibilityLabel.contains("47 cm to 47 cm"))
    }

    /// An empty plot says it is empty. A chart that announces nothing is a chart a listener cannot
    /// tell from one that failed to load — which is the §5.6 problem in a different costume: a
    /// surface that draws nothing must not *speak* nothing while still being a stop.
    @Test("C23 · a plot with no readings says so")
    func emptyLineChartSaysSo() {
        #expect(LineChart(points: []).accessibilityLabel == "Growth plot with no readings.")
    }

    /// C23's bar row cannot summarise itself and the type stops it trying. `heights` are drawing
    /// units in the mock's 0…34 viewBox, already scaled against a maximum the *caller* chose — and
    /// on screen 13 that maximum is shared across three series so the rows can be compared (D2).
    /// Reading a height back out would announce a fraction of somebody else's maximum, which is a
    /// wrong count rather than no count.
    @Test("C23 · a bar row's label is required of the caller, not derived from the drawing")
    func barChartLabelIsRequired() {
        let row = BarChart(
            heights: [8, 4, 10, 13, 17, 34, 17, 10, 8, 8, 4, 4],
            accessibilityLabel: "Photos by month. January 2, March 3."
        )
        #expect(row.accessibilityLabel == "Photos by month. January 2, March 3.")
        #expect(!row.accessibilityLabel.contains("34"), "a viewBox height reached the listener")
    }

    // MARK: - C27 / C28 · The two meters

    /// C28's number is honest only with its qualification attached.
    ///
    /// `VisitShortlist.confidence(topDistanceM:runnerUpDistanceM:accuracyM:)` says outright that
    /// this is GPS geometry — how much clear air there is between the nearest tree and the next,
    /// against the fix's own error — and not a confidence that the species is right. A sighted user
    /// reads that off the screen around the bar, which is drawn under a card headed "CONFIRM BY
    /// EYE" beside a distinguishing trait. A listener has only the words.
    @Test("C28 · the confidence bar says what it is confident about")
    func confidenceBarIsQualified() {
        let spoken = ConfidenceBar(fraction: 0.88).accessibilityLabel
        #expect(spoken.contains("88 percent"))
        #expect(spoken.contains("GPS"))
        #expect(
            !spoken.hasPrefix("Confidence"),
            "the bar leads with a bare \"Confidence\" again — \"\(spoken)\""
        )
        // Out-of-range fractions clamp rather than announcing 140 percent.
        #expect(ConfidenceBar(fraction: 1.4).accessibilityLabel.contains("100 percent"))
        #expect(ConfidenceBar(fraction: -0.2).accessibilityLabel.contains("0 percent"))
    }

    // MARK: - C26 · Rendering nothing announces nothing

    /// ARCHITECTURE §5.6 / DECISIONS constraint 1, one level down from the aggregate rule: a stack
    /// with no bubbles in it is not an element.
    ///
    /// This was live. C26 carried an unconditional `children: .ignore` plus the word "Regulars",
    /// and E71 records that the API hands over caretakers as bare UUIDs with no initials — so on
    /// the shipping stack VoiceOver stopped on an empty box and said "Regulars". Sighted users saw
    /// no row; listeners were told there was one.
    @Test("C26 · an empty avatar stack has nothing to say")
    func emptyAvatarStackIsSilent() {
        #expect(AvatarStack(initials: [], overflow: nil).accessibilityLabel.isEmpty)
    }

    /// And when it does draw, it says what it drew. `+3` is a glyph; "3 more" is what a sighted
    /// reader takes from it.
    @Test("C26 · a drawn avatar stack speaks its bubbles")
    func filledAvatarStackSpeaksItsBubbles() {
        let full = AvatarStack(initials: ["N", "M", "J"], overflow: "+3").accessibilityLabel
        #expect(full == "Regulars: N, M, J, 3 more")

        // The shipping shape (E71): no initials, one overflow bubble.
        let overflowOnly = AvatarStack(initials: [], overflow: "+6").accessibilityLabel
        #expect(overflowOnly == "Regulars: 6 regulars")
        #expect(!overflowOnly.contains("+"), "the drawn glyph reached the listener")
    }

    /// The threshold that keeps the row from existing at all. Two caretakers is below A8's three,
    /// so there is no `Caretakers` value to hand a view — which is the reason the empty case above
    /// is a safety net rather than the normal path.
    @Test("§5.6 · below the caretaker threshold there is no surface to announce")
    func belowThresholdProducesNoSurface() {
        #expect(TreeProfilePresentation.caretakerThreshold == 3)
    }

    /// The other half of §5.6, in `Core`. A `Series` that is a page has no `totalCount`, so nothing
    /// that counts can render — or speak — a page's size as a total (ERRATA E38).
    @Test("§5.6 · a page has no count to announce")
    func aPageAnnouncesNoCount() {
        let page = Series(items: Array(repeating: UUID(), count: 30), isComplete: false)
        #expect(page.totalCount == nil)
        #expect(Series(complete: Array(repeating: UUID(), count: 30)).totalCount == 30)
    }

    // MARK: - Motion can always be switched off

    /// An animation that cannot be turned off is an accessibility defect, not polish. Every curve
    /// in the design system goes through `resolved(_:reduceMotion:)`, and `nil` — not a shorter
    /// curve — is what it returns: `Animation` has no "off", and `nil` is how SwiftUI is told to
    /// apply a state change without one. A faster animation is still an animation.
    @Test("every named curve can be switched off")
    func everyCurveHonoursReduceMotion() {
        let curves: [(String, Animation)] = [
            ("czFade", CypressMotion.fade),
            ("czSheet", CypressMotion.sheet),
            ("czPinDrop", CypressMotion.pinDrop),
            ("czPulse", CypressMotion.pulse),
            ("czFlash", CypressMotion.flash),
            ("czPop", CypressMotion.pop),
            ("map camera", CypressMotion.camera),
            ("pin selection", CypressMotion.selection),
        ]
        for (name, curve) in curves {
            #expect(
                CypressMotion.resolved(curve, reduceMotion: true) == nil,
                "\(name) still animates under Reduce Motion"
            )
            #expect(CypressMotion.resolved(curve, reduceMotion: false) != nil, "\(name) does not animate")
        }
    }

    /// The durations are the README's, and the point of naming them is that they stop drifting.
    /// Three literals existed in `Features/` before this pass and none of them matched each other.
    @Test("the durations are the ones the handoff names")
    func durationsMatchTheHandoff() {
        #expect(CypressMotion.Duration.fade == 0.32)
        #expect(CypressMotion.Duration.sheet == 0.5)
        #expect(CypressMotion.Duration.pinDrop == 0.45)
        #expect(CypressMotion.Duration.pulse == 2.4)
        #expect(CypressMotion.Duration.flash == 0.35)
        #expect(CypressMotion.Duration.pop == 0.4)
    }

    /// The offsets the keyframes move through, kept beside the curves so a caller cannot animate
    /// the right duration through the wrong distance.
    @Test("the keyframe offsets are the ones the handoff draws")
    func offsetsMatchTheHandoff() {
        #expect(CypressMotionOffset.fadeRise == 10)
        #expect(CypressMotionOffset.sheetRise == 90)
        #expect(CypressMotionOffset.pinDropRise == -14)
        #expect(CypressMotionOffset.pinDropScale == 0.4)
        #expect(CypressMotionOffset.flashOpacity == 0.9)
        #expect(CypressMotionOffset.pulseSpread == 10)
        #expect(CypressMotionOffset.pulseOpacity == 0.4)
    }
}
