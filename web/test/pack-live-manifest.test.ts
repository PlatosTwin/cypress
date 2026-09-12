import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { decodeManifest } from '../src/lib/pack/manifest.ts';
import { NEWEST_KNOWN_PACK_SCHEMA_VERSION } from '../src/lib/pack/versions.ts';

/**
 * The decoder against the artifact it will actually be handed.
 *
 * `test/support/manifest-v2.captured.json` is **the live catalog, verbatim** — fetched from
 * `https://cypress-cities.t3.tigrisbucket.io/manifest-v2.json` on 2026-09-10, byte for byte, not
 * edited and not reformatted. sha256
 * `e2de71266dd2dcd559fc7477d1f6a6f74f8c426a6c742308dd6003239d9179a0`, 8,985 bytes, and the
 * object's own `generated_at` says `2026-08-25T07:04:04+00:00`. A hand-written specimen agrees
 * with whatever its author believed the publisher emits; this one cannot.
 *
 * **It is a snapshot and it is stated as one.** Nothing here fetches — a suite that reaches the
 * network is a suite that fails when the network does, and CI has no business talking to the
 * bucket. So this file is evidence about the catalog as it stood on that date, and the assertions
 * below are chosen to be the ones that should survive a republish: shape, key handling, the
 * relationship between a pack id and its parent city. The specific tree counts are asserted too,
 * and a republish making one of them stale is a *finding to re-capture*, not a defect.
 *
 * **What this does NOT verify**: that any pack named here opens. The seven packs total 713,605,120
 * bytes and none was downloaded. Every statement this suite makes about a generation-17 pack's
 * *contents* comes from a fixture built from `Fixtures/seed/schema.sql`, never from a published
 * file. Said plainly because the difference is easy to lose.
 */
const capturedPath = fileURLToPath(new URL('./support/manifest-v2.captured.json', import.meta.url));
const captured = readFileSync(capturedPath, 'utf8');

describe('the live catalog, as captured on 2026-09-10', () => {
  it('is the bytes this file claims it is', () => {
    // The provenance check CLAUDE.md asks for, done in the suite rather than in prose: if someone
    // edits the fixture to make a test pass, it stops being a capture and this says so. Re-capture
    // and update BOTH numbers, together, in the same change.
    assert.equal(Buffer.byteLength(captured, 'utf8'), 8985);
    assert.equal(
      createHash('sha256').update(captured).digest('hex'),
      'e2de71266dd2dcd559fc7477d1f6a6f74f8c426a6c742308dd6003239d9179a0',
      'test/support/manifest-v2.captured.json is no longer the object that was captured from the '
        + 'bucket. If it was re-captured deliberately, update the hash and the byte count here and '
        + 'in this file’s header; if it was edited to make something pass, it is not a capture.',
    );
  });

  it('decodes, and every entry is a format-2 entry', () => {
    const manifest = decodeManifest(captured);
    assert.equal(manifest.format, 2);
    // The control. A decoder handed an empty `cities` array passes every loop below without
    // executing one of them, which is this project's dominant test-suite defect class.
    assert.equal(
      manifest.cities.length,
      7,
      `the captured catalog decoded ${manifest.cities.length} cities; it holds 7, so this is `
        + 'reading the wrong file or the decoder dropped entries',
    );
    for (const city of manifest.cities) {
      assert.ok(city.id.length > 0, 'an entry has no id');
      assert.ok(city.sha256.length === 64, `${city.id} has a sha256 of ${city.sha256.length} chars`);
      assert.ok(city.bytes > 0, `${city.id} claims ${city.bytes} bytes`);
      assert.ok(city.treeCount > 0, `${city.id} claims ${city.treeCount} trees`);
      assert.notEqual(city.region, null, `${city.id} carries no region, in a format-2 catalog`);
      assert.notEqual(city.contentRev, null, `${city.id} carries no content_rev`);
      assert.notEqual(city.bbox, null, `${city.id} carries no bbox`);
      assert.notEqual(city.centroid, null, `${city.id} carries no centroid`);
    }
  });

  it('every published pack is a generation this build reads', () => {
    // The one assertion that could go red without anybody touching this repository — a publish
    // ahead of the app. That is exactly what it is for, and the message says where to look.
    for (const city of decodeManifest(captured).cities) {
      assert.ok(
        city.schemaVersion <= NEWEST_KNOWN_PACK_SCHEMA_VERSION,
        `the catalog publishes ${city.id} at generation ${city.schemaVersion} and this build reads `
          + `up to ${NEWEST_KNOWN_PACK_SCHEMA_VERSION}. Teach the read layer the new generation `
          + 'before relaxing this.',
      );
    }
  });

  it('carries a key the decoder does not read, which is R37.4 working rather than a gap', () => {
    // Every entry in the live catalog has an `attribution` key. Neither `CityManifest.City` nor
    // this port decodes it, and both are correct to ignore it: R37.4 reserves the right to add
    // keys without a format bump, and a strict decoder would have taken the Cities screen offline
    // the day it appeared. Asserted in both directions so the tolerance is a tested property and
    // not an accident of nobody having looked.
    const raw: unknown = JSON.parse(captured);
    const cities = (raw as Record<string, unknown>)['cities'];
    assert.ok(Array.isArray(cities));
    const first = cities[0] as Record<string, unknown>;
    assert.ok('attribution' in first, 'the captured catalog no longer carries `attribution`');
    const decoded = decodeManifest(captured).cities[0];
    assert.ok(decoded !== undefined);
    assert.equal('attribution' in decoded, false);
  });

  it('the five New York packs are boroughs of one city; the two California ones are whole cities', () => {
    // The relationship format 2 exists to express. `id` is the PACK and `region.parent_city` is
    // the CITY, and they differ only for a sub-city unit — which no published pack demonstrated
    // until New York, so a reader that conflated them would have looked right for a year.
    const cities = decodeManifest(captured).cities;
    const boroughs = cities.filter((city) => city.region?.level === 'borough');
    assert.equal(boroughs.length, 5, `found ${boroughs.length} borough packs, expected 5`);
    for (const borough of boroughs) {
      assert.equal(borough.region?.parentCity, 'us-ny-nyc');
      assert.equal(borough.region?.parentCityDisplayName, 'New York City');
      assert.notEqual(borough.id, borough.region?.parentCity);
    }
    const wholeCities = cities.filter((city) => city.region?.level === 'city');
    assert.deepEqual(wholeCities.map((city) => city.id).sort(), ['sf', 'us-ca-sj']);
    for (const city of wholeCities) assert.equal(city.id, city.region?.parentCity);
  });

  it('San Jose is level city and coverage downtown, which are different questions', () => {
    // `dim_region`'s own comment: "NOTE THAT LEVEL IS NOT COVERAGE: San Jose is level `city` with
    // coverage `downtown`, because it is a whole city of which part shipped." The live catalog is
    // where that distinction is observable, and it is the kind of pair a reader collapses.
    const sanJose = decodeManifest(captured).cities.find((city) => city.id === 'us-ca-sj');
    assert.ok(sanJose !== undefined, 'us-ca-sj is not in the captured catalog');
    assert.equal(sanJose.region?.level, 'city');
    assert.equal(sanJose.coverage, 'downtown');
    const sf = decodeManifest(captured).cities.find((city) => city.id === 'sf');
    assert.equal(sf?.coverage, 'full');
  });

  it('a pack path is the immutable versioned path R37.2 specifies', () => {
    // `cities/<id>/<version>/<id>.sqlite`. Built here from the entry's OWN id and version rather
    // than pattern-matched, so it is an equality and not a shape that a wrong path could satisfy.
    // Note that `version` is still read as opaque: it is compared, never parsed.
    for (const city of decodeManifest(captured).cities) {
      assert.equal(city.path, `cities/${city.id}/${city.version}/${city.id}.sqlite`);
    }
  });

  it('the whole corpus is 713,605,120 bytes, which is why none of it was downloaded', () => {
    // Recorded rather than assumed. The reason this suite has no test that opens a published pack
    // is this number, and a number in the suite is harder to lose than a number in a report.
    const total = decodeManifest(captured).cities.reduce((sum, city) => sum + city.bytes, 0);
    assert.equal(total, 713_605_120);
  });
});
