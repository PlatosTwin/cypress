/**
 * `Quantity` — a number that cannot exist without its method — and the units it can be entered in.
 *
 * Ported from `Cypress/Core/Units/Quantity.swift` (`MeasurementMethod`, `MeasurementSeries`,
 * `LengthUnit`, `Quantity`, `Quantity.PlausibleRange`) and `Cypress/Core/Models/TreeMeasurement.swift`
 * (`MeasurementKind.plausibleSIRange`, which is where the two plausibility windows are selected by
 * kind).
 *
 * D7 / DECISIONS §3.5: every numeric observation carries method and unit metadata, and a
 * submission without them fails at the type level. The Swift enforces that by having no
 * initializer that omits `method`; `makeQuantity` below is likewise the only constructor exported,
 * `siValue` is derived inside it, and `Quantity` is declared `readonly` throughout, so the two
 * representations cannot be edited into disagreement.
 *
 * ── Where TypeScript and Swift may legitimately differ ───────────────────────────────────────
 *
 * 1. **Nothing in the arithmetic.** Swift `Double` and JS `number` are both IEEE-754 binary64, and
 *    every operation here is one multiply or one divide. `web/test/support/swift-reference.json`
 *    records what the real `Quantity.swift` produces for eleven cases across all five units, and
 *    the test beside this file asserts bit-for-bit equality — including the `converted(to:)`
 *    round trip, which is inexact in BOTH languages in exactly the same way: 12.5 in stores as
 *    0.3175 m and reads back as 12.5 in, but 64 cm reads back as 25.19685039370079 in and
 *    2.099737532808399 ft. That is the arithmetic, not a port artifact.
 *
 * 2. **The type system, which is the real difference and it is not in the numbers.** Swift's
 *    `LengthUnit` is a closed enum: a value outside the five cannot be constructed and a `switch`
 *    over them is exhaustive at compile time. TypeScript's union is erased at runtime, so a
 *    `LengthUnit` arriving from JSON can be any string. `metersPerUnitOf` therefore THROWS on an
 *    unregistered unit rather than returning a default, which is the nearest honest equivalent of
 *    "unrepresentable": a silent 1.0 would turn an unknown unit into meters.
 *
 * 3. **`ClosedRange` vs a pair.** Swift traps at runtime when `lowerBound > upperBound`;
 *    `isPlausible` here checks the same and throws, rather than quietly answering `false` for
 *    every input, which is how a plausibility guard passes while measuring nothing.
 */

// ── How a number was obtained (D7, DECISIONS §3.5) ──────────────────────────────────────────
//
// A `const` tuple plus a derived union, not a TypeScript `enum`: `web/tsconfig.json` sets
// `erasableSyntaxOnly`, because Node runs `.ts` by erasing types to whitespace and an `enum` needs
// emit. The raw values are the BUILD-PLAN §4 `method text` vocabulary verbatim, as in the Swift.

export const measurementMethods = ['tape', 'caliper', 'estimate', 'laser'] as const;
export type MeasurementMethod = (typeof measurementMethods)[number];

/**
 * The two chart series a quantity can belong to. There is no third and no "combined" case: having
 * only these two is what makes "one connecting line across estimated + taped values" (D7)
 * unrepresentable at the chart layer.
 */
export const measurementSeriesNames = ['measured', 'estimated'] as const;
export type MeasurementSeries = (typeof measurementSeriesNames)[number];

/** Chart series membership. Estimated and measured values never share a line (D7, BUILD-PLAN §15). */
export function seriesOf(method: MeasurementMethod): MeasurementSeries {
  return method === 'estimate' ? 'estimated' : 'measured';
}

// ── The unit a value can be entered in ──────────────────────────────────────────────────────

export const lengthUnits = ['mm', 'cm', 'm', 'in', 'ft'] as const;
export type LengthUnit = (typeof lengthUnits)[number];

/** Meters per one unit. Canonical storage is SI regardless (DECISIONS §3.6). */
export const metersPerUnit: Readonly<Record<LengthUnit, number>> = {
  mm: 0.001,
  cm: 0.01,
  m: 1,
  in: 0.0254,
  ft: 0.3048,
};

const metricUnits: ReadonlySet<string> = new Set<LengthUnit>(['mm', 'cm', 'm']);

/** True for the three SI units, false for inches and feet. */
export function isMetric(unit: LengthUnit): boolean {
  metersPerUnitOf(unit);
  return metricUnits.has(unit);
}

/**
 * The conversion factor, or a throw.
 *
 * See note 2 in the file header: the union is erased at runtime, so this is where an unregistered
 * unit has to be refused. Defaulting to 1 would silently reinterpret it as meters.
 */
export function metersPerUnitOf(unit: LengthUnit): number {
  const factor: number | undefined = metersPerUnit[unit];
  if (factor === undefined) {
    throw new Error(
      `unknown length unit ${JSON.stringify(unit)} — the registered units are `
        + `${lengthUnits.join(', ')}. A value in an unregistered unit has no SI reading, and `
        + `treating it as meters would invent one.`,
    );
  }
  return factor;
}

// ── The quantity itself ─────────────────────────────────────────────────────────────────────

export interface Quantity {
  /** The number as the human typed it, in `unitEntered`. Never silently converted for display. */
  readonly value: number;
  /** The unit that was on the keypad when the value was entered (BUILD-PLAN §4 `unit_entered`). */
  readonly unitEntered: LengthUnit;
  /** Canonical SI value, always meters (BUILD-PLAN §4 `si_value`, DECISIONS §3.6). */
  readonly siValue: number;
  /** How the number was obtained. Required (D7). */
  readonly method: MeasurementMethod;
}

/**
 * The only constructor. `siValue` is derived, never passed in, so the two representations cannot
 * disagree — the same reason the Swift has exactly one initializer.
 */
export function makeQuantity(
  value: number,
  unit: LengthUnit,
  method: MeasurementMethod,
): Quantity {
  return {
    value,
    unitEntered: unit,
    siValue: value * metersPerUnitOf(unit),
    method,
  };
}

/** The value expressed in another unit, for display only. The stored entry is untouched. */
export function converted(quantity: Quantity, unit: LengthUnit): number {
  return quantity.siValue / metersPerUnitOf(unit);
}

/** Which chart series this point belongs to (D7). */
export function seriesOfQuantity(quantity: Quantity): MeasurementSeries {
  return seriesOf(quantity.method);
}

/**
 * Decoding re-derives `siValue` from `value` and `unitEntered`, for the same reason the
 * constructor does: a persisted row that disagrees with itself resolves to the entered value.
 *
 * This is `Quantity.init(from:)` in the Swift, and it is the function the web's read layer will
 * meet a stored row through, so the resolution rule has to travel with it.
 */
export function quantityFromJSON(raw: unknown): Quantity {
  if (typeof raw !== 'object' || raw === null) {
    throw new Error(`a Quantity decodes from an object; got ${typeof raw}`);
  }
  const row = raw as Record<string, unknown>;
  const value = row['value'];
  const unit = row['unitEntered'];
  const method = row['method'];
  if (typeof value !== 'number') throw new Error(`Quantity.value is not a number: ${String(value)}`);
  if (typeof unit !== 'string' || !(lengthUnits as readonly string[]).includes(unit)) {
    throw new Error(`Quantity.unitEntered is not a registered unit: ${String(unit)}`);
  }
  if (typeof method !== 'string' || !(measurementMethods as readonly string[]).includes(method)) {
    throw new Error(`Quantity.method is not a registered method: ${String(method)}`);
  }
  return makeQuantity(value, unit as LengthUnit, method as MeasurementMethod);
}

// ── Plausibility (DECISIONS §3.6) ───────────────────────────────────────────────────────────

/** A closed interval in meters, both ends inclusive — Swift's `ClosedRange<Double>`. */
export interface ClosedRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

/**
 * Plausibility bounds for range validation on entry (DECISIONS §3.6). Out-of-range values are
 * warned about at the point of entry; they never block submission (PRODUCT §1 principle 2).
 */
export const plausibleRange: Readonly<Record<'dbhM' | 'heightM', ClosedRange>> = {
  /** DBH beyond ~4 m is a keypad slip, not a street tree. */
  dbhM: { lowerBound: 0.001, upperBound: 4.0 },
  /** Tallest known trees sit under 120 m; street trees under 40 m. */
  heightM: { lowerBound: 0.05, upperBound: 120.0 },
};

export const measurementKinds = ['dbh', 'height'] as const;
export type MeasurementKind = (typeof measurementKinds)[number];

/** Plausibility window for range validation on entry. Warns; never blocks. */
export function plausibleSIRange(kind: MeasurementKind): ClosedRange {
  switch (kind) {
    case 'dbh':
      return plausibleRange.dbhM;
    case 'height':
      return plausibleRange.heightM;
    default: {
      const unreachable: never = kind;
      throw new Error(`unknown measurement kind ${JSON.stringify(unreachable)}`);
    }
  }
}

/**
 * Whether the SI reading falls inside the window. False means "warn the user", never "reject".
 *
 * An inverted range throws rather than answering `false` for everything — see note 3 in the file
 * header. Swift traps; a guard that silently says "implausible" about every reading is the worse
 * of the two failures, because it looks like the rule working.
 */
export function isPlausible(quantity: Quantity, range: ClosedRange): boolean {
  if (range.lowerBound > range.upperBound) {
    throw new Error(
      `plausibility range ${range.lowerBound}…${range.upperBound} is inverted; Swift's `
        + `ClosedRange traps on this, and answering "implausible" for every reading would look `
        + `like the rule working`,
    );
  }
  return quantity.siValue >= range.lowerBound && quantity.siValue <= range.upperBound;
}
