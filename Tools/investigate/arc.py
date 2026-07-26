# THROWAWAY investigation helper -- supports docs/investigations/city-tree-source.md.
# Read-only queries against the public SF Public Works BUF_Street_Trees feature service.
import json, time, urllib.parse, urllib.request

LAYER = ("https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/"
         "BUF_Street_Trees/FeatureServer/3/query")


def q(**params):
    params.setdefault("f", "json")
    body = urllib.parse.urlencode(params).encode()
    for attempt in range(4):
        try:
            req = urllib.request.Request(LAYER, data=body)
            with urllib.request.urlopen(req, timeout=90) as r:
                d = json.load(r)
            if "error" in d:
                raise RuntimeError(d["error"])
            return d
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def count(where):
    return q(where=where, returnCountOnly="true")["count"]


def rows(where, out="*", geom="false", **kw):
    d = q(where=where, outFields=out, returnGeometry=geom, **kw)
    return [f["attributes"] for f in d.get("features", [])]
