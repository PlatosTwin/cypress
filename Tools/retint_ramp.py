#!/usr/bin/env python3
"""Retint the caption ramp in OKLCh so it clears WCAG AA — RULINGS R1 and R1a, ERRATA E108.

    python3 Tools/retint_ramp.py            # the before/after table R1 asks for
    python3 Tools/retint_ramp.py --check    # exit non-zero if the shipped hexes miss their targets

Why this exists rather than a number in a diff: ERRATA E8 fitted the light -> dark transform in
OKLCh, because lightness, chroma and hue are the three things a designer moves and sRGB mixes
them. R1 overrules five transcribed values and R1a two more, and they overrule exactly one of
those three coordinates: **lightness moves, chroma and hue are held**, so the palette still reads
as the palette the designer chose. This script is that move, run as arithmetic. One further value
moves and is not an overrule at all — `surfaceEmptyThumb`'s *derived* dark, corrected under E8's
own rule; it is a ground rather than a foreground and lives in CORRECTED_GROUNDS.

The method, per token and per appearance:

  1. convert the current hex to OKLCh (sRGB -> linear -> OKLab -> polar);
  2. hold C and h; walk L toward the target contrast against the *binding* surface — the one of
     the token's two backgrounds that gives the worse ratio, which is the screen in light and the
     card in dark, and is not the same surface in both appearances;
  3. round the result back to 8-bit sRGB and re-measure on *every* surface the token sits on, in
     that appearance, because a value that is good on one ground is not thereby good on another.

Step 3 is the whole point. E106's sharpest observation is that `text.faint` on a card is worse
after dark (2.98) than in light (3.16) — the one place E8's transform moved a ratio the wrong way,
and it moved it that way because it was fitted on lightness alone and never re-measured against
the ground the token actually sits on. Nothing here is accepted on a fit; every number printed
below is measured on the rounded 8-bit hex that ships.

No dependencies: stdlib only.
"""

from __future__ import annotations

import argparse
import math
import sys

# ── sRGB ↔ OKLab ↔ OKLCh ──────────────────────────────────────────────────────────────────────
# Björn Ottosson's matrices, unmodified. OKLab L is 0…1 perceptual lightness.


def hex_to_rgb(value: int) -> tuple[float, float, float]:
    return (((value >> 16) & 0xFF) / 255, ((value >> 8) & 0xFF) / 255, (value & 0xFF) / 255)


def rgb_to_hex(rgb: tuple[float, float, float]) -> int:
    out = 0
    for channel in rgb:
        byte = int(round(min(max(channel, 0.0), 1.0) * 255))
        out = (out << 8) | byte
    return out


def _linearize(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _delinearize(c: float) -> float:
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def rgb_to_oklab(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = (_linearize(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklab_to_rgb(lab: tuple[float, float, float]) -> tuple[float, float, float]:
    L, a, b = lab
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = (v ** 3 for v in (l_, m_, s_))
    return (
        _delinearize(+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        _delinearize(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        _delinearize(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
    )


def oklab_to_oklch(lab: tuple[float, float, float]) -> tuple[float, float, float]:
    L, a, b = lab
    return (L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360)


def oklch_to_oklab(lch: tuple[float, float, float]) -> tuple[float, float, float]:
    L, C, h = lch
    return (L, C * math.cos(math.radians(h)), C * math.sin(math.radians(h)))


def hex_to_oklch(value: int) -> tuple[float, float, float]:
    return oklab_to_oklch(rgb_to_oklab(hex_to_rgb(value)))


def in_gamut(rgb: tuple[float, float, float], tolerance: float = 1e-4) -> bool:
    return all(-tolerance <= c <= 1 + tolerance for c in rgb)


def oklch_to_hex(lch: tuple[float, float, float]) -> tuple[int, bool]:
    """Round an OKLCh triple to 8-bit sRGB. Returns (hex, was_in_gamut_before_clamping).

    Chroma is reduced rather than clipped per channel when a lightness move walks the colour out
    of sRGB — clipping a channel moves the hue, and R1 holds the hue.
    """
    L, C, h = lch
    rgb = oklab_to_rgb(oklch_to_oklab((L, C, h)))
    if in_gamut(rgb):
        return rgb_to_hex(rgb), True
    lo, hi = 0.0, C
    for _ in range(48):
        mid = (lo + hi) / 2
        if in_gamut(oklab_to_rgb(oklch_to_oklab((L, mid, h)))):
            lo = mid
        else:
            hi = mid
    return rgb_to_hex(oklab_to_rgb(oklch_to_oklab((L, lo, h)))), False


# ── WCAG 2.1 ──────────────────────────────────────────────────────────────────────────────────
# Deliberately the same arithmetic as ContrastTests.contrast(_:_:), so a number printed here is
# the number the test pins.


def luminance(value: int) -> float:
    r, g, b = (_linearize(c) for c in hex_to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: int, b: int) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# ── The palette this touches ──────────────────────────────────────────────────────────────────
# Mirrors Cypress/DesignSystem/Tokens/CypressColor.swift. Surfaces are transcribed and do not
# move; R1 moves only the foregrounds listed under TARGETS.

LIGHT, DARK = "light", "dark"

SURFACE = {
    # token          light       dark        (both halves transcribed, SCREENS.md §1.2 / D1–D3)
    "surface.screen": (0xF5F6EF, 0x0E1712),
    "surface.card": (0xFFFFFF, 0x18251D),
    "surface.sheet": (0xFDFDF8, 0x18251D),
}


class Target:
    """A token R1 moves, the grounds it sits on, and the floor it has to clear on each."""

    def __init__(self, name, was, grounds, floor, aim, note, between=None, appearances=(LIGHT, DARK)):
        # A forced-dark token (`CypressColor.Dark.*`) has one value and one appearance: screen 04
        # is dark whether or not the phone is. Those pass `appearances=(DARK,)`, and both halves of
        # `was`/of the result are the same hex.
        self.appearances = appearances
        self.name = name          # CypressColor property
        self.was = was            # (light hex, dark hex) before R1
        self.grounds = grounds    # surfaces it is drawn on — measured on every one of them
        self.floor = floor        # the WCAG floor R1 holds it to
        self.aim = aim            # what this script solves for: floor + headroom, see below
        self.note = note
        # Set where a token's value is fixed by its *place in the ramp* rather than by a floor.
        # `text.faintAlt` is the only one: solved against 4.5 alone it lands 0.03 from `text.faint`,
        # which is R1's own objection to E106's fix ("a rounding error with two names") reappearing
        # one rung lower. So it keeps the fraction of the faint→muted lightness interval the
        # designer gave it, measured on the light pair: (faint.L − faintAlt.L) / (faint.L − muted.L).
        self.between = between    # (lower token, upper token) in OKLCh lightness


# The aim is deliberately above the floor. Two reasons, both about the 8-bit rounding at the end:
# a value solved to land exactly on 4.500 rounds to something that can read 4.49, and R1 pins
# these to ±0.05, so a pin sitting on the floor turns every future re-measure into a coin flip.
# The headroom is small enough not to eat the gap between two rungs.
TARGETS = [
    Target(
        "textFaint", (0x8B9482, 0x5F6F61),
        ["surface.screen", "surface.card"], 4.5, 4.62,
        "R1: the floor for text, on both surfaces, in both appearances",
    ),
    Target(
        "textFaintAlt", (0x77836F, 0x5F6F61),
        ["surface.screen", "surface.card"], 4.5, 4.62,
        "R1: same floor; drawn as a footnote on the screen, measured on the card too",
        between=("textFaint", "textMuted"),
    ),
    Target(
        "textMuted", (0x66735F, 0x94A496),
        ["surface.screen", "surface.card", "surface.sheet"], 6.0, 6.15,
        "R1: lifted to 6.0 so the rung above faint is visibly above it",
    ),
    Target(
        "estimatedBadgeText", (0x8A6A2A, 0xD99A4E),
        ["estimatedBadgeFill"], 4.5, 4.62,
        "R1: D7 makes `est.` the difference between a reading and a guess",
    ),
    Target(
        # Both grounds on purpose. C24 is `surface.card` on `surface.screen` at 1.09:1, so the
        # border is a boundary between two surfaces and 1.4.11 asks it to be visible against the
        # thing on either side of it. The screen is the harder of the two by ~0.1.
        "amberAttentionCardBorder", (0xD9A05B, 0xD99A4E),
        ["surface.card", "surface.screen"], 3.0, 3.10,
        "R1: C24's border is the only thing saying this card is different (WCAG 1.4.11)",
    ),

    # ── R1a ───────────────────────────────────────────────────────────────────────────────────
    # Three failures R1 was written without, because it was written from E106's table and E106's
    # sweep did not reach them. Two are foregrounds and are below; the third is a ground and is
    # `CORRECTED_GROUNDS`.
    Target(
        # C20's placeholder and magnifier. It wore `text.faintAlt`'s light hex by coincidence
        # rather than by alias, so R1 retired that value everywhere except here — and here is
        # screen 01, the default screen and the first thing anyone sees. Placeholder text is text.
        "searchGlyph", (0x77836F, 0x94A496),
        ["search.fill"], 4.5, 4.62,
        "R1a: C20's placeholder on the search bar, over the map paper it is 94% opaque against",
    ),
    Target(
        # `CypressColor.Dark.textFaint`, the forced-dark palette's micro-label grey. Screen 04 is
        # dark by design in both appearances, so a label R1 made legible when the *phone* is dark
        # was still illegible when the *screen* is — R1's own argument failing on its own terms.
        #
        # The disabled `Log visit` label is drawn in this token on `Dark.surfaceThumb` and that
        # ground is deliberately not in the list: WCAG 1.4.3 exempts text that is part of an
        # inactive component, and solving against it would make a disabled control read exactly as
        # strongly as an enabled one. Same call as `ctaDisabledLabel` in R1.
        "Dark.textFaint", (0x5F6F61, 0x5F6F61),
        ["camera.noteField", "camera.tray", "camera.shell"], 4.5, 4.62,
        "R1a: 04's note-field prompt and micro-labels; the forced-dark half of the same ramp",
        appearances=(DARK,),
    ),
    Target(
        # The rung above it, checked rather than assumed: if `Dark.textFaint` lifts into
        # `Dark.textMuted`, the forced-dark ramp collapses exactly as the resolving one would.
        "Dark.textMuted", (0x94A496, 0x94A496),
        ["camera.noteField", "camera.tray", "camera.shell"], 6.0, 6.15,
        "R1a: 04's offline line; held to R1's 6.0 so the rung above faint stays above it",
        appearances=(DARK,),
    ),
]

# A **corrected derivation**, not an overrule: E8's rule is that a derived value may be corrected,
# and this one is derived. `surfaceEmptyThumb` is 14's empty photo well. E8 read it as "a recess in
# a card" and snapped it to `dark.surface.thumb` `#1F2E22`, which is a *raised* rung — and the well
# is not in a card, it is on the screen, and its light value `#FAFBF4` is a card-level plane. The
# near-identical `surfaceShareCard` `#FAF8EF` derives to `dark.surface.card` on exactly that
# reading. Moving it there is E8 doing what E8 says it does, and it closes the last text pair the
# R1 retint left failing: `text.faint` on it goes 2.67 → 4.16 → 4.64 after dark.
CORRECTED_GROUNDS = {
    "surfaceEmptyThumb": {
        "was": (0xFAFBF4, 0x1F2E22),
        "now": (0xFAFBF4, 0x18251D),
        "carries": ["textFaint", "textFaintAlt", "textMuted"],
        "floor": 4.5,
        "note": "E8 correction: a well on the screen is a card-level plane → dark.surface.card",
    },
}

# Grounds that are not the three surfaces above.
EXTRA_GROUNDS = {
    "estimatedBadgeFill": (0xF1EAD8, 0x2E271A),  # transcribed light, E8-derived dark; both stay
    # C20's search fill is `rgba(255,255,255,.94)` over the map, so the ground the placeholder
    # actually sits on is the composite and not the token. Flattened over `surface.mapPaper`,
    # which is what 01 draws under the bar almost everywhere. It costs 0.06 in light and nothing
    # in dark (the dark composite rounds back onto `#18251D`), and measuring the token instead
    # would have been the same class of mistake as measuring faint on the wrong surface.
    "search.fill": (0xFEFDFC, 0x18251D),
    # Screen 04, dark in both appearances. Both halves are the same hex for that reason.
    "camera.shell": (0x10160F, 0x10160F),         # Dark.bgCamera
    "camera.tray": (0x151D15, 0x151D15),          # Dark.bgCameraTray
    "camera.noteField": (0x1B241B, 0x1B241B),     # Dark.surfaceCardAlt
    "camera.disabledButton": (0x1F2E22, 0x1F2E22),  # Dark.surfaceThumb — 1.4.3-exempt, reported only
    # 14's empty photo well, at its corrected dark value. See CORRECTED_GROUNDS.
    "surfaceEmptyThumb": (0xFAFBF4, 0x18251D),
    "ctaDisabledFill": (0xE9ECDE, 0x18251D),
}

# The rungs that do not move, for the monotonicity check. R1: "text.body and text.ink do not move."
FIXED_RAMP = {
    "textBody": (0x3C4A3E, 0xAEBBAB),
    "textInk": (0x1C2A21, 0xE4EBE2),
}


def ground(name: str, appearance: str) -> int:
    table = SURFACE if name in SURFACE else EXTRA_GROUNDS
    return table[name][0 if appearance == LIGHT else 1]


# ── The solve ─────────────────────────────────────────────────────────────────────────────────


def solve(current: int, grounds: list[str], appearance: str, aim: float, floor: float) -> tuple[int, bool]:
    """Move L, hold C and h, until the worst of `grounds` clears `aim`. Returns (hex, in_gamut).

    Direction is read off the colour rather than assumed: text darker than its ground gets darker,
    text lighter than its ground gets lighter. In practice that is "down in light, up in dark",
    but the two amber marks are not on the same ground as the text ramp and asserting the rule
    from the palette rather than from the appearance is what keeps them honest.

    **A half that already clears its floor is not moved.** An overrule is spent where it is needed
    and nowhere else: three of the ten halves here (both amber darks and `text.muted` dark) pass
    already, and moving them would substitute for a designer's hex to buy nothing. That is also
    why the aim is only consulted for a half that fails — the headroom is for landing a value, not
    for improving one.
    """
    L, C, h = hex_to_oklch(current)
    grounds_hex = [ground(g, appearance) for g in grounds]

    def worst(value: int) -> float:
        return min(contrast(value, g) for g in grounds_hex)

    if worst(current) >= floor:
        return current, True

    darker = luminance(current) < max(luminance(g) for g in grounds_hex)
    lo, hi = (0.0, L) if darker else (L, 1.0)
    best, gamut_ok = None, True
    for _ in range(64):
        mid = (lo + hi) / 2
        candidate, ok = oklch_to_hex((mid, C, h))
        if worst(candidate) >= aim:
            best, gamut_ok = candidate, ok
            if darker:
                lo = mid
            else:
                hi = mid
        else:
            if darker:
                hi = mid
            else:
                lo = mid
    if best is None:
        raise SystemExit(f"no lightness at C={C:.4f} h={h:.1f} reaches {aim} — chroma must move")

    # The binary search converges on a real-valued L; the shipped value is 8-bit. Step one 8-bit
    # notch back toward the original wherever that still clears the aim, so the retint is the
    # smallest one that works rather than the first one the search happened to land on.
    step = -1 if darker else 1
    while True:
        nudged = _nudge(best, -step)
        if nudged is None or worst(nudged) < aim:
            break
        best = nudged
    return best, gamut_ok


def _nudge(value: int, direction: int) -> int | None:
    """One 8-bit step along the token's own OKLCh lightness axis."""
    L, C, h = hex_to_oklch(value)
    for delta in range(1, 60):
        candidate, _ = oklch_to_hex((L + direction * delta * 0.0005, C, h))
        if candidate != value:
            return candidate
    return None


# ── Reporting ─────────────────────────────────────────────────────────────────────────────────


def measure(token_hex: int, grounds: list[str], appearance: str) -> list[tuple[str, float]]:
    return [(g, contrast(token_hex, ground(g, appearance))) for g in grounds]


def solve_all() -> dict[str, tuple[int, int]]:
    """The whole ruling, as {token: (light hex, dark hex)}."""
    out: dict[str, tuple[int, int]] = {}
    for target in TARGETS:
        if target.between:
            continue
        halves, gamut_ok = [], True
        for i, appearance in enumerate((LIGHT, DARK)):
            if appearance not in target.appearances:
                halves.append(None)
                continue
            value, ok = solve(target.was[i], target.grounds, appearance, target.aim, target.floor)
            halves.append(value)
            gamut_ok &= ok
        # A forced-dark token resolves to its one value in both appearances.
        light = halves[0] if halves[0] is not None else halves[1]
        dark = halves[1] if halves[1] is not None else halves[0]
        if not gamut_ok:
            print(f"  ! {target.name}: chroma was reduced to stay in sRGB", file=sys.stderr)
        out[target.name] = (light, dark)

    for target in TARGETS:
        if not target.between:
            continue
        out[target.name] = place_between(target, out)
    return out


def place_between(target: Target, solved: dict[str, tuple[int, int]]) -> tuple[int, int]:
    """Put a token back where it sat between two others in OKLCh lightness.

    Light: the fraction of the faint→muted lightness interval `text.faintAlt` occupied before is
    read off the three transcribed light hexes and reapplied to the two retinted ones. Dark: D3
    documents the footnote as `dark.text.faint` — one value, not two — so the dark half simply
    follows whatever the dark half of `text.faint` became, and the two stay the same colour after
    dark exactly as they were the same colour before it.
    """
    lower, upper = target.between
    was_lower = next(t for t in TARGETS if t.name == lower).was[0]
    was_upper = next(t for t in TARGETS if t.name == upper).was[0]
    span = hex_to_oklch(was_lower)[0] - hex_to_oklch(was_upper)[0]
    fraction = (hex_to_oklch(was_lower)[0] - hex_to_oklch(target.was[0])[0]) / span

    new_lower = hex_to_oklch(solved[lower][0])[0]
    new_upper = hex_to_oklch(solved[upper][0])[0]
    _, C, h = hex_to_oklch(target.was[0])
    light, ok = oklch_to_hex((new_lower - fraction * (new_lower - new_upper), C, h))
    if not ok:
        print(f"  ! {target.name}: chroma was reduced to stay in sRGB", file=sys.stderr)

    worst = min(contrast(light, ground(g, LIGHT)) for g in target.grounds)
    if worst < target.floor:  # the interval cannot hold it — fall back to the floor solve
        light, _ = solve(target.was[0], target.grounds, LIGHT, target.aim, target.floor)
    return light, solved[lower][1]


def report(solved: dict[str, tuple[int, int]]) -> None:
    print("RULINGS R1 / R1a — the caption ramp, retinted in OKLCh (L moves, C and h held)\n")
    for target in TARGETS:
        new = solved[target.name]
        print(f"{target.name}  — floor {target.floor}")
        print(f"    {target.note}")
        for i, appearance in enumerate((LIGHT, DARK)):
            if appearance not in target.appearances:
                continue
            was, now = target.was[i], new[i]
            wl, wc, wh = hex_to_oklch(was)
            nl, nc, nh = hex_to_oklch(now)
            print(
                f"    {appearance:<5} #{was:06X} -> #{now:06X}   "
                f"L {wl:.3f} -> {nl:.3f}   C {wc:.4f} -> {nc:.4f} (Δ{nc - wc:+.4f})   "
                f"h {wh:5.1f} -> {nh:5.1f} (Δ{(nh - wh + 180) % 360 - 180:+.1f})"
            )
            for g, before in measure(was, target.grounds, appearance):
                after = contrast(now, ground(g, appearance))
                flag = "  FAILS" if after < target.floor else ""
                print(f"          on {g:<18} {before:5.2f} -> {after:5.2f}{flag}")
        print()

    print("Corrected derivations — a ground moving, under E8's own rule rather than an overrule\n")
    for name, entry in CORRECTED_GROUNDS.items():
        print(f"{name}  #{entry['was'][0]:06X} ↔ #{entry['was'][1]:06X}"
              f"  ->  #{entry['now'][0]:06X} ↔ #{entry['now'][1]:06X}")
        print(f"    {entry['note']}")
        for token in entry["carries"]:
            value = solved[token]
            for i, appearance in enumerate((LIGHT, DARK)):
                before = contrast(value[i], entry["was"][i])
                after = contrast(value[i], entry["now"][i])
                flag = "  FAILS" if after < entry["floor"] else ""
                print(f"      {token:<13} {appearance:<5} {before:5.2f} -> {after:5.2f}{flag}")
    print()

    print("Reported, not solved for — 1.4.3 exempts text in an inactive component\n")
    for token, ground_name, what in (
        ("textFaint", "ctaDisabledFill", "09's disabled `Done` label (ctaDisabledLabel)"),
        ("Dark.textFaint", "camera.disabledButton", "04's disabled `Log visit` label"),
    ):
        value = solved[token]
        light = contrast(value[0], ground(ground_name, LIGHT))
        dark = contrast(value[1], ground(ground_name, DARK))
        print(f"    {what:<45} light {light:5.2f}   dark {dark:5.2f}")
    print()

    print("The ramp, after — contrast against each ground, both appearances\n")
    ramp = [
        ("text.faint", solved["textFaint"]),
        ("text.faintAlt", solved["textFaintAlt"]),
        ("text.muted", solved["textMuted"]),
        ("text.body", FIXED_RAMP["textBody"]),
        ("text.ink", FIXED_RAMP["textInk"]),
    ]
    header = f"    {'rung':<14}" + "".join(
        f"{a[:1]}·{s.split('.')[1]:<9}" for a in (LIGHT, DARK) for s in SURFACE
    )
    print(header)
    for name, pair in ramp:
        row = f"    {name:<14}"
        for appearance in (LIGHT, DARK):
            value = pair[0 if appearance == LIGHT else 1]
            for surface in SURFACE:
                row += f"{contrast(value, ground(surface, appearance)):<11.2f}"
        print(row)

    print("\nMonotonic — faint < muted < body < ink, so no future edit collapses two rungs:")
    for appearance in (LIGHT, DARK):
        for surface in ("surface.screen", "surface.card"):
            values = [
                (name, contrast(pair[0 if appearance == LIGHT else 1], ground(surface, appearance)))
                for name, pair in ramp
                if name != "text.faintAlt"
            ]
            ok = all(a[1] < b[1] for a, b in zip(values, values[1:]))
            print(
                f"    {appearance:<5} {surface:<15} "
                + " < ".join(f"{v:.2f}" for _, v in values)
                + ("   ok" if ok else "   NOT MONOTONIC")
            )
    print("\n    …and text.faintAlt keeps its place between faint and muted:")
    for appearance in (LIGHT, DARK):
        for surface in ("surface.screen", "surface.card"):
            i = 0 if appearance == LIGHT else 1
            trio = [
                contrast(solved[t][i], ground(surface, appearance))
                for t in ("textFaint", "textFaintAlt", "textMuted")
            ]
            same = trio[0] == trio[1]
            note = "   ok (one dark faint: D3)" if same else ("   ok" if trio[0] < trio[1] < trio[2] else "   OUT OF ORDER")
            print(
                f"    {appearance:<5} {surface:<15} " + " ≤ ".join(f"{v:.2f}" for v in trio) + note
            )


# What CypressColor.swift ships, so `--check` compares the derivation against the file rather than
# against itself. Two ways this pass can rot and both are caught here: the script changing and the
# tokens not following it, or the tokens changing and nobody re-running the script.
SHIPPED = {
    "textFaint": (0x697260, 0x7E8F80),
    "textFaintAlt": (0x5D6855, 0x7E8F80),
    "textMuted": (0x535F4C, 0x94A496),
    "estimatedBadgeText": (0x836324, 0xD99A4E),
    "amberAttentionCardBorder": (0xB8803A, 0xD99A4E),
    "searchGlyph": (0x6C7764, 0x94A496),
    "Dark.textFaint": (0x7E8F80, 0x7E8F80),
    "Dark.textMuted": (0x94A496, 0x94A496),
}


def check(solved: dict[str, tuple[int, int]]) -> int:
    failures = 0
    for target in TARGETS:
        shipped = SHIPPED[target.name]
        if solved[target.name] != shipped:
            print(
                f"DRIFT {target.name}: the solve gives "
                f"#{solved[target.name][0]:06X} ↔ #{solved[target.name][1]:06X}, "
                f"CypressColor.swift ships #{shipped[0]:06X} ↔ #{shipped[1]:06X}"
            )
            failures += 1
        for i, appearance in enumerate((LIGHT, DARK)):
            if appearance not in target.appearances:
                continue
            for g, ratio in measure(shipped[i], target.grounds, appearance):
                if ratio < target.floor:
                    print(f"FAIL {target.name} {appearance} on {g}: {ratio:.2f} < {target.floor}")
                    failures += 1

    # The corrected grounds carry the ramp, so they are checked against the ramp rather than
    # against a value of their own.
    for name, entry in CORRECTED_GROUNDS.items():
        for token in entry["carries"]:
            for i, appearance in enumerate((LIGHT, DARK)):
                ratio = contrast(SHIPPED[token][i], entry["now"][i])
                if ratio < entry["floor"]:
                    print(f"FAIL {token} {appearance} on {name}: {ratio:.2f} < {entry['floor']}")
                    failures += 1

    print("ok" if not failures else f"{failures} problem(s)")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true",
        help="verify the hexes CypressColor.swift ships are this derivation's, and still clear "
             "R1's floors on every ground; non-zero if not",
    )
    args = parser.parse_args()

    solved = solve_all()
    if args.check:
        return check(solved)

    report(solved)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
