#!/usr/bin/env python3
"""Generate refined Cypress badge-logo candidates (direction B).

Branches are tapered polygons computed by offsetting a cubic-Bezier
centerline; every limb's base sits ON the trunk centerline and its tip
ends INSIDE a foliage pad, so nothing can float or misconnect.
Foliage pads are unions of overlapping ellipses (same fill -> one
organic silhouette mass). Deterministic (no random)."""

import math

# ---------- palette ----------
DEEP = "#1d4634"
MID = "#2f6b4f"
LIGHT = "#4e8f6a"
BARK = "#7a4f33"
BARK_D = "#5e3b26"
ROCK = "#97a695"
FOG = "#e3ebd9"
PAPER = "#eef2e7"

# ---------- bezier helpers ----------

def bez(p0, p1, p2, p3, t):
    mt = 1 - t
    return (mt**3*p0[0] + 3*mt*mt*t*p1[0] + 3*mt*t*t*p2[0] + t**3*p3[0],
            mt**3*p0[1] + 3*mt*mt*t*p1[1] + 3*mt*t*t*p2[1] + t**3*p3[1])

def bez_d(p0, p1, p2, p3, t):
    mt = 1 - t
    return (3*mt*mt*(p1[0]-p0[0]) + 6*mt*t*(p2[0]-p1[0]) + 3*t*t*(p3[0]-p2[0]),
            3*mt*mt*(p1[1]-p0[1]) + 6*mt*t*(p2[1]-p1[1]) + 3*t*t*(p3[1]-p2[1]))

class Branch:
    """Tapered branch along a cubic bezier centerline."""
    def __init__(self, p0, p1, p2, p3, w0, w1, flare=0.0):
        self.pts = (p0, p1, p2, p3)
        self.w0, self.w1, self.flare = w0, w1, flare

    def point(self, t):
        return bez(*self.pts, t)

    def width(self, t):
        w = self.w0 + (self.w1 - self.w0) * (t ** 0.85)
        if self.flare:  # root flare near the base
            w += self.flare * max(0.0, (1 - t*5)) ** 1.6
        return w

    def path(self, samples=28):
        left, right = [], []
        for i in range(samples + 1):
            t = i / samples
            x, y = bez(*self.pts, t)
            dx, dy = bez_d(*self.pts, t)
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L, dx / L
            hw = self.width(t) / 2
            left.append((x + nx*hw, y + ny*hw))
            right.append((x - nx*hw, y - ny*hw))
        pts = left + right[::-1]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
        # round caps at both ends
        bx, by = self.point(0); tx, ty = self.point(1)
        caps = (f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="{self.width(0)/2:.1f}"/>'
                f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="{self.width(1)/2:.1f}"/>')
        return f'<path d="{d}"/>' + caps


def det(i, seed):
    """Deterministic jitter in [-1, 1]."""
    return math.sin(i * 12.9898 + seed * 78.233) % 1 * 2 - 1


def pad_ellipses(cx, cy, w, h, seed=1):
    """A foliage pad: one main row + a raised top row of ellipses.
    Returns list of (cx, cy, rx, ry). Bottoms roughly aligned -> flat
    underside, domed billowy top: the Monterey cypress lens shape."""
    out = []
    n = max(3, round(w / 30))
    span = w - w / n            # centers span
    step = span / (n - 1) if n > 1 else 0
    for i in range(n):
        ex = cx - span/2 + i*step + det(i, seed) * step * 0.12
        ry = h * (0.52 + 0.10 * det(i + 7, seed))
        rx = step * 0.72 + w / n * 0.35
        ey = cy + (h*0.45 - ry)      # align bottoms near cy + h*0.45
        out.append((ex, ey, rx, ry))
    m = n - 1
    if m >= 1:
        for i in range(m):
            ex = cx - span/2 + (i + 0.5)*step + det(i + 3, seed) * step * 0.10
            rx = step * 0.62
            ry = h * (0.42 + 0.08 * det(i + 11, seed))
            ey = cy - h * 0.28
            # taper the top row toward the pad ends
            edge = abs((i + 0.5) - m/2) / (m/2 or 1)
            ry *= (1 - 0.25 * edge)
            out.append((ex, ey, rx, ry))
    return out


def ellipses_svg(ells, fill):
    return "".join(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"/>'
                   for x, y, rx, ry in ells)


def poly(points, fill, opacity=None):
    d = "M" + " L".join(f"{x} {y}" for x, y in points) + " Z"
    op = f' opacity="{opacity}"' if opacity else ""
    return f'<path d="{d}" fill="{fill}"{op}/>'


def birds(spots, color):
    out = []
    for x, y, s in spots:
        out.append(f'<path d="M{x} {y} q {2.2*s} {-1.8*s} {4.4*s} 0 q {2.2*s} {-1.8*s} {4.4*s} 0" '
                   f'fill="none" stroke="{color}" stroke-width="{1.5*s}" stroke-linecap="round"/>')
    return "".join(out)


# ---------- tree assemblies ----------

def tree_sentinel(color=None, duotone=False):
    """Centered, majestic: broad flat crown on a near-upright trunk."""
    trunk = Branch((114, 158), (108, 130), (104, 100), (112, 70), 13.5, 4.8, flare=5)
    limb_l = Branch((106.5, 117), (94, 110), (82, 104), (64, 97), 5.8, 2.2)
    limb_r = Branch((107, 128), (126, 116), (148, 105), (166, 95), 6.2, 2.4)
    root_l = Branch((113, 153), (106, 156), (100, 158), (94, 160), 7, 1.5)
    root_r = Branch((116, 153), (124, 156), (130, 158), (137, 160), 7, 1.5)
    pads = [pad_ellipses(118, 58, 132, 30, seed=2),
            pad_ellipses(170, 96, 64, 21, seed=5),
            pad_ellipses(58, 98, 52, 19, seed=8)]
    if duotone:
        wood = "".join(b.path() for b in (limb_l, limb_r, root_l, root_r, trunk))
        s = f'<g fill="{BARK}">{wood}</g>'
        for p in pads:
            s += ellipses_svg(p, DEEP)
            s += ellipses_svg([(x, y - ry*0.22, rx*0.78, ry*0.78) for x, y, rx, ry in p], MID)
            s += ellipses_svg([(x - rx*0.18, y - ry*0.5, rx*0.4, ry*0.38) for x, y, rx, ry in p], LIGHT)
        return s
    c = color or DEEP
    s = f'<g fill="{c}">'
    s += "".join(b.path() for b in (limb_l, limb_r, root_l, root_r, trunk))
    for p in pads:
        s += ellipses_svg(p, c).replace(f' fill="{c}"', "")
    return s + "</g>"


def tree_windswept(color=None):
    """Leaning trunk, crown streaming leeward (right)."""
    trunk = Branch((88, 154), (90, 124), (100, 96), (126, 74), 12, 4.2, flare=5)
    limb_r = Branch((103.5, 104), (126, 96), (150, 92), (172, 92), 5.5, 2.2)
    limb_t = Branch((97, 114), (86, 108), (76, 103), (66, 99), 4.5, 2.0)
    root_l = Branch((87, 149), (80, 152), (74, 154), (68, 156), 6.5, 1.5)
    root_r = Branch((90, 149), (98, 152), (104, 154), (111, 156), 6.5, 1.5)
    pads = [pad_ellipses(150, 60, 120, 28, seed=3),
            pad_ellipses(180, 94, 58, 19, seed=6),
            pad_ellipses(62, 97, 38, 15, seed=9)]
    c = color or DEEP
    s = f'<g fill="{c}">'
    s += "".join(b.path() for b in (limb_r, limb_t, root_l, root_r, trunk))
    for p in pads:
        s += ellipses_svg(p, c).replace(f' fill="{c}"', "")
    return s + "</g>"


def tree_grove(color=None):
    """Bold close crop: one huge flat canopy, heavy trunk."""
    trunk = Branch((116, 180), (112, 152), (110, 124), (118, 96), 16, 6, flare=7)
    limb_l = Branch((111, 136), (96, 128), (82, 121), (68, 114), 7, 2.6)
    limb_r = Branch((112.5, 126), (132, 119), (152, 114), (168, 110), 7, 2.6)
    root_l = Branch((115, 174), (106, 178), (99, 180), (91, 183), 9, 1.8)
    root_r = Branch((119, 174), (128, 178), (135, 180), (143, 183), 9, 1.8)
    pads = [pad_ellipses(120, 70, 124, 32, seed=4),
            pad_ellipses(64, 110, 54, 19, seed=7),
            pad_ellipses(174, 107, 52, 18, seed=10)]
    c = color or DEEP
    s = f'<g fill="{c}">'
    s += "".join(b.path() for b in (limb_l, limb_r, root_l, root_r, trunk))
    for p in pads:
        s += ellipses_svg(p, c).replace(f' fill="{c}"', "")
    return s + "</g>"


# ---------- badge scaffolding ----------

def badge(inner, rid, ring=True, fill=PAPER, ring_color=DEEP):
    s = f'<clipPath id="{rid}"><circle cx="120" cy="120" r="98"/></clipPath>'
    s += f'<circle cx="120" cy="120" r="98" fill="{fill}"/>'
    s += f'<g clip-path="url(#{rid})">{inner}</g>'
    if ring:
        s += (f'<circle cx="120" cy="120" r="98" fill="none" stroke="{ring_color}" stroke-width="3.5"/>'
              f'<circle cx="120" cy="120" r="90" fill="none" stroke="{ring_color}" stroke-width="1" opacity="0.35"/>')
    return s


def sea(y, x0, x1, color, op):
    return f'<rect x="{x0}" y="{y}" width="{x1-x0}" height="2" fill="{color}" opacity="{op}" rx="1"/>'


def headland(points, color):
    return poly(points, color)


# ---------- variants ----------

def v_sentinel():
    inner = sea(168, 26, 214, DEEP, .45) + sea(175, 140, 206, DEEP, .28) + sea(175, 34, 86, DEEP, .28)
    inner += headland([(34, 222), (38, 206), (64, 194), (92, 178), (110, 164), (122, 158),
                       (138, 162), (158, 172), (184, 190), (202, 204), (206, 222)], DEEP)
    inner += tree_sentinel()
    return badge(inner, "cA")


HEADLAND_PTS = [(18, 222), (18, 178), (44, 172), (68, 160), (86, 152), (102, 154),
                (114, 162), (124, 174), (132, 190), (138, 206), (142, 222)]

def v_headland():
    inner = sea(180, 152, 212, DEEP, .40) + sea(187, 164, 204, DEEP, .25)
    inner += headland(HEADLAND_PTS, DEEP)
    inner += birds([(160, 130, 1.0), (174, 122, 0.8)], DEEP)
    inner += tree_windswept()
    return badge(inner, "cB")


def v_grove():
    ledge = Branch((66, 186), (100, 181), (140, 181), (174, 186), 4.5, 4.5)
    inner = f'<g fill="{DEEP}">{ledge.path()}</g>'
    inner += tree_grove()
    return badge(inner, "cC")


def v_fogmoon():
    inner = f'<circle cx="164" cy="96" r="46" fill="{FOG}"/>'
    inner += sea(180, 152, 212, DEEP, .40) + sea(187, 164, 204, DEEP, .25)
    inner += headland(HEADLAND_PTS, DEEP)
    inner += tree_windswept()
    return badge(inner, "cD")


def v_duotone():
    inner = f'<circle cx="126" cy="80" r="54" fill="{FOG}"/>'
    inner += sea(168, 26, 214, "#6e8172", .55) + sea(175, 140, 206, "#6e8172", .35) + sea(175, 34, 86, "#6e8172", .35)
    inner += headland([(34, 222), (38, 206), (64, 194), (92, 178), (110, 164), (122, 158),
                       (138, 162), (158, 172), (184, 190), (202, 204), (206, 222)], ROCK)
    inner += headland([(70, 192), (98, 176), (116, 164), (134, 168), (112, 178), (90, 190)], "#7d8f80")
    inner += tree_sentinel(duotone=True)
    return badge(inner, "cE")


VARIANTS = [
    ("B1", "Sentinel", v_sentinel,
     "The seal, rebuilt: upright trunk with root flare gripping the point, three-pad crown, sea on both sides. Calm, institutional, timeless."),
    ("B2", "Headland", v_headland,
     "Asymmetric composition: the cypress leans off its headland over open water, crown streaming leeward, two gulls for scale. The most alive."),
    ("B3", "Grove", v_grove,
     "Tight crop, heavy trunk, one great umbrella canopy on a simple ledge — no scenery, just the tree. Boldest at small sizes."),
    ("B4", "Fog Moon", v_fogmoon,
     "Headland composition with the pale coastal fog disc behind the crown — the one two-tone note in an otherwise single-ink mark."),
    ("B5", "Duotone", v_duotone,
     "Sentinel geometry in the full identity palette — bark trunk, three-green crown, granite point — for wherever color is welcome."),
]

# ---------- page ----------

CSS = """
:root{--bg:#edf1e8;--card:#ffffff;--ink:#1c2a21;--muted:#5c6b60;--line:#d7ded0;--accent:#2f6b4f;--stage:#f6f8f2;--dark:#0f1a14;
--display:'Iowan Old Style','Palatino Nova',Palatino,'Book Antiqua',Georgia,serif;
--body:'Seravek','Avenir Next','Gill Sans','Trebuchet MS',system-ui,sans-serif;
--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace;}
@media (prefers-color-scheme: dark){:root{--bg:#0e1712;--card:#18251d;--ink:#e4ebe2;--muted:#94a496;--line:#27352b;--accent:#6fae8c;--stage:#141f18;}}
:root[data-theme="dark"]{--bg:#0e1712;--card:#18251d;--ink:#e4ebe2;--muted:#94a496;--line:#27352b;--accent:#6fae8c;--stage:#141f18;}
:root[data-theme="light"]{--bg:#edf1e8;--card:#ffffff;--ink:#1c2a21;--muted:#5c6b60;--line:#d7ded0;--accent:#2f6b4f;--stage:#f6f8f2;}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--ink);font-family:var(--body);margin:0;line-height:1.5;}
.wrap{max-width:1060px;margin:0 auto;padding:40px 24px 80px;}
h1{font-family:var(--display);font-weight:600;font-size:clamp(1.7rem,3.5vw,2.3rem);margin:.3em 0 .15em;text-wrap:balance;}
.kicker{font-family:var(--mono);font-size:.72rem;letter-spacing:.14em;text-transform:uppercase;color:var(--accent);}
p.lede{max-width:62ch;color:var(--muted);margin:.2em 0 0;}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(440px,1fr));gap:24px;margin-top:32px;}
@media (max-width:520px){.grid{grid-template-columns:1fr}}
.cand{background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden;display:flex;flex-direction:column;}
.stage{background:radial-gradient(110% 85% at 50% 20%,var(--stage) 0%,var(--card) 75%);display:flex;align-items:center;justify-content:center;padding:26px 20px 14px;}
.meta{padding:16px 22px 18px;border-top:1px solid var(--line);}
.meta .nm{font-family:var(--display);font-size:1.25rem;font-weight:600;}
.meta .nm span{font-family:var(--mono);font-size:.7rem;color:var(--accent);letter-spacing:.1em;margin-right:8px;vertical-align:2px;}
.meta p{font-size:.86rem;color:var(--muted);margin:.35em 0 .8em;}
.sizes{display:flex;align-items:center;gap:14px;}
.sizes .lab{font-family:var(--mono);font-size:.64rem;color:var(--muted);letter-spacing:.08em;text-transform:uppercase;margin-right:2px;}
.chipbox{display:flex;align-items:center;justify-content:center;border:1px solid var(--line);border-radius:10px;background:var(--card);}
.chipbox.dark{background:var(--dark);border-color:#243026;}
.s64{width:72px;height:68px}.s32{width:44px;height:42px}
footer{margin-top:56px;padding-top:18px;border-top:1px solid var(--line);font-size:.82rem;color:var(--muted);}
"""

def card(vid, name, fn, blurb):
    mark = fn()
    sym = f'<symbol id="m{vid}" viewBox="0 0 240 240">{mark}</symbol>'
    return sym, f"""
<div class="cand">
  <div class="stage"><svg width="290" height="290" viewBox="0 0 240 240"><use href="#m{vid}"/></svg></div>
  <div class="meta">
    <div class="nm"><span>{vid}</span>{name}</div>
    <p>{blurb}</p>
    <div class="sizes"><span class="lab">Scale</span>
      <div class="chipbox s64"><svg width="56" height="56" viewBox="0 0 240 240"><use href="#m{vid}"/></svg></div>
      <div class="chipbox s32"><svg width="30" height="30" viewBox="0 0 240 240"><use href="#m{vid}"/></svg></div>
      <div class="chipbox dark s64"><svg width="56" height="56" viewBox="0 0 240 240"><use href="#m{vid}"/></svg></div>
    </div>
  </div>
</div>"""


def main():
    syms, cards = [], []
    for vid, name, fn, blurb in VARIANTS:
        s, c = card(vid, name, fn, blurb)
        syms.append(s); cards.append(c)
    html = f"""<title>Cypress — Logo, direction B refined</title>
<style>{CSS}</style>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>{''.join(syms)}</defs></svg>
<div class="wrap">
  <div class="kicker">Cypress · logo — direction B, refined</div>
  <h1>The Lone Cypress badge, five ways</h1>
  <p class="lede">Geometry is now generated, not hand-drawn: every limb's base sits on the trunk's centerline and every tip ends inside the crown, with continuous taper from root flare to leader. Same badge language, five compositions.</p>
  <div class="grid">{''.join(cards)}</div>
  <footer>Single ink: Cypress Deep #1D4634 on paper #EEF2E7 · B5 uses the full identity palette. The chosen mark replaces the logo across the identity page and app mocks.</footer>
</div>"""
    out = "/Users/nikitabogdanov/PycharmProjects/cypress/mocks/logo-candidates.html"
    with open(out, "w") as f:
        f.write(html)
    print(f"wrote {out} ({len(html)} bytes)")


if __name__ == "__main__":
    main()
