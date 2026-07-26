# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# Uniform random sample of DataSF rows checked against the city's ArcGIS layer,
# plus a few whole-layer counts.
import json, math, random, sys
from collections import Counter
sys.path.insert(0, "Tools/investigate")
from arc import rows, count

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))
random.seed(999)
s = random.sample(sorted(local), 6000)

hit = set()
for i in range(0, len(s), 250):
    chunk = s[i:i + 250]
    for a in rows("TREEID IN (" + ",".join(chunk) + ")", out="TREEID"):
        hit.add(str(a["TREEID"]))
    if i % 1500 == 0:
        print(f"  {i}", flush=True)

p = len(hit) / len(s)
se = math.sqrt(p * (1 - p) / len(s))
print(f"DataSF rows present in ArcGIS: {len(hit)}/{len(s)} = {p:.3%} +/- {1.96*se:.3%}")
print(f"=> intersection approx {p*198435:,.0f} (95% CI {(p-1.96*se)*198435:,.0f} - {(p+1.96*se)*198435:,.0f})")
print(f"=> DataSF-only approx {(1-p)*198435:,.0f}")

miss = [t for t in s if t not in hit]
print("\nmissing-from-ArcGIS DataSF rows, by legal status:")
for k, v in Counter(local[t]["legal"] for t in miss).most_common():
    print(f"   {k!r:34} {v}")
dpw = [t for t in miss if local[t]["legal"] == "DPW Maintained"]
print(f"\nDPW-Maintained absentees ({len(dpw)} of sample):")
print("   caretaker:", Counter(local[t]["care"] for t in dpw).most_common(6))
print("   dbh 0/blank:", sum(1 for t in dpw if not local[t]["dbh"] or float(local[t]["dbh"] or 0) == 0))
print("   site:", Counter(local[t]["site"] for t in dpw).most_common(5))

print("\nwhole-layer counts on the city's service:")
for w, lbl in [("BOTANICAL = 'Potential Site'", "BOTANICAL = 'Potential Site'"),
               ("BOTANICAL IS NULL", "BOTANICAL null"),
               ("DBH = 0", "DBH = 0"),
               ("DBH IS NULL", "DBH null"),
               ("Address IS NULL OR Address = ''", "Address blank")]:
    print(f"   {lbl:30} {count(w)}")
