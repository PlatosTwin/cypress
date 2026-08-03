# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# Not part of the build; safe to delete.
import csv, json, sys, os

# Repo-relative, so the script runs in any checkout. Overridable for a copy kept elsewhere.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.environ.get("STREET_TREE_CSV", os.path.join(REPO, "Fixtures/raw/street_tree_list.csv"))
out = {}
n = 0
with open(SRC, newline="", encoding="utf-8") as fh:
    for r in csv.DictReader(fh):
        n += 1
        tid = r["TreeID"].strip()
        out[tid] = {
            "species": r["qSpecies"], "addr": r["qAddress"], "lat": r["Latitude"],
            "lon": r["Longitude"], "dbh": r["DBH"], "legal": r["qLegalStatus"],
            "plant": r["PlantType"], "site": r["qSiteInfo"], "so": r["SiteOrder"],
            "care": r["qCaretaker"],
        }
print("rows", n, "unique", len(out), file=sys.stderr)
json.dump(out, open(sys.argv[1], "w"))
