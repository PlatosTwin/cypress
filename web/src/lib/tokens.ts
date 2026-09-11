/**
 * The Swift design tokens, read as data, and rendered as CSS custom properties.
 *
 * `Cypress/DesignSystem/Tokens/*.swift` is the source of truth for 213 colors, 224 spacing
 * values, 105 font declarations and the rest of ARCHITECTURE §6's "tokens only" rule. The web
 * needs the same numbers and must not acquire a second copy of them that a designer can change
 * in one place and not the other.
 *
 * **Deliberately string-in / data-out with no I/O**, the same shape as `toolchain.ts`: the
 * caller opens the Swift files. A module that reads its own repository cannot be tested without
 * one, and every specimen in `test/tokens.test.ts` is a string whose answer was known before the
 * parser saw it.
 *
 * ── The one property this module is built around ───────────────────────────────────────────
 *
 * **Nothing is skipped silently.** Every `static let` inside a token scope is classified into
 * exactly one of: a token that is exported, a private constant other tokens resolve against, or
 * a *named* entry on the skip list with a reason. Anything that matches none of those throws.
 * A `static let` in a scope this module does not know about is recorded in `foreignScopes`.
 *
 * That is the whole design. A parser that returns "the tokens I understood" is green on the day
 * someone adds a declaration it does not understand, and the export quietly stops matching its
 * source — which is this repository's dominant test-suite defect
 * (`docs/investigations/repeat-failures-postmortem.md`). The test asserts the skip list
 * entry-by-entry, so a new unexportable declaration is a red test and a deliberate decision,
 * not a silent omission.
 */

// ── Scopes ───────────────────────────────────────────────────────────────────────────────────

/** The families a token can belong to, in the order they are emitted. */
export const FAMILIES = ['color', 'radius', 'space', 'font', 'motion', 'shadow'] as const;
export type Family = (typeof FAMILIES)[number];

interface ScopeRule {
  readonly family: Family;
  /** Extra path segments in the CSS name, e.g. `CypressColor.Dark` → `--color-dark-…`. */
  readonly prefix: readonly string[];
}

/**
 * Every Swift type path whose `static let`s are tokens, and where each lands in the CSS name.
 *
 * A dotted path, matched exactly. `CypressRadius` covers both `enum CypressRadius` and
 * `extension CypressRadius` — §2's component radii are declared in the extension and are tokens
 * on the same footing as §1's.
 */
export const TOKEN_SCOPES: Readonly<Record<string, ScopeRule>> = {
  CypressColor: { family: 'color', prefix: [] },
  'CypressColor.Dark': { family: 'color', prefix: ['dark'] },

  CypressRadius: { family: 'radius', prefix: [] },

  CypressSpacing: { family: 'space', prefix: [] },
  'CypressSpacing.Device': { family: 'space', prefix: ['device'] },
  'CypressSpacing.Component': { family: 'space', prefix: [] },

  CypressFont: { family: 'font', prefix: [] },
  'CypressFont.Face': { family: 'font', prefix: ['face'] },
  'CypressFont.Tracking': { family: 'font', prefix: ['tracking'] },
  'CypressFont.LineSpacing': { family: 'font', prefix: ['line-spacing'] },
  'CypressFont.ComponentTracking': { family: 'font', prefix: ['tracking'] },

  CypressMotion: { family: 'motion', prefix: [] },
  'CypressMotion.Easing': { family: 'motion', prefix: ['ease'] },
  'CypressMotion.Duration': { family: 'motion', prefix: ['duration'] },
  CypressMotionOffset: { family: 'motion', prefix: ['offset'] },

  CypressShadow: { family: 'shadow', prefix: [] },
  'CypressShadow.Dark': { family: 'shadow', prefix: ['dark'] },
};

/**
 * The generic CSS fallbacks for each installed family, keyed by the PostScript prefix that
 * `CypressFont.Face` names.
 *
 * The one hand-written table in this file, and the only web-only judgment in the export: the
 * Swift names a face and stops, because on iOS a missing face falls back to the system font
 * with no stack to write. `theFallbackTableCoversExactlyTheInstalledFamilies` asserts the keys
 * against the faces the Swift actually declares, so a fourth family cannot land here unnoticed.
 *
 * The family NAME is not in this table — it is derived from the PostScript prefix by the same
 * word split that builds every CSS name (`SourceSerif4` → `Source Serif 4`), and the derivation
 * is checked against the three families' `name` table entries, read off the TTFs.
 */
export const GENERIC_FALLBACKS: Readonly<Record<string, readonly string[]>> = {
  SourceSerif4: ['Georgia', '"Times New Roman"', 'serif'],
  AlegreyaSans: ['ui-sans-serif', 'system-ui', 'sans-serif'],
  SplineSansMono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
};

/**
 * `CGFloat` tokens that are NOT lengths, keyed `Scope.name`.
 *
 * **A Swift type annotation is not a unit.** `CGFloat` is the type of every point value in the
 * design system and is also the type of `pinDropScale`, which is a multiplier — 0.4 of full
 * size, the scale a map pin drops in from. Emitting it as `0.4px` would be a plausible,
 * unreadable wrong answer of exactly the kind this repository loses conclusions to.
 *
 * One entry, and `theUnitlessListIsExactlyWhatItClaims` asserts both the count and that the
 * declaration still exists. The list grows one entry at a time with a reason each time; it is
 * not a place to put a token the emitter merely found inconvenient.
 */
export const UNITLESS_CGFLOATS: readonly string[] = ['CypressMotionOffset.pinDropScale'];

/** PostScript style suffix → CSS `font-weight`. */
export const FACE_WEIGHTS: Readonly<Record<string, number>> = {
  Regular: 400,
  Italic: 400,
  Medium: 500,
  SemiBold: 600,
  Bold: 700,
  ExtraBold: 800,
};

// ── The parsed shapes ────────────────────────────────────────────────────────────────────────

export interface ColorValue {
  readonly hex: number;
  readonly alpha: number;
}

export type TokenValue =
  | { readonly kind: 'color'; readonly light: ColorValue; readonly dark: ColorValue }
  /** A number in iOS points, emitted as CSS `px`. */
  | { readonly kind: 'length'; readonly px: number }
  /** A bare number: a duration in seconds, or an opacity. */
  | { readonly kind: 'seconds'; readonly value: number }
  | { readonly kind: 'number'; readonly value: number }
  | { readonly kind: 'cubicBezier'; readonly points: readonly [number, number, number, number] }
  | { readonly kind: 'shadow'; readonly color: ColorValue; readonly blur: number; readonly x: number; readonly y: number }
  | { readonly kind: 'face'; readonly postScript: string; readonly group: string; readonly weight: number; readonly italic: boolean }
  | { readonly kind: 'fontStyle'; readonly group: string; readonly size: number; readonly weight: number; readonly italic: boolean };

export interface Token {
  /** The Swift type path, e.g. `CypressColor.Dark`. */
  readonly scope: string;
  /** The Swift property name, e.g. `surfaceScreen`. */
  readonly name: string;
  readonly family: Family;
  /** The custom property, without the leading `--`. */
  readonly cssName: string;
  readonly value: TokenValue;
  readonly sourceFile: string;
  readonly line: number;
}

export interface Skipped {
  readonly scope: string;
  readonly name: string;
  readonly reason: string;
}

export interface ParsedTokens {
  readonly tokens: readonly Token[];
  readonly skipped: readonly Skipped[];
  /** Scopes that held a `static let` and are not in `TOKEN_SCOPES`, with one example each. */
  readonly foreignScopes: readonly string[];
}

// ── Names ────────────────────────────────────────────────────────────────────────────────────

/**
 * A Swift identifier split into words: `accentGPSHalo` → `accent GPS Halo`,
 * `headerPaddingBottom02` → `header Padding Bottom 02`, `SourceSerif4` → `Source Serif 4`.
 *
 * Three boundaries, and each one is exercised by a specimen in the test: lower-or-digit before
 * upper, an acronym run before a capitalized word, and a letter before a digit run. Getting the
 * acronym rule wrong turns `hazardCTAFill` into `hazard-c-t-a-fill`, which is a name nobody can
 * trace back to the Swift.
 */
export function splitWords(identifier: string): readonly string[] {
  return identifier
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2')
    .replace(/([A-Za-z])([0-9])/g, '$1 $2')
    .split(' ')
    .filter((word) => word.length > 0);
}

/** `surfaceScreen` → `surface-screen`. */
export function kebab(identifier: string): string {
  return splitWords(identifier)
    .map((word) => word.toLowerCase())
    .join('-');
}

/** The PostScript family prefix as a CSS family name: `SourceSerif4` → `Source Serif 4`. */
export function familyName(postScriptPrefix: string): string {
  return splitWords(postScriptPrefix).join(' ');
}

// ── Swift source, reduced to declarations ────────────────────────────────────────────────────

interface Declaration {
  readonly scope: string;
  readonly name: string;
  readonly isPrivate: boolean;
  readonly typeAnnotation: string | null;
  readonly expression: string;
  readonly line: number;
}

/**
 * Strip `//` line comments. The token files carry no `/* … *\/` blocks and no `//` inside a
 * string literal — both are asserted in the test rather than assumed, because a comment
 * stripper that eats half a string literal fails by producing plausible garbage.
 */
function stripComments(source: string): string {
  return source
    .split('\n')
    .map((line) => {
      let inString = false;
      for (let i = 0; i < line.length; i += 1) {
        const ch = line[i];
        if (ch === '"' && line[i - 1] !== '\\') inString = !inString;
        if (!inString && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
      }
      return line;
    })
    .join('\n');
}

/** True once every bracket opened in `text` has been closed. */
function balanced(text: string): boolean {
  let depth = 0;
  let inString = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === '"' && text[i - 1] !== '\\') inString = !inString;
    if (inString) continue;
    if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    if (ch === ')' || ch === ']' || ch === '}') depth -= 1;
  }
  return depth <= 0;
}

/**
 * Every `static let` in the file, with the Swift type path it sits in.
 *
 * Scope is tracked by brace depth over `enum`/`struct`/`extension` headers, so
 * `extension CypressRadius { … }` yields the same scope string as `enum CypressRadius { … }`
 * and §2's component radii are not a second namespace.
 */
export function declarations(source: string, _file = '<memory>'): readonly Declaration[] {
  const lines = stripComments(source).split('\n');
  const found: Declaration[] = [];
  /** One entry per open brace: the scope name it introduced, or null. */
  const braces: (string | null)[] = [];
  const path = (): string => braces.filter((b): b is string => b !== null).join('.');

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] ?? '';

    const header = /^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:enum|struct|extension)\s+([A-Za-z_][\w]*)/.exec(line);

    const declaration = /^\s*(private\s+|fileprivate\s+)?static\s+let\s+([A-Za-z_]\w*)\s*(?::\s*([^=]+?))?\s*=\s*(.*)$/.exec(line);
    if (declaration !== null) {
      let expression = declaration[4] ?? '';
      let end = i;
      while (!balanced(expression) && end + 1 < lines.length) {
        end += 1;
        expression += `\n${lines[end] ?? ''}`;
      }
      found.push({
        scope: path(),
        name: declaration[2] ?? '',
        isPrivate: declaration[1] !== undefined,
        typeAnnotation: (declaration[3] ?? '').trim() || null,
        expression: expression.trim(),
        line: i + 1,
      });
      // Skip the lines the expression consumed. Its own braces are balanced within it, so the
      // scope depth is the same on the other side and nothing is lost by not walking them.
      i = end;
      continue;
    }

    let first = true;
    for (let c = 0; c < line.length; c += 1) {
      if (line[c] === '{') {
        braces.push(first && header !== null ? (header[1] ?? null) : null);
        first = false;
      }
      if (line[c] === '}') braces.pop();
    }
  }
  return found;
}

// ── Value parsing ────────────────────────────────────────────────────────────────────────────

/** Collapse a multi-line expression to one line, so one set of regexes reads either shape. */
function flatten(expression: string): string {
  return expression.replace(/\s+/g, ' ').trim();
}

function number(text: string): number | null {
  const match = /^-?\d+(?:\.\d+)?$/.exec(text.trim());
  return match === null ? null : Number(match[0]);
}

function hex(text: string): number | null {
  const match = /^0x([0-9A-Fa-f]{6})$/.exec(text.trim());
  return match === null ? null : Number.parseInt(match[1] ?? '', 16);
}

/** `light: 0x1D4634, dark: 0x8EC3A5, lightAlpha: 0.14` → a keyed map, positional args under `_`. */
function args(inside: string): { positional: string[]; keyed: Record<string, string> } {
  const positional: string[] = [];
  const keyed: Record<string, string> = {};
  let depth = 0;
  let current = '';
  const parts: string[] = [];
  for (const ch of inside) {
    if (ch === '(' || ch === '[') depth += 1;
    if (ch === ')' || ch === ']') depth -= 1;
    if (ch === ',' && depth === 0) {
      parts.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  if (current.trim().length > 0) parts.push(current);
  for (const part of parts) {
    const keyedMatch = /^\s*([A-Za-z_]\w*)\s*:\s*(.+)$/.exec(part);
    if (keyedMatch !== null) keyed[keyedMatch[1] ?? ''] = (keyedMatch[2] ?? '').trim();
    else positional.push(part.trim());
  }
  return { positional, keyed };
}

/** The text inside `call(…)` when `expression` is exactly that call, else null. */
function callArgs(expression: string, name: string): string | null {
  const flat = flatten(expression);
  if (!flat.startsWith(`${name}(`) || !flat.endsWith(')')) return null;
  return flat.slice(name.length + 1, -1);
}

function color(hexText: string, alphaText: string | undefined): ColorValue | null {
  const h = hex(hexText);
  if (h === null) return null;
  const alpha = alphaText === undefined ? 1 : number(alphaText);
  if (alpha === null) return null;
  return { hex: h, alpha };
}

/** Why a `private static let` is not a token: it is resolved, then left out of the file. */
const PRIVATE_REASON = 'private to the Swift — resolved for the declarations that name it, not a token of its own';

// ── The classifier ───────────────────────────────────────────────────────────────────────────

/** The six token files, in emission order. `Record<file name, source text>`. */
export type TokenSources = Readonly<Record<string, string>>;

/**
 * Classify every `static let` in the supplied Swift sources.
 *
 * Throws on a declaration inside a token scope that matches no rule — see the header. The
 * caller gets tokens, a named skip list, and the scopes that were not token scopes.
 */
export function parseTokens(sources: TokenSources): ParsedTokens {
  const tokens: Token[] = [];
  const skipped: Skipped[] = [];
  const foreign = new Set<string>();
  /** Scalars other declarations resolve against, keyed `Scope.name`. */
  const scalars = new Map<string, number>();
  /** Colors other declarations alias, keyed `Scope.name`. */
  const colors = new Map<string, { light: ColorValue; dark: ColorValue }>();
  /** Faces, keyed by their Swift name inside `CypressFont.Face`. */
  const faces = new Map<string, { postScript: string; group: string; weight: number; italic: boolean }>();

  const skip = (declaration: Declaration, reason: string): void => {
    skipped.push({ scope: declaration.scope, name: declaration.name, reason });
  };

  for (const [file, source] of Object.entries(sources)) {
    for (const declaration of declarations(source, file)) {
      const rule = TOKEN_SCOPES[declaration.scope];
      if (rule === undefined) {
        foreign.add(declaration.scope);
        continue;
      }
      const flat = flatten(declaration.expression);
      const cssName = [rule.family, ...rule.prefix, kebab(declaration.name)].join('-');
      const emit = (value: TokenValue): void => {
        tokens.push({
          scope: declaration.scope,
          name: declaration.name,
          family: rule.family,
          cssName,
          value,
          sourceFile: file,
          line: declaration.line,
        });
      };

      // ── Colors ───────────────────────────────────────────────────────────────────────────
      if (rule.family === 'color') {
        let pair: { light: ColorValue; dark: ColorValue } | null = null;
        for (const constructor of ['dynamic', 'derived', 'overruled']) {
          const inside = callArgs(flat, constructor);
          if (inside === null) continue;
          const { keyed } = args(inside);
          const light = color(keyed['light'] ?? '', keyed['lightAlpha']);
          const dark = color(keyed['dark'] ?? '', keyed['darkAlpha']);
          if (light !== null && dark !== null) pair = { light, dark };
        }
        for (const constructor of ['lightOnly', 'escalated']) {
          const inside = callArgs(flat, constructor);
          if (inside === null) continue;
          const { positional, keyed } = args(inside);
          const flatColor = color(positional[0] ?? '', keyed['alpha']);
          if (flatColor !== null) pair = { light: flatColor, dark: flatColor };
        }
        const raw = callArgs(flat, 'Color');
        if (raw !== null) {
          const { keyed } = args(raw);
          const flatColor = color(keyed['cypressHex'] ?? '', keyed['alpha']);
          if (flatColor !== null) pair = { light: flatColor, dark: flatColor };
        }
        if (pair === null && /^[A-Za-z_]\w*$/.test(flat)) {
          const aliased = colors.get(`${declaration.scope}.${flat}`) ?? colors.get(`CypressColor.${flat}`);
          if (aliased !== undefined) pair = aliased;
        }
        if (pair !== null) {
          colors.set(`${declaration.scope}.${declaration.name}`, pair);
          if (declaration.isPrivate) skip(declaration, PRIVATE_REASON);
          else emit({ kind: 'color', light: pair.light, dark: pair.dark });
          continue;
        }
        // The registry check comes FIRST: `derivedTokens` is also an array literal, and the
        // reason on the skip list should say what the declaration is, not what shape it has.
        if (declaration.typeAnnotation === '[CypressReviewToken]') {
          skip(declaration, 'the E8/R1 design-review registry, not a token');
          continue;
        }
        if (/linearGradient|cssGradientPoints|LinearGradient/.test(flat)) {
          skip(declaration, 'a gradient — several colors and a geometry, not one custom property');
          continue;
        }
        if (/^\[/.test(flat)) {
          skip(declaration, 'an array of colors, not one custom property');
          continue;
        }
        throw new Error(
          `${file}:${declaration.line}: ${declaration.scope}.${declaration.name} is a color-scope `
            + `declaration this parser does not understand: ${flat.slice(0, 120)}`,
        );
      }

      // ── Fonts ────────────────────────────────────────────────────────────────────────────
      if (rule.family === 'font' && declaration.scope === 'CypressFont.Face') {
        const literal = /^"([A-Za-z0-9]+)-([A-Za-z]+)"$/.exec(flat);
        if (literal !== null) {
          const postScript = flat.slice(1, -1);
          const style = literal[2] ?? '';
          const weight = FACE_WEIGHTS[style];
          if (weight === undefined) {
            throw new Error(`${file}:${declaration.line}: face style "${style}" has no CSS weight`);
          }
          const group = (splitWords(declaration.name)[0] ?? '').toLowerCase();
          const face = { postScript, group, weight, italic: style === 'Italic' };
          faces.set(declaration.name, face);
          emit({ kind: 'face', ...face });
          continue;
        }
        if (/^\[/.test(flat)) {
          skip(declaration, 'an array of the faces above');
          continue;
        }
        throw new Error(`${file}:${declaration.line}: unreadable face declaration: ${flat.slice(0, 120)}`);
      }

      if (rule.family === 'font' && declaration.scope === 'CypressFont') {
        // `font(Face.x, size, .style)` and `styled(size, Face.x, .style)` — note that the two
        // helpers take the SAME two arguments in the OPPOSITE order. A parser that assumes one
        // order reads 88 of the 105 declarations correctly and silently inverts the rest.
        const viaFont = callArgs(flat, 'font');
        const viaStyled = callArgs(flat, 'styled');
        const inside = viaFont ?? viaStyled;
        if (inside !== null) {
          const { positional } = args(inside);
          const faceText = (viaFont !== null ? positional[0] : positional[1]) ?? '';
          const sizeText = (viaFont !== null ? positional[1] : positional[0]) ?? '';
          const faceName = /^Face\.([A-Za-z_]\w*)$/.exec(faceText)?.[1] ?? '';
          const face = faces.get(faceName);
          const size = number(sizeText) ?? scalars.get(`CypressFont.${sizeText}`) ?? null;
          if (face === undefined || size === null) {
            throw new Error(
              `${file}:${declaration.line}: ${declaration.name} names face "${faceText}" and size `
                + `"${sizeText}", and one of them did not resolve`,
            );
          }
          emit({ kind: 'fontStyle', group: face.group, size, weight: face.weight, italic: face.italic });
          continue;
        }
        if (declaration.typeAnnotation === 'CGFloat' && flat.startsWith('{')) {
          skip(declaration, 'measured off the installed face at runtime, not a constant');
          continue;
        }
      }

      // ── Easing tuples ────────────────────────────────────────────────────────────────────
      if (declaration.typeAnnotation === '(Double, Double, Double, Double)') {
        const tuple = flat.startsWith('(') && flat.endsWith(')') ? flat.slice(1, -1) : '';
        const values = tuple.split(',').map((part) => number(part));
        const [x1, y1, x2, y2] = values;
        if (
          values.length === 4
          && x1 !== null && x1 !== undefined
          && y1 !== null && y1 !== undefined
          && x2 !== null && x2 !== undefined
          && y2 !== null && y2 !== undefined
        ) {
          emit({ kind: 'cubicBezier', points: [x1, y1, x2, y2] });
          continue;
        }
      }

      // ── Shadows ──────────────────────────────────────────────────────────────────────────
      if (rule.family === 'shadow') {
        const inside = callArgs(flat, 'CypressShadowStyle');
        if (inside !== null) {
          const { keyed } = args(inside);
          const shadowColor = color(keyed['hex'] ?? '', keyed['opacity']);
          const blur = number(keyed['blur'] ?? '');
          const y = number(keyed['offsetY'] ?? '');
          const x = keyed['offsetX'] === undefined ? 0 : number(keyed['offsetX']);
          if (shadowColor !== null && blur !== null && y !== null && x !== null) {
            emit({ kind: 'shadow', color: shadowColor, blur, x, y });
            continue;
          }
        }
        throw new Error(`${file}:${declaration.line}: unreadable shadow: ${flat.slice(0, 120)}`);
      }

      // ── Scalars, and the aliases that point at them ──────────────────────────────────────
      const annotation = declaration.typeAnnotation;
      if (annotation === 'CGFloat' || annotation === 'Double') {
        const literal = number(flat);
        const aliased = /^[A-Za-z_][\w.]*$/.test(flat)
          ? scalars.get(flat.includes('.') ? flat : `${declaration.scope}.${flat}`)
          : undefined;
        const value = literal ?? aliased ?? null;
        if (value !== null) {
          scalars.set(`${declaration.scope}.${declaration.name}`, value);
          if (declaration.isPrivate) {
            skip(declaration, PRIVATE_REASON);
          } else if (rule.family === 'motion' && declaration.scope === 'CypressMotion.Duration') {
            emit({ kind: 'seconds', value });
          } else if (annotation === 'Double' || UNITLESS_CGFLOATS.includes(`${declaration.scope}.${declaration.name}`)) {
            emit({ kind: 'number', value });
          } else {
            emit({ kind: 'length', px: value });
          }
          continue;
        }
      }

      if (rule.family === 'motion' && /^Animation\b/.test(flat)) {
        skip(
          declaration,
          'a composed SwiftUI Animation — one value pairing a curve with a duration, which CSS '
            + 'spells as two separate properties',
        );
        continue;
      }

      if ((annotation ?? '').startsWith('[') || flat.startsWith('[')) {
        skip(declaration, 'an array of values, not one custom property');
        continue;
      }

      throw new Error(
        `${file}:${declaration.line}: ${declaration.scope}.${declaration.name} matched no rule: `
          + `${(annotation ?? 'no annotation')} = ${flat.slice(0, 120)}`,
      );
    }
  }

  // Two tokens on one custom property is a silent overwrite in the emitted file.
  const seen = new Map<string, Token>();
  for (const token of tokens) {
    const previous = seen.get(token.cssName);
    if (previous !== undefined) {
      throw new Error(
        `--${token.cssName} is claimed by both ${previous.scope}.${previous.name} and `
          + `${token.scope}.${token.name}`,
      );
    }
    seen.set(token.cssName, token);
  }

  return { tokens, skipped, foreignScopes: [...foreign].sort() };
}

// ── Rendering ────────────────────────────────────────────────────────────────────────────────

/** A trailing-zero-free decimal: `0.5` → `0.5`, `1` → `1`, `12.50` → `12.5`. */
function decimal(value: number): string {
  return String(Number(value.toFixed(4)));
}

export function cssHex(value: ColorValue): string {
  const digits = value.hex.toString(16).toUpperCase().padStart(6, '0');
  if (value.alpha >= 1) return `#${digits}`;
  const r = (value.hex >> 16) & 0xff;
  const g = (value.hex >> 8) & 0xff;
  const b = value.hex & 0xff;
  return `rgb(${r} ${g} ${b} / ${decimal(value.alpha)})`;
}

/**
 * The CSS `box-shadow` value.
 *
 * `CypressShadowStyle(blur:)` takes the CSS blur and halves it for SwiftUI's Gaussian radius
 * (see the file header in `CypressShadow.swift`), so the *argument* is already the CSS number
 * and this reads it back without inverting anything. `theShadowsAgreeWithTheCssInTheirOwnDoc
 * Comments` in the test checks each one against the `rgba(…)` shorthand transcribed above it.
 */
export function cssShadow(value: Extract<TokenValue, { kind: 'shadow' }>): string {
  const x = value.x === 0 ? '0' : `${decimal(value.x)}px`;
  return `${x} ${decimal(value.y)}px ${decimal(value.blur)}px ${cssHex(value.color)}`;
}

function fontFamilyStack(postScript: string): string {
  const prefix = postScript.split('-')[0] ?? '';
  const fallbacks = GENERIC_FALLBACKS[prefix];
  if (fallbacks === undefined) {
    throw new Error(`no generic fallback stack for font family "${prefix}" — add it to GENERIC_FALLBACKS`);
  }
  return [`"${familyName(prefix)}"`, ...fallbacks].join(', ');
}

interface Declared {
  readonly property: string;
  readonly value: string;
}

/** The `:root` declarations a token contributes, in order. Empty for a face. */
export function declarationsFor(token: Token): readonly Declared[] {
  const value = token.value;
  switch (value.kind) {
    case 'color':
      return [{ property: token.cssName, value: cssHex(value.light) }];
    case 'length':
      return [{ property: token.cssName, value: `${decimal(value.px)}px` }];
    case 'seconds':
      return [{ property: token.cssName, value: `${decimal(value.value)}s` }];
    case 'number':
      return [{ property: token.cssName, value: decimal(value.value) }];
    case 'cubicBezier':
      return [{ property: token.cssName, value: `cubic-bezier(${value.points.map(decimal).join(', ')})` }];
    case 'shadow':
      return [{ property: token.cssName, value: cssShadow(value) }];
    case 'face':
      // A PostScript name is an iOS concept. What the web needs out of the face list is one
      // family stack per group, emitted once by `renderCss`, plus the weight each ramp style
      // resolves to — which reaches the CSS through the styles that name the face.
      return [];
    case 'fontStyle': {
      const declared: Declared[] = [
        { property: `${token.cssName}-family`, value: `var(--font-family-${value.group})` },
        { property: `${token.cssName}-size`, value: `${decimal(value.size)}px` },
        { property: `${token.cssName}-weight`, value: String(value.weight) },
      ];
      if (value.italic) declared.push({ property: `${token.cssName}-style`, value: 'italic' });
      return declared;
    }
  }
}

/** The dark override a color token contributes, or null when its dark value is its light one. */
export function darkDeclarationFor(token: Token): Declared | null {
  if (token.value.kind !== 'color') return null;
  const { light, dark } = token.value;
  if (light.hex === dark.hex && light.alpha === dark.alpha) return null;
  return { property: token.cssName, value: cssHex(dark) };
}

/**
 * One family stack per face group, derived from the faces.
 *
 * Throws when one group names two PostScript families: `serifRegular` and `serifSemiBold` must
 * both be Source Serif 4, or `--font-family-serif` means two things.
 */
export function familyStacks(tokens: readonly Token[]): readonly Declared[] {
  const byGroup = new Map<string, string>();
  for (const token of tokens) {
    if (token.value.kind !== 'face') continue;
    const prefix = token.value.postScript.split('-')[0] ?? '';
    const existing = byGroup.get(token.value.group);
    if (existing !== undefined && existing !== prefix) {
      throw new Error(`face group "${token.value.group}" names both ${existing} and ${prefix}`);
    }
    byGroup.set(token.value.group, prefix);
  }
  return [...byGroup.entries()].map(([group, prefix]) => ({
    property: `font-family-${group}`,
    value: fontFamilyStack(`${prefix}-Regular`),
  }));
}

const HEADER = `/*
 * GENERATED FILE — do not edit.
 *
 * Rendered from Cypress/DesignSystem/Tokens/*.swift by Tools/export_tokens.mjs.
 * web/test/tokens.test.ts re-runs that render against the Swift and fails when this file and
 * its source disagree, so an edit here is reverted by the next test run rather than kept.
 *
 * Dark mode is a \`prefers-color-scheme\` block and nothing else, because that is what the Swift
 * declares: every paired token is \`Color(UIColor { traits in traits.userInterfaceStyle == .dark })\`,
 * which resolves off the system setting. The app has no in-app appearance control — the only
 * \`preferredColorScheme\` calls in the whole target are in #Preview blocks — so an export with a
 * \`[data-theme]\` hook would be exporting a product decision the source does not contain.
 *
 * Only tokens whose dark value DIFFERS appear in the dark block. \`lightOnly\` and \`escalated\`
 * tokens resolve to the same value in both schemes by definition and are absent from it.
 */`;

/** The whole `tokens.css` file, byte for byte. */
export function renderCss(parsed: ParsedTokens): string {
  const lines: string[] = [HEADER, '', ':root {'];

  const stacks = familyStacks(parsed.tokens);
  if (stacks.length > 0) {
    lines.push('  /* font families — the PostScript faces the Swift names, as web stacks */');
    for (const stack of stacks) lines.push(`  --${stack.property}: ${stack.value};`);
    lines.push('');
  }

  for (const family of FAMILIES) {
    const inFamily = parsed.tokens.filter((token) => token.family === family);
    const declared = inFamily.flatMap((token) => declarationsFor(token));
    if (declared.length === 0) continue;
    lines.push(`  /* ${family} — ${inFamily.length} token${inFamily.length === 1 ? '' : 's'} */`);
    for (const entry of declared) lines.push(`  --${entry.property}: ${entry.value};`);
    lines.push('');
  }
  if (lines[lines.length - 1] === '') lines.pop();
  lines.push('}', '');

  const dark = parsed.tokens
    .map((token) => darkDeclarationFor(token))
    .filter((entry): entry is Declared => entry !== null);
  lines.push('@media (prefers-color-scheme: dark) {', '  :root {');
  lines.push(`    /* ${dark.length} of ${parsed.tokens.filter((t) => t.value.kind === 'color').length} color tokens change */`);
  for (const entry of dark) lines.push(`    --${entry.property}: ${entry.value};`);
  lines.push('  }', '}', '');

  return lines.join('\n');
}

/** The six files this export reads, relative to the repository root. */
export const TOKEN_FILES: readonly string[] = [
  'Cypress/DesignSystem/Tokens/CypressColor.swift',
  'Cypress/DesignSystem/Tokens/CypressRadius.swift',
  'Cypress/DesignSystem/Tokens/CypressSpacing.swift',
  'Cypress/DesignSystem/Tokens/CypressFont.swift',
  'Cypress/DesignSystem/Tokens/CypressMotion.swift',
  'Cypress/DesignSystem/Tokens/CypressShadow.swift',
];

/**
 * The two files in `Tokens/` this export deliberately does NOT read, and why.
 *
 * Named here and asserted in the test so that a seventh token file cannot appear in that
 * directory and be missed: the test lists the directory and requires every `.swift` in it to be
 * either read or on this list.
 */
export const NOT_EXPORTED: Readonly<Record<string, string>> = {
  'Cypress/DesignSystem/Tokens/CypressGradient.swift':
    'gradient recipes — multi-stop linear and radial fields with their own geometry. Not a '
    + 'custom property; the W1 hero needs them and they are W-C\'s to port.',
  'Cypress/DesignSystem/Tokens/TokenGallery.swift':
    'a SwiftUI gallery VIEW. Every value in it is read from the six files above; it declares no '
    + 'token of its own.',
};
