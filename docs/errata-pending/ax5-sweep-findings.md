# The AX5 sweep's defect inventory (task #144)

*Unnumbered, per the pending-entry rule. One entry for the sweep's findings; each finding below
is a candidate ticket for the next round, not a fix in this one.*

## What was done

`ScreenSweepShots.pair` — light and dark at the drawn size only — is gone. Every state the shot
suites render (the 21-screen sweep, the cold and empty states, the five city-record states, the
land-context handoffs, the species-claim pair, the #151 camera trays) now renders in four
appearances: light, dark, `light-ax5`, `dark-ax5` (`UIContentSizeCategory` AX5 via
`DynamicTypeSize.accessibility5`). Tall captures take a separate `ax5ViewportHeight` capped at
`tallestViewport` (2,700 pt), the E145 ceiling the blank guard enforces.

To regenerate the evidence: run `CypressTests/ScreenSweepShots`, `LandContextShots`,
`SpeciesClaimTests`, and `PhenologyObservedStatesShots` with `TEST_RUNNER_CYPRESS_SHOT_DIR`
set; the shot names below are stable. The run behind this inventory: iPhone 16e simulator,
fresh container, `VERIFY-OK: Test run with 29 tests in 4 suites passed` (plus the phenology
shots suite, 1 test, separately).

**Verified red before green:** with one AX5 viewport forced past the E145 ceiling (2,800 pt),
the guard rejected exactly the AX5 leg — `BLANK CAPTURE 02b-add-tree-light-ax5 — 393×2800 —
only 1 unique color` — and the suite failed. Restored, the sweep is green. Blankness at AX5 is
not silently passable.

**A structural "the primary CTA exists in the AX5 accessibility tree" assertion was built,
watched fail on every screen, and removed** — not because it was wrong but because it is
impossible in-process: SwiftUI serves accessibility over its own bridge and populates no UIKit
element tree (`accessibilityElements` empty, `accessibilityElementCount()` 0, VoiceOver running
or not). `CypressTests/AccessibilityTests`' header already records this dead end at length.
Asserting CTA presence at AX5 needs XCUITest; that is a next-round ticket if wanted.

## Defects found at AX5 (find, don't fix)

Severity is a reading, not a ruling. "Shot" names carry `-light-ax5`; the dark twin shows the
same geometry in every case checked.

1. **Screen 02 (identify, populated) overflows the glass horizontally.** The title renders
   "hat tree is this?", the status capsule "o trees in range · confirm b…", the confirm-by-eye
   callout is clipped on *both* edges ("m by eye. Both are inside t / rror circle…"), and the
   footer reads "one of these? Add this tre". Content wider than 393 pt is being centered and
   clipped, not wrapped. The denied state (`e02-identify-denied`) does not overflow, so the
   width comes from the shortlist furniture, not the header. Shot: `02-identify-light-ax5.png`.

2. **Screen 02 denied-state notice loses its own instruction.** The body truncates with an
   ellipsis mid-sentence: "…or add the tree you are standing…" — the way out it is naming is
   the part that is cut. A line limit is meeting the ramp. Shot: `e02-identify-denied-light-ax5.png`.

3. **Screen 11 (growth history) overflows the glass horizontally.** The tree-name pill is
   clipped off the left edge, the back circle is half off-glass, both charts' end values are
   clipped at the right ("64…", "18…") and the unit labels at the left ("7 cm", "4 m" —
   the leading digits are gone). Shot: `11-growth-history-light-ax5.png`.

4. **Screen 19 (memorial) name column collapses beside the fixed REMOVED badge.** The name
   renders "Juda" next to the badge; the bare fixture renders "Red / Flow / erin" one fragment
   per line. The badge is `.fixedSize()`-shaped and the name gets what is left, which at AX5 is
   a few characters — the same shape as the E106/E183 family. Shots:
   `19-memorial-light-ax5.png`, `e19-memorial-bare-light-ax5.png`.

5. **Screen 10 (share) action captions fragment to nonsense.** "Mes sa…", "Insta gram",
   "AirD rop", "Cop y li…" under the four action circles; the share-card link line also breaks
   mid-token ("cypress.ap / p/sf/tree…"). Shot: `10-share-light-ax5.png`.

6. **Screen 15 (account ask) sign-in CTA truncates.** "Continue with Goo…" — a control label
   with an ellipsis in it. Shot: `15-account-ask-light-ax5.png`.

7. **Screen 07 (species) fact chips split mid-word.** "Cupressac eae", "Evergree n" — the two
   chips share the row at widths the ramp outgrew. Same geometry in `e07-species-uncurated`.
   Shot: `07-species-light-ax5.png`.

8. **The city-record section's two-column grid fragments its values (screens 03/14, §9b).**
   At AX5 the cards keep half-width and the mono values break anywhere: "#22127 / 7" (a record
   number reading as two numbers), "DPW Mainta ined", "Sidewa lk: Curb side : Cutout",
   "A privat e party", "Friend s of the Urban Forest". The C8 quad row above it ellipsizes its
   labels ("Favo…", "Rep…"). One column at accessibility sizes is the likely shape of the fix.
   Shots: `c06-city-record-full-ramp-light-ax5.png` (representative; c01–c05 same geometry).

9. **Minor:** screen 09's field placeholder ellipsizes ("Photo or note (optio…") —
   `09-care-log-light-ax5.png`; screen 18's mono subtitle sets flush to the right glass edge —
   `18-next-tree-light-ax5.png`. Cosmetic mid-word breaks in big serif titles ("Grandmoth er
   Cypress" on 03, 10) are the system wrapping without hyphenation, recorded here so nobody
   re-reports them as clipping.

## Screens that hold at AX5

02b (add composer), 04, 05, 06, 08, 09 (but the placeholder above), 12, 12b, 12c, 13, 14b, 16,
17, 18, 20, 21, the e-series empty states not named above, e141 both arms, e146 all five, and
the three n151 camera trays. Nothing loses a control off-glass on these; pinned CTAs stay on
screen and legible.

## The two open questions the brief carried

- **#132 (add-tree caption truncation) appears already repaired.** The composer joined the
  sweep for the first time (`02b-add-tree`); at AX5 the empty-well sentence renders in full
  *below* the well — the relocation E174's twin commits made on 2026-07-31 (`7668eed`,
  `6255999`), whose doc comment describes exactly #132's truncation ("photo of the tree is
  requir") as the defect it removes. The sweep is not blind — it sees the screen, the well, and
  the whole sentence. Recommend: owner confirms on the phone, then #132 closes citing E174.

- **#142 / the empty-filter card:** no message box, card, or notice stands in for an empty
  filter anywhere in the AX5 renders, matching #165's deletion (`MapChrome.swift` now states
  "no message box ever stands in for a filter"). Screen 01 itself cannot join this harness
  (MapKit renders nothing truthful off-screen — E-record on the map's own errata); its AX5
  contract lives in `CypressUITests/MapFilterAccessibilityTests`.
