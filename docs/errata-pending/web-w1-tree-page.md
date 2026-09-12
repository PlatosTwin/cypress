# Unnumbered — the orchestrator splices these under the next E numbers at merge (CLAUDE.md,
# Numbering). Written from branch `web/w1-tree-page`, 2026-09-11, milestone W-C. Every claim below
# was measured on this tree or against the pinned seed
# (`Fixtures/seed/cypress-seed.sqlite`, sha256 `c9a440b2…68fb`, `count(*)` 198,625 = the pin's
# `tree_count`), not copied from a document.

### §W1's fact column is drawn from two databases, and the page can reach one of them

`SCREENS.md` §W1 (line 1591) specifies six fact rows, a foliage strip with a photo caption, and a
recent-visits panel. Held against a real pack, **seven of those eleven elements have no public
source**. `docs/ROADMAP.md` already records the halving in general terms; this entry records the
element-by-element result, because "about half" is not a thing a later reader can check a page
against.

What the pack answers, measured on the pinned seed: `address`, `city`, `species`, `planted_year`,
`site_type`, `external_ref`, `inventory_source`, `status`, and the city's published DBH bucket
(`dbh_city_cm_min`/`dbh_city_cm_max`).

**One correction to the roadmap's own summary while it is being checked.** `docs/ROADMAP.md`'s
2026-09-10 amendment says species is answered "though `common_name` is null on real rows". Counted
on the pinned seed rather than sampled: of 198,625 trees, **25,087 carry no `species_current` at
all** and a further **15,361** point at a species row whose `common_name` is null — 40,448 together,
**20.4%**. So the column is populated for four rows in five, and the H1 falls through to the address
for the fifth. Both halves of that matter: the page has a species name to draw far more often than
the roadmap implies, and it must have a title for the one time in five that it does not.

What it does not answer, and what the page therefore does **not** draw:

| §W1 element | Why it is absent |
|---|---|
| `Height` row (`18 m` + `est.` badge) | A measurement. `AppSchema`'s writable database; no public read (Class R). |
| `Trunk · DBH` as a **taped** reading (`64 cm` + `taped` badge) | Same. The page draws the city's published *bucket* instead — see the next entry. |
| Foliage strip (C3 web variant) | Photos. `cypress-photos` is private by design; opening it is a D11 decision with its own round (ROADMAP, "No photos on the public surface in v1"). |
| Photo caption `FOLIAGE · JAN THROUGH DEC · 214 PHOTOS SINCE 2019` | A photo count, and a date range over photos. Both follow the strip. |
| Recent visits panel (three rows) | Visits and their notes. Contributed, Class R. |
| `Sign in` | Owner decision 7 of the web round: the public surface does not sign anybody in. |
| `Open in the app` | A deep link to a universal-link host that does not exist yet (W-E), from a page that cannot tell whether the app is installed. A button that reliably does nothing is worse than no button. |

Each is **omitted**, not stubbed. There is no placeholder height, no greyed-out visit list, and no
`0 photos` — DECISIONS constraint 15 forbids inventing civic and botanical content, and an empty
state drawn where the mock drew data is itself a screen nobody designed (constraint 21).

**Two rows in that table stopped being unanswerable while this branch was in flight, and the branch
did not notice until it merged `main`.** W-G's `GET /api/v1/public/trees/{id}` landed in #163 and
publishes the latest live height and the latest live trunk DBH, each with its method and month, plus
the beloved state. W1 does not call it. The table above is therefore accurate about **this page**
and no longer accurate about **the system**: `Height` and a taped `Trunk · DBH` are available and
unrendered, which is a different fact from unavailable. Chip backlog item 26.

### Four §W1 labels say more than the pack can support, and the page says less

These are deviations from a transcribed mock, so they are written down rather than absorbed.

1. **`Status` is the lifecycle status, not vitality.** §W1 draws `Thriving · vitality 4`. Vitality is
   a rubric over contributed observations (`Cypress/Core/Rubric/Vitality.swift`, writable database).
   The pack carries `trees.status`, whose vocabulary the seed contract closes to five values; the
   page draws that, in the app's own words (`Alive`, `Declining`, `Appears dead`, `Removed?`,
   `Vacant site` — `SegmentedControl`'s labels, parsed at run time rather than transcribed).
2. **`Trunk · DBH` is badged `city record`, not `taped`.** The value is a *bucket* the city
   publishes, rendered by `TreeProfilePresentation.cityDBHRangeText`'s own rule (en dash, no spaces,
   collapsing when the exclusive upper bound is one unit away). D7 and E63 are the reason the badge
   is load-bearing rather than decorative: an unbadged range reads as somebody's tape measure.
3. **`In the city record since 1898` is rendered `Planted 2017`.** The column is `planted_year`
   (DataSF's `PlantDate`). It states when the tree went in, not when the city opened a file on it.
   The mock's label makes a claim the data does not; `Planted` is the label the app already draws
   over this same column.
4. **`City record` drops the city prefix and the cadence.** §W1 draws `SF DPW #114-88 · synced
   weekly`. R28 removed the `SF ` prefix after it named the wrong city on 52,788 San Jose rows, and
   `CityRecordCopy.recordNumber` has written a bare `#‹ref›` ever since. `· synced weekly` is a claim
   about a refresh cadence; the packs carry a `content_rev` and nothing promises a week.

### `Data` cannot say `ODbL · CSV / GeoJSON`, and the real seed proves why in one row

§W1's `Data` value is `ODbL · CSV / GeoJSON`. Measured on the pinned seed: **San Francisco's two
inventories record no license at all**, and San Jose's records `CC-BY`. Neither is ODbL. The page
renders what the receipt states and, where it states nothing, says so — the web round's fourth owner
decision ("state each source's own terms") applied to a row the mock had pre-filled.

**The spelling of the key is the trap, and it is live in the shipped artifact.**
`Tools/publish_cities.py:855` reads `inventory_‹tag›_licence` and falls back to
`inventory_‹tag›_license`. Every pack published so far carries the **British** spelling: the pinned
seed's only license row is `inventory_sj_street_tree_licence` → `CC-BY`. A reader checking the
American key alone would have printed "no license recorded" over San Jose's whole inventory — an
attribution obligation dropped in silence, on the one row that has one. `resolveTreePage` reads both,
in the publisher's own order, and both spellings are covered by a test that builds the keys from
their tails so `src/lib/spelling.ts`'s American-English sweep does not have to be exempted.

### A public tree page has a dark mode that nobody designed

`web/src/styles/tokens.css` pairs each token as `lightOnly` or `dynamic`. §W1's three page-specific
surfaces (`#F5F6EF`, `#FBFBF5`, `#E3E8D9`) resolve to tokens that are **light-only**, while the
generic page background, hairline and body-ink tokens the rest of the page uses **flip** under
`prefers-color-scheme: dark`. The result is a third rendering — half of §W1's palette over a dark
ground — which is a screen state not in the mocks (constraint 21).

Taken conservatively rather than raised as a blocker, and named here so it is not discovered as a
defect: `w1.css` states the gap in its own header, and the page does not opt into a dark scheme.
The real fix belongs in the DesignSystem round that decides whether these three surfaces get dark
counterparts, not in a page.

### An Astro page cannot attach a header to its own 404; an endpoint can

Measured on this tree, not inferred. `src/pages/[idSpace]/tree/[uuid].astro` returning
`new Response(null, { status: 404, headers: { 'x-cypress-refusal': … } })` arrives at the client as a
bare 404: Astro re-materializes a page 404 through its own not-found handling and the custom headers
do not survive. The same Response shape from `src/pages/[idSpace]/tree/[uuid]/og.svg.ts` — an
`APIRoute` — keeps them (`curl -D-` shows `x-cypress-refusal: notFound`).

The consequence, and why it matters more than a header: **the one refusal an operator needs to see is
"there are no packs mounted at all"**, which is a deployment fault and not a missing tree. That case
therefore returns **503** from the page and writes a `console.warn`, so it is distinguishable from a
404 in the service log rather than only in a header the platform discards.

### New York's disclaimer had to follow the data onto the page, and the pack cannot carry it

R36's binding consequence (b) — "any data served or published must carry its source's attribution
obligations (NYC's verbatim disclaimer is the first)" — reaches a public web page the moment that
page serves an NYC tree. R78 ruled the how: ruling 2 puts the text on the surface offering the data
and **is the constraint-21 sign-off** for adding it there, and ruling 3 says the manifest's
machine-readable `attribution` array does **not** discharge it. `web/README.md` already carried the
consequence forward in one line; W-C is the round where a page exists to carry it.

**The pack cannot answer this.** `Tools/publish_cities.py` writes a per-inventory receipt
(`inventory_<tag>_{name,url,snapshot_on,licen[cs]e,id_space}`) and no disclaimer key — confirmed by
listing `seed_meta` on the pinned seed. So the text is a port like the rest of W1's copy:
`web/src/lib/obligations.ts` holds it and `web/test/obligations.test.ts` compares it, character for
character, against `CityDownloadsPresentation.swift` parsed at run time. The iOS suite already
checks that Swift string against `docs/operations/nyc-data-obligations.md`, so the web's copy is two
mechanical hops from the City's own terms with no transcription at either end.

Two details worth recording because both were found by the comparison rather than by reading:

* **The Swift writes the required sentence as a multi-line literal with trailing-backslash line
  continuations.** No parser in `web/test/support/sources.ts` could read that shape, so
  `swiftMultilineStringLet` was added — and both of Swift's rules are traps. The closing delimiter
  sets the indent stripped from every line, and a trailing `\` joins with **no** newline. A parser
  that joined on newlines returns a string that reads correctly and is equal to nothing.
* **The attribution line uses a straight apostrophe.** `Recreation's`, not `Recreation’s`. The web
  copy matches it rather than applying this project's usual typographic apostrophe, because the
  whole value of the constant is that a machine can prove it equal to the app's.

**Verified by rendering, not by reasoning.** A synthetic `us-ny-nyc` pack was built from
`Fixtures/seed/schema.sql`, mounted, and the page fetched: the disclaimer is on the page, under a
`Data disclaimer` micro-label, at the fact column's own body size rather than a footnote size.
