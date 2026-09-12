import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  cssBackgroundImage,
  cssColor,
  cssLinear,
  cssRadial,
  cssScrim,
  rgb,
  rgba,
  W1_HERO,
  W1_SCRIM,
} from '../src/lib/gradients.ts';
import {
  markdownGradientRecipe,
  markdownScrim,
  markdownSection,
  repoFile,
  swiftGradientRecipe,
} from './support/sources.ts';

/**
 * The gradient port, guarded in the two halves `src/lib/gradients.ts` describes.
 *
 * The token export carries no gradient — `CypressGradient.swift` is the first of the three things
 * `web/README.md` names as deliberately outside it — so W1's hero is the one part of this page's
 * palette that had to be re-typed rather than generated. A re-typed constant with no guard is how
 * the vitality rubric forked for two weeks (ticket #261), so:
 *
 * 1. **W1's recipe against `SCREENS.md` §W1**, parsed at run time. §W1 is where W1's hero is
 *    declared; no Swift file carries it, because W1 is a web screen.
 * 2. **The CSS emitter against `CypressGradient.swift`**, parsed at run time. `heroProfile` is
 *    declared in both the Swift and `SCREENS.md` §3, so the emitter is fed the Swift's recipe and
 *    required to produce the markdown's CSS. That is a claim about the RENDERER rather than about
 *    a constant, and it is the half that catches a reversed layer order or a lost percentage.
 *
 * Half 1 alone would prove only that this file was typed correctly. Half 2 alone would leave W1's
 * own recipe — which the Swift does not carry — unguarded.
 */

const screens = repoFile('docs/distilled/SCREENS.md');
const gradientSwift = repoFile('Cypress/DesignSystem/Tokens/CypressGradient.swift');

describe('the CSS emitter', () => {
  it('writes a color the way both documents write one', () => {
    // Known answers first. `#4E8F6A` is C2's own first radial and `rgba(78,143,106,.5)` is screen
    // 04's; the second is the same color written the other way, which is what makes the pair a
    // calibration rather than two examples.
    assert.equal(cssColor(rgb(0x4e8f6a)), '#4e8f6a');
    assert.equal(cssColor(rgba(0x4e8f6a, 0.5)), 'rgba(78,143,106,.5)');
    assert.equal(cssColor(rgba(0x102016, 0)), 'rgba(16,32,22,0)');
    // A color whose channels need leading zeros, which `toString(16)` drops.
    assert.equal(cssColor(rgb(0x000a0b)), '#000a0b');
  });

  it('writes one radial layer as CSS, with the extent as a `transparent` stop', () => {
    assert.equal(
      cssRadial({ x: 0.26, y: 0.5, color: rgb(0x4e8f6a), extent: 0.34 }),
      'radial-gradient(circle at 26% 50%, #4e8f6a 0%, transparent 34%)',
    );
  });

  it('does not let binary floating point into a percentage', () => {
    // 0.34 * 100 is 34.00000000000001 in binary64. Nobody transcribed that, and a value that
    // rendered it would still LOOK right in a browser, which is why this is asserted rather than
    // trusted: the comparison against the markdown below is string equality.
    assert.ok(!cssRadial({ x: 0.34, y: 0.62, color: rgb(0x2f6b4f), extent: 0.38 }).includes('0000'));
  });

  it('puts the radials in front of the base, which is CSS order and not SwiftUI order', () => {
    const css = cssBackgroundImage(W1_HERO);
    assert.ok(
      css.indexOf('radial-gradient') < css.indexOf('linear-gradient'),
      'a CSS background-image list paints its FIRST layer on top, so the base must be last; a '
        + 'SwiftUI ZStack is the other way round and this is where copying that order shows up',
    );
    assert.equal(css.split('radial-gradient').length - 1, W1_HERO.radials.length);
  });

  it('writes a two-stop linear base at the positions CSS gives it', () => {
    assert.equal(
      cssLinear({ degrees: 170, stops: [
        { color: rgb(0xe4ebd8), position: 0 },
        { color: rgb(0xb9cdbc), position: 1 },
      ] }),
      'linear-gradient(170deg, #e4ebd8 0%, #b9cdbc 100%)',
    );
  });
});

describe('W1’s hero, against SCREENS.md §W1', () => {
  const section = markdownSection(screens, '#### W1 · Public tree page');

  it('is the gradient the specification transcribes, layer for layer', () => {
    const declared = markdownGradientRecipe(section);
    // The control. A parser that found nothing would make every comparison below vacuous, and the
    // count is the cheapest thing that cannot be satisfied by an empty answer.
    assert.equal(declared.radials.length, 4, 'the §W1 parse found the wrong number of radials');
    assert.equal(declared.base.stops.length, 3);
    assert.equal(
      cssBackgroundImage(W1_HERO),
      cssBackgroundImage(declared),
      'src/lib/gradients.ts W1_HERO no longer matches SCREENS.md §W1',
    );
  });

  it('is the scrim §W1 transcribes — 46% to .6, not screen 03’s 48% to .5', () => {
    const declared = markdownScrim(section);
    assert.deepEqual({ ...W1_SCRIM }, { ...declared });
    assert.equal(
      cssScrim(W1_SCRIM),
      'linear-gradient(180deg, rgba(16,32,22,0) 46%, rgba(16,32,22,.6) 100%)',
    );
  });

  it('is NOT the app’s tree-profile hero, which is the thing it is easiest to be', () => {
    // `CypressGradient.heroProfile` is one or two points away on every number and a different
    // color on two base stops. Borrowing it would have looked right on screen and been wrong in
    // the file, so the difference is asserted rather than assumed.
    const fromSwift = swiftGradientRecipe(gradientSwift, 'heroProfile');
    assert.notEqual(cssBackgroundImage(W1_HERO), cssBackgroundImage(fromSwift));
  });
});

describe('the emitter, against CypressGradient.swift', () => {
  it('renders the Swift’s own heroProfile as the CSS SCREENS.md 03 transcribes', () => {
    const fromSwift = swiftGradientRecipe(gradientSwift, 'heroProfile');
    const fromMarkdown = markdownGradientRecipe(markdownSection(screens, '#### 03 · Tree profile'));

    // Controls, both directions: the Swift parse and the markdown parse each have to have found
    // four layers before their agreement means anything. Two empty recipes agree perfectly.
    assert.equal(fromSwift.radials.length, 4, 'the Swift parse found the wrong number of radials');
    assert.equal(fromMarkdown.radials.length, 4, 'the §3 parse found the wrong number of radials');

    assert.equal(
      cssBackgroundImage(fromSwift),
      cssBackgroundImage(fromMarkdown),
      'the CSS emitter and Cypress/DesignSystem/Tokens/CypressGradient.swift disagree about the '
        + 'gradient they both describe. Either the emitter is wrong, or the Swift and SCREENS.md '
        + 'have drifted from each other — read the diff before touching either.',
    );
  });

  it('renders an alpha-carrying recipe, which the hero does not exercise', () => {
    // Screen 04's viewfinder is the shape with `hex(0x…, 0.50)` stops, and it is here because
    // every W1 layer is opaque: without it the `rgba(…)` arm of `cssColor` is never reached by a
    // parity check and could be deleted without a red.
    const viewfinder = swiftGradientRecipe(gradientSwift, 'cameraViewfinder');
    const declared = markdownGradientRecipe(markdownSection(screens, '#### 04 · Visit (dark camera)'));
    assert.equal(viewfinder.radials.length, 3);
    assert.equal(cssBackgroundImage(viewfinder), cssBackgroundImage(declared));
    assert.ok(cssBackgroundImage(viewfinder).includes('rgba('));
  });
});
