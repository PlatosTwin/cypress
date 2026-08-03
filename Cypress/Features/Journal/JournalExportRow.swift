//
//  JournalExportRow.swift
//  Cypress — Features/Journal
//
//  The export, given a way to press it (ERRATA E39's method, ERRATA E131's finding).
//
//  ── The defect this closes ────────────────────────────────────────────────────────────────────
//  `CypressAPI.exportLatest(_:)` is a protocol requirement, implemented in `LocalAPI` over this
//  device's own contributions, carrying `verification_state` and the structure-flag disclaimer per
//  D12. It follows its own cursor to the end of the journal, which is a fix E39 made specifically so
//  that a subject-access export could not come back silently short. Its only caller anywhere in the
//  repository was `CypressTests/JournalExportTests`.
//
//  Its own documentation ties it to "what a coordinator's 'export my morning' and the account-data
//  request both need". That makes it **a privacy commitment with no surface**. An app that says your
//  data is yours and offers no way to take it out has not made a weaker promise than one that never
//  said it — it has made one it does not keep, and this is the more serious kind of the defect the
//  rest of this round is about. `PrivateReminderList` closed the same shape for D4's reminders; this
//  closes it for the record as a whole.
//
//  ── Why the You tab and not this feature's own screen ─────────────────────────────────────────
//  The row sits in the You tab's `Your contributions` section, beside the outbox row. Both are doors
//  out of the same body of work — the outbox is what has not left yet, this is a copy of what is
//  here — and BUILD-PLAN §9's M2 list puts the person's own doors on that tab. It lives in this
//  folder because what it exports is the journal, and its copy is the journal's.
//
//  ── Two `Transferable`s rather than one with a parameter ──────────────────────────────────────
//  `ShareLink` resolves its payload from the *type*, so a single type carrying a format field would
//  need one content type for both formats and would hand the share sheet a `.csv` labeled as map
//  data or the reverse. The failure mode of that arrangement is one control quietly exporting the
//  other one's bytes, which looks identical to working until somebody opens the file. Two types make
//  the format part of what the compiler checks, and the suite asserts each carries its own.
//
//  The bytes are loaded **when the sheet asks for them**, not when the row draws: an export walks the
//  whole journal, and doing that on every appearance of the You tab would be a full table scan to
//  render a row nobody pressed.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - The payloads

/// The CSV export, resolved on demand.
struct JournalCSVExport: Transferable {
    let load: @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            try await export.load()
        }
        .suggestedFileName(JournalCopy.exportFileName(.csv))
    }
}

/// The GeoJSON export, resolved on demand.
///
/// `.json` is the content type, because GeoJSON *is* JSON and no system type is narrower; the
/// `.geojson` extension travels on the suggested file name, which is what mapping software looks at.
struct JournalGeoJSONExport: Transferable {
    let load: @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try await export.load()
        }
        .suggestedFileName(JournalCopy.exportFileName(.geojson))
    }
}

// MARK: - The rows

/// One labeled block of two C10 rows, each a `ShareLink`.
///
/// C10 is the row this tab already uses for the outbox, and screen 10 is where `ShareLink` is
/// already the app's way of handing something to the system — so neither half of this is a new
/// pattern. The `record` accent is the one screen 13 gives to a measurement, which is the nearest
/// thing in the palette to "a written-down fact about a tree".
/// The one operation this section needs from the boundary: bytes, per format.
///
/// **A struct rather than a bare closure, and the reason is the compiler rather than taste.** Held as
/// `(@Sendable (ExportFormat) async throws -> Data)?`, the `@Sendable` does not survive the trip
/// through the `Optional` under `SWIFT_APPROACHABLE_CONCURRENCY`: unwrapping it yields a value the
/// compiler no longer believes is sendable, and handing that to a parameter which requires one is
/// `warning: converting non-sendable function value … may introduce data races` — the only warning in
/// the whole build, and an error under Swift 6's language mode. A typealias does not fix it, because
/// the attribute is lost at the unwrap and not at the declaration. Wrapping the closure in an
/// explicitly `Sendable` struct does, because what travels through the `Optional` is then a nominal
/// type that states its own sendability, and the function comes back out by stored property rather
/// than by rebinding.
struct JournalExportBytes: Sendable {

    private let bytes: @Sendable (ExportFormat) async throws -> Data

    init(_ bytes: @escaping @Sendable (ExportFormat) async throws -> Data) {
        self.bytes = bytes
    }

    /// So call sites read `export(.csv)`, exactly as they did when this was a bare closure.
    func callAsFunction(_ format: ExportFormat) async throws -> Data {
        try await bytes(format)
    }
}

struct JournalExportRows: View {

    /// The bytes, per format. A closure rather than the API itself so the section can be drawn — and
    /// photographed — without one.
    let export: JournalExportBytes

    /// The two payloads the body hands its two `ShareLink`s.
    ///
    /// **Hoisted out of the body deliberately, and this is not tidying.** Built inline, the one thing
    /// that can go wrong here — a row asking `export` for the *other* row's format — lived only
    /// inside a `some View` and could not be reached by a test. A suite that builds its own
    /// `JournalCSVExport { try await api.exportLatest(.csv) }` proves that `.csv` returns CSV, which
    /// nobody doubted; it says nothing about which format the button asks for. Swapping the two
    /// arguments here left every export assertion green, so this is the seam that makes the mistake
    /// the file comment warns about a catchable one.
    /// The closure form, so a caller with a bare closure — every test here, and every preview — reads
    /// as it did before `JournalExportBytes` existed. The wrapper is there to survive an `Optional`,
    /// which is a problem only the You tab has.
    ///
    /// Both overloads are `nonisolated`. They took `@MainActor` from `View` conformance and use none
    /// of it: each builds two `Sendable`-closure value types from a `Sendable` input and touches no
    /// view state. The isolation was what stopped the seam this comment describes from being reached
    /// from a suite that is not itself on the main actor.
    nonisolated static func payloads(
        _ export: @escaping @Sendable (ExportFormat) async throws -> Data
    ) -> (csv: JournalCSVExport, geoJSON: JournalGeoJSONExport) {
        payloads(JournalExportBytes(export))
    }

    nonisolated static func payloads(
        _ export: JournalExportBytes
    ) -> (csv: JournalCSVExport, geoJSON: JournalGeoJSONExport) {
        (
            JournalCSVExport { try await export(.csv) },
            JournalGeoJSONExport { try await export(.geojson) }
        )
    }

    var body: some View {
        let payloads = Self.payloads(export)

        return VStack(alignment: .leading, spacing: 0) {
            Text(JournalCopy.exportLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            VStack(spacing: CypressSpacing.gapRows) {
                ShareLink(
                    item: payloads.csv,
                    preview: SharePreview(JournalCopy.exportFileName(.csv))
                ) {
                    IconTextRow(
                        accent: .record,
                        title: JournalCopy.exportAction(.csv),
                        subtitle: JournalCopy.exportTitle(.csv)
                    )
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: payloads.geoJSON,
                    preview: SharePreview(JournalCopy.exportFileName(.geojson))
                ) {
                    IconTextRow(
                        accent: .record,
                        title: JournalCopy.exportAction(.geojson),
                        subtitle: JournalCopy.exportTitle(.geojson)
                    )
                }
                .buttonStyle(.plain)
            }

            // What is in the file, said once under both rows rather than twice inside them. It names
            // the disclaimer the file itself carries (D12), so the two cannot drift.
            Text(JournalCopy.exportBody)
                .font(CypressFont.body12)
                .foregroundStyle(CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CypressSpacing.gapVitality)
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }
}
