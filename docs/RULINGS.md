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

> **Declined on inspection — the collapse is a trap (ERRATA E122).** Checked against the tokens before
> building, and there is no beneficial collapse to make. The tokens this ruling names — `borderAmberMid`,
> `borderAmberStrong` — have **zero call-site uses**, so collapsing them changes nothing drawn. The amber
> borders that *are* drawn include two that must not move: `amberAttentionCardBorder` was deliberately
> darkened by **R1** for contrast, and `hazardPanelBorder` is the 311 panel's whole boundary (pinned in
> `ContrastTests.knownFailures`). Collapsing either toward the paler ambers re-breaks what R1 fixed. And
> **dark is already collapsed** — every amber border derives to `#D99A4E` (E8). Executing R9 as written
> would trade a cosmetic tidy, invisible on non-adjacent components, for two weakened contrast decisions.
> So R9 is recorded and not built. The dead `borderAmberMid` / `borderAmberStrong` tokens are left in
> place rather than deleted, because a token nobody draws is harmless and removing it touches the gallery
> and the derived-token registry for no user-facing gain.

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

> **Already discharged, and the code says how — checked before building (like R6 and R9).** The app
> does not have one empty-state pattern, it has two, both deliberate and both documented:
>
> 1. **`§5.6` restrained reading** on the tab roots and every derived block: a block whose data is
>    absent is not drawn, and the screen keeps its chrome and an always-present honest footnote. This
>    is a decision recorded in ERRATA **E44** (the almanac) and **E48** (the grove), not an oversight
>    — the footnote is the empty state's sentence ("the only content the empty grove has, and the
>    sentence that makes the screen honest whatever else is on it").
> 2. **Explicit `…yet.` copy** on the two tree-scoped detail screens whose *whole* content is one
>    collection — `GrowthHistoryCopy.emptyState`, `ActivityCopy.emptyState` — where §5.6 would leave a
>    bare titled screen with nothing to explain it.
>
> R11's one testable core — *no section label may render over an empty section* ("a heading over
> nothing promises something") — **already holds in every feature**. Every micro-label is guarded by
> its content: `showsNearby` is `!nearby.items.isEmpty`, the almanac's season / composition / coverage
> blocks each guard on their own data, the grove's ring / callout / grid derive and vanish together.
> There is no void with a heading over it to fix.
>
> So R11 as written over-generalises: "name what would fill it" is right for a lone collection screen
> and wrong for a tab root, where §5.6 deliberately says less. Building naming-copy everywhere would
> **override E44 and E48**, not extend them.
>
> **The one residual with real merit, left to design.** On a device with no location fix the almanac
> and screen 07's `Near you` go quiet by §5.6 — and that is the one empty state a *user action*
> (granting location) would fill, which R11's own second sentence is about. E44 chose silence there on
> purpose ("a header that named an area we could not determine would be the screen's first lie"), but
> that reasoning is about the *header pill*, not about a one-line prompt beneath it. Whether a
> `Turn on location to see your neighbourhood` line belongs there is a genuine tension between R11 and
> E44, it is the only place R11 is not already discharged, and it is a drawn decision — so it stays
> with design rather than being invented here.

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

### R13 — SCREENS.md holds screen 05's vitality anchor sentences

The open question was which document owns the exact words under each vitality level on screen 05 (`1 ·
Severe decline · Mostly bare in season; over 50% dieback; survival doubtful`, and its four siblings) —
`PRODUCT.md`, which describes the rubric as a product concept, or `SCREENS.md`, which draws it.

**`SCREENS.md` holds them, and its wording is what ships.** They are *drawn screen copy* — a string
rendered on a control on a specific screen — and screen copy is `SCREENS.md`'s domain; `PRODUCT.md`
describes what the rubric is *for*, not the verbatim sentence a user reads. Where the two diverge, the
drawn text follows `SCREENS.md`, for the same reason constraint 21 exists: the app's words must be
traceable to the screen that draws them, not assembled from a higher-tier document that never intended
to be quoted letter-for-letter. `PRODUCT.md` stays the authority on the rubric's *meaning* — how many
levels there are, what each signifies — and a conflict there (a level added or redefined) outranks
`SCREENS.md`, because that is product, not copy. This splits cleanly: **meaning is `PRODUCT.md`'s,
wording is `SCREENS.md`'s.**

### R14 — screen 04 keeps its viewfinder at accessibility sizes and scrolls everything else

The open question was what screen 04 does at large Dynamic Type. `SCREENS.md` draws it at default type
only, so there was no specified variant, and ARCHITECTURE §5.8 says stop rather than invent one. This
is that stop, answered under the standing delegation.

**The finding.** At AX5 the screen cannot hold the viewfinder, the three framing chips, the note field,
the phenology chips and the Log visit button at once, and the framing chips end up *below the bottom of
the display*. So E152's feature — one camera session taking a full tree, a trunk and a leaf — is not
merely cramped at that size, it is **unreachable**. AX1 is already at the limit: the viewfinder is
squeezed to roughly a third of the screen.

**The ruling: the viewfinder shrinks to a fixed minimum, and the controls beneath it scroll.**

The reasoning, which is what should govern the details this entry does not fix. A person on screen 04
is *aiming a camera*, and nobody can compose a shot they cannot see — so the viewfinder must stay
visible at every text size, which rules out letting the whole screen scroll it away. Everything else on
the screen is a control, and a control reachable by scrolling **is** reachable, where a control below
the bottom edge is not. So the viewfinder keeps a floor and the controls get a scroll view. This
follows R11's principle rather than departing from it: R11 required every empty state to name what
would fill it, on the reasoning that a person must never be left unable to tell what the app wants from
them. A control that has silently left the screen is the same failure by a different route.

**Deliberately not fixed here**, because they are judgments better made against the running layout than
from a document: the viewfinder's minimum height (derive it from the capture's own aspect ratio or the
default-size proportion, not a round number), the size class at which the behaviour switches on (not
AX5 alone — AX1 is already cramped), and whether the shutter pins above the scroll or travels with it.
Whoever builds this draws the result in `SCREENS.md` as screen 04's accessibility variant, so the next
person inherits a spec rather than a precedent.

### R15 — the empty stat slot is a per-measure door; screen 11 carries the general one

The open question was where a general "add a reading" action belongs, and what an *empty* measurement
stat card on screen 03 means. `SCREENS.md` 03 draws four filled stat cards and lists
`DBH/Height cards → 11`; it specifies no add control at all. `SCREENS.md` 11 enumerates its parts —
two charts, a legend, a log, a footnote — and specifies none either. So there was no drawn answer,
ARCHITECTURE §5.8 says stop rather than invent, and this is that stop.

**The finding, which is two findings.** The project owner walked the app and reported both in one
sentence: *"'add a reading' is misleading because it's in a box for Height … and if you wanted to add
a reading for height on a tree that already had height you'd be confused how to do it."*

1. **The routing was simply wrong.** `Route.measure` carried a tree id and nothing else, and
   `MeasureDraft.kind` defaults to `.dbh`. Every entrance to screen 16 therefore opened on trunk
   diameter, including the empty `Height` card whose entire meaning is that this tree has no height.
   Somebody entering under the word `Height` and typing the number off the tape wrote a DBH in
   metres, and nothing downstream was positioned to notice: 16's sanity pill compares a draft against
   previous readings *of the drafted kind*, of which there were none.
2. **The general action had been drawn as a per-measure one.** An empty slot exists only while its own
   measurement is missing, so a tree carrying both a height and a DBH has no slot, and — because the
   slot was the app's only door to 16 — no route to the measure sheet from anywhere. The trees with
   the most growth left to record were exactly the trees with no way to record it. That is E74's
   original gap, a built screen with no entrance, reopened for the case that matters most, and it sat
   under 819 passing tests for weeks.

**The ruling: two entrances, each meaning one thing.**

**A stat slot is a door to its own measurement.** `Route.measure` carries a `MeasurementKind` and the
profile hands it the kind of the card that was tapped: `Height` opens 16 on height, `DBH` on DBH. Half
of this is just the bug, and it is recorded here anyway, because it is what makes the slot's framing
honest — once the Height card opens a height form, "Add a reading" inside a box labelled `Height`
means *add a height*, which is true — and because a designer reversing this entry needs both halves in
one place.

**The general entrance goes on screen 11, under the measurement log.** Those are E74's own words for
the control it declined to invent, which makes it the least-invented thing available. It draws
wherever 11 draws and the record accepts contributions, including over the empty state.

**What this overrules.** E74's resolution paragraph, in one clause: *"11 keeps its enumerated parts
and gains no control."* Everything else in E74 and E98 stands, including the empty slot on 03 and its
copy.

**Why E74's argument survives being half-reversed**, which is the part worth reading before reversing
this. E74 chose the profile over the history screen because "the tree profile is where every other
field action in this app starts" and "a contributor holding a tape has no reason to have opened a
history screen first." That is an argument about a **first** reading, and it still holds — the empty
slots are still on the profile, still the first thing a person at the tree sees. What E74 did not have
in view is the **repeat** reading. Somebody recording a second height on a tree that already has one is
by definition interested in the series, and 11 is the screen that draws the series; it is one tap from
the profile via `See every reading`. The two entrances split by what the person is doing rather than by
taste, which is why both can be right.

**Deliberately not changed**, so that the next reader does not re-open them:

- **The copy stays `Add a reading` in both places** — E74's own phrase, and already the string on 03's
  slot. `Add a height` was considered and declined: the box's label says `Height` two lines above, and
  a card that says the same word twice is arguing with nobody.
- **The general control opens 16 on DBH**, `SCREENS.md` 16 §2's drawn selection. It is the one
  entrance in the app that names no measurement, so it has none to carry, and 16's kind control is the
  first thing under its header.
- **Filled stat cards still open 11, not 16.** That is specified, and not this entry's to touch.

**Where to reverse it.** Both halves are decided in two properties, in two files:
`TreeProfilePresentation.StatDestination` carries the kind, and
`GrowthHistoryPresentation.offersAddReading` decides whether 11 draws the link. Deleting the second and
dropping the payload from the first restores the E74/E98 arrangement exactly.

### R16 — C20 gains a clear control and two ways out of the keyboard (task #110)

The open question was what screen 01's search bar does about being *left*. `SCREENS.md` §2 draws C20
as a pill with one glyph — the leading magnifier — and a placeholder; screen 01 lists the bar at
`top:68px` and says of its behaviour only that "search opens species/street/neighborhood search",
three lines above "**NOT SPECIFIED:** search results". Nothing anywhere draws a clear affordance, a
Cancel, or any dismissal of the keyboard. So there was no specified variant, and DECISIONS constraint
21 says stop rather than invent one. This is that stop, answered under the standing delegation.

**The finding, which is two owner reports about one control.** *"On search, it's possible to get stuck
in the search bar — cursor active and no way to exit out of keyboard"* and *"On search, I want a
little x in far right of bar to clear contents"*. The component was a `TextField` and a `Shape` in an
`HStack` with no clear button, no `submitLabel`, no `FocusState` and no `scrollDismissesKeyboard`,
and its only map caller added none of them.

**One of those two reports is literally true and the other is not, and the correction changes what
the fix is.** There was no clear control — that half is exactly as reported. There was no keyboard
*trap*: measured on the simulator against `SearchBar` exactly as it shipped, with no `FocusState`, no
`submitLabel` and no `onSubmit`, pressing return already resigned focus, because that is SwiftUI's
default for a single-line `TextField`. A test written to prove the return key had been fixed passed
against the unfixed component, which is how this was caught.

So the defect is **discoverability, not capability**, and it is still a real defect. The key that
worked is labelled `return`, which reads as "insert a newline" rather than "I am finished". Nothing
else on screen 01 dismisses the keyboard: tapping the map does not, because an `MKMapView` does not
resign anyone's first responder, and covering it with a transparent tap-catcher takes the pan and the
pinch with it — the map would stop being a map for as long as the keyboard was up. Dismissing on
camera movement was the other candidate and was rejected for the opposite reason: the keyboard
animating in is itself a layout change, so the bar would have thrown away focus on the frame it
gained it. Meanwhile the keyboard covers the FAB, the bottom card and the tab bar. A person who has
not been taught to reach for `return` is, for every practical purpose, stuck.

**The ruling: a ✕ at the trailing edge, and a visible way out of the keyboard beside the invisible
one that already worked.**

- **The ✕** appears only when there is text, sits hard against the bar's own 18 pt inset where the
  owner asked for it, carries the VoiceOver label `Clear search`, and has the 44 pt target
  ARCHITECTURE §6 requires — grown leftwards and outwards from the glyph rather than centred around
  it, and drawn as an overlay so that growing it cannot change the bar's ~45 pt height. It clears the
  text and **keeps focus**: clearing is the start of the next query far more often than it is the end
  of searching, and a ✕ that did both would do neither predictably.
- **The return key is relabelled**, `Search` instead of `return` (`submitLabel(.search)`). This costs
  no pixels and changes nothing about what the key *does* — it changes what it says, which is the
  whole of what was wrong with it. There is deliberately **no** `onSubmit` resigning focus: it was
  written, measured, found to change nothing, and removed. A line that appears to cause behaviour it
  merely coincides with is how a comment ends up ratifying a defect.
- **A `Done` above the keyboard**, because a relabelled key is still a key on a keyboard, and "no way
  to exit" is a report about what a person could *find*. It lives on the keyboard, so nothing screen
  01 positions moves.

The glyph is hand-drawn — a ring with an ✕ inside it, at C20's own 1.8 stroke and in C20's own glyph
colour, so the bar carries the same line weight at both ends. There are no SF Symbols and no icon
font in this app (`ShareDestinationGlyph` states the policy), and the ring rather than a bare ✕ is
what makes it read as a control: an unringed ✕ at 16 pt beside a 14.5 pt field is the weight of a
letter.

**What this overrules:** nothing. §2's C20 is a description of a bar that did nothing, and this adds
to it rather than contradicting it — the magnifier, the pill, the fill, the border, the radius, the
padding and the placeholder are all untouched, and the ✕ occupies space §2 left empty. Whoever draws
C20 next should draw the ✕ into it and give screen 01 a focused variant.

**Deliberately not decided here**, because they are judgments better made against a running screen
than from a document: whether the bar should also gain a Cancel *beside* it while focused (the iOS
convention, and a real layout change to screen 01 that a mock should make rather than an
implementation), and whether a query short enough to match most of the catalogue should narrow the
map at all — one character now matches 555 of 577 species, and the status line says so under E38
rather than the bar refusing to search. Both belong to whoever revisits screen 01's search surface.

## The owner's own decisions, recorded here so they are not re-opened

These are **not** delegated rulings — they were made by the project owner directly, and are written
down for the same reason the rulings are: so a later reader can find the decision rather than
rediscover the question.

**2026-07-26 · anonymised means anonymous, permanently (#74).** Deleting an account offers two doors,
and the default leaves records unattributed. Anonymising cleared `user_id` but kept `device_id`, so
D9's device-scoped ownership let `claimDevice` re-adopt those rows onto the next account signed in on
that phone — a real re-identification on a shared or handed-down device. The owner ruled for a
**tombstone**: rows anonymised by a deletion are marked and `claimDevice` skips them forever.
`device_id` is *not* cleared, because that would also break the legitimate D9 case of an unsigned-in
contributor keeping their own work. **The accepted cost, stated so nobody re-litigates it:** someone who
deletes an account and signs back in on their own phone does not get their own work back. The owner
weighed that against the re-identification risk and chose this. The deletion copy must say so.

**2026-07-26 · the species legend stays as it is (#96).** The legend renders as two rows of chips under
the search field and filter row, and at a dense local zoom it occludes a band of pins. The owner looked
at it on his own iPhone and ruled it acceptable: *"Legend is good for now."* Not fixed, deliberately.
If it is revisited, the options considered were collapsing to one row with a `+2 more`, tap to
expand/dismiss, moving it below the CTA, or auto-hiding shortly after the palette changes — and the
binding constraint is the widest chip, since DataSF's double-name format means `Sycamore: London Plane`
nearly fills a row on its own.

## What is still design's, and was not delegated

- Everything constraint 21 covers. The one-time exception for the six entrances (E98) is spent.

### R17 — screen 01's opening camera does not gain a test-only door, and the search UI tests read the viewport instead

Tasks #104 and #101. Not a design decision about anything a person sees — recorded here because the
obvious repair *would* have been one, and the next reader of `MapSearchUITests` will think of it
within a minute.

**The question.** `testTypingASpeciesNameNarrowsTheMap` needs a viewport that holds the species it is
about to search for. There are two ways to get one:

1. **Tell the app where to open.** `DebugDeepLink` already establishes the pattern — a `#if DEBUG`
   environment variable the UI test target sets, read at launch, compiled out of Release. A
   `CYPRESS_MAP_CENTRE=lat,lon` beside `CYPRESS_SCREEN` would pin screen 01's camera, and the test
   could then assert unconditionally and never skip.
2. **Ask the map what it is holding, and search for that.** The pins already name their own species
   once the map colours them, so a black-box test can read the viewport's census off the
   accessibility tree and pick its query from it.

**The ruling: (2), and (1) is deliberately not built.**

- **A camera door is product surface with a test's name on it.** `DebugDeepLink` earned its exception
  by reaching sixteen screens that a test otherwise cannot reach at all (E117); nothing here is
  unreachable. Screen 01 is the app's default screen and its opening camera is being actively
  reworked (task #115 — it should open on the person, or on a persisted camera). A second mechanism
  that overrides that camera at launch is a second answer to the question #115 is deciding, added by
  a test, in the same week.
- **Pinning the camera would only move the assumption.** A test that pins `37.78485,-122.4215` and
  searches `Platanus` still hardcodes a fact about the seed at a coordinate; it is the same defect as
  #104 with a longer fuse — it just fails on the day the inventory changes rather than on the day the
  machine's location does. Reading the viewport has no such expiry.
- **The cost is accepted openly: this test can skip.** Over a park, over the ocean, or over a street
  of one species, it reports "not checked here" rather than a green tick. That is the honest report,
  it names the census it found and the fix in its own message, and it has been shown firing. The
  alternative — a test that cannot skip because it forced its own preconditions into the app — is
  how this file got a guard that could not fire in the first place.

**What this does not decide**, and is left to whoever takes #115: whether screen 01 should have a way
to be opened on a given coordinate at all, for screenshots or for a share link. If one is ever built
for a product reason, these tests may use it, and should then assert instead of skipping.

### R18 — tree identity is qualified by id space, not by source; and `sf`'s prefix is frozen empty

**The decision.** `trees.uuid` stays `uuid5(NS_TREE, <seed string>)`, and the seed string becomes

```
ID_SPACES[<space>].identity_prefix + <the source's own id, verbatim>
```

An **id space** is the numbering scheme record ids are drawn from — not a city and not an
inventory. San Francisco's two inventories are one space. **`sf`'s `identity_prefix` is the empty
string and is frozen.**

**Why not qualify by source, which is what the task asked for.** Adding the inventory to the seed
string would give `city` and `datasf` different uuids for the same tree, and their uuids being
*equal* is a load-bearing property: it is what made the DataSF → city switch reversible with zero
uuids moved over 130,070 shared records (E156), and it is what keeps a photograph attached to its
tree when the seed is rebuilt from the other list. Two inventories of one numbering scheme must
collide. Two cities must not. The id space is the thing that distinguishes those cases, and the
source is not.

**Why the empty prefix is not a hack that needs tidying.** 145,837 shipped uuids are derived with
no prefix, and DECISIONS constraint 13 makes a tree's citable identity permanent. Any non-empty
`sf` prefix rewrites every public tree URL. So the empty string is a *value* — the historical one —
and the registry enforces that it is not a template: `require_id_space` rejects any space other
than `sf` whose prefix is empty or does not end in `:`, `source_ref` may not contain `:`, and
`check_id_space_registry` rejects two spaces sharing a prefix. A second city cannot be registered
into San Francisco's uuid space without a red test.

**What this settles for #107.** A new city is one `IdSpace` line, one `Inventory` line, and one
`InventoryAdapter` subclass. It cannot mint an SF uuid. It does not need a new namespace constant,
a migration, or any change to `InventorySource` on the Swift side.

**What it does not settle.** `trees.external_ref INTEGER UNIQUE` is still a global constraint on a
source-local id and must be widened before a second space is inserted; see the errata entry. That
is a schema decision for whoever does #107, not one taken here.

### A source states what a record is; the ingest may not infer it from a missing species

**The decision.** `InventoryRecord.kind` is required, has no default, and is one of `tree`,
`planting_site`, `not_a_tree`. Every record also carries `kind_basis`, which distinguishes "the
source published a field for this" from `inferred_from_absent_species` — the adapter guessing from
a hole. The build receipt counts them separately.

**Why it is a ruling and not just a refactor.** It costs something real. `not_a_tree` has no
`trees.status` to map onto, so `build_seed.STATUS_FOR_KIND` maps it to `alive` and the seed carries
a fact its own vocabulary cannot express. That mismatch is deliberate: the alternative is that the
fact has nowhere to be recorded at all, which is the state that produced #94 and kept it
unmeasured for as long as it existed. One dict entry with a comment beats an absence.

**What this rules out permanently.** No future source may describe a planting site by omitting a
species, and none may describe a tree that way either. `validate()` refuses a planting site that
names a species, refuses a blank string in any optional field, and refuses a non-positive `dbh_in`
— so a source's "not recorded" sentinel has to be resolved by the adapter that knows it is a
sentinel, and cannot arrive as a measurement.

**What it does not decide.** Whether the 1,777 inferred vacancies should become trees of unknown
species, and whether the 312 not-a-tree records should get a status of their own, be `removed`, or
be excluded from the corpus. Those change what the map draws and are #94's to settle. This ruling
only makes them countable and makes the schema that permitted them look wrong.

### R19 — a confirmed-dead tree says so in words; whether it gets its own drawn pin is still open


Raised by task #58 / ERRATA E170, which made `dead_reported` reachable from the app for the first
time. Two questions arrived with it. One is answered here; the other is deliberately not, and this
entry exists so the second does not get answered by accident.

---

**Decided: `dead_reported` shares the removed *drawing* and shares none of its *words*.**

The grey pin and the grey badge say "there is no living tree at this site", which is true of a
removed tree and true of a standing dead one. `MapPin.Kind` is a closed catalogue — its sixth entry,
the vacant-site pin, took RULINGS R7 — and `StatusBadge` has four colour pairs and no fifth. So the
drawing is borrowed and no new visual vocabulary is invented.

Every *word* is separate, and that is not a compromise:

- badge `Dead`, never `Removed`
- pin spoken as `Dead tree, still standing`, never `Removed tree, memorial`
- profile Callout saying a reviewer confirmed it and that it is still worth reporting
- queue row `Reported dead` / `Confirm dead`, beside the removal's own pair

The rule this encodes: **two statuses may share a drawing while sharing no sentence.** A reader who
sees only colour learns "not a living tree here", which is right. A reader who reads or listens
learns which of the two, which is what actually changes what they should do — a removed tree needs
nothing from anybody, and a dead one standing over a pavement needs reporting.

**Not decided: whether a standing dead tree deserves a pin of its own.**

There is a real case for one. A dead street tree is the highest-consequence record on the map, it is
the only grey pin you can still act on, and R7's argument for the vacant site — that borrowing
`.removed` made the map assert something untrue — applies here in a weaker form: the map is not
asserting removal, but it is declining to distinguish a hazard from a memorial.

It is left open for the reason E107 left the same half open: a new pin is a design decision against a
closed catalogue, and an errata fixing a data-layer defect has no standing to make one. E170 fixed
what the pin *says*, which needed no catalogue change; what it *draws* waits for whoever owns C19.

**If it is taken up**, the shape is `MapPinKind.kind(for:)`, which already switches
`case .deadReported, .removed: return .removed` — one line, and `MapPinCopy.deadReportedLabel` is
already the override that would move onto the new case's `accessibilityLabel`. What must not happen
is the reverse: routing `deadReported` to screen 19 to make the map tidy. That takes the REPORT
button off the one status where a hazard report matters most, and `ModerationTests` asserts against
it.

### R20 — San Jose is the first city through the contract, and `FACILITYID` is its identity

     parallel agent. Written for #107, the survey half. -->

### San Jose is its own id space, keyed on `FACILITYID`, and a source's asset id is what an id space is made of

**The decision.** San Jose is registered as `ID_SPACES["us-ca-sj"]` with `identity_prefix
"us-ca-sj:"`, and its `source_ref` is **`FACILITYID`** — verbatim, as a string. Its inventory is
`INVENTORIES["sj_street_tree"]`.

R18 settled that identity is qualified by id space and left open what an id space is *for a city
that is not San Francisco*. San Jose forces the question, because its Street Tree layer publishes
**three** ids that are each non-null and each distinct over all 344,879 rows (measured 2026-07-31),
so uniqueness does not choose between them.

**Why `FACILITYID`.** It is Esri's Local Government Information Model asset id: the id San Jose's own
asset records are keyed on and the one its CSV and GeoJSON extracts carry. 344,879 distinct values
over 344,879 rows, zero null, and no `:` in any of the 1,000 sampled.

**Why not `DAVEYID`.** It reads `MB 20140207121505` — a crew code and a collection timestamp from the
Davey Resource Group survey. It is an id **for the visit, not for the site.** A re-surveyed site gets
a second one; a tree planted after the contract has none the contractor ever issued. Keying identity
on it would make a tree's permanent public URL a property of when somebody happened to walk past it.

**Why not `OBJECTID`.** It is the feature service's row number and is the one id in the layer
documented to move on republish. DECISIONS constraint 13 makes a tree's citable identity permanent.

**Why not `INTID`.** `FACILITYID` and `INTID` hold the same number as a string and an integer, and
were identical on all 1,000 rows sampled. They are **one numbering, not two**, so choosing between
them is a choice of representation and not of space. The string form is taken because `source_ref` is
defined as the source's own id verbatim as a string.

**The rule this generalises to.** *An id space is the numbering an inventory's publisher keys its own
asset records on — not the numbering that is most convenient, most unique, or most numeric.* A
source may publish several unique ids and they are not interchangeable: one names the asset, one
names a survey event, one names a row in a response. Only the first is an identity. The test a new
source must pass is not "is it unique" but **"would the publisher still issue this id to this site
next year".**

**Why San Jose cannot collide with San Francisco, structurally rather than luckily.** `sf`'s prefix
is the frozen empty string, so an `sf` seed string is a bare `TreeID` and contains no `:` at all,
while every `us-ca-sj` seed string contains one at position 8 and `source_ref` may not contain the
separator. This matters because the two numberings **do** overlap: San Jose `FACILITYID` 3 and San
Francisco `TreeID` 3 both exist and are different trees in different cities. `require_id_space`
refuses an empty or unterminated prefix and `check_id_space_registry` refuses two spaces sharing
one; both refusals are pinned by tests that assert the reason.

**What this rules out.** No city may be registered into `sf`. No city may be given a space because
its id ranges happen not to have collided with San Francisco's yet — **Sacramento's `GISOBJID` is
eight digits and does not currently overlap, and that is not a reason to share a space.** A space is
shared when two inventories publish the same numbering, which in California is a property of San
Francisco publishing one asset register twice and of nothing else surveyed.

**What it does not decide.** Whether a source with no asset id at all should be ingested. Oakland
publishes only `objectid`, a row number in a 2013 extract; under the contract the honest handling is
`source_ref=None`, which makes `has_stable_identity` False and is a materially weaker promise.
Whether the app should carry rows with that weaker promise is a product question and is not settled
here.

### A source's own conventions are the adapter's to resolve, including when the source contradicts itself

**The decision.** When a source states the same fact twice and disagrees with itself, the adapter
**picks the field whose only meaning is that fact, drops the other, and counts the row.** It does not
average them, does not prefer the richer-looking one, and does not drop the record.

San Jose states vacancy in two places: `VACANTSITE` (`Yes`/`No`, which means nothing else) and
`NAMESCIENTIFIC` (which carries a taxon, a vacancy string, `Stump`, `Unknown`, or nothing). Measured
2026-07-31: **611** rows are `VACANTSITE = 'Yes'` and name a real taxon, **82** are `VACANTSITE =
'No'` and say `Vacant site`, and **3,666** are `VACANTSITE = 'Yes'` with a positive trunk diameter.

`VACANTSITE` wins for the kind, because it is the field with one meaning. The species is dropped on a
planting site — a planting site that names a species is one of the two records the contract exists to
forbid — and so is `dbh_in`, because a measured trunk in an empty hole is two unreconciled records
rather than a fact. Every one of those decisions increments a named counter in `adapter.stats`.

**Why it is a ruling and not just an adapter detail.** The counting is the load-bearing half. E169's
whole finding was that a defect nobody could count stayed unfixed for as long as it existed. An
adapter that resolves a source's self-contradiction silently is indistinguishable, from downstream,
from a source that never contradicted itself — and the next person to read the corpus has no way to
learn that 3,666 trunk measurements were discarded.

**What this rules out.** No adapter may resolve a conflict between two of its source's fields without
a counter naming it. No adapter may fill a field its source left empty. And no adapter may widen the
contract to accommodate its source: San Jose's `TRUNKDIAM = 0` on 72,142 rows is a hard `validate()`
failure until the adapter resolves the sentinel, and that is the contract working rather than an
obstacle to it.

**What it does not decide.** Which of San Jose's two statements is *right*. The adapter records that
they disagree and how often; reconciling them is San Jose's, and choosing what the map draws for the
611 is #94's.

### R21 — a control that acts on one record belongs on any surface where that record is the unambiguous subject


**Raised by:** #126, reopening #78. **Supersedes** the second half of E147's "what was not built".

E147 put the photo delete on screen 20 alone and gave one reason for keeping it off the other two
surfaces at once: *"a delete on the hero would act on whichever photograph the rule happened to
pick"*. That reason is sound, and it is a reason about **ambiguity of subject**, not about screen 20
being the home of per-photograph controls. It was then applied to the full-screen viewer, which has
no ambiguity of subject at all — it is handed one `photoID` and draws that photograph and no other.

The ruling, stated so the next control does not repeat this:

> A control that acts on one record may be placed on **any** surface where that record is the
> unambiguous subject — and should be, when that surface is where a person's gesture lands. It is
> withheld only where the surface would have to *choose* which record it means. "This screen is the
> canonical home for these controls" is not by itself a reason to withhold one; a canonical home is
> a claim about where a control can always be found, not a claim that it may be found nowhere else.

Two consequences worth naming:

**The hero on screen 03 keeps its exemption**, and now for a stated reason rather than by
association. The hero is whichever photograph `PhotoHero.choose` ranked first this frame, so its
subject moves under a vote. That is the ambiguity the rule is about, and it is real.

**Duplication of a control is not duplication of its logic.** The viewer drives the same
`TreePhotosModel` screen 20 drives, so "may this person delete this, and what does removing it cost
the tree" has one implementation and one set of words. A second control reached by a second gesture
is a convenience; a second answer to the same question is a defect waiting for the two to disagree.

**The general shape.** This project has now twice shipped something correct that nobody could reach:
E110's `Back` that was in the tree and could not be tapped, and this. Both passed their tests. The
common failure is testing that a thing *is* rather than that a person can *get to it*, and the
correction is a test that starts at a launch and taps its way in.

### R22 — at accessibility sizes the add-tree screen is a form with a photograph in it, not a photograph with a form under it


The open question was what the community add's photo well does when the frame it must be — 3:4, the
shape of the capture, fixed by E162 and derived from `Camera.captureAspectRatio` — does not fit on the
screen alongside the form it sits above. `SCREENS.md` draws no add-tree screen at all (the view's own
header says so), so there is no specified variant at any text size, and ARCHITECTURE §5.8 says stop
rather than invent one. This is that stop, answered under the standing delegation, against the running
app rather than from a document.

**The finding.** At the drawn size on a 390 pt phone the well took 83 % of the composer's scroll
viewport, leaving 105 pt into which the screen fitted a link, a sentence and the top half of the words
`Move the pin`. At AX5 the well was taller than the whole viewport, so the first screenful was one
clipped grey box and every field was below a fold nothing on the screen admitted to. The owner's
report — that it is not clear there is content below the photo — was an understatement of the AX5 case.

**The ruling, in two parts.**

**1 · A bound on the photograph takes width, never height, and never ratio.** The well is the frame of
the photograph it holds, so it is always exactly the photograph's shape; when there is not room for it
at the gutter's width it takes less width and is centred. This is the point E162 missed when it refused
a cap, and E162's reasoning is otherwise intact: a *height* cap on a gutter-wide well does return the
letterbox, and with a `.resizeAspectFill` preview it crops the crown off a street tree, which is the
defect E162 exists to prevent. A width cap does neither. Anyone revisiting this may move the share; the
one thing they may not do is bound the height or restate the ratio.

**2 · At accessibility sizes the well keeps its share of the viewport, and the form scrolls.** This is
R14's answer to the same conflict on screen 04, and it lands differently here because the screens are
different. On 04 a person is aiming a camera and the viewfinder must survive, so the viewfinder keeps a
floor and the controls scroll under it. On the add screen the photograph is one field of a form: there
is a library path and a shutter, the well is as often a *review* of a shot as a viewfinder for one, and
everything on the screen is already inside a scroll. So the well takes two thirds of whatever viewport
it has and no more, at every size — which at AX5 on a 390 pt phone is 91 × 116 pt.

**The cost of part 2, stated rather than buried:** a 91 pt-wide live viewfinder is not a viewfinder
anybody can compose a shot in. The alternative was refused because it is worse: give the well a floor
big enough to aim in and the AX5 viewport is entirely consumed by it again, which is the reported
defect, on the display of the reader least able to absorb it. **At accessibility sizes this screen is a
form with a photograph in it rather than a photograph with a form under it**, and the shutter and the
library are both a scroll away and both reachable. If that trade turns out to be wrong in the field,
the thing to change is the *screen* at accessibility sizes — a variant that makes the photograph its
own step — and not the share.

**Deliberately not decided here**, because they want evidence this ticket does not have: whether two
thirds is the right share at the drawn size or merely a defensible one (it was chosen so that the
remainder is a band of form rather than a clipped line, and looked at on the running app); whether the
accuracy chip, now pinned above the scroll so that the remaining third is genuinely below the
photograph, should stay pinned once the screen has more chips than one; and whether the AX5 layout
deserves its own drawn variant in `SCREENS.md` the way R14 gave screen 04 one. Whoever answers the last
of those draws the result, so the next person inherits a spec rather than a precedent.

---

### R23 — the map's filter is a conjunction, the species dimension *is* the legend, and the year control states its own blind spot

**Ticket #116.** The owner asked screen 01 for four narrowings, in stated order of importance: **Yours,
Favourites, species, year.** Design was delegated. This is what was decided and why, including the two
things that were deliberately not built.

---

#### 1 · The row is a conjunction, and `All` stops being a chip

SCREENS.md 01 §12 draws `All / In bloom / Needs care`, "single-select with `All` default". The four
new narrowings do not fit that shape, because **they are not alternatives to one another**. "My trees"
and "planted in the 2010s" are a question a reader can sensibly ask at once, and single-select would
answer the second by silently discarding the first — a control that undoes your last instruction when
you give it a new one.

So `MapFilter` is a struct of independent dimensions, all ANDed. Consequences that follow and are not
negotiable:

- **`All` is gone as a chip.** A chip meaning "no filter" has a selected state indistinguishable from
  the resting state of the row it sits in, and it cost a slot `Yours` needed. The un-narrowed map is
  now the row with nothing on, which is what `All` selected anyway.
- **Every chip is a toggle**, including the membership pair. A conjunction with no way to remove one
  term is a conjunction you can only escape wholesale.
- **A `Clear filters` chip appears only when something is on**, and it is also the button on the empty
  notice. Two ways out, both labelled.
- **`Needs care` and `In bloom` keep their places** inside the conjunction. They are the mock's own and
  they still mean what they meant. `In bloom` still matches nothing, because every `seasonal` in the
  shipped seed is `{}` and inventing bloom months is what BUILD-PLAN §15 forbids — that was already
  true and this ruling does not change it. *(→ Stale as of E189: the seed this bullet measured has
  been replaced, and 511 of 569 species now carry seasonal data. The bullet's reasoning stands; its
  factual claim about the seed does not. `MapConditionAvailability` now asks the seed instead of a
  document.)*

`membership` is single-select *within itself*: `Yours ∩ Favourites` is a set so small and so
unmotivated that offering it would be a control nobody wants. Tapping the other one swaps.

#### 2 · The species filter is the legend, made tappable — there is no species chip

This is the ruling's real content. The owner attached two constraints to the species dimension: the
filter and the legend "must agree with each other", and they "must not fight for the same screen
space" — the legend having covered the map once already (#96).

A species chip beside the legend would have been a second control naming the same four species in the
same strip of chrome: both constraints broken at once, and the agreement between them would have been
something to *maintain* rather than something true.

**The strongest available guarantee that two controls agree is that they are one control.** The legend
already names the ≤4 coloured species, already sits in the chrome, already costs the space it costs.
Tapping an entry narrows the map to that species; tapping it again clears; the selected entry takes the
filter row's own selected fill so the state is said in the language the chips beside it use. Zero new
screen space, and the two surfaces cannot disagree because there is one of them.

A species outside the four is reached the way it always was — typed into C20 — and `MapModel.speciesIDs`
**intersects** the two rather than letting either win. Typing "plane" and then tapping the London Plane
legend chip leaves London Planes; neither control silently undoes the other.

#### 3 · Yours and Favourites are id sets, not predicates, and they suspend A1

What this device has visited, photographed, checked in on, measured or added lives in `main`; the seed
knows none of it and no `WHERE` clause over `trees` could. So the set is resolved first
(`CypressAPI.mapMembership(_:)`, one read per press of the chip, not per pan) and rides on the viewport
the way `speciesIDs` already does — which also means a changed membership is a *different viewport* and
the existing fetch debounce sees it.

Three rules fall out and all three are load-bearing:

- **`[]` means "narrowed to nothing", never "not narrowed".** A reader with no favourites who taps
  `Favourites` has asked a question, and the whole city is not its answer. `nil` is the un-narrowed
  case. Collapsing the two anywhere between `MapModel` and the SQL shows every tree in San Francisco as
  though it were theirs.
- **No marker grid.** The 44 pt cell exists to bound an answer that grows with the viewport's area. A
  membership set does not grow — it is bounded by what one person tapped. Gridding it would thin a set
  that fits on screen twice over and make the map say "showing 12 of 31" about an answer it could have
  drawn whole.
- **A1's clustering is suspended, and only here.** Badges bound an unbounded answer; there is nothing
  to bound. Clustering would answer "where are my trees?" with a number the reader has to zoom into
  four times. This is a deliberate, argued deviation and it is narrow: a *year* narrowing still
  clusters, because it can still match 37,962 trees.

`Yours` unions the four contribution tables **plus `community_trees`** — a tree you added is the most
emphatically yours there is, and it is in none of the four. That arm carries no owner clause because
the table carries no owner columns, which is correct today (no sync brings anybody else's rows down)
and is flagged in the code as the thing that must change on the same day those columns arrive.

#### 4 · The year control is a decade, and it says out loud what it cannot judge

**Counted before it was designed, which was the instruction.** Against the shipped seed:
**145,837 trees, 37,962 carrying `planted_year` — 26.03 %.** Among the 133,424 living ones it is
28,725, or **21.5 %**. Distribution of the dated rows: pre-1990 7,742 · 1990s 8,746 · 2000s 10,134 ·
2010s 8,493 · 2020s 2,847.

Two decisions follow.

**Decades, not years.** The seed spans 1955–2026. Seventy-two options holding a citywide mean of 527
trees each is a control whose every setting is invisible in a viewport. Five buckets, sized off the
real distribution; the first is open-ended because 7,742 rows spread over 35 years do not split.

**The control states its blind spot every time it is on.** Roughly three trees in four are set aside
*before* the filter judges anything. Silence would make their absence read as an answer — "there are no
2010s trees here" — when the truth is "the city did not record when most of these were planted". Those
are different claims about the same empty patch of map and only the second one is ours to make. So
`MapYearFilterCopy.setAside` renders whenever a decade is chosen:

> About 3 in 4 trees have no recorded planting date—none of them can appear under a year.

**Deliberately not built: a per-viewport count of the undated.** "214 more trees here have no date"
would be the better sentence. Getting it honestly costs a **second full fetch of the same box with the
year predicate removed** — the map's hot path, doubled, on every pan while the chip is on — to produce
a caveat that does not change in kind as the reader moves. The proportion is a fact about the inventory
the map is drawn from, true on every screenful, and `MapFilterTests` pins it against the shipped seed
so a re-ingest that moved coverage fails the build rather than leaving the sentence lying. If somebody
later finds a way to get the count for free, take it; do not buy it with a second fetch.

#### 5 · The number over the map, and the two rules it sits between

The result line (`31 trees`) exists because a filtered map that says nothing about its own result is
asking the reader to count pins.

**D1.** The owner's brief draws the line precisely — a neutral count as a *filter result* is fine, a
count that reads as a personal total is not. The difference is what the number is *of*. `31 trees` is a
fact about the viewport and it changes when the reader pans, which is what makes it not a score.
`You have visited 31 trees` would be stable, about the person, and forbidden. So the noun is always
**trees**, the sentence never takes a second person, and there is no phrasing available in
`MapFilterCopy` that could say otherwise — a test asserts the absence of "your", "you have", "visited",
"contributed" and "total" across every value the line can take.

**E38.** The line reads `content`, never `pins`. The grid thins, so the drawn array can be a spatial
sample; `PinAnswer.matchesInView` is non-nil exactly when that happened, and the two cases render in
different words (`1458 trees—showing 151`). A page is not a total.

**And the line yields when the notice is already speaking.** Found by running the app rather than by
reading it: a `0 trees` pill sat in the chrome while `No trees of yours here` sat in the card below —
the same fact twice, weaker phrasing on top. The count now draws nothing when the map is empty.

#### 6 · The empty state (E126)

A filtered map with no matches says why, and how to leave. Both halves, and the second is the one that
gets skipped. The notice reuses `MapLocationNotice` — same slot, same card, same trailing button, whose
label was hard-coded to `Settings` and is now a parameter.

`Yours` and `Favourites` get **two** different reasons, because "none here" and "none anywhere" are
different facts and only one of them is fixed by panning. Telling somebody who has never hearted a tree
to "zoom out to look further" is advice to go hunting for something that does not exist — the dead end
D16 (b) names.

---

#### Deliberately not decided here

- **Whether the chrome is now too tall.** With a filter on and a legend showing, screen 01 carries a
  search bar, two wrapped chip rows, a result line and up to two legend rows. Each row earns its place
  and the legend rows are not new, but this was looked at on the running app and it is dense. The
  obvious next move — merging the legend chips into the filter row, now that they are both filters — was
  not made, because it would take the legend's job as a *key* (explaining pin colour when nothing is
  filtered) and fold it into a control row, and that is a change to #96's surface rather than to this
  one. Whoever takes it should measure the saved row against that loss.
- **Whether `In bloom` should survive.** It cannot match a tree in the shipped seed, and now that an
  empty result costs a notice card explaining itself, a chip guaranteed to produce one is closer to a
  dead end than it was when it merely drew nothing. Left alone because it is the mock's and because the
  curated species pipeline is what fixes it, not this ticket.
- **Combining two memberships.** `Yours ∩ Favourites` is refused above on the grounds that nobody wants
  it. That is an assertion about readers, not a measurement.

---

### R24 — a seed row must carry its source's own id, and a rule written over one city's vocabulary does not run against another's

Two decisions, taken while ingesting the second city (#129, ERRATA E176). They are one entry because
they are the same mistake seen from two sides: **San Francisco's arrangements had become the
framework's, invisibly, by being the only ones there had ever been.**

---

#### 1. `trees.external_ref` is `NOT NULL`, so a source with no id of its own cannot be a seed row

**The decision.** With uniqueness moved to `UNIQUE (id_space, external_ref)`, `external_ref` is
declared `NOT NULL`. `build_seed.emit()` stops the build, loudly, on any record whose
`has_stable_identity` is False, rather than writing a row with a NULL ref.

**Why NOT NULL rather than the nullable column the old schema had.** SQLite treats NULLs as distinct
in a unique index. A nullable `external_ref` would let every identity-less row through the constraint
the column exists to enforce — and it would do so silently, which is worse than the old
`INTEGER UNIQUE`: that at least failed at the first collision.

**What this rules out, and it is a real cost.** `InventoryRecord.source_ref` is optional by design.
The survey found a source that needs it: Oakland's Socrata dataset publishes no id but `objectid`, a
row number in a 2013 extract, and E172 records that the honest adapter passes `source_ref=None` so
`has_stable_identity` reads False. **Under this ruling Oakland cannot be ingested into the seed.**
That is stated as a limit rather than hidden as a crash: the contract can still represent such a
record, `build_seed` refuses it with a sentence naming this ruling, and whoever wants Oakland has to
decide what a seed row's identity is when the publisher issues none — a lineage key, a coordinate
hash, or a `has_stable_identity` column beside the ref. **Do not resolve it by making the column
nullable again.**

**Why not store the qualified string `us-ca-sj:3` in one column instead.** It makes "which space is
this row in" a parse rather than a column, and the id space is a thing the receipt, the contract test
and the UI all need to name. Two columns and a composite unique index cost one integer of index width
and answer the question directly.

---

#### 2. `LandContext.inferred(from:)` is San Francisco's rule, and it now refuses to answer for anywhere else

**The decision.** `LandContext.inferred(from:idSpace:)` returns nil for any `idSpace` other than
`sf`. `Tree` carries `idSpace`; nil means "the record does not say", which is how every seed built
before the v14 pass reads and is correct for those files.

**Why it is a ruling and not a bug fix.** The function did not crash or throw against San Jose. It
answered — for all 52,788 rows, confidently, and wrongly. 48,036 of them resolved to
`.privateProperty` because San Jose's `OWNEDBY` says `Private` where San Jose's model is that the
*adjacent owner maintains* a tree standing in the public right-of-way. Not one row of a layer called
*Street Trees* resolved to `.street`. The function's own doc comment already warns about exactly this
error one column to the left — it is the reason `qLegalStatus` leads and `qCaretaker` only fills in —
and the warning did not generalise because nothing had ever asked it to.

**Why nil and not a San Jose branch.** Writing one would be a design decision taken in passing, on a
vocabulary nobody has studied, inside a change about schema. And the branch somebody would write is
probably the wrong one: `GROWSPACE` (`Park Strip`, `Well/Pit`, `Median`, `Tree Lawn`) is a far better
signal for where a San Jose tree stands than `OWNEDBY`, and choosing between them deserves its own
look. Meanwhile nil draws nothing, which is what E9 already established for a species with no sourced
leaf retention: **absence renders as absence, and a default is the bug.**

**The rule this generalises to, and it is the point of the entry.** *A derivation over a publisher's
own vocabulary is qualified by the id space it was written for, and must decline outside it.* The
test a shared function has to pass is not "does it return something sensible for the new source" but
**"was this rule written from this publisher's documentation".** If it was not, it does not run. The
merged national inventory D16 describes is a table of many publishers' vocabularies, and a rule that
silently spans them produces confident wrong answers at exactly the scale the product is for.

**What it does not decide.** How San Jose's land context *should* be read, whether `site_type` should
carry the answer instead of being derived per city, and whether the six `city_record` columns —
documented as DataSF's `qLegalStatus`, `qCaretaker`, `PlantType`, `PlotSize`, `PermitNotes` — should
be holding another publisher's differently-meaning columns at all. That last one is the deeper
question and `SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS` is where it lives.

### R25 — screen 01's search bar drops a list of species, and the list says what it is a page of (task #109)

---

**What was already specified, quoted rather than summarised.** `SCREENS.md` §2 draws C20 as a pill
with a leading magnifier, a placeholder and nothing else. Screen 01 lists the bar at `top:68px` as
item 11 of its structure, says of its behaviour only that "search opens species/street/neighborhood
search", and then, three lines later under **States/variants**, says:

> **NOT SPECIFIED:** search results, zoom controls, empty/no-GPS state.

So screen 01 specifies that the bar searches species and specifies **nothing whatever** about what
comes back — no list, no rows, no dropdown, at any text size. DECISIONS constraint 21 says stop rather
than invent one. This is that stop, answered under the standing delegation.

**The finding, which is one sentence from the owner.** *"I think it should surface drop downs with
species (as you type)."* What the bar did instead: typing narrowed the map in place and drew a status
line under the chips (E134, and `MapSearch` argues at length why there is no results *screen*). A
person typing `cypr` got a map that changed shape and no way to find out what it had changed to.

**Two rulings already stand on this control and neither is disturbed.** R16 (task #110) gave C20 the
✕ and the `Done`; both are untouched, and the ✕ still clears without dismissing the keyboard. E165
(task #108) made the catalogue match a word anywhere in either name with a rank; no matching is
written here at all — the list is a second reading of the page that call already returns.

---

#### The ruling, in six parts

**1 · The list is in the flow between the bar and the filter chips, not an overlay over them.**

The obvious dropdown floats. Floating is wrong twice. An overlay leaves the chips underneath
*reachable* by an assistive technology while invisible to a sighted reader — the covered-but-hittable
failure `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists to catch, arriving through
a different door. And it puts the rows somewhere other than immediately after the field in the element
tree, which is exactly where a VoiceOver reader who has just typed goes looking for them. In the flow,
the chips move down and stay real, and the swipe order is field → suggestions → chips → status line,
which is the order the words are in. `MapSuggestionUITests` asserts both halves: the chips move rather
than being covered, and they stay hittable.

**← CORRECTED 2026-08-01 (task #143; the measurement is ERRATA E183 §3).** The last two sentences
overstated what the layout delivered. Being in the flow made the *geometry* right — the chips move
down and stay hittable, which was asserted and true — but the swipe-order claim was written from the
view code's order, not from the tree, and the tree exposed something else: the suggestion rows
arrived **after** the chips, and the bottom chrome plus the whole tab bar arrived **before** the
field's own ✕ (a consequence, in part, of this very ruling's block reorder in part 6, which applies
the bottom block first so the top draws over it — drawing order and reading order want opposite
arrangements). The stated order is now true and is *declared* rather than inherited: screen 01's
chrome carries explicit `accessibilitySortPriority` values — the top block over the bottom block
over the tab bar, and within the top block the field, then the suggestions, then the chips, then
the status lines, then the legend. Note the chips are #145's row by the time this lands (`Yours ·
In bloom · Needs care · More filters`), so the order the priorities pin is over that row.

**And the correction carries its own caveat, measured the hard way.** A swipe-order test was
written against E183 §3's own instrument — the order `app.buttons` hands back — run red against
the pre-fix tree, and then run against the fixed tree, where it returned the *identical*
24-element order: that enumeration violates the view hierarchy, geometry and creation order at
once, and does not move under sort priorities at all, so it is XCUITest's internal order and not a
listener's swipe order. (E183 §3's listing already disagreed with its own prose — `Clear search`
sat before the four tabs in it.) Asserting the reading order through that channel would be E183
§4's mistake, so no test claims it; the fix stands on Apple's documented contract for
`accessibilitySortPriority`, and **verification with VoiceOver on the physical phone is owed**.
The paragraph above is otherwise undisturbed; nothing else in this ruling moves.

**2 · Six rows, and under them — never inside the scroll — a sentence about the rest.**

Not `MapSearch.speciesLimit`'s 100, which is the right number for narrowing a *map* — every extra
species there is another pin the reader might be hunting and nothing is read in a list. Not
`SpeciesPickModel.resultLimit`'s 25 either, which is the right number for a screen whose whole job is
the list and which may scroll as long as it likes. This list floats over the map that is answering the
question, so every row it adds hides some of the answer.

**Measured on an iPhone 16e rather than estimated:** a two-line row is about 79 pt, so six of them are
around 480 pt — more than the cap allows, which means five and a bit rows are drawn and the part-row
at the cut is what says the list scrolls. That is a better dropdown than six rows exactly, and it is
not what this ruling first assumed; the assumption was "about a third of the display", and the running
app said otherwise. The number stayed at six because the cap, not the count, is what governs how much
of the map is hidden.

**3 · A page is not a total, and the list may not print a number nobody counted (E38).**

This is the part of the ticket most likely to be got wrong and it is the reason `Remainder` is a type
rather than a comment. E165 made the 100-species cap **routine**: `a` prefix-matched 97 species before
that change and *contains*-matched 555 after it. So the dropdown is a page of a page. Three states,
and the third is the whole point:

| state | when | what it says |
|---|---|---|
| `.none` | every match is on screen and the catalogue's answer was not itself a page | *nothing* — the list is the answer |
| `.exactly(n)` | more matched, and the catalogue counted them all | "Showing 6 of 21 matching species. Keep typing to narrow it." |
| `.atLeast(n)` | the catalogue returned a full page, so the total is unknown *and unknowable from here* | "Showing 6 of at least 100 matching species. Keep typing to narrow it." |

`atLeast` claims the weaker of the two available sentences for the same reason
`MapSearch.Narrowed.isTruncated` does one level up: "at least 100" is true when exactly 100 matched
**and** when 555 did, and the reverse is not. A caller that flattened the two cases into one would
print a total the app has never counted. The sentence names the way out — a list that says "there are
more" without saying how to see them has told the reader they are stuck.

**And the sentence is pinned under the scroll rather than being the last row of it.** It began as the
last row, on the reasoning that a reader who hears the rows should hear what they are a page of in the
same sweep. Typed into the running app, `a` drew six rows, filled the cap exactly, and put
`Showing 6 of at least 100 matching species` **below the fold** — E38's own defect, reproduced one
level down by the change written to prevent it. It is now inside the card and outside the scroll:
still one sweep for VoiceOver, and never scrollable away, because the one sentence that says the list
is a page cannot be a thing you have to scroll to find.

**4 · No matches draws no list, because the sentence for that state already exists thirty points
below.**

E126 requires a surface with nothing on it to say why, and this obeys it by *not* adding a second
voice. `MapSearchCopy.status` has printed `No species matches “sycamore”` since E134, in a line that
is on screen for exactly this state and no other. A no-match row in the list as well would put two
spellings of one sentence on one screen and leave the reader working out whether they were being told
two things. The unit suite pins the two halves together in one test, so an empty list is only ever
acceptable while that line exists.

**5 · A row is two names and nothing else.**

Common name in the serif list face, scientific name in the italic serif beneath — the same pairing
`SpeciesPickView`'s row and `SpeciesTile` already draw, so a species looks like a species everywhere
in this app rather than looking like a search result here. A species with no common name (59 of the
seeded 569 have none, E9) shows its scientific name once, on the first line, and no dangling comma in
the VoiceOver label.

Two things were considered and refused. **A thumbnail:** C22's gradient is derived from the name
rather than photographed, so it would add four colours over a map whose own species palette is already
four colours, for no information. **A count of trees:** a per-species count is a read of a
195,309-row table on the typing path, which `TreeQueries` forbids outright — and a count of what is
*in view* is not the same number as a count of what is in the city, which is E38 again, one row
further down.

**6 · At accessibility sizes the list keeps a share of the display and scrolls; it does not shrink.**

At AX5 a row is a wrapped paragraph rather than two lines, so six of them are more than the whole
display. The list takes at most **half** the height it was given and scrolls inside that — R14's
answer on screen 04 and R22's on the add screen, applied a third time and for the third different
reason. Dropping to fewer rows at large sizes was refused: the reader who most needs the names spelled
out would get the fewest of them, and the remainder sentence would then have to count *two* different
truncations. The cap is a `ScrollView`'s `maxHeight` and deliberately **not** `.clipped()`, which has
clipped drawing without clipping touches on this project before and left a control reporting
`isHittable` while answering nobody.

**Two costs of part 6, stated rather than buried.** At AX5 on a 390 pt phone the card is most of the
usable display: about one and a half rows of scroll, plus a four-line remainder sentence that is not
allowed to be cut. And the filter chips, pushed down by a card that tall, land behind the keyboard for
as long as the list is open — visible again the moment it closes, which is enough on a screen where
the reader is currently typing a species name rather than filtering by bloom. Both were looked at on
the running app.

**One thing outside this ticket had to move for part 6 to be true, and it is worth naming.** Screen
01's chrome is two absolutely positioned blocks, and the bottom one — recentre, FAB, tree card — was
applied *after* the top one, so it drew over it. At the drawn size the two never overlap and nobody
noticed. At AX5 with the list open, the FAB sat squarely over the sentence that says the list is a
page: `Showing 6 of at least 100 match……. Keep ty…… it.` The blocks are now applied in the other
order, so the chrome the reader is typing into outranks the control they are not. Nothing inside
either block changed.

---

#### What choosing a row does, and why it is the opposite of the ✕

Tapping a suggestion pins the map to **that one species**, writes that species' name into the field,
closes the list, and **dismisses the keyboard**.

The pinning is the ticket's own sentence — "tapping one selects that species rather than leaving the
raw typed string in place" — and it is not cosmetic. Typing `cypress` narrows to the six species whose
names contain the word (E165). Picking `Monterey Cypress` off the list is a statement about one of
those six, and the map must stop showing the other five. The species set is therefore pinned rather
than re-derived from the field's new text, which would resolve `Monterey Cypress` back through the
catalogue and could pick up anything else containing the phrase. A subsequent keystroke releases the
pin, because at that moment the field no longer names the chosen species and a map still claiming it
would be saying something the field contradicts.

The keyboard is the deliberate contrast with R16. The ✕ clears and **keeps** focus, because clearing
is the start of the next query far more often than it is the end of searching. Choosing is the
opposite act: the reader has said which tree they meant, and the thing they asked for is the map that
the keyboard is covering. So the same bar now has one control that keeps focus and one that gives it
up, and the rule that tells them apart is whether the act ends a query or begins one.

`SearchBar` gains an **optional** external focus binding for this, and R16's argument for owning the
`FocusState` internally is untouched: it is `nil` at three of the four call sites and they are
unchanged. Screen 01 is the one caller that has to *read* focus, because a dropdown belongs to the act
of typing and must go when the typing stops.

---

#### What a VoiceOver reader hears

A list that appears under a field is a classic trap — the rows are drawn, are visible, are hittable
with a finger, and are somewhere a swipe never reaches. Four properties, all asserted by a launched
app because SwiftUI builds no in-process accessibility tree (E116):

- the rows are **buttons**, immediately after the field, in the swipe order;
- each row is **one element carrying both names** — `Monterey Cypress, Hesperocyparis macrocarpa` —
  rather than two elements that make a reader swipe twice for one species and hear the latin name as
  an orphan;
- the list is a **container with its own label**, `6 species suggestions`, so a reader navigating by
  element is told a list arrived under the field they are still typing into;
- the E38 sentence is **inside that container**, so the reader who hears the rows hears what they are
  a page of in the same sweep, and so it scrolls with them rather than being the one thing that never
  moves.

---

#### What this overrules

Nothing. Screen 01 named search results as unspecified and this fills that hole; §2's C20 is untouched
— the magnifier, the pill, the fill, the border, the radius, the padding, the placeholder and R16's ✕
all stay exactly where they were. Whoever draws C20 next should draw the list into screen 01 as a
variant, at the drawn size and at AX5, so the next person inherits a spec rather than a precedent.

#### Deliberately not decided here

- **Whether the list should offer anything that is not a species.** The placeholder stopped promising
  street and neighbourhood search under E134 because the bar cannot do either, and both are
  `Tools/build_seed.py`'s work before they are the client's. When they arrive, a mixed list needs
  section headers and this ruling does not design them.
- **Whether choosing should also move the camera.** Picking `Monterey Cypress` in a viewport holding
  none of them currently narrows the map to nothing and says `No Monterey Cypress in view`, which is
  honest and is also a dead end. Offering to fly to the nearest one is a real feature with a real
  question behind it (nearest to the camera, or nearest to the reader?) and it is not this ticket.
- **Whether the debounce should be shorter for the list than for the map.** They share one 300 ms
  debounce today because they share one read, and a list that raced ahead of the map would offer rows
  for a narrowing that had not happened. If the list ever feels slow, the thing to measure is whether
  577 species can answer on a shorter debounce than 195,309 trees can — not whether to add a second
  query.

---

<!-- Written for #129, the ingest half. Append to docs/RULINGS.md as R24. Do not renumber. -->

### R26 — adoption is a private commitment to a tree, not a claim on it

The owner asked for adoption on 2026-07-27: *"Self verified, and just means you get reminders to water
it, and updates when others take care of or record observation about it."* On 2026-07-31 they confirmed
the reading below and asked for it to be built.

**What this overrules, stated plainly rather than folded in.** `DESIGN.md:155,205` and
`SPEC-PHASE1.md:19` both put adoption and watering reminders *out* of Phase 1, deliberately. This is the
owner overruling their own scope, which is theirs to do; it is recorded here so that a reader who finds
the old lines knows they were superseded on purpose and by whom, rather than drifted past.

**1 · Adoption is self-verified, and therefore asserts nothing to anyone.** It confers no authority, no
priority, and no standing over another contributor. It does not gate, moderate, or outrank anybody
else's observations of the same tree. Concretely: **more than one person may adopt the same tree, and
this is a feature.** Exclusive adoption would turn a quiet commitment into a land grab, and a scarce
public claim is the exact shape D1 exists to keep out of this app — the competition would simply move
from a leaderboard to the map. A tree with four adopters is a well-loved tree, not a conflict.

**2 · The adopter is never named, to anyone, anywhere.** D11 is unconditional on this point and nothing
here softens it. It follows that *"updates when others take care of it"* must arrive **unattributed** —
"someone recorded a watering", never a name and never a stable pseudonym, since a pseudonym plus a fixed
location is an identity. `User.publicAttribution` cannot be turned on anywhere today (E100), so there is
no path by which this leaks; the constraint is written down here so that whoever *does* build
attribution knows adoption is not covered by it.

**3 · A reminder is an offer, never a debt.** Watering reminders mean local notifications, permission,
and a scheduling model — a genuinely new subsystem, and the first in this app (there is no
`UNUserNotification` code at all today; `PrivateReminder` is a note, never scheduled). The design
constraint that matters is not technical: **a missed reminder must leave no record.** No streak, no
lapse, no "you have not watered this in 3 weeks", no count of waterings performed, and nothing on the
tree or in the grove that a person could read as their own score. D1 forbids counting a person's
actions, and a reminder subsystem is the easiest place in this codebase to violate it by accident,
because guilt is the default idiom of every reminder app. The cadence is the adopter's to choose and to
silence, and silencing it is not an event either.

**4 · Adoption is device-scoped, like every other ownership fact here** (D9), and it ends the way a
favourite does — with a real off state that leaves nothing behind (R2). Un-adopting is not a failure
state and generates no note.

**Deliberately not decided here:** whether adoption belongs on the tree profile, in My Grove, or both;
what the notification actually says (it should carry the tree, not the obligation); and whether
seasonal watering cadence should follow the species' own phenology data, which is in the schema and
would be the honest answer, or a flat interval, which is the shippable one. Whoever answers the last of
those should say which they chose and why, because a flat interval that pretends to be seasonal is
worse than one that admits it is flat.

### R27 — a tree can be beloved without anyone being ranked for loving it

The owner asked, on 2026-07-27, for *"hand-picked great trees, as many city websites feature these, and
also a place to view a neighborhood's most beloved trees (most favorites? Most photos?) but without
turning the view into a leaderboard or score."* They named the tension themselves. This is the answer,
confirmed by them on 2026-07-31.

**The two halves are separable and only one of them is hard.**

**1 · Great trees are editorial, and San Francisco publishes a real list.** The city's own Landmark
Trees are a curated set with a public source, which makes this the same kind of work as the curated
species field guide (#6): content, not mechanism. It ships first because it is separable and because it
is the visible half. Constraint 15 governs it — do not invent botanical or civic content; a landmark
tree's designation comes from the city or it is not stated.

**2 · "Most beloved" is answered by moving the count off the person and onto the tree.** D1 forbids
counting a person's actions; it does not forbid a tree having properties. The distinction is not a
loophole, it is the whole design: *how many people know this tree* is a fact about the tree, and no
individual is nameable, rankable, or scoreable through it. Three rules make that real rather than
rhetorical:

- **Belovedness is a state, not a position.** A tree is beloved or it is not. There is no first, no
  order, no number shown, and no "top ten". This is the same move D1 made on the almanac.
  **← SUPERSEDED the same day by R27.1 below. The owner overruled it. Do not build to this bullet.**
- **It has a floor, and the floor is a privacy mechanism as much as a cold-start one.** DECISIONS
  already sets the precedent — caretakers are shown only at ≥3 distinct people. Favourites are private
  (R2, D11), so a threshold of one would publish a private bookmark and a threshold of two would make
  it inferable by anyone who knows they are the other. The floor must be high enough that no individual
  is recoverable from the state.
- **The set is shown unordered and rotating, not ranked.** A neighbourhood's beloved trees is a handful
  of trees to go and see, drawn from those over the floor, and the order carries no meaning. If the set
  is larger than the view, it rotates rather than truncates to the "top" — E38 applies, and a page is
  not a total.
  **← SUPERSEDED the same day by R27.1 below. The owner overruled it. Do not build to this bullet.**

**What this costs, stated rather than buried:** the owner asked "most favorites? most photos?" and the
answer is neither, in the superlative sense. There is no "most". A reader who wants to know which tree
in the Mission is the single most loved will not find out, and that is the intended outcome, because
every mechanism that answers it is a leaderboard wearing a different noun.
**← This paragraph is the part the owner rejected, and they were right. See R27.1.**

**Deliberately not decided here:** the numeric floor (it wants the real distribution of favourites per
tree, which nobody has looked at yet — count it before choosing it); whether photographs and favourites
should count toward the same state or two different ones; and whether "neighbourhood" here means the
analysis-neighbourhood geometry already in `Fixtures/raw/sf_analysis_neighborhoods.geojson` or the
viewport the reader is looking at.

### R27.1 — trees may be ranked; people may not. The owner overruled R27's second half, and the distinction it was missing is whose actions are being counted

Recorded 2026-07-31, hours after R27, at the owner's direction: *"I DO want people to be able to find
the most loved tree in the mission. No need to know which has most photos, etc. But part of the point
of the app is to bring people TO trees, and knowing which ones are beloved can help people navigate to
new and interesting ones."*

**What R27 got wrong.** It read D1 as forbidding ranking, and D1 does not. D1 forbids ranking **people**
— "nothing counts a person's actions, no streaks and no leaderboards" — and every reason given for it
is a reason about people: farmable metrics, drive-by check-ins, extrinsic reward crowding out intrinsic
users. A ranked list of *trees* contains no person, exposes no person, and rewards no person. R27
generalised a constraint on one noun to a different noun and called the result principle. The owner's
correction also supplies the purpose R27 had lost sight of: **the app exists to bring people to trees.**
A discovery surface that refuses to say which tree is worth the walk is not being principled, it is
being useless.

**The ruling.**

**1 · A neighbourhood's beloved trees is an ordered list, and it says which is first.** Rank by how many
distinct people have favourited the tree. Show the ordering. Showing the number too is permitted and
preferred — ranking while coyly hiding the count is the worst of both, since the reader infers a number
anyway and cannot tell how thin the margin is.

**2 · The floor from R27 survives untouched, and its job is privacy, not modesty.** Favourites are
private (R2, D11). A tree below the floor must not appear in the ranking at all, because at a count of
one the surface publishes somebody's private bookmark and at two it is inferable to whoever knows they
are the other. The floor is a k-anonymity threshold; DECISIONS' existing precedent is ≥3 distinct
people. It is not negotiable downward for a sparser neighbourhood — a neighbourhood with nothing above
the floor shows nothing and says why (E126), rather than lowering the bar to fill the screen.

**3 · No person is named, counted, or reachable through the list.** The ranking is over trees. Nothing
in it links to who favourited anything, no contributor appears, and there is no route from a beloved
tree to the set of people who love it. D1 and D11 are untouched by this ruling and remain absolute.

**4 · The one panel finding that survives is real, and the owner's own framing answers it.** The
round-2 panel's objection (DECISIONS §2.6) was that ranked attention routes toward Grandmother Cypress
and away from the young street trees that most need eyes. That is a genuine failure mode and this
ruling does not dismiss it — but the owner asked for a surface that brings people to **"new and
interesting"** trees, which is not the same as the same famous tree every time. So the list is
**personalised by exclusion**: a tree you have already favourited, photographed or visited drops out of
your own view of it. The ranking is global and honest; what it shows *you* is the part of it you have
not met. This costs nothing in integrity — the order is unchanged, nothing is fabricated, and the
reader who wants the famous one can search for it — and it converts the panel's objection into the
feature the owner asked for.

**5 · Favourites only.** The owner was explicit that photo counts are not wanted here. One signal, one
meaning: *how many people chose to keep this tree*. Do not blend photographs, visits or care events
into a composite score — a composite is unreadable, unfalsifiable, and is the shape that eventually
grows into a leaderboard.

**Still open, inherited from R27:** the numeric floor, which wants the real distribution of favourites
per tree before it is chosen — count it, do not guess it; and whether "neighbourhood" means the
analysis-neighbourhood geometry in `Fixtures/raw/sf_analysis_neighborhoods.geojson` or the viewport the
reader is looking at. **New and open:** whether the ranking is stable enough to be worth ordering at
local-beta volumes. With a handful of devices, first place may be a tree with four favourites and second
a tree with three, and an order that reshuffles on one tap is a worse answer than no order. Measure the
real spread before shipping the numbers, and if the margins are that thin, say so on the screen rather
than presenting a coin flip as a ranking.

<!-- Written for #137. Append to docs/RULINGS.md as R28. Do not renumber. -->

### R28 — the tree profile asks the row which city it is from, and San Francisco's sentence does not run anywhere else (task #137)

Four decisions, taken together because they are one mistake seen four times: **San Francisco's name
had become the framework's, invisibly, by being the only one there had ever been.** This is R24's
finding one layer up, in copy rather than in an inference, and it is the same sentence that closes
R24: *a rule written over one city's vocabulary does not run against another's.*

---

**What was on screen.** On a San Jose tree, the profile said San Francisco four times — the subtitle's
source label (`SF city inventory`), the record card (`SF #167879`), the section header
(`WHAT SAN FRANCISCO HAS ON FILE`) and a sentence about how San Francisco records pruning — while
the provenance line **at the foot of the same section** read *"From the City of San Jose Street Tree
inventory, July 31, 2026."* and was correct. One screen, two answers, and the wrong one in the
larger type. E176 found it, filed it, and declined to fix it because generalizing a city's name
across five surfaces is a design decision rather than an ingest change. This is that decision.

**The machinery already existed and four call sites were not using it.** `InventorySource` resolves
per row through `LocalAPI.provenance(of:in:)` from `trees.inventory_source`, and its own
documentation already declared `name` to be "the phrase the app puts on screen". The profile's
subtitle was a `switch` over `TreeSource` with two string literals in it.

---

#### 1 · The source label names the row's inventory, in the same string the provenance line uses

`TreeProfilePresentation.provenance` returns `InventorySource.name` — byte for byte what
`CityRecordCopy.provenanceNote` puts at the bottom of the screen. That identity is the ruling, not a
convenience: the top of the profile and the bottom of it now read from one value, so they cannot
disagree again for any city, in any seed. There is no second derivation to drift.

**The fallback is city-neutral, not San Francisco.** A seed built before the `inventory_*` receipt
keys cannot say which inventory a row came from, but `source == .cityImport` still says it is a
municipal one — and that is the distinction SCREENS.md drew this element for, `city inventory`
against `community-added, unverified`. Naming a city the row cannot supply is the defect; naming the
category it can supply is not.

**Why not keep it short and city-neutral for everyone.** That was the other candidate: let the
subtitle say `city inventory` always and let the bottom line name which. It is tidier and it loses
something real. Under D16 the map is a merged national table, and *which city's inventory this row
is from* is a fact a reader wants at the top of the screen rather than 800 points below it. Dropping
it would be a regression dressed as a simplification.

#### 2 · The record number keeps the publisher's id and loses the city

`SF #167879` was doing two jobs and only one of them survives a second city.

**The number survives.** It is San Francisco's `TreeID` or San Jose's `FACILITYID` — different
columns, the same kind of thing, and the only string a reader can carry back to the city that issued
it. The card renders `#167879`.

**The prefix does not.** It named a city, and on 52,788 rows it named the wrong one. Nothing is lost
by dropping it: the card's label already reads `City record`, and *which* city is now stated twice
more on the same screen, both times from the row.

**It is not replaced by the qualified identity.** `us-ca-sj:167879` is R18's *identity* key, the
string the uuid5 is derived from, and it exists so two cities' numberings cannot collide in one
table. It is Cypress's namespacing, not San Jose's record number, and printing it would hand the
reader a slug that means nothing in the city's own asset system.

#### 3 · The header names the kind of source, and the section's own last line names which one

`What the city has on file`. **This is the one of the four that does not derive from the row, and
the reason is the type rather than the principle.** The header is a micro-label — uppercase mono
with letter-spacing — and the only value the row can honestly supply is the inventory's published
name, `City of San Jose Street Tree inventory`, 38 characters. Set in that face at that width it is
four wrapped lines of shouting above a two-card grid.

So the header states the category, which is true of every municipal inventory the merged table will
ever hold, and the provenance line **inside the same section** states which one, in full, with the
day it was read. A constant that is true everywhere is not the same defect as a constant that is
true in one city.

#### 4 · The pruning sentence is San Francisco's claim about San Francisco's columns, and it declines outside `sf`

`CityRecordPresentation.pruningNote(idSpace:)` returns nil for any id space but `sf`. Nil `idSpace`
keeps the sentence, matching `LandContext.inferred(from:idSpace:)` exactly — a seed built before the
column existed holds one city and the sentence is true of it.

**This is the part of the ticket most likely to be got wrong, and the wrong answer is a translation.**
The sentence is not a label. It is a specific, sourced claim: DataSF `tkzw-k3nq` has eighteen columns
and no pruning event, and SF Public Works' own layer carries `Prune_Status` and `Prune_Year` **at
keymap-grid grain**, which is what "records pruning by block, not by tree" reports (E143, #91).

San Jose's Street Tree layer publishes no pruning field at all. That is a **different** claim —
"this inventory records nothing about pruning" rather than "it records it at the wrong grain" — and
writing it would be Cypress stating what is and is not in another city's field list on the strength
of one adapter's column selection rather than the city's published metadata. R24's test is not "does
it return something sensible for the new source" but **"was this rule written from this publisher's
documentation"**, and for San Jose it was not.

**So a San Jose reader gets one fewer sentence, and that is the outcome rather than a gap to fill.**
The section is not empty for them — the cards draw and the provenance line draws — so the half of
E126 that governs is not "a surface with nothing on it must say why" but the temptation E126 and E9
both refuse: a plausible-looking stand-in for a fact the app does not have. Absence renders as
absence, and a default is the bug.

**What this does not decide.** Whether San Jose's inventory should get a pruning sentence of its own
once somebody reads the city's published field list, and where a per-inventory "what this source does
not record" fact would live if a third city needs a third sentence. The honest shape at that point is
a column on `inventories`, not a third branch here.

---

#### The mock pins this overruled, and why the departure was in scope

ARCHITECTURE §5 rule 8 makes departing from a drawn mock a decision rather than a commit. The owner
gave the go-ahead for the departure and did not pre-decide the wording; the wording is above and the
pins are updated in place, each with the reason beside it.

| pinned where | drawn | now | why |
|---|---|---|---|
| SCREENS.md 14 §3 | `Lophostemon confertus · SF city inventory` | `… · City of San Jose Street Tree inventory` on a San Jose row | the mock was drawn when the seed held one city |
| SCREENS.md 03 §5, 14 §5, 19 §6 | `SF #114-88`, `SF #201-33`, `SF #088-21` | `#114-88`, `#201-33`, `#088-21` | the prefix named a city; the number is the publisher's |
| SCREENS.md §1 type sample | `DBH 64 cm · taped · SF #114-88` | annotated, sample left as drawn | it is a *typography* sample, not a screen |
| `SiteTests.identityLeadsWithTheAddress` | `Vacant planting site · SF city inventory` | `Vacant planting site · city inventory` | the fixture carries no inventory to name |
| `MemorialPresentationTests` | `SF #088-21` | `#088-21` | as above |
| `TreePlacementTests` | `line.contains("SF city inventory")` | the city-neutral fallback, **and no `SF` anywhere in the line** | the assertion now bites in the direction of the defect |

The **section header** and the **pruning sentence** were pinned only by this repo's own tests and doc
comments, not by SCREENS.md, because §9b is NOT SPECIFIED and always has been (E145).

**`mocks/cypress-mocks.html` is not edited.** It is the drawing, and a drawing is a record of what
was drawn. SCREENS.md is where the departure is recorded, because SCREENS.md is what the contract
calls visual truth.

---

#### The same two literals on screens 14 and 19, fixed with the same one derivation

`SitePresentation` and `MemorialPresentation` each carried their own copy of `SF city inventory` and
`SF #<ref>`. The vacant-site screen is not a hypothetical: **11,787 of the shipped seed's vacant
planting sites are San Jose's**, and that screen's own provenance line was already correct, so it had
the identical top-and-bottom contradiction. Both now call `CityRecordCopy.recordSource` and
`CityRecordCopy.recordNumber`. One string, three screens — a memorial cannot start naming a city the
other two have stopped naming.

### R29 — What the almanac is about, once the record holds more than one city

**Task #138.** Delegated by the ticket: *"Two candidate shapes, and choosing between them IS the
work."* Implemented in ERRATA **E182**.

---

## The question

`seed.neighborhoods` is San Francisco's 41 Analysis Neighborhoods and nothing else. Every read
behind screen 12 was `WHERE t.neighborhood_id = :neighborhood`. So all 52,788 San Jose rows, which
carry `neighborhood_id IS NULL`, were invisible to the almanac, to the neighborhood species mix, and
to the coverage panel — *the surface D1 makes the app's only directed ask*. E176 found the hole,
declined to make the product decision, and said so.

The decision is what "your area" means when the destination is **D16**: one database holding every
municipal tree inventory in the country, merged into a single normalized format.

## The two shapes, and what is actually wrong with each

**Give each city its own polygons.** Direct analogue of what SF has. Keeps the almanac's existing
concept whole, keeps the pill a place name, and San Jose does publish boundary sets.

The obvious objection is cost — a polygon set per city, sourced, licensed and ingested before that
city's trees are visible at all. That objection is real and it compounds under D16, but it is not
the objection that decides this. **The one that decides it is that the unit would not be the same
unit.** San Francisco publishes 41 *Analysis Neighborhoods*, a statistical construct its planning
department drew. San Jose publishes council districts, which are political and get redrawn every ten
years, and planning areas, which are neither. Most cities publish nothing. Presenting all of those
under one word would reintroduce at the polygon level exactly the seam D16's normalized format
removes at the tree level — and it would do it invisibly, because a pill reading `District 3` and a
pill reading `Sunset/Parkside` look like the same kind of promise and are not.

There is a second, quieter cost: it makes the almanac's national coverage a function of how many
polygon sets somebody has sourced. A second ingest pipeline, with its own licensing and its own
staleness, gating a screen that the first pipeline has already made answerable.

**Make the geography derive from something every city has** — a radius, a viewport, a generated
grid. No per-city asset; works for city thirty as well as city three.

The objection here is not the one the ticket anticipated. The copy's dependence on names turns out
to be thin: exactly two surfaces print the area's name, C1's trailing pill and the same pill on the
`PinSet` destination. The bloom row names a *street*, the elder names a species and a year, the
composition card names species. Nothing says "the Mission's oldest tree".

**What a radius genuinely loses is that the almanac stops being about a place and starts being about
you.** A named polygon is the same area for everybody standing in it: the elder is the elder, the
nine young trees are the nine, and two people on the same block are reading the same page. A circle
centred on the reader moves as they walk. "Walk the nine" becomes a claim about where somebody was
standing when they read it, and the coverage ask — the app's only directed ask — stops being
referenceable between two people. A generated grid recovers stability and loses the ability to be
named at all; `Almanac · cell 4829` is not a pill.

## The ruling

**The almanac's subject is a named area where the merged record holds one, and a stated radius
around the reader where it does not. The fallback is named as what it is — a distance, not a place —
and the screen says so in a sentence, not only in a pill.**

Three parts, and the third is the one that makes this a hybrid rather than a hedge.

1. **The polygon is preferred wherever it exists.** Nothing about San Francisco changes: the same
   ids, the same predicate, the same counts, the same denominators. This is not conservatism, it is
   the argument above — a stable, named, shared area is a better subject than a moving one, and it
   is kept everywhere it is available.
2. **The fallback is the default, not the exception.** A city's trees are visible in the almanac the
   day its inventory is merged, with no second asset. Under D16 that is the property that matters:
   the almanac's coverage is the inventory's coverage.
3. **The fallback never dresses itself as a place.** C1's pill reads **`Within a 15-minute walk`**,
   and a line under the header reads:

   > No neighborhood boundaries are on file for where you are, so this almanac is drawn around you
   > instead. It will name a neighborhood once this city's boundaries join the record.

   The pill alone is too quiet. A reader who has only ever seen `Sunset/Parkside` in that slot has
   no way to tell that `Within a 15-minute walk` is a different kind of thing rather than an oddly
   named neighborhood, and "your area" and "the Mission" are different promises. The sentence says
   which one is being made, and — D16(b)'s rule, that an honest degraded state must say what *would*
   change rather than only what does not — what would give the area a name back.

   It never names the city. The app does not know which city a coordinate is in; it knows only that
   no boundary in the record contains it, and saying more than that would be the screen guessing.

**And a third area exists: none.** A circle drawn around a reader in Sacramento is a perfectly
well-formed area with no record in it. The fallback is only taken where the inventory actually
covers the ground, and where it does not the screen says so instead of heading a blank page with a
distance. That state is E182's half of this work and would have been built whichever shape won.

## The radius is 1,200 m, and the number is not free

Two things had to be true and one number satisfies both.

- **It has to be a neighborhood-sized area, or the cold-start floors change meaning.** DECISIONS
  §2.6 shows aggregates only above their thresholds; a smaller area crosses them less often and
  would silently empty panels that were populating. SF's 41 polygons span 0.015–0.045 degrees of
  latitude; a 1,200 m radius is 0.0216, inside that range rather than beside it. Measured on the
  shipped seed, the circle around downtown San Jose holds **6,963 records and 167 species** — between
  Outer Richmond (6,216) and Noe Valley (6,361).
- **§4's second sentence has to stay honest.** The coverage card says "All nine are within a
  15-minute walk" only after checking, against `AlmanacMetrics.walkRadiusM` = 1,200 m. Setting the
  fallback to the same distance makes that check pass by construction — the sentence being *true*,
  not the check being skipped.

The two constants stay separate. If they diverge, the fallback may hold a tree §4 declines to call
walkable, which costs a true sentence rather than printing a false one.

## What this ruling does not do

- **It does not fetch San Jose's polygons**, though the ticket authorized it. Under this ruling they
  would be an optimization for one city rather than the mechanism, and adding them would require a
  `neighborhoods` table with a city column, a rule for name collisions between two cities'
  neighborhoods, and a seed rebuild that does not travel with a branch. If San Jose's boundaries are
  ingested later, R29 needs no amendment: the polygon path is already preferred and San Jose would
  simply start taking it. **That is the test of the hybrid and it passes** — the fallback is not a
  thing to migrate off, it is the floor under every city that has not been reached yet.
- **It does not change the resolution mechanism.** A polygon is still resolved through the nearest
  inventoried tree's `neighborhood_id` rather than by point-in-polygon (E44, A4). The seam A4 will
  move through is still one function.
- **It does not touch screen 07's `Near you` count or screen 08's resident neighborhood**, both of
  which have the identical SF-shaped hole. See E182; they are two other screens' tickets, and a
  geography ruling made on screen 12's behalf is not standing to redesign them.

### R23.1 — four filters show and the rest live behind one expandable control. The owner restructured R23's row; its substance is untouched

Recorded 2026-07-31, from the owner walking the running app: *"Only filters that should show are
yours, in bloom, needs care, and year — and favorites (and any others we add later) should go to a
separate expandable filter button."*

This is an amendment, in R27.1's sense: R23 is not overturned and is not renumbered. One paragraph of
it is superseded and the rest of it is the reason this change is safe.

---

#### What is superseded

**R23 §1's row.** R23 drew `Yours · Favourites · Year ▾ · Needs care · In bloom` and argued for every
chip in it. The chips are the same chips; what changed is that one of them is no longer in the row,
and that the four which remain are drawn in the order the owner said them:

> `Yours · In bloom · Needs care · Year ▾ · More filters`

`MapFilter.Condition`'s declaration order is now that order — `inBloom` before `needsCare` — so the
owner's ordering lives in one place rather than in a literal beside the view.

**R23 §1's sentence "`membership` is single-select within itself … tapping the other one swaps".** The
rule survives verbatim; what changed is that the swap now crosses two surfaces, because the two halves
of `membership` are no longer drawn beside each other. Turning `Favorites` on inside the control turns
`Yours` off in the row above it. That arm is written exactly once, in `MapExtraFilter.favorites`.

**The spelling.** The owner named the word: *favorites*, not *favourites*. `MapMembership.favorites`,
`MapFilterCopy.membershipLabel(.favorites)` → `"Favorites"`, and the two empty-state sentences are
American now. **This is deliberately not a sweep.** There are 157 `favourite`, 422 `centre`, 189
`neighbourhood` and 182 `colour` across 169 Swift files; that is its own ticket and two other branches
are live in the same files. What was renamed is the vocabulary of the control the owner was looking at
when they said it. Note that `DeviceContributions.favorites` and the `favorites` table were already
spelled this way, so this narrows an existing split rather than opening a new one.

---

#### What survives, and is load-bearing

Every one of these was checked against the restructure rather than assumed:

- **The row is still a conjunction, not a single-select.** Moving a term out of sight does not make it
  an alternative to the terms left behind. `Yours` and `In bloom` and a decade are still ANDed, and so
  is `Favorites` while it is set from behind the control.
- **`All` is still not a chip.** The un-narrowed map is still the row with nothing on.
- **`Clear filters` still appears only when something is on, and it now clears what is hidden too.**
  See below; this is the part the restructure makes load-bearing rather than tidy.
- **The species filter is still the legend and there is still no species chip.** R23 §2's argument —
  that the strongest guarantee two controls agree is that they are one control — is untouched, and the
  new control is deliberately *not* where the species dimension went. Putting it there would have
  reopened the fight for screen space that §2 settled.
- **The result line still obeys E38 and D1.** `MapFilterCopy.result` is unchanged. The noun is still
  *trees*, the sentence still never takes a second person, a page is still not a total.
- **The empty state still says why and how to leave, and `Yours` and `Favorites` still get two
  different reasons** for "none here" versus "none anywhere". This is now more important than it was,
  not less: see the hazard below.
- **The year control still states its own blind spot** whenever a decade is chosen (R23 §4, E175).

---

#### 1 · The control is an extension point, not a drawer with one thing in it

The owner's parenthesis — *"and any others we add later"* — is the requirement, not an aside. A
`Favorites` chip written inline behind an `if isExpanded` would satisfy the sentence and none of its
intent: the second narrowing to arrive would be a second inline chip, and the collapsed control's
"something is on" indicator would be a hand-maintained condition that somebody eventually forgets to
extend — on the day they forget it, a filter is on and nothing on screen says so.

So the shape is a type. `MapExtraFilter` is a `CaseIterable` enum whose every case carries its own
`label`, `isOn(_:)` and `toggle(in:)`. The drawer renders `allCases`; the collapsed chip counts and
names `allCases`; `MapFilter.activeExtras` is the single expression all three read. **Adding a
narrowing later is one case and two switch arms, and no view changes at all.**

`isOn`/`toggle` live beside the case rather than on `MapFilter` for the same reason: they are the whole
definition of what a hidden narrowing *means*, and keeping them there is what makes the case the only
thing a new one has to write.

#### 2 · The hazard the restructure creates, and the three channels that answer it

**A filter set inside a collapsed control is a map narrowed by a cause nobody can see.** That is ERRATA
E126's defect — "a screen showing something other than what you asked for must say why" — wearing a
new hat, and it is created by this change rather than inherited. R23 could not have it: every narrowing
was a chip you could look at.

Three channels, and they are three because they reach different readers:

| channel | what it says | who it reaches |
|---|---|---|
| the selected fill on the collapsed chip | *something in here is on* | a sighted reader, at a glance |
| a count in the visible label — `More filters (1)` | *how many*, exactly | a sighted reader who cannot tell the two fills apart, and anyone reading a screenshot |
| `accessibilityValue` — `Collapsed, on: Favorites` | *which ones*, by name | a listener, for whom the other two do not exist |

**Why the label counts and the spoken value names.** The control exists precisely because names do not
fit in this row — putting them back in the collapsed chip's label would undo the change on the one
screen width that made it necessary. A spoken string has no width, so that is where the names go. At
AX5 the difference is not academic: `More filters (1)` fits and `More filters: Favorites` does not.

**Why the state word is in the value and not the label.** A disclosure that does not say whether it is
open leaves a listener pressing it to find out, and "the panel appeared below" is not an observation
available to them. So the value carries both facts — `Expanded` / `Collapsed`, then the names — and the
hint says what is behind the control rather than what pressing it does.

#### 3 · One clear-everything control, and this is now the argument for it rather than a preference

R23 gave `Clear filters` two homes — the chip in the row and the button on the empty notice — and one
meaning. That is now the only safe arrangement. **If the way out of a hidden filter were also hidden, a
reader would have to know a filter existed in order to find the control that removes it.** `filter =
.all` clears every dimension, drawn or hidden, and the chip is on screen whenever *any* of them is set
— including when the only thing set is behind a shut control.

A second, drawer-local "clear these" was considered and refused. It would be a second control saying a
weaker version of the same sentence, reachable only by opening the thing you are trying to escape.

#### 4 · Shut means shut — the drawer's chips leave the accessibility tree

The contents are behind an `if`, not an `.opacity(0)`, not a zero-height frame, and not an overlay.

This is R25's argument one control over, and it is the reason R25 put the suggestion list *in the flow*
rather than over the chips: a surface that hides something visually while leaving it in the element
tree produces a control a sighted reader cannot see and a VoiceOver reader can still swipe onto and
press. `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists for that failure; this
project has also had `.clipped()` clip drawing without clipping touches, leaving a control reporting
`isHittable` and answering nobody. The drawer is in the flow under the row for the same reason, so
opening it moves what is below rather than covering it.

**Closing the control does not clear what is inside it.** A disclosure that discarded your instruction
when you tidied the screen would be the single-select bug R23 §1 was written against, arriving through
a different door. That is exactly why the collapsed chip has to say that something is still on, and why
§2 above is a requirement rather than a nicety.

---

#### Deliberately not decided here

- **Whether the chrome is now too tall.** R23 left this open and the restructure improves it slightly
  — one fewer chip in the resting row — without settling it. Opening the drawer adds a block, but only
  while the reader has asked for it.
- **What goes in the control next.** It is an extension point; nothing is queued for it. The species
  dimension is specifically *not* a candidate (§2 of R23).
- **Whether `In bloom` and `Needs care` should survive at all.** Both match nothing in the shipped seed
  *(→ half stale as of E189: `In bloom` now matches for nine months of the year against the current
  seed; `Needs care` remains exactly as written)* — `In bloom` because every `seasonal` is `{}` (R23
  already says so, and is stale the same way), and `Needs care` because
  `MapPinKind.needsCare` is `status == .declining` and the seed carries only `alive` (174,425) and
  `vacant_site` (24,200). R23 left the first open on the grounds that the curated species pipeline is
  what fixes it. The second is the same shape of question and the owner has just re-confirmed both
  chips by name, so neither is touched here. **It is recorded because it was not written down
  anywhere**, and because a chip that cannot match is a chip guaranteed to produce an empty-state
  card.

### R30 — the copy names the control the app draws, and the heart stays unbuilt (task #139)

**The finding.** The map's Favorites empty state said *"You have not hearted a tree yet. Tap the
heart on any tree's page and it will appear here."* The owner reported it as false, and it is. See
ERRATA E184.

**The question this ticket forced.** Two closures were available and the choice was real: either the
heart affordance ought to exist and is missing, in which case the copy is a bug report against the
screen; or the copy describes something that was never drawn, in which case the copy is the bug.

**The ruling: the copy is the bug, and no heart is built.**

The record is one-sided once you go and look at it:

- `SCREENS.md` §2 C8 — "**NOT SPECIFIED:** icons for these four actions — the spec shows text only."
- `SCREENS.md` §5 gap 3 — "Icons for `Favorite` / `Care` / `Share` / `Report` (C8) — text only."
- `SCREENS.md` 03 §6 draws the row as `Favorite` · `Care` · `Share` · `Report`.
- `mocks/cypress-mocks.html` contains the string "heart" **zero** times.
- RULINGS R2 already litigated this and corrected itself in the building: its first draft said "the
  heart glyph fills, glyph and label take `accent`", and the correction reads "**C8 has no glyph.**
  … Adding a heart to one of four text cells would have been a drawn decision on the very component
  this ruling treats as already-drawn — constraint 21, arriving from the direction I was not
  watching."

So the heart is not a replaced affordance whose copy outlived it. It is a word that entered the
prose from R2's retracted first draft and reached a user-facing sentence. Building one now would
mean inventing a glyph for one of four text cells — DECISIONS constraint 21, refused once already
for these exact reasons — and it would be a **sixth** violation of the drawn-glyph policy the
project is already carrying five of (#130). The day design lands the four icons, R2 says it is one
line in `QuadActionRow.appearance`, and this ruling does not move that day earlier.

**No mock is overruled and `SCREENS.md` is not amended.** This is worth stating beside #137, which
established the convention for departing from a mock deliberately — update `SCREENS.md` in place
with the reason next to it, and record the departure in the ruling. That convention does not apply
here, and applying it would have been the mistake: #137's screen departed from its mock and the mock
needed the note. Here the *copy* had departed from the mock, and the fix is the copy coming back.
Writing a departure note for a change that removes a departure would leave the record claiming a
divergence that no longer exists.

**What the sentence says now.** *"You have not favorited a tree yet. Tap Favorite on any tree's page
and it will appear here."* It quotes the cell's own label, which R2 fixed as `Favorite` in both
states — a noun naming the thing rather than a verb naming the next tap — so the word the notice
sends the reader to look for is the word they will find. A test asserts the two strings agree, and a
second sweeps every sentence the type can produce for the word "heart", because the failure mode
here was not one bad sentence but a word that no test would notice being wrong.

#### A note on copy tests

`MapFilterTests` required the empty state to contain the word "hearted". The intent was sound — a
reader with no favorites must be told what to do rather than told to pan around — but the assertion
was written against the phrasing instead of against the fact, and so the test defended the defect.
The general form, for whoever writes the next one: **assert that the copy names the control, by
reading the control's own label; never assert that it contains a particular word.** A phrase pinned
in a test is a phrase nobody can fix.

#### Spelling

The owner named "favorites", not "favourites". This change spells it American in the two files it
owns (`TreeProfileModel.swift` and the new `FavoriteRoundTripTests.swift`) and in the new
user-facing sentence, and touches nothing else: the codebase-wide sweep is task #140 and must run
alone. `MapMembership.favourites` is deliberately left as it is — a concurrent branch is renaming
it, and two branches renaming one case is how a merge eats a fix.

### R31 — the two chips that cannot match yet stay visible, stay honest, and name two different waits (task #136)

The owner fixed the map's visible filter set: yours, in bloom, needs care, year. That settles half
of #136 — `In bloom` and `Needs care` stay on the row, undemoted — and leaves the half this ruling
decides: what a chip does during the time it cannot possibly match, which for both chips is right
now. Every `seasonal` value in the seed is `{}`, and the seed's only statuses are `alive` and
`vacant_site` (R23.1's findings). A chip whose only possible outcome is E126's apology card is
#59's defect wearing filter clothes: a control that promises and cannot deliver.

> **Correction at implementation (E189).** The premise this ruling inherited from R23 had expired:
> the current seed carries seasonal data on 511 of 569 species, so `In bloom` is not impossible —
> it is *seasonal*, live nine months of the year and dead three. The ruling's mechanism survives
> intact and gains a case: availability is asked of the store per month (`MapConditionAvailability`),
> and the disabled chip now speaks **three** sentences, not two — the debt sentence only when no
> calendar exists at all, an out-of-season sentence when the calendars are merely quiet, and the
> invitation for `Needs care`, which is exactly as this ruling described. The self-enable clause
> ("the data's arrival is the switch") turned out to be the whole design; the two-sentence framing
> was the part written from a stale document. Four documents carried the expired claim — this is
> the row-for-row lesson from the postmortem, in the rulings themselves.

**Decision: the chips render enabled-looking never; they render disabled with the reason on the
chip's own surface, and the two reasons are different sentences, because the two waits are
different in kind.** `In bloom` waits on us — the curated species pipeline (#6) owes the calendars,
and D5's schema is ready for them. `Needs care` waits on the neighborhood — `declining` is a
status no city publishes, so it arrives through community observation or not at all. The first
sentence is the app being honest about its debt; the second is an invitation. The implementer
drafts the final words in the register of R23 §6's notices, and tests them under R30's rule:
assert that the copy states the fact, never that it contains a phrase.

A disabled chip does not spend the reader's tap on a card that says what the chip already said —
the reason lives on the chip (visually, and as the chip's accessibility value), and the E126
notice path is never entered because the filter never activates. Each chip enables itself the
moment its data exists: `Needs care` on the first community observation that stands a declining
tree in the current scope, `In bloom` when a species calendar lands and a scoped tree is in its
bloom months. No flag, no release — the data's arrival is the switch.


> **Corrected 2026-08-01 (task #165, owner directive; the presentation clause is struck).** The
> owner: "We should NEVER display a message box in place of an empty filter. … Just have the
> Needs Care pill and if nothing matches, fine." The chips render as ordinary tappable pills on
> every machine in every month; a filter that matches nothing empties the map and draws nothing
> else — no card, no zero-count line, no sentence. E126's empty-notice card no longer applies to
> a filter the reader just set themselves (E126 itself stands for location notices and search
> status). The way out is the row's `Clear filters` chip (R23.1 §3 survives; it is now the only
> control wearing that label). The whole availability chain was removed with the presentation —
> `MapConditionAvailability`, its API requirement, `LocalAPI`'s read, the query helpers, and
> `MapConditionAvailabilityTests`; the bloom-calendar seed facts that test happened to pin (11
> species with calendars, no Oct–Dec bloom) lost their pin with it and must be re-pinned by any
> later surface that quotes them. What survives of R31: the chips stay on the row, undemoted, in
> the owner's order.

### R32 — a hazard on private land is not the city's to fix, and the app stops saying it is (task #88)

`ReportPresentation.showsHazardBranch` is `selection.hazard != nil` and nothing else, so a tree the
record marks private-property gets the identical "Call 311 now" handoff as a street tree. Since
#69 shipped the land-context picker, that is live, not latent. 311 is the city's line for city
trees; sending someone there about a tree in a private front yard is the app being confidently
wrong — the class of sentence E175 exists to hunt.

**Decision: the 311 handoff branches on the tree's land context, and the private branch tells the
truth.** For a community-added tree whose `land_context` is private, the hazard flow says plainly
that this tree is not the city's to fix, still records the observation — under D16 the record is
the product, and a private tree's decline is still a fact about the neighborhood — and names the
caretaker when the record holds one. No 311 copy, no 311 button.

**What does not change: a city row keeps 311 regardless of its `caretaker` column.** 163,955 city
rows say `Private`, and most are street trees a neighbor waters. Membership in the city's
inventory is what makes 311 the right line, not who waters the tree. The branch key is the
community row's `land_context`, which required the reader to say it; it is never inferred.

Implementation note: `ReportModel` holds a `treeID` and never reads the tree — the gate needs the
read, and the read belongs in the model rather than the presentation guessing from what it was
handed. Task #88 is the orchestrator's own.

> **Correction, same day, before any code was written to this ruling.** R32 was written from
> ticket #88's text, and the ticket was stale: commit `c970795` (2026-07-25) had already closed
> the hole, recorded as **E146**, with tests (`LandContextScreenTests`) and a design that is
> better than this ruling in one respect R32 now defers to. Where R32 said "no 311 copy, no 311
> button," the shipped screen **demotes the call to a plain `Call 311 anyway` instead of deleting
> it** — because a contributor's land answer can be wrong too, and the harm of suppressing a real
> safety call runs one way. The shipped screen also distinguishes a *stated* private context
> (demote) from one *inferred* from the city's own record (inform, don't act) — R32's "never
> inferred" sentence, made sharper. E146's design stands in full; R32's two contributions that
> survive are the framing that city rows keep 311 regardless of `caretaker`, which the shipped
> code independently agrees with, and the record of the owner-delegated decision itself. Two
> sections above, R31 warned that a ruling stating a false fact about a screen is worse than
> silence; this correction exists so R32 is not that ruling. The lesson is E118/E183's again:
> **a ruling is written from the code and the screen, never from a ticket.**

### R33 — The favorite's on state inverts to the accent pair (task #153)

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

### R34 — The photo browser gains segmented access by framing (task #154)

**The report.** Owner's device walk, 2026-07-31: "the photo browser shows ONLY full-tree shots;
leaf and trunk photos are unreachable."

**The premise, checked before building on it — and refuted at the code level.** There is no
`.fullTree` filter anywhere on the browsing path. `ContributionStore.photos(treeID:)` selects
every undeleted row of every shot type; `TreePhotosModel.load()` filters only
`isVisibleToItsContributor` (tombstones); screen 20 draws every row it gets and already captions
them `Trunk`, `Leaf close-up`, `Photo`. The capture, staging, outbox and upload path carries the
framing end-to-end (E152), and `VisitCameraSessionTests.threePhotographsRoundTrip` proves three
framings land as three rows. Nothing to check under #47 either: the full-tree preference lives
only in the hero *heuristic* (`Photo.isBestPhotoShot`, `PhotoHero.choose` tier 3), which is not
on the browser's path.

What the owner most plausibly saw: photo binaries upload only when `photoUploadsAllowed`
(the wi-fi gate) — a visit's JSON can land while its trunk/leaf binaries sit `awaitingWifi`, and
in that window the only photographs *in the table* are community-add photos, which `addTree`
inserts directly and labels `.fullTree`. That is a browser showing only full-tree shots, with the
mechanism in the outbox rather than in a filter. Field confirmation is the owner's — check the
outbox screen for `awaitingWifi` rows next walk.

**The decision (pre-authorized in the task): the browser gains a segmented subject filter, in
place, no new screen.**

- Segments: `All · Full tree · Trunk · Leaf close-up` — the whole timeline first, then the three
  framings screen 04 offers, in the chip row's own order, each named by
  `TreePhotosPresentation.subject(_:)` so the segment and the caption cannot spell one framing
  two ways.
- No segment for `.other`. Nothing in the app lets somebody frame a shot as "other" — the value
  exists for care photos and for pre-shot-type outbox rows — so a segment would name a choice
  nobody made. `.other` rows are on the timeline under `All`.
- The filter is a **view** of the timeline, not a different read: the hero, `deletablePhotoIDs`
  and the community-add sentence keep answering for the tree. An empty slice of a photographed
  tree gets its own sentence naming the framing, because "no photos of this tree yet" would be
  false with the timeline one tap away.

**Hero voting is untouched — and one premise in the task is corrected on the record.** The task
says "keep hero voting full-tree-only". The shipped rule (E125, A3's escape clause) is that a
thumbs-up is the manual pin and **overrides** the full-tree heuristic — an up-voted leaf can lead
the page, deliberately, because a person's "this one" outranks a shot type. This change does not
touch `PhotoHero`; narrowing the vote's power to full-tree would be a reversal of E125, which a
browser-affordance ticket has no standing to make. What "full-tree-only" is true of is the
*heuristic tier*: with no votes, the hero is still the most recent full tree.

**The anonymized-photos half of the ask.** No, ownerless photos are not excluded by any browser
filter — screen 20 gates on `deletedAt` alone, and under `LocalAPI` `ownPhotoIDs` is every row on
the device, so `TreeProfilePresentation.visiblePhotos` keeps them too. The latent risk sits one
layer out, for whichever round builds `RemoteAPI`: `visiblePhotos` shows a non-own photo only if
`isPubliclyVisible`, and nothing in the app can ever set `.approved` — so the day `ownPhotoIDs`
becomes a real ownership set, an anonymized (`PhotoOwner.nobody`) photo drops out of the hero,
the pill count and the season strip while remaining in the browser. That is #131's territory and
is not fixed here; it is named so the next round does not find it by report.

### R35 — Observed states are never gated by what the app knows (task #151)

*Pre-authorized under delegated authority, 2026-07-31.*

## The ruling

A phenology tag at check-in is the **observer's report of what is in front of them**, not the
app's claim about the species. DECISIONS constraint 15 forbids the app asserting botanical facts
it does not have; a contributor's own observation is the opposite of that — it is the community
data D16 says the product exists to collect.

Therefore: **the observed-state options (leaf out, full leaf, flowering, fruiting, fall color,
bare) are always available at check-in, whatever the species record knows.** The species'
seasonal calendar may ORDER or HINT — e.g. surface expected states first — but it never gates
availability. An unknown calendar, an unauthored field-guide entry (`curated = 0`), and an
unsourced habit (`leaf_retention` NULL, ERRATA E9) are all states of the *app's* knowledge, and
none of them is a reason to refuse the observer a word for what they can see.

## The one exclusion that stands

D5 survives, narrowed to what it actually says: a species **known** to be evergreen is never
asked about fall color or bare. That is a sourced fact that makes the tag a contradiction rather
than an observation, it is enforced in the schema CHECK, and it is the documented decision
(DECISIONS §3.14). A species whose habit nobody sourced gets the full list — excluding fall
color there would itself assert "this is an evergreen", which is the unsourced claim E9 exists
to prevent.

## What this does NOT change

- **The app's own phenology surfaces.** Screen 07's phenology section, the season strip, and
  the chips the APP draws still render only from authored content (`showsPhenology` still
  requires a sourced habit; `FoliageStrip.enforcingD5` still clamps bare months for an unknown
  habit). The ruling is about what the observer may say, not what the app may say.
- **Vitality's leaf-off gating.** `Vitality.isRatingPermitted` / `leafOffSeason` gates the
  vitality RATING — a judgement that is meaningless against a bare deciduous canopy — and its
  reasoning (PRODUCT §3) is untouched.

## Left standing, proposed for a follow-up decision

A tree with **no species record at all** (nil species: unmapped or non-taxon rows, and profile
reads that have not landed) still draws no chip row. The same principle arguably applies — the
observer can see flowering on a tree the seed calls "Shrub" — but `VisitPhenologyChips` and
`Chip.phenology(_:for:)` are built over a non-optional `Species`, and widening that is a larger
change than #151 requires. Proposed, not done.

## Where it is pinned

`CypressTests/PhenologyObservedStatesTests.swift` — the reported record (seed `sf/222615`,
Cassia leptophylla, species row 209) through the real read path, the empty-calendar and
unknown-habit cases, D5's surviving exclusion, and the seasonal order of a known calendar.

### R36 — local for the slow heavy layer, live for the fast thin layer (owner-ratified architecture)

*Owner, 2026-08-01, ratifying the recommendation in `docs/investigations/api-hosting.md` after
challenging it — the challenge and its answer are both part of the record.*

D16 says one database, available over an API. This ruling says which parts of it travel which
way, and it turns on a freshness split the owner's challenge surfaced: **the city layer changes
at ingest cadence** — a live query API serves rows exactly as old as the last ingest run, the
same age a published file would be — while **the community layer is the thing that must be live**,
because the community-review loop means seeing other people's contributions, and no downloaded
file can show a bloom sighting from an hour ago.

**The architecture:**

- **Base layer — versioned per-city SQLite files** published by the ingest pipeline to object
  storage with a manifest. The app geolocates, offers the reader's city on first launch, and
  background-refreshes when the manifest says a newer version exists. The map's pan loop, species
  search, the almanac's aggregates and the filter distributions keep running against local SQLite,
  which two performance campaigns (E130, E139) made fast and no $2 server could match.
- **Live layer — a thin API on a small Fly machine** that starts as the write-only contribution
  sync endpoint the outbox already expects, and grows read endpoints for the community delta
  ("contributions in this viewport since my last sync") when multi-user surfaces land — R27.1's
  beloved trees is the first feature that cannot exist without it.
- **Platform: Fly.io + Tigris primary** (the owner's existing footprint; egress is the whole bill
  for this workload and Tigris zero-rates it), **Cloudflare Workers + R2 + D1 the named fallback.**
  Vercel is ruled out on its Hobby tier's non-commercial term colliding with D14's paid org tier.
- **Shape B — a live query API over the full corpus — is the documented fallback**, not the plan,
  reached only if cross-city queries outgrow what a phone can hold.

**Consequences that are binding:** (a) NYC-scale cities arrive as downloadable files, never as
bundle growth — the 103 MB bundled seed becomes a bootstrap, not the distribution; (b) any data
served or published must carry its source's attribution obligations (NYC's verbatim disclaimer
is the first); (c) seed-coverage constants (`MapFilter.undatedShareOfSeed` and kin) become
properties of the *installed* cities, which is a known open edge to design at #157, not a
surprise to find later.

### R37 — City file versioning and the manifest contract (task #156, delegated)

The publish step needed four decisions R36 did not make. Taken 2026-08-01:

**1. A city file's version is `s<schema_version>-r<content_rev>`, both parts derived,
neither invented.** `schema_version` continues the seed-pass numbering the record
already uses (E176's "v14 pass" — the generation that added `id_space`), starting at
14; it bumps when `Fixtures/seed/schema.sql` changes shape, and the app refuses
generations it was not built to read. `content_rev` is the newest upstream snapshot
date among the city's own inventories, read from `seed_meta` — never the wall clock,
so republishing the same seed yields the same version and byte-identical files. There
is no third "build number" component: two publishes of the same data ARE the same
version, which is what makes the object paths immutable.

**2. Versioned paths are immutable; only `manifest.json` is ever rewritten.** Objects
land at `cities/<id>/<version>/<id>.sqlite`, written once; the update check on device
is string equality on `version`. Files upload before the manifest that names them.

**3. City files are narrowed copies, not rebuilt files.** The publisher byte-copies
the fused seed and DELETEs the other city out (then VACUUMs), so schema fidelity is
by construction. What survives: the city's `trees`, its `species_assertions` and
R*Tree entries, only its `id_spaces`/`inventories` rows, only referenced
`neighborhoods` — but `species`/`species_map` stay WHOLE, because the species
catalogue and its curated content are shared authored work, not city data, and
splitting them would fork curation. `species_map.tree_count` therefore still
describes the fused build; `seed_meta.species_map_counts_scope` says so in-band.

**4. Files ship uncompressed, and the manifest's `base_url_hint` is not for the
app.** Uncompressed: Tigris egress is free (R36), `#157`'s consumer stays a plain
file download with a sha256 check, and gzip (~2x) can be added later as a new
manifest key without breaking format 1. The download base URL is app configuration;
a manifest field that named it would let a stale or hostile manifest redirect
downloads.

Also binding on the next ingest round: manifest `coverage` currently maps the ad-hoc
`seed_meta.sj_ship_extent` key by hand; when a third city lands, `build_seed.py`
should write `coverage_<id_space>` keys and the publisher's `COVERAGE_KEYS` shim
retires.

### R38 — The filter row is one horizontally scrolling line (task #166)

**A correction to the row presentation R23 recorded ("two wrapped chip rows") and #145
inherited. Owner directive, verbatim, task #166 (2026-08-01):**

> More filters should be on the same line as Yours and In bloom and Needs care; one row for
> filters, that's it.

## The decision

Screen 01's filter row — `Yours · In bloom · Needs care · More filters`, plus `Clear filters`
when anything is on — is **one horizontally scrolling line**. It never wraps to a second line
and never forms a separate cluster, at any Dynamic Type size. Chips past the trailing edge are
reached by dragging the row.

The wrap it replaces was chosen against a real hazard — "a horizontal scroller on top of a map
is a gesture competing with the pan underneath it" (R23's words, borrowed from the legend) —
and that hazard is real but narrow: the scroller only owns drags that *start on the row*, one
line of chips at the top of the chrome, and the owner judged the second line of chips the worse
cost. The directive wins; the trade is recorded rather than relitigated.

## What is unchanged

- **The expandable control keeps its box** (#145): `Favorites` and `Year` stay behind
  `More filters`, and the opened drawer is still a block *under* the row that wraps internally —
  the owner's "one row" is about the chips, not about the box a chip opens.
- R23.1's three channels for a narrowing set behind the shut control (fill, count, spoken
  names).
- The legend still wraps (`FlowRow` survives there and in the drawer); its constraint was never
  part of this directive.

## What holds it (verified red-then-green on the assigned simulator)

`CypressUITests/MapFilterAccessibilityTests` pins the contract at the default size and at AX5:
every row chip reports the same line, nothing clips on the vertical axis, and every chip —
including the ones past the edge at AX5 — can be scrolled onto the glass and pressed. The AX5
wrap test this file used to carry asserted the opposite fact and was inverted, not deleted.

### R39 — A destination button does what its label says, and standard sheets run full height (task #146)

Owner direction (2026-08-01, verbatim, device screenshot on file): "Share is still fucked.
Also half-screened, like Care. Each button takes you to the same share dialog on the iPhone,
which makes individual buttons useless. If we're going to have a Messages button then clicking
it SHOULD INSTANTLY BRING YOU TO MESSAGES SHARING, not to the same screen that you get if you
click AirDrop…" This overrides E59's routing (every named destination → the system sheet) and
SCREENS.md 10 §4's four-button row. Ticket #146.

**The rule the rebuilt screen obeys: a destination button does exactly what its label says, and
a label that cannot keep that promise does not get a button.** As built:

1. **`Messages` opens Messages composition directly** — `MFMessageComposeViewController`,
   presented in-app with the public link as the body. Where the composer cannot exist
   (`canSendText() == false`: every simulator, and a device with no messaging account) the
   button falls back to the system share sheet rather than going dead; `MessagesRoute` in
   `SharePresentation.swift` is that decision as a pure function, so the device-side branch is
   asserted by the unit suite from a machine that cannot exhibit it. Verified on simulator that
   the fallback presents (screenshot in the #146 report); the composer branch is untestable on
   simulators and is wired through the same presentation path.

2. **`Copy link` is unchanged** — writes the public URL to the pasteboard. Verified end to end
   on simulator: the pasteboard held the exact card URL after one tap.

3. **`Share…` (tray + up arrow glyph) is the system share sheet**, via `ShareLink`. It is the
   honest name for what E59's three buttons all did. **AirDrop folded into it**: an "AirDrop"
   button cannot be built as labelled — `excludedActivityTypes` cannot exclude third-party
   share extensions, so a "trimmed" sheet is still a general share sheet with AirDrop at the
   top, i.e. not distinct from `Share…` in any way a user can perceive.

4. **`Instagram` is removed, not rerouted.** Instagram publishes no API for sharing links; the
   Stories URL scheme requires a registered Meta app ID (an external registration and an API
   key), and the product line is zero external dependencies. A button that can do nothing
   distinct from `Share…` should not exist as a separate button; when a real Instagram path
   exists someday, it comes back under this ruling's rule.

**Sheet height (the mechanism #168 rebases on):** C17's `.standard` bottom sheet is now
full-height — the card runs from the 62pt status-bar strip to the bottom of the display,
content top-aligned inside a `ScrollView` (`BottomSheet.swift`). The mocks drew 09/10 as
content-sized bottom cards; the owner's "half-screened" overrides them. Two rules ride along:

- A screen hosting `BottomSheet` must use `.ignoresSafeArea(.container)`, never the bare form —
  bare `.ignoresSafeArea()` includes `.keyboard` and is the exact mechanism by which the care
  log's keyboard covered the note field being typed into. With the keyboard region respected,
  the sheet shrinks above the keyboard and the `ScrollView` keeps the focused field visible.
- `.account` (screen 15) keeps its content-sized card: a short ask with no text input, whose
  mock is a card, not a page. Nothing about 15 was reported or changed.

The unit ledger (`SharePresentationTests`) pins the three labels by name and order, the hints,
and both `MessagesRoute` branches; `SheetHeightUITests` pins the full-height geometry of 09 and
10 and the note field's position above any keyboard's reach. A direct keyboard-frame assertion
was written first and deleted as vacuous: on a runner with a hardware keyboard attached,
`app.keyboards` exists *below the screen* (y=946 on an 874pt device), so it passed against the
broken build too. The geometry assertion went red against the pre-#146 layout (field at 0.81 of
the screen against a 0.55 ceiling); all five new/changed tests were proven red by mutation.
