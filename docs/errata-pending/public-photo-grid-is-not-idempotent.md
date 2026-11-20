### The 25 m public photo grid is not idempotent, and the read path applies it twice

**Unnumbered — the orchestrator splices this under the real next E number at merge.**

Found while porting `Coordinate.snappedToPublicPhotoGrid()` to TypeScript for ROADMAP W-B. No
Swift was changed; this is a report.

**The rule.** `Cypress/Core/Models/Geometry.swift:31-41` snaps a published photo location to a
universal 25 m grid (A7, BUILD-PLAN §10). The latitude step is a constant, `25 / 111_320`. The
longitude step is **derived from the latitude**:

```
let metersPerDegreeLon = metersPerDegreeLat * cos(latitude * .pi / 180)
let lonStep = metersPerDegreeLon > 1 ? cell / metersPerDegreeLon : latStep
```

**The defect.** The same call also moves the latitude. So a second application measures the
longitude against a *different* grid than the first did, and lands in a different cell. It is not
a rounding wobble: measured on the real `Geometry.swift`, compiled unmodified
(`web/test/support/swift-reference/main.swift`), across thirteen coordinates —

| coordinate | movement on the **second** snap |
|---|---|
| 37.760123, -122.505456 (SF, the `SharePresentationTests` specimen) | 9.01 m |
| 37.3382, -121.8863 (San Jose) | 10.05 m |
| 37.0, -122.0 | 12.17 m |
| 89.9, 100.0 (near the pole, where `cos` has collapsed to 0.0017) | 12.20 m |
| 40.7128, -74.0060 (NYC) | 0.93 m |
| 0, 0 | 0 m |
| 89.9999, 100.0001 (inside the `latStep` fallback) | 0 m |

A third application is a fixed point in every case, so the drift is one extra hop of up to about
half a cell rather than an unbounded walk.

**Where the `latStep` fallback actually begins, corrected.** An earlier draft of the row above
labelled `89.9, 100.0` as "near the pole, where the `latStep` fallback is in force". It is not, and
the correction is worth keeping because the mistake is easy to make twice: `cos` collapsing is not
the same event as the guard tripping. The branch needs `metersPerDegreeLon = 111_320 · cos(lat)` to
fall to **1 or below**, which is latitude above **89.99948530560983°** — bisected in real Swift
against this repository's `Geometry.swift`, compiled unmodified:

```
89.9      metersPerDegreeLon = 194.28995369179447    fallback? no
89.99     metersPerDegreeLon = 19.429005134590977    fallback? no
89.999    metersPerDegreeLon = 1.9429005232231993    fallback? no
89.9995   metersPerDegreeLon = 0.971450261664357     fallback? YES
89.9999   metersPerDegreeLon = 0.19429005234069185   fallback? YES
```

Until this was corrected **no coordinate in the reference table reached the fallback at all**, so
`lonStep = latStep` was unmeasured in both languages and the TypeScript port reproduced it from a
reading of the Swift rather than from measured output. Two coordinates above the threshold —
`89.9999, 100.0001` and `-89.99995, -100.0001`, one per hemisphere, with longitudes deliberately
off the latitude grid so the branch is distinguishable from the other one — are now in
`web/test/support/swift-reference/main.swift` and recorded in `swift-reference.json`, and
`web/test/geometry.test.ts` asserts the reference still reaches the branch on both sides. Neither
coordinate drifts on a second snap: at that latitude the longitude step is the latitude step, which
does not move when the latitude does, so the fallback is the one place the function IS idempotent.

**It is reachable, on the read path.** `Photo.init` snaps `publicCoordinate` unconditionally
(`Cypress/Core/Models/Photo.swift:94`) — deliberately, so a caller cannot forget the grid, and
`CypressTests/SharePresentationTests.swift:242` asserts exactly that. But
`ContributionStore.decodePhoto` reads the already-snapped `latitude`/`longitude` back out of SQLite
and passes them through that same initializer
(`Cypress/Data/Store/ContributionStore.swift`, the `publicCoordinate:` argument around line 2703).
The value a photo row is read back as is therefore **not** the value that was stored. `Photo`'s
`Codable` conformance is synthesized and assigns stored properties directly, so the JSON path does
not re-snap; the SQLite path is the live one.

**What it is and is not.** It is not a privacy hole — the published point is still on a 25 m grid
and still coarse, which is all A7 asks for. It is a correctness and reproducibility problem: the
published location is not a function of the true location alone, a photo's location can differ
between two surfaces depending on how many times it has been through `Photo.init`, and any future
"the published coordinate has not changed" check would see spurious movement. It also falsifies
the reading a reader takes from `Photo.swift:61` ("already snapped to the universal 25 m grid") —
already snapped to *a* grid, not to *the* grid the next call will use.

**The fix is a decision, not an obvious edit**, which is why this is an erratum and not a PR:

1. **Snap the latitude first, then derive the longitude step from the snapped latitude.** Makes
   the function idempotent and changes every existing published longitude by up to half a cell.
2. **Derive the longitude step from a latitude that does not move** — the cell's own row index, or
   a fixed reference latitude per city. Idempotent, and changes existing values too.
3. **Leave the rule and stop re-applying it**: have `decodePhoto` bypass the snapping initializer
   for a coordinate that is already stored snapped. Changes no published value; leaves the
   function non-idempotent for the next caller who does not know.

Whichever is chosen, 1 and 2 move already-published photo coordinates, so they interact with
whatever guarantee the published packs are held to.

**Where this is asserted today.** `web/test/geometry.test.ts`, "reproduces the Swift's second and
third snap, drift and all", pins the current behavior against the recorded Swift output, including
the drift. If the Swift is repaired, that test goes red and names this file.

**A second, unrelated observation from the same reference run, recorded because it is the kind of
thing that gets rediscovered.** Darwin's `cos()` and V8's `Math.cos` disagree by one unit in the
last place at latitude 40.71280991735537 (`0x3fe84171264570ad` against `...ac`). It reaches the
snapped longitude as 1.42e-14 degrees — 1.2 nanometers — so it matters to an equality assertion
and to nothing else. The web suite's comparator accepts it under a stated 1e-12° threshold and
asserts that exactly two of its seventy-eight comparisons need that threshold, so the tolerance cannot
widen unnoticed.
