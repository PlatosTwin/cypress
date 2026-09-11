/**
 * A number and how it was obtained, said the only way the product allows.
 *
 * Ported from `Cypress/DesignSystem/Components/MethodBadge.swift` — `MethodBadge.label`,
 * `MethodBadge.accessibilityLabel`, `MeasuredValue.formatted` and `MeasuredValue.number`. Not
 * authored here, for `cityRecord.ts`'s reason: a second vocabulary for the same fact is how the
 * vitality rubric forked for two weeks (ticket #261), and this vocabulary is load-bearing rather
 * than decorative. D7's whole point is that `taped` and `est.` are not decoration on a number —
 * they are the difference between a reading and a guess, and R1 spent a token retint on making the
 * two distinguishable at 4.5:1 to a reader with low contrast vision.
 *
 * `web/test/measuredValue.test.ts` parses the Swift at run time and fails when this file and it
 * disagree.
 *
 * ── The inline size, and only the inline size ────────────────────────────────────────────────
 *
 * The Swift badge has two sizes and they differ in exactly one word: `est.` inline (03, 14) and
 * `estimated` in the growth log (11). W1's fact column is C30, which is the inline form — §W1
 * draws `18 m` `est.` — and the growth log has no web surface, so the other size is not ported.
 * Porting an unused branch would mean maintaining a second answer nothing checks against a screen.
 */
import { cityRecordBadge } from './cityRecord.ts';
import type { MeasurementMethod, Quantity } from './quantity.ts';
import { seriesOf } from './quantity.ts';

/**
 * Which of the three badge treatments a value takes.
 *
 * `cityRecord` is a third case beside the two series rather than a third method, exactly as
 * `MethodBadge.Source` makes it: the city's published bucket was not measured by anybody, and
 * giving it a `MeasurementMethod` would mean choosing one the record does not state (E63).
 */
export type BadgeTone = 'measured' | 'estimated' | 'cityRecord';

/** A badge: the word, the treatment it takes, and what it means said out loud. */
export interface Badge {
  readonly text: string;
  readonly tone: BadgeTone;
  /** `MethodBadge.accessibilityLabel` — the meaning, not the abbreviation. */
  readonly spoken: string;
}

/**
 * `MethodBadge.label` for `.cityRecord`, with its spoken form.
 *
 * The text is `cityRecord.ts`'s, imported rather than retyped: that module already carries it and
 * `cityRecord.test.ts` already checks it against the Swift, so one string stays one string.
 */
export const CITY_RECORD_BADGE: Badge = {
  text: cityRecordBadge,
  tone: 'cityRecord',
  spoken: 'from the city record',
};

/**
 * `MethodBadge.label` (inline) and `MethodBadge.accessibilityLabel`, per method.
 *
 * `caliper` and `laser` carry their own word: the Swift's comment states why, and it is the same
 * reason the badge exists at all — *"the badge never claims a caliper reading was taped"*. They
 * take the measured treatment because `seriesOf` puts them there.
 */
const methodBadges: Readonly<Record<MeasurementMethod, { text: string; spoken: string }>> = {
  tape: { text: 'taped', spoken: 'measured with a tape' },
  caliper: { text: 'caliper', spoken: 'measured with a caliper' },
  laser: { text: 'laser', spoken: 'measured with a laser' },
  estimate: { text: 'est.', spoken: 'estimated' },
};

/** The badge for a quantity. There is no rendering of a quantity's number without one (D7). */
export function methodBadge(method: MeasurementMethod): Badge {
  const badge = methodBadges[method];
  if (badge === undefined) {
    // `MeasurementMethod` is a closed enum in Swift and an erased union here, so this is the one
    // place a fourth value could arrive. It throws rather than defaulting: a badge that guessed
    // would put an unlabeled number on a public page, which is the laundering D7 forbids.
    throw new Error(
      `no badge for measurement method ${JSON.stringify(method)} — the registered methods are `
        + `${Object.keys(methodBadges).join(', ')}, and a number drawn without its method would be `
        + `an estimate laundered into a measurement (D7)`,
    );
  }
  return { text: badge.text, tone: seriesOf(method), spoken: badge.spoken };
}

/**
 * `MeasuredValue.number` — whole numbers print bare, anything else keeps one decimal.
 *
 * `18` and not `18.0`; `12.5` and not `12.50`. The Swift rounds to the nearest whole for the
 * comparison and formats with `%.1f` otherwise, and both halves are reproduced rather than
 * approximated with `toLocaleString`, which would group thousands and localize the separator.
 */
export function measuredNumber(value: number): string {
  return value === Math.round(value) ? String(Math.round(value)) : value.toFixed(1);
}

/** `MeasuredValue.formatted` — `64 cm`, the value as entered, in the unit it was entered in. */
export function measuredValueText(quantity: Quantity): string {
  return `${measuredNumber(quantity.value)} ${quantity.unitEntered}`;
}
