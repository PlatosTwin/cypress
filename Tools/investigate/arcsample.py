# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
# Uniform random sample of the city's ArcGIS records (by OBJECTID), checked for
# membership in the local DataSF tkzw-k3nq snapshot. This is the unbiased estimator
# for "how many city trees are missing from the open-data export".
import json, math, random, sys
from collections import Counter
sys.path.insert(0, "Tools/investigate")
from arc import q, rows, count

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))

d = q(where="1=1", outStatistics='[{"statisticType":"min","onStatisticField":"OBJECTID","outStatisticFieldName":"mn"},'
                                 '{"statisticType":"max","onStatisticField":"OBJECTID","outStatisticFieldName":"mx"}]')
mn, mx = d["features"][0]["attributes"]["mn"], d["features"][0]["attributes"]["mx"]
print("OBJECTID range", mn, mx, "count", count("1=1"), "-> contiguous:", mx - mn + 1 == 133577)

random.seed(4242)
ids = sorted(random.sample(range(mn, mx + 1), 4000))
got = []
for i in range(0, len(ids), 400):
    chunk = ids[i:i + 400]
    got += rows("OBJECTID IN (" + ",".join(map(str, chunk)) + ")")
    print(f"  fetched {len(got)}", flush=True)

print("sampled arcgis records:", len(got))
inloc = [a for a in got if str(a["TREEID"]) in local]
outloc = [a for a in got if str(a["TREEID"]) not in local]
p = len(outloc) / len(got)
se = math.sqrt(p * (1 - p) / len(got))
print(f"not in DataSF: {len(outloc)}/{len(got)} = {p:.3%}  (+/- {1.96*se:.3%} 95% CI)")
print(f"=> approx {p*133577:,.0f} of 133,577 city records absent from tkzw-k3nq "
      f"(95% CI {max(0,(p-1.96*se))*133577:,.0f} - {(p+1.96*se)*133577:,.0f})")
print(f"=> intersection approx {(1-p)*133577:,.0f}")

print("\ncharacter of the ArcGIS-only records:")
print("   TREEID > 276035 (above DataSF max):", sum(1 for a in outloc if a["TREEID"] > 276035))
print("   Prune_Status:", Counter(a["Prune_Status"] for a in outloc).most_common())
print("   DBH:", Counter(a["DBH"] for a in outloc).most_common(8))
print("   bos:", Counter(a["bos"] for a in outloc).most_common(5))
print("   botanical blank:", sum(1 for a in outloc if not a["BOTANICAL"]))
for a in outloc[:20]:
    print("     ", a["TREEID"], a["Address"], "|", a["BOTANICAL"], "| DBH", a["DBH"], "|", a["Prune_Year"])

# Where does 276198 sit? Confirm the above-max block.
print("\nTREEID > 276035 in the whole layer:", count("TREEID > 276035"))
hi = rows("TREEID > 276035", out="TREEID,Address,BOTANICAL,DBH,Prune_Year,bos")
print("   sample of that block:", [(a["TREEID"], a["Address"]) for a in hi[:8]])
print("   how many of that block are in DataSF:",
      sum(1 for a in hi if str(a["TREEID"]) in local), "of", len(hi))
json.dump(got, open(SCRATCH + "/arcsample.json", "w"))
