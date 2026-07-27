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

Identity model (two keys, on purpose):
  trees.id    INTEGER PRIMARY KEY -- internal join key. Every foreign key and
              index uses it; this is where the on-device size savings come from.
  trees.uuid  TEXT NOT NULL UNIQUE -- the stable, citable external identity
              required by DECISIONS.md constraint 13. Derived as UUIDv5 over a
              fixed namespace and the DataSF TreeID, so a rebuild reproduces
              byte-identical uuids and a tree's public URL never changes.

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
now; the numbers it used to produce are in docs/errata-pending/city-source.md.

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
import json
import os
import sqlite3
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timezone

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

# qSpecies strings that are site placeholders rather than species. BUILD-PLAN 7
# names "Tree(s) ::", "::" and empty; the live data also carries a handful of
# equivalent forms, all of which describe a planting site with no tree in it.
PLACEHOLDER_SPECIES = {
    "",
    "::",
    ":: ",
    "tree(s) ::",
    "tree(s)",
    ":: tree(s)",
    "tree ::",
    "nan ::",
    "nan",
    "potential site ::",
    "potential site",
    "vacant site ::",
    "vacant site",
    "vacant lot ::",
    "no species ::",
    "unknown ::",
}

# qSpecies strings whose scientific-name half names no taxon: a growth habit
# ("Shrub"), an ownership note ("Private shrub"), a vernacular that resolves to
# no single plant ("Privet" is any of three Ligustrum species in this same
# inventory), a genus the surveyor could not read ("Palm (unknown Genus)"), or
# an admission that nobody has identified it yet ("To Be Determine").
#
# These are NOT placeholders: the city recorded something growing at the site,
# so the tree is `alive`. They are also not species, so they map to no species
# row at all. Before this list existed each one minted a species of its own and
# a site labelled `Shrub` inherited that species' phenology chips, autumn strip
# and field guide (DECISIONS constraint 15: do not invent botanical content).
#
# The test for membership is "no taxon at any rank can be recovered from the
# string", and Fixtures/species/leaf_retention.yaml is the evidence: these seven
# are the only entries of 577 for which the sourcing pass resolved NEITHER a
# family NOR a leaf retention, because there is nothing to resolve. `Ficus
# laurel` deliberately stays out — `Ficus` is a genus the city did record, and
# the entry carries a sourced family. See ERRATA E15 for why the count is seven
# and not the six SOURCES.md section 10.2 lists.
#
# Keys are lowercased and whitespace-collapsed.
NON_TAXON_SPECIES = {
    "shrub :: shrub",
    "private shrub :: private shrub",
    "privet ::",
    ":: to be determine",
    "palm (unknown genus) :: palm spp",
    "new zealand tea tree :: new zealand tea tree",
    ":: brisbane box",
}

# Misspellings in qSpecies that hold one species as two. Keyed on the lowercased
# whitespace-collapsed qSpecies string; the value is (scientific name, confidence).
#
# Only entries an outside source already resolved belong here. `patanus racemosa`
# is a one-character misspelling of a name present in this same dataset, and
# Fixtures/species/leaf_retention.yaml carries the resolution with its own
# citation (SelecTree tree-detail/1107, match_method
# `fuzzy_name_edit_distance_1_to_"platanus racemosa"`). The confidence is below
# the 1.0 a clean binomial earns because the correction is ours, not the city's.
#
# What must NOT go here: a vernacular-only string merged onto a binomial by
# judgment. "Brisbane Box" names both Lophostemon confertus and Tristania
# conferta, which this inventory carries as two separate species rows, so
# merging on the common name would be a synonymy ruling with no source behind
# it. Those strings go to NON_TAXON_SPECIES instead.
QSPECIES_NAME_CORRECTIONS = {
    "patanus racemosa ::": ("Platanus racemosa", 0.9),
}

# Fixtures/species/*.yaml carries one entry per species the PREVIOUS build
# minted, so correcting the map above strands eight of them: the seven non-taxa
# lose their species row, and `patanus racemosa ::` folds into Platanus
# racemosa. The YAML files are left byte-identical — they are a sourcing record
# with citations, not a generated index — so the loader is told which absences
# are deliberate. Any OTHER stranded entry is real drift between the fixtures
# and the parser, and fails the build.
#
# Keyed on the `scientific_name` the previous build wrote, which is what the
# YAML entry carries; species uuids are derived from that name and are not
# restated here.
RETIRED_SPECIES_NAMES = {
    "Shrub",
    "Private shrub",
    "Privet",
    ":: To Be Determine",
    "Palm (unknown Genus)",
    "New Zealand Tea Tree",
    ":: Brisbane Box",
}

# The stranded entry whose sourced content is not discarded but re-keyed onto
# the species it was always a misspelling of. Its leaf retention must agree with
# what the target's own entry says, or the build fails.
MERGED_SPECIES_NAMES = {
    "patanus racemosa ::": "Platanus racemosa",
}

# DataSF columns consumed by an explicit mapping; everything else goes to
# city_raw (which is NULL unless --with-city-raw).
#
# The six added below were previously in the city_raw bucket, which in the
# shipped seed means they were on nobody's tree page: city_raw is NULL there and
# the app has never had a code path that reads it. qLegalStatus is the sharpest
# case -- an old comment here claimed it was "explicitly retained per BUILD-PLAN
# 7", and it was retained the way something is retained by being written to a
# column that ships empty. It has a column of its own now.
MAPPED_COLUMNS = {
    "TreeID",
    "qSpecies",
    "qAddress",
    "Latitude",
    "Longitude",
    "PlantDate",
    "DBH",
    "qSiteInfo",
    "qLegalStatus",
    "qCaretaker",
    "qCareAssistant",
    "PlantType",
    "PlotSize",
    "PermitNotes",
}

# (seed column, DataSF column) for the six carried verbatim. One list so the
# DDL, the INSERT and the ingest loop cannot drift apart.
CITY_RECORD_COLUMNS = [
    ("legal_status", "qLegalStatus"),
    ("caretaker", "qCaretaker"),
    ("care_assistant", "qCareAssistant"),
    ("plant_type", "PlantType"),
    ("plot_size", "PlotSize"),
    ("permit_notes", "PermitNotes"),
]

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


def city_qspecies(botanical: str, common: str) -> str:
    """The city layer's two name fields -> one DataSF-convention qSpecies string.

    DataSF writes `Scientific name :: Common name` in a single column and the whole
    species pipeline is built on that convention, so the city's `BOTANICAL` and
    `COMMON` are rejoined into it rather than given a second parser.

    ONE CORRECTION IS APPLIED, AND IT MOVES NO INFORMATION. 475 of the city's
    133,577 rows leave `BOTANICAL` null and put the botanical name in `COMMON`:
    `Laurus nobilis 'Saratoga'`, `Lophostemon confertus`, `Pistacia chinensis`.
    Left alone those parse as `:: <string>`, which the qSpecies parser correctly
    refuses to read as a taxon, and each one would mint a stub species of its own
    beside the real species it names. Swapping the halves when `BOTANICAL` is
    empty and `COMMON` reads as a binomial -- capitalised genus, lowercase
    alphabetic epithet -- puts the string the city already wrote on the side of
    the separator that means what it says. Nothing is invented and no name is
    changed; the two columns are read in the order the values are in.
    """
    botanical = " ".join((botanical or "").strip().split())
    common = " ".join((common or "").strip().split())
    if not botanical and common:
        tokens = common.split()
        if (
            len(tokens) >= 2
            and tokens[0][:1].isupper()
            and tokens[0].replace("-", "").isalpha()
            and tokens[1][:1].islower()
            and tokens[1].replace("-", "").isalpha()
        ):
            botanical, common = common, ""
    return f"{botanical} :: {common}".strip()


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
# trees.uuid   = uuid5(NS_TREE, <DataSF TreeID as an ASCII string>)
# species.uuid = uuid5(NS_SPECIES, <lowercased, whitespace-collapsed scientific name>)
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")
NS_SPECIES = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0002")

STUB_CEILING_PCT = 2.0
DBH_BUCKET_CM = 5.0
INCH_TO_CM = 2.54

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
--                                DETERMINISTIC: a rebuild from the same TreeID
--                                reproduces the same uuid byte for byte, so
--                                public tree URLs and export rows survive a
--                                re-import. Required by DECISIONS.md
--                                constraint 13.
--
-- Frozen UUIDv5 namespace constants (see Tools/build_seed.py):
--   trees.uuid   = uuidv5(6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001, <DataSF TreeID>)
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
--   external_ref text           -> INTEGER. Every DataSF TreeID observed is
--                                  numeric (verified across all 195,309 rows).
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
    external_ref       INTEGER UNIQUE,          -- DataSF TreeID
    source             TEXT NOT NULL,           -- city_import | community
    -- WHICH OF SAN FRANCISCO'S TWO INVENTORIES LISTED THIS RECORD. 'city' or
    -- 'datasf', matching `--source` and `seed_meta.trees_source`.
    --
    -- Under `--source datasf` every row says 'datasf' and the column is
    -- redundant. Under `--source city` it is not: the row set is the city's
    -- operational layer, but that layer has no vacant-site category at all
    -- (`PlantType` is `Tree` on all 133,577 of its records), so the seed's
    -- vacant planting sites are carried across from the DataSF export and are
    -- the only rows in the file the city's layer does not list. A seed built
    -- from two inventories owes every reader the ability to ask which one a
    -- given row came from -- otherwise the provenance sentence on screen is a
    -- claim about the file rather than about the record, and for 12,260 of
    -- them it would be the wrong inventory's name.
    inventory_source   TEXT NOT NULL,           -- city | datasf
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
    CHECK (status IN ('alive','declining','dead_reported','removed','vacant_site')),
    CHECK (inventory_source IN ('city','datasf')),
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
    -- 1 = the string names no taxon ("Shrub", "Privet", "To Be Determine").
    -- A tree stands at the site, so it is NOT a placeholder and its status is
    -- `alive`; it simply carries no species. Provenance is a queryable column
    -- rather than a comment (DECISIONS constraint 13).
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


def parse_planted_date(raw: str):
    """PlantDate -> a date, or None. DataSF ships '03/08/2024 12:00:00 AM'.

    The sentinel guard's upper bound is SEED_EPOCH's year, not the wall clock's.
    `datetime.now()` here was harmless in output terms while the two agreed, and
    it was still a clock reading inside a build the repo declares byte-for-byte
    reproducible -- the exact shape of the defect ERRATA E13 records. Reading the
    epoch instead means a rebuild in 2030 from the same CSV still produces the
    same file.
    """
    raw = (raw or "").strip()
    if not raw:
        return None
    head = raw.split(" ")[0]
    horizon = datetime.fromisoformat(NOW).year + 1
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%Y/%m/%d"):
        try:
            parsed = datetime.strptime(head, fmt).date()
        except ValueError:
            continue
        # Guard against sentinel dates.
        if 1800 <= parsed.year <= horizon:
            return parsed
        return None
    return None


def parse_dbh_bucket(raw: str):
    """DataSF DBH is inches. -> half-open [min, max) 5 cm bucket, or (None, None).

    DBH values of 0 or blank mean "not recorded" in this dataset, not "a zero
    inch trunk", so they map to NULL rather than the [0,5) bucket.
    """
    raw = (raw or "").strip()
    if not raw:
        return None, None
    try:
        inches = float(raw)
    except ValueError:
        return None, None
    if inches <= 0 or inches > 400:  # 400in ~ 10m diameter; anything above is junk
        return None, None
    cm = inches * INCH_TO_CM
    lo = int(cm // DBH_BUCKET_CM) * int(DBH_BUCKET_CM)
    return lo, lo + int(DBH_BUCKET_CM)


def normalise_species_key(sci: str) -> str:
    return " ".join(sci.strip().lower().split())


def parse_qspecies(raw: str):
    """Parse the DataSF 'Scientific name :: Common name' convention.

    Returns (kind, scientific_name, common_name, confidence) where kind is one
    of 'placeholder', 'non_taxon', 'parsed', 'stub'.
    """
    s = (raw or "").strip()
    if s.lower() in PLACEHOLDER_SPECIES:
        return "placeholder", None, None, 0.0

    key = " ".join(s.lower().split())
    if key in NON_TAXON_SPECIES:
        # Something is planted here; it is just not a species. See NON_TAXON_SPECIES.
        return "non_taxon", None, None, 0.0

    correction = QSPECIES_NAME_CORRECTIONS.get(key)
    if correction:
        corrected_name, corrected_conf = correction
        _, _, common = s.partition("::")
        return "parsed", corrected_name, " ".join(common.strip().split()) or None, corrected_conf

    if "::" not in s:
        # No convention marker at all -> stub with the raw string as the name.
        return "stub", s, None, 0.2

    sci, _, common = s.partition("::")
    sci = " ".join(sci.strip().split())
    common = " ".join(common.strip().split())

    if not sci:
        # ':: Something' -- a common name with no scientific name.
        if not common or common.lower() in {
            "tree",
            "tree(s)",
            "potential site",
            "vacant site",
            "nan",
        }:
            return "placeholder", None, None, 0.0
        return "stub", s, common, 0.3

    if sci.lower() in {"tree(s)", "tree", "nan", "potential site", "vacant site"}:
        return "placeholder", None, None, 0.0

    tokens = sci.split()
    genus = tokens[0]

    # A scientific name should start with a capitalised genus of letters only.
    if not genus[:1].isupper() or not genus.replace("-", "").isalpha():
        return "stub", s, common or None, 0.2

    if len(tokens) == 1:
        # Genus only, e.g. "Ficus".
        conf = 0.7
    elif tokens[1].lower() in {"sp.", "spp.", "sp", "spp", "x", "hybrid"}:
        # Genus + explicit indeterminate/hybrid marker.
        conf = 0.75
    elif tokens[1][:1].islower() and tokens[1].replace("-", "").isalpha():
        # Proper binomial, optionally with cultivar/variety trailing.
        conf = 1.0 if len(tokens) == 2 else 0.9
    else:
        conf = 0.6

    return "parsed", sci, common or None, conf


SEASONAL_KEYS = ("bloom_months", "fall_color_months", "fruit_months", "new_growth_months")


def _compact_json(value) -> str:
    """One spelling of every JSON column, so a rebuild is byte-identical."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def load_species_content(fixtures_dir: str, species_by_key: dict, strict: bool = True) -> dict:
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

    def apply(entry: dict, path: str, curated: bool) -> None:
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
            if not strict:
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


def build(repo_root: str, do_fetch: bool, limit: int, with_city_raw: bool,
          source: str = DEFAULT_SOURCE) -> int:
    if source not in SOURCES:
        die(f"--source must be one of {', '.join(SOURCES)}, got {source!r}")
    raw_dir = os.path.join(repo_root, "Fixtures", "raw")
    seed_dir = os.path.join(repo_root, "Fixtures", "seed")
    fixtures_dir = os.path.join(repo_root, "Fixtures")
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(seed_dir, exist_ok=True)

    csv_path = os.path.join(raw_dir, "street_tree_list.csv")
    nb_path = os.path.join(raw_dir, "sf_analysis_neighborhoods.geojson")
    db_path = os.path.join(seed_dir, "cypress-seed.sqlite")
    schema_path = os.path.join(seed_dir, "schema.sql")
    map_path = os.path.join(fixtures_dir, "sf_species_map.csv")

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
    stats = {
        "source_rows": 0,
        "dropped_no_coords": 0,
        "dropped_out_of_bbox": 0,
        "dropped_dupe_treeid": 0,
        "kept": 0,
        "vacant_site": 0,
        "alive": 0,
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
        **{"city_" + csv_column: 0 for _, csv_column in CITY_RECORD_COLUMNS},
    }

    species_by_key = {}      # normalised scientific name -> species row dict
    qspecies_stats = {}      # raw qSpecies string -> dict
    seen_external_refs = set()
    city_kind_by_ref = {}    # TreeID -> parse_qspecies kind, city rows only

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

    def emit(
        external_ref,
        uuid_seed: str,
        lat: float,
        lon: float,
        qspecies: str,
        address,
        site_type,
        planted_date,
        dbh_raw,
        city_record: list,
        city_raw,
        inventory_source: str,
    ) -> None:
        """One inventory record -> the seed's row shapes.

        Shared by both sources on purpose: identity, the species pipeline, the
        vacant-site rule, the DBH bucket and the neighbourhood stamp are the seed's
        rules and not any one upstream's, so `--source city` and `--source datasf`
        cannot drift in what they mean by a row.

        `inventory_source` is which inventory listed this record, and it is a
        parameter rather than a closed-over constant because the city build reads
        both: its living trees are the city layer's and its vacant planting sites
        are the export's. See the `inventory_source` column comment.
        """
        tree_uuid = str(uuid.uuid5(NS_TREE, uuid_seed))

        # ---- row rule: species / placeholder
        kind, sci, common, conf = parse_qspecies(qspecies)

        qs = qspecies_stats.setdefault(
            qspecies,
            {"kind": kind, "confidence": conf, "species_id": None,
             "species_uuid": None, "count": 0},
        )
        qs["count"] += 1

        species_id = None
        if kind == "non_taxon":
            stats["non_taxon_rows"] += 1
        elif kind != "placeholder":
            key = normalise_species_key(sci)
            sp = species_by_key.get(key)
            if sp is None:
                sp = {
                    "id": len(species_by_key) + 1,
                    "uuid": str(uuid.uuid5(NS_SPECIES, key)),
                    "scientific_name": sci,
                    "common_name": common,
                    "stub": kind == "stub",
                }
                species_by_key[key] = sp
            elif sp["common_name"] is None and common:
                sp["common_name"] = common
            species_id = sp["id"]
            qs["species_id"] = species_id
            qs["species_uuid"] = sp["uuid"]
            if kind == "stub":
                stats["stub_rows"] += 1
            else:
                stats["parsed_rows"] += 1

        status = "vacant_site" if kind == "placeholder" else "alive"
        if status == "vacant_site":
            stats["vacant_site"] += 1
        else:
            stats["alive"] += 1

        planted_year = planted_date.year if planted_date else None
        planted_on = planted_date.isoformat() if planted_date else None
        if planted_year:
            stats["planted_year_present"] += 1
        dbh_min, dbh_max = parse_dbh_bucket(dbh_raw)
        if dbh_min is not None:
            stats["dbh_present"] += 1

        # ---- neighborhood stamp
        neighborhood_id = None
        if strtree is not None:
            pt = Point(lon, lat)
            for idx in strtree.query(pt):
                nid, prepared = nb_by_index[int(idx)]
                if prepared.contains(pt):
                    neighborhood_id = nid
                    break
            if neighborhood_id is None:
                stats["no_neighborhood"] += 1

        ids["tree"] += 1
        tree_id = ids["tree"]
        observe_case("site_type", site_type)
        for (seed_column, _), value in zip(CITY_RECORD_COLUMNS, city_record):
            if seed_column in case_counts:
                observe_case(seed_column, value)
        tree_rows.append(
            [
                tree_id,
                tree_uuid,
                external_ref,
                "city_import",
                inventory_source,
                lat,
                lon,
                address,
                site_type,
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
                city_raw,
                NOW,
                NOW,
                None,
            ]
        )
        rtree_rows.append((tree_id, lat, lat, lon, lon))

        if species_id is not None:
            ids["assertion"] += 1
            assertion_rows.append(
                (ids["assertion"], tree_id, species_id, "city_import", conf,
                 None, None, NOW)
            )
            stats["assertions"] += 1

        stats["kept"] += 1

    # `emit` appends to `tree_rows` and the case-normalisation pass below rewrites
    # columns inside those rows, so rows are held until the whole source has been
    # read rather than flushed in 20,000-row batches. Peak resident size is about
    # 250 MB for the DataSF export and 170 MB for the city layer; the batching it
    # replaces existed to bound exactly that, and a normalisation that can only be
    # computed from the whole corpus is worth the memory.
    if source == "datasf":
        with open(csv_path, "r", encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            header = reader.fieldnames or []
            required = {"TreeID", "qSpecies", "qAddress", "Latitude", "Longitude"}
            missing = required - set(header)
            if missing:
                die(f"CSV is missing expected columns: {sorted(missing)}")
            raw_columns = [c for c in header if c and c not in MAPPED_COLUMNS]

            for row in reader:
                stats["source_rows"] += 1
                if limit and stats["source_rows"] > limit:
                    stats["source_rows"] -= 1
                    break

                # ---- row rule: coordinates
                lat_s = (row.get("Latitude") or "").strip()
                lon_s = (row.get("Longitude") or "").strip()
                if not lat_s or not lon_s:
                    stats["dropped_no_coords"] += 1
                    continue
                try:
                    lat = float(lat_s)
                    lon = float(lon_s)
                except ValueError:
                    stats["dropped_no_coords"] += 1
                    continue
                if lat != lat or lon != lon:  # NaN
                    stats["dropped_no_coords"] += 1
                    continue
                if not (
                    SF_BBOX["min_lat"] <= lat <= SF_BBOX["max_lat"]
                    and SF_BBOX["min_lon"] <= lon <= SF_BBOX["max_lon"]
                ):
                    stats["dropped_out_of_bbox"] += 1
                    continue

                # ---- identity
                ref_str = (row.get("TreeID") or "").strip()
                qspecies = (row.get("qSpecies") or "").strip()
                if not ref_str:
                    # No TreeID: no stable external identity is derivable from the
                    # city record, so key the uuid on the immutable facts instead.
                    external_ref = None
                    uuid_seed = f"{lat:.7f},{lon:.7f},{qspecies}"
                else:
                    if ref_str in seen_external_refs:
                        stats["dropped_dupe_treeid"] += 1
                        continue
                    seen_external_refs.add(ref_str)
                    external_ref = int(ref_str) if ref_str.isdigit() else ref_str
                    uuid_seed = ref_str

                city_raw = None
                if with_city_raw:
                    payload = {}
                    for col in raw_columns:
                        val = (row.get(col) or "").strip()
                        if val:
                            payload[col] = val
                    city_raw = json.dumps(payload, separators=(",", ":"))

                # The city's own record, verbatim except for the case
                # normalisation applied below (#95). Blank becomes NULL -- an empty
                # string in this CSV means the city recorded nothing, and storing ''
                # would make "no value" and "the value is nothing" indistinguishable
                # to every reader downstream.
                city_record = []
                for _, csv_column in CITY_RECORD_COLUMNS:
                    value = (row.get(csv_column) or "").strip()
                    city_record.append(value or None)
                    if value:
                        stats["city_" + csv_column] += 1

                emit(
                    external_ref=external_ref,
                    uuid_seed=uuid_seed,
                    lat=lat,
                    lon=lon,
                    qspecies=qspecies,
                    address=(row.get("qAddress") or "").strip() or None,
                    site_type=(row.get("qSiteInfo") or "").strip() or None,
                    planted_date=parse_planted_date(row.get("PlantDate")),
                    dbh_raw=row.get("DBH"),
                    city_record=city_record,
                    city_raw=city_raw,
                    inventory_source="datasf",
                )

                if stats["source_rows"] % 20000 == 0:
                    log(f"  {stats['source_rows']:,} rows read / {stats['kept']:,} kept "
                        f"({time.time() - t0:.0f}s)")
    else:
        # ---- the city's own inventory.
        #
        # Nine of the DataSF export's columns have no counterpart here and are
        # NULL for every row: qLegalStatus, qSiteInfo, qCaretaker, qCareAssistant,
        # PlantDate, PlotSize, PermitNotes, and the two state-plane coordinates.
        # That is the cost of the switch, and it is recorded in seed_meta rather
        # than filled in with a guess.
        #
        # Addresses are stored EXACTLY as the city writes them, which here means
        # mostly uppercase (`1 TWIN PEAKS BLVD`). Title-casing them would read
        # better and would also turn `MCALLISTER ST` into `Mcallister St`, which
        # is a spelling of that street nobody uses; the DataSF export itself
        # carries both `McAllister St` (146 rows) and `MCALLISTER ST` (37), so
        # uppercase is not even foreign to the column. Verbatim is the rule the
        # six city columns already follow and it is the rule here too.
        for record in city_rows:
            stats["source_rows"] += 1
            if limit and stats["source_rows"] > limit:
                stats["source_rows"] -= 1
                break

            lat = record.get("Latitude")
            lon = record.get("Longitude")
            if lat is None or lon is None or lat != lat or lon != lon:
                stats["dropped_no_coords"] += 1
                continue
            if not (
                SF_BBOX["min_lat"] <= lat <= SF_BBOX["max_lat"]
                and SF_BBOX["min_lon"] <= lon <= SF_BBOX["max_lon"]
            ):
                stats["dropped_out_of_bbox"] += 1
                continue

            ref = record["TREEID"]
            ref_str = str(ref)
            if ref_str in seen_external_refs:
                stats["dropped_dupe_treeid"] += 1
                continue
            seen_external_refs.add(ref_str)

            # `PlantType` is the city layer's own; the other five come from the
            # export's row for this same TreeID, or are NULL for a record only the
            # city has. See `load_datasf_attributes` for why that join exists.
            extra = enrichment.get(ref_str)
            if extra is None:
                stats["city_only_rows"] += 1
            else:
                stats["enriched_rows"] += 1
            plant_type = (record.get("PlantType") or "").strip() or None
            city_record = []
            for seed_column, csv_column in CITY_RECORD_COLUMNS:
                value = plant_type if seed_column == "plant_type" else (extra or {}).get(csv_column)
                city_record.append(value)
                if value:
                    stats["city_" + csv_column] += 1

            # Kept so the second pass can say which kind of overlap it found when
            # the export calls a site empty and the city's layer lists it at all.
            qspecies = city_qspecies(record.get("BOTANICAL"), record.get("COMMON"))
            city_kind_by_ref[ref_str] = parse_qspecies(qspecies)[0]

            emit(
                external_ref=ref,
                uuid_seed=ref_str,
                lat=lat,
                lon=lon,
                qspecies=qspecies,
                address=(record.get("Address") or "").strip() or None,
                site_type=(extra or {}).get("qSiteInfo"),
                planted_date=parse_planted_date((extra or {}).get("PlantDate")),
                dbh_raw=str(record["DBH"]) if record.get("DBH") is not None else "",
                city_record=city_record,
                city_raw=None,
                inventory_source="city",
            )

            if stats["source_rows"] % 20000 == 0:
                log(f"  {stats['source_rows']:,} rows read / {stats['kept']:,} kept "
                    f"({time.time() - t0:.0f}s)")

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
        # as `alive` from the first pass, so the test is simply "did the first
        # pass already emit this TreeID", which also makes a duplicate
        # `external_ref` unrepresentable rather than merely unlikely. Measured on
        # this extract: 258 of the export's 12,518 sites are listed by the city,
        # 128 of them as a living tree and 130 as an empty site the city's own
        # `BOTANICAL = 'Potential Site'` also calls empty. 12,260 carry through.
        #
        # Nothing here can add a *tree*: `parse_qspecies` has already decided the
        # row is a placeholder, and `emit` gives every placeholder
        # `status = 'vacant_site'` and no species. A row that stopped parsing as
        # a placeholder would stop being carried, not become a tree.
        with open(csv_path, "r", encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            raw_columns = [c for c in (reader.fieldnames or []) if c and c not in MAPPED_COLUMNS]
            for row in reader:
                qspecies = (row.get("qSpecies") or "").strip()
                if parse_qspecies(qspecies)[0] != "placeholder":
                    continue
                stats["export_vacant_rows"] += 1
                # `--limit` is for smoke tests and bounds both passes, so a
                # limited build still exercises this one instead of skipping it.
                if limit and stats["export_vacant_carried"] >= limit:
                    break

                lat_s = (row.get("Latitude") or "").strip()
                lon_s = (row.get("Longitude") or "").strip()
                try:
                    lat = float(lat_s)
                    lon = float(lon_s)
                except ValueError:
                    stats["dropped_no_coords"] += 1
                    continue
                if lat != lat or lon != lon:
                    stats["dropped_no_coords"] += 1
                    continue
                if not (
                    SF_BBOX["min_lat"] <= lat <= SF_BBOX["max_lat"]
                    and SF_BBOX["min_lon"] <= lon <= SF_BBOX["max_lon"]
                ):
                    stats["dropped_out_of_bbox"] += 1
                    continue

                ref_str = (row.get("TreeID") or "").strip()
                if not ref_str:
                    external_ref = None
                    uuid_seed = f"{lat:.7f},{lon:.7f},{qspecies}"
                else:
                    if ref_str in seen_external_refs:
                        # The city's layer already listed this TreeID and the
                        # first pass emitted it. Which of the two cases this is
                        # -- a contradiction the city won, or an empty site both
                        # inventories agree about -- is counted for the record.
                        if city_kind_by_ref.get(ref_str) == "placeholder":
                            stats["export_vacant_city_lists_site"] += 1
                        else:
                            stats["export_vacant_city_lists_tree"] += 1
                        continue
                    seen_external_refs.add(ref_str)
                    external_ref = int(ref_str) if ref_str.isdigit() else ref_str
                    uuid_seed = ref_str

                city_raw = None
                if with_city_raw:
                    payload = {}
                    for col in raw_columns:
                        val = (row.get(col) or "").strip()
                        if val:
                            payload[col] = val
                    city_raw = json.dumps(payload, separators=(",", ":"))

                city_record = []
                for _, csv_column in CITY_RECORD_COLUMNS:
                    value = (row.get(csv_column) or "").strip()
                    city_record.append(value or None)
                    if value:
                        stats["city_" + csv_column] += 1

                stats["export_vacant_carried"] += 1
                emit(
                    external_ref=external_ref,
                    uuid_seed=uuid_seed,
                    lat=lat,
                    lon=lon,
                    qspecies=qspecies,
                    address=(row.get("qAddress") or "").strip() or None,
                    site_type=(row.get("qSiteInfo") or "").strip() or None,
                    planted_date=parse_planted_date(row.get("PlantDate")),
                    dbh_raw=row.get("DBH"),
                    city_record=city_record,
                    city_raw=city_raw,
                    inventory_source="datasf",
                )

        log(f"vacant planting sites from the export: {stats['export_vacant_carried']:,} carried, "
            f"{stats['export_vacant_city_lists_tree']:,} excluded because the city's layer lists "
            f"a living tree at that TreeID, {stats['export_vacant_city_lists_site']:,} already "
            f"in the seed as the city's own empty site")

    # ---- #95, applied. One spelling per case-folded value in the columns the app
    # compares against a literal. `WHERE plant_type = 'Tree'` used to drop three
    # rows spelled `tree`; the seed contract now fails if any such pair returns.
    stats["case_normalised_values"] = 0
    column_index = {name: index for index, name in enumerate(
        ["id", "uuid", "external_ref", "source", "inventory_source", "lat", "lon", "address", "site_type",
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
    species_content, content_stats = load_species_content(
        fixtures_dir, species_by_key, strict=(source == "datasf" and not limit)
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

    # ------------------------------------------------------------ stub ceiling
    species_bearing_rows = stats["parsed_rows"] + stats["stub_rows"]
    stub_pct = (
        100.0 * stats["stub_rows"] / species_bearing_rows if species_bearing_rows else 0.0
    )
    stub_pct_all = 100.0 * stats["stub_rows"] / stats["kept"] if stats["kept"] else 0.0

    # ------------------------------------------------------- species map table
    map_rows = []
    for qs_string, info in sorted(
        qspecies_stats.items(), key=lambda kv: (-kv[1]["count"], kv[0])
    ):
        map_rows.append(
            (
                qs_string,
                info["species_id"],
                info["species_uuid"],
                round(info["confidence"], 2),
                1 if info["kind"] == "stub" else 0,
                1 if info["kind"] == "placeholder" else 0,
                1 if info["kind"] == "non_taxon" else 0,
                info["count"],
            )
        )
    conn.executemany(
        "INSERT INTO species_map(qspecies_string,species_id,species_uuid,confidence,"
        "is_stub,is_placeholder,is_non_taxon,tree_count) VALUES(?,?,?,?,?,?,?,?)",
        map_rows,
    )

    with open(map_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        # species_id carries the species UUID, not the internal integer id:
        # integer ids depend on CSV row order, uuids are order-independent and
        # survive a rebuild, which is what a checked-in mapping file needs.
        #
        # An empty species_id is the honest answer for three kinds of string: a
        # vacant-site placeholder, a string that names no taxon
        # (NON_TAXON_SPECIES), and nothing else. This file is REGENERATED by
        # every build, so a correction belongs in the tables at the top of this
        # script, not in the CSV — editing the CSV loses the edit on the next run.
        w.writerow(["qSpecies_string", "species_id", "confidence"])
        for qs_string, _sid, suuid, conf, _stub, _ph, _nt, _count in map_rows:
            w.writerow([qs_string, suuid or "", f"{conf:.2f}"])
    log(f"wrote {map_path} ({len(map_rows)} distinct qSpecies strings)")

    # ---- which inventory this seed is, and WHEN it was taken.
    #
    # `trees_snapshot_on` is the one key nothing else can substitute for. A seed
    # with no snapshot date is what made "is our data stale" unanswerable the last
    # time it was asked: the file could be a day old or a year old and no reader,
    # inside the app or outside it, could tell. It is a date the *source* was read,
    # never a clock reading at build time, so rebuilding this seed in 2030 from the
    # same cache still says 2026.
    if source == "city":
        source_meta = {
            "trees_source": "city",
            "trees_source_name": "SF Public Works street tree inventory",
            "trees_source_url": CITY_LAYER_SERVICE,
            "trees_source_map_url": CITY_LAYER_MAP_URL,
            "trees_snapshot_on": city_meta["extracted_on"],
            "trees_source_last_edit_on": str(city_meta.get("server_last_edit_date") or ""),
            "trees_source_feature_count": str(city_meta.get("server_feature_count") or ""),
            # Which trees exist is the city's answer; these seven columns are the
            # export's, for the records both list. See `load_datasf_attributes`.
            "attributes_source": "datasf",
            "attributes_dataset_id": TREES_DATASET_ID,
            "attributes_snapshot_on": NOW[:10],
            "attributes_columns": ",".join(ENRICHED_COLUMNS),
            "rows_enriched": str(stats["enriched_rows"]),
            "rows_city_only": str(stats["city_only_rows"]),
            # The vacant planting sites, which are the export's rows and not the
            # layer's -- it has no such category. `trees.inventory_source` says
            # which inventory each row came from; these are the totals.
            "sites_source": "datasf",
            # The second pass's own row accounting, so the seed contract can close
            # the arithmetic over both passes: rows read = rows shipped + rows
            # dropped, with nothing unexplained on either side.
            "export_vacant_rows_read": str(stats["export_vacant_rows"]),
            "rows_from_city": str(stats["kept"] - stats["export_vacant_carried"]),
            "rows_from_datasf": str(stats["export_vacant_carried"]),
            "export_vacant_sites_excluded_city_lists_tree":
                str(stats["export_vacant_city_lists_tree"]),
            "export_vacant_sites_already_city_listed":
                str(stats["export_vacant_city_lists_site"]),
            # One name/url/date triple per inventory the file actually holds rows
            # from, keyed by the same identifier `trees.inventory_source` stores.
            # The app resolves a row's provenance line through these, so a seed
            # built from two inventories can say which one each record came from
            # instead of putting one name over all of them.
            "inventory_city_name": "SF Public Works street tree inventory",
            "inventory_city_url": CITY_LAYER_SERVICE,
            "inventory_city_snapshot_on": city_meta["extracted_on"],
            "inventory_datasf_name": "DataSF Street Tree List",
            "inventory_datasf_url": TREES_CSV_URL,
            "inventory_datasf_snapshot_on": NOW[:10],
            # Nothing is unavailable outright: the two state-plane coordinates are
            # the same point as lat/lon and were never ingested from either source.
            "columns_absent_from_source": "",
        }
    else:
        source_meta = {
            "trees_source": "datasf",
            "trees_source_name": "DataSF Street Tree List",
            "trees_dataset_id": TREES_DATASET_ID,
            "trees_source_url": TREES_CSV_URL,
            # The DataSF export publishes no per-row as-of date; the snapshot date
            # is the dataset's own last update, which is what SEED_EPOCH is set to
            # (ERRATA E1). Stated rather than left to be inferred from `generated_at`.
            "trees_snapshot_on": NOW[:10],
            "rows_from_datasf": str(stats["kept"]),
            "inventory_datasf_name": "DataSF Street Tree List",
            "inventory_datasf_url": TREES_CSV_URL,
            "inventory_datasf_snapshot_on": NOW[:10],
            "columns_absent_from_source": "",
        }

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
        "vacant_site_rows": str(stats["vacant_site"]),
        "non_taxon_rows": str(stats["non_taxon_rows"]),
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
    if source == "city":
        print(f"    from city layer      {stats['kept'] - stats['export_vacant_carried']:,}")
        print(f"    from datasf export   {stats['export_vacant_carried']:,}")
    print(f"    status=alive         {stats['alive']:,}")
    print(f"    status=vacant_site   {stats['vacant_site']:,}")
    print(f"    alive, no species    {stats['non_taxon_rows']:,}  (qSpecies names no taxon)")
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
    city_columns = ",".join(name for name, _ in CITY_RECORD_COLUMNS)
    placeholders = ",".join("?" * (22 + len(CITY_RECORD_COLUMNS)))
    conn.executemany(
        "INSERT INTO trees(id,uuid,external_ref,source,inventory_source,lat,lon,address,site_type,"
        "neighborhood_id,status,species_current,planted_year,planted_on,"
        "dbh_city_cm_min,dbh_city_cm_max,site_lineage,verification_state,"
        f"{city_columns},city_raw,"
        f"created_at,updated_at,deleted_at) VALUES({placeholders})",
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
    args = ap.parse_args()
    return build(args.repo_root, args.fetch, args.limit, args.with_city_raw, args.source)


if __name__ == "__main__":
    sys.exit(main())
