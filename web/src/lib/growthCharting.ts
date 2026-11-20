/**
 * D6's growth-charting gate: a point is charted only if the fix that produced it can be trusted.
 *
 * Ported from two declarations, and the first one was not where I expected to find it:
 *
 *  * `Cypress/Core/Models/CoreEntity.swift:41-52` — `FieldCaptured.isEligibleForGrowthCharting`,
 *    a default implementation on a protocol, and `GPSAccuracy.growthChartingLimitM = 15`. It is
 *    inherited by `Visit`, `TreeMeasurement`, `Observation` and every other field-captured
 *    contribution, which is why the rule has no file of its own.
 *  * `Cypress/Core/Models/TreeMeasurement.swift:152` — `isChartable`, which is that AND not
 *    soft-deleted, and `splitBySeries` at :156, which is the only way a series may be drawn.
 *
 * "Points with gps_accuracy_m above 15 are excluded from per-tree charts" (D6, BUILD-PLAN §4).
 * The gate is INCLUSIVE at 15 and an unknown accuracy is unusable rather than assumed good: a
 * chart that omits a point understates what is known, where one that invents it asserts something
 * nobody measured.
 *
 * ── Where TypeScript and Swift may legitimately differ ───────────────────────────────────────
 *
 * 1. **`nil` is one absence in Swift and two in JavaScript.** `gpsAccuracyM: Double?` is either a
 *    number or nothing. Here a field can be `null` (a JSON null, which is what a column with no
 *    reading decodes to) or `undefined` (the key absent). Both mean "no reading" and both must
 *    fail the gate; the test asserts all three of `null`, `undefined` and a missing property.
 * 2. **`NaN` has no Swift counterpart reachable here** and is the one input where a naive
 *    `accuracy <= limit` and a naive `accuracy > limit` disagree about the same value. `NaN <= 15`
 *    is false, so the port refuses it — the same direction as an unknown reading, which is the
 *    safe one. Swift would also answer false for `Double.nan`, so this is agreement rather than
 *    divergence; it is named because it is the input a reader will wonder about.
 * 3. **Sort stability in `splitBySeries`.** `Array.prototype.sort` is required to be stable;
 *    Swift's `sorted(by:)` is not guaranteed to be, though it is in practice. Two points captured
 *    at the same instant may therefore come back in a different order from the two
 *    implementations. Nothing downstream depends on that order — both are drawn as one series —
 *    but it is a real difference and it is not worth hiding.
 */

/** "Points with gps_accuracy_m above 15 are excluded from per-tree charts" (D6, BUILD-PLAN §4). */
export const growthChartingLimitM = 15;

/**
 * A contribution captured in the field, carrying the GPS accuracy of the moment of capture (D6).
 *
 * The Swift protocol is `FieldCaptured` and also requires `capturedAt`, `clientUUID` and the
 * `CoreEntity` triple. Only the two fields the rule reads are required here; a structural type
 * asking for more than the predicate uses would refuse callers the Swift accepts.
 */
export interface FieldCaptured {
  // `| undefined` is written out, not left to the `?`. `web/tsconfig.json` inherits
  // `exactOptionalPropertyTypes` from astro's strictest preset, under which `x?: number | null`
  // means "absent, a number, or null" and REFUSES an explicit `undefined`. The predicate below
  // handles all three at run time, so the type has to say all three — otherwise the port would be
  // claiming a guarantee it does not have, and the test that exercises the third case would not
  // compile. That is the JS-vs-Swift difference this file's header names, spelled in the type.
  readonly gpsAccuracyM?: number | null | undefined;
}

/** Nothing in the domain ever hard-deletes; sync needs the tombstone (BUILD-PLAN §4). */
export interface SoftDeletable {
  readonly deletedAt?: Date | string | null | undefined;
}

/**
 * Points captured with GPS accuracy worse than 15 m are excluded from per-tree growth charts
 * (D6, BUILD-PLAN §4). Unknown accuracy is treated as unusable rather than assumed good.
 */
export function isEligibleForGrowthCharting(point: FieldCaptured): boolean {
  const accuracy = point.gpsAccuracyM;
  if (accuracy === null || accuracy === undefined) return false;
  return accuracy <= growthChartingLimitM;
}

/** True when `deletedAt` is absent or null. `SoftDeletable.isDeleted` inverted. */
export function isDeleted(record: SoftDeletable): boolean {
  return record.deletedAt !== null && record.deletedAt !== undefined;
}

/**
 * Chartable only when the GPS fix was good enough to trust the attribution (D6) and the point is
 * not soft-deleted. Excluded above 15 m (D6, BUILD-PLAN §4).
 */
export function isChartable(point: FieldCaptured & SoftDeletable): boolean {
  return isEligibleForGrowthCharting(point) && !isDeleted(point);
}

/** The shape `splitBySeries` reads. See `TreeMeasurement` in `Core/Models`. */
export interface ChartablePoint extends FieldCaptured, SoftDeletable {
  readonly kind: string;
  readonly series: string;
  readonly capturedAt: number;
}

/**
 * Splits a measurement series the only way it may ever be drawn: two series, never joined (D7).
 *
 * `capturedAt` is a number — epoch milliseconds or seconds, the caller's choice, as long as it is
 * one of them consistently. `Date` would have been the closer analogue of Swift's `Date` and is
 * the worse type here: `a < b` on two `Date`s works by coercion and `a - b` does not typecheck,
 * so the comparator would read as if it could be written either way when only one is right.
 */
export function splitBySeries<Point extends ChartablePoint>(
  points: readonly Point[],
  kind: string,
): { readonly measured: readonly Point[]; readonly estimated: readonly Point[] } {
  // `.filter` returns a new array, so the in-place `.sort` below cannot reach the caller's.
  // That ordering is load-bearing and not incidental: JS's `sort` mutates where Swift's
  // `sorted(by:)` does not, so a future edit that sorts BEFORE filtering would silently reorder a
  // caller's cached array. `splitBySeries does not mutate the array it was handed` is the test
  // that goes red for it, and it was red-proved by making exactly that swap.
  const eligible = points
    .filter((point) => point.kind === kind && isChartable(point))
    .sort((a, b) => a.capturedAt - b.capturedAt);
  return {
    measured: eligible.filter((point) => point.series === 'measured'),
    estimated: eligible.filter((point) => point.series === 'estimated'),
  };
}
