/**
 * The 25 m public-photo grid, and the sphere the rest of the geometry is measured on.
 *
 * Ported from `Cypress/Core/Models/Geometry.swift` — `Coordinate`, `Coordinate.distance(to:)`,
 * `Coordinate.snappedToPublicPhotoGrid()` and `Coordinate.publicPhotoGridM`. That file is the
 * rule's only declaration; nothing in `Data` or `Features` re-derives it, and `Photo.init`
 * (`Cypress/Core/Models/Photo.swift:94`) applies it unconditionally so a caller cannot forget it.
 *
 * ── The one place a naive port is WRONG, and it is silent ────────────────────────────────────
 *
 * Swift's `Double.rounded()` is `.toNearestOrAwayFromZero`: `(-2.5).rounded() == -3`. JavaScript's
 * `Math.round` is round-half-**up** — toward positive infinity — so `Math.round(-2.5) === -2`. Both
 * halves of that were measured, not recalled: the Swift side by compiling the real
 * `Geometry.swift` and printing `(-2.5).rounded()` (see `web/test/support/swift-reference.json`),
 * the JS side by running it.
 *
 * Every longitude in San Francisco, San Jose and New York is negative, so the divergent branch is
 * the one this app is actually in. It only bites when `coordinate / step` lands exactly on a half
 * — rare, and the size of the disagreement is one grid cell, which is 25 m, which is the entire
 * point of the grid. `roundedAwayFromZero` below is therefore explicit and tested against a
 * negative tie — and it is built ON `Math.round`, under `Math.abs`. That is the file's one and
 * only CALL to `Math.round`; every other mention of the name here is prose. It is also the only
 * place a call to it is safe: `Math.abs` hands it a non-negative magnitude, so there is no signed
 * tie for round-half-up to break the wrong way, and `Math.sign` puts the sign back afterwards.
 * The claim, stated so it is true: **no bare `Math.round` on a signed value.** This paragraph
 * read "`Math.round` appears nowhere in this file" until PR #173's review pointed at the call.
 *
 * ── Where the two implementations may legitimately differ ────────────────────────────────────
 *
 * `Math.cos` / `Math.sin` / `Math.atan2` / `Math.sqrt` are not required by either language to be
 * correctly rounded, so V8 and Darwin's libm may disagree in the last unit in the last place. That
 * propagates into `snappedToPublicPhotoGrid` through `metersPerDegreeLon` and into `distance`
 * through the haversine. The tests beside this file assert the Swift output EXACTLY where the two
 * agree bit for bit on this machine and say so, and to a stated tolerance where they cannot be
 * required to. On the sizes involved — 1e-16 degrees, roughly 1e-11 m — the difference is eleven
 * orders of magnitude below the grid cell, so it cannot move a point to a different cell except
 * at a tie, which is the case the paragraph above already governs.
 */

/**
 * A WGS-84 (EPSG:4326) point.
 *
 * An interface rather than a class, for the same reason the Swift is a struct and not a
 * `CLLocationCoordinate2D`: the rule layer stays free of anything that would drag a map framework
 * in behind it.
 */
export interface Coordinate {
  readonly latitude: number;
  readonly longitude: number;
}

/** 25 m snap-to-grid for published photo locations (BUILD-PLAN §10, A7). */
export const publicPhotoGridM = 25;

/** Mean Earth radius, in meters — the sphere `distance` measures on. */
export const earthRadiusM = 6_371_008.8;

/**
 * Meters in one degree of latitude, as the GRID uses it.
 *
 * Deliberately the round 111,320 rather than `π · 6_371_008.8 / 180`, matching the Swift. The two
 * differ by about a tenth of a percent, which costs nothing in a grid and is wrong in a ruler —
 * `VisitPinAdjustPresentation.metersPerDegreeLatitude` carries the other constant and says why.
 */
const gridMetersPerDegreeLatitude = 111_320.0;

/**
 * Swift's `Double.rounded()`: to the nearest, ties away from zero.
 *
 * NOT `Math.round`, which breaks ties toward positive infinity. Negative zero is preserved, which
 * `Math.sign(-0) === -0` gives for free and which matters only because `assert.strictEqual` uses
 * `Object.is` and would separate `-0` from `0` — the Swift produces `-0.0` for a longitude just
 * west of the meridian and this has to produce it too.
 */
export function roundedAwayFromZero(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

/**
 * Public photo locations snap to a universal 25 m grid — everywhere, not only near residential
 * parcels (A7, BUILD-PLAN §10). Tree pins themselves stay exact; this is only for photos.
 *
 * The arithmetic is the Swift's, operation for operation and in the same order, because floating
 * point is not associative and a "tidier" grouping is a different function.
 */
export function snappedToPublicPhotoGrid(coordinate: Coordinate): Coordinate {
  const cell = publicPhotoGridM;
  const metersPerDegreeLat = gridMetersPerDegreeLatitude;
  const metersPerDegreeLon = metersPerDegreeLat * Math.cos((coordinate.latitude * Math.PI) / 180);
  const latStep = cell / metersPerDegreeLat;
  // Toward the poles `cos` collapses and the longitude step would run away; the Swift falls back
  // to the latitude step there rather than dividing by something near zero.
  const lonStep = metersPerDegreeLon > 1 ? cell / metersPerDegreeLon : latStep;
  return {
    latitude: roundedAwayFromZero(coordinate.latitude / latStep) * latStep,
    longitude: roundedAwayFromZero(coordinate.longitude / lonStep) * lonStep,
  };
}

/**
 * Great-circle distance in meters. Used for the "what tree is this?" shortlist ordering and the
 * 10 m add-a-tree proximity dedupe (BUILD-PLAN §6).
 */
export function distance(from: Coordinate, to: Coordinate): number {
  const lat1 = (from.latitude * Math.PI) / 180;
  const lat2 = (to.latitude * Math.PI) / 180;
  const dLat = ((to.latitude - from.latitude) * Math.PI) / 180;
  const dLon = ((to.longitude - from.longitude) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2)
    + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * earthRadiusM * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
