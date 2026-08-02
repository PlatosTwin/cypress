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

  seed_meta           the fused build receipt is kept verbatim EXCEPT the two
                      keys that name this file rather than the build that fed
                      it (`id_spaces_in_file`, `rows_kept`), which are
                      rewritten to the truth about this file. Publisher facts
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
  version         "s<schema_version>-r<content_rev>", e.g. "s14-r2026-07-31".
                  This is the immutable path segment on object storage:
                  cities/<id>/<version>/<id>.sqlite. A given version is
                  write-once; only manifest.json ever changes in place.

DETERMINISM. The per-city files contain no wall-clock value: every stamped
fact is derived from the input seed, and the narrowing is DELETE + VACUUM,
which is deterministic for a given input file and SQLite build. Two runs over
the same seed produce byte-identical city files (verify: run twice, compare
sha256 -- the manifest's `generated_at` is the one wall-clock field, and it
lives only in the manifest, which is content-addressed by nothing).

UPLOAD. This script never touches credentials. It writes dist/upload.sh, which
uses the standard aws CLI against AWS_* variables the RUNNER must already have
in their environment (the bucket's keys live as cypress-sync app secrets and
in the owner's Tigris dashboard; see server/README.md). If you are an agent
without those variables: stop, hand dist/ and upload.sh to the orchestrator.
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
SEED_SCHEMA_VERSION = 14

# Manifest envelope format, for the app-side parser (#157). Bump on any change
# that would break a reader of the previous shape; additive keys do not bump it.
MANIFEST_FORMAT = 1

# Display names are civic facts, entered by hand on purpose: a city id with no
# entry here fails the run loudly rather than shipping an invented or derived
# name (DECISIONS constraint 15 is about botanical/civic content invention).
DISPLAY_NAMES = {
    "sf": "San Francisco",
    "us-ca-sj": "San Jose",
}

# seed_meta keys that state a city's ship coverage. The v14-era ingest writes
# per-city ad-hoc key names; map them here until build_seed.py standardizes on
# coverage_<id_space>. Absent key means full coverage.
COVERAGE_KEYS = {
    "us-ca-sj": "sj_ship_extent",
}


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


def build_city_file(src: str, dest: str, space: str) -> dict:
    """Copy the fused seed to dest, narrow it to one city, verify, and measure.

    Returns the measured facts for the manifest entry. Any failed check exits.
    """
    shutil.copyfile(src, dest)
    con = sqlite3.connect(dest)
    try:
        cur = con.cursor()

        # Refuse to sever a lineage link across id spaces. None exist today
        # (a site's replacement stands in the same city); if one ever does,
        # deleting silently would corrupt provenance.
        (cross,) = cur.execute(
            "SELECT COUNT(*) FROM trees t JOIN trees p ON p.id = t.site_lineage "
            "WHERE t.id_space = ? AND p.id_space != ?", (space, space)).fetchone()
        if cross:
            fail(f"{space}: {cross} site_lineage links cross id spaces; "
                 "splitting would sever provenance -- stop and report")

        cur.execute("DELETE FROM species_assertions WHERE tree_id IN "
                    "(SELECT id FROM trees WHERE id_space != ?)", (space,))
        cur.execute("DELETE FROM trees_rtree WHERE id IN "
                    "(SELECT id FROM trees WHERE id_space != ?)", (space,))
        cur.execute("DELETE FROM trees WHERE id_space != ?", (space,))
        cur.execute("DELETE FROM neighborhoods WHERE id NOT IN "
                    "(SELECT neighborhood_id FROM trees "
                    " WHERE neighborhood_id IS NOT NULL)")
        cur.execute("DELETE FROM inventories WHERE id_space != ?", (space,))
        cur.execute("DELETE FROM id_spaces WHERE id != ?", (space,))
        con.commit()

        fused_meta = meta(con)
        rev = content_rev_for(space, fused_meta)
        (count,) = cur.execute("SELECT COUNT(*) FROM trees").fetchone()
        if count == 0:
            fail(f"{space}: zero trees survived the split")

        # The two receipt keys that name THIS FILE, rewritten to the truth
        # about it; everything else in seed_meta stays the fused build receipt.
        rewrites = {
            "id_spaces_in_file": space,
            "rows_kept": str(count),
            "trees_snapshot_on": rev,
        }
        additions = {
            "publish_city_id": space,
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
            fail(f"{space}: foreign_key_check reported {len(fk)} violations, "
                 f"first: {fk[0]!r}")
        (integrity,) = cur.execute("PRAGMA integrity_check").fetchone()
        if integrity != "ok":
            fail(f"{space}: integrity_check said {integrity!r}")
        (foreign_rows,) = cur.execute(
            "SELECT COUNT(*) FROM trees WHERE id_space != ?", (space,)).fetchone()
        if foreign_rows:
            fail(f"{space}: {foreign_rows} foreign-space trees survived")
        (rtree_count,) = cur.execute("SELECT COUNT(*) FROM trees_rtree").fetchone()
        if rtree_count != count:
            fail(f"{space}: rtree has {rtree_count} entries for {count} trees")
        (orphan_assertions,) = cur.execute(
            "SELECT COUNT(*) FROM species_assertions sa "
            "LEFT JOIN trees t ON t.id = sa.tree_id WHERE t.id IS NULL").fetchone()
        if orphan_assertions:
            fail(f"{space}: {orphan_assertions} orphaned species_assertions")

        bbox = cur.execute(
            "SELECT MIN(lat), MAX(lat), MIN(lon), MAX(lon) FROM trees").fetchone()
    finally:
        con.close()

    coverage = "full"
    cov_key = COVERAGE_KEYS.get(space)
    if cov_key and fused_meta.get(cov_key):
        coverage = fused_meta[cov_key]

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
    ap.add_argument("--base-url", default="https://fly.storage.tigris.dev/cypress-cities")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        fail(f"no seed at {args.db} -- run Tools/build_seed.py or "
             "Tools/setup_worktree.sh first", 3)

    src_con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    spaces = [r[0] for r in src_con.execute(
        "SELECT DISTINCT id_space FROM trees ORDER BY id_space")]
    declared = {r[0] for r in src_con.execute("SELECT id FROM id_spaces")}
    if not set(spaces) <= declared:
        fail(f"trees carry id_spaces {set(spaces) - declared} not declared "
             "in id_spaces", 3)
    fused_counts = dict(src_con.execute(
        "SELECT id_space, COUNT(*) FROM trees GROUP BY id_space"))
    (fused_total,) = src_con.execute("SELECT COUNT(*) FROM trees").fetchone()
    fused_meta_src = meta(src_con)

    missing = [s for s in spaces if s not in DISPLAY_NAMES]
    if missing:
        fail(f"no display name for id_space(s) {missing}; add them to "
             "DISPLAY_NAMES -- names are entered, never derived", 3)

    cities_dir = os.path.join(args.out, "cities")
    if os.path.isdir(cities_dir):
        shutil.rmtree(cities_dir)
    os.makedirs(cities_dir, exist_ok=True)

    entries = []
    for space in spaces:
        rev_preview = content_rev_for(space, fused_meta_src)
        version = f"s{SEED_SCHEMA_VERSION}-r{rev_preview}"
        rel_path = f"cities/{space}/{version}/{space}.sqlite"
        dest = os.path.join(args.out, rel_path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        print(f"building {rel_path} ...")
        facts = build_city_file(args.db, dest, space)
        if facts["content_rev"] != rev_preview:
            fail(f"{space}: content_rev drifted during the build")
        if facts["tree_count"] != fused_counts[space]:
            fail(f"{space}: split kept {facts['tree_count']} trees but the fused "
                 f"seed holds {fused_counts[space]} for this space")

        size = os.path.getsize(dest)
        digest = sha256_of(dest)
        print(f"  {facts['tree_count']:>7} trees  {size / 1e6:7.1f} MB  sha256 {digest[:16]}...")

        entries.append({
            "id": space,
            "display_name": DISPLAY_NAMES[space],
            "coverage": facts["coverage"],
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
        fail(f"per-city counts sum to {total_split}, fused seed holds {fused_total}")

    manifest = {
        "manifest_format": MANIFEST_FORMAT,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "Tools/publish_cities.py",
        "base_url_hint": args.base_url,
        "source_seed": {
            "generated_at": fused_meta_src.get("generated_at", ""),
            "tree_count": fused_total,
            "sha256": sha256_of(args.db),
        },
        "cities": entries,
    }
    manifest_path = os.path.join(args.out, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")

    # ---- verify the manifest against the files it describes ----
    with open(manifest_path) as f:
        readback = json.load(f)
    for entry in readback["cities"]:
        path = os.path.join(args.out, entry["path"])
        if sha256_of(path) != entry["sha256"]:
            fail(f"{entry['id']}: manifest sha256 does not match the file")
        if os.path.getsize(path) != entry["bytes"]:
            fail(f"{entry['id']}: manifest byte size does not match the file")

    upload_sh = os.path.join(args.out, "upload.sh")
    with open(upload_sh, "w") as f:
        f.write("#!/bin/sh\n")
        f.write("# Generated by Tools/publish_cities.py. Requires AWS_ACCESS_KEY_ID,\n")
        f.write("# AWS_SECRET_ACCESS_KEY in the environment (Tigris keys -- see\n")
        f.write("# server/README.md). Never commit this environment anywhere.\n")
        f.write("set -eu\n")
        f.write('cd "$(dirname "$0")"\n')
        f.write("ENDPOINT=https://fly.storage.tigris.dev\n")
        f.write("BUCKET=s3://cypress-cities\n")
        for entry in entries:
            f.write(f'aws s3 cp "{entry["path"]}" "$BUCKET/{entry["path"]}" '
                    f'--endpoint-url "$ENDPOINT"\n')
        f.write('aws s3 cp manifest.json "$BUCKET/manifest.json" '
                '--endpoint-url "$ENDPOINT" --content-type application/json\n')
    os.chmod(upload_sh, 0o755)

    print(f"\nmanifest: {manifest_path}")
    print(f"upload:   {upload_sh}  (run only with the bucket's AWS_* env present)")
    print("OK")


if __name__ == "__main__":
    main()
