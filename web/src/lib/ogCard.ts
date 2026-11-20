/**
 * The OpenGraph card, drawn from the same ingredients as the page.
 *
 * §W1's caption is the requirement, verbatim: *"the OpenGraph image is rendered from the same
 * three ingredients so the group-chat preview and the page agree."* So this takes the model the
 * page renders — not a second query, not a second copy of the precedences — and lays the hero out
 * at card proportions. Change what the page says about a tree and the card says it too, because
 * there is one `TreePageModel` and both read it.
 *
 * ── It is an SVG, and that is a real limitation, stated ──────────────────────────────────────
 *
 * **Facebook, X/Twitter, LinkedIn, Slack, Discord and Telegram do not render `image/svg+xml` as an
 * `og:image`.** A crawler that cannot decode the type shows the card with no image at all; it does
 * not show a broken one, and it does not fall back to something wrong. So this tag is correct
 * where it is honored (an `<img>`, a browser opening the endpoint, a renderer that accepts SVG)
 * and inert everywhere else — which is worth having and is NOT the group-chat preview §W1 asks
 * for.
 *
 * The reason it stops here is `web/`'s zero-extra-runtime-dependency discipline. Rasterizing means
 * either a headless browser or an image library, and **text is the part that cannot be faked**: a
 * PNG encoder is 80 lines of `node:zlib` and would happily paint this gradient, but nothing in the
 * standard library can set a glyph, and a card carrying the gradient without the tree's name is a
 * colored rectangle. Choosing a rasterizer is a dependency decision with an owner, not an
 * implementation detail, so it is written up rather than taken here.
 *
 * ── Two things this deliberately does not do ─────────────────────────────────────────────────
 *
 * **No web fonts.** An SVG served as a document loads no stylesheet from this app, and a
 * `@font-face` pointing at a font file would be a second network dependency inside an image. The
 * families are named in the same order `tokens.css` names them, so a renderer that has
 * `Source Serif 4` installed uses it and everything else falls back to the generic — which is what
 * the generic exists for.
 *
 * **No wrapping.** SVG has no line-breaking, and implementing one without font metrics means
 * guessing at glyph widths. Text is truncated at a character budget per line instead, with an
 * ellipsis, which is a visibly approximate rule rather than an invisible one: a title that is cut
 * short looks cut short.
 */
import { W1_HERO, W1_SCRIM, type GradientRecipe, type Scrim } from './gradients.ts';
import type { TreePageModel } from './treePage.ts';

/** The size every social crawler documents as the one it wants. */
export const CARD_WIDTH = 1200;
export const CARD_HEIGHT = 630;

export const CARD_CONTENT_TYPE = 'image/svg+xml; charset=utf-8';

/** XML text escaping. Five characters, and `'` is included because attributes are single-quoted. */
export function escapeXML(text: string): string {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

/**
 * `text`, or its first `budget - 1` characters and an ellipsis.
 *
 * Characters and not bytes, iterated as code points so an emoji or an accented letter is one unit
 * and a surrogate pair is never split in half — splitting one produces a lone surrogate, which is
 * not valid XML and would make the whole card fail to parse rather than look short.
 */
export function truncate(text: string, budget: number): string {
  if (budget <= 0) throw new RangeError(`a character budget must be positive, got ${budget}`);
  const characters = [...text];
  if (characters.length <= budget) return text;
  return `${characters.slice(0, budget - 1).join('')}…`;
}

/**
 * The gradient, flattened into the SVG elements that draw it.
 *
 * CSS and SVG both have radial gradients and they do not have the same defaults, so this is a
 * translation rather than a copy — and the translation is exactly what
 * `CypressGradientField.farthestCorner` already had to work out for SwiftUI:
 *
 * - CSS `radial-gradient(circle at X% Y%, C 0%, transparent N%)` with no size keyword means
 *   `farthest-corner`, so the radius is `N` × the distance from the center to the furthest corner
 *   of the box. SVG's `<radialGradient>` has no such keyword; `r` is given in the coordinate
 *   system chosen by `gradientUnits`. `userSpaceOnUse` and an explicit radius in pixels is the
 *   only spelling that reproduces the CSS, because `objectBoundingBox` would scale the circle into
 *   an ellipse on a 1200×630 box.
 * - Layer order flips. CSS paints the FIRST background layer on top; SVG paints the LAST element
 *   on top. So the layers are emitted in reverse, base first — which is the SwiftUI order, and is
 *   why this is the second place in the codebase to write that sentence down.
 */
function gradientDefs(recipe: GradientRecipe, scrim: Scrim, width: number, height: number): {
  defs: string;
  rects: string;
} {
  const defs: string[] = [];
  const rects: string[] = [];

  const baseStops = recipe.base.stops
    .map((stop) => {
      const color = `#${stop.color.rgb.toString(16).padStart(6, '0')}`;
      return `<stop offset="${stop.position}" stop-color="${color}"/>`;
    })
    .join('');
  // `linear-gradient(180deg, …)` runs top to bottom. SVG's default x1/y1/x2/y2 runs left to right,
  // so the vector is stated rather than defaulted.
  defs.push(
    `<linearGradient id="base" x1="0" y1="0" x2="0" y2="1">${baseStops}</linearGradient>`,
  );
  rects.push(`<rect width="${width}" height="${height}" fill="url(#base)"/>`);

  recipe.radials.forEach((stop, index) => {
    const cx = stop.x * width;
    const cy = stop.y * height;
    const corners: readonly (readonly [number, number])[] = [
      [0, 0], [width, 0], [0, height], [width, height],
    ];
    const farthest = Math.max(...corners.map(([x, y]) => Math.hypot(x - cx, y - cy)));
    const radius = Math.max(1, stop.extent * farthest);
    const color = `#${stop.color.rgb.toString(16).padStart(6, '0')}`;
    defs.push(
      `<radialGradient id="r${index}" gradientUnits="userSpaceOnUse" `
        + `cx="${cx.toFixed(2)}" cy="${cy.toFixed(2)}" r="${radius.toFixed(2)}">`
        + `<stop offset="0" stop-color="${color}" stop-opacity="${stop.color.alpha}"/>`
        + `<stop offset="1" stop-color="${color}" stop-opacity="0"/>`
        + `</radialGradient>`,
    );
    rects.push(`<rect width="${width}" height="${height}" fill="url(#r${index})"/>`);
  });

  const scrimColor = `#${scrim.rgb.toString(16).padStart(6, '0')}`;
  defs.push(
    `<linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">`
      + `<stop offset="${scrim.from}" stop-color="${scrimColor}" stop-opacity="0"/>`
      + `<stop offset="1" stop-color="${scrimColor}" stop-opacity="${scrim.to}"/>`
      + `</linearGradient>`,
  );
  rects.push(`<rect width="${width}" height="${height}" fill="url(#scrim)"/>`);

  return { defs: defs.join(''), rects: rects.join('') };
}

/**
 * The card for one tree.
 *
 * The text block sits on the same baseline logic as the page's hero — eyebrow, title, subtitle,
 * bottom-aligned over the scrim — and adds the one thing a preview needs that the page does not:
 * the fact rows, which are what makes the card legible as a record rather than as a photograph.
 */
export function treeCardSVG(model: TreePageModel): string {
  const { defs, rects } = gradientDefs(W1_HERO, W1_SCRIM, CARD_WIDTH, CARD_HEIGHT);
  // The one color in this file that is not in the recipe: the ink the hero text is set in. It is
  // `--color-text-on-photo-web`, whose value is `CypressColor.textOnPhotoWeb`, and it is inlined
  // as a literal because an SVG served as its own document cannot read a custom property from a
  // stylesheet it never loads. `web/test/ogCard.test.ts` reads the value out of `tokens.css`.
  const ink = TEXT_ON_PHOTO_WEB;
  const serif = '&apos;Source Serif 4&apos;, Georgia, serif';
  const sans = '&apos;Alegreya Sans&apos;, system-ui, sans-serif';
  const mono = '&apos;Spline Sans Mono&apos;, ui-monospace, monospace';

  const lines: string[] = [];
  const left = 72;
  if (model.eyebrow !== null) {
    lines.push(
      `<text x="${left}" y="392" font-family="${sans}" font-size="24" font-weight="700" `
        + `letter-spacing="2.4" fill="${ink}" fill-opacity="0.85">`
        + `${escapeXML(truncate(model.eyebrow.toUpperCase(), 58))}</text>`,
    );
  }
  lines.push(
    `<text x="${left}" y="462" font-family="${serif}" font-size="64" font-weight="600" `
      + `fill="${ink}">${escapeXML(truncate(model.title, 30))}</text>`,
  );
  const subtitle = model.subtitle.map((part) => part.text).join(' · ');
  if (subtitle.length > 0) {
    lines.push(
      `<text x="${left}" y="504" font-family="${serif}" font-size="27" font-style="italic" `
        + `fill="${ink}" fill-opacity="0.9">${escapeXML(truncate(subtitle, 68))}</text>`,
    );
  }
  const facts = model.facts
    .map((row) => `${row.label}  ${row.value}`)
    .join('     ');
  if (facts.length > 0) {
    lines.push(
      `<text x="${left}" y="562" font-family="${mono}" font-size="21" fill="${ink}" `
        + `fill-opacity="0.85">${escapeXML(truncate(facts, 86))}</text>`,
    );
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${CARD_WIDTH}" height="${CARD_HEIGHT}" `
    + `viewBox="0 0 ${CARD_WIDTH} ${CARD_HEIGHT}" role="img" `
    + `aria-label="${escapeXML(model.description)}">`
    + `<defs>${defs}</defs>${rects}${lines.join('')}</svg>`;
}

/**
 * `CypressColor.textOnPhotoWeb` — `text.onPhoto` for W1, and `lightOnly`, so it has one value in
 * both schemes and a card that is always drawn over the light hero is always right to use it.
 *
 * The one literal color in this module, for the reason given at the call site. It is not a second
 * source of truth: `ogCard.test.ts` reads `--color-text-on-photo-web` out of the generated
 * `tokens.css` and fails if this stops matching it.
 */
export const TEXT_ON_PHOTO_WEB = '#EFF5EA';
