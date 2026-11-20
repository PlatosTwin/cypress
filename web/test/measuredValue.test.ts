import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  CITY_RECORD_BADGE,
  measuredNumber,
  measuredValueText,
  methodBadge,
} from '../src/lib/measuredValue.ts';
import { makeQuantity, measurementMethods } from '../src/lib/quantity.ts';
import { repoFile, swiftStringCases } from './support/sources.ts';

/**
 * `src/lib/measuredValue.ts` against `Cypress/DesignSystem/Components/MethodBadge.swift`.
 *
 * The badge words are parsed out of the Swift at run time rather than transcribed here, which is
 * the whole practice of this directory: a transcription compares the port to its author's memory,
 * and D7's four words are the difference between a reading and a guess on a page a search engine
 * indexes.
 *
 * `MeasuredValue.number`'s rule is not a value and no parser here can read it, so it is held by a
 * fingerprint in `swiftDrift.test.ts` and by the examples below — the Swift's own two branches,
 * `String(Int(rounded))` and `%.1f`, exercised from both sides.
 */
const swift = repoFile('Cypress/DesignSystem/Components/MethodBadge.swift');

/**
 * `MethodBadge.label`'s inline word for a method whose case is a `size ==` ternary.
 *
 * `swiftStringCases` reads `case .x: return "…"` and correctly does not match
 * `case .estimate: return size == .growthLog ? "estimated" : "est."` — the `return` is not
 * followed by a quote. That one case is the whole reason the badge has two sizes, so it is parsed
 * here with its own pattern rather than left unchecked, and the pattern is calibrated below
 * against a specimen whose two answers were known before it saw them.
 */
function ternaryBadgeLabel(source: string, method: string, size: 'inline' | 'growthLog'): string {
  const pattern = new RegExp(
    String.raw`case\s+\.${method}\s*:\s*return\s+size\s*==\s*\.growthLog\s*\?\s*"([^"]*)"\s*:\s*"([^"]*)"`,
  );
  const match = pattern.exec(source);
  assert.notEqual(match, null, `no \`case .${method}: return size == .growthLog ? … : …\` found`);
  const [, growthLog, inline] = match as RegExpExecArray;
  const answer = size === 'growthLog' ? growthLog : inline;
  assert.notEqual(answer, undefined);
  return answer as string;
}

describe('the method badge says what the Swift says', () => {
  it('the ternary parser is reading the right half of the ternary', () => {
    // Calibration, on a specimen whose answers were known before the parser ran, and deliberately
    // not on the real file: the two arms are different strings in a fixed order, so a parser that
    // returned the wrong one would be caught here and nowhere else. The real `estimate` case is
    // `? "estimated" : "est."`, so a swapped parser would answer `estimated` for inline — which
    // reads plausibly and is the wrong word for C30.
    const specimen = 'case .estimate: return size == .growthLog ? "LONG" : "SHORT"';
    assert.equal(ternaryBadgeLabel(specimen, 'estimate', 'inline'), 'SHORT');
    assert.equal(ternaryBadgeLabel(specimen, 'estimate', 'growthLog'), 'LONG');
  });

  it('every method the port knows is a method the Swift badges, and no more', () => {
    const labels = swiftStringCases(swift, 'label');
    // The four the value parser can reach, plus the one it cannot. Asserted as a set so a fifth
    // method arriving in the Swift — or `estimate` being rewritten as a plain `return` — is red
    // here rather than quietly unchecked.
    assert.deepEqual(
      [...labels.keys()].sort(),
      ['caliper', 'cityRecord', 'laser', 'tape'],
      'MethodBadge.label no longer has exactly these four plain cases. If a method was added, '
        + 'src/lib/measuredValue.ts needs its word; if `estimate` stopped being a ternary, this '
        + 'test should read it through swiftStringCases instead.',
    );
    assert.deepEqual(
      [...measurementMethods].sort(),
      ['caliper', 'estimate', 'laser', 'tape'],
      'MeasurementMethod has changed and the badge table has to change with it',
    );
  });

  it('taped, caliper and laser carry their own word and the measured treatment', () => {
    const labels = swiftStringCases(swift, 'label');
    for (const method of ['tape', 'caliper', 'laser'] as const) {
      const badge = methodBadge(method);
      assert.equal(badge.text, labels.get(method), `the ${method} badge's word has drifted`);
      // The Swift's own comment: "the badge never claims a caliper reading was taped". All three
      // take the taped *styling* through `seriesOf` and none of them takes its word.
      assert.equal(badge.tone, 'measured');
    }
    assert.equal(methodBadge('tape').text, 'taped');
    assert.notEqual(methodBadge('caliper').text, methodBadge('tape').text);
  });

  it('an estimate says `est.` inline, which is the size §W1 draws', () => {
    assert.equal(methodBadge('estimate').text, ternaryBadgeLabel(swift, 'estimate', 'inline'));
    assert.equal(methodBadge('estimate').text, 'est.');
    assert.equal(methodBadge('estimate').tone, 'estimated');
    // And the growth-log word is deliberately NOT ported: the port must not be the long one.
    assert.notEqual(methodBadge('estimate').text, ternaryBadgeLabel(swift, 'estimate', 'growthLog'));
  });

  it('the city record badge is its own case and not a method', () => {
    assert.equal(CITY_RECORD_BADGE.text, swiftStringCases(swift, 'label').get('cityRecord'));
    assert.equal(CITY_RECORD_BADGE.tone, 'cityRecord');
    // It is not reachable through a method, which is E63's separation: constructing a Quantity for
    // a published bucket would mean choosing a MeasurementMethod the record does not state.
    for (const method of measurementMethods) {
      assert.notEqual(methodBadge(method).tone, 'cityRecord');
    }
  });

  it('a method outside the vocabulary throws rather than drawing an unbadged number', () => {
    // The union is erased at run time, so this is the one place a fourth value could arrive. A
    // default would put a number on a public page with no provenance, which is what D7 forbids.
    assert.throws(
      // @ts-expect-error — deliberately outside `MeasurementMethod`, which is the point.
      () => methodBadge('vibes'),
      /no badge for measurement method/,
    );
  });

  it('every badge speaks its meaning rather than its abbreviation', () => {
    const spoken = swiftStringCases(swift, 'accessibilityLabel');
    assert.equal(CITY_RECORD_BADGE.spoken, spoken.get('cityRecord'));
    for (const method of measurementMethods) {
      assert.equal(methodBadge(method).spoken, spoken.get(method), `${method} speaks differently`);
    }
    // The point of the property, asserted rather than assumed: the spoken form is never the badge.
    assert.equal(methodBadge('estimate').spoken, 'estimated');
    assert.notEqual(methodBadge('estimate').spoken, methodBadge('estimate').text);
  });
});

describe('a value is written the way MeasuredValue writes it', () => {
  it('whole numbers print bare and everything else keeps one decimal', () => {
    assert.equal(measuredNumber(18), '18');
    assert.equal(measuredNumber(18.0), '18');
    assert.equal(measuredNumber(64), '64');
    assert.equal(measuredNumber(12.5), '12.5');
    assert.equal(measuredNumber(12.54), '12.5');
    assert.equal(measuredNumber(12.55), '12.6');
    assert.equal(measuredNumber(0.5), '0.5');
    // Negative and zero, because `rounded()` and `Int()` are where a port of this usually differs.
    assert.equal(measuredNumber(0), '0');
    assert.equal(measuredNumber(-1.25), '-1.3');
  });

  it('a thousand is a thousand and not `1,000`', () => {
    // `toLocaleString` would group and would localize the separator, which is the obvious wrong
    // implementation of this function and the one a reader would not notice until a mono column
    // said `1,200 mm`.
    assert.equal(measuredNumber(1200), '1200');
  });

  it('the value keeps the unit it was entered in, never a converted one', () => {
    assert.equal(measuredValueText(makeQuantity(18, 'm', 'estimate')), '18 m');
    assert.equal(measuredValueText(makeQuantity(64, 'cm', 'tape')), '64 cm');
    // 64 cm is 0.64 m and this says `64 cm`. `Quantity` stores SI alongside and the display rule
    // is "never silently converted"; a port that reached for `siValue` would print `0.64 m`.
    assert.equal(makeQuantity(64, 'cm', 'tape').siValue, 0.64);
    assert.equal(measuredValueText(makeQuantity(12.5, 'in', 'caliper')), '12.5 in');
  });
});
