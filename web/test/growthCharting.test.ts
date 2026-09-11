/**
 * D6's growth-charting gate, against the real `CoreEntity.swift` and `TreeMeasurement.swift`.
 *
 * The ported cases are the whole of `LocationAccuracyTests.gateBoundaries`
 * (`CypressTests/LocationAccuracyTests.swift:51-69`), `MeasurePresentationTests.gateBoundary`
 * (:390-397), and `GrowthHistoryPresentationTests.swift:117` (`growthChartingLimitM == 15`). The
 * D7 split is `TreeMeasurement.splitBySeries` (`Cypress/Core/Models/TreeMeasurement.swift:156`).
 *
 * The limit is parsed out of the Swift rather than transcribed. It is one number in one place and
 * it decides whether a person's measurement appears on the chart they took it for — E65 is about
 * what happens when the answer silently becomes "no" for everything.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  growthChartingLimitM,
  isChartable,
  isDeleted,
  isEligibleForGrowthCharting,
  splitBySeries,
} from '../src/lib/growthCharting.ts';
import { repoFile, swiftDoubleLet } from './support/sources.ts';

const reference = JSON.parse(
  readFileSync(new URL('./support/swift-reference.json', import.meta.url), 'utf8'),
) as { growthChartingLimitM: number };

describe('the D6 limit', () => {
  it('is the number CoreEntity.swift declares', () => {
    const inSwift = swiftDoubleLet(
      repoFile('Cypress/Core/Models/CoreEntity.swift'),
      'growthChartingLimitM',
    );
    assert.equal(
      growthChartingLimitM,
      inSwift,
      `web/src/lib/growthCharting.ts excludes points worse than ${growthChartingLimitM} m; `
        + `GPSAccuracy.growthChartingLimitM in Swift is ${inSwift} m. Two surfaces charting `
        + `different subsets of the same measurements is a disagreement a contributor sees and `
        + `cannot explain.`,
    );
    // The value #117 of GrowthHistoryPresentationTests pins, restated here because that suite does
    // not run on a web change.
    assert.equal(inSwift, 15, 'D6 and BUILD-PLAN §4 say 15 m');
    assert.equal(reference.growthChartingLimitM, inSwift, 'regenerate support/swift-reference.json');
  });
});

/**
 * `LocationAccuracyTests.gateBoundaries` and `MeasurePresentationTests.gateBoundary`, ported.
 *
 * Both Swift suites assert the same three facts about the same three inputs, from different sides
 * of the app. 15 is in; 15.1 is out; nothing at all is out.
 */
describe('the gate is inclusive at the limit and excludes a missing reading', () => {
  it('15 m is eligible and 15.1 m is not', () => {
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: 15 }), true);
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: 15.1 }), false);
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: 8 }), true);
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: 40 }), false);
  });

  /**
   * Swift has one absence and JavaScript has two — plus a key that was never there at all. D6 says
   * an unknown fix is unusable, and that is the safe direction: a chart that omits a point
   * understates what is known, where one that invents it asserts something nobody measured.
   */
  it('every shape of “no reading” is excluded, not assumed good', () => {
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: null }), false, 'null');
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: undefined }), false, 'undefined');
    assert.equal(isEligibleForGrowthCharting({}), false, 'the key absent entirely');
    assert.equal(isEligibleForGrowthCharting({ gpsAccuracyM: Number.NaN }), false, 'NaN');
  });

  /**
   * The specimen that makes the three above mean something. A gate written `accuracy > limit` and
   * negated, or one that read a missing key as 0, would pass some of them; a gate that returned
   * `false` unconditionally would pass all the exclusions and fail here.
   */
  it('the gate admits something, so the exclusions above are not a constant false', () => {
    const admitted = [0, 1, 5, 8, 14.9, 15].filter((accuracy) =>
      isEligibleForGrowthCharting({ gpsAccuracyM: accuracy }));
    assert.deepEqual(admitted, [0, 1, 5, 8, 14.9, 15]);
  });
});

/** `TreeMeasurement.isChartable` — the gate AND not soft-deleted (`TreeMeasurement.swift:152`). */
describe('isChartable is the gate and the tombstone', () => {
  it('a good fix that has been withdrawn does not chart', () => {
    const withdrawn = { gpsAccuracyM: 5, deletedAt: new Date('2026-08-01T00:00:00Z') };
    assert.equal(isEligibleForGrowthCharting(withdrawn), true, 'the premise: the fix is fine');
    assert.equal(isDeleted(withdrawn), true);
    assert.equal(isChartable(withdrawn), false);
  });

  it('a live point with a good fix charts', () => {
    assert.equal(isChartable({ gpsAccuracyM: 5, deletedAt: null }), true);
    assert.equal(isChartable({ gpsAccuracyM: 5 }), true);
  });

  it('a poor fix does not chart whether or not it is withdrawn', () => {
    assert.equal(isChartable({ gpsAccuracyM: 40 }), false);
    assert.equal(isChartable({ gpsAccuracyM: 40, deletedAt: new Date() }), false);
  });
});

/**
 * D7: estimated and measured points are separate series and are never connected. The Swift filters
 * to one `kind`, drops everything unchartable, sorts by capture time and splits.
 */
describe('splitBySeries', () => {
  const point = (
    id: string,
    kind: string,
    series: string,
    capturedAt: number,
    gpsAccuracyM: number | null,
    deletedAt: Date | null = null,
  ) => ({ id, kind, series, capturedAt, gpsAccuracyM, deletedAt });

  it('keeps the two series apart, in capture order, dropping what D6 excludes', () => {
    const points = [
      point('c', 'dbh', 'measured', 300, 5),
      point('a', 'dbh', 'estimated', 100, 5),
      point('b', 'dbh', 'measured', 200, 5),
      point('poor', 'dbh', 'measured', 250, 40),
      point('gone', 'dbh', 'estimated', 150, 5, new Date()),
      point('unknown', 'dbh', 'measured', 260, null),
      point('other-kind', 'height', 'measured', 120, 5),
    ];
    const split = splitBySeries(points, 'dbh');
    assert.deepEqual(split.measured.map((p) => p.id), ['b', 'c']);
    assert.deepEqual(split.estimated.map((p) => p.id), ['a']);
    // Named, not just counted: "the poor fix, the withdrawal, the unknown accuracy and the other
    // kind are all absent" is four different rules, and a count of 3 is satisfied by three of them
    // working and one dropping the wrong row.
    const kept = [...split.measured, ...split.estimated].map((p) => p.id).sort();
    assert.deepEqual(kept, ['a', 'b', 'c']);
  });

  it('the other kind comes back when it is the kind asked for', () => {
    // The `kind` filter admits as well as excludes; without this the filter could be `() => false`
    // for `height` and the test above would not notice.
    const points = [point('h', 'height', 'measured', 120, 5), point('d', 'dbh', 'measured', 100, 5)];
    assert.deepEqual(splitBySeries(points, 'height').measured.map((p) => p.id), ['h']);
    assert.deepEqual(splitBySeries(points, 'dbh').measured.map((p) => p.id), ['d']);
  });

  it('does not mutate the array it was handed', () => {
    // Swift's `filter` returns a new array and `sorted(by:)` does not sort in place. JS's `sort`
    // does, and a caller whose points came from a cache would find them reordered.
    const points = [point('b', 'dbh', 'measured', 200, 5), point('a', 'dbh', 'measured', 100, 5)];
    const before = points.map((p) => p.id);
    splitBySeries(points, 'dbh');
    assert.deepEqual(points.map((p) => p.id), before, 'splitBySeries reordered its input');
  });

  it('an empty input is two empty series, not a throw', () => {
    const split = splitBySeries([], 'dbh');
    assert.deepEqual(split.measured, []);
    assert.deepEqual(split.estimated, []);
  });
});
