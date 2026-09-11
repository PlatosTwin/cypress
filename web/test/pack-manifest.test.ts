import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  MalformedManifestError,
  UnknownManifestFormatError,
  decodeManifest,
} from '../src/lib/pack/manifest.ts';

/**
 * A format-2 entry with every key the live catalog carries.
 *
 * Transcribed from the shape `Tools/publish_cities.py` writes (`manifest = {"manifest_format":
 * MANIFEST_FORMAT, **envelope, "cities": entries}`) rather than invented, so the decoder is being
 * asked about the object it will actually be handed. The values are made up; the KEYS are not.
 */
const liveShapedEntry = {
  id: 'us-ny-nyc-brooklyn',
  display_name: 'Brooklyn',
  coverage: 'full',
  tree_count: 237596,
  schema_version: 17,
  version: 's17-r2026-08-22.02-ac7b1ccc',
  content_rev: '2026-08-22.02',
  bbox: { min_lat: 40.55, max_lat: 40.74, min_lon: -74.05, max_lon: -73.83 },
  centroid: { lat: 40.65, lon: -73.95 },
  region: { level: 'borough', parent_city: 'us-ny-nyc', parent_city_display_name: 'New York City' },
  path: 'cities/us-ny-nyc-brooklyn/s17-r2026-08-22.02-ac7b1ccc/us-ny-nyc-brooklyn.sqlite',
  bytes: 159080448,
  sha256: 'a'.repeat(64),
};

/**
 * The error `run` threw, as a value.
 *
 * `assert.throws` returns `undefined` — it asserts and discards. Three assertions here are about
 * the error's own fields (`format`, the entry it names), and written as
 * `assert.throws(...) as SomeError` they read as if they worked and threw `Cannot read properties
 * of undefined` instead. Measured, not assumed: that is how the first draft of this file failed.
 */
function captured(run: () => unknown): unknown {
  try {
    run();
  } catch (error) {
    return error;
  }
  assert.fail('expected a throw, and nothing was thrown');
}

const envelope = (format: number, cities: unknown[]): string =>
  JSON.stringify({
    manifest_format: format,
    generated_at: '2026-08-22T00:00:00Z',
    generator: 'Tools/publish_cities.py',
    base_url_hint: 'https://cypress-cities.t3.tigrisbucket.io',
    source_seed: 'c9a440b2',
    cities,
  });

describe('the catalog decoder', () => {
  it('decodes a format-2 entry, every field', () => {
    const manifest = decodeManifest(envelope(2, [liveShapedEntry]));
    assert.equal(manifest.format, 2);
    assert.equal(manifest.cities.length, 1);
    const city = manifest.cities[0];
    assert.ok(city !== undefined);
    assert.equal(city.id, 'us-ny-nyc-brooklyn');
    assert.equal(city.displayName, 'Brooklyn');
    assert.equal(city.coverage, 'full');
    assert.equal(city.treeCount, 237596);
    assert.equal(city.schemaVersion, 17);
    assert.equal(city.version, 's17-r2026-08-22.02-ac7b1ccc');
    assert.equal(city.contentRev, '2026-08-22.02');
    assert.deepEqual(city.bbox, {
      minLatitude: 40.55, maxLatitude: 40.74, minLongitude: -74.05, maxLongitude: -73.83,
    });
    assert.deepEqual(city.centroid, { latitude: 40.65, longitude: -73.95 });
    assert.deepEqual(city.region, {
      level: 'borough', parentCity: 'us-ny-nyc', parentCityDisplayName: 'New York City',
    });
    assert.equal(city.bytes, 159080448);
  });

  it('a borough is told from its city by parent_city, which is the only way to ask', () => {
    // The one fact format 2 exists for. `id` is the PACK and `region.parent_city` is the CITY; for
    // a one-region city they are the same string, which is why a reader that assumed they always
    // were would have looked correct against every pack published before New York.
    const wholeCity = {
      ...liveShapedEntry,
      id: 'sf',
      display_name: 'San Francisco',
      region: { level: 'city', parent_city: 'sf', parent_city_display_name: 'San Francisco' },
    };
    const manifest = decodeManifest(envelope(2, [wholeCity, liveShapedEntry]));
    const [sf, brooklyn] = manifest.cities;
    assert.ok(sf !== undefined && brooklyn !== undefined);
    assert.equal(sf.id, sf.region?.parentCity);
    assert.notEqual(brooklyn.id, brooklyn.region?.parentCity);
    assert.equal(brooklyn.region?.parentCity, 'us-ny-nyc');
  });

  it('keeps the publisher order, because the publisher order is the display order', () => {
    // R43 §2. Sorting here would be a silent product decision.
    const ids = ['c', 'a', 'b'].map((id) => ({ ...liveShapedEntry, id }));
    assert.deepEqual(
      decodeManifest(envelope(2, ids)).cities.map((city) => city.id),
      ['c', 'a', 'b'],
    );
  });

  it('reads a format-1 entry, where an absent region is the answer and not a gap', () => {
    // Format 1 stopped being WRITTEN on 2026-08-23; the frozen object it produced is still in the
    // bucket. Every format-1 entry ever published was a whole city, so nil region is correct.
    const { region: _region, content_rev: _rev, bbox: _bbox, centroid: _centroid, ...legacy } =
      liveShapedEntry;
    const manifest = decodeManifest(envelope(1, [{ ...legacy, id: 'sf', display_name: 'San Francisco' }]));
    assert.equal(manifest.format, 1);
    const city = manifest.cities[0];
    assert.ok(city !== undefined);
    assert.equal(city.region, null);
    assert.equal(city.contentRev, null);
    assert.equal(city.bbox, null);
    assert.equal(city.centroid, null);
    assert.equal(city.id, 'sf');
  });

  it('refuses a format it does not know, and says which ones it does', () => {
    const error = captured(() => decodeManifest(envelope(3, [liveShapedEntry])));
    assert.ok(error instanceof UnknownManifestFormatError, `threw ${String(error)}`);
    assert.equal(error.format, 3);
    assert.match(error.message, /manifest_format 3/);
    assert.match(error.message, /1, 2/);
  });

  it('refuses an unknown format BEFORE it looks at the cities', () => {
    // The divergence from the Swift, asserted so it is a decision rather than a difference nobody
    // noticed. A format this build does not read is refused on the format, whatever the entries
    // under it look like — here they are not even objects.
    const error = captured(() => decodeManifest(envelope(99, ['not an object at all'])));
    assert.ok(error instanceof UnknownManifestFormatError, `threw ${String(error)}`);
    assert.equal(error.format, 99);
  });

  it('ignores keys it does not know, because R37.4 reserves the right to add them', () => {
    const withFutureKeys = {
      ...liveShapedEntry,
      compression: 'zstd',
      something_nobody_has_written_yet: { nested: true },
    };
    const manifest = decodeManifest(envelope(2, [withFutureKeys]));
    assert.equal(manifest.cities[0]?.id, 'us-ny-nyc-brooklyn');
  });

  it('carries an unrecognized region level through instead of rejecting the catalog', () => {
    // `level` is the publisher's vocabulary and may gain a member without a format bump. An
    // exhaustive type here would turn an additive value into a decode failure that takes the
    // whole catalog offline — which is a worse outcome than showing a pack by the names it
    // carries, and is the reasoning CityManifest.Region.level states.
    const future = { ...liveShapedEntry, region: { ...liveShapedEntry.region, level: 'arrondissement' } };
    assert.equal(decodeManifest(envelope(2, [future])).cities[0]?.region?.level, 'arrondissement');
  });

  it('does not surface base_url_hint, and does not parse it at all', () => {
    // R37.4: a pack path resolves against the READER's configured base URL, never against a field
    // the remote catalog supplies about itself. Asserted on the decoded value's own keys, so a
    // future edit that adds the field has to delete this test on purpose.
    const manifest = decodeManifest(envelope(2, [liveShapedEntry]));
    assert.deepEqual(Object.keys(manifest).sort(), ['cities', 'format']);
  });

  it('refuses a missing required key, naming the entry and the key', () => {
    const { sha256: _sha, ...noSha } = liveShapedEntry;
    const error = captured(() => decodeManifest(envelope(2, [liveShapedEntry, noSha])));
    assert.ok(error instanceof MalformedManifestError, `threw ${String(error)}`);
    assert.match(error.message, /cities\[1\]/);
    assert.match(error.message, /sha256/);
  });

  it('refuses a count that is not a whole number', () => {
    // A NaN or a 1.5 passing for a count survives into arithmetic and surfaces somewhere
    // unrelated. `typeof === "number"` alone accepts both.
    for (const bad of [1.5, 'many', null]) {
      assert.throws(
        () => decodeManifest(envelope(2, [{ ...liveShapedEntry, tree_count: bad }])),
        MalformedManifestError,
      );
    }
  });

  it('refuses an envelope with no manifest_format, rather than assuming the newest', () => {
    const error = captured(() => decodeManifest(JSON.stringify({ cities: [] })));
    assert.ok(error instanceof MalformedManifestError, `threw ${String(error)}`);
    assert.match(error.message, /manifest_format/);
  });

  it('refuses text that is not JSON, and text that is JSON but not a catalog', () => {
    assert.throws(() => decodeManifest('not json at all'), MalformedManifestError);
    assert.throws(() => decodeManifest('[]'), MalformedManifestError);
    assert.throws(
      () => decodeManifest(JSON.stringify({ manifest_format: 2, cities: {} })),
      MalformedManifestError,
    );
  });

  it('an empty catalog decodes to an empty list — that is data, not an error', () => {
    // Worth pinning: a bucket mid-publish can legitimately list nothing, and turning that into a
    // throw would take a Cities screen offline over a state the publisher passes through.
    assert.deepEqual(decodeManifest(envelope(2, [])).cities, []);
  });
});
