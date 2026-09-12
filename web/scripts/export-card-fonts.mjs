#!/usr/bin/env node
/**
 * Copy the font faces the OpenGraph card sets into `web/fonts/`, and their license with them.
 *
 * ── Why a copy exists at all ─────────────────────────────────────────────────────────────────
 *
 * The card is rasterized by `@resvg/resvg-js`, which takes fonts as **file paths on disk** — 2.6.2
 * has `fontFiles` and `fontDirs` and no buffer form. So the faces have to be files in the running
 * container, and the container is built from a context of `web/` and nothing else:
 * `.github/workflows/web.yml` runs `docker build … web` and `web/Dockerfile` copies an explicit
 * list from inside it. `COPY ../Cypress/Resources/Fonts` is not a thing Docker can do, and
 * widening the context to the repository root would make the whole iOS tree a build input of a web
 * image — which `web/README.md` rules out, under this heading, for the Swift sources.
 *
 * So this is the bargain `src/styles/tokens.css` already is: **generated and checked in**, a real
 * file that ships and is reviewable in a diff, with a test that fails when it stops matching its
 * source. The cost is staleness, and the staleness is what `test/ogRaster.test.ts` refuses — by
 * sha256, not by size.
 *
 * The list of faces is NOT here. It is `CARD_FONT_FACES` in `src/lib/ogRaster.ts`, beside the
 * renderer that asks for them, and this script and the test both read it from there — the same
 * arrangement `export-tokens.mjs` has with `TOKEN_FILES`.
 *
 *   npm run fonts          # rewrite web/fonts/
 *   npm run fonts:check    # exit 1 if a copy is stale, missing, or unaccounted for
 *
 * Node ≥ 24 strips the types from the `.ts` import with no build step, the same way `npm test`
 * does. There is no new dependency here and no compile output.
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CARD_FONT_FACES, FONT_LICENSE, unexpectedFontFiles } from '../src/lib/ogRaster.ts';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(web, '..');
const source = join(repo, 'Cypress', 'Resources', 'Fonts');
const target = join(web, 'fonts');
const files = [...CARD_FONT_FACES, FONT_LICENSE];

/** @param {Buffer} bytes */
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

mkdirSync(target, { recursive: true });

const check = process.argv.includes('--check');
const stale = [];
for (const name of files) {
  const wanted = readFileSync(join(source, name));
  let current = null;
  try {
    current = readFileSync(join(target, name));
  } catch {
    current = null;
  }
  if (current !== null && digest(current) === digest(wanted)) continue;
  stale.push(name);
  if (!check) writeFileSync(join(target, name), wanted);
}

const extra = unexpectedFontFiles(target);

if (check) {
  if (stale.length === 0 && extra.length === 0) {
    console.error(`web/fonts is current: ${files.length} files from Cypress/Resources/Fonts`);
    process.exit(0);
  }
  if (stale.length > 0) console.error(`stale or missing in web/fonts: ${stale.join(', ')}`);
  if (extra.length > 0) console.error(`in web/fonts and not from the source: ${extra.join(', ')}`);
  console.error('Run `npm run fonts` in web/ and commit the result.');
  process.exit(1);
}

console.error(
  stale.length === 0
    ? `web/fonts was already current (${files.length} files)`
    : `wrote ${stale.map((name) => `web/fonts/${name}`).join(', ')}`,
);
if (extra.length > 0) {
  console.error(`warning: web/fonts also holds ${extra.join(', ')}, which nothing here put there`);
}
