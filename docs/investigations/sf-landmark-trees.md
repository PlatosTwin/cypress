# San Francisco's landmark trees: what is published, and how much of it we already hold

Investigation, 2026-07-31. Written for ticket **#118 part 1** ("great trees"), which RULINGS **R27**
put under DECISIONS constraint 15 — *do not invent civic content; a landmark tree's designation
comes from the city or it is not stated*. R27 assumed "San Francisco publishes a real list." It
does. This note establishes exactly what that list is, where it lives, what it says, and how much
of it can be attached to a row in `Cypress/Resources/cypress-seed.sqlite`.

Nothing here builds, runs a simulator, or edits a `.swift` file. The seed was queried read-only from
a copy. No source was written to.

---

## Verdict up front

**#118 part 1 is an afternoon, but it is an afternoon of editorial transcription, not of ingest.**

San Francisco has **26 designated landmark trees** — twenty-six *designations*, some of which cover
a grove — and the roster is a prose list on a web page, not a dataset. There is a machine-readable
flag (`qLegalStatus = 'Landmark tree'` in the DataSF Street Tree List) and it is already in our seed
on 217 rows, but **the flag is not the register**: it misses four of the twenty-six designations,
flags two trees that are not designated, and cannot tell a permanent designation from a temporary
one. The editorial content a "great trees" screen needs — why the tree matters — exists in exactly
one place, an unlabelled ArcGIS table uploaded by a City staff account, and **fourteen of its
twenty-five rows name a private individual, trust, or LLC as the property owner**, which we may not
ship.

The deciding number is in §3. The short form: **19 of 26 designations (73%) are reachable by a pure
key join with zero fetching; 22 of 26 (85%) if you add a species-plus-coordinate step for three
unflagged ones; 4 of 26 are unreachable and always will be, because they are trees in private
backyards that no street-tree inventory lists.**

---

## 0 · Request counts and caching

Every response is cached under `Fixtures/raw/sf_landmark/`, keyed by `sha1(url)` in `bodies/`, with
`index.tsv` mapping key → source → URL and `requests.log` recording every request that actually
went out. A URL already on disk was never re-requested. One second minimum between requests to the
same host. No bulk download was made from any source; the largest single response is the 3,148-row
significant-tree query, which is the whole of that category and was fetched once.

**Total: 36 requests**, read off `Fixtures/raw/sf_landmark/requests.log`.

| source | requests | | source | requests |
|---|---:|---|---|---:|
| `sf_arcgis` (services.arcgis.com/Zs2aNLFN00jrS4gG) | 11 | | `arcgis_online_item` | 2 |
| `datasf` (data.sfgov.org) | 11 | | `sfpublicworks` | 1 |
| `socrata_catalog` (discovery) | 5 | | `sfenvironment` | 1 |
| `ordinance` (2 × sfenvironment, 1 × amlegal) | 3 | | `arcgis_online_search` (discovery) | 1 |
| `google_mymaps` | 1 | | **TOTAL** | **36** |

One request failed: `codelibrary.amlegal.com` returned **403** to both WebFetch and a scripted
request, with a Cloudflare "Just a moment…" interstitial — the Berkeley signature, a bot check
rather than a paywall. It is recorded here as **unverified**, not as restricted. It did not matter:
the same ordinance text is published by the City itself as a PDF (§4 below), and that is the copy
this note quotes.

---

## 1 · What is published, and under what terms

Four things carry landmark designations. They disagree with each other, and the disagreements are
the substance of this note.

### 1.1 The roster — SF Public Works, "Significant and Landmark Trees"

<https://sfpublicworks.org/services/significant-and-landmark-trees>

A numbered prose list of **26** entries: number, common name, botanical name, address, and — for two
of them — a note that the tree was removed (#10 "removed due to structural failure", #23 "removed
due to tree death"). No coordinates, no dates, no ordinance numbers. HTML, no API, no download.
This is the closest thing to the authoritative roster that is actually published; the *legally*
authoritative record is a book (§4).

**Terms:** none stated on the page. The site carries no data licence. This is a City of San
Francisco public web page describing an act of the Board of Supervisors.

### 1.2 The map — SF Environment, "Landmark Tree Program"

<https://www.sfenvironment.org/landmark-tree-program>

Carries its own list of **25** entries (alphabetical by common name, omitting 4 Montclair Terrace),
plus an embedded **Google My Maps** map titled "San Francisco Landmark Trees — Protected Trees given
Landmark Status by the SF Board of Supervisors", mid `1NK4oc4n35UXpAt19FrJUHAkQaxmvmv9a`. Its KML
export (cached as `sf_landmark_trees_google_mymaps.kml`) holds **25 placemarks** with exactly four
fields each: `Address`, `Latitude`, `Longitude`, `Scientific Name`. No narrative, no dates, no
photographs. It is a strictly poorer copy of §1.3.

**Terms:** the *content* is the City's; the *delivery* is Google's, and Google Maps Platform terms
are a click-through the City accepted, not one we have. Flagged, not assumed: if anyone wants to
redistribute from this endpoint rather than from the City's own ArcGIS org, that needs a decision.
It is not needed — §1.3 has everything this has and more.

### 1.3 The content table — City ArcGIS, "Confirmed Landmark tree data table"

```
https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/Confirmed_Landmark_tree_data_table/FeatureServer/0
```

AGOL item `1d7f24c0623e4762ab020ca86c513257`, owner `jesus.lozano_sfenv` (SF Environment), org
`Zs2aNLFN00jrS4gG` — the same City org that serves `BUF_Street_Trees`, which we already read.
`access: public`, no token. Created 2024-05-16, modified 2024-05-16, **90 views**. Point geometry,
WKID 102100. **25 rows**, `Landmark_order` 1–25 in designation-date order (1996-02-15 → 2022-11-04).

**This is the only source that carries any reason a tree was designated.** Its full field list, and
what is actually in each field, is §5.

A sibling table, `Sullivan_Candidate_Landmark_significant_tree_data_table` (item
`f04cda2b32dd46c9b017e7d5f2cf845a`, same owner), holds 37 rows in layer 0 ("Sullivan candidate
list") and 51 in table 1 ("Review"), with the same schema plus `Date_landmarked__TBD_`. It is a
**nomination candidate list**, not a designation record — almost certainly the Urban Forestry
Council working file behind a nomination round. **It must not be read as designation.** Constraint
15 says a designation comes from the city; a candidate list is the city saying *not yet*.

**Terms:** `serviceDescription`, `description`, `copyrightText`, `licenseInfo`, `accessInformation`
and `tags` are all **empty**. There is no stated licence, no attribution string, and no description
of what the table is. It is publicly shared and unauthenticated, which is what our authorisation
covers, but "publicly shared by a staff account with no metadata" is weaker provenance than
`BUF_Street_Trees` (which at least carries `source: "City and County of San Francisco"` on its
parent item). Recorded as **public, unlicensed, provenance thin**.

### 1.4 The flag — DataSF Street Tree List `tkzw-k3nq`

The list we already ingest. `qLegalStatus` is a 13-value free-text column and two of its values
matter here:

| `qLegalStatus` | rows (live, 2026-07-31) | rows in our seed |
|---|---:|---:|
| `Landmark tree` | **244** | **217** |
| `Significant Tree` | **3,148** | **2,176** |

**Terms — and this is the good news:** `data.sfgov.org/api/views/tkzw-k3nq.json` states
`licenseId: "PDDL"`, `license.name: "Open Data Commons Public Domain Dedication and License"`,
`termsLink: http://opendatacommons.org/licenses/pddl/1.0/`, `attribution: "San Francisco Public
Works"`, `provenance: "official"`. A public-domain dedication, on the source we already use. No
click-through, no login, no no-redistribution term. Nothing was hit that required stopping.

---

## 2 · Landmark and Significant are different in kind, and only one of them is editorial

Answered from the ordinance itself: **Public Works Code Article 16, §810 and §810A**, published by
the City as a PDF and cached at
`Fixtures/raw/sf_landmark/pdf/sf_publicworks_art16_sec810_landmark_trees.pdf`.

**A landmark tree is a legislative act.** §810(b)(4):

> "Upon the recommendation of the Urban Forestry Council, the Board of Supervisors, by ordinance,
> may designate as a 'landmark tree' any tree within the territorial limits of the City and County
> of San Francisco that meets the adopted designation criteria, or may rescind such designations."

Nomination is by the property owner, the Board, the Planning Commission, the Landmarks Preservation
Advisory Board, or a department head (§810(b)(1)); each tree needs its own nomination; the Urban
Forestry Council holds a public hearing and adopts written findings; the Board decides. The criteria
(§810(g)(4)) are age/size/species, visual characteristics, cultural or historic characteristics,
ecological characteristics, and locational characteristics.

**A significant tree is a tape measure.** §810A(a) — a significant tree is a tree (1) on property
under Public Works' jurisdiction *or* (2) on private property with any part of its trunk within 10
feet of the public right-of-way, *and* (3) with DBH over 12 in, *or* height over 20 ft, *or* canopy
over 15 ft. No nomination, no hearing, no ordinance, no roster. A tree becomes significant by
growing. And explicitly:

> "A landmark tree shall not be treated as a significant tree even if the landmark tree meets one or
> more of the abovementioned criteria."

**So: they are distinct categories, they are not nested, and only Landmark is editorial content.**
The 3,148 `Significant Tree` rows say "this tree is large and near a pavement" — 2,176 of them are
already in our seed and they are emphatically **not** great trees. Surfacing them under #118 would
be exactly the invention constraint 15 forbids. They belong to tree *protection*, which is a
different feature.

### 2.1 Both are revocable, and Landmark has a third state

Three lifecycle facts, all from the ordinance, all of which say a boolean column is the wrong shape:

1. **Rescission.** §810(b)(4), quoted above: the Board "may rescind such designations". A landmark
   designation is a state that can end while the tree stands.
2. **Removal.** §810(f) permits removal of a landmark tree only where it "constitutes a hazard tree
   pursuant to Section 802(o)", after public notice and a hearing; on private property, only under a
   special permit issued after a public hearing. Two of the 26 have already gone this way (#10, #23)
   and the City's own roster keeps them listed *with a note*, rather than deleting them. **The
   roster is a register of designations, not a list of standing trees** — which is precisely the
   shape our own `status` vocabulary already has for `removed`, and a reason a "great trees" screen
   should be able to show a tree that is gone.
3. **Temporary designation.** §810(d): a tree is *temporarily* designated the moment a resolution of
   intent is introduced, is subject to all landmark provisions while proceedings are pending, and
   the temporary status **expires after 215 days** unless the Board extends it by up to 90 more; a
   tree whose temporary designation lapsed cannot be re-designated temporarily for two years. The
   Director may also issue an emergency temporary designation to stop an imminent removal.

That third state is not hypothetical in the data. DataSF row `111205` carries the free-text
`permitnotes`:

> `Tree has temporary Landmark Status while nonimation is under consideration. - Chris Buck 4/7/16`

That tree is now designation #21 (46A Cook Street, designated 2016-05-20) — so the flag was carrying
a pending nomination as if it were a designation, and later the same flag meant something else. **A
`qLegalStatus` of `Landmark tree` does not distinguish designated, temporarily designated, or
rescinded.** If #118 ever stores this, the field is an enum with a date, not a flag.

---

## 3 · The deciding number

### 3.1 Method, stated

**This is a key join, not a spatial match.** The landmark flag rides on the DataSF Street Tree List,
whose primary key is `TreeID` — the same id space our seed keys on. RULINGS **R18**: identity is
qualified by id space, `sf`'s `identity_prefix` is the empty string, and
`trees.uuid = uuid5(NS_TREE, "<TreeID>")`. So a DataSF landmark row and a seed row are the same tree
if and only if their `TreeID` is equal, with no tolerance and no geometry involved.

Measured by loading the 244 flagged rows and intersecting `treeid` against
`trees.external_ref` over all 145,837 seed rows.

### 3.2 Row level

| | rows | |
|---|---:|---|
| DataSF rows with `qLegalStatus = 'Landmark tree'` | 244 | live, 2026-07-31 |
| …matched to a seed row by exact `TreeID` | **217** | **88.9%** |
| …not in the seed at all | 27 | 11.1% |

All 217 are `inventory_source = 'city'` rows and **all 217 already carry
`legal_status = 'Landmark tree'` in the shipped seed.** Zero of the 12,260 `datasf` rows are
landmark-flagged. Nothing needs to be fetched at runtime and nothing needs to be re-ingested to know
which seed rows the city calls landmarks: the query is
`SELECT … FROM trees WHERE legal_status = 'Landmark tree'` and it returns 217 rows today.

### 3.3 Why the 27 miss, checked rather than guessed

All 27 were queried against the city's own operational layer,
`BUF_Street_Trees/FeatureServer/3`, with `TREEID IN (…)`. **It returned zero features.** So the miss
is structural, not a seed-build bug: these trees are in DataSF's export and are not in the city's
maintenance layer, which is where 133,577 of our 145,837 rows come from.

Broken down:

| why | rows |
|---|---:|
| No coordinate at all in DataSF (`latitude` null) — the Quesada Avenue median palms, TreeIDs 251108–251116 | 9 |
| On private property (`qSiteInfo` = Back Yard / Front Yard / Side Yard) — outside a *street* tree layer by definition | 12 |
| Curb-side cutout, DPW-maintained, but superseded (see below) | 6 |

Twelve of the 27 turn out to be **legacy ids for trees the seed already holds under a newer id**.
The clearest case is designation #1, "1801 Bush Street: Six Blue Gum Eucalyptus". DataSF flags
**twelve** Blue Gum rows at that corner: `2614`–`2619` (absent from the seed) and
`138024`–`138028`, `138087` (all six present). Six trees, twelve records, two generations of
TreeID. The same pattern holds for `64380`→`231331`, `105444`→`151836`, `111205`→`248932`,
`111749`→`262216`, `111757`→`262217`, `111763`→`262215` — in every case the "missing" row and a
matched row share an address and a species, and the matched row is itself flagged `Landmark tree`.

### 3.4 What a spatial match actually does here, with the tolerance stated

Because the join is a key join, no spatial match is needed for the 217. It was run anyway on the
27 misses, to answer what a fallback would cost. Distance is haversine, in metres, against
`trees.lat/lon`.

| tolerance | misses with ≥1 seed row inside it |
|---|---|
| 5 m | 16 of the 18 that have a coordinate |
| **10 m** | **18 of 18** |
| 15 m | 18 of 18 |
| 25 m | 18 of 18 |

**A 10 m radius keys every one of them and is wrong about most of them.** D6 says street trees are
6–10 m apart; this is that warning, measured:

| landmark (DataSF) | nearest seed row within 10 m | distance |
|---|---|---:|
| `262274` Coast Redwood, 4 Montclair Ter (designation #26) | `133116` **Pittosporum undulatum**, 1070 Lombard St | 6.6 m |
| `262100` Giant Sequoia, 3066 Market St (#20) | `25174` **Ulmus parvifolia**, 3062 Market St | 4.7 m |
| `264739` + `264741` Canary Island Date Palms, 2040 Sutter | `138361` **Ficus retusa nitida**, 2060 Sutter — *the same row for both* | 1.9 m |
| `2614`–`2618` Blue Gums, 1661X Octavia | `138024` — *one row for five landmarks* | 3.3 m |

A radius alone gives you a cheesewood for a coast redwood and a Chinese elm for a giant sequoia, and
collapses a six-tree grove onto one pin. Constraining to an exact scientific-name match fixes the
species error and immediately exposes the other one: at 10 m + same species, 12 of the 27 "match" —
and every one of those 12 lands on a seed row **that an exact key join has already claimed for a
different landmark record**. There is no tolerance at which a spatial fallback adds a tree. It only
adds duplicates.

**Recommendation: do not implement a spatial fallback for this feature.** The 27 are not a matching
problem. Twelve are duplicate ids for trees we already have, nine have no coordinate anywhere in
the source, and six are private-property trees that the street-tree inventory has never listed.

### 3.5 Designation level — the number that actually decides #118

A "great trees" screen lists designations, not inventory rows. 244 rows is mostly one designation:
**184 of the 244 are the Canary Island Date Palms of the Dolores Street median** (designation #6,
"Dolores Street Center Island: All Canary Island Date Palms"), and all 184 are in our seed. So the
honest denominator is **26**.

Crosswalking the SFPW roster to the flag and to the seed, by address and species:

| | designations | of 26 |
|---|---:|---:|
| Reachable by the key join on `legal_status = 'Landmark tree'` alone | **19** | **73%** |
| Present on the roster but never flagged in DataSF, yet findable in the seed by species + address | 3 | 12% |
| **Reachable at all** | **22** | **85%** |
| **Not in the seed under any method** | **4** | **15%** |

The three that the flag misses but the seed holds anyway, each verified by hand:

- **#8** Cliff Date Palms (*Phoenix rupicola*), Dolores median → seed `25023`, flagged `DPW Maintained`
- **#9** Guadalupe Palm grove (*Brahea edulis*), 1608 Dolores → seed `25132`/`25133`, flagged `DPW Maintained`
- **#23** California Buckeye, 2694 McAllister (removed 2022) → seed `255909`, flagged `Significant Tree`

The four, hand-checked against the seed at the City's own published coordinates within 40 m:

| # | designation | nearest thing in our seed |
|---|---|---|
| 20 | Giant Sequoia, behind 3066 Market St | `25174` Chinese elm at 4.3 m — a street tree on the other side of a building |
| 22 | Canary Island Pine, 2251 Filbert St (backyard) | `58803` water gum at 8.3 m; **no record at that address exists in DataSF at all** |
| 25 | Coast Redwood, 313 Scott St (backyard) | `247397` camphor at 34.6 m |
| 26 | Coast Redwood, 4 Montclair Terrace (backyard) | `133116` cheesewood at 6.6 m |

All four are trees in private back gardens. They are not in the seed because they are not street
trees, and no amount of ingest will put them there. **For #118 they are content without a pin** —
which is fine, and is a design question, not a data question: SF Environment's own page says *"many
trees are in private backyards and are not available for public viewing."*

### 3.6 The flag is not the register — in both directions

Under-counts: designations **#8, #9, #22, #23** carry no `Landmark tree` flag in DataSF. Three of
them are in the seed under a different `qLegalStatus` and one is absent entirely. So a pipeline that
trusts the flag silently loses four of twenty-six designations, including two whole groves on
Dolores Street.

Over-counts: two Quesada Avenue trees are flagged `Landmark tree` and are **not** the designated
species — `Acacia melanoxylon` and `Prunus domestica 'Mariposa'` — where designation #7 covers "13
Canary Island Date Palms". Two more rows at `2040 Sutter St` are flagged and correspond to no roster
entry. And the flag carried at least one *temporary* designation as though it were permanent (§2.1).

This is the finding that matters most for constraint 15: **`qLegalStatus` is an operational
attribute in a maintenance inventory, not the Board of Supervisors' designation register.** For
#118, the roster of 26 is the source of truth and the flag is a convenience for finding the pins.

---

## 4 · What the legally authoritative register actually is

§810(c):

> "Upon Board of Supervisors designation of a landmark tree, the Department or affected agency shall
> record a notice on the subject property concerning the landmark tree. The Department also shall
> record the landmark tree designation in an official book entitled Landmark Trees. … The Department
> shall maintain this book for public review and update it on a regular basis with the assistance of
> affected agencies."

**The register is a book, held for public review at Public Works.** It is not published as data, and
nothing found in this investigation is it. Every source in §1 is a rendering of it, and the three
renderings disagree: SFPW says 26, SF Environment says 25, the ArcGIS table says 25, and the three
sets are not the same 25 — SFPW and SF Environment both omit something the other has. The union is
26 and every entry in it appears in at least two of the three.

**Could not be determined:** the ordinance file number and Board file number for each designation.
Every designation is an ordinance with a Clerk of the Board file number (the enabling resolution's
own number, 440-06 / File No. 060487, is quoted in §810(a), so the numbers exist and are public).
None of the four published sources carries them. Retrieving them means twenty-six Legistar lookups,
which is a bounded piece of work but was outside this pass. If #118 wants to cite the ordinance that
made a tree a landmark — which is the strongest possible answer to constraint 15 — that is the
follow-on task.

---

## 5 · What content exists beyond the flag

The `Confirmed_Landmark_tree_data_table` layer, all 25 rows read. Populated counts are exact.

| field | type | what is in it |
|---|---|---|
| `Landmark_order` | string | 1–25, designation order. Not a TreeID and not the roster's numbering. |
| `Common_Name`, `Scientific_Name` | string | Populated 25/25. Casing inconsistent (`phoenix canariensis`). **Row 19 has the address and the scientific name swapped.** |
| `Quantity` | integer | Trees covered by the designation. Sums to 53 — but says `1` for the Dolores median palms, which DataSF flags 184 of. Not trustworthy. |
| `Latitude`, `Longitude` | double | Populated 25/25, and they are good — every one landed within metres of the expected block. |
| `Address` | string | Populated, informal ("3rd Street and Yosemite"). **Row 5 reads `"Private"`** where the roster says Quesada Street median. |
| `Zipcode` | integer | Populated. |
| `Local_Native__Native__or_Non_native_to_CA` | string | Populated. Genuinely useful and not in any other source. |
| `Age` | string | **17 of 25 are `"N/S"` (not stated)**, one is null. Real values: `120`, `>100`, `> 100`, `> 130`, `> 90`, `> 80`. Free text, not a number. |
| `Historical_Signifigance` *(sic)* | string | **13 of 25 are `"N/S"`.** The other 12 are the best writing in any of these sources: *"Genetic remnant of original SF forest"* (×4), *"Historic palm plantings"* (×3), *"Rare (thought to be extinct) species of Manzanita studied by experts. Former site of Laurel Hill Cemetary"*, *"Predated 1906 fire, genetic remnant of original SF forest"*, *"Original plantings in Richmond district development, some of oldest trees in Western San Francisco"*. |
| `Ecosystem_Value` | string | Populated on most; short controlled-ish phrases — `Windbreak`, `Fruit food source`, `Pollinator attractive`, `Indigenous species habitat, prevents erosion, acts as sound barrier`. |
| `Date_landmarked` | string | The designation date, 25/25 — 1996-02-15 through 2022-11-04. **Free text, `MM/DD/YY`, and two rows are just `"07"`.** |
| `Property_Type_and_Owner__as_of_2023_` | string | Populated 25/25. **See the warning below.** |
| `Managed_by` | string | `Private` 15, `DPW` 8, `DPW / Quesada Garden Initiative` 1, `Private - FUF` 1. |
| `Dead_or_Alive__` | string | **Null on all 25.** |
| `Health_Rating` | string | **Null on all 25.** |
| `Date_last_checked` | string | **Null on all 25.** |

**There is no photograph field, no ordinance or case number, and no nomination narrative** — the
ordinance requires nominations to include "one or more pictures of the tree" (§810(b)(2)), so the
photographs exist in the Council's files; none of them is published in any source found here.

So the answer to "is it a bare flag?" is: **not bare, but thin and half-empty.** A screen can honestly
show, per designation: common and botanical name, address, coordinate, designation date, native
status, an ecosystem-value phrase, and — for **12 of 26** — one sentence about why it is historically
significant. For the other 14 the honest text is the designation date and nothing else, and under
constraint 15 that is what it must say.

### 5.1 Do not ship the owner column

Fourteen of the twenty-five rows name a private party:

> `Private - Cronander Revocable Trust James and Victoria Cronander`
> `Private - backyard of Robert and Susan Call`
> `Private - backyard of Melissa and Benjamin Kremers`
> `Private - Douglas J Durkin Living Trust`

D11 (privacy hardening) and R27's own reasoning apply directly. A screen that pins a tree to a
backyard and names the couple who live there is worse than a leaderboard. The usable part of that
column is its first token — `Public` / `Private` / `Private business` — which is what "not available
for public viewing" needs. **The names must be dropped at ingest, not at render.**

### 5.2 Two species our seed gets wrong

Both would be visible on a great-trees screen today, and both are constraint-15 failures:

| designation | roster + ArcGIS say | our seed says (from DataSF) |
|---|---|---|
| #17, 115 Parker Ave | Howell's Manzanita, *Arctostaphylos hispidula* — *"Rare (thought to be extinct) species … studied by experts"* | `253858` → *Arctostaphylos manzanita 'Dr Hurd'*, "Dr. Hurd Manzanita" — **a garden cultivar** |
| #3, 1701 Franklin St | Flaxleaf Paperbark, *Melaleuca linariifolia* | `7946` → *Melaleuca ericifolia*, "Heath Melaleuca" |

The first is not a spelling difference. The whole reason that tree is a landmark is that it is a
rare species thought extinct; our seed calls it a nursery cultivar. Written up as **ERRATA E178**,
alongside **E179** (the `Landmark tree` flag is not the register, in either direction) and **E180**
(`legal_status` reaches `city` rows from the other inventory).

---

## 6 · What this means for #118 part 1

**Shape of the work, in order:**

1. **Transcribe the roster of 26 by hand into curated content in the repo**, the way the species
   field guide (#6) is curated, with the ArcGIS table's designation date, native status, ecosystem
   value and historical-significance sentence carried across and the owner names dropped. Twenty-six
   entries. This is the afternoon.
2. **Key each entry to seed rows by `TreeID`**, taking the flag as a hint and the roster as truth —
   19 designations join directly, 3 need the species-plus-address step done once by hand and then
   written down as ids, and 4 have no pin. Store the resolved `TreeID` list per designation, because
   a designation is one-to-many (six Blue Gums, 184 Dolores palms) and the join is not stable enough
   to re-derive at runtime.
3. **Decide what a pinless landmark looks like** — four backyard trees the reader cannot go and see.
   That is a screen question for whoever owns #118, and **R27.1** sharpens it rather than softening
   it: the owner's stated purpose is that *"the app exists to bring people TO trees"*. Four of the
   twenty-six are trees nobody can walk to, and one of them (#22, 2251 Filbert) has no record in any
   inventory we hold. They are still landmarks and the city still lists them; showing them next to
   twenty-two you can visit, with no distinction, would be the surface answering the wrong question.
   R27.1 changed nothing about part 1 — the landmark half is editorial and constraint 15 still
   governs it — but its reason for existing applies here too.
4. **Do not model the designation as a boolean.** §810 gives it at least four states — temporary
   (215-day clock), designated, rescinded, and designated-but-removed — and the City's own roster
   already carries two removed trees rather than deleting them.

**What must not happen:** treating `qLegalStatus = 'Significant Tree'` as any part of this. It is
3,148 rows of "over twelve inches and near a pavement", it is a different section of the code, and
§810A says in terms that a landmark tree is not one of them.

**Why it is an afternoon and not a project:** the deciding number came out high (73% by pure key
join, 85% with one hand step), the licence on the source we already use is a public-domain
dedication, the whole corpus is 26 items, and 217 rows in the shipped seed are already flagged. The
part that is *not* an afternoon is the part nobody asked for: chasing the 26 ordinance file numbers,
and getting photographs, which are not published anywhere found here.

---

## 7 · Stated plainly: what could not be determined

- **The ordinance / Clerk of the Board file number per designation.** They exist and are public;
  none of the four published sources carries them. Twenty-six Legistar lookups away.
- **Whether the SFPW roster of 26 is current.** It is the largest of the three renderings and the
  only one with 4 Montclair Terrace, but no source found carries a "last updated" stamp, and the
  ArcGIS table has not been touched since 2024-05-16. There may be a 27th designation nobody has
  published.
- **What the two rows at `2040 Sutter St` flagged `Landmark tree` are.** They match no roster entry.
  Rescinded? Mis-keyed? Unresolved.
- **Whether any designation has ever actually been rescinded.** §810(b)(4) permits it; no evidence
  was found either way, and the two removals on the roster are tree deaths, not rescissions.
- **`codelibrary.amlegal.com` terms.** 403 with a Cloudflare interstitial to every scripted request.
  Recorded **unverified**. Not needed — the City publishes the same text itself.
- **Whether the Urban Forestry Council's nomination photographs are obtainable.** §810(b)(2) requires
  them in every nomination. None is published in any source found here.
