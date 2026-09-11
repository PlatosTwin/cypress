import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { PackTooNewError, openPack, readOnlyURI } from '../src/lib/pack/pack.ts';
import { PackContractError, columnNames, introspect, tableExists } from '../src/lib/pack/seedSchema.ts';
import { NEWEST_KNOWN_PACK_SCHEMA_VERSION } from '../src/lib/pack/versions.ts';
import { buildNonPack, buildPack, buildShortNameWithoutIdSpacePack, type Fixture }
  from './support/packFixture.ts';

/**
 * Fixtures are built once per generation and torn down at the end.
 *
 * `immutable: false` throughout: these files sit in a temp directory that the suite itself wrote
 * moments earlier, which is precisely the case `immutable=1` is unsound for. A published pack at
 * its versioned path is the case it IS sound for, and `pack-real-seed.test.ts` opens the pinned
 * seed the way the phone opens a pack.
 */
const fixtures: Fixture[] = [];
const pack = (generation: 14 | 15 | 16 | 17, options?: { publishSchemaVersion?: number | null }): Fixture => {
  const fixture = buildPack(generation, options);
  fixtures.push(fixture);
  return fixture;
};
after(() => {
  for (const fixture of fixtures) fixture.cleanup();
});

describe('the read-only URI', () => {
  it('carries mode=ro and immutable=1, and percent-encodes the path', () => {
    // A path with a space truncates the filename if it reaches SQLite unencoded, which is the
    // failure `SeedDatabase.readOnlyURI` names.
    const uri = readOnlyURI('/tmp/a directory/pack.sqlite');
    assert.match(uri, /^file:\/\/\/tmp\/a%20directory\/pack\.sqlite\?mode=ro&immutable=1$/);
  });

  it('drops immutable when told to, and keeps mode=ro either way', () => {
    assert.match(readOnlyURI('/tmp/p.sqlite', { immutable: false }), /\?mode=ro$/);
  });

  it('SQLite really parses those parameters — the calibration, not an assumption', () => {
    // Without this, a URI SQLite silently ignored would be indistinguishable from one it honored,
    // and every claim about read-only-ness below would rest on a query string nobody read. The
    // proof is a value SQLite must reject: `mode=bogus` is refused by name.
    const fixture = pack(17);
    assert.throws(
      () => new DatabaseSync(`${readOnlyURI(fixture.path, { immutable: false })}`.replace('mode=ro', 'mode=bogus')),
      /no such access mode: bogus/,
    );
    // And the other half: the same text on a path with no `file:` scheme is NOT a URI, so SQLite
    // looks for a file whose name ends in `?mode=ro` and does not find one.
    //
    // **`{ readOnly: true }` is load-bearing in this line and its absence is what the first draft
    // got wrong.** Without it `DatabaseSync` opens read-write, which means it CREATES — so the
    // call quietly succeeded by making a new, empty file literally named `s17.sqlite?mode=ro`,
    // and the calibration meant to prove SQLite parses the URI proved only that this test was
    // measuring something else. It is left here as the specimen rather than smoothed away.
    assert.throws(
      () => new DatabaseSync(`${fixture.path}?mode=ro`, { readOnly: true }),
      /unable to open database file/,
    );
    assert.equal(
      existsSync(`${fixture.path}?mode=ro`),
      false,
      'a file named after the query string exists, so this open created one instead of refusing',
    );
  });
});

describe('opening a pack', () => {
  it('opens a generation-17 pack and reports its shape', () => {
    const opened = openPack(pack(17).path, { immutable: false });
    assert.deepEqual(opened.schema, {
      treeIdentityColumn: 'uuid',
      speciesIdentityColumn: 'uuid',
      rtreeJoinColumn: 'id',
      hasCityRaw: true,
      hasInventorySource: true,
      hasIdSpace: true,
      hasSpeciesTrigrams: true,
      // 16 DROPPED `id_spaces.short_name`, so a 17 pack does not have it. This `false` is the
      // reason `hasDimCity` cannot be read as implying `hasCivicShortNames`.
      hasCivicShortNames: false,
      hasDimCity: true,
      hasRegions: true,
      usesIntegerPrimaryKeys: true,
    });
    assert.equal(opened.statedSchemaVersion, 17);
    opened.close();
  });

  it('the generation flags move exactly as the generations did', () => {
    // Read as a table, because the story these four rows tell is the one a reader gets wrong:
    // 15 added two things at once, 16 added one and REMOVED one, 17 added two together. Nothing
    // about this is monotonic, which is why the read layer asks each flag independently.
    const expected = [
      { generation: 17, trigrams: true, shortName: false, dimCity: true, regions: true },
      { generation: 16, trigrams: true, shortName: false, dimCity: true, regions: false },
      { generation: 15, trigrams: true, shortName: true, dimCity: false, regions: false },
      { generation: 14, trigrams: false, shortName: false, dimCity: false, regions: false },
    ] as const;
    for (const row of expected) {
      const opened = openPack(pack(row.generation).path, { immutable: false });
      assert.equal(opened.schema.hasSpeciesTrigrams, row.trigrams, `s${row.generation} trigrams`);
      assert.equal(opened.schema.hasCivicShortNames, row.shortName, `s${row.generation} short name`);
      assert.equal(opened.schema.hasDimCity, row.dimCity, `s${row.generation} dim_city`);
      assert.equal(opened.schema.hasRegions, row.regions, `s${row.generation} regions`);
      // `hasIdSpace` arrived at 14 and never left, so it is the one that must be true throughout.
      assert.equal(opened.schema.hasIdSpace, true, `s${row.generation} id_space`);
      opened.close();
    }
  });

  it('reads seed_meta whole', () => {
    const opened = openPack(pack(17).path, { immutable: false });
    assert.equal(opened.meta.get('publish_schema_version'), '17');
    assert.equal(opened.meta.get('publish_pack_id'), 'sf');
    assert.equal(opened.meta.get('nothing_wrote_this'), undefined);
    opened.close();
  });

  // ── The refusals ──────────────────────────────────────────────────────────────────────────
  it('refuses a pack that states a generation from the future, and names both numbers', () => {
    const future = NEWEST_KNOWN_PACK_SCHEMA_VERSION + 1;
    let thrown: unknown;
    try {
      openPack(pack(17, { publishSchemaVersion: future }).path, { immutable: false });
    } catch (error) {
      thrown = error;
    }
    assert.ok(thrown instanceof PackTooNewError, `threw ${String(thrown)}`);
    assert.equal(thrown.fileVersion, future);
    assert.equal(thrown.buildKnows, NEWEST_KNOWN_PACK_SCHEMA_VERSION);
  });

  it('opens a pack that states no generation at all, reading it as 0', () => {
    // "An ancient file, attachable, just never preferable." Absence is an answer here, not an
    // error — and the pack must still be readable, or a pre-publisher seed becomes unopenable.
    const opened = openPack(pack(17, { publishSchemaVersion: null }).path, { immutable: false });
    assert.equal(opened.statedSchemaVersion, 0);
    assert.equal(opened.schema.hasRegions, true, 'the file is still generation-17 SHAPED');
    opened.close();
  });

  it('a stated generation and an actual shape are different facts, and both are reported', () => {
    // The pair this layer keeps separate on purpose: a file may CLAIM 14 and BE shaped like 17.
    // `statedSchemaVersion` is only ever used to refuse a future generation; every branch in the
    // query layer reads `schema`.
    const opened = openPack(pack(17, { publishSchemaVersion: 14 }).path, { immutable: false });
    assert.equal(opened.statedSchemaVersion, 14);
    assert.equal(opened.schema.hasRegions, true);
    opened.close();
  });

  it('refuses a SQLite database that is not a Cypress pack, naming the missing table', () => {
    const fixture = buildNonPack();
    fixtures.push(fixture);
    let thrown: unknown;
    try {
      openPack(fixture.path, { immutable: false });
    } catch (error) {
      thrown = error;
    }
    assert.ok(thrown instanceof PackContractError, `threw ${String(thrown)}`);
    assert.match(thrown.message, /no table 'trees'/);
  });

  it('refuses a file that is not a database at all', () => {
    const directory = mkdtempSync(join(tmpdir(), 'cypress-notdb-'));
    const path = join(directory, 'garbage.sqlite');
    writeFileSync(path, 'this is not a database');
    try {
      assert.throws(() => openPack(path, { immutable: false }));
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('a refused open leaks no handle, measured by reopening the same file', () => {
    // A connection left open on a refusal is invisible until a server has run for a while. The
    // check is indirect but real: if the first open left the handle alive, this loop would climb
    // the process's file-descriptor ceiling rather than complete.
    const fixture = pack(17, { publishSchemaVersion: NEWEST_KNOWN_PACK_SCHEMA_VERSION + 1 });
    for (let attempt = 0; attempt < 200; attempt += 1) {
      assert.throws(() => openPack(fixture.path, { immutable: false }), PackTooNewError);
    }
    // And the file is still openable afterwards, which it would not be if 200 handles were held.
    const opened = openPack(pack(17).path, { immutable: false });
    opened.close();
  });
});

describe('a pack is opened read-only, and SQLite is what enforces it', () => {
  it('refuses a write, and the refusal comes from the engine', () => {
    const fixture = pack(17);
    const opened = openPack(fixture.path, { immutable: false });
    for (const write of [
      "INSERT INTO trees (id, uuid, lat, lon, status) VALUES (999, 'x', 0, 0, 'alive')",
      "UPDATE trees SET status = 'removed'",
      'DELETE FROM trees',
      'DROP TABLE trees',
      'CREATE TABLE scratch (a INTEGER)',
      'CREATE INDEX idx_scratch ON trees(status)',
    ]) {
      assert.throws(
        () => opened.db.exec(write),
        /readonly database/,
        `"${write}" was not refused — the pack is writable through this handle`,
      );
    }
    opened.close();
  });

  it('and the file on disk is byte-for-byte unchanged after a session of reads', () => {
    // The assertion that would catch a write SQLite allowed: a journal, a `-wal` sidecar, an
    // analysis pragma, a VACUUM. Size and mtime, because the read layer is supposed to leave no
    // trace at all.
    const fixture = pack(17);
    const before = statSync(fixture.path);
    const opened = openPack(fixture.path, { immutable: false });
    opened.db.prepare('SELECT COUNT(*) AS n FROM trees').get();
    opened.db.prepare('SELECT * FROM species').all();
    opened.close();
    const after = statSync(fixture.path);
    assert.equal(after.size, before.size, 'the pack file changed size');
    assert.equal(after.mtimeMs, before.mtimeMs, 'the pack file was written to');
  });
});

describe('introspection, at the level below openPack', () => {
  it('columnNames answers empty for a table that is not there, rather than throwing', () => {
    // Load-bearing: it is what keeps `hasCivicShortNames` correct on a pack with no `id_spaces`
    // table at all, without a separate `hasIdSpace` check.
    const opened = openPack(pack(17).path, { immutable: false });
    assert.deepEqual(columnNames(opened.db, 'a_table_that_does_not_exist'), []);
    assert.ok(columnNames(opened.db, 'trees').includes('lat'));
    opened.close();
  });

  it('tableExists sees tables and views, and does not see what is absent', () => {
    const opened = openPack(pack(17).path, { immutable: false });
    assert.equal(tableExists(opened.db, 'trees'), true);
    assert.equal(tableExists(opened.db, 'dim_region'), true);
    assert.equal(tableExists(opened.db, 'dim_region_that_is_not_there'), false);
    opened.close();
  });

  it('refuses a trees table missing lat, lon or status, naming what is missing', () => {
    const directory = mkdtempSync(join(tmpdir(), 'cypress-nolatlon-'));
    const path = join(directory, 'shapeless.sqlite');
    const db = new DatabaseSync(path);
    db.exec(`
      CREATE TABLE trees (id INTEGER PRIMARY KEY, uuid TEXT);
      CREATE TABLE species (id INTEGER PRIMARY KEY);
      CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY);
      CREATE VIRTUAL TABLE trees_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
    `);
    try {
      assert.throws(() => introspect(db), (error: unknown) => {
        assert.ok(error instanceof PackContractError);
        assert.match(error.message, /lat, lon, status/);
        return true;
      });
    } finally {
      db.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('the degenerate pack — short_name with no trees.id_space — still prepares', () => {
    // The shape that turns a wrongly-gated projection into `no such column: isp.short_name` at
    // PREPARE time rather than into a null result. `hasCivicShortNames` is true and `hasIdSpace`
    // is false, which is the combination the gating exists for.
    const fixture = buildShortNameWithoutIdSpacePack();
    fixtures.push(fixture);
    const opened = openPack(fixture.path, { immutable: false });
    assert.equal(opened.schema.hasCivicShortNames, true);
    assert.equal(opened.schema.hasIdSpace, false);
    opened.close();
  });
});
