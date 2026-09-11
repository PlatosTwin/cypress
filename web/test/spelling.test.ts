import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, relative } from 'node:path';

import { offenses } from '../src/lib/spelling.ts';

const webRoot = fileURLToPath(new URL('../', import.meta.url));

/**
 * The web's own source, as an author sees it.
 *
 * Generated directories are skipped by NAME rather than by consulting `.gitignore`: this walk
 * has to mean the same thing in a fresh clone, in CI and in a worktree that has just built, and
 * `node_modules` alone holds 229 top-level directories that are nobody's prose.
 */
const SKIP_DIRS = new Set(['node_modules', 'dist', '.astro', '.git']);
const EXTENSIONS = ['.ts', '.astro', '.mjs', '.js', '.json', '.md', '.toml'];

/**
 * **The only two files this sweep does not read, and why the list is asserted rather than
 * trusted.**
 *
 * A spelling guard cannot check the file that spells out what it is looking for: `spelling.ts`
 * is 40 British words by construction, and this file's own specimens are three more. Exempting
 * them is unavoidable. Exempting them QUIETLY is the failure CLAUDE.md names — "tests here have
 * exempted the thing they were guarding as its own wrapper" — so the list is exactly two entries,
 * `theExemptionIsExactlyTwoFilesThatExist` asserts both the count and that each still exists, and
 * a red-proof plants a British spelling in a third file to show the sweep still bites.
 *
 * The hole this leaves is named rather than hidden: prose written INSIDE these two files is
 * unchecked. Both are about spelling, both are read by anyone editing the list, and neither ships
 * anything a reader sees.
 */
const EXEMPT = ['src/lib/spelling.ts', 'test/spelling.test.ts'];

function sourceFiles(dir: string = webRoot): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      if (SKIP_DIRS.has(entry)) continue;
      found.push(...sourceFiles(full));
      continue;
    }
    // The lockfile is generated and names 367 packages nobody here wrote.
    if (entry === 'package-lock.json') continue;
    if (EXTENSIONS.some((extension) => entry.endsWith(extension))) found.push(full);
  }
  return found.sort();
}

describe('American spellings, over the web source', () => {
  // ── The word list itself, before it is pointed at anything ────────────────────────────────
  //
  // Specimens with answers known before the matcher saw them, for the same reason the toolchain
  // parsers get them: a matcher asserted only against the real files agrees with whatever those
  // files happen to say, and would agree just as readily if it matched nothing at all.
  it('finds the forms it names', () => {
    const found = offenses(
      'a colour pair\ntheir neighbours\nthe centre of it\na nanometre\nsome picometres',
    );
    assert.deepEqual(
      found.map((o) => [o.matched, o.american, o.line]),
      [
        ['colour', 'color', 1],
        ['neighbour', 'neighbor', 2],
        ['centre', 'center', 3],
        // The `-metre` family, which had no case here at all until PR #173's delta review (D7).
        // Its absence is exactly how `nanometres` got in: the sweep over `web/` passes whether or
        // not the family exists, because it passes vacuously on the ABSENCE of the word, and the
        // three occurrences that were there had just been fixed. A specimen is the only thing that
        // tells the difference between a rule that works and a rule that is not there. `picometre`
        // is the second row because the fix that would have been reached for — adding `nanometre`
        // alone — leaves it in the same hole.
        ['nanometre', 'nanometer', 4],
        ['picometre', 'picometer', 5],
      ],
    );
  });

  /**
   * The false negative the bare-`metre` lookbehind costs, declared rather than discovered.
   *
   * `(?<![A-Za-z])` is what stops a bare `metre` striking "flameTree" as "fla-meTre-e", and the
   * price is that a `metre` glued to the end of a longer word is not caught — a camelCase
   * `fooMetre` included. `spelling.ts` says so in a comment; before this the comment claimed the
   * test beside it asserted the fact, and the only related assertion was `flameTree` in the
   * INNOCENT list, which guards the opposite thing (PR #173 delta review, D7).
   *
   * This assertion exists to be READ. If somebody ever finds a lookbehind that keeps `flameTree`
   * innocent and catches `fooMetre`, this goes red and the comment gets rewritten with it.
   */
  it('declares the false negative the bare-metre lookbehind costs', () => {
    assert.deepEqual(
      offenses('fooMetre'),
      [],
      'a `metre` behind a letter is now caught; the deliberate false negative documented in '
        + 'spelling.ts is no longer one, and that comment needs rewriting',
    );
    // Behind a space, the same word is caught — so the miss above is the lookbehind and not a
    // missing rule. Without this line the assertion above would pass just as well if `metre` had
    // been dropped from the list entirely.
    assert.deepEqual(
      offenses('one metre').map((o) => [o.matched, o.american]),
      [['metre', 'meter']],
    );
  });

  it('finds every occurrence on one line, not just the first', () => {
    // A `/g` regex reused across calls carries `lastIndex` and skips matches. This is the
    // assertion that would go red if `offenses` ever stopped rebuilding it per line.
    const found = offenses('colour, colour and colour again');
    assert.equal(found.length, 3);
  });

  it('leaves correct English alone', () => {
    // Each of these contains a British spelling as a substring, or is correct in both forms.
    // They are the reason the word boundaries in the list exist, and deleting one of those
    // boundaries turns this red.
    const innocent = [
      'flameTree',        // fla-meTre-e — the bare `metre` case
      'analysis',         // correct in both; only `analyse` is not
      'diameter',         // di-ameter, not `metre`
      'parameter',
      'grayscale',
      'concentration',
      'the greyhound is spelled that way',  // `grey` before a letter is left alone
    ];
    for (const text of innocent) {
      assert.deepEqual(offenses(text), [], `false positive in “${text}”`);
    }
  });

  // ── The sweep ─────────────────────────────────────────────────────────────────────────────
  it('every web source file is spelled in American English', () => {
    const files = sourceFiles();
    const failures: string[] = [];
    for (const file of files) {
      if (EXEMPT.includes(relative(webRoot, file))) continue;
      const text = readFileSync(file, 'utf8');
      for (const o of offenses(text)) {
        failures.push(`${relative(webRoot, file)}:${o.line}: “${o.matched}” should be “${o.american}”`);
      }
    }
    assert.deepEqual(
      failures,
      [],
      `${failures.length} British spelling(s) in web/:\n${failures.slice(0, 25).join('\n')}`,
    );
  });

  // ── The guard's own provenance: it must not pass by seeing nothing ─────────────────────────
  //
  // This project's signature failure is a green result from a check that ran on nothing, and a
  // file walk produces one for free — a renamed directory, a wrong root, an extension list that
  // stopped matching. Both halves are asserted: enough files, and the right ones.
  it('the sweep can see the source it claims to check', () => {
    const files = sourceFiles().map((f) => relative(webRoot, f));
    assert.ok(
      files.length >= 10,
      `the spelling sweep found only ${files.length} file(s) under web/, so it is passing without `
        + `checking anything. Fix the walk, not the assertion. Found: ${files.join(', ')}`,
    );
    // Named files, not just a count: a walk that found ten copies of the same thing satisfies a
    // floor. These are the files this round's three occurrences were actually in.
    for (const expected of [
      'src/layouts/Base.astro',
      'src/pages/index.astro',
      'src/lib/toolchain.ts',
      'tsconfig.json',
      'README.md',
      'fly.toml',
    ]) {
      assert.ok(files.includes(expected), `the sweep did not reach ${expected}; it checked ${files.length} files`);
    }
  });

  it('the exemption is exactly two files, and both still exist', () => {
    // The count first. An exemption list is the cheapest way to make a guard green while the
    // defect is present, and it grows one entry at a time with a good reason each time.
    assert.equal(
      EXEMPT.length,
      2,
      `the spelling sweep now exempts ${EXEMPT.length} files (${EXEMPT.join(', ')}). Only the word `
        + `list and this file's own specimens can be exempt — anything else is the guard being `
        + `taught to ignore the thing it found.`,
    );
    // And that each is real. A stale entry naming a moved file exempts nothing and reads as if
    // it does, which leaves a reader believing the hole is somewhere it is not.
    const files = sourceFiles().map((f) => relative(webRoot, f));
    for (const exempt of EXEMPT) {
      assert.ok(files.includes(exempt), `exempt path ${exempt} does not exist — the list is stale`);
    }
  });
});
