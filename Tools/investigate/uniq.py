# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
import sys
sys.path.insert(0, "Tools/investigate")
from arc import q, count

# Does the service let us ask for duplicate TREEIDs directly?
try:
    d = q(where="1=1", groupByFieldsForStatistics="TREEID",
          outStatistics='[{"statisticType":"count","onStatisticField":"OBJECTID","outStatisticFieldName":"c"}]',
          having="COUNT(OBJECTID) > 1", returnCountOnly="true")
    print("TREEIDs appearing more than once:", d)
except Exception as e:
    print("having/returnCountOnly not supported:", e)

try:
    d = q(where="1=1", groupByFieldsForStatistics="TREEID",
          outStatistics='[{"statisticType":"count","onStatisticField":"OBJECTID","outStatisticFieldName":"c"}]',
          having="COUNT(OBJECTID) > 1", outFields="TREEID", resultRecordCount=50)
    fs = d.get("features", [])
    print("sample duplicate TREEIDs:", [(f["attributes"]["TREEID"], f["attributes"]["c"]) for f in fs[:20]])
    print("returned", len(fs))
except Exception as e:
    print("having listing failed:", e)

# Exact distinct count, if supported.
try:
    d = q(where="1=1",
          outStatistics='[{"statisticType":"count","onStatisticField":"TREEID","outStatisticFieldName":"c"}]',
          returnDistinctValues="true")
    print("distinct-count attempt:", d.get("features"))
except Exception as e:
    print("distinct count failed:", e)

print("null TREEID rows:", count("TREEID IS NULL"))
print("TREEID > 276035 (above local DataSF max):", count("TREEID > 276035"))
print("TREEID <= 276035:", count("TREEID <= 276035"))
