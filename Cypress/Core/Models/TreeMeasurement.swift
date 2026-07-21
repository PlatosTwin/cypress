import Foundation

/// `measurements.kind` (BUILD-PLAN §4). The capture UI is screen 16, the measure sheet (D7).
public enum MeasurementKind: String, Codable, Sendable, Hashable, CaseIterable {
    case dbh = "dbh"
    case height = "height"

    /// Plausibility window for range validation on entry (DECISIONS §3.6). Warns; never blocks.
    public var plausibleSIRange: ClosedRange<Double> {
        switch self {
        case .dbh: return Quantity.PlausibleRange.dbhM
        case .height: return Quantity.PlausibleRange.heightM
        }
    }
}

/// A single measured or estimated number about a tree (BUILD-PLAN §4 `measurements`).
///
/// Named `TreeMeasurement` rather than `Measurement` to avoid shadowing `Foundation.Measurement`
/// module-wide; the database table is still `measurements`.
///
/// The quantity carries its method by construction (`Quantity`, D7), so a method-less measurement
/// cannot be built. The two factory methods are the only way in, which is what keeps
/// `measurementHeightM` attached to DBH and absent from height.
public struct TreeMeasurement: FieldCaptured {
    public let id: UUID
    public let treeID: UUID
    public let userID: UUID?
    public let deviceID: UUID
    public let clientUUID: UUID
    public let capturedAt: Date
    public let gpsAccuracyM: Double?
    public let kind: MeasurementKind
    /// Value, entered unit, canonical SI value, and method — all four, always (D7).
    public let quantity: Quantity
    /// `measurement_height_m numeric default 1.4 for dbh` (BUILD-PLAN §4). Nil for height.
    public let measurementHeightM: Double?
    public var verificationState: VerificationState
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    /// Default DBH measurement height in metres, ≈4.5 ft (BUILD-PLAN §4, C-M3).
    public static let defaultDBHMeasurementHeightM: Double = 1.4

    private init(
        id: UUID,
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID,
        capturedAt: Date,
        gpsAccuracyM: Double?,
        kind: MeasurementKind,
        quantity: Quantity,
        measurementHeightM: Double?,
        verificationState: VerificationState,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.treeID = treeID
        self.userID = attribution.userID
        self.deviceID = attribution.deviceID
        self.clientUUID = clientUUID
        self.capturedAt = capturedAt
        self.gpsAccuracyM = gpsAccuracyM
        self.kind = kind
        self.quantity = quantity
        self.measurementHeightM = measurementHeightM
        self.verificationState = verificationState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Diameter at breast height. `measurementHeightM` defaults to 1.4 (BUILD-PLAN §4).
    public static func dbh(
        id: UUID = UUID(),
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID = UUID(),
        capturedAt: Date,
        gpsAccuracyM: Double? = nil,
        quantity: Quantity,
        measurementHeightM: Double = TreeMeasurement.defaultDBHMeasurementHeightM,
        verificationState: VerificationState = .unverified,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) -> TreeMeasurement {
        TreeMeasurement(
            id: id,
            treeID: treeID,
            attribution: attribution,
            clientUUID: clientUUID,
            capturedAt: capturedAt,
            gpsAccuracyM: gpsAccuracyM,
            kind: .dbh,
            quantity: quantity,
            measurementHeightM: measurementHeightM,
            verificationState: verificationState,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    /// Tree height. Carries no measurement height, by construction.
    public static func height(
        id: UUID = UUID(),
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID = UUID(),
        capturedAt: Date,
        gpsAccuracyM: Double? = nil,
        quantity: Quantity,
        verificationState: VerificationState = .unverified,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) -> TreeMeasurement {
        TreeMeasurement(
            id: id,
            treeID: treeID,
            attribution: attribution,
            clientUUID: clientUUID,
            capturedAt: capturedAt,
            gpsAccuracyM: gpsAccuracyM,
            kind: .height,
            quantity: quantity,
            measurementHeightM: nil,
            verificationState: verificationState,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    public var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }

    /// Which of the two chart series this point belongs to. Estimated and measured points are
    /// separate series and are never connected (D7, BUILD-PLAN §15).
    public var series: MeasurementSeries { quantity.series }

    /// Range validation on entry (DECISIONS §3.6). False means "warn the user", never "reject":
    /// submission is never blocked for lack of rigor (PRODUCT §1 principle 2).
    public var isPlausible: Bool { quantity.isPlausible(within: kind.plausibleSIRange) }

    /// Chartable only when the GPS fix was good enough to trust the attribution (D6) and the point
    /// is not soft-deleted. Excluded above 15 m (D6, BUILD-PLAN §4).
    public var isChartable: Bool { isEligibleForGrowthCharting && deletedAt == nil }
}

extension Collection where Element == TreeMeasurement {
    /// Splits a measurement series the only way it may ever be drawn: two series, never joined (D7).
    public func splitBySeries(kind: MeasurementKind) -> (measured: [TreeMeasurement], estimated: [TreeMeasurement]) {
        let points = filter { $0.kind == kind && $0.isChartable }
            .sorted { $0.capturedAt < $1.capturedAt }
        return (
            measured: points.filter { $0.series == .measured },
            estimated: points.filter { $0.series == .estimated }
        )
    }
}
