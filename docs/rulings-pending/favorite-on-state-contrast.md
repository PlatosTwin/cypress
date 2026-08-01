# The favorite's on state inverts to the accent pair (task #153)

**UNNUMBERED — pending. The orchestrator assigns the R number at merge and rewrites any code
comments that cite this filename.**

**The finding.** From the owner's device walk of 2026-07-31 (task #153): tapping `Favorite` on
screen 03 persists correctly — E184's refresh-race fix holds, `FavoriteRoundTripTests` proves the
write — but the owner reported the button as rendering identically in both states, so a tap gives
no confirmation.

**The premise, checked before building on it.** The claim "renders identically" is false of the
code as written: E112 built R2's selected appearance and it has been on every build since —
`callout.green.fill` card, `cta.fill` label and border, `hairlineStrong` against `hairline`,
12/800 against 12/600, photographed in both schemes by `FavoriteAppearanceShots`. What the report
is evidence of is not a missing state but an **illegible** one: in light mode the on-fill is
`#EFF3E3` against the idle `#FFFFFF` and the label moves between two dark greens (`#1D4634` and
`#3C4A3E`); in dark mode the two fills are `#1A241A` against `#18251D`. A difference a screen
shows indoors and a phone in daylight does not. The channels that survive greyscale — border
width and weight — are real but small at a 12pt label.

**The ruling: the selected cell takes the selected filter chip's own treatment.**

- fill `cta.fill`, label `cta.label` — the exact pair C4's `filterSelected` draws, which is the
  app's established rendering of "this text control is on". `#1D4634` under white in light,
  mint `#8EC3A5` under near-black in dark.
- border `cta.fill` at `hairlineStrong`, and 12/800, both unchanged from E112.
- No glyph. R2's correction and R30 both stand: C8 has no heart, and this change draws nothing —
  the state change is fill, tint and weight, all existing tokens.
- The label stays `Favorite` in both states (R2), and the spoken value/`.isSelected` trait are
  unchanged.

**What this departs from and why that is allowed.** R2's clause "the card fill takes the app's
existing tinted green surface" is superseded for this one cell: the tinted surface was tried,
shipped (E112), and reported unreadable by the decision-owner from the field, which is a stronger
record than the ruling's original guess at a fill. The luminance inversion is itself a channel
that survives greyscale, so the state now carries in fill-luminance, border width and weight —
one more channel than E112 had, not one fewer.

**Verification.** `FavoriteToggleTests` asserts the two appearances differ as facts (distinct
fill, label, border width, font) and that the selected pair clears 4.5:1 in both schemes;
`FavoriteAppearanceShots` photographs both states, light and dark. Camera-truth on the physical
phone remains the owner's to confirm.
