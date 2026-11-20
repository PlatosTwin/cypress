#!/usr/bin/env python3
"""
fetch_dc_trees.py -- cache the District of Columbia's street tree layer.

    https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/Urban_Tree_Canopy/
        MapServer/23   ("UFA Street Trees")

About 224,000 point features, published by the District Department of
Transportation (DDOT) Urban Forestry Division under CC BY 4.0.
`Tools/build_seed.py` reads the cache this script writes and never talks to the
service. The model is `Tools/fetch_san_jose_trees.py`; the differences are named
below.

Discipline, because this is somebody else's public server:

  * sequential, one request at a time, never parallel;
  * `resultRecordCount` at the layer's own `maxRecordCount` of 2000, ~112 pages;
  * a delay between pages (--delay, default 1.0 s);
  * ordered by OBJECTID, so pages are stable between runs;
  * RESUMABLE. Each page lands in its own file under <cache>/dc_pages/ and a
    re-run skips every page already on disk;
  * every request that leaves this machine is appended to
    <cache>/dc_street_trees.requests.log.

THE CACHE LIVES OUTSIDE THE REPO, like New York's, so its location is a required
argument (`--cache-dir`). The repo carries only the small sample under
`Fixtures/raw/dc/`.

GEOMETRY IS REQUESTED WITH `outSR=4326`. The layer's native spatial reference is
Maryland State Plane (wkid 26985, metres). An un-projected fetch returns
coordinates in the hundreds of thousands and every tree lands nowhere.

THE COUNT IS CHECKED, NOT ASSUMED. Paging by `resultOffset` over a layer that
DDOT edits daily can skip or repeat a row if an edit lands mid-fetch. So the
script deduplicates on GLOBALID and then refuses to write a cache whose distinct
GLOBALID count differs from the server's own `returnCountOnly` answer. A
mismatch means the fetch must be re-run with `--force`.

`--verify` re-requests the first, middle and last pages and checks that every
feature is inside the District and carries a GLOBALID (ERRATA E172's deep-page
check: one source served another city's rows at offset 0).

The User-Agent is generic on purpose. It names the tool, not a person.

Output, under --cache-dir:

  dc_pages/page_%05d.json        one raw `query` response per page, verbatim
  dc_street_trees.ndjson         one feature per line
                                 ({"attributes": {...}, "geometry": {...}}),
                                 sorted by GLOBALID
  dc_street_trees.meta.json      extraction date, server count, newest
                                 LAST_EDITED_DATE, layer metadata
  dc_street_trees.requests.log   one line per request that left this machine

Usage:
    python3 Tools/fetch_dc_trees.py --cache-dir PATH [--delay SECONDS]
                                    [--force] [--verify]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

SERVICE = (
    "https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/Urban_Tree_Canopy/"
    "MapServer/23"
)
QUERY = SERVICE + "/query"
PAGE_SIZE = 2000  # the layer's own maxRecordCount

UA = "Cypress-tree-ingest/1.0 (research)"

# Asked for by name rather than `*`, so a field appearing upstream does not
# change the cache's shape under a build. DISEASE, PESTS, SIGN and WARRANTY are
# deliberately NOT fetched: on this layer they hold editor usernames, not the
# values their names suggest. RETIREDDT and CONDITIODT are not fetched either;
# their values are not dates anyone can rely on.
FIELDS = [
    "OBJECTID", "GLOBALID", "FACILITYID", "SCI_NM", "CMMN_NM", "GENUS_NAME",
    "FAM_NAME", "DBH", "DATE_PLANT", "CONDITION", "TBOX_STAT", "WARD",
    "VICINITY", "OWNERSHIP", "TBOX_L", "TBOX_W", "LAST_EDITED_DATE",
]

#: The District's own extent, padded. Used only by the page checks.
#:
#: NOT EVERY ROW IS INSIDE IT, AND THAT IS REAL DATA. Measured on 2026-11-12:
#: 1,407 rows sit in one cluster near Laurel, Maryland (39.10, -76.79), every
#: one with VICINITY "Oak hill Dr" and OWNERSHIP DGS (1,083) or UFA (321) --
#: District-owned land outside the District. So a single row outside the box is
#: counted, not fatal; `Tools/build_seed.py`'s DC_BBOX drops them at build time.
#: What IS fatal is a page where MOST rows are outside: that is E172's failure
#: (another source's rows) or an ignored `outSR=4326`, where every row is wrong.
DC_BBOX = (38.70, 39.05, -77.25, -76.85)  # lat_min, lat_max, lon_min, lon_max
#: More than this share of a page outside DC_BBOX stops the fetch.
MAX_OUTSIDE_SHARE = 0.5

_request_log_path: str | None = None
_requests_sent = 0


def log(msg: str) -> None:
    print(f"[fetch_dc] {msg}", flush=True)


def die(msg: str, code: int = 3):
    print(f"[fetch_dc] FATAL: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def _note_request(url: str, note: str) -> None:
    global _requests_sent
    _requests_sent += 1
    if _request_log_path is None:
        return
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(_request_log_path, "a", encoding="utf-8") as fh:
        fh.write(f"{stamp}\tdc\t{note}\t{url}\n")


def post(note: str, **params):
    """One POST to the map service, with a backoff. Never called concurrently."""
    params.setdefault("f", "json")
    body = urllib.parse.urlencode(params).encode()
    last = None
    for attempt in range(5):
        try:
            _note_request(QUERY, note if attempt == 0 else f"{note}/retry{attempt}")
            req = urllib.request.Request(QUERY, data=body, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=180) as resp:
                payload = json.load(resp)
            if "error" in payload:
                raise RuntimeError(payload["error"])
            return payload
        except Exception as exc:  # noqa: BLE001
            last = exc
            if attempt == 4:
                break
            wait = 3 * (attempt + 1)
            log(f"  request failed ({exc}); retrying in {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"giving up after 5 attempts: {last}")


def get(url: str, note: str):
    _note_request(url, note)
    req = urllib.request.Request(url + "?f=json", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def query_page(offset: int, note: str):
    return post(
        note,
        where="1=1",
        outFields=",".join(FIELDS),
        returnGeometry="true",
        outSR="4326",
        orderByFields="OBJECTID ASC",
        resultOffset=str(offset),
        resultRecordCount=str(PAGE_SIZE),
    )


def check_features(features, where: str) -> int:
    """The page is District tree records, or the run stops. See E172 and DC_BBOX.

    Returns how many located features fall outside DC_BBOX. Stops the run if
    that is more than MAX_OUTSIDE_SHARE of the located features, or if any
    feature carries no GLOBALID.
    """
    lat_min, lat_max, lon_min, lon_max = DC_BBOX
    located = outside = 0
    first_outside = None
    for feature in features:
        attrs = feature.get("attributes") or {}
        geom = feature.get("geometry") or {}
        if not str(attrs.get("GLOBALID") or "").strip():
            die(f"{where}: a feature carries no GLOBALID; identity is not derivable")
        lat, lon = geom.get("y"), geom.get("x")
        if lat is None or lon is None:
            continue  # a record with no position is the adapter's to drop
        located += 1
        if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
            outside += 1
            if first_outside is None:
                first_outside = (attrs.get("GLOBALID"), lat, lon)
    if located and outside > MAX_OUTSIDE_SHARE * located:
        die(
            f"{where}: {outside} of {located} located features are outside the District "
            f"(first: GLOBALID {first_outside[0]!r} at ({first_outside[1]}, "
            f"{first_outside[2]})). Either this response is not this layer's data (E172) "
            f"or outSR=4326 was ignored."
        )
    return outside


def fetch(cache_dir: str, delay: float, force: bool, verify: bool) -> int:
    global _request_log_path
    cache_dir = os.path.abspath(cache_dir)
    pages_dir = os.path.join(cache_dir, "dc_pages")
    os.makedirs(pages_dir, exist_ok=True)
    _request_log_path = os.path.join(cache_dir, "dc_street_trees.requests.log")

    ndjson_path = os.path.join(cache_dir, "dc_street_trees.ndjson")
    meta_path = os.path.join(cache_dir, "dc_street_trees.meta.json")

    if force:
        for name in sorted(os.listdir(pages_dir)):
            if name.startswith("page_") and name.endswith(".json"):
                os.remove(os.path.join(pages_dir, name))
        log("--force: cleared the page cache")

    layer = get(SERVICE, "layer-metadata")
    total = post("count", where="1=1", returnCountOnly="true")["count"]
    log(f"layer {layer.get('name')!r}: {total:,} features, "
        f"maxRecordCount {layer.get('maxRecordCount')}")
    if layer.get("maxRecordCount", PAGE_SIZE) < PAGE_SIZE:
        die(f"maxRecordCount dropped to {layer['maxRecordCount']}; lower PAGE_SIZE")

    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    fetched = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.json")
        if os.path.exists(path):
            continue
        offset = page * PAGE_SIZE
        payload = query_page(offset, f"page-{page}")
        got = len(payload.get("features", []))
        if got == 0:
            die(f"page {page} (offset {offset}) came back empty; the layer moved under us")
        tmp = path + ".part"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, separators=(",", ":"))
        os.replace(tmp, path)
        fetched += 1
        if page % 10 == 0 or page + 1 == pages:
            log(f"  page {page + 1}/{pages}  offset {offset:>7}  {got} features")
        if page + 1 < pages:
            time.sleep(delay)

    log(f"{fetched} pages fetched this run, {pages - fetched} already cached")

    # ---- concatenate, deduplicate on GLOBALID, sort ----------------------
    by_ref = {}
    dupes = 0
    no_ref = 0
    max_edit = None
    outside_total = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.json")
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
        features = payload.get("features", [])
        outside_total += check_features(features, f"cached page {page}")
        for feature in features:
            attrs = feature.get("attributes") or {}
            key = str(attrs.get("GLOBALID") or "").strip()
            if not key:
                no_ref += 1
                continue
            if key in by_ref:
                dupes += 1
                continue
            edited = attrs.get("LAST_EDITED_DATE")
            if isinstance(edited, (int, float)) and (max_edit is None or edited > max_edit):
                max_edit = edited
            by_ref[key] = {"attributes": attrs, "geometry": feature.get("geometry")}

    # THE COUNT CHECK. A cache that does not hold every row the server says it
    # has is refused, so a build never ships a silently partial District.
    if len(by_ref) != total:
        die(
            f"the cache holds {len(by_ref):,} distinct GLOBALIDs but the server reports "
            f"{total:,} features ({dupes} duplicates across pages, {no_ref} rows with no "
            f"GLOBALID). The layer was most likely edited during the fetch. Re-run with "
            f"--force."
        )

    tmp = ndjson_path + ".part"
    with open(tmp, "w", encoding="utf-8") as fh:
        for key in sorted(by_ref):
            fh.write(json.dumps(by_ref[key], separators=(",", ":"), sort_keys=True))
            fh.write("\n")
    os.replace(tmp, ndjson_path)
    log(f"wrote {ndjson_path} ({len(by_ref):,} rows; matches the server count)")

    if verify:
        for label, offset in (
            ("first", 0),
            ("middle", (pages // 2) * PAGE_SIZE),
            ("last", (pages - 1) * PAGE_SIZE),
        ):
            payload = query_page(offset, f"verify-{label}")
            features = payload.get("features", [])
            outside = check_features(features, f"verify {label} (offset {offset})")
            log(f"  verify {label:6} offset {offset:>7}: {len(features)} features, "
                f"{outside} outside the District box, all carry a GLOBALID")
            time.sleep(delay)

    meta = {
        "service": SERVICE,
        "layer_name": layer.get("name"),
        "publisher": "District Department of Transportation (DDOT), Urban Forestry Division",
        "licence": "CC-BY-4.0",
        # The date this cache was taken. A resumed run keeps the OLDEST date,
        # because the cache is only as fresh as its oldest page.
        "extracted_on": datetime.now(timezone.utc).date().isoformat(),
        "server_feature_count": total,
        "rows_written": len(by_ref),
        "duplicate_globalids_dropped": dupes,
        "rows_without_globalid": no_ref,
        "rows_outside_district_box": outside_total,
        "max_last_edited_date": (
            datetime.fromtimestamp(max_edit / 1000.0, tz=timezone.utc).isoformat(timespec="seconds")
            if max_edit is not None else None
        ),
        "page_size": PAGE_SIZE,
        "pages": pages,
        "fields": FIELDS,
        "requests_this_run": _requests_sent,
    }
    if os.path.exists(meta_path) and fetched < pages:
        try:
            with open(meta_path, "r", encoding="utf-8") as fh:
                previous = json.load(fh)
            if previous.get("extracted_on"):
                meta["extracted_on"] = previous["extracted_on"]
        except (OSError, ValueError):
            pass
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
    log(f"wrote {meta_path} (extracted_on {meta['extracted_on']}, newest edit "
        f"{meta['max_last_edited_date']})")
    log(f"{_requests_sent} requests left this machine this run")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--cache-dir", required=True,
                    help="where the pages, ndjson and meta are written; keep it outside the repo")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--force", action="store_true", help="discard the page cache first")
    ap.add_argument("--verify", action="store_true",
                    help="re-request first/middle/last pages and check them (E172)")
    args = ap.parse_args(argv)
    return fetch(args.cache_dir, args.delay, args.force, args.verify)


if __name__ == "__main__":
    raise SystemExit(main())
