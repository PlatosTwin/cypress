#!/usr/bin/env python3
"""
Tools/map_species_palette.py — reproduces the four species-slot colours on screen 01.

ERRATA E149. `CypressColor.pinSpeciesA`…`D` are the only tokens in the design system whose *light*
half is ours as well as the dark one, because SCREENS.md draws no species colouring at all. This is
the arithmetic behind them, in the same space `Tools/retint_ramp.py` and ERRATA E8's derivation work
in — OKLCh, which separates the three things a designer actually moves.

    python3 Tools/map_species_palette.py            # verify the shipped four
    python3 Tools/map_species_palette.py --search   # re-run the search that chose them

── The five constraints, all at once ────────────────────────────────────────────────────────────
1. >= 3:1 (WCAG 1.4.11, non-text mark) against *every* ground screen 01 draws, in both appearances.
   Seven grounds each: the map paper, the grid, the street band, the park block, the park inset ring,
   the ocean, the beach. The paper is the easiest of the seven and is the one a careless check would
   use; the binding grounds are the park block in light and the park inset ring in dark.
2. >= 0.10 OKLab dE from each other, five times the ~0.02 just-noticeable difference.
3. >= 0.099 OKLab dE from every mark on the map whose hue already carries a meaning: Canopy (the
   residual city pin), Signal Amber ("this tree needs something"), the GPS dot, the cluster badge and
   a memorial's grey. Three whole arcs of the wheel are excluded outright — amber 20-115 deg, Canopy
   125-200 deg, GPS 232-272 deg — and what is left will not hold six hues this far apart, which is
   why there are four slots.
4. The pin ring (and the glyph, drawn in the same token) reads on every fill at >= 3:1.
5. Lightness descends A->D in light and ascends A->D in dark, so the rank is faintly legible as
   weight. Not load-bearing: the glyph is.

dE, not WCAG contrast, for constraints 2 and 3. Contrast is a luminance ratio, so two colours of the
same lightness and opposite hue read 1.0:1 — the right tool for "can I see this mark on that ground"
and the wrong one for "can I tell these two marks apart".
"""

from __future__ import annotations

import argparse
import itertools
import math

# ── sRGB <-> OKLab/OKLCh ─────────────────────────────────────────────────────────────────────────


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_to_rgb(value: int) -> tuple[float, float, float]:
    return ((value >> 16 & 255) / 255, (value >> 8 & 255) / 255, (value & 255) / 255)


def rgb_to_hex(r: float, g: float, b: float) -> int:
    clamp = lambda v: max(0, min(255, int(round(v * 255))))
    return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b)


def rgb_to_oklab(r: float, g: float, b: float) -> tuple[float, float, float]:
    r, g, b = _srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def _oklab_to_linear(L: float, a: float, b: float) -> tuple[float, float, float]:
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def lch_to_hex(L: float, C: float, H: float) -> int:
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    return rgb_to_hex(*(_linear_to_srgb(max(0.0, min(1.0, v))) for v in _oklab_to_linear(L, a, b)))


def hex_to_lch(value: int) -> tuple[float, float, float]:
    L, a, b = rgb_to_oklab(*hex_to_rgb(value))
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def in_gamut(L: float, C: float, H: float) -> bool:
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    return all(-0.001 <= v <= 1.001 for v in _oklab_to_linear(L, a, b))


def max_chroma(L: float, H: float, cap: float = 0.37) -> float:
    lo, hi = 0.0, cap
    for _ in range(40):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if in_gamut(L, mid, H) else (lo, mid)
    return lo


# ── WCAG and dE ──────────────────────────────────────────────────────────────────────────────────


def luminance(value: int) -> float:
    r, g, b = (_srgb_to_linear(c) for c in hex_to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: int, b: int) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def delta_e(a: int, b: int) -> float:
    return math.dist(rgb_to_oklab(*hex_to_rgb(a)), rgb_to_oklab(*hex_to_rgb(b)))


# ── The grounds and the reserved marks, from CypressColor ────────────────────────────────────────

LIGHT_GROUNDS = {
    "map paper": 0xE9E5D4,
    "map grid": 0xF7F4E6,
    "street band": 0xFAF7EC,
    "park block": 0xCDE0BC,
    "park inset ring": 0xBCD3A6,
    "ocean": 0xA9CDC7,
    "beach": 0xEADFB4,
}
DARK_GROUNDS = {
    "bg.map": 0x141E16,
    "map grid": 0x1C2A1F,
    "street band": 0x232F24,
    "park block": 0x1B3123,
    "park inset ring": 0x274531,
    "ocean": 0x14282B,
    "beach": 0x2B3226,
}
RESERVED_LIGHT = {
    "canopy pin (residual)": 0x2F6B4F,
    "signal amber (needs care)": 0xB4711F,
    "gps dot": 0x3577C9,
    "cluster badge": 0x1D4634,
    "memorial grey": 0xC4C8B8,
}
RESERVED_DARK = {
    "canopy pin (residual)": 0x6FAE8C,
    "signal amber (needs care)": 0xD99A4E,
    "gps dot": 0x6FA8E8,
    "cluster badge": 0x8EC3A5,
    "memorial grey": 0xC4C8B8,
}
RING_LIGHT, RING_DARK = 0xFFFFFF, 0x0E1712

GROUND_FLOOR = 3.0
PAIRWISE_FLOOR = 0.10
RESERVED_FLOOR = 0.099

# What shipped. Slot, hue, light L, dark L, and the two hexes.
SHIPPED = [
    ("A · plum", 335, 0.420, 0.820, 0x7B226D, 0xFC9FE9),
    ("B · lagoon", 230, 0.420, 0.820, 0x085570, 0x74D1FC),
    ("C · iris", 290, 0.460, 0.820, 0x5A43A4, 0xC3BAFC),
    ("D · cherry", 0, 0.500, 0.660, 0xA33460, 0xD9668E),
]
CHROMA_CAP = 0.15

# Hue arcs a species slot may not enter, because a mark in them already means something.
BANNED_ARCS = [(20, 115), (125, 200), (232, 272)]


def value_on(hue: float, lightness: float) -> int:
    return lch_to_hex(lightness, min(max_chroma(lightness, hue) * 0.95, CHROMA_CAP), hue)


# ── Verify ───────────────────────────────────────────────────────────────────────────────────────


def verify() -> bool:
    ok = True
    print("The four shipped slots, regenerated from their (hue, L) and compared:\n")
    for name, hue, light_L, dark_L, light_hex, dark_hex in SHIPPED:
        made_light, made_dark = value_on(hue, light_L), value_on(hue, dark_L)
        match = made_light == light_hex and made_dark == dark_hex
        ok &= match
        print(
            f"  {name:12s} hue {hue:3d}  light #{light_hex:06X} (regenerated #{made_light:06X})"
            f"  dark #{dark_hex:06X} (regenerated #{made_dark:06X})  {'ok' if match else 'MISMATCH'}"
        )

    print("\nEvery ground, every slot (floor %.1f:1):" % GROUND_FLOOR)
    for name, _, _, _, light_hex, dark_hex in SHIPPED:
        worst_l = min((contrast(light_hex, g), n) for n, g in LIGHT_GROUNDS.items())
        worst_d = min((contrast(dark_hex, g), n) for n, g in DARK_GROUNDS.items())
        ok &= worst_l[0] >= GROUND_FLOOR and worst_d[0] >= GROUND_FLOOR
        print(
            f"  {name:12s} light worst {worst_l[0]:5.2f}:1 on the {worst_l[1]:15s}"
            f"   dark worst {worst_d[0]:5.2f}:1 on the {worst_d[1]}"
        )

    print("\nPairwise separation (floor %.3f):" % PAIRWISE_FLOOR)
    worst = (99.0, "")
    for (n1, _, _, _, l1, d1), (n2, _, _, _, l2, d2) in itertools.combinations(SHIPPED, 2):
        for tag, value in ((f"light {n1} / {n2}", delta_e(l1, l2)), (f"dark {n1} / {n2}", delta_e(d1, d2))):
            worst = min(worst, (value, tag))
    ok &= worst[0] >= PAIRWISE_FLOOR
    print(f"  tightest pair: dE {worst[0]:.3f}  ({worst[1]})")

    print("\nSeparation from the reserved marks (floor %.3f):" % RESERVED_FLOOR)
    worst = (99.0, "")
    for name, _, _, _, light_hex, dark_hex in SHIPPED:
        for r, h in RESERVED_LIGHT.items():
            worst = min(worst, (delta_e(light_hex, h), f"light {name} vs {r}"))
        for r, h in RESERVED_DARK.items():
            worst = min(worst, (delta_e(dark_hex, h), f"dark {name} vs {r}"))
    ok &= worst[0] >= RESERVED_FLOOR
    print(f"  tightest: dE {worst[0]:.3f}  ({worst[1]})")

    print("\nNo slot sits in a reserved hue arc:")
    for name, hue, *_ in SHIPPED:
        inside = [arc for arc in BANNED_ARCS if arc[0] <= hue <= arc[1]]
        ok &= not inside
        print(f"  {name:12s} hue {hue:3d}  {'inside ' + str(inside) if inside else 'clear'}")

    print("\nThe ring and glyph on every fill (floor %.1f:1):" % GROUND_FLOOR)
    for name, _, _, _, light_hex, dark_hex in SHIPPED:
        cl, cd = contrast(RING_LIGHT, light_hex), contrast(RING_DARK, dark_hex)
        ok &= cl >= GROUND_FLOOR and cd >= GROUND_FLOOR
        print(f"  {name:12s} light {cl:5.2f}:1   dark {cd:5.2f}:1")

    print("\n" + ("ALL CONSTRAINTS HOLD" if ok else "FAILED — a constraint above is broken"))
    return ok


# ── Search ───────────────────────────────────────────────────────────────────────────────────────


def search() -> None:
    """Re-runs the choice: maximise the smallest separation in the whole set.

    Slow on purpose (a few minutes). It exists so the four values are answerable rather than
    asserted — change a ground, a reserved mark or an arc and this says what the new answer is.
    """
    hues = [h for h in range(0, 360, 5) if not any(a <= h <= b for a, b in BANNED_ARCS)]
    light_ls = [0.34, 0.38, 0.42, 0.46, 0.50, 0.54]
    dark_ls = [0.62, 0.66, 0.70, 0.74, 0.78, 0.82]

    cells = {}
    for hue in hues:
        for light_L in light_ls:
            light = value_on(hue, light_L)
            if min(contrast(light, g) for g in LIGHT_GROUNDS.values()) < GROUND_FLOOR:
                continue
            reserved_light = min(delta_e(light, r) for r in RESERVED_LIGHT.values())
            for dark_L in dark_ls:
                dark = value_on(hue, dark_L)
                if min(contrast(dark, g) for g in DARK_GROUNDS.values()) < GROUND_FLOOR:
                    continue
                reserved = min(reserved_light, min(delta_e(dark, r) for r in RESERVED_DARK.values()))
                cells[(hue, light_L, dark_L)] = (light, dark, reserved)
    print(f"admissible (hue, L_light, L_dark) cells: {len(cells)}")

    best = None
    for quad in itertools.combinations(sorted({k[0] for k in cells}), 4):
        picks = []
        for hue in quad:
            candidates = sorted(
                ((v[2], k, v) for k, v in cells.items() if k[0] == hue), reverse=True
            )
            if not candidates:
                break
            picks.append(candidates[:4])
        if len(picks) != 4:
            continue
        for combo in itertools.product(*picks):
            lights = [c[2][0] for c in combo]
            darks = [c[2][1] for c in combo]
            reserved = min(c[0] for c in combo)
            pairwise = min(
                min(delta_e(a, b) for a, b in itertools.combinations(lights, 2)),
                min(delta_e(a, b) for a, b in itertools.combinations(darks, 2)),
            )
            score = min(reserved, pairwise)
            if best is None or score > best[0]:
                best = (score, reserved, pairwise, [c[1] for c in combo], lights, darks)

    score, reserved, pairwise, keys, lights, darks = best
    print(f"best achievable minimum separation: {score:.3f}"
          f"  (vs reserved {reserved:.3f}, pairwise {pairwise:.3f})")
    for key, light, dark in zip(keys, lights, darks):
        print(f"  hue {key[0]:3d}  light L {key[1]:.2f} -> #{light:06X}"
              f"   dark L {key[2]:.2f} -> #{dark:06X}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--search", action="store_true", help="re-run the palette search (slow)")
    args = parser.parse_args()
    if args.search:
        search()
    else:
        raise SystemExit(0 if verify() else 1)
