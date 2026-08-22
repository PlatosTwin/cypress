# Species content sources, provenance and licence analysis

This file backs `Fixtures/species/curated.yaml` and `Fixtures/species/leaf_retention.yaml`.
It is also the answer to PRODUCT.md open question 3, "how much can be licensed/sourced openly
versus authored".

The rule these files were built under is BUILD-PLAN §15 and DECISIONS constraint 15: **do not
invent botanical content**. Every botanical value in the two YAML files carries a citation to a
source that was actually fetched during authoring, naming the field or quote the value came from.
Where no source could be found, the value is `null` or an empty array. Nothing was written from
recall and no citation was constructed to justify a value that had already been written.

Everything below was fetched on **2026-07-21**.

---

## 1. Summary: what can be shipped and under what terms

| Source | What we took | Licence position | Ships? |
|---|---|---|---|
| GBIF Backbone Taxonomy | `family` for 569 of 577 species, plus 481 of the 503 in `nyc_species.yaml` | CC BY 4.0, explicit | **Yes**, with attribution |
| Cal Poly SelecTree (UFEI) | `leaf_retention` for 480 species directly plus 19 by genus uniformity, plus 374 of the 503 in `nyc_species.yaml`; morphology facts behind `id_tips` | **No published reuse licence.** Facts are uncopyrightable; the prose and photos are not | **Yes for the scalar facts**, no prose or images. Written permission recommended before launch |
| NC State Extension Plant Toolbox | `leaf_retention` for 12 species; morphology facts behind `id_tips` for 18 of the top 40 | © NC State University, no open licence found | **Yes for the facts**, no verbatim prose. Permission recommended |
| SF Public Works 2024 Recommended Street Tree List | all `care_notes` | City and County of San Francisco publication | **Yes.** Short factual quotations, attributed |
| Friends of the Urban Forest Tree Care FAQ | watering guidance (cited, currently unused in the shipped rows) | No published reuse licence | Attribute; ask before quoting at length |
| iNaturalist observation annotations | `bloom_months`, `fruit_months`, `fall_color_months` | Underlying observations default to **CC BY-NC**. See §7, this is the one real risk | **Conditionally.** See the flag below |
| DataSF Street Tree List | the species strings and frequencies themselves | Public open data, already the seed | Yes |
| NYC Parks Forestry Tree Points | the species strings and frequencies behind `nyc_species.yaml`, and the common names it carries | Public open data (NYC Data Mine terms; notify + disclaimer) | Yes |
| USA National Phenology Network | nothing. Evaluated and rejected | n/a | n/a |

**The one licence flag that matters.** iNaturalist's default content licence is CC BY-NC, and
Cypress has a paid tier (D14). What we took from iNaturalist is a set of month-of-year counts,
which are facts about a dataset rather than the copyrighted observations, and the derived value in
the YAML is an array of integers. That is a defensible position under US law (facts and
non-creative compilations are not protected, *Feist*), but it is a position, not a permission. The
twenty non-empty seasonal arrays would be worth re-deriving from a permissively licensed
source before the paid tier ships, or clearing with iNaturalist directly. Nothing else in these two
files depends on an NC-licensed source. If iNaturalist has to be dropped entirely, the cost is
**eleven species lose bloom months, eight lose fruit months, and Ginkgo loses the only
`fall_color_months` in the repo**; no `leaf_retention`, `family`, `id_tips` or `care_notes` value
is affected.

---

## 2. Cal Poly SelecTree — the primary source for `leaf_retention`

- Publisher: Urban Forest Ecosystems Institute, California Polytechnic State University.
- Human page: `https://selectree.calpoly.edu/tree-detail/<id>`
- JSON used: `https://selectree.calpoly.edu/api/tree/detail/<id>` (undocumented but public; it
  is what the site's own front end calls). The index at
  `https://selectree.calpoly.edu/api/tree/search-by-name?name=…` returns the full catalogue of
  2,095 records regardless of the `name` parameter, which is how the catalogue was enumerated.
- Fields taken: `foliage_type`, `foliage_fall_color`, `family`, and, for `id_tips`,
  `leaf_arrangement`, `leaf_form`, `leaflet_shape`, `foliage_growth_color`, `bark_color`,
  `bark_texture`, `tree_shape`, `flower_color`, `flower_showiness`, `flower_time`, `fruit_type`,
  `fruit_color`, `fruit_size`, `fruiting_time`, `litter_type`, `fragrance`, `health_hazard`,
  `disease_susceptibility`, `height_high`, `width_high`.
- Vocabulary mapping: `Evergreen → evergreen`, `Deciduous → deciduous`,
  `Partly Deciduous → semi_deciduous`. Those are the only three values the field takes.

### Licence

No terms-of-use, copyright or data-reuse statement could be found. `https://selectree.calpoly.edu/`
serves a JavaScript shell with no footer text; `https://ufei.calpoly.edu/terms-of-use` is a 404;
a targeted web search for SelecTree/UFEI reuse terms returned only Cal Poly's general library
copyright guides, which are not about this dataset. **Position:** the individual attributes we take
(a species is evergreen; its family is Myrtaceae) are facts and are not copyrightable. The site's
descriptive prose and its photographs are, and **neither is used here**. Before launch, send UFEI a
short note describing the use and asking for written confirmation; it is a state university
institute and the request is routine. Attribution string in use:
`Cal Poly SelecTree (Urban Forest Ecosystems Institute)`.

### Two things about SelecTree that a later maintainer needs to know

**1. The `memo` field is not usable.** It reads as machine-generated marketing prose and is wrong.
The memo on `tree/detail/1` (*Abies amabilis*, a fir) describes "elongated, oval leaves that provide
ample shade" and "small, creamy yellow flowers". A fir has needles and cones. This field was
checked, found unreliable, and **excluded from the pipeline entirely**. Do not reintroduce it.

**2. Thirty-five records are internally self-contradictory.** They carry
`foliage_type = "Evergreen"` together with `foliage_fall_color = 1`. Sixteen of those are species in
the SF inventory, together 7,372 street trees, and the largest is *Prunus cerasifera* at rank 6 with
6,670 trees, which is unambiguously deciduous. Taking SelecTree at face value here would have
written "evergreen" onto the sixth most common street tree in San Francisco and, under D5,
permanently suppressed its fall-colour chip. The pipeline therefore **quarantines any record with
that combination**, falls back to NC State where a page exists, and leaves `leaf_retention` null
where one does not. Every affected row carries the reason in its `notes`. This check should stay in
place if the table is ever rebuilt.

---

## 3. NC State Extension Gardener Plant Toolbox — second source and tie-breaker

- `https://plants.ces.ncsu.edu/plants/<genus-species>/`
- Field taken for `leaf_retention`: `Whole Plant Traits > Leaf Characteristics`, mapping
  `Deciduous → deciduous`, `Broadleaf Evergreen → evergreen`, `Needled Evergreen → evergreen`.
  Rows whose value combines both (`"Broadleaf Evergreen Deciduous"`) were treated as unusable.
- Fields taken for `id_tips`: `Leaf Description`, `Bark Description`, `Flower Description`,
  `Fruit Description`, `Stem Description`.
- Coverage: 123 of the top 260 SF species have a page. The Australian and New Zealand species that
  dominate SF's street inventory (*Lophostemon*, *Tristaniopsis*, *Metrosideros*, *Melaleuca*,
  *Corymbia*, *Pittosporum*, *Myoporum*, *Lagunaria*, *Eriobotrya deflexa*, *Pinus radiata*) are
  mostly absent, which is why it is a second source and not the primary one.
- Role in the table: **primary** for 12 species where SelecTree was self-contradictory,
  **corroborating** for 108 species where both sources agree. **There were zero conflicts** between
  the two sources on any species where SelecTree's own record was internally consistent.

### Licence

Content is © NC State University. No open licence statement was located
(`https://plants.ces.ncsu.edu/about/` returns 404). Cooperative Extension material is generally
published for educational reuse with attribution, but that is not a licence. Same position as
SelecTree: **facts only, no verbatim prose, and ask before launch.** One heuristic in the scraper
was found unreliable and dropped: a page mentioning the phrase "Fall Color" anywhere is not evidence
that the species colours, because the phrase appears in site navigation. Nothing in the shipped
files depends on it.

---

## 4. GBIF Backbone Taxonomy — `family`

- `https://api.gbif.org/v1/species/match?kingdom=Plantae&name=…`
- Licence: **CC BY 4.0**, stated explicitly at
  `https://api.gbif.org/v1/dataset/d7dddbf4-2cf0-4f39-9b2a-bb099caae36c`. This is the cleanest
  source in the set.
- Citation required by the licence:
  > GBIF Secretariat (2023). GBIF Backbone Taxonomy. Checklist dataset
  > https://doi.org/10.15468/39omei accessed via GBIF.org on 2026-07-21.
- Gotcha found and worked around: a bare genus name returns
  `{"matchType":"NONE","note":"Multiple equal matches for Pinus"}` unless `kingdom=Plantae` is
  supplied. Every call in the pipeline sends it.
- Eight species have no family: six placeholder strings that are not taxa (`Shrub`,
  `:: To Be Determine`, `Private shrub`, `Palm (unknown Genus)`, `Privet`, `Ficus laurel`) and two
  DataSF strings GBIF could not resolve (`patanus racemosa ::`, `:: Brisbane Box`).

---

## 5. San Francisco Public Works — `care_notes`

- *2024 Recommended Street Tree Species List*, approved by the Urban Forestry Council on
  27 August 2024, produced with SF Public Works Urban Forestry and Friends of the Urban Forest.
- `https://sfpublicworks.org/sites/default/files/BUF/Street%20Tree%20Planting/AUGUST%202024%20Recommended%20Street%20Tree%20List%20Update.pdf`
- Every `care_note` in `curated.yaml` comes from this document's Notes, Minimum Sidewalk Width or
  Allergy Friendly columns, with the source line quoted in the citation. Twenty of the top 40 have
  one; the other twenty have none, because the document says nothing about them.
- It is also the citable authority for several nomenclature equivalences the pipeline relied on:
  "Formerly Tristania conferta", "Formerly known as Tristania laurina",
  "Podocarpus gracilior/Afrocarpus falcatus", "Eucalyptus conferruminata/E. lehmanni",
  "Corymbia maculata/Eucalyptus m.".
- Licence: a City and County of San Francisco publication. Short factual quotations with
  attribution are safe. It is not marked with an open licence, so do not republish the table
  wholesale.

### Rejected: the PDF's bold-means-evergreen convention

The list's species column is headed "Species (bolded trees are evergreen)", which looked like a
free, SF-specific leaf-retention source. The bold runs are recoverable from the PDF font
information, and they were extracted. **They are wrong often enough to be unusable.** *Jacaranda
mimosifolia* and *Quercus phellos* are bolded as evergreen and are not; *Cassia leptophylla* is not
bolded although the same row's note says "Semi-evergreen"; and the entire palm section on page 8 is
unbolded even though palms are evergreen. This source was fetched, tested against the others,
and **rejected for `leaf_retention`**. It is used only for `care_notes` and for the nomenclature
equivalences above.

---

## 6. Friends of the Urban Forest — watering guidance

- `https://www.friendsoftheurbanforest.org/faq-treecare`
- Quoted: "The standard recommendation for young trees is to water 15-20 gal per week, which would
  mean filling a water bag once per week until it's about 3 years old." and "After trees are in the
  ground for 3 years, weekly watering is generally no longer needed."
- This is genuine, SF-specific and citable, but it is **not species-specific**, so it appears in the
  pipeline as an available citation rather than as a repeated note on all 40 species. It belongs on
  a general care screen, not in `species.care_notes`.
- Licence: no reuse statement published. Attribute; ask before quoting at length.
- Note: `https://www.fuf.net/` does not resolve. The live domain is
  `friendsoftheurbanforest.org`.

---

## 7. iNaturalist — the seasonal month arrays

- `https://api.inaturalist.org/v1/observations/histogram?taxon_id=…&place_id=…&interval=month_of_year&term_id=…&term_value_id=…`
- Annotations used: Flowers and Fruits = Flowers (12/13) for `bloom_months`, Flowers and Fruits =
  Fruits or Seeds (12/14) for `fruit_months`, Leaves = Colored Leaves (36/39) for
  `fall_color_months`, Leaves = Breaking Leaf Buds (36/37) for `new_growth_months`.
- Places: San Francisco County (`place_id=854`) preferred; California (`place_id=14`) used when
  the SF sample was too small. The place actually used is recorded in every citation.

### The derivation rule, stated so it can be checked

1. Require at least 50 annotated observations (60 for `fall_color_months`) in the chosen place.
2. Take the **smallest run of consecutive months, wrapping the year boundary, that holds at least
   70 percent of those observations**.
3. Emit it only if that run is eight months or shorter. A longer run means the annotation does not
   discriminate a season, and the field is left empty.

Every citation records the taxon, the place, the observation count and the full twelve monthly
counts, so the arrays can be recomputed or disputed without refetching.

### Two API traps that were hit

- **`verifiable=true` silently zeroes the result** when combined with `term_id`. The first full run
  of the pipeline included it and produced all-zero histograms for taxa that plainly have data
  (*Ginkgo biloba* coloured leaves in California: 0 with the parameter, 408 without). Do not send it.
- **`taxa?q=` name search returns confident wrong answers.** `Ficus nitida` resolves to
  *Ficus benjamina* and `Pyrus kawakamii` to *Pyrus calleryana* var. *calleryana*. Both were caught
  by reading the resolved names and overridden by hand; the overrides are recorded in the citations.

### What this source did and did not give us

Coverage is thin. Of the top 40 species, eleven got `bloom_months`, eight got `fruit_months`, one
got `fall_color_months`, and none got `new_growth_months`. The Breaking Leaf Buds annotation is
essentially unused in California, so `new_growth_months` is empty for all 40 and that is not
recoverable from this source.

One result is worth recording because it contradicts a plausible assumption. *Metrosideros excelsa*
is the New Zealand Christmas tree and flowers in December in New Zealand; the San Francisco County
histogram (n=102) puts its flowering in months 3 to 7. The northern-hemisphere shift is real and the
data is right. This is the reason the arrays are taken from observations rather than from
descriptions written for the plant's native range.

### Licence

iNaturalist's terms license user-contributed content as **CC BY-NC by default** unless the
contributor chose otherwise, and the terms separately prohibit using iNaturalist data to train
commercial AI models. We are not training anything. We are reading aggregate counts through the
public API and storing derived integers. See §1 for the position and the recommended action.
Attribution string in use: `iNaturalist observation annotations, month-of-year histogram`.

---

## 8. USA National Phenology Network — fetched, evaluated, rejected

- `https://services.usanpn.org/npn_portal/species/getSpecies.json` (1,940 species, works)
- `https://services.usanpn.org/npn_portal/observations/getSummarizedData.json?…` (works)

This looked like the ideal source for `fall_color_months`: an observation network with an explicit
"Colored leaves" phenophase. **The sample is far too small.** For *Ginkgo biloba*, one of the
best-monitored species in the network, all of California across 2010 to 2025 yields **eight**
"Colored leaves" records across five sites, spread over months 5, 9 and 11. That is noise. The
Australasian species that make up most of SF's street trees are not in the network at all. Fetched,
measured, discarded. Recorded here so nobody spends the afternoon on it again.

---

## 9. Sources checked and found unusable

| Source | What happened |
|---|---|
| USDA PLANTS API | `https://plants.usda.gov/api/plants/search?…` and `/api/PlantCharacteristics/<id>` both return an IIS **404** page. Whatever the current API surface is, it is not at the documented paths |
| Kew Plants of the World Online API | `https://powo.science.kew.org/api/2/search?q=…` returns **403** |
| Wikidata SPARQL | not needed once GBIF resolved 569 of 577 families under an explicit CC BY licence. Untested here |
| Wikipedia REST summaries | tried as a last resort for *Syzygium paniculatum*. The summary describes the tree in detail but never states whether it is evergreen, so it was **not** used. The field stayed null |
| SF PDF bold-means-evergreen | see §5 |
| SelecTree `memo` field | see §2 |
| `https://www.fuf.net/` | does not resolve |

---

## 10. How DataSF strings were matched to source records

The DataSF `qSpecies` strings are messy: trade names, misspellings, superseded genera, cultivars,
and genus-only entries. Matching was done in this order, and the method used is recorded in every
`leaf_retention` citation so any single row can be audited.

| Method | Species matched |
|---|---|
| `selectree_name_exact` | 332 |
| `selectree_name_exact_species_level` (DataSF names a cultivar, matched the species) | 52 |
| `selectree_synonym_other_taxa` (SelecTree's own `other_taxa` synonym list) | 50 |
| `gbif_backbone_species_key` (both names resolve to the same GBIF species) | 21 |
| `selectree_primary_taxon` | 8 |
| `selectree_synonym_other_taxa_species_level` | 5 |
| `fuzzy_name_edit_distance_1` | 5 |
| `fuzzy_name_edit_distance_2` | 4 |
| `token_subset_of_"…"` | 3 |

Fuzzy matching runs only when everything else has failed, only for a single unambiguous candidate,
and only up to two character edits. All nine fuzzy matches were inspected by hand: `Podocarpus
gracilor` → *Podocarpus gracilior*, `patanus racemosa ::` → *Platanus racemosa*, `Eucalyptus
lehmanni` → *Eucalyptus lehmannii*, `Casurina stricta` → *Casuarina stricta*, `Ilex altaclarensis
'Wilsonii'` → *Ilex × altaclerensis 'Wilsonii'*, `Carya illinoensis` → *Carya illinoinensis*, and
three quoting variants of cultivar names.

**Genus-only DataSF strings** (`Eucalyptus Spp`, `Pinus Spp`, `Betula spp`, …) get a
`leaf_retention` only when **every** SelecTree record in that genus agrees and there are at least
three of them. Nineteen species qualified. Genera whose members disagree (*Ulmus*, *Pyrus*,
*Ficus*, *Ilex*, *Acer*, *Quercus*, *Prunus*, *Fraxinus*, *Magnolia*, *Salix*) are left null rather
than guessed.

### Two DataSF data-quality problems this surfaced

1. **`patanus racemosa ::`** (188 trees, rank 113) is a misspelling of *Platanus racemosa*, and
   `Fixtures/sf_species_map.csv` maps it to a **different** species id from the correctly spelled
   `Platanus racemosa` (84 trees, rank 181). The inventory therefore holds one species as two.
   Fixing that belongs in the species map, not here.
2. **`Shrub`, `Private shrub`, `Privet`, `Palm (unknown Genus)`, `:: To Be Determine`,
   `Ficus laurel`** are mapped to species ids in `sf_species_map.csv` even though they are not taxa.
   They will render as species with a name and nothing else. They should probably map to null and
   become `vacant_site` or an unknown-species stub instead.

---

## 11. What is missing, stated plainly

- **`new_growth_months` is empty for all 40 curated species.** No source consulted gives leaf-out
  timing for these species in this climate. The iNaturalist Breaking Leaf Buds annotation is
  effectively unused in California.
- **`fall_color_months` is populated for exactly one species**, *Ginkgo biloba* (November and
  December, from 408 California records). Every other deciduous species in the top 40 has an empty
  array, not because it lacks autumn colour but because **no source gives the months**. SelecTree
  records *that* a species colours (`foliage_fall_color`) but never *when*. The autumn strip and the
  fall-colour chip will be almost entirely dataless until this is solved. Options: commission the
  data, derive it from Cypress's own `phenology_tag = fall_color` photos once there are enough
  (which is the honest long-term answer and fits A5's "strip fills over time"), or find a
  California-specific phenology dataset that does not exist as far as this search could tell.
- **`bloom_months` is populated for 12 of 40**, `fruit_months` for 7 of 40.
- **66 of 577 species have a null `leaf_retention`**, together 1,880 trees, 0.95% of the inventory:
  38 with no source found, 12 genus-only strings whose genus is not uniform, 10 where SelecTree
  contradicted itself and no second source exists, 6 that are not taxa at all. The largest single
  gap is *Syzygium paniculatum* (493 trees, rank 64), which is in neither SelecTree nor NC State.
- **No reference photos.** BUILD-PLAN §8 also asks for "licensed or commissioned reference photos
  used as profile fallback heroes". None are included. SelecTree's images are credited to named
  photographers and carry no reuse licence, and iNaturalist's photo licences vary per observation.
  This needs a licensing decision and probably a budget, not a scraper.
- **The Swift model requires a value.** `Species.leafRetention` in
  `Cypress/Core/Models/Species.swift` is non-optional `LeafRetention`, but the database column and
  these files both allow null. The migration that loads this content has to decide what a null
  becomes. That decision was not made here.

---

## 12. Reproducing this

The fetch and join were done in a throwaway session directory, not checked in. To rebuild from
scratch you need: the SelecTree catalogue and 2,092 detail records, GBIF matches for both the 577
DataSF names and the 2,095 SelecTree names, NC State pages for the top 260 names, the SF Public
Works PDF, and roughly 312 iNaturalist histogram calls. Everything a rebuild needs to be checked
against is already in the YAML: each citation carries the exact URL, the field name, the matched
taxon, and for iNaturalist the raw monthly counts.

`Tools/validate_species.py` re-checks D5, the month ranges, the citation requirement and the join
to the seed database on every run.
