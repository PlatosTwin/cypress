### The search UI tests depended on the machine's last `simctl location`, and the guard that was supposed to notice could not fire

Tasks #104 and #101. Two defects in `CypressUITests/MapSearchUITests`, filed separately and fixed
together because they are one mistake: **a test depending on ambient machine state it never states.**

**Neither is a product defect.** Screen 01 does the right thing in every state described below,
including the one the red test was actually finding. What was wrong was what the tests knew.

---

**#104 — "intermittent and unexplained" was neither.**

`testTypingASpeciesNameNarrowsTheMap` typed `Platanus` — the London Plane, the commonest street tree
in San Francisco — and asserted the map was not empty afterwards. Its guard, `requireAMapWithPins`,
only checked that the map had drawn *some* pins. "Some pins are drawn" and "this viewport holds
London Planes" are claims about different sets, and over most of the city they disagree.

Measured on this branch, twice, minutes apart, with no code change between:

| simulated fix | trees in the opening viewport | London Planes | result |
| --- | --- | --- | --- |
| `37.7505,-122.4950` (Sunset Blvd at 37th) | 264 — 95 Monterey Cypress, 52 Monterey Pine | **0** | red: `narrowing … emptied the map` |
| `37.78485,-122.4215` | 156 | **47** | green |
| location revoked outright (opens on Dolores Park) | pins drawn | **0** | red |

The counts are from the seed, queried directly against a 120 × 261 m box at each fix —
`MapLayout.defaultSpanMetres` on this phone's aspect — rather than inferred from pin counts. The
map's settled viewport is slightly wider than that box, so the pins it draws run a little above these
numbers (56 planes drawn at the second fix against 47 in the box); the zeroes are the load-bearing
part and they are zero either way.

So the failure is deterministic in whatever `xcrun simctl location` the device was last left at —
which no code in the file read, no failure message mentioned, and every agent had set differently.
That is why it read as a flake across three machines.

Two traps that kept it hidden and are worth writing down: `xcrun simctl location <udid> clear` does
**not** unfix a device (the app keeps the last fix; revoking the app's location grant is what
unfixes it), and a *streaming* route started with `simctl location <udid> start` persists across
runs and appears in no failure message.

**Fixed by asking instead of assuming.** The map already colours the commonest few species among the
pins it has drawn and puts their names on those pins' accessibility labels (`MapSpeciesPalette`,
`MapPinKind.accessibilityLabel(for:palette:)`). So the test reads the viewport's own census, types
the name of a species that is provably on this screen, and watches a second one disappear while the
first survives. It hardcodes no species, no coordinate, and no assumption about where the map opens
— which matters twice over, because task #115 is changing that. Picking a coordinate that holds
London Planes today was rejected: it is the same defect with a longer fuse.

---

**#101 — a guard that could not fire.**

`requireAMapWithPins` was written as a GPS-fix detector, on the stated grounds that "screen 01 opens
on the user when it has a fix and on the whole city when it does not, and the whole city is zoom ≤ 15
— A1's clustered side: badges, not individual pins."

Every clause after the first is false. Screen 01 opens at `MapLayout.defaultSpanMetres` — 120 m
across — with a fix and without one; only the centre differs, and the fixless centre is
`MapLayout.defaultCentre`, Mission Dolores Park. 120 m is far inside A1's pin threshold, so the
clustered whole-city view the guard was watching for is a state launch cannot produce.
`AlmanacGroupTapTests` had already measured this and written it down against this file by name.

Confirmed here: with location revoked for the app, **five tests ran and none skipped** — and the
narrowing test still failed. The guard stood in front of two tests, certified a precondition it could
not check, and one of them then failed for the exact reason it had just certified absent.

A guard that cannot fire is the same defect as a test that cannot fail, which this file has retired
once already (the return-key test under E166). It now guards what
`testAWordNoSpeciesMatchesSaysSo` actually needs — pins to watch go away, which a viewport over a
park or the ocean legitimately does not have — and its skip message says that instead of prescribing
a GPS fix.

---

**The product behaviour the red test was actually finding, checked on the device rather than read off
the source.** The obvious suspicion is that a search narrowing to zero visible pins draws an empty map
and says nothing — which would be a real defect, and the one worth finding here. It does not. Typed
into a running build at `37.7505,-122.4950`, `Platanus` empties the map and draws, under the search
bar:

> None of the 11 matching species are in view

`MapSearchCopy.status`' `matched == 0` branch, in its counted form — eleven because matching has been
`LIKE '%query%'` over both names since E165, and E38's rule that a page must not wear a total's
clothes applies to the species set as well as the trees. Naming the *viewport* rather than the query
is deliberate: it tells the reader to move the map rather than doubt the spelling.

So the empty map was never silent, and there is no product defect behind #104. What there was is a
test that could not tell that state from a broken one — it read "no pins" and reported "broken",
which is exactly the mistake the app's own copy exists to stop a *person* making.
