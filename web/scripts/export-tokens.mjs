#!/usr/bin/env node
//
// Render Cypress/DesignSystem/Tokens/*.swift to web/src/styles/tokens.css.
//
// The design system is declared once, in Swift, and ARCHITECTURE §6 forbids a second copy of any
// hex, font size or radius. The web needs the same numbers, so it gets them mechanically: this
// script reads the Swift and writes the CSS, and `web/test/tokens.test.ts` re-runs the same
// render and fails when the checked-in file and the Swift disagree.
//
// All of the parsing lives in `web/src/lib/tokens.ts`, which is string-in / data-out and is unit
// tested against specimens. This file is the I/O around it and nothing else.
//
//   npm run tokens          (web/) write web/src/styles/tokens.css
//   npm run tokens:check    (web/) exit 1 if the file on disk differs; silent when it matches
//
// ── Why this lives under `web/` and not in `Tools/`, where the repo keeps its scripts ────────
//
// Both CI workflows decide what to run by PATH. `web.yml` runs the web suite on an ALLOW-list
// (`web/**` plus the two harness scripts, named one by one), and `testflight.yml`'s `WEB_ONLY`
// exempts the same set from 34 minutes of `macos-26` that would exercise nothing. A generator at
// `Tools/export_tokens.mjs` is in neither list: a change to it alone would skip the web suite and
// run the iOS one, which is both halves of the classification wrong.
//
// Adding it to those lists is the other fix, and it is not this round's to make: `WEB_ONLY` is
// guarded by `CypressTests/DeployPathsAgreeTests`, so widening it is a change the **iOS** suite
// proves, and this round has no simulator. Moving the file needs no workflow edit and no
// unverified widening of the predicate that decides whether a suite runs at all.
//
// Reaching up out of `web/` for the Swift is what `web/test/tokens.test.ts` already does — the
// repository root is two levels up from this file.
//
// Node ≥ 24 strips the types from the `.ts` import with no build step, which is the same thing
// `npm test` relies on. There is no new dependency here and there is no compile output.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseTokens, renderCss, TOKEN_FILES } from '../src/lib/tokens.ts';

/** The repository root: two levels up from `web/scripts/`. */
const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const sources = Object.fromEntries(
  TOKEN_FILES.map((file) => [file, readFileSync(join(repo, file), 'utf8')]),
);
const rendered = renderCss(parseTokens(sources));
const target = join(repo, 'web/src/styles/tokens.css');

if (process.argv.includes('--check')) {
  let onDisk = '';
  try {
    onDisk = readFileSync(target, 'utf8');
  } catch {
    console.error(`${target} does not exist. Run \`npm run tokens\` in web/.`);
    process.exit(1);
  }
  if (onDisk !== rendered) {
    console.error(
      `web/src/styles/tokens.css does not match Cypress/DesignSystem/Tokens/*.swift.\n`
        + `Run \`npm run tokens\` in web/ and commit the result.`,
    );
    process.exit(1);
  }
  process.exit(0);
}

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, rendered);
console.error(`wrote ${target} (${rendered.split('\n').length} lines)`);
