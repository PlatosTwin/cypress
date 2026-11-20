/**
 * The OpenGraph card, rasterized — the half of §W1's caption an SVG could not deliver.
 *
 * `src/lib/ogCard.ts` draws the card and says, at length, why serving it as `image/svg+xml` is
 * correct where it is honored and inert everywhere it matters: Facebook, X, LinkedIn, Slack,
 * Discord, iMessage and Telegram do not decode an SVG `og:image`, and a crawler that cannot decode
 * the type shows no image at all. §W1's caption asks for a group-chat preview. This module is the
 * owner's answer to that, and it is a **dependency decision**, which is why it is one module with
 * its own file rather than four lines inside `ogCard.ts`.
 *
 * ── The card is not drawn twice ──────────────────────────────────────────────────────────────
 *
 * `treeCardPNG` rasterizes the string `treeCardSVG` returns. It does not re-lay-out the card, it
 * does not re-read the model, and there is no second copy of the eyebrow's letter-spacing or the
 * title's budget. That is the whole point of the arrangement: the caption's requirement is that
 * the preview and the page agree, and the way two renderings agree is by being one rendering.
 * `test/ogRaster.test.ts` asserts the PNG is a raster OF that SVG rather than of some other one.
 *
 * ── The dependency, and what was rejected ────────────────────────────────────────────────────
 *
 * **`@resvg/resvg-js`**, pinned exactly. It is a prebuilt N-API binding to `resvg`, the Rust SVG
 * renderer: 3.4 MB installed on one platform, one transitive package (its own platform binary),
 * no system libraries, and — the property that decided it — **it rasterizes text from font files
 * you hand it**, with `loadSystemFonts: false`, so what it draws does not depend on what happens
 * to be installed on the machine drawing it.
 *
 * - **`sharp`** renders SVG through libvips' librsvg, which resolves text through *fontconfig*.
 *   The image would need a fontconfig setup and system fonts, and the card's typography would be
 *   whatever the container happened to have. It also pulls 25 optional platform packages and a
 *   separate libvips package per platform, for an image pipeline this app has no other use for.
 * - **`puppeteer` / `playwright`** rasterize by running Chromium. That is a browser download, a
 *   process per render and several hundred megabytes in an image whose whole job is to answer
 *   reads from a SQLite file. Rejected on size before correctness.
 * - **`satori`** composes an SVG from JSX. The card already IS an SVG; satori would replace the
 *   drawing, not rasterize it, and would still need a rasterizer after it.
 * - **`canvas` / `@napi-rs/canvas`** would mean re-drawing the card imperatively against a 2D
 *   context — a second copy of the layout, diverging from the SVG the moment either is edited.
 *   That is the exact failure `treeCardPNG` is shaped to avoid.
 * - **`node:zlib` and no dependency at all.** A PNG encoder is 80 lines and would paint the
 *   gradient happily. Nothing in the standard library can set a glyph, and a card carrying the
 *   gradient without the tree's name is a colored rectangle. `ogCard.ts` said so; it is still true.
 *
 * ── Fonts are files, and the files are in this directory ─────────────────────────────────────
 *
 * resvg 2.6.2 takes fonts as **paths on disk** — `fontFiles` and `fontDirs`, no buffer form. The
 * image is built from a context of `web/` (`docker build … web`), so the faces have to live under
 * `web/`. They do, in `web/fonts/`, copied from `Cypress/Resources/Fonts/` by
 * `scripts/export-card-fonts.mjs` and checked byte-for-byte against their originals by
 * `test/ogRaster.test.ts` — the same generated-and-checked-in bargain `src/styles/tokens.css` is,
 * for the same reason and with the same staleness guard.
 *
 * **A missing face is a throw, not a blank card.** With `loadSystemFonts: false` resvg draws
 * *nothing* for a family it cannot resolve: no error, no fallback, a gradient with no words on it.
 * That is precisely the shape of failure this repository keeps shipping, so the font directory is
 * checked before a render is attempted and the failure names the directory and the files.
 */
import { Resvg } from '@resvg/resvg-js';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { CARD_HEIGHT, CARD_WIDTH, treeCardSVG } from './ogCard.ts';
import type { TreePageModel } from './treePage.ts';

/** What a PNG is served as. No parameters: `image/png` takes none, unlike the SVG's charset. */
export const CARD_PNG_CONTENT_TYPE = 'image/png';

/**
 * The four faces `treeCardSVG` sets, and nothing else.
 *
 * `ogCard.ts` asks for the sans at weight 700 (the eyebrow), the serif at 600 (the title), the
 * serif italic (the subtitle) and the mono at regular (the fact row). The other nine faces in
 * `Cypress/Resources/Fonts/` would be 1.8 MB of glyphs in the image that nothing asks for.
 *
 * This is the list `scripts/export-card-fonts.mjs` copies and `test/ogRaster.test.ts` checks, so
 * there is one home for it. The test also renders the card with each face withheld in turn and
 * requires the output to change, which is what keeps this from becoming a list of files the card
 * does not actually use.
 */
export const CARD_FONT_FACES = [
  'AlegreyaSans-Bold.ttf',
  'SourceSerif4-SemiBold.ttf',
  'SourceSerif4-Italic.ttf',
  'SplineSansMono-Regular.ttf',
] as const;

/**
 * Where the faces are, at run time.
 *
 * `<cwd>/fonts`, and the three ways this process is started all put the cwd in the same place: an
 * `npm` script runs with the cwd at `web/` (dev, start, test), and the container's `WORKDIR` is
 * `/app` with `CMD ["node", "./dist/server/entry.mjs"]`. Deliberately NOT resolved from
 * `import.meta.url`: this module is bundled into `dist/server/chunks/` by the Astro build and the
 * chunk's own depth is not something to build a file path on.
 *
 * `CYPRESS_CARD_FONT_DIR` overrides it, for a host that starts the entry point from somewhere
 * else. It is an override and not a requirement — unlike `CYPRESS_PACK_DIR`, which has no default
 * because packs are deployment data, these files ship inside the image.
 */
export function cardFontDir(env: NodeJS.ProcessEnv = process.env): string {
  const override = env['CYPRESS_CARD_FONT_DIR'];
  if (override !== undefined && override.trim().length > 0) return override.trim();
  return join(process.cwd(), 'fonts');
}

/** What `verifyCardFonts` found, when it did not find four usable faces. */
export class MissingCardFonts extends Error {
  readonly directory: string;
  readonly missing: readonly string[];

  constructor(directory: string, missing: readonly string[]) {
    super(
      `the OpenGraph card cannot be rasterized: ${missing.join(', ')} `
        + `${missing.length === 1 ? 'is' : 'are'} missing or empty in ${directory}. `
        + `resvg draws nothing at all for a family it cannot resolve, so this refuses rather than `
        + `serving a gradient with no words on it. Run \`npm run fonts\` in web/, and check that `
        + `the Dockerfile still copies web/fonts into the runtime stage.`,
    );
    this.name = 'MissingCardFonts';
    this.directory = directory;
    this.missing = missing;
  }
}

/**
 * The absolute paths of the four faces, or a throw naming the ones that are not there.
 *
 * Non-empty as well as present: a zero-byte file is a truncated copy or a failed download, and it
 * resolves to no family just as an absent one does while passing every existence check.
 */
export function cardFontPaths(directory: string = cardFontDir()): readonly string[] {
  const missing: string[] = [];
  const paths: string[] = [];
  for (const face of CARD_FONT_FACES) {
    const path = join(directory, face);
    try {
      if (statSync(path).size > 0) paths.push(path);
      else missing.push(face);
    } catch {
      missing.push(face);
    }
  }
  if (missing.length > 0) throw new MissingCardFonts(directory, missing);
  return paths;
}

/**
 * The card for one tree, as PNG bytes.
 *
 * `fitTo: { mode: 'original' }` — the SVG states `width="1200" height="630"`, so the raster is
 * that size because the drawing says so rather than because this function repeats the numbers.
 * It is asserted against `CARD_WIDTH`/`CARD_HEIGHT` afterwards anyway: a renderer that silently
 * produced some other size would produce a card every crawler crops differently, and the assertion
 * costs two comparisons.
 */
export function treeCardPNG(
  model: TreePageModel,
  options: { readonly fontDir?: string } = {},
): Buffer {
  const fontFiles = cardFontPaths(options.fontDir ?? cardFontDir());
  const rendered = new Resvg(treeCardSVG(model), {
    fitTo: { mode: 'original' },
    font: {
      // The whole reason this renderer was chosen. What the card looks like is a property of the
      // four files above and of nothing installed on the host.
      loadSystemFonts: false,
      fontFiles: [...fontFiles],
      // Named so that a family the SVG asks for and these files do not provide falls back to the
      // card's own serif rather than to nothing. It is a safety net under a case the test makes
      // impossible; it is not the mechanism.
      defaultFontFamily: 'Source Serif 4',
    },
    logLevel: 'error',
  }).render();

  if (rendered.width !== CARD_WIDTH || rendered.height !== CARD_HEIGHT) {
    throw new Error(
      `the rasterizer produced ${rendered.width}×${rendered.height}, not `
        + `${CARD_WIDTH}×${CARD_HEIGHT}. The page's og:image:width and og:image:height declare the `
        + `latter, and a crawler believes the tags.`,
    );
  }
  return rendered.asPng();
}

/**
 * The files in `directory` that are not one of the four faces or their license.
 *
 * Used by the export script and by the test. An orphan face ships in every image, is never asked
 * for, and reads to the next person as if the card sets it.
 */
export function unexpectedFontFiles(directory: string): readonly string[] {
  const expected = new Set<string>([...CARD_FONT_FACES, FONT_LICENSE]);
  return readdirSync(directory).filter((name) => !expected.has(name)).sort();
}

/**
 * The SIL Open Font License, copied beside the faces because the OFL requires it to travel with
 * them. Not a formality and not optional: the four files above are redistributed in a public
 * container image.
 */
export const FONT_LICENSE = 'LICENSE.txt';
