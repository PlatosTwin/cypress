import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { openPack, type Pack } from '../src/lib/pack/pack.ts';
import { packIdentity, treeByUUID, treeCount, treesInBounds } from '../src/lib/pack/queries.ts';
import {
  FIXTURE,
  buildPack,
  buildShortNameWithoutIdSpacePack,
  type Fixture,
} from './support/packFixture.ts';

const open: Fixture[] = [];
const packs: Pack[] = [];
function generation(n: 14 | 15 | 16 | 17): Pack {
  const fixture = buildPack(n);
  open.push(fixture);
  const pack = openPack(fixture.path, { immutable: false });
  packs.push(pack);
  return pack;
}
after(() => {
  for (const pack of packs) pack.close();
  for (const fixture of open) fixture.cleanup();
});

/** The box that holds the two Mission trees and excludes the far-away one. */
const missionBounds = {
  minLatitude: 37.77,
  maxLatitude: 37.78,
  minLongitude: -122.43,
  maxLongitude: -122.41,
};

describe('one tree by uuid', () => {
  it('returns the row, field for field', () => {
    const tree = treeByUUID(generation(17), FIXTURE.aliveTreeUUID);
    assert.notEqual(tree, null, 'the alive tree was not found — every assertion below would be vacuous');
    assert.ok(tree !== null);
    assert.equal(tree.uuid, FIXTURE.aliveTreeUUID);
    assert.equal(tree.latitude, FIXTURE.aliveTreeLatitude);
    assert.equal(tree.longitude, FIXTURE.aliveTreeLongitude);
    assert.equal(tree.status, 'alive');
    assert.equal(tree.address, '100 Valencia St');
    assert.equal(tree.speciesScientificName, FIXTURE.speciesScientificName);
    assert.equal(tree.speciesCommonName, FIXTURE.speciesCommonName);
    assert.equal(tree.neighborhoodName, FIXTURE.neighborhoodName);
    assert.equal(tree.cityName, FIXTURE.cityDisplayName);
  });

  it('a vacant planting site has no species, and is a row all the same', () => {
    // The LEFT JOIN this asserts is the difference between "no species" and "no tree". A vacant
    // site is a real record — it is what a reader plants into — and an INNER JOIN would delete it.
    const tree = treeByUUID(generation(17), FIXTURE.vacantTreeUUID);
    assert.ok(tree !== null, 'the vacant site vanished, which an INNER JOIN would do');
    assert.equal(tree.status, 'vacant_site');
    assert.equal(tree.speciesScientificName, null);
    assert.equal(tree.speciesCommonName, null);
    // The OTHER neighborhood, not the alive tree's. The two differ on purpose: a neighborhood
    // join that read a constant row would agree with itself on a fixture where every tree shared
    // one neighborhood, which is what this fixture used to be.
    assert.equal(tree.neighborhoodName, FIXTURE.otherNeighborhoodName);
  });

  it('matches an uppercase uuid, because the app binds uppercase and packs store lowercase', () => {
    // `lower(?)` in the SQL. Foundation's canonical UUID string is uppercase; every pack stores
    // lowercase. Without the normalization this returns null and looks like a missing tree.
    const pack = generation(17);
    const upper = FIXTURE.aliveTreeUUID.toUpperCase();
    assert.notEqual(upper, FIXTURE.aliveTreeUUID, 'the specimen is not actually uppercase');
    assert.equal(treeByUUID(pack, upper)?.uuid, FIXTURE.aliveTreeUUID);
  });

  it('returns null for a uuid that is not there', () => {
    assert.equal(treeByUUID(generation(17), '00000000-0000-4000-8000-000000000000'), null);
  });

  it('does not return a soft-deleted tree', () => {
    // The row exists in the table. It must not come back through any read here.
    const pack = generation(17);
    const raw = pack.db
      .prepare('SELECT COUNT(*) AS n FROM trees WHERE deleted_at IS NOT NULL')
      .get();
    assert.equal(
      Number((raw as Record<string, unknown>)['n']),
      1,
      'the fixture holds no soft-deleted tree, so this test proves nothing',
    );
    assert.equal(treeByUUID(pack, FIXTURE.softDeletedTreeUUID), null);
  });
});

describe('the city-name fallback, which is three sources and not one', () => {
  it('a generation-16-or-newer pack names the city from dim_city', () => {
    for (const n of [16, 17] as const) {
      assert.equal(
        treeByUUID(generation(n), FIXTURE.aliveTreeUUID)?.cityName,
        FIXTURE.cityDisplayName,
        `s${n} did not resolve its city through dim_city`,
      );
    }
  });

  it('a generation-15 pack falls back to id_spaces.short_name, and the text proves which', () => {
    // The two sources carry DELIBERATELY DIFFERENT strings in the fixture — "San Francisco" in
    // `dim_city.display_name`, "SF (short name)" in `id_spaces.short_name`. If they matched, this
    // assertion would pass whichever source the query read, which is a test agreeing with itself.
    assert.notEqual(FIXTURE.cityDisplayName, FIXTURE.shortName);
    assert.equal(treeByUUID(generation(15), FIXTURE.aliveTreeUUID)?.cityName, FIXTURE.shortName);
  });

  it('dim_city wins when a file carries both sources, which is the order and not a coincidence', () => {
    // No real generation has both — 16 added `dim_city` in the same pass that dropped
    // `id_spaces.short_name` — so the PRECEDENCE between them is invisible on every other fixture
    // here. This test exists because inverting the two branches in `cityNameSource` left the whole
    // suite green: a guard that was green while the defect it names was present, caught by
    // red-proving it rather than by reading it.
    const fixture = buildPack(16, { withShortNameToo: true });
    open.push(fixture);
    const pack = openPack(fixture.path, { immutable: false });
    packs.push(pack);
    assert.equal(pack.schema.hasDimCity, true);
    assert.equal(pack.schema.hasCivicShortNames, true, 'the fixture carries only one source');
    assert.equal(
      treeByUUID(pack, FIXTURE.aliveTreeUUID)?.cityName,
      FIXTURE.cityDisplayName,
      'the city name came from id_spaces.short_name, but dim_city is the preferred source: it is '
        + 'the table id_spaces.short_name was absorbed INTO, so preferring short_name shows the '
        + 'older of two answers as if it were the newer.',
    );
  });

  it('a generation-14 pack has neither, and says null rather than inventing one', () => {
    // DECISIONS constraint 15: do not invent civic content. Null is the honest answer.
    assert.equal(treeByUUID(generation(14), FIXTURE.aliveTreeUUID)?.cityName, null);
  });

  it('short_name with no trees.id_space prepares and answers null, instead of throwing', () => {
    // The prepare-time collision the gating exists for. A projection of `isp.short_name` gated on
    // `hasCivicShortNames` ALONE references an alias its own join never introduced, and SQLite
    // answers `no such column: isp.short_name` when the statement is prepared — a failure that
    // looks like a naming bug and is a gating bug.
    const fixture = buildShortNameWithoutIdSpacePack();
    open.push(fixture);
    const pack = openPack(fixture.path, { immutable: false });
    packs.push(pack);
    assert.equal(pack.schema.hasCivicShortNames, true);
    assert.equal(pack.schema.hasIdSpace, false);
    const tree = treeByUUID(pack, FIXTURE.aliveTreeUUID);
    assert.ok(tree !== null, 'the degenerate pack returned no tree at all');
    assert.equal(tree.cityName, null);
  });
});

describe('trees in a bounding box', () => {
  it('returns the trees inside it and not the one outside', () => {
    const rows = treesInBounds(generation(17), missionBounds, 50);
    assert.deepEqual(
      rows.map((row) => row.uuid),
      [FIXTURE.aliveTreeUUID, FIXTURE.vacantTreeUUID],
      'the box did not return exactly the two Mission trees',
    );
  });

  it('goes through the R*Tree: a live tree in the box with no R*Tree row is not returned', () => {
    // **The assertion that makes the R*Tree join falsifiable without the 103 MB seed.**
    //
    // `treesInBounds` re-tests `lat`/`lon` on `trees` after the join, so a fixture whose every
    // tree is reachable through some R*Tree row cannot tell a correct join from a wrong one — the
    // re-test re-derives the right answer either way. `unindexedTreeUUID` is live, sits inside
    // this box, and has no R*Tree row, so the correct query CANNOT return it and any query that
    // reaches it did not go through the index. See `packFixture.ts`'s `insertTrees`.
    const pack = generation(17);
    assert.equal(
      treeByUUID(pack, FIXTURE.unindexedTreeUUID)?.uuid,
      FIXTURE.unindexedTreeUUID,
      'the unindexed tree is missing from the table, so its absence below would prove nothing',
    );
    const indexed = pack.db
      .prepare('SELECT COUNT(*) AS n FROM trees_rtree WHERE id = 5')
      .get() as Record<string, unknown>;
    assert.equal(Number(indexed['n']), 0, 'the unindexed tree acquired an R*Tree row');
    assert.equal(
      treesInBounds(pack, missionBounds, 50).map((row) => row.uuid)
        .includes(FIXTURE.unindexedTreeUUID),
      false,
      'a tree with no R*Tree row came back from a query that is supposed to go through it',
    );
  });

  it('an R*Tree row with no tree behind it produces no row', () => {
    // The other direction of the same join. `phantomRtreeId` sits inside this box and matches no
    // tree, so a projection reading the index rather than the table would emit a row for it.
    const pack = generation(17);
    const entries = pack.db.prepare('SELECT COUNT(*) AS n FROM trees_rtree').get();
    assert.equal(
      Number((entries as Record<string, unknown>)['n']),
      5,
      'the R*Tree does not hold the phantom entry, so this test is asserting nothing',
    );
    assert.equal(treesInBounds(pack, missionBounds, 50).length, 2);
  });

  it('the two trees in the box resolve different neighborhoods', () => {
    // Not decoration: it is the statement that `neighborhood_id` varies across these rows, which
    // is what makes wiring the R*Tree join to that column change the answer. If this ever
    // collapses to one name, the R*Tree join has stopped being falsifiable here.
    assert.notEqual(FIXTURE.neighborhoodName, FIXTURE.otherNeighborhoodName);
    assert.deepEqual(
      treesInBounds(generation(17), missionBounds, 50).map((row) => row.neighborhoodName),
      [FIXTURE.neighborhoodName, FIXTURE.otherNeighborhoodName],
    );
  });

  it('the excluded tree is excluded for being outside, not for being absent', () => {
    // The control that separates "the filter works" from "the query returns nothing". Widen the
    // box to hold all three and the third appears.
    const pack = generation(17);
    const wide = { minLatitude: 30, maxLatitude: 45, minLongitude: -125, maxLongitude: -70 };
    const uuids = treesInBounds(pack, wide, 50).map((row) => row.uuid);
    assert.equal(uuids.length, 3, `a box holding every live tree returned ${uuids.length}`);
    assert.ok(uuids.includes(FIXTURE.farAwayTreeUUID));
    // Three, not four: the fourth live tree has no R*Tree row. Stated here so the count above is
    // read as the arrangement it is rather than as `liveTreeCount`.
    assert.equal(uuids.includes(FIXTURE.unindexedTreeUUID), false);
  });

  it('excludes the soft-deleted tree even though it sits inside the box', () => {
    // It shares the alive tree's coordinates exactly, so the R*Tree returns it and only the
    // predicate can drop it. That is what makes this an assertion about the predicate.
    const uuids = treesInBounds(generation(17), missionBounds, 50).map((row) => row.uuid);
    assert.equal(uuids.includes(FIXTURE.softDeletedTreeUUID), false);
  });

  it('honors the limit', () => {
    assert.equal(treesInBounds(generation(17), missionBounds, 1).length, 1);
  });

  it('refuses a limit that is not a positive whole number', () => {
    // A read surface that can be asked for every row by a query string has a denial of service in
    // it, and a default nobody chose is how that ships.
    const pack = generation(17);
    for (const bad of [0, -1, 1.5, Number.NaN]) {
      assert.throws(() => treesInBounds(pack, missionBounds, bad), RangeError);
    }
  });

  it('returns the same rows on every generation, because geometry did not change', () => {
    for (const n of [14, 15, 16, 17] as const) {
      assert.deepEqual(
        treesInBounds(generation(n), missionBounds, 50).map((row) => row.uuid),
        [FIXTURE.aliveTreeUUID, FIXTURE.vacantTreeUUID],
        `s${n} returned a different set for the same box`,
      );
    }
  });

  it('an empty box returns nothing, and that is not how a broken query looks', () => {
    // Asserted beside the populated case on purpose. On its own an empty result is exactly what a
    // query reading the wrong table produces.
    const empty = { minLatitude: -1, maxLatitude: -0.9, minLongitude: -1, maxLongitude: -0.9 };
    assert.deepEqual(treesInBounds(generation(17), empty, 50), []);
  });
});

describe('counting and identity', () => {
  it('counts the live trees and not the soft-deleted one', () => {
    const pack = generation(17);
    assert.equal(treeCount(pack), FIXTURE.liveTreeCount);
    const total = pack.db.prepare('SELECT COUNT(*) AS n FROM trees').get();
    assert.equal(
      Number((total as Record<string, unknown>)['n']),
      FIXTURE.liveTreeCount + 1,
      'the table holds no soft-deleted row, so treeCount excluding one proves nothing',
    );
  });

  it('a generation-17 pack states its region, its level and its city', () => {
    const identity = packIdentity(generation(17));
    assert.deepEqual(identity, {
      packId: FIXTURE.packId,
      regionDisplayName: FIXTURE.regionDisplayName,
      regionLevel: FIXTURE.regionLevel,
      cityDisplayName: FIXTURE.cityDisplayName,
      cityState: 'CA',
      urbanForestryURL: 'https://example.invalid/urban-forestry',
      statedPackId: FIXTURE.packId,
      statedSchemaVersion: 17,
    });
  });

  it('a generation-16 pack has a city and no region, and says so with nulls', () => {
    const identity = packIdentity(generation(16));
    assert.equal(identity.packId, null);
    assert.equal(identity.regionLevel, null);
    assert.equal(identity.cityDisplayName, FIXTURE.cityDisplayName);
    assert.equal(identity.statedSchemaVersion, 16);
  });

  it('a generation-15 pack has neither table, and reads without throwing', () => {
    const identity = packIdentity(generation(15));
    assert.equal(identity.packId, null);
    assert.equal(identity.cityDisplayName, null);
    assert.equal(identity.statedSchemaVersion, 15);
  });
});
