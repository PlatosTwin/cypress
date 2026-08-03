### E?? — The San-Francisco-assumption family, swept: four more members, and the two shapes they come in (found while fixing #181)

*UNNUMBERED — the orchestrator splices the number at merge. Filed from branch `p1/species-page-copy`.*

---

#137, #138, #141 and now #181 have each found one surface that assumed the only city was San
Francisco. Four rediscoveries is enough; the brief for #181 asked for a sweep instead of a fifth
ticket. This is the sweep. **Nothing below is fixed here** — #181's delegation covered its own
card's copy and nothing wider — and each item is sized so it can be picked up as its own ticket.

The sweep found that the family is really **two** families, and only one of them is what the
previous four tickets fixed.

---

## Shape A — a city's *name* hardcoded in reader-facing copy

This is the shape R28 fixed four times over and #181 fixed a fifth. One member remains.

### A1 · The share card names San Francisco on every tree, including San Jose's

**`Cypress/Features/Share/SharePresentation.swift`** — `ShareCopy.city = "San Francisco"`, assembled
into `locationLine` as `<address> · San Francisco` (screen 10 §3).

The doc comment states the justification: *"The city is a constant because the product is one city
deep at launch."* **That premise is now false** — the shipped seed carries 52,788 San Jose rows — so
a San Jose tree shared from screen 10 is captioned with the wrong city, which is #137's defect on a
surface #137 did not reach. Related: `ShareCopy.publicURLPrefix = "https://cypress.app/sf/tree/"`
hardcodes the `sf` slug for every tree (E60 already records that nothing is behind that link).

**Why it is not fixed here.** Unlike screen 07, this surface *has* a row, so R28's mechanism applies
in principle — but R28 derives an **inventory name** (`City of San Jose Street Tree inventory`), and
what this line needs is a short **city name**, which no table carries: `id_spaces` has `id`,
`identity_prefix` and a prose `note`, and `inventories` has the inventory's published name. Deciding
where a short civic name comes from is a data decision beyond this ticket's delegation. It is the
one remaining Shape A member and it should be ticketed.

---

## Shape B — an SF-specific *column meaning* applied to every row

Not a name. A rule written over San Francisco's vocabulary running against another city's data, and
producing a confident, wrong sentence. **This is the shape the existing regression guard cannot
see**, and it is worse on screen than A1.

### B1 · `City lists this as — N/A` on 97.9 % of San Jose trees

**`Cypress/Features/TreeProfile/CityRecordPresentation.swift:125`** — `listedAsText` suppresses the
card when `plant_type` is `"tree"` and draws it otherwise. That is exactly right for DataSF, where
`PlantType` is `Tree` on ~194,988 rows and disagrees on a handful — the card exists to report the
rare row the city says is *not* a tree.

San Jose's `plant_type` is not a plant type at all. It is mapped from `GROWSPACE`, a growing-space
category (`Tools/inventory_adapters.py:712`). **Verified against the shipped seed:**

| id space | rows that draw the card |
|---|---:|
| `sf` | **166** |
| `us-ca-sj` | **51,689** of 52,788 (97.9 %) |

San Jose's values are `N/A` (25,032), `Park Strip` (15,907), `Well/Pit` (3,758), `Median` (1,868),
`Tree Lawn` (1,732), `Open/Unrestricted` (1,200), `Unassigned` (805). So under a photograph of a
tree, a San Jose reader is told **`City lists this as — N/A`**, which is the app asserting that the
city's record says this is not a tree. San Jose's record says no such thing. This is R24's rule —
*a rule written over one city's vocabulary does not run against another's* — broken on 51,689 rows.

### B2 · The `Site` card prints the same San Jose column a second time

**`Cypress/Features/TreeProfile/TreeProfilePresentation.swift:833`** and
**`Cypress/Features/Site/SitePresentation.swift:137`**, both commented as "the DataSF `qSiteInfo`
string verbatim". San Jose's `site_type` is mapped from `GROWSPACE` too
(`Tools/inventory_adapters.py:931`). **Verified: `site_type` is identical to `plant_type` on all
52,788 San Jose rows.**

So a San Jose reader gets one value under two headings — `Site — Park Strip` and
`City lists this as — Park Strip` — and on 25,032 rows reads `Site — N/A` as a recorded placement.
**B1 and B2 must be fixed together**: repairing B1 alone leaves the junk value on screen under the
other label.

### B3 · The no-fix map opens on San Francisco and calls it "the city"

**`Cypress/Features/Map/MapKitBasemap.swift:312`** — `defaultCentre` is Mission Dolores Park,
consumed by `MapOpeningCamera.openingRegion` and `PinSetPresentation.frame(around:)`, with the copy
at `MapOpeningCamera.swift:360`: `"The map is over the middle of the city."`

Documented as "near enough the centre of the inventory", which was true when the inventory was one
city. Under R43 a reader can attach San Jose's file as the *only* inventory; on a cold launch with no
fix they are dropped on San Francisco and told the map is over the middle of the city, above ground
the attached inventory does not cover. Lower severity than B1/B2 and it needs a data-side companion
— `CityManifest.City` carries no centre or bbox to derive one from — which is likely why it survived.

---

## Why the existing guard did not catch Shape B, and what would

`CypressTests/CityRecordSectionTests.everyCitySurfaceNamesTheRowsOwnInventory` sweeps the drawn
strings of one row per inventory for *another city's name* (`foreignCityMarkers`: `SF`,
`San Francisco`, `DataSF`, `San Jose`). It is a good guard for Shape A and it is why Shape A is
nearly extinct.

**It cannot see Shape B, because `N/A` contains no city name.** The string sweep tests the symptom
the first four tickets happened to share, not the disease. The property that would catch B1 and B2
is different in kind: *no card derived from a column whose meaning differs by id space may render
unguarded.* That needs a per-column judgment — which columns are cross-city facts (coordinates,
species) and which are one publisher's vocabulary (`plant_type`, `site_type`, `plot_size`,
`legal_status`, `caretaker`) — and is a ticket of its own.

## Checked and cleared

Recorded so the next sweep does not re-walk them: `agencyGlossary` (keyed on SF caretaker codes San
Jose never emits), `plotSizeText` (San Jose's `SPACEWIDTH` values all return nil — silent data loss,
not a mislabel), `maintenanceOptOutNote` (switches on strings absent from San Jose's
`legal_status`), `pruningNote(idSpace:)` and `LandContext.inferred(from:idSpace:)` (both explicitly
guarded on `sf` — R28/R24 holding), `recordSource`/`recordNumber`/`provenanceNote` (row-derived),
every `AlmanacQueries` read and `AlmanacScope` (fully scope-driven — R29 holding),
`SpeciesQueries.resolveNeighborhood` and `GroveQueries.residentNeighborhood` (both callers fall
through to a radius scope), `TreeQueries.tree` (`LEFT JOIN neighborhoods`, so a null does not drop
the row), the `DataGates` bbox gate (already per-id-space), `ReportPresentation`/311 (copy is
city-neutral; the hazard split runs off `LandContext`, nil outside `sf`), and
`Cypress/Features/Cities/*` (no `sf` literal anywhere). **No hardcoded `id_space = 'sf'` exists in
the app's read layer** — the only occurrences are in `DataGates`, correctly per-space, and in tests.
