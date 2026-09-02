# The v20 index round. One tester-visible clause, and a long note about why it is only one.
#
# v19 recollated the dead per-tree contribution indexes. v20 finishes the same survey over the
# three families it scoped out: the species chain, the community rows, and the seed's species
# catalogue. Two of those three are structurally right and perceptually invisible, and this file
# says so rather than dressing them up — the round's honest tester-facing surface is screen 07.
#
# ── WHAT WAS SEEN, on the running screen rather than inferred ────────────────────────────────
#
# iPhone 16 Pro Max (DE8E11AE), on a database that was genuinely carried across the version —
# not a fresh install reporting the new number. The v19 build (origin/main at e574a0a) was
# installed and launched, which produced a real `user_version = 19` file with
# `idx_species_assertions_tree` BINARY and no `idx_community_trees_id`; one community tree and a
# two-link species chain were written into it; the file was copied out; the v20 build was
# installed and the file put back under it. That indirection is deliberate and it is worth
# stating: `simctl install` replaced the data container on every attempt here, fresh database
# and all, so "install the new build over the old one" silently produces a FIRST RUN. The first
# attempt did exactly that and reported `user_version = 20` — the right number for the wrong
# reason. What was actually checked is a v19 file opened by the v20 build, which is the
# migration path.
#
#   1. The file came up at 20. All rows survived: one community tree, two assertions, and
#      exactly one un-superseded head — the invariant v20 refuses to touch, intact.
#   2. `idx_species_assertions_tree` is `COLLATE NOCASE` and `idx_community_trees_id` exists;
#      `idx_species_assertions_head` is still the BINARY partial UNIQUE index v14 wrote, byte for
#      byte. Read out of `sqlite_master` on the device's own file.
#   3. Planned against that same file, with the app's own predicates: the chain and head reads
#      both `SEARCH species_assertions USING INDEX idx_species_assertions_tree (tree_uuid=?)`, and
#      the community lookup `SEARCH community_trees USING INDEX idx_community_trees_id (id=?)`.
#      The cross-case lookup — upper-case bound against a lower-case stored id — returns its row.
#   4. **The species resolution path, on screen.** Map, species filter still set to Southern
#      Magnolia from the carried-over state, magenta pins drawn — that filter is
#      `TreeQueries.speciesRowIDs`, one of the five statements this round changed. Tapped a pin:
#      `Southern Magnolia · Magnolia grandiflora · 110 m NE`. Opened it: the full profile, with
#      the scientific name, `SF Public Works street tree inventory`, the recognition tip ("Big
#      leathery leaves, glossy dark green above, with rusty-brown felt underneath"), DBH 250–255
#      cm marked `city record`, site `Sidewalk: Curb side : Cutout`, city record #5440. Every one
#      of those fields comes through the species projection whose comparison changed.
#   5. **The community-tree path, on screen.** The added tree drew as the dashed ring the
#      unverified layer uses (DECISIONS §3.16) — invisible at first because it had been placed at
#      exactly the simulated device coordinate and was underneath the location dot, which is a
#      fixture mistake and not a defect; moving the device 120 m separated them. Tapped it:
#      `Unidentified · 117 m NE`, correct, because the row carries no `species_current`. Opened
#      it: `Tree — community-added, unverified · position from GPS`, with the community
#      affordances (`Say what species you think this is`, `Report that there is no tree here`).
#
# What is NOT claimed from any of this: a speed observation. None of these screens was timed by
# eye and none of them was slow before. The numbers below are measured separately and stated as
# what they are.
#
# ── WHAT THE ROUND ACTUALLY CHANGES ──────────────────────────────────────────────────────────
#
# Three families, all dead the same way: a `COLLATE NOCASE` comparison cannot reach an index
# built with the BINARY collation, so a lookup that looked indexed walked its table instead. It
# is the same defect v19 fixed for `visits` and its four neighbours, and the same one PR #131
# fixed for `trees.uuid`. Two of the three are fixed by recollating an index (a migration); the
# third could not be, because `species` lives in the read-only seed, so the comparison moved
# instead.
#
#   1. `species_assertions` — `idx_species_assertions_tree` recollated NOCASE. Both readers of
#      the species chain now seek it.
#   2. `community_trees` — a new `idx_community_trees_id`, because the table's own primary key is
#      SQLite's `sqlite_autoindex_community_trees_1` and there is no `CREATE INDEX` text to
#      rewrite. All six statements that look a community tree up by id now seek it.
#   3. `seed.species` — five reads moved from `= :uuid COLLATE NOCASE` to `= lower(:uuid)`,
#      PR #131's form, which is the only comparison that both matches and seeks.
#
# ── THE MEASUREMENTS, AND WHICH ONE IS WORTH A LINE ──────────────────────────────────────────
#
# EXPLAIN QUERY PLAN and repeated in-process reads against the pinned bundled seed (198,625
# trees, 731 species), and against a scratch database carrying this schema's real DDL. The
# instrument was calibrated first, and the first version of it failed that calibration: a
# `.timer on` loop in the sqlite3 CLI reported a full scan of 198,625 rows at the same 0.001 s
# as `SELECT 1`, which is not a fast query, it is a broken stopwatch. The numbers below come from
# the replacement, which separates a no-op from a known full scan by 8,700x.
#
#     read                                          before (ms)   after (ms)
#     screen 07 `Nearby individuals`, 1,200 m          10.36         1.38
#     screen 07 `Near you` count, radius arm            5.75         1.10
#     screen 07 `Near you` count, neighborhood arm      1.46         0.94
#     screen 07 `In this inventory` count               1.13         1.10
#     one species by uuid (the field guide entry)       0.044        0.010
#     the map's species filter, 25 uuids                0.063        0.034
#
# **Only the first two are claimed below**, and the reason is the second column rather than the
# ratio. A read that goes from 0.044 ms to 0.010 ms got four times faster and saved 34
# microseconds; nobody has ever waited for it. The two that are claimed are the ones whose
# *before* number is large enough to be part of a visible wait, and they are on the same screen.
#
# The `Nearby individuals` row is the one that grows with the radius rather than shrinking: the
# old plan drove from the bounding box and did a lookup into `species` for every tree inside it,
# so pulling the search radius out made it worse. Driving from the one species row instead does
# not. That is why the line below says "however far the search reaches".
#
# ── WHAT IS DELIBERATELY NOT CLAIMED ─────────────────────────────────────────────────────────
#
# **The community-tree lookups.** All six went from a table walk to a seek, which reads like a
# result and is not one: `community_trees` holds the trees *this contributor has added by hand* —
# tens of rows on a phone, and the table's own comment says so, which is why it has no R*Tree
# either. The walk was cheap because the table is small. The index is worth having because the
# table is unbounded in principle and the cost of finding out otherwise is a slow write path
# nobody profiles, not because anyone will feel it. No line for it.
#
# **The species chain.** Same shape: a chain is a handful of assertions per tree.
#
# **No frame, anywhere.** Nothing here has measured a dropped frame before or after. These are
# database reads on a background queue.
#
# **`In this inventory`** is in the table above and not in the line below on purpose — 1.13 to
# 1.10 ms is not a change, and it is listed so the round's own numbers do not read as though
# every row improved. That statement was changed with its two neighbours so the three read alike,
# not for its timing.
#
# ── A CONTRACT THAT NOW HAS A GATE ───────────────────────────────────────────────────────────
#
# `lower(:uuid)` matches only what is already stored lower case, so the third family above rests
# on a property of every published file: `species.uuid` is lower case. It is true of the bundle
# (0 of 731) and it is true by construction of every pack — `Tools/build_seed.py` writes species
# uuids through Python's `str(uuid.UUID)`, which is lower case, and `Tools/publish_cities.py`
# keeps the `species` table WHOLE by byte-copy while it narrows `trees`, so a pack's rows are the
# seed's rows.
#
# Until this round that was an argument. `DataGates.armsWithUppercaseSpeciesUUIDs` makes it a
# check, per attached file, and `SpeciesAccessPlanTests` carries its own negative control: a pack
# that keeps the contract is accepted and the same pack with its species uuids upper-cased is
# named. A file that broke it would not be slow — it would be *empty*: no field guide entry, no
# counts, no `Nearby individuals`, and an empty species filter, none of them reported as an
# error. That is a failure a gate has to catch before a reader does.
#
# ── WHAT THIS ROUND REFUSED TO DO ────────────────────────────────────────────────────────────
#
# `idx_species_assertions_head` is a partial UNIQUE index — v14's "one current claim per tree",
# the same instrument as `tree_names`' D15 index. Recollating it NOCASE would change *which pairs
# of rows the schema calls a conflict*, on databases already in the field, and could make the
# migration itself fail. It stays BINARY. The measurement is what made that free: with
# `idx_species_assertions_tree` recollated, the head reader seeks that index instead and never
# reads the unique one, so refusing cost nothing. `SchemaV20Tests.theHeadIndexKeepsItsBinaryCollation`
# is the trip-wire for the next person who reads the diff and thinks the job is half done.
#
# ── ON LENGTH ────────────────────────────────────────────────────────────────────────────────
# One line, inside the 200 the check allows.

A species page's Near you and Nearby individuals now open quickly however far the search reaches — they used to get slower the wider you looked.
