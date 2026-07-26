# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
import json, random, sys
from collections import Counter, defaultdict
sys.path.insert(0, "Tools/investigate")
from arc import rows, count

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))

print("=== the 1,338 TREEIDs above the DataSF ceiling (276035)")
hi = rows("TREEID > 276035")
print("   rows", len(hi))
print("   DBH:", Counter(a["DBH"] for a in hi).most_common(10))
print("   DBH >= 12 (mature):", sum(1 for a in hi if (a["DBH"] or 0) >= 12))
print("   Prune_Status:", Counter(a["Prune_Status"] for a in hi).most_common())
print("   bos:", Counter(a["bos"] for a in hi).most_common())
print("   top addresses:", Counter(a["Address"] for a in hi).most_common(8))
print("   distinct addresses:", len({a["Address"] for a in hi}))
print("   'Potential Site' rows:", sum(1 for a in hi if a["BOTANICAL"] == "Potential Site"))
print("   top species:", Counter(a["BOTANICAL"] for a in hi).most_common(6))

print("\n=== presence in ArcGIS by DataSF qCaretaker (does the city layer carry park trees?)")
by = defaultdict(list)
for k, v in local.items():
    by[v["care"] or "(blank)"].append(k)
random.seed(11)
for k, v in sorted(by.items(), key=lambda x: -len(x[1]))[:12]:
    s = random.sample(v, min(300, len(v)))
    h = set()
    for i in range(0, len(s), 250):
        for a in rows("TREEID IN (" + ",".join(s[i:i + 250]) + ")", out="TREEID"):
            h.add(str(a["TREEID"]))
    print(f"   {k!r:26} n={len(s):4d} present {len(h)/len(s):7.2%}  (pop {len(v)})", flush=True)

print("\n=== species-disagreement triage over a fresh window sample")
random.seed(5150)
starts = random.sample(range(1, 277000), 30)
same_genus = diff_genus = agree = 0
examples = []
for s in starts:
    for a in rows(f"TREEID >= {s} AND TREEID < {s+400}"):
        L = local.get(str(a["TREEID"]))
        if not L:
            continue
        bot = " ".join((a["BOTANICAL"] or "").upper().split())
        lbot = " ".join((L["species"] or "").upper().split()).split("::")[0].strip()
        if not bot or not lbot:
            continue
        if bot == lbot or bot in lbot or lbot in bot:
            agree += 1
        elif bot.split()[0] == lbot.split()[0]:
            same_genus += 1
        else:
            diff_genus += 1
            if len(examples) < 10:
                examples.append((a["TREEID"], a["Address"], bot, lbot))
tot = agree + same_genus + diff_genus
print(f"   compared {tot}: agree {agree} ({agree/tot:.2%}), "
      f"same genus different epithet/cultivar {same_genus} ({same_genus/tot:.2%}), "
      f"different genus {diff_genus} ({diff_genus/tot:.2%})")
for e in examples:
    print("     ", e)
