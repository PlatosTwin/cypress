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

## R19 — A confirmed-dead tree says so in words; whether it gets its own drawn pin is still open


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
