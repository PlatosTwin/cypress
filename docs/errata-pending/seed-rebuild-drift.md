# E— — what a seed rebuild surfaced that nobody had changed (task #103)

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge
and rewrites the citation in `CypressTests/SeedCorpus.swift`.*

Task #103 is the first ticket in a while to rebuild the seed rather than read it. Two things came
out of the rebuild that are **not** consequences of #103's change, and both would otherwise be
discovered by whoever rebuilds next, as a mysterious red.

---

## 1 · The shipped seed was one raw-cache snapshot stale

`CypressTests/SeedCorpus.cityWithSanJose` recorded `permit_notes: 78_095`. A rebuild from the current
`Fixtures/raw/` reads **78,094**, and the difference is a single tree: SF TreeID 234040, which the
shipped file carries as `Permit Number 805842` and which
`Fixtures/raw/street_tree_list.csv` now publishes with an empty `PermitNotes`.

**It is the artifact that moved, not the ingest.** The SF-only variant (`--source city --sj-extent
none`) reads `permit_notes: 27_046` before and after the #103 change, which is the constant already
checked in — so the SF-only number was recomputed against the current CSV at some point and the
SF+San-Jose number was not. Nothing in the ingest treats that column differently between the two
extents; the SF rows are identical in both builds.

Everything else in the rebuild is identical to the shipped file. Compared table by table — `species`,
`species_map`, `trees` (id, uuid, external_ref, status, species_current), `neighborhoods`,
`inventories` — the only difference in the whole database was that one tree's free-text passthrough
and the `seed_meta` counter that reports it.

**Two consequences worth stating.** The build *is* byte-for-byte deterministic as its docstring
claims: two consecutive rebuilds from the same inputs produced the same sha256
(`d3e3d229…`). And a checked-in corpus constant is only as fresh as the last person who rebuilt; the
number in the fixture had been right about a file, not about the pipeline, for some time.

## 2 · One plant, several spellings — and #103 fixes only the unreadable ones

The catalogue carries the same plant under spellings that differ by more than case, so the seed's
own key (`normalise_species_key`, which lowercases and collapses whitespace) cannot merge them:

- `Arbutus 'Marina'` · `Arbutus marina` · `Arbutus ‘Marina’` — straight quotes, none, typographic
- `Platanus acerifolia 'Columbia'` · `Platanus x acerifolia 'Columbia'` ·
  `Platanus x hispanica 'Columbia'` · `Platanus hispanica 'columbia'`
- `Magnolia grandiflora 'Samuel Sommer'` · `Magnolia grandiflora 'Sam Sommers'` ·
  `Magnolia grandiflora 'Samuel Sommer"` — the last with a closing double quote

The suggestion list shows every one of them, so a reader typing `marina` still sees duplicate rows
after #103. This is the general form of the ticket's "one species appears twice under two names";
#103 removed only the half where one of the two names was **not a name** (`:: Arbutus 'Marina'`).

**It is left alone on purpose.** Merging `Arbutus marina` into `Arbutus 'Marina'` is a synonymy
ruling, and no source in the pipeline states it — the same reason `QSPECIES_NAME_CORRECTIONS` admits
a one-character misspelling that an outside source already resolved and refuses `Brisbane Box`,
which names two species this inventory carries separately. Typographic-versus-straight quotes is the
one subgroup that looks mechanical enough to fix without a source, and even there `Arbutus ‘Marina’`
and `Arbutus 'Marina'` being the same plant is an inference about a keyboard, not a citation.

Anyone taking this on should note it changes species uuids (`uuid5` of the normalised name), which
is the thing the seed is careful never to move.
