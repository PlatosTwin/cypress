# The v20 index round. One tester-visible clause, and a long note about why it is only one.
#
# v19 recollated the dead per-tree contribution indexes. v20 finishes the same survey over the
# three families it scoped out: the species chain, the community rows, and the seed's species
# catalogue. Two of those three are structurally right and perceptually invisible, and this file
# says so rather than dressing them up — the round's honest tester-facing surface is screen 07.
#
# ── WHAT WAS SEEN, on the running screen rather than inferred ────────────────────────────────
#
# PLACEHOLDER-DEVICE-OBSERVATION
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
