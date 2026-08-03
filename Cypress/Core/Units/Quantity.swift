import Foundation

/// How a number was obtained. Mandatory on every quantitative value (D7, DECISIONS §3.5).
///
/// Raw values are the BUILD-PLAN §4 `method text` vocabulary verbatim. On charts, `estimate`
/// points and instrument-measured points render as separate series and are never connected (D7).
public enum MeasurementMethod: String, Codable, Sendable, Hashable, CaseIterable {
    case tape = "tape"
    case caliper = "caliper"
    case estimate = "estimate"
    case laser = "laser"

    /// Chart series membership. Estimated and measured values never share a line (D7, BUILD-PLAN §15).
    public var series: MeasurementSeries {
        switch self {
        case .estimate: return .estimated
        case .tape, .caliper, .laser: return .measured
        }
    }
}

/// The two chart series a quantity can belong to. There is no third, and no "combined" case:
/// having only these two makes "one connecting line across estimated + taped values" (D7)
/// unrepresentable at the chart layer.
public enum MeasurementSeries: String, Codable, Sendable, Hashable, CaseIterable {
    case measured = "measured"
    case estimated = "estimated"
}

/// A length unit a value can be *entered* in. Canonical storage is SI (meters) regardless
/// (DECISIONS §3.6: "Canonical SI internally, entered unit captured").
public enum LengthUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case millimeters = "mm"
    case centimeters = "cm"
    case meters = "m"
    case inches = "in"
    case feet = "ft"

    /// Meters per one unit.
    public var metersPerUnit: Double {
        switch self {
        case .millimeters: return 0.001
        case .centimeters: return 0.01
        case .meters: return 1
        case .inches: return 0.0254
        case .feet: return 0.3048
        }
    }

    public var isMetric: Bool {
        switch self {
        case .millimeters, .centimeters, .meters: return true
        case .inches, .feet: return false
        }
    }
}

/// A number that cannot exist without its method.
///
/// D7 / DECISIONS §3.5: "Every numeric observation carries method and unit metadata; submissions
/// without them fail at the type level." There is deliberately **no** initializer that omits
/// `method`, no default value for it, and no mutating setter that could null it out — the only way
/// to obtain a `Quantity` is to state how the number was obtained.
///
/// Both the entered unit and the canonical SI value are stored, mirroring the BUILD-PLAN §4
/// `measurements` columns `value`, `unit_entered`, `si_value`.
public struct Quantity: Hashable, Codable, Sendable {
    /// The number as the human typed it, in `unitEntered`. Never silently converted for display.
    public let value: Double
    /// The unit that was on the keypad when the value was entered (BUILD-PLAN §4 `unit_entered`).
    public let unitEntered: LengthUnit
    /// Canonical SI value, always meters (BUILD-PLAN §4 `si_value`, DECISIONS §3.6).
    public let siValue: Double
    /// How the number was obtained. Required (D7).
    public let method: MeasurementMethod

    /// The only initializer. `siValue` is derived, never passed in, so the two representations
    /// cannot disagree.
    public init(value: Double, unit: LengthUnit, method: MeasurementMethod) {
        self.value = value
        self.unitEntered = unit
        self.siValue = value * unit.metersPerUnit
        self.method = method
    }

    /// The value expressed in another unit, for display only. The stored entry is untouched.
    public func converted(to unit: LengthUnit) -> Double {
        siValue / unit.metersPerUnit
    }

    /// Which chart series this point belongs to (D7).
    public var series: MeasurementSeries { method.series }

    // Decoding re-derives `siValue` from `value` and `unitEntered` for the same reason the
    // initializer does: a persisted row that disagrees with itself resolves to the entered value.
    private enum CodingKeys: String, CodingKey {
        case value, unitEntered, method
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(Double.self, forKey: .value)
        let unit = try container.decode(LengthUnit.self, forKey: .unitEntered)
        let method = try container.decode(MeasurementMethod.self, forKey: .method)
        self.init(value: value, unit: unit, method: method)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(unitEntered, forKey: .unitEntered)
        try container.encode(method, forKey: .method)
    }
}

extension Quantity {
    /// Plausibility bounds for range validation on entry (DECISIONS §3.6). Out-of-range values are
    /// warned about at the point of entry; they never block submission (PRODUCT §1 principle 2).
    public enum PlausibleRange {
        /// DBH beyond ~4 m is a keypad slip, not a street tree.
        public static let dbhM: ClosedRange<Double> = 0.001...4.0
        /// Tallest known trees sit under 120 m; street trees under 40 m.
        public static let heightM: ClosedRange<Double> = 0.05...120.0
    }

    public func isPlausible(within range: ClosedRange<Double>) -> Bool {
        range.contains(siValue)
    }
}
