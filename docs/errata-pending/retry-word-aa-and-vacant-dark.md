### Two findings the task-#14 design sweep turned up on the way, and neither was its to close (ticket #249, ticket #251)

Both came out of the measurement rig behind `docs/design-proposals/2026-08-06-task14.md`
(2026-08-06, branch `design/14-proposals` — a camera rig whose code ships nothing). Both are
findings about screens that already shipped rather than about the questions the rig was asked, which
is why they are here and not in the rulings entry beside them. Both are now closed by ticket #251.

Its contrast arithmetic is WCAG 2.1 relative luminance implemented to match `ContrastTests.swift`'s
own `luminance()`, and it was calibrated before any number below was believed: fifteen pairs this
repo already pins reproduced within 0.005 against a 0.05 tolerance. That calibration was repeated
independently while implementing #251 — twenty of this repo's own pinned ratios reproduced (C24
light 3.39/3.394, `text.ink` on a dark card 13.08/13.079, C10 dark 3.05/3.055, `border.cool` light
1.15/1.149, and so on), and the OKLCh half reproduced E120's `#A8B29C → #7F8974` as chroma held to
0.0002 and hue to 0.98°.

---

#### 1 · Screen 17's `retry` / `stopped` state word failed AA in light, and nothing was watching (#249)

**The finding.** `OutboxView`'s trailing state word is drawn in `accentAmber` `#B4711F` at
`CypressFont.mono11Bold` on `surface.card`: **3.95:1**. On `surface.screen` it is 3.63.

**The floor is 4.5, and that is the whole of it.** WCAG's large-text exemption, which would drop the
floor to 3.0, begins at 18 pt regular or **14 pt bold**. 11 pt bold is neither, so no exemption
applies and the pair takes the body floor like any other sentence. Measured on both grounds because
`OutboxQueueRow` is drawn inside C24 on 17 and the row also sits on the page behind it — the page is
the harder of the two, exactly as it is for C24's border.

**Why the suite did not catch it, which is the more useful half.** `ContrastTests` measures
`accentAmber` in exactly one role: as a **map pin** against map paper, where 3.0 is the correct floor
for a non-text mark. The token was measured in one role and thereby assumed answered in another.
That is this suite's own recurring lesson, restated by R1a two entries ago — "a pair that is never
measured is a pair that never fails" — and it survived R1a because R1a extended the sweep to grounds,
not to roles.

**Closed at the call site, not in the token.** `accentAmber` is Signal Amber, a brand hue with a
reserved meaning (SCREENS.md §1.1, "solely for 'this tree needs something'") that also draws the
amber map pin at 7.08:1 on the dark map paper. Retinting it to clear a text floor on screen 17 would
move a mark on screen 01, which nobody asked about. The word is now drawn in
`amberChipSelectedText` `#8A5A17` — **5.91:1** on the card, 5.43 on the page — which is already what
the reason line directly beneath it uses, so the two terminal lines read as one voice. Dark is
unchanged: both tokens resolve to `#D99A4E` there, at 6.57:1.

**The guard.** A contrast pin cannot see this change, because no token moved. So the decision is a
value — `OutboxQueueRow.terminalStateWordColor` — pinned in `Task14DrawingDecisionTests` against
both `amberChipSelectedText` and, separately, against `#B4711F` coming back. A second pin asserts
that Signal Amber itself is still `#B4711F` ↔ `#D99A4E`, so a future "fix" that satisfies the floor
by retinting the brand hue fails instead of passing. Red-proofed: setting
`terminalStateWordColor` back to `CypressColor.accentAmber` failed both assertions, naming
`#B4711F` and the 3.95:1 pair, and nothing else.

#### 2 · E122's vacant tile was still effectively invisible after dark

**The finding.** E122 swapped the vacant tile's base and highlight and measured the improvement in
*light*: 1.05 → 1.64:1 on the card. It did not measure dark. After dark
`borderDashedStrong` `#364133` on `dark.surface.card` `#18251D` is **1.48:1**, and the render shows
what that means — the shipped radial gradient did not read as anything at all, where both proposed
replacements did.

**This is a finding about a fix, which is the kind most likely to go unrecorded.** E122 was a
contrast correction that closed its own measurement and left the other appearance unmeasured; the
entry reads as complete because the number it quotes did improve. The same shape as #249 above: not
a wrong measurement, a measurement of one case treated as an answer for two.

**Closed by task #14's item 3, and independently of it.** The almanac tile is now drawn as
`surfaceEmptyThumb` under a dashed `borderDashedStrong` edge — 14's empty photo well at 34 pt —
rather than as a radial-gradient blob. The ruling for that change is a *treatment* argument (ROADMAP
§1: a vacant site is "a distinct planting-site state, **not** a variant of the tree profile"; see
`docs/rulings-pending/task14-design-decisions.md`), and this is a second and sufficient reason for
it.

**The ratio does not change and the rendering does, which is the point worth stating plainly.**
The dashed edge is the same `#364133` on the same `#18251D`, still 1.48:1. What changed is that a
dashed frame on a plane is a *shape*, and a radial wash at 1.48:1 is not — the same reason no C10
tile is asked to clear 3:1 and none is meant to (`elder`'s base is 1.18:1; the house-style band
`ContrastTests.knownFailures` already records for `border.cool` is 1.15:1). Do not read this entry
as a claim that 1.48:1 became acceptable; read it as a claim that the tile now has an edge where it
previously had only a gradient.

Sampled off the shipped renders on iPhone 16 Plus `24D1629F-9FA8-4E3D-812E-F6BC85C9E668`, light and
dark, after confirming each image's page pixel was `#F5F6EF` and `#0E1712` respectively: the vacant
tile is `#FAFBF4` with 872 px of `#C4CEB4` dash in light and `#18251D` with 882 px of `#364133` dash
in dark, against the `elder` tile's solid `#E7EFE2` / `#27352B` one section above it.
