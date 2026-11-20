import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { markdownSection, repoFile } from './support/sources.ts';

/**
 * `src/styles/w1.css` against `SCREENS.md` §W1 and against `tokens.css`.
 *
 * Two claims, and they are different:
 *
 * 1. **The `--w1-*` block still says what §W1 says.** Those are the numbers the specification
 *    states that the token export does not carry — W1's type scale and its page padding, which no
 *    iOS screen uses. They are literals in a stylesheet, which is exactly the shape §6 forbids
 *    everywhere else, so they are confined to one block and checked against the specification
 *    parsed at run time.
 * 2. **Everything else is a token.** No hex, no bare font size, no bare radius outside that block.
 *    Asserted by sweeping the file rather than by reading it, because "I looked and there were
 *    none" is a claim that stops being true on the next edit.
 *
 * The numbers below were read out of §W1 by a human before this file was written; the parser is
 * then required to find the same ones, which is what makes it a measurement rather than a
 * restatement of whatever the parser happened to match.
 */

const css = readFileSync(fileURLToPath(new URL('../src/styles/w1.css', import.meta.url)), 'utf8');
const section = markdownSection(repoFile('docs/distilled/SCREENS.md'), '#### W1 · Public tree page');

/** The value of one `--w1-*` custom property, as the stylesheet declares it. */
function custom(name: string): string {
  const match = new RegExp(String.raw`--w1-${name}:\s*([^;]+);`).exec(css);
  assert.notEqual(match, null, `src/styles/w1.css declares no --w1-${name}`);
  return (match?.[1] ?? '').trim();
}

/** The first capture of a pattern against §W1's own text. */
function spec(pattern: RegExp, what: string): string {
  const match = pattern.exec(section);
  assert.notEqual(match, null, `SCREENS.md §W1 no longer states ${what} (/${pattern.source}/)`);
  return match?.[1] ?? '';
}

describe('the numbers §W1 states and the token export does not carry', () => {
  it('the parser is reading §W1 and not the whole document', () => {
    // Calibration. §W1's section must contain its own frame line and must NOT contain screen 03's
    // hero height, which is two hundred lines further up in the same file. A section slice that
    // silently ran to the end of the document would find both.
    assert.ok(section.includes('ChromeWindow` 1180×780'));
    assert.ok(!section.includes('height **224px**'), 'the §W1 slice reaches into another screen');
  });

  it('the H1 is a 42px serif at line-height 1.05, and the CSS caps there', () => {
    assert.equal(spec(/H1 Serif \*\*(\d+)px\*\*/, "the H1's size"), '42');
    assert.equal(spec(/`line-height:([\d.]+)`/, "the H1's line height"), '1.05');
    // The clamp is this file's own — §W1 was drawn at one width and a 42px serif headline wraps
    // into two half-empty lines on a phone — so what is asserted is the CEILING.
    assert.match(custom('hero-title-size'), /^clamp\(.*,\s*42px\)$/);
    assert.equal(custom('hero-title-line-height'), '1.05');
  });

  it('the latin line is an 18px italic serif', () => {
    assert.equal(spec(/Latin Serif italic (\d+)px/, "the latin line's size"), '18');
    assert.equal(custom('latin-size'), '18px');
  });

  it('the top bar is padded 14px 32px with 26px between its items', () => {
    assert.equal(spec(/`padding:(\d+)px 32px`/, "the top bar's padding"), '14');
    assert.equal(spec(/`HStack\(spacing:(\d+)\)`/, "the top bar's gap"), '26');
    assert.equal(custom('bar-padding-block'), '14px');
    assert.equal(custom('page-padding'), '32px');
    assert.equal(custom('bar-gap'), '26px');
  });

  it('the fact column is padded 32px 34px', () => {
    assert.equal(spec(/`padding:32px (\d+)px`/, "the fact column's padding"), '34');
    assert.equal(custom('column-padding-inline'), '34px');
  });

  it('the logo and the button pair are both 10px gaps', () => {
    assert.equal(spec(/`gap:(\d+)px`/, "the logo's gap"), '10');
    assert.equal(spec(/`HStack\(spacing:(\d+)\)`, `margin-top:22px`/, "the button pair's gap"), '10');
    assert.equal(custom('logo-gap'), '10px');
    assert.equal(custom('button-gap'), '10px');
  });

  it('the body is a 1.45fr / 1fr grid', () => {
    assert.equal(
      spec(/grid-template-columns:([\d.]+)fr 1fr/, "the body grid's ratio"),
      '1.45',
    );
    assert.equal(custom('hero-fraction'), '1.45fr');
    assert.match(css, /grid-template-columns:\s*var\(--w1-hero-fraction\) 1fr;/);
  });
});

describe('everything else in the stylesheet is a token', () => {
  /** The file with the `--w1-*` block removed, which is the only place a literal may live. */
  const outsideTheBlock = css.replace(/\s*--w1-[a-z-]+:[^;]+;/g, '');

  it('the sweep can see the file it claims to check', () => {
    // The control that keeps this pair from being vacuous: the block has to have been found and
    // removed, and what is left has to still be the stylesheet.
    assert.ok(css.includes('--w1-page-padding:'), 'the --w1-* block is not in the file');
    assert.ok(!outsideTheBlock.includes('--w1-page-padding:'), 'the block was not removed');
    assert.ok(outsideTheBlock.includes('.w1-fact'), 'the sweep removed more than the block');
  });

  it('holds no color literal anywhere, block included', () => {
    // ARCHITECTURE §6, and the whole reason `tokens.css` is generated. `rgb(`/`rgba(`/`hsl(` too:
    // a color written a different way is the same second copy of a fact that has an owner.
    const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '');
    assert.deepEqual(withoutComments.match(/#[0-9A-Fa-f]{3,8}\b/g) ?? [], []);
    assert.deepEqual(withoutComments.match(/\b(rgba?|hsla?|color-mix)\(/g) ?? [], []);
  });

  it('sets every color through a custom property', () => {
    const withoutComments = outsideTheBlock.replace(/\/\*[\s\S]*?\*\//g, '');
    for (const property of ['color', 'background', 'background-color', 'border-radius']) {
      const pattern = new RegExp(String.raw`(?<![-\w])${property}:\s*([^;]+);`, 'g');
      for (const match of withoutComments.matchAll(pattern)) {
        const value = (match[1] ?? '').trim();
        // `transparent` and `0` are not colors or radii with owners; everything else is a token.
        if (value === 'transparent' || value === '0') continue;
        assert.ok(
          value.includes('var(--'),
          `w1.css sets \`${property}: ${value}\` without a token`,
        );
      }
    }
  });

  it('sets every font size through a token or the --w1-* block', () => {
    const withoutComments = outsideTheBlock.replace(/\/\*[\s\S]*?\*\//g, '');
    for (const match of withoutComments.matchAll(/(?<![-\w])font-size:\s*([^;]+);/g)) {
      const value = (match[1] ?? '').trim();
      assert.ok(value.includes('var(--'), `w1.css sets \`font-size: ${value}\` without a token`);
    }
  });

  it('names only tokens that the generated tokens.css actually declares', () => {
    // A `var(--color-on-cta-fill)` that nothing declares renders as nothing at all — an invisible
    // failure, and the exact one this caught while the page was being written.
    const declared = new Set(
      [...readFileSync(
        fileURLToPath(new URL('../src/styles/tokens.css', import.meta.url)),
        'utf8',
      ).matchAll(/^\s{2,4}(--[a-z0-9-]+):/gm)].map((match) => match[1]),
    );
    assert.ok(declared.size > 100, `tokens.css parsed to ${declared.size} properties`);
    const used = [...css.matchAll(/var\((--[a-z0-9-]+)\)/g)].map((match) => match[1] ?? '');
    assert.ok(used.length > 20, `w1.css uses ${used.length} custom properties`);
    const missing = [...new Set(used)]
      .filter((name) => !name.startsWith('--w1-'))
      .filter((name) => !declared.has(name));
    assert.deepEqual(missing, [], 'w1.css reads custom properties tokens.css does not declare');
  });
});
