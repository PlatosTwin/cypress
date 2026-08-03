//
//  MeasurePreviews.swift
//  Cypress — Features/Measure
//
//  Previews for screen 16, including the states SCREENS.md does not draw: a tree with no previous
//  reading (which is every tree in the shipped app), a trunk that shrank, and a GPS fix D6 will not
//  chart.
//
//  `MeasureScreen` is fed a finished `MeasurePresentation` rather than an API, so a preview is the
//  state it says it is: a view whose content arrives from an `async` read renders as the loading
//  state in a detached window and photographs as one too.
//

#if DEBUG
import SwiftUI

// MARK: - Fixtures

enum MeasurePreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000016")!
    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    /// The year the mock is drawn in.
    static let now = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 18))!

    static let treeName = "Grandmother Cypress"

    static func date(_ year: Int, _ month: Int, _ day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 16 §3's drawn sanity pill: `Last recorded 62 cm, Jun 2024`.
    static func previousDBH(
        _ centimeters: Double = 62,
        method: MeasurementMethod = .tape,
        at capturedAt: Date = date(2024, 6, 14)
    ) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: capturedAt,
            gpsAccuracyM: 7,
            quantity: Quantity(value: centimeters, unit: .centimeters, method: method)
        )
    }

    static func draft(
        kind: MeasurementKind = .dbh,
        method: MeasurementMethod = .tape,
        unit: LengthUnit? = nil,
        entry: String
    ) -> MeasureDraft {
        var draft = MeasureDraft()
        draft.select(kind: kind)
        draft.method = method
        if let unit { draft.unit = unit }
        draft.entry = entry
        return draft
    }

    static func presentation(
        draft: MeasureDraft,
        treeDisplayName: String? = treeName,
        previous: TreeMeasurement? = nil,
        gpsAccuracyM: Double? = 8
    ) -> MeasurePresentation {
        MeasurePresentation(
            draft: draft,
            treeDisplayName: treeDisplayName,
            previous: previous,
            gpsAccuracyM: gpsAccuracyM,
            now: now
        )
    }
}

// MARK: - Previews

/// **The state SCREENS.md 16 draws**: `64` cm, tape, and the sanity pill under the readout.
#Preview("16 · measure") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(entry: "64"),
                previous: MeasurePreviewFixtures.previousDBH()
            )
        )
    }
}

/// **A first reading.** No previous measurement, so no sanity pill — which is every tree in the
/// shipped app, because the seed carries no `measurements` table and this screen is the only thing
/// that writes one.
#Preview("16 · first reading") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(entry: "")
            )
        )
    }
}

/// **The trunk shrank.** §7's "sure about that?", as a line above a CTA that stays live —
/// submission is never blocked (DECISIONS §2.5). **NOT SPECIFIED**; see ERRATA.
#Preview("16 · sure about that") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(entry: "58"),
                previous: MeasurePreviewFixtures.previousDBH()
            )
        )
    }
}

/// **A fix D6 will not chart.** 40 m is well outside the 15 m limit, so the reading is recorded and
/// says that it stays off the growth chart. **NOT SPECIFIED**; see ERRATA and E65.
#Preview("16 · fix too poor to chart") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(entry: "64"),
                previous: MeasurePreviewFixtures.previousDBH(),
                gpsAccuracyM: 40
            )
        )
    }
}

/// **No fix at all.** Unknown accuracy is unusable rather than assumed good (D6, `CoreEntity`), and
/// the height segment drops §7's `Taken at 1.4 m` because a height carries no measurement height.
#Preview("16 · height, no fix") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(kind: .height, method: .estimate, entry: "18"),
                gpsAccuracyM: nil
            )
        )
    }
}

/// Dark. SCREENS.md gives 16 no dark row, so this is evidence of what the token layer resolves the
/// screen to rather than a design. See ERRATA.
#Preview("16 · dark") {
    NavigationStack {
        MeasureScreen(
            presentation: MeasurePreviewFixtures.presentation(
                draft: MeasurePreviewFixtures.draft(entry: "64"),
                previous: MeasurePreviewFixtures.previousDBH()
            )
        )
    }
    .preferredColorScheme(.dark)
}
#endif
