#!/usr/bin/env python3
"""fetch_sf_park_trees.py -- survey and cache San Francisco Rec & Park's tree records.

Task #106: Golden Gate Park is empty because SF Public Works' street-tree layer
covers streets. The trees inside a park are Rec & Park's, and this script is the
measuring instrument for what Rec & Park actually publishes -- and, once found,
the downloader that `Tools/build_seed.py` reads from.

WHY IT CACHES EVERYTHING. Somebody else's public server. Every response lands
under `Fixtures/raw/sf_park/bodies/` keyed by a sha1 of the URL, a URL already on
disk is never requested again, and every request that actually went out is
appended to `Fixtures/raw/sf_park/requests.log`. The per-source request count in
the write-up is therefore read off a file rather than recalled -- the discipline
`Tools/fetch_city_trees.py` (67 pages) and `Tools/ca_inventory_survey.py` apply.

Subcommands:
    probe    ask a Socrata dataset or an ArcGIS layer its metadata / count / sample
    counts   print the request counts per source, read from requests.log
    fetch    page a chosen source into `Fixtures/raw/sf_park/`
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
CACHE_ROOT = os.path.join(REPO_ROOT, "Fixtures", "raw", "sf_park")
BODIES = os.path.join(CACHE_ROOT, "bodies")
REQUEST_LOG = os.path.join(CACHE_ROOT, "requests.log")
DEFAULT_DELAY = 1.0

_last_hit: dict[str, float] = {}


def log(msg: str) -> None:
    print(f"[sf_park] {msg}", flush=True)


def _paths(url: str):
    key = hashlib.sha1(url.encode()).hexdigest()[:20]
    return os.path.join(BODIES, key + ".body"), os.path.join(BODIES, key + ".meta.json")


def fetch(url: str, source: str, note: str = "", delay: float = DEFAULT_DELAY, timeout: int = 90):
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
    os.makedirs(CACHE_ROOT, exist_ok=True)
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


def cmd_counts(args) -> int:
    counts = request_counts()
    for source in sorted(counts):
        print(f"{source:<28} {counts[source]:>4} requests")
    print(f"{'TOTAL':<28} {sum(counts.values()):>4} requests")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("counts")
    p.set_defaults(func=cmd_counts)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
