#!/usr/bin/env python3
"""
fetch_city_trees.py -- cache San Francisco Public Works' own street-tree layer.

The city's public map at https://bsm.sfdpw.org/urbanforestry/ is drawn from

    services.arcgis.com/Zs2aNLFN00jrS4gG/.../BUF_Street_Trees/FeatureServer/3

layer 3, `StreetTrees`, ~133,577 point features. `Tools/build_seed.py` reads the
cache this script writes; it never talks to the service itself, so a seed rebuild
costs the city nothing.

Discipline, because this is somebody else's public server:

  * sequential, one request at a time, never parallel;
  * `resultRecordCount` at the layer's own `maxRecordCount` of 2000, so ~67 pages;
  * a delay between pages (--delay, default 1.0s);
  * ordered by OBJECTID, which the layer guarantees contiguous 1..N, so pages are
    stable between runs and a page fetched once is never fetched again;
  * RESUMABLE. Each page lands in its own file under Fixtures/raw/city_pages/.
    A re-run skips every page already on disk. A failure at page 50 costs 17
    requests, not 67.

Output (all under Fixtures/raw/, which .gitignore already excludes -- this is a
regenerable download of the same kind as street_tree_list.csv):

  city_pages/page_%05d.json   one raw `query` response per page, kept verbatim
  city_street_trees.ndjson    the concatenation, one feature's attributes per line,
                              sorted by TREEID
  city_street_trees.meta.json extraction date, server counts, layer metadata

THE EXTRACTION DATE LIVES IN THE META FILE, NOT IN THE CLOCK. `build_seed.py`
reads it from there, so a rebuild months later from the same cache produces the
same seed bytes and still reports the date the data was actually taken.

Usage:
    python3 Tools/fetch_city_trees.py [--repo-root PATH] [--delay SECONDS] [--force]
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
    "https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/"
    "BUF_Street_Trees/FeatureServer/3"
)
QUERY = SERVICE + "/query"
PAGE_SIZE = 2000  # the layer's own maxRecordCount

# Ask for these by name rather than `*`, so a field appearing upstream does not
# silently change the cache's shape underneath a build.
FIELDS = [
    "OBJECTID", "TREEID", "Address", "SiteOrder", "COMMON", "BOTANICAL", "DBH",
    "Latitude", "Longitude", "PlantType", "bos", "keymap",
    "Prune_Status", "Prune_TreeCount", "Prune_Year", "DBHRange",
]


def log(msg: str) -> None:
    print(f"[fetch_city] {msg}", flush=True)


def die(msg: str, code: int = 3):
    print(f"[fetch_city] FATAL: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def post(url: str, **params):
    """One POST to the feature service, with a backoff. Never called concurrently."""
    params.setdefault("f", "json")
    body = urllib.parse.urlencode(params).encode()
    last = None
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, data=body)
            with urllib.request.urlopen(req, timeout=120) as resp:
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


def get(url: str):
    req = urllib.request.Request(url + "?f=json")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def fetch(repo_root: str, delay: float, force: bool) -> int:
    raw_dir = os.path.join(repo_root, "Fixtures", "raw")
    pages_dir = os.path.join(raw_dir, "city_pages")
    os.makedirs(pages_dir, exist_ok=True)

    ndjson_path = os.path.join(raw_dir, "city_street_trees.ndjson")
    meta_path = os.path.join(raw_dir, "city_street_trees.meta.json")

    if force:
        for name in sorted(os.listdir(pages_dir)):
            os.remove(os.path.join(pages_dir, name))
        log("--force: cleared the page cache")

    layer = get(SERVICE)
    total = post(QUERY, where="1=1", returnCountOnly="true")["count"]
    last_edit = layer.get("editingInfo", {}).get("lastEditDate")
    last_edit_iso = (
        datetime.fromtimestamp(last_edit / 1000, timezone.utc).date().isoformat()
        if last_edit else None
    )
    log(f"layer {layer.get('name')!r}: {total:,} features, "
        f"maxRecordCount {layer.get('maxRecordCount')}, lastEdit {last_edit_iso}")
    if layer.get("maxRecordCount", PAGE_SIZE) < PAGE_SIZE:
        die(f"maxRecordCount dropped to {layer['maxRecordCount']}; lower PAGE_SIZE")

    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    fetched = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.json")
        if os.path.exists(path):
            continue
        offset = page * PAGE_SIZE
        payload = post(
            QUERY,
            where="1=1",
            outFields=",".join(FIELDS),
            returnGeometry="false",
            orderByFields="OBJECTID ASC",
            resultOffset=str(offset),
            resultRecordCount=str(PAGE_SIZE),
        )
        got = len(payload.get("features", []))
        if got == 0:
            die(f"page {page} (offset {offset}) came back empty; the layer moved under us")
        tmp = path + ".part"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, separators=(",", ":"))
        os.replace(tmp, path)
        fetched += 1
        log(f"  page {page + 1}/{pages}  offset {offset:>6}  {got} features")
        if page + 1 < pages:
            time.sleep(delay)

    log(f"{fetched} pages fetched this run, {pages - fetched} already cached")

    # ---- concatenate, deduplicate on TREEID, sort
    by_treeid = {}
    dupes = 0
    for page in range(pages):
        path = os.path.join(pages_dir, f"page_{page:05d}.json")
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
        for feature in payload.get("features", []):
            attrs = feature["attributes"]
            key = attrs.get("TREEID")
            if key is None:
                continue
            if key in by_treeid:
                dupes += 1
                continue
            by_treeid[key] = attrs

    tmp = ndjson_path + ".part"
    with open(tmp, "w", encoding="utf-8") as fh:
        for key in sorted(by_treeid):
            fh.write(json.dumps(by_treeid[key], separators=(",", ":"), sort_keys=True))
            fh.write("\n")
    os.replace(tmp, ndjson_path)

    meta = {
        "service": SERVICE,
        "layer_name": layer.get("name"),
        # The date this cache was taken from the city. Recorded here and nowhere
        # else, so a rebuild reports when the data was fetched rather than when
        # the rebuild ran.
        "extracted_on": datetime.now(timezone.utc).date().isoformat(),
        "server_last_edit_date": last_edit_iso,
        "server_feature_count": total,
        "rows_written": len(by_treeid),
        "duplicate_treeids_dropped": dupes,
        "page_size": PAGE_SIZE,
        "pages": pages,
        "fields": FIELDS,
    }
    # Preserve the original extraction date across a resumed or topped-up run:
    # the cache is only as fresh as its OLDEST page.
    if os.path.exists(meta_path) and fetched == 0:
        with open(meta_path, "r", encoding="utf-8") as fh:
            meta["extracted_on"] = json.load(fh).get("extracted_on", meta["extracted_on"])
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)

    log(f"wrote {ndjson_path} ({len(by_treeid):,} rows, {dupes} duplicate TREEIDs dropped)")
    log(f"wrote {meta_path} (extracted_on {meta['extracted_on']})")
    if len(by_treeid) != total:
        log(f"NOTE: {total:,} features reported, {len(by_treeid):,} distinct TREEIDs written")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root",
                    default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--delay", type=float, default=1.0,
                    help="seconds between pages (default 1.0). Be kind.")
    ap.add_argument("--force", action="store_true", help="discard the page cache and refetch")
    args = ap.parse_args()
    return fetch(args.repo_root, args.delay, args.force)


if __name__ == "__main__":
    sys.exit(main())
