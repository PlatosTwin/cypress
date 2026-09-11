import { after, describe, it as declareTest } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { openPack, type Pack } from '../src/lib/pack/pack.ts';
import { packIdentity, treeByUUID, treeCount, treesInBounds } from '../src/lib/pack/queries.ts';
import { seedState } from '../src/lib/pack/localSeed.ts';
import { NEWEST_KNOWN_PACK_SCHEMA_VERSION } from '../src/lib/pack/versions.ts';

/**
 * The read layer against the real, 103 MB, checked-out seed.
 *
 * # How this behaves without the seed, stated up front because it is the thing to get wrong
 *
 * `Fixtures/seed/cypress-seed.sqlite` is git-ignored. `Tools/setup_worktree.sh` copies it into a
 * worktree; **CI has no copy and never will.** So this file has to answer a question CLAUDE.md
 * puts sharply: a test that silently skips when its fixture is absent is a green that means
 * nothing, and this project's signature failure is exactly that.
 *
 * Three decisions, each deliberate:
 *
 * 1. **This is not the only tier.** Every claim about how the read layer behaves — introspection,
 *    the city-name fallback, the refusals, the bounding box, the manifest — is made in
 *    `pack-open.test.ts`, `pack-queries.test.ts`, `pack-manifest.test.ts` and
 *    `pack-live-manifest.test.ts`, against packs built by executing the repository's own tracked
 *    `Fixtures/seed/schema.sql` and against the live catalog captured verbatim. Those run on a
 *    runner with no seed, and they fail there if they are broken.
 *
 *    **"Nothing is covered only here" was written as an assertion about the suite and it was
 *    false, twice.** Both times the fixture tier held a test for the behavior and the fixture
 *    agreed with the defect anyway:
 *
 *    * `treesInBounds`'s R*Tree join, wired to `t.neighborhood_id`, passed all seven fixture
 *      bounding-box tests — every fixture tree carried `neighborhood_id` 1, and the `lat`/`lon`
 *      re-test on `trees` re-derived the right answer from the wrong join. Only the Mission test
 *      below went red, and only on a machine holding the seed.
 *    * `packIdentity`'s `ORDER BY id LIMIT 1`, reversed to `DESC`, reddened nothing without the
 *      seed: no fixture carried a second `dim_city` row, which is the only shape that choice is
 *      about. Found by re-auditing the claim after the first one was reported.
 *
 *    Both fixtures were made discriminating (`packFixture.ts`'s `insertTrees` and its `fused`
 *    option) and both mutations are now red with the seed moved aside. The claim is therefore
 *    made in the form it can be held to: **the way to believe it is to mutate the behavior, move
 *    the seed aside, and require red** — not to read this comment.
 * 2. **What IS only here is scale and reality**: 198,625 real rows, a real R*Tree, a real
 *    two-id-space file, real species names. A fixture cannot pretend to those, so the assertions
 *    below are the ones whose answers were confirmed with the `sqlite3` CLI before this file was
 *    written.
 * 3. **The three states are distinguished, and only one of them is a skip.** A seed that is
 *    present but is NOT the pinned one is a **failure**, never a skip — a wrong artifact is worse
 *    than a missing one, because every count below would go red and send the reader hunting for a
 *    defect in the read layer. `absent` skips, and `node --test` prints the skip into the TAP
 *    summary, where `Tools/verify_web_test_log.sh` reports it in its verdict line and notes that
 *    "a change in these between two runs of the same tree is worth a second look" — the same
 *    posture the iOS side takes toward `CypressUITests`'s skip count.
 * 4. **The census below always runs**, in every environment, and checks the two lists of test
 *    names against **what this file actually registered with `node:test`** — not against a literal
 *    beside it. A skip that hides a deleted test is the one thing a skip count cannot catch on its
 *    own, and a count compared against a hand-maintained list in the same file cannot catch it
 *    either: that was the first version of this census, and deleting a test with the list left
 *    alone was green in both tiers.
 *
 *    The second version added a regex over this file's own bytes, to catch a test registered
 *    directly instead of through the helper, and the comment beside it said that closed the hole.
 *    **It did not**, and the review that checked it is why this one is built differently: the
 *    pattern recognized a single spelling, missed nine others — including the multi-line form this
 *    very file already uses for a long name — and reddened on a doc comment that merely described
 *    the rule. Registration now goes through one wrapper that `node:test` can only be reached
 *    through, so the census compares behavior rather than text; see `it` and `registrations` below
 *    for what that does and does not reach.
 */
const state = seedState();
const havePinnedSeed = state.kind === 'present';

/** Confirmed with `sqlite3 Fixtures/seed/cypress-seed.sqlite` before this file was written. */
const MEASURED = {
  treeRows: 198_625,
  softDeletedRows: 0,
  speciesRows: 731,
  neighborhoodRows: 41,
  rtreeRows: 198_625,
  idSpaces: ['sf', 'us-ca-sj'],
  dimCityRows: 2,
  /** The pin's own claim, which is generation 16 — NOT 17, and that difference is a finding. */
  pinnedGeneration: 16,
} as const;

/**
 * Every test in this file that needs the seed, by name, **in declaration order**.
 *
 * The census compares this against the names `seedDependent` handed to `node:test`, so it is a
 * declaration that gets checked rather than a number that gets believed. Order-sensitive on
 * purpose: a mismatch then names the position as well as the name, which is the difference between
 * "the list is wrong" and "the list is wrong HERE". Reordering the tests means reordering the list.
 */
const SEED_DEPENDENT_TESTS: readonly string[] = [
  'opens the pinned seed exactly as the phone opens a pack',
  'is generation 16 by shape, which is a generation behind every published pack',
  'states no generation about itself, and its PRAGMA user_version is 0',
  'holds the row counts the sqlite3 CLI reported',
  'reads a real tree, by a uuid taken from the file itself',
  'a bounding box over the Mission returns real trees, all inside it',
  'is a fused two-city seed, which a published pack is not',
  'refuses every write, on a byte-identical copy of the real file',
  'the pinned seed is byte-for-byte what pinned-seed.json pins, after every read above',
];

/**
 * Every test in this file that does NOT need the seed, by name, in declaration order.
 *
 * The other half of the census, and the half that closes the evasions a list of seed-gated names
 * cannot see on its own. A test gated inside its own BODY (`if (!havePinnedSeed) return;`, or
 * `t.skip()`) registers ungated and would never appear in `SEED_DEPENDENT_TESTS` — but it does
 * appear here, and it is not one of these four.
 */
const ALWAYS_RUN_TESTS: readonly string[] = [
  'the census: this file registered the tests it says it does, gated as it says they are',
  'the pin file is readable and states what it must, whether or not the seed is here',
  'a seed that is present and is not the pinned one is a failure, not a skip',
  'says out loud which tier this run is',
];

/** The sha256 of a file on disk, read whole. Used on a 103 MB file, twice, and that is fine. */
function sha256Of(path: string): string {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

/** This file, by name, so its own frames can be picked out of a stack. */
const OWN_FILE = basename(fileURLToPath(import.meta.url));

/**
 * Where in this file a test was declared, read off the stack at registration time.
 *
 * Routing every registration through one wrapper costs the runner's per-test `location`, which
 * becomes the wrapper's line for every test in the file — a real loss of a navigation aid. This
 * buys it back: the frames belonging to this file are `it` (here), possibly `seedDependent`, and
 * then the `describe` callback, which is the line the reader wants. Taking the LAST of them lands
 * on that line for a direct call and for a helper call alike.
 */
function declarationSite(): string {
  const frames = (new Error().stack ?? '').split('\n').filter((line) => line.includes(OWN_FILE));
  const last = frames[frames.length - 1];
  if (last === undefined) return 'an unreadable stack';
  const match = /([^/\\() ]+:\d+:\d+)\)?\s*$/.exec(last);
  return match?.[1] ?? last.trim();
}

type TestBody = () => void | Promise<void>;
type SeedGate = { readonly skip: boolean | string };

/**
 * What this file handed `node:test`, recorded by the **only** path it has to it.
 *
 * `node:test`'s `it` is imported under a different name and is called in exactly one place — the
 * wrapper below. So a registration reaches the runner only by passing through code that records
 * it, whatever the call looks like in the source: on one line or five, single- or double-quoted,
 * `{ skip }` or `{ skip: havePinnedSeed ? false : 'why' }`, direct or through another helper.
 *
 * **This replaces a regex over this file's own bytes, which claimed to close the same hole and did
 * not.** That pattern matched one formulation — `it('name', { skip }` on a single line — and the
 * review that checked it found nine spellings it missed (a multi-line call in the shape this file
 * itself already uses for a long name, double quotes, `it.skip`, `{ skip: skip }`, a second
 * wrapper, in-body gating) and three it falsely tripped on (prose describing the rule,
 * commented-out code, an unrelated `{ skip }`). A guard that reddens on its own documentation gets
 * deleted by whoever hits it; and `web/` carries no linter and no formatter, so nothing keeps a
 * future author on the one spelling a pattern can see. The difference is that the census is now a
 * statement about BEHAVIOR — what the runner was given — rather than about text.
 *
 * **What it still cannot see**, stated because the last version of this comment overstated its
 * reach: a registration made by calling `declareTest` directly, or by importing `node:test` a
 * second time under another name. Both are a visible edit to the top of this file plus a call
 * that does not look like its neighbors, which is what "deliberate" means here — the same standing
 * as editing `SEED_DEPENDENT_TESTS` to cover a deletion. The claim is that no ORDINARY spelling of
 * a test registration escapes, not that escape is impossible.
 */
const registrations: {
  readonly name: string;
  readonly gate: SeedGate | undefined;
  readonly handle: unknown;
}[] = [];

function it(name: string, body: TestBody): unknown;
function it(name: string, gate: SeedGate, body: TestBody): unknown;
function it(name: string, second: TestBody | SeedGate, third?: TestBody): unknown {
  const gate = typeof second === 'function' ? undefined : second;
  const body = typeof second === 'function' ? second : third;
  if (body === undefined) throw new TypeError(`"${name}" was registered with no body`);
  const site = declarationSite();
  const located = async (): Promise<void> => {
    try {
      await body();
    } catch (error) {
      // The navigation aid the wrapper took away, handed back on the one path that needs it.
      if (error instanceof Error) error.message = `${error.message}\n  declared at ${site}`;
      throw error;
    }
  };
  const handle = gate === undefined ? declareTest(name, located) : declareTest(name, gate, located);
  registrations.push({ name, gate, handle });
  return handle;
}

describe('the pinned seed — the tier that needs a 103 MB file CI does not have', () => {
  const seeded: Pack[] = [];
  after(() => {
    for (const pack of seeded) pack.close();
  });
  const withSeed = (): Pack => {
    const pack = openPack(state.path);
    seeded.push(pack);
    return pack;
  };
  const skip = havePinnedSeed
    ? false
    : `no pinned seed at ${state.path} (state: ${state.kind}) — run Tools/setup_worktree.sh`;
  /**
   * The one gate object, shared by every seed-dependent registration.
   *
   * Shared rather than rebuilt per call on purpose: the census compares by IDENTITY, so a test
   * gated on anything else — `{ skip: true }`, `{ skip: someOtherCondition }`, a fresh
   * `{ skip }` literal — is a different object and is named, even if its name is on the list.
   */
  const seedGate: SeedGate = { skip };

  /**
   * Registers a seed-dependent test: `it` above, with this file's one gate.
   *
   * It is a convenience and a single place to put the gate, no longer the census's only evidence —
   * `it` itself is what records, so a test written without this helper is seen all the same. What
   * this adds is that the gate cannot drift: every seed-dependent test carries the SAME `skip`
   * object, and the census asserts that identity rather than merely that some gate was passed.
   *
   * **What the census can catch**: a seed-dependent test deleted, renamed, reordered or
   * duplicated; a new one added; a test gated on something other than the seed; a test that gates
   * itself in its body instead of at registration; and an always-run test deleted or added. Every
   * one of those is red in both tiers, because registration happens whether a test then runs or
   * skips — which is the point, since the tier where a deleted test hides is the one where these
   * are skipped.
   *
   * **What it cannot catch**: a deletion that also edits `SEED_DEPENDENT_TESTS` and the literal
   * count beside it. That is three edits in one diff and it is what "deliberate" means here.
   */
  const seedDependent = (name: string, body: () => void): void => {
    it(name, seedGate, body);
  };

  // ── Always runs, in every environment ──────────────────────────────────────────────────────
  it('the census: this file registered the tests it says it does, gated as it says they are', () => {
    // Declared first and therefore printed first, but it reads `registrations` — which is complete
    // by the time any test BODY runs, because `describe`'s callback registers every subtest
    // synchronously before the runner starts them. Confirmed against a three-test specimen before
    // this was written, rather than assumed from the docs.
    const misdiagnosis = 'A deletion, a rename, a reorder or a new test is what this looks like — '
      + 'compare POSITION as well as spelling before concluding something was removed. The list '
      + 'is the declaration: fix whichever of the two is wrong.';
    assert.deepEqual(
      registrations.filter((entry) => entry.gate !== undefined).map((entry) => entry.name),
      [...SEED_DEPENDENT_TESTS],
      `the GATED tests this file handed to node:test are not the ones SEED_DEPENDENT_TESTS names. ${misdiagnosis}`,
    );
    // The other half, and the one a list of seed-gated names cannot supply: everything else this
    // file registered. A test that gates itself in its body rather than at registration lands
    // here, where it is not one of the four names above.
    assert.deepEqual(
      registrations.filter((entry) => entry.gate === undefined).map((entry) => entry.name),
      [...ALWAYS_RUN_TESTS],
      `the UNGATED tests this file handed to node:test are not the ones ALWAYS_RUN_TESTS names. ${misdiagnosis} `
        + 'A seed-dependent test that gates itself inside its own body registers ungated and '
        + 'arrives here rather than in the list above.',
    );
    assert.equal(
      SEED_DEPENDENT_TESTS.length,
      9,
      'the seed-dependent test list changed size. That is fine if it was deliberate — update this '
        + 'number in the same change — and is a deletion hiding behind a skip otherwise.',
    );
    assert.equal(
      ALWAYS_RUN_TESTS.length,
      4,
      'the always-run test list changed size; same rule as the line above.',
    );
    const names = registrations.map((entry) => entry.name);
    assert.equal(new Set(names).size, names.length, 'two tests in this file share a name');
    assert.ok(
      registrations.every((entry) => entry.handle instanceof Promise),
      'a name reached the census without node:test returning a test handle for it, so the helper '
        + 'recorded something it did not register',
    );
    // Every gated test carries THE seed gate, by identity — not merely some gate. A test skipped
    // for another reason, or pinned to `{ skip: true }` while its name stays on the list, is a
    // test that no longer runs in the tier that has the seed, and it would otherwise look
    // identical to one that does.
    assert.ok(
      registrations.filter((entry) => entry.gate !== undefined)
        .every((entry) => entry.gate === seedGate),
      'a test was gated on something other than this file\'s seed gate. Every seed-dependent test '
        + 'must share the one `seedGate` object, so that "skipped" means "no pinned seed" and '
        + 'nothing else.',
    );
    // And the gate is the one the environment calls for, which is what makes a skip in this run
    // mean the seed is absent rather than that someone left a `true` behind.
    assert.equal(seedGate.skip, havePinnedSeed ? false : skip);
    // ── The census's own reach, asserted rather than asserted ABOUT ────────────────────────────
    // It sees this file. A seed-gated test added to another file under `test/` is outside it
    // entirely — outside the lists and outside the wrapper — so the one thing worth checking is
    // that no other file has started down that road. This is exactly what it measures and no
    // more: whether any sibling test file mentions `seedState`, which is the only way to learn
    // whether the seed is here.
    const here = dirname(fileURLToPath(import.meta.url));
    const siblings = readdirSync(here, { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.test.ts') && entry.name !== OWN_FILE)
      .filter((entry) => readFileSync(join(here, entry.name), 'utf8').includes('seedState'))
      .map((entry) => entry.name);
    assert.deepEqual(
      siblings,
      [],
      'another test file under web/test/ refers to seedState, so it can tell whether the pinned '
        + 'seed is present — and a test gated on that in THAT file is invisible to this census, '
        + 'which only ever sees its own registrations. Either move it here, or give that file a '
        + 'census of its own.',
    );
  });

  it('the pin file is readable and states what it must, whether or not the seed is here', () => {
    // `pinned-seed.json` is tracked, so this runs in CI. It is what makes `mismatched` detectable
    // at all: without a pin there is nothing to compare a present file against, and every
    // seed-dependent assertion would be believing whatever file happened to be on disk.
    assert.ok(state.pin.bytes > 100_000_000, `the pin claims ${state.pin.bytes} bytes`);
    assert.equal(state.pin.sha256.length, 64);
    assert.ok(state.pin.treeCount > 0);
    assert.equal(state.pin.schemaVersion, MEASURED.pinnedGeneration);
    assert.deepEqual([...state.pin.idSpaces], [...MEASURED.idSpaces]);
  });

  it('a seed that is present and is not the pinned one is a failure, not a skip', () => {
    // The assertion that turns the wrong-artifact case into a red. It runs everywhere: in CI the
    // state is `absent` and this passes trivially; on a machine holding the wrong seed it is the
    // only thing standing between a stale 103 MB file and a report about a defect that is not
    // there. CLAUDE.md: "never trust an artifact you did not watch being produced".
    assert.notEqual(
      state.kind,
      'mismatched',
      state.kind === 'mismatched'
        ? `${state.path} is not the seed Fixtures/seed/pinned-seed.json pins: ${state.detail}. `
          + 'Re-run Tools/setup_worktree.sh from the main checkout. Do NOT relax this — every '
          + 'count in this file was measured against the pinned bytes.'
        : '',
    );
  });

  it('says out loud which tier this run is', () => {
    // Not decoration. A reader of a green log needs to know whether the 198,625-row assertions
    // ran, and the TAP body is where they will look.
    const summary = havePinnedSeed
      ? `the pinned seed is present at ${state.path}; the ${SEED_DEPENDENT_TESTS.length} `
        + 'seed-dependent tests below ran'
      : state.kind === 'mismatched'
        ? `THE WRONG SEED is at ${state.path} — ${state.detail}. The `
          + `${SEED_DEPENDENT_TESTS.length} seed-dependent tests below did not run, AND this run `
          + 'is RED: a wrong artifact is a failure, not a skip.'
        : `NO PINNED SEED at ${state.path}; the ${SEED_DEPENDENT_TESTS.length} seed-dependent `
          + 'tests below are SKIPPED. Every behavior they cover is also covered by the '
          + 'fixture-built packs in pack-open.test.ts and pack-queries.test.ts, which ran.';
    console.log(`CYPRESS-WEB-PACK: ${summary}`);
    assert.ok(summary.length > 0);
  });

  // ── Needs the seed ─────────────────────────────────────────────────────────────────────────
  seedDependent('opens the pinned seed exactly as the phone opens a pack', () => {
    // `immutable: true` here, unlike every fixture test: the pinned seed is a real, immutable
    // artifact at a path nothing writes, which is the case `immutable=1` is sound for.
    const pack = withSeed();
    assert.equal(pack.schema.usesIntegerPrimaryKeys, true);
    assert.equal(pack.schema.treeIdentityColumn, 'uuid');
    assert.equal(pack.schema.rtreeJoinColumn, 'id');
    assert.equal(pack.schema.hasIdSpace, true);
    assert.equal(pack.schema.hasSpeciesTrigrams, true);
    assert.equal(pack.schema.hasInventorySource, true);
    assert.equal(pack.schema.hasCityRaw, true);
  });

  seedDependent('is generation 16 by shape, which is a generation behind every published pack', () => {
    // **The finding this tier exists to pin.** The checked-in seed has `dim_city` and no
    // `dim_region`; every pack in the live catalog is generation 17. The two are different
    // generations at the same time, on purpose — `SeedDatabase` says the app "deliberately bundles
    // an s16 seed while attaching s17 packs beside it" — and a read layer that assumed one
    // generation would be wrong about whichever file it was not written for.
    const pack = withSeed();
    assert.equal(pack.schema.hasDimCity, true, 'the pinned seed has no dim_city; it is pre-16');
    assert.equal(
      pack.schema.hasRegions,
      false,
      'the pinned seed now HAS dim_region and trees.region_id, so it is a generation 17 file and '
        + 'Fixtures/seed/pinned-seed.json still says schema_version 16. Re-pin before trusting '
        + 'anything else in this file.',
    );
    assert.equal(pack.schema.hasCivicShortNames, false, '16 dropped id_spaces.short_name');
    // What that means for a read: the city resolves through dim_city, not through short_name.
    assert.equal(packIdentity(pack).cityDisplayName, 'San Francisco');
    assert.equal(packIdentity(pack).packId, null, 'a pre-17 file names no published region');
    assert.ok(MEASURED.pinnedGeneration < NEWEST_KNOWN_PACK_SCHEMA_VERSION);
  });

  seedDependent('states no generation about itself, and its PRAGMA user_version is 0', () => {
    // Two facts that are easy to assume and are both false of this file.
    //
    // 1. The SOURCE seed carries no `publish_schema_version`: `Tools/publish_cities.py` writes that
    //    key into each PACK it cuts, not into the seed it cuts them from. So the file states
    //    nothing, and `openPack` reads that as 0 — "an ancient file, attachable, just never
    //    preferable" — which is why the shape assertion above is the one that establishes 16.
    // 2. `PRAGMA user_version` is 0. It belongs to the third version space, the writable
    //    database's migration counter, and a pack has nothing to say in it.
    const pack = withSeed();
    assert.equal(pack.meta.get('publish_schema_version'), undefined);
    assert.equal(pack.statedSchemaVersion, 0);
    const row = pack.db.prepare('PRAGMA user_version').get();
    assert.equal(Number((row as Record<string, unknown>)['user_version']), 0);
    // It is not an empty seed_meta, though — the table is there and full.
    assert.ok(pack.meta.size > 50, `seed_meta holds ${pack.meta.size} rows`);
    assert.equal(pack.meta.get('generator'), 'Tools/build_seed.py');
  });

  seedDependent('holds the row counts the sqlite3 CLI reported', () => {
    // Every number here was read with `sqlite3` before this file was written, which is the
    // calibration that separates a measurement from whatever the query happened to return.
    const pack = withSeed();
    const count = (sql: string): number =>
      Number((pack.db.prepare(sql).get() as Record<string, unknown>)['n']);
    assert.equal(count('SELECT COUNT(*) AS n FROM trees'), MEASURED.treeRows);
    assert.equal(
      count('SELECT COUNT(*) AS n FROM trees WHERE deleted_at IS NOT NULL'),
      MEASURED.softDeletedRows,
    );
    assert.equal(count('SELECT COUNT(*) AS n FROM species'), MEASURED.speciesRows);
    assert.equal(count('SELECT COUNT(*) AS n FROM neighborhoods'), MEASURED.neighborhoodRows);
    assert.equal(count('SELECT COUNT(*) AS n FROM trees_rtree'), MEASURED.rtreeRows);
    // The layer's own count agrees, and agrees with the pin — a third party to the same number.
    assert.equal(treeCount(pack), MEASURED.treeRows);
    assert.equal(treeCount(pack), state.pin.treeCount);
  });

  seedDependent('reads a real tree, by a uuid taken from the file itself', () => {
    // The uuid is drawn from the seed rather than hard-coded, because a hard-coded one pins a row
    // that a rebuild may legitimately renumber. What IS asserted hard is that the round trip
    // returns the SAME row the direct query did, field by field — which a query reading the wrong
    // table cannot satisfy, and which an empty result cannot satisfy either.
    const pack = withSeed();
    const sample = pack.db
      .prepare(
        'SELECT uuid, lat, lon, status FROM trees WHERE species_current IS NOT NULL '
          + 'AND address IS NOT NULL AND deleted_at IS NULL ORDER BY id LIMIT 1',
      )
      .get() as Record<string, unknown> | undefined;
    assert.ok(sample !== undefined, 'the seed has no tree with a species and an address');
    const uuid = String(sample['uuid']);
    assert.match(uuid, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
      'the seed stores a uuid that is not lowercase canonical, which lower(?) relies on');

    const tree = treeByUUID(pack, uuid);
    assert.ok(tree !== null, `treeByUUID found nothing for a uuid read out of the same file`);
    assert.equal(tree.uuid, uuid);
    assert.equal(tree.latitude, Number(sample['lat']));
    assert.equal(tree.longitude, Number(sample['lon']));
    assert.equal(tree.status, String(sample['status']));
    assert.ok(
      tree.speciesScientificName !== null && tree.speciesScientificName.length > 0,
      'the species join returned nothing for a tree whose species_current is not null',
    );
    assert.equal(tree.cityName, 'San Francisco', 'the dim_city join did not resolve');
    // And uppercase still matches, on the real BINARY index.
    assert.equal(treeByUUID(pack, uuid.toUpperCase())?.uuid, uuid);
  });

  seedDependent('a bounding box over the Mission returns real trees, all inside it', () => {
    const pack = withSeed();
    const bounds = {
      minLatitude: 37.75,
      maxLatitude: 37.77,
      minLongitude: -122.43,
      maxLongitude: -122.41,
    };
    const rows = treesInBounds(pack, bounds, 200);
    // Non-zero, which is the whole anti-vacuous point, and the number is a floor rather than an
    // equality: a re-pinned seed may legitimately hold more trees in the Mission, and an equality
    // would fail for a reason that is not a defect. A floor of 100 over a box this size cannot be
    // satisfied by a query that returned nothing.
    assert.ok(rows.length >= 100, `the Mission box returned ${rows.length} trees; expected 100+`);
    assert.equal(rows.length, 200, 'the limit was not applied');
    for (const row of rows) {
      assert.ok(row.latitude >= bounds.minLatitude && row.latitude <= bounds.maxLatitude,
        `${row.uuid} is at lat ${row.latitude}, outside the box`);
      assert.ok(row.longitude >= bounds.minLongitude && row.longitude <= bounds.maxLongitude,
        `${row.uuid} is at lon ${row.longitude}, outside the box`);
    }
    // ── The R*Tree's own false positives, which the loop above could not see ──────────────────
    //
    // The R*Tree is a CONSERVATIVE pre-filter — it stores 32-bit floats and rounds every box
    // outward — so for this box it hands back rows whose real coordinates are outside it, and the
    // `lat`/`lon` re-test in `treesInBounds` is what removes them. The per-row loop above was
    // written for exactly that and could never see one: measured with `sqlite3`, the box has 8,990
    // live R*Tree candidates, 7 of them genuinely outside it, and NONE of those 7 in the first 200
    // by uuid — so the loop is clipped by the `LIMIT 200` the line above asserts. Removing the
    // re-test entirely was green in both tiers.
    //
    // So: count the two sets in SQL, assert there is something to remove, and then ask the read
    // layer for the whole box.
    const box = [
      bounds.minLatitude, bounds.maxLatitude, bounds.minLongitude, bounds.maxLongitude,
    ] as const;
    const candidates = (retest: boolean): number => {
      const row = pack.db.prepare(
        `SELECT COUNT(*) AS n FROM trees_rtree r JOIN trees t ON t.id = r.id
          WHERE r.max_lat >= ? AND r.min_lat <= ? AND r.max_lon >= ? AND r.min_lon <= ?
            AND t.deleted_at IS NULL
            ${retest ? 'AND t.lat BETWEEN ? AND ? AND t.lon BETWEEN ? AND ?' : ''}`,
      ).get(...(retest ? [...box, ...box] : [...box])) as Record<string, unknown>;
      return Number(row['n']);
    };
    const prefiltered = candidates(false);
    const trulyInside = candidates(true);
    assert.ok(
      prefiltered > trulyInside,
      `the R*Tree returns ${prefiltered} rows for this box and ${trulyInside} of them are really `
        + 'inside it, so on this seed the pre-filter over-returns nothing and the assertion below '
        + 'proves nothing about the re-test. Pick a box whose float32 boxes do escape it.',
    );
    assert.equal(
      treesInBounds(pack, bounds, prefiltered + 1).length,
      trulyInside,
      `asked for the whole box, the read layer returned a different number of trees than the `
        + `${trulyInside} whose lat/lon are actually inside it. The R*Tree pre-filter offers `
        + `${prefiltered}; the difference is what the lat/lon re-test on trees exists to remove.`,
    );
    // A box just outside the city returns nothing at all, which is the control that says the
    // filter is a filter.
    assert.deepEqual(
      treesInBounds(pack, {
        minLatitude: 37.75, maxLatitude: 37.77, minLongitude: -100.0, maxLongitude: -99.99,
      }, 200),
      [],
    );
  });

  seedDependent('is a fused two-city seed, which a published pack is not', () => {
    // The other difference between this file and a pack, and the reason `packIdentity` reads the
    // FIRST row rather than assuming one: `publish_cities.py` narrows both `dim_city` and
    // `dim_region` to the single unit a pack is for. The fused seed they are cut FROM carries all
    // of them, so a query written as "the pack's city" would silently pick one of two here.
    const pack = withSeed();
    const spaces = pack.db.prepare('SELECT id FROM id_spaces ORDER BY id').all()
      .map((row) => String((row as Record<string, unknown>)['id']));
    assert.deepEqual(spaces.sort(), [...MEASURED.idSpaces].sort());
    const cities = Number(
      (pack.db.prepare('SELECT COUNT(*) AS n FROM dim_city').get() as Record<string, unknown>)['n'],
    );
    assert.equal(cities, MEASURED.dimCityRows);
    assert.ok(cities > 1, 'the fused seed now holds one city, so it is shaped like a pack');
    assert.equal(pack.meta.get('id_spaces_in_file'), 'sf,us-ca-sj');
  });

  seedDependent('refuses every write, on a byte-identical copy of the real file', () => {
    // The fixture tests prove this on a file the suite wrote. This proves it on a 103 MB, real,
    // two-id-space artifact, which is the thing a fixture cannot pretend to.
    //
    // **On a COPY, and that is not fastidiousness.** This test used to probe
    // `Fixtures/seed/cypress-seed.sqlite` itself, and when the read-only property was red-proved
    // by removing `readOnly: true` the probes below did not merely fail — they SUCCEEDED, and
    // rewrote the pinned seed in place: still 108,249,088 bytes, sha256 `c9a440b2…` → `0c2b699a…`.
    // The size never moved, so only the hash half of the pin would have caught it, and the next
    // agent to run the suite would have been chasing a mismatched seed it did not cause. A
    // destructive probe belongs on a file the suite is allowed to destroy. `copyFileSync` of 103 MB
    // costs a fraction of a second and the copy is hashed before it is trusted, so it is the same
    // artifact in every sense this test cares about.
    const directory = mkdtempSync(join(tmpdir(), 'cypress-seed-write-probe-'));
    try {
      const copy = join(directory, 'cypress-seed.sqlite');
      copyFileSync(state.path, copy);
      assert.equal(sha256Of(copy), state.pin.sha256, 'the copy is not byte-identical to the seed');

      const pack = openPack(copy);
      try {
        for (const write of [
          "UPDATE trees SET status = 'removed' WHERE id = 1",
          'DELETE FROM trees WHERE id = 1',
          'CREATE TABLE scratch (a INTEGER)',
          'PRAGMA user_version = 99',
        ]) {
          assert.throws(() => pack.db.exec(write), `"${write}" was not refused on the real file`);
        }
      } finally {
        pack.close();
      }
      // A refusal that threw and wrote anyway is a shape `assert.throws` cannot see. Cheap here,
      // and it is the same assertion `pack-open.test.ts` makes about a session of reads.
      assert.equal(sha256Of(copy), state.pin.sha256, 'a write reached the file despite throwing');
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  seedDependent(
    'the pinned seed is byte-for-byte what pinned-seed.json pins, after every read above',
    () => {
      // Declared last, so it runs last — `node:test` runs a suite's subtests in declaration order.
      // But it does not DEPEND on running last: it compares against the pin rather than against a
      // value captured earlier in this file, so wherever it runs it is a true statement about the
      // artifact at that moment. `seedState()` is memoized over the whole process and cannot serve
      // here; this re-reads the bytes.
      //
      // `pack-open.test.ts:217` makes the same assertion about a fixture after a session of reads.
      // The real-seed tier had no equivalent, and the tier that had no equivalent is the one where
      // the artifact is irreplaceable and git-ignored.
      const size = statSync(state.path).size;
      assert.equal(
        size,
        state.pin.bytes,
        `${state.path} is now ${size} bytes and pinned-seed.json pins ${state.pin.bytes}. `
          + 'Something in this run wrote to it. Restore it with Tools/setup_worktree.sh.',
      );
      const actual = sha256Of(state.path);
      assert.equal(
        actual,
        state.pin.sha256,
        `${state.path} now hashes to ${actual} and pinned-seed.json pins ${state.pin.sha256}, at `
          + 'the same size. Something in this run wrote to it — the size is why a size check alone '
          + 'would not have told you. Restore it with Tools/setup_worktree.sh.',
      );
    },
  );
});
