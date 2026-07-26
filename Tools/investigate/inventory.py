# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
import sys
sys.path.insert(0, "Tools/investigate")
from arc import q, count

print("total", count("1=1"))
d = q(where="1=1", outStatistics='[{"statisticType":"count","onStatisticField":"TREEID","outStatisticFieldName":"c"}]',
      returnDistinctValues="true")
# distinct TREEID count via groupBy is expensive; instead compare count of duplicates by sampling later.

for fld in ("Prune_Status", "PlantType", "bos"):
    d = q(where="1=1", outFields=fld, groupByFieldsForStatistics=fld,
          outStatistics='[{"statisticType":"count","onStatisticField":"OBJECTID","outStatisticFieldName":"c"}]',
          resultRecordCount=200)
    print("---", fld)
    for f in sorted(d["features"], key=lambda x: -x["attributes"]["c"]):
        print("   ", repr(f["attributes"][fld]), f["attributes"]["c"])

print("--- Prune_Year top values")
d = q(where="1=1", outFields="Prune_Year", groupByFieldsForStatistics="Prune_Year",
      outStatistics='[{"statisticType":"count","onStatisticField":"OBJECTID","outStatisticFieldName":"c"}]',
      resultRecordCount=400)
vals = sorted(d["features"], key=lambda x: -x["attributes"]["c"])
print("   distinct:", len(vals))
for f in vals[:25]:
    print("   ", repr(f["attributes"]["Prune_Year"]), f["attributes"]["c"])
