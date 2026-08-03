//
//  OutboxPreviews.swift
//  Cypress — Features/Outbox
//
//  Previews for screen 17, including the two states that matter most and that SCREENS.md draws
//  neither of: an empty queue, which is what a contributor sees almost every time they open this
//  screen, and an item that has run out the 48 h cap.
//
//  `OutboxScreen` is fed a finished `OutboxPresentation` rather than a queue, so a preview is the
//  state it says it is. The records below are built in memory: `OutboxSnapshot` takes
//  `OutboxStore.Record`s, so no database, no drain and no clock is needed to photograph any state.
//

#if DEBUG
import SwiftUI

// MARK: - Fixtures

enum OutboxPreviewFixtures {

    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!
    static let cypressID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000017")!
    static let gumID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000018")!
    static let teaTreeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000019")!
    static let ginkgoID = UUID(uuidString: "9F3A0000-0000-4000-8000-00000000001A")!
    static let boxID = UUID(uuidString: "9F3A0000-0000-4000-8000-00000000001B")!

    static let treeNames: [UUID: String] = [
        cypressID: "Grandmother Cypress",
        gumID: "Judah Street Gum",
        teaTreeID: "The Tea Tree at 46th",
        ginkgoID: "Ginkgo on Noriega",
        boxID: "Brisbane Box"
    ]

    /// The morning the mock is drawn in.
    static let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 6, day: 18, hour: 11, minute: 55
    ))!

    static func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 6, day: 18, hour: hour, minute: minute
        ))!
    }

    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    static func record(
        _ payload: OutboxPayload,
        photos: [OutboxPhoto] = [],
        state: OutboxItem.State = .pending,
        failCount: Int = 0,
        reason: String? = nil,
        code: APIError? = nil,
        jsonSynced: Bool = false,
        createdAt: Date,
        updatedAt: Date? = nil,
        sequence: Int64
    ) -> OutboxStore.Record {
        let item = OutboxItem(
            kind: payload.kind,
            clientUUID: payload.clientUUID,
            payload: (try? payload.encoded()) ?? Data(),
            photos: photos,
            state: state,
            failCount: failCount,
            lastError: reason,
            lastErrorCode: code,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )
        return OutboxStore.Record(
            sequence: sequence,
            item: item,
            jsonSynced: jsonSynced,
            windowStartedAt: createdAt,
            nextAttemptAt: state == .pending ? createdAt.addingTimeInterval(30) : nil
        )
    }

    // MARK: The three drawn rows

    static var visit: OutboxStore.Record {
        record(
            .visit(Visit(
                treeID: cypressID,
                attribution: attribution,
                note: "Fog dripping off the crown",
                gpsAccuracyM: 6,
                capturedAt: at(11, 42)
            )),
            photos: [
                OutboxPhoto(path: "/tmp/cypress-preview-1.jpg", shotType: .fullTree),
                OutboxPhoto(path: "/tmp/cypress-preview-2.jpg", shotType: .leaf)
            ],
            createdAt: at(11, 42),
            sequence: 1
        )
    }

    static var checkIn: OutboxStore.Record {
        record(
            .observation(TreeObservation(
                treeID: gumID,
                attribution: attribution,
                capturedAt: at(11, 18),
                gpsAccuracyM: 9,
                status: .alive,
                vitality: .fair,
                foliage: FoliageAssessment(density: .thinning)
            )),
            createdAt: at(11, 18),
            sequence: 2
        )
    }

    /// §2's third row: a measurement that has run out the 48 h window and is asking for a tap.
    static var expiredMeasurement: OutboxStore.Record {
        record(
            .measurement(TreeMeasurement.dbh(
                treeID: teaTreeID,
                attribution: attribution,
                capturedAt: at(11, 3),
                gpsAccuracyM: 7,
                quantity: Quantity(value: 31, unit: .centimeters, method: .tape)
            )),
            state: .failed,
            failCount: 12,
            reason: OutboxFailureReason.expired,
            createdAt: at(11, 3),
            updatedAt: at(11, 40),
            sequence: 3
        )
    }

    /// The other terminal state: the API said no in a way that will not change.
    static var rejectedCare: OutboxStore.Record {
        record(
            .careEvent(CareEvent(
                treeID: boxID,
                attribution: attribution,
                capturedAt: at(10, 12),
                gpsAccuracyM: 8,
                actions: [.watered, .mulched]
            )),
            state: .failed,
            failCount: 1,
            reason: OutboxFailureReason.describe(
                error: APIError.validationFailed,
                failCount: 1,
                state: .failed
            ),
            code: .validationFailed,
            createdAt: at(10, 12),
            updatedAt: at(10, 13),
            sequence: 4
        )
    }

    /// The note went, the binaries did not. This is the only shape `awaitingWifiCount` admits.
    static var awaitingWifi: OutboxStore.Record {
        record(
            .visit(Visit(
                treeID: ginkgoID,
                attribution: attribution,
                gpsAccuracyM: 5,
                capturedAt: at(9, 30)
            )),
            photos: [
                OutboxPhoto(path: "/tmp/cypress-preview-3.jpg", shotType: .fullTree),
                OutboxPhoto(path: "/tmp/cypress-preview-4.jpg", shotType: .trunk),
                OutboxPhoto(path: "/tmp/cypress-preview-5.jpg", shotType: .leaf)
            ],
            reason: OutboxFailureReason.awaitingWifi(photoCount: 3),
            jsonSynced: true,
            createdAt: at(9, 30),
            sequence: 5
        )
    }

    // MARK: §4's receipts

    static var syncedVisit: OutboxStore.Record {
        record(
            .visit(Visit(treeID: ginkgoID, attribution: attribution, gpsAccuracyM: 5, capturedAt: at(9, 50))),
            state: .done,
            jsonSynced: true,
            createdAt: at(9, 50),
            updatedAt: at(9, 56),
            sequence: 6
        )
    }

    static var syncedCare: OutboxStore.Record {
        record(
            .careEvent(CareEvent(
                treeID: boxID,
                attribution: attribution,
                capturedAt: at(9, 38),
                gpsAccuracyM: 7,
                actions: [.watered]
            )),
            state: .done,
            jsonSynced: true,
            createdAt: at(9, 38),
            updatedAt: at(9, 41),
            sequence: 7
        )
    }

    // MARK: Snapshots

    static func snapshot(
        _ records: [OutboxStore.Record],
        syncPhotosOnWifiOnly: Bool = true
    ) -> OutboxSnapshot {
        OutboxSnapshot(
            records: records,
            treeNames: treeNames,
            now: now,
            syncPhotosOnWifiOnly: syncPhotosOnWifiOnly
        )
    }

    static func presentation(
        _ records: [OutboxStore.Record],
        syncPhotosOnWifiOnly: Bool = true
    ) -> OutboxPresentation {
        OutboxPresentation(
            snapshot: snapshot(records, syncPhotosOnWifiOnly: syncPhotosOnWifiOnly),
            now: now
        )
    }
}

// MARK: - Previews

/// **The state SCREENS.md 17 draws**: three queued items, the third of them terminal and amber, the
/// wi-fi row, two receipts and the summary line.
#Preview("17 · outbox") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([
                OutboxPreviewFixtures.visit,
                OutboxPreviewFixtures.checkIn,
                OutboxPreviewFixtures.expiredMeasurement,
                OutboxPreviewFixtures.syncedVisit,
                OutboxPreviewFixtures.syncedCare
            ]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
}

/// **Empty.** What a contributor sees almost every time they open this screen, and what SCREENS.md
/// §5 gap 5 names as a decision the build has to take. See ERRATA.
#Preview("17 · empty") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
}

/// **The 48 h cap, alone.** The amber card, the sentence that says why, and a `retry` that is a
/// control rather than a label (BUILD-PLAN §4).
#Preview("17 · expired") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([
                OutboxPreviewFixtures.expiredMeasurement
            ]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
}

/// **Terminal, and not worth a tap.** `validation_failed` is not retryable, so the row reads
/// `stopped` and carries no control. **NOT SPECIFIED**; see ERRATA.
#Preview("17 · stopped") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([
                OutboxPreviewFixtures.rejectedCare
            ]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
}

/// **Waiting for wi-fi.** Three binaries on one item, so the sentence says three and not one
/// (`awaitingWifiPhotoCount`).
#Preview("17 · waiting for wi-fi") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([
                OutboxPreviewFixtures.awaitingWifi
            ]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
}

/// The same rows with the toggle off: nothing is behind it any more, so the sentence is gone.
#Preview("17 · wi-fi toggle off") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation(
                [OutboxPreviewFixtures.awaitingWifi],
                syncPhotosOnWifiOnly: false
            ),
            syncPhotosOnWifiOnly: .constant(false)
        )
    }
}

/// Dark. SCREENS.md gives 17 no dark row, so this is evidence of what the token layer resolves the
/// screen to rather than a design. See ERRATA.
#Preview("17 · dark") {
    NavigationStack {
        OutboxScreen(
            presentation: OutboxPreviewFixtures.presentation([
                OutboxPreviewFixtures.visit,
                OutboxPreviewFixtures.expiredMeasurement,
                OutboxPreviewFixtures.syncedVisit
            ]),
            syncPhotosOnWifiOnly: .constant(true)
        )
    }
    .preferredColorScheme(.dark)
}
#endif
