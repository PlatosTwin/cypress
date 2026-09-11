import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  KNOWN_MANIFEST_FORMATS,
  NEWEST_KNOWN_MANIFEST_FORMAT,
  NEWEST_KNOWN_PACK_SCHEMA_VERSION,
  pythonIntConstant,
  swiftIntConstant,
  swiftIntSetConstant,
  swiftMigrationVersions,
} from '../src/lib/pack/versions.ts';
import { repositoryRoot } from '../src/lib/pack/localSeed.ts';

const read = (relative: string): string => readFileSync(`${repositoryRoot}${relative}`, 'utf8');

/**
 * TypeScript source with `/* … *\/` blocks and `//` lines removed.
 *
 * Crude on purpose and exercised on a specimen below: it does not understand a `//` inside a
 * string literal, which is fine for the one question it is asked — whether a *code* reference to
 * the writable database's migration counter exists — and would not be fine for anything else.
 */
function codeWithoutComments(source: string): string {
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
}

const SEED_DATABASE_SWIFT = 'Cypress/Data/Store/SeedDatabase.swift';
const CITY_MANIFEST_SWIFT = 'Cypress/Data/Cities/CityManifest.swift';
const APP_SCHEMA_SWIFT = 'Cypress/Data/Store/AppSchema.swift';
const PUBLISH_CITIES_PY = 'Tools/publish_cities.py';

describe('the constant parsers', () => {
  // Specimens first, with answers known before the parser saw them. Without these, every
  // assertion below agrees with whatever the Swift happens to say — including if the parser
  // matched the wrong line, or nothing at all.
  it('reads a Swift integer constant from its declaration', () => {
    assert.equal(swiftIntConstant('    public static let newestKnownSchemaVersion = 17', 'newestKnownSchemaVersion'), 17);
    assert.equal(swiftIntConstant('static let knownFormat = 2', 'knownFormat'), 2);
    assert.equal(swiftIntConstant('    public static let x: Int = -3', 'x'), -3);
  });

  it('does not read a Swift constant out of the prose that explains it', () => {
    // The trap this parser exists for: `newestKnownSchemaVersion` is mentioned nine times in
    // SeedDatabase.swift, once as a declaration and eight times inside doc comments. A matcher
    // that took the first mention of the name would be reading a comment and would have no way
    // to say so.
    const prose = [
      '/// A published city file newer than newestKnownSchemaVersion = 99 is refused.',
      '/// See the note on newestKnownSchemaVersion = 98 above.',
      '    public static let newestKnownSchemaVersion = 17',
    ].join('\n');
    assert.equal(swiftIntConstant(prose, 'newestKnownSchemaVersion'), 17);
  });

  it('refuses a name that has no declaration, rather than defaulting', () => {
    assert.throws(
      () => swiftIntConstant('/// newestKnownSchemaVersion is 17, honest', 'newestKnownSchemaVersion'),
      /no Swift declaration/,
    );
  });

  it('reads a Swift Set<Int> and does not confuse it with the scalar whose name it extends', () => {
    // `knownFormat` is a prefix of `knownFormats`. A lax matcher reads one declaration as the
    // other and reports the same number for both while never failing.
    const source = [
      '    public static let knownFormat = 2',
      '    public static let knownFormats: Set<Int> = [1, 2]',
    ].join('\n');
    assert.deepEqual(swiftIntSetConstant(source, 'knownFormats'), [1, 2]);
    assert.equal(swiftIntConstant(source, 'knownFormat'), 2);
    assert.throws(() => swiftIntSetConstant(source, 'knownFormat'), /no Swift declaration/);
  });

  it('reads a Python module-level integer, with or without a trailing comment', () => {
    assert.equal(pythonIntConstant('SEED_SCHEMA_VERSION = 17\n', 'SEED_SCHEMA_VERSION'), 17);
    assert.equal(pythonIntConstant('MANIFEST_FORMAT = 2  # the envelope\n', 'MANIFEST_FORMAT'), 2);
    assert.throws(() => pythonIntConstant('X = "2"\n', 'X'), /no Python assignment/);
  });

  it('strips comments without stripping code', () => {
    // The specimen this stripper needed before it could be believed: the check it feeds went red
    // on a doc comment that was explaining the very rule it enforces.
    const source = [
      '/** currentVersion is deliberately not used here. */',
      "const keep = 'user_version';",
      '// currentVersion again, in a line comment',
      'const alsoKeep = 1;',
    ].join('\n');
    const code = codeWithoutComments(source);
    assert.equal(/currentVersion/.test(code), false, 'a commented mention survived the strip');
    assert.ok(code.includes("const keep = 'user_version';"), 'the stripper ate a line of code');
    assert.ok(code.includes('const alsoKeep = 1;'));
  });

  it('collects every Migration(version:) and not just the last line', () => {
    const source = [
      'Migration(version: 19, name: "a", sql: v19),',
      'Migration(version: 21, name: "c", migrate: applyV21)',
      'Migration(version: 20, name: "b", sql: v20),',
    ].join('\n');
    assert.deepEqual([...swiftMigrationVersions(source)], [19, 21, 20]);
    assert.equal(Math.max(...swiftMigrationVersions(source)), 21);
  });
});

describe('the three version spaces, each against the source it copies', () => {
  // ── Space 1: the published pack generation ────────────────────────────────────────────────
  it('NEWEST_KNOWN_PACK_SCHEMA_VERSION equals SeedDatabase.newestKnownSchemaVersion', () => {
    const swift = swiftIntConstant(read(SEED_DATABASE_SWIFT), 'newestKnownSchemaVersion');
    assert.equal(
      NEWEST_KNOWN_PACK_SCHEMA_VERSION,
      swift,
      `web/src/lib/pack/versions.ts says the newest pack generation is `
        + `${NEWEST_KNOWN_PACK_SCHEMA_VERSION} and ${SEED_DATABASE_SWIFT} says ${swift}. The Swift `
        + `is the source of truth; change the constant, not this assertion. Until they agree the `
        + `web will refuse a pack the phone reads, or read one the phone refuses.`,
    );
  });

  it('and so does the publisher that stamps it into every pack', () => {
    // A third copy, in a third language. `publish_cities.py` writes this integer into each pack's
    // `seed_meta.publish_schema_version` and into each manifest entry's `schema_version`, so a
    // publisher ahead of the app is the exact condition `PackTooNewError` exists for — and it
    // must be a deliberate, visible state rather than a surprise.
    const python = pythonIntConstant(read(PUBLISH_CITIES_PY), 'SEED_SCHEMA_VERSION');
    assert.equal(
      python,
      NEWEST_KNOWN_PACK_SCHEMA_VERSION,
      `${PUBLISH_CITIES_PY} publishes generation ${python} and this build reads up to `
        + `${NEWEST_KNOWN_PACK_SCHEMA_VERSION}. If the publisher moved first this is expected and `
        + `the web must be taught the new generation before it can open what is being published.`,
    );
  });

  // ── Space 2: the manifest envelope format ─────────────────────────────────────────────────
  it('NEWEST_KNOWN_MANIFEST_FORMAT equals CityManifest.knownFormat', () => {
    const swift = swiftIntConstant(read(CITY_MANIFEST_SWIFT), 'knownFormat');
    assert.equal(NEWEST_KNOWN_MANIFEST_FORMAT, swift);
  });

  it('KNOWN_MANIFEST_FORMATS equals CityManifest.knownFormats — the set, not the newest', () => {
    // The app reads a SET and the publisher writes ONE, because a format bump is dual-published
    // for a release cycle rather than cut over (D8). Asserting only the newest would let the
    // reader silently stop accepting the frozen format-1 object still sitting in the bucket.
    const swift = swiftIntSetConstant(read(CITY_MANIFEST_SWIFT), 'knownFormats');
    assert.deepEqual([...KNOWN_MANIFEST_FORMATS].sort((a, b) => a - b), [...swift]);
    assert.ok(
      KNOWN_MANIFEST_FORMATS.size > 1,
      'this build reads exactly one manifest format. That may be correct one day, but it is not '
        + 'what CityManifest.knownFormats says today, and dropping a format is a decision.',
    );
  });

  it('the publisher writes a format this reader accepts', () => {
    const python = pythonIntConstant(read(PUBLISH_CITIES_PY), 'MANIFEST_FORMAT');
    assert.ok(
      KNOWN_MANIFEST_FORMATS.has(python),
      `${PUBLISH_CITIES_PY} writes manifest_format ${python} and this build reads `
        + `${[...KNOWN_MANIFEST_FORMATS].join(', ')}`,
    );
  });

  // ── Space 3: the writable database's migration counter, which the web must NOT import ─────
  it('AppSchema.currentVersion is a different number from the other two, and is not exported here', () => {
    // The tripwire. CLAUDE.md: "four tickets sat 'blocked on v14' for a week because one advanced
    // and the other was assumed to have." This test reads the live migration counter and asserts
    // it collides with neither of the two constants this module does export — so the day someone
    // copies the wrong integer into versions.ts, the suite says which two spaces were conflated
    // instead of the web quietly refusing every pack in the bucket.
    const migrations = swiftMigrationVersions(read(APP_SCHEMA_SWIFT));
    assert.ok(
      migrations.length >= 10,
      `only ${migrations.length} Migration(version:) entries were found in ${APP_SCHEMA_SWIFT}; `
        + 'this is reading the wrong file or the wrong pattern, and the assertions below would be '
        + 'about nothing.',
    );
    const appSchemaCurrentVersion = Math.max(...migrations);
    assert.notEqual(
      appSchemaCurrentVersion,
      NEWEST_KNOWN_PACK_SCHEMA_VERSION,
      `AppSchema.currentVersion is ${appSchemaCurrentVersion} and this module's pack generation `
        + `is ${NEWEST_KNOWN_PACK_SCHEMA_VERSION}. They are independent version spaces that have `
        + `been confused before. If they have genuinely met at the same integer this assertion is `
        + `wrong and needs rewriting with that stated — but check first that nobody copied one `
        + `into the other.`,
    );
    assert.notEqual(appSchemaCurrentVersion, NEWEST_KNOWN_MANIFEST_FORMAT);

    // And the reason it can be asserted this way at all: **no module that opens or queries a
    // pack refers to space 3**, so there is nothing for a future edit to accidentally compare
    // against. `versions.ts` is deliberately not in this list — naming all three spaces is its
    // whole job, and `swiftMigrationVersions` above is how this very test reads the live number.
    //
    // Comments are stripped before looking, because the first version of this check grepped the
    // raw text and went red on `versions.ts`'s own doc comment explaining why it does not use
    // this space. A check that cannot tell prose from code is answering a different question than
    // the one asked, and it looked exactly like a real finding.
    for (const file of [
      'web/src/lib/pack/pack.ts',
      'web/src/lib/pack/queries.ts',
      'web/src/lib/pack/seedSchema.ts',
      'web/src/lib/pack/manifest.ts',
    ]) {
      const code = codeWithoutComments(read(file));
      assert.equal(
        /AppSchema|currentVersion|user_version/.exec(code),
        null,
        `${file} refers to the writable database's migration counter in code. The web opens no `
          + 'writable database; a pack states its generation in seed_meta.publish_schema_version, '
          + "and a pack's own PRAGMA user_version is 0.",
      );
    }
  });

  it('a pack does not carry its generation in PRAGMA user_version, and the pin agrees', () => {
    // The measured fact behind the assertion above, pinned so it stops being folklore: the
    // repository's own pin states generation 16 for a file whose user_version is 0. `user_version`
    // belongs to the writable database; a pack's generation is in seed_meta. The user_version
    // half is measured in pack-real-seed.test.ts, where there is a real pack to measure.
    const pin: unknown = JSON.parse(read('Fixtures/seed/pinned-seed.json'));
    const stated = (pin as Record<string, unknown>)['schema_version'];
    assert.ok(
      typeof stated === 'number' && stated > 0,
      'Fixtures/seed/pinned-seed.json states no schema_version, so the pinned seed names no '
        + 'generation anywhere a reader can find it',
    );
    assert.ok(
      stated <= NEWEST_KNOWN_PACK_SCHEMA_VERSION,
      `the pinned seed is generation ${String(stated)} and this build reads up to `
        + `${NEWEST_KNOWN_PACK_SCHEMA_VERSION}`,
    );
  });
});

/**
 * The files this suite reads from outside `web/`, and the workflow that has to know about them.
 *
 * Every entry here is opened by a test in this directory. `.github/workflows/web.yml` triggers on
 * an allow-list of paths, so a file the suite reads that is NOT on that list is a guard CI skips
 * on exactly the diff it guards: bump `newestKnownSchemaVersion` in Swift, touch no `web/` path,
 * and the assertion that the web still reads the same generation does not run — it runs later, on
 * an unrelated web change, and looks like that change's fault.
 */
const READ_FROM_OUTSIDE_WEB: readonly string[] = [
  SEED_DATABASE_SWIFT,
  APP_SCHEMA_SWIFT,
  CITY_MANIFEST_SWIFT,
  PUBLISH_CITIES_PY,
  'Fixtures/seed/schema.sql',
  'Fixtures/seed/pinned-seed.json',
];

describe('the workflow triggers on every file this suite reads', () => {
  const workflow = read('.github/workflows/web.yml');

  /** The quoted entries under a `paths:` key, per block. One list per trigger. */
  function pathBlocks(yaml: string): readonly (readonly string[])[] {
    const blocks: string[][] = [];
    let current: string[] | null = null;
    for (const line of yaml.split('\n')) {
      if (/^\s*paths:\s*$/.test(line)) {
        current = [];
        blocks.push(current);
        continue;
      }
      if (current === null) continue;
      // The trailing `#…` is not decoration in this regex. `web.yml` writes at least one entry as
      // `- 'Cypress/DesignSystem/Tokens/**'   # web/test/tokens.test.ts re-renders these to CSS`,
      // and without the comment group that line matches no entry, is not a comment line either,
      // and so ENDS the block — silently dropping every path after it. The suite went red on
      // `SeedDatabase.swift`, the first entry below that line, and the report read as a missing
      // trigger rather than as a parser that had stopped reading. The specimen below carries the
      // same shape, so a future narrowing of this regex fails against a known answer first.
      const entry = /^\s*-\s*'([^']+)'\s*(?:#.*)?$/.exec(line);
      if (entry?.[1] !== undefined) {
        current.push(entry[1]);
        continue;
      }
      // A comment inside the list is still inside the list; anything else ends it.
      if (!/^\s*#/.test(line) && line.trim().length > 0) current = null;
    }
    return blocks;
  }

  it('the paths: parser reads a block and stops at the end of it', () => {
    // Specimen first, answer known before the parser saw it — including the three traps: a comment
    // between entries, an entry with a comment AFTER it on the same line, and a following key
    // whose value is also a quoted string.
    //
    // The middle one is in `web.yml` today and was not in this specimen when the parser was
    // written; the parser ended the block on it and reported the six entries below it as absent
    // from a filter that lists all six. A specimen that does not carry the shapes the real file
    // carries is a calibration of the wrong instrument.
    const specimen = [
      '  push:',
      '    paths:',
      "      - 'web/**'",
      '      # a comment inside the list',
      "      - 'Tools/x.sh'   # and a comment after an entry, on the entry's own line",
      "      - 'Fixtures/y.sql'",
      '  pull_request:',
      "    branches: ['main']",
      '    paths:',
      "      - 'web/**'",
    ].join('\n');
    assert.deepEqual(
      pathBlocks(specimen).map((block) => [...block]),
      [['web/**', 'Tools/x.sh', 'Fixtures/y.sql'], ['web/**']],
    );
  });

  it('every out-of-web file the suite reads is on both trigger lists', () => {
    const blocks = pathBlocks(workflow);
    // The control. Zero blocks, or one, means the parser found the wrong thing and every
    // assertion below would be about an empty list.
    assert.equal(
      blocks.length,
      2,
      `.github/workflows/web.yml has ${blocks.length} paths: block(s); this expects two (push and `
        + 'pull_request). Either a trigger was added, or this is reading the file wrong and is '
        + 'asserting nothing.',
    );
    for (const block of blocks) {
      // Calibration, run against this file rather than against a specimen: a path that is
      // deliberately NOT on the list must be reported as absent. Without it, a `includes` that
      // always answered true would satisfy every assertion below.
      assert.equal(
        block.includes('Cypress/Data/Store/TreeQueries.swift'),
        false,
        'the membership test says the workflow lists a file it does not list',
      );
      for (const path of READ_FROM_OUTSIDE_WEB) {
        assert.ok(
          block.includes(path),
          `web/test reads ${path} and .github/workflows/web.yml does not trigger on it, so a `
            + 'change to that file will not run this suite. Add it to BOTH paths: lists.',
        );
      }
    }
  });

  it('and every file on that list actually exists', () => {
    // A stale entry naming a moved file triggers on nothing and reads as if it guards something.
    for (const path of READ_FROM_OUTSIDE_WEB) {
      assert.doesNotThrow(() => read(path), `${path} is on the read list and is not there`);
    }
  });
});
