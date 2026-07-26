# THROWAWAY investigation script -- supports docs/investigations/city-tree-source.md.
import json, math, random, sys
from collections import Counter
sys.path.insert(0, "Tools/investigate")
from arc import rows

SCRATCH = ("/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/"
           "0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad")
local = json.load(open(SCRATCH + "/local.json"))
random.seed(5150)
starts = random.sample(range(1, 277000), 30)


def dist_m(a, b, c, d):
    try:
        a, b, c, d = float(a), float(b), float(c), float(d)
    except Exception:
        return None
    return math.hypot((a - c) * 111320, (b - d) * 111320 * math.cos(math.radians(a)))


agree_addr = disagree_addr = 0
near = 0
n = 0
rows_far = []
for s in starts:
    for a in rows(f"TREEID >= {s} AND TREEID < {s+400}"):
        L = local.get(str(a["TREEID"]))
        if not L:
            continue
        bot = " ".join((a["BOTANICAL"] or "").upper().split())
        lbot = " ".join((L["species"] or "").upper().split()).split("::")[0].strip()
        if not bot or not lbot:
            continue
        if bot == lbot or bot in lbot or lbot in bot or bot.split()[0] == lbot.split()[0]:
            continue
        n += 1
        la = " ".join((a["Address"] or "").upper().split())
        ll = " ".join((L["addr"] or "").upper().split())
        if la == ll or la.split()[1:] == ll.split()[1:]:
            agree_addr += 1
        else:
            disagree_addr += 1
        dm = dist_m(a["Latitude"], a["Longitude"], L["lat"], L["lon"])
        if dm is not None and dm <= 3:
            near += 1
        elif dm is not None:
            rows_far.append((a["TREEID"], round(dm), a["Address"], L["addr"]))

print(f"genus-level species disagreements examined: {n}")
print(f"   address still agrees (same street, same/near number): {agree_addr} ({agree_addr/n:.1%})")
print(f"   address disagrees:                                    {disagree_addr} ({disagree_addr/n:.1%})")
print(f"   coordinates within 3 m:                               {near} ({near/n:.1%})")
print("   coordinate outliers among them (first 10):")
for x in rows_far[:10]:
    print("     ", x)
