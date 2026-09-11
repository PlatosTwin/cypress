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
//   Tools/export_tokens.mjs            write web/src/styles/tokens.css
//   Tools/export_tokens.mjs --check    exit 1 if the file on disk differs (prints nothing on OK)
//
// Node ≥ 24 strips the types from the `.ts` import with no build step, which is the same thing
// `npm test` relies on. There is no new dependency here and there is no compile output.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..');
const { parseTokens, renderCss, TOKEN_FILES } = await import(
  join(repo, 'web/src/lib/tokens.ts')
);

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
    console.error(`${target} does not exist. Run Tools/export_tokens.mjs.`);
    process.exit(1);
  }
  if (onDisk !== rendered) {
    console.error(
      `web/src/styles/tokens.css does not match Cypress/DesignSystem/Tokens/*.swift.\n`
        + `Run Tools/export_tokens.mjs and commit the result.`,
    );
    process.exit(1);
  }
  process.exit(0);
}

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, rendered);
console.error(`wrote ${target} (${rendered.split('\n').length} lines)`);
