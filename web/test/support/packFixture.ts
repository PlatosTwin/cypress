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
 * **Why the seed's schema is also a PACK's schema**, which this file rests on and did not used to
 * say: `Tools/publish_cities.py` narrows a fused seed into a pack with `DELETE` and `VACUUM` and
 * nothing else — it issues no DDL at all (`grep -cE 'CREATE TABLE|ALTER TABLE|DROP TABLE|CREATE
 * INDEX|DROP INDEX' Tools/publish_cities.py` → 0, against 21 in `schema.sql`). A pack therefore
 * carries the schema of the seed it was cut from, row ids included: `neighborhoods` is narrowed by
 * `DELETE`, never renumbered, so a real pack's neighborhood ids are as unrelated to its tree ids as
 * they are below.
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
  /**
   * Lowercase, as every pack stores its uuids — see `treeByUUID`'s note on the BINARY index.
   *
   * **It carries hex LETTERS on purpose.** An all-digit uuid is unchanged by `toUpperCase()`, so
   * the test that proves an uppercase uuid still matches would compare a string with itself and
   * pass against a query that did no normalization at all. It sorts before the vacant site and the
   * far-away tree, and AFTER the four R*Tree false positives, whose uuids sort first while their
   * rowids sort last — see `rtreeFalsePositives` for why that crossing matters.
   */
  aliveTreeUUID: '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  vacantTreeUUID: '22222222-2222-4222-8222-222222222222',
  farAwayTreeUUID: '33333333-3333-4333-8333-333333333333',
  softDeletedTreeUUID: '44444444-4444-4444-8444-444444444444',
  /** In the Mission box, alive, and **deliberately absent from the R*Tree**. See `insertTrees`. */
  unindexedTreeUUID: '55555555-5555-4555-8555-555555555555',
  /**
   * Trees the R*Tree hands back for the Mission box whose real `lat`/`lon` are outside it —
   * **the false positives the `lat`/`lon` re-test in `treesInBounds` exists to remove.**
   *
   * Every other fixture tree sits at a coordinate its R*Tree box and the table agree about, so
   * pre-filter and re-test returned the same set by construction and the re-test was unfalsifiable
   * here: replacing all four `t.lat`/`t.lon` bounds with `? IS NOT NULL` was green in this tier AND
   * against the 103 MB seed, whose own per-row loop is clipped by the `LIMIT 200` the same test
   * asserts on the line above (8,990 R*Tree candidates for that box, 7 genuinely outside it, and 0
   * of those 7 in the first 200 by uuid — measured with the `sqlite3` CLI).
   *
   * **Built on the real mechanism rather than on a hand-widened box.** SQLite's R*Tree stores
   * 32-bit floats and rounds each `min` down and each `max` up, so even a point entry occupies a
   * box slightly larger than the point: a tree inserted at `37.780001` is stored as
   * `min_lat 37.77999496…, max_lat 37.78000259…`, which overlaps a box ending at `37.78`. That
   * outward rounding is where a real pack's false positives come from, and these four reproduce it.
   * The offsets fall inside one float32 step and were measured rather than guessed —
   * `-122.4300001` and not `-122.430001`, because the latter rounds to a box that does NOT reach
   * `-122.43` and would have been a specimen that proves nothing.
   *
   * **One per bound**, so each of the four re-tested bounds has a row only it excludes: drop any
   * single `BETWEEN` end and exactly one of these comes back.
   *
   * Their uuids sort BEFORE every other tree's while their `trees.id`s come after, which is a
   * second job: it is what makes `treesInBounds`'s `ORDER BY t.<identity column>` falsifiable.
   * With uuid order and rowid order agreeing — which they did while these were `6666…` — ordering
   * by `t.id` instead, or dropping the `ORDER BY` altogether, changed nothing any test could see,
   * and the order is what makes a `LIMIT`ed read deterministic rather than "whatever the join
   * produced first".
   */
  rtreeFalsePositives: [
    {
      uuid: '06666666-6666-4666-8666-000000000001',
      lat: 37.780001,
      lon: -122.42,
      escapes: 'its latitude is above the box',
    },
    {
      uuid: '06666666-6666-4666-8666-000000000002',
      lat: 37.769999,
      lon: -122.42,
      escapes: 'its latitude is below the box',
    },
    {
      uuid: '06666666-6666-4666-8666-000000000003',
      lat: 37.775,
      lon: -122.409999,
      escapes: 'its longitude is above the box',
    },
    {
      uuid: '06666666-6666-4666-8666-000000000004',
      lat: 37.775,
      lon: -122.4300001,
      escapes: 'its longitude is below the box',
    },
  ],
  aliveTreeLatitude: 37.7749,
  aliveTreeLongitude: -122.4194,
  vacantTreeLatitude: 37.775,
  vacantTreeLongitude: -122.4195,
  unindexedTreeLatitude: 37.7751,
  unindexedTreeLongitude: -122.4193,
  /** Deliberately outside the box the bounds tests ask for. */
  farAwayLatitude: 40.7128,
  farAwayLongitude: -74.006,
  speciesScientificName: 'Platanus x hispanica',
  speciesCommonName: 'London plane',
  /**
   * Two neighborhoods, and **no tree's `neighborhood_id` equals its own `id`**.
   *
   * Both facts are load-bearing rather than decorative, and the reason is a defect this fixture
   * used to hide. Every tree here carried `neighborhood_id` 1, so `JOIN trees t ON
   * t.neighborhood_id = r.id` — the R*Tree join wired to the wrong column — returned the same set
   * as the correct `t.id = r.id`, and `treesInBounds`'s `lat`/`lon` re-test on `trees` re-derived
   * the right answer from the cross product either way. Every bounding-box test passed with the
   * join wrong; only the seed-gated Mission test went red, on a runner that has the seed. See
   * `insertTrees` for the full arrangement.
   *
   * The ids are therefore assigned across the trees rather than alongside them, which is also
   * what the real seed looks like: 41 neighborhoods over 198,625 trees.
   */
  missionNeighborhoodId: 2,
  otherNeighborhoodId: 1,
  /** Neighborhood id 2 — the alive tree's and the unindexed tree's. */
  neighborhoodName: 'Mission Dolores',
  /** Neighborhood id 1 — the vacant site's, the far-away tree's and the soft-deleted one's. */
  otherNeighborhoodName: 'Noe Valley',
  /**
   * An R*Tree entry inside the Mission box with **no tree behind it**.
   *
   * Synthetic: the pinned seed's `trees` and `trees_rtree` counts match exactly, so no real file
   * carries one. It is here as a specimen for the other half of the join — a query that projected
   * from `trees_rtree` alone, or joined it with a LEFT JOIN, would emit a row for it.
   */
  phantomRtreeId: 99,
  idSpace: 'sf',
  /** `dim_city.display_name` — what a generation-16-or-newer pack resolves a tree's city to. */
  cityDisplayName: 'San Francisco',
  /** `id_spaces.short_name` — what a generation-15 pack falls back to. Deliberately DIFFERENT text. */
  shortName: 'SF (short name)',
  packId: 'sf',
  regionDisplayName: 'San Francisco',
  regionLevel: 'city',
  /**
   * The second city, region and id space a `fused: true` fixture carries.
   *
   * **The shape the SOURCE seed has and no published pack does.** `publish_cities.py` narrows
   * `dim_region` and `dim_city` to the one unit a pack is for, so a pack holds exactly one row in
   * each; the fused seed every pack is cut from holds all of them — two here, as the pinned seed
   * does (`sf` and `us-ca-sj`). `packIdentity` reads the FIRST row by `id` for exactly that case,
   * and until this fixture existed that choice was observable only against the 103 MB seed:
   * reversing the ordering to `ORDER BY id DESC` reddened one seed-gated test and nothing at all
   * on a runner without the seed. Measured, not supposed.
   */
  secondCitySlug: 'us-ca-sj',
  secondCityDisplayName: 'San Jose',
  secondIdSpace: 'us-ca-sj',
  secondPackId: 'us-ca-sj',
  secondInventoryId: 'sj_street_tree',
  secondRegionId: 2,
  /**
   * **A tree that lives in the second id space** — the fact row the fused fixture was missing.
   *
   * The first fused fixture gave the file two of everything at the *dimension* tables and nothing
   * at the *fact* table: every fixture tree still carried `id_space = 'sf'`, so no row resolved
   * through `id_spaces` row 2 or `dim_city` row 2. A join predicate over those dimensions could
   * therefore be wrong in a single-valued way and no fixture could tell —
   * `LEFT JOIN dim_city dc ON dc.id = isp.city_id` loosened to `ON dc.id = 1` was green in BOTH
   * tiers, while mislabelling all 52,788 San Jose trees in the pinned seed as San Francisco. A
   * duplicating mutation (`ON 1 = 1`) was caught and a constant one was not, because the answer the
   * constant returns was the only answer any fixture row had.
   *
   * Only a `fused: true` pack carries it: `trees.id_space`, `trees.region_id` and
   * `trees.inventory_source` are all foreign keys, and the rows they point at exist only there.
   * Deliberately far outside the Mission box, so it changes no bounding-box expectation.
   */
  sanJoseTreeUUID: '77777777-7777-4777-8777-777777777777',
  sanJoseTreeLatitude: 37.3382,
  sanJoseTreeLongitude: -121.8863,
  /**
   * Trees that are not soft-deleted, in a pack that is not `fused`: the alive tree, the vacant
   * site, the far-away tree, the unindexed tree and the four R*Tree false positives. A fused pack
   * holds one more — the San Jose tree above.
   */
  liveTreeCount: 8,
} as const;

/** `trees.id` of the first R*Tree false positive. Ids 6..9 — one per bound of the Mission box. */
const FIRST_FALSE_POSITIVE_ID = 6;
/** `trees.id` of the San Jose tree, which only a `fused: true` pack carries. */
const SAN_JOSE_TREE_ID = 10;

/** The rows every generation gets, in dependency order. Generation-specific rows are added after. */
function insertCommonRows(db: DatabaseSync, fused: boolean): void {
  const now = '2026-01-01T00:00:00Z';
  db.exec(`
    INSERT INTO species (id, uuid, scientific_name, common_name, family, leaf_retention,
                         created_at, updated_at)
    VALUES (1, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '${FIXTURE.speciesScientificName}',
            '${FIXTURE.speciesCommonName}', 'Platanaceae', 'deciduous', '${now}', '${now}');

    INSERT INTO neighborhoods (id, name, geom_geojson, min_lat, max_lat, min_lon, max_lon,
                               created_at, updated_at)
    VALUES (${FIXTURE.missionNeighborhoodId}, '${FIXTURE.neighborhoodName}',
            '{"type":"Polygon","coordinates":[]}',
            37.76, 37.78, -122.43, -122.41, '${now}', '${now}'),
           (${FIXTURE.otherNeighborhoodId}, '${FIXTURE.otherNeighborhoodName}',
            '{"type":"Polygon","coordinates":[]}',
            37.73, 37.76, -122.44, -122.42, '${now}', '${now}');

    INSERT INTO inventories (id, id_space, name, url)
    VALUES ('sf_city', '${FIXTURE.idSpace}', 'SF Public Works street tree inventory',
            'https://example.invalid/sf');
  `);
  if (fused) {
    // The second id space's own inventory. `trees.inventory_source` is a foreign key, so the San
    // Jose tree below cannot borrow the SF one without claiming a provenance that is not its own —
    // which is the thing `inventories` exists to make answerable per row.
    db.exec(`
      INSERT INTO inventories (id, id_space, name, url)
      VALUES ('${FIXTURE.secondInventoryId}', '${FIXTURE.secondIdSpace}',
              'San Jose street tree inventory', 'https://example.invalid/sj');
    `);
  }
}

/**
 * The rows, always written at the generation-17 shape.
 *
 * **`region_id` is supplied for every generation, including the ones that will not have the
 * column.** `degrade` runs after this, so at insert time the table is still the 17 contract and
 * `region_id` is `NOT NULL`. Writing the rows first and subtracting afterwards is deliberate: it
 * is the only order in which the older fixtures are a strict subtraction from the real contract
 * rather than a hand-built approximation of it, which is the whole argument in this file's header.
 *
 * ## The arrangement, which exists to make the R*Tree join falsifiable
 *
 * `treesInBounds` joins `trees` to `trees_rtree` on `t.<rtreeJoinColumn> = r.id` and then re-tests
 * `lat`/`lon` on `trees`. **That re-test re-derives the right answer from a wrong join**, so a
 * fixture in which the join column is indistinguishable from its neighbors proves nothing about
 * the join. The first version of this file was exactly that fixture: four trees, all
 * `neighborhood_id` 1, R*Tree ids equal to tree ids. Wiring the join to `t.neighborhood_id`
 * reddened no test here at all — only the seed-gated Mission test, on a machine holding the seed.
 *
 * Four properties are arranged here so that a wrong join changes the returned SET, on a runner
 * with no seed:
 *
 * 1. **Two neighborhoods**, and **no tree whose `neighborhood_id` equals its own `id`**. The
 *    `id`/`neighborhood_id` cross-over is what a same-valued column cannot give.
 * 2. **A live tree inside the box with no R*Tree row** (`unindexedTreeUUID`). The correct join
 *    cannot return it, so anything that does — a wrong join that reaches it through another row's
 *    box, or a query that stopped going through the R*Tree at all — shows up as an EXTRA uuid
 *    rather than as an empty set. An empty set is what every broken query looks like; an extra row
 *    names which one.
 * 3. **An R*Tree row with no tree behind it** (`phantomRtreeId`), inside the box, for the other
 *    direction: a projection that read the index instead of the table would emit it.
 * 4. The soft-deleted tree keeps its R*Tree row and the alive tree's exact coordinates, as before,
 *    so only the predicate can drop it.
 * 5. **Four trees whose R*Tree box overlaps the Mission box and whose real coordinates do not**
 *    (`rtreeFalsePositives`), one per re-tested bound. The R*Tree is a *conservative* pre-filter
 *    and the `lat`/`lon` re-test is what removes what it over-returns; without a specimen the
 *    pre-filter and the re-test agree by construction and the re-test can be deleted in silence.
 *
 * Wiring the join to `t.neighborhood_id` now returns the alive tree, the vacant site AND the
 * unindexed tree for the Mission box — three uuids where two are correct.
 */
function insertTrees(db: DatabaseSync, fused: boolean): void {
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
    neighborhood: number,
    deletedAt: string,
    space: { id: string; inventory: string; region: number } = {
      id: FIXTURE.idSpace,
      inventory: 'sf_city',
      region: 1,
    },
  ): string => `
    INSERT INTO trees (id, uuid, id_space, external_ref, source, inventory_source, region_id,
                       lat, lon, address, neighborhood_id, status, species_current,
                       verification_state, created_at, updated_at, deleted_at)
    VALUES (${id}, '${uuid}', '${space.id}', '${ref}', 'city_import', '${space.inventory}',
            ${space.region},
            ${lat}, ${lon}, '${address}', ${neighborhood}, '${status}', ${species},
            'city_record', '${now}', '${now}', ${deletedAt});
  `;

  db.exec(
    tree(1, FIXTURE.aliveTreeUUID, '1001', FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude,
         'alive', '1', '100 Valencia St', FIXTURE.missionNeighborhoodId, 'NULL')
    // A vacant planting site: no species, which is what makes the LEFT JOIN worth asserting. Its
    // neighborhood is the OTHER one, so the two trees the Mission box returns resolve different
    // names — a constant would agree with a join that read the wrong row.
    + tree(2, FIXTURE.vacantTreeUUID, '1002', FIXTURE.vacantTreeLatitude, FIXTURE.vacantTreeLongitude,
           'vacant_site', 'NULL', '102 Valencia St', FIXTURE.otherNeighborhoodId, 'NULL')
    + tree(3, FIXTURE.farAwayTreeUUID, '1003', FIXTURE.farAwayLatitude, FIXTURE.farAwayLongitude,
           'alive', '1', '1 Nowhere Ave', FIXTURE.otherNeighborhoodId, 'NULL')
    + tree(4, FIXTURE.softDeletedTreeUUID, '1004', FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude,
           'alive', '1', '104 Valencia St', FIXTURE.otherNeighborhoodId, "'2026-02-01T00:00:00Z'")
    // Property 2 above: live, inside the Mission box, and given no R*Tree row below.
    + tree(5, FIXTURE.unindexedTreeUUID, '1005', FIXTURE.unindexedTreeLatitude,
           FIXTURE.unindexedTreeLongitude, 'alive', '1', '106 Valencia St',
           FIXTURE.missionNeighborhoodId, 'NULL'),
  );

  // Property 5: the R*Tree's own false positives. Ids 6..9, each one float32 step outside one
  // bound of the Mission box; see `FIXTURE.rtreeFalsePositives`.
  FIXTURE.rtreeFalsePositives.forEach((specimen, index) => {
    db.exec(tree(FIRST_FALSE_POSITIVE_ID + index, specimen.uuid, `200${index}`,
                 specimen.lat, specimen.lon, 'alive', '1', `${index} Edge St`,
                 FIXTURE.otherNeighborhoodId, 'NULL'));
  });

  if (fused) {
    // The fact row in the SECOND id space. See `FIXTURE.sanJoseTreeUUID`: without it the fused
    // fixture doubled every dimension table and left `trees` entirely in the first id space, so a
    // join predicate over those dimensions could resolve through one value only and still look
    // right.
    db.exec(tree(SAN_JOSE_TREE_ID, FIXTURE.sanJoseTreeUUID, '3001',
                 FIXTURE.sanJoseTreeLatitude, FIXTURE.sanJoseTreeLongitude, 'alive', '1',
                 '1 Almaden Blvd', FIXTURE.otherNeighborhoodId, 'NULL',
                 {
                   id: FIXTURE.secondIdSpace,
                   inventory: FIXTURE.secondInventoryId,
                   region: FIXTURE.secondRegionId,
                 }));
  }

  // The R*Tree is populated by hand rather than by a trigger, because the contract has no trigger:
  // `Tools/build_seed.py` fills it, and a fixture that filled it some other way would be testing a
  // mechanism the real packs do not have. Degenerate boxes (min == max) are what a point gets —
  // and a degenerate box is still WIDER than the point, because the R*Tree keeps 32-bit floats and
  // rounds `min` down and `max` up. That expansion is not an aside here: it is what makes ids 6..9
  // false positives rather than misses.
  //
  // Tree 5 is deliberately absent and `phantomRtreeId` is deliberately present; see the header.
  const boxes: [number, number, number][] = [
    [1, FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude],
    [2, FIXTURE.vacantTreeLatitude, FIXTURE.vacantTreeLongitude],
    [3, FIXTURE.farAwayLatitude, FIXTURE.farAwayLongitude],
    [4, FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude],
    [FIXTURE.phantomRtreeId, FIXTURE.aliveTreeLatitude, FIXTURE.aliveTreeLongitude],
  ];
  FIXTURE.rtreeFalsePositives.forEach((specimen, index) => {
    boxes.push([FIRST_FALSE_POSITIVE_ID + index, specimen.lat, specimen.lon]);
  });
  if (fused) {
    boxes.push([SAN_JOSE_TREE_ID, FIXTURE.sanJoseTreeLatitude, FIXTURE.sanJoseTreeLongitude]);
  }
  for (const [id, lat, lon] of boxes) {
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
  options: {
    publishSchemaVersion?: number | null;
    withShortNameToo?: boolean;
    /**
     * Two cities, two regions, two id spaces **and a tree in the second one** — the fused source
     * shape. The fact row is the half that was missing; see `FIXTURE.sanJoseTreeUUID`.
     */
    fused?: boolean;
  } = {},
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
    if (options.fused === true) {
      // Higher ids than the rows above, so "the first row by id" and "the row this fixture's
      // other assertions are about" are the same row — and a reversed ordering picks these.
      db.exec(`
        INSERT INTO dim_city (id, slug, display_name, state, county, urban_forestry_url)
        VALUES (2, '${FIXTURE.secondCitySlug}', '${FIXTURE.secondCityDisplayName}', 'CA',
                'Santa Clara', 'https://example.invalid/urban-forestry-2');

        INSERT INTO dim_region (id, pack_id, display_name, level, city_id)
        VALUES (2, '${FIXTURE.secondPackId}', '${FIXTURE.secondCityDisplayName}', 'city', 2);

        INSERT INTO id_spaces (id, identity_prefix, note, city_id)
        VALUES ('${FIXTURE.secondIdSpace}', 'sj', 'fixture', 2);
      `);
    }
    insertCommonRows(db, options.fused === true);
    insertTrees(db, options.fused === true);
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

    // **A file carrying BOTH civic name sources at once**, which no generation produces on its
    // own — 16 added `dim_city` in the same pass that dropped `id_spaces.short_name`. It is the
    // only shape in which the fallback's ORDER is observable, and without it a read layer that
    // preferred `short_name` over `dim_city` passes every other test in this suite. Found by
    // red-proving exactly that inversion and watching the suite stay green.
    //
    // Not hypothetical, either: the flags are introspected independently and `SeedSchema` says so
    // outright, so a hand-built or transitional file with both is a file this layer may be handed.
    if (options.withShortNameToo === true && generation >= 16) {
      db.exec('ALTER TABLE id_spaces ADD COLUMN short_name TEXT');
      db.exec(`UPDATE id_spaces SET short_name = '${FIXTURE.shortName}'`);
    }
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
 * A pack with **`dim_city` and no `trees.id_space`**, and with **no `trees.deleted_at`**.
 *
 * The mirror image of `buildShortNameWithoutIdSpacePack`, and it exists because the re-audit that
 * found the `dim_city` join resolving through one value found two more branches of the same shape:
 * claims the read layer makes that no fixture could falsify.
 *
 * 1. **`cityNameSource` gates `dc.display_name` on `hasDimCity && hasIdSpace`, never on
 *    `hasDimCity` alone**, because `dc` is joined THROUGH `isp` — its docstring says so at length
 *    and no fixture could show it. Dropping `&& schema.hasIdSpace` was green in both tiers: every
 *    other pack here with a `dim_city` also has `trees.id_space`, so the two flags never disagreed.
 *    On this file they do, and the mutation becomes `no such column: isp.city_id` at prepare time.
 * 2. **`softDeletePredicate` applies `deleted_at IS NULL` only where the column exists.** Every
 *    other fixture carries the column — `schema.sql` always has — so hard-coding the predicate
 *    "always applied" was green everywhere. Here the column is absent and the same mutation is
 *    `no such column: t.deleted_at`.
 *
 * Two degeneracies in one specimen, which is worth being uneasy about; they are kept together
 * because their failures name different columns and cannot be confused for one another, and both
 * were red-proved by mutation before this comment was written.
 *
 * Hand-built for the reason the sibling below gives: `trees.id_space` is part of
 * `UNIQUE (id_space, external_ref)` and SQLite refuses `DROP COLUMN` on an indexed column, so this
 * shape cannot be degraded out of the real contract.
 */
export function buildDimCityWithoutIdSpacePack(): Fixture {
  const directory = mkdtempSync(join(tmpdir(), 'cypress-pack-dimcity-noidspace-'));
  const path = join(directory, 'degenerate-dim-city.sqlite');
  const db = new DatabaseSync(path);
  const now = '2026-01-01T00:00:00Z';
  db.exec(`
    CREATE TABLE species (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                          scientific_name TEXT NOT NULL, common_name TEXT);
    CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE dim_city (id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE,
                           display_name TEXT NOT NULL, state TEXT NOT NULL, county TEXT NOT NULL,
                           urban_forestry_url TEXT NOT NULL);
    CREATE TABLE id_spaces (id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL,
                            note TEXT NOT NULL, city_id INTEGER NOT NULL REFERENCES dim_city(id));
    CREATE TABLE trees (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                        lat REAL NOT NULL, lon REAL NOT NULL, status TEXT NOT NULL,
                        address TEXT, neighborhood_id INTEGER, species_current INTEGER,
                        created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
    CREATE VIRTUAL TABLE trees_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
    INSERT INTO dim_city (id, slug, display_name, state, county, urban_forestry_url)
    VALUES (1, 'us-ca-sf', '${FIXTURE.cityDisplayName}', 'CA', 'San Francisco',
            'https://example.invalid/urban-forestry');
    INSERT INTO id_spaces (id, identity_prefix, note, city_id)
    VALUES ('${FIXTURE.idSpace}', '', 'fixture', 1);
    INSERT INTO trees (id, uuid, lat, lon, status, created_at, updated_at)
    VALUES (1, '${FIXTURE.aliveTreeUUID}', ${FIXTURE.aliveTreeLatitude},
            ${FIXTURE.aliveTreeLongitude}, 'alive', '${now}', '${now}');
    INSERT INTO trees_rtree (id, min_lat, max_lat, min_lon, max_lon)
    VALUES (1, ${FIXTURE.aliveTreeLatitude}, ${FIXTURE.aliveTreeLatitude},
            ${FIXTURE.aliveTreeLongitude}, ${FIXTURE.aliveTreeLongitude});
  `);
  db.close();
  return { path, generation: 16, cleanup: () => rmSync(directory, { recursive: true, force: true }) };
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
