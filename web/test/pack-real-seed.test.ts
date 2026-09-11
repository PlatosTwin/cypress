import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';

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
 *    runner with no seed, and they fail there if they are broken. **Nothing in the suite is
 *    covered only here**, so a skipped tier costs scale, not coverage.
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
 * 4. **The census below always runs**, in every environment, and asserts how many tests this file
 *    holds. A skip that hides a deleted test is the one thing a skip count cannot catch on its
 *    own.
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
 * Every test in this file that needs the seed, by name.
 *
 * Named rather than counted in the abstract so the census below can assert both the number and
 * that it is this list — a count on its own goes stale silently when a test is renamed away.
 */
const SEED_DEPENDENT_TESTS: readonly string[] = [
  'opens the pinned seed exactly as the phone opens a pack',
  'is generation 16 by shape, which is a generation behind every published pack',
  'states no generation about itself, and its PRAGMA user_version is 0',
  'holds the row counts the sqlite3 CLI reported',
  'reads a real tree, by a uuid taken from the file itself',
  'a bounding box over the Mission returns real trees, all inside it',
  'is a fused two-city seed, which a published pack is not',
  'refuses every write, on the real file',
];

describe('the pinned seed — the tier that needs a 103 MB file CI does not have', () => {
  // ── Always runs, in every environment ──────────────────────────────────────────────────────
  it('the census: this file holds the seed-dependent tests it says it does', () => {
    assert.equal(
      SEED_DEPENDENT_TESTS.length,
      8,
      'the seed-dependent test list changed size. That is fine if it was deliberate — update this '
        + 'number in the same change — and is a deletion hiding behind a skip otherwise.',
    );
    assert.equal(
      new Set(SEED_DEPENDENT_TESTS).size,
      SEED_DEPENDENT_TESTS.length,
      'two seed-dependent tests share a name',
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

  it('opens the pinned seed exactly as the phone opens a pack', { skip }, () => {
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

  it('is generation 16 by shape, which is a generation behind every published pack', { skip }, () => {
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

  it('states no generation about itself, and its PRAGMA user_version is 0', { skip }, () => {
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

  it('holds the row counts the sqlite3 CLI reported', { skip }, () => {
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

  it('reads a real tree, by a uuid taken from the file itself', { skip }, () => {
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

  it('a bounding box over the Mission returns real trees, all inside it', { skip }, () => {
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
    // The R*Tree is a CONSERVATIVE pre-filter, so the re-test on lat/lon above is load-bearing
    // rather than belt-and-braces. A box just outside the city returns nothing at all, which is
    // the control that says the filter is a filter.
    assert.deepEqual(
      treesInBounds(pack, {
        minLatitude: 37.75, maxLatitude: 37.77, minLongitude: -100.0, maxLongitude: -99.99,
      }, 200),
      [],
    );
  });

  it('is a fused two-city seed, which a published pack is not', { skip }, () => {
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

  it('refuses every write, on the real file', { skip }, () => {
    // The fixture tests prove this on a file the suite wrote. This proves it on the artifact the
    // web will actually be pointed at, and it is the assertion that makes "read-only" a property
    // of the connection rather than a promise in a comment.
    const pack = withSeed();
    for (const write of [
      "UPDATE trees SET status = 'removed' WHERE id = 1",
      'DELETE FROM trees WHERE id = 1',
      'CREATE TABLE scratch (a INTEGER)',
      'PRAGMA user_version = 99',
    ]) {
      assert.throws(() => pack.db.exec(write), `"${write}" was not refused on the pinned seed`);
    }
  });
});
