/**
 * The layered gradient recipes W1 paints its hero with, and the CSS they render to.
 *
 * ── Why this file exists at all ──────────────────────────────────────────────────────────────
 *
 * `web/src/styles/tokens.css` is generated from `Cypress/DesignSystem/Tokens/*.swift` and it
 * carries every color, radius, space and font the design system declares. It carries **no
 * gradient**, and that is deliberate rather than an oversight — `web/README.md` names
 * `CypressGradient.swift` as the first of "three things the export does not carry", because a
 * multi-stop radial with its own geometry is not one custom property and cannot be made into one.
 * The same README says what follows from that: "W1's hero is a gradient, so W-C ports them."
 *
 * This is that port. It is the same shape as the Swift's own: `CypressRadialStop` and
 * `CypressGradientRecipe` are data, `CypressGradientField` renders them, and no component file
 * contains an image hex. Here the renderer emits CSS instead of a `ZStack`, and the recipes are
 * the ones `SCREENS.md` transcribes for the screens this app draws.
 *
 * **The hexes here are not raw hex in the ARCHITECTURE §6 sense.** §6 forbids a color literal in a
 * *component*, because the design system owns that value. These ARE the design system's values,
 * in the one file that owns them, exactly as `CypressGradient.swift` holds them for iOS — and
 * `web/test/gradients.test.ts` refuses to let them drift from the two documents that declare them.
 *
 * ── What the guard actually proves, in two halves ────────────────────────────────────────────
 *
 * 1. **The recipes agree with `docs/distilled/SCREENS.md`**, parsed at run time. That is where
 *    W1's hero is declared; it exists in no Swift file, because W1 is a web screen and
 *    `CypressColor` says so itself — its `lightOnly` helper documents a token that "belongs to the
 *    spec document or to W1", and `surfaceWeb` adds "W1 is out of scope for iOS".
 * 2. **The CSS emitter agrees with `Cypress/DesignSystem/Tokens/CypressGradient.swift`**, also
 *    parsed at run time. `heroProfile` — screen 03's hero — is declared in BOTH the Swift and
 *    SCREENS.md, so the test reads the recipe out of the Swift, renders it through
 *    `cssBackgroundImage` below, and requires the result to equal the CSS that SCREENS.md
 *    transcribes for screen 03. An emitter that mangled a stop, reversed the layer order or lost a
 *    percentage would fail that, and it fails it against the iOS source rather than against a
 *    transcription of it.
 *
 * Half 1 without half 2 would only prove this file was typed correctly; half 2 without half 1
 * would leave W1's own recipe — which the Swift does not carry — unguarded. Neither is sufficient.
 *
 * ── CSS → SwiftUI, and back ──────────────────────────────────────────────────────────────────
 *
 * `CypressGradient.swift`'s header records the conversion it made in the other direction, and it
 * is the reason this port is a re-emission rather than a re-derivation:
 *
 * > `radial-gradient(circle at X% Y%, C 0%, transparent N%)` with no size keyword defaults to
 * > `farthest-corner`
 *
 * So `extent` is a fraction of the farthest-corner distance, and emitting `transparent N%` gives
 * it back verbatim. The Swift had to write `color.opacity(0)` instead of `Color.clear` because
 * SwiftUI interpolates toward black; CSS interpolates `transparent` in premultiplied alpha and
 * does not, which is why `transparent` is correct here and was not there.
 *
 * **Layer order is reversed between the two renderers and this file emits the CSS one.** A
 * SwiftUI `ZStack` draws its first child at the back; a CSS `background-image` list draws its
 * first layer at the front. `SCREENS.md` lists the radials first and the linear base last, which
 * is CSS order, and so does `cssBackgroundImage`.
 */

/** A color as the design documents write it: `#RRGGBB`, or `rgba(r,g,b,a)` when a layer is faded. */
export interface RecipeColor {
  /** `0xRRGGBB`. Kept as a number so a parser and this file compare values, not spellings. */
  readonly rgb: number;
  /** 0…1. `1` renders as `#RRGGBB`; anything else as `rgba(…)`, which is how both documents write it. */
  readonly alpha: number;
}

/** One `radial-gradient(circle at x% y%, color 0%, transparent extent%)` layer. */
export interface RadialStop {
  /** Center, as a fraction of the box width. */
  readonly x: number;
  /** Center, as a fraction of the box height. */
  readonly y: number;
  readonly color: RecipeColor;
  /** The `transparent N%` stop, as a fraction of the farthest-corner distance. */
  readonly extent: number;
}

/** One stop of the linear base — a color and its position, as a fraction. */
export interface LinearStop {
  readonly color: RecipeColor;
  readonly position: number;
}

/** `linear-gradient(<degrees>deg, …)`. */
export interface LinearBase {
  readonly degrees: number;
  readonly stops: readonly LinearStop[];
}

/** A layered image placeholder: radial layers over a linear base. `CypressGradientRecipe`. */
export interface GradientRecipe {
  readonly radials: readonly RadialStop[];
  readonly base: LinearBase;
}

/**
 * The C2 scrim — `linear-gradient(180deg, rgba(r,g,b,0) <from>, rgba(r,g,b,<to>) 100%)`, drawn
 * over the hero and under the text.
 */
export interface Scrim {
  readonly rgb: number;
  /** Where the transparent stop sits, as a fraction. */
  readonly from: number;
  /** The alpha at 100%. */
  readonly to: number;
}

export function rgb(value: number): RecipeColor {
  return { rgb: value, alpha: 1 };
}

export function rgba(value: number, alpha: number): RecipeColor {
  return { rgb: value, alpha };
}

// ── Emission ────────────────────────────────────────────────────────────────────────────────

/**
 * `#4e8f6a`, lowercase, six digits.
 *
 * Lowercase rather than the documents' uppercase because that is what every CSS serializer emits
 * and a reader comparing the rendered page's computed style to this file should not have to think
 * about case. The comparison that matters is done on numbers, in the test, before either is a
 * string.
 */
function hex(value: number): string {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffff) {
    throw new RangeError(`${value} is not a 24-bit color`);
  }
  return `#${value.toString(16).padStart(6, '0')}`;
}

/**
 * A number as CSS writes it: no trailing zeros, no leading `0` before a decimal point when the
 * documents omit it (`.6`), because the alpha values in `SCREENS.md` are written that way and a
 * round trip through this file should produce the document's own text.
 */
function percent(fraction: number): string {
  const value = fraction * 100;
  // `Number.prototype.toString` already drops trailing zeros; the rounding is here because
  // 0.34 * 100 is 34.00000000000001 in binary64 and `34.00000000000001%` is not what anybody
  // transcribed. Six places is far more than any stop in either document carries.
  return `${Number(value.toFixed(6))}%`;
}

function alphaText(alpha: number): string {
  const text = String(Number(alpha.toFixed(6)));
  return text.startsWith('0.') ? text.slice(1) : text;
}

/** `#4e8f6a`, or `rgba(78,143,106,.5)` when the layer carries an alpha — the documents' own two spellings. */
export function cssColor(color: RecipeColor): string {
  if (color.alpha === 1) return hex(color.rgb);
  const r = (color.rgb >> 16) & 0xff;
  const g = (color.rgb >> 8) & 0xff;
  const b = color.rgb & 0xff;
  return `rgba(${r},${g},${b},${alphaText(color.alpha)})`;
}

/** One radial layer: `radial-gradient(circle at 26% 50%, #4e8f6a 0%, transparent 34%)`. */
export function cssRadial(stop: RadialStop): string {
  return `radial-gradient(circle at ${percent(stop.x)} ${percent(stop.y)}, `
    + `${cssColor(stop.color)} 0%, transparent ${percent(stop.extent)})`;
}

/** The linear base: `linear-gradient(180deg, #eaf0e2 0%, #c9dccc 55%, #8fb59b 100%)`. */
export function cssLinear(base: LinearBase): string {
  const stops = base.stops
    .map((stop) => `${cssColor(stop.color)} ${percent(stop.position)}`)
    .join(', ');
  return `linear-gradient(${base.degrees}deg, ${stops})`;
}

/**
 * The whole recipe as one `background-image` value — radials first, base last.
 *
 * See this file's header on layer order: this is CSS order, and it is the order both documents
 * write the stack in. Reversing it is the mistake the Swift-parity half of the guard catches.
 */
export function cssBackgroundImage(recipe: GradientRecipe): string {
  return [...recipe.radials.map(cssRadial), cssLinear(recipe.base)].join(', ');
}

/** `linear-gradient(180deg, rgba(16,32,22,0) 46%, rgba(16,32,22,.6) 100%)`. */
export function cssScrim(scrim: Scrim): string {
  return cssLinear({
    degrees: 180,
    stops: [
      { color: rgba(scrim.rgb, 0), position: scrim.from },
      { color: rgba(scrim.rgb, scrim.to), position: 1 },
    ],
  });
}

// ── The recipes W1 draws ────────────────────────────────────────────────────────────────────

/**
 * W1's hero, `SCREENS.md` §W1.
 *
 * **Not `CypressGradient.heroProfile`, and the difference is the point.** Screen 03's hero is
 * `radial(28% 46%, … 0→36%)`; W1's is `radial(26% 50%, … 0→34%)`. Every one of the nine numbers
 * differs, and the base's middle and end stops are different colors. They are near enough that
 * borrowing the Swift's would have looked right on screen and been wrong in the file — which is
 * why the test parses §W1 rather than accepting a recipe that "matches the app".
 */
export const W1_HERO: GradientRecipe = {
  radials: [
    { x: 0.26, y: 0.5, color: rgb(0x4e8f6a), extent: 0.34 },
    { x: 0.52, y: 0.34, color: rgb(0x35704f), extent: 0.4 },
    { x: 0.72, y: 0.54, color: rgb(0x24513b), extent: 0.38 },
    { x: 0.42, y: 0.62, color: rgb(0x2f6b4f), extent: 0.36 },
  ],
  base: {
    degrees: 180,
    stops: [
      { color: rgb(0xeaf0e2), position: 0 },
      { color: rgb(0xc9dccc), position: 0.55 },
      { color: rgb(0x8fb59b), position: 1 },
    ],
  },
};

/** W1's scrim — `rgba(16,32,22,0)→.6` from 46%. Screen 03's is `.5` from 48%. */
export const W1_SCRIM: Scrim = { rgb: 0x102016, from: 0.46, to: 0.6 };
