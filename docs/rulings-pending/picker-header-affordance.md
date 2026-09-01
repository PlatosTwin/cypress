# Rulings pending — the Journal stats picker's affordance (owner decision, 2026-08-31)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge and rewrites any comment that cites this filename. No code comment in this round
cites it by filename; the two view files and `HeaderPillButton` say "the picker-header ruling,
pending" in prose.

One entry. It **supersedes** the affordance shipped in PR #132, on the owner's own later decision —
which per `format1-retirement.md` is the only mechanism that may do that.

---

### R??? — The Journal stats header pill is the area picker

**Date:** 2026-08-31. **Decided by:** owner. **Implemented by:** this round.

**Supersedes:** the affordance shipped in PR #132 (`AreaPickerCopy.change`, a boxed
`SecondaryOutlineButton` under the provenance sentence on both Journal stats segments).

#### What was wrong

The owner's report, verbatim: *"the UI for changing where you are in a city or neighborhood is
trash. the 'Change' button is ugly and the spacing is horrible."*

Three separate faults, and the spacing one is the one a screenshot shows fastest:

1. **It crowded a section it was not part of.** The provenance block was
   `VStack { sentence; Change }` at the gutter, and directly beneath it — with no separation but
   `labelSectionTop` — sat §2's `THIS SEASON` micro-label. Three unrelated things in a vertical
   stack, reading as one, and the control belonged to none of the two around it. On a 402 pt screen
   it also pushed §4's `Walk to it` off the first screenful.
2. **It outranked the screen's real primary action.** A 44 pt outlined box in the CTA green is the
   app's C7, the shape of a secondary *action*. §4's `Walk to it` is the almanac's one directed ask,
   and the picker — a preference, used rarely — was drawn at comparable weight two thirds of the
   screen above it.
3. **It named an operation without its subject.** "Change" alone does not say change *what*; a
   reader had to look up to the header to find out, and VoiceOver users got `Change, button` with
   the answer nowhere in the utterance.

#### The ruling

The owner's words: **"Tappable header name — the place name in the header becomes the control — a
pill/chip with a small drawn chevron. The separate button and its stacked spacing disappear
entirely; the provenance sentence stays as one quiet line."**

#### What was built

`HeaderPillButton` (DesignSystem/Components/ScreenHeader.swift), used by `AlmanacScreen.header` and
`CityScreen.header` whenever there is something to pick.

- **The same capsule `HeaderPill` already draws**, unchanged: `surfaceCard` fill, `borderCool`
  hairline, `body12` in `textMuted`, `headerPillPaddingV/H`. It is the element it always was —
  still the screen naming its own subject — and re-styling it as a "button" would have re-imported
  the visual weight fault 2 is about.
- **Plus a drawn chevron**, `CypressChevron(direction: .down)`, 9×5 at the default type setting and
  scaling from there. That mark is the entire visual difference between the label and the control,
  which is the point: it is the smallest thing that says *pressable*. Its color is ruled on
  separately below, and the reason it needed a ruling is that same sentence.
- **The mark scales with the label**, `@ScaledMetric(relativeTo: .caption)`. The precedent is
  `AccountAskView.AccountProviderButton`, whose comment says to pick the curve the paired font
  actually scales on; there that is `.body` for `body15Bold`, here it is `.caption` for `body12`.
  Following the precedent literally rather than by its reasoning would have been wrong.
- **Aligned to the first text baseline**, not centered. Centered is indistinguishable while the
  label is one line and wrong the moment it is two — see the wrapped-pill note below.
- **`direction: .down` is new and is drawn, not rotated.** A `RotatedShape` keeps its unrotated
  frame as its layout box, so a quarter-turned 10×16 chevron lays out 10 wide and reads 16 wide, and
  the pill would be spaced against a box the mark does not occupy. There are no SF Symbols here
  (R57, `DrawnGlyphGuardTests`).
- **`cypressHitArea()`**: the pill draws ~24 pt tall and gets the 44 pt target without the drawn
  size moving (ARCHITECTURE §6).

The provenance sentence is now a bare `Text` on both segments. `AreaPickerCopy.change` is deleted.

#### Amendment (orchestrator, 2026-08-31) — the mark's color is a contrast requirement

**Ruled after the PR review.** The chevron shipped in `chevronDisclosure`, the token every other
disclosure chevron in the app uses. Measured off rendered pixels, that is **1.96:1** against the
capsule in light and **2.16:1** in dark. WCAG 2.1 SC 1.4.11 asks **3:1** of a graphical object that
alone identifies a control, and this component's own docstring says the mark is exactly that.

**The ruling: the pill's chevron takes an existing token measuring ≥3:1 against the pill fill in
both schemes.** No new token is minted, and `chevronDisclosure` is not changed at its other sites —
there the mark sits on a full-width row with a trailing edge, so the layout is also saying "this
opens something" and the chevron is not carrying the claim alone. Here it is.

**Chosen: `textMuted`** — the pill's own label color.

| | chevron | capsule (`surfaceCard`) | ratio |
| --- | --- | --- | --- |
| light, was | `#B4BCA9` | `#FFFFFF` | **1.96:1** ✗ |
| dark, was | `#4A5A4C` | `#18251D` | **2.16:1** ✗ |
| light, now | `#535F4C` | `#FFFFFF` | **6.75:1** ✓ |
| dark, now | `#94A496` | `#18251D` | **6.06:1** ✓ |

Method: sampled from rendered device screenshots at the chevron's stroke core, not read off the
token table. The calculator was calibrated first by reproducing the reviewer's two published
numbers (1.96 and 2.16) from their sampled RGB before it was trusted on the new ones.

Choosing the label's own token, rather than any other passing token, has a second virtue: the name
and the mark become one object instead of a name with a decoration attached, which is what the
ruling above wanted the pill to read as in the first place.

#### What was weighed and rejected

- **Keep the button, fix its spacing.** Cheapest, and it addresses only fault 1. The owner named the
  button itself as the problem ("ugly"), not its margins.
- **Move the button into the header, beside the pill.** Two controls in C1 competing for a row that
  already has a title and, on screen 12, a back circle — and the Dynamic Type note in `ScreenHeader`
  records what that row does at AX5 when it is over-subscribed.
- **Make the whole provenance sentence tappable.** A sentence is not a control; it has no affordance
  of its own, and a 2-line tap target that looks like body copy is worse for everyone than a pill.
- **A filled or accent-colored pill.** Re-introduces fault 2 in a smaller box.

#### Scope — the two picker entry points deliberately left alone

The coarse-fix and out-of-range states keep their `Pick an area` / `Pick a city`
`SecondaryOutlineButton`s. Those screens name no area, so there is **no pill to make tappable**, and
the button there is the only thing on an otherwise empty screen rather than a second control beside
a first. The owner's complaint was about the `Change` button specifically. The rule that falls out
is one sentence: **the control is the name, so where there is no name there is no control.**

#### Accessibility

The pill carries the button trait and the **place name** as its label, with a hint naming the list
that opens — `AreaPickerCopy.changeAreaHint` / `.changeCityHint`. VoiceOver reads
`Sunset/Parkside, button, Opens the list of neighborhoods on this phone.`

This is strictly more than the retired control offered (`Change, button`), which is fault 3 fixed.

**Dynamic Type, and the wrapped pill.** The mark scales on the label's own curve (above). Alignment
is the other half: the radius fallback's pill (`Within a 15-minute walk`) wraps to two lines at
large type, and a centered mark then floats against the full height of the wrapped label, beside the
line break, touching neither line. `.firstTextBaseline` puts it on the first line at every size.

A `Shape` has no baseline, so SwiftUI would align its bottom edge. The `alignmentGuide` reports a
point half an x-height **below** the mark's center, so that lining that point up with the text's
baseline leaves the mark's center half an x-height **above** the baseline — the label's optical
midline. The half x-height is `CypressFont.body12HalfXHeight`, read from `UIFont.xHeight` of the
face that actually draws, and scaled on `.caption` like the mark itself.

**This was wrong in the first fix round and the correction is worth recording.** That version
returned the mark's plain center, which put the center *on the baseline* — a half x-height low —
while this paragraph and the code comment both claimed it was on the midline. Measured on a 402 pt
device at default type: chevron center `414.5` against a label baseline of `414`, i.e. **+2.33 pt
below the midline** and +3.00 pt below the capsule's own center. It traded a correct single-line
pill — every reader at default type, on both segments — for the correct wrapped one. Both cases are
required.

**Measured from rendered pixels, iPhone 16 Pro (402 pt), light.** Chevron isolated as the rightmost
ink cluster inside the capsule; baseline as the label's lowest ink row (neither `Western Addition`
nor `San Francisco` carries a descender); x-height top as the modal per-column ink top.

| case | chevron centre vs label midline |
| --- | --- |
| default type, Almanac — before | **+2.33 pt** (centre 414.5 on baseline 414) |
| default type, Almanac — after | **+0.00 pt** (centre 407.5, midline 407.5) |
| default type, City segment — after | **+0.00 pt** (centre 407.5, midline 407.5) |
| AX5, single line — after | **−0.17 pt** |
| AX5, radius fallback (wrapped) — after | **−1.83 pt** vs the *first* line's midline |

Against the capsule's own centre the mark went from +3.00 pt low to +0.67 pt.

**The wrapped case still rides the first line**, which is the property the baseline alignment exists
for: chevron ink spans y 1190–1233, inside line one's band (1158–1248) and outside line two's
(1295–1375).

**One honest limit:** XCUITest exposes an element's label, traits and value, and **not its hint**,
so `AreaPickerUITests` witnesses the trait and the label and cannot witness the hint. What is
checkable about the hint is checked in `AreaPickerTests` — that the two segments' hints differ and
each names its own list, which is the plausible failure (one pasted from the other, correct on the
segment it was written for and wrong on the other, with nothing on screen to contradict it).

#### Standing

**NOT SPECIFIED.** SCREENS.md §2 draws C1's trailing pill as a label and never as a control, so this
ships under DECISIONS constraint 21's delegated-authority pattern, with the owner's ruling above as
the mandate rather than as a proposal awaiting one.
