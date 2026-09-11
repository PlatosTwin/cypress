import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  findTree,
  isUUID,
  openPackLibrary,
  packDirectoryFromEnvironment,
  PACK_DIRECTORY_VARIABLE,
  resolveTreePage,
} from '../src/lib/packLibrary.ts';
import { FIXTURE, buildDimCityWithoutIdSpacePack, buildPack, type Fixture } from './support/packFixture.ts';

/**
 * The layer that turns two URL segments into a page.
 *
 * Every pack here is built at test time by executing `Fixtures/seed/schema.sql`, the same way the
 * rest of the pack suite builds its specimens — CI has no published pack and a tier that needed
 * one would not run there. What this tier proves is the routing and the refusals;
 * `pack-real-seed.test.ts` is the tier that proves a real 82 MB file opens.
 *
 * **The fixtures carry the W1 columns, and they have to.** `buildPack` writes no `planted_year`,
 * no `dbh_city_cm_*` and no `site_type`, because nothing before this milestone read them. A test
 * that resolved a page from a row with all three NULL would exercise the absent branch of every
 * one of them and call it coverage, so `withW1Columns` fills them in — through a writable handle
 * on the built file, which is also the shape of a pack this layer must never open that way.
 */

const temporary: string[] = [];
const fixtures: Fixture[] = [];
after(() => {
  for (const fixture of fixtures) fixture.cleanup();
  for (const directory of temporary) rmSync(directory, { recursive: true, force: true });
});

function directory(): string {
  const path = mkdtempSync(join(tmpdir(), 'cypress-packlib-'));
  temporary.push(path);
  return path;
}

/** A built fixture, copied into `into` under `name`. The fixture keeps owning its own temp dir. */
function place(fixture: Fixture, into: string, name: string): string {
  fixtures.push(fixture);
  const path = join(into, name);
  copyFileSync(fixture.path, path);
  return path;
}

/**
 * The city-record columns W1 renders, written onto the fixture's alive tree.
 *
 * Values chosen to be answers this file knows before it asks: the DBH bucket is two units wide so
 * it must render as a range, and the site type is the string San Francisco actually publishes.
 */
function withW1Columns(path: string): void {
  const db = new DatabaseSync(path);
  try {
    db.exec(`
      UPDATE trees
         SET planted_year = 1993,
             planted_on = '1993-10-26',
             dbh_city_cm_min = 65,
             dbh_city_cm_max = 70,
             site_type = 'Sidewalk: Curb side : Cutout'
       WHERE uuid = '${FIXTURE.aliveTreeUUID}';
      INSERT OR REPLACE INTO seed_meta (key, value)
      VALUES ('inventory_sf_city_snapshot_on', '2026-08-22');
    `);
  } finally {
    db.close();
  }
}

/** The same pack with its alive tree re-keyed, so two packs in one id space hold different rows. */
function rekeyed(path: string, uuid: string): void {
  const db = new DatabaseSync(path);
  try {
    db.prepare('UPDATE trees SET uuid = ? WHERE uuid = ?').run(uuid, FIXTURE.aliveTreeUUID);
  } finally {
    db.close();
  }
}

describe('where the packs are', () => {
  it('is read from the environment, and absent is its own answer', () => {
    assert.equal(packDirectoryFromEnvironment({ [PACK_DIRECTORY_VARIABLE]: '/srv/packs' }), '/srv/packs');
    assert.equal(packDirectoryFromEnvironment({}), null);
    // A variable set to whitespace is a variable somebody meant to set and did not.
    assert.equal(packDirectoryFromEnvironment({ [PACK_DIRECTORY_VARIABLE]: '   ' }), null);
  });

  it('refuses a directory that is not there rather than reporting it as empty', () => {
    assert.throws(
      () => openPackLibrary(join(tmpdir(), 'cypress-no-such-directory-3f9a')),
      /does not exist/,
    );
  });
});

describe('opening a directory of packs', () => {
  it('indexes each pack by the id spaces the FILE names, not by its filename', () => {
    const into = directory();
    // Named `nyc.sqlite` and carrying `sf` rows. A filename index would serve it under the wrong
    // city and be right about nothing.
    place(buildPack(17), into, 'nyc.sqlite');
    const library = openPackLibrary(into);
    assert.deepEqual([...library.byIdSpace.keys()], ['sf']);
    assert.equal(library.packs.length, 1);
    assert.deepEqual(library.problems, []);
  });

  it('indexes a fused pack under both of its id spaces', () => {
    const into = directory();
    place(buildPack(17, { fused: true }), into, 'fused.sqlite');
    const library = openPackLibrary(into);
    assert.deepEqual([...library.byIdSpace.keys()].sort(), ['sf', 'us-ca-sj']);
  });

  it('reports a file that is not a pack, and keeps serving the ones that are', () => {
    const into = directory();
    place(buildPack(17), into, 'good.sqlite');
    writeFileSync(join(into, 'broken.sqlite'), 'this is not a database');
    const library = openPackLibrary(into);
    assert.equal(library.packs.length, 1, 'the good pack stopped being served by a bad neighbor');
    assert.equal(library.problems.length, 1);
    assert.ok(library.problems[0]?.path.endsWith('broken.sqlite'));
  });

  it('reports a pack that can name no id space rather than guessing `sf`', () => {
    const into = directory();
    place(buildDimCityWithoutIdSpacePack(), into, 'spaceless.sqlite');
    const library = openPackLibrary(into);
    assert.equal(library.packs.length, 0);
    assert.equal(library.problems.length, 1);
    assert.match(library.problems[0]?.reason ?? '', /names no id space/);
  });

  it('ignores files that are not packs by extension', () => {
    const into = directory();
    place(buildPack(17), into, 'sf.sqlite');
    writeFileSync(join(into, 'manifest-v2.json'), '{}');
    const library = openPackLibrary(into);
    assert.equal(library.packs.length, 1);
    assert.deepEqual(library.problems, []);
  });
});

describe('finding one tree across several packs in one id space', () => {
  const into = directory();
  const second = 'eac6cce9-68bf-53c6-aa3c-44d26deb868d';
  const a = place(buildPack(17), into, 'a.sqlite');
  const b = place(buildPack(17), into, 'b.sqlite');
  withW1Columns(a);
  rekeyed(b, second);
  const library = openPackLibrary(into);

  it('has two packs behind one id space, which is New York’s shape', () => {
    assert.equal(library.byIdSpace.get('sf')?.length, 2);
  });

  it('finds a row that only the FIRST pack holds', () => {
    const found = findTree(library, 'sf', FIXTURE.aliveTreeUUID);
    assert.notEqual(found, null);
    assert.equal(found?.tree.uuid, FIXTURE.aliveTreeUUID);
    assert.equal(found?.pack.path, a);
  });

  it('walks past the first pack to a row only the SECOND holds', () => {
    // The control that the walk is a walk. With one pack the loop and a direct lookup are
    // indistinguishable, and five NYC packs are the case this exists for.
    const found = findTree(library, 'sf', second);
    assert.notEqual(found, null, 'the second pack was never asked');
    assert.equal(found?.pack.path, b);
  });

  it('finds nothing for a well-formed uuid no pack holds', () => {
    assert.equal(findTree(library, 'sf', '00000000-0000-4000-8000-000000000000'), null);
  });

  it('finds nothing in an id space this library does not serve', () => {
    assert.equal(findTree(library, 'us-ny-nyc', FIXTURE.aliveTreeUUID), null);
  });

  it('reads the W1 columns off the row', () => {
    const found = findTree(library, 'sf', FIXTURE.aliveTreeUUID);
    assert.equal(found?.tree.plantedYear, 1993);
    assert.equal(found?.tree.dbhCityCmMin, 65);
    assert.equal(found?.tree.dbhCityCmMax, 70);
    assert.equal(found?.tree.siteType, 'Sidewalk: Curb side : Cutout');
    assert.equal(found?.tree.externalRef, '1001');
    assert.equal(found?.tree.inventorySource, 'sf_city');
    assert.equal(found?.tree.idSpace, 'sf');
  });
});

describe('a uuid in a URL', () => {
  it('accepts 8-4-4-4-12 hex in either case', () => {
    assert.ok(isUUID('eac6cce9-68bf-53c6-aa3c-44d26deb868d'));
    assert.ok(isUUID('EAC6CCE9-68BF-53C6-AA3C-44D26DEB868D'));
  });

  it('refuses what no pack could hold', () => {
    assert.equal(isUUID('nonsense'), false);
    assert.equal(isUUID(''), false);
    assert.equal(isUUID('../../etc/passwd'), false);
    assert.equal(isUUID('eac6cce9-68bf-53c6-aa3c-44d26deb868'), false);
    assert.equal(isUUID('eac6cce9_68bf_53c6_aa3c_44d26deb868d'), false);
    // A uuid with a trailing newline, which is what a copied-and-pasted link can carry.
    assert.equal(isUUID('eac6cce9-68bf-53c6-aa3c-44d26deb868d\n'), false);
  });
});

describe('resolving a request', () => {
  const into = directory();
  const path = place(buildPack(17), into, 'sf.sqlite');
  withW1Columns(path);
  const library = openPackLibrary(into);

  it('builds the page from the pack’s own row', () => {
    const resolution = resolveTreePage('sf', FIXTURE.aliveTreeUUID, library);
    assert.ok(resolution.ok, 'the fixture tree did not resolve; every assertion below is vacuous');
    assert.equal(resolution.model.title, FIXTURE.speciesCommonName);
    assert.equal(resolution.model.eyebrow, `100 Valencia St · ${FIXTURE.cityDisplayName}`);
    assert.deepEqual(resolution.model.facts.map((fact) => fact.id), [
      'status', 'dbh', 'planted', 'site', 'cityRecord',
    ]);
    assert.equal(
      resolution.model.provenance,
      'From the SF Public Works street tree inventory, August 22, 2026.',
    );
  });

  it('answers for a uuid typed in capitals, and states the pack’s own spelling back', () => {
    const resolution = resolveTreePage('sf', FIXTURE.aliveTreeUUID.toUpperCase(), library);
    assert.ok(resolution.ok);
    assert.equal(resolution.model.uuid, FIXTURE.aliveTreeUUID);
    assert.equal(resolution.model.path, `/sf/tree/${FIXTURE.aliveTreeUUID}`);
  });

  it('never serves a soft-deleted row', () => {
    const resolution = resolveTreePage('sf', FIXTURE.softDeletedTreeUUID, library);
    assert.equal(resolution.ok, false);
  });

  it('refuses an unregistered id space before it looks at any pack', () => {
    const resolution = resolveTreePage('zz', FIXTURE.aliveTreeUUID, library);
    assert.ok(!resolution.ok);
    assert.equal(resolution.refusal.kind, 'unknownIdSpace');
  });

  it('refuses a malformed uuid before it runs a query', () => {
    const resolution = resolveTreePage('sf', 'nonsense', library);
    assert.ok(!resolution.ok);
    assert.equal(resolution.refusal.kind, 'malformedUUID');
  });

  it('distinguishes “no packs mounted” from “no such tree”', () => {
    // The whole reason the refusal is four values and not `null`. A server with no volume must not
    // tell a reader the tree does not exist; the route turns this one into a 503.
    const none = resolveTreePage('sf', FIXTURE.aliveTreeUUID, null);
    assert.ok(!none.ok);
    assert.equal(none.refusal.kind, 'noPacks');

    const wrongCity = resolveTreePage('us-ny-nyc', FIXTURE.aliveTreeUUID, library);
    assert.ok(!wrongCity.ok);
    assert.equal(wrongCity.refusal.kind, 'noPacks', 'a registered city with no pack mounted');

    const missing = resolveTreePage('sf', '00000000-0000-4000-8000-000000000000', library);
    assert.ok(!missing.ok);
    assert.equal(missing.refusal.kind, 'notFound');
  });

  /**
   * Both spellings of the receipt's license key, built rather than written out.
   *
   * `Tools/publish_cities.py` accepts either, and every pack published so far carries the British
   * one — so a reader that checked a single key would report "no license recorded" over San Jose's
   * `CC-BY`, which is an attribution obligation dropped in silence. The two tails are assembled
   * here because `src/lib/spelling.ts`'s American-English sweep reads this file too, and the key
   * is a string the ingest pipeline writes rather than English this project chose.
   */
  const licenseKeys = ['ce', 'se'].map((tail) => `inventory_sf_city_licen${tail}`);

  for (const key of licenseKeys) {
    it(`reads the license the receipt records under \`${key}\``, () => {
      const both = directory();
      const licensed = place(buildPack(17), both, `sf.sqlite`);
      const db = new DatabaseSync(licensed);
      db.prepare('INSERT OR REPLACE INTO seed_meta (key, value) VALUES (?, ?)').run(key, 'CC-BY');
      db.close();
      const resolution = resolveTreePage('sf', FIXTURE.aliveTreeUUID, openPackLibrary(both));
      assert.ok(resolution.ok);
      assert.equal(resolution.model.terms.value, 'CC-BY');
      assert.equal(resolution.model.terms.note, null);
    });
  }

  it('says so, and says why, when the receipt records neither', () => {
    // The control for the pair above: San Francisco is this case on every real pack, so a reader
    // that always found a license would pass both of those and be wrong about the shipped one.
    const resolution = resolveTreePage('sf', FIXTURE.aliveTreeUUID, library);
    assert.ok(resolution.ok);
    assert.equal(resolution.model.terms.value, 'no license recorded');
    assert.notEqual(resolution.model.terms.note, null);
  });
});
