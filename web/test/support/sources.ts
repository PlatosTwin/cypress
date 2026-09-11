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
 */

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
