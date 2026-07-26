# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# For each DataSF qLegalStatus (and for site type / plant type), sample local TreeIDs
# and ask the city's ArcGIS layer whether it holds them.
import json, random, sys
from collections import Counter, defaultdict
sys.path.insert(0, "Tools/investigate")
from arc import rows

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))
random.seed(7)

by = defaultdict(list)
for k, v in local.items():
    by[v["legal"] or "(blank)"].append(k)

print("DataSF qLegalStatus totals (all 198,435 rows):")
for k, v in sorted(by.items(), key=lambda x: -len(x[1])):
    print(f"   {k!r:34} {len(v)}")


def present(ids):
    hit = set()
    for i in range(0, len(ids), 250):
        chunk = ids[i:i + 250]
        got = rows("TREEID IN (" + ",".join(chunk) + ")", out="TREEID")
        hit.update(str(a["TREEID"]) for a in got)
    return hit


print("\npresence of DataSF rows in the city's ArcGIS layer, by qLegalStatus:")
N = 500
overall_w = 0.0
for k, v in sorted(by.items(), key=lambda x: -len(x[1])):
    s = random.sample(v, min(N, len(v)))
    h = present(s)
    rate = len(h) / len(s)
    overall_w += rate * len(v)
    print(f"   {k!r:34} n={len(s):4d} present={len(h):4d}  {rate:7.2%}   (pop {len(v)})", flush=True)
print(f"   weighted estimate of DataSF rows present in ArcGIS: {overall_w:,.0f} of {len(local):,}")

# Same, sliced by site type family, restricted to the dominant status so the
# slices are comparable.
print("\npresence by qSiteInfo family (DPW Maintained rows only):")
fam = defaultdict(list)
for k, v in local.items():
    if v["legal"] == "DPW Maintained":
        fam[(v["site"] or ":").split(":")[0].strip() or "(blank)"].append(k)
for k, v in sorted(fam.items(), key=lambda x: -len(x[1]))[:8]:
    s = random.sample(v, min(300, len(v)))
    h = present(s)
    print(f"   {k!r:34} n={len(s):4d} present={len(h):4d}  {len(h)/len(s):7.2%}   (pop {len(v)})", flush=True)

print("\npresence by PlantType:")
pt = defaultdict(list)
for k, v in local.items():
    pt[v["plant"] or "(blank)"].append(k)
for k, v in sorted(pt.items(), key=lambda x: -len(x[1])):
    s = random.sample(v, min(300, len(v)))
    h = present(s)
    print(f"   {k!r:34} n={len(s):4d} present={len(h):4d}  {len(h)/len(s):7.2%}   (pop {len(v)})", flush=True)
