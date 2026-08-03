### R?? — One plant under several spellings is a corpus repair, not a list behaviour — and only its last tier is a synonymy claim (task #184, delegated)

*Written under the delegated design authority for #184, which covers the (a)/(b) call and the copy
that would follow it. `RULINGS R47` named this ticket as what #103 left open and `ERRATA E208 §2`
records the defect.*

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge.*

**Status: decided and surveyed, NOT implemented.** No code and no seed in this branch changes because
of it. §6 says exactly why, and what the implementing branch has to be given.

---

#### What was delegated

#184 asks for one of two answers: **(a)** an explicit synonymy table with a stated source, extending
the existing corrections mechanism, or **(b)** a decision that the suggestion list groups visually
without asserting the rows are the same species.

**The answer is (a)** — and the survey below is why the question as posed is one question too few.
The duplicates are not one problem needing one table. They are **three tiers**, and only the third
is a synonymy claim at all. Tiers 1 and 2 are one string spelled several ways, which no source needs
to adjudicate; tier 3 is two names for one taxon, which no amount of string handling can reach.

---

#### 1 · The survey, measured against the shipped seed

All figures from `Cypress/Resources/cypress-seed.sqlite` (198,625 trees; 731 species rows, 726 once
R47's five unreadable rows are set aside), computed by normalising `scientific_name` and grouping.
The seed's own key is `normalise_species_key` — lowercase, collapse whitespace — which is why none of
these merged at build time.

| tier | the rule that would merge them | families | rows | rows that would go | trees under them |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | quote **glyph**, letter case, internal whitespace | 10 | 20 | 10 | 4,935 |
| 1+2 | …and quote **presence**, including unbalanced quotes | 15 | 34 | 19 | 5,646 |
| 1+2+3a | …and the hybrid marker `x` / `×` | 25 | 55 | 30 | 16,601 |
| 3b | two epithets, one taxon | *not reachable by any rule over the string* | | | |

**Tier 1 — the same characters, different Unicode.** `Acer rubrum 'October Glory'` ·
`Acer rubrum ‘October Glory’`. Also `Zelkova serrata 'Musashino'` against
`Zelkova serrata 'Musashino’`, which opens with a straight quote and closes with a typographic one —
one keystroke, in one cell, in one city's spreadsheet.

**Tier 2 — the quotes themselves, and the damage around them.**
`Arbutus 'Marina'` · `Arbutus marina` · `Arbutus ‘Marina’`.
`Magnolia grandiflora 'Little Gem'` · `‘Little Gem’` · `"Little Gem"` · `'Little Gem"`.
`Carpinus betulus 'Fastigiata'` against `Carpinus betulus ' Fastigiata'` — a leading space *inside*
the quotes. `Cedrus atlantica Glauca` against `Cedrus atlantica 'Glauca'`.
`Robinia pseudoacacia 'Umbraculifera'` against the same with no closing quote.

**Tier 3a — the hybrid marker.** `Platanus x hispanica` · `Platanus hispanica`;
`Acer x freemanii` · `Acer freemanii`; `Aesculus x carnea` · `Aesculus carnea`;
`Ulmus 'Frontier'` · `Ulmus x 'Frontier'`. Ten more families like them.

**Tier 3b — the one the ticket named, and the only true synonymy in the corpus.**
`Platanus × acerifolia` and `Platanus × hispanica` are two names for the London plane. Nothing in
either string says so. In the seed that costs `Columbia` **five rows**:

| row | trees | common name |
| --- | ---: | --- |
| `Platanus acerifolia 'Columbia'` | 1,075 | — |
| `Platanus x hispanica 'Columbia'` | 234 | `Columbia Hybrid Plane Tree` |
| `Platanus hispanica 'columbia'` | 20 | — |
| `Platanus x acerifolia ‘Columbia’` | 2 | — |
| `Platanus x acerifolia 'Columbia'` | 1 | — |

Tiers 1–3a collapse those five to **two**. Only a synonymy claim collapses the two to one.

---

#### 2 · Why (b) is refused, and the refusal is measured rather than argued

(b) would fix the dropdown and leave everything else. But **the split is not a list defect; it is a
corpus defect that the list happens to expose**, and three other surfaces are already wrong because
of it:

- **Screen 07's count card is understated on every family.** `In this inventory · 3,824` for
  `Arbutus 'Marina'`; the corpus holds 3,835. `Columbia Hybrid Plane Tree` says **234**; the London
  planes named Columbia number **1,332**. That is `RULINGS R48`'s defect exactly — a label over a
  population it does not name — reappearing from a different cause, and (b) does not touch it.
- **Curated content follows one row and abandons the rest.** In 22 of the 25 families some rows
  carry a common name and others carry none, and it is not always the big one:
  `Platanus acerifolia 'Columbia'` holds 1,075 trees and has no common name at all, while the row
  with the name holds 234. A reader who lands on the larger row gets a page headed with a Latin
  string; the smaller row gets `Columbia Hybrid Plane Tree`.
- **The map legend and the species-narrowed map split too.** `MapSpeciesPalette` colours by species
  id, so one plant takes two swatches and two legend entries, and tapping one narrows the map to a
  fraction of its own trees.

A grouping that renders rows together while the ids stay apart would have to be re-derived on each
of those surfaces, in four places, from four different values — and each would be free to disagree.
The one place the corpus's own identity is decided is `Tools/build_seed.py`, which is where R47 sent
the safe half of #103 for the same reason.

---

#### 3 · The ruling

**Tiers 1 and 2 are a key change in the builder, and they are not synonymy.** The claim being made
is "these strings are one string" — that a straight apostrophe and U+2019 are the same character for
indexing, that `Little Gem"` is `'Little Gem'` with a typo, that a space inside quotes is not part
of a cultivar epithet. No outside source is needed to say so and none could: this is the *same
assertion the seed already makes* when `normalise_species_key` lowercases and collapses whitespace,
extended by three more classes of the same kind of noise. It is stated as a rule in one function
with its own doc comment, and it is testable by listing what it merges.

**Tier 3a — the hybrid marker — is admitted, and it is the boundary case.** The `×` in
`Platanus × hispanica` denotes a hybrid and is conventionally disregarded when names are indexed or
alphabetised; `Acer freemanii` is not a second taxon, it is `Acer × freemanii` written without the
sign. This is one step further than tiers 1–2 because it appeals to a nomenclatural convention
rather than to a keyboard. It is still not a synonymy: it merges two spellings of *one* name, not two
names. **If the implementing branch wants to be conservative, this is the tier to drop** — it is 10
families and 11 rows, and dropping it costs nothing that tiers 1–2 buy.

**Tier 3b requires an explicit table with a per-entry citation, and it is the only tier that does.**
The mechanism already exists in shape: `QSPECIES_NAME_CORRECTIONS` in `Tools/inventory_adapters.py`
is a hand-written table whose one entry carries its source in the comment above it (SelecTree
tree-detail/1107, `match_method fuzzy_name_edit_distance_1_to_"platanus racemosa"`), and whose
header states the rule this ruling is bound by: *"Only entries an outside source already resolved
belong here … What must NOT go here: a vernacular-only string merged onto a binomial by judgment."*
A synonymy table is a sibling of it, not an extension: the corrections table maps a raw qSpecies
string to a name, and this maps an accepted name to a name it supersedes. One entry today:

    Platanus × acerifolia  →  Platanus × hispanica     [source required]

**The source must be named per entry, and this ruling does not name it.** POWO (Kew) and the GBIF
Backbone both state the relationship, and neither has been read by anybody on this branch. Writing
the citation from memory is precisely the failure the corrections table's own header refuses, and it
is what `Fixtures/species/leaf_retention.yaml` already avoids by carrying `match_method` and a source
id beside each row. **An implementing branch that cannot produce a citation must ship tiers 1–3a and
leave the two Columbia rows apart** — that is a smaller and honest result, and it still takes the
`Columbia` family from five rows to two.

**The direction of a merge is by tree count, not by which name is "better".** The row with the most
trees wins its family and keeps its `scientific_name` verbatim; the losers' trees are re-pointed and
their rows do not enter the file. Any common name or curated content present on exactly one row of a
family travels with the winner, which is what fixes the `Columbia` split above.

---

#### 4 · The trap, restated so it cannot be walked into

**No dedupe here strips a cultivar.** `Arbutus 'Marina'`, `Ceanothus 'Ray Hartman'` and
`Ulmus 'Frontier'` are real, wanted rows and stay distinct from `Arbutus unedo`, `Ceanothus
thyrsiflorus` and `Ulmus parvifolia`. Every rule above normalises how a cultivar epithet is
*punctuated*; none removes one. A rule that merged `Arbutus 'Marina'` into `Arbutus` was explicitly
refuted as a fix for #103 and is not reintroduced by any tier.

**A premise in the #184 brief is wrong and is corrected here.** The brief states that R47 records
"175 cultivars kept as distinct species on purpose". R47 records no such number — the word
*cultivars* appears in it twice, both times in the singular, describing what the builder's swap
reads. The measured figure is **194** species rows carrying a quoted cultivar epithet (`SELECT
count(*) FROM species WHERE scientific_name NOT LIKE ':: %' AND scientific_name LIKE any quote`).
The substance of the warning is right and unchanged; the citation and the number are not.

---

#### 5 · What a merge moves, and what it must not

`species.uuid = uuid5(NS_SPECIES, normalise_species_key(scientific_name))` — E208 closes by warning
that a merge changes species uuids, "the thing the seed is careful never to move". That warning is
about the wrong half of the change and it is worth being exact, because taken at face value it would
stop tiers 1–2 for no reason.

**Mint each surviving row's uuid from its own verbatim name, exactly as today, and use the normalised
key only to decide which rows share a family.** Then no surviving uuid moves: `Arbutus 'Marina'`
keeps `uuid5(NS_SPECIES, "arbutus 'marina'")` and the 194 cultivar rows keep theirs. What
disappears is 19 to 30 loser uuids, which is unavoidable and is the point of the ticket. A design
that normalised the *minting* input instead would move all 194 — including every row a grove entry,
a favourite or a `species_assertions` chain already points at — and there is no reason to.

---

#### 6 · Why this branch stops here, stated plainly

Tiers 1–3a are a rebuild: `python3 Tools/build_seed.py --source city --sj-extent downtown`, a new
103 MB artifact into `Fixtures/seed/` and `Cypress/Resources/`, a new sha256 replacing
`d3e3d229…`, and new values for `seed_meta.species_count` (731 today), `distinct_qspecies` and the
per-family counts. `CypressTests/SeedCorpus.swift` pins several of those constants, `SeedCorpus`
comments cite the pre-#103 figures, and every live branch reading the seed inherits the new file at
merge. That is an announced, scheduled corpus change with a rebuild verification of its own — not
something to land beside a copy fix, and #184's own ticket says the same.

**What the implementing branch needs, and this ruling supplies:** the tier boundaries, the exact 25
families and 55 rows (reproducible from the query in §1), the merge direction, the uuid rule in §5,
the cultivar trap in §4, and the one synonymy entry that needs a citation before it can be written.
What it still owes: that citation, or the decision to ship without tier 3b.

---

#### What this does not settle

**`Magnolia grandiflora 'Sam Sommers'` (4 trees) beside `Magnolia grandiflora 'Samuel Sommer'`
(260).** E208 lists it with the quote variants and it does not belong there: `Sam Sommers` and
`Samuel Sommer` are different words, not different punctuation, and merging them is an edit-distance
judgment about a person's name. It is the same class as `patanus racemosa` — which the corrections
table admits only because an outside source already resolved it — and it needs the same treatment,
one row at a time, with a citation. No tier above touches it. `Magnolia 'Samuel Sommer'` (2 trees,
no `grandiflora`) is a third case again: a cultivar attached to a bare genus, which may or may not be
the same plant, and which nothing in the string settles.

**Whether the app should say anything about a merge having happened.** It should not, and no copy is
specified: a corpus that holds one row per plant is the state every other species on screen 07 is
already in, and a sentence explaining an absence nobody can see would be the fabricated state
DECISIONS constraint 21 forbids.
