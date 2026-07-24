# Rulings

Five questions that were design's to answer and had no answer. On 2026-07-21 the project owner
delegated all five to me explicitly, in writing, and asked that a call be made on each. This file is
that call.

**These are rulings, not discoveries.** Everything in `ERRATA.md` is a conflict found between
documents that already existed. Everything here is a decision made where no document said anything,
under authority that was granted rather than assumed. Each entry says what it overrules, so that a
designer arriving later can find every place their intent was substituted for and reverse it in one
pass.

The distinction that governs the colour entries, carried forward from E8:

- a **transcribed** value is a hex read out of `SCREENS.md` — it may not be changed;
- a **derived** value was computed by the light→dark transform — it may be corrected;
- an **overruled** value was transcribed and is being changed anyway, under this delegation.

R1 is the only overrule in the app. It touches three tokens.

---

## R1 — The caption ramp is retinted, not reassigned (closes E106)

**The finding.** `text.faint` fails WCAG AA in both appearances: 2.90:1 on the screen and 3.16:1 on a
card in light, 3.42 and 2.98 dark, against a 4.5 floor for text. It is not one badge. It is every
mono micro-label, every timestamp, and every meta line in the app — 61 call sites across 24 files.
`text.faintAlt`, the footnote colour, fails the same way at 3.67 / 3.42.

**The ruling: change the token, not the call sites.**

E106 proposed the other fix — move every caption to `text.muted`, one rung up, which already clears
at 4.62. That is a 61-site edit that permanently collapses a four-rung ramp into three, and it leaves
`text.faint` in the file as a trap: the next screen to want a quiet label reaches for the token named
*faint* and reintroduces the defect. Retinting is one edit, keeps the ramp, and makes the failure
unrepresentable rather than merely absent.

**The ramp is re-spaced so all four rungs survive.** Lifting faint to exactly 4.5 would put it within
0.12 of muted, which is not a ramp, it is a rounding error with two names. So both move:

| Token | Was (light) | Target | Why |
|---|---|---|---|
| `text.faint` | 2.90 / 3.16 | **≥ 4.5 on both surfaces** | the floor for text, in both appearances |
| `text.faintAlt` | 3.67 | **≥ 4.5** | same |
| `text.muted` | 4.62 | **≥ 6.0** | so the rung above faint is visibly above it |

`text.body` (7.9–9.4) and `text.ink` (13.8–15.0) do not move; the ramp becomes 4.5 / 6.0 / 8 / 14,
which is roughly even in perceived lightness and legible at every rung. Hues are held: the retint
moves lightness in OKLCh and leaves chroma and hue where the designer put them, so the palette still
reads as the same palette. **The failing pair must be measured on the surface it actually sits on** —
faint on a card and faint on the screen are different measurements and both must clear.

**Two more pairs are fixed because meaning hangs off them.**

- The `est.` badge (C12) at 4.19 — a third of a point short, and D7 makes "estimated" the whole
  difference between a reading and a guess. Its partner `taped` reads at 6.08. A contributor who
  cannot tell the two apart cannot tell data from a guess.
- The C24 attention card border at 2.30 against a 3.0 floor. C24 is `surface.card` on
  `surface.screen` at 1.09:1 — the border is the *only* thing saying this card is different, which is
  exactly the case WCAG 1.4.11 is written for.

**Three pairs are left failing, deliberately, and the test keeps pinning them.**

- The 311 panel border (1.82 light). The panel has its own fill; the border is not what identifies
  it. House style, not a defect.
- The C10 locked glyph (1.84 / 2.12) and the C23 chart series on a dark card (2.53 / 2.27). Both are
  real, both are E8's to answer, and both are a *drawn* decision — a glyph and a data encoding — not
  a text ramp. They are the next thing a designer should look at and the first thing on their list.

Ratios stay pinned to ±0.05 in `ContrastTests` so that a number getting worse **and a number quietly
getting better** both fail. A silent improvement means someone changed a token without reading this.

---

## R1a — The same ruling, applied where E106 had not looked

R1 was written from E106's table, and E106's sweep did not cover everything the caption ramp is drawn
on. Implementing R1 turned up five residual failures. This amendment says what happens to each, so
that none of them is settled by silence.

**The line R1a draws: an accessibility floor justifies an overrule; a matching set does not.**

**Overruled, because they are the same failure R1 already ruled on.**

- **The forced-dark palette.** `Dark.textFaint` reads 3.44 / 2.99 on screen 04, which is dark by
  design in both appearances. `Dark.*` is verbatim transcription and was outside R1's list; it is
  inside R1a's. R1's argument was that the caption ramp is not one badge but every micro-label in the
  app — and a label legible when the *phone* is dark and illegible when the *screen* is dark is that
  argument failing on its own terms. Derived the same way, against the grounds screen 04 draws on.
- **The search placeholder.** `searchGlyph` at 3.95 on the search fill. It kept `faintAlt`'s retired
  hex through an alias, which made it the last thing in the app still wearing a value R1 withdrew —
  on screen 01, the default screen.

**Corrected, not overruled — which is a different thing and must stay labelled as one.**

- **The empty photo well** (screen 14). `text.faint` lands at 4.16 dark on `surfaceEmptyThumb`, and
  closing it *in the token* would put faint 0.042 from muted in OKLCh lightness — inside E8's own
  0.075 ladder step, which is the ramp collapse R1 refused. But `surfaceEmptyThumb`'s dark value is
  **derived**, and E8's standing rule is that a derived value may be corrected. So it is corrected,
  and it belongs with the derived tokens rather than the overruled ones. No designer is overruled
  here; a guess is improved.

**Left failing, on the record.**

- **`ctaDisabledLabel`**, an alias of faint, at 4.19 / 4.64. WCAG 1.4.3 exempts inactive components,
  and a disabled control that reads as strongly as an enabled one is a different defect.
- **The three light amber border weights have come apart.** C24's border is now darker than
  `borderAmberMid` and `amberChipSelectedBorder`, which were one hex with it before. This is correct
  under 1.4.11 and it is a visual change nobody drew. Design's to reconcile, and the likely answer is
  that the two chip borders follow C24 down.

---

## R2 — The heart comes off where it went on (closes E101)

**The finding.** A favourite can be written and cannot be removed. C8's `Favorite` cell is drawn once,
in one state; nothing in the mock set un-favourites a tree; `RootView` writes `isFavorite: true` and
never `false`.

**The ruling: C8's first cell gets a selected appearance, and a second tap removes the favourite.**

Of the two closures E101 offers — a selected state on C8, or a surface that lists favourites and can
remove one — this is the smaller and the more honest. A list is a new screen, and the authorization
that covered inventing *entrances* does not cover inventing screens. A state on a drawn component is
a variant of something the designer already drew.

What the selected cell is: the card fill takes the app's existing tinted green surface, the label and
border take `accent`, the border goes to the heavier hairline and the label from 600 to 800. **The
label does not change.** It says `Favorite` in both states because it is a noun naming the thing, not
a verb naming the next tap — `Unfavorite` would be a different word appearing under the same icon,
which is how a control starts lying about what it is.

> **Corrected while building this.** The clause above originally read "the heart glyph fills, glyph
> and label take `accent`". **C8 has no glyph.** Its icons are marked NOT SPECIFIED in §2 and again in
> §5's gap list, so all four cells are text, and there was nothing to fill. Adding a heart to one of
> four text cells would have been a drawn decision on the very component this ruling treats as
> already-drawn — constraint 21, arriving from the direction I was not watching. So the glyph is not
> built, and it is one line in `QuadActionRow.appearance` the day icons land.
>
> That absence is also why the selected state carries in **three** channels rather than one. With no
> glyph, hue alone would have been the whole encoding, which is E103's finding — a state conveyed only
> by colour — arriving by another road.

Three consequences, each of which reverses something E101 recorded as forced:

- **The write is no longer fire-and-forget.** E101 dropped its error because there was no state in
  which the screen could honestly report one. There is now: the state reverts.
- **The double-tap trick is retired.** Replaying one client UUID per tree existed only because a
  control with no on-state would otherwise queue one event per tap. With an on-state, the second tap
  is a *different statement* and needs its own key, or un-favouriting silently no-ops.
- **A memorial can still be favourited.** Settled under E89 and unchanged: the gate that refuses the
  heart also refuses removing it, which makes the toggle one-way again in exactly the place the
  record is most likely to matter to someone.

---

## R3 — Account deletion deletes what only the account could read (closes task #18)

**The finding.** DECISIONS §3.12 says deletion nulls `user_id` and severs the device link. Two tables
now hold rows owned exclusively by one or the other — `private_reminders` and, since E89, `favorites`
— under `CHECK ((user_id IS NULL) <> (device_id IS NULL))`. A row cannot survive both halves of that
sentence. Something has to give.

**The ruling: these rows are deleted, and the deletion copy says so.**

§3.12 anonymizes *contributions*, and the word is doing real work. A photograph, a measurement, a
check-in — these have value to the forest independent of who made them, which is the entire argument
for keeping them: the record outlives the account. A private reminder and a favourite have no such
value. Nobody but their owner can read them, and after anonymization nobody at all can — an
ownerless favourite is a row that no query returns and no person can remove. Keeping it is not
privacy-preserving, it is litter that happens to be unreachable.

So: anonymize what the forest keeps, delete what only one person could ever see. This is not an
exception to §3.12; it is what §3.12 means by *contribution*, made explicit.

**The deletion confirmation must enumerate both.** A person deleting an account should be told that
their reminders and favourites go with it, before it happens, in the same sentence that tells them
their observations stay. Deleting more than someone expected is the failure mode this ruling creates,
and copy is the whole defence against it.

---

## R4 — Screen 15 is not presented in the local beta

**The finding.** Screen 15 is the account ask. It is built, tested, and cannot sign anyone in: auth is
magic-link only (DECISIONS §3), magic links need a backend, and the beta has no backend.

**The ruling: it stays built and stays unreachable, behind a named constant rather than an omission.**

A screen that asks for an email address and then does nothing with it is worse than no screen — it
takes something from a person and gives nothing back, which is the one thing the privacy posture in
§3 exists to prevent. Presenting it "just to see the flow" costs a real email address.

The constant is `BetaCapability.accountsAvailable`, false, in one place, with this ruling cited beside
it. **A flag, not a deleted route** — a route commented out is indistinguishable from a route someone
forgot to write, and the next person to read `AppRouter` should be able to see that 15 exists, works,
and is waiting on a server rather than on an engineer.

Everything the account ask would have gated on stays device-scoped in the meantime, which is already
how favourites (E89) and private reminders (E23) work.

---

## R5 — The denominator is 215, and it stays 3%

**The finding.** E47 established that screen 08's species denominator is 215 — the true count of
distinct species in the neighbourhood — and not the 40 the mock's fixture implies. A contributor who
has met seven species therefore sees `7 of 215` and a progress ring at 3%.

**The ruling: no change. The number is right and the ring is right.**

The temptation is to find a friendlier denominator — species seen by anyone nearby, or a milestone
ladder where 7 is most of the way to 10. Both are mechanics that nobody designed, invented to make a
true number feel better. 3% of a neighbourhood's species is what one contributor has met, and 56 of
those 215 species are represented by a *single tree* in the whole neighbourhood.

That is not a failing grade. It is the product's actual thesis: the almanac (D1) exists to point at
coverage gaps, and a ring at 3% is the most honest possible statement that the gap is where the
interesting work is. A denominator chosen to flatter would quietly delete the reason the app exists.

If this reads as discouraging in the beta, the fix is copy around the ring, not arithmetic inside it.

---

## R6–R12 — the second delegation

The project owner delegated the six design questions left open after M5, and chose the moderation
route for screen 19. Same standing as R1–R5: made because nothing in the documents said anything, not
because the documents conflicted. That is the ERRATA/RULINGS split.

### R6 — screen 17's queue tiles name the kind in words, not in a new glyph

Visit and check-in draw the same tile, so a queue of four items says nothing about what is in it. The
tempting fix is a glyph per kind, and it is the wrong one twice over: SCREENS.md draws no such glyphs,
so inventing four is exactly what constraint 21 forbids, and a glyph that repeats a word is what E116
found the tab bar already doing — decoration a VoiceOver user has to be shielded from.

**The kind is written, using the mono section label the screen already uses.** Text cannot be
misread, needs no legend, costs nothing at AX5, and is the only version of this that is also correct
for someone who cannot see the tile. A glyph may be added later *beside* the word; it may not replace
it.

> **Already satisfied — no build needed.** Checked against the code before building, and the remedy is
> in place: `OutboxCopy.title` renders `"\(kindLabel(kind)) · \(treeName)"`, so the rows read `Visit ·
> Southern Magnolia` and `Check-in · Southern Magnolia`, and `kindLabel` names all six kinds. The
> shared `LeafGlyph` beside them is `.accessibilityHidden(true)`, so it reaches no assistive
> technology and adds no stop.
>
> The note this ruling came from — "visit and check-in indistinguishable" — was true only of the
> *glyph*, and the glyph is decoration the text already outranks. Giving each kind its own is exactly
> what the ruling above rejects. **R6 therefore stands as a rule for future rows rather than as work.**

### R7 — a vacant planting site gets a hollow ring, not the grey dot that means "removed"

C19 has no vacant-site pin, so 12,518 basins currently draw as the grey dot for a removed tree. That
is not a styling gap, it is the map asserting that something was there and is gone — the same lie
E107 and E113 spent two entries removing everywhere else. It is the last surface still telling it.

**A hollow ring: the existing pin geometry, outline only, no fill**, in the dashed-border family the
vacant-site screen and the empty photo well already speak (`borderDashedStrong`). Nothing is added to
the palette. An empty outline reads as "nothing here" without needing a colour to be learned, and it
cannot be confused with a filled dot at any size — which a second grey could.

### R8 — the two failing contrast pairs are fixed by lightness, and C23 gains a non-colour encoding

R1 fixed the text ramp and deliberately left the C10 locked glyph and the C23 chart series, both under
3:1, because a glyph and a data encoding are drawn decisions rather than a ramp. Delegated now, the
answer is R1's method: **lightness-only moves in OKLCh, holding chroma and hue**, so the marks stay
recognisably themselves.

C23 gets one thing more. If the series cannot all reach 3:1 by lightness without becoming hard to tell
apart, **the series carry a dash pattern as well as a colour**. A chart that distinguishes its lines
only by hue is unreadable to a colour-blind reader at *any* contrast ratio, so the redundant encoding
is owed regardless — and it is what makes the lightness moves affordable.

### R9 — one amber border colour

> **Corrected while building this.** The ruling above was written from a note saying "three amber
> border *weights* come apart". `CypressColor` says something more precise, and the correction
> strengthens the case rather than weakening it. They are three near-identical *colours* —
> `borderAmberSoft #EBD3A8`, `borderAmberStrong #E0B070`, `borderAmberMid #D9A05B` — not three line
> widths; the widths are a separate matter (1px, except 1.5px on the two hazard surfaces). The naming
> is itself drift: "mid" is the darkest of the three and "strong" sits between.

**Dark has already run this experiment.** All three derive to the single `#D99A4E`, because the dark
palette contains exactly two ambers (E8), so the amber pill, the selected amber chip and the 311 panel
are *already* indistinguishable by border in dark — and no entry in ERRATA records anyone missing the
distinction. If one amber is enough in dark, three in light is drift rather than design.

**They collapse to `borderAmberMid #D9A05B`**, which is 0.016 from the dark amber in OKLab. That makes
the light and dark borders very nearly the same colour, so the component stops changing character
between appearances as well.

**Not built yet, and deliberately last.** This is the only one of R6–R11 that is purely visual: it
fixes no lie and unblocks nothing, while changing the look of three components at once. Everything
else here earns its build first, and this wants the screens photographed after it — which is what
found E110 and E106.

### R10 — screen 12 gains the vacant-site block E115 proposed

The almanac can see 195,309 records and speaks about 182,791 of them. **It should say how many
planting sites in the neighbourhood are empty**, because that is the one true and useful thing the app
can say about the 12,518 it otherwise hides — and E115 established that hiding them is a status
predicate doing its job rather than a bug to widen away.

The copy inherits `SitePresentation`'s line and may not cross it: Cypress keeps the record of what is
planted, it does not plant. The block reports a count. It does not call for volunteers, promise a
replanting, or imply anyone has been told.

### R11 — every empty state names what would fill it, and who fills it

"No data" is a dead end. The screens that already do this do it well — `No measurements on this tree
yet.`, `Nothing has been recorded on this tree yet.` — and the ruling is that **this is the pattern,
extended to every screen lacking one**: say what the space is for and whose action puts something in
it. Where nothing the user can do would fill it, say that instead of implying they failed.

### R12 — screen 19 unblocks through moderation, and moderation is Phase 2

The owner chose the moderation route: designated community leads verify removals. That is the right
call and it is already the shape the data expects — an `appears_removed` observation raises a
`review_flags` row and deliberately does not mutate `trees.status` (BUILD-PLAN §6, DECISIONS §3.7),
and `VerificationState.orgVerified` is already defined as "confirmed by an org member with the steward
or coordinator role". The mechanism is built. What is missing is the confirming step and anyone with
standing to take it.

**It cannot ship in the local beta, and the blocker is R4.** A community lead has to *be someone*, and
`BetaCapability.accountsAvailable` is `false` — there is no sign-in, so there is no role to hold and no
identity to attribute a confirmation to. Building the confirm path now would produce a moderation
queue that nobody can be a moderator of.

So the order is: **accounts (R4 reversed) → roles → the confirm step → screen 19 becomes reachable.**
Until then screen 19 keeps the coverage it has (unit tests and a `ScreenSweepShots` fixture) and the
deep-link harness keeps no `memorial` case, for the reason E117 gives: the seed holds only `alive` and
`vacant_site`, and opening a memorial over a standing tree is the class of lie that suite exists to
catch.

**One consequence worth stating plainly.** Every `Removed?` check-in a beta tester makes raises a flag
that no one will ever action, and the app currently says nothing about that. Whatever acknowledgement
it grows must not overclaim — ARCHITECTURE §5.4 — and screen 06 already shows the standard to meet: it
says `the city has not been notified` in as many words.

## What is still design's, and was not delegated

- The rubric wording on screen 05 — whether `PRODUCT.md` or `SCREENS.md` holds the anchor sentences.
- Everything constraint 21 covers. The one-time exception for the six entrances (E98) is spent.
