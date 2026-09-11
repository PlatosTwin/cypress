/**
 * The 25 m grid, against the real `Geometry.swift`.
 *
 * Two kinds of assertion, proving different things:
 *
 *  * the **constant** is parsed out of `Cypress/Core/Models/Geometry.swift` at run time, so a
 *    change to the grid size fails this file rather than leaving the web on 25 m quietly;
 *  * the **outputs** are compared against `support/swift-reference.json`, which the real Swift
 *    printed — see `support/swift-reference/main.swift` for the command and for why a recorded run
 *    rather than a live one.
 *
 * The ported Swift cases are thin here, and that is a finding rather than an omission: the only
 * direct test of the grid in `CypressTests` is `SharePresentationTests.swift:242-247`, which
 * asserts `Photo.init` snaps unconditionally and that snapping moves the point. Both are below.
 * Everything else is new coverage the reference run made possible — including the two things it
 * turned up, which are recorded in this file's other two doc comments.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  distance,
  publicPhotoGridM,
  roundedAwayFromZero,
  snappedToPublicPhotoGrid,
} from '../src/lib/geometry.ts';
import { repoFile, swiftDoubleLet } from './support/sources.ts';

interface SnapCase {
  readonly lat: number;
  readonly lon: number;
  readonly snappedLat: number;
  readonly snappedLon: number;
  readonly twiceLat: number;
  readonly twiceLon: number;
  readonly thriceLat: number;
  readonly thriceLon: number;
  readonly driftM: number;
}

interface Reference {
  readonly publicPhotoGridM: number;
  readonly rounded: readonly { x: number; rounded: number }[];
  readonly snapped: readonly SnapCase[];
  readonly distances: readonly { a: [number, number]; b: [number, number]; meters: number }[];
}

const reference = JSON.parse(
  readFileSync(new URL('./support/swift-reference.json', import.meta.url), 'utf8'),
) as Reference;

/**
 * **Where the two implementations legitimately differ, measured rather than predicted.**
 *
 * Neither language requires `cos` to be correctly rounded, and Darwin's libm and V8 disagree by
 * one unit in the last place for exactly one of the latitudes below. For 40.71280991735537 rad
 * → both agree on 0.7105725807964517 to the bit, and then:
 *
 *     Swift  cos = 0.7579885241971361   (0x3fe84171264570ad)
 *     Node   cos = 0.757988524197136    (0x3fe84171264570ac)
 *
 * That is a one-bit difference. It reaches the snapped longitude as 1.42e-14 degrees, which is
 * 1.2 NANOMETERS — eleven orders of magnitude under the 25 m cell it is a coordinate on.
 *
 * So the comparator below accepts bit-equality, or a difference under a threshold stated in
 * degrees and far too small to hide a real error: a wrong rounding rule misplaces a point by a
 * whole cell and a transposed step by more, both of which are 1e12 times this. **And the tolerance
 * cannot quietly widen into covering a real divergence, because the number of comparisons that
 * NEED it is asserted** — 2 of 78 today, measured. A port that started needing the tolerance
 * everywhere would fail that count, which is the assertion that keeps this from being a way of
 * saying "close enough".
 */
const TOLERANCE_DEGREES = 1e-12;

let toleranceUsed = 0;

function agreesWithSwift(got: number, swift: number, what: string): void {
  if (Object.is(got, swift)) return;
  toleranceUsed += 1;
  const delta = Math.abs(got - swift);
  assert.ok(
    delta < TOLERANCE_DEGREES,
    `${what}: TypeScript ${got}, Swift ${swift}, difference ${delta}° — far above the `
      + `${TOLERANCE_DEGREES}° that a last-bit disagreement in cos() can produce. This is a port `
      + `error, not a libm difference.`,
  );
}

describe('the 25 m public photo grid', () => {
  it('the cell size is the one Geometry.swift declares', () => {
    const inSwift = swiftDoubleLet(repoFile('Cypress/Core/Models/Geometry.swift'), 'publicPhotoGridM');
    assert.equal(
      publicPhotoGridM,
      inSwift,
      `web/src/lib/geometry.ts says the grid cell is ${publicPhotoGridM} m; `
        + `Cypress/Core/Models/Geometry.swift says ${inSwift} m. A7 and BUILD-PLAN §10 specify one `
        + `universal grid, and two surfaces publishing photo locations on different grids is a `
        + `privacy claim nobody made.`,
    );
    assert.equal(
      reference.publicPhotoGridM,
      inSwift,
      'support/swift-reference.json was produced from a different grid size than the Swift now '
        + 'declares. Regenerate it — see support/swift-reference/main.swift.',
    );
  });

  /**
   * **The one place a naive port is silently wrong.**
   *
   * `Math.round(-2.5)` is -2 and Swift's `(-2.5).rounded()` is -3: `.toNearestOrAwayFromZero`
   * against round-half-toward-positive-infinity. Every longitude this app cares about is negative.
   * The specimens come from the reference run, so the expected side is Swift's own output rather
   * than a reading of the documentation.
   */
  it('rounds ties away from zero, the way Swift does and Math.round does not', () => {
    assert.equal(reference.rounded.length, 10, 'the reference lost its rounding cases');
    let disagreements = 0;
    for (const { x, rounded } of reference.rounded) {
      assert.ok(
        Object.is(roundedAwayFromZero(x), rounded),
        `roundedAwayFromZero(${x}) is ${roundedAwayFromZero(x)}; Swift's (${x}).rounded() is ${rounded}`,
      );
      if (Math.round(x) !== rounded) disagreements += 1;
    }
    assert.equal(
      disagreements,
      4,
      `${disagreements} of the reference's rounding cases disagree with Math.round, not 4. If this `
        + `is 0 the specimens no longer include a negative tie, and the assertion above would pass `
        + `with roundedAwayFromZero replaced by Math.round — which is the bug it exists to catch.`,
    );
  });

  it('reproduces the Swift’s snapped coordinates', () => {
    assert.equal(
      reference.snapped.length,
      13,
      `the reference holds ${reference.snapped.length} snapped coordinates, not 13 — a case table `
        + `that shrank is a check that stopped checking`,
    );
    for (const row of reference.snapped) {
      const got = snappedToPublicPhotoGrid({ latitude: row.lat, longitude: row.lon });
      // `Object.is` inside `agreesWithSwift`, not `===`: the reference records `-0` for a
      // longitude just west of the meridian, and `-0 === 0`. The sign of zero is the whole
      // reason this is spelled out rather than left to `assert.equal`.
      agreesWithSwift(got.latitude, row.snappedLat, `snap(${row.lat}, ${row.lon}).latitude`);
      agreesWithSwift(got.longitude, row.snappedLon, `snap(${row.lat}, ${row.lon}).longitude`);
    }
  });

  it('the cases cover both hemispheres and both signs of longitude', () => {
    // The rounding divergence only shows on negatives; a table of San Francisco coordinates would
    // exercise one sign of longitude and neither sign of latitude.
    const quadrants = new Set(
      reference.snapped
        .filter((row) => row.lat !== 0 && row.lon !== 0)
        .map((row) => `${Math.sign(row.lat)},${Math.sign(row.lon)}`),
    );
    assert.equal(
      quadrants.size,
      4,
      `the snapped cases reach ${quadrants.size} of the four sign quadrants (${[...quadrants].join(' ')})`,
    );
  });

  /**
   * `SharePresentationTests.swift:242-247`, ported. The Swift builds a `Photo` to show the snap is
   * unconditional; `Photo` is not part of W-B, so what is ported is the claim that test makes
   * about the coordinate itself.
   */
  it('snapping moves an exact coordinate', () => {
    const exact = { latitude: 37.760123, longitude: -122.505456 };
    assert.notDeepEqual(
      snappedToPublicPhotoGrid(exact),
      exact,
      'the specimen is already on the grid, so this proves nothing',
    );
  });

  /**
   * **A finding, not a port artifact: the snap is NOT idempotent, and the port reproduces that.**
   *
   * The longitude step is derived from the latitude — `metersPerDegreeLon = 111_320 · cos(lat)` —
   * and the first pass MOVES the latitude. A second pass therefore measures the longitude against
   * a different grid and lands in a different cell. Measured on the real `Geometry.swift`: up to
   * 12.20 m of movement on the second pass across the thirteen reference coordinates, settling from
   * the third.
   *
   * It is reachable. `ContributionStore.decodePhoto` (`Cypress/Data/Store/ContributionStore.swift`,
   * the `publicCoordinate:` argument around line 2703) reads the already-snapped latitude and
   * longitude out of SQLite and hands them to `Photo.init`, which snaps again — so a photo's
   * published location as read back is not the location that was stored. Written up unnumbered in
   * `docs/errata-pending/public-photo-grid-is-not-idempotent.md`. Nothing in the Swift was changed
   * for it; this round ports rules and does not edit them.
   *
   * The assertion is what the Swift DOES, so the port is proved faithful rather than proved
   * pleasant. If the Swift is ever repaired, this goes red and points at the errata.
   */
  it('reproduces the Swift’s second and third snap, drift and all', () => {
    let moved = 0;
    let worst = 0;
    for (const row of reference.snapped) {
      const once = snappedToPublicPhotoGrid({ latitude: row.lat, longitude: row.lon });
      const twice = snappedToPublicPhotoGrid(once);
      const thrice = snappedToPublicPhotoGrid(twice);
      const where = `(${row.lat}, ${row.lon})`;
      agreesWithSwift(twice.latitude, row.twiceLat, `second snap of ${where}, latitude`);
      agreesWithSwift(twice.longitude, row.twiceLon, `second snap of ${where}, longitude`);
      agreesWithSwift(thrice.latitude, row.thriceLat, `third snap of ${where}, latitude`);
      agreesWithSwift(thrice.longitude, row.thriceLon, `third snap of ${where}, longitude`);
      // Third equals second in the reference: one extra hop, not a runaway.
      assert.ok(
        Object.is(row.thriceLat, row.twiceLat) && Object.is(row.thriceLon, row.twiceLon),
        `${where} had not settled by the third snap in the Swift either — the drift compounds, `
          + `which is worse than the errata records and needs the errata rewritten`,
      );
      if (row.driftM > 0) moved += 1;
      worst = Math.max(worst, row.driftM);
    }
    // The premise, asserted. If the reference ever shows no drift anywhere, every assertion above
    // is comparing a value to itself and this test has stopped saying anything.
    assert.ok(
      moved >= 8 && worst > 1,
      `only ${moved} of ${reference.snapped.length} reference coordinates move on a second snap `
        + `(worst ${worst} m). Either the Swift was repaired — in which case delete this test and `
        + `the errata — or the specimens no longer exercise the defect.`,
    );
  });

  /**
   * **The `lonStep = latStep` fallback, measured rather than read.**
   *
   * This test did not exist, and the errata said the fallback was "in force" at 89.9. It is not.
   * PR #173's review caught the sentence; the threshold was then bisected in real Swift against
   * this repository's own `Geometry.swift` — the branch fires at latitude above
   * **89.99948530560983°**, where `111_320 · cos(lat)` finally drops to 1 or below. At 89.9 that
   * expression is 194.28995369179447, which is not remotely close.
   *
   * So until the two rows above 89.9999 were added to the reference table, NO reference coordinate
   * reached the branch, `geometry.ts` reproduced it by reading the Swift rather than by measuring
   * it, and this suite would have been just as green with the fallback written any other way. The
   * assertion below is what makes the branch a measured one: it checks the reference actually
   * contains coordinates on BOTH sides of the threshold, so the rows above cannot quietly drift
   * back out of the branch and leave the exact comparisons passing on the near side only.
   */
  it('the reference reaches the pole fallback, on both sides of the threshold', () => {
    // Recomputed here from the constants the port declares, rather than pasted as 89.99949: a
    // threshold transcribed from a comment is the thing that was wrong in the first place.
    const metersPerDegreeLon = (lat: number): number =>
      111_320.0 * Math.cos((lat * Math.PI) / 180);
    const inFallback = (lat: number): boolean => !(metersPerDegreeLon(Math.abs(lat)) > 1);

    assert.equal(inFallback(89.9), false, 'the premise: 89.9 is NOT in the fallback');
    assert.ok(
      metersPerDegreeLon(89.9) > 190,
      `111_320·cos(89.9°) is ${metersPerDegreeLon(89.9)} m/°, nowhere near the 1 m/° the branch needs`,
    );

    const reached = reference.snapped.filter((row) => inFallback(row.lat));
    assert.ok(
      reached.length >= 2,
      `${reached.length} of the ${reference.snapped.length} reference coordinates reach the `
        + `\`lonStep = latStep\` fallback. Below two, the branch is exercised on one side of the `
        + `pole or on neither, and geometry.ts reproduces it from a reading of the Swift rather `
        + `than from measured output — which is the thing this whole directory exists not to do.`,
    );
    assert.equal(
      new Set(reached.map((row) => Math.sign(row.lat))).size,
      2,
      'the fallback coordinates are all in one hemisphere',
    );
    // And the branch actually DID something: with the cos-derived step these longitudes would land
    // in an entirely different place (25/0.194 ≈ 129° per cell), so a port that took the wrong
    // branch could not produce the recorded value by accident.
    for (const row of reached) {
      const cosStep = publicPhotoGridM / metersPerDegreeLon(row.lat);
      assert.ok(
        cosStep > 100,
        `at ${row.lat} the cos-derived step is ${cosStep}°, which is close enough to the latitude `
          + `step that this row does not distinguish the two branches`,
      );
      assert.ok(
        Math.abs(row.snappedLon - row.lon) < 0.001,
        `snap(${row.lat}, ${row.lon}) moved the longitude to ${row.snappedLon}, which is not the `
          + `small move the latitude-sized step produces — read the reference, not this comment`,
      );
    }
  });

  it('no snapped point is further than one cell from where it started', () => {
    // The property the grid is FOR, stated independently of the arithmetic that implements it:
    // the published point stays in the neighborhood of the real one.
    for (const row of reference.snapped) {
      const original = { latitude: row.lat, longitude: row.lon };
      const movedM = distance(original, snappedToPublicPhotoGrid(original));
      assert.ok(
        movedM <= publicPhotoGridM,
        `snapping (${row.lat}, ${row.lon}) moved it ${movedM} m, more than one ${publicPhotoGridM} m cell`,
      );
    }
  });
});

describe('great-circle distance', () => {
  it('reproduces the Swift’s meters exactly', () => {
    assert.equal(reference.distances.length, 5, 'the reference lost its distance cases');
    for (const row of reference.distances) {
      const got = distance(
        { latitude: row.a[0], longitude: row.a[1] },
        { latitude: row.b[0], longitude: row.b[1] },
      );
      assert.ok(
        Object.is(got, row.meters),
        `distance(${row.a}, ${row.b}) — TypeScript ${got}, Swift ${row.meters}, `
          + `delta ${got - row.meters} m`,
      );
    }
  });
});

/**
 * Runs last, and reads what the comparator recorded while the tests above ran.
 *
 * `describe` bodies execute before any `it`, so the count here is the count after the whole file.
 * The point is in the file header: a tolerance that nobody counts is a tolerance that grows.
 */
describe('the size of the libm disagreement', () => {
  it('only the two comparisons that are known to need the tolerance use it', () => {
    assert.equal(
      toleranceUsed,
      2,
      `${toleranceUsed} of the 78 coordinate comparisons needed the ${TOLERANCE_DEGREES}° `
        + `tolerance rather than matching Swift to the bit; 2 did when this was measured, both of `
        + `them the longitude of the second snap at 40.7128, -74.006, where Darwin's cos() and `
        + `V8's differ in the last bit. MORE than 2 means something in the port stopped being `
        + `exact and is being carried by the tolerance. FEWER means the toolchains converged, `
        + `which is good news and still wants this number corrected rather than left loose.`,
    );
  });

  it('a last-bit disagreement is eleven orders of magnitude under the grid cell', () => {
    // `Math.nextUp` is a proposal, not a function V8 has. The next representable double up is
    // computed through the bit pattern instead, which is the definition rather than an estimate.
    const nextUp = (value: number): number => {
      const view = new DataView(new ArrayBuffer(8));
      view.setFloat64(0, value);
      view.setBigUint64(0, view.getBigUint64(0) + 1n);
      return view.getFloat64(0);
    };
    assert.notEqual(nextUp(37.7601), 37.7601, 'nextUp returned its argument; this measures nothing');
    const worstCase = distance(
      { latitude: 37.7601, longitude: -122.5054 },
      { latitude: nextUp(37.7601), longitude: -122.5054 },
    );
    assert.ok(worstCase > 0, 'one ULP of latitude measured as zero distance; this measures nothing');
    assert.ok(
      worstCase < publicPhotoGridM / 1e9,
      `one unit in the last place of a latitude is ${worstCase} m, which is not negligible against `
        + `a ${publicPhotoGridM} m cell — the reasoning in this file's header no longer holds`,
    );
  });
});
