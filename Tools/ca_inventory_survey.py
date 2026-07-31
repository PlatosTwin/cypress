#!/usr/bin/env python3
"""ca_inventory_survey.py -- probe California cities' public tree inventories.

Task #107 asks which city is ingested after San Francisco. This script is the
measuring instrument for that question: it asks each candidate's own API what it
publishes, and writes the answers down. Nothing here builds a seed and nothing
here writes Swift; it produces the facts that
`docs/investigations/ca-tree-inventories.md` is written from.

WHY IT CACHES EVERYTHING. These are somebody else's public servers. Every
response lands under `Fixtures/raw/ca_survey/bodies/` keyed by a sha1 of the URL,
a URL already on disk is never requested again, and every request that actually
went out is appended to `Fixtures/raw/ca_survey/requests.log`. So the per-source
request count in the write-up is a number read off a file rather than a
recollection -- the same discipline `Tools/fetch_city_trees.py` applies to San
Francisco's 67 pages.

WHAT IT ASKS EACH SOURCE. Three cheap questions, never a bulk download:

    metadata   the field list, so the contract's fields can be looked for by name
    count      `returnCountOnly` / `$select=count(*)`, so a row count is measured
    sample     five rows, so a field's *values* can be read rather than guessed

A field named `DBH` that is a string range like `"12-18"` and a field named `DBH`
that is a number are the same name and different data, and only the sample tells
them apart. That distinction is the whole reason `InventoryRecord.dbh_in` says
"inches, measured".

Usage:
    python3 Tools/ca_inventory_survey.py                # probe all candidates
    python3 Tools/ca_inventory_survey.py --only berkeley
    python3 Tools/ca_inventory_survey.py --counts       # print request counts
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

UA = "Cypress-tree-survey/1.0 (research; contact nmbogdan@alumni.stanford.edu)"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_ROOT = os.path.join(REPO_ROOT, "Fixtures", "raw", "ca_survey")
BODIES = os.path.join(CACHE_ROOT, "bodies")
REQUEST_LOG = os.path.join(CACHE_ROOT, "requests.log")
DEFAULT_DELAY = 1.0

_last_hit: dict[str, float] = {}


# ---------------------------------------------------------------------------
# The candidates
# ---------------------------------------------------------------------------
# Each entry is one *published inventory*, not one city: a city that publishes
# two lists gets two entries, exactly as San Francisco does. `kind` is the API
# family, which decides which three questions get asked.

CANDIDATES = [
    {
        "key": "berkeley",
        "city": "Berkeley",
        "name": "City Trees",
        "kind": "socrata",
        "domain": "data.cityofberkeley.info",
        "dataset": "9t35-jmin",
    },
    {
        "key": "santa_monica",
        "city": "Santa Monica",
        "name": "Trees Inventory",
        "kind": "socrata",
        "domain": "data.smgov.net",
        "dataset": "w8ue-6cnd",
    },
    {
        "key": "oakland",
        "city": "Oakland",
        "name": "Oakland Street Trees",
        "kind": "socrata",
        "domain": "data.oaklandca.gov",
        "dataset": "4jcx-enxf",
    },
    {
        "key": "los_angeles",
        "city": "Los Angeles",
        "name": "Trees (Bureau of Street Services)",
        "kind": "arcgis",
        "service": (
            "https://services5.arcgis.com/7nsPwEMP38bSkCjy/arcgis/rest/services/"
            "Trees_Data_Bureau_of_Street_Services/FeatureServer"
        ),
        "layer": 0,
    },
    {
        "key": "sacramento",
        "city": "Sacramento",
        "name": "City Maintained Trees",
        "kind": "arcgis",
        "service": (
            "https://services5.arcgis.com/54falWtcpty3V47Z/arcgis/rest/services/"
            "City_Maintained_Trees/FeatureServer"
        ),
        "layer": 0,
    },
    {
        "key": "san_jose",
        "city": "San Jose",
        "name": "Street Tree",
        "kind": "arcgis",
        "service": "https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/MapServer",
        "layer": 510,
    },
    {
        "key": "san_mateo",
        "city": "San Mateo",
        "name": "Street Trees",
        "kind": "arcgis",
        "service": (
            "https://services2.arcgis.com/g26Y0m7OCdjU0ObA/arcgis/rest/services/"
            "Street_Trees/FeatureServer"
        ),
        "layer": 0,
    },
]


# ---------------------------------------------------------------------------
# Polite cached HTTP
# ---------------------------------------------------------------------------


def _paths(url: str):
    key = hashlib.sha1(url.encode()).hexdigest()[:20]
    return os.path.join(BODIES, key + ".body"), os.path.join(BODIES, key + ".meta.json")


def fetch(url: str, source: str, note: str = "", delay: float = DEFAULT_DELAY, timeout: int = 60):
    """(status, body, from_cache). A cached URL costs no request, ever."""
    os.makedirs(BODIES, exist_ok=True)
    body_path, meta_path = _paths(url)
    if os.path.exists(body_path):
        with open(body_path, "rb") as fh:
            return 200, fh.read(), True
    if os.path.exists(meta_path):
        with open(meta_path) as fh:
            meta = json.load(fh)
        if meta.get("error"):
            return meta.get("status", 0), b"", True

    host = urllib.parse.urlparse(url).netloc
    waited = time.time() - _last_hit.get(host, 0.0)
    if waited < delay:
        time.sleep(delay - waited)
    _last_hit[host] = time.time()

    status, body, error = 0, b"", None
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status, body = response.status, response.read()
    except urllib.error.HTTPError as e:
        status, body, error = e.code, e.read()[:4000], f"HTTPError {e.code}"
    except Exception as e:  # noqa: BLE001
        error = f"{type(e).__name__}: {e}"

    meta = {
        "url": url,
        "source": source,
        "status": status,
        "bytes": len(body),
        "fetched_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "error": error,
        "note": note,
    }
    with open(meta_path, "w") as fh:
        json.dump(meta, fh, indent=1)
    if error is None:
        with open(body_path, "wb") as fh:
            fh.write(body)
    with open(REQUEST_LOG, "a") as fh:
        fh.write(json.dumps(meta) + "\n")
    return status, body, False


def request_counts() -> dict:
    counts: dict[str, int] = {}
    if not os.path.exists(REQUEST_LOG):
        return counts
    with open(REQUEST_LOG) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                source = json.loads(line)["source"]
            except Exception:  # noqa: BLE001
                continue
            counts[source] = counts.get(source, 0) + 1
    return counts


def log(msg: str) -> None:
    print(f"[survey] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Per-API-family probes
# ---------------------------------------------------------------------------


def probe_arcgis(c: dict) -> dict:
    base = f"{c['service']}/{c['layer']}"
    out = {"endpoint": base}

    status, body, hit = fetch(base + "?f=json", c["key"], "layer metadata")
    out["metadata_status"] = status
    if status == 200:
        meta = json.loads(body)
        out["layer_name"] = meta.get("name")
        out["max_record_count"] = meta.get("maxRecordCount")
        out["copyright"] = (meta.get("copyrightText") or "").strip()[:500]
        out["description"] = (meta.get("description") or "").strip()[:800]
        out["fields"] = [
            {"name": f.get("name"), "type": f.get("type"), "alias": f.get("alias")}
            for f in meta.get("fields", [])
        ]
        out["object_id_field"] = meta.get("objectIdField")

    status, body, hit = fetch(
        base + "/query?where=1%3D1&returnCountOnly=true&f=json", c["key"], "row count"
    )
    if status == 200:
        try:
            out["row_count"] = json.loads(body).get("count")
        except Exception:  # noqa: BLE001
            out["row_count"] = None

    status, body, hit = fetch(
        base + "/query?where=1%3D1&outFields=*&resultRecordCount=5&returnGeometry=true"
        "&outSR=4326&f=json",
        c["key"],
        "five sample rows",
    )
    if status == 200:
        try:
            data = json.loads(body)
            out["sample"] = [
                {"attributes": f.get("attributes"), "geometry": f.get("geometry")}
                for f in data.get("features", [])
            ]
        except Exception:  # noqa: BLE001
            out["sample"] = []
    return out


def probe_socrata(c: dict) -> dict:
    domain, dataset = c["domain"], c["dataset"]
    out = {"endpoint": f"https://{domain}/resource/{dataset}"}

    status, body, hit = fetch(
        f"https://{domain}/api/views/{dataset}.json", c["key"], "dataset metadata"
    )
    out["metadata_status"] = status
    if status == 200:
        meta = json.loads(body)
        out["layer_name"] = meta.get("name")
        out["description"] = (meta.get("description") or "").strip()[:1200]
        lic = meta.get("license") or {}
        out["license_name"] = lic.get("name")
        out["license_url"] = lic.get("termsLink") or lic.get("logoUrl")
        out["license_id"] = meta.get("licenseId")
        out["attribution"] = meta.get("attribution")
        out["rows_updated_at"] = meta.get("rowsUpdatedAt")
        out["fields"] = [
            {
                "name": col.get("fieldName"),
                "type": col.get("dataTypeName"),
                "alias": col.get("name"),
                "description": (col.get("description") or "")[:160],
            }
            for col in meta.get("columns", [])
        ]

    status, body, hit = fetch(
        f"https://{domain}/resource/{dataset}.json?%24select=count(*)%20AS%20n",
        c["key"],
        "row count",
    )
    if status == 200:
        try:
            out["row_count"] = int(json.loads(body)[0]["n"])
        except Exception:  # noqa: BLE001
            out["row_count"] = None

    status, body, hit = fetch(
        f"https://{domain}/resource/{dataset}.json?%24limit=5", c["key"], "five sample rows"
    )
    if status == 200:
        try:
            out["sample"] = json.loads(body)
        except Exception:  # noqa: BLE001
            out["sample"] = []
    return out


PROBES = {"arcgis": probe_arcgis, "socrata": probe_socrata}


# ---------------------------------------------------------------------------


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", action="append", default=[], help="probe only these keys")
    ap.add_argument("--counts", action="store_true", help="print request counts and exit")
    ap.add_argument("--out", default=os.path.join(CACHE_ROOT, "survey.json"))
    args = ap.parse_args(argv)

    if args.counts:
        counts = request_counts()
        for source in sorted(counts):
            print(f"{source:<20} {counts[source]:>4} requests")
        print(f"{'TOTAL':<20} {sum(counts.values()):>4} requests")
        return 0

    wanted = [c for c in CANDIDATES if not args.only or c["key"] in args.only]
    results = {}
    for c in wanted:
        log(f"probing {c['key']} ({c['city']} -- {c['name']}, {c['kind']})")
        try:
            result = PROBES[c["kind"]](c)
        except Exception as e:  # noqa: BLE001
            log(f"  {c['key']}: FAILED {type(e).__name__}: {e}")
            result = {"error": f"{type(e).__name__}: {e}"}
        result.update({k: c[k] for k in ("city", "name", "kind")})
        results[c["key"]] = result
        log(
            f"  rows={result.get('row_count')} fields={len(result.get('fields') or [])} "
            f"licence={result.get('license_name') or result.get('copyright') or '(none stated)'}"
        )

    os.makedirs(CACHE_ROOT, exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(results, fh, indent=1, sort_keys=True)
    log(f"wrote {args.out}")

    counts = request_counts()
    log("requests made (cumulative, from requests.log):")
    for source in sorted(counts):
        log(f"    {source:<20} {counts[source]:>4}")
    log(f"    {'TOTAL':<20} {sum(counts.values()):>4}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
