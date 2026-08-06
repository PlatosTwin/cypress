## Task #14's four residual design questions, decided (closes the design half of E85, E60, E119/E122)

**2026-08-06.** Four questions that were design's to answer. A design agent measured each on the
real app and the real seed and wrote them up as options with renders and computed ratios
(`docs/design-proposals/2026-08-06-task14.md`, on the throwaway branch `design/14-proposals`,
which is a camera rig and whose code ships nothing). The project owner read that document and
answered, verbatim:

> all of these look fine. go with your recommended options in each case

That is the delegation this entry records, and the four recommendations below are what it approved.
A fifth item — an AA failure the rig found on the way, ticket #249 — was approved in the same
sentence and is recorded here too, because it changes what a screen draws.

**What kind of entry this is.** Everything in `ERRATA.md` is a conflict found between documents that
already existed. This is the other kind: a decision made where the documents said nothing, under
authority that was granted rather than assumed. It follows R1's own distinction, carried from E8 —
a **transcribed** value may not be changed, a **derived** value may be corrected, and an
**overruled** value was already answered and is being changed anyway under a delegation. Two values
here are overruled; nothing else in the palette moves.

---

### 1 — Screen 17's dark amber comes apart into two rungs (item 1a; closes E85's first question)

**The question, as E85 put it:** C24's border, the state word and the tile glyph all collapse onto
the single `#D99A4E` the dark palette gives amber, so the card, its word and its glyph become one
hue at one weight.

It is worse than E85 stated. Screen 17 draws **four** distinct ambers in light — `#EBD3A8` pill
border, `#B8803A` card border (R1 darkened that one deliberately), `#B4711F` state word, `#8A5A17`
reason line and glyph — and **one** after dark. The render is the argument: in dark the terminal
card's *border* was the loudest thing on the screen, louder than any word on it, where in light it
is quieter than the text it surrounds.

**The ruling: one new dark amber, `#A2670D`, and it is for boundaries only.**
`amberAttentionCardBorder` and `amberPillBorder` take it after dark. Every amber **mark** — the
state word, the reason line, the tile glyph, the pill text — stays at `#D99A4E`, exactly where E8's
derivation put it.

`#A2670D` is a lightness-only move in OKLCh from `dark.accent.amber` `#D99A4E` — R1's method and the
E120 precedent, run downward instead of up:

```
#D99A4E   L 0.7328   C 0.1193   H 69.11°
#A2670D   L 0.5648   C 0.1189   H 69.35°      ΔL −0.168   ΔC −0.0004   ΔH +0.24°
```

Chroma and hue are held to 0.0004 and a quarter of a degree, so no hue enters the palette — the
discipline R7 and E8 both keep. The lightness is chosen so the dark border lands on **3.39:1**
against `surface.card`, the *same* ratio R1 chose for the light border, so the boundary reads at one
strength in both appearances.

| Pair | Light | Dark, before | Dark, now |
|---|---|---|---|
| C24 border on the card it identifies | 3.39 | 6.57 | **3.39** |
| C24 border on the page behind it | 3.12 | 7.55 | **3.90** |
| amber pill border on its fill | 1.28 | 6.11 | **3.15** |
| state word / reason line / tile glyph | — | 6.57 / 6.57 / 6.11 | *unchanged* |

WCAG 1.4.11's 3.0 floor binds on all three, for the reason R1 already established for C24:
`surface.card` on `surface.screen` is 1.09:1, so the border is the only thing distinguishing the
card. The light pill border is left at `#EBD3A8` / 1.28 — a pill is identified by its fill and its
label, which is the same reading that leaves `amberChipSelectedBorder` where R1 found it.

**What was declined, and why it is worth recording.** The three-rung alternate also moved the state
word, to `#C18436`. It mirrors light's ordering exactly, and it costs a brand hue: the state word is
`accentAmber`, Signal Amber, which also draws the amber map pin, and moving its dark value takes
that pin from 7.08:1 to 5.40:1 on the dark map paper. A brand hue does not change on a screen nobody
asked about. The "do nothing" alternate was also on the table and is genuinely defensible — every
dark amber pair already cleared AA, so the collapse cost hierarchy and not accessibility.

### 2 — Screen 16's 56 pt readout is left exactly as it is (item 1b; closes E85's second question)

**The question:** the largest single piece of type in the app had never been looked at after dark.

**Looked at. It holds, and nothing changes.** Dark reads 15.03:1 against light's 13.77:1 — a 9%
difference, with *dark* the stronger, which is the halation worry stated as a number. Both proposed
corrections were worse than the complaint. Dimming to light parity (`#DBE1D9`) is ΔE **0.029** in
OKLab from the shipped value: above E8's 0.02 "the designer already wrote this color" threshold and
far below its 0.05 rejection tolerance, which is to say it buys a new token for a move nobody can
see. Dropping to the documented `text.body` dark rung makes the readout **quieter than the keypad
digits below it**, and the subject of a screen must not be the dimmest thing on it.

And the structural cost either way: `text.ink` is a **transcribed** D2 value, so changing it for one
call site means overruling the designer app-wide or minting a screen-16-only ink token. For 0.029 in
OKLab, neither. **No code changes for this item** — it is recorded so the question is closed rather
than merely unasked.

### 3 — Screen 10's link becomes a full-width row, and unclamps at accessibility sizes (item 2; closes E60's layout half)

**The question:** E60 recorded that the mock's four-hex slug cannot name one of 195,309 trees, so
the card renders the tree's own UUID, and 36 characters of mono 10.5 do not fit the drawn card
beside a 72 pt thumbnail.

**What the rig found changes the shape of the answer.** The string is `cypress.app/sf/tree/` plus a
36-character UUID — **56 characters** — and the card's *full inner width* holds about 48 at the
drawn size. **No two-column arrangement makes it one line.** Widening the text column is not the
fix; giving two lines a place to live is.

**And at accessibility sizes it was not wrapping at all — it was truncating to nothing.**
`lineLimit(2)` in a column that narrow yielded `cypress.app/sf/tree/0…`: the reader got **none** of
the identifier, which is precisely the outcome E60 says is worse than extra lines, happening today.

**The ruling: 10a, plus releasing the line limit above the accessibility threshold.** Row 1 is the
thumb beside name + location + strip, exactly as drawn. Row 2 is the link, at the card's full inner
width, below both. **No new token and no new spacing** — `ShareMetrics.urlTop` (6) is the gap and
`ShareMetrics.cardPadding` (14) the inset, both already this string's own. At AX5 the whole link now
renders over several lines with no ellipsis, which is the only arrangement in which somebody at AX5
can read or type it at all — E60's own reason for refusing to truncate it.

The two alternates both kept the wrap where it was: indenting the row to the text column leaves the
thumb's 72 pt of gutter unused, and sending the strip wide as well costs vertical space for a
different benefit.

**The short public slug is still open and is still the owner's.** E60 named it — a base32 of the id
would restore the single line at any type size — and it changes the app's **public identifier**,
against DECISIONS §2.5's commitment to "stable citable tree UUIDs". Nothing here touches it.

### 4 — The vacant-site almanac tile is redrawn as the empty well (item 3; closes E119/E122's treatment half)

**What was still open.** E122 closed the *contrast* half of this tile by swapping base and highlight.
It did not touch the *treatment*: the tile was still a 34 pt rounded square with a radial-gradient
blob at 45%/42%, which is the **same drawing** as the five living-tree tiles beside it, differing
only in color. ROADMAP §1's decision on vacant sites is "a distinct planting-site state, **not** a
variant of the tree profile", and R7/E119/E123 gave that state a drawn vocabulary everywhere else —
the map pin, 14's empty photo well, the site screen, `LocationPrompt`. The almanac tile was the one
member still wearing the tree's clothes.

**The ruling: 12a — the empty well, at tile size.** `surfaceEmptyThumb` under a dashed
`borderDashedStrong` edge, the exact treatment those three call sites already draw, at 34 pt. **No
new token and no new hue**, and off the map a dashed frame is what this family already speaks: E119
chose a *solid* ring for the map pin only because on the map dashes mean the community layer
(DECISIONS §3.16), and screen 12 has no community layer.

The alternate — the map pin's hollow ring, so the almanac row and the pin are literally the same
mark — has cross-surface consistency in its favor and loses on legibility of kind: at 34 pt a ring
can read as a bullet or a status dot, where a dashed frame can only read as an empty place.

**On contrast, so it is not asked.** No C10 tile clears 3:1 against its card and none is meant to —
`elder`'s base is 1.18:1 and the vacant mark 1.64:1, the same house-style band as `border.cool` at
1.15:1 that `ContrastTests.knownFailures` already records. This is a treatment question. It does,
however, close a *rendering* problem E122 only half-fixed; that half is an ERRATA matter and is
written up in `docs/errata-pending/retry-word-aa-and-vacant-dark.md`.

### 5 — Ticket #249: 17's state word moves at the call site, and Signal Amber is not touched

Approved in the same sentence. The `retry` / `stopped` state word is `accentAmber` `#B4711F` at mono
11 pt **bold** on `surface.card`: **3.95:1**, against a 4.5 floor, because WCAG's large-text
exemption starts at 18 pt regular or 14 pt bold and 11 pt bold is neither.

**The ruling: change what the screen draws, not what the token is.** The word is drawn in
`amberChipSelectedText` `#8A5A17` — **5.91:1** on the card, and already the color of the reason line
directly beneath it. Signal Amber is a brand hue with a reserved meaning (§1.1) that also draws the
amber map pin; retinting it to clear a text floor on screen 17 would move a mark on screen 01. The
finding itself is an ERRATA matter and is written up with the entry above.

---

**Where these landed.** `amberAttentionCardBorder` and `amberPillBorder` are now `overruled` in
`CypressColor`, both listed in `overruledTokens` with their measured before/after, and both swatches
updated in `TokenGallery`. The three boundary ratios and the marks that did not move are pinned in
`ContrastTests`; the two call-site decisions (#249's color, screen 12's drawing) are pinned as values
in `Task14DrawingDecisionTests`, because a contrast pin cannot see either. Screen 10's line-limit
decision is `ShareMetrics.urlLineLimit(isAccessibilitySize:)`, pinned in `AX5ReflowTests`.
