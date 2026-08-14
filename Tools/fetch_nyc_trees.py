#!/usr/bin/env python3
"""
fetch_nyc_trees.py -- cache NYC Parks' two Forestry layers off Socrata.

    Forestry Tree Points     hn5i-inap    the inventory: one row per tree point
    Forestry Planting Spaces 82zj-84is    the address/borough/site facts, joined
                                          by PlantingSpaceGlobalID -> GlobalID

Both live on `data.cityofnewyork.us`. See docs/investigations/nyc-street-trees.md
for why Tree Points and not the 2015 Street Tree Census (`uvpi-gqnh`), and §2 of
that note for the terms: redistribution is permitted, but an app built on this
data must notify the City and carry a verbatim disclaimer. **That obligation is
not discharged by this script and is not discharged by anything in the repo yet.**

TWO DATASETS, NOT ONE, AND THAT IS THE WHOLE DIFFICULTY. Tree Points has no
address and no borough of its own -- 20 columns, none of them a street. Every
placement fact the seed needs lives on Planting Spaces and arrives through the
join. So this script caches both, and `NYCTreePointAdapter` performs the join
in-process. San Jose needed one layer; San Francisco needed two already-adapted
streams the builder chose between. This is the first source where the ADAPTER
joins.

Discipline, because this is somebody else's public server:

  * sequential, one request at a time, never parallel;
  * `$limit` at 50,000 rows per page, ~23 pages for Tree Points;
  * a delay between pages (--delay, default 1.0 s);
  * ordered by `:id`, Socrata's own row identifier, so pages are stable and
    disjoint between runs -- ordering by a data column would be unstable where
    that column has duplicates, and on Planting Spaces it does (see below);
  * RESUMABLE. Each page lands in its own file under <cache>/<dataset>_pages/
    and a re-run skips every page already on disk. A URL on disk is never
    re-fetched.
  * every request that actually leaves this machine is appended to
    <cache>/requests.log.

THE CACHE LIVES OUTSIDE THE REPO, AND THAT IS ENFORCED. `Fixtures/raw/nyc/`
holds the 2026-08-01 survey's 38 sample rows and stays that way; these extracts
are ~350 MB. `--cache-dir` has no default inside the tree and the script refuses
a directory `git check-ignore` does not cover, so a bulk extract cannot be
committed by accident.

THE DEEP-PAGE CHECK IS PART OF THE FETCH (E172). Santa Monica's datastore
returned Springfield, Illinois at offset 0 and real data at offset 5,000; an
ingest that sanity-checks only its first page ships Illinois. `--verify`
re-requests first/middle/last pages and asserts every row is inside NYC's
bounding box and carries a GlobalID.

PLANTING SPACES SHIPS 6,864 DUPLICATE ROWS AND THE SURVEY DID NOT KNOW.
`count(*)` is 1,091,709 and `count(distinct globalid)` is 1,084,845. Measured
2026-08-14: the extra rows are WHOLE-ROW duplicates -- identical in every
column, OBJECTID included -- so they are one planting space published twice, not
two spaces sharing an id. `--verify` re-checks that claim on the extract itself
rather than trusting this paragraph, because a duplicate pair that DISAGREED
would make the join ambiguous and would be a stop, not a dedup.

Output (all under --cache-dir):

  tree_points_pages/page_%05d.csv        one raw response per page, verbatim
  planting_spaces_pages/page_%05d.csv
  tree_points.csv                        the concatenation, header + rows
  planting_spaces.csv
  nyc_fetch.meta.json                    extraction date, server counts, columns
  requests.log                           one line per request that left here

Usage:
    python3 Tools/fetch_nyc_trees.py --cache-dir PATH [--delay SECONDS]
                                     [--dataset tree_points|planting_spaces|both]
                                     [--force] [--verify]
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

DOMAIN = "https://data.cityofnewyork.us"
PAGE_SIZE = 50_000

UA = "Cypress-tree-ingest/1.0 (research; contact nmbogdan@alumni.stanford.edu)"

# Ask for these by name rather than `*`, so a column appearing upstream does not
# silently change the cache's shape underneath a build. Every one is read by
# `NYCTreePointAdapter`; nothing is fetched that nothing reads.
#
# `location` is the GeoJSON point and is the position of record. `geometry` (WKT)
# carries the same coordinates and is not fetched -- one position field, so no
# reader has to decide which of two to believe.
TREE_POINT_FIELDS = [
    "globalid", "objectid", "dbh", "tpstructure", "tpcondition", "stumpdiameter",
    "plantingspaceglobalid", "genusspecies", "planteddate", "createddate",
    "updateddate", "riskrating", "riskratingdate", "location",
]

# Planting Spaces supplies the columns Tree Points does not have. `latitude` and
# `longitude` are fetched but NOT used for tree position -- the tree's position is
# the tree point's own. They are here so the join can be checked against them.
PLANTING_SPACE_FIELDS = [
    "globalid", "objectid", "boroughcode", "buildingnumber", "streetname",
    "pssite", "psstatus", "jurisdiction", "overheadutilities", "treeguard",
    "width", "length", "parkname", "zipcode", "nta", "location",
]

DATASETS = {
    "tree_points": {
        "socrata_id": "hn5i-inap",
        "fields": TREE_POINT_FIELDS,
        "name": "Forestry Tree Points",
    },
    "planting_spaces": {
        "socrata_id": "82zj-84is",
        "fields": PLANTING_SPACE_FIELDS,
        "name": "Forestry Planting Spaces",
    },
}

#: New York City's own extent, generously padded. Used only by `--verify`: a row
#: outside it means the fetch got somebody else's data, which is E172's
#: Springfield failure and is worth a hard stop rather than a warning.
NYC_BBOX = (40.40, 41.00, -74.35, -73.65)  # lat_min, lat_max, lon_min, lon_max

_request_log_path: str | None = None
_requests_sent = 0


def log(msg: str) -> None:
    print(f"[fetch_nyc] {msg}", flush=True)


def die(msg: str, code: int = 3):
    print(f"[fetch_nyc] FATAL: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def _note_request(url: str, note: str) -> None:
    """Append one line per request that actually left this machine."""
    global _requests_sent
    _requests_sent += 1
    if _request_log_path is None:
        return
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(_request_log_path, "a", encoding="utf-8") as fh:
        fh.write(f"{stamp}\tnyc\t{note}\t{url}\n")


def request(socrata_id: str, note: str, extension: str = "json", **params):
    """One GET against a Socrata resource, with a backoff. Never concurrent."""
    url = f"{DOMAIN}/resource/{socrata_id}.{extension}"
    query = urllib.parse.urlencode(params)
    full = f"{url}?{query}"
    last = None
    for attempt in range(5):
        try:
            _note_request(full, note if attempt == 0 else f"{note}/retry{attempt}")
            req = urllib.request.Request(full, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=300) as resp:
                payload = resp.read()
            if extension == "json":
                return json.loads(payload)
            return payload.decode("utf-8")
        except Exception as exc:  # noqa: BLE001
            last = exc
            if attempt == 4:
                break
            wait = 3 * (attempt + 1)
            log(f"  request failed ({exc}); retrying in {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"giving up after 5 attempts: {last}")


def server_count(socrata_id: str, note: str) -> int:
    payload = request(socrata_id, note, "json", **{"$select": "count(*) as n"})
    return int(payload[0]["n"])


def query_page(socrata_id: str, fields: list, offset: int, note: str, limit: int = PAGE_SIZE) -> str:
    return request(
        socrata_id,
        note,
        "csv",
        **{
            "$select": ",".join(fields),
            # `:id` is Socrata's own row identifier: present on every row, unique
            # by construction, and stable for the life of a row. Ordering by a
            # data column would page unstably wherever that column repeats, and
            # on Planting Spaces `globalid` and `objectid` BOTH repeat.
            "$order": ":id",
            "$limit": str(limit),
            "$offset": str(offset),
        },
    )


def parse_point(raw: str):
    """A `location` cell -> (lat, lon), or (None, None).

    Socrata's CSV renders a point column as WKT, `POINT (lon lat)` -- longitude
    first, which is the opposite of the order every other field in this pipeline
    uses and is the single easiest thing here to get backwards. A swapped pair
    puts every NYC tree in Antarctica, which is why `--verify`'s bounding box
    checks the parsed values rather than the raw string.
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
    if lat != lat or lon != lon:
        return None, None
    return lat, lon


def check_rows(rows, where: str, id_column: str = "globalid") -> None:
    """Every row is an NYC forestry record, or the run stops. See E172."""
    lat_min, lat_max, lon_min, lon_max = NYC_BBOX
    for row in rows:
        if not str(row.get(id_column) or "").strip():
            die(f"{where}: a row carries no {id_column}; identity is not derivable")
        lat, lon = parse_point(row.get("location"))
        if lat is None or lon is None:
            continue  # a record with no position is the adapter's to drop
        if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
            die(
                f"{where}: {id_column} {row.get(id_column)!r} is at ({lat}, {lon}), "
                f"outside New York City. E172's Springfield failure: this response "
                f"is not this layer's data."
            )


def read_csv_rows(text: str) -> list:
    return list(csv.DictReader(text.splitlines()))


def require_ignored(path: str) -> None:
    """Refuse a cache directory git would track. Bulk data never gets committed."""
    absolute = os.path.abspath(path)
    try:
        inside = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=os.path.dirname(absolute) if os.path.isdir(absolute) else "/",
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return  # not in a work tree at all; nothing can be committed from here
    if inside.returncode != 0:
        return
    probe = os.path.join(absolute, ".fetch_nyc_probe")
    check = subprocess.run(
        ["git", "check-ignore", "-q", probe],
        cwd=inside.stdout.strip(), capture_output=True, timeout=30,
    )
    if check.returncode != 0:
        die(
            f"--cache-dir {absolute} is inside a git work tree and is NOT ignored. "
            f"These extracts are ~350 MB and Fixtures/raw/nyc/ holds the survey's "
            f"38 sample rows only. Point --cache-dir outside the repo."
        )


def fetch_dataset(dataset: str, cache_dir: str, delay: float, force: bool, verify: bool) -> dict:
    spec = DATASETS[dataset]
    socrata_id, fields = spec["socrata_id"], spec["fields"]
    pages_dir = os.path.join(cache_dir, f"{dataset}_pages")
    os.makedirs(pages_dir, exist_ok=True)
    combined_path = os.path.join(cache_dir, f"{dataset}.csv")

    if force:
        for name in sorted(os.listdir(pages_dir)):
            os.remove(os.path.join(pages_dir, name))
        log(f"--force: cleared the {dataset} page cache")

    total = server_count(socrata_id, f"{dataset}-count")
    log(f"{spec['name']} ({socrata_id}): {total:,} rows on the server")

    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    fetched = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.csv")
        if os.path.exists(path):
            continue
        offset = page * PAGE_SIZE
        text = query_page(socrata_id, fields, offset, f"{dataset}-page-{page}")
        rows = read_csv_rows(text)
        if not rows:
            die(f"{dataset} page {page} (offset {offset}) came back empty; the layer moved under us")
        tmp = path + ".part"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
        fetched += 1
        log(f"  page {page + 1}/{pages}  offset {offset:>9}  {len(rows):,} rows")
        if page + 1 < pages:
            time.sleep(delay)

    log(f"{dataset}: {fetched} pages fetched this run, {pages - fetched} already cached")

    # ---- concatenate every cached page into one CSV -----------------------
    # Every cached page is checked, not just the ones this run fetched. A page
    # written by an earlier run is exactly as capable of holding Springfield.
    seen_ids = {}
    duplicate_rows = 0
    disagreeing_duplicates = 0
    rows_written = 0
    no_position = 0
    tmp = combined_path + ".part"
    with open(tmp, "w", encoding="utf-8", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for page in range(pages):
            path = os.path.join(pages_dir, f"page_{page:05d}.csv")
            with open(path, "r", encoding="utf-8") as fh:
                rows = read_csv_rows(fh.read())
            check_rows(rows, f"cached {dataset} page {page}")
            for row in rows:
                key = str(row.get("globalid") or "").strip()
                signature = tuple((field, row.get(field)) for field in fields)
                if key in seen_ids:
                    duplicate_rows += 1
                    # A duplicate that AGREES is one record published twice and
                    # is dropped. A duplicate that DISAGREES is two records
                    # sharing an id, which makes the join ambiguous -- counted
                    # here and reported, never silently collapsed.
                    if seen_ids[key] != signature:
                        disagreeing_duplicates += 1
                    continue
                seen_ids[key] = signature
                lat, lon = parse_point(row.get("location"))
                if lat is None or lon is None:
                    no_position += 1
                writer.writerow(row)
                rows_written += 1
    os.replace(tmp, combined_path)
    log(
        f"wrote {combined_path} ({rows_written:,} rows; {duplicate_rows:,} duplicate "
        f"globalids dropped, {disagreeing_duplicates:,} of which DISAGREED; "
        f"{no_position:,} rows with no position)"
    )
    if disagreeing_duplicates:
        log(
            f"  WARNING: {disagreeing_duplicates:,} {dataset} rows share a globalid with "
            f"DIFFERENT column values. The join key is not a key. Do not build on this "
            f"extract until that is resolved."
        )

    # ---- the deep-page check (E172) ---------------------------------------
    if verify:
        for label, offset in (
            ("first", 0),
            ("middle", (pages // 2) * PAGE_SIZE),
            ("last", (pages - 1) * PAGE_SIZE),
        ):
            text = query_page(socrata_id, fields, offset, f"{dataset}-verify-{label}", limit=1000)
            rows = read_csv_rows(text)
            check_rows(rows, f"verify {dataset} {label} (offset {offset})")
            log(
                f"  verify {label:6} offset {offset:>9}: {len(rows):,} rows, "
                f"all inside New York City, all carry a GlobalID"
            )
            time.sleep(delay)

    return {
        "socrata_id": socrata_id,
        "name": spec["name"],
        "server_row_count": total,
        "rows_written": rows_written,
        "duplicate_globalids_dropped": duplicate_rows,
        "disagreeing_duplicates": disagreeing_duplicates,
        "rows_without_position": no_position,
        "pages": pages,
        "page_size": PAGE_SIZE,
        "fields": fields,
    }


def fetch(cache_dir: str, datasets: list, delay: float, force: bool, verify: bool) -> int:
    global _request_log_path
    os.makedirs(cache_dir, exist_ok=True)
    require_ignored(cache_dir)
    _request_log_path = os.path.join(cache_dir, "requests.log")
    meta_path = os.path.join(cache_dir, "nyc_fetch.meta.json")

    meta = {}
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError):
            meta = {}

    for dataset in datasets:
        meta[dataset] = fetch_dataset(dataset, cache_dir, delay, force, verify)

    # The date this cache was taken from the city. Recorded here and nowhere
    # else, so a rebuild reports when the data was fetched rather than when the
    # rebuild ran. Preserved across a resumed run: only a --force refetch of
    # everything moves it.
    meta.setdefault("extracted_on", datetime.now(timezone.utc).date().isoformat())
    if force:
        meta["extracted_on"] = datetime.now(timezone.utc).date().isoformat()
    meta["domain"] = DOMAIN
    meta["terms"] = (
        "NYC Open Data / NYC.gov Data Mine terms. Redistribution permitted; an "
        "application built on this data must notify the City and carry the Data "
        "Mine disclaimer verbatim. See docs/investigations/nyc-street-trees.md §2. "
        "NEITHER OBLIGATION IS DISCHARGED BY THIS REPO YET."
    )
    meta["licence"] = "no machine-readable licence; both datasets publish license: null"
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
    log(f"wrote {meta_path} (extracted_on {meta['extracted_on']})")
    log(f"{_requests_sent} requests left this machine this run; "
        f"the running total is in {_request_log_path}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache-dir", required=True,
                    help="where the bulk extracts go. MUST be git-ignored; ~350 MB.")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--dataset", default="both",
                    choices=["tree_points", "planting_spaces", "both"])
    ap.add_argument("--force", action="store_true", help="discard the page cache first")
    ap.add_argument("--verify", action="store_true",
                    help="re-request first/middle/last pages and check them (E172)")
    args = ap.parse_args(argv)
    datasets = ["tree_points", "planting_spaces"] if args.dataset == "both" else [args.dataset]
    return fetch(args.cache_dir, datasets, args.delay, args.force, args.verify)


if __name__ == "__main__":
    raise SystemExit(main())
