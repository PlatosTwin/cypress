/**
 * Reading the ORIGINAL declarations back out of the repository, so a port cannot drift silently.
 *
 * Every module under `web/src/lib/` that this milestone adds is a second copy of a rule that
 * already exists in Swift or in Python. A second copy with no guard is exactly how
 * `Vitality.anchor`, `PRODUCT.md` §3 and `SCREENS.md` 05 §3 forked and stood forked for two weeks
 * (ticket #261). So the tests do not compare the TypeScript against a transcription of the Swift;
 * they compare it against the Swift, parsed at run time.
 *
 * Deliberately string-in / value-out with the file reading in ONE place (`repoFile`), for the
 * reason `src/lib/toolchain.ts` gives: a parser that reads its own repository cannot be calibrated
 * without one, and every parser here is calibrated in `test/sources.test.ts` against a specimen
 * whose answer was known before the parser saw it.
 *
 * ── What this CANNOT do, said plainly ────────────────────────────────────────────────────────
 *
 * The web suite runs on `web/**` changes (`.github/workflows/web.yml` `paths:`). A change to
 * `Cypress/Core/Rubric/Vitality.swift` alone therefore does not fire it, and the drift these
 * parsers exist to catch would be caught on the NEXT web change rather than on the change that
 * caused it. `sourcesTheWebSuiteReads` below is the list of files that gap covers, and
 * `test/sources.test.ts` asserts the workflow names every one of them in its `paths:` — which is
 * what closes it.
 *
 * **And these parsers read VALUES, not arithmetic.** A constant, a range, an enum's cases, a
 * switch table. They are blind to the expressions that combine those values and to the operators
 * that gate them, which is how two one-character edits to the real Swift passed the whole suite in
 * PR #173's review. `swiftDeclaration` below, and the tripwire table in `test/swiftDrift.test.ts`
 * that uses it, are the answer to that; both carry the full account. Value parsing and the
 * tripwire are complements, not alternatives — the first says what the Swift MEANS, the second
 * only that it has not moved.
 */

import { createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

/**
 * The repository root: `web/`'s parent.
 *
 * Asserted rather than assumed. A wrong root does not fail loudly — `readFileSync` throws, a
 * reader concludes "the test environment is odd", and the honest failure (the port has drifted)
 * never gets a chance to be the explanation. Two markers, because one could be a coincidence.
 */
export function repositoryRoot(): string {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  for (const marker of ['Cypress.xcodeproj', 'Tools/inventory_contract.py', 'web/package.json']) {
    if (!existsSync(join(root, marker))) {
      throw new Error(
        `${root} is not the Cypress repository root — it has no ${marker}. Every parity check `
          + `below reads the Swift and Python from here, and a wrong root makes all of them `
          + `unrunnable rather than wrong, which is the better of the two failures but still `
          + `needs fixing at the walk and not at the assertion.`,
      );
    }
  }
  return root;
}

/** The exact files the web suite reads to check its ports against. */
export const sourcesTheWebSuiteReads = [
  'Cypress/Core/Rubric/Vitality.swift',
  'Cypress/Core/Units/Quantity.swift',
  'Cypress/Core/Models/Geometry.swift',
  'Cypress/Core/Models/CoreEntity.swift',
  'Cypress/Core/Models/TreeMeasurement.swift',
  'Cypress/Core/Models/Species.swift',
  'Tools/inventory_contract.py',
  'Tools/build_seed.py',
  'docs/distilled/PRODUCT.md',
  'docs/distilled/SCREENS.md',
  // ── W-C. The public tree page borrows its gradient and its copy rather than authoring them ──
  //
  // `CypressGradient.swift` is already covered by `web.yml`'s `Cypress/DesignSystem/Tokens/**`
  // entry, and it is named here anyway: this list is what `sources.test.ts` matches against the
  // workflow literally, and a directory glob standing in for a file is a coupling nobody could
  // check. The five `Features`/`Components` files have no such glob behind them at all.
  'Cypress/DesignSystem/Tokens/CypressGradient.swift',
  'Cypress/DesignSystem/Components/MethodBadge.swift',
  'Cypress/DesignSystem/Components/SegmentedControl.swift',
  'Cypress/Features/TreeProfile/CityRecordPresentation.swift',
  'Cypress/Features/TreeProfile/TreeProfilePresentation.swift',
  'Cypress/Features/Site/SitePresentation.swift',
  // The NYC Data Mine disclaimer the public page must render verbatim (R36 (b), R78 rulings 2
  // and 3). `web/test/obligations.test.ts` parses all three strings out of it at run time.
  'Cypress/Features/Cities/CityDownloadsPresentation.swift',
] as const;

export function repoFile(relative: string): string {
  return readFileSync(join(repositoryRoot(), relative), 'utf8');
}

// ── Swift ───────────────────────────────────────────────────────────────────────────────────

class ParseFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ParseFailure';
  }
}

function fail(reason: string): never {
  throw new ParseFailure(reason);
}

export { ParseFailure };

/**
 * `… let <name>: Double = <number>` — the value, as a number.
 *
 * The type annotation is required by the pattern on purpose: `let publicPhotoGridM = 25` would be
 * an `Int` in Swift and a different declaration, and a parser that accepted both would report the
 * same answer for two things this repository keeps apart.
 */
export function swiftDoubleLet(source: string, name: string): number {
  const pattern = new RegExp(
    String.raw`\blet\s+${name}\s*:\s*Double\s*=\s*(-?[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][-+]?\d+)?)`,
  );
  const match = pattern.exec(source);
  if (match?.[1] === undefined) {
    fail(`no \`let ${name}: Double = <number>\` in the source`);
  }
  return Number(match[1].replace(/_/g, ''));
}

/**
 * A whole Swift declaration — signature through its closing brace — normalized and fingerprinted.
 *
 * ── Why this exists, and what it is NOT ──────────────────────────────────────────────────────
 *
 * The other Swift parsers on this page read VALUES: a constant, a range, an enum's cases, a
 * switch table. They are blind to everything between those values — the arithmetic that combines
 * them and the comparisons that gate them. PR #173's review demonstrated the hole with two
 * one-character edits to the real Swift that left the whole web suite green while the two
 * implementations genuinely diverged:
 *
 *   * `Geometry.swift`, `metersPerDegreeLat` from `111_320.0` to `111_000.0` — an un-annotated,
 *     function-local `let` that `swiftDoubleLet` cannot see by design. The two implementations
 *     then snapped the same coordinate 8.2 m apart in latitude, and the suite said 103 of 103.
 *   * `CoreEntity.swift`, `gpsAccuracyM <= …` to `<` — the D6 boundary. The test pins the number
 *     15 three times and never the comparison, so it stayed green.
 *
 * A fingerprint over the declaration's own text catches both, and catches the next one too,
 * because it is not a list of the things somebody thought to look for.
 *
 * **It is a tripwire, not a parity check.** It proves the Swift has not been edited since the
 * fingerprint was recorded. It cannot tell an edit that changes behavior from one that does not,
 * and it says nothing at all about whether the TypeScript agrees with the Swift — that is the
 * recorded `swift-reference.json` run's job, and re-recording BOTH is what a legitimate Swift
 * change owes. A cosmetic edit going red here is the tripwire working, not a false positive: a
 * human reads the diff and decides, which is exactly the step the review found missing.
 *
 * ── The normalization, and its one known blind spot ──────────────────────────────────────────
 *
 * Comments are dropped (a `//` line, a `/* … *\/` block, nested as Swift allows) and every run of
 * whitespace collapses to a single space, so reflowing a doc comment or re-indenting a body does
 * not trip the wire. Everything else is kept verbatim, operators and parentheses included.
 *
 * The scanner tracks `"…"` string literals so a `//` inside one is not read as a comment. It does
 * NOT know about `"""` multi-line literals. If one ever appears inside a fingerprinted
 * declaration the string state flips and the scan ends somewhere arbitrary — which produces a
 * different, still deterministic, fingerprint, so the wire trips rather than failing open. There
 * are none in the declarations listed today, and this is recorded so the next reader does not
 * have to re-derive whether it matters.
 *
 * The comment-insensitivity has to hold at the LOOKUP stage too, not only in the normalizer, or a
 * doc comment quoting the signature it documents counts as a second declaration and the caller is
 * told to "narrow the signature" for a pure-prose edit. `codeOnly` below is what makes that true;
 * it also blanks string-literal bodies, so a signature quoted inside a literal is likewise not a
 * declaration.
 *
 * ── What the bounding does NOT refuse ────────────────────────────────────────────────────────
 *
 * The scan takes the first balanced `{ … }` it meets after the signature, wherever that is. A
 * signature with no body of its own — a protocol requirement, a `let` — therefore fingerprints
 * through to the NEXT declaration's closing brace whenever one follows, and only fails when
 * nothing does. That is not a hole in the wire: the fingerprint then covers MORE text than the
 * row names, so it is strictly more sensitive, never less, and a red still points at the file and
 * the signature. But it means the refusal is "no balanced body anywhere after this", not "no body
 * of its own", and the calibration below is named for what it proves rather than for what the
 * refusal sounds like. Found by PR #173's delta review (D4). Every row in the tripwire table
 * today names a declaration that does have its own body, which is the condition under which the
 * bound is exact; adding a body-less one would need this widened first.
 */
export interface SwiftDeclaration {
  /** The declaration exactly as the file has it, signature through closing brace. */
  readonly source: string;
  /** The same with comments dropped and whitespace runs collapsed to one space. */
  readonly normalized: string;
  /** `sha256` of `normalized`, hex — what the tripwire table records. */
  readonly fingerprint: string;
}

/**
 * `source` with every comment body and string-literal body blanked to spaces, same length.
 *
 * Positions are preserved deliberately: an index found in this masked copy indexes the ORIGINAL,
 * so the body scan below still reads real source. Newlines survive so line structure does.
 *
 * This exists because the lookup used to scan raw text, which made the signature search sensitive
 * to prose. A doc comment that names the function it documents — an ordinary thing to write — made
 * `swiftDeclaration` report `appears more than once in the source — narrow the signature`, advice
 * that cannot be followed, for an edit that changed no code. Demonstrated on the real
 * `Geometry.swift` by PR #173's delta review (D5). Comment-insensitivity is claimed twice in
 * `swiftDrift.test.ts`, so it has to hold at the lookup stage and not only in the normalizer.
 */
function codeOnly(source: string): string {
  const out = source.split('');
  const blank = (index: number): void => {
    if (out[index] !== '\n') out[index] = ' ';
  };
  let mode: 'code' | 'line' | 'block' | 'string' = 'code';
  let blockDepth = 0;
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i] as string;
    const next = source[i + 1];
    if (mode === 'code') {
      if (c === '/' && next === '/') { mode = 'line'; blank(i); blank(i + 1); i += 1; continue; }
      if (c === '/' && next === '*') {
        mode = 'block'; blockDepth = 1; blank(i); blank(i + 1); i += 1; continue;
      }
      // The delimiters stay; only what is between them is blanked, so `return "x"` keeps its shape.
      if (c === '"') { mode = 'string'; continue; }
      continue;
    }
    if (mode === 'line') {
      if (c === '\n') { mode = 'code'; continue; }
      blank(i);
      continue;
    }
    if (mode === 'block') {
      if (c === '/' && next === '*') { blockDepth += 1; blank(i); blank(i + 1); i += 1; continue; }
      if (c === '*' && next === '/') {
        blockDepth -= 1; blank(i); blank(i + 1); i += 1;
        if (blockDepth === 0) mode = 'code';
        continue;
      }
      blank(i);
      continue;
    }
    // string
    if (c === '\\') { blank(i); if (i + 1 < source.length) blank(i + 1); i += 1; continue; }
    if (c === '"') { mode = 'code'; continue; }
    blank(i);
  }
  return out.join('');
}

export function swiftDeclaration(source: string, signature: string): SwiftDeclaration {
  // Both the search and the ambiguity count run over code only — see `codeOnly`. A signature
  // quoted in a doc comment is not a second declaration and must not be counted as one.
  const code = codeOnly(source);
  const first = code.indexOf(signature);
  if (first < 0) fail(`no \`${signature}\` in the source`);
  // Ambiguity is refused rather than resolved by taking the first. `Quantity.series` and
  // `MeasurementMethod.series` share a prefix in one file, and a parser that quietly picked one
  // of two would fingerprint whichever the file happened to list first.
  if (code.indexOf(signature, first + 1) >= 0) {
    fail(`\`${signature}\` appears more than once in the source — narrow the signature`);
  }

  let mode: 'code' | 'line' | 'block' | 'string' = 'code';
  let blockDepth = 0;
  let braceDepth = 0;
  let sawBrace = false;
  let end = -1;
  const out: string[] = [];

  for (let i = first; i < source.length; i += 1) {
    const c = source[i] as string;
    const next = source[i + 1];
    if (mode === 'code') {
      if (c === '/' && next === '/') { mode = 'line'; out.push(' '); i += 1; continue; }
      if (c === '/' && next === '*') { mode = 'block'; blockDepth = 1; out.push(' '); i += 1; continue; }
      if (c === '"') { mode = 'string'; out.push(c); continue; }
      if (c === '{') { braceDepth += 1; sawBrace = true; }
      if (c === '}') {
        braceDepth -= 1;
        out.push(c);
        if (sawBrace && braceDepth === 0) { end = i; break; }
        continue;
      }
      out.push(c);
      continue;
    }
    if (mode === 'line') { if (c === '\n') { mode = 'code'; out.push(' '); } continue; }
    if (mode === 'block') {
      if (c === '/' && next === '*') { blockDepth += 1; i += 1; continue; }
      if (c === '*' && next === '/') {
        blockDepth -= 1; i += 1;
        if (blockDepth === 0) { mode = 'code'; out.push(' '); }
        continue;
      }
      continue;
    }
    // string
    out.push(c);
    if (c === '\\') { const escaped = source[i + 1]; if (escaped !== undefined) out.push(escaped); i += 1; continue; }
    if (c === '"') mode = 'code';
  }

  if (end < 0) {
    fail(
      `\`${signature}\` has no balanced \`{ … }\` body after it — the declaration runs to the end `
        + `of the file, which means the signature matched something this parser cannot bound`,
    );
  }

  const normalized = out.join('').replace(/\s+/g, ' ').trim();
  return {
    source: source.slice(first, end + 1),
    normalized,
    fingerprint: createHash('sha256').update(normalized, 'utf8').digest('hex'),
  };
}

/** `… let <name>: ClosedRange<Double> = <low>...<high>`. */
export function swiftClosedRangeLet(
  source: string,
  name: string,
): { lowerBound: number; upperBound: number } {
  const number = String.raw`-?[0-9][0-9_]*(?:\.[0-9_]+)?`;
  const pattern = new RegExp(
    String.raw`\blet\s+${name}\s*:\s*ClosedRange<Double>\s*=\s*(${number})\.\.\.(${number})`,
  );
  const match = pattern.exec(source);
  if (match?.[1] === undefined || match[2] === undefined) {
    fail(`no \`let ${name}: ClosedRange<Double> = a...b\` in the source`);
  }
  return {
    lowerBound: Number(match[1].replace(/_/g, '')),
    upperBound: Number(match[2].replace(/_/g, '')),
  };
}

/**
 * The `case <name> = <raw>` lines of a Swift enum, in declaration order.
 *
 * Scoped to the named enum's own body by brace depth rather than by "everything after the header",
 * so a second enum further down the file cannot contribute rows — the mistake that makes a parser
 * agree with whatever the file happens to contain.
 */
export function swiftEnumCases(source: string, enumName: string): { name: string; raw: string }[] {
  const header = new RegExp(String.raw`\benum\s+${enumName}\b[^{]*\{`).exec(source);
  if (header === null) fail(`no \`enum ${enumName}\` in the source`);
  let depth = 0;
  let index = header.index + header[0].length - 1;
  const start = index;
  for (; index < source.length; index += 1) {
    const character = source[index];
    if (character === '{') depth += 1;
    else if (character === '}') {
      depth -= 1;
      if (depth === 0) break;
    }
  }
  if (depth !== 0) fail(`\`enum ${enumName}\` is not closed`);
  const body = source.slice(start + 1, index);
  const found: { name: string; raw: string }[] = [];
  const caseLine = /^\s*case\s+([A-Za-z_]\w*)\s*=\s*(?:"([^"]*)"|(-?\d+))\s*$/gm;
  let match: RegExpExecArray | null;
  while ((match = caseLine.exec(body)) !== null) {
    const name = match[1];
    const raw = match[2] ?? match[3];
    if (name === undefined || raw === undefined) continue;
    found.push({ name, raw });
  }
  if (found.length === 0) fail(`\`enum ${enumName}\` declares no \`case x = y\` rows`);
  return found;
}

/**
 * A `switch self { case .a: return <x> … }` inside the named computed property, as a table.
 *
 * `LengthUnit.metersPerUnit` and `LengthUnit.isMetric` are both written this way, and a case may
 * list several names (`case .millimeters, .centimeters, .meters: return true`), so each name in a
 * case gets the same value.
 */
export function swiftSwitchTable(source: string, propertyName: string): Map<string, string> {
  const header = new RegExp(String.raw`\bvar\s+${propertyName}\s*:[^{]*\{`).exec(source);
  if (header === null) fail(`no \`var ${propertyName}: … {\` in the source`);
  const body = source.slice(header.index);
  const table = new Map<string, string>();
  const caseLine = /^\s*case\s+((?:\.\w+\s*,\s*)*\.\w+)\s*:\s*return\s+(.+?)\s*$/gm;
  let match: RegExpExecArray | null;
  let scanned = 0;
  while ((match = caseLine.exec(body)) !== null) {
    // Stop at the end of this property: the first `}` at column 4 closes it in this codebase's
    // style. Cheaper and more legible than brace counting, and the calibration specimen in
    // `sources.test.ts` includes a second property below the first to prove it stops.
    const upTo = body.slice(scanned, match.index);
    if (/\n {4}\}/.test(upTo)) break;
    scanned = match.index;
    const names = match[1];
    const value = match[2];
    if (names === undefined || value === undefined) continue;
    for (const name of names.split(',')) {
      table.set(name.trim().replace(/^\./, ''), value);
    }
  }
  if (table.size === 0) fail(`\`var ${propertyName}\` has no \`case .x: return y\` rows`);
  return table;
}

/**
 * The `return "…"` string a `case .<name>:` maps to, inside the named computed property.
 *
 * `Vitality.label` and `Vitality.anchor` put the `return` on its own line, so this is the
 * multi-line shape of `swiftSwitchTable` and is kept separate rather than made general: one
 * parser that handles both shapes is one parser whose calibration has to cover both, and these
 * two are asserted against different things.
 */
export function swiftStringCases(source: string, propertyName: string): Map<string, string> {
  const header = new RegExp(String.raw`\bvar\s+${propertyName}\s*:\s*String\s*\{`).exec(source);
  if (header === null) fail(`no \`var ${propertyName}: String {\` in the source`);
  const body = source.slice(header.index);
  const end = /\n {4}\}/.exec(body);
  const scope = body.slice(0, end === null ? body.length : end.index);
  const table = new Map<string, string>();
  const pattern = /case\s+\.(\w+)\s*:\s*\n?\s*return\s+"((?:[^"\\]|\\.)*)"/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(scope)) !== null) {
    const name = match[1];
    const text = match[2];
    if (name === undefined || text === undefined) continue;
    table.set(name, text);
  }
  if (table.size === 0) fail(`\`var ${propertyName}: String\` has no \`case .x: return "…"\` rows`);
  return table;
}

// ── Python ──────────────────────────────────────────────────────────────────────────────────

/**
 * Every `<key>: IdSpace(id=…, identity_prefix=…)` in `ID_SPACES`, as key → prefix.
 *
 * Only the two fields that are load-bearing. `note` is prose and is explicitly not compared; the
 * TypeScript shortens it on purpose and says so.
 */
export function pythonIdSpacePrefixes(source: string): Map<string, string> {
  const start = source.indexOf('\nID_SPACES = {');
  if (start < 0) fail('no `ID_SPACES = {` in the source');
  const table = new Map<string, string>();
  const pattern = /IdSpace\(\s*\n\s*id="([^"]*)",\s*\n\s*identity_prefix="([^"]*)",/g;
  pattern.lastIndex = start;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(source)) !== null) {
    const id = match[1];
    const prefix = match[2];
    if (id === undefined || prefix === undefined) continue;
    table.set(id, prefix);
  }
  if (table.size === 0) fail('`ID_SPACES` holds no `IdSpace(id=…, identity_prefix=…)` rows');
  return table;
}

/** A `<NAME> = "<value>"` module constant. */
export function pythonStringConstant(source: string, name: string): string {
  const match = new RegExp(String.raw`^${name}\s*=\s*"([^"]*)"`, 'm').exec(source);
  if (match?.[1] === undefined) fail(`no \`${name} = "…"\` at module level`);
  return match[1];
}

/** `<NAME> = uuid.UUID("<value>")`. */
export function pythonUUIDConstant(source: string, name: string): string {
  const match = new RegExp(String.raw`^${name}\s*=\s*uuid\.UUID\("([^"]*)"\)`, 'm').exec(source);
  if (match?.[1] === undefined) fail(`no \`${name} = uuid.UUID("…")\` at module level`);
  return match[1];
}

// ── Markdown ────────────────────────────────────────────────────────────────────────────────

/**
 * Every `| level | … | anchor | …` row of the first table inside the section headed `heading`.
 *
 * A direct port of `RubricTable.anchors` in `CypressTests/VitalityRubricTests.swift`, including
 * why it finds the column by its HEADER (`Anchor …`) rather than by position: `PRODUCT.md` carries
 * a trailing band column and `SCREENS.md` a leading title column, and neither should need
 * per-document arithmetic.
 *
 * **The one place the port cannot be literal.** Swift's `Int(cells[0])` returns nil for anything
 * that is not entirely digits; `Number("")` is 0 and `parseInt("3 rows")` is 3. A literal port
 * would admit an empty leading cell as level 0 and a separator row as a level. The strict test is
 * therefore explicit, and `sources.test.ts` feeds the parser both specimens.
 */
export function markdownAnchorTable(markdown: string, heading: string): Map<number, string> {
  const lines = markdown.split('\n');
  const start = lines.findIndex((line) => line.startsWith(heading));
  if (start < 0) fail(`no line begins “${heading}”`);
  const rest = lines.slice(start + 1);
  const stop = rest.findIndex((line) => line.startsWith('#'));
  const section = stop < 0 ? rest : rest.slice(0, stop);

  const rows = section.filter((line) => line.trim().startsWith('|'));
  const header = rows[0];
  if (header === undefined) fail(`the section headed “${heading}” has no table`);
  const column = cells(header).findIndex((cell) => cell.startsWith('Anchor'));
  if (column < 0) {
    fail(
      `no column of “${heading}”'s table is headed “Anchor” — its header row reads `
        + `${JSON.stringify(cells(header))}`,
    );
  }

  const found = new Map<number, string>();
  for (const row of rows.slice(1)) {
    const parts = cells(row);
    const first = parts[0];
    const anchor = parts[column];
    if (first === undefined || anchor === undefined) continue;
    if (!/^\d+$/.test(first)) continue;
    const level = Number(first);
    if (level < 1 || level > 5) continue;
    found.set(level, anchor);
  }
  return found;
}

function cells(row: string): string[] {
  const parts = row.split('|');
  if (parts.length <= 2) return [];
  return parts.slice(1, -1).map((cell) => cell.trim().replace(/^`+|`+$/g, ''));
}

// ── Gradients (W-C) ─────────────────────────────────────────────────────────────────────────

/**
 * The two documents below both declare gradient stacks, in two notations, and
 * `web/src/lib/gradients.ts` is a third copy of some of them. The parsers here are what keep the
 * third copy honest — the same posture as every other parser on this page, and for the same
 * reason ticket #261 records.
 *
 * `RecipeColor`, `RadialStop` and the rest are re-declared here as plain data rather than imported
 * from `src/lib/gradients.ts`: a parser that returns the type the thing under test defines is a
 * parser that agrees with it by construction, and this one has to be able to disagree.
 */
export interface ParsedColor {
  readonly rgb: number;
  readonly alpha: number;
}

export interface ParsedRadial {
  readonly x: number;
  readonly y: number;
  readonly color: ParsedColor;
  readonly extent: number;
}

export interface ParsedRecipe {
  readonly radials: readonly ParsedRadial[];
  readonly base: { readonly degrees: number; readonly stops: readonly { color: ParsedColor; position: number }[] };
}

export interface ParsedScrim {
  readonly rgb: number;
  readonly from: number;
  readonly to: number;
}

/**
 * The lines under one `#### <heading>` of a markdown document, up to the next heading of the same
 * or a higher level.
 *
 * Bounded rather than "everything after", because `SCREENS.md` draws twenty screens and every one
 * of them has a gradient: an unbounded slice would let screen 04's viewfinder answer a question
 * about screen 03's hero, and the answer would look entirely reasonable.
 */
export function markdownSection(markdown: string, heading: string): string {
  const lines = markdown.split('\n');
  const start = lines.findIndex((line) => line.startsWith(heading));
  if (start < 0) fail(`no line begins “${heading}”`);
  const level = /^#+/.exec(heading)?.[0].length ?? 0;
  if (level === 0) fail(`“${heading}” is not a markdown heading, so its section cannot be bounded`);
  const rest = lines.slice(start + 1);
  const stop = rest.findIndex((line) => {
    const hashes = /^#+/.exec(line)?.[0].length;
    return hashes !== undefined && hashes <= level;
  });
  return (stop < 0 ? rest : rest.slice(0, stop)).join('\n');
}

function color(hex: string, alpha: number): ParsedColor {
  return { rgb: Number.parseInt(hex.replace(/^#|^0x/i, ''), 16), alpha };
}

/**
 * `radial(28% 46%, #4E8F6A 0→36%)` … `base `linear-gradient(180deg,#EAF0E2 0%,…)`` — one screen's
 * hero stack, as `SCREENS.md` §3 transcribes it.
 *
 * **Only the radials BEFORE the base are taken.** Every hero in the document is written radials
 * first and base last, and the screens that carry a second gradient — 03's activity thumbs, 13's
 * photo strip — write theirs further down the same section. Stopping at the base is what keeps a
 * thumb out of a hero's answer; without it screen 03's four-layer hero parses as five.
 */
export function markdownGradientRecipe(section: string): ParsedRecipe {
  // `base` is optional because §3 writes the stack two ways: screens 03 and W1 label the linear
  // layer `base`, screen 04 writes `Base: <radials>, <linear>` with the word on the whole line.
  // The FIRST linear-gradient in the section is the base in both spellings, and anything after it
  // — 04's ghost overlay, 13's photo strip — belongs to another element.
  const baseMatch = /(?:base\s+)?`linear-gradient\(\s*(\d+)deg\s*,([^`]*)\)`/.exec(section);
  if (baseMatch?.[1] === undefined || baseMatch[2] === undefined) {
    fail('the section has no `linear-gradient(<deg>, …)` base');
  }
  const beforeBase = section.slice(0, baseMatch.index);
  const radials: ParsedRadial[] = [];
  const radial = /radial\(\s*([\d.]+)%\s+([\d.]+)%\s*,\s*(#[0-9A-Fa-f]{6}|rgba\(([^)]*)\))\s+0→([\d.]+)%\s*\)/g;
  let found: RegExpExecArray | null;
  while ((found = radial.exec(beforeBase)) !== null) {
    const [, x, y, colorText, rgbaBody, extent] = found;
    if (x === undefined || y === undefined || colorText === undefined || extent === undefined) continue;
    radials.push({
      x: Number(x) / 100,
      y: Number(y) / 100,
      color: rgbaBody === undefined ? color(colorText, 1) : rgbaText(rgbaBody),
      extent: Number(extent) / 100,
    });
  }
  if (radials.length === 0) fail('the section declares no `radial(x% y%, C 0→N%)` layers');

  const stops = baseMatch[2]
    .split(',')
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .map((part) => {
      const stop = /^(#[0-9A-Fa-f]{6})(?:\s+([\d.]+)%)?$/.exec(part);
      if (stop?.[1] === undefined) fail(`\`${part}\` is not a \`#RRGGBB [N%]\` linear stop`);
      return { text: stop[1], position: stop[2] };
    });
  return {
    radials,
    base: {
      degrees: Number(baseMatch[1]),
      stops: stops.map((stop, index) => ({
        color: color(stop.text, 1),
        // A two-stop base is written without positions — `linear-gradient(170deg,#E4EBD8,#B9CDBC)`
        // — and CSS puts those at 0 and 1. Derived rather than defaulted to 0, because defaulting
        // would put both stops of every such base in the same place and still parse.
        position: stop.position === undefined
          ? (stops.length === 1 ? 0 : index / (stops.length - 1))
          : Number(stop.position) / 100,
      })),
    },
  };
}

function rgbaText(body: string): ParsedColor {
  const parts = body.split(',').map((part) => part.trim());
  const [r, g, b, a] = parts;
  if (r === undefined || g === undefined || b === undefined || a === undefined) {
    fail(`\`rgba(${body})\` does not have four components`);
  }
  return {
    rgb: (Number(r) << 16) | (Number(g) << 8) | Number(b),
    alpha: Number(a),
  };
}

/** `Scrim `rgba(16,32,22,0)→.5` from 48%.` — C2's scrim, as a screen's section states it. */
export function markdownScrim(section: string): ParsedScrim {
  const match = /[Ss]crim\s+`rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*0\s*\)→(\.?[\d.]+)`\s+from\s+([\d.]+)%/
    .exec(section);
  if (match === null) fail('the section has no `Scrim `rgba(r,g,b,0)→.N`` from M%` line');
  const [, r, g, b, to, from] = match;
  if (r === undefined || g === undefined || b === undefined || to === undefined || from === undefined) {
    fail('the scrim line matched without its numbers');
  }
  return {
    rgb: (Number(r) << 16) | (Number(g) << 8) | Number(b),
    from: Number(from) / 100,
    to: Number(to),
  };
}

/**
 * `static let <name> = CypressGradientRecipe(base: linear(…), radials: [CypressRadialStop(…)])`,
 * out of `Cypress/DesignSystem/Tokens/CypressGradient.swift`.
 *
 * The Swift writes the base FIRST and the radials after, because a SwiftUI `ZStack` draws its
 * first child at the back. CSS draws its first background layer at the front. This parser returns
 * the recipe in neither order — it returns the two halves named — so the renderer under test is
 * the only thing that decides an order, which is what makes getting it backwards a red.
 */
export function swiftGradientRecipe(source: string, name: string): ParsedRecipe {
  const header = new RegExp(String.raw`\blet\s+${name}\s*=\s*CypressGradientRecipe\s*\(`).exec(source);
  if (header === null) fail(`no \`let ${name} = CypressGradientRecipe(\` in the source`);
  const open = header.index + header[0].length - 1;
  let depth = 0;
  let end = -1;
  for (let i = open; i < source.length; i += 1) {
    const character = source[i];
    if (character === '(') depth += 1;
    else if (character === ')') {
      depth -= 1;
      if (depth === 0) { end = i; break; }
    }
  }
  if (end < 0) fail(`\`${name}\`'s CypressGradientRecipe(…) is not closed`);
  const body = source.slice(open + 1, end);

  const radials: ParsedRadial[] = [];
  const stop = /CypressRadialStop\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*(?:CypressGradient\.)?hex\(\s*0x([0-9A-Fa-f]{6})\s*(?:,\s*([\d.]+)\s*)?\)\s*,\s*([\d.]+)\s*\)/g;
  let found: RegExpExecArray | null;
  while ((found = stop.exec(body)) !== null) {
    const [, x, y, hexText, alpha, extent] = found;
    if (x === undefined || y === undefined || hexText === undefined || extent === undefined) continue;
    radials.push({
      x: Number(x),
      y: Number(y),
      color: color(hexText, alpha === undefined ? 1 : Number(alpha)),
      extent: Number(extent),
    });
  }
  if (radials.length === 0) fail(`\`${name}\` declares no CypressRadialStop layers`);

  return { radials, base: swiftLinearBase(body, name) };
}

/**
 * `linear(180, [(0xEAF0E2, 0), (0xCFE0D2, 0.55), (0x9DBFA6, 1)])` or the two-color shorthand
 * `linear(170, 0xE4EBD8, 0xB9CDBC)`, which the Swift itself expands to stops at 0 and 1.
 */
function swiftLinearBase(body: string, name: string): ParsedRecipe['base'] {
  const listed = /(?:CypressGradient\.)?linear\(\s*(\d+)\s*,\s*\[([^\]]*)\]\s*\)/.exec(body);
  if (listed?.[1] !== undefined && listed[2] !== undefined) {
    const stops: { color: ParsedColor; position: number }[] = [];
    const pair = /\(\s*0x([0-9A-Fa-f]{6})\s*,\s*([\d.]+)\s*\)/g;
    let found: RegExpExecArray | null;
    while ((found = pair.exec(listed[2])) !== null) {
      const [, hexText, position] = found;
      if (hexText === undefined || position === undefined) continue;
      stops.push({ color: color(hexText, 1), position: Number(position) });
    }
    if (stops.length === 0) fail(`\`${name}\`'s linear(…) base lists no (hex, position) stops`);
    return { degrees: Number(listed[1]), stops };
  }
  const shorthand = /(?:CypressGradient\.)?linear\(\s*(\d+)\s*,\s*0x([0-9A-Fa-f]{6})\s*,\s*0x([0-9A-Fa-f]{6})\s*\)/
    .exec(body);
  if (shorthand?.[1] === undefined || shorthand[2] === undefined || shorthand[3] === undefined) {
    fail(`\`${name}\` has no \`linear(<deg>, …)\` base in either of the two forms`);
  }
  return {
    degrees: Number(shorthand[1]),
    stops: [
      { color: color(shorthand[2], 1), position: 0 },
      { color: color(shorthand[3], 1), position: 1 },
    ],
  };
}

// ── Swift string constants (W-C) ────────────────────────────────────────────────────────────

/**
 * `static let <name> = "…"` — a copy constant, as written.
 *
 * Escape sequences are NOT decoded: the constants this reads are plain prose and a `\n` appearing
 * in one would be a different kind of value than the one this is for. It would come back as the
 * two characters, and the comparison against the TypeScript would fail rather than quietly
 * succeed on a string neither file contains.
 */
export function swiftStringLet(source: string, name: string): string {
  // The DECLARATION is found in the masked copy and the VALUE is read from the original, because
  // `codeOnly` blanks string bodies: running the value regex over the mask would return a string
  // of spaces, which is a parser that always agrees with nothing. Positions are preserved by
  // `codeOnly` precisely so a two-step lookup like this one is possible.
  const declaration = new RegExp(String.raw`\blet\s+${name}\s*(?::\s*String\s*)?=\s*"`);
  const found = declaration.exec(codeOnly(source));
  if (found === null) fail(`no \`let ${name} = "…"\` in the source`);
  const match = /^"((?:[^"\\]|\\.)*)"/.exec(source.slice(found.index + found[0].length - 1));
  if (match?.[1] === undefined) fail(`\`let ${name}\`'s string literal is not closed`);
  return match[1];
}

/**
 * The value of a `static let <name> = """ … """` — Swift's multi-line string literal.
 *
 * Written for one job: `CityDownloadsCopy.nycDisclaimerRequired`, the sentence
 * `Cypress/Features/Cities/CityDownloadsPresentation.swift` calls "the only string in this app that
 * must not be edited". A page that serves New York's data has to render it verbatim (R36
 * consequence (b), R78 ruling 3), so the web's copy of it must be compared against the Swift's and
 * not against a transcription — and the Swift writes it in the one literal form
 * `swiftStringLet` cannot read.
 *
 * **The two rules that make this a parser rather than a slice**, both of which the specimen in
 * `sources.test.ts` exercises because getting either wrong yields a string that merely looks right:
 *
 * 1. **The closing delimiter's indentation is stripped from every line.** Swift measures it off the
 *    line the closing `"""` sits on, so the literal's own text starts at that column. Slicing the
 *    raw lines instead would carry eight spaces of Swift source into the middle of a legal notice.
 * 2. **A trailing `\` joins to the next line with no newline.** That is how a one-paragraph
 *    sentence is written across four lines of Swift. Joining on `\n` regardless would put line
 *    breaks inside the City's sentence, which is not the sentence.
 *
 * Escapes other than the line continuation are left alone; this literal has none, and inventing an
 * unescaper for a case that does not arise would be code nothing here can check.
 */
export function swiftMultilineStringLet(source: string, name: string): string {
  const header = new RegExp(String.raw`\blet\s+${name}\s*(?::\s*String\s*)?=\s*"""[^\n]*\n`)
    .exec(source);
  if (header === null) fail(`no \`let ${name} = """\` in the source`);
  const body = source.slice(header.index + header[0].length);
  const end = body.indexOf('"""');
  if (end < 0) fail(`\`let ${name}\`'s multi-line literal is not closed`);
  const lines = body.slice(0, end).split('\n');
  // The closing delimiter's own line is the last one, and its leading whitespace is the indent
  // Swift strips from every line above it.
  const closing = lines.pop() ?? '';
  const indent = /^[ \t]*/.exec(closing)?.[0] ?? '';
  const stripped = lines.map((line) => (line.startsWith(indent) ? line.slice(indent.length) : line));
  let text = '';
  for (const [index, line] of stripped.entries()) {
    if (line.endsWith('\\')) {
      text += line.slice(0, -1);
      continue;
    }
    text += line;
    if (index < stripped.length - 1) text += '\n';
  }
  return text;
}

/**
 * The string members of a `static let <name>: Set<String> = [ … ]`, in declaration order.
 *
 * Bounded by the closing bracket rather than by a line count, because the set this exists to read
 * — `CityRecordCopy.noValueMarkers` — is written across three lines today and the number of lines
 * is not a fact anybody should have to preserve.
 */
export function swiftStringSetLet(source: string, name: string): string[] {
  const header = new RegExp(String.raw`\blet\s+${name}\s*:\s*Set<String>\s*=\s*\[`)
    .exec(codeOnly(source));
  if (header === null) fail(`no \`let ${name}: Set<String> = [\` in the source`);
  const open = header.index + header[0].length - 1;
  const close = source.indexOf(']', open);
  if (close < 0) fail(`\`${name}\` is not closed`);
  const members = [...source.slice(open + 1, close).matchAll(/"((?:[^"\\]|\\.)*)"/g)]
    .map((match) => match[1])
    .filter((value): value is string => value !== undefined);
  if (members.length === 0) fail(`\`${name}\` holds no string members`);
  return members;
}

/**
 * The `case .<name>: return "<text>"` rows of a `switch` inside a Swift closure — the shape
 * `SegmentedControl.status`'s `label:` argument is written in, which is neither a computed
 * property nor a top-level function and so is reachable by neither `swiftStringCases` nor
 * `swiftSwitchTable`.
 *
 * Scoped to the text between `marker` and the first line that closes a brace at the given indent,
 * for `swiftStringCases`' reason: an unscoped scan over a file with several `switch`es returns
 * whichever rows the file happens to list, which is a parser that agrees with everything.
 */
export function swiftClosureStringCases(source: string, marker: string): Map<string, string> {
  const code = codeOnly(source);
  const start = code.indexOf(marker);
  if (start < 0) fail(`no \`${marker}\` in the source`);
  if (code.indexOf(marker, start + 1) >= 0) {
    fail(`\`${marker}\` appears more than once in the source — narrow the marker`);
  }
  const rest = source.slice(start);
  const end = /\n {12}\}/.exec(rest);
  const scope = rest.slice(0, end === null ? rest.length : end.index);
  const table = new Map<string, string>();
  for (const match of scope.matchAll(/case\s+\.(\w+)\s*:\s*return\s+"((?:[^"\\]|\\.)*)"/g)) {
    const name = match[1];
    const text = match[2];
    if (name === undefined || text === undefined) continue;
    table.set(name, text);
  }
  if (table.size === 0) fail(`\`${marker}\` has no \`case .x: return "…"\` rows`);
  return table;
}
