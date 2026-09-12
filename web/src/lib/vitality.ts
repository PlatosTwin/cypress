/**
 * The anchored five-class vitality rubric (PRODUCT §3, "Vitality scale").
 *
 * Ported from `Cypress/Core/Rubric/Vitality.swift` — the enum's raw values, `label`, `anchor`,
 * `rubric`, `isRatingPermitted(leafRetention:month:leafOnMonths:)` and `suppression`. The
 * seasonality gate's INPUT, `Species.leafOnMonths`, lives in `Cypress/Core/Models/Species.swift`
 * and is deliberately NOT ported here: it is a different rule (a phenological window recovered
 * from two month sets, with a year-wrap that ERRATA E33 is about), W-B does not name it, and the
 * gate below takes the window as a parameter exactly as the Swift's primary signature does.
 *
 * The label and the anchor sentence are carried BY THE RULE, verbatim, because D3 requires the
 * anchor to be visible at rating time. A page renders `anchorOf`; it never authors this copy.
 *
 * Color is secondary coding only (D3) and lives in the design system, not here.
 *
 * ── The copy problem, and what is done about it ──────────────────────────────────────────────
 *
 * The five sentences now exist in FOUR places: `Vitality.swift`, `docs/distilled/PRODUCT.md` §3,
 * `docs/distilled/SCREENS.md` 05 §3, and this file. Ticket #261 exists because the first three
 * had forked and nothing noticed for two weeks. A fourth copy with no guard would be the same
 * mistake with a straight face, so `web/test/vitality.test.ts` parses all three sources and
 * asserts this file agrees with each — the web analogue of `VitalityRubricTests`'s
 * `allThreeSourcesStateTheSameRubric`, extended by one source.
 *
 * ── Where TypeScript and Swift may legitimately differ ───────────────────────────────────────
 *
 * 1. **Nothing numeric.** `classNumber` is the Swift enum's `Int` raw value, 1–5.
 * 2. **The enum is a union of names, not a closed type.** `labelOf`/`anchorOf` throw on an
 *    unregistered name rather than returning a placeholder, for the reason `metersPerUnitOf`
 *    throws: a rubric row with invented copy is worse than no row.
 * 3. **`Set<Int>` vs `ReadonlySet<number>`** is a like-for-like swap, but `leafOnMonths` being
 *    ABSENT is `null`/`undefined` here where Swift has one `nil`. Both are handled, and both mean
 *    the same thing: a caller with the habit but not the calendar, which does not suppress.
 */

/**
 * The five classes, keyed by the Swift enum's case names.
 *
 * A union rather than a TypeScript `enum` — `erasableSyntaxOnly`, see `web/tsconfig.json`.
 */
export const vitalityNames = ['severeDecline', 'poor', 'fair', 'good', 'thriving'] as const;
export type Vitality = (typeof vitalityNames)[number];

/** The numeric class as stored in `observations.vitality` (BUILD-PLAN §4, `vitality int 1 to 5`). */
const classNumbers: Readonly<Record<Vitality, number>> = {
  severeDecline: 1,
  poor: 2,
  fair: 3,
  good: 4,
  thriving: 5,
};

/** Class label, verbatim from the PRODUCT §3 rubric table. */
const labels: Readonly<Record<Vitality, string>> = {
  severeDecline: 'Severe decline',
  poor: 'Poor',
  fair: 'Fair',
  good: 'Good',
  thriving: 'Thriving',
};

/**
 * Plain-language anchor sentence, verbatim from the rubric table (ticket #261). Always visible at
 * rating time (D3) — never truncated, never moved into a view.
 *
 * Every row states its dieback band, and the five bands partition the whole percents 0–100 exactly
 * once: `thriving` 0, `good` 1–10, `fair` 11–25, `poor` 26–50, `severeDecline` over half.
 *
 * Row 3 does not mention discoloration, and must not: a deciduous species in fall color is inside
 * its leaf-on window by construction, so the seasonality gate does not suppress the rubric for it
 * (ERRATA E33), and a rater cannot tell seasonal color from stress color by looking.
 */
const anchors: Readonly<Record<Vitality, string>> = {
  severeDecline: 'Over half the crown is dead wood or bare in season; major limbs dead',
  poor: '26 to 50% of the crown is dead wood or bare; large dead sections',
  fair: '11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf',
  good: '1 to 10% of the crown is dead wood; canopy otherwise full',
  thriving: 'No dead wood visible; canopy full for the season',
};

function require_<Value>(table: Readonly<Record<Vitality, Value>>, vitality: Vitality, what: string): Value {
  const found: Value | undefined = table[vitality];
  if (found === undefined) {
    throw new Error(
      `no ${what} for vitality ${JSON.stringify(vitality)}; the five classes are `
        + `${vitalityNames.join(', ')}. D3 requires the anchor to be visible at rating time, so a `
        + `class with no copy is a class that must not render.`,
    );
  }
  return found;
}

export function classNumberOf(vitality: Vitality): number {
  return require_(classNumbers, vitality, 'class number');
}

export function labelOf(vitality: Vitality): string {
  return require_(labels, vitality, 'label');
}

export function anchorOf(vitality: Vitality): string {
  return require_(anchors, vitality, 'anchor');
}

/** The class a stored `observations.vitality` integer names, or `null` when it is outside 1–5. */
export function vitalityFromClassNumber(classNumber: number): Vitality | null {
  return vitalityNames.find((name) => classNumbers[name] === classNumber) ?? null;
}

/**
 * The five rows in the order screen 05 presents them (D3, five full-width rows).
 *
 * **Worst at the top.** The design export draws the rows `1 · Severe decline` … `5 · Thriving`
 * downward and SCREENS.md 05 §3 transcribes them in that order. The order is part of the rubric
 * rather than of the view: a rater who learns "the top row is the bad one" on one screen must not
 * meet the opposite on another.
 */
export const rubric: readonly Vitality[] = ['severeDecline', 'poor', 'fair', 'good', 'thriving'];

// ── Seasonality ─────────────────────────────────────────────────────────────────────────────

/** `Cypress/Core/Models/Species.swift:12`. Raw values are the stored ones. */
export const leafRetentions = ['evergreen', 'deciduous', 'semi_deciduous'] as const;
export type LeafRetention = (typeof leafRetentions)[number];

/**
 * Why the vitality section is hidden, so the leaf-off state can say so rather than silently
 * dropping a row (PRODUCT §5 M6, BUILD-PLAN §9 M2).
 */
export const suppressions = ['none', 'leafOffSeason'] as const;
export type Suppression = (typeof suppressions)[number];

/**
 * `| undefined` is spelled out on both optional fields rather than left to the `?`: under
 * `exactOptionalPropertyTypes` (astro's strictest, which `web/tsconfig.json` extends) a `?` field
 * refuses an explicit `undefined`, and `isRatingPermitted` accepts one. See the same note in
 * `growthCharting.ts`.
 */
export interface RatingWindow {
  /** The species attribute that drives all phenology surfaces (D5), or absent when unsourced. */
  readonly leafRetention?: LeafRetention | null | undefined;
  /** Calendar month, 1–12. */
  readonly month: number;
  /** The months this species is in leaf, or absent when unknown. See `Species.leafOnMonths`. */
  readonly leafOnMonths?: ReadonlySet<number> | null | undefined;
}

/**
 * Whether a vitality rating may be collected for this species in this calendar month.
 *
 * PRODUCT §3: deciduous species are rated only in leaf-on season; the app suppresses the vitality
 * UI off-season using species leaf phenology, and structure flags remain available year-round.
 *
 * Evergreen and semi-deciduous species are ratable year-round. **Unknown habit permits the rating**
 * (ERRATA E9): suppression is itself an assertion — that this tree is out of leaf right now — and
 * with no sourced habit we cannot make it. The two errors do not cost the same. Wrongly permitting
 * costs one observation a rater can skip; wrongly suppressing removes the vitality UI from a tree
 * for half the year with no way for anybody in the field to say otherwise.
 */
export function isRatingPermitted(window: RatingWindow): boolean {
  const { leafRetention, month, leafOnMonths } = window;
  // Swift's `(1...12).contains(month)` over an `Int`. A non-integer month cannot come from a
  // calendar and is refused here rather than compared, because `11.5` would otherwise pass the
  // bounds test and then miss every entry of a set of integers — a suppression nobody decided.
  if (!Number.isInteger(month) || month < 1 || month > 12) return false;
  if (leafRetention === null || leafRetention === undefined) return true;
  if (leafRetention === 'evergreen' || leafRetention === 'semi_deciduous') return true;
  // Deciduous. A deciduous species always has a window (`Species.leafOnMonths`), so the absent
  // case only fires for a caller that has the habit but not the calendar; it does not suppress.
  if (leafOnMonths === null || leafOnMonths === undefined) return true;
  return leafOnMonths.has(month);
}

export function suppressionFor(window: RatingWindow): Suppression {
  return isRatingPermitted(window) ? 'none' : 'leafOffSeason';
}
