# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# Samples contiguous TREEID windows from the city's ArcGIS layer and compares them,
# id for id, with the local DataSF tkzw-k3nq snapshot.
import json, math, random, sys
sys.path.insert(0, "Tools/investigate")
from arc import rows

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))
print("local ids", len(local), "max", max(int(k) for k in local))

MAXID = 277733
WIN = 600
random.seed(20260725)
starts = sorted(random.sample(range(1, MAXID - WIN), 60))

arc = {}
for i, s in enumerate(starts):
    got = rows(f"TREEID >= {s} AND TREEID < {s + WIN}")
    for a in got:
        arc.setdefault(a["TREEID"], []).append(a)
    if i % 10 == 0:
        print(f"  window {i}/{len(starts)} start={s} rows={len(got)} cum={len(arc)}", flush=True)

covered = set()
for s in starts:
    covered.update(range(s, s + WIN))
loc_in = {int(k) for k in local if int(k) in covered}

print("=== windows", len(starts), "ids covered", len(covered))
print("arcgis rows in windows", sum(len(v) for v in arc.values()), "distinct TREEID", len(arc))
dupes = {k: v for k, v in arc.items() if len(v) > 1}
print("arcgis duplicate TREEIDs in sample", len(dupes))
print("datasf rows in windows", len(loc_in))

both = set(arc) & loc_in
only_arc = set(arc) - loc_in
only_loc = loc_in - set(arc)
print("in both", len(both), "arcgis-only", len(only_arc), "datasf-only", len(only_loc))


def norm(s):
    return " ".join((s or "").upper().split())


def dist_m(a, b, c, d):
    try:
        a, b, c, d = float(a), float(b), float(c), float(d)
    except Exception:
        return None
    return math.hypot((a - c) * 111320, (b - d) * 111320 * math.cos(math.radians(a)))


addr_ok = sp_ok = 0
d_ok3 = d_ok10 = 0
dists = []
addr_bad, sp_bad, far = [], [], []
for t in sorted(both):
    A = arc[t][0]
    L = local[str(t)]
    la = norm(A["Address"])
    ll = norm(L["addr"])
    if la == ll:
        addr_ok += 1
    else:
        addr_bad.append((t, A["Address"], L["addr"]))
    bot = norm(A["BOTANICAL"])
    lsp = norm(L["species"])
    if bot and (bot in lsp or lsp.startswith(bot)):
        sp_ok += 1
    else:
        sp_bad.append((t, A["COMMON"], A["BOTANICAL"], L["species"]))
    dm = dist_m(A["Latitude"], A["Longitude"], L["lat"], L["lon"])
    if dm is not None:
        dists.append(dm)
        if dm <= 3:
            d_ok3 += 1
        if dm <= 10:
            d_ok10 += 1

n = len(both)
print(f"address exact match {addr_ok}/{n} = {addr_ok/n:.4%}")
print(f"botanical name match {sp_ok}/{n} = {sp_ok/n:.4%}")
print(f"coords within 3m {d_ok3}/{len(dists)} = {d_ok3/len(dists):.4%}; within 10m {d_ok10/len(dists):.4%}")
dists.sort()
print("dist median %.2fm p95 %.2fm p99 %.2fm max %.2fm" % (
    dists[len(dists)//2], dists[int(len(dists)*.95)], dists[int(len(dists)*.99)], dists[-1]))
print("--- address mismatches (first 15)")
for x in addr_bad[:15]:
    print("   ", x)
print("--- species mismatches (first 15)")
for x in sp_bad[:15]:
    print("   ", x)

from collections import Counter
print("--- DataSF-only rows in windows, by qLegalStatus")
for k, v in Counter(local[str(t)]["legal"] for t in only_loc).most_common():
    print("   ", repr(k), v)
print("--- DataSF-only rows, by qSiteInfo (top 10)")
for k, v in Counter(local[str(t)]["site"] for t in only_loc).most_common(10):
    print("   ", repr(k), v)
print("--- DataSF-only rows, by PlantType")
for k, v in Counter(local[str(t)]["plant"] for t in only_loc).most_common():
    print("   ", repr(k), v)
print("--- ArcGIS-only sample (first 15)")
for t in sorted(only_arc)[:15]:
    a = arc[t][0]
    print("   ", t, a["Address"], "|", a["BOTANICAL"], "| DBH", a["DBH"], "|", a["Prune_Year"])

json.dump({"arc": {str(k): v for k, v in arc.items()},
           "starts": starts, "win": WIN},
          open(SCRATCH + "/sample.json", "w"))
