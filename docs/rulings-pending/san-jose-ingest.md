<!-- Written for #129, the ingest half. Append to docs/RULINGS.md as R24. Do not renumber. -->

### R24 — a seed row must carry its source's own id, and a rule written over one city's vocabulary does not run against another's

Two decisions, taken while ingesting the second city (#129, ERRATA E176). They are one entry because
they are the same mistake seen from two sides: **San Francisco's arrangements had become the
framework's, invisibly, by being the only ones there had ever been.**

---

#### 1. `trees.external_ref` is `NOT NULL`, so a source with no id of its own cannot be a seed row

**The decision.** With uniqueness moved to `UNIQUE (id_space, external_ref)`, `external_ref` is
declared `NOT NULL`. `build_seed.emit()` stops the build, loudly, on any record whose
`has_stable_identity` is False, rather than writing a row with a NULL ref.

**Why NOT NULL rather than the nullable column the old schema had.** SQLite treats NULLs as distinct
in a unique index. A nullable `external_ref` would let every identity-less row through the constraint
the column exists to enforce — and it would do so silently, which is worse than the old
`INTEGER UNIQUE`: that at least failed at the first collision.

**What this rules out, and it is a real cost.** `InventoryRecord.source_ref` is optional by design.
The survey found a source that needs it: Oakland's Socrata dataset publishes no id but `objectid`, a
row number in a 2013 extract, and E172 records that the honest adapter passes `source_ref=None` so
`has_stable_identity` reads False. **Under this ruling Oakland cannot be ingested into the seed.**
That is stated as a limit rather than hidden as a crash: the contract can still represent such a
record, `build_seed` refuses it with a sentence naming this ruling, and whoever wants Oakland has to
decide what a seed row's identity is when the publisher issues none — a lineage key, a coordinate
hash, or a `has_stable_identity` column beside the ref. **Do not resolve it by making the column
nullable again.**

**Why not store the qualified string `us-ca-sj:3` in one column instead.** It makes "which space is
this row in" a parse rather than a column, and the id space is a thing the receipt, the contract test
and the UI all need to name. Two columns and a composite unique index cost one integer of index width
and answer the question directly.

---

#### 2. `LandContext.inferred(from:)` is San Francisco's rule, and it now refuses to answer for anywhere else

**The decision.** `LandContext.inferred(from:idSpace:)` returns nil for any `idSpace` other than
`sf`. `Tree` carries `idSpace`; nil means "the record does not say", which is how every seed built
before the v14 pass reads and is correct for those files.

**Why it is a ruling and not a bug fix.** The function did not crash or throw against San Jose. It
answered — for all 52,788 rows, confidently, and wrongly. 48,036 of them resolved to
`.privateProperty` because San Jose's `OWNEDBY` says `Private` where San Jose's model is that the
*adjacent owner maintains* a tree standing in the public right-of-way. Not one row of a layer called
*Street Trees* resolved to `.street`. The function's own doc comment already warns about exactly this
error one column to the left — it is the reason `qLegalStatus` leads and `qCaretaker` only fills in —
and the warning did not generalise because nothing had ever asked it to.

**Why nil and not a San Jose branch.** Writing one would be a design decision taken in passing, on a
vocabulary nobody has studied, inside a change about schema. And the branch somebody would write is
probably the wrong one: `GROWSPACE` (`Park Strip`, `Well/Pit`, `Median`, `Tree Lawn`) is a far better
signal for where a San Jose tree stands than `OWNEDBY`, and choosing between them deserves its own
look. Meanwhile nil draws nothing, which is what E9 already established for a species with no sourced
leaf retention: **absence renders as absence, and a default is the bug.**

**The rule this generalises to, and it is the point of the entry.** *A derivation over a publisher's
own vocabulary is qualified by the id space it was written for, and must decline outside it.* The
test a shared function has to pass is not "does it return something sensible for the new source" but
**"was this rule written from this publisher's documentation".** If it was not, it does not run. The
merged national inventory D16 describes is a table of many publishers' vocabularies, and a rule that
silently spans them produces confident wrong answers at exactly the scale the product is for.

**What it does not decide.** How San Jose's land context *should* be read, whether `site_type` should
carry the answer instead of being derived per city, and whether the six `city_record` columns —
documented as DataSF's `qLegalStatus`, `qCaretaker`, `PlantType`, `PlotSize`, `PermitNotes` — should
be holding another publisher's differently-meaning columns at all. That last one is the deeper
question and `SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS` is where it lives.
