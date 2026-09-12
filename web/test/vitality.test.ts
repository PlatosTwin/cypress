/**
 * The vitality rubric, and the fork ticket #261 closed — held shut across one more source.
 *
 * `CypressTests/VitalityRubricTests.swift` exists because `Vitality.anchor`, `PRODUCT.md` §3 and
 * `SCREENS.md` 05 §3 had disagreed on all five anchor sentences since the day both documents were
 * distilled, and nothing in the repository read the two tables. `web/src/lib/vitality.ts` makes a
 * FOURTH copy. A fourth copy with no guard is that mistake repeated with a straight face, so this
 * file is that suite ported and extended by one source:
 *
 *   §1  the bands, and the copy that has to state them        — everyClassStatesItsBand,
 *                                                               theTableCoversTheRubric,
 *                                                               bandsPartitionTheWholePercents
 *   §2  the four sources state one rubric                     — allThreeSourcesStateTheSameRubric,
 *                                                               plus vitality.ts
 *   §3  the one clause the seasonality gate cannot rescue     — noAnchorAsksAboutDiscoloration
 *   §4  the gate itself                                       — SeasonalWindowTests,
 *                                                               SeedContractTests
 *
 * The markdown parser's own calibration lives in `sources.test.ts`, which is where
 * `VitalityRubricTests.theParserIsCalibrated` was ported to.
 *
 * **What the first version of the Swift file got wrong, because the shape recurs and this port
 * inherits the fix.** `VitalityBand` used to carry `percents` and a hand-written `phrase` as two
 * independent fields, and the test computed the correct phrase and then used it only in the
 * failure message. A reviewer set `.fair`'s anchor to "10 to 25%…" with a matching phrase, left
 * `percents: 11...25`, and got four green tests while 10 percent was claimed by two rows. A guard
 * that computes the truth and does not assert on it is indistinguishable from one that works. The
 * band statement below is derived from `percents` and from nothing else.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  anchorOf,
  classNumberOf,
  isRatingPermitted,
  labelOf,
  leafRetentions,
  rubric,
  suppressionFor,
  vitalityFromClassNumber,
  vitalityNames,
  type LeafRetention,
  type Vitality,
} from '../src/lib/vitality.ts';
import { markdownAnchorTable, repoFile, swiftEnumCases, swiftStringCases } from './support/sources.ts';

// ── How a band must be stated ───────────────────────────────────────────────────────────────

interface Band {
  readonly vitality: Vitality;
  readonly low: number;
  readonly high: number;
}

/**
 * Ticket #261, Candidate A. The whole percents of crown dieback each class claims.
 *
 * The claim an anchor has to make is DERIVED from these numbers below, never authored beside them.
 */
const bands: readonly Band[] = [
  { vitality: 'thriving', low: 0, high: 0 },
  { vitality: 'good', low: 1, high: 10 },
  { vitality: 'fair', low: 11, high: 25 },
  { vitality: 'poor', low: 26, high: 50 },
  { vitality: 'severeDecline', low: 51, high: 100 },
];

/** What a reader of a failure message needs: the claim in words. */
function describedStatement(band: Band): string {
  if (band.low === 0 && band.high === 0) return 'no dieback at all, stated as such and with no percentage';
  if (band.high === 100) return 'more than half the crown';
  return `the band ${band.low} to ${band.high}%`;
}

/** Whether `anchor` makes the claim `band` obliges it to make. A predicate over the quantity the
 * sentence asserts, not over how it is worded: a re-word that keeps the quantity passes. */
function statesItsBand(band: Band, anchor: string): boolean {
  if (band.low === 0 && band.high === 0) {
    // The negation and the noun in the same clause, so a sentence that merely contains "no"
    // elsewhere does not qualify — and no percentage at all.
    return !anchor.includes('%') && /\b(?:no|none|zero)\b[^;.]*\b(?:dead wood|dieback|dead)\b/i.test(anchor);
  }
  if (band.high === 100) return /\b(?:over|more than)\s+(?:half|50\s*%)/i.test(anchor);
  // "11 to 25%", "11-25%", "11–25%", "11—25%".
  const separator = String.raw`\s*(?:to|-|–|—)\s*`;
  return new RegExp(String.raw`\b${band.low}${separator}${band.high}\s*%`, 'i').test(anchor);
}

describe('the bands, and the copy that has to state them', () => {
  for (const band of bands) {
    it(`${classNumberOf(band.vitality)} · ${labelOf(band.vitality)} states its band`, () => {
      const anchor = anchorOf(band.vitality);
      assert.ok(
        statesItsBand(band, anchor),
        `${classNumberOf(band.vitality)} · ${labelOf(band.vitality)} claims ${band.low}–${band.high}% `
          + `crown dieback, so its anchor has to state ${describedStatement(band)}. It reads `
          + `“${anchor}”. A class's band is its operational definition (RULINGS R13 reserves a `
          + `class's meaning to PRODUCT.md); a rater holding a percentage must find the row that `
          + `names it.`,
      );
    });
  }

  /**
   * The matcher, on specimens whose answers are known before it sees them. Without this, the five
   * assertions above agree with whatever the five anchors happen to say — and would agree just as
   * readily if `statesItsBand` returned `true` unconditionally.
   */
  it('the band matcher declines a sentence that does not state the band', () => {
    const fair = { vitality: 'fair', low: 11, high: 25 } as const;
    assert.equal(statesItsBand(fair, '11 to 25% of the crown is dead wood'), true);
    assert.equal(statesItsBand(fair, '11–25% dead'), true, 'an en dash is the same claim');
    assert.equal(statesItsBand(fair, '10 to 25% of the crown is dead wood'), false, 'the #59 defect');
    assert.equal(statesItsBand(fair, 'noticeably thin but clearly in leaf'), false, 'no quantity at all');

    const thriving = { vitality: 'thriving', low: 0, high: 0 } as const;
    assert.equal(statesItsBand(thriving, 'No dead wood visible; canopy full'), true);
    assert.equal(statesItsBand(thriving, 'Under 10% dieback'), false, 'draft v0’s overlap with .good');
    assert.equal(statesItsBand(thriving, 'no more than 5% dead wood'), false, 'names a percentage');
    assert.equal(statesItsBand(thriving, 'Canopy full; no thinning. Some dead wood'), false,
      'the negation and the noun are in different clauses');

    const severe = { vitality: 'severeDecline', low: 51, high: 100 } as const;
    assert.equal(statesItsBand(severe, 'Over half the crown is dead wood'), true);
    assert.equal(statesItsBand(severe, 'more than 50% dead'), true);
    assert.equal(statesItsBand(severe, 'Most of the crown is dead'), false, '“most” is not a quantity');
  });

  it('the band table names all five classes, worst first', () => {
    assert.deepEqual(bands.map((band) => band.vitality), [...rubric].reverse());
  });

  it('every whole percent from 0 to 100 belongs to exactly one class', () => {
    for (let percent = 0; percent <= 100; percent += 1) {
      const owners = bands.filter((band) => percent >= band.low && percent <= band.high);
      const named = owners.map((band) => `${classNumberOf(band.vitality)} · ${labelOf(band.vitality)}`);
      assert.equal(
        owners.length,
        1,
        `${percent}% crown dieback is claimed by ${owners.length} classes (${named.join(', ')}). A `
          + `rater who reads that value off a crown has `
          + `${owners.length === 0 ? 'no row to tap' : 'more than one row that fits'}.`,
      );
    }
  });
});

// ── The four sources state one rubric ───────────────────────────────────────────────────────

const vitalitySwift = repoFile('Cypress/Core/Rubric/Vitality.swift');
const PRODUCT_HEADING = '### Vitality scale';
const SCREENS_HEADING = '#### 05 \u{00b7} Light check-in';

describe('Vitality.swift, PRODUCT §3, SCREENS 05 §3 and vitality.ts state one rubric', () => {
  it('all four agree, class by class', () => {
    const swiftAnchors = swiftStringCases(vitalitySwift, 'anchor');
    const product = markdownAnchorTable(repoFile('docs/distilled/PRODUCT.md'), PRODUCT_HEADING);
    const screens = markdownAnchorTable(repoFile('docs/distilled/SCREENS.md'), SCREENS_HEADING);

    for (const vitality of rubric) {
      const level = classNumberOf(vitality);
      const web = anchorOf(vitality);
      const swift = swiftAnchors.get(vitality);
      const inProduct = product.get(level);
      const inScreens = screens.get(level);
      assert.ok(swift !== undefined, `Vitality.swift's anchor has no .${vitality} case`);
      assert.ok(inProduct !== undefined, `PRODUCT §3's table has no row for level ${level}`);
      assert.ok(inScreens !== undefined, `SCREENS 05 §3's table has no row for level ${level}`);

      // Which source moved is decided by the majority: three agreeing against a fourth is what
      // identifies the fourth. "They disagree" is not actionable when there are four of them.
      const sources = [
        ['web/src/lib/vitality.ts', web],
        ['Cypress/Core/Rubric/Vitality.swift', swift],
        ['docs/distilled/PRODUCT.md §3', inProduct],
        ['docs/distilled/SCREENS.md 05 §3', inScreens],
      ] as const;
      const tally = new Map<string, string[]>();
      for (const [name, text] of sources) tally.set(text, [...(tally.get(text) ?? []), name]);
      const odd = [...tally.entries()].filter(([, names]) => names.length < sources.length / 2);
      const culprit =
        tally.size === 1
          ? ''
          : odd.length === 1 && odd[0] !== undefined
            ? `**${odd[0][1].join(' and ')} ${odd[0][1].length === 1 ? 'has' : 'have'} drifted from the rest.**`
            : '**No majority**, so this is not one edit going astray.';

      assert.equal(
        tally.size,
        1,
        `level ${level} (${labelOf(vitality)}): ${culprit}\n`
          + sources.map(([name, text]) => `  ${name}: “${text}”`).join('\n')
          + `\nTicket #261 landed one rubric in three places on purpose, closing a fork that had `
          + `stood since the handoff; W-B made it four. Whichever of them is right, they cannot differ.`,
      );
    }
  });

  it('the labels and the class numbers agree with the Swift enum too', () => {
    const swiftLabels = swiftStringCases(vitalitySwift, 'label');
    const swiftCases = swiftEnumCases(vitalitySwift, 'Vitality');
    assert.equal(swiftCases.length, 5, `Vitality declares ${swiftCases.length} cases, not 5`);
    for (const { name, raw } of swiftCases) {
      assert.ok(
        (vitalityNames as readonly string[]).includes(name),
        `Vitality.swift has a case .${name} the web does not know`,
      );
      assert.equal(
        classNumberOf(name as Vitality),
        Number(raw),
        `.${name} is stored as ${raw} in observations.vitality and the web calls it `
          + `${classNumberOf(name as Vitality)}`,
      );
      assert.equal(labelOf(name as Vitality), swiftLabels.get(name), `.${name}'s label`);
    }
    // And the reverse map, so a stored integer resolves the same way.
    for (const { name, raw } of swiftCases) {
      assert.equal(vitalityFromClassNumber(Number(raw)), name);
    }
    assert.equal(vitalityFromClassNumber(0), null, '0 is not a vitality class');
    assert.equal(vitalityFromClassNumber(6), null, '6 is not a vitality class');
  });

  /**
   * **Both parsers can see what they claim to have checked.** An equality over an empty table
   * passes, and a heading rename or a table reshape empties one silently. `VitalityRubricTests`
   * calls this `theParserFindsBothTables`; both documents must yield exactly five levels, and the
   * Swift must yield exactly five anchors, before any comparison above means anything.
   */
  it('every source parsed to exactly the five levels', () => {
    for (const [path, heading] of [
      ['docs/distilled/PRODUCT.md', PRODUCT_HEADING],
      ['docs/distilled/SCREENS.md', SCREENS_HEADING],
    ] as const) {
      const parsed = markdownAnchorTable(repoFile(path), heading);
      assert.deepEqual(
        [...parsed.keys()].sort((a, b) => a - b),
        [1, 2, 3, 4, 5],
        `${path}: the rubric table under “${heading}” parsed to levels `
          + `${[...parsed.keys()].sort((a, b) => a - b).join(', ')}, not 1–5. The parser is reading `
          + `the wrong table or no table, and every comparison that depends on it is passing on nothing.`,
      );
      for (const [level, anchor] of parsed) {
        assert.notEqual(anchor, '', `${path}: level ${level}'s anchor cell parsed empty`);
      }
    }
    const swiftAnchors = swiftStringCases(vitalitySwift, 'anchor');
    assert.deepEqual([...swiftAnchors.keys()].sort(), [...vitalityNames].sort());
  });

  it('the rows are ordered worst first, in the rubric and in SCREENS', () => {
    // "Worst at the top." A rater who learns "the top row is the bad one" on one screen must not
    // meet the opposite on another, so the order is part of the rubric and not of the view.
    assert.deepEqual(rubric.map(classNumberOf), [1, 2, 3, 4, 5]);
    const swiftRubric = /public static let rubric: \[Vitality\] = \[([^\]]*)\]/.exec(vitalitySwift);
    assert.ok(swiftRubric?.[1] !== undefined, 'Vitality.swift no longer declares `rubric`');
    assert.deepEqual(
      swiftRubric[1].split(',').map((entry) => entry.trim().replace(/^\./, '')),
      [...rubric],
      'Vitality.rubric and web/src/lib/vitality.ts order the five rows differently',
    );
  });
});

/**
 * `VitalityRubricTests.noAnchorAsksAboutDiscoloration`, ported verbatim in substance.
 *
 * The single absence assertion in this file, and it earns its place: no gate change can fix this
 * one. `Species.leafOnMonths` runs the deciduous window to the close of the fall-color season, so
 * fall color sits inside leaf-on by construction — intended behavior, and the derivation ERRATA
 * E33 repaired for a different bug. A tree in fall color is therefore in leaf, ratable and
 * discolored, and draft v0's row 3 pointed that rater at a decline class. Adding a second
 * condition to the gate would suppress the rubric in the fall for trees that are in leaf, which is
 * what E33 exists to prevent, so the repair is copy — and copy that has to stay repaired.
 */
describe('the one clause the seasonality gate cannot rescue', () => {
  for (const vitality of vitalityNames) {
    it(`${classNumberOf(vitality)} · ${labelOf(vitality)} does not ask about discoloration`, () => {
      assert.equal(
        anchorOf(vitality).toLowerCase().includes('discolor'),
        false,
        `${classNumberOf(vitality)} · ${labelOf(vitality)} asks about discoloration: `
          + `“${anchorOf(vitality)}”. A deciduous species in fall color is in leaf, so the `
          + `seasonality gate does not and must not suppress the rubric for it (ERRATA E33), and a `
          + `rater cannot tell seasonal color from stress color by looking.`,
      );
    });
  }
});

// ── The seasonality gate ────────────────────────────────────────────────────────────────────

describe('the seasonality gate', () => {
  it('the three leaf-retention values are the Swift’s, raw values and all', () => {
    assert.deepEqual(
      [...leafRetentions].sort(),
      swiftEnumCases(repoFile('Cypress/Core/Models/Species.swift'), 'LeafRetention')
        .map((row) => row.raw)
        .sort(),
      'the stored `leaf_retention` vocabulary has moved; a habit the web does not know is a '
        + 'species row it reads as unknown',
    );
  });

  /**
   * `SeasonalWindowTests.ratingFollowsTheWrappedWindow`, ported.
   *
   * The Swift builds a `Species` whose fall color wraps the year and asserts the window that comes
   * out is `{3…12, 1}`. `Species.leafOnMonths` is a different rule and is not ported (see this
   * module's header), so the window is passed in — as the Swift's own primary signature takes it —
   * at exactly the value that Swift test asserts `leafOnMonths` produces.
   */
  it('vitality stays ratable in a wrapped month, and only there', () => {
    const wrapped = new Set([3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 1]);
    assert.equal(isRatingPermitted({ leafRetention: 'deciduous', month: 1, leafOnMonths: wrapped }), true);
    assert.equal(suppressionFor({ leafRetention: 'deciduous', month: 1, leafOnMonths: wrapped }), 'none');
    assert.equal(isRatingPermitted({ leafRetention: 'deciduous', month: 2, leafOnMonths: wrapped }), false);
    assert.equal(
      suppressionFor({ leafRetention: 'deciduous', month: 2, leafOnMonths: wrapped }),
      'leafOffSeason',
    );
  });

  /** `SeedContractTests.unknownLeafRetentionStaysUnknown`, ported. ERRATA E9. */
  it('an unknown habit permits the rating in all twelve months', () => {
    for (let month = 1; month <= 12; month += 1) {
      assert.equal(isRatingPermitted({ month }), true, `month ${month}, habit absent`);
      assert.equal(isRatingPermitted({ leafRetention: null, month }), true, `month ${month}, habit null`);
      assert.equal(suppressionFor({ leafRetention: null, month }), 'none');
    }
  });

  it('evergreen and semi-deciduous are ratable year round, whatever the window says', () => {
    const januaryOnly = new Set([1]);
    for (const habit of ['evergreen', 'semi_deciduous'] as LeafRetention[]) {
      for (let month = 1; month <= 12; month += 1) {
        assert.equal(
          isRatingPermitted({ leafRetention: habit, month, leafOnMonths: januaryOnly }),
          true,
          `${habit} in month ${month}`,
        );
      }
    }
  });

  it('a deciduous species with no window is permitted, not suppressed', () => {
    // "A deciduous species always has a window, so this only fires for a caller that has the habit
    // but not the calendar; it does not suppress."
    for (const window of [undefined, null]) {
      for (let month = 1; month <= 12; month += 1) {
        assert.equal(isRatingPermitted({ leafRetention: 'deciduous', month, leafOnMonths: window }), true);
      }
    }
  });

  it('a deciduous species with a window is suppressed outside it — the gate is not a constant true', () => {
    const summer = new Set([4, 5, 6, 7, 8, 9, 10]);
    const permitted: number[] = [];
    for (let month = 1; month <= 12; month += 1) {
      if (isRatingPermitted({ leafRetention: 'deciduous', month, leafOnMonths: summer })) permitted.push(month);
    }
    assert.deepEqual(permitted, [4, 5, 6, 7, 8, 9, 10]);
  });

  it('a month outside 1–12 is refused, and so is a month that is not a whole number', () => {
    for (const month of [0, 13, -1, 100]) {
      assert.equal(isRatingPermitted({ month }), false, `month ${month}`);
      assert.equal(suppressionFor({ month }), 'leafOffSeason');
    }
    // Swift's `(1...12).contains(month)` is over an `Int` and cannot be handed 11.5. Here it can,
    // and 11.5 passes the bounds test and then misses every entry of a set of integers — a
    // suppression nobody decided. Refused at the top instead.
    assert.equal(isRatingPermitted({ month: 11.5 }), false);
    assert.equal(isRatingPermitted({ leafRetention: 'evergreen', month: 11.5 }), false);
    assert.equal(isRatingPermitted({ month: Number.NaN }), false);
  });
});
