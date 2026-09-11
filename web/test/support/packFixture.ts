/**
 * Packs built at test time from the repository's own schema contract.
 *
 * **The point of this file is that the web suite is not vacuous in CI.** The ~103 MB seed is
 * git-ignored, so a suite whose only real data is that file tests nothing on a CI runner and says
 * so in a green summary — the exact shape `Tools/verify_web_test_log.sh` exists to refuse. Two
 * files beside the seed *are* tracked, and they are enough to do better:
 * `Fixtures/seed/schema.sql`, the generation-17 contract, and `Fixtures/seed/pinned-seed.json`.
 *
 * So every shape assertion runs against a pack built here from `schema.sql` — **the real contract,
 * executed, not a paraphrase of it** — with a handful of rows whose values the test knew before it
 * asked. That runs identically on a laptop and on a runner with no seed. The real seed is then an
 * *additional* tier (`test/pack-real-seed.test.ts`), not the only one.
 *
 * ## The degradations, and why they are subtractive
 *
 * A generation-16 fixture is built by taking the 17 contract and removing what 17 added; 15 by
 * removing what 16 added and restoring what 16 dropped; 14 by removing 15's table. Subtracting
 * from the real contract rather than writing four hand-rolled schemas keeps the older shapes
 * honest about the columns they share with the newest one — a hand-written "s15" would agree with
 * whatever its author believed s15 looked like, which is how a fixture ends up testing the
 * author's memory.
 *
 * **What it cannot be: evidence about a real s15 or s14 pack.** No such file was consulted; these
 * reproduce the *flags* those generations set, which is what the read layer branches on. The claim
 * is about `introspect` and the fallback chain, not about the bytes any historical publish
 * produced.
 */
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { seedSchemaContractPath } from '../../src/lib/pack/localSeed.ts';

/** The generation a fixture is built at. `17` is the contract as checked in. */
export type Generation = 14 | 15 | 16 | 17;

export interface Fixture {
  readonly path: string;
  readonly generation: Generation;
  /** Removes the whole temporary directory. Call it in an `after` hook. */
  cleanup(): void;
}

/**
 * Known values, written here so a test can assert them rather than assert whatever came back.
 *
 * These are the answers the tests know before they ask — the discipline `toolchain.test.ts` names:
 * "a parser asserted only against the real files is a parser that agrees with whatever the files
 * happen to say."
 */
export const FIXTURE = {
  /** Lowercase, as every pack stores its uuids — see `treeByUUID`'s note on the BINARY index. */
  aliveTreeUUID: '11111111-1111-4111-8111-111111111111',
  vacantTreeUUID: '22222222-2222-4222-8222-222222222222',
  farAwayTreeUUID: '33333333-3333-4333-8333-333333333333',
  softDeletedTreeUUID: '44444444-4444-4444-8444-444444444444',
  aliveTreeLatitude: 37.7749,
  aliveTreeLongitude: -122.4194,
  vacantTreeLatitude: 37.775,
  vacantTreeLongitude: -122.4195,
  /** Deliberately outside the box the bounds tests ask for. */
  farAwayLatitude: 40.7128,
  farAwayLongitude: -74.006,
  speciesScientificName: 'Platanus x hispanica',
  speciesCommonName: 'London plane',
  neighborhoodName: 'Mission Dolores',
  idSpace: 'sf',
  /** `dim_city.display_name` — what a generation-16-or-newer pack resolves a tree's city to. */
  cityDisplayName: 'San Francisco',
  /** `id_spaces.short_name` — what a generation-15 pack falls back to. Deliberately DIFFERENT text. */
  shortName: 'SF (short name)',
  packId: 'sf',
  regionDisplayName: 'San Francisco',
  regionLevel: 'city',
  /** Trees that are not soft-deleted. The soft-deleted one is excluded from every read. */
  liveTreeCount: 3,
} as const;

/** The rows every generation gets, in dependency order. Generation-specific rows are added after. */
function insertCommonRows(db: DatabaseSync): void {
  const now = '2026-01-01T00:00:00Z';
  db.exec(`
    INSERT INTO species (id, uuid, scientific_name, common_name, family, leaf_retention,
                         created_at, updated_at)
    VALUES (1, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '${FIXTURE.speciesScientificName}',
            '${FIXTURE.speciesCommonName}', 'Platanaceae', 'deciduous', '${now}', '${now}');

    INSERT INTO neighborhoods (id, name, geom_geojson, min_lat, max_lat, min_lon, max_lon,
                               created_at, updated_at)
    VALUES (1, '${FIXTURE.neighborhoodName}', '{"type":"Polygon","coordinates":[]}',
            37.76, 37.78, -122.43, -122.41, '${now}', '${now}');

    INSERT INTO inventories (id, id_space, name, url)
    VALUES ('sf_city', '${FIXTURE.idSpace}', 'SF Public Works street tree inventory',
            'https://example.invalid/sf');
  `);
}

/**
 * The rows, always written at the generation-17 shape.
 *
 * **`region_id` is supplied for every generation, including the ones that will not have the
 * column.** `degrade` runs after this, so at insert time the table is still the 17 contract and
 * `region_id` is `NOT NULL`. Writing the rows first and subtracting afterwards is deliberate: it
 * is the only order in which the older fixtures are a strict subtraction from the real contract
 * rather than a hand-built approximation of it, which is the whole argument in this file's header.
 */
function insertTrees(db: DatabaseSync): void {
  const now = '2026-01-01T00:00:00Z';
  const tree = (
    id: number,
    uuid: string,
    ref: string,
    lat: number,
    lon: number,
    status: string,
    species: string,
    address: string,
    deletedAt: string,
  ): string => `
    INSERT INTO trees (id, uuid, id_space, external_ref, source, inventory_source, region_id,
                       lat, lon, address, neighborhood_id, status, species_current,
                       verification_state, created_at, updated_at, deleted_at)
    VALUES (${id}, '${uuid}', '${FIXTURE.idSpace}', '${ref}', 'city_import', 'sf_city', 1,
            ${lat}, ${lon}, '${address}', 1, '${status}', ${species},
            'city_record', '${now}', '${now}', ${deletedAt});
  `;

  db.exec(
    tree(1, FIXTURE.aliveTreeUUID, '1001', FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude,
         'alive', '1', '100 Valencia St', 'NULL')
    // A vacant planting site: no species, which is what makes the LEFT JOIN worth asserting.
    + tree(2, FIXTURE.vacantTreeUUID, '1002', FIXTURE.vacantTreeLatitude, FIXTURE.vacantTreeLongitude,
           'vacant_site', 'NULL', '102 Valencia St', 'NULL')
    + tree(3, FIXTURE.farAwayTreeUUID, '1003', FIXTURE.farAwayLatitude, FIXTURE.farAwayLongitude,
           'alive', '1', '1 Nowhere Ave', 'NULL')
    + tree(4, FIXTURE.softDeletedTreeUUID, '1004', FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude,
           'alive', '1', '104 Valencia St', "'2026-02-01T00:00:00Z'"),
  );

  // The R*Tree is populated by hand rather than by a trigger, because the contract has no trigger:
  // `Tools/build_seed.py` fills it, and a fixture that filled it some other way would be testing a
  // mechanism the real packs do not have. Degenerate boxes (min == max) are what a point gets.
  for (const [id, lat, lon] of [
    [1, FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude],
    [2, FIXTURE.vacantTreeLatitude, FIXTURE.vacantTreeLongitude],
    [3, FIXTURE.farAwayLatitude, FIXTURE.farAwayLongitude],
    [4, FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude],
  ] as const) {
    db.prepare(
      'INSERT INTO trees_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?, ?, ?, ?, ?)',
    ).run(id, lat, lat, lon, lon);
  }
}

/**
 * Takes the generation-17 contract down to `generation`.
 *
 * Two ordering constraints, both discovered by hitting them rather than assumed:
 *
 * * **`DROP COLUMN` needs the index over that column gone first**, so `idx_trees_region` goes
 *   before `trees.region_id`.
 * * **`node:sqlite` turns foreign keys ON by default** (`enableForeignKeyConstraints`, unlike
 *   SQLite's own default of off), so a referenced table cannot be dropped while a referencing
 *   column still exists: `id_spaces.city_id` goes before `dim_city`, and `dim_region` — which also
 *   references `dim_city` — is already gone by then because 16's step ran first.
 */
function degrade(db: DatabaseSync, generation: Generation): void {
  if (generation <= 16) {
    // 17 added `dim_region` and `trees.region_id` together, so 16 removes them together.
    db.exec('DROP INDEX IF EXISTS idx_trees_region');
    db.exec('ALTER TABLE trees DROP COLUMN region_id');
    db.exec('DROP TABLE dim_region');
  }
  if (generation <= 15) {
    // 16 added `dim_city` and `id_spaces.city_id`, and DROPPED `id_spaces.short_name`. Going back
    // to 15 therefore restores a column as well as removing two — which is the whole reason
    // `hasDimCity` and `hasCivicShortNames` are introspected independently instead of one being
    // taken to imply the other.
    db.exec('ALTER TABLE id_spaces DROP COLUMN city_id');
    db.exec('DROP TABLE dim_city');
    db.exec('ALTER TABLE id_spaces ADD COLUMN short_name TEXT');
    db.exec(`UPDATE id_spaces SET short_name = '${FIXTURE.shortName}'`);
  }
  if (generation <= 14) {
    // 15 added `species_trigrams` AND `id_spaces.short_name` in one generation — "two additions
    // folded into one generation rather than two", in `SeedDatabase`'s words — so 14 removes both.
    db.exec('DROP TABLE species_trigrams');
    db.exec('ALTER TABLE id_spaces DROP COLUMN short_name');
  }
}

/**
 * Builds a pack at `generation` in a fresh temporary directory.
 *
 * `publishSchemaVersion` defaults to the generation, which is what a real publish writes. Pass
 * something else to exercise a file whose claim about itself disagrees with its shape — the case
 * `CityLibrary.validateCityFile` refuses on, and a `null` to build a file that makes no claim at
 * all.
 */
export function buildPack(
  generation: Generation,
  options: { publishSchemaVersion?: number | null } = {},
): Fixture {
  const directory = mkdtempSync(join(tmpdir(), `cypress-pack-s${generation}-`));
  const path = join(directory, `s${generation}.sqlite`);
  const db = new DatabaseSync(path);
  try {
    db.exec(readFileSync(seedSchemaContractPath, 'utf8'));

    db.exec(`
      INSERT INTO dim_city (id, slug, display_name, state, county, urban_forestry_url)
      VALUES (1, 'us-ca-sf', '${FIXTURE.cityDisplayName}', 'CA', 'San Francisco',
              'https://example.invalid/urban-forestry');

      INSERT INTO dim_region (id, pack_id, display_name, level, city_id)
      VALUES (1, '${FIXTURE.packId}', '${FIXTURE.regionDisplayName}', '${FIXTURE.regionLevel}', 1);

      INSERT INTO id_spaces (id, identity_prefix, note, city_id)
      VALUES ('${FIXTURE.idSpace}', '', 'fixture', 1);
    `);
    insertCommonRows(db);
    insertTrees(db);
    db.exec(
      "INSERT INTO species_trigrams (species_id, trigram) VALUES (1, 'pla'), (1, 'lat')",
    );

    const stated = options.publishSchemaVersion === undefined
      ? generation
      : options.publishSchemaVersion;
    if (stated !== null) {
      db.prepare("INSERT INTO seed_meta (key, value) VALUES ('publish_schema_version', ?)")
        .run(String(stated));
      db.prepare("INSERT INTO seed_meta (key, value) VALUES ('publish_pack_id', ?)")
        .run(FIXTURE.packId);
    }

    degrade(db, generation);
  } finally {
    db.close();
  }
  return {
    path,
    generation,
    cleanup: () => rmSync(directory, { recursive: true, force: true }),
  };
}

/** A file that is a valid SQLite database and is not a Cypress pack. */
export function buildNonPack(): Fixture {
  const directory = mkdtempSync(join(tmpdir(), 'cypress-nonpack-'));
  const path = join(directory, 'not-a-pack.sqlite');
  const db = new DatabaseSync(path);
  db.exec('CREATE TABLE something_else (a INTEGER); INSERT INTO something_else VALUES (1)');
  db.close();
  return { path, generation: 17, cleanup: () => rmSync(directory, { recursive: true, force: true }) };
}

/**
 * A pack with `id_spaces.short_name` and **no `trees.id_space`** — the one shape that turns a
 * wrongly-gated city-name projection into a *prepare-time* error rather than a null.
 *
 * Hand-built rather than degraded from `Fixtures/seed/schema.sql`, and the reason is the finding:
 * `trees.id_space` cannot be dropped from the real contract, because it is part of
 * `UNIQUE (id_space, external_ref)` and SQLite refuses `DROP COLUMN` on an indexed column. So this
 * specimen carries only the tables `introspect` requires, at the identity model the projection
 * branches on. It exists to reproduce exactly one thing — `no such column: isp.short_name`, thrown
 * when a projection reads an alias its own join never introduced — and it is evidence about
 * nothing else.
 *
 * The phone has the same fixture for the same reason
 * (`CivicShortNameTests.aFixtureWithShortNameButNoTreeIDSpaceStillPrepares`).
 */
export function buildShortNameWithoutIdSpacePack(): Fixture {
  const directory = mkdtempSync(join(tmpdir(), 'cypress-pack-noidspace-'));
  const path = join(directory, 'degenerate.sqlite');
  const db = new DatabaseSync(path);
  const now = '2026-01-01T00:00:00Z';
  db.exec(`
    CREATE TABLE species (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                          scientific_name TEXT NOT NULL, common_name TEXT);
    CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE id_spaces (id TEXT PRIMARY KEY, short_name TEXT);
    CREATE TABLE trees (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                        lat REAL NOT NULL, lon REAL NOT NULL, status TEXT NOT NULL,
                        address TEXT, neighborhood_id INTEGER, species_current INTEGER,
                        created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
    CREATE VIRTUAL TABLE trees_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
    INSERT INTO id_spaces (id, short_name) VALUES ('${FIXTURE.idSpace}', '${FIXTURE.shortName}');
    INSERT INTO trees (id, uuid, lat, lon, status, created_at, updated_at)
    VALUES (1, '${FIXTURE.aliveTreeUUID}', ${FIXTURE.aliveTreeLatitude},
            ${FIXTURE.aliveTreeLongitude}, 'alive', '${now}', '${now}');
    INSERT INTO trees_rtree (id, min_lat, max_lat, min_lon, max_lon)
    VALUES (1, ${FIXTURE.aliveTreeLatitude}, ${FIXTURE.aliveTreeLatitude},
            ${FIXTURE.aliveTreeLongitude}, ${FIXTURE.aliveTreeLongitude});
  `);
  db.close();
  return { path, generation: 15, cleanup: () => rmSync(directory, { recursive: true, force: true }) };
}
