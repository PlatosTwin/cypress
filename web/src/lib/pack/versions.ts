/**
 * The three version spaces, named separately because conflating them has cost this project real
 * time, and mirrored here rather than derived.
 *
 * CLAUDE.md states the rule and deliberately does not state the numbers: "There are three version
 * spaces and this bullet will not tell you their numbers … Read all three from the code, never
 * from this file", because that sentence has gone stale twice. The web is a fourth reader of those
 * spaces, so it gets the same treatment the Node version gets in `toolchain.ts` — **derive
 * nothing, assert that the copies agree**. The constants below are written down once; the parsers
 * below them read the same facts back out of the Swift and Python sources, and
 * `test/pack-versions.test.ts` fails the moment the two disagree.
 *
 * Reading the Swift at runtime instead was considered and is wrong for the same reason
 * `toolchain.ts` does not read `package.json`: the published web server has no `Cypress/`
 * directory beside it. The source of truth is the Swift; the constant is a copy; the test is what
 * makes the copy honest.
 *
 * ## The three, and which one this layer actually uses
 *
 * 1. **The published seed/city pack generation** — `SeedDatabase.newestKnownSchemaVersion`, the
 *    `s` in R37's `s<schema_version>` and the `schema_version` a manifest entry carries. **This is
 *    the only one this read layer enforces**, because a pack is the only thing it opens.
 * 2. **The manifest envelope format** — `CityManifest.knownFormat` (newest, the one the reader
 *    prefers) and `CityManifest.knownFormats` (every one it accepts), against
 *    `Tools/publish_cities.py MANIFEST_FORMAT` (the one the publisher writes). The app reads a
 *    set and the publisher writes one, because a format bump is dual-published for a release
 *    cycle rather than cut over (D8).
 * 3. **The writable database's migration counter** — `AppSchema.currentVersion`, the highest
 *    entry in `AppSchema.migrations`, stamped in that database's `PRAGMA user_version`. **The web
 *    has no writable database and never will through this layer**, so no constant for it is
 *    exported. Only a parser is, so that `test/pack-versions.test.ts` can read the live number and
 *    assert it is *not* equal to the other two — a tripwire that goes red the day someone copies
 *    the wrong integer in here.
 *
 * Note that a *pack file* does not carry its generation in `PRAGMA user_version`. Measured on the
 * pinned seed: `PRAGMA user_version` is 0. `user_version` belongs to space (3). A published pack
 * states its generation in `seed_meta.publish_schema_version`, written by
 * `Tools/publish_cities.py`; see `pack.ts`.
 */

/**
 * The newest pack generation this build was written against —
 * `SeedDatabase.newestKnownSchemaVersion`.
 *
 * A pack that states a *higher* generation is refused rather than guessed at, which is exactly
 * `CityLibrary.validateCityFile`'s rule. A pack that states a lower one is opened and read through
 * whatever it actually carries, which is what `seedSchema.ts` introspects for.
 */
export const NEWEST_KNOWN_PACK_SCHEMA_VERSION = 17;

/** The newest manifest envelope format this reader prefers — `CityManifest.knownFormat`. */
export const NEWEST_KNOWN_MANIFEST_FORMAT = 2;

/**
 * **Every** envelope format this reader accepts — `CityManifest.knownFormats`.
 *
 * More than one, and the extra member is not slack: format 1 stopped being *written* on
 * 2026-08-23 and the frozen `manifest.json` object it produced is still in the bucket. Refusing it
 * would break against that object and every archived mirror of it in exchange for nothing. An
 * unknown format is still refused outright; what changed is that 1 is no longer unknown.
 */
export const KNOWN_MANIFEST_FORMATS: ReadonlySet<number> = new Set([1, 2]);

// ── Readers for the sources the constants above are copies of ─────────────────────────────────
//
// String-in / number-out with no I/O, for the reason `toolchain.ts` gives: a module that reads its
// own repository is a module that cannot be tested without one. The tests open the files.

/**
 * The integer a Swift `public static let <name> = <n>` declares.
 *
 * Anchored to a declaration rather than to the name alone: `newestKnownSchemaVersion` appears
 * nine times in `SeedDatabase.swift`, once as the declaration and eight times inside the prose
 * that explains it, and a matcher that took the first mention would be reading a comment.
 */
export function swiftIntConstant(source: string, name: string): number {
  const re = new RegExp(
    `^\\s*(?:public\\s+)?static\\s+let\\s+${name}\\s*(?::\\s*\\w+\\s*)?=\\s*(-?\\d+)\\s*$`,
    'm',
  );
  const match = re.exec(source);
  if (match?.[1] === undefined) {
    throw new Error(`no Swift declaration "static let ${name} = <integer>" in that source`);
  }
  return Number(match[1]);
}

/**
 * The integers a Swift `public static let <name>: Set<Int> = [a, b]` declares, sorted.
 *
 * A separate reader from `swiftIntConstant` because a set is a different fact from a number, and
 * because `knownFormat` is a prefix of `knownFormats`: a lax matcher reads one declaration as the
 * other and reports `2` for both without ever failing.
 */
export function swiftIntSetConstant(source: string, name: string): readonly number[] {
  const re = new RegExp(
    `^\\s*(?:public\\s+)?static\\s+let\\s+${name}\\s*:\\s*Set<Int>\\s*=\\s*\\[([^\\]]*)\\]`,
    'm',
  );
  const match = re.exec(source);
  if (match?.[1] === undefined) {
    throw new Error(`no Swift declaration "static let ${name}: Set<Int> = [...]" in that source`);
  }
  const body = match[1].trim();
  if (body.length === 0) return [];
  return body
    .split(',')
    .map((part) => {
      const n = Number(part.trim());
      if (!Number.isInteger(n)) throw new Error(`"${part.trim()}" in ${name} is not an integer`);
      return n;
    })
    .sort((a, b) => a - b);
}

/** The integer a Python module-level `NAME = <n>` assigns. */
export function pythonIntConstant(source: string, name: string): number {
  const re = new RegExp(`^${name}\\s*=\\s*(-?\\d+)\\s*(?:#.*)?$`, 'm');
  const match = re.exec(source);
  if (match?.[1] === undefined) {
    throw new Error(`no Python assignment "${name} = <integer>" at module level in that source`);
  }
  return Number(match[1]);
}

/**
 * The highest `version:` among a Swift source's `Migration(version: N, …)` entries — which is how
 * `AppSchema.currentVersion` is computed (`migrations.map(\.version).max() ?? 0`).
 *
 * Every entry, then the maximum, rather than the last line in the file: the order of the array is
 * not something this parser should be asked to trust, and `max` is what the Swift does.
 *
 * It also returns how many it found, because a count is the only thing that separates "the highest
 * is 21" from "the regex matched one line and 21 was it". A sequence with a hole in it is a
 * reservation for a live branch (CLAUDE.md) and is deliberately NOT an error here.
 */
export function swiftMigrationVersions(source: string): readonly number[] {
  const found: number[] = [];
  const re = /Migration\(version:\s*(\d+)\s*,/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(source)) !== null) {
    if (match[1] !== undefined) found.push(Number(match[1]));
  }
  return found;
}
