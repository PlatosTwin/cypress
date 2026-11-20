/**
 * `Quantity`, against the real `Quantity.swift`.
 *
 * The vocabulary (the five units, the four methods, the two series) and the four numeric constants
 * (`metersPerUnit`, both `PlausibleRange` bounds) are read out of
 * `Cypress/Core/Units/Quantity.swift` and `Cypress/Core/Models/TreeMeasurement.swift` at run time,
 * so a factor or a bound that moves in Swift fails here rather than leaving the web converting by
 * last month's numbers. The arithmetic is compared against `support/swift-reference.json`, which
 * the real Swift printed.
 *
 * **Every one of the 66 numbers the reference records matches to the bit.** Swift `Double` and JS
 * `number` are the same IEEE-754 binary64, and every operation here is a single multiply or a
 * single divide — no trig, so none of the libm caveat that `geometry.test.ts` carries applies. The
 * inexactness that IS present is the arithmetic's own and is identical on both sides: 64 cm reads
 * back as 25.19685039370079 in, not 25.196850393700787, and 2.099737532808399 ft.
 *
 * The ported Swift cases are `MeasurePresentationTests.swift:371` (900 cm of DBH is implausible)
 * and `SQLiteStoreTests.swift:77` (12.5 inches with a caliper). There is no dedicated `Quantity`
 * suite in `CypressTests` — a finding in its own right; this file is the first place the
 * conversion table itself is asserted.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  converted,
  isMetric,
  isPlausible,
  lengthUnits,
  makeQuantity,
  measurementMethods,
  measurementSeriesNames,
  metersPerUnitOf,
  plausibleRange,
  plausibleSIRange,
  quantityFromJSON,
  seriesOf,
  seriesOfQuantity,
  type LengthUnit,
  type MeasurementMethod,
} from '../src/lib/quantity.ts';
import {
  repoFile,
  swiftClosedRangeLet,
  swiftEnumCases,
  swiftSwitchTable,
} from './support/sources.ts';

interface Reference {
  readonly lengthUnits: readonly { unit: LengthUnit; metersPerUnit: number; isMetric: boolean }[];
  readonly quantities: readonly {
    value: number;
    unit: LengthUnit;
    method: MeasurementMethod;
    siValue: number;
    series: string;
    plausibleDBH: boolean;
    plausibleHeight: boolean;
    converted: Record<LengthUnit, number>;
  }[];
  readonly plausible: {
    dbhLow: number;
    dbhHigh: number;
    heightLow: number;
    heightHigh: number;
  };
}

const reference = JSON.parse(
  readFileSync(new URL('./support/swift-reference.json', import.meta.url), 'utf8'),
) as Reference;

const quantitySwift = repoFile('Cypress/Core/Units/Quantity.swift');

describe('the vocabulary is the Swift’s', () => {
  it('the five length units, with the raw values the database stores', () => {
    const inSwift = swiftEnumCases(quantitySwift, 'LengthUnit').map((row) => row.raw);
    assert.deepEqual(
      [...lengthUnits],
      inSwift,
      `web/src/lib/quantity.ts has ${lengthUnits.join(', ')}; LengthUnit in Swift has `
        + `${inSwift.join(', ')}. These are the values in \`measurements.unit_entered\`, so a unit `
        + `the web does not know is a stored row it cannot read.`,
    );
  });

  it('the four methods and the two series', () => {
    assert.deepEqual(
      [...measurementMethods],
      swiftEnumCases(quantitySwift, 'MeasurementMethod').map((row) => row.raw),
    );
    assert.deepEqual(
      [...measurementSeriesNames],
      swiftEnumCases(quantitySwift, 'MeasurementSeries').map((row) => row.raw),
    );
  });

  /**
   * D7: estimated and measured values never share a line. The table is read out of the Swift's own
   * `switch`, by the case NAME, so a method moved from one series to the other fails here.
   */
  it('every method is in the series Swift puts it in', () => {
    const caseNames = new Map(
      swiftEnumCases(quantitySwift, 'MeasurementMethod').map((row) => [row.name, row.raw]),
    );
    const table = swiftSwitchTable(quantitySwift, 'series');
    assert.equal(table.size, 4, `Swift's MeasurementMethod.series has ${table.size} cases, not 4`);
    for (const [caseName, swiftSeries] of table) {
      const raw = caseNames.get(caseName);
      assert.ok(raw !== undefined, `MeasurementMethod.series names .${caseName}, which is not a case`);
      assert.equal(
        seriesOf(raw as MeasurementMethod),
        swiftSeries.replace(/^\./, ''),
        `'${raw}' is ${seriesOf(raw as MeasurementMethod)} on the web and ${swiftSeries} in Swift. `
          + `D7 forbids one connecting line across estimated and measured values; that is only `
          + `unrepresentable if both surfaces agree which is which.`,
      );
    }
  });

  it('every conversion factor is the one Swift declares', () => {
    const caseNames = new Map(
      swiftEnumCases(quantitySwift, 'LengthUnit').map((row) => [row.name, row.raw]),
    );
    const factors = swiftSwitchTable(quantitySwift, 'metersPerUnit');
    const metric = swiftSwitchTable(quantitySwift, 'isMetric');
    assert.equal(factors.size, 5, `Swift's metersPerUnit has ${factors.size} cases, not 5`);
    assert.equal(metric.size, 5, `Swift's isMetric has ${metric.size} cases, not 5`);
    for (const [caseName, literal] of factors) {
      const raw = caseNames.get(caseName) as LengthUnit | undefined;
      assert.ok(raw !== undefined, `metersPerUnit names .${caseName}, which is not a LengthUnit case`);
      assert.equal(
        metersPerUnitOf(raw as LengthUnit),
        Number(literal),
        `1 ${raw} is ${metersPerUnitOf(raw as LengthUnit)} m on the web and ${literal} m in Swift`,
      );
      assert.equal(isMetric(raw as LengthUnit), metric.get(caseName) === 'true', `isMetric('${raw}')`);
    }
  });

  it('both plausibility windows are the ones Swift declares', () => {
    assert.deepEqual(plausibleRange.dbhM, swiftClosedRangeLet(quantitySwift, 'dbhM'));
    assert.deepEqual(plausibleRange.heightM, swiftClosedRangeLet(quantitySwift, 'heightM'));
    // And that `MeasurementKind` still selects between them the same way. The selection lives in
    // a different file from the windows, and reading only the windows would miss a swap.
    const kinds = repoFile('Cypress/Core/Models/TreeMeasurement.swift');
    const table = swiftSwitchTable(kinds, 'plausibleSIRange');
    assert.equal(table.get('dbh'), 'Quantity.PlausibleRange.dbhM');
    assert.equal(table.get('height'), 'Quantity.PlausibleRange.heightM');
    assert.deepEqual(plausibleSIRange('dbh'), plausibleRange.dbhM);
    assert.deepEqual(plausibleSIRange('height'), plausibleRange.heightM);
  });

  it('the fixture was generated from the constants the Swift declares now', () => {
    // The fixture records derived outputs, which cannot drift on their own; what can drift is what
    // they were derived FROM. This is the assertion that turns a moved constant into "regenerate
    // the fixture" instead of a green suite comparing today's TypeScript to last month's Swift.
    const dbh = swiftClosedRangeLet(quantitySwift, 'dbhM');
    const height = swiftClosedRangeLet(quantitySwift, 'heightM');
    assert.deepEqual(
      reference.plausible,
      {
        dbhLow: dbh.lowerBound,
        dbhHigh: dbh.upperBound,
        heightLow: height.lowerBound,
        heightHigh: height.upperBound,
      },
      'support/swift-reference.json was produced from different plausibility bounds than the Swift '
        + 'now declares. Regenerate it — see support/swift-reference/main.swift.',
    );
    const factors = swiftSwitchTable(quantitySwift, 'metersPerUnit');
    const caseNames = new Map(
      swiftEnumCases(quantitySwift, 'LengthUnit').map((row) => [row.raw, row.name]),
    );
    for (const row of reference.lengthUnits) {
      const caseName = caseNames.get(row.unit);
      assert.ok(caseName !== undefined, `the fixture records a unit '${row.unit}' Swift no longer has`);
      assert.equal(
        row.metersPerUnit,
        Number(factors.get(caseName as string)),
        `the fixture records 1 ${row.unit} = ${row.metersPerUnit} m; Swift now says otherwise`,
      );
    }
  });
});

describe('Quantity reproduces the Swift’s arithmetic', () => {
  it('every recorded case matches to the bit', () => {
    assert.equal(
      reference.quantities.length,
      11,
      `the reference holds ${reference.quantities.length} quantities, not 11 — a case table that `
        + `shrank is a check that stopped checking`,
    );
    let comparisons = 0;
    for (const row of reference.quantities) {
      const quantity = makeQuantity(row.value, row.unit, row.method);
      const where = `${row.value} ${row.unit} by ${row.method}`;
      assert.ok(
        Object.is(quantity.siValue, row.siValue),
        `${where}: siValue is ${quantity.siValue} on the web and ${row.siValue} in Swift`,
      );
      assert.equal(seriesOfQuantity(quantity), row.series, `${where}: series`);
      assert.equal(
        isPlausible(quantity, plausibleRange.dbhM),
        row.plausibleDBH,
        `${where}: plausible as a DBH?`,
      );
      assert.equal(
        isPlausible(quantity, plausibleRange.heightM),
        row.plausibleHeight,
        `${where}: plausible as a height?`,
      );
      comparisons += 4;
      for (const unit of lengthUnits) {
        const expected = row.converted[unit];
        assert.ok(
          Object.is(converted(quantity, unit), expected),
          `${where} read back in ${unit}: ${converted(quantity, unit)} on the web, ${expected} in Swift`,
        );
        comparisons += 1;
      }
    }
    // Every comparison, counted. `node --test` reports one `it` whatever happens inside it, and a
    // loop over a table that lost its rows reports the same green line as a loop that checked
    // everything. This is the number that separates the two.
    assert.equal(
      comparisons,
      99,
      `${comparisons} comparisons ran, not 99 (11 cases × (4 + 5 units)). The case table or the `
        + `unit list has changed size and this loop is no longer checking what it says it is.`,
    );
  });

  /**
   * The conversion round trip is inexact in BOTH languages, identically. Asserting `converted(q,
   * q.unitEntered) === q.value` would be asserting something false about Swift as well, so what is
   * asserted is that the two are inexact the same way — which the case table above already does —
   * plus the two cases that DO round-trip, so the claim is not vacuous.
   */
  it('the round trip is inexact where Swift’s is, and exact where Swift’s is', () => {
    const exact = makeQuantity(12.5, 'in', 'caliper');   // SQLiteStoreTests.swift:77
    assert.equal(converted(exact, 'in'), 12.5);
    const inexact = makeQuantity(64, 'cm', 'tape');
    assert.equal(converted(inexact, 'cm'), 64);
    // …and the cross-unit reading is where the digits appear, on both sides.
    assert.equal(converted(inexact, 'in'), 25.19685039370079);
    assert.notEqual(converted(inexact, 'in'), 25.196850393700787, 'that is the real-number answer');
  });

  /** `MeasurePresentationTests.swift:371` — 900 cm of trunk diameter is a slipped keypad. */
  it('900 cm is not a plausible DBH, and is not rejected either', () => {
    const slip = makeQuantity(900, 'cm', 'tape');
    assert.equal(isPlausible(slip, plausibleSIRange('dbh')), false);
    // PRODUCT §1 principle 2: implausible warns, never blocks. The rule layer has nothing to
    // refuse with — there is no throw on this path, and that absence is the guarantee.
    assert.equal(slip.siValue, 9);
    assert.equal(slip.value, 900, 'the entered digits are unchanged by being implausible');
  });

  it('both bounds are inclusive, on both windows', () => {
    for (const [kind, range] of [['dbh', plausibleRange.dbhM], ['height', plausibleRange.heightM]] as const) {
      const low = makeQuantity(range.lowerBound, 'm', 'tape');
      const high = makeQuantity(range.upperBound, 'm', 'tape');
      assert.equal(isPlausible(low, range), true, `${kind}: the lower bound itself is implausible`);
      assert.equal(isPlausible(high, range), true, `${kind}: the upper bound itself is implausible`);
      // Swift's `ClosedRange.contains` is inclusive at both ends; a `<` on either side would
      // pass every other assertion in this file.
      assert.equal(isPlausible(makeQuantity(range.upperBound * 1.0000001, 'm', 'tape'), range), false);
    }
  });
});

describe('the type system is where TypeScript and Swift differ', () => {
  /**
   * Swift's `LengthUnit` is closed: a value outside the five cannot be constructed. The union here
   * is erased at run time, so an unregistered unit arrives from JSON as an ordinary string. Silent
   * defaulting to 1.0 would reinterpret it as meters, which is the failure a throw prevents.
   */
  it('an unregistered unit is refused rather than defaulted', () => {
    assert.throws(
      () => metersPerUnitOf('fathoms' as LengthUnit),
      /unknown length unit "fathoms"/,
    );
    assert.throws(() => makeQuantity(3, 'fathoms' as LengthUnit, 'tape'), /unknown length unit/);
    assert.throws(() => converted(makeQuantity(3, 'm', 'tape'), 'cubits' as LengthUnit), /unknown length unit/);
  });

  it('decoding re-derives siValue from the entered value, as Quantity.init(from:) does', () => {
    // "A persisted row that disagrees with itself resolves to the entered value" — the Swift
    // decoder does not even read `siValue`, and neither does this one.
    const decoded = quantityFromJSON({ value: 5, unitEntered: 'ft', method: 'tape', siValue: 999 });
    assert.equal(decoded.siValue, 1.524, 'the stored siValue won over the entered value');
    assert.deepEqual(decoded, makeQuantity(5, 'ft', 'tape'));
  });

  it('a row with no method does not decode — D7 at the only boundary that can enforce it', () => {
    assert.throws(() => quantityFromJSON({ value: 5, unitEntered: 'ft' }), /not a registered method/);
    assert.throws(() => quantityFromJSON({ unitEntered: 'ft', method: 'tape' }), /not a number/);
    assert.throws(() => quantityFromJSON({ value: 5, unitEntered: 'furlong', method: 'tape' }), /not a registered unit/);
    assert.throws(() => quantityFromJSON(null), /decodes from an object/);
  });

  it('an inverted plausibility range throws rather than calling everything implausible', () => {
    assert.throws(
      () => isPlausible(makeQuantity(1, 'm', 'tape'), { lowerBound: 4, upperBound: 0.001 }),
      /inverted/,
    );
  });
});
