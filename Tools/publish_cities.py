#!/usr/bin/env python3
"""
publish_cities.py -- split the fused seed into versioned per-city SQLite files
plus a manifest.json, ready for upload to the `cypress-cities` Tigris bucket.

R36 (docs/RULINGS.md) makes the base layer "versioned per-city SQLite files
published by the ingest pipeline to object storage with a manifest". This is
that publish step. It consumes the ingest pipeline's OUTPUT -- the fused seed
Tools/build_seed.py writes to Fixtures/seed/cypress-seed.sqlite -- and never
talks to any upstream source itself.

    python3 Tools/publish_cities.py [--db PATH] [--out DIR] [--base-url URL]

    --db        the fused seed (default: Fixtures/seed/cypress-seed.sqlite,
                resolved against the repo root this script lives in)
    --out       output directory (default: dist/). Cleared of a previous run's
                cities/ tree and manifest.json before writing; nothing else in
                it is touched.
    --base-url  informational only; recorded in the manifest as `base_url_hint`
                so a reader of the artifact knows where it was headed. The app
                must NOT read it -- the app's base URL is app configuration.

Exit codes:
    0  every per-city file built, verified, and described in manifest.json
    1  a verification failed -- nothing in --out should be trusted
    3  a required input was missing

WHAT GOES IN A CITY FILE. Each output starts as a byte-copy of the fused seed
and is then narrowed, so its schema (tables, indexes, CHECKs, the R*Tree) is
the fused seed's schema by construction, never a re-statement of it:

  trees               only rows whose `id_space` is the city's
  species_assertions  only rows whose tree survived
  trees_rtree         only entries whose tree survived
  neighborhoods       only polygons some surviving tree references (an
                      unreferenced polygon can answer no query in a city file;
                      San Jose currently references none and ships none)
  id_spaces           the city's row only -- a city file that listed a foreign
                      id space would be claiming an identity authority it
                      does not carry
  inventories         the city's inventories only, same reason
  species,            kept WHOLE. The species catalogue (and the curated field
  species_map         guide riding on it) is shared authored content, not city
                      data; splitting it would fork curation. species_map's
                      `tree_count` therefore still describes the FUSED build --
                      seed_meta.species_map_counts_scope says so in-band.

  seed_meta           the fused build receipt is kept verbatim EXCEPT the keys
                      that name this file rather than the build that fed it
                      (`id_spaces_in_file`, `rows_kept`, and every
                      `rows_from_<inventory>`), which are rewritten to the
                      truth about this file. Publisher facts
                      are added under `publish_*` keys. `trees_snapshot_on`
                      (which the app shows as "city record as of") is
                      rewritten to the city's own content revision.

VERSIONING (delegated decision -- RULINGS R37):

  schema_version  integer, the seed schema generation. The record already
                  numbers these ("the v14 seed pass", E176/E169 -- id_space
                  arrived in v14), so the publisher continues that numbering
                  rather than inventing a parallel one. Bump it when
                  Fixtures/seed/schema.sql changes shape.
  content_rev     YYYY-MM-DD, the newest upstream snapshot date among the
                  city's own inventories (seed_meta inventory_*_snapshot_on).
                  Derived from data, never from the wall clock, so re-running
                  the publisher over the same seed yields the same version.
  build_id        the first 8 hex of the SOURCE SEED's sha256. Added by task
                  #197 / RULINGS R60, which amends R37.2. Without it the two
                  fields above name the CITY's data, never the build, so an
                  ingest fix that changes the corpus while the city's snapshot
                  date stands still produces different bytes under the SAME
                  version -- and the only honest ways out are to rewrite an
                  immutable path or to falsify content_rev. That is exactly
                  what happened: the published files predated task #103's
                  ingest fix by a day and nothing could say so.
                  Still derived, never wall-clock, so determinism holds: the
                  same seed yields the same build_id and therefore the same
                  path.
  version         "s<schema_version>-r<content_rev>-<build_id>", e.g.
                  "s14-r2026-07-31-d3e3d229".
                  This is the immutable path segment on object storage:
                  cities/<id>/<version>/<id>.sqlite. A given version is
                  write-once; only manifest.json ever changes in place. The
                  app treats it as an OPAQUE string compared by equality
                  (RULINGS R43), so lengthening the grammar is safe on the
                  reader's side -- but never shorten or reorder it without
                  re-reading CityManifest.

DETERMINISM. The per-city files contain no wall-clock value: every stamped
fact is derived from the input seed, and the narrowing is DELETE + VACUUM,
which is deterministic for a given input file and SQLite build. Two runs over
the same seed produce byte-identical city files (verify: run twice, compare
sha256 -- the manifest's `generated_at` is the one wall-clock field, and it
lives only in the manifest, which is content-addressed by nothing).

UPLOAD. This script never touches credentials. It writes dist/upload.sh, which
authenticates to Tigris via a NAMED AWS CLI PROFILE (default `cypress-tigris`,
override with CYPRESS_TIGRIS_PROFILE) on every aws invocation -- never ambient
AWS_* environment variables. An explicit --profile makes the AWS CLI resolve
credentials from that profile alone; it does not fall back to env-var
credentials or the [default] profile in ~/.aws/credentials. That silent
fallback is what caused #248: with no AWS_* exported in the shell, the CLI
picked up the owner's unrelated AMAZON [default] keys and Tigris rejected them
mid-multipart-upload with InvalidAccessKeyId, twice in two days. Before
touching any object the script preflights the profile with one cheap
authenticated call and fails fast, naming the fix
(`aws configure --profile cypress-tigris`), if it cannot authenticate. Set the
profile up once from the bucket's keys (cypress-sync app secrets and the
owner's Tigris dashboard; see server/README.md). If you are an agent without
that profile configured: stop, hand dist/ and upload.sh to the orchestrator.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import sys
from datetime import datetime, timezone

# The seed schema generation this publisher understands. See VERSIONING above.
# Bump together with Fixtures/seed/schema.sql shape changes.
#
# 15 adds `species_trigrams`, the species-search similarity index (ERRATA E165),
# AND `id_spaces.short_name`, the hand-maintained civic short name (ERRATA
# E209/#233) -- folded into one generation because neither had published as of
# this writing (verified against the live manifest: both cities were still
# `schema_version: 14`), and R37.2 makes a generation number a publish event,
# not a code change; two unpublished additions are one bump, not two.
#
# `species_trigrams` is carried by the byte-copy like every other shared
# species table (R37.3): the publisher narrows `trees` and leaves `species`
# whole, and the trigram rows key on `species.id`, so a narrowed city file
# inherits the whole catalog's index and nothing has to be rebuilt per city.
#
# `id_spaces` is narrower still -- narrowed to the city's own row already
# (VERSIONING above), so `short_name` travels with it automatically and this
# publisher needed no change for the second addition, only this comment.
#
# 16 (task #237) drops `id_spaces.short_name` and adds `dim_city` -- the city
# dimension table `short_name` is absorbed into, joined through
# `id_spaces.city_id`. `build_city_file` below narrows `dim_city` to the one
# row this file's `id_spaces` row still references, the same shape as
# `id_spaces`/`inventories` above and for the same reason: a city file that
# carried another city's civic facts would be claiming an authority it does
# not have.
#
# 17 (the s17 round) adds `dim_region` -- the unit a pack is published in --
# and `trees.region_id`, a NOT NULL foreign key into it. `build_city_file`
# below narrows on THAT column instead of `id_space`, which is the whole
# reason the generation exists: RULING D1 makes New York's published unit the
# borough, and `id_space` cannot express a unit smaller than a city. San
# Francisco and San Jose are one `city`-level region each and publish
# unchanged in meaning (RULING D2: one shape everywhere, no NYC-only concept).
SEED_SCHEMA_VERSION = 17

# Manifest envelope format, for the app-side parser (#157). Bump on any change
# that would break a reader of the previous shape; additive keys do not bump it.
#
# 2 (the s17 round) is such a change, and R37.4's additive tolerance does NOT
# cover it: the UNIT'S MEANING changes. A format-1 reader shown a format-2
# manifest would install a borough believing it was a city -- it would read
# `id`, `display_name` and `tree_count` successfully and be wrong about all
# three. That is what a format bump is for.
MANIFEST_FORMAT = 2

# The format-1 envelope, still published beside it. See `MANIFEST_V1_NAME`.
LEGACY_MANIFEST_FORMAT = 1

# RULING D8 -- DUAL-PUBLISH FOR ONE RELEASE CYCLE, AND WHY THE OLD NAME IS THE
# OLD FORMAT RATHER THAN THE NEW ONE.
#
# `CityManifest.decode` refuses an unknown format outright, before reading
# anything else. That is correct -- guessing at a future format's meaning is how
# a reader silently mis-installs a file -- but it means the day format 2
# publishes at the path every shipped build already fetches, EVERY UNUPDATED
# INSTALL loses the whole Cities screen at once and shows "Couldn't check what's
# available." That is a self-inflicted outage on readers who did nothing.
#
# So `manifest.json` -- the path every existing build hard-codes -- keeps its
# format-1 shape and lists whole-city packs only, and format 2 publishes beside
# it under a new name that only a build that understands it asks for. An old
# install therefore keeps a working screen; the s17 files it lists are refused
# per-city as `needsNewerApp`, which is a truthful sentence about one city
# rather than a dead screen.
#
# The window is one release cycle, at which point the format-1 object stops
# being written. It costs a few kilobytes.
#
# R37.2 SAYS "ONLY manifest.json IS EVER REWRITTEN IN PLACE", AND THERE ARE NOW
# TWO SUCH OBJECTS. Worth stating plainly rather than letting the ruling quietly
# become inaccurate: the property R37.2 is protecting is that every object
# holding DATA is write-once and hash-verified, and that the mutable surface is
# small, enumerable, and carries no bytes a reader trusts without checking. That
# still holds -- both manifests are catalogues, neither is content-addressed by
# anything, and every file either one names is still immutable and still verified
# by sha256 before a byte is kept. What changed is the count, from one to two,
# for one release cycle.
#
# The ordering rule that follows from it is unchanged and is why `upload.sh`
# writes both manifests LAST: files upload before the manifest that names them.
MANIFEST_V2_NAME = "manifest-v2.json"
MANIFEST_V1_NAME = "manifest.json"

# Display names are civic facts, entered by hand on purpose: an id with no
# entry here fails the run loudly rather than shipping an invented or derived
# name (DECISIONS constraint 15 is about botanical/civic content invention).
#
# KEYED BY PACK ID SINCE s17, AND A PARENT CITY NEEDS ITS OWN ENTRY TOO. For a
# one-region city the two are one key -- `sf` is both the pack and the city, and
# this table is unchanged. New York will need six: one per borough pack, plus
# `us-ny-nyc` for the `region.parent_city_display_name` every borough entry
# carries.
#
# The agreement between these names and the seed's own `dim_region.display_name`
# is now CHECKED at publish (see `main`), which is what the note below asks for
# and previously only requested.
#
# DUPLICATION WITH THE SEED'S dim_city (task #237), evaluated and left alone.
# `Tools/build_seed.py`'s `DIM_CITY` now carries the same two display names
# (plus slug, state, county, and a source URL DISPLAY_NAMES has never carried)
# and this publisher could read `display_name` out of the fused seed's
# `dim_city` table instead of repeating it here. Left as its own dict because
# the two tools are separately owned by design (`Tools/build_seed.py`'s
# SHORT_CITY_NAMES carried the same independence, for the same reason, before
# task #237 absorbed it): a change to the seed's civic content should not
# silently reach into the publisher's manifest output on the next run, and a
# change to the manifest's display name should not require touching the seed
# schema author's file. If this drifts, the fix is to keep both hand-entries
# in sync, not to import one from the other.
DISPLAY_NAMES = {
    "sf": "San Francisco",
    "us-ca-sj": "San Jose",
    # New York's six, which is the count the note above predicted: five borough
    # PACK ids, plus the parent CITY id space `us-ny-nyc`, which is never a pack
    # and is here only because every borough entry carries
    # `region.parent_city_display_name` and that line indexes this table by
    # `id_space`. Removing the parent entry is what F1 of PR #108 caught, and the
    # guard in `main` now refuses the run before a pack is written rather than
    # raising `KeyError` with two packs already on disk.
    #
    # The five borough names agree with `build_seed.REGIONS`' `display_name`, and
    # that agreement is CHECKED at publish rather than maintained by care -- see
    # the drift check below. Both tables take the name from the City's own
    # boundary file (`boroname`), which is why this reads "Bronx".
    "us-ny-nyc": "New York City",
    "us-ny-nyc-manhattan": "Manhattan",
    "us-ny-nyc-brooklyn": "Brooklyn",
    "us-ny-nyc-queens": "Queens",
    "us-ny-nyc-bronx": "Bronx",
    "us-ny-nyc-si": "Staten Island",
}

# seed_meta keys that state a city's ship coverage. The v14-era ingest wrote
# per-city ad-hoc key names; these are those names, kept as a FALLBACK for files
# built before the s17 round. Absent key means full coverage.
#
# **THE STANDARDISED KEY IS `coverage_<id_space>` AND IT IS PREFERRED** --
# `Tools/build_seed.py` writes it as of s17, which is what R37's trailing clause
# asked for ("when a third city lands, `build_seed.py` should write
# `coverage_<id_space>` keys and the publisher's `COVERAGE_KEYS` shim retires").
#
# THIS SHIM WAS ALSO A LIVE DIVERGENCE, AND THAT IS THE DEFECT THIS ROUND CLOSES.
# `SeedCities.coverage` on the Swift side already preferred `coverage_<id_space>`
# and fell back to this table; this publisher read this table and ONLY this
# table. The two agreed about San Jose for exactly one reason -- nothing had ever
# written the standardised key -- so the first build that wrote it would have had
# the app's bundled row and the published manifest stating different coverage for
# the same city, with no error anywhere and nothing comparing them. `coverage_for`
# below now reads the two keys in the same order the app does, and
# `Tools/test_publish_cities.py` pins the orders together rather than trusting
# this comment.
COVERAGE_KEYS = {
    "us-ca-sj": "sj_ship_extent",
}


def coverage_for(space: str, fused_meta: dict[str, str]) -> str:
    """This city's shipped extent, or `"full"`.

    Two keys, in the order `SeedCities.coverage` reads them: the standardised
    `coverage_<id_space>` first, the legacy per-city name second. Keeping the
    orders identical is the point -- see `COVERAGE_KEYS` above.

    ── COVERAGE IS KEYED ON THE ID SPACE WHILE IDENTITY MOVED TO THE PACK ──────
    A deliberate divergence, raised by adversarial review (finding F9) and
    decided here rather than left to be noticed later.

    **What coverage means: how much of a CITY's inventory this publish shipped.**
    San Jose's `downtown` says the seed holds the central window and not the rest
    of San Jose. That is a fact about the city's corpus, not about any one pack,
    and every pack cut from that corpus inherits it -- which is why the key is
    the city's and each of its packs reports the same value.

    **Why not move it to the region.** For New York it would say the same thing
    five times: every borough pack ships all of its borough, so each is `full`
    and the fact they share is `us-ny-nyc` is fully covered. A per-region key
    would be five copies of one fact, five chances to disagree, and a second
    hand-maintained table for `SeedCities` to mirror -- the exact shape of the
    divergence this round just closed.

    **The condition that forces the move, stated so it is recognisable.** The day
    a city publishes SEVERAL regions and ships less than all of at least one of
    them, one key cannot describe them: `us-ca-sj` shipping `downtown` complete
    plus `north` partial has no single answer. That state is refused rather than
    guessed -- see the ambiguity check in `main` -- so it cannot ship quietly,
    and the refusal is what will make the move deliberate when it is needed.
    """
    for key in [f"coverage_{space}"] + (
        [COVERAGE_KEYS[space]] if space in COVERAGE_KEYS else []
    ):
        value = fused_meta.get(key)
        if value:
            return value
    return "full"


def fail(msg: str, code: int = 1) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def meta(con: sqlite3.Connection) -> dict[str, str]:
    return dict(con.execute("SELECT key, value FROM seed_meta"))


def content_rev_for(space: str, fused_meta: dict[str, str]) -> str:
    """Newest snapshot date among the city's own inventories.

    seed_meta carries inventory_<tag>_id_space and inventory_<tag>_snapshot_on
    pairs; pair them up by tag rather than assuming any fixed tag list.
    """
    dates = []
    for key, value in fused_meta.items():
        if key.startswith("inventory_") and key.endswith("_id_space") and value == space:
            tag = key[len("inventory_"):-len("_id_space")]
            snap = fused_meta.get(f"inventory_{tag}_snapshot_on")
            if snap:
                dates.append(snap)
    if not dates:
        fail(f"no inventory_*_snapshot_on in seed_meta for id_space {space!r}; "
             "cannot derive a content revision", 3)
    return max(dates)


def build_city_file(src: str, dest: str, region: dict) -> dict:
    """Copy the fused seed to dest, narrow it to one region, verify, and measure.

    Returns the measured facts for the manifest entry. Any failed check exits.

    ── s17: THIS NARROWS ON `region_id`, NOT ON `id_space` ──────────────────────
    The two are the same cut for a one-region city and are not the same cut for
    New York, which is the entire reason the generation exists. `region` is a
    row of `dim_region` as a dict: `id` (the rowid `trees.region_id` holds),
    `pack_id` (the published identity), `id_space` (the space it sits in).

    The id-space deletes below are kept and are NOT redundant: a pack must carry
    exactly its own region's rows AND exactly its own city's vocabulary, and
    narrowing on region alone would leave another city's `id_spaces` and
    `inventories` rows in the file. Every borough of New York is in one id space,
    so for NYC the region delete is the narrow one and the space delete is a
    no-op; for a hypothetical region spanning spaces they would disagree, and the
    per-region count check below is what would catch it.
    """
    space = region["id_space"]
    region_id = region["id"]
    pack = region["pack_id"]
    shutil.copyfile(src, dest)
    con = sqlite3.connect(dest)
    try:
        cur = con.cursor()

        # Refuse to sever a lineage link across regions. None exist today
        # (a site's replacement stands in the same place); if one ever does,
        # deleting silently would corrupt provenance.
        #
        # KEYED ON REGION SINCE s17, WHICH IS STRICTLY STRONGER. The old check
        # asked whether a link crossed an ID SPACE, and every borough of New York
        # is in one id space -- so a Queens tree whose predecessor stood in
        # Brooklyn passed it, and the delete below then severed the link.
        #
        # WHAT THAT COST WAS A DIAGNOSIS, NOT THE DATA. Review finding F3
        # corrected an earlier claim here that the severing was silent. It is
        # not: the severed link leaves `site_lineage` pointing at a deleted row,
        # and the `PRAGMA foreign_key_check` in this function's own verification
        # pass catches it and refuses the publish. Measured on the pre-fix code:
        #
        #   FAIL: us-ny-nyc-queens: foreign_key_check reported 1 violations,
        #         first: ('trees', 4, 'trees', 0)
        #
        # exit 1, nothing published. So the artifact was never in danger -- what
        # was missing is a message that says which tree and which link, instead
        # of a rowid pair the reader has to go and resolve by hand. Post-fix the
        # same seed gives `1 site_lineage links cross regions; splitting would
        # sever provenance -- stop and report`, before any delete runs.
        #
        # A cut is a cut at whatever granularity the cut is made, and this is now
        # made per region -- which is also the check that would still be needed
        # if the FK ever stopped covering it.
        (cross,) = cur.execute(
            "SELECT COUNT(*) FROM trees t JOIN trees p ON p.id = t.site_lineage "
            "WHERE t.region_id = ? AND p.region_id != ?", (region_id, region_id)).fetchone()
        if cross:
            fail(f"{pack}: {cross} site_lineage links cross regions; "
                 "splitting would sever provenance -- stop and report")

        cur.execute("DELETE FROM species_assertions WHERE tree_id IN "
                    "(SELECT id FROM trees WHERE region_id != ?)", (region_id,))
        cur.execute("DELETE FROM trees_rtree WHERE id IN "
                    "(SELECT id FROM trees WHERE region_id != ?)", (region_id,))
        cur.execute("DELETE FROM trees WHERE region_id != ?", (region_id,))
        cur.execute("DELETE FROM neighborhoods WHERE id NOT IN "
                    "(SELECT neighborhood_id FROM trees "
                    " WHERE neighborhood_id IS NOT NULL)")
        cur.execute("DELETE FROM inventories WHERE id_space != ?", (space,))
        cur.execute("DELETE FROM id_spaces WHERE id != ?", (space,))
        # dim_region narrowed to this pack's own row, the same reason and the
        # same shape as dim_city below: a pack carrying another region's civic
        # facts would be claiming an authority it does not have. BEFORE the
        # dim_city delete, because dim_region.city_id references it and the
        # subquery there reads the surviving id_spaces row.
        cur.execute("DELETE FROM dim_region WHERE id != ?", (region_id,))
        # dim_city AFTER id_spaces: narrowed to the one row the surviving
        # id_spaces row still references (task #237), the same reason
        # inventories/id_spaces above are narrowed to this city alone. The
        # ordering is load-bearing for the subquery below, which reads the
        # already-narrowed id_spaces. Nothing else enforces it: this
        # connection never enables `PRAGMA foreign_keys`, so the FK on
        # id_spaces.city_id refuses nothing here (measured in PR #33 review);
        # a wrong-order delete would surface only in the foreign_key_check
        # pass further down.
        cur.execute("DELETE FROM dim_city WHERE id NOT IN (SELECT city_id FROM id_spaces)")
        con.commit()

        fused_meta = meta(con)
        rev = content_rev_for(space, fused_meta)
        (count,) = cur.execute("SELECT COUNT(*) FROM trees").fetchone()
        if count == 0:
            fail(f"{pack}: zero trees survived the split")

        # The receipt keys that name THIS FILE, rewritten to the truth about it;
        # everything else in seed_meta stays the fused build receipt.
        #
        # `rows_from_<inventory>` JOINED THIS LIST WITH THE BOROUGH SPLIT, and the
        # reason it was not on it before is worth stating rather than fixing
        # silently. Every pack before New York held ALL of its inventory's rows --
        # one id space, one pack -- so the fused claim and the pack's own count
        # agreed by geometry, and `verify_seed` check 1b passed on every pack ever
        # built. A borough is the first pack that holds a strict SUBSET of an
        # inventory, and the Queens pack shipped claiming 898,643 rows from
        # `nyc_tree_points` while holding 298,839. Measured, before this fix:
        #
        #     [FAIL] 1b. per-inventory row counts match what seed_meta claims
        #            nyc_tree_points: 298,839 rows, seed_meta says 898,643
        #
        # It is the same argument `rows_kept` was already rewritten under -- a key
        # that says how much of something is in THIS FILE is a fact about this
        # file, not about the build that fed it. Counted from the pack's own
        # `trees` rather than derived from the fused number, because the split is
        # what decided it.
        rows_from = {
            f"rows_from_{inventory}": str(n)
            for inventory, n in cur.execute(
                "SELECT inventory_source, COUNT(*) FROM trees GROUP BY inventory_source"
            ).fetchall()
        }
        # A fused key for an inventory this pack holds NO rows from would otherwise
        # survive verbatim and overstate the pack by its whole corpus.
        for key in fused_meta:
            if key.startswith("rows_from_") and key not in rows_from:
                rows_from[key] = "0"
        rewrites = {
            "id_spaces_in_file": space,
            "rows_kept": str(count),
            "trees_snapshot_on": rev,
            **rows_from,
        }
        additions = {
            # `publish_city_id` keeps its name and its meaning -- the ID SPACE,
            # i.e. the city -- and `publish_pack_id` is the new, finer fact. They
            # are the same string for a one-region city and differ for a borough,
            # which is exactly why the existing key could not simply be
            # repurposed: something reading it expects a city.
            "publish_city_id": space,
            "publish_pack_id": pack,
            "publish_region_level": region["level"],
            "publish_schema_version": str(SEED_SCHEMA_VERSION),
            "publish_content_rev": rev,
            "publish_generator": "Tools/publish_cities.py",
            "publish_source_generated_at": fused_meta.get("generated_at", ""),
            "species_map_counts_scope":
                "fused build; tree_count spans all published cities",
        }
        for k, v in rewrites.items():
            cur.execute("UPDATE seed_meta SET value = ? WHERE key = ?", (v, k))
        for k, v in additions.items():
            cur.execute("INSERT OR REPLACE INTO seed_meta(key, value) VALUES (?, ?)",
                        (k, v))
        con.commit()
        con.execute("VACUUM")

        # ---- verify the artifact we just produced, not the plan for it ----
        fk = cur.execute("PRAGMA foreign_key_check").fetchall()
        if fk:
            fail(f"{pack}: foreign_key_check reported {len(fk)} violations, "
                 f"first: {fk[0]!r}")
        (integrity,) = cur.execute("PRAGMA integrity_check").fetchone()
        if integrity != "ok":
            fail(f"{pack}: integrity_check said {integrity!r}")
        (foreign_rows,) = cur.execute(
            "SELECT COUNT(*) FROM trees WHERE id_space != ?", (space,)).fetchone()
        if foreign_rows:
            fail(f"{pack}: {foreign_rows} foreign-space trees survived")
        # The region cut, asserted on the artifact. Strictly finer than the
        # id-space check above and the one that means anything for a borough:
        # every NYC pack passes the space check by construction.
        (foreign_region_rows,) = cur.execute(
            "SELECT COUNT(*) FROM trees WHERE region_id != ?", (region_id,)).fetchone()
        if foreign_region_rows:
            fail(f"{pack}: {foreign_region_rows} trees from another region survived")
        (regions_left,) = cur.execute("SELECT COUNT(*) FROM dim_region").fetchone()
        if regions_left != 1:
            fail(f"{pack}: {regions_left} dim_region rows survived, expected exactly 1")
        (rtree_count,) = cur.execute("SELECT COUNT(*) FROM trees_rtree").fetchone()
        if rtree_count != count:
            fail(f"{pack}: rtree has {rtree_count} entries for {count} trees")
        (orphan_assertions,) = cur.execute(
            "SELECT COUNT(*) FROM species_assertions sa "
            "LEFT JOIN trees t ON t.id = sa.tree_id WHERE t.id IS NULL").fetchone()
        if orphan_assertions:
            fail(f"{pack}: {orphan_assertions} orphaned species_assertions")

        bbox = cur.execute(
            "SELECT MIN(lat), MAX(lat), MIN(lon), MAX(lon) FROM trees").fetchone()
    finally:
        con.close()

    # One lookup, in the app's own key order -- see `coverage_for`.
    coverage = coverage_for(space, fused_meta)

    return {
        "tree_count": count,
        "content_rev": rev,
        "coverage": coverage,
        "bbox": {
            "min_lat": bbox[0], "max_lat": bbox[1],
            "min_lon": bbox[2], "max_lon": bbox[3],
        },
        "centroid": {
            "lat": round((bbox[0] + bbox[1]) / 2, 6),
            "lon": round((bbox[2] + bbox[3]) / 2, 6),
        },
        "fused_meta": fused_meta,
    }


def attribution_for(space: str, src_con: sqlite3.Connection,
                    fused_meta: dict[str, str]) -> list[dict]:
    """R36 binding consequence (b): published data carries its sources'
    attribution obligations. One entry per inventory in the city file."""
    out = []
    for inv_id, name, url in src_con.execute(
            "SELECT id, name, url FROM inventories WHERE id_space = ? ORDER BY id",
            (space,)):
        tag = inv_id  # seed_meta tags: inventory_<tag>_* where tag == inventories.id
        entry = {"inventory": inv_id, "name": name, "url": url}
        snap = fused_meta.get(f"inventory_{tag}_snapshot_on")
        if snap:
            entry["snapshot_on"] = snap
        license_ = fused_meta.get(f"inventory_{tag}_licence") or \
            fused_meta.get(f"inventory_{tag}_license")
        if license_:
            entry["license"] = license_
        out.append(entry)
    return out


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--db", default=os.path.join(repo_root, "Fixtures/seed/cypress-seed.sqlite"))
    ap.add_argument("--out", default=os.path.join(repo_root, "dist"))
    # Anonymous reads are served only on the bucket's dedicated public domain.
    # Tigris denies anonymous GET on the S3 API endpoints (fly.storage.tigris.dev,
    # t3.storage.dev) even when the bucket is public -- verified 2026-08-01.
    ap.add_argument("--base-url", default="https://cypress-cities.t3.tigrisbucket.io")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        fail(f"no seed at {args.db} -- run Tools/build_seed.py or "
             "Tools/setup_worktree.sh first", 3)

    src_con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)

    # THE FILE MUST BE A GENERATION THIS PUBLISHER WRITES. `dim_region` is what
    # s17 added and what everything below narrows on; an s16 seed has no such
    # table, and reaching the first query with a helpful message beats an
    # `OperationalError: no such table` three frames down.
    have_tables = {r[0] for r in src_con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'")}
    if "dim_region" not in have_tables:
        fail(f"{args.db} has no dim_region table, so it is a pre-s17 seed and this "
             f"publisher writes s{SEED_SCHEMA_VERSION}. Rebuild it with "
             f"Tools/build_seed.py.", 3)

    spaces = [r[0] for r in src_con.execute(
        "SELECT DISTINCT id_space FROM trees ORDER BY id_space")]
    declared = {r[0] for r in src_con.execute("SELECT id FROM id_spaces")}
    if not set(spaces) <= declared:
        fail(f"trees carry id_spaces {set(spaces) - declared} not declared "
             "in id_spaces", 3)

    # ---- the regions this file holds, which are the packs it will publish ----
    # Ordered by `id`, which is `dim_region`'s rowid and therefore the order
    # `Tools/build_seed.py` inserted them in. RULINGS R43 §2 makes the
    # publisher's order the display order, so this is a decision and not an
    # accident: regions appear as their city registered them.
    #
    # Joined through `id_spaces` rather than read off the region row, because
    # `dim_region.city_id` names a CITY and this publisher narrows and attributes
    # per ID SPACE. The two are one-to-one today; the join is what keeps this
    # correct rather than lucky if they ever are not.
    # ── dim_region IS READ WHOLE, THEN RESOLVED. NOT AN INNER JOIN. ──────────
    # This was `FROM dim_region r JOIN id_spaces s ON s.city_id = r.city_id`, and
    # an inner join here DROPS a region whose city has no `id_spaces` row instead
    # of reporting it (review finding F4). Both directions of that drop were
    # measured, and both are worse than a crash:
    #
    #   * the region HAS trees -> the orphan check below fired with
    #     `1 trees carry region_id(s) [3] that dim_region does not declare`,
    #     which is A FALSE STATEMENT ABOUT THE DATA. dim_region declares it
    #     perfectly well; the join dropped it. Anyone reading that message goes
    #     looking for a bad `region_id` on a tree and finds nothing wrong.
    #   * the region has NO trees -> exit 0, and the pack simply never publishes.
    #     A region the seed declares vanishes from the catalogue with no error
    #     anywhere, which is the silent-omission class this whole round is about.
    #
    # So the table is the authority for WHAT EXISTS, and the id space is looked
    # up afterwards where a failure to find one can be named.
    declared_regions = list(src_con.execute(
        "SELECT id, pack_id, display_name, level, city_id FROM dim_region ORDER BY id"))
    if not declared_regions:
        fail("dim_region is empty; the seed declares no publishable unit", 3)

    # city_id -> every id space in that city. A list, not a scalar: a city with
    # two id spaces is the ambiguity the guard below refuses, and collapsing it
    # here would hide it.
    spaces_by_city: dict = {}
    for space_id, city_id in src_con.execute("SELECT id, city_id FROM id_spaces"):
        spaces_by_city.setdefault(city_id, []).append(space_id)

    unresolved = [
        (pack, city_id) for _, pack, _, _, city_id in declared_regions
        if not spaces_by_city.get(city_id)
    ]
    if unresolved:
        fail(f"region(s) {[p for p, _ in unresolved]} name a dim_city "
             f"{sorted({c for _, c in unresolved})} that no id_spaces row points at, so this "
             f"publisher cannot tell which numbering their trees are drawn from. The regions "
             f"ARE declared -- this is not a bad region_id on a tree -- and publishing "
             f"without them would drop packs the seed declares.", 3)

    regions = [
        {"id": rid, "pack_id": pack, "display_name": name, "level": level,
         "id_space": spaces_by_city[city_id][0], "city_id": city_id}
        for rid, pack, name, level, city_id in declared_regions
    ]

    # A CITY WITH TWO ID SPACES HAS NO SINGLE ANSWER, so refuse rather than pick.
    # `dim_region.city_id` names a city while this publisher narrows and
    # attributes per id space; they are one-to-one today and nothing in the
    # schema says they must stay that way.
    #
    # Under the inner join this used to build, a second space MULTIPLIED the
    # region -- two packs at one `pack_id`, the second overwriting the first's
    # object at an immutable path R37.2 promises is written once. The resolution
    # above takes `spaces_by_city[...][0]`, which cannot multiply, so the hazard
    # is now silent selection rather than duplication: it would publish a pack
    # attributed to whichever space sorted first. Both are wrong and this refuses
    # both. Kept as an explicit check rather than left to the count arithmetic,
    # which fires late and blames the split for losing rows.
    doubled = {
        region["pack_id"]: sorted(spaces_by_city[region["city_id"]])
        for region in regions if len(spaces_by_city[region["city_id"]]) > 1
    }
    if doubled:
        fail(f"region(s) {sorted(doubled)} resolve to several id spaces {doubled} -- a region "
             f"belongs to one city and this publisher narrows per id space, so a city with two "
             f"spaces has no single answer. Stop and report: this needs a decision, not a "
             f"default.", 3)

    fused_counts = dict(src_con.execute(
        "SELECT region_id, COUNT(*) FROM trees GROUP BY region_id"))
    (fused_total,) = src_con.execute("SELECT COUNT(*) FROM trees").fetchone()
    fused_meta_src = meta(src_con)
    # Hashed once, up front: it is both the manifest's source_seed receipt and (R60) the
    # build_id inside every version string, and those two must never disagree.
    source_seed_sha = sha256_of(args.db)

    # EVERY REGION THAT HOLDS ROWS MUST BE PUBLISHED, AND EVERY PUBLISHED REGION
    # MUST HOLD ROWS. `trees.region_id` is NOT NULL, so a row cannot be in no
    # region -- but a region the seed registered and then put nothing in would
    # publish as an empty pack, and a region holding rows that this loop skipped
    # would drop them silently. The total check further down catches the second;
    # this catches both, by name, before anything is written.
    region_ids = {r["id"] for r in regions}
    orphan_counts = {rid: n for rid, n in fused_counts.items() if rid not in region_ids}
    if orphan_counts:
        fail(f"{sum(orphan_counts.values())} trees carry region_id(s) "
             f"{sorted(orphan_counts)} that dim_region does not declare", 3)
    empty = [r["pack_id"] for r in regions if not fused_counts.get(r["id"])]
    if empty:
        fail(f"region(s) {empty} are declared but hold no trees; an empty pack is "
             f"a download that buys a reader nothing", 3)

    # EVERY NAME THIS RUN WILL INDEX, CHECKED BEFORE A SINGLE PACK IS WRITTEN.
    #
    # TWO KINDS OF KEY, AND CHECKING ONLY ONE OF THEM WAS A REVIEW FINDING (F1).
    # Before s17 this guard read `[s for s in spaces if s not in DISPLAY_NAMES]`
    # -- it checked ID SPACES, because an id space was the only thing a pack
    # could be. The s17 rewrite changed it to check PACK IDS and dropped the id
    # space half, but `parent_city_display_name` in the entry below still indexes
    # `DISPLAY_NAMES[space]`. Measured on a fixture whose boroughs are all
    # registered and whose parent city is not: `KeyError: 'us-ny-nyc'`, raised
    # from inside the build loop **after two packs had already been written to
    # disk** -- an uncaught traceback rather than a `fail()`, so no diagnosis and
    # a half-populated output tree.
    #
    # A guard that runs before the loop is worth nothing if it does not cover
    # every key the loop will index. Both sets are collected from the data and
    # checked together, so adding a third kind of name to an entry cannot quietly
    # escape this.
    needed_names = {r["pack_id"] for r in regions} | {r["id_space"] for r in regions}
    # F9's ambiguity, refused rather than guessed. `coverage` describes how much
    # of a CITY shipped and every pack of that city inherits it, which is exact
    # while a partial city has ONE region and while a multi-region city ships all
    # of each. The state it cannot describe is both at once: several regions in
    # one id space AND a coverage that is not `full`. Then "how much of this pack
    # shipped" has no single answer and the entries would all repeat a value that
    # is true of none of them.
    #
    # This is the trigger for moving coverage onto `dim_region`, and it is a stop
    # rather than a default so that the move is made deliberately by whoever
    # first needs it -- with the seed in front of them -- instead of being
    # discovered afterwards in a manifest that quietly mis-described five packs.
    regions_per_space: dict = {}
    for region in regions:
        regions_per_space.setdefault(region["id_space"], []).append(region["pack_id"])
    ambiguous = {
        space: sorted(packs) for space, packs in regions_per_space.items()
        if len(packs) > 1 and coverage_for(space, fused_meta_src) != "full"
    }
    if ambiguous:
        detail = "; ".join(
            f"{space} ships {coverage_for(space, fused_meta_src)!r} across packs {packs}"
            for space, packs in sorted(ambiguous.items())
        )
        fail(f"coverage is stated per id space and cannot describe these: {detail}. Every pack "
             f"of a city inherits its coverage, which is exact only while a partial city has one "
             f"region. This seed has several AND ships part of the city, so one value would be "
             f"true of no pack. Move coverage onto dim_region -- see `coverage_for` -- rather "
             f"than publishing a number that describes none of them.", 3)

    missing = sorted(name for name in needed_names if name not in DISPLAY_NAMES)
    if missing:
        packs = sorted(r["pack_id"] for r in regions)
        fail(f"no display name for {missing}; add them to DISPLAY_NAMES -- names are "
             f"entered, never derived. NOTE that a pack's PARENT CITY needs an entry of "
             f"its own as well as the pack: this run publishes packs {packs} whose parent "
             f"id space(s) are {sorted({r['id_space'] for r in regions})}", 3)

    # THE DUPLICATION `DISPLAY_NAMES` DELIBERATELY KEEPS, NOW CHECKED RATHER THAN
    # ASKED FOR. Its comment says the two hand-entered copies are separately
    # owned by design and that "if this drifts, the fix is to keep both
    # hand-entries in sync". That instruction had no instrument behind it: a
    # drift produced a manifest naming a pack one thing and the file inside it
    # naming itself another, and nothing looked. Independence of ownership does
    # not require silence about disagreement.
    drifted = [
        f"{r['pack_id']}: manifest {DISPLAY_NAMES[r['pack_id']]!r} vs "
        f"dim_region {r['display_name']!r}"
        for r in regions if DISPLAY_NAMES[r["pack_id"]] != r["display_name"]
    ]
    if drifted:
        fail("DISPLAY_NAMES disagrees with the seed's own dim_region.display_name -- "
             + "; ".join(drifted), 3)

    cities_dir = os.path.join(args.out, "cities")
    if os.path.isdir(cities_dir):
        shutil.rmtree(cities_dir)
    os.makedirs(cities_dir, exist_ok=True)

    # The build's own identity, derived from the source seed rather than the clock (R60).
    # Computed once: it is a property of the input, shared by every city in this run.
    build_id = source_seed_sha[:8]

    entries = []
    for region in regions:
        pack = region["pack_id"]
        space = region["id_space"]
        rev_preview = content_rev_for(space, fused_meta_src)
        version = f"s{SEED_SCHEMA_VERSION}-r{rev_preview}-{build_id}"
        # PATHS ARE KEYED ON THE PACK, NOT THE ID SPACE, and this is the only
        # shape that can hold five boroughs of one id space.
        #
        # For a one-region city the PACK SEGMENT is unchanged -- `cities/sf/...`
        # is the same `sf` it has always been, and that is the part R37.2's
        # immutability is about, because it is the install key and the directory
        # every existing object already sits under. The VERSION segment does
        # move, from `s16-...` to `s17-...`: a generation bump is a new version
        # and therefore a new immutable path BY DESIGN, which is exactly what
        # R37.2 provides for. So the path is not byte-identical and is not
        # supposed to be; what must not change is the id under which a reader
        # already has this city installed.
        rel_path = f"cities/{pack}/{version}/{pack}.sqlite"
        dest = os.path.join(args.out, rel_path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        print(f"building {rel_path} ...")
        facts = build_city_file(args.db, dest, region)
        if facts["content_rev"] != rev_preview:
            fail(f"{pack}: content_rev drifted during the build")
        if facts["tree_count"] != fused_counts[region["id"]]:
            fail(f"{pack}: split kept {facts['tree_count']} trees but the fused "
                 f"seed holds {fused_counts[region['id']]} for this region")

        size = os.path.getsize(dest)
        digest = sha256_of(dest)
        print(f"  {facts['tree_count']:>7} trees  {size / 1e6:7.1f} MB  sha256 {digest[:16]}...")

        entries.append({
            "id": pack,
            "display_name": DISPLAY_NAMES[pack],
            "coverage": facts["coverage"],
            # ---- format 2's addition: the entry's region identity ----------
            # A pack is no longer necessarily a city, so an entry has to say what
            # it is. Three facts, exactly as §6.3 scopes them: the level, the
            # parent city, and the bbox the entry already carried.
            #
            # `parent_city` is the ID SPACE, which is what `publish_city_id`
            # inside the file says and what the app's install/attach path already
            # speaks. For a one-region city it equals `id`; for a borough it does
            # not, and a reader that wants to know which city a pack belongs to
            # has no other way to ask.
            "region": {
                "level": region["level"],
                "parent_city": space,
                "parent_city_display_name": DISPLAY_NAMES[space],
            },
            "bbox": facts["bbox"],
            "centroid": facts["centroid"],
            "tree_count": facts["tree_count"],
            "schema_version": SEED_SCHEMA_VERSION,
            "content_rev": facts["content_rev"],
            "version": version,
            "path": rel_path,
            "bytes": size,
            "sha256": digest,
            "attribution": attribution_for(space, src_con, facts["fused_meta"]),
        })

    total_split = sum(e["tree_count"] for e in entries)
    if total_split != fused_total:
        fail(f"per-region counts sum to {total_split}, fused seed holds {fused_total}")

    # ── The fused seed itself, published as a build input (task #196) ──────────────────
    # The per-city files above are what the APP downloads at runtime. This is what a
    # BUILD needs: the ~103 MB fused seed that ships inside the bundle, which is
    # git-ignored (it is a reproducible build product) and therefore absent from a fresh
    # CI checkout -- without it 13 tests fail on `seedURL -> nil` and the app ships empty.
    #
    # Published under the build_id rather than a fixed name, for R60's reason: two seeds
    # that declare the same generated_at can still differ byte for byte, so a fixed
    # "latest" path would be the same trap this ticket's parent (#197) was.
    # CI resolves it from this manifest and verifies sha256 before trusting the bytes.
    seed_rel = f"seed/{build_id}/cypress-seed.sqlite"
    seed_dest = os.path.join(args.out, seed_rel)
    os.makedirs(os.path.dirname(seed_dest), exist_ok=True)
    print(f"copying {seed_rel} ...")
    shutil.copyfile(args.db, seed_dest)
    seed_bytes = os.path.getsize(seed_dest)
    # Re-hash the COPY, not the source: this asserts the bytes that will be uploaded,
    # which is the whole point of publishing a hash beside a file.
    seed_copy_sha = sha256_of(seed_dest)
    if seed_copy_sha != source_seed_sha:
        fail(f"the seed copy hashes {seed_copy_sha[:16]} but the source hashed "
             f"{source_seed_sha[:16]}; refusing to publish a hash that does not "
             "describe the file beside it")
    print(f"          {seed_bytes / 1e6:7.1f} MB  sha256 {seed_copy_sha[:16]}...")

    envelope = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "Tools/publish_cities.py",
        "base_url_hint": args.base_url,
        "source_seed": {
            "generated_at": fused_meta_src.get("generated_at", ""),
            "tree_count": fused_total,
            "sha256": source_seed_sha,
            "build_id": build_id,
            "path": seed_rel,
            "bytes": seed_bytes,
        },
    }

    manifest = {"manifest_format": MANIFEST_FORMAT, **envelope, "cities": entries}

    # ---- RULING D8's second object: the format-1 manifest, whole cities only --
    # `city`-level packs and nothing else. A format-1 reader has no concept of a
    # region, so listing a borough to it would be handing it something it would
    # confidently mis-describe -- it would draw "Queens" as a city with its own
    # civic identity. Filtering is the whole of what makes the old format still
    # TRUE rather than merely still parseable.
    #
    # The entries are otherwise unchanged, `region` key included: a format-1
    # reader ignores keys it does not know (R37.4), so carrying it costs nothing
    # and removing it would mean maintaining two entry shapes.
    legacy_entries = [e for e in entries if e["region"]["level"] == "city"]
    if not legacy_entries:
        fail("no city-level pack to publish in the format-1 manifest; RULING D8 "
             "requires unupdated installs keep a working catalogue")
    legacy_manifest = {
        "manifest_format": LEGACY_MANIFEST_FORMAT, **envelope, "cities": legacy_entries,
    }

    manifest_path = os.path.join(args.out, MANIFEST_V2_NAME)
    legacy_path = os.path.join(args.out, MANIFEST_V1_NAME)
    for path, doc in ((manifest_path, manifest), (legacy_path, legacy_manifest)):
        with open(path, "w") as f:
            json.dump(doc, f, indent=2, sort_keys=False)
            f.write("\n")

    # ---- verify each manifest against the files it describes ----
    # Both of them, read back off disk. The format-1 object is a smaller list of
    # the same entries, and "it is a subset so it must be fine" is exactly the
    # reasoning that stops being true the day the filter above gains a condition.
    for path in (manifest_path, legacy_path):
        with open(path) as f:
            readback = json.load(f)
        name = os.path.basename(path)
        for entry in readback["cities"]:
            full = os.path.join(args.out, entry["path"])
            if sha256_of(full) != entry["sha256"]:
                fail(f"{name}: {entry['id']}: manifest sha256 does not match the file")
            if os.path.getsize(full) != entry["bytes"]:
                fail(f"{name}: {entry['id']}: manifest byte size does not match the file")

    # Uploads every pack, not just the ones the format-1 list names -- the
    # objects have to exist before either manifest names them.
    upload_sh = write_upload_sh(args.out, entries, seed_rel,
                                manifests=(MANIFEST_V2_NAME, MANIFEST_V1_NAME))

    print(f"\nmanifest: {manifest_path}  (format {MANIFEST_FORMAT}, "
          f"{len(entries)} pack(s))")
    print(f"          {legacy_path}  (format {LEGACY_MANIFEST_FORMAT}, "
          f"{len(legacy_entries)} whole-city pack(s), RULING D8)")
    print(f"upload:   {upload_sh}  (run only with the CYPRESS_TIGRIS_PROFILE / "
          "cypress-tigris AWS profile configured)")
    print("OK")


def write_upload_sh(out_dir: str, entries: list[dict], seed_rel: str,
                    manifests: tuple = (MANIFEST_V2_NAME, MANIFEST_V1_NAME)) -> str:
    """Write dist/upload.sh. Pulled out of main() so it can be exercised (and
    red-proofed -- #248) against synthetic entries without rebuilding the seed.

    `manifests` is every manifest object to upload and verify. RULING D8 puts two
    of them in the bucket for one release cycle; both are mutable objects that
    must land AFTER the immutable files they name, which is the ordering below.
    """
    upload_sh = os.path.join(out_dir, "upload.sh")
    with open(upload_sh, "w") as f:
        f.write("#!/bin/sh\n")
        f.write("# Generated by Tools/publish_cities.py. Authenticates via a NAMED AWS\n")
        f.write("# CLI PROFILE, never ambient AWS_* environment variables (#248: an\n")
        f.write("# unset AWS_* pair silently fell back to the owner's [default]\n")
        f.write("# ~/.aws/credentials profile -- unrelated AMAZON keys -- and Tigris\n")
        f.write("# rejected them mid-multipart-upload with InvalidAccessKeyId, twice in\n")
        f.write("# two days). An explicit --profile on every aws command below makes the\n")
        f.write("# CLI resolve credentials from that profile ONLY; it will not fall back\n")
        f.write("# to env-var credentials or [default]. This is the load-bearing property\n")
        f.write("# of this script. Set the profile up once (keys from the Tigris\n")
        f.write("# dashboard -- see server/README.md):\n")
        f.write("#   aws configure --profile cypress-tigris\n")
        f.write("# Override the profile name with CYPRESS_TIGRIS_PROFILE. Never commit\n")
        f.write("# this environment anywhere.\n")
        f.write("set -eu\n")
        f.write('cd "$(dirname "$0")"\n')
        f.write('PROFILE="${CYPRESS_TIGRIS_PROFILE:-cypress-tigris}"\n')
        f.write("ENDPOINT=https://fly.storage.tigris.dev\n")
        f.write("BUCKET=s3://cypress-cities\n")
        f.write("PUBLIC=https://cypress-cities.t3.tigrisbucket.io\n")
        f.write("\n")
        f.write("# PREFLIGHT. Prove the named profile can authenticate against Tigris\n")
        f.write("# before any upload is attempted -- a cheap authenticated call (list the\n")
        f.write("# bucket), capped so a hung network doesn't hang the whole publish.\n")
        f.write("# --profile is what makes this trustworthy: it is the same flag every\n")
        f.write("# command below carries, so a preflight pass means the uploads that\n")
        f.write("# follow resolve credentials the identical way.\n")
        f.write('PREFLIGHT_ERR="$(mktemp)"\n')
        f.write('if ! aws s3 ls "$BUCKET" --endpoint-url "$ENDPOINT" --profile "$PROFILE" '
                '\\\n')
        f.write('        --cli-connect-timeout 5 --cli-read-timeout 10 \\\n')
        f.write('        >/dev/null 2>"$PREFLIGHT_ERR"; then\n')
        f.write('  if grep -q "could not be found" "$PREFLIGHT_ERR"; then\n')
        f.write('    echo "FAIL: AWS CLI profile '"'"'$PROFILE'"'"' does not exist." >&2\n')
        f.write('    echo "  Create it once with:" >&2\n')
        f.write('    echo "    aws configure --profile cypress-tigris" >&2\n')
        f.write('  else\n')
        f.write('    echo "FAIL: profile '"'"'$PROFILE'"'"' could not authenticate against '
                '$BUCKET." >&2\n')
        f.write('    echo "  Its stored keys are most likely stale or wrong for Tigris." '
                '>&2\n')
        f.write('    echo "  Re-run:" >&2\n')
        f.write('    echo "    aws configure --profile cypress-tigris" >&2\n')
        f.write('  fi\n')
        f.write('  echo "  (keys from the Tigris dashboard -- see server/README.md)." >&2\n')
        f.write('  echo "  Override the profile name with CYPRESS_TIGRIS_PROFILE=<name>." '
                '>&2\n')
        f.write('  echo "--- aws error ---" >&2\n')
        f.write('  cat "$PREFLIGHT_ERR" >&2\n')
        f.write('  rm -f "$PREFLIGHT_ERR"\n')
        f.write('  exit 1\n')
        f.write('fi\n')
        f.write('rm -f "$PREFLIGHT_ERR"\n')
        f.write("\n")
        for entry in entries:
            f.write(f'aws s3 cp "{entry["path"]}" "$BUCKET/{entry["path"]}" '
                    f'--endpoint-url "$ENDPOINT" --profile "$PROFILE"\n')
        f.write(f'aws s3 cp "{seed_rel}" "$BUCKET/{seed_rel}" '
                f'--endpoint-url "$ENDPOINT" --profile "$PROFILE"\n')
        # LAST, and in this order. R37.2: files upload before the manifest that
        # names them. With two manifests the newest format goes first, so the
        # window in which a format-2 reader can see a catalogue that a format-1
        # reader cannot is the shorter of the two possible windows.
        for name in manifests:
            f.write(f'aws s3 cp {name} "$BUCKET/{name}" '
                    '--endpoint-url "$ENDPOINT" --profile "$PROFILE" '
                    '--content-type application/json\n')
        f.write("# Verify anonymous READ (GET, not HEAD: Tigris has returned\n")
        f.write("# HEAD 200 alongside GET 403). One-byte range GETs on the\n")
        f.write("# public domain; -f fails the script on any non-2xx.\n")
        for entry in entries:
            f.write(f'curl -fsS -r 0-0 -o /dev/null "$PUBLIC/{entry["path"]}"\n')
        f.write(f'curl -fsS -r 0-0 -o /dev/null "$PUBLIC/{seed_rel}"\n')
        for name in manifests:
            f.write(f'curl -fsS "$PUBLIC/{name}" | cmp - {name}\n')
        f.write('echo "anonymous GET verified on $PUBLIC"\n')
    os.chmod(upload_sh, 0o755)
    return upload_sh


if __name__ == "__main__":
    main()
