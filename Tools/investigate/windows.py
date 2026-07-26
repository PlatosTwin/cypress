# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# Non-overlapping random TREEID windows: exact set comparison inside each window,
# plus attribute agreement for the ids present in both sources.
import json, math, random, sys
from collections import Counter
sys.path.insert(0, "Tools/investigate")
from arc import rows

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))
MAXID = 277733
WIN = 500
random.seed(31337)

starts, used = [], []
while len(starts) < 80:
    s = random.randrange(1, MAXID - WIN)
    if all(abs(s - u) >= WIN for u in used):
        starts.append(s)
        used.append(s)
starts.sort()

arc = {}
for i, s in enumerate(starts):
    for a in rows(f"TREEID >= {s} AND TREEID < {s + WIN}"):
        arc[a["TREEID"]] = a
    if i % 20 == 0:
        print(f"  window {i}/{len(starts)}", flush=True)

covered = set()
for s in starts:
    covered.update(range(s, s + WIN))
loc_in = {int(k) for k in local if int(k) in covered}
both = set(arc) & loc_in
only_arc = sorted(set(arc) - loc_in)
only_loc = sorted(loc_in - set(arc))

print(f"=== {len(starts)} non-overlapping windows of {WIN}, {len(covered):,} ids of id-space")
print(f"arcgis {len(arc):,} | datasf {len(loc_in):,} | both {len(both):,} | "
      f"arcgis-only {len(only_arc):,} | datasf-only {len(only_loc):,}")
print(f"arcgis rows also in datasf: {len(both)/len(arc):.2%}")
print(f"datasf rows also in arcgis: {len(both)/len(loc_in):.2%}")


def norm_addr(s):
    s = " ".join((s or "").upper().split())
    return s.replace("X ", " ", 1) if "X " in s[:12] else s


def dist_m(a, b, c, d):
    try:
        a, b, c, d = float(a), float(b), float(c), float(d)
    except Exception:
        return None
    return math.hypot((a - c) * 111320, (b - d) * 111320 * math.cos(math.radians(a)))


exact_addr = loose_addr = sp_exact = so_ok = dbh_ok = 0
dists, far = [], []
sp_bad = []
for t in sorted(both):
    A, L = arc[t], local[str(t)]
    la, ll = " ".join((A["Address"] or "").upper().split()), " ".join((L["addr"] or "").upper().split())
    if la == ll:
        exact_addr += 1
    if la == ll or la == ll.replace("X ", " ", 1) or la.split()[1:] == ll.split()[1:]:
        loose_addr += 1
    bot = " ".join((A["BOTANICAL"] or "").upper().split())
    lsp = " ".join((L["species"] or "").upper().split())
    lbot = lsp.split("::")[0].strip()
    if bot and lbot and (bot == lbot or bot in lbot or lbot in bot):
        sp_exact += 1
    else:
        sp_bad.append((t, A["BOTANICAL"], L["species"]))
    if str(A["SiteOrder"]) == str(L["so"]).split(".")[0]:
        so_ok += 1
    try:
        if int(A["DBH"] or 0) == int(float(L["dbh"] or 0)):
            dbh_ok += 1
    except Exception:
        pass
    dm = dist_m(A["Latitude"], A["Longitude"], L["lat"], L["lon"])
    if dm is not None:
        dists.append(dm)
        if dm > 10:
            far.append((t, round(dm), A["Address"], L["addr"]))

n = len(both)
print(f"\n--- attribute agreement over {n:,} ids present in BOTH")
print(f"address identical           {exact_addr:6d}  {exact_addr/n:7.2%}")
print(f"address same street+number  {loose_addr:6d}  {loose_addr/n:7.2%}")
print(f"botanical name agrees       {sp_exact:6d}  {sp_exact/n:7.2%}")
print(f"SiteOrder agrees            {so_ok:6d}  {so_ok/n:7.2%}")
print(f"DBH agrees exactly          {dbh_ok:6d}  {dbh_ok/n:7.2%}")
d = sorted(dists)
print(f"coords: n={len(d)} median {d[len(d)//2]:.3f}m  p95 {d[int(len(d)*.95)]:.2f}m  "
      f"p99 {d[int(len(d)*.99)]:.2f}m  max {d[-1]:.0f}m")
for thr in (1, 3, 10, 50):
    print(f"   within {thr:3d} m: {sum(1 for x in d if x <= thr)/len(d):7.3%}")
print(f"beyond 10 m: {len(far)} ({len(far)/len(d):.3%})")
for x in far[:12]:
    print("     ", x)
print(f"\nspecies disagreements: {len(sp_bad)}; first 12")
for x in sp_bad[:12]:
    print("     ", x)

print("\n--- ArcGIS-only ids in windows: character")
print("   above DataSF max id (276035):", sum(1 for t in only_arc if t > 276035))
print("   DBH counter:", Counter(a for a in (arc[t]["DBH"] for t in only_arc)).most_common(6))
print("   Prune_Status:", Counter(arc[t]["Prune_Status"] for t in only_arc).most_common())
print("   bos blank:", sum(1 for t in only_arc if not arc[t]["bos"]))
print("   first 12:", [(t, arc[t]["Address"], arc[t]["BOTANICAL"]) for t in only_arc[:12]])

print("\n--- DataSF-only ids in windows: character")
print("   legal:", Counter(local[str(t)]["legal"] for t in only_loc).most_common())
print("   caretaker:", Counter(local[str(t)]["care"] for t in only_loc).most_common(8))
print("   dbh==0 or blank:", sum(1 for t in only_loc
                                 if not local[str(t)]["dbh"] or float(local[str(t)]["dbh"] or 0) == 0))
dpw_only = [t for t in only_loc if local[str(t)]["legal"] == "DPW Maintained"]
print(f"   of the DPW-Maintained absentees ({len(dpw_only)}):")
print("      caretaker:", Counter(local[str(t)]["care"] for t in dpw_only).most_common(6))
print("      site:", Counter(local[str(t)]["site"] for t in dpw_only).most_common(6))
print("      dbh 0/blank:", sum(1 for t in dpw_only
                                if not local[str(t)]["dbh"] or float(local[str(t)]["dbh"] or 0) == 0))
