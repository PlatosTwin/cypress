#!/usr/bin/env python3
"""
build_seed.py -- build the Cypress on-device seed SQLite database from DataSF.

Implements BUILD-PLAN.md section 7 (Ingest spec, DataSF) against the schema of
section 4, adapted to SQLite-on-device (no PostGIS).

Sources (verified live 2026-07-21; the city layer 2026-07-26):
  trees          DataSF "Street Tree List"        dataset id tkzw-k3nq
                 https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD
                 (the id `tuvn-fjcn` quoted in BUILD-PLAN 7 returns HTTP 404)
  city layer     SF Public Works' OWN street-tree inventory, the one drawn by
                 https://bsm.sfdpw.org/urbanforestry/ -- BUF_Street_Trees layer 3.
                 Cached to Fixtures/raw/ by Tools/fetch_city_trees.py; this script
                 never talks to the service. See `load_city_layer`.
  neighborhoods  DataSF "Analysis Neighborhoods"  dataset id j2bu-swwd
                 (the commonly cited p5b7-5n3h is a map visualisation whose
                  backing tabular view is j2bu-swwd; only the tabular view
                  serves geometry over SODA)
                 https://data.sfgov.org/resource/j2bu-swwd.geojson?$limit=200
  species        Fixtures/species/leaf_retention.yaml  family + leaf retention,
                 one entry per mapped species, cited or null
                 Fixtures/species/curated.yaml         the authored field guide
                 for the top 40 SF species (BUILD-PLAN 8)

Determinism. The seed is a build product and the repo treats it as
byte-for-byte reproducible (.gitignore says so). Every timestamp therefore
comes from SEED_EPOCH, never from the wall clock, and every derived table is
written in a sorted or file order. Two runs over the same inputs produce the
same sha256.

THE INGEST CONTRACT. Every inventory this script reads is filtered through
`InventoryRecord` (`Tools/inventory_contract.py`) by an adapter
(`Tools/inventory_adapters.py`). Read the contract first; this file is one
consumer of it. What lives where:

  the adapter    its source's field names, units, date formats, the value that
                 means "not recorded", the convention for packing two facts into
                 one column, and dropping records with no usable position.
  this file      the seed's own rules -- identity, the bounding box, uniqueness
                 of a source ref, the species catalogue, the DBH ladder, the
                 neighbourhood stamp, and which `trees.status` a record kind
                 becomes (`STATUS_FOR_KIND`).

Nothing upstream-specific survives past an adapter, which is the whole point:
before this split, whatever `emit()` happened to accept was the contract, and
what it happened to accept was DataSF's shape.

Identity model (two keys, on purpose):
  trees.id    INTEGER PRIMARY KEY -- internal join key. Every foreign key and
              index uses it; this is where the on-device size savings come from.
  trees.uuid  TEXT NOT NULL UNIQUE -- the stable, citable external identity
              required by DECISIONS.md constraint 13. Derived as

                  uuid5(NS_TREE, ID_SPACES[<space>].identity_prefix + <source id>)

              so a rebuild reproduces byte-identical uuids and a tree's public
              URL never changes.

              QUALIFIED BY ID SPACE, NOT BY SOURCE. An id space is the numbering
              scheme record ids are drawn from. San Francisco's two inventories
              are ONE space on purpose -- they publish the same TreeID numbering,
              and their uuids colliding is what made the DataSF -> city switch
              reversible with zero uuids moved over 130,070 shared records
              (E156). A second CITY declares its own space and its own frozen
              prefix, so its TreeID 276198 cannot mint the uuid of
              `1 TWIN PEAKS BLVD`. `sf`'s prefix is the empty string and is
              FROZEN: 145,837 shipped uuids are derived with no prefix.

              Still source-unsafe and not fixed here: `trees.external_ref` is
              `INTEGER UNIQUE`, a global constraint on a source-local id, so two
              id spaces cannot be inserted into one seed until it is widened.

TWO INVENTORIES, ONE FLAG. `--source` picks which of San Francisco's two
street-tree inventories the seed is built from:

    --source city     SF Public Works' own operational layer, the one its public
                      map at bsm.sfdpw.org/urbanforestry draws -- 133,577 rows,
                      every living tree in the seed -- PLUS the DataSF export's
                      12,260 vacant planting sites, which the layer has no
                      category for and therefore no opinion about. ~145,837 rows.
                      THE DEFAULT, per issue #91: our map is supposed to agree
                      with the city's map.
    --source datasf   The DataSF open-data export `tkzw-k3nq`. ~195,309 rows.
                      What shipped before #91, kept working and kept tested.

THERE IS NO THIRD VALUE, AND THE VACANT SITES ARE NOT ONE. A `--source` value
answers "which inventory does this seed believe about the trees", and on that the
two possible answers are the city's layer and the export. The export's vacant
sites are not a third answer to that question: they are rows about *sites*, and
the city's layer publishes no site records at all, so no build that wants a
working "where a tree could go" can decline them and no build that has them is
disagreeing with the city about anything. A `city-no-sites` flag would only ever
be selected by somebody reproducing a measurement in an errata entry, and the
cost of it is a third path to test forever. `--source city` means what it says
now; the numbers it used to produce are in ERRATA E156, in the paragraph reading
"This is what `--source city` means now, not a third flag value."

Both paths are live and both are tested. Reverting to the export is one command:

    python3 Tools/build_seed.py --source datasf
    cp Fixtures/seed/cypress-seed.sqlite Cypress/Resources/cypress-seed.sqlite

See docs/investigations/city-tree-source.md for what changes when you do.

**trees.uuid does not move between the two.** Both derive it as
uuid5(NS_TREE, <TreeID as ASCII>), and the two sources use the same TreeID
space (verified over 130,070 shared ids, median coordinate disagreement 0.04 m),
so a tree present in both keeps one identity across the switch and back.

Usage:
    python3 Tools/build_seed.py [--source city|datasf] [--fetch] [--with-city-raw]
                                [--repo-root PATH] [--limit N]

    --source          which inventory to build from (default: city)
    --fetch           re-download the raw files before building. For --source city
                      this is Tools/fetch_city_trees.py's job, not this script's --
                      run it separately, politely, once.
    --with-city-raw   populate trees.city_raw with the DataSF passthrough JSON.
                      Off by default: it costs ~74 MB (~380 bytes/row) and is
                      fully regenerable from Fixtures/raw/street_tree_list.csv.
                      Meaningless under --source city, which has no CSV.
    --limit           build from only the first N source rows (smoke tests)

Exit codes:
    0  seed built and all row rules satisfied
    2  stub-path share exceeded the 2% ceiling (BUILD-PLAN 7) -- nothing shipped
    3  a required input was missing or unreachable
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sqlite3
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from typing import Optional

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

TREES_DATASET_ID = "tkzw-k3nq"
TREES_CSV_URL = (
    f"https://data.sfgov.org/api/views/{TREES_DATASET_ID}/rows.csv?accessType=DOWNLOAD"
)
NEIGHBORHOODS_DATASET_ID = "j2bu-swwd"
NEIGHBORHOODS_GEOJSON_URL = (
    f"https://data.sfgov.org/resource/{NEIGHBORHOODS_DATASET_ID}.geojson?$limit=200"
)

# The city's own inventory, cached by Tools/fetch_city_trees.py. This script only
# ever reads the cache; it never touches the service, so a rebuild costs the city
# nothing and is offline-reproducible.
CITY_LAYER_SERVICE = (
    "https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/"
    "BUF_Street_Trees/FeatureServer/3"
)
CITY_LAYER_MAP_URL = "https://bsm.sfdpw.org/urbanforestry/"
CITY_NDJSON_NAME = "city_street_trees.ndjson"
CITY_META_NAME = "city_street_trees.meta.json"

SOURCES = ("city", "datasf")
DEFAULT_SOURCE = "city"

# How much of San Jose goes in. `none` is San Francisco alone, which is what
# every existing test and every previous build means. See `SJ_SHIP_WINDOW` for
# why `downtown` exists and why it is a window rather than a sample.
SJ_EXTENTS = ("none", "downtown", "full")

# San Francisco bounding box used to reject null-island rows, state-plane
# leakage and out-of-county geocodes. Deliberately a little generous: it spans
# Ocean Beach / Lands End in the west (-122.514) to Hunters Point (-122.348) and
# Treasure Island (37.832) in the north-east, down to the Daly City county line
# (~37.708). It intentionally EXCLUDES the Farallon Islands (~-123.00), which
# are legally part of the City and County but carry no street trees.
SF_BBOX = {
    "min_lat": 37.6900,
    "max_lat": 37.8500,
    "min_lon": -122.5400,
    "max_lon": -122.3300,
}

# San Jose's own extent, on the same job: reject null-island rows, state-plane
# leakage and anything the layer serves that is not San Jose. Generous enough to
# hold the whole incorporated city (Alviso in the north at ~37.43, Coyote Valley
# in the south at ~37.16, Alum Rock in the east at ~-121.75, and the west edge
# against Campbell/Saratoga at ~-122.06).
#
# IT IS ALSO THE E172 CHECK IN THE BUILD RATHER THAN ONLY IN THE FETCH. Santa
# Monica's datastore serves Springfield, Illinois at offset 0; an ingest whose
# only geography check ran in the downloader would have one place to fail rather
# than two.
SJ_BBOX = {
    "min_lat": 37.1000,
    "max_lat": 37.5000,
    "min_lon": -122.1000,
    "max_lon": -121.6500,
}

# New York City's own extent, on the same job: reject null-island rows,
# projection leakage and anything Socrata serves that is not New York City.
#
# MEASURED, NOT GUESSED. Across the full 1,121,106-row Tree Points extract and
# the 1,084,845-row Planting Spaces extract (2026-08-14) both datasets occupy
# exactly lat [40.49668, 40.91419], lon [-74.25499, -73.69808] -- Tottenville
# at the south end of Staten Island to the north edge of the Bronx, and the
# Staten Island west shore to the eastern edge of Queens. The box below pads
# that to the nearest sensible bound and holds every row in both extracts, with
# zero rows outside it.
#
# IT IS ALSO THE E172 CHECK IN THE BUILD RATHER THAN ONLY IN THE FETCH, for the
# same reason San Jose's is: an ingest whose only geography check runs in the
# downloader has one place to fail rather than two. It catches, specifically, a
# `POINT (lon lat)` parsed in the wrong order -- WKT puts longitude first, and a
# swapped NYC pair lands at (-73.9, 40.9), which is off West Africa and outside
# this box by a wide margin.
NYC_BBOX = {
    "min_lat": 40.45,
    "max_lat": 40.95,
    "min_lon": -74.30,
    "max_lon": -73.65,
}

# The admission box for each id space. `accepts()` reads this rather than
# SF_BBOX: a bounding box is a fact about a city, and applying San Francisco's to
# San Jose's rows would reject all 344,879 of them without a word.
BBOX_BY_ID_SPACE = {
    "sf": SF_BBOX,
    "us-ca-sj": SJ_BBOX,
    "us-ny-nyc": NYC_BBOX,
}

# `--source` names one of SAN FRANCISCO'S two inventories and is unchanged; the
# `inventories.id` those two rows carry gained an `sf_` prefix in the v14 pass
# (E169: `city` is a poor identifier once there is more than one city). Prefixing
# the flag as well would make it say the city twice.
SF_INVENTORY_FOR_SOURCE = {"city": "sf_city", "datasf": "sf_datasf"}

# The San Jose cache written by `Tools/fetch_san_jose_trees.py`. As with the SF
# city layer, this script only ever READS the cache; it never touches the
# service, so a rebuild costs San Jose nothing.
SJ_NDJSON = "sj_street_trees.ndjson"
SJ_META = "sj_street_trees.meta.json"

# The checked-in species-string map, ONE FILE PER ID SPACE. A species string is a
# publisher's own spelling, so two publishers' strings do not belong in one file
# named after one of them. `sf_species_map.csv` is the historical name and stays.
SPECIES_MAP_FILES = {
    "sf": "sf_species_map.csv",
    "us-ca-sj": "sj_species_map.csv",
    "us-ny-nyc": "nyc_species_map.csv",
}

# ---------------------------------------------------------------------------
# WHAT SHIPS TO A PHONE, WHICH IS NOT WHAT IS INGESTED
# ---------------------------------------------------------------------------
# San Jose is 344,879 records against San Francisco's 145,837. Ingesting all of
# them is the point of the contract and costs nothing but build time. SHIPPING
# all of them is a different decision with a different unit: the seed is a file
# inside the .app, it is already 78 MB for San Francisco alone (~535 bytes/row),
# and San Jose entire would add roughly 185 MB for a total near 265 MB. That is
# past Apple's cellular-download ceiling and unreasonable for a local beta.
#
# So a subset ships, and WHICH KIND of subset is the whole decision:
#
#   * NOT a random sample. A 1-in-4 sample looks fine in aggregate and is a lie
#     at the grain the app actually operates at: somebody standing on a street
#     sees three of the four trees in front of them missing, with no way to tell
#     a sampled-out tree from one the city never listed. The map's implicit
#     promise is "every tree on this block".
#   * NOT trees-only. 75,886 of San Jose's records are vacant sites and
#     `VACANTSITE` is the entire reason this source was chosen (E172); dropping
#     them would throw away the finding.
#   * A CONTIGUOUS GEOGRAPHIC WINDOW, complete inside it. Within the window the
#     inventory is whole -- every tree, every planting site, every stump the city
#     lists. Outside it there is nothing at all, which is a visible, explainable
#     absence rather than an invisible dilution. A beta tester walks blocks, not
#     counties.
#
# The window is central San Jose: downtown, SoFA, Japantown, Naglee Park, the
# Alameda, the north end of Willow Glen, and Roosevelt Park. Bounds are stated
# here, in the build, so the shipped file's own extent is a checked-in fact
# rather than something to be measured off the database afterwards.
SJ_SHIP_WINDOW = {
    "min_lat": 37.3050,
    "max_lat": 37.3700,
    "min_lon": -121.9300,
    "max_lon": -121.8550,
}


def load_nyc_layers(cache_dir: str):
    """`<cache>/{tree_points,planting_spaces}.csv` -> (tree points, spaces, meta).

    Cache-only, exactly like `load_city_layer` and `load_san_jose_layer`: the
    fetch is `Tools/fetch_nyc_trees.py`'s job and is run separately, politely,
    once. The cache lives OUTSIDE the repo -- it is ~430 MB across the two
    extracts, against the 38 sample rows in `Fixtures/raw/nyc/` -- so unlike the
    other two sources its location is a required argument rather than a
    convention.

    Returns the planting spaces as {GlobalID -> row}. `fetch_nyc_trees.py` has
    already dropped the 6,864 whole-row duplicates and verified they agreed.
    """
    tree_points_path = os.path.join(cache_dir, "tree_points.csv")
    spaces_path = os.path.join(cache_dir, "planting_spaces.csv")
    meta_path = os.path.join(cache_dir, "nyc_fetch.meta.json")
    if not os.path.exists(tree_points_path) or not os.path.exists(spaces_path):
        die(
            f"{cache_dir} does not hold both NYC extracts. Run:\n"
            f"    python3 Tools/fetch_nyc_trees.py --cache-dir {cache_dir} --verify\n"
            f"It pages both Socrata datasets sequentially and caches them; a page "
            f"already on disk is never re-fetched."
        )

    def read(path):
        with open(path, "r", encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                lat, lon = _nyc_parse_point(row.get("location"))
                row["lat"], row["lon"] = lat, lon
                yield row

    tree_points = list(read(tree_points_path))
    spaces = {}
    for row in read(spaces_path):
        key = (row.get("globalid") or "").strip()
        if key:
            spaces[key] = row
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as fh:
            meta = json.load(fh)
    return tree_points, spaces, meta


def _nyc_parse_point(raw):
    """A Socrata CSV point cell -> (lat, lon). WKT is `POINT (lon lat)`.

    Longitude first, which is the opposite of the order every other field in
    this pipeline uses. A swapped pair puts every NYC tree in Antarctica and
    nothing downstream would say so, which is why `fetch_nyc_trees.py` bounds-
    checks the PARSED values rather than the raw string.
    """
    text = (raw or "").strip()
    if not text.upper().startswith("POINT"):
        return None, None
    inside = text[text.find("(") + 1: text.rfind(")")].strip()
    parts = inside.split()
    if len(parts) != 2:
        return None, None
    try:
        lon, lat = float(parts[0]), float(parts[1])
    except ValueError:
        return None, None
    return lat, lon


def load_san_jose_layer(raw_dir: str):
    """`Fixtures/raw/sj_street_trees.{ndjson,meta.json}` -> (features, meta).

    Cache-only, exactly like `load_city_layer`: the fetch is
    `Tools/fetch_san_jose_trees.py`'s job and is run separately, politely, once.
    If the cache is absent the build stops and says how to make it, rather than
    quietly building a seed with no San Jose in it.
    """
    ndjson_path = os.path.join(raw_dir, SJ_NDJSON)
    meta_path = os.path.join(raw_dir, SJ_META)
    if not os.path.exists(ndjson_path):
        die(
            f"{ndjson_path} is absent. Run:\n"
            f"    python3 Tools/fetch_san_jose_trees.py --verify\n"
            f"It pages San Jose's public layer sequentially and caches it; a page "
            f"already on disk is never re-fetched."
        )
    features = []
    with open(ndjson_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                features.append(json.loads(line))
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as fh:
            meta = json.load(fh)
    written = meta.get("rows_written")
    if written is not None and written != len(features):
        die(
            f"{SJ_META} says {written} rows and {SJ_NDJSON} holds {len(features)}; "
            f"the cache is inconsistent. Re-run Tools/fetch_san_jose_trees.py."
        )
    log(f"san jose cache: {len(features):,} features, extracted "
        f"{meta.get('extracted_on', 'unknown')}")
    return features, meta

# ---------------------------------------------------------------------------
# The ingest contract, and the per-source adapters that satisfy it
# ---------------------------------------------------------------------------
# Everything that used to live here as a module-level constant -- the qSpecies
# placeholder vocabulary, the non-taxon list, the DataSF column mapping -- was a
# statement about ONE upstream's spelling habits sitting in the shared ingest
# core, where the next city would have inherited it by default. It now lives in
# `Tools/inventory_adapters.py`, behind `Tools/inventory_contract.py`.
#
# Read `inventory_contract.py` first: it is the contract, and this file is one
# consumer of it.
#
# The names are re-exported because `Tools/validate_species.py` imports two of
# them from here and because the schema comments below still cite them.
from inventory_contract import (  # noqa: E402
    CONDITION_ALIVE,
    CONDITION_DEAD,
    CONDITION_DECLINING,
    CONDITION_REMOVED,
    CONDITIONS,
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    ID_SPACES,
    INVENTORIES,
    KindBasis,
    require_inventory,
)
from inventory_adapters import (  # noqa: E402
    CITY_RECORD_COLUMNS,
    INCH_TO_CM,
    MAPPED_COLUMNS,
    MERGED_SPECIES_NAMES,
    NON_TAXON_SPECIES,
    PLACEHOLDER_SPECIES,
    QSPECIES_NAME_CORRECTIONS,
    RETIRED_SPECIES_NAMES,
    SFCityLayerAdapter,
    SFDataSFAdapter,
    BoroughResolver,
    NYCTreePointAdapter,
    SanJoseStreetTreeAdapter,
    normalise_species_key,
    parse_qspecies,
)

# WHICH `trees.status` A CONTRACT RECORD BECOMES. The one place the seed's own
# vocabulary meets the contract's, and therefore the one place task #94 has to
# change.
#
# `KIND_NOT_A_TREE` has no status of its own. The seed's CHECK constraint permits
# alive / declining / dead_reported / removed / vacant_site, and none of those
# means "the source says the thing growing here is a shrub". So the records whose
# source said exactly that become `alive` -- 85 under `--source city`, 312 under
# `--source datasf`. They are counted under `records_not_a_tree` in the build
# receipt, and that count is the size of half of #94. This mapping is deliberately
# a dict rather than an `if`: the fact has somewhere to be, the seed cannot yet
# hold it, and that mismatch is visible in one line instead of being absent from
# the code entirely.
#
# ── s17: THIS USED TO BE `STATUS_FOR_KIND`, A DICT KEYED ON `kind` ALONE ───────
# That shape was itself a defect, and `feat/nyc-ingest` is what found it: keyed
# on `kind`, NO ADAPTER COULD EVER SHIP A ROW AS ANYTHING BUT `alive` OR
# `vacant_site`. NYC Parks publishes `TPCondition`, 10,635 of its rows are a
# `Full` structure in `Dead` condition -- a tree still standing over a pavement,
# which is exactly what RULINGS R19 defines `dead_reported` to mean -- and the
# ingest had nowhere to put it but a free-text `permit_notes` string.
#
# The survey (`docs/investigations/nyc-street-trees.md` §6) recorded this as a
# missing seed value and was WRONG about it; the branch's own correction block
# says so. `trees.status` has permitted `dead_reported` since before any of this.
# The gap was here, in the lookup, and closing it is a Python contract change
# rather than a migration -- which is why RULING D17 could keep the s17
# generation's identity resting on the region column instead.
#
# `condition is None` -- no claim -- maps exactly where `kind` alone used to,
# so San Francisco and San Jose, whose sources publish no condition field, do
# not move a single row. That is asserted, not assumed: see
# `Tools/test_build_seed_status.py` and the rebuild receipt in the PR body.
STATUS_FOR_CONDITION = {
    CONDITION_ALIVE: "alive",
    CONDITION_DECLINING: "declining",
    CONDITION_DEAD: "dead_reported",
    CONDITION_REMOVED: "removed",
}

#: What a record with no condition claim becomes, per kind -- the pre-s17
#: behaviour, preserved exactly.
STATUS_FOR_KIND_WITHOUT_CONDITION = {
    KIND_TREE: "alive",
    KIND_PLANTING_SITE: "vacant_site",
    KIND_NOT_A_TREE: "alive",
}


# THE `trees` INSERT COLUMN LIST, DECLARED ONCE (review finding F5a).
#
# It used to be built inside `flush` while `REGION_ROW_INDEX` was a hand-written
# `6` up here, which made the two a pair of literals that had to be kept in step
# by care. That is the shape this file's own comments warn about: an off-by-one
# writes region ids into `lat`, and SQLite accepts it silently because both are
# numbers. Now there is ONE list and the index is DERIVED from it, so they cannot
# disagree -- `emit` cannot put the placeholder somewhere the INSERT does not
# expect it, because there is no second place to put it.
#
# Rows stay LISTS, deliberately, and this was measured rather than assumed: at
# New York's ~898,000 rows a dict per row costs about 3.9x the memory and 5.9x
# the build time, against 1.7 microseconds paid once for the `.index()` below.
# The derived index plus the assertion in `flush` buys the same safety for
# nothing.
TREE_COLUMNS: tuple = (
    "id", "uuid", "id_space", "external_ref", "source", "inventory_source",
    "region_id", "lat", "lon", "address", "site_type", "neighborhood_id",
    "status", "species_current", "planted_year", "planted_on",
    "dbh_city_cm_min", "dbh_city_cm_max", "site_lineage", "verification_state",
    *(name for name, _ in CITY_RECORD_COLUMNS),
    "city_raw", "created_at", "updated_at", "deleted_at",
)

#: Where the region placeholder sits in a `tree_rows` row. DERIVED from
#: `TREE_COLUMNS`, never written down twice.
REGION_ROW_INDEX = TREE_COLUMNS.index("region_id")


def resolve_region_ids(tree_rows: list, region_id_by_key: dict) -> None:
    """Rewrite each row's `(id_space, source region name)` to a `dim_region.id`.

    In place, because `tree_rows` holds ~200,000 lists and the
    case-normalisation pass already rewrites columns inside them the same way.

    Fails loudly on a key it cannot place. That is the whole reason this is a
    lookup with a raise instead of a `.get(..., None)`: `trees.region_id` is NOT
    NULL precisely so a row cannot end up in no pack, and silently defaulting
    here would reintroduce exactly what the constraint forbids.
    """
    unplaceable: dict = {}
    for row in tree_rows:
        key = row[REGION_ROW_INDEX]
        region_id = region_id_by_key.get(key)
        if region_id is None:
            unplaceable[key] = unplaceable.get(key, 0) + 1
            continue
        row[REGION_ROW_INDEX] = region_id
    if unplaceable:
        detail = "; ".join(
            f"{count:,} row(s) in id space {space!r} naming region {name!r}"
            for (space, name), count in sorted(unplaceable.items(), key=lambda kv: str(kv[0]))
        )
        die(
            f"no dim_region row for {detail}. A region is entered in REGIONS, never derived "
            f"(DECISIONS constraint 15) -- and a `None` region resolves to the id space's SOLE "
            f"region, so this also fires when a space has several and an adapter did not say "
            f"which. Shipping these rows would put them in no published pack at all."
        )


def status_for_record(kind: str, condition: Optional[str]) -> str:
    """The seed's `trees.status` for one contract record.

    Total over `KINDS x (CONDITIONS + {None})`; the one combination that cannot
    mean anything -- a planting site in a condition -- is refused by
    `InventoryRecord.validate` before it can reach here, and refused again below
    so this function is not merely correct by someone else's care.
    """
    if kind == KIND_PLANTING_SITE:
        if condition is not None:
            raise ValueError(
                f"planting site with condition {condition!r}: an empty site has nothing in "
                f"it to be in a condition. The contract forbids this pair; reaching it here "
                f"means a record bypassed InventoryRecord.validate"
            )
        return STATUS_FOR_KIND_WITHOUT_CONDITION[KIND_PLANTING_SITE]
    if condition is None:
        return STATUS_FOR_KIND_WITHOUT_CONDITION[kind]
    if condition not in STATUS_FOR_CONDITION:
        raise ValueError(f"condition {condition!r} is not one of {CONDITIONS}")
    return STATUS_FOR_CONDITION[condition]


# ---------------------------------------------------------------------------
# dim_city (task #237)
# ---------------------------------------------------------------------------
# The city dimension table's rows, keyed by `ID_SPACES` id. Hand-entered on
# purpose, the same instrument `SHORT_CITY_NAMES` (task #233, now absorbed
# here as `display_name`) and `Tools/publish_cities.py`'s `DISPLAY_NAMES` used
# before it -- civic content (DECISIONS constraint 15) is entered, never
# derived or guessed. A contributing id space with no entry here fails the
# build loudly (see the dim_city insert below) rather than shipping a blank
# past the schema's own `CHECK`s.
#
# `slug` is the "us-ca-sf" convention -- never `id_spaces.id` (frozen internal
# identity plumbing; see the dim_city CREATE TABLE comment). `state` is the
# postal abbreviation ("CA"), not the full name -- flagged for owner sign-off
# in the PR that introduced this table.
#
# Every `urban_forestry_url` was fetched live and confirmed to resolve to the
# named page (2026-08-05) before being entered here:
#   sf        https://sfpublicworks.org/streettreesf
#             "StreetTreeSF | Public Works" -- San Francisco Public Works'
#             Bureau of Urban Forestry program page.
#   us-ca-sj  https://www.sanjoseca.gov/your-government/departments-offices/
#             transportation/forestry
#             "Forestry | City of San José" -- the City of San José's Forestry
#             program page (Trees & Landscaping, Transportation department).
DIM_CITY: dict[str, dict[str, str]] = {
    "sf": {
        "slug": "us-ca-sf",
        "display_name": "San Francisco",
        "state": "CA",
        "county": "San Francisco",
        "urban_forestry_url": "https://sfpublicworks.org/streettreesf",
    },
    "us-ca-sj": {
        "slug": "us-ca-sj",
        "display_name": "San Jose",
        "state": "CA",
        "county": "Santa Clara",
        "urban_forestry_url": (
            "https://www.sanjoseca.gov/your-government/departments-offices/"
            "transportation/forestry"
        ),
    },
    # NEEDS OWNER SIGN-OFF ON TWO FIELDS, and they are flagged rather than guessed.
    #
    # `urban_forestry_url` is the DEPARTMENT home page, not a forestry program
    # page like the other two, because no forestry program page could be
    # confirmed to resolve on 2026-08-14. Fetched and checked that day:
    #   https://www.nyc.gov/parks                     200, redirects to
    #       https://www.nyc.gov/html/dpr/home.html, title "New York City
    #       Department of Parks & Recreation"  <- entered
    #   .../site/parks/services/forestry.page         404
    #   .../site/parks/services/trees.page            404
    #   .../site/parks/services/street-tree-planting.page  404
    #   .../site/parks/trees-and-nature/street-trees.page  404
    #   https://www.nycgovparks.org/trees             403 from CloudFront to a
    #       non-browser agent. NOT retried with a spoofed agent: that is bot
    #       detection and working around it is not something this build does.
    #
    # `county` is the harder one. New York City is five counties (New York,
    # Kings, Queens, Bronx, Richmond) and this column holds ONE string, so
    # unlike SF (coterminous) and San Jose (Santa Clara) there is no true
    # answer. "New York City" is entered as the least wrong option -- it names
    # the jurisdiction the data actually comes from -- and it is deliberately
    # NOT one of the five county names, because picking one would be a false
    # civic claim about the other four. If a borough-partitioned distribution
    # lands, this column is the natural place for the borough and that is a
    # schema question, not one this build may answer.
    "us-ny-nyc": {
        "slug": "us-ny-nyc",
        "display_name": "New York City",
        "state": "NY",
        "county": "New York City",
        "urban_forestry_url": "https://www.nyc.gov/parks",
    },
}


# ---------------------------------------------------------------------------
# dim_region (s17) -- the unit a pack is published in
# ---------------------------------------------------------------------------
# WHY THIS TABLE EXISTS AT ALL, WHICH IS THE WHOLE OF WHAT MAKES 16 -> 17 A
# GENERATION. `Tools/publish_cities.py` has always narrowed the fused seed on
# `id_space` and shipped the result as a city. RULING D1 makes New York's
# published unit the BOROUGH, so the publisher needs something finer than
# `id_space` to narrow on, and a borough needs somewhere to keep its own name.
#
# It could not ride `trees.city_raw`. That column's family renders on the tree
# profile through `CityRecordPresentation`, whose `caretaker` label reads
# "Cared for by ..." -- and *Cared for by Queens* is a sentence the app would be
# shipping to a reader as fact. `feat/nyc-ingest` reached exactly this wall,
# carried borough in `raw_json` as a deliberate placeholder, and named a real
# `trees.region` column as the honest destination without taking the decision
# (RULING D17 then took it). This is that column.
#
# ── The three columns, and why each is entered rather than derived ────────────
# `pack_id` IS FROZEN AND IT IS DISTRIBUTION IDENTITY, NOT CIVIC CONTENT. It is
# simultaneously the manifest entry's `id`, the `<id>` in R37.2's immutable
# object path `cities/<id>/<version>/<id>.sqlite`, and the install key on a
# reader's device. `sf` and `us-ca-sj` are frozen at the values the format-1
# manifest has already published: changing either orphans every installed copy
# and breaks paths that R37.2 promises never move. **A new region's pack_id is
# chosen once, here, by a human, and never again.** This is why
# `InventoryRecord.region` carries the source's own word instead -- an adapter
# reading a data file is the wrong layer to be minting a permanent identity.
#
# `display_name` is civic content and is entered (DECISIONS constraint 15). For
# a one-region city it repeats `DIM_CITY[space]["display_name"]`, and it repeats
# it rather than joining to it because the two answer different questions: one
# names the city a tree is in, the other names the pack a reader downloaded, and
# NYC is about to make them different strings for the same row.
#
# `level` is the vocabulary RULING D2 requires -- one shape everywhere, no
# NYC-only concept. San Francisco is a `city`-level region of itself; that is
# not a special case, it is the general case with one member.
#
# `source_names` maps what an adapter passes as `InventoryRecord.region` onto
# this row. Empty tuple means "this id space's sole region", which is what a
# record's `region=None` resolves to.
REGION_LEVELS = ("city", "borough", "extent")

REGIONS: dict[str, list[dict]] = {
    "sf": [
        {
            "pack_id": "sf",
            "display_name": "San Francisco",
            "level": "city",
            "source_names": (),
        },
    ],
    "us-ca-sj": [
        {
            # FROZEN as `us-ca-sj` -- the published path and install key, not the
            # `us-ca-sj` slug in DIM_CITY that happens to read the same. They are
            # separate facts that currently agree; `sf` is the pair that does not
            # (pack `sf`, slug `us-ca-sf`), which is why they are separate columns.
            "pack_id": "us-ca-sj",
            "display_name": "San Jose",
            # `city`, not `extent`, and the distinction is worth stating because
            # San Jose ships only its downtown window. LEVEL DESCRIBES THE UNIT,
            # COVERAGE DESCRIBES HOW MUCH OF IT SHIPPED -- they are different
            # facts and conflating them is what the `coverage` key is for. San
            # Jose is a whole city of which part shipped, and its manifest entry
            # says exactly that: level `city`, coverage `downtown`.
            "level": "city",
            "source_names": (),
        },
    ],
    # ── New York City: five borough-level regions in one id space ────────────
    # RULING D1 makes the borough the published unit, which is the reason
    # `dim_region` exists at all. This is the first id space with more than one
    # region, so it is also the first place where the two consequences below are
    # load-bearing rather than theoretical.
    #
    # `pack_id` IS FROZEN HERE AND NOW. Each becomes `cities/<id>/<version>/…`
    # under R37.2's write-once path rule and the install key on every reader's
    # device, so these five strings can never change once a byte is published.
    # They follow the shape `us-ca-sj` already set: the id space, then the unit.
    #
    # `source_names` holds NYC's OWN word for each borough, and it is a tuple
    # because two independent producers must both land on this row:
    #   * Forestry Planting Spaces' `boroughcode` column, for a tree point that
    #     joined a planting space; and
    #   * `Fixtures/nyc_survey/borough_boundaries.geojson`'s `boroname`, which
    #     `BoroughResolver` returns for the ~22,995 that joined none (D18).
    # Measured, not assumed: both vocabularies are the same five bare,
    # title-case strings, so ONE name per row is correct and a second spelling
    # would be an invention. `NYCTreePointAdapter._borough_for` returns exactly
    # one of these and `InventoryRecord.region` carries it here unchanged.
    #
    # `display_name` is civic content (DECISIONS constraint 15) and is taken
    # from the City's own boundary file's `boroname`, not composed: that is why
    # this table says "Bronx" rather than "The Bronx" -- the City writes
    # "Bronx" in both of the two vocabularies above, and preferring the
    # colloquially-correct article here would be this file inventing a civic
    # name it was not given.
    #
    # NOTE THAT `(us-ny-nyc, None)` IS NOT REGISTERED, and that is the point.
    # `sole` is False for a space with five regions, so a record arriving with
    # `region=None` finds no key and `resolve_region_ids` stops with the count.
    # That stop is what ENFORCES D18's point-in-polygon orphan assignment rather
    # than trusting the ingest to have run it; see the block comment there.
    "us-ny-nyc": [
        {
            "pack_id": "us-ny-nyc-manhattan",
            "display_name": "Manhattan",
            "level": "borough",
            "source_names": ("Manhattan",),
        },
        {
            "pack_id": "us-ny-nyc-brooklyn",
            "display_name": "Brooklyn",
            "level": "borough",
            "source_names": ("Brooklyn",),
        },
        {
            "pack_id": "us-ny-nyc-queens",
            "display_name": "Queens",
            "level": "borough",
            "source_names": ("Queens",),
        },
        {
            "pack_id": "us-ny-nyc-bronx",
            "display_name": "Bronx",
            "level": "borough",
            "source_names": ("Bronx",),
        },
        {
            # `-si`, not `-staten-island`, following the only precedent the repo
            # has: `Tools/test_publish_cities.py`'s fixture, written by the s17
            # round and reviewed with it. Flagged for confirmation before the
            # first publish freezes it -- see this round's PR body.
            "pack_id": "us-ny-nyc-si",
            "display_name": "Staten Island",
            "level": "borough",
            "source_names": ("Staten Island",),
        },
    ],
}


# ---------------------------------------------------------------------------
# Case normalisation (issue #95)
# ---------------------------------------------------------------------------
# The seed columns whose values the APP COMPARES AGAINST A LITERAL, and which are
# therefore normalised to one spelling per case-folded value at ingest.
#
# The bug: `PlantType` held 'Tree' 194,988 times and 'tree' 3 times (TreeIDs
# 253212, 253634, 96598), so `WHERE plant_type = 'Tree'` silently dropped three
# rows and `CityRecordPresentation.plantTypeTree` had to case-fold by hand to see
# them. That is not a tidiness complaint: a closed vocabulary that holds two
# spellings of one value is a filter that lies, and it lies quietly.
#
# The previous comment here argued the opposite -- that correcting the case would
# be "editing the city's record to make it tidier, which is not this file's job".
# It is this file's job, for these columns only, because these are the columns the
# app matches on: `LandContext.inferred(from:)` reads legal_status and caretaker,
# `CityRecordCopy.agencyGlossary` keys on caretaker, and
# `CityRecordCopy.pruneOptOutStatus` compares legal_status to a literal.
#
# WHAT IS DELIBERATELY NOT NORMALISED, with today's counts, so the exclusion is a
# stated decision rather than an oversight:
#   address       87,388 distinct values, 2,277 case-variant groups
#                 ('1 Church St' / '1 CHURCH ST'). Free text, never compared,
#                 shown as the city wrote it. Case-folding it would also have to
#                 pick between 'McAllister St' (146) and 'MCALLISTER ST' (37) --
#                 the city writes both -- and one of those is a real spelling.
#   plot_size     588 distinct, 61 case-variant groups ('10x10' / '10X10'). Shown
#                 verbatim and never parsed; see the schema comment.
#   permit_notes  35,623 distinct, 2 case-variant groups. A key into a permitting
#                 system, not a vocabulary.
# The seed contract asserts the absence of case-variant duplicates over the
# normalised columns and NOT over these three, and says so.
NORMALISED_SEED_COLUMNS = [
    "legal_status", "caretaker", "care_assistant", "plant_type", "site_type",
]


def canonical_case_map(counts: dict) -> dict:
    """{observed value: count} -> {observed value: the spelling to store}.

    The winner of a case-variant group is the commonest spelling; ties break
    lexicographically, so the map is a pure function of the input and a rebuild
    reproduces it. Values with no variant map to themselves.
    """
    groups = {}
    for value, count in counts.items():
        groups.setdefault(" ".join(value.lower().split()), []).append((value, count))
    mapping = {}
    for variants in groups.values():
        winner = sorted(variants, key=lambda vc: (-vc[1], vc[0]))[0][0]
        for value, _ in variants:
            mapping[value] = winner
    return mapping




# The DataSF columns the city's own layer does not publish, which are carried across
# for the records both inventories list. See `load_datasf_attributes`.
ENRICHED_COLUMNS = (
    "qLegalStatus", "qSiteInfo", "qCaretaker", "qCareAssistant",
    "PlantDate", "PlotSize", "PermitNotes",
)


def load_datasf_attributes(csv_path: str) -> dict:
    """`Fixtures/raw/street_tree_list.csv` -> {TreeID: {column: value}}, seven columns.

    WHY THE CITY BUILD READS THE EXPORT AT ALL.

    #91 is about *which trees exist*: our map is supposed to draw what the city's
    own map draws, and only SF Public Works' operational layer knows that. It is
    not about which facts we hold, and on that the layer is much the poorer of the
    two -- it publishes sixteen fields against the export's eighteen and drops
    nine of them, including every planting date.

    Taking the row set from one and those nine columns from the other is not a
    compromise between two answers; it is two different questions answered by
    whichever source knows. The spine is the city's layer: a record it does not
    list is not in the seed, whatever the export says about it. The attributes are
    the export's, for the 130,070 records both list, because for those records the
    two are describing the same tree -- verified over that whole intersection at a
    median coordinate disagreement of 0.04 m.

    What this does NOT do: add a row. A TreeID in the export and not in the layer
    stays out, which is the entire point of the switch. The 3,507 records only the
    city has simply carry NULL in these seven columns, and `seed_meta` says how
    many.

    Dropping this join would cost, measurably: no planting dates at all, so screen
    12's elder, plantings and coverage rows are empty for the whole city and
    `LandContext.inferred(from:)` can place no tree, so the `Stands on` sentence
    never draws. That was measured on a build without it.
    """
    index = {}
    with open(csv_path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        missing = set(ENRICHED_COLUMNS) - set(reader.fieldnames or [])
        if missing:
            die(f"the DataSF export is missing {sorted(missing)}; the city build carries "
                f"those columns across and cannot silently ship without them")
        for row in reader:
            ref = (row.get("TreeID") or "").strip()
            if not ref or ref in index:
                continue
            index[ref] = {column: (row.get(column) or "").strip() or None
                          for column in ENRICHED_COLUMNS}
    return index


def load_city_layer(raw_dir: str):
    """Fixtures/raw/city_street_trees.{ndjson,meta.json} -> (rows, meta).

    Written by `Tools/fetch_city_trees.py`, which is the only thing in this repo
    that talks to the city's server. If the cache is absent the build stops and
    says so rather than fetching 67 pages as a side effect of a seed rebuild.
    """
    ndjson_path = os.path.join(raw_dir, CITY_NDJSON_NAME)
    meta_path = os.path.join(raw_dir, CITY_META_NAME)
    for path in (ndjson_path, meta_path):
        if not os.path.exists(path):
            die(f"missing {path}. Build it once with:\n"
                f"    python3 Tools/fetch_city_trees.py\n"
                f"It pages the city's public layer sequentially and caches it; this "
                f"script never touches the service itself.")
    with open(meta_path, "r", encoding="utf-8") as fh:
        meta = json.load(fh)
    rows = []
    with open(ndjson_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    if meta.get("rows_written") != len(rows):
        die(f"{CITY_NDJSON_NAME} holds {len(rows)} rows but its meta says "
            f"{meta.get('rows_written')}; the cache is inconsistent. Re-run "
            f"Tools/fetch_city_trees.py.")
    if not meta.get("extracted_on"):
        die(f"{CITY_META_NAME} carries no extraction date. A snapshot with no date "
            f"is the thing that made 'is our data stale' unanswerable last time.")
    # TREEID is the join key with DataSF and therefore with every existing uuid.
    # A null or duplicate one is not something to paper over.
    seen = set()
    for row in rows:
        key = row.get("TREEID")
        if key is None:
            die(f"{CITY_NDJSON_NAME} holds a feature with no TREEID")
        if key in seen:
            die(f"{CITY_NDJSON_NAME} holds TREEID {key} twice")
        seen.add(key)
    # Sorted by TREEID so integer tree ids are a pure function of the cache.
    rows.sort(key=lambda r: r["TREEID"])
    return rows, meta

# ---------------------------------------------------------------------------
# UUIDv5 namespaces. THESE ARE FROZEN CONSTANTS -- changing one silently
# rewrites every public tree URL and breaks every citation in the wild.
# ---------------------------------------------------------------------------
# trees.uuid   = uuid5(NS_TREE, <id-space prefix> + <the source's own id, as ASCII>)
#                For San Francisco the prefix is the empty string and the seed
#                string is the bare TreeID, which is what all 145,837 shipped
#                uuids are derived from. See ID_SPACES in inventory_contract.py --
#                the prefix, not this namespace, is what keeps a second city out.
# species.uuid = uuid5(NS_SPECIES, <lowercased, whitespace-collapsed scientific name>)
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")
NS_SPECIES = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0002")

STUB_CEILING_PCT = 2.0
DBH_BUCKET_CM = 5.0

# Every created_at / updated_at in the seed, and the build receipt's own
# generated_at. FROZEN, and deliberately not the wall clock: the seed is a build
# product the repo declares byte-for-byte reproducible, and a clock reading in
# 195,309 rows makes every rebuild a different file for no gain. The value is
# the DataSF Street Tree List snapshot date (ERRATA E1), which is what these
# rows are actually as-of. Override with SOURCE_DATE_EPOCH when rebuilding from
# a newer download.
SEED_EPOCH_DEFAULT = "2026-07-20T00:00:00+00:00"


def _seed_epoch() -> str:
    raw = os.environ.get("SOURCE_DATE_EPOCH", "").strip()
    if not raw:
        return SEED_EPOCH_DEFAULT
    try:
        seconds = int(raw)
    except ValueError:
        die(f"SOURCE_DATE_EPOCH must be an integer number of seconds, got {raw!r}")
    return datetime.fromtimestamp(seconds, timezone.utc).replace(microsecond=0).isoformat()


# --------------------------------------------------------------------------
# Schema (also written out to Fixtures/seed/schema.sql as the GRDB contract)
# --------------------------------------------------------------------------

SCHEMA_SQL = r"""
-- Cypress on-device seed schema.
--
-- Generated by Tools/build_seed.py. This file is the CONTRACT between the
-- ingest tooling and the app's GRDB layer: field names track BUILD-PLAN.md
-- section 4 as closely as SQLite allows. Deviations from section 4, all forced
-- by the absence of PostGIS on device or by on-device size limits, are called
-- out inline.
--
-- Timestamps are ISO-8601 UTC strings. Booleans are 0/1 INTEGERs. jsonb columns
-- from section 4 are TEXT holding JSON.
--
-- IDENTITY MODEL. Section 4 says "every table gets id uuid primary key". On
-- device that costs roughly 90 MB across the row payloads and every index that
-- copies a key, so the seed splits identity in two:
--
--   id    INTEGER PRIMARY KEY  -- internal join key, used by every FK, index
--                                and the R*Tree. Not stable across a rebuild;
--                                never expose it, never persist it off-device.
--   uuid  TEXT NOT NULL UNIQUE -- stable citable external identity, on the
--                                tables that need one (trees, species).
--                                DETERMINISTIC: a rebuild from the same source
--                                id reproduces the same uuid byte for byte, so
--                                public tree URLs and export rows survive a
--                                re-import. Required by DECISIONS.md
--                                constraint 13.
--
-- Frozen UUIDv5 namespace constants (see Tools/build_seed.py):
--   trees.uuid   = uuidv5(6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001,
--                         <id-space prefix> + <the source's own id>)
--                  San Francisco's id-space prefix is the empty string, so for
--                  this seed the name is the bare TreeID. A second city gets a
--                  non-empty prefix; see Tools/inventory_contract.py.
--   species.uuid = uuidv5(6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0002, <scientific name,
--                         lowercased, whitespace-collapsed>)
-- Changing either constant rewrites every public identifier. Do not.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------- species --
-- The city import supplies only the two names. Every other content column
-- (family, leaf_retention, id_tips, seasonal, care_notes, curated) is filled
-- from Fixtures/species/*.yaml, the authored species pipeline of BUILD-PLAN
-- section 8, and is NULL or empty wherever no source could be found.
--
-- leaf_retention in particular is null for the species whose habit no
-- authoritative source states. That is a real state, not a gap to be papered
-- over with a default: unknown renders no phenology chip and no autumn colour
-- anywhere in the app (ERRATA E9).
CREATE TABLE species (
    id              INTEGER PRIMARY KEY,
    uuid            TEXT NOT NULL UNIQUE,       -- stable external identity
    scientific_name TEXT NOT NULL,
    common_name     TEXT,
    family          TEXT,

    -- Drives phenology chips and the season strip (D5).
    leaf_retention  TEXT
        CHECK (leaf_retention IS NULL
               OR leaf_retention IN ('evergreen','deciduous','semi_deciduous')),

    -- json array of {icon, text}; 2 to 4 entries once authored
    id_tips         TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(id_tips)),
    -- json {bloom_months:[], fall_color_months:[], fruit_months:[], new_growth_months:[]}
    seasonal        TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(seasonal)),
    -- json array of {month_range, text}
    care_notes      TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(care_notes)),

    curated         INTEGER NOT NULL DEFAULT 0 CHECK (curated IN (0,1)),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    deleted_at      TEXT,

    -- D5 enforced in the database: an evergreen must never carry fall colour
    -- months, so the UI cannot render a fall-colour chip on an evergreen even
    -- if the content pipeline gets it wrong. `IS NOT` is the null-safe form, so
    -- a NULL leaf_retention (the unpopulated state) is unconstrained.
    CHECK (leaf_retention IS NOT 'evergreen'
           OR json_array_length(
                COALESCE(json_extract(seasonal, '$.fall_color_months'), '[]')) = 0)
);
CREATE UNIQUE INDEX idx_species_scientific_name ON species(scientific_name);
CREATE INDEX idx_species_common_name ON species(common_name);
CREATE INDEX idx_species_curated ON species(curated);

-- -------------------------------------------------------- species_trigrams --
-- BUILD-PLAN section 6 specifies a trigram index over both species names.
-- ERRATA E165 shipped substring matching as the on-device stand-in and recorded
-- what that still does not do: a typo misses, and so does a name the catalog
-- spells differently. This table is the part that fixes those two.
--
-- Why this and not `CREATE VIRTUAL TABLE ... USING fts5(tokenize='trigram')`:
-- FTS5's trigram tokenizer answers *substring* queries. Measured against this
-- very catalog, `MATCH 'liquidamber'` returns 0 rows and `MATCH 'sweetgum'`
-- returns 1 -- byte-identical to what E165's LIKE '%q%' already returns, so an
-- FTS5 trigram index would have added nothing to the two cases it was asked to
-- fix. What section 6 means by "trigram index" is Postgres' pg_trgm, whose
-- value is *similarity* -- the fraction of the query's trigrams a name carries
-- -- and that is a set-overlap question, not a token-match one. So the overlap
-- is stored directly and scored in SQL.
--
-- The scheme is pg_trgm's: lowercase, every non-[a-z0-9] run becomes a single
-- space, then the string is padded with two leading and one trailing space and
-- cut into 3-character windows. `Cypress` -> {'  c','  cy',...} etc. Padding is
-- what makes a word's opening letters score, and the single internal space is
-- what lets a trigram straddle two words, which is how a two-word query with a
-- typo in each half ('monteray cypres') still reaches Monterey Cypress.
--
-- WITHOUT ROWID because every column is in the primary key: the table IS its
-- index, so there is no second B-tree and no rowid to carry. ~21k rows for the
-- 726 live species, which is why this costs well under a megabyte on a 108 MB
-- file.
--
-- `Cypress/Data/Store/SpeciesQueries.swift` computes the query side and MUST
-- agree with `species_trigrams()` in this file character for character;
-- `SpeciesTrigramTests` is the test that holds the two together.
CREATE TABLE species_trigrams (
    trigram    TEXT NOT NULL,
    species_id INTEGER NOT NULL REFERENCES species(id),
    PRIMARY KEY (trigram, species_id)
) WITHOUT ROWID;

-- ---------------------------------------------------------- neighborhoods --
-- Section 4 stores geom as MultiPolygon. On device we keep the source GeoJSON
-- geometry verbatim in `geom_geojson` and precompute a bbox for cheap filters.
-- `name` is the stable external key here; no uuid column is needed.
CREATE TABLE neighborhoods (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    geom_geojson TEXT NOT NULL,
    min_lat      REAL NOT NULL,
    max_lat      REAL NOT NULL,
    min_lon      REAL NOT NULL,
    max_lon      REAL NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);

-- ---------------------------------------------------------------- dim_city --
-- Task #237. A city dimension table: the reader-facing civic facts about a
-- city -- slug, display name, state, county, the city's own official
-- street-tree/urban-forestry page -- joined through `id_spaces.city_id`
-- instead of scattered across other tables one column at a time.
--
-- SUPERSEDES renaming `id_spaces.id` to a "us-ca-sf"-style slug. `id_spaces.id`
-- stays FROZEN internal identity plumbing -- it is the key `trees.id_space`
-- carries and `Tools/inventory_contract.py`'s `IdSpace.identity_prefix` is
-- frozen per space (`sf`'s is the empty string; DECISIONS 13, see the trees
-- table above). The clean "us-ca-sf" convention lives here, on `dim_city.slug`,
-- never on `id_spaces.id`.
--
-- `id_spaces.short_name` (task #233) is ABSORBED here as `dim_city.display_name`
-- and the column is DROPPED from `id_spaces` in this pass -- one source of
-- truth for a city's reader-facing name rather than two hand-maintained
-- mappings that can drift apart. A reader-facing surface must check
-- `SeedSchema.hasDimCity` (table-gated, the same shape `hasSpeciesTrigrams`
-- uses for a new table) before joining through it, and falls back to
-- `SeedSchema.hasCivicShortNames`'s `id_spaces.short_name` for a file built
-- before this pass, never to a guess.
--
-- Hand-entered in `Tools/build_seed.py`'s DIM_CITY, sourced from each city's own
-- official pages and verified live -- see that dict's comment for the source
-- URL behind every value. A contributing id space with no entry there fails the
-- build loudly, the same shape as DISPLAY_NAMES/SHORT_CITY_NAMES before it.
CREATE TABLE dim_city (
    id                  INTEGER PRIMARY KEY,
    -- The "us-ca-sf" convention: <country>-<state>-<city>, lowercase. Never
    -- `id_spaces.id` (frozen internal identity plumbing, see above).
    slug                TEXT NOT NULL UNIQUE,
    display_name        TEXT NOT NULL,
    -- Postal abbreviation ("CA"), not the full state name. Flagged for owner
    -- sign-off in the PR that introduced this table.
    state               TEXT NOT NULL,
    county              TEXT NOT NULL,
    -- The city's own official street-tree / urban-forestry page.
    urban_forestry_url  TEXT NOT NULL,
    CHECK (slug <> ''),
    CHECK (display_name <> ''),
    CHECK (state <> ''),
    CHECK (county <> ''),
    CHECK (urban_forestry_url <> '')
);

-- --------------------------------------------------------------- dim_region --
-- THE UNIT A PACK IS PUBLISHED IN (seed generation 17). Hand-entered in
-- `Tools/build_seed.py`'s REGIONS; see the block comment there for why each
-- column is entered rather than derived.
--
-- This table is what makes 16 -> 17 a generation. Until it, the published unit
-- was the id space and `Tools/publish_cities.py` narrowed on `trees.id_space`.
-- RULING D1 makes New York's unit the borough, so the publisher needs something
-- finer to narrow on, and a borough needs a place to keep its own name that is
-- not `city_raw` -- whose column family renders as "Cared for by ...", making
-- *Cared for by Queens* a falsehood the app would ship.
--
-- Same shape and same reason as `dim_city` at s16: a pack that carried another
-- region's civic facts would be claiming an authority it does not have, so
-- `publish_cities.py` narrows this table to the one row the pack is for.
CREATE TABLE dim_region (
    id            INTEGER PRIMARY KEY,
    -- FROZEN PER REGION, AND IT IS DISTRIBUTION IDENTITY. Simultaneously the
    -- manifest entry's `id`, the `<id>` in R37.2's immutable object path
    -- `cities/<id>/<version>/<id>.sqlite`, and the install key on device.
    -- Changing one orphans every installed copy of that pack. NOT
    -- `dim_city.slug` (`sf` here is `us-ca-sf` there) and NOT `id_spaces.id`,
    -- though a one-region city's pack_id and id space currently agree.
    pack_id       TEXT NOT NULL UNIQUE,
    -- Civic content, entered (DECISIONS constraint 15). Names the PACK, which
    -- for New York is a borough and not the city the tree is in.
    display_name  TEXT NOT NULL,
    -- What kind of unit this is. RULING D2: one shape everywhere, so a
    -- one-region city is `city` rather than a special case. `extent` is
    -- reserved for a published unit that is neither -- a named sub-city window
    -- that is not a civic division. NOTE THAT LEVEL IS NOT COVERAGE: San Jose
    -- is level `city` with coverage `downtown`, because it is a whole city of
    -- which part shipped.
    level         TEXT NOT NULL,
    -- The city this region belongs to. A borough's civic facts (state, county,
    -- urban forestry page) are its city's; only the name and the extent are
    -- its own.
    city_id       INTEGER NOT NULL REFERENCES dim_city(id),
    CHECK (pack_id <> ''),
    CHECK (display_name <> ''),
    CHECK (level IN ('city','borough','extent'))
);

-- ----------------------------------------------------- id spaces, inventories --
-- THE SEED DECLARES ITS OWN VOCABULARY INSTEAD OF THE SCHEMA ENUMERATING IT.
--
-- `trees.inventory_source` used to carry `CHECK (inventory_source IN
-- ('city','datasf'))` -- a closed two-value list, which is a hard failure the
-- first time a second city is ingested (ERRATA E169 reproduced it:
-- `sqlite3.IntegrityError: CHECK constraint failed`). The CHECK's real job is
-- "no row may name an inventory the receipt cannot describe", and a hardcoded
-- list is the wrong instrument for that: every new city would edit the schema.
--
-- So these two tables are written by `build_seed.py` from `INVENTORIES` and
-- `ID_SPACES` in `Tools/inventory_contract.py`, **for exactly the inventories
-- that contributed rows**, and the vocabulary becomes a foreign key. A city that
-- shipped no rows is not in here, so `SELECT * FROM inventories` is a list of
-- what this file actually holds rather than a list of what the builder knows
-- about.
--
-- `id_spaces.identity_prefix` is the load-bearing column. `trees.uuid` is
-- `uuid5(NS_TREE, identity_prefix || external_ref)` and until now the prefix
-- lived in ONE `seed_meta` key, which was correct only while the whole file was
-- one id space. With two, a single key is a claim that is wrong for one of them.
-- Reading it per space out of a table is what lets the contract test re-derive
-- every row's uuid rather than trust one.
CREATE TABLE id_spaces (
    id              TEXT PRIMARY KEY,
    -- Prepended to a source's own id to make the uuid5 seed string. FROZEN per
    -- space: changing one rewrites every public tree URL in it (DECISIONS 13).
    -- `sf`'s is the empty string and is the one space permitted to have one.
    identity_prefix TEXT NOT NULL,
    note            TEXT NOT NULL,
    -- The city dimension row carrying this space's reader-facing civic facts
    -- (task #237). REPLACES `short_name` (task #233, dropped in this pass) --
    -- see `dim_city` above for why a whole table now sits behind this column
    -- instead of one string beside it. `SeedSchema.hasDimCity` is the app-side
    -- flag that must be true before a reader joins through it.
    city_id         INTEGER NOT NULL REFERENCES dim_city(id),
    CHECK (id <> '')
);

CREATE TABLE inventories (
    id        TEXT PRIMARY KEY,
    id_space  TEXT NOT NULL REFERENCES id_spaces(id),
    name      TEXT NOT NULL,
    url       TEXT NOT NULL,
    CHECK (id <> ''),
    CHECK (name <> '')
);

-- ------------------------------------------------------------------ trees --
-- Deviations from section 4:
--   geom geometry(Point,4326)   -> lat REAL + lon REAL (WGS84 degrees)
--   dbh_city_cm_range int4range -> dbh_city_cm_min / dbh_city_cm_max (half-open
--                                  [min, max), 5 cm buckets, both NULL together)
--   city_raw jsonb              -> city_raw TEXT holding a JSON object. NULL in
--                                  the shipped seed: the passthrough costs
--                                  ~74 MB and is regenerable from the raw CSV
--                                  via `build_seed.py --with-city-raw`. The
--                                  column is always declared so the schema
--                                  contract does not move.
--   external_ref text           -> TEXT NOT NULL, beside id_space TEXT NOT NULL,
--                                  unique over the PAIR. See below.
--
-- `external_ref` WAS A SOURCE-LOCAL ID UNDER A GLOBAL UNIQUE CONSTRAINT, WHICH
-- WAS THE BLOCKER FOR A SECOND CITY (ERRATA E169, reproduced:
-- `sqlite3.IntegrityError: UNIQUE constraint failed: trees.external_ref`).
-- San Jose FACILITYID 3 and San Francisco TreeID 3 are two different trees and
-- both exist; the second INSERT simply failed on the index.
--
-- Widened in the v14 seed pass (#129, ERRATA E176) to `UNIQUE (id_space,
-- external_ref)`, with the id space stored beside the ref rather than folded
-- into it:
--
--   * `id_space` holds the `ID_SPACES` key -- `sf`, `us-ca-sj` -- so "which
--     numbering is this row's id drawn from" is a column and not a parse. The
--     alternative, storing the qualified seed string `us-ca-sj:3` in one column,
--     is worse for exactly that reason, and the id space is a thing the receipt
--     and the UI both need to be able to name.
--   * `external_ref` is TEXT, NOT INTEGER: `InventoryRecord.source_ref` is
--     defined as the source's own id VERBATIM AS A STRING, and nothing
--     guarantees the third city's is numeric. San Jose's FACILITYID is a string
--     field in its own layer. Storing it as an integer would have made the
--     column's type a property of the first two sources that happened to arrive.
--   * NOT NULL, which is a decision and not a tidy-up. SQLite treats NULLs as
--     distinct in a unique index, so a nullable `external_ref` would let every
--     identity-less row escape the constraint the column exists for. The
--     contract does permit `source_ref=None` (Oakland publishes nothing but a
--     row number), and such a source cannot be a row in THIS file until the
--     schema grows a representation for it -- `emit()` stops the build rather
--     than writing one. See RULINGS R24.
--
-- The uuid derivation was already safe -- identity is qualified by id space (see
-- the namespace block in Tools/build_seed.py and ID_SPACES in
-- Tools/inventory_contract.py) -- and now the column is too.
--
-- THE SIX CITY COLUMNS CARRY NO CHECK, AND THAT IS THE DECISION.
-- Every closed vocabulary in the *app* schema carries its vocabulary in a CHECK,
-- because that database is written by a DAO and by whoever opens it in a
-- debugger, and the invariant has to hold against both. None of that reasoning
-- reaches here. This file is a read-only bundle regenerated from a live city
-- feed; the only writer is the loop below, and the only "hand-written INSERT" a
-- CHECK could catch is one nobody can perform against a database shipped inside
-- an .app.
--
-- What a CHECK would do instead is pin twelve strings that belong to San
-- Francisco rather than to Cypress. qLegalStatus has 12 values this week and had
-- fewer before; qCaretaker has 27, and they read like an org chart -- 'Asian
-- Arts Commission', 'Mission Verde', 'Office of Mayor' -- which is a list that
-- grows whenever a department is renamed. A CHECK over it would turn the next
-- weekly diff into a build failure over a string the city was entitled to add.
-- That is ERRATA E136's mistake written in advance rather than discovered
-- afterwards: a constraint wearing a ruling's clothes, forbidding a state the
-- source is allowed to reach. BUILD-PLAN section 7 already settled the same
-- question the same way for site_type ("kept as free text because the source
-- vocabulary is open-ended"), and these six are the same kind of column.
--
-- The vocabulary that IS closed -- street / city park / private property /
-- other public land -- is Cypress's own, is derived from these columns rather
-- than stored beside them, and is CHECK-pinned where it is actually written
-- down: main.community_trees.land_context (AppSchema v11). The derivation lives
-- in LandContext.inferred(from:) so that changing our reading of the city's
-- vocabulary is a code change rather than a 95 MB rebuild.
--
-- plot_size is TEXT and is never parsed into a number. The city's own 588
-- distinct values include 'Width 3ft', '3x3', '3X3', '60' and '10x10' -- three
-- incompatible notations and a bare integer of unstated unit -- and DataSF's
-- published description of the field reads "date tree was planted", copied from
-- PlantDate. Turning that into an area would be D7's forbidden move: dressing an
-- estimate as a measurement. It is shown as the city wrote it, or not at all.
--
-- Not ingested, and each for a reason:
--   SiteOrder                 an ordinal disambiguating several trees at one
--                             address (99.1% populated). It is a key inside the
--                             city's own table, not a fact about the tree, and
--                             "tree 3 of 7" answers nothing anybody asked.
--   XCoord / YCoord           CA State Plane III, the same point as lat/lon.
--   Location                  the string "(lat, lon)". Same point again.
--   Fire Prevention Districts, Police Districts, Supervisor Districts,
--   Zip Codes, Neighborhoods (old), Analysis Neighborhoods
--                             Socrata :@computed_region_* spatial-join
--                             artifacts. Their values are opaque row ids into
--                             other datasets, not names or numbers -- the "Zip
--                             Codes" column's commonest value is 28859. The
--                             seed does its own neighbourhood join against
--                             j2bu-swwd and keeps the name.
--
-- planted_year is section 4's column and stays. planted_on is DataSF's PlantDate
-- kept at its own grain (ISO 'YYYY-MM-DD'), added because the almanac (screen 12)
-- asks "how many trees were planted this spring" and a year cannot answer a
-- question about a season. The two are always set together or both NULL, and
-- planted_year is always planted_on's year -- a pinned invariant rather than a
-- convention, so the cheap column stays usable and the two can never disagree.
CREATE TABLE trees (
    id                 INTEGER PRIMARY KEY,     -- internal join key
    uuid               TEXT NOT NULL UNIQUE,    -- stable citable identity
    -- The source's own id, verbatim as a string, and the numbering it is drawn
    -- from. Unique over the pair, never over the ref alone -- see the block above.
    id_space           TEXT NOT NULL REFERENCES id_spaces(id),
    external_ref       TEXT NOT NULL,           -- SF TreeID | SJ FACILITYID
    source             TEXT NOT NULL,           -- city_import | community
    -- WHICH INVENTORY LISTED THIS RECORD. An `inventories.id` -- 'sf_city',
    -- 'sf_datasf', 'sj_street_tree' -- and a foreign key rather than a CHECK,
    -- so a new city is a row in a table and not an edit to this schema.
    --
    -- Under `--source datasf` every row says 'sf_datasf' and the column is
    -- redundant. Under `--source city` it is not: the row set is the city's
    -- operational layer, but that layer has no vacant-site category at all
    -- (`PlantType` is `Tree` on all 133,577 of its records), so the seed's
    -- vacant planting sites are carried across from the DataSF export and are
    -- the only rows in the file the city's layer does not list. A seed built
    -- from two inventories owes every reader the ability to ask which one a
    -- given row came from -- otherwise the provenance sentence on screen is a
    -- claim about the file rather than about the record, and for 12,260 of
    -- them it would be the wrong inventory's name.
    inventory_source   TEXT NOT NULL REFERENCES inventories(id),
    -- WHICH PUBLISHED REGION THIS ROW SHIPS IN (seed generation 17). NOT NULL
    -- on purpose: `Tools/publish_cities.py` narrows packs on this column, so a
    -- NULL would be a row that silently appears in no pack at all -- present in
    -- the fused seed, absent from every file a reader can download, and visible
    -- to nobody. The publisher's per-region counts must sum to the fused total,
    -- and this constraint is what makes that arithmetic closeable.
    --
    -- An INTEGER join key rather than the region's name, for the reason the
    -- identity model above gives: New York is ~898,000 rows and a TEXT borough
    -- on each of them is tens of megabytes of repeated string in the payload
    -- and in every index that copies it.
    region_id          INTEGER NOT NULL REFERENCES dim_region(id),
    lat                REAL NOT NULL,
    lon                REAL NOT NULL,
    address            TEXT,
    site_type          TEXT,
    neighborhood_id    INTEGER REFERENCES neighborhoods(id),
    status             TEXT NOT NULL,           -- alive | declining | dead_reported | removed | vacant_site
    species_current    INTEGER REFERENCES species(id),
    planted_year       INTEGER,
    planted_on         TEXT,                    -- ISO date, DataSF PlantDate
    dbh_city_cm_min    INTEGER,
    dbh_city_cm_max    INTEGER,
    site_lineage       INTEGER REFERENCES trees(id),
    verification_state TEXT NOT NULL,           -- unverified | org_verified | city_record
    -- ------------------------------------------------- the city's own record --
    -- Six DataSF columns carried verbatim, for the tree page's "what the city
    -- has on file" panel. All six are FREE TEXT and none carries a CHECK, which
    -- is a decision rather than an omission -- see the block comment below.
    legal_status       TEXT,                    -- DataSF qLegalStatus
    caretaker          TEXT,                    -- DataSF qCaretaker
    care_assistant     TEXT,                    -- DataSF qCareAssistant
    plant_type         TEXT,                    -- DataSF PlantType
    plot_size          TEXT,                    -- DataSF PlotSize, verbatim, never parsed
    permit_notes       TEXT,                    -- DataSF PermitNotes
    city_raw           TEXT,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    deleted_at         TEXT,
    -- One id per numbering, and the numbering is part of the key. Replaces the
    -- column-level `external_ref INTEGER UNIQUE` that could not hold two cities.
    UNIQUE (id_space, external_ref),
    CHECK (status IN ('alive','declining','dead_reported','removed','vacant_site')),
    -- Non-emptiness plus the foreign key above. The vocabulary lives in
    -- `inventories`, which the build writes; it is not enumerated here.
    CHECK (inventory_source <> ''),
    CHECK (external_ref <> ''),
    CHECK (verification_state IN ('unverified','org_verified','city_record')),
    CHECK ((dbh_city_cm_min IS NULL) = (dbh_city_cm_max IS NULL)),
    CHECK (city_raw IS NULL OR json_valid(city_raw)),
    -- The two planting columns are one fact at two grains; neither may drift
    -- from the other, and neither may exist without the other.
    CHECK ((planted_on IS NULL) = (planted_year IS NULL)),
    CHECK (planted_on IS NULL OR CAST(substr(planted_on, 1, 4) AS INTEGER) = planted_year)
);

-- Covering index for viewport / nearest queries that do not want the R*Tree.
CREATE INDEX idx_trees_lat_lon ON trees(lat, lon, id);
CREATE INDEX idx_trees_species_current ON trees(species_current);
CREATE INDEX idx_trees_neighborhood ON trees(neighborhood_id);
CREATE INDEX idx_trees_status ON trees(status);
-- The publisher's narrowing scan (s17): one DELETE per pack over this column,
-- and the per-region counts it checks the split against.
CREATE INDEX idx_trees_region ON trees(region_id);
-- The almanac's two neighbourhood-scoped planting reads (screen 12): the elder
-- is a MIN over this within one neighbourhood, and the recent-planting window is
-- a range scan over it. Both are ordered by date inside one neighbourhood, so the
-- index leads on the neighbourhood.
CREATE INDEX idx_trees_neighborhood_planted ON trees(neighborhood_id, planted_on);

-- Spatial index for "trees near a point" and map viewport bbox queries.
-- Keyed directly on trees.id, which is an INTEGER PRIMARY KEY and therefore a
-- rowid alias -- stable across VACUUM, unlike the implicit rowid of a TEXT-PK
-- table. Degenerate (point) rectangles: min == max on both axes.
--
-- IMPORTANT for the GRDB layer: SQLite's rtree module stores coordinates as
-- 32-bit floats and rounds each rectangle OUTWARD. It is therefore a
-- conservative filter -- it never drops a true hit, but it returns a handful of
-- rows just outside the requested box (measured drift here: <= 1.6e-5 deg,
-- about 1.7 m). ALWAYS re-check exactly against trees.lat / trees.lon:
--
--   SELECT t.* FROM trees_rtree r JOIN trees t ON t.id = r.id
--    WHERE r.max_lat >= :minLat AND r.min_lat <= :maxLat
--      AND r.max_lon >= :minLon AND r.min_lon <= :maxLon
--      AND t.lat BETWEEN :minLat AND :maxLat
--      AND t.lon BETWEEN :minLon AND :maxLon;
--
-- For "trees near a point", filter by bbox first, then order by squared
-- distance with a cos(lat) correction on the longitude term.
CREATE VIRTUAL TABLE trees_rtree USING rtree(
    id,               -- == trees.id
    min_lat, max_lat,
    min_lon, max_lon
);

-- ------------------------------------------------------ species_assertions --
-- Append-only. Every non-placeholder city row gets exactly one city_import row.
CREATE TABLE species_assertions (
    id            INTEGER PRIMARY KEY,
    tree_id       INTEGER NOT NULL REFERENCES trees(id),
    species_id    INTEGER NOT NULL REFERENCES species(id),
    source        TEXT NOT NULL,               -- city_import | community | org | ai_suggestion
    confidence    REAL,
    asserted_by   INTEGER,
    superseded_by INTEGER REFERENCES species_assertions(id),
    created_at    TEXT NOT NULL,
    CHECK (source IN ('city_import','community','org','ai_suggestion'))
);
CREATE INDEX idx_assertions_tree ON species_assertions(tree_id);
CREATE INDEX idx_assertions_species ON species_assertions(species_id);

-- ------------------------------------------------------ import provenance --
-- Not part of BUILD-PLAN 4. Mirrors Fixtures/sf_species_map.csv so the weekly
-- diff and Tools/verify_seed.py can audit the mapping without the CSV.
-- species_uuid, not species_id, is the key the checked-in CSV carries: integer
-- ids depend on CSV row order, uuids do not.
CREATE TABLE species_map (
    qspecies_string TEXT PRIMARY KEY,
    species_id      INTEGER REFERENCES species(id),
    species_uuid    TEXT,
    confidence      REAL NOT NULL,
    is_stub         INTEGER NOT NULL,      -- 1 = fell through to the stub path
    is_placeholder  INTEGER NOT NULL,      -- 1 = vacant-site placeholder, no species
    -- 1 = the string names no taxon ("Shrub", "Privet", "To Be Determine",
    -- "Stump"). EVERY COLUMN IN THIS TABLE IS A CLAIM ABOUT THE STRING, AND
    -- THIS ONE SAYS NOTHING ABOUT THE STATUS OF ANY ROW CARRYING IT. The string
    -- resolves to no species; whether a tree stands at a given site is
    -- `trees.status`, and the two are independent.
    --
    -- This sentence used to read "a tree stands at the site, so its status is
    -- `alive`", which was true of every such string while San Francisco was the
    -- only source -- its five non-taxon strings sit on `alive` rows alone -- and
    -- is false now. San Jose's `Stump` names no taxon on all of its rows and its
    -- vacancy flag calls most of them empty. Do not infer a status from this
    -- column. Provenance is a queryable column rather than a comment (DECISIONS
    -- constraint 13).
    is_non_taxon    INTEGER NOT NULL DEFAULT 0,
    tree_count      INTEGER NOT NULL,
    CHECK (species_id IS NULL OR (is_placeholder = 0 AND is_non_taxon = 0))
);

-- Single-row build receipt.
CREATE TABLE seed_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def log(msg: str) -> None:
    print(f"[build_seed] {msg}", flush=True)


def die(msg: str, code: int = 3) -> "None":
    print(f"[build_seed] FATAL: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


NOW = _seed_epoch()


def species_map_kind(kinds, species_id) -> str:
    """One qSpecies STRING's kind, from every row that carried it.

    `species_map` is keyed on the string, so `is_stub` / `is_placeholder` /
    `is_non_taxon` are claims about the string. They used to be read off
    whichever row reached the string first, which made them claims about the
    order of the source file. San Francisco never noticed: its vacancy lives in
    the species field itself, so every row carrying a given string agrees on the
    kind. San Jose publishes `VACANTSITE` and `NAMESCIENTIFIC` as two fields,
    and 611 empty sites name a real taxon -- so `Magnolia` arrives on 2 empty
    sites and 77 living trees, and when an empty site came first the row claimed
    a species AND `is_placeholder = 1`, which the table's own CHECK forbids.
    That is why `--source city --sj-extent full` did not build (ERRATA E274).

    The precedence below is not a tie-break. It is which FIELD each kind is
    reached through:

      * A string that resolved to a species names a taxon, whatever any single
        row said. That is the CHECK constraint's own statement, so it is first.
      * `not_a_tree` is only ever reached THROUGH the string: all three sites
        that return it match `NON_TAXON_SPECIES` or `SJ_NON_TREE_SPECIES` and
        carry basis `STATED_AS_NON_TAXON`. One such row is therefore a statement
        about the string -- `Stump` names no taxon on all 1,933 of its rows,
        including the 1,624 the vacancy flag calls empty.
      * `placeholder` is the opposite, and decides the string only when EVERY
        row agrees. San Jose reaches it from `VACANTSITE` on 76,048 of its
        76,109 placeholder rows -- a field about the SITE, which says nothing
        about the string. Otherwise `Unknown` (4,507 trees against 6 empty
        sites) would become a placeholder, when RULINGS R18 and
        `SanJoseStreetTreeAdapter.classify` both call it a tree whose species is
        not known.

        THE OTHER 61 ROWS ARE WHERE THAT REASONING AND THIS RULE COME APART, and
        they are named here because the next reader will meet them. Their basis
        is `INFERRED_FROM_ABSENT_SPECIES`, which does reach `placeholder`
        through the string: the string being EMPTY is the whole of the evidence.
        But that is the absence of content rather than a reading of it, and the
        basis name says the kind is OURS and not the source's -- where
        `not_a_tree` earns its one-row power by MATCHING the string against a
        vocabulary, which is a positive statement about what the string means.
        So unanimity still wins here, and `''` comes out `is_placeholder = 0` on
        the strength of the 229 rows San Jose itself placed in the ordinary
        category, against 812 stated-vacant and those 61. That is also the value
        `origin/main` shipped -- but there by luck of row order, since reversing
        the source flips it, and here on purpose.

    Counts measured on the 2026-07-31 caches at `--sj-extent full`.
    """
    if species_id is not None:
        return "stub" if "stub" in kinds else "parsed"
    if "non_taxon" in kinds:
        return "non_taxon"
    if kinds == {"placeholder"}:
        return "placeholder"
    return "parsed"


def fetch(url: str, dest: str) -> None:
    log(f"fetching {url}")
    tmp = dest + ".part"
    try:
        with urllib.request.urlopen(url, timeout=900) as resp, open(tmp, "wb") as out:
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
    except Exception as exc:  # noqa: BLE001
        if os.path.exists(tmp):
            os.remove(tmp)
        die(f"could not fetch {url}: {exc}")
    os.replace(tmp, dest)
    log(f"  -> {dest} ({os.path.getsize(dest) / 1e6:.1f} MB)")


def dbh_bucket_cm(inches):
    """Inches measured -> a half-open [min, max) 5 cm bucket, or (None, None).

    A SEED rule, not a source rule, so it stays here: the app renders a bucket
    and never a point value, and every inventory's diameters land in the same
    ladder. The source's own conventions -- the unit, and the `0` that means "not
    recorded" rather than "a zero-inch trunk" -- are resolved by its adapter
    before the number gets here. See `inventory_adapters.parse_dbh_inches`.
    """
    if inches is None:
        return None, None
    cm = inches * INCH_TO_CM
    lo = int(cm // DBH_BUCKET_CM) * int(DBH_BUCKET_CM)
    return lo, lo + int(DBH_BUCKET_CM)




SEASONAL_KEYS = ("bloom_months", "fall_color_months", "fruit_months", "new_growth_months")


def _compact_json(value) -> str:
    """One spelling of every JSON column, so a rebuild is byte-identical."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


# Two leading spaces and one trailing, pg_trgm's padding. The leading pair is
# what makes the first and second letters of a word carry their own trigram, so
# a query's opening is scored rather than lost; the trailing single space closes
# the last one.
TRIGRAM_PAD_HEAD = "  "
TRIGRAM_PAD_TAIL = " "


def species_trigrams(text: str) -> set:
    """The trigram set of one name -- the seed side of E165's similarity search.

    Normalisation is deliberately ASCII-only: `.lower()` folds the query and the
    catalog the same way for a-z, and every other scalar (a hyphen, a comma, an
    apostrophe in `'Rotundiloba'`, an accented letter) collapses to a single
    space. That is the same fold
    `SpeciesQueries.trigrams(_:)` performs in Swift, and the pair is pinned by
    `SpeciesTrigramTests.theSwiftAndPythonTrigramsAgree`. Change one and the
    seed's index stops answering the app's questions -- silently, because a
    mismatched trigram simply never joins.
    """
    folded = "".join(
        c if ("a" <= c <= "z" or "0" <= c <= "9") else " "
        for c in text.lower()
    )
    # Collapse runs and trim, so 'Sycamore,  London Plane' and 'Sycamore London
    # Plane' produce one trigram set rather than two.
    collapsed = " ".join(folded.split())
    if not collapsed:
        return set()
    padded = TRIGRAM_PAD_HEAD + collapsed + TRIGRAM_PAD_TAIL
    return {padded[i:i + 3] for i in range(len(padded) - 2)}


def build_species_trigram_index(conn) -> int:
    """Fill `species_trigrams` from the finished `species` table. Returns the row count.

    Runs after the species content pass, because it indexes the names as they
    ship: a name corrected by Fixtures/species/*.yaml must be indexed as
    corrected, not as the city import first spelled it.

    Stub rows (`:: 9662` -- a qSpecies string the ingest could not read, RULINGS
    R47) and soft-deleted rows are skipped. They are the rows the search itself
    excludes, so indexing them would only cost space and let a fuzzy match
    surface a name the catalog refuses to offer.
    """
    rows = conn.execute(
        "SELECT id, scientific_name, COALESCE(common_name, '') FROM species "
        "WHERE deleted_at IS NULL AND scientific_name NOT LIKE ':: %'"
    ).fetchall()

    pairs = []
    for species_id, scientific_name, common_name in rows:
        for gram in species_trigrams(scientific_name) | species_trigrams(common_name):
            pairs.append((gram, species_id))

    # Sorted so a rebuild writes the same pages in the same order; the file is
    # meant to be byte-identical across builds of the same data (R37.1).
    pairs.sort()
    conn.executemany(
        "INSERT OR IGNORE INTO species_trigrams(trigram, species_id) VALUES(?,?)", pairs
    )
    conn.commit()
    return len(pairs)


def load_species_content(fixtures_dir: str, species_by_key: dict, strict: bool = True,
                         extra_files: tuple = ()) -> dict:
    """Fixtures/species/*.yaml -> {species uuid: content row}. BUILD-PLAN section 8.

    Two files, read in this order so the authored guide wins the overlap:

      leaf_retention.yaml  family + leaf_retention for every mapped species,
                           null wherever no source states it (ERRATA E9, E10)
      curated.yaml         the top 40 by SF row count, with id_tips, seasonal
                           and care_notes

    Citations are not copied into the database. They are the reason a value is
    allowed to exist (DECISIONS constraint 15) and they live in the YAML, which
    is checked in; the seed carries the value, and Tools/validate_species.py is
    what refuses to let an uncited one through.

    Returns (content, stats).
    """
    if yaml is None:
        die("PyYAML is required to load the species content; "
            "pip install -r Tools/requirements.txt")

    uuid_to_name = {sp["uuid"]: sp["scientific_name"] for sp in species_by_key.values()}
    merge_targets = {
        name: str(uuid.uuid5(NS_SPECIES, normalise_species_key(target)))
        for name, target in MERGED_SPECIES_NAMES.items()
    }

    content = {}
    stats = {"leaf_retention": 0, "family": 0, "curated": 0, "retired": 0, "merged": 0, "absent": 0}

    def apply(entry: dict, path: str, curated: bool, allow_absent: bool = False) -> None:
        """`allow_absent` -- this fixture may legitimately describe species this
        build does not contain.

        `strict` exists to catch DRIFT: a fixture and a parser that disagree
        about what the corpus holds. A whole-city fixture read by a
        single-borough build is not drift -- `nyc_species.yaml` describes all
        898,643 NYC rows, and a Manhattan pack contains 98,929 of them, so ~400
        of its entries name species that pack correctly does not have.

        The NAME-MISMATCH check below stays strict for every file: a fixture
        claiming a different name for a uuid the seed DOES carry is still a
        build failure, whichever file it came from.
        """
        name = entry.get("scientific_name")
        species_uuid = entry.get("species_uuid")

        if name in RETIRED_SPECIES_NAMES:
            stats["retired"] += 1
            return
        if name in merge_targets:
            species_uuid = merge_targets[name]
            if species_uuid not in uuid_to_name:
                if not strict:
                    stats["absent"] += 1
                    return
                die(f"{os.path.basename(path)}: {name!r} merges into a species the seed does "
                    f"not carry ({species_uuid})")
            stats["merged"] += 1
        elif species_uuid not in uuid_to_name:
            if allow_absent or not strict:
                # `--limit` builds only part of the CSV, so most species are simply absent.
                stats["absent"] += 1
                return
            die(f"{os.path.basename(path)}: {name!r} ({species_uuid}) is not a species in the "
                f"seed, and is not one of the entries the map corrections retire. The fixtures "
                f"and the qSpecies parser have drifted apart.")

        if name not in merge_targets and uuid_to_name[species_uuid] != name:
            die(f"{os.path.basename(path)}: {species_uuid} is {uuid_to_name[species_uuid]!r} in "
                f"the seed but {name!r} in the fixture")

        row = content.setdefault(
            species_uuid,
            {"family": None, "leaf_retention": None, "id_tips": [], "seasonal": {},
             "care_notes": [], "curated": 0},
        )

        for field in ("family", "leaf_retention"):
            value = entry.get(field)
            if value is None:
                continue
            if row[field] is not None and row[field] != value:
                # Two entries landing on one species must agree. This is the check
                # that makes the `patanus racemosa` merge safe rather than a guess.
                die(f"{name}: {field} is {row[field]!r} from one fixture and {value!r} from "
                    f"another; they describe the same species and must agree")
            row[field] = value

        if not curated:
            return

        row["curated"] = 1
        row["id_tips"] = [
            {"icon": tip["icon"], "text": tip["text"]} for tip in entry.get("id_tips") or []
        ]
        seasonal = entry.get("seasonal") or {}
        row["seasonal"] = {key: sorted(seasonal.get(key) or []) for key in SEASONAL_KEYS}
        row["care_notes"] = [
            {
                "month_range": {
                    "start": note["month_range"]["start"],
                    "end": note["month_range"]["end"],
                },
                "text": note["text"],
            }
            for note in entry.get("care_notes") or []
        ]

    # `extra_files` carries the fixtures that only describe a city this build
    # actually contains. `nyc_species.yaml` names 500-odd species that an
    # SF-only build has never heard of, and `strict` would (correctly) call every
    # one of them drift between the fixtures and the parser. So the file is
    # offered when NYC is in the build and withheld when it is not, rather than
    # weakening the check that catches real drift.
    for path, curated in (
        (os.path.join(fixtures_dir, "species", "leaf_retention.yaml"), False),
        (os.path.join(fixtures_dir, "species", "curated.yaml"), True),
    ):
        if not os.path.exists(path):
            die(f"missing species fixture {path}")
        with open(path, "r", encoding="utf-8") as fh:
            document = yaml.safe_load(fh)
        entries = document.get("species") or []
        log(f"loaded {len(entries)} entries from {os.path.basename(path)}")
        for entry in entries:
            apply(entry, path, curated)

    for path, curated in tuple(extra_files):
        if not os.path.exists(path):
            die(f"missing species fixture {path}")
        with open(path, "r", encoding="utf-8") as fh:
            document = yaml.safe_load(fh)
        entries = document.get("species") or []
        before = stats["absent"]
        for entry in entries:
            apply(entry, path, curated, allow_absent=True)
        log(f"loaded {len(entries)} entries from {os.path.basename(path)} "
            f"({stats['absent'] - before} name species this build does not contain, "
            f"which a city-scoped fixture read by a partial build is expected to)")

    # D5 / DECISIONS constraint 14, enforced here as well as in the database CHECK,
    # in Species.init and in Tools/validate_species.py. BUILD-PLAN section 7 wants
    # ingest failures loud, and a fall-colour chip on an evergreen is exactly the
    # bug D5 was written for.
    for species_uuid, row in content.items():
        if row["leaf_retention"] == "evergreen" and (row["seasonal"].get("fall_color_months") or []):
            die(f"D5 violation: {uuid_to_name.get(species_uuid, species_uuid)} is evergreen and "
                f"carries fall_color_months {row['seasonal']['fall_color_months']}")

    stats["leaf_retention"] = sum(1 for r in content.values() if r["leaf_retention"])
    stats["family"] = sum(1 for r in content.values() if r["family"])
    stats["curated"] = sum(1 for r in content.values() if r["curated"])
    return content, stats


def load_neighborhoods(path: str):
    """-> list of dicts with a 1-based integer id, name, geojson, bbox, geometry."""
    try:
        from shapely.geometry import shape  # noqa: PLC0415
    except ImportError:
        die("shapely is required; pip install -r Tools/requirements.txt")

    with open(path, "r", encoding="utf-8") as fh:
        gj = json.load(fh)

    feats = []
    for feat in gj.get("features", []):
        geom = feat.get("geometry")
        props = feat.get("properties") or {}
        name = props.get("nhood") or props.get("name")
        if geom and name:
            feats.append((name, geom))
    # Sort by name so integer ids are stable across re-downloads.
    feats.sort(key=lambda kv: kv[0])

    out = []
    for i, (name, geom) in enumerate(feats, start=1):
        g = shape(geom)
        if not g.is_valid:
            g = g.buffer(0)
        minx, miny, maxx, maxy = g.bounds
        out.append(
            {
                "id": i,
                "name": name,
                "geojson": json.dumps(geom, separators=(",", ":")),
                "bbox": (miny, maxy, minx, maxx),  # min_lat, max_lat, min_lon, max_lon
                "geom": g,
            }
        )
    return out


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------


def _species_map_drift(current: str, derived: str):
    """What actually differs between two species maps, as ROWS keyed by species string.

    Returns (removed, added, changed) -- falsy when the two say the same thing.

    Not a line-by-line comparison. The first version zipped the files
    positionally and added the length difference, which is not a diff: one
    inserted row shifts every row after it and all of them count as changed. It
    reported 628 differing lines for a 631-line file. Nor a byte comparison,
    which fires when only the line terminator differs and so fired on every
    build.
    """
    def rows_by_key(blob: str) -> dict:
        reader = csv.reader(io.StringIO(blob))
        next(reader, None)  # header
        return {row[0]: row[1:] for row in reader if row}

    before, after = rows_by_key(current), rows_by_key(derived)
    removed = sorted(set(before) - set(after))
    added = sorted(set(after) - set(before))
    changed = sorted(k for k in set(before) & set(after) if before[k] != after[k])
    return removed, added, changed


def species_map_csv(rows) -> str:
    """The species-map CSV as text, so it can be compared before it is written.

    species_id carries the species UUID, not the internal integer id: integer
    ids depend on CSV row order, uuids are order-independent and survive a
    rebuild, which is what a checked-in mapping file needs.

    An empty species_id is the honest answer for three kinds of string: a
    vacant-site placeholder, a string that names no taxon (NON_TAXON_SPECIES),
    and nothing else. A correction belongs in the tables at the top of this
    script, not in the CSV -- the file is derived from them, so an edit to it is
    lost the next time it is regenerated.
    """
    # LF, not csv's default CRLF. The working tree stores these files with LF
    # (autocrlf=input, no .gitattributes rule), so a CRLF writer made every
    # build's output differ from the checked-in copy in every single line --
    # which meant `--write-species-map` churned the whole file, and the drift
    # NOTE below fired on every build even when the content was identical. The
    # rows are unchanged; only the terminator is.
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["qSpecies_string", "species_id", "confidence"])
    for qs_string, _sid, suuid, conf, _stub, _ph, _nt, _count in rows:
        w.writerow([qs_string, suuid or "", f"{conf:.2f}"])
    return out.getvalue()


def build(repo_root: str, do_fetch: bool, limit: int, with_city_raw: bool,
          source: str = DEFAULT_SOURCE, sj_extent: str = "none",
          write_species_map: bool = False,
          nyc_cache: str = "", nyc_borough: str = "", nyc_structures: str = "Full") -> int:
    if source not in SOURCES:
        die(f"--source must be one of {', '.join(SOURCES)}, got {source!r}")
    if sj_extent not in SJ_EXTENTS:
        die(f"--sj-extent must be one of {', '.join(SJ_EXTENTS)}, got {sj_extent!r}")
    raw_dir = os.path.join(repo_root, "Fixtures", "raw")
    seed_dir = os.path.join(repo_root, "Fixtures", "seed")
    fixtures_dir = os.path.join(repo_root, "Fixtures")
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(seed_dir, exist_ok=True)

    csv_path = os.path.join(raw_dir, "street_tree_list.csv")
    nb_path = os.path.join(raw_dir, "sf_analysis_neighborhoods.geojson")
    db_path = os.path.join(seed_dir, "cypress-seed.sqlite")
    schema_path = os.path.join(seed_dir, "schema.sql")

    if do_fetch or not os.path.exists(csv_path):
        fetch(TREES_CSV_URL, csv_path)
    if do_fetch or not os.path.exists(nb_path):
        fetch(NEIGHBORHOODS_GEOJSON_URL, nb_path)

    if not os.path.exists(csv_path):
        die(f"missing {csv_path}; rerun with --fetch")

    city_rows, city_meta, enrichment = [], {}, {}
    if source == "city":
        city_rows, city_meta = load_city_layer(raw_dir)
        log(f"city layer: {len(city_rows):,} features, extracted "
            f"{city_meta['extracted_on']}, server last edit "
            f"{city_meta.get('server_last_edit_date')}")
        enrichment = load_datasf_attributes(csv_path)
        log(f"enrichment index: {len(enrichment):,} DataSF rows by TreeID")

    nyc_rows, nyc_spaces, nyc_meta, nyc_boroughs = None, {}, {}, None
    if nyc_cache:
        nyc_rows, nyc_spaces, nyc_meta = load_nyc_layers(nyc_cache)
        # RULING D18: every NYC row carries a borough, so the boundary file is
        # not optional -- a build without it stops on the first orphan.
        boundaries = os.path.join(nyc_cache, "borough_boundaries.geojson")
        if not os.path.exists(boundaries):
            die(
                f"{boundaries} is absent. RULING D18 requires every NYC tree to carry a "
                f"borough and 22,995 of them join no planting space, so the City's "
                f"borough polygons are required. Re-run Tools/fetch_nyc_trees.py."
            )
        with open(boundaries, "r", encoding="utf-8") as fh:
            nyc_boroughs = BoroughResolver(json.load(fh))
        log(f"nyc: {len(nyc_rows):,} tree points, {len(nyc_spaces):,} planting spaces, "
            f"extracted {nyc_meta.get('extracted_on')}")

    sj_rows, sj_meta, sj_window = None, {}, None
    if sj_extent != "none":
        sj_rows, sj_meta = load_san_jose_layer(raw_dir)
        sj_window = SJ_SHIP_WINDOW if sj_extent == "downtown" else None

    # ---------------------------------------------------------- neighborhoods
    neighborhoods = []
    strtree = None
    nb_by_index = []
    if os.path.exists(nb_path):
        neighborhoods = load_neighborhoods(nb_path)
        log(f"loaded {len(neighborhoods)} analysis neighborhoods")
        if neighborhoods:
            from shapely import STRtree  # noqa: PLC0415
            from shapely.geometry import Point  # noqa: PLC0415
            from shapely.prepared import prep  # noqa: PLC0415

            strtree = STRtree([n["geom"] for n in neighborhoods])
            nb_by_index = [(n["id"], prep(n["geom"])) for n in neighborhoods]
    else:
        log("WARNING: neighborhoods file absent; neighborhood_id will be NULL")

    # --------------------------------------------------------------- database
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(db_path + suffix):
            os.remove(db_path + suffix)

    conn = sqlite3.connect(db_path)
    conn.executescript("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;")
    conn.executescript(SCHEMA_SQL)
    with open(schema_path, "w", encoding="utf-8") as fh:
        fh.write(SCHEMA_SQL.lstrip("\n"))

    conn.executemany(
        "INSERT INTO neighborhoods(id,name,geom_geojson,min_lat,max_lat,min_lon,max_lon,"
        "created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
        [(n["id"], n["name"], n["geojson"], *n["bbox"], NOW, NOW) for n in neighborhoods],
    )

    # ------------------------------------------------------------ ingest pass
    #
    # THE SHAPE OF THIS PASS IS THE POINT. Every inventory is read by an adapter
    # (`Tools/inventory_adapters.py`) that yields `InventoryRecord`s
    # (`Tools/inventory_contract.py`), and `emit` below accepts nothing else. So
    # the rules that are the SEED's -- identity, the species catalogue, the DBH
    # ladder, the neighbourhood stamp, the bounding box, uniqueness of a source
    # ref -- are written once, here, and the rules that are one UPSTREAM's live
    # in its adapter and reach no further.
    stats = {
        "source_rows": 0,
        "dropped_no_coords": 0,
        "dropped_out_of_bbox": 0,
        "dropped_dupe_treeid": 0,
        "kept": 0,
        # ── One counter per value `trees.status` may hold (s17) ──────────────
        # Every member of the CHECK constraint's vocabulary is declared here,
        # including the ones no current source produces, so a status that starts
        # appearing shows up as a number moving off zero rather than as a
        # KeyError in a build nobody is watching.
        #
        # These REPLACE the bare `alive` and `vacant_site` counters. Renaming
        # them was the point rather than a tidy-up: `alive` was incremented by an
        # `else`, so its name and its meaning ("everything that is not a vacant
        # site") only agreed while two statuses existed. One name per value keeps
        # them agreeing as the vocabulary grows.
        "status_alive": 0,
        "status_declining": 0,
        "status_dead_reported": 0,
        "status_removed": 0,
        "status_vacant_site": 0,
        # How many records arrived with a condition claim at all, and what it
        # said. `condition_stated` is the size of what s17 made representable:
        # while `STATUS_FOR_KIND` was keyed on `kind`, this number could only
        # ever have been zero.
        "condition_stated": 0,
        "condition_alive": 0,
        "condition_declining": 0,
        "condition_dead": 0,
        "condition_removed": 0,
        "assertions": 0,
        "stub_rows": 0,
        "parsed_rows": 0,
        "non_taxon_rows": 0,
        "no_neighborhood": 0,
        "planted_year_present": 0,
        "dbh_present": 0,
        "enriched_rows": 0,
        "city_only_rows": 0,
        # The export's vacant planting sites, under `--source city` only.
        "export_vacant_rows": 0,
        "export_vacant_carried": 0,
        "export_vacant_city_lists_tree": 0,
        "export_vacant_city_lists_site": 0,
        # San Jose, under `--sj-extent` other than `none`.
        "sj_source_rows": 0,
        "sj_kept": 0,
        "nyc_kept": 0,
        "nyc_source_rows": 0,
        # Records read and validated but deliberately not shipped, because they
        # fall outside `SJ_SHIP_WINDOW`. This is the one drop counter in the
        # build that is a PRODUCT decision rather than a data defect, and it is
        # named so it cannot be read as one.
        "sj_outside_ship_window": 0,
        # ---- what the contract made countable -------------------------------
        # Records whose source says the thing growing there is not a tree
        # (`Shrub`, `Private shrub`, `Privet`). The seed's `status` vocabulary
        # has no value for that, so `STATUS_FOR_KIND` maps them to `alive` and
        # this counter is the size of the lie. Half of task #94.
        "records_not_a_tree": 0,
        # Records the seed calls a vacant planting site where the SOURCE SAID NO
        # SUCH THING -- its species field was blank, or read `Tree`. The other
        # half of #94, and the more serious half: 1,326 of the export's `::`
        # rows carry `qLegalStatus = DPW Maintained`, which is the city saying it
        # maintains a street tree at a location our seed draws as an empty hole.
        "planting_sites_inferred_from_absent_species": 0,
        "planting_sites_stated_by_source": 0,
        "contract_violations": 0,
        **{"city_" + csv_column: 0 for _, csv_column in CITY_RECORD_COLUMNS},
    }

    species_by_key = {}      # normalised scientific name -> species row dict
    qspecies_stats = {}      # raw qSpecies string -> dict
    # (id space, source ref) pairs already emitted. THE PAIR, not the ref: San
    # Jose FACILITYID 3 and San Francisco TreeID 3 are two different trees.
    seen_external_refs = set()
    # Which inventories actually put a row in the file. `inventories` is written
    # from this at the end, so the table describes the file and not the builder.
    contributing_inventories = set()
    city_kind_by_ref = {}    # TreeID -> contract kind, city rows only

    tree_rows = []
    rtree_rows = []
    assertion_rows = []
    ids = {"tree": 0, "assertion": 0}
    t0 = time.time()

    # ---- #95: one spelling per case-folded value, over the columns the app
    # matches on. Built from a pre-pass over the whole source, because the
    # commonest spelling is not knowable from one row. See NORMALISED_SEED_COLUMNS.
    case_counts = {column: {} for column in NORMALISED_SEED_COLUMNS}

    def observe_case(column: str, value):
        if value:
            case_counts[column][value] = case_counts[column].get(value, 0) + 1

    # The contract's four `kind`/`is_stub` combinations back to the four names
    # `parse_qspecies` used, which `Fixtures/sf_species_map.csv` is keyed on.
    def legacy_kind(record) -> str:
        if record.kind == KIND_PLANTING_SITE:
            return "placeholder"
        if record.kind == KIND_NOT_A_TREE:
            return "non_taxon"
        return "stub" if record.species_is_stub else "parsed"

    def accepts(record) -> bool:
        """The seed's own admission rules, applied to a validated record.

        Bounding box and source-ref uniqueness are the SEED's rules, not any
        upstream's, so they are here rather than in an adapter -- two adapters
        that each decided them would eventually decide them differently.
        """
        problems = record.validate()
        if problems:
            stats["contract_violations"] += 1
            die("record {}/{} violates the ingest contract: {}".format(
                record.inventory, record.source_ref, "; ".join(problems)))
        # The box belongs to the record's own city, not to the file's first one.
        bbox = BBOX_BY_ID_SPACE[require_inventory(record.inventory).id_space]
        if not (
            bbox["min_lat"] <= record.lat <= bbox["max_lat"]
            and bbox["min_lon"] <= record.lon <= bbox["max_lon"]
        ):
            stats["dropped_out_of_bbox"] += 1
            return False
        return True

    def emit(record) -> None:
        """One `InventoryRecord` -> the seed's row shapes.

        Shared by every adapter on purpose: identity, the species catalogue, the
        vacant-site mapping, the DBH ladder and the neighbourhood stamp are the
        seed's rules and not any one upstream's, so no two sources can drift in
        what they mean by a row.
        """
        # ---- identity.
        #
        # Qualified by ID SPACE and not by inventory, which is the whole trick.
        # San Francisco's two inventories share a space deliberately -- they
        # publish the same TreeID numbering, and their uuids colliding is what
        # made the DataSF -> city switch reversible with zero uuids moved
        # (E156). A second CITY gets its own space and its own frozen prefix, so
        # its TreeID 276198 cannot mint the uuid of `1 TWIN PEAKS BLVD`.
        #
        # The space is the RECORD's, resolved through its own inventory. It used
        # to be the file's -- one `id_space` variable derived from `--source` --
        # which was correct only while a seed held one city.
        record_space = ID_SPACES[require_inventory(record.inventory).id_space]
        contributing_inventories.add(record.inventory)
        if record.has_stable_identity:
            uuid_seed = record.identity_seed(record_space)
            # VERBATIM, AS A STRING. It used to be coerced to an integer when it
            # looked like one, which made the column's type a property of the
            # first two sources that arrived. `source_ref` is defined as the
            # source's own id as a string and the column is TEXT now.
            external_ref = record.source_ref
        else:
            # No id from the source. The contract permits this -- Oakland
            # publishes nothing but a row number -- but `trees.external_ref` is
            # NOT NULL, because a nullable column under `UNIQUE (id_space,
            # external_ref)` lets every such row escape the constraint (SQLite
            # treats NULLs as distinct). So this seed cannot hold one, and it
            # says so instead of writing a row nobody can identify. RULINGS R24.
            die(
                f"record {record.inventory}/(no source_ref) at "
                f"{record.lat:.6f},{record.lon:.6f} has no stable identity, and "
                f"trees.external_ref is NOT NULL. A source that publishes no id "
                f"needs a decision (RULINGS R24), not a NULL that silently "
                f"escapes UNIQUE (id_space, external_ref)."
            )
        tree_uuid = str(uuid.uuid5(NS_TREE, uuid_seed))

        # ---- where this row's FACTS came from, counted only now that the row is
        # certain to ship. `seed_meta.rows_enriched` is a claim about the file.
        if source == "city":
            if record.inventory == "sf_city":
                if record.attributes_from is None:
                    stats["city_only_rows"] += 1
                else:
                    stats["enriched_rows"] += 1

        # EVERY row that carries the string, not just the first one to reach it.
        # `species_map` is keyed on the string, so its columns are claims about
        # the string; taking them from one arbitrary row made them claims about
        # file order instead. See `species_map_kind`.
        qs = qspecies_stats.setdefault(
            record.species_text or "",
            {"kinds": set(), "confidence": 0.0,
             "species_id": None, "species_uuid": None, "count": 0, "spaces": set()},
        )
        qs["count"] += 1
        qs["kinds"].add(legacy_kind(record))
        # Which id space's vocabulary this string belongs to. San Francisco's
        # `Ulmus parvifolia :: Chinese Elm` and San Jose's `Ulmus parvifolia` are
        # two different sources' spellings and they are written to two different
        # checked-in files, each named for the space it describes -- a file called
        # `sf_species_map.csv` holding San Jose strings would be the same quiet
        # falsehood as a provenance line naming the wrong inventory.
        qs["spaces"].add(record_space.id)

        # ---- species.
        species_id = None
        if record.kind == KIND_NOT_A_TREE:
            stats["non_taxon_rows"] += 1
            stats["records_not_a_tree"] += 1
        elif record.scientific_name is not None:
            key = normalise_species_key(record.scientific_name)
            sp = species_by_key.get(key)
            if sp is None:
                sp = {
                    "id": len(species_by_key) + 1,
                    "uuid": str(uuid.uuid5(NS_SPECIES, key)),
                    "scientific_name": record.scientific_name,
                    "common_name": record.common_name,
                    "stub": record.species_is_stub,
                }
                species_by_key[key] = sp
            elif sp["common_name"] is None and record.common_name:
                sp["common_name"] = record.common_name
            species_id = sp["id"]
            qs["species_id"] = species_id
            qs["species_uuid"] = sp["uuid"]
            # From the rows that RESOLVED the string, so a row carrying the
            # string without resolving it cannot set the confidence of a
            # resolution it took no part in. No string in any of the three
            # `--sj-extent` corpora shows two different confidences among its
            # resolving rows, so this max is a defined value and not a vote.
            qs["confidence"] = max(qs["confidence"], record.species_confidence or 0.0)
            if record.species_is_stub:
                stats["stub_rows"] += 1
            else:
                stats["parsed_rows"] += 1

        # ---- what the record IS, and how it is DOING. One lookup, so #94 has
        # one place to change; two arguments since s17, so a source that
        # publishes a condition can reach `declining` / `dead_reported` instead
        # of being flattened to `alive` (see `status_for_record`).
        status = status_for_record(record.kind, record.condition)
        if record.kind == KIND_PLANTING_SITE:
            if record.kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES:
                stats["planting_sites_inferred_from_absent_species"] += 1
            else:
                stats["planting_sites_stated_by_source"] += 1
        # Counted per status rather than per branch. `stats["alive"]` used to be
        # incremented by an `else` on "is it a vacant site", and that stopped
        # being a correct reading of it the moment a condition could produce
        # `declining` or `dead_reported`: the `else` would have counted standing
        # dead trees as living ones, in the build receipt, silently.
        stats["status_" + status] += 1
        if record.condition is not None:
            stats["condition_stated"] += 1
            stats["condition_" + record.condition] += 1

        planted_year = record.planted_on.year if record.planted_on else None
        planted_on = record.planted_on.isoformat() if record.planted_on else None
        if planted_year:
            stats["planted_year_present"] += 1
        dbh_min, dbh_max = dbh_bucket_cm(record.dbh_in)
        if dbh_min is not None:
            stats["dbh_present"] += 1

        # ---- neighborhood stamp
        #
        # THE POLYGONS ARE SAN FRANCISCO'S ANALYSIS NEIGHBORHOODS AND ONLY
        # THOSE. A San Jose row falls in none of them and gets NULL, which is
        # the honest answer -- there is no San Jose neighbourhood layer in this
        # seed -- and it is also a real product consequence rather than a
        # cosmetic one: every neighbourhood-scoped surface (the almanac, screen
        # 12) is keyed on this column. See ERRATA E176 for what that does to the
        # almanac with two cities present.
        neighborhood_id = None
        if strtree is not None:
            pt = Point(record.lon, record.lat)
            for idx in strtree.query(pt):
                nid, prepared = nb_by_index[int(idx)]
                if prepared.contains(pt):
                    neighborhood_id = nid
                    break
            if neighborhood_id is None:
                stats["no_neighborhood"] += 1

        ids["tree"] += 1
        tree_id = ids["tree"]
        city_record = [record.city_record.get(name) for name, _ in CITY_RECORD_COLUMNS]
        observe_case("site_type", record.site_type)
        for (seed_column, csv_column), value in zip(CITY_RECORD_COLUMNS, city_record):
            if value:
                stats["city_" + csv_column] += 1
            if seed_column in case_counts:
                observe_case(seed_column, value)
        tree_rows.append(
            [
                tree_id,
                tree_uuid,
                record_space.id,
                external_ref,
                "city_import",
                record.inventory,
                # A PLACEHOLDER, REWRITTEN TO A dim_region.id BEFORE THE FLUSH.
                # It cannot be the real key yet: `dim_region`'s rowids are not
                # assigned until the contributing spaces are known, which is
                # after the whole source has been read. `resolve_region_ids`
                # below does the rewrite and fails loudly on anything it cannot
                # place -- the same shape the case-normalisation pass uses to
                # rewrite columns inside these rows.
                (record_space.id, record.region),
                record.lat,
                record.lon,
                record.address,
                record.site_type,
                neighborhood_id,
                status,
                species_id,
                planted_year,
                planted_on,
                dbh_min,
                dbh_max,
                None,
                "city_record",
                *city_record,
                record.raw_json,
                NOW,
                NOW,
                None,
            ]
        )
        rtree_rows.append((tree_id, record.lat, record.lat, record.lon, record.lon))

        if species_id is not None:
            ids["assertion"] += 1
            assertion_rows.append(
                (ids["assertion"], tree_id, species_id, "city_import",
                 record.species_confidence or 0.0, None, None, NOW)
            )
            stats["assertions"] += 1

        stats["kept"] += 1

    # `emit` appends to `tree_rows` and the case-normalisation pass below rewrites
    # columns inside those rows, so rows are held until the whole source has been
    # read rather than flushed in 20,000-row batches. Peak resident size is about
    # 250 MB for the DataSF export and 170 MB for the city layer; the batching it
    # replaces existed to bound exactly that, and a normalisation that can only be
    # computed from the whole corpus is worth the memory.
    horizon_year = datetime.fromisoformat(NOW).year + 1
    sf_inventory = SF_INVENTORY_FOR_SOURCE[source]
    id_space = ID_SPACES[require_inventory(sf_inventory).id_space]

    def already_seen(record) -> bool:
        """Has this (id space, source ref) already been emitted?

        KEYED ON THE PAIR, not on the ref. San Jose FACILITYID 3 and San
        Francisco TreeID 3 are two different trees; a set of bare refs would have
        silently dropped one of them as a duplicate, which is the same defect as
        the old `external_ref INTEGER UNIQUE` wearing different clothes.
        """
        return (require_inventory(record.inventory).id_space, record.source_ref) in seen_external_refs

    def mark_seen(record) -> None:
        seen_external_refs.add(
            (require_inventory(record.inventory).id_space, record.source_ref)
        )

    if source == "datasf":
        primary = SFDataSFAdapter(csv_path, horizon_year, with_raw=with_city_raw, limit=limit)
    else:
        primary = SFCityLayerAdapter(city_rows, enrichment, horizon_year, limit=limit)

    for record in primary.records():
        if not accepts(record):
            continue
        if record.source_ref is not None:
            if already_seen(record):
                stats["dropped_dupe_treeid"] += 1
                continue
            mark_seen(record)
            if source == "city":
                # Kept so the second pass can say which kind of overlap it found
                # when the export calls a site empty and this layer lists it.
                city_kind_by_ref[record.source_ref] = record.kind
        emit(record)
        if primary.stats["source_rows"] % 20000 == 0:
            log(f"  {primary.stats['source_rows']:,} rows read / {stats['kept']:,} kept "
                f"({time.time() - t0:.0f}s)")

    stats["source_rows"] = primary.stats["source_rows"]
    stats["dropped_no_coords"] += primary.stats["dropped_no_coords"]

    if source == "city":
        # ---- second pass: the export's vacant planting sites.
        #
        # WHY A ROW SET THAT IS OTHERWISE THE CITY'S TAKES ROWS FROM THE EXPORT.
        #
        # The city's layer publishes no vacant-site category. `PlantType` is
        # `Tree` on all 133,577 of its records; there is no `qSiteInfo`, no
        # `qLegalStatus`, no site-status column of any kind. So on a vacant site
        # the two inventories are not disagreeing -- the city's layer has no
        # opinion to disagree with, and reading its silence as "there is a tree
        # there now" would be inferring a fact from a schema.
        #
        # That is a different claim from the one the switch makes about living
        # trees, where the layer IS the operational record and a tree it stopped
        # listing is most likely gone. Here the export is the only source that
        # has ever described these 12,518 sites, and dropping them to 153 took a
        # whole feature (#11, #31, #32) down to a vestige across 17 of the city's
        # 41 neighbourhoods.
        #
        # THE ONE PLACE THE TWO REALLY DO DISAGREE, AND WHO WINS. A TreeID the
        # export calls an empty basin and the city's layer lists as a planted
        # tree is a genuine contradiction, and there the city wins -- the same
        # rule the living-tree spine follows. Those rows are already in the seed
        # from the first pass, so the test is simply "did the first pass already
        # emit this source ref", which also makes a duplicate `external_ref`
        # unrepresentable rather than merely unlikely.
        #
        # Nothing here can add a *tree*: the adapter is constructed
        # `planting_sites_only`, so every record it yields is already
        # `KIND_PLANTING_SITE` and `STATUS_FOR_KIND` gives it `vacant_site` and
        # no species. A row that stopped parsing as a planting site would stop
        # being carried, not become a tree.
        sites = SFDataSFAdapter(
            csv_path, horizon_year, with_raw=with_city_raw, planting_sites_only=True
        )
        for record in sites.records():
            if limit and stats["export_vacant_carried"] >= limit:
                break
            if not accepts(record):
                continue
            if record.source_ref is not None:
                if already_seen(record):
                    # The city's layer already listed this TreeID and the first
                    # pass emitted it. Which of the two cases this is -- a
                    # contradiction the city won, or an empty site both
                    # inventories agree about -- is counted for the record.
                    if city_kind_by_ref.get(record.source_ref) == KIND_PLANTING_SITE:
                        stats["export_vacant_city_lists_site"] += 1
                    else:
                        stats["export_vacant_city_lists_tree"] += 1
                    continue
                mark_seen(record)
            stats["export_vacant_carried"] += 1
            emit(record)

        stats["export_vacant_rows"] = sites.stats["candidate_rows"]
        stats["dropped_no_coords"] += sites.stats["dropped_no_coords"]

        log(f"vacant planting sites from the export: {stats['export_vacant_carried']:,} carried, "
            f"{stats['export_vacant_city_lists_tree']:,} excluded because the city's layer lists "
            f"a living tree at that TreeID, {stats['export_vacant_city_lists_site']:,} already "
            f"in the seed as the city's own empty site")

    # ---- the second CITY. -------------------------------------------------
    #
    # Everything above this line is San Francisco's two inventories in one id
    # space. This is the first time the seed holds rows from a second, and it
    # goes through the same `accepts` / `emit` pair as everything else -- which
    # is the point of the contract, and is why this block is short.
    #
    # INGESTING AND SHIPPING ARE TWO DECISIONS. `--sj-extent full` reads all
    # 344,879 records and is what proves the contract carries the corpus;
    # `--sj-extent downtown` is what ships, and the window it applies is stated
    # in `SJ_SHIP_WINDOW` with its reasoning. See ERRATA E176.
    if sj_rows is not None:
        sj = SanJoseStreetTreeAdapter(sj_rows, limit=limit)
        for record in sj.records():
            if not accepts(record):
                continue
            if sj_window is not None and not (
                sj_window["min_lat"] <= record.lat <= sj_window["max_lat"]
                and sj_window["min_lon"] <= record.lon <= sj_window["max_lon"]
            ):
                stats["sj_outside_ship_window"] += 1
                continue
            if record.source_ref is not None:
                if already_seen(record):
                    stats["dropped_dupe_treeid"] += 1
                    continue
                mark_seen(record)
            emit(record)
            stats["sj_kept"] += 1
            if sj.stats["source_rows"] % 50000 == 0:
                log(f"  san jose: {sj.stats['source_rows']:,} rows read / "
                    f"{stats['kept']:,} kept in total ({time.time() - t0:.0f}s)")

        stats["sj_source_rows"] = sj.stats["source_rows"]
        stats["dropped_no_coords"] += sj.stats["dropped_no_coords"]
        for key, value in sj.stats.items():
            if key not in ("source_rows", "dropped_no_coords"):
                stats["sj_" + key] = value
        log(f"san jose: {sj.stats['source_rows']:,} rows read, "
            f"{stats['sj_outside_ship_window']:,} outside the ship window, "
            f"{sj.stats['kind_inferred_from_absent_species']:,} rows whose kind is ours")

    # ---- the THIRD city, and the first outside California. ----------------
    #
    # Structurally this block is the same shape as San Jose's above, which is
    # the contract paying off a second time. What is different is entirely
    # inside the adapter: NYC is TWO datasets joined on a foreign id, and the
    # borough filter below is a PLANTING SPACES fact, so a tree point that
    # joins to nothing cannot be placed in a borough at all.
    #
    # INGESTING AND SHIPPING ARE TWO DECISIONS, exactly as for San Jose.
    # `--nyc-borough` exists because the distribution architecture for a city
    # this size is an open design question and per-borough numbers are what
    # that design round needs. Nothing about the borough is baked in: it is one
    # flag, and the whole city is `--nyc-borough ""`.
    if nyc_rows is not None:
        structures = None
        if nyc_structures and nyc_structures.lower() != "all":
            structures = {s.strip() for s in nyc_structures.split(",") if s.strip()}
        nyc = NYCTreePointAdapter(
            nyc_rows, nyc_spaces, horizon_year, limit=limit,
            structures=structures, borough=nyc_borough or None,
            with_raw=with_city_raw, borough_resolver=nyc_boroughs,
        )
        for record in nyc.records():
            if not accepts(record):
                continue
            if record.source_ref is not None:
                if already_seen(record):
                    stats["dropped_dupe_treeid"] += 1
                    continue
                mark_seen(record)
            emit(record)
            stats["nyc_kept"] += 1
            if nyc.stats["source_rows"] % 100000 == 0:
                log(f"  nyc: {nyc.stats['source_rows']:,} rows read / "
                    f"{stats['kept']:,} kept in total ({time.time() - t0:.0f}s)")

        stats["nyc_source_rows"] = nyc.stats["source_rows"]
        stats["dropped_no_coords"] += nyc.stats["dropped_no_coords"]
        for key, value in nyc.stats.items():
            if key not in ("source_rows", "dropped_no_coords"):
                stats["nyc_" + key] = value

    # ---- #95, applied. One spelling per case-folded value in the columns the app
    # compares against a literal. `WHERE plant_type = 'Tree'` used to drop three
    # rows spelled `tree`; the seed contract now fails if any such pair returns.
    stats["case_normalised_values"] = 0
    column_index = {name: index for index, name in enumerate(
        ["id", "uuid", "id_space", "external_ref", "source", "inventory_source", "lat", "lon", "address", "site_type",
         "neighborhood_id", "status", "species_current", "planted_year", "planted_on",
         "dbh_city_cm_min", "dbh_city_cm_max", "site_lineage", "verification_state"]
        + [name for name, _ in CITY_RECORD_COLUMNS]
    )}
    for column in NORMALISED_SEED_COLUMNS:
        mapping = {k: v for k, v in canonical_case_map(case_counts[column]).items() if k != v}
        if not mapping:
            continue
        index = column_index[column]
        changed = 0
        for row in tree_rows:
            replacement = mapping.get(row[index])
            if replacement is not None:
                row[index] = replacement
                changed += 1
        stats["case_normalised_values"] += changed
        log(f"#95 {column}: folded {len(mapping)} case-variant spelling(s) over "
            f"{changed:,} rows -> {sorted(set(mapping.values()))}")

    # ---- the vocabulary this file's own rows are checked against.
    #
    # Written for EXACTLY the inventories that contributed rows, so `SELECT *
    # FROM inventories` describes the file rather than the builder. This is what
    # replaced `CHECK (inventory_source IN ('city','datasf'))`: the constraint is
    # now a foreign key into these rows, and a new city is a row here instead of
    # an edit to a shipped schema (ERRATA E169 blocker 2, E176).
    #
    # BEFORE the trees insert, because `PRAGMA foreign_keys = ON` is in the
    # schema and `trees.inventory_source REFERENCES inventories(id)` is enforced
    # at insert time. A parent written afterwards is a build that fails on its
    # first row.
    contributing = sorted(contributing_inventories)
    if not contributing:
        die("no inventory contributed a row; the seed would have an empty vocabulary")
    spaces = sorted({INVENTORIES[i].id_space for i in contributing})
    missing_dim_city = [s for s in spaces if s not in DIM_CITY]
    if missing_dim_city:
        die(
            f"no dim_city row registered for id space(s) {missing_dim_city!r} in "
            f"DIM_CITY -- civic facts are entered, never derived"
        )
    # dim_city first: id_spaces.city_id is a foreign key into it, and
    # `PRAGMA foreign_keys = ON` (top of SCHEMA_SQL) enforces that at insert
    # time. Inserted in `spaces`' own sorted order, which is what keeps this
    # build deterministic -- `dim_city.id` is the table's rowid, and a fixed
    # insertion order reproduces the same rowids on every rebuild.
    city_id_by_space = {}
    for s in spaces:
        city = DIM_CITY[s]
        cur = conn.execute(
            "INSERT INTO dim_city(slug,display_name,state,county,urban_forestry_url) "
            "VALUES (?,?,?,?,?)",
            (city["slug"], city["display_name"], city["state"], city["county"],
             city["urban_forestry_url"]),
        )
        city_id_by_space[s] = cur.lastrowid
    conn.executemany(
        "INSERT INTO id_spaces(id,identity_prefix,note,city_id) VALUES(?,?,?,?)",
        [
            (s, ID_SPACES[s].identity_prefix, ID_SPACES[s].note, city_id_by_space[s])
            for s in spaces
        ],
    )

    # ---- dim_region (s17), and the key every tree row is about to resolve ----
    # After `dim_city` because `dim_region.city_id` is a foreign key into it and
    # `PRAGMA foreign_keys = ON`; before the flush because
    # `trees.region_id` is a foreign key into THIS and is NOT NULL.
    #
    # Registered in `spaces`' sorted order and, within a space, in REGIONS'
    # declared order -- the same determinism `dim_city` above relies on, for the
    # same reason: these rowids are `trees.region_id`'s values and a rebuild
    # must reproduce them.
    missing_regions = [s for s in spaces if s not in REGIONS]
    if missing_regions:
        die(
            f"no dim_region row registered for id space(s) {missing_regions!r} in "
            f"REGIONS -- a published unit's identity is entered, never derived"
        )
    region_id_by_key: dict = {}
    region_rows = []
    for s in spaces:
        entries = REGIONS[s]
        sole = len(entries) == 1
        for entry in entries:
            if entry["level"] not in REGION_LEVELS:
                die(f"region {entry['pack_id']!r} has level {entry['level']!r}, "
                    f"not one of {REGION_LEVELS}")
            cur = conn.execute(
                "INSERT INTO dim_region(pack_id,display_name,level,city_id) VALUES(?,?,?,?)",
                (entry["pack_id"], entry["display_name"], entry["level"],
                 city_id_by_space[s]),
            )
            region_id = cur.lastrowid
            # `None` -- "the id space's sole region" -- is registered only when
            # the space HAS exactly one. A space with several and a record that
            # named none is a stop, not a guess: `resolve_region_ids` finds no
            # key and dies with the count.
            if sole:
                region_id_by_key[(s, None)] = region_id
            for source_name in entry["source_names"]:
                region_id_by_key[(s, source_name)] = region_id
            region_rows.append((s, entry["pack_id"], entry["level"]))
    conn.commit()
    log("regions: " + ", ".join(
        f"{pack} ({level}) in {space}" for space, pack, level in region_rows))

    resolve_region_ids(tree_rows, region_id_by_key)
    conn.executemany(
        "INSERT INTO inventories(id,id_space,name,url) VALUES(?,?,?,?)",
        [(i, INVENTORIES[i].id_space, INVENTORIES[i].name, INVENTORIES[i].url)
         for i in contributing],
    )
    conn.commit()
    log(f"inventories: {', '.join(contributing)} in id space(s) {', '.join(spaces)}")

    flush(conn, species_by_key, tree_rows, rtree_rows, assertion_rows)

    # species rows may have gained a common_name after first insert
    conn.executemany(
        "UPDATE species SET common_name = COALESCE(common_name, ?) WHERE id = ?",
        [(sp["common_name"], sp["id"]) for sp in species_by_key.values() if sp["common_name"]],
    )
    conn.commit()

    # ------------------------------------------------- species content (sec 8)
    # `strict` demands that every fixture entry lands on a species the seed carries.
    # That holds for the DataSF export, which is what the fixtures were sourced
    # against. It cannot hold for the city layer: it inventories 62,000 fewer
    # records and simply does not contain some of those species, so 75 of the 577
    # sourced entries have nothing to attach to. Those are absences in the corpus,
    # not drift between the fixtures and the parser, and the count is reported
    # rather than swallowed. The name-mismatch check stays strict on both paths --
    # a fixture claiming a different name for a uuid the seed does carry is still a
    # build failure.
    nyc_fixtures = ()
    if nyc_rows is not None:
        nyc_fixtures = ((os.path.join(fixtures_dir, "species", "nyc_species.yaml"), False),)
    species_content, content_stats = load_species_content(
        fixtures_dir, species_by_key, strict=(source == "datasf" and not limit),
        extra_files=nyc_fixtures,
    )
    if content_stats["absent"]:
        log(f"species fixtures: {content_stats['absent']} sourced entries name a species "
            f"this seed does not carry (source={source})")
    id_by_uuid = {sp["uuid"]: sp["id"] for sp in species_by_key.values()}
    conn.executemany(
        "UPDATE species SET family=?, leaf_retention=?, id_tips=?, seasonal=?, "
        "care_notes=?, curated=? WHERE id=?",
        [
            (
                row["family"],
                # NULL, not '' and not a sentinel: the column means "no source
                # states this species' habit" and the app must be able to tell
                # that apart from every real value (ERRATA E9).
                row["leaf_retention"],
                _compact_json(row["id_tips"]),
                _compact_json(row["seasonal"] or {key: [] for key in SEASONAL_KEYS}),
                _compact_json(row["care_notes"]),
                row["curated"],
                id_by_uuid[species_uuid],
            )
            for species_uuid, row in sorted(species_content.items())
        ],
    )
    conn.commit()
    log(
        f"species content: leaf_retention on {content_stats['leaf_retention']}, "
        f"family on {content_stats['family']}, curated {content_stats['curated']} "
        f"of {len(species_by_key)} species"
    )

    # ------------------------------------------------------- species trigrams
    # Strictly after the content pass above: it is the last thing that can
    # change a name, and the index has to describe the names that ship (E165).
    trigram_rows = build_species_trigram_index(conn)
    log(f"species trigrams: {trigram_rows:,} rows")

    # ------------------------------------------------------------ stub ceiling
    species_bearing_rows = stats["parsed_rows"] + stats["stub_rows"]
    stub_pct = (
        100.0 * stats["stub_rows"] / species_bearing_rows if species_bearing_rows else 0.0
    )
    stub_pct_all = 100.0 * stats["stub_rows"] / stats["kept"] if stats["kept"] else 0.0

    # ------------------------------------------------------- species map table
    map_rows = []
    spaces_by_string = {}
    for qs_string, info in sorted(
        qspecies_stats.items(), key=lambda kv: (-kv[1]["count"], kv[0])
    ):
        spaces_by_string[qs_string] = info["spaces"]
        kind = species_map_kind(info["kinds"], info["species_id"])
        map_rows.append(
            (
                qs_string,
                info["species_id"],
                info["species_uuid"],
                round(info["confidence"], 2),
                1 if kind == "stub" else 0,
                1 if kind == "placeholder" else 0,
                1 if kind == "non_taxon" else 0,
                info["count"],
            )
        )
    conn.executemany(
        "INSERT INTO species_map(qspecies_string,species_id,species_uuid,confidence,"
        "is_stub,is_placeholder,is_non_taxon,tree_count) VALUES(?,?,?,?,?,?,?,?)",
        map_rows,
    )

    # ONE CHECKED-IN FILE PER ID SPACE, EACH NAMED FOR THE SPACE IT DESCRIBES.
    # `sf_species_map.csv` is San Francisco's vocabulary -- the `Genus species ::
    # Common name` packed strings the DataSF export publishes -- and San Jose's
    # `NAMESCIENTIFIC` is a different vocabulary from a different publisher.
    # Writing both into a file called `sf_species_map.csv` would put another
    # city's strings under San Francisco's name, which is the same class of quiet
    # falsehood as a provenance line naming the wrong inventory. The `species_map`
    # TABLE in the database holds every string in the file, because that table is
    # a property of the file rather than of any one city.
    #
    # A BUILD NEVER WRITES THE CHECKED-IN COPY UNLESS ASKED TO. These CSVs used
    # to be rewritten as a side effect of every run, which meant any build --
    # including a `--limit` measurement run that reads a fraction of the source
    # and therefore sees a fraction of the strings -- silently rewrote a tracked
    # file. An NYC measurement build dirtied `Fixtures/sf_species_map.csv` with
    # 375 of its 419 lines changed, and the only thing that caught it was an
    # agent noticing `git status`. A build's inputs are not its outputs: the
    # derived copy goes to the git-ignored build directory, drift against the
    # checked-in copy is reported, and updating the checked-in copy is a
    # deliberate act (`--write-species-map`).
    map_out_dir = fixtures_dir if write_species_map else os.path.join(fixtures_dir, "build")
    os.makedirs(map_out_dir, exist_ok=True)
    for space_id, file_name in SPECIES_MAP_FILES.items():
        rows_for_space = [
            row for row in map_rows if space_id in spaces_by_string.get(row[0], set())
        ]
        if not rows_for_space:
            continue
        text = species_map_csv(rows_for_space)
        path = os.path.join(map_out_dir, file_name)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        log(f"wrote {path} ({len(rows_for_space)} distinct species strings "
            f"in id space {space_id})")

        tracked = os.path.join(fixtures_dir, file_name)
        if write_species_map or not os.path.exists(tracked):
            continue
        with open(tracked, encoding="utf-8", newline="") as fh:
            current = fh.read()
        # Gated on the KEYED comparison below, never on raw bytes. A byte
        # comparison also fires for a difference in line terminators or column
        # quoting, i.e. for two files that say exactly the same thing -- and a
        # note that fires on every build is one its reader learns to skim past,
        # which is the failure this whole branch is about.
        removed, added, changed = _species_map_drift(current, text)
        # `any(...)`, not the tuple itself: a tuple of three EMPTY lists is still
        # a non-empty tuple and therefore truthy, so gating on the return value
        # directly fired the note at 0/0/0 -- the exact defect this gate was
        # added to remove, reintroduced by the fix for it. Caught by running the
        # build whose answer was known (a full --source city build derives the
        # checked-in map exactly) rather than by reading the diff.
        if any((removed, added, changed)):
            log(f"NOTE: {tracked} differs from what this build derived: "
                f"{len(removed)} rows only in the checked-in copy, {len(added)} only "
                f"in this build's, {len(changed)} mapped differently. The checked-in "
                f"copy was NOT touched. If this build read the whole source and the "
                f"difference is intended, rerun with --write-species-map to update it.")

    # ---- which inventory this seed is, and WHEN it was taken.
    #
    # `trees_snapshot_on` is the one key nothing else can substitute for. A seed
    # with no snapshot date is what made "is our data stale" unanswerable the last
    # time it was asked: the file could be a day old or a year old and no reader,
    # inside the app or outside it, could tell. It is a date the *source* was read,
    # never a clock reading at build time, so rebuilding this seed in 2030 from the
    # same cache still says 2026.
    #
    # Which of San Francisco's two inventories this build read, as the REGISTRY
    # describes it. `sf_inventory` above is the id; this is the whole record, and
    # it is what the `trees_source*` keys below are written from.
    sf_inv = INVENTORIES[sf_inventory]
    if source == "city":
        source_meta = {
            # The inventory id, which is now `sf_city` and used to be `city`
            # (E169: a poor identifier once there is more than one city). It is
            # the same string `trees.inventory_source` stores and the same key
            # `inventory_<id>_*` below is built from, and those three agreeing is
            # what lets `InventorySource(id:seedMeta:)` resolve a row's
            # provenance without knowing any city's name in advance.
            #
            # READ FROM THE REGISTRY, NOT WRITTEN AGAIN HERE (s17). These three
            # keys were literals -- `"sf_city"`, the name spelled out a second
            # time, and a module constant for the url -- while
            # `INVENTORIES["sf_city"]` already held all three, and the comment
            # directly above was asserting that they agree. That is a comment
            # claiming an invariant nothing enforced, on a value the seed's own
            # provenance resolution depends on: rename the inventory in the
            # registry and this key kept the old string, silently, in every
            # published file. The registry is the one source now, so the
            # comment's claim is true by construction rather than by care.
            "trees_source": sf_inv.id,
            "trees_source_name": sf_inv.name,
            "trees_source_url": sf_inv.url,
            "trees_source_map_url": CITY_LAYER_MAP_URL,
            "trees_snapshot_on": city_meta["extracted_on"],
            "trees_source_last_edit_on": str(city_meta.get("server_last_edit_date") or ""),
            "trees_source_feature_count": str(city_meta.get("server_feature_count") or ""),
            # Which trees exist is the city's answer; these seven columns are the
            # export's, for the records both list. See `load_datasf_attributes`.
            "attributes_source": INVENTORIES["sf_datasf"].id,
            "attributes_dataset_id": TREES_DATASET_ID,
            "attributes_snapshot_on": NOW[:10],
            "attributes_columns": ",".join(ENRICHED_COLUMNS),
            "rows_enriched": str(stats["enriched_rows"]),
            "rows_city_only": str(stats["city_only_rows"]),
            # The vacant planting sites, which are the export's rows and not the
            # layer's -- it has no such category. `trees.inventory_source` says
            # which inventory each row came from; these are the totals.
            "sites_source": INVENTORIES["sf_datasf"].id,
            # The second pass's own row accounting, so the seed contract can close
            # the arithmetic over both passes: rows read = rows shipped + rows
            # dropped, with nothing unexplained on either side.
            "export_vacant_rows_read": str(stats["export_vacant_rows"]),
            "rows_from_sf_city":
                str(stats["kept"] - stats["export_vacant_carried"] - stats["sj_kept"]),
            "rows_from_sf_datasf": str(stats["export_vacant_carried"]),
            "export_vacant_sites_excluded_city_lists_tree":
                str(stats["export_vacant_city_lists_tree"]),
            "export_vacant_sites_already_city_listed":
                str(stats["export_vacant_city_lists_site"]),
            # One name/url/date triple per inventory the file actually holds rows
            # from, keyed by the same identifier `trees.inventory_source` stores.
            # The app resolves a row's provenance line through these, so a seed
            # built from two inventories can say which one each record came from
            # instead of putting one name over all of them.
            "inventory_sf_city_name": INVENTORIES["sf_city"].name,
            "inventory_sf_city_url": INVENTORIES["sf_city"].url,
            "inventory_sf_city_snapshot_on": city_meta["extracted_on"],
            # Which numbering scheme this inventory's ids -- and therefore its
            # uuids -- are drawn from. Both of San Francisco's are `sf`, on
            # purpose: they publish the same TreeID space, so a record listed by
            # both keeps one identity across a source switch (E156). A second
            # CITY declares its own space, and a seed holding rows from two
            # spaces is a seed whose uuids were derived two ways.
            "inventory_sf_city_id_space": INVENTORIES["sf_city"].id_space,
            "inventory_sf_datasf_name": INVENTORIES["sf_datasf"].name,
            "inventory_sf_datasf_url": INVENTORIES["sf_datasf"].url,
            "inventory_sf_datasf_snapshot_on": NOW[:10],
            "inventory_sf_datasf_id_space": INVENTORIES["sf_datasf"].id_space,
            # Nothing is unavailable outright: the two state-plane coordinates are
            # the same point as lat/lon and were never ingested from either source.
            "columns_absent_from_source": "",
        }
    else:
        source_meta = {
            "trees_source": sf_inv.id,
            "trees_source_name": sf_inv.name,
            "trees_dataset_id": TREES_DATASET_ID,
            "trees_source_url": sf_inv.url,
            # The DataSF export publishes no per-row as-of date; the snapshot date
            # is the dataset's own last update, which is what SEED_EPOCH is set to
            # (ERRATA E1). Stated rather than left to be inferred from `generated_at`.
            "trees_snapshot_on": NOW[:10],
            "rows_from_sf_datasf": str(stats["kept"] - stats["sj_kept"]),
            "inventory_sf_datasf_name": INVENTORIES["sf_datasf"].name,
            "inventory_sf_datasf_url": INVENTORIES["sf_datasf"].url,
            "inventory_sf_datasf_snapshot_on": NOW[:10],
            "inventory_sf_datasf_id_space": INVENTORIES["sf_datasf"].id_space,
            "columns_absent_from_source": "",
        }

    # San Jose's own receipt keys, written only when San Jose contributed rows.
    # Same `inventory_<id>_*` shape as San Francisco's two, because the app
    # resolves a row's provenance line by that shape and knows no city's name.
    sj_meta_keys = {}
    if sj_rows is not None:
        sj_meta_keys = {
            "inventory_sj_street_tree_name": INVENTORIES["sj_street_tree"].name,
            "inventory_sj_street_tree_url": INVENTORIES["sj_street_tree"].url,
            "inventory_sj_street_tree_snapshot_on": sj_meta.get("extracted_on", ""),
            "inventory_sj_street_tree_id_space": INVENTORIES["sj_street_tree"].id_space,
            "inventory_sj_street_tree_licence": "CC-BY",
            "rows_from_sj_street_tree": str(stats["sj_kept"]),
            # THE TWO NUMBERS THAT MUST NOT BE CONFLATED (#129). The first is
            # what the ingest read and validated; the second is what a phone
            # gets. A reader who sees only one of them cannot tell a corpus that
            # was never fetched from one that was deliberately not shipped.
            "sj_source_feature_count": str(sj_meta.get("server_feature_count", "")),
            "sj_rows_read": str(stats["sj_source_rows"]),
            "sj_rows_shipped": str(stats["sj_kept"]),
            "sj_rows_outside_ship_window": str(stats["sj_outside_ship_window"]),
            "sj_ship_extent": sj_extent,
            "sj_ship_window": json.dumps(sj_window) if sj_window else "",
            # The adapter's own accounting of where San Jose disagrees with
            # itself. OVER THE ROWS READ, not the rows shipped: the adapter
            # classifies every record it yields and the ship window is applied
            # after, so under `--sj-extent downtown` these describe the whole
            # 344,879-record corpus and `sj_rows_shipped` describes the file.
            "sj_kind_from_vacancy_flag": str(stats.get("sj_kind_from_vacancy_flag", 0)),
            "sj_kind_from_species_vocabulary":
                str(stats.get("sj_kind_from_species_vocabulary", 0)),
            "sj_kind_inferred_from_absent_species":
                str(stats.get("sj_kind_inferred_from_absent_species", 0)),
            "sj_vacant_sites_naming_a_taxon":
                str(stats.get("sj_vacant_sites_naming_a_taxon", 0)),
            "sj_planting_sites_with_a_trunk_diameter":
                str(stats.get("sj_planting_sites_with_a_trunk_diameter", 0)),
            "sj_trunk_diameter_over_ceiling":
                str(stats.get("sj_trunk_diameter_over_ceiling", 0)),
        }
    nyc_meta_keys = {}
    if nyc_rows is not None:
        nyc_meta_keys = {
            "inventory_nyc_tree_points_name": INVENTORIES["nyc_tree_points"].name,
            "inventory_nyc_tree_points_url": INVENTORIES["nyc_tree_points"].url,
            "inventory_nyc_tree_points_snapshot_on": nyc_meta.get("extracted_on", ""),
            "inventory_nyc_tree_points_id_space": INVENTORIES["nyc_tree_points"].id_space,
            # NOT a licence string: both datasets publish `license: null`. The
            # operative grant is the NYC.gov Data Mine terms, which REQUIRE the
            # City to be notified and a verbatim disclaimer to be carried
            # wherever the app is downloaded. See the investigation note §2.
            "inventory_nyc_tree_points_licence": "NYC Open Data / Data Mine terms; "
                                                 "notification + verbatim disclaimer required",
            "nyc_rows_read": str(stats["nyc_source_rows"]),
            "nyc_rows_shipped": str(stats["nyc_kept"]),
            "nyc_borough": nyc_borough or "(whole city)",
            "nyc_structures": nyc_structures,
            "nyc_joined_to_planting_space": str(stats.get("nyc_joined_to_planting_space", 0)),
            "nyc_no_planting_space_match": str(stats.get("nyc_no_planting_space_match", 0)),
            # How many rows this file ships as `dead_reported` -- a `Full`
            # structure NYC rates `Dead`, standing over a pavement (R19). It was
            # `nyc_standing_dead_mapped_to_alive` and it counted an information
            # LOSS; s17's condition seam closed that, so the key now counts a
            # fact about the file rather than an apology for it.
            "nyc_standing_dead": str(stats.get("nyc_standing_dead", 0)),
            # How many NYC rows carry a condition claim at all, and how many
            # leave it to `None`. `Unknown` (33,132 whole-dataset) is the second.
            "nyc_condition_stated": str(stats.get("nyc_condition_stated", 0)),
            "nyc_condition_not_stated": str(stats.get("nyc_condition_not_stated", 0)),
            # The borough rides on the record in `trees.city_raw`, ALWAYS -- not
            # only under --with-city-raw, and not merely as a build-time filter.
            # The distribution design makes a borough the published unit.
            "nyc_borough_carried": str(stats.get("nyc_borough_carried", 0)),
            "nyc_no_borough_to_carry": str(stats.get("nyc_no_borough_to_carry", 0)),
            # RULING D18's four outcomes, so a pack's completeness is a fact in
            # the file rather than something to recompute.
            "nyc_borough_stated": str(stats.get("nyc_borough_stated_by_planting_space", 0)),
            "nyc_borough_point_in_polygon": str(stats.get("nyc_borough_from_point_in_polygon", 0)),
            "nyc_borough_nearest_polygon": str(stats.get("nyc_borough_from_nearest_polygon", 0)),
            "nyc_borough_unassigned": str(stats.get("nyc_borough_unassigned", 0)),
            "nyc_borough_geometry_agrees": str(stats.get("nyc_borough_geometry_agrees", 0)),
            "nyc_borough_geometry_disagrees": str(stats.get("nyc_borough_geometry_disagrees", 0)),
            # RULING D19: the publisher's own staleness, recorded.
            "nyc_tree_points_rows_updated_at":
                str((nyc_meta.get("tree_points") or {}).get("rows_updated_at", "")),
            "nyc_planting_spaces_rows_updated_at":
                str((nyc_meta.get("planting_spaces") or {}).get("rows_updated_at", "")),
            "nyc_planting_spaces_duplicates_dropped":
                str((nyc_meta.get("planting_spaces") or {}).get("duplicate_globalids_dropped", "")),
            "nyc_dedupe_rule":
                str((nyc_meta.get("planting_spaces") or {}).get("dedupe_rule", "")),
            "nyc_planted_date_beyond_horizon":
                str(stats.get("nyc_planted_date_beyond_horizon", 0)),
        }

    source_meta = {**source_meta, **sj_meta_keys, **nyc_meta_keys}

    # ---- coverage, standardised (s17) -----------------------------------
    # WHAT R37'S TRAILING CLAUSE ASKED FOR, PAID NOW. It reads: "manifest
    # `coverage` currently maps the ad-hoc `seed_meta.sj_ship_extent` key by
    # hand; when a third city lands, `build_seed.py` should write
    # `coverage_<id_space>` keys and the publisher's `COVERAGE_KEYS` shim
    # retires." New York is that third city and this is that round.
    #
    # THE DIVERGENCE THIS CLOSES WAS LIVE AND SILENT. `SeedCities.coverage`
    # (Swift) already preferred `coverage_<id_space>` and fell back to the
    # legacy per-city name; `Tools/publish_cities.py` read the legacy name and
    # ONLY the legacy name. So the bundled row and the published manifest agreed
    # about San Jose purely because nothing had ever written the standardised
    # key -- the day anything did, the app's own bundle and the catalogue would
    # have disagreed about how much of a city a reader had, with no error
    # anywhere. The publisher now prefers the same key in the same order as the
    # app, and `Tools/test_publish_cities.py` pins the two orders together.
    #
    # Absent still means full; the key is written explicitly anyway, because
    # "nobody stated it" and "somebody measured it and it was all of it" are
    # different facts and only one of them survives a source changing shape.
    coverage_keys = {}
    for space in spaces:
        if space == "us-ca-sj":
            # `sj_extent` is this build's own flag and is the honest answer for
            # it: `downtown` ships the SJ_SHIP_WINDOW box, `full` ships the
            # whole corpus. `none` contributes no rows and no space here.
            coverage_keys[f"coverage_{space}"] = (
                "full" if sj_extent == "full" else sj_extent
            )
        else:
            coverage_keys[f"coverage_{space}"] = "full"

    # ---- per-inventory completeness, standardised (s17) ------------------
    # `rows_from_<inventory>` has always said what SHIPPED. What the source says
    # it PUBLISHES was recorded under two ad-hoc, differently-shaped names --
    # `trees_source_feature_count` (San Francisco's, and global, so it could only
    # ever describe one inventory) and `sj_source_feature_count` (San Jose's,
    # prefixed by hand) -- so "did we ship all of it" was a question that could
    # be asked of one inventory at a time and never uniformly. With New York
    # about to add two more inventories in a third space, the ad-hoc shape does
    # not extend.
    #
    # Same `inventory_<id>_*` shape as the name/url/date triple beside it, keyed
    # by the same identifier `trees.inventory_source` stores. Written ONLY where
    # the source actually publishes a count: an absent key means the source does
    # not say, which is a different fact from a count of zero and must not be
    # spelled as one. `Tools/verify_seed.py` check 1d reads these.
    #
    # BOTH LEGACY KEYS ARE KEPT. `Cypress/Data/Tests/DataGates.swift` reads
    # `trees_source_feature_count` today; retiring it here would break a gate in
    # the same change that adds a generation, and the two facts are not in
    # conflict -- the new key is the general form of the old one.
    completeness_keys = {}
    if source == "city" and city_meta.get("server_feature_count"):
        completeness_keys["inventory_sf_city_source_feature_count"] = \
            str(city_meta["server_feature_count"])
    if sj_rows is not None and sj_meta.get("server_feature_count"):
        completeness_keys["inventory_sj_street_tree_source_feature_count"] = \
            str(sj_meta["server_feature_count"])

    source_meta = {**source_meta, **coverage_keys, **completeness_keys}

    meta = {
        "generator": "Tools/build_seed.py",
        "generated_at": NOW,
        **source_meta,
        "neighborhoods_dataset_id": NEIGHBORHOODS_DATASET_ID,
        "neighborhoods_source_url": NEIGHBORHOODS_GEOJSON_URL,
        "sf_bbox": json.dumps(SF_BBOX),
        "ns_tree_uuid": str(NS_TREE),
        "ns_species_uuid": str(NS_SPECIES),
        "city_raw_populated": "1" if with_city_raw else "0",
        "source_rows": str(stats["source_rows"]),
        "case_normalised_values": str(stats["case_normalised_values"]),
        "case_normalised_columns": ",".join(NORMALISED_SEED_COLUMNS),
        "rows_kept": str(stats["kept"]),
        "dropped_no_coords": str(stats["dropped_no_coords"]),
        "dropped_out_of_bbox": str(stats["dropped_out_of_bbox"]),
        "dropped_dupe_treeid": str(stats["dropped_dupe_treeid"]),
        "vacant_site_rows": str(stats["status_vacant_site"]),
        # One receipt key per status the file actually holds (s17). The seed has
        # always stated how many vacant sites it carries; it could not state how
        # many standing dead trees it carries, because until `status_for_record`
        # it could not hold one.
        "rows_status_alive": str(stats["status_alive"]),
        "rows_status_declining": str(stats["status_declining"]),
        "rows_status_dead_reported": str(stats["status_dead_reported"]),
        "rows_status_removed": str(stats["status_removed"]),
        "rows_with_condition_stated": str(stats["condition_stated"]),
        "non_taxon_rows": str(stats["non_taxon_rows"]),
        # ---- what the ingest contract made countable ------------------------
        # These three are not new facts about the corpus. They are the same rows
        # that were always here, split by WHO SAID SO -- which was not expressible
        # before `InventoryRecord.kind_basis` existed, so the whole of it sat
        # inside `vacant_site_rows` as a single number nobody could argue with.
        #
        #   ..._stated_by_source     the source describes a planting site:
        #                            `Tree(s) ::` on a Permitted Site, the city
        #                            layer's literal `BOTANICAL = 'Potential Site'`.
        #   ..._inferred_from_absent_species
        #                            THE SOURCE SAID NO SUCH THING. Its species
        #                            field was blank or read `Tree`, and the
        #                            ingest turned that silence into an empty hole
        #                            in the pavement. 1,326 of the export's `::`
        #                            rows carry `qLegalStatus = DPW Maintained`.
        #   records_not_a_tree       the source says the thing growing there is a
        #                            shrub, and `trees.status` has no value for
        #                            that, so `STATUS_FOR_KIND` calls it `alive`.
        #
        # Together they are the size of task #94, in the file, per build.
        "planting_sites_stated_by_source": str(stats["planting_sites_stated_by_source"]),
        "planting_sites_inferred_from_absent_species":
            str(stats["planting_sites_inferred_from_absent_species"]),
        "records_not_a_tree": str(stats["records_not_a_tree"]),
        "ingest_contract": "Tools/inventory_contract.py",
        # The id space the PRIMARY inventory's uuids are derived in, and the
        # prefix they are derived with.
        #
        # THESE TWO ARE NO LONGER A STATEMENT ABOUT THE WHOLE FILE, and a reader
        # who treats them as one is wrong for every San Jose row. They are kept
        # because a seed built before the v14 pass has nothing else, and because
        # they are still right for a single-city file. The per-row answer is
        # `trees.id_space` joined to `id_spaces.identity_prefix`, and
        # `id_spaces_in_file` below says outright when there is more than one.
        "identity_id_space": require_inventory(sf_inventory).id_space,
        "identity_prefix": ID_SPACES[require_inventory(sf_inventory).id_space].identity_prefix,
        "id_spaces_in_file": ",".join(
            sorted({INVENTORIES[i].id_space for i in contributing_inventories})
        ),
        "species_with_leaf_retention": str(content_stats["leaf_retention"]),
        "species_with_family": str(content_stats["family"]),
        "species_curated": str(content_stats["curated"]),
        "stub_rows": str(stats["stub_rows"]),
        "stub_pct_of_species_rows": f"{stub_pct:.4f}",
        "stub_ceiling_pct": str(STUB_CEILING_PCT),
        "distinct_qspecies": str(len(qspecies_stats)),
        # Population of each city column, so a future rebuild can be compared
        # against this one without re-reading a 53 MB CSV.
        **{
            "city_" + seed_column + "_rows": str(stats["city_" + csv_column])
            for seed_column, csv_column in CITY_RECORD_COLUMNS
        },
        "species_count": str(len(species_by_key)),
        "species_trigram_rows": str(trigram_rows),
        "schema_contract": "Fixtures/seed/schema.sql",
    }
    conn.executemany("INSERT INTO seed_meta(key,value) VALUES(?,?)", sorted(meta.items()))
    conn.commit()

    log("ANALYZE + VACUUM ...")
    conn.execute("ANALYZE")
    conn.commit()
    conn.execute("VACUUM")
    conn.commit()
    conn.close()

    size_mb = os.path.getsize(db_path) / 1e6

    # ------------------------------------------------------------------ report
    print()
    print("=" * 66)
    print("BUILD SUMMARY")
    print("=" * 66)
    print(f"  source                 --source {source}  ({meta['trees_source_name']})")
    print(f"  snapshot taken         {meta['trees_snapshot_on']}")
    print(f"  source url             {meta['trees_source_url']}")
    print(f"  neighborhoods dataset  {NEIGHBORHOODS_DATASET_ID} ({len(neighborhoods)} polygons)")
    print(f"  SF bbox                lat [{SF_BBOX['min_lat']}, {SF_BBOX['max_lat']}]  "
          f"lon [{SF_BBOX['min_lon']}, {SF_BBOX['max_lon']}]")
    print(f"  city_raw               {'populated' if with_city_raw else 'NULL (--with-city-raw to populate)'}")
    if sj_rows is not None:
        print(f"  san jose               --sj-extent {sj_extent}  "
              f"({stats['sj_source_rows']:,} read, {stats['sj_kept']:,} shipped, "
              f"{stats['sj_outside_ship_window']:,} outside the ship window)")
        if sj_window:
            print(f"  SJ ship window         lat [{sj_window['min_lat']}, {sj_window['max_lat']}]  "
                  f"lon [{sj_window['min_lon']}, {sj_window['max_lon']}]")
    print(f"  source rows read       {stats['source_rows']:,}")
    print(f"    dropped, no coords   {stats['dropped_no_coords']:,}")
    print(f"    dropped, out of bbox {stats['dropped_out_of_bbox']:,}")
    print(f"    dropped, dup TreeID  {stats['dropped_dupe_treeid']:,}")
    if source == "city":
        print(f"  export vacant sites    {stats['export_vacant_rows']:,} read")
        print(f"    carried through      {stats['export_vacant_carried']:,}")
        print(f"    excluded, city lists a tree there "
              f"{stats['export_vacant_city_lists_tree']:,}")
        print(f"    already in, city lists it empty too "
              f"{stats['export_vacant_city_lists_site']:,}")
    print(f"  trees written          {stats['kept']:,}")
    if sj_rows is not None:
        print(f"    from san jose        {stats['sj_kept']:,}")
    if source == "city":
        print(f"    from city layer      "
              f"{stats['kept'] - stats['export_vacant_carried'] - stats['sj_kept']:,}")
        print(f"    from datasf export   {stats['export_vacant_carried']:,}")
    # Every status the build produced, in the CHECK constraint's own order, and
    # only the ones that happened. A zero line for `dead_reported` would read as
    # a claim that the sources were asked and said none; they were not asked,
    # because neither SF nor SJ publishes a condition at all.
    for _status in ("alive", "declining", "dead_reported", "removed", "vacant_site"):
        _n = stats[f"status_{_status}"]
        if _n:
            print(f"    status={_status:<14} {_n:,}")
    if stats["condition_stated"]:
        print(f"    condition stated     {stats['condition_stated']:,}  "
              f"(alive {stats['condition_alive']:,}, "
              f"declining {stats['condition_declining']:,}, "
              f"dead {stats['condition_dead']:,}, "
              f"removed {stats['condition_removed']:,})")
    print(f"      the source says so {stats['planting_sites_stated_by_source']:,}")
    print(f"      WE INFERRED IT     {stats['planting_sites_inferred_from_absent_species']:,}"
          f"  (blank or 'Tree' species field -- #94)")
    print(f"    alive, no species    {stats['non_taxon_rows']:,}  (qSpecies names no taxon)")
    print(f"      of which the source calls not-a-tree "
          f"{stats['records_not_a_tree']:,}  (#94)")
    print("  city record columns")
    for seed_column, csv_column in CITY_RECORD_COLUMNS:
        present = stats["city_" + csv_column]
        pct = 100.0 * present / stats["kept"] if stats["kept"] else 0.0
        print(f"    {seed_column:<18} {present:>8,}  ({pct:5.2f}%)  <- {csv_column}")
    print(f"    planted date set     {stats['planted_year_present']:,}  (planted_year + planted_on)")
    print(f"    dbh bucket set       {stats['dbh_present']:,}")
    print(f"    no neighborhood      {stats['no_neighborhood']:,}")
    print(f"  species_assertions     {stats['assertions']:,}")
    print(f"  distinct qSpecies      {len(qspecies_stats):,}")
    print(f"  species rows           {len(species_by_key):,}")
    print(f"    leaf_retention set   {content_stats['leaf_retention']:,}"
          f"   ({len(species_by_key) - content_stats['leaf_retention']:,} NULL: unknown, ERRATA E9)")
    print(f"    family set           {content_stats['family']:,}")
    print(f"    curated              {content_stats['curated']:,}")
    print(f"  stub rows              {stats['stub_rows']:,}")
    print(f"  stub % (species rows)  {stub_pct:.4f}%   ceiling {STUB_CEILING_PCT}%")
    print(f"  stub % (all rows)      {stub_pct_all:.4f}%")
    print(f"  seed file              {db_path}")
    print(f"  seed size              {size_mb:.1f} MB")
    print("=" * 66)

    if stub_pct > STUB_CEILING_PCT:
        die(
            f"stub path took {stub_pct:.3f}% of species-bearing rows, ceiling is "
            f"{STUB_CEILING_PCT}% (BUILD-PLAN section 7). Extend the qSpecies parser "
            f"or hand-map the offenders in Fixtures/sf_species_map.csv.",
            code=2,
        )

    log("OK")
    return 0


def flush(conn, species_by_key, tree_rows, rtree_rows, assertion_rows) -> None:
    conn.executemany(
        "INSERT OR IGNORE INTO species(id,uuid,scientific_name,common_name,family,"
        "leaf_retention,id_tips,seasonal,care_notes,curated,created_at,updated_at) "
        "VALUES(?,?,?,?,NULL,NULL,'[]','{}','[]',0,?,?)",
        [
            (sp["id"], sp["uuid"], sp["scientific_name"], sp["common_name"], NOW, NOW)
            for sp in species_by_key.values()
        ],
    )
    placeholders = ",".join("?" * len(TREE_COLUMNS))

    # THE INDEX IS DERIVED FROM THIS LIST (see TREE_COLUMNS), so it cannot drift
    # from it. The assertion stays anyway, and cheaply: it now catches the OTHER
    # half of the pair -- a row whose length does not match the column list,
    # which is what a mis-built row in `emit` looks like. SQLite would report
    # that one itself, but not before `executemany` has partially run.
    if TREE_COLUMNS[REGION_ROW_INDEX] != "region_id":
        die(f"REGION_ROW_INDEX resolves to {TREE_COLUMNS[REGION_ROW_INDEX]!r}, not 'region_id'")
    bad = next((i for i, row in enumerate(tree_rows) if len(row) != len(TREE_COLUMNS)), None)
    if bad is not None:
        die(f"tree row {bad} has {len(tree_rows[bad])} values for {len(TREE_COLUMNS)} "
            f"columns; `emit` and TREE_COLUMNS have drifted apart")

    conn.executemany(
        f"INSERT INTO trees({','.join(TREE_COLUMNS)}) VALUES({placeholders})",
        tree_rows,
    )
    conn.executemany(
        "INSERT INTO trees_rtree(id,min_lat,max_lat,min_lon,max_lon) VALUES(?,?,?,?,?)",
        rtree_rows,
    )
    conn.executemany(
        "INSERT INTO species_assertions(id,tree_id,species_id,source,confidence,"
        "asserted_by,superseded_by,created_at) VALUES(?,?,?,?,?,?,?,?)",
        assertion_rows,
    )
    conn.commit()
    tree_rows.clear()
    rtree_rows.clear()
    assertion_rows.clear()


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the Cypress seed SQLite database.")
    ap.add_argument("--fetch", action="store_true", help="re-download the raw sources")
    ap.add_argument(
        "--with-city-raw",
        action="store_true",
        help="populate trees.city_raw (~74 MB); off by default, regenerable from the CSV",
    )
    ap.add_argument(
        "--repo-root",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    )
    ap.add_argument("--limit", type=int, default=0, help="only read the first N source rows")
    ap.add_argument(
        "--source",
        choices=SOURCES,
        default=DEFAULT_SOURCE,
        help="which street-tree inventory to build from. `city` is SF Public Works' "
             "own layer, the one its public map draws (~133,577 rows, the default "
             "since #91). `datasf` is the open-data export tkzw-k3nq (~195,309 rows, "
             "what shipped before #91). Both paths are supported and tested; see "
             "docs/investigations/city-tree-source.md for what changes between them.",
    )
    ap.add_argument(
        "--sj-extent",
        choices=SJ_EXTENTS,
        default="none",
        help="how much of San Jose's Street Tree layer goes in. `none` is San "
             "Francisco alone, which is what every build before #129 meant. "
             "`downtown` ships the central-San-Jose window in SJ_SHIP_WINDOW, "
             "complete inside it. `full` ingests all 344,879 records, which "
             "proves the contract carries the corpus and produces a file far too "
             "large to ship. Reads the cache written by "
             "Tools/fetch_san_jose_trees.py and never touches the service.",
    )
    ap.add_argument(
        "--write-species-map",
        action="store_true",
        help="update the checked-in Fixtures/*_species_map.csv from this build. Off "
             "by default: a build must not modify a tracked input as a side effect, "
             "and a --limit or single-city run derives a map from only part of the "
             "source. Without it the derived copy goes to Fixtures/build/ and any "
             "drift against the checked-in copy is reported.",
    )
    ap.add_argument(
        "--nyc-cache", default="",
        help="directory holding tree_points.csv and planting_spaces.csv, as written "
             "by Tools/fetch_nyc_trees.py. Empty (the default) means no New York "
             "City at all. The cache lives OUTSIDE the repo -- ~430 MB across the "
             "two extracts -- so its location is given rather than assumed.",
    )
    ap.add_argument(
        "--nyc-borough", default="",
        help="restrict NYC to one Forestry Planting Spaces boroughcode: Manhattan, "
             "Brooklyn, Queens, Bronx or Staten Island. Empty is the whole city. "
             "Borough is a PLANTING SPACES column, so the 22,995 Full tree points "
             "that join to no planting space are dropped by any borough build and "
             "counted under nyc_dropped_wrong_borough -- they have no borough to "
             "be placed in.",
    )
    ap.add_argument(
        "--nyc-structures", default="Full",
        help="comma-separated TPStructure values to ingest, or `all`. The default "
             "`Full` is the 898,643 currently-standing tree points; `all` adds the "
             "Retired, Stump, Shaft and Stump - Uprooted records, which are real "
             "history the contract's not_a_tree can hold.",
    )
    args = ap.parse_args()
    return build(args.repo_root, args.fetch, args.limit, args.with_city_raw, args.source,
                 args.sj_extent, args.write_species_map,
                 args.nyc_cache, args.nyc_borough, args.nyc_structures)


if __name__ == "__main__":
    sys.exit(main())
