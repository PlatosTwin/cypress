#!/usr/bin/env python3
"""
fetch_san_jose_trees.py -- cache the City of San Jose's Street Tree layer.

    https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/
        MapServer/510

344,879 point features, CC-BY (`license_id: cc-by` on the city's own CKAN
package `street-tree` -- the only surveyed California source that publishes an
actual licence grant, see docs/investigations/ca-tree-inventories.md §4).
`Tools/build_seed.py` reads the cache this script writes and never talks to the
service, exactly as `fetch_city_trees.py` arranges for San Francisco.

Discipline, because this is somebody else's public server:

  * sequential, one request at a time, never parallel;
  * `resultRecordCount` at the layer's own `maxRecordCount` of 2000, ~173 pages;
  * a delay between pages (--delay, default 1.0 s);
  * ordered by OBJECTID, so pages are stable between runs;
  * RESUMABLE. Each page lands in its own file under Fixtures/raw/sj_pages/ and
    a re-run skips every page already on disk. A URL on disk is never re-fetched.
  * every request that actually goes out is appended to
    Fixtures/raw/sj_street_trees.requests.log, so the count in ERRATA E176 is a
    number read off a file rather than a recollection.

GEOMETRY IS REQUESTED, unlike San Francisco's layer, which publishes Latitude
and Longitude as attributes. San Jose publishes neither, so the point comes from
`geometry` and `outSR=4326` is not optional -- the layer's native spatial
reference is California State Plane and an un-projected fetch would put every
tree in the Pacific with no error anywhere.

THE DEEP-PAGE CHECK IS PART OF THE FETCH, NOT AN AFTERTHOUGHT. Santa Monica's
CKAN datastore returns Springfield, Illinois at offset 0 and real data at offset
5,000 (ERRATA E172); an ingest that sanity-checks only its first page ships
Illinois. So `--verify` re-requests three pages spread across the result set --
first, middle, last -- and asserts every feature is inside San Jose's bounding
box and carries a FACILITYID. It is three requests and it is the difference
between "the download looked fine" and "the download was checked".

Output (all under Fixtures/raw/, which .gitignore already excludes):

  sj_pages/page_%05d.json         one raw `query` response per page, verbatim
  sj_street_trees.ndjson          the concatenation, one feature per line
                                  ({"attributes": {...}, "geometry": {...}}),
                                  sorted by FACILITYID
  sj_street_trees.meta.json       extraction date, server counts, layer metadata
  sj_street_trees.requests.log    one line per request that left this machine

Usage:
    python3 Tools/fetch_san_jose_trees.py [--repo-root PATH] [--delay SECONDS]
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
    "https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/"
    "MapServer/510"
)
QUERY = SERVICE + "/query"
PAGE_SIZE = 2000  # the layer's own maxRecordCount

UA = "Cypress-tree-ingest/1.0 (research; contact nmbogdan@alumni.stanford.edu)"

# Ask for these by name rather than `*`, so a field appearing upstream does not
# silently change the cache's shape underneath a build. Every one is read by
# `SanJoseStreetTreeAdapter`; nothing is fetched that nothing reads.
FIELDS = [
    "OBJECTID", "FACILITYID", "NAMESCIENTIFIC", "TRUNKDIAM", "INSTALLDATE",
    "CONDITION", "ADDRESSNUM", "STREETNAME", "GROWSPACE", "SPACEWIDTH",
    "VACANTSITE", "OWNEDBY", "MAINTBY",
]

#: San Jose's own extent, generously padded. Used only by `--verify`: a feature
#: outside it means the fetch got somebody else's rows, which is E172's
#: Springfield failure and is worth a hard stop rather than a warning.
SJ_BBOX = (36.95, 37.55, -122.30, -121.50)  # lat_min, lat_max, lon_min, lon_max

_request_log_path: str | None = None
_requests_sent = 0


def log(msg: str) -> None:
    print(f"[fetch_sj] {msg}", flush=True)


def die(msg: str, code: int = 3):
    print(f"[fetch_sj] FATAL: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def _note_request(url: str, note: str) -> None:
    """Append one line per request that actually left this machine."""
    global _requests_sent
    _requests_sent += 1
    if _request_log_path is None:
        return
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(_request_log_path, "a", encoding="utf-8") as fh:
        fh.write(f"{stamp}\tsan_jose\t{note}\t{url}\n")


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


def check_features(features, where: str) -> None:
    """Every feature is a San Jose tree record, or the run stops. See E172."""
    lat_min, lat_max, lon_min, lon_max = SJ_BBOX
    for feature in features:
        attrs = feature.get("attributes") or {}
        geom = feature.get("geometry") or {}
        lat, lon = geom.get("y"), geom.get("x")
        if lat is None or lon is None:
            continue  # a record with no position is the adapter's to drop
        if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
            die(
                f"{where}: FACILITYID {attrs.get('FACILITYID')!r} is at "
                f"({lat}, {lon}), outside San Jose. E172's Springfield failure: "
                f"this response is not this layer's data."
            )
        if not str(attrs.get("FACILITYID") or "").strip():
            die(f"{where}: a feature carries no FACILITYID; identity is not derivable")


def fetch(repo_root: str, delay: float, force: bool, verify: bool) -> int:
    global _request_log_path
    raw_dir = os.path.join(repo_root, "Fixtures", "raw")
    pages_dir = os.path.join(raw_dir, "sj_pages")
    os.makedirs(pages_dir, exist_ok=True)
    _request_log_path = os.path.join(raw_dir, "sj_street_trees.requests.log")

    ndjson_path = os.path.join(raw_dir, "sj_street_trees.ndjson")
    meta_path = os.path.join(raw_dir, "sj_street_trees.meta.json")

    if force:
        for name in sorted(os.listdir(pages_dir)):
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

    # ---- concatenate, deduplicate on FACILITYID, sort ---------------------
    by_ref = {}
    dupes = 0
    no_ref = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.json")
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
        features = payload.get("features", [])
        # Every cached page is checked, not just the ones this run fetched. A
        # page written by an earlier run is exactly as capable of holding
        # Springfield as one written by this one.
        check_features(features, f"cached page {page}")
        for feature in features:
            attrs = feature.get("attributes") or {}
            key = str(attrs.get("FACILITYID") or "").strip()
            if not key:
                no_ref += 1
                continue
            if key in by_ref:
                dupes += 1
                continue
            by_ref[key] = {
                "attributes": attrs,
                "geometry": feature.get("geometry"),
            }

    tmp = ndjson_path + ".part"
    with open(tmp, "w", encoding="utf-8") as fh:
        for key in sorted(by_ref):
            fh.write(json.dumps(by_ref[key], separators=(",", ":"), sort_keys=True))
            fh.write("\n")
    os.replace(tmp, ndjson_path)
    log(f"wrote {ndjson_path} ({len(by_ref):,} rows, {dupes} duplicate FACILITYIDs "
        f"dropped, {no_ref} rows with no FACILITYID)")

    # ---- the deep-page check (E172) ---------------------------------------
    if verify:
        for label, offset in (
            ("first", 0),
            ("middle", (pages // 2) * PAGE_SIZE),
            ("last", (pages - 1) * PAGE_SIZE),
        ):
            payload = query_page(offset, f"verify-{label}")
            features = payload.get("features", [])
            check_features(features, f"verify {label} (offset {offset})")
            log(f"  verify {label:6} offset {offset:>7}: {len(features)} features, "
                f"all inside San Jose, all carry a FACILITYID")
            time.sleep(delay)

    meta = {
        "service": SERVICE,
        "layer_name": layer.get("name"),
        "copyright_text": layer.get("copyrightText"),
        "licence": "CC-BY (license_id: cc-by, CKAN package `street-tree`)",
        # The date this cache was taken from the city. Recorded here and nowhere
        # else, so a rebuild reports when the data was fetched rather than when
        # the rebuild ran. Preserved across a resumed run below: the cache is
        # only as fresh as its OLDEST page.
        "extracted_on": datetime.now(timezone.utc).date().isoformat(),
        "server_feature_count": total,
        "rows_written": len(by_ref),
        "duplicate_facilityids_dropped": dupes,
        "rows_without_facilityid": no_ref,
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
    log(f"wrote {meta_path} (extracted_on {meta['extracted_on']})")
    log(f"{_requests_sent} requests left this machine this run; "
        f"the running total is in {_request_log_path}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--force", action="store_true", help="discard the page cache first")
    ap.add_argument("--verify", action="store_true",
                    help="re-request first/middle/last pages and check them (E172)")
    args = ap.parse_args(argv)
    return fetch(args.repo_root, args.delay, args.force, args.verify)


if __name__ == "__main__":
    raise SystemExit(main())
