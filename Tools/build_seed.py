#!/usr/bin/env python3
"""
build_seed.py -- build the Cypress on-device seed SQLite database from DataSF.

Implements BUILD-PLAN.md section 7 (Ingest spec, DataSF) against the schema of
section 4, adapted to SQLite-on-device (no PostGIS).

Sources (verified live 2026-07-21):
  trees          DataSF "Street Tree List"        dataset id tkzw-k3nq
                 https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD
                 (the id `tuvn-fjcn` quoted in BUILD-PLAN 7 returns HTTP 404)
  neighborhoods  DataSF "Analysis Neighborhoods"  dataset id j2bu-swwd
                 (the commonly cited p5b7-5n3h is a map visualisation whose
                  backing tabular view is j2bu-swwd; only the tabular view
                  serves geometry over SODA)
                 https://data.sfgov.org/resource/j2bu-swwd.geojson?$limit=200

Identity model (two keys, on purpose):
  trees.id    INTEGER PRIMARY KEY -- internal join key. Every foreign key and
              index uses it; this is where the on-device size savings come from.
  trees.uuid  TEXT NOT NULL UNIQUE -- the stable, citable external identity
              required by DECISIONS.md constraint 13. Derived as UUIDv5 over a
              fixed namespace and the DataSF TreeID, so a rebuild reproduces
              byte-identical uuids and a tree's public URL never changes.

Usage:
    python3 Tools/build_seed.py [--fetch] [--with-city-raw] [--repo-root PATH] [--limit N]

    --fetch           re-download both raw files before building
    --with-city-raw   populate trees.city_raw with the DataSF passthrough JSON.
                      Off by default: it costs ~74 MB (~380 bytes/row) and is
                      fully regenerable from Fixtures/raw/street_tree_list.csv.
    --limit           build from only the first N CSV rows (smoke tests)

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

# DataSF columns consumed by an explicit mapping; everything else (plus
# qLegalStatus, which is explicitly retained per BUILD-PLAN 7) goes to city_raw.
MAPPED_COLUMNS = {
    "TreeID",
    "qSpecies",
    "qAddress",
    "Latitude",
    "Longitude",
    "PlantDate",
    "DBH",
    "qSiteInfo",
}

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

NOW = datetime.now(timezone.utc).replace(microsecond=0).isoformat()


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
-- All content columns below (family, leaf_retention, id_tips, seasonal,
-- care_notes, curated) are DELIBERATELY EMPTY in the city import. They are the
-- target of the authored species pipeline in BUILD-PLAN section 8. The types
-- and constraints are declared here so that pipeline and the Swift data layer
-- have a fixed contract to write against.
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
CREATE TABLE trees (
    id                 INTEGER PRIMARY KEY,     -- internal join key
    uuid               TEXT NOT NULL UNIQUE,    -- stable citable identity
    external_ref       INTEGER UNIQUE,          -- DataSF TreeID
    source             TEXT NOT NULL,           -- city_import | community
    lat                REAL NOT NULL,
    lon                REAL NOT NULL,
    address            TEXT,
    site_type          TEXT,
    neighborhood_id    INTEGER REFERENCES neighborhoods(id),
    status             TEXT NOT NULL,           -- alive | declining | dead_reported | removed | vacant_site
    species_current    INTEGER REFERENCES species(id),
    planted_year       INTEGER,
    dbh_city_cm_min    INTEGER,
    dbh_city_cm_max    INTEGER,
    site_lineage       INTEGER REFERENCES trees(id),
    verification_state TEXT NOT NULL,           -- unverified | org_verified | city_record
    city_raw           TEXT,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    deleted_at         TEXT,
    CHECK (status IN ('alive','declining','dead_reported','removed','vacant_site')),
    CHECK (verification_state IN ('unverified','org_verified','city_record')),
    CHECK ((dbh_city_cm_min IS NULL) = (dbh_city_cm_max IS NULL)),
    CHECK (city_raw IS NULL OR json_valid(city_raw))
);

-- Covering index for viewport / nearest queries that do not want the R*Tree.
CREATE INDEX idx_trees_lat_lon ON trees(lat, lon, id);
CREATE INDEX idx_trees_species_current ON trees(species_current);
CREATE INDEX idx_trees_neighborhood ON trees(neighborhood_id);
CREATE INDEX idx_trees_status ON trees(status);

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
    tree_count      INTEGER NOT NULL
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


def parse_planted_year(raw: str):
    """PlantDate -> year int, or None. DataSF ships '03/08/2024 12:00:00 AM'."""
    raw = (raw or "").strip()
    if not raw:
        return None
    head = raw.split(" ")[0]
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%Y/%m/%d"):
        try:
            year = datetime.strptime(head, fmt).year
        except ValueError:
            continue
        # Guard against sentinel dates.
        if 1800 <= year <= datetime.now().year + 1:
            return year
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
    of 'placeholder', 'parsed', 'stub'.
    """
    s = (raw or "").strip()
    if s.lower() in PLACEHOLDER_SPECIES:
        return "placeholder", None, None, 0.0

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


def build(repo_root: str, do_fetch: bool, limit: int, with_city_raw: bool) -> int:
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
        "csv_rows": 0,
        "dropped_no_coords": 0,
        "dropped_out_of_bbox": 0,
        "dropped_dupe_treeid": 0,
        "kept": 0,
        "vacant_site": 0,
        "alive": 0,
        "assertions": 0,
        "stub_rows": 0,
        "parsed_rows": 0,
        "no_neighborhood": 0,
        "planted_year_present": 0,
        "dbh_present": 0,
    }

    species_by_key = {}      # normalised scientific name -> species row dict
    qspecies_stats = {}      # raw qSpecies string -> dict
    seen_external_refs = set()

    tree_rows = []
    rtree_rows = []
    assertion_rows = []
    tree_id = 0
    assertion_id = 0
    t0 = time.time()

    with open(csv_path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []
        required = {"TreeID", "qSpecies", "qAddress", "Latitude", "Longitude"}
        missing = required - set(header)
        if missing:
            die(f"CSV is missing expected columns: {sorted(missing)}")
        raw_columns = [c for c in header if c and c not in MAPPED_COLUMNS]

        for row in reader:
            stats["csv_rows"] += 1
            if limit and stats["csv_rows"] > limit:
                stats["csv_rows"] -= 1
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
            if not ref_str:
                # No TreeID: no stable external identity is derivable from the
                # city record, so key the uuid on the immutable facts instead.
                external_ref = None
                uuid_seed = f"{lat:.7f},{lon:.7f},{(row.get('qSpecies') or '').strip()}"
            else:
                if ref_str in seen_external_refs:
                    stats["dropped_dupe_treeid"] += 1
                    continue
                seen_external_refs.add(ref_str)
                external_ref = int(ref_str) if ref_str.isdigit() else ref_str
                uuid_seed = ref_str
            tree_uuid = str(uuid.uuid5(NS_TREE, uuid_seed))

            # ---- row rule: species / placeholder
            qspecies = (row.get("qSpecies") or "").strip()
            kind, sci, common, conf = parse_qspecies(qspecies)

            qs = qspecies_stats.setdefault(
                qspecies,
                {"kind": kind, "confidence": conf, "species_id": None,
                 "species_uuid": None, "count": 0},
            )
            qs["count"] += 1

            species_id = None
            if kind != "placeholder":
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

            planted_year = parse_planted_year(row.get("PlantDate"))
            if planted_year:
                stats["planted_year_present"] += 1
            dbh_min, dbh_max = parse_dbh_bucket(row.get("DBH"))
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

            city_raw = None
            if with_city_raw:
                payload = {}
                for col in raw_columns:
                    val = (row.get(col) or "").strip()
                    if val:
                        payload[col] = val
                city_raw = json.dumps(payload, separators=(",", ":"))

            tree_id += 1
            tree_rows.append(
                (
                    tree_id,
                    tree_uuid,
                    external_ref,
                    "city_import",
                    lat,
                    lon,
                    (row.get("qAddress") or "").strip() or None,
                    (row.get("qSiteInfo") or "").strip() or None,
                    neighborhood_id,
                    status,
                    species_id,
                    planted_year,
                    dbh_min,
                    dbh_max,
                    None,
                    "city_record",
                    city_raw,
                    NOW,
                    NOW,
                    None,
                )
            )
            rtree_rows.append((tree_id, lat, lat, lon, lon))

            if species_id is not None:
                assertion_id += 1
                assertion_rows.append(
                    (assertion_id, tree_id, species_id, "city_import", conf,
                     None, None, NOW)
                )
                stats["assertions"] += 1

            stats["kept"] += 1

            if len(tree_rows) >= 20000:
                flush(conn, species_by_key, tree_rows, rtree_rows, assertion_rows)
                log(
                    f"  {stats['csv_rows']:,} rows read / {stats['kept']:,} kept "
                    f"({time.time() - t0:.0f}s)"
                )

    flush(conn, species_by_key, tree_rows, rtree_rows, assertion_rows)

    # species rows may have gained a common_name after first insert
    conn.executemany(
        "UPDATE species SET common_name = COALESCE(common_name, ?) WHERE id = ?",
        [(sp["common_name"], sp["id"]) for sp in species_by_key.values() if sp["common_name"]],
    )
    conn.commit()

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
                info["count"],
            )
        )
    conn.executemany(
        "INSERT INTO species_map(qspecies_string,species_id,species_uuid,confidence,"
        "is_stub,is_placeholder,tree_count) VALUES(?,?,?,?,?,?,?)",
        map_rows,
    )

    with open(map_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        # species_id carries the species UUID, not the internal integer id:
        # integer ids depend on CSV row order, uuids are order-independent and
        # survive a rebuild, which is what a checked-in mapping file needs.
        w.writerow(["qSpecies_string", "species_id", "confidence"])
        for qs_string, _sid, suuid, conf, _stub, _ph, _count in map_rows:
            w.writerow([qs_string, suuid or "", f"{conf:.2f}"])
    log(f"wrote {map_path} ({len(map_rows)} distinct qSpecies strings)")

    meta = {
        "generator": "Tools/build_seed.py",
        "generated_at": NOW,
        "trees_dataset_id": TREES_DATASET_ID,
        "trees_source_url": TREES_CSV_URL,
        "neighborhoods_dataset_id": NEIGHBORHOODS_DATASET_ID,
        "neighborhoods_source_url": NEIGHBORHOODS_GEOJSON_URL,
        "sf_bbox": json.dumps(SF_BBOX),
        "ns_tree_uuid": str(NS_TREE),
        "ns_species_uuid": str(NS_SPECIES),
        "city_raw_populated": "1" if with_city_raw else "0",
        "csv_rows": str(stats["csv_rows"]),
        "rows_kept": str(stats["kept"]),
        "dropped_no_coords": str(stats["dropped_no_coords"]),
        "dropped_out_of_bbox": str(stats["dropped_out_of_bbox"]),
        "dropped_dupe_treeid": str(stats["dropped_dupe_treeid"]),
        "vacant_site_rows": str(stats["vacant_site"]),
        "stub_rows": str(stats["stub_rows"]),
        "stub_pct_of_species_rows": f"{stub_pct:.4f}",
        "stub_ceiling_pct": str(STUB_CEILING_PCT),
        "distinct_qspecies": str(len(qspecies_stats)),
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
    print(f"  trees dataset          {TREES_DATASET_ID}")
    print(f"  neighborhoods dataset  {NEIGHBORHOODS_DATASET_ID} ({len(neighborhoods)} polygons)")
    print(f"  SF bbox                lat [{SF_BBOX['min_lat']}, {SF_BBOX['max_lat']}]  "
          f"lon [{SF_BBOX['min_lon']}, {SF_BBOX['max_lon']}]")
    print(f"  city_raw               {'populated' if with_city_raw else 'NULL (--with-city-raw to populate)'}")
    print(f"  CSV rows read          {stats['csv_rows']:,}")
    print(f"    dropped, no coords   {stats['dropped_no_coords']:,}")
    print(f"    dropped, out of bbox {stats['dropped_out_of_bbox']:,}")
    print(f"    dropped, dup TreeID  {stats['dropped_dupe_treeid']:,}")
    print(f"  trees written          {stats['kept']:,}")
    print(f"    status=alive         {stats['alive']:,}")
    print(f"    status=vacant_site   {stats['vacant_site']:,}")
    print(f"    planted_year set     {stats['planted_year_present']:,}")
    print(f"    dbh bucket set       {stats['dbh_present']:,}")
    print(f"    no neighborhood      {stats['no_neighborhood']:,}")
    print(f"  species_assertions     {stats['assertions']:,}")
    print(f"  distinct qSpecies      {len(qspecies_stats):,}")
    print(f"  species rows           {len(species_by_key):,}")
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
    conn.executemany(
        "INSERT INTO trees(id,uuid,external_ref,source,lat,lon,address,site_type,"
        "neighborhood_id,status,species_current,planted_year,dbh_city_cm_min,"
        "dbh_city_cm_max,site_lineage,verification_state,city_raw,created_at,"
        "updated_at,deleted_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
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
    ap.add_argument("--limit", type=int, default=0, help="only read the first N CSV rows")
    args = ap.parse_args()
    return build(args.repo_root, args.fetch, args.limit, args.with_city_raw)


if __name__ == "__main__":
    sys.exit(main())
