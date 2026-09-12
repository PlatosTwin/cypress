import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  CARD_CONTENT_TYPE,
  CARD_HEIGHT,
  CARD_WIDTH,
  escapeXML,
  TEXT_ON_PHOTO_WEB,
  treeCardSVG,
  truncate,
} from '../src/lib/ogCard.ts';
import { W1_HERO } from '../src/lib/gradients.ts';
import { treePageModel, type TreePageInput } from '../src/lib/treePage.ts';

/**
 * The OpenGraph card.
 *
 * §W1's caption is the requirement: the card is "rendered from the same three ingredients so the
 * group-chat preview and the page agree". That is a claim about a shared SOURCE, so the tests
 * below feed `treeCardSVG` the same `TreePageModel` the page renders and require the card to carry
 * what the page carries — rather than asserting that some text appears somewhere in an SVG, which
 * a second copy of the precedences would satisfy just as well.
 *
 * **What is NOT tested here, because it is not true:** that a social platform will render this.
 * The major ones do not accept `image/svg+xml` as an `og:image`; `src/lib/ogCard.ts` says so at
 * length and the pull request says so again. A test cannot make that false.
 */

const tokens = readFileSync(
  fileURLToPath(new URL('../src/styles/tokens.css', import.meta.url)),
  'utf8',
);

const lombard: TreePageInput = {
  idSpace: 'sf',
  uuid: 'eac6cce9-68bf-53c6-aa3c-44d26deb868d',
  status: 'alive',
  address: '2576 LOMBARD ST',
  neighborhoodName: 'Marina',
  cityName: 'San Francisco',
  speciesCommonName: 'Monterey Cypress',
  speciesScientificName: 'Cupressus macrocarpa',
  plantedYear: 1993,
  dbhCityCmMin: 65,
  dbhCityCmMax: 70,
  siteType: 'Sidewalk: Curb side : Cutout',
  externalRef: '13284',
  inventoryName: 'SF Public Works street tree inventory',
  inventoryURL: 'https://example.invalid/sf',
  inventorySnapshotOn: '2026-08-22',
  inventoryLicense: null,
};

describe('XML escaping', () => {
  it('escapes all five, including the apostrophe the attributes are quoted with', () => {
    assert.equal(escapeXML(`<a href='x' & "y">`), '&lt;a href=&apos;x&apos; &amp; &quot;y&quot;&gt;');
  });

  it('escapes the ampersand first, so an entity is not double-escaped into nonsense', () => {
    // `&` → `&amp;` has to run before `<` → `&lt;`, or the `&` of `&lt;` gets escaped again and
    // the output reads `&amp;lt;`. The specimen is `Data & export`, which is on this page's own
    // nav bar and is the string that would have found this.
    assert.equal(escapeXML('Data & export'), 'Data &amp; export');
    assert.equal(escapeXML('a < b & c'), 'a &lt; b &amp; c');
  });
});

describe('truncation', () => {
  it('leaves a string that fits', () => {
    assert.equal(truncate('Monterey Cypress', 30), 'Monterey Cypress');
    assert.equal(truncate('exactly ten', 11), 'exactly ten');
  });

  it('cuts to the budget, ellipsis included', () => {
    assert.equal(truncate('abcdefghij', 5), 'abcd…');
    assert.equal([...truncate('abcdefghij', 5)].length, 5);
  });

  it('never splits a surrogate pair, which would be invalid XML rather than short text', () => {
    // A lone surrogate is not a character and an XML parser refuses the whole document, so the
    // card would not fail to look right — it would fail to exist.
    const flowers = '🌲🌲🌲🌲🌲';
    const cut = truncate(flowers, 3);
    assert.equal([...cut].length, 3);
    assert.ok(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/.test(cut));
    assert.ok(!/(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(cut));
  });

  it('refuses a budget that cannot hold an ellipsis', () => {
    assert.throws(() => truncate('abc', 0), RangeError);
  });
});

describe('the card', () => {
  const model = treePageModel(lombard);
  const svg = treeCardSVG(model);

  it('is the size every crawler documents', () => {
    assert.equal(CARD_WIDTH, 1200);
    assert.equal(CARD_HEIGHT, 630);
    assert.ok(svg.startsWith('<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" '));
    assert.ok(svg.includes('viewBox="0 0 1200 630"'));
    assert.ok(svg.endsWith('</svg>'));
  });

  it('declares the content type an SVG document is served as', () => {
    assert.equal(CARD_CONTENT_TYPE, 'image/svg+xml; charset=utf-8');
  });

  it('says what the page says, because both read one model', () => {
    assert.ok(svg.includes('>Monterey Cypress<'), 'the H1');
    assert.ok(svg.includes('>2576 LOMBARD ST · SAN FRANCISCO<'), 'the eyebrow, uppercased');
    assert.ok(svg.includes('Cupressus macrocarpa · SF Public Works street tree inventory'));
    // The facts line carries the page's own rows, in the page's own order, with the page's own
    // formats — including the en dash and the `city record` bucket's value.
    assert.ok(svg.includes('Status  Alive'));
    assert.ok(svg.includes('Trunk · DBH  65–70 cm'));
    assert.ok(svg.includes('Planted  1993'));
  });

  it('carries the page’s description as its accessible name', () => {
    assert.ok(svg.includes(`aria-label="${escapeXML(model.description)}"`));
  });

  it('draws W1’s gradient, base first — SVG paints its LAST element on top', () => {
    const base = svg.indexOf('fill="url(#base)"');
    const firstRadial = svg.indexOf('fill="url(#r0)"');
    const scrim = svg.indexOf('fill="url(#scrim)"');
    assert.ok(base > 0 && firstRadial > base, 'the radials must be painted over the base');
    assert.ok(scrim > firstRadial, 'the scrim must be painted over the radials');
    // As many radial layers as the recipe has, and no more. A dropped layer is invisible in a
    // blurred gradient and would never be noticed by eye.
    assert.equal(
      (svg.match(/<radialGradient /g) ?? []).length,
      W1_HERO.radials.length,
      'the card lost or gained a radial layer relative to W1_HERO',
    );
  });

  it('gives each radial a farthest-corner radius in user space, not a bounding-box one', () => {
    // `objectBoundingBox` on a 1200×630 box turns a circle into an ellipse. The first radial sits
    // at 26% 50% of the card, so its farthest corner is (1200, 0) or (1200, 630) — 888 across and
    // 315 down, 941.19 — and 34% of that is 320.0. Computed by hand before the code was read.
    const cx = 0.26 * CARD_WIDTH;
    const cy = 0.5 * CARD_HEIGHT;
    const expected = 0.34 * Math.hypot(CARD_WIDTH - cx, CARD_HEIGHT - cy);
    assert.ok(svg.includes('gradientUnits="userSpaceOnUse"'));
    assert.ok(
      svg.includes(`cx="${cx.toFixed(2)}" cy="${cy.toFixed(2)}" r="${expected.toFixed(2)}"`),
      `the first radial is not at ${cx.toFixed(2)},${cy.toFixed(2)} r ${expected.toFixed(2)}`,
    );
  });

  it('uses the design system’s own ink for text on the hero', () => {
    // The one literal color in `ogCard.ts`, because an SVG document loads no stylesheet and cannot
    // read a custom property. It is checked against the generated token here so the two cannot
    // drift — which is the same bargain `tokens.css` itself is.
    const declared = /--color-text-on-photo-web:\s*(#[0-9A-Fa-f]{6});/.exec(tokens);
    assert.notEqual(declared, null, 'tokens.css no longer declares --color-text-on-photo-web');
    assert.equal(TEXT_ON_PHOTO_WEB.toUpperCase(), declared?.[1]?.toUpperCase());
    assert.ok(svg.includes(`fill="${TEXT_ON_PHOTO_WEB}"`));
  });

  it('leaves no unescaped markup character from the data in the output', () => {
    // A civic string carrying `&` or `<` would otherwise produce a document no parser accepts.
    const hostile = treeCardSVG(treePageModel({
      ...lombard,
      address: '1 <script>alert("x")</script> & Co. ST',
      speciesCommonName: "Quercus 'Ampersand & Co'",
    }));
    assert.ok(!hostile.includes('<script>'));
    assert.ok(!hostile.includes('alert("x")'));
    // Every `&` in the document opens a named entity, which is the check that catches a value
    // whose escaping was skipped rather than one whose escaping was wrong.
    for (const match of hostile.matchAll(/&(?!(amp|lt|gt|quot|apos);)/g)) {
      assert.fail(`an unescaped ampersand at index ${match.index}`);
    }
  });

  it('omits the eyebrow line entirely when the model has none', () => {
    const noWhere = treeCardSVG(treePageModel({
      ...lombard, address: null, cityName: null, neighborhoodName: null,
    }));
    // Three text elements, not four: the card draws an absence as an absence, the same way the
    // page does, rather than as an empty line that shifts the title.
    assert.equal((noWhere.match(/<text /g) ?? []).length, 3);
  });
});
