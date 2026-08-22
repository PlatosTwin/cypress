# Unnumbered rulings — the s17 region generation

Staged per CLAUDE.md, "Numbering and shared files". These are the shape decisions the s17 round
had to take that the design proposal delegated rather than settled. The orchestrator splices them
under real R numbers at merge.

---

### R??? — The region's identity is three separate strings, and only one of them is frozen

`dim_region` carries `pack_id`, `display_name` and `level`, plus `city_id`. Three decisions inside
that, each taken because collapsing it into an existing column was the tempting and wrong move.

**1. `pack_id` is distribution identity and is frozen; it is not `dim_city.slug` and not
`id_spaces.id`.** It is simultaneously the manifest entry's `id`, the `<id>` in R37.2's immutable
object path `cities/<id>/<version>/<id>.sqlite`, and the install key on a reader's device. `sf` and
`us-ca-sj` are frozen at the values the format-1 manifest has already published — changing either
orphans every installed copy and breaks paths R37.2 promises never move.

It is a separate column from `dim_city.slug` because for San Francisco the two are *already*
different strings: the pack is `sf`, the slug is `us-ca-sf`. A design that reused the slug would
have had to either rewrite San Francisco's published path or special-case it forever.

**2. `level` is not `coverage`, and San Jose is the case that proves it.** `level` describes the
KIND of unit (`city` | `borough` | `extent`); `coverage` describes how much of that unit shipped.
San Jose ships only its downtown window and is nonetheless level `city` with coverage `downtown` —
a whole city of which part shipped. Folding the extent into the level would have made "San Jose" a
different kind of thing from "San Francisco" on the basis of a shipping decision, and the day San
Jose ships completely its level would change, which is a fact about identity changing on the basis
of a fact about volume.

**3. A one-region city is `level: "city"`, not a special case.** RULING D2's "one shape everywhere"
taken literally: San Francisco is a city-level region of itself. There is no NYC-only concept, no
nullable region, and no `if` in the publisher or the screen.

---

### R??? — An adapter names a region in its source's own words; the pack id is entered elsewhere

`InventoryRecord.region` carries what the **source** calls the region — NYC Parks writes
`"Queens"`, so an adapter passes `"Queens"`. `Tools/build_seed.REGIONS` is the hand-entered table
that maps `(id_space, that string)` onto a `dim_region` row, and the frozen `pack_id` lives there.

The seam is where it is for two reasons. Civic naming is entered, never derived (DECISIONS
constraint 15). And an adapter reading a data file is the wrong layer to be minting an identity
that R37.2 then freezes into an immutable object path forever — an adapter that emitted
`"us-ny-nyc-queens"` would be deriving distribution identity from upstream's spelling habits, which
is the same class of mistake as `trees.inventory_source`'s old closed CHECK (ERRATA E169).

The practical consequence: `feat/nyc-ingest`'s **adapter** already emits the five bare borough
names, so the values it produces satisfy this contract as they stand.

**But "the ingest needs no rework" was too strong, and adversarial review (finding F6) measured
two things the NYC round must still do.** Both fail loudly at merge — neither can ship quietly —
and the NYC round's brief inherits this list:

1. **Register New York in `Tools/build_seed.REGIONS`.** It holds `['sf', 'us-ca-sj']` today. An
   ingest contributing rows in `us-ny-nyc` hits, before any tree is written:

       no dim_region row registered for id space(s) ['us-ny-nyc'] in REGIONS
       -- a published unit's identity is entered, never derived

   That is the constraint-15 gate doing its job: the five `pack_id`s and the five display names
   are civic/distribution identity and must be entered by a human, once, and then frozen.

2. **Every NYC record must name its region.** The `(space, None)` key — "this id space's sole
   region" — is registered only when a space has exactly one, so with five boroughs `sole` is
   `False` and `None` resolves to nothing. Any record arriving with `region=None` hits:

       no dim_region row for N row(s) in id space 'us-ny-nyc' naming region None

   This is deliberate rather than incidental: a space with several regions and a record naming
   none has no defensible default, and guessing would put trees in an arbitrary pack. It is also
   exactly what RULING D18's point-in-polygon orphan assignment exists to satisfy — the ~22,995
   trees with no planting space must arrive carrying a borough, and this is the check that
   enforces it rather than trusting the ingest to have done it.

`region=None` therefore means "the id space's sole region", and a space with more than one region
and a record naming none is a **stop**, not a guess.

---

### R??? — `trees.region_id` is NOT NULL, and that constraint is the pack arithmetic

A nullable region would mean a row that is present in the fused seed and absent from every pack a
reader can download — visible to nobody, reported by nothing. The publisher narrows on this column,
so NULL is not "unassigned", it is "deleted from every output".

NOT NULL is what makes the per-region counts sum to the fused total, which is the check that closes
the arithmetic. RULING D18's point-in-polygon orphan assignment exists for exactly this reason on
the NYC side; this is the same requirement expressed as a constraint the database enforces rather
than a property the ingest is trusted to maintain.

It is an INTEGER join key rather than the region's name for the reason the identity model already
gives: New York is ~898,000 rows, and a TEXT borough on each is tens of megabytes of repeated
string in the payload and in every index that copies it.

---

### R??? — The format-1 manifest keeps the old *path*, and format 2 takes a new one

RULING D8 requires dual-publishing for one release cycle. It does not say which object gets which
name, and the choice is load-bearing.

`CityManifest.decode` refuses an unknown format outright, before reading anything else — correctly.
So publishing format 2 at `manifest.json`, the path every shipped build hard-codes, would take the
entire Cities screen offline for every unupdated install at once. Format 2 therefore publishes at
`manifest-v2.json` and the old name keeps its old format, listing **city-level packs only**.

Filtering the format-1 list is the whole of what keeps the old format TRUE rather than merely
parseable: a format-1 reader has no concept of a region, so listing a borough to it would hand it
something it would confidently mis-describe as a city with its own civic identity.

**And the reverse direction, which D8 does not cover.** D8 protects an old install against a new
bucket; nothing protects a new *build* against an old bucket, which is the ordinary state of the
world between shipping this round and running the next publish. `CityDownloader.fetchManifest`
therefore falls back to `manifest.json` — **on absence and on nothing else.** Absence means a `404`
**or a `403`** (see below); a 500, a timeout or a manifest that does not decode are facts about that
fetch, and retrying them elsewhere would turn one honest error into a confusing second one and
silently downgrade a reader to the whole-cities-only catalog on a transient blip.

**`403` counts as absence, and that is a judgement call rather than a reading of HTTP.** It is
recorded here because it is the kind of decision that looks like a bug to the next person who finds
it, and a source comment is not where a reader looks for the reasoning.

- **The measurement that forces it.** `CityDownloader`'s own header records it: *Tigris has served
  `HEAD 200` beside `GET 403` on the same key.* An S3-compatible store answers `403` rather than
  `404` for a key the caller may not enumerate, so on the public domain — the only host the app
  talks to — a manifest that has simply never been published can arrive as `403`. A fallback
  watching `404` alone was therefore dead code exactly where it was needed, which is what
  adversarial review found.
- **Why it cannot mask an authorization failure.** *There is nothing to authorize.* Every request
  from this type is anonymous: the app holds no bucket credential, sends none, and R37.4 forbids
  reading a host out of the manifest. For an unauthenticated reader `403` and `404` carry the same
  information — you cannot have this object. There is no credential that could be wrong, so there
  is no auth failure to be masked.
- **A real lockout still surfaces, because the fallback retries once and never swallows.** If the
  bucket were misconfigured to private, *every* object answers `403`, including the legacy manifest
  this falls back to — so the second fetch fails too and **its** error propagates. The reader sees
  the legacy path's failure, which is the more informative one, because that is the object every
  shipped build depends on.
- **Scope.** Only the manifest consults this. `downloadCity` does not: a `403` on a city file stays
  a hard failure, because that object's absence is not a recoverable transitional state — it is a
  manifest that lied.

`CityManifest.knownFormats` becomes `{1, 2}`. The rule that did not soften: an unknown format is
still refused at the door.

**Deliberately UNSCHEDULED, and named so it is not mistaken for an oversight:** retiring the
format-1 object and the `level == "city"` filter that keeps it honest has **no date and no ticket**.
D8 sets the window at "one release cycle" without fixing when it starts, and the honest trigger is
the first NYC publish — the moment the format-1 catalogue starts omitting real packs rather than
merely describing whole cities. That is an owner decision about TestFlight adoption, not an
author's, and it is being carried to the owner separately. Until it is taken, both objects publish
and both are verified on every run.

---

### R??? — `region.level` decodes as a string, not a Swift enum

The level is the publisher's vocabulary and may gain a member without a format bump — R37.4's
additive-change rule covers a new *value* the same way it covers a new *key*. A non-exhaustive
Swift enum would turn that addition into a decode failure across the **whole manifest**: every city
gone from the screen over one string in one entry.

A reader that does not recognize a level shows the pack by the names it carries, which is what it
does today. Pinned by `RegionGenerationTests.anUnknownLevelStillDecodes`.

---

### R??? — Condition is a field on the record, not a fourth `kind`

A standing dead tree is a `KIND_TREE` — something woody stands there, it occupies the site, it is
drawn on the map — whose `condition` is `dead`. Modelling it as a fourth kind was considered and
rejected: every `kind` consumer would then have to remember that one of the four is really a tree,
and `kind` answers "what does this record describe" while condition answers "how is it doing".
They are independent, and the contract now forbids the one pair that cannot mean anything — a
planting site in a condition — in both `InventoryRecord.validate` and `status_for_record`.

`None` is "the source made no claim" and is **not** `alive`. It maps to `alive` only because that
is what the seed has always shipped for a listed tree, and stating the two separately is what lets
a future source distinguish "we asked and it is alive" from "nobody asked".

---

### R??? — Coverage stays keyed on the id space, and the state that would force the move is refused

Raised by adversarial review of the s17 PR (finding F9): pack identity moved to the region, and
`coverage` did not. Decided rather than left to be noticed.

**Coverage describes how much of a CITY's inventory a publish shipped.** San Jose's `downtown` says
the seed holds the central window and not the rest of San Jose — a fact about the city's corpus,
not about any one pack. Every pack cut from that corpus inherits it, which is why the key is the
city's and each of its packs reports the same value.

**Kept on the id space, not moved to the region.** For New York a per-region key would state the
same fact five times: every borough pack ships all of its borough, so each is `full` and the fact
they share is that `us-ny-nyc` is fully covered. Five copies of one fact is five chances to
disagree, plus a second hand-maintained table for `SeedCities` to mirror — which is the exact shape
of the divergence this round just closed (see the coverage-key erratum). R37's own trailing clause
names `coverage_<id_space>`, and this keeps it.

**The state one key cannot describe, refused rather than guessed.** Several regions in one id space
*and* a coverage that is not `full`. Then "how much of this pack shipped" has no single answer and
every entry would repeat a value true of none of them. `Tools/publish_cities.py` fails on exactly
that pair, naming the move as the fix — so the divergence cannot ship quietly, and whoever first
needs per-region coverage meets the decision with the seed in front of them.

Both directions red-proved: removing the guard lets the ambiguous seed publish; broadening it to
any partial coverage refuses San Jose's live shape.
