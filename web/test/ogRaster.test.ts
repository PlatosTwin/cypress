import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Resvg } from '@resvg/resvg-js';

import {
  CARD_FONT_FACES,
  CARD_PNG_CONTENT_TYPE,
  FONT_LICENSE,
  MissingCardFonts,
  cardFontDir,
  cardFontPaths,
  treeCardPNG,
  unexpectedFontFiles,
} from '../src/lib/ogRaster.ts';
import { CARD_HEIGHT, CARD_WIDTH, TEXT_ON_PHOTO_WEB, treeCardSVG } from '../src/lib/ogCard.ts';
import { treePageModel, type TreePageInput } from '../src/lib/treePage.ts';
import { repositoryRoot } from './support/sources.ts';
import {
  band,
  countNear,
  decodePNG,
  distinctColors,
  hasPNGSignature,
  pixelAt,
  pngHeader,
  rightmostNear,
  sharpEdgeCount,
  type Rect,
} from './support/png.ts';

/**
 * The rasterized OpenGraph card.
 *
 * **What this file is defending against is a card with nothing on it.** `ogRaster.ts` renders with
 * `loadSystemFonts: false`, which is the setting that makes the card look the same on a laptop, on
 * `ubuntu-latest` and in a Debian container — and it is also the setting under which resvg draws
 * *absolutely nothing* for a family it cannot resolve. No error, no fallback, no warning: a 1200×630
 * gradient with no words on it, served with a `200`, indistinguishable at every level a normal test
 * looks at from a card that works. `CLAUDE.md` names that class first and this repository has
 * shipped it more than once.
 *
 * So nothing below asserts that a function returned a buffer. Every claim is read out of the
 * encoded PNG — its signature, its IHDR, its unfiltered pixels — by `test/support/png.ts`, which
 * decodes the bytes rather than asking the renderer what it thinks it drew.
 *
 * **The measure that finds type is `sharpEdgeCount`, and the obvious measure does not work.**
 * Three of the card's four runs are drawn at `fill-opacity` below 1, so their glyphs are the ink
 * color blended with the gradient; counting ink-colored pixels finds none of them and finds the
 * pale corner of the gradient instead. A glyph edge is a step and `W1_HERO` is smooth everywhere,
 * so counting steps separates them by three orders of magnitude. Measured on the real card before
 * the thresholds below were chosen: 0 steps across a 1080×300 window of pure gradient, and between
 * 1,700 and 4,800 in each of the four text bands.
 */

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

const root = repositoryRoot();
const webFonts = join(root, 'web', 'fonts');
const sourceFonts = join(root, 'Cypress', 'Resources', 'Fonts');

/** Every render in this file names its font directory, so none of them depends on the cwd. */
function render(input: TreePageInput, fontDir: string = webFonts): Buffer {
  return treeCardPNG(treePageModel(input), { fontDir });
}

const sha256 = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');

/**
 * The four bands the card sets type in, and one window that is only gradient.
 *
 * Read off `ogCard.ts`'s own baselines — the eyebrow at y 392, the title at 462, the subtitle at
 * 504 and the fact row at 562 — with a band above each baseline deep enough to hold its ascenders
 * and shallow enough not to reach its neighbor.
 */
const BANDS = {
  eyebrow: { x: 60, y: 362, width: 1080, height: 36 },
  title: { x: 60, y: 404, width: 1080, height: 66 },
  subtitle: { x: 60, y: 478, width: 1080, height: 36 },
  facts: { x: 60, y: 540, width: 1080, height: 32 },
} as const satisfies Record<string, Rect>;

/** A window with no type in it at all: above the eyebrow, below the top edge. */
const GRADIENT_ONLY: Rect = { x: 60, y: 40, width: 1080, height: 300 };

const INK: readonly [number, number, number] = [
  Number.parseInt(TEXT_ON_PHOTO_WEB.slice(1, 3), 16),
  Number.parseInt(TEXT_ON_PHOTO_WEB.slice(3, 5), 16),
  Number.parseInt(TEXT_ON_PHOTO_WEB.slice(5, 7), 16),
];

// ── The instrument, before any reading taken with it ───────────────────────────────────────────

describe('the PNG reader this file measures with', () => {
  it('reads a specimen whose answer was known before the reader saw it', () => {
    // Four pixels by two, left half `#FF0000`, right half `#0000FF`, on a pixel boundary so there
    // is nothing for the rasterizer to antialias. The answer, written down first: 4×2, eight
    // bit, color type 6, not interlaced; (0,0) is opaque red and (3,0) is opaque blue; two
    // distinct colors; and exactly two horizontal steps, one per row, at x = 2.
    const specimen = '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="2" '
      + 'viewBox="0 0 4 2"><rect x="0" y="0" width="2" height="2" fill="#FF0000"/>'
      + '<rect x="2" y="0" width="2" height="2" fill="#0000FF"/></svg>';
    const png = new Resvg(specimen, { fitTo: { mode: 'original' } }).render().asPng();

    assert.ok(hasPNGSignature(png));
    const header = pngHeader(png);
    assert.deepEqual(
      { ...header },
      { width: 4, height: 2, bitDepth: 8, colorType: 6, interlace: 0 },
    );
    const image = decodePNG(png);
    assert.deepEqual([...pixelAt(image, 0, 0)], [255, 0, 0, 255]);
    assert.deepEqual([...pixelAt(image, 3, 0)], [0, 0, 255, 255]);
    const whole: Rect = { x: 0, y: 0, width: 4, height: 2 };
    assert.equal(distinctColors(image, whole), 2);
    assert.equal(sharpEdgeCount(image, whole, 8), 2);
  });

  it('reports a flat fill as having no steps in it, which is the false answer to rule out', () => {
    // The control for the measure above. If `sharpEdgeCount` answered nonzero on a solid
    // rectangle, every "there is type here" assertion below would be satisfied by a blank card.
    const flat = '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="10" '
      + 'viewBox="0 0 40 10"><rect width="40" height="10" fill="#2B4A2F"/></svg>';
    const image = decodePNG(new Resvg(flat, { fitTo: { mode: 'original' } }).render().asPng());
    assert.equal(sharpEdgeCount(image, { x: 0, y: 0, width: 40, height: 10 }, 8), 0);
    assert.equal(distinctColors(image, { x: 0, y: 0, width: 40, height: 10 }), 1);
  });

  it('unfilters to the same bytes the renderer says it drew', () => {
    // Two independent paths to one answer: resvg's own RGBA buffer, and this file's inflate plus
    // unfilter of the PNG it encoded. A wrong Paeth predictor, an off-by-one stride or a missed
    // filter type would disagree here and nowhere else — every assertion below would still pass,
    // on pixels that were not the card's.
    const rendered = new Resvg(treeCardSVG(treePageModel(lombard)), {
      fitTo: { mode: 'original' },
      font: { loadSystemFonts: false, fontFiles: [...cardFontPaths(webFonts)] },
    }).render();
    const decoded = decodePNG(rendered.asPng());
    assert.equal(decoded.pixels.length, rendered.pixels.length);
    assert.equal(sha256(decoded.pixels), sha256(rendered.pixels));
  });
});

// ── The artifact ───────────────────────────────────────────────────────────────────────────────

describe('the card is a PNG, at the size the page declares', () => {
  const png = render(lombard);

  it('is served as image/png, which takes no parameters', () => {
    assert.equal(CARD_PNG_CONTENT_TYPE, 'image/png');
  });

  it('starts with the eight bytes that make a file a PNG', () => {
    // The magic bytes, not the content-type header — a header is a claim and these are the file.
    assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  });

  it('declares 1200×630 in its own IHDR, which is what the meta tags promise', () => {
    const header = pngHeader(png);
    assert.equal(header.width, CARD_WIDTH);
    assert.equal(header.height, CARD_HEIGHT);
    assert.equal(header.bitDepth, 8);
    assert.equal(header.colorType, 6);
    assert.equal(header.interlace, 0);
  });
});

describe('it is not a blank canvas', () => {
  const image = decodePNG(render(lombard));

  it('is a gradient and not one flat color', () => {
    // Measured: 17,232 distinct RGB triples on the real card. A single-color canvas answers 1 and
    // a two-stop ramp with no radials would answer in the low hundreds.
    assert.ok(
      distinctColors(image, { x: 0, y: 0, width: CARD_WIDTH, height: CARD_HEIGHT }) > 1000,
      'the card is close to flat — the gradient did not paint',
    );
    // And the ramp runs the way `W1_HERO` runs: light at the top, dark under the scrim.
    const [, topGreen] = pixelAt(image, 600, 4);
    const [, bottomGreen] = pixelAt(image, 600, CARD_HEIGHT - 4);
    assert.ok(topGreen > bottomGreen + 60, `the hero is not lighter at the top (${topGreen} vs ${bottomGreen})`);
  });

  it('has type in all four of the bands the card sets type in', () => {
    for (const [name, rect] of Object.entries(BANDS)) {
      const edges = sharpEdgeCount(image, rect, 8);
      assert.ok(
        edges > 500,
        `the ${name} band has ${edges} glyph edges in it. Under 500 means the run did not `
          + `rasterize — the family resolved to nothing, which resvg does in silence.`,
      );
    }
  });

  it('and no type where there is none, so the measure is not counting the gradient', () => {
    // The control that makes the four assertions above mean something. Measured at 0 on the real
    // card; the allowance is for a renderer that dithers a ramp differently, not for a headline.
    const edges = sharpEdgeCount(image, GRADIENT_ONLY, 8);
    assert.ok(edges <= 10, `${edges} steps in a window that holds only gradient`);
  });

  it('sets the title in the design system’s own ink, at full opacity', () => {
    // The title is the one run drawn at `fill-opacity` 1, so it is the one whose pixels are the
    // token color itself. Measured: 3,505 within a radius of 10, and 0 anywhere in the gradient
    // window at the same radius.
    assert.ok(countNear(image, BANDS.title, INK, 10) > 1500, 'the title is not set in the ink token');
    assert.equal(countNear(image, GRADIENT_ONLY, INK, 10), 0);
  });
});

describe('the card says what the model says', () => {
  it('is deterministic: the same model twice is the same bytes', () => {
    // Not a triviality — it is what makes every comparison below a statement about the input.
    assert.equal(sha256(render(lombard)), sha256(render(lombard)));
  });

  it('rasterizes the SVG `ogCard.ts` draws, rather than drawing the card a second time', () => {
    // §W1's caption asks that the preview and the page agree, and the way two renderings agree is
    // by being one rendering. This is the assertion that there is no second layout to drift.
    const direct = new Resvg(treeCardSVG(treePageModel(lombard)), {
      fitTo: { mode: 'original' },
      font: {
        loadSystemFonts: false,
        fontFiles: [...cardFontPaths(webFonts)],
        defaultFontFamily: 'Source Serif 4',
      },
      logLevel: 'error',
    }).render().asPng();
    assert.equal(sha256(render(lombard)), sha256(direct));
  });

  it('a different species changes the title band and leaves the address band alone', () => {
    // The two inputs differ in one field, and the field feeds the title and not the eyebrow. A
    // card that painted the same pixels either way would be a card that is not reading the model.
    const other = { ...lombard, speciesCommonName: 'Coast Live Oak' };
    const a = decodePNG(render(lombard));
    const b = decodePNG(render(other));
    assert.notEqual(
      sha256(band(a, BANDS.title)), sha256(band(b, BANDS.title)),
      'two different species rasterized to the same title',
    );
    assert.equal(
      sha256(band(a, BANDS.eyebrow)), sha256(band(b, BANDS.eyebrow)),
      'the species leaked into the eyebrow, which is the address and the city',
    );
  });

  it('does not run the title off the edge of the card', () => {
    // `truncate` caps the title at 30 characters and the card is 1200 wide with a 72px margin.
    // The claim is about the pixels, not about the budget: the rightmost ink in the title band
    // stays inside the mirror of that margin.
    const long = {
      ...lombard,
      speciesCommonName: 'Brisbane Box Lophostemon Confertus Of Unusual Length',
    };
    const image = decodePNG(render(long));
    const rightmost = rightmostNear(image, BANDS.title, INK, 20);
    assert.ok(rightmost > 0, 'the long title did not rasterize at all');
    assert.ok(
      rightmost <= CARD_WIDTH - 60,
      `the title reaches x=${rightmost} on a ${CARD_WIDTH}-wide card`,
    );
  });
});

// ── The fonts, which are the part that can silently vanish ─────────────────────────────────────

describe('the fonts the card is rasterized with', () => {
  it('web/fonts holds the four faces and their license, and nothing else', () => {
    assert.deepEqual(
      readdirSync(webFonts).sort(),
      [...CARD_FONT_FACES, FONT_LICENSE].sort(),
      'web/fonts is not the set `CARD_FONT_FACES` names. Run `npm run fonts` in web/.',
    );
    assert.deepEqual([...unexpectedFontFiles(webFonts)], []);
  });

  it('each copy is byte-identical to the face in Cypress/Resources/Fonts', () => {
    // The tokens.css bargain, applied to binaries: generated and checked in, with the staleness
    // that buys refused by a test. By sha256 and not by size — a re-hinted face is the same
    // length and different glyphs.
    for (const name of [...CARD_FONT_FACES, FONT_LICENSE]) {
      assert.equal(
        sha256(readFileSync(join(webFonts, name))),
        sha256(readFileSync(join(sourceFonts, name))),
        `web/fonts/${name} is not Cypress/Resources/Fonts/${name}. Run \`npm run fonts\` in web/.`,
      );
    }
  });

  it('every face on the list is one the card actually sets', () => {
    // The list could rot into "fonts somebody once copied". Each face is swapped, in turn, for
    // another face's bytes under its own name — the family it declares then no longer resolves —
    // and the card has to come out different. A face nothing asks for would change nothing.
    const reference = sha256(render(lombard));
    for (const face of CARD_FONT_FACES) {
      const dir = mkdtempSync(join(tmpdir(), 'cypress-card-fonts-'));
      for (const name of CARD_FONT_FACES) copyFileSync(join(webFonts, name), join(dir, name));
      const standIn = CARD_FONT_FACES.find((name) => name !== face);
      assert.notEqual(standIn, undefined);
      writeFileSync(join(dir, face), readFileSync(join(webFonts, standIn ?? '')));
      assert.notEqual(
        sha256(render(lombard, dir)), reference,
        `${face} is in CARD_FONT_FACES and the card renders identically without it, so it is `
          + `either unused or something else is standing in for it`,
      );
    }
  });

  it('a face that is missing is a throw that names it, not a card with no words on it', () => {
    const dir = mkdtempSync(join(tmpdir(), 'cypress-card-fonts-'));
    for (const name of CARD_FONT_FACES) copyFileSync(join(webFonts, name), join(dir, name));
    const [first] = CARD_FONT_FACES;
    writeFileSync(join(dir, first), '');
    assert.throws(
      () => cardFontPaths(dir),
      (error: unknown) => {
        assert.ok(error instanceof MissingCardFonts);
        assert.deepEqual([...error.missing], [first]);
        assert.equal(error.directory, dir);
        return true;
      },
      'an empty face has to refuse — resvg renders a family it cannot resolve as nothing at all',
    );

    const empty = mkdtempSync(join(tmpdir(), 'cypress-card-fonts-'));
    assert.throws(() => cardFontPaths(empty), MissingCardFonts);
  });

  it('resolves to <cwd>/fonts, and lets a host say otherwise', () => {
    assert.equal(cardFontDir({}), join(process.cwd(), 'fonts'));
    assert.equal(cardFontDir({ CYPRESS_CARD_FONT_DIR: '/srv/faces' }), '/srv/faces');
    // Blank is not an answer: an unset variable and one set to nothing mean the same thing to a
    // shell, and treating "" as a directory resolves every face against the filesystem root.
    assert.equal(cardFontDir({ CYPRESS_CARD_FONT_DIR: '  ' }), join(process.cwd(), 'fonts'));
  });

  it('the Dockerfile carries web/fonts into the image that runs', () => {
    // The suite above proves the faces are on this disk. The deployment reads them from `/app/fonts`
    // in a container built from a context of `web/`, and a forgotten COPY is invisible to every
    // other assertion in this file — it is a 500 at the first share, in production.
    const dockerfile = readFileSync(
      fileURLToPath(new URL('../Dockerfile', import.meta.url)),
      'utf8',
    );
    assert.match(dockerfile, /^COPY fonts \.\/fonts$/m, 'the build stage does not copy web/fonts');
    assert.match(
      dockerfile,
      /^COPY --from=build \/app\/fonts \.\/fonts$/m,
      'the runtime stage does not copy the fonts out of the build stage',
    );
    // And the cwd `cardFontDir()` resolves against is that image's WORKDIR.
    assert.match(dockerfile, /^WORKDIR \/app$/m);
  });
});

// ── What the page tells a crawler it is about to fetch ─────────────────────────────────────────

describe('the page and the card agree about what the card is', () => {
  const page = readFileSync(
    fileURLToPath(new URL('../src/pages/[idSpace]/tree/[uuid].astro', import.meta.url)),
    'utf8',
  );
  const shell = readFileSync(
    fileURLToPath(new URL('../src/layouts/Base.astro', import.meta.url)),
    'utf8',
  );

  it('W1 points og:image at the raster, not at the vector', () => {
    // The whole reason this round exists: Facebook, X, LinkedIn, Slack, Discord and Telegram do
    // not decode `image/svg+xml` as an `og:image`, so the tag was inert in the one place §W1's
    // caption asks for.
    assert.match(page, /const cardPath = `\$\{model\.path\}\/og\.png`;/);
    assert.match(page, /type: CARD_PNG_CONTENT_TYPE,/);
    assert.match(page, /width: CARD_WIDTH,/);
    assert.match(page, /height: CARD_HEIGHT,/);
  });

  it('the shell publishes the width and the height, which it never used to', () => {
    // `og:image` and `og:image:type` were the whole set. A consumer that lays out before it
    // fetches had nothing to lay out from.
    assert.match(shell, /<meta property="og:image:width" content=\{String\(openGraph\.image\.width\)\} \/>/);
    assert.match(shell, /<meta property="og:image:height" content=\{String\(openGraph\.image\.height\)\} \/>/);
    assert.match(shell, /<meta property="og:image:type" content=\{openGraph\.image\.type\} \/>/);
  });

  it('the SVG endpoint is still there, because it is the drawing the PNG is made of', () => {
    const endpoints = readdirSync(
      fileURLToPath(new URL('../src/pages/[idSpace]/tree/[uuid]', import.meta.url)),
    ).sort();
    assert.deepEqual(endpoints, ['og.png.ts', 'og.svg.ts']);
  });
});
