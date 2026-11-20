import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

import {
  FAMILIES,
  GENERIC_FALLBACKS,
  NOT_EXPORTED,
  TOKEN_FILES,
  TOKEN_SCOPES,
  UNITLESS_CGFLOATS,
  cssHex,
  cssShadow,
  declarations,
  declarationsFor,
  familyStacks,
  familyName,
  kebab,
  parseTokens,
  renderCss,
  splitWords,
  type Token,
} from '../src/lib/tokens.ts';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const read = (relative: string): string => readFileSync(join(repoRoot, relative), 'utf8');

const sources = Object.fromEntries(TOKEN_FILES.map((file) => [file, read(file)]));
const parsed = parseTokens(sources);
const checkedIn = read('web/src/styles/tokens.css');

const token = (scope: string, name: string): Token => {
  const found = parsed.tokens.find((t) => t.scope === scope && t.name === name);
  assert.ok(found !== undefined, `${scope}.${name} was not exported`);
  return found;
};

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The parser, on specimens whose answers were known before it saw them.
//
// Pointed only at the real Swift, a parser agrees with whatever the Swift happens to say and
// would agree just as readily if it read nothing at all. Every string below states its own
// answer. This is the same argument `toolchain.test.ts` and `spelling.test.ts` make.
// ─────────────────────────────────────────────────────────────────────────────────────────────

describe('naming', () => {
  it('splits an identifier the three ways a Swift name is written', () => {
    assert.deepEqual(splitWords('surfaceScreen'), ['surface', 'Screen']);
    // An acronym run followed by a capitalized word: the boundary is BEFORE the last capital.
    assert.deepEqual(splitWords('accentGPSHalo'), ['accent', 'GPS', 'Halo']);
    assert.deepEqual(splitWords('hazardCTAFill'), ['hazard', 'CTA', 'Fill']);
    // A digit run is its own word, which is what keeps `body155` traceable to `body.15.5`.
    assert.deepEqual(splitWords('headerPaddingBottom02'), ['header', 'Padding', 'Bottom', '02']);
    assert.deepEqual(splitWords('SourceSerif4'), ['Source', 'Serif', '4']);
  });

  it('kebabs the names the CSS carries', () => {
    assert.equal(kebab('surfaceScreen'), 'surface-screen');
    assert.equal(kebab('hazardCTAFill'), 'hazard-cta-fill');
    assert.equal(kebab('body105SemiBold'), 'body-105-semi-bold');
    assert.equal(kebab('pinSpeciesA'), 'pin-species-a');
  });

  it('derives each font family name from its PostScript prefix', () => {
    // The answers are the `name` table family (ID 1) of the TTFs in Cypress/Resources/Fonts/,
    // read off the files. Nothing here is invented: the three families are spelled this way in
    // the fonts the app ships.
    assert.equal(familyName('SourceSerif4'), 'Source Serif 4');
    assert.equal(familyName('AlegreyaSans'), 'Alegreya Sans');
    assert.equal(familyName('SplineSansMono'), 'Spline Sans Mono');
  });
});

describe('reading Swift declarations', () => {
  it('finds a declaration and the type path it sits in', () => {
    const found = declarations(`
enum Thing {
    static let a: CGFloat = 4
    enum Inner {
        static let b: CGFloat = 5
    }
}
extension Thing {
    static let c: CGFloat = 6
}
`);
    assert.deepEqual(
      found.map((d) => [d.scope, d.name, d.expression]),
      [
        ['Thing', 'a', '4'],
        ['Thing.Inner', 'b', '5'],
        // An `extension Thing` is the SAME namespace as `enum Thing`. §2's component radii are
        // declared in one and §1's in the other, and they are one family of tokens.
        ['Thing', 'c', '6'],
      ],
    );
  });

  it('reads a declaration that spans lines', () => {
    const found = declarations(`
enum Thing {
    static let pair = dynamic(
        light: 0xFFFFFF, dark: 0x000000
    )
    static let after: CGFloat = 1
}
`);
    assert.deepEqual(found.map((d) => d.name), ['pair', 'after']);
    assert.equal(found[0]?.scope, 'Thing');
    // `after` must still be inside `Thing`: a parser that walked the multi-line expression's
    // closing paren as a brace would have popped the scope and put `after` at the top level.
    assert.equal(found[1]?.scope, 'Thing');
  });

  it('ignores a trailing comment but not a slash inside a string', () => {
    const found = declarations(`
enum Thing {
    static let a: CGFloat = 4 // = 5, obviously
    static let b = "http://example.test/x" // a comment
}
`);
    assert.equal(found[0]?.expression, '4');
    assert.equal(found[1]?.expression, '"http://example.test/x"');
  });

  it('records a private declaration as private', () => {
    const found = declarations(`
enum Thing {
    private static let hidden: CGFloat = 12
}
`);
    assert.equal(found[0]?.isPrivate, true);
  });
});

describe('classifying values', () => {
  const parse = (swift: string) => parseTokens({ 'specimen.swift': swift });

  it('reads the five color constructors, alpha included', () => {
    const result = parse(`
enum CypressColor {
    static let paired = dynamic(light: 0x1D4634, dark: 0x8EC3A5)
    static let tinted = dynamic(light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.14)
    static let flat = lightOnly(0x102016, alpha: 0.45)
    static let questioned = escalated(0xFFFFFF)
    static let corrected = overruled(light: 0x535F4C, dark: 0x94A496)
    static let computed = derived(light: 0xFDFDF8, dark: 0x18251D)
}
`);
    assert.deepEqual(
      result.tokens.map((t) => [t.cssName, cssHex((t.value as { light: { hex: number; alpha: number } }).light)]),
      [
        ['color-paired', '#1D4634'],
        ['color-tinted', 'rgb(29 70 52 / 0.14)'],
        ['color-flat', 'rgb(16 32 22 / 0.45)'],
        ['color-questioned', '#FFFFFF'],
        ['color-corrected', '#535F4C'],
        ['color-computed', '#FDFDF8'],
      ],
    );
    // `lightOnly` and `escalated` resolve to one value in both schemes BY DEFINITION, which is
    // the property that keeps them out of the dark block.
    const flat = result.tokens.find((t) => t.name === 'flat');
    assert.deepEqual(flat?.value, {
      kind: 'color',
      light: { hex: 0x102016, alpha: 0.45 },
      dark: { hex: 0x102016, alpha: 0.45 },
    });
  });

  it('resolves a color that is declared as another token', () => {
    const result = parse(`
enum CypressColor {
    static let textInk = dynamic(light: 0x1C2A21, dark: 0xE4EBE2)
    static let calloutGradientText = textInk
}
`);
    const alias = result.tokens.find((t) => t.name === 'calloutGradientText');
    assert.deepEqual(alias?.value, {
      kind: 'color',
      light: { hex: 0x1c2a21, alpha: 1 },
      dark: { hex: 0xe4ebe2, alpha: 1 },
    });
  });

  it('reads the two font helpers, whose arguments are in OPPOSITE orders', () => {
    // `font(face, size, style)` and `styled(size, face, style)`. This is the assertion that
    // catches a parser that assumed one order: with the orders confused, `ramp` resolves its
    // face from `26` and its size from `Face.serifSemiBold`, and both lookups fail loudly —
    // but had `styled` been read positionally as `font`, the sizes would have come out as the
    // face names' text and the weights would all have been one value.
    const result = parse(`
enum CypressFont {
    enum Face {
        static let serifSemiBold = "SourceSerif4-SemiBold"
        static let sansExtraBold = "AlegreyaSans-ExtraBold"
        static let serifItalic = "SourceSerif4-Italic"
    }
    static let ramp = font(Face.serifSemiBold, 26, .title2)
    static let component = styled(10.5, Face.sansExtraBold, .caption2)
    static let slanted = font(Face.serifItalic, 15, .subheadline)
}
`);
    assert.deepEqual(result.tokens.find((t) => t.name === 'ramp')?.value, {
      kind: 'fontStyle', group: 'serif', size: 26, weight: 600, italic: false,
    });
    assert.deepEqual(result.tokens.find((t) => t.name === 'component')?.value, {
      kind: 'fontStyle', group: 'sans', size: 10.5, weight: 800, italic: false,
    });
    assert.deepEqual(result.tokens.find((t) => t.name === 'slanted')?.value, {
      kind: 'fontStyle', group: 'serif', size: 15, weight: 400, italic: true,
    });
  });

  it('resolves a font size that names a constant', () => {
    const result = parse(`
enum CypressFont {
    enum Face {
        static let sansRegular = "AlegreyaSans-Regular"
    }
    private static let body12Size: CGFloat = 12
    static let body12 = font(Face.sansRegular, body12Size, .caption)
}
`);
    assert.equal(
      (result.tokens.find((t) => t.name === 'body12')?.value as { size: number }).size,
      12,
    );
    // The private constant is named on the skip list rather than exported.
    assert.equal(result.skipped.length, 1);
    assert.equal(result.skipped[0]?.name, 'body12Size');
    assert.match(result.skipped[0]?.reason ?? '', /^private to the Swift/);
  });

  it('reads a shadow back out as the CSS it was transcribed from', () => {
    // `CypressShadowStyle(blur:)` takes the CSS blur and halves it for SwiftUI. The argument is
    // therefore already the CSS number, and this is the specimen that says so: the doc comment
    // in CypressShadow.swift above `rest` reads `0 1px 3px rgba(25,40,28,.05)`.
    const result = parse(`
enum CypressShadow {
    static let rest = CypressShadowStyle(hex: 0x19281C, opacity: 0.05, blur: 3, offsetY: 1)
    static let sheet = CypressShadowStyle(hex: 0x0A140E, opacity: 0.32, blur: 40, offsetY: -12)
}
`);
    const rest = result.tokens.find((t) => t.name === 'rest');
    const sheet = result.tokens.find((t) => t.name === 'sheet');
    assert.equal(cssShadow(rest?.value as never), '0 1px 3px rgb(25 40 28 / 0.05)');
    assert.equal(cssShadow(sheet?.value as never), '0 -12px 40px rgb(10 20 14 / 0.32)');
  });

  it('reads an easing tuple as a cubic-bezier', () => {
    const result = parse(`
enum CypressMotion {
    enum Easing {
        static let house: (Double, Double, Double, Double) = (0.22, 0.9, 0.3, 1)
    }
    enum Duration {
        static let fade: Double = 0.32
    }
}
`);
    assert.deepEqual(
      result.tokens.map((t) => [t.cssName, t.value]),
      [
        ['motion-ease-house', { kind: 'cubicBezier', points: [0.22, 0.9, 0.3, 1] }],
        ['motion-duration-fade', { kind: 'seconds', value: 0.32 }],
      ],
    );
  });

  // ── The property the whole design rests on ──────────────────────────────────────────────
  it('THROWS on a declaration it does not understand, rather than skipping it', () => {
    assert.throws(
      () => parse(`
enum CypressRadius {
    static let mystery = someHelperNobodyWroteARuleFor(4)
}
`),
      /matched no rule/,
      'a parser that returns only what it understood is green on the day the export stops '
        + 'matching its source',
    );
  });

  it('THROWS when two declarations claim one custom property', () => {
    assert.throws(
      () => parse(`
enum CypressRadius {
    static let cardLg: CGFloat = 18
}
extension CypressRadius {
    static let cardLg: CGFloat = 20
}
`),
      /is claimed by both/,
    );
  });

  it('records a static let in an unknown scope rather than dropping it', () => {
    const result = parse(`
struct SomeHelperType {
    static let notAToken: CGFloat = 3
}
`);
    assert.deepEqual(result.foreignScopes, ['SomeHelperType']);
    assert.equal(result.tokens.length, 0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The real Swift.
// ─────────────────────────────────────────────────────────────────────────────────────────────

describe('the export against Cypress/DesignSystem/Tokens', () => {
  // ── THE BINDING REQUIREMENT (docs/ROADMAP.md, W-B) ────────────────────────────────────────
  it('web/src/styles/tokens.css is what the Swift renders to, byte for byte', () => {
    const rendered = renderCss(parsed);
    assert.equal(
      rendered === checkedIn,
      true,
      'web/src/styles/tokens.css no longer matches Cypress/DesignSystem/Tokens/*.swift.\n'
        + 'Run `npm run tokens` in web/ and commit the result. First differing line: '
        + firstDifference(checkedIn, rendered),
    );
  });

  // ── The guard's own provenance: it must not pass by reading nothing ───────────────────────
  it('the six token files were all read, and all of them had tokens in them', () => {
    assert.equal(TOKEN_FILES.length, 6);
    for (const file of TOKEN_FILES) {
      const fromFile = parsed.tokens.filter((t) => t.sourceFile === file);
      assert.ok(
        fromFile.length > 0,
        `${file} contributed no tokens, so the walk is passing without reading it`,
      );
    }
    assert.ok(parsed.tokens.length > 500, `only ${parsed.tokens.length} tokens were found`);
  });

  it('the sources hold the two things stripComments assumes about them', () => {
    // `stripComments` in src/lib/tokens.ts takes both on faith: no `/* … */` block, and no `//`
    // inside a string literal. A stripper that eats half a string literal fails by producing
    // plausible garbage rather than by throwing, so the assumption is asserted here rather than
    // trusted in a comment. Both are true today; this is what makes them stay true.
    //
    // Calibrated, in the same run, against text whose answers are known beforehand: a file that
    // DOES carry block comments, and a line that DOES hide `//` in a literal.
    const literals = (text: string): string[] => [...text.matchAll(/"(?:[^"\\]|\\.)*"/g)].map((m) => m[0]);
    const specimen = 'let home = "https://example.com" // the trailing comment';
    assert.ok(checkedIn.includes('/*'), 'calibration: tokens.css does carry a block comment');
    assert.ok(
      literals(specimen).some((literal) => literal.includes('//')),
      'calibration: the literal scan does find `//` inside a string literal',
    );

    for (const [file, source] of Object.entries(sources)) {
      assert.equal(source.includes('/*'), false, `${file} now carries a /* … */ block comment`);
      for (const [index, line] of source.split('\n').entries()) {
        // A whole-line comment is removed before its quotes are ever reached, so a `///` line
        // linking to a URL is not what this is about. Code lines are.
        if (line.trim().startsWith('//')) continue;
        for (const literal of literals(line)) {
          assert.equal(
            literal.includes('//'),
            false,
            `${file}:${index + 1} hides // inside a string literal: ${literal}. stripComments `
              + 'would stop stripping at the quote and leave comment text in the walk.',
          );
        }
      }
    }
  });

  it('every .swift in Tokens/ is either read or named as not-exported, with a reason', () => {
    // A seventh token file appearing in that directory and being missed is the failure this
    // catches. The directory is listed rather than assumed.
    const directory = 'Cypress/DesignSystem/Tokens';
    const onDisk = readdirSync(join(repoRoot, directory))
      .filter((entry) => entry.endsWith('.swift'))
      .map((entry) => `${directory}/${entry}`)
      .sort();
    const accounted = [...TOKEN_FILES, ...Object.keys(NOT_EXPORTED)].sort();
    assert.deepEqual(onDisk, accounted);
    for (const reason of Object.values(NOT_EXPORTED)) assert.ok(reason.length > 40);
  });

  it('every static let in the six files is inside a scope this export knows', () => {
    // The count the parser saw against a count taken a completely different way — a flat grep
    // over the raw text. They agree only if the scope walk reached every declaration.
    for (const [file, source] of Object.entries(sources)) {
      const byGrep = (source.match(/^\s*(?:private\s+|fileprivate\s+)?static\s+let\s/gm) ?? []).length;
      const byWalk = declarations(source, file).filter((d) => TOKEN_SCOPES[d.scope] !== undefined).length;
      assert.equal(byWalk, byGrep, `${file}: the walk saw ${byWalk} static lets, grep sees ${byGrep}`);
    }
    assert.deepEqual(parsed.foreignScopes, []);
  });

  it('the counts per file are the ones the source declares', () => {
    // Known answers: `grep -c 'static let'` on each file, and the same three numbers W-A's
    // Base.astro states in prose ("213 colors, 224 spacing values and 105 font declarations").
    const perFile = Object.fromEntries(
      TOKEN_FILES.map((file) => [
        file.split('/').pop(),
        declarations(sources[file] ?? '', file).length,
      ]),
    );
    assert.deepEqual(perFile, {
      'CypressColor.swift': 213,
      'CypressRadius.swift': 32,
      'CypressSpacing.swift': 224,
      'CypressFont.swift': 105,
      'CypressMotion.swift': 24,
      'CypressShadow.swift': 25,
    });
    assert.equal(parsed.tokens.length + parsed.skipped.length, 623);
  });

  // ── What is NOT exported, named one by one ────────────────────────────────────────────────
  it('the skip list is exactly these 23 declarations, in this order', () => {
    // An export that quietly drops a declaration it cannot render is indistinguishable from one
    // that renders everything. Each entry is named, so adding a `static let` the parser cannot
    // turn into a custom property is a red test and a decision, not an omission.
    assert.deepEqual(parsed.skipped.map((s) => `${s.scope}.${s.name}`), [
      // Gradients: several colors and a geometry, not one custom property. CypressGradient.swift
      // is excluded whole for the same reason; the W1 hero needs them and they are W-C's to port.
      'CypressColor.gradient140',
      'CypressColor.gradient120',
      'CypressColor.gradient90',
      'CypressColor.calloutGradient',
      'CypressColor.Dark.mapOcean',
      // Arrays.
      'CypressColor.compositionSwatches',
      'CypressColor.avatarFills',
      // The E8 / R1 design-review registry — a list of claims ABOUT tokens, not tokens.
      'CypressColor.reviewTokens',
      'CypressColor.derivedTokens',
      'CypressColor.overruledTokens',
      'CypressColor.escalatedTokens',
      'CypressSpacing.Component.chartGridlineY',
      'CypressFont.Face.all',
      // Not constants.
      'CypressFont.body12Size',        // private; resolved for the sizes that name it
      'CypressFont.body12HalfXHeight', // measured off the installed face at runtime
      // The eight composed Animations. Their curves are `--motion-ease-*` and six of their
      // durations are `--motion-duration-*`; `camera` (0.4s) and `selection` (0.18s) write their
      // durations inline rather than in `Duration`, so those two numbers are NOT on the web.
      // That gap is named here rather than hidden; closing it means adding them to `Duration`.
      'CypressMotion.fade',
      'CypressMotion.sheet',
      'CypressMotion.pinDrop',
      'CypressMotion.pulse',
      'CypressMotion.flash',
      'CypressMotion.pop',
      'CypressMotion.camera',
      'CypressMotion.selection',
    ]);
    assert.equal(parsed.skipped.length, 23);
    for (const entry of parsed.skipped) {
      assert.ok(entry.reason.length > 10, `${entry.scope}.${entry.name} has no reason`);
    }
  });

  it('the unitless list is exactly what it claims', () => {
    assert.equal(UNITLESS_CGFLOATS.length, 1);
    assert.deepEqual(token('CypressMotionOffset', 'pinDropScale').value, { kind: 'number', value: 0.4 });
    assert.ok(checkedIn.includes('--motion-offset-pin-drop-scale: 0.4;'));
    // Its neighbor in the same enum, with the same Swift type, IS a length. That is the whole
    // reason the list exists.
    assert.deepEqual(token('CypressMotionOffset', 'pinDropRise').value, { kind: 'length', px: -14 });
  });

  // ── Values, against answers written in the Swift's own doc comments ───────────────────────
  it('the shadows agree with the CSS transcribed above them in CypressShadow.swift', () => {
    // The strongest check available here: SCREENS.md §1.5's `box-shadow` shorthand is quoted in
    // the doc comment over each token, so the file contains an INDEPENDENT transcription of the
    // same fact. This compares the export against it, one shadow at a time. It is what proves
    // the blur is not doubled or halved — a transform no round-trip through the parser alone
    // would ever catch.
    const swift = sources['Cypress/DesignSystem/Tokens/CypressShadow.swift'] ?? '';
    const lines = swift.split('\n');
    const compared: string[] = [];
    for (let i = 0; i < lines.length; i += 1) {
      const declaration = /static let (\w+) = CypressShadowStyle\(/.exec(lines[i] ?? '');
      if (declaration === null) continue;
      // The nearest doc-comment line above that carries an `rgba()` shorthand.
      let documented: string | null = null;
      for (let j = i - 1; j >= 0 && (lines[j] ?? '').trim().startsWith('///'); j -= 1) {
        const shorthand = /`?(-?\d+) (-?\d+)px (\d+)px rgba\((\d+),\s*(\d+),\s*(\d+),\s*(\.?\d*\.?\d+)\)/
          .exec(lines[j] ?? '');
        if (shorthand !== null) {
          const alpha = Number((shorthand[7] ?? '').startsWith('.') ? `0${shorthand[7]}` : shorthand[7]);
          documented = `${shorthand[1]} ${shorthand[2]}px ${shorthand[3]}px `
            + `rgb(${shorthand[4]} ${shorthand[5]} ${shorthand[6]} / ${alpha})`;
          break;
        }
      }
      if (documented === null) continue;
      const name = declaration[1] ?? '';
      // By SOURCE LINE, not by name. `fab` is declared twice — once in `CypressShadow` and once
      // in `CypressShadow.Dark` — and a lookup by name silently compares the light token against
      // the dark one's doc comment. That is what this assertion caught on its first run, and it
      // is the shape of a check that answers a different question than the one asked.
      const exported = parsed.tokens.find(
        (t) => t.family === 'shadow' && t.sourceFile.endsWith('CypressShadow.swift') && t.line === i + 1,
      );
      assert.ok(exported !== undefined, `shadow ${name} at line ${i + 1} was not exported`);
      assert.equal(exported.name, name);
      assert.equal(
        cssShadow(exported.value as never),
        documented,
        `--shadow-${kebab(name)} disagrees with the CSS in its own doc comment`,
      );
      compared.push(`${exported.scope}.${name}`);
    }
    // A doc-comment scrape that matched nothing would pass every assertion above it.
    assert.ok(
      compared.length >= 20,
      `only ${compared.length} shadows had a documented CSS shorthand to compare against; the `
        + `scrape has stopped matching. Found: ${compared.join(', ')}`,
    );
  });

  it('reads the values a reader can check by eye against SCREENS.md', () => {
    assert.deepEqual(token('CypressColor', 'surfaceScreen').value, {
      kind: 'color', light: { hex: 0xf5f6ef, alpha: 1 }, dark: { hex: 0x0e1712, alpha: 1 },
    });
    // `borderPinRing` carries a light alpha and no dark one.
    assert.deepEqual(token('CypressColor', 'borderPinRing').value, {
      kind: 'color', light: { hex: 0x1d4634, alpha: 0.14 }, dark: { hex: 0x2b3a2c, alpha: 1 },
    });
    assert.deepEqual(token('CypressRadius', 'pill').value, { kind: 'length', px: 999 });
    // §2's component radii live in an `extension` and are tokens on the same footing.
    assert.deepEqual(token('CypressRadius', 'grovePill').value, { kind: 'length', px: 11 });
    assert.deepEqual(token('CypressSpacing.Device', 'width').value, { kind: 'length', px: 402 });
    assert.deepEqual(token('CypressMotion.Duration', 'stagger').value, { kind: 'seconds', value: 0.07 });
  });

  it('the four font families the Swift names resolve to three web stacks', () => {
    assert.deepEqual(Object.keys(GENERIC_FALLBACKS).sort(), ['AlegreyaSans', 'SourceSerif4', 'SplineSansMono']);
    // Keys against the PostScript prefixes the Swift ACTUALLY declares, so a fourth family
    // landing in CypressFont.Face is a red test rather than a throw in production.
    const declared = new Set(
      parsed.tokens
        .filter((t) => t.value.kind === 'face')
        .map((t) => ((t.value as { postScript: string }).postScript.split('-')[0] ?? '')),
    );
    assert.deepEqual([...declared].sort(), Object.keys(GENERIC_FALLBACKS).sort());
    assert.ok(checkedIn.includes('--font-family-serif: "Source Serif 4", Georgia, "Times New Roman", serif;'));
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The file that ships.
// ─────────────────────────────────────────────────────────────────────────────────────────────

describe('web/src/styles/tokens.css', () => {
  it(':root declares exactly what the tokens produce, and nothing else', () => {
    const root = checkedIn.split('@media (prefers-color-scheme: dark)')[0] ?? '';
    const inFile = [...root.matchAll(/^\s*--([\w-]+):/gm)].map((m) => m[1] ?? '').sort();
    const expected = [
      ...familyStacks(parsed.tokens).map((entry) => entry.property),
      ...parsed.tokens.flatMap((t) => declarationsFor(t).map((entry) => entry.property)),
    ].sort();
    assert.deepEqual(inFile, expected);
    // A face contributes no property of its own — what the web needs out of the face list is
    // one family stack per group, plus the weight each ramp style resolves to.
    const faces = parsed.tokens.filter((t) => t.value.kind === 'face');
    assert.equal(faces.length, 12);
    for (const face of faces) assert.deepEqual(declarationsFor(face), []);
  });

  it('has no duplicate declaration inside either block', () => {
    const blocks = checkedIn.split('@media (prefers-color-scheme: dark)');
    assert.equal(blocks.length, 2, 'there should be exactly one dark block');
    for (const [index, block] of blocks.entries()) {
      const names = [...block.matchAll(/^\s*(--[\w-]+):/gm)].map((m) => m[1] ?? '');
      assert.ok(names.length > 0);
      assert.equal(new Set(names).size, names.length, `block ${index} declares a property twice`);
    }
  });

  it('the dark block holds exactly the tokens whose dark value differs', () => {
    const dark = checkedIn.split('@media (prefers-color-scheme: dark)')[1] ?? '';
    const overridden = new Set([...dark.matchAll(/^\s*--([\w-]+):/gm)].map((m) => m[1] ?? ''));

    const changes = parsed.tokens.filter(
      (t) => t.value.kind === 'color'
        && (t.value.light.hex !== t.value.dark.hex || t.value.light.alpha !== t.value.dark.alpha),
    );
    assert.deepEqual([...overridden].sort(), changes.map((t) => t.cssName).sort());
    assert.ok(changes.length > 100, `only ${changes.length} tokens change between schemes`);

    // Named cases, both directions. `surfaceScreen` is a documented pair; `cypressDeep` is a
    // brand hue with no dark counterpart by definition (SCREENS.md gives none, and none is
    // derived); `heroMetaPillFill` rides on imagery.
    assert.ok(overridden.has('color-surface-screen'));
    assert.ok(!overridden.has('color-cypress-deep'));
    assert.ok(!overridden.has('color-hero-meta-pill-fill'));
    // Only COLORS are exported per scheme. Shadows are scheme-dependent in the Swift too —
    // `CypressShadow.Dark` declares five dark elevations and `CypressSchemeShadow` resolves them
    // off `@Environment(\.colorScheme)`, with `cypressCardShadow()` meaning NO shadow in dark —
    // but the export mirrors the Swift's own shape and emits that family as flat `--shadow-dark-*`
    // properties in `:root`, for a consumer to select between. So the dark BLOCK is colors only.
    for (const name of overridden) assert.ok(name.startsWith('color-'), `${name} is in the dark block`);
  });

  it('is a prefers-color-scheme export and declares no theme attribute', () => {
    // The Swift resolves off `traits.userInterfaceStyle`, which is the system setting; the app
    // has no in-app appearance control. A `[data-theme]` hook would be a product decision the
    // source does not contain, and the test that this export matches its source cannot protect
    // anything the source does not say.
    assert.ok(checkedIn.includes('@media (prefers-color-scheme: dark)'));
    // Over the CSS with its comments removed: the header explains why there is no `[data-theme]`
    // hook and therefore contains the word. A selector is code; a comment is not.
    const code = checkedIn.replace(/\/\*[\s\S]*?\*\//g, '');
    assert.ok(!code.includes('data-theme'), 'tokens.css declares a theme attribute selector');
    assert.ok(code.includes('@media (prefers-color-scheme: dark)'));
  });

  it('says it is generated and names what regenerates it', () => {
    assert.ok(checkedIn.startsWith('/*\n * GENERATED FILE'));
    assert.ok(checkedIn.includes('web/scripts/export-tokens.mjs'));
  });

  it('the header names the line-spacings that are a clamp, and the line-height each one hides', () => {
    // `--font-line-spacing-*` is SwiftUI's EXTRA leading, not CSS `line-height`. The README's
    // inversion (`line-height = 1.2 + leading / size`) is exact for four of the six and WRONG for
    // the two the Swift declares `0`: that `0` is SwiftUI's floor, stated as such in the doc
    // comment beside each, and inverting it returns 1.2 against a documented 1.1 and 1.05 —
    // looser than the design, on the two largest display styles. The caveat has to travel with
    // the artifact rather than live in prose, so it is in the generated file's own header. WHICH
    // two and WHAT line-height are read out of the Swift here, so lifting a clamp in the source
    // makes the header stale and this test red instead of leaving a wrong number in front of a
    // consumer. Same shape as the shadow doc-comment scrape above: the source's own words are an
    // independent transcription, and a round trip through the parser can never be one.
    const swift = (sources['Cypress/DesignSystem/Tokens/CypressFont.swift'] ?? '').split('\n');
    const lineSpacings = parsed.tokens.filter((t) => t.scope === 'CypressFont.LineSpacing');
    assert.equal(lineSpacings.length, 6, 'CypressFont.LineSpacing no longer declares six tokens');

    const clamped = new Map<string, string>();
    for (const t of lineSpacings) {
      // The doc comment directly above the declaration; `t.line` is 1-based.
      const comment = swift[t.line - 2] ?? '';
      assert.match(
        comment,
        /line-height/,
        `${t.scope}.${t.name} no longer documents a line-height on the line above it, so a `
          + 'consumer has nothing to use in place of the exported leading',
      );
      if (!comment.includes('clamp at 0')) continue;
      assert.deepEqual(t.value, { kind: 'length', px: 0 }, `${t.name} says "clamp at 0" and is not 0`);
      const documented = /line-height (\d+(?:\.\d+)?)/.exec(comment);
      assert.ok(documented !== null, `${t.name}'s clamp comment states no line-height`);
      clamped.set(t.cssName, documented[1] ?? '');
    }
    // A scrape that matched nothing would satisfy every loop below it, so the pair is named here
    // rather than counted. If a clamp is genuinely lifted in the Swift, this is the first thing
    // that goes red and the header below is the second — update both, in that order.
    assert.deepEqual(
      [...clamped.keys()].sort(),
      ['font-line-spacing-species-hero', 'font-line-spacing-tree-name-hero'],
      'the set of line-spacings the Swift documents as "clamp at 0" has changed. Update this '
        + "pair AND the matching lines in tokens.ts's HEADER, then run `npm run tokens`.",
    );

    const header = checkedIn.split('*/')[0] ?? '';
    for (const [cssName, lineHeight] of clamped) {
      assert.match(
        header,
        new RegExp(`--${cssName}\\b[^\\n]*line-height ${lineHeight.replace('.', '\\.')}(?!\\d)`),
        `tokens.css's header does not say that --${cssName} is a clamp hiding line-height `
          + `${lineHeight}. The Swift documents it; the generated file has to carry it.`,
      );
    }
    // Both directions. If a clamp is lifted in the Swift and the header left alone, the header
    // names a token that is no longer clamped, and that is just as wrong as omitting one.
    const named = new Set(
      [...header.matchAll(/--(font-line-spacing-[a-z0-9-]+)/g)].map((m) => m[1] ?? ''),
    );
    assert.deepEqual([...named].sort(), [...clamped.keys()].sort());
  });

  it('carries no raw value the Swift does not declare', () => {
    // ARCHITECTURE §6 in the other direction: every hex in this file has to have come from the
    // Swift. A hand-added color would fail the byte-for-byte test above; this one says WHICH
    // value, which is the difference between a diff and a defect report.
    const hexes = [...checkedIn.matchAll(/#([0-9A-F]{6})\b/g)].map((m) => (m[1] ?? '').toUpperCase());
    const known = new Set<string>();
    for (const t of parsed.tokens) {
      if (t.value.kind !== 'color') continue;
      known.add(t.value.light.hex.toString(16).toUpperCase().padStart(6, '0'));
      known.add(t.value.dark.hex.toString(16).toUpperCase().padStart(6, '0'));
    }
    assert.ok(hexes.length > 200, `only ${hexes.length} hex values were found in the file`);
    for (const value of hexes) assert.ok(known.has(value), `#${value} is in the CSS and not in the Swift`);
  });

  it('every family named by the parser reaches the file', () => {
    for (const family of FAMILIES) {
      const inFamily = parsed.tokens.filter((t) => t.family === family);
      assert.ok(inFamily.length > 0, `no ${family} tokens`);
      const first = inFamily.find((t) => t.value.kind !== 'face');
      assert.ok(
        checkedIn.includes(`  --${first?.cssName}`),
        `the ${family} family's first token, --${first?.cssName}, is not in the CSS`,
      );
    }
  });
});

/** The first line where two renderings differ, for a failure message worth reading. */
function firstDifference(a: string, b: string): string {
  const left = a.split('\n');
  const right = b.split('\n');
  for (let i = 0; i < Math.max(left.length, right.length); i += 1) {
    if (left[i] !== right[i]) {
      return `line ${i + 1}\n  on disk: ${left[i] ?? '<end of file>'}\n  rendered: ${right[i] ?? '<end of file>'}`;
    }
  }
  return 'none — the files differ in length only';
}
