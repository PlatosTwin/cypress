#!/usr/bin/env python3
"""Cypress logo, direction B5 — metaball-contour renderer.

Foliage and rock are scalar fields (sums of disc potentials); their
silhouettes are extracted as smooth iso-contours via marching squares
and Chaikin smoothing. Mid/light tones are higher-threshold contours of
the same field shifted toward the light — organic painterly layers, not
stacked ellipses. Branches remain tapered offset polygons whose bases
sit on the trunk centerline and whose tips end inside the field, so
nothing can disconnect."""

import os
import math

DEEP, MID, LIGHT = "#1d4634", "#2f6b4f", "#4e8f6a"
BARK, BARK_D = "#7a4f33", "#5e3b26"
ROCK, ROCK_D = "#97a695", "#7d8f80"
FOG, PAPER = "#e3ebd9", "#eef2e7"
SEA = "#6e8172"

# ---------------- bezier branch (tapered offset polygon) ----------------

def bez(p0, p1, p2, p3, t):
    mt = 1 - t
    return (mt**3*p0[0] + 3*mt*mt*t*p1[0] + 3*mt*t*t*p2[0] + t**3*p3[0],
            mt**3*p0[1] + 3*mt*mt*t*p1[1] + 3*mt*t*t*p2[1] + t**3*p3[1])

def bez_d(p0, p1, p2, p3, t):
    mt = 1 - t
    return (3*mt*mt*(p1[0]-p0[0]) + 6*mt*t*(p2[0]-p1[0]) + 3*t*t*(p3[0]-p2[0]),
            3*mt*mt*(p1[1]-p0[1]) + 6*mt*t*(p2[1]-p1[1]) + 3*t*t*(p3[1]-p2[1]))

class Branch:
    def __init__(self, p0, p1, p2, p3, w0, w1, flare=0.0):
        self.pts = (p0, p1, p2, p3)
        self.w0, self.w1, self.flare = w0, w1, flare
        self._sample()

    def width(self, t):
        w = self.w0 + (self.w1 - self.w0) * (t ** 0.85)
        if self.flare:
            w += self.flare * max(0.0, (1 - t*5)) ** 1.6
        return w

    def _sample(self, n=30):
        self.left, self.right, self.center = [], [], []
        for i in range(n + 1):
            t = i / n
            x, y = bez(*self.pts, t)
            dx, dy = bez_d(*self.pts, t)
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L, dx / L
            hw = self.width(t) / 2
            self.center.append((x, y))
            self.left.append((x + nx*hw, y + ny*hw))
            self.right.append((x - nx*hw, y - ny*hw))

    def path(self):
        pts = self.left + self.right[::-1]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
        bx, by = self.center[0]; tx, ty = self.center[-1]
        return (f'<path d="{d}"/>'
                f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="{self.width(0)/2:.1f}"/>'
                f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="{self.width(1)/2:.1f}"/>')

    def edge(self, inset=1.4, lo=0.12, hi=0.9):
        """Polyline along the right edge, inset inward — bark shading line."""
        n = len(self.right) - 1
        pts = []
        for i, (rx, ry) in enumerate(self.right):
            t = i / n
            if t < lo or t > hi:
                continue
            cx, cy = self.center[i]
            L = math.hypot(rx - cx, ry - cy) or 1.0
            ux, uy = (cx - rx) / L, (cy - ry) / L
            pts.append((rx + ux*inset, ry + uy*inset))
        return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)

# ---------------- metaball contour extraction ----------------

def field_contours(discs, T=1.0, h=1.1, shift=(0.0, 0.0), min_area=30.0,
                   neg=None, smooth_iters=2, keep_pts=110):
    sx, sy = shift
    neg = neg or []

    def f(px, py):
        s = 0.0
        for x, y, r in discs:
            dx = px - (x + sx); dy = py - (y + sy)
            s += r * r / (dx*dx + dy*dy + 1e-6)
        for x, y, r in neg:
            dx = px - (x + sx); dy = py - (y + sy)
            s -= r * r / (dx*dx + dy*dy + 1e-6)
        return s - T

    # grow the sampling window until the whole boundary is outside the
    # contour (metaball fields sum and decay slowly, so a fixed pad can
    # leave the field above threshold at the border -> open chains)
    pad = 12.0
    for _ in range(6):
        xs0 = min(x - r for x, y, r in discs) - pad
        xs1 = max(x + r for x, y, r in discs) + pad
        ys0 = min(y - r for x, y, r in discs) - pad
        ys1 = max(y + r for x, y, r in discs) + pad
        nx = int((xs1 - xs0) / h) + 2
        ny = int((ys1 - ys0) / h) + 2
        g = [[f(xs0 + i*h, ys0 + j*h) for i in range(nx)] for j in range(ny)]
        border = (g[0] + g[-1] + [row[0] for row in g] + [row[-1] for row in g])
        if max(border) < 0:
            break
        pad *= 1.8

    # Endpoints are identified by their grid EDGE (exact), not by coords.
    coords = {}

    def cross(kind, i, j, pa, pb, va, vb):
        key = (kind, i, j)
        if key not in coords:
            t = va / (va - vb)
            coords[key] = (pa[0] + (pb[0]-pa[0]) * t, pa[1] + (pb[1]-pa[1]) * t)
        return key

    segs = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            x0, y0 = xs0 + i*h, ys0 + j*h
            v00, v10 = g[j][i], g[j][i+1]
            v01, v11 = g[j+1][i], g[j+1][i+1]
            ids = []
            if (v00 > 0) != (v10 > 0):
                ids.append(cross('H', i, j, (x0, y0), (x0+h, y0), v00, v10))
            if (v10 > 0) != (v11 > 0):
                ids.append(cross('V', i+1, j, (x0+h, y0), (x0+h, y0+h), v10, v11))
            if (v01 > 0) != (v11 > 0):
                ids.append(cross('H', i, j+1, (x0, y0+h), (x0+h, y0+h), v01, v11))
            if (v00 > 0) != (v01 > 0):
                ids.append(cross('V', i, j, (x0, y0), (x0, y0+h), v00, v01))
            if len(ids) == 2:
                segs.append((ids[0], ids[1]))
            elif len(ids) == 4:  # ambiguous saddle: pair arbitrarily
                segs.append((ids[0], ids[1])); segs.append((ids[2], ids[3]))

    # chain segments into loops (exact keys -> exact closure)
    adj = {}
    for a, b in segs:
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    loops = []
    seen_edges = set()

    def ekey(a, b):
        return (a, b) if a <= b else (b, a)

    for a, b in segs:
        if ekey(a, b) in seen_edges:
            continue
        loop = [a, b]
        seen_edges.add(ekey(a, b))
        closed = False
        while True:
            cur, prev = loop[-1], loop[-2]
            nxts = [p for p in adj.get(cur, []) if p != prev and ekey(cur, p) not in seen_edges]
            if not nxts:
                break
            loop.append(nxts[0])
            seen_edges.add(ekey(cur, nxts[0]))
            if loop[-1] == loop[0]:
                closed = True
                break
        if closed and len(loop) > 8:
            loops.append([coords[k] for k in loop[:-1]])

    def area(lp):
        s = 0.0
        for i in range(len(lp)):
            x1, y1 = lp[i]; x2, y2 = lp[(i+1) % len(lp)]
            s += x1*y2 - x2*y1
        return abs(s) / 2

    loops = [lp for lp in loops if area(lp) >= min_area]

    def chaikin(lp, it=2):
        for _ in range(it):
            out = []
            for i in range(len(lp)):
                p, q = lp[i], lp[(i+1) % len(lp)]
                out.append((0.75*p[0]+0.25*q[0], 0.75*p[1]+0.25*q[1]))
                out.append((0.25*p[0]+0.75*q[0], 0.25*p[1]+0.75*q[1]))
            lp = out
        return lp

    paths = []
    for lp in loops:
        lp = chaikin(lp, smooth_iters)
        step = max(1, len(lp) // keep_pts)
        lp = lp[::step]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in lp) + " Z"
        paths.append(d)
    return paths


def fill_paths(paths, color, opacity=None):
    op = f' opacity="{opacity}"' if opacity else ""
    return "".join(f'<path d="{d}" fill="{color}"{op}/>' for d in paths)


def canopy(discs, base=DEEP, mid=MID, light=LIGHT, duotone=True):
    """Three organic tone layers from one field."""
    s = fill_paths(field_contours(discs, T=1.0), base)
    if duotone:
        s += fill_paths(field_contours(discs, T=1.5, shift=(-2.0, -3.0), min_area=30), mid)
        s += fill_paths(field_contours(discs, T=2.4, shift=(-3.5, -5.5), min_area=14), light)
    return s

# ---------------- disc placement helpers ----------------

def pad_discs(cx, cy, half_w, r_max, seed=1):
    """A horizontal cypress pad: big discs centre, smaller at the tips,
    slight deterministic undulation."""
    discs = []
    n = max(4, round(half_w / 11))
    for i in range(-n, n + 1):
        u = i / n
        x = cx + u * half_w
        r = r_max * (0.42 + 0.58 * math.sqrt(max(0.02, 1 - u*u)))
        y = cy + 2.2 * math.sin(3.1 * u + seed) + 1.2 * math.sin(7.3 * u + seed*2)
        discs.append((x, y, r))
    # sparse lower lobes give the flat underside a gentle scallop
    for i in range(-(n//2), n//2, 2):
        u = (i + 0.35) / max(1, n//2)
        x = cx + u * half_w * 0.75
        discs.append((x, cy + r_max*0.6, r_max*0.38))
    return discs

# ---------------- the mark ----------------

def sentinel(duotone=True, crown_scale=1.0):
    trunk = Branch((114, 158), (108, 130), (104, 100), (112, 70), 13.5, 4.6, flare=5)
    limb_l = Branch((106.5, 117), (94, 110), (82, 103), (62, 95), 5.8, 2.2)
    limb_r = Branch((107, 128), (126, 116), (148, 104), (168, 93), 6.2, 2.4)
    limb_u = Branch((104.5, 101), (98, 94), (94, 86), (92, 76), 4.5, 2.0)
    root_l = Branch((113, 153), (106, 156), (100, 158), (94, 160), 7, 1.5)
    root_r = Branch((116, 153), (124, 156), (130, 158), (137, 160), 7, 1.5)

    k = crown_scale
    top = pad_discs(118, 54, 52*k, 8.5*k, seed=2)
    top += [(92, 68, 5.5*k), (112, 66, 6*k)]        # under-lobes: leaders enter here
    left = pad_discs(52, 96, 21*k, 7*k, seed=5) + [(60, 95, 5*k)]
    right = pad_discs(176, 93, 24*k, 7.5*k, seed=8) + [(168, 93, 5.5*k)]

    wood_fill = BARK if duotone else DEEP
    wood = f'<g fill="{wood_fill}">' + "".join(
        b.path() for b in (limb_l, limb_r, limb_u, root_l, root_r, trunk)) + "</g>"
    if duotone:
        wood += (f'<path d="{trunk.edge(1.6)}" fill="none" stroke="{BARK_D}" '
                 f'stroke-width="2.2" stroke-linecap="round" opacity=".6"/>')

    crown = (canopy(top, duotone=duotone)
             + canopy(left, duotone=duotone)
             + canopy(right, duotone=duotone))
    return wood + crown


def rock_mound(duotone=True, dx=0, dy=0):
    discs = [(88 + dx, 174 + dy, 9), (106 + dx, 170 + dy, 12), (126 + dx, 170 + dy, 12),
             (146 + dx, 174 + dy, 9), (117 + dx, 176 + dy, 13)]
    base = ROCK if duotone else DEEP
    s = fill_paths(field_contours(discs, T=1.0), base)
    if duotone:
        s += fill_paths(field_contours(discs, T=1.8, shift=(3.5, 3), min_area=25), ROCK_D)
    return s


def sea_lines(color):
    return (f'<rect x="30" y="168" width="180" height="2" rx="1" fill="{color}" opacity=".45"/>'
            f'<rect x="26" y="176" width="44" height="1.8" rx="1" fill="{color}" opacity=".28"/>'
            f'<rect x="172" y="176" width="42" height="1.8" rx="1" fill="{color}" opacity=".28"/>')


def badge(inner, rid):
    return (f'<clipPath id="{rid}"><circle cx="120" cy="120" r="98"/></clipPath>'
            f'<circle cx="120" cy="120" r="98" fill="{PAPER}"/>'
            f'<g clip-path="url(#{rid})">{inner}</g>'
            f'<circle cx="120" cy="120" r="98" fill="none" stroke="{DEEP}" stroke-width="3.5"/>'
            f'<circle cx="120" cy="120" r="90" fill="none" stroke="{DEEP}" stroke-width="1" opacity=".35"/>')


def mark_duotone(crown_scale=1.0, rid="d1"):
    inner = f'<circle cx="126" cy="78" r="54" fill="{FOG}"/>'
    inner += sea_lines(SEA)
    inner += rock_mound(True)
    inner += sentinel(True, crown_scale)
    return badge(inner, rid)


def mark_ink(rid="i1"):
    inner = sea_lines(DEEP) + rock_mound(False) + sentinel(False, crown_scale=1.15)
    return badge(inner, rid)

# ---------------- intricate windswept mark ----------------

def h2(i, seed):
    return (math.sin(i * 127.1 + seed * 311.7) * 43758.5453) % 1.0


def polyline_point(spine, t):
    lens, tot = [], 0.0
    for a, b in zip(spine, spine[1:]):
        L = math.hypot(b[0]-a[0], b[1]-a[1])
        lens.append(L); tot += L
    d = t * tot
    for (a, b), L in zip(zip(spine, spine[1:]), lens):
        if d <= L or (a, b) == (spine[-2], spine[-1]):
            u = 0.0 if L == 0 else min(1.0, d / L)
            px, py = b[0]-a[0], b[1]-a[1]
            n = math.hypot(px, py) or 1.0
            return (a[0] + px*u, a[1] + py*u), (-py/n, px/n)
        d -= L
    a, b = spine[-2], spine[-1]
    px, py = b[0]-a[0], b[1]-a[1]
    n = math.hypot(px, py) or 1.0
    return b, (-py/n, px/n)


def scatter(spine, n, r0, r1, spread, seed, mid_bias=True):
    """Discs strewn along a polyline spine with deterministic jitter —
    ragged, intricate foliage instead of clean lens shapes."""
    out = []
    for i in range(n):
        t = min(1.0, max(0.0, (i + 0.5) / n + (h2(i, seed) - 0.5) * 0.9 / n))
        (x, y), (nx, ny) = polyline_point(spine, t)
        off = (h2(i, seed + 1) - 0.5) * 2 * spread
        r = r0 + (r1 - r0) * (math.sin(math.pi * t) if mid_bias else 1.0)
        r *= 0.7 + 0.6 * h2(i, seed + 2)
        out.append((x + nx*off, y + ny*off, r))
    return out


def grass_tuft(cx, cy, n, height, seed, lean=0.0):
    blades = []
    for i in range(n):
        u = (i / max(1, n - 1) - 0.5) * 2
        hgt = height * (0.55 + 0.5 * h2(i, seed))
        sway = u * 7 + lean * 4 + (h2(i, seed + 3) - 0.5) * 4
        b = Branch((cx + u*6, cy), (cx + u*6 + sway*0.4, cy - hgt*0.5),
                   (cx + u*6 + sway*0.8, cy - hgt*0.85), (cx + u*6 + sway, cy - hgt),
                   1.7, 0.25)
        blades.append(b.path())
    return "".join(blades)


def cypress_intricate(duotone=True):
    # --- wood skeleton: leaning trunk, long bare mid branch, twigs ---
    trunk_lo = Branch((92, 180), (84, 152), (88, 124), (106, 98), 13, 6.5, flare=6)
    leader = Branch((106, 98), (118, 86), (132, 74), (152, 63), 6.5, 2.2)
    limb_left = Branch((99, 109), (86, 104), (74, 100), (58, 97), 4.5, 1.6)
    bare = Branch((97, 118), (120, 117), (148, 118), (180, 117), 4.2, 1.2)
    twig1 = Branch((146, 117.6), (154, 111), (160, 107), (167, 104), 1.7, 0.6)
    twig2 = Branch((158, 118.3), (166, 122), (174, 124), (183, 127), 1.5, 0.5)
    twig3 = Branch((122, 117.2), (128, 111), (132, 107), (137, 104), 1.4, 0.5)
    root_l = Branch((91, 175), (84, 178), (78, 180), (71, 183), 7, 1.2)
    root_r = Branch((94, 175), (102, 178), (108, 180), (115, 183), 7, 1.2)
    wood_main = (trunk_lo, leader, limb_left, bare, twig1, twig2, twig3, root_l, root_r)

    # --- foliage fields: scattered discs + negative gap discs ---
    canopy_spine = [(66, 79), (100, 64), (148, 56), (192, 62)]
    canopy = scatter(canopy_spine, 34, 4.0, 6.2, 4.5, seed=3)
    canopy += scatter(canopy_spine, 64, 1.5, 2.8, 9.0, seed=11, mid_bias=False)
    # notches cut along the underside edge -> clumps separated by sky
    under_spine = [(70, 88), (104, 74), (150, 66), (188, 70)]
    gaps = scatter(under_spine, 14, 2.0, 3.2, 4.5, seed=21, mid_bias=False)
    gaps += scatter([(90, 60), (160, 52)], 6, 1.8, 2.6, 5.0, seed=27, mid_bias=False)

    left_spine = [(40, 105), (70, 93)]
    left_pad = scatter(left_spine, 13, 3.0, 4.8, 3.4, seed=5)
    left_pad += scatter(left_spine, 22, 1.3, 2.3, 7.5, seed=13, mid_bias=False)
    left_gaps = scatter([(48, 102), (68, 96)], 7, 1.6, 2.4, 4.5, seed=23, mid_bias=False)

    tuft_spine = [(178, 116), (194, 111)]
    tuft = [(179, 115, 3.0)] + scatter(tuft_spine, 7, 2.4, 3.8, 2.6, seed=7)
    tuft += scatter(tuft_spine, 8, 1.1, 1.9, 4.2, seed=17, mid_bias=False)

    def foliage(discs, neg):
        base = DEEP
        s = fill_paths(field_contours(discs, T=1.35, h=0.8, neg=neg,
                                      min_area=3, smooth_iters=1, keep_pts=300), base)
        if duotone:
            s += fill_paths(field_contours(discs, T=1.95, h=0.8, neg=neg, shift=(-1.8, -2.6),
                                           min_area=9, smooth_iters=1, keep_pts=220), MID)
            s += fill_paths(field_contours(discs, T=3.0, h=0.8, neg=neg, shift=(-3.2, -5.0),
                                           min_area=6, smooth_iters=1, keep_pts=150), LIGHT)
        return s

    wood_fill = BARK if duotone else DEEP
    s = f'<g fill="{wood_fill}">' + "".join(b.path() for b in wood_main) + "</g>"
    if duotone:
        s += (f'<path d="{trunk_lo.edge(1.6)}" fill="none" stroke="{BARK_D}" '
              f'stroke-width="2.0" stroke-linecap="round" opacity=".55"/>')
    s += foliage(canopy, gaps)
    s += foliage(left_pad, left_gaps)
    s += foliage(tuft, [])
    # grass at the base
    grass_fill = MID if duotone else DEEP
    s += f'<g fill="{grass_fill}">'
    s += grass_tuft(74, 184, 7, 15, seed=31, lean=-0.6)
    s += grass_tuft(112, 186, 8, 13, seed=37, lean=0.5)
    s += "</g>"
    return s


def shore_squiggle(x0, y0, w, color, op):
    return (f'<path d="M{x0} {y0} q {w*0.18} -3 {w*0.38} 0 t {w*0.34} 1 t {w*0.28} -1" '
            f'fill="none" stroke="{color}" stroke-width="1.6" stroke-linecap="round" opacity="{op}"/>')


def mark_intricate(duotone=True, rid="w1"):
    inner = ""
    if duotone:
        inner += f'<circle cx="170" cy="94" r="30" fill="{FOG}"/>'
        inner += (f'<ellipse cx="158" cy="88" rx="15" ry="2.4" fill="{SEA}" opacity=".5"/>'
                  f'<ellipse cx="186" cy="99" rx="13" ry="2.1" fill="{SEA}" opacity=".4"/>')
        sea_c = SEA
    else:
        sea_c = DEEP
    # horizon + shore
    inner += f'<rect x="128" y="146" width="86" height="1.8" rx="0.9" fill="{sea_c}" opacity=".55"/>'
    inner += shore_squiggle(130, 170, 74, sea_c, .5)
    inner += shore_squiggle(144, 181, 60, sea_c, .35)
    inner += rock_mound(duotone, dx=-24, dy=8)
    inner += cypress_intricate(duotone)
    return badge(inner, rid)

# ---------------- page ----------------

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
.hero{display:grid;grid-template-columns:minmax(320px,1.15fr) minmax(260px,1fr);gap:24px;margin-top:32px;}
@media (max-width:720px){.hero{grid-template-columns:1fr}}
.panel{background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden;}
.stage{background:radial-gradient(110% 85% at 50% 20%,var(--stage) 0%,var(--card) 75%);display:flex;align-items:center;justify-content:center;padding:30px;}
.meta{padding:18px 24px 22px;border-top:1px solid var(--line);}
.meta .nm{font-family:var(--display);font-size:1.3rem;font-weight:600;}
.meta p{font-size:.88rem;color:var(--muted);margin:.35em 0 .9em;}
.sizes{display:flex;align-items:center;gap:14px;flex-wrap:wrap;}
.sizes .lab{font-family:var(--mono);font-size:.64rem;color:var(--muted);letter-spacing:.08em;text-transform:uppercase;margin-right:2px;width:100%;}
.chipbox{display:flex;align-items:center;justify-content:center;border:1px solid var(--line);border-radius:10px;background:var(--card);}
.chipbox.dark{background:var(--dark);border-color:#243026;}
.s96{width:104px;height:100px}.s64{width:72px;height:68px}.s32{width:44px;height:42px}
.alts{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;margin-top:22px;}
.alts .stage{padding:20px;}
.alts .meta{padding:12px 18px 14px;}
.alts .nm{font-size:1.05rem;}
footer{margin-top:56px;padding-top:18px;border-top:1px solid var(--line);font-size:.82rem;color:var(--muted);}
"""

def main():
    hero = mark_intricate(True, "w1")
    full = mark_duotone(1.0, "d1")
    ink = mark_intricate(False, "w2")
    syms = (f'<symbol id="mHero" viewBox="0 0 240 240">{hero}</symbol>'
            f'<symbol id="mFull" viewBox="0 0 240 240">{full}</symbol>'
            f'<symbol id="mInk" viewBox="0 0 240 240">{ink}</symbol>')
    html = f"""<title>Cypress — Logo, B5 final</title>
<style>{CSS}</style>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>{syms}</defs></svg>
<div class="wrap">
  <div class="kicker">Cypress · logo — B5, re-rendered</div>
  <h1>The Sentinel, drawn with fields instead of ovals</h1>
  <p class="lede">New renderer: the crown and granite are scalar fields whose silhouettes are extracted as smooth iso-contours, then shaded by eroding the same field toward the light. Organic, continuous masses — no stacked ellipses, nothing floating.</p>

  <div class="hero">
    <div class="panel">
      <div class="stage"><svg width="380" height="380" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
      <div class="meta">
        <div class="nm">B5 · Windswept Sentinel — proposed final</div>
        <p>Intricate cut: ragged foliage with sky showing through, a long bare branch with twigs, leaning trunk with root flare, grass at the base, setting sun with cloud slivers, horizon and shore lines.</p>
        <div class="sizes"><span class="lab">Scale &amp; ground</span>
          <div class="chipbox s96"><svg width="84" height="84" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
          <div class="chipbox s64"><svg width="56" height="56" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
          <div class="chipbox s32"><svg width="30" height="30" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
          <div class="chipbox dark s96"><svg width="84" height="84" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
          <div class="chipbox dark s64"><svg width="56" height="56" viewBox="0 0 240 240"><use href="#mHero"/></svg></div>
        </div>
      </div>
    </div>
    <div style="display:flex;flex-direction:column;gap:20px">
      <div class="panel">
        <div class="stage"><svg width="220" height="220" viewBox="0 0 240 240"><use href="#mInk"/></svg></div>
        <div class="meta"><div class="nm">One-ink twin</div>
          <p>Same geometry, single Cypress Deep — for stamps, embroidery, favicons, engraving. Ships alongside the color mark as one system.</p>
        </div>
      </div>
      <div class="panel">
        <div class="stage"><svg width="220" height="220" viewBox="0 0 240 240"><use href="#mFull"/></svg></div>
        <div class="meta"><div class="nm">Alternate: smooth cut</div>
          <p>The previous smooth-pad version, kept for comparison — calmer, but flatter.</p>
        </div>
      </div>
    </div>
  </div>

  <footer>Generated by mocks/logo_gen2.py — every shape is parametric; any tweak (crown density, lean, rock size) is a one-line change.</footer>
</div>"""
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo-candidates.html")
    with open(out, "w") as f:
        f.write(html)
    print(f"wrote {out} ({len(html)} bytes)")


if __name__ == "__main__":
    main()
