# Pending errata — landmark trees (unnumbered; from `docs/investigations/sf-landmark-trees.md`)

Raised 2026-07-31 by the #118 part 1 research pass. Written here rather than into `docs/ERRATA.md`
so the numbering stays the owner's. Three entries; the first is the one that matters.

---

## E?? — the seed calls a landmark tree by the wrong species, and in one case by a cultivar

Two of San Francisco's 26 landmark trees carry a species in `cypress-seed.sqlite` that contradicts
the City's own landmark roster. Both would be rendered on any "great trees" surface built for #118,
and both are DECISIONS constraint 15 failures — botanical content the app would be asserting that
the city does not assert.

| landmark | SFPW roster and the City's ArcGIS landmark table | our seed |
|---|---|---|
| #17, 115 Parker Ave (designated 2005-09-03) | Howell's Manzanita, *Arctostaphylos hispidula* | `external_ref` **253858** → *Arctostaphylos manzanita 'Dr Hurd'*, common name "Dr. Hurd Manzanita" |
| #3, 1701 Franklin St (designated 1996-02-15) | Flaxleaf Paperbark, *Melaleuca linariifolia* | `external_ref` **7946** → *Melaleuca ericifolia*, common name "Heath Melaleuca" |

The first is not a synonym or a spelling drift. The City's own stated reason for the designation is
*"Rare (thought to be extinct) species of Manzanita studied by experts. Former site of Laurel Hill
Cemetary"* — the rarity **is** the designation. Our seed calls it a widely planted nursery cultivar.

The seed is not wrong about its source: it faithfully carries what DataSF `tkzw-k3nq` publishes for
those TreeIDs. The disagreement is between two of the City's own records, and it is the *landmark
roster* that carries the authority here, because §810 makes the species part of the finding the
Board adopted.

**What this does not settle:** whether a curated landmark entry may override the seed's
`species_current`, or whether it must render the city's two claims side by side. That is a #118
decision. It is recorded now so that nobody discovers it by shipping it.

---

## E?? — `qLegalStatus = 'Landmark tree'` is not the designation register, in either direction

The seed's `legal_status` column carries `Landmark tree` on 217 rows, and it is tempting — it is a
key join on `TreeID`, it needs no fetch, and it is already there. It is not the roster.

**It under-counts.** Four of the 26 designations carry no landmark flag anywhere in DataSF:

- #8, Two Cliff Date Palms (*Phoenix rupicola*), Dolores median → seed `25023`, flagged `DPW Maintained`
- #9, the Guadalupe Palm grove (*Brahea edulis*), 1608 Dolores → seed `25132`/`25133`, flagged `DPW Maintained`
- #22, Canary Island Pine, 2251 Filbert St → **no record at that address exists in DataSF at all**
- #23, California Buckeye, 2694 McAllister (removed 2022) → seed `255909`, flagged `Significant Tree`

**It over-counts.** Two Quesada Avenue trees are flagged `Landmark tree` and are not the designated
species — `Acacia melanoxylon` and `Prunus domestica 'Mariposa'` — where designation #7 covers "13
Canary Island Date Palms". Two rows at `2040 Sutter St` are flagged and match no roster entry at all.

**And it cannot express the state it is holding.** Public Works Code §810(d) creates a *temporary*
designation that begins on a resolution of intent and expires after 215 days unless extended.
DataSF row `111205` carries the note `Tree has temporary Landmark Status while nonimation is under
consideration. - Chris Buck 4/7/16` under the same `Landmark tree` flag; that tree was later
genuinely designated (#21, 2016-05-20). §810(b)(4) also lets the Board **rescind** a designation.
So the flag conflates designated, temporarily designated, and — potentially — rescinded, and a
boolean or a single free-text value is the wrong shape for it.

---

## E?? — `trees.legal_status` is documented as "DataSF `qLegalStatus`", but 130,029 `city` rows carry it

Observational, low stakes, recorded because the schema comment is load-bearing for provenance.

`build_seed.py`'s schema comment describes six columns as "Six DataSF columns carried verbatim, for
the tree page's *what the city has on file* panel". `legal_status` is one of them. But
`BUF_Street_Trees/FeatureServer/3` publishes no legal-status field of any kind — its 16 fields are
`OBJECTID`, `TREEID`, `Address`, `SiteOrder`, `PlantType`, `Prune_Status`, `Prune_Year`,
`Prune_TreeCount`, `DBH`, `DBHRange`, `COMMON`, `BOTANICAL`, `bos`, `keymap`, `Latitude`,
`Longitude` — and yet 130,029 of the seed's 133,577 `city` rows carry a non-null `legal_status`
(3,548 are null).

So for a `city` row, `legal_status` is a value from the *other* inventory joined on `TreeID`. That
is almost certainly correct behaviour and is what makes §3 of the landmark investigation possible.
But it means a `city` row's `inventory_source` does not describe where every one of its fields came
from, and the "what the city has on file" panel is quietly showing a reader one inventory's column
under another inventory's name — the precise thing the `inventory_source` comment says the column
exists to prevent. Worth a sentence in the schema comment, or a provenance stamp per field.
