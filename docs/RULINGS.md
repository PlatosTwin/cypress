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

C19 has no vacant-site pin, so the basins currently draw as the grey dot for a removed tree (12,518
of them when this was ruled — San Francisco alone; 24,200 across both cities today, E206). That
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
can say about the vacant sites it otherwise hides (12,518 when this was ruled, 24,200 today — E206)
— and E115 established that hiding them is a status
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

### R40 — The photo/note extras are the fields, on both contribution surfaces (tasks #168, #169)

Owner direction (task #168, verbatim, device, screenshots on file): "Care is still fucked.
Screen is half-sized which is weird, and also means that when you go to type the keyboard runs
over the area you're typing. Also to add a photo there's no option to take one (or multiple);
all it allows is adding from your library, which is inefficient. Also the behavior of clicking
on 'Photo or note' and then getting a new textbox that says 'Anything worth remembering' is
awkward." And for screen 05 (task #169): "Check-in page has a gap: the add photos/notes does
nothing. It should allow you to TAKE A PHOTO or SELECT A PHOTO, and then of course to add
notes."

The half-height and keyboard halves were already closed by #146's sheet mechanism (R39) —
verified on the running screen before this work started, not assumed. What this ruling records
is the interaction redesign of the optional slot itself, delegated authority, written from the
screens as built.

**The rule: the extras are the fields.** On 09 and on 05, the optional photo/note slot renders
its fields directly — no reveal step, no control that turns into a different control when
tapped. Concretely, on both screens (`ContributionExtras`, one component, so the two surfaces
are one design):

1. **The note field is simply there** — screen 04's field in the light register, prompt
   `Anything worth remembering?` verbatim, 1–3 line growth, set into the draft at save, trimmed,
   blank stored as NULL. The two-step "tap 'Photo or note' → get a textbox" is gone; it was the
   reported awkwardness, and a field a contributor can see is a promise the slot keeps by
   standing there.

2. **Two photo sources, side by side, each doing what its label says** (R39's destination-button
   rule): `Take a photo` opens the in-app camera; `Add from library` is the system picker,
   multi-select. The camera is `ContributionCameraView` — the same `VisitCameraController`
   session, preview layer, shutter, ✕ and library fallback screen 04 runs, with none of 04's
   visit surface (ghost, framings, phenology). Reused, not reinvented; on a device with no
   camera (and on every simulator) it falls back to the library picker with screen 04's own
   sentence, so the button never goes dead.

3. **Photos are plural and each is its own fact.** The camera stays up across shutter taps
   ("take one (or multiple)" is one open-close; a czFlash and a tray count line receipt each
   frame). Attachments render as thumbnails, each wearing its own ✕ — removal is per photograph
   and reversible, like every field on these surfaces. Each attachment is staged to its own path
   (fresh UUID through `VisitPhotoStaging`, so E148's metadata strip applies and no two share a
   path — a shared path would let the drain take siblings out of the outbox row).

4. **The C15 well survives as words, not as a control.** On 09 its verbatim copy
   (`Photo or note (optional)`) captions the block; on 05 its copy
   (`Add photos · notes (optional)`) becomes the slot's micro-label in the card's own section
   chrome. That is where "optional" keeps being said, and it is the minimal call on a layout the
   mocks never drew opened — nothing else on screen 05 moves (constraint 21). 09's caption keeps
   the mock's singular "Photo" although the slot now takes several; the word is the mock's,
   verbatim, and re-writing it was judged a larger invention than leaving it.

**What survives of #147.** Everything below the surface: the wiring E185 records — staging
through `VisitPhotoStaging` as `.other`, `CareLogDraft`/`CareEvent.note`, the unchanged writers,
no migration — plus the note-at-save timing and the trim. What #168 removed of #147's design:
the one-way reveal (`isEditingExtras`), the single-photo replace-on-repick semantics, the
library-only source, and the `Photo attached` / `Remove` text row (thumbnails carry both facts
now). #147's reachability diagnosis was right; the owner's walk showed its interaction was not.

**Screen 05's slot is wired with the same block (task #169, E25's closure).** `CheckInDraft` has
carried `note` and `photos` since M1 and `CheckInOutboxWriter` always wrote both; only the
entrance was missing. `CheckInModel` gained the same `note`/`attachPhoto`/`removePhoto` surface
as the care log's model. The saved check-in is asserted as stored rows, not UI:
`CheckInExtrasTests` pins the durable outbox row (one `.observation` item carrying both
binaries on distinct paths) and the post-drain rows on the tree (observation with the trimmed
note; two `photos` rows, `.other`, `visitID == nil`, real files behind their storage keys).

**Copy designed here** (NOT SPECIFIED anywhere in the mocks): `Take a photo`,
`Add from library`, the camera tray's `Done`, `That frame could not be captured. Try again.`,
and the tray receipt `N photo(s) added`. Each states a fact and stops; all swept by the same
ARCHITECTURE §5.4 / D1 word tests the sheets' other copy passes.

### R41 — No message ever accompanies a filter (task #180; hardens the R31 correction)

**Owner directive, verbatim, task #180 (2026-08-02):**

> No messages should appear alongside filters ever. for any reason. ever again. Right now the
> year filter has a message about 4 of 5 trees. That's stupid. Never ever show something like
> that. add it as a rule. At most a message like this can be a single-dismiss pop up but never
> ever again clutter the map with bullshit like this.

## The decision

**A filter's entire voice is its chip.** No filter — active, empty, narrowed, partial, or in
any state yet to be invented — may render companion text, a count, a notice, a card, or any
other surface on the map or beside the filter row. This is the third time a filter-adjacent
message has been ruled out (#142 killed the growing notice, the R31 correction killed the
empty-filter box); each time, a message survived under a different mechanism. The rule is now
categorical so no mechanism can shelter one: the test is "does text appear because a filter
did something?" — if yes, it does not ship.

If information is ever judged genuinely essential (a legal notice, a data-loss warning — not a
count), the only permitted form is a **single-dismiss popup**: shown once, dismissed with one
tap, never recurring for the same cause, never persistent on the glass. Nothing in the current
product qualifies. Counts and narrowing facts already have their three sanctioned channels
(R23.1: chip fill, count *on the chip*, spoken names) — on the chip is the chip's voice, not a
companion message.

E126's carve-out (location notices and search status) survives for *location* and *search* —
those are not filters. Any reading of E126 that shelters filter-triggered text is wrong from
today.

## What holds it

Task #180 removes the year filter's "4 of 5 trees" message, audits every filter state for
remaining companion text, and adds a structural test that fails when any filter state renders
text on the map outside the chips themselves.

### R42 — How a full-height sheet is exited (task #175, delegated)

*Written under the delegated design authority for #175. The mocks are static HTML and draw no
gesture, so nothing here contradicts a drawing; it decides what the drawing's grabber and scrim
actually do on a phone. Everything below was measured on the running app (iPhone 16 Pro
simulator), not inferred from the brief.*

#### What this rules

Screens 09 (care log) and 10 (share) are `BottomSheet .standard`: full-height cards under R39,
with a grabber, no close button, presented in a `fullScreenCover` — so the shell owns every way
out. The owner's report: "clicking outside of them does nothing, and while you think you'd be
able to drag the top of the page down (it looks like the kind of page that does that, because
of the bar at the top), in practice the page is stuck… your only option is to close the app
entirely."

#### The diagnosis this ruling is built on

The scrim tap was **wired and working** — both hosts pass `onScrimTap: onClose`, and a tap
that reaches the scrim dismisses. What was broken is reachability:

- A full-height card exposes exactly one strip of scrim: the 62pt `statusBarInset` band at the
  very top of the display.
- On a Dynamic Island device the system's own status-bar hit region (clock, indicators,
  island) consumes roughly the top 54pt of that band. Measured by injecting taps on the
  simulator: **(201, 30) and (60, 45) never reach the app; (60, 58) and (201, 58) dismiss.**
- So the one exit was an ~8pt-tall invisible sliver between the system's gate and the card's
  top corner radius. Not a broken control — an unreachable one. "Clicking outside does
  nothing" is the OS eating the tap.
- And the grabber was pure decoration: no drag gesture existed anywhere in the shell, on a
  card whose grabber is precisely the drawing that promises one.

#### The ruling

**1. The primary exit is the drag the grabber promises.** R39's own principle — a control does
exactly what it looks like — cuts both ways: the full-height card kept the grabber, so it must
keep the grabber's meaning. A full-width handle band across the top of the card
(`CypressSpacing.Component.sheetDragZone`, 62pt: the card's top padding, the grabber row, and
the title line — the "bar at the top" the owner tried to pull) drags the card down with the
finger. Release commits or springs back by `SheetDismissRule`: a slow drag commits at a
quarter of the card's height; a flick commits when its *predicted* end — velocity folded into
distance, `predictedEndTranslation` — crosses half. Upward drags do nothing: the card refuses
to rise above its resting place. The spring back animates on `czSheet` through
`CypressMotion.resolved`, so Reduce Motion snaps instead of springing; following the finger is
direct manipulation, not decoration, and is not switched off.

**2. The whole card does not drag, and that is deliberate.** The native-sheet feel — the card
dragging from anywhere once the interior scroll sits at its top — was considered and declined.
The interior `ScrollView` is load-bearing for #146's keyboard mechanism (it is what moves 09's
focused note field clear of the keyboard), and SwiftUI offers no gesture-failure ordering
against a `ScrollView` that would not gamble with it. A competing whole-card gesture is
exactly how a drag on the note field starts dismissing the page someone is typing into. Below
the handle band, every drag belongs to the content; `SheetExitUITests` pins that a drag on the
note field leaves the sheet standing.

**3. The scrim tap stays, as wiring, sliver, and VoiceOver's exit.** The strip still dismisses
where the OS lets a tap through (pinned at y=58 by test), and the scrim remains the named
"Dismiss" element — VoiceOver activation reaches it without hit-testing, so it is the
accessible exit regardless of what the status bar swallows. But the strip is no longer *the*
exit; it is the margin of one.

**4. 09 and 10 stay close-button-less.** The mocks draw no close button on either screen
(constraint 21 — a control not in the mocks is not invented here), and with a working drag,
a working scrim margin, and a named VoiceOver exit, none is needed. If a future walk still
finds the exits under-discoverable, a close button is the owner's call, not this delegation's.

**5. Scope.** `.account` (15) is untouched: its card is content-sized, most of the display is
reachable scrim, it draws no grabber — so it promises no drag — and it has its own buttons.
Check-in (05) is a pushed screen with a back control, not this shell. The only two surfaces in
the trap were the only two `.standard` hosts, 09 and 10, and the fix is in the shell they
share, so a third `.standard` host inherits its exits.

### R43 — City downloads: the app side of the R36 base layer (task #157, delegated)

*Written under the delegated design authority the owner granted this surface. The download UI
has no mock (DECISIONS constraint 21), so this ruling is the mock. Everything in it is built
from the app's existing vocabulary: the You tab's door-and-fact sections, C10 rows, screen 17's
row metrics, and the unspecified-copy conventions in `YouCopy`'s header comment. Nothing here
is a store.*

#### What this rules

R36 made cities downloadable files; R37 fixed their versioning (`s<schema>-r<content_rev>`,
immutable paths, `manifest.json` rewritten last). This ruling decides the app side: where city
management lives, what a city row says, what the affordances are, what happens on failure, and
which file the map actually draws from.

#### 1. One inventory is attached at a time, and that is the load-bearing decision

Every read the app performs is qualified `seed.` against a single attached schema
(`SeedDatabase.schemaName`); two performance campaigns (E130, E139) tuned that path. Attaching
several city files at once would mean union reads across N schemas through the R*Tree — a
rewrite of the whole read layer with an unproven planner, which is not #157 and is not attempted
here.

So: **exactly one inventory is attached, always under the `seed` schema name, exactly the way
the bundle attaches today** (read-only, `immutable=1`, `SeedDatabase.attach`). The choices are
the **built-in inventory** (the fused bundled seed — the bootstrap R36 demoted it to) or **one
downloaded city file**. The reader picks; the default is built-in. Downloading never switches
the map by itself — `Use` does. The one exception: updating the city that is currently in use
re-attaches the new file, because the reader already made that choice and the update is the
same choice with fresher data.

Switching rebuilds the data layer (the composition root re-boots `DataLayer` and the view tree
under it). A downloaded file that fails to attach or validate is deactivated and the app falls
back to the built-in inventory rather than failing to launch — the row then simply shows the
city as installed but not in use.

Multi-city simultaneous attach is recorded as future work riding on a read-layer design, not as
a gap in this one.

#### 2. Where it lives

- **You tab**, a new `City data` section between the export rows and Settings: one C10
  `IconTextRow` (title `Cities`, subtitle below) pushing a new `Route.cityDownloads`.
- The pushed screen is **Cities**: `ScreenHeader` back-circle screen, one card for the built-in
  inventory, then one card per city the manifest lists, in manifest order. That is the whole
  screen.

#### 3. What a city card says

Card chrome is the You tab's setting-card idiom (surfaceCard fill, borderCool, screen-17 row
metrics). Contents, top to bottom:

- **Display name** from the manifest (`display_name` — a civic fact entered at publish, never
  derived on device).
- **Coverage**, only when not `"full"`: `Covers <coverage> only` (e.g. `Covers downtown only`).
- **State line**, one of:
  - not installed — the download size, e.g. `81 MB` (ByteCountFormatter over manifest `bytes`);
  - installed and current — `Installed · <version>` (the raw R37 version string; this is a
    data-management screen and the string is the fact);
  - update available — `Update available · <version> installed`;
  - downloading — `Downloading…` with a determinate progress bar;
  - failed — `Download failed. Nothing was changed.` (state reverts to whatever was true
    before the attempt);
  - schema too new — `Needs a newer app`, detail line
    `This city's data is a newer format than this app can read.`
- **Affordances** (compact buttons, never more than two visible):
  - not installed → `Download`;
  - installed, current, not in use → `Use` and `Remove`;
  - installed and in use → the state label `In use` (not a button) and `Remove`;
  - update available → `Update` and `Remove`;
  - downloading → `Cancel`;
  - schema too new, not installed → no button at all — an affordance that cannot keep its
    promise does not get drawn (R39's rule, borrowed);
  - schema too new but an older compatible version is installed → the installed copy keeps its
    `Use`/`Remove`; only the update is refused.

The **built-in inventory card** carries the title `Built-in inventory`, the subtitle
`Ships with the app and cannot be removed`, and `Use`/`In use` only.

The manifest is fetched when the screen appears and is never persisted; a fetch failure renders
the built-in card, every installed city from disk facts alone, and one line:
`Couldn't check what's available. Downloaded cities still work.` While the first fetch is in
flight the screen says `Checking what's available…`. One download runs at a time.

#### 4. The contract with the bucket (data layer)

- **Base URL is app configuration** — `https://cypress-cities.t3.tigrisbucket.io`, a constant in
  the app, per R37.4; `base_url_hint` in the manifest is never read. All probes are GETs —
  Tigris has answered HEAD 200 beside GET 403 (server/README.md), so a HEAD reachability check
  is a false green by construction.
- **Manifest**: `GET <base>/manifest.json`, decoded strictly; `manifest_format != 1` is refused,
  unknown keys are ignored (R37 lets additive keys ride).
- **Schema gate, refused not deferred**: an entry whose `schema_version` exceeds the newest
  generation this build reads (`SeedDatabase.newestKnownSchemaVersion`, 14 today) is never
  downloaded. This is the fossil-install lesson pointed forward: "user_version N but build
  knows up to M" — a file from the future must be refused, not attached.
- **Download**: to a temp path in the library's own staging directory, never the final layout.
  **sha256 (CryptoKit) and byte count are verified against the manifest entry before anything
  else happens**; a mismatch deletes the temp file and changes nothing. Only a verified file is
  moved — an atomic same-volume rename — into the on-device mirror of the bucket's immutable
  layout: `Application Support/Cypress/cities/<id>/<version>/<id>.sqlite`. Disk is the record
  of what is installed; there is no parallel bookkeeping to disagree with it.
- **Update** = download-new-then-prune: the new version lands at its own immutable path,
  verified, before the old version's directory is deleted — the same "rewritten last" discipline
  the manifest itself uses (R37.2). A failed update leaves the installed version untouched.
- **The active choice** is a marker file (`cities/active-city`) holding the city id; absent
  means built-in. At boot the marker is resolved and the file **re-validated before attach**
  (seed-shape introspection plus the `publish_schema_version` gate read from the file's own
  `seed_meta` — the manifest said 14, but the file testifies for itself); a dangling or invalid
  marker is cleared and the built-in inventory attaches.
- **No schema migration.** The writable database is untouched by all of this; installed-city
  state lives on disk and in one marker file.
- **Attribution travels inside the file** (R37.3 keeps `inventories` and `seed_meta` in every
  city file), so the existing city-record surfaces (`CityRecordPresentation`) state the right
  source for whichever inventory is attached, with no new attribution UI.

#### 5. Seed-coverage constants become measured facts (R36 consequence c) — **STRUCK by R41/E205**

*This section ruled that `MapYearFilterCopy.undatedShareOfSeed` be measured per attached inventory
and rendered as the sentence `About <X in Y> trees have no recorded planting date…`. **R41 then
forbade the sentence itself** — no message accompanies a filter, categorically — so the measurement
had no consumer left. The sentence, the constant, and the aggregate that fed it were removed
together rather than left unread (tasks #178–#180, ERRATA E205). This section decided how the
sentence should be computed; R41 decided that it should not exist, and R41 is later and is the
owner's direct instruction. §§1–4 and §6 of this ruling are untouched.*

#### 6. What this ruling refuses

No store furniture: no prices, ratings, screenshots, hero art, or recommendations. No
auto-download and no background manifest refresh in #157 — R36's "background-refreshes when the
manifest says a newer version exists" needs a background-task design and lands with its own
ticket. No invented city names or coverage words: every civic string on the screen comes from
the manifest or the file, both of which got them from `publish_cities.py`'s hand-entered table.

### R44 — Tree or empty planting site is a filter, and it lives in the drawer (task #179, delegated)

*Written under the delegated design authority for #179. No mock covers this control — ROADMAP
§1 records that no mock covers the vacant-site state at all (DECISIONS constraint 21) — so this
ruling is the mock. Everything in it is built from vocabulary the app already uses.*

#### What this rules

The map can be narrowed to **sites with a tree** or to **empty planting sites**, from a control in
the `More filters` drawer. It is the third narrowing behind that control, after `Favorites` (R23.1)
and `Year` (#145).

#### 1 · Why it is in the drawer and was never a candidate for the row

R38 fixed the visible row at one horizontally scrolling line — `Yours · In bloom · Needs care ·
More filters`, plus `Clear filters` — on the owner's directive: "one row for filters, that's it."
A fifth resting chip would reopen a question the owner has now closed twice (#145, #166).

R23.1 called the drawer an **extension point** rather than a drawer with one thing in it, and said
what arriving there should cost: "one case and two switch arms, and no view changes at all." This
ruling is the first test of that claim by a narrowing that was not in the row first, and the claim
held — `MapExtraFilter.siteKind`, its two arms, and one arm in `MapFilterChips.drawer`.

#### 2 · A menu of three, not two toggle chips

The control is a `Menu` with `Tree or site` (clear), `Has a tree`, `Empty planting site` — the same
shape `Year` uses, for the same reasons R23.1 gives: a decade is a *value*, not a toggle, and the
system's platter is already a ≥44 pt target list, already Dynamic Type correct, already dismissible
by the gesture readers expect, and draws no SF Symbol (adding nothing to #130's five debts).

**Two toggle chips were considered and refused.** The arms are exclusive by construction — every row
is one or the other — so a pair of toggles would offer a both-on state and a both-off state that
both mean "the un-narrowed map", which is a control whose selected state is indistinguishable from
its resting state. That is the exact argument R23 used to stop `All` being a chip, and the argument
R23 §1 used to make `membership` single-select within itself.

#### 3 · The words, none of which are invented

DECISIONS constraint 15 forbids inventing civic or botanical content. Nothing here is invented:

- **`Site`** is the control's name. It is E107's own screen title for this record.
- **`Empty planting site`** — `SegmentedControl` already says `Vacant site`, E107's screen says
  `No tree at this site.`, and `MapPin` speaks `Planting site, no tree`. "Empty planting site" is
  the register of those three in a chip.
- **`Has a tree`** — the plain complement, phrased as an answer to "what is here" so the chip reads
  as a sentence: `Site: Has a tree`, `Site: Empty planting site`. That is `Year: 2010s`'s grammar,
  so the drawer's two value-carrying controls speak alike.

**There is deliberately no sentence anywhere in this control.** R41 forbids one, and a filter that
had to explain itself in prose beside the map would be task #180 arriving through a new door.

#### 4 · Where the boundary between the two arms is drawn

`MapSiteKind.of(TreeStatus)`, an exhaustive switch beside the status — the shape
`TreeStatus.acceptsNewContributions` uses, so that adding a status is a compile error rather than a
silent assignment to one arm (E95).

- `vacant_site` → **empty site**
- `alive`, `declining`, `dead_reported`, **`removed`** → **has a tree**

`removed` is the one arm worth arguing, and it goes with the trees. A removed tree is a *memorial*
record (`TreeStatus.isMemorial`, DECISIONS §3.17) — a tree the app knows about and can still show
you — and **R7 reserves the vacant-site presentation for a basin that never had one**. Folding
memorials into "empty planting site" would put them behind a label promising no tree was ever here
and would collide with R7 on the pin. So the binary is literally the one the seed draws.

The shipped seed carries only `alive` and `vacant_site`, so the other three arms are decisions about
data that does not exist yet, taken once and in the open rather than left to whoever adds the data.

#### 5 · What it composes with, including the contradiction it makes reachable

It is a term in the conjunction like every other dimension (R23 §1). Nothing is special-cased.

That makes one contradiction reachable: **`Empty planting site` + a decade returns nothing**, because
task #178 excludes vacant sites from a year narrowing. This is correct and is left alone. The
alternative — having one dimension clear the other — is the single-select behaviour R23 §1 was
written against, and it would silently discard an instruction the reader gave.

The map empties and says nothing, which is what the task #165 correction to R31 requires ("if
nothing matches, fine") and what R41 requires. The way out is the `Clear filters` chip, which is on
screen whenever any dimension is set, including one set behind the shut drawer (R23.1 §3).

#### 6 · Why this had to ship with #178 rather than after it

#178 removes 9,237 vacant planting sites from the year filter's answers. Those rows are, per
ROADMAP §1, "the single best answer to 'where could a tree go'" and E115 established that hiding
them is a status claim the app is not entitled to make. Shipping #178 alone would take away the one
way they were (accidentally, and dishonestly) findable and put nothing back. This control is what
makes #178 a correction rather than a disappearance.

#### What holds it

`CypressTests/MapFilterTests` — the two arms return only their own rows (parameterized over both,
read back from the seed by `trees.status` in an independent query), the empty-site arm actually
draws vacant sites, and the year/site contradiction returns nothing rather than letting one term
win. Red-proofed by inverting `MapSiteKind.statuses`, which reddens all three.

`extraFiltersAreDrivenByTheirOwnCases` already existed and required a new arm to compile — R23.1's
extension point catching its first new narrowing, exactly as designed.

### R45 — A species claim is corrected by whoever made it; everybody else reports it (tasks #86 and #124, delegated)

*Written under the delegated design authority for #86/#124, from the code and the migration rather than from the tickets — two of whose premises did not survive the check. Answers the governance question open since #15 and #58.*

Raised by tasks **#86** ("a species claim cannot be corrected once made") and **#124** ("flag a
manually-added tree's species as wrong"), which are one question asked from two sides. Open since
**#15** and **#58**. R19's precedent puts an answer of this kind in a ruling rather than an errata:
nothing here is a defect being repaired, it is a rule being chosen, and a rule chosen inside a bug
fix is a rule nobody reviewed.

The question: **who may supersede whose species assertion, with no moderator present?**

---

#### What was actually true before this round, and what was not

Verified against the code rather than the tickets, because two premises in these four tickets did
not survive the check.

- `species_assertions` existed **only in the read-only bundled seed** (`Tools/build_seed.py`), with
  the city's one `city_import` row per tree. `AppSchema` had no copy. That absence, not a missing
  screen, is why `SpeciesClaim` refuses a correction: there was nowhere to put one.
- The only writable species anywhere was `community_trees.species_current`, a bare TEXT column with
  no foreign key available to it, and the only edit to it that needs no history is the one where
  there is nothing to supersede. Hence `LocalAPI.claimSpecies`' two refusals — community rows only,
  first claim wins — the second of them written into the SQL as `WHERE species_current IS NULL`, so
  that two callers cannot both see NULL and the second one win.
- `ReviewFlag.Kind.wrongSpecies` has existed in the enum and in the `review_flags` CHECK since they
  were written, and **nothing raised it and nothing could resolve it**. `confirmedStatus` returns
  nil for it, so `confirmReview` and `dismissReview` throw `.validationFailed`;
  `ModerationTests` asserts exactly that. The vocabulary was there and the loop was not.
- **`community_trees` records no author at all** — no `user_id`, no `device_id`, no `client_uuid`
  owner. `TreeProfilePresentation.speciesNamedByContributor` says "a contributor", not "the
  contributor", and says why: the record cannot name which person. So on the day this ruling is
  written, **no species claim on this device is attributable to anybody**.

That last fact is the ruling's hinge and it is not in any ticket.

---

#### Decided

**An assertion may be superseded without review only by the identity that made it. Every other
correction is a claim against somebody else's statement, and it is recorded as one — a
`wrong_species` review flag — never as a silent overwrite.**

Three arms, and the third is the one that pays for the first two.

##### 1. Your own claim is yours to correct, with no moderator, for ever (#86)

`tree_names`' rule — "one active name per tree; first namer wins" (BUILD-PLAN §4, binding through
D15) — is the precedent `SpeciesClaim` reached for, and it was reached for slightly wrongly. That
rule exists to stop one contributor discarding another's statement. Where the two are the same
person there is no other statement to protect, and refusing is not protection, it is a refusal to
let somebody admit a mistake about a tree they were standing in front of.

Identity is `Attribution`: the signed-in account when there is one, this device otherwise (D9). Both
arms, because on this app an anonymous contributor is a real contributor and the account arrives at
the third save. The predicate is `ContributionOwner.isOwned(by:)`, which is `PhotoOwner`'s, already
carrying "delete your own photograph" — one predicate for "this record is mine to act on", not two
that will drift.

Nothing is overwritten even here. The claim keeps its row, gains `superseded_by`, and the correction
is appended. The history is what `species_assertions` is for, and a self-correction is history like
any other.

##### 2. Somebody else's claim is not yours to overwrite, with or without a moderator (#124)

You report it. `flagWrongSpecies` raises a `wrong_species` flag and changes nothing else:
`species_current` still says what the namer said, because a report is a disagreement on the record
and not a decision. A person who thinks the species is wrong now has a move that is neither "shrug"
nor "overwrite a stranger", which is what #124 asked for.

Refused when the claim is your own — you correct it, and a screen offering both would be offering a
worse version of the same act. Refused when a report is already open: BUILD-PLAN §6's "two offline
users flagging the same tree produce two flags on one thread, not a conflict" governs the **sync
merge** between devices that could not see each other, and this is a local write by somebody looking
at the open report on their screen.

##### 3. A claim owned by **nobody** is nobody's to overwrite either

This is the arm the migration forces and the one worth arguing.

Every species claimed before AppSchema v14 has no recorded author, because `community_trees` never
had a column for one. The v14 backfill could have written this device's id into those rows — every
community tree in the database really was added on this phone, since `LocalAPI.addTree` is the only
writer and nothing syncs anyone else's rows down — and AppSchema v12's backfill reasoned in exactly
that way for `photos`.

It is refused here, and the difference between the two cases is the whole of it. v12 was retro-fitting
who *took a photograph*; being wrong over-attributes a JPEG on the owner's own screen. This column
decides **who may overwrite somebody's statement without asking**, and a claim attributed to this
device by assumption hands that authority to whoever is holding the phone. The honest value is the
one the database can support, and the database supports "unknown".

So a pre-v14 claim is `.nobody`'s, `isOwned(by:)` is false for everybody — the same answer it already
gives for a photograph whose author deleted their account — and correcting one goes through the
report route. The cost is real and small: a handful of beta rows lose the one-tap fix and keep a
two-tap one. The alternative was to write a fact the record does not hold.

##### Resolution: correcting the species **is** confirming the report

There is no second verb to forget. `correctSpecies` appends the correction and moves any open
`wrong_species` flag on that tree to `confirmed`, in one transaction. `dismissSpeciesReview` is the
other half — the report answered by leaving the species alone, nothing appended, on E170's argument
that a queue whose only verb is "agree" is not a review.

Who may answer a report:

- **a lead** (`canConfirmReviewFlag`: moderator, admin, coordinator — DECISIONS §3.7), and for
  `correctSpecies` **only in answer to a report that exists**. The role is authority to resolve
  somebody's report, not a licence to rewrite any species at will. A lead with an opinion and no
  report in front of them is a contributor and takes arm 1's route;
- **the author of the disputed claim**, for both verbs. This is what keeps the loop closed on a
  phone with no lead on it. Without it, "with no moderator present" would have an answer this
  project has already paid for once: a kind that can be raised and never resolved (E170).

"No moderator present" is otherwise not a special case. The local beta grants the lead role through
the You tab's DEBUG affordance, which is how every `appears_removed` flag is resolved today; this
seam inherits that route rather than inventing one.

---

#### What this deliberately does not build

Named so the next round does not read the absence as an oversight.

- **No queue.** The report is answered on the tree's own profile, where the species is. A second
  section in the You tab would be a moderation product, and `openReviews` serves
  `statusReviewKinds` — deriving it from `confirmedStatus != nil`, which is nil for `wrongSpecies`
  and must stay nil.
- **No reputation, no voting, no confidence weighting.** `confidence` is a column because BUILD-PLAN
  §4 has one; nothing on device writes it. A rule that counted agreements would need a model of who
  is agreeing, and this is a correction path, not a verification tier (C-M5 is Phase 2, DECISIONS
  §2.4).
- **No correction of a city row's species.** `claimSpecies` already refuses one with `.forbidden`
  and `correctSpecies` refuses it the same way. A community counter-claim over an inventory row is
  what D16 actually wants — the community layered on the merged national inventory — but reading it
  back needs a species-override path parallel to `tree_status_overrides`, touching the map, the
  profile, the almanac and the export. That is a ticket, not a clause. **Raising `wrong_species` on
  a city row is refused too, and refused deliberately**: a report nothing can resolve is the E170
  defect, and shipping the raise ahead of the read path would be shipping it.
- **Nothing goes through the outbox.** `claimSpecies` never did; assertions follow it. When
  `POST /trees/{id}/species-assertions` exists, the chain is already the right shape to send.

---

#### The seam, and why it is beside E170's rather than inside it

`ReviewFlag.Kind` now answers `resolution` — `.status(TreeStatus)`, `.speciesAssertion`, or
`.byHand` — and `confirmedStatus` is derived from it instead of switching a second time.
`statusReviewKinds` is unchanged and still derived from `confirmedStatus != nil`, so the lead queue
does not gain a species report, and `speciesReviewKinds` is derived from the same switch for the
seam that does serve it.

E170's property is preserved exactly: one exhaustive switch that both the raise and the resolve
read, so a kind that can be raised and not resolved is a compile error. What is *not* done is the
tempting one-liner — pointing `wrongSpecies.confirmedStatus` at some status to make it resolvable.
Confirming a wrong-species report must never write `trees.status`. A species correction that quietly
marked a tree removed would not be a repeat of E170; it would be the worse version of it, because
the queue would look right while the trees moved.

### R46 — "This tree does not exist at all" is its own review kind, not a removal (task #125, decision only)

*Decided by the writable-v14 migration author, 2026-08-02, because a new `review_flags.kind` value is nearly free inside a migration being written and a whole schema version afterwards. Only the CHECK value landed; #125 still owns what the kind means and what raises it.*

Decided for task **#125**, which asked only for the decision this round; #125's surface and its
resolution path land later. Nothing was built here beyond one string in a CHECK constraint that
AppSchema v14 was rebuilding anyway.

**Decided: a new `review_flags.kind` value, `never_existed`. It does not reuse `.appearsRemoved`.**

#### Why not reuse it

Because of what confirming `.appearsRemoved` *writes*. `ReviewFlag.Kind.confirmedStatus` maps it to
`TreeStatus.removed`, and this product has settled what that means: `acceptsNewContributions` goes
false, the profile becomes a memorial record (screen 19), and the map pin is spoken as "Removed
tree, memorial" (E170, R19). A record that never had a tree behind it would get a memorial page for
a tree that never lived.

That is the map asserting something untrue, which is the argument R7 made when it refused to let the
vacant site borrow `.removed`'s drawing, and the argument R19 restated for the standing dead tree.
The same argument decides this one; it would be strange to make it twice and then not make it a
third time in the case where the assertion is not merely imprecise but false.

The second reason is downstream. D16 makes the merged national inventory the product rather than a
seed-building convenience, and `removed` and `never_existed` are different facts to publish into it:
one is a lifecycle event that happened on a date, the other is a row that should not be in the
inventory. A consumer that cannot tell them apart mis-states a city's history, and the whole point of
the merged table is that it does not.

#### The argument against, and why it loses

A reporter standing at the site often cannot tell "the tree is gone" from "there was never a tree
here", and asking people to distinguish what they cannot observe is the mistake D3 was written about.

It loses because the cases that motivate #125 are the ones where the reporter *can* tell: a record in
the middle of a building, a duplicate two metres from another pin, a community add that was a
mis-tap. A stump, an empty basin, fresh cut — that is a removal, and screen 05 already offers it. The
two are distinguishable exactly where it matters, and where they are not, a reporter picks "removed"
and is right often enough that nothing is lost.

#### What landed, and what did not

Only the CHECK value, in AppSchema v14's rebuild of `review_flags`. SQLite cannot widen a CHECK in
place, so the alternative was an entire migration of its own for one string.

`ReviewFlag.Kind` gains **no case**. #125 owns what the kind means, what raises it, and what
confirming it writes — which is a real open question, since `TreeStatus.vacantSite` already exists
and may be the truthful confirmed state, in which case the kind belongs on the status seam and the
existing queue rather than beside it. Until #125 lands, nothing can write `never_existed`: the store
binds `Kind.rawValue` and there is no case to bind. The widened CHECK is a reservation, not a
reachable state, and `ReviewFlagKindTests` asserts both halves — that the column accepts the value
and that the enum does not yet offer it.

### R47 — The species suggestion list offers only names a reader can read (task #103, delegated)

*Written under the delegated design authority for #103. R25 specified six things about the suggestion list and none of them is what it does with a row whose name is not a name; this is that gap.*

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge
and rewrites the citations in `Cypress/Data/Store/SpeciesQueries.swift` and
`CypressTests/SeedStubNamingTests.swift`.*

---

**What was delegated.** Task #103 raised half of itself in priority: not "canonicalise the species
name in the builder", which is a corpus repair with an obvious right answer, but "decide what the
suggestion list does with a stub row at all", which is a design question about a screen. R25 (task
#109) put a species list under screen 01's search field and specified six things about it; none of
them is what the list should do with a row whose name is not a name. This is that gap, answered
under the standing delegation.

**The measurement, taken from the shipped corpus rather than from the ticket.** A species the ingest
could not read keeps the raw source string as its scientific name. Before #103 the seed carried
fifteen of them, standing under sixty-five trees out of 198,625. Every one had the same shape — an
empty scientific half in front of DataSF's `::` separator — so every one rendered in the list with a
visible `:: ` prefix:

| what the reader saw | line 1 | line 2 |
| --- | --- | --- |
| the stub | `Arbutus 'Marina'` | `:: Arbutus 'Marina'` |
| the real species, in the same list | `Hybrid Strawberry Tree` | `Arbutus 'Marina'` |

Two rows, one plant, and the reader has no way to tell which to press. The second line is labelled
by position as the scientific name; `:: Arbutus 'Marina'` is not a scientific name, it is our
parser's failure quoted back at someone looking for a tree.

**The builder half went first, and it changed the size of this question.** `Tools/build_seed.py`'s
BOTANICAL/COMMON swap now reads a miscased genus and a quoted cultivar, so fifty-eight of those
sixty-five trees merged into the species they were always naming and seven duplicate rows left the
catalogue. **Five stub species and seven trees remain**, and they are the residue that cannot be
merged on form alone: `:: Magnolia`, `:: 9662`, `:: Chitalpatashkentensis`, `:: Magnolia Little Gem`,
`:: Podocarpus Gracilor`. Two of those five still shadow a real species (`Magnolia` and
`Podocarpus gracilor`). So canonicalisation alone does not close this, exactly as the ticket said.

---

#### The ruling

**1 · The list does not offer a species whose name the ingest could not read.** Not a merge, not an
honest rendering — the row is not there.

**Merging is not the list's to do.** Where a merge is safe it has already happened, in the builder,
on evidence: the city wrote a name and the only thing wrong with it was case, or a cultivar in
quotes. The five that remain are unmergeable *because nothing in them says what they are* —
`Podocarpus Gracilor` is probably `Podocarpus gracilor` and `:: 9662` is probably a work-order
number, and "probably" is the word that disqualifies it. Asserting either from the client would be a
synonymy no source states, which is the judgment `QSPECIES_NAME_CORRECTIONS` already refuses to make
in the one place that has the whole corpus in front of it. A screen that has one query's worth of
rows is not better placed to make it.

**Rendering them honestly fails for E126's reason.** E126's principle is that a state a reader
cannot interpret is worse than one that is not drawn: a failed read that drew the cold-start screen
was "invisible by construction rather than ugly". A `:: ` prefix is the same defect facing the other
way — it is not invisible, it is *unreadable*, and it is unreadable in the one field a reader uses
to decide whether this is the tree they meant. There is no copy that fixes it, because the honest
sentence is "the city's record of this tree does not say what it is", and that is a sentence about
the seven trees, not about the species the reader was searching for.

**2 · The rule is applied in `SpeciesQueries.searchSQL()`, so it holds on both surfaces.** The same
read feeds the map's suggestion list and the add-tree species picker
(`SpeciesPickModel`). Filtering in `MapSuggestions.init(matches:)` would fix the dropdown and leave
the picker offering `:: 9662` as something to record a tree as — which is worse, because that one
writes. `MapSuggestionTests.typingDropsAList` asserts the one-read-two-surfaces invariant; this
ruling keeps it.

**3 · The predicate is the name's shape, and the fact it stands for is asserted beside the seed.**
The exact statement of "the ingest could not read this" is `species_map.is_stub`. It is not what the
query asks, and the reason is measured: `species_map` carries no index on `species_id`, so a
correlated `EXISTS` over it is a scan per candidate row, and it fails
`SpeciesSearchTests.searchStaysOnItsCoveringIndexes`. Adding that index would change
`Fixtures/seed/schema.sql`, and the per-city files already published at seed schema 14 would not
have it — the gate would pass against the bundled seed and the scan would happen against a
downloaded city.

So the query filters on `scientific_name NOT LIKE ':: %'`, and
`SeedStubNamingTests.theMarkerAndTheProvenanceFlagAgree` proves that the marker and `is_stub` select
the same rows in the seed as built. That is what makes the cheap predicate a statement rather than a
guess about the shape of the data, and it is what will fail — loudly, next to the seed — if a future
ingest ever mints a stub that does not carry the marker.

**4 · The seven trees keep their pins.** This is a rule about a *name list*, not about the map. The
trees are still on screen 01, still tappable, still openable; what a reader cannot do is arrive at
them by typing a name, and there was never a name to type.

---

#### What this does not settle

**The corpus holds the same plant under several spellings, and #103 does not touch it.** `Arbutus
'Marina'`, `Arbutus marina` and `Arbutus ‘Marina’` — straight quotes, no quotes, typographic quotes
— are three species rows for one plant, and there are more like them (`Platanus acerifolia
'Columbia'`, `Platanus x acerifolia 'Columbia'`, `Platanus x hispanica 'Columbia'`, `Platanus
hispanica 'columbia'`). The suggestion list shows them all, and a reader typing `marina` still sees
duplicates. That is the ticket's "one species appears twice" complaint in its general form; the
stub half of it is fixed here, and the rest is a synonymy question with no source behind it.
Recorded in `ERRATA E208`, not fixed.

**The species page is out of scope and still renders the raw name.** A tree whose species is
`:: Magnolia` shows that string wherever the species name is drawn. It is seven trees, and the fix
is not a filter — you cannot omit a tree's own species from its own page — so it wants its own
ticket and probably its own sentence of copy.

### R48 — Screen 07's count card names the population it counted, and that population is not a city (task #181, delegated)

*Written under the delegated design authority for #181. The first member of the San-Francisco-assumption family where R28's per-row mechanism is structurally unavailable — screen 07 has no tree to ask.*

*Written under the delegated design authority for #181, which covers the copy on this card and
nothing wider. UNNUMBERED — the orchestrator splices the number at merge.*

---

#### The reported defect is the smaller half of the real one

#181 reads: the species page hardcodes `In San Francisco` on its citywide count card, so it says San
Francisco to a reader standing in San Jose. That is true. It is also not the worst of it.

**The number under that label was never San Francisco's.** `SpeciesQueries.cityTreeCount` carries no
id-space predicate — it is `COUNT(*)` over every standing tree of the species in the attached
inventory — and the shipped bundle is fused across two id spaces (`sf`, 145,837 trees; `us-ca-sj`,
52,788). Measured on the shipped seed, on species that stand in both:

| species | San Francisco | San Jose | the card printed |
|---|---:|---:|---:|
| Crape Myrtle | 97 | 3,649 | `In San Francisco · 3,746` |
| Chinese Pistache | 431 | 2,026 | `In San Francisco · 2,457` |
| Ornamental Pear | 2,160 | 1,344 | `In San Francisco · 3,504` |
| Southern Magnolia | 5,115 | 983 | `In San Francisco · 6,098` |

A San Francisco reader looking up Crape Myrtle was told their city holds 3,746 of them. It holds 97.
So the card was wrong for **every** reader, not only for the one standing in the second city.

#### Why the obvious fix is refused

The naive repair — resolve the tree's city and say `In San Jose` to a San Jose reader — fails twice.

1. **It would put one city's name over a two-city number.** The count is not scoped by id space, so
   any single city name is a mislabel; swapping which city is mislabelled is not a fix. Scoping the
   count instead would be a different change with its own consequences, and it is not what the
   ticket asked for.
2. **There is no tree on this screen to ask.** `SpeciesModel` is constructed from a species id
   alone, entered from a grove tile, the search list or the map legend. R28's mechanism — the row
   states its own inventory through `LocalAPI.provenance(of:in:)` — has no row to run against here.
   This is the first member of the family where R28's answer is structurally unavailable, which is
   worth stating because the family's habit is to be fixed the same way each time.

#### The ruling

**The label names the population that was actually counted: `In this inventory`.**

Under R43 exactly one inventory is attached at a time — the built-in fused bundle or one downloaded
city file — and every read on the screen is qualified against it. `inventory` is R43's own word for
that unit (`Built-in inventory`, "one inventory is attached at a time", `In use`), so this borrows
vocabulary the reader has already met in Cities rather than coining any.

The card is now exactly true in both configurations R43 permits:

- **built-in bundle** — the count spans San Francisco and San Jose, and the label claims neither;
- **a downloaded city file** — the count is that city's, and the label is still true of it.

**R28 §3 is the precedent and it is followed rather than extended.** Faced with a label too small to
carry an inventory's published name, R28 made the section header state the *category* — `What the
city has on file` — and let the provenance line inside the section name which one. Its reasoning
transfers unchanged: *"A constant that is true everywhere is not the same defect as a constant that
is true in one city."* `In this inventory` is that constant for this card.

#### What this ruling does not do

- **It does not scope the count.** Adding `AND t.id_space = :space` would make the card a per-city
  number and is a different product question — which city, resolved how, on a screen with no row.
  If it is ever wanted, the honest shape is a scoped count *and* a label naming the scope, decided
  together. Noted, not taken.
- **It does not touch `Near you`.** That card was fixed by #141 and is scoped through
  `AlmanacScope`; its label is already city-neutral and its number already honest.
- **It does not rename the inventory anywhere else.** No shared identifier changed.

#### The mock pin this overrules

ARCHITECTURE §5 rule 8 makes departing from a drawn mock a decision rather than a commit.

| pinned where | drawn | now | why |
|---|---|---|---|
| SCREENS.md 07 §5 | `In San Francisco` → `1,204` | `In this inventory` → `1,204` | the mock was drawn when the seed held one city, and the number it labels has never been one city's since |

`mocks/cypress-mocks.html` is not edited — it is the drawing, and a drawing is a record of what was
drawn (R28's rule).

#### What holds it

`CypressTests/SecondCityGeographyTests.theCountCardNamesThePopulationItCounted` — the family's own
seed-backed suite. It resolves at runtime a species the seed holds in **both** id spaces, asserts
`cityTreeCount` equals the sum of the two (so the count provably spans two cities, which is what
makes any city name a lie), and then asserts the label contains none of `San Francisco`, `San Jose`,
`SF`, `DataSF`. Markers rather than a fixed string, so swapping one hardcoded city for another
cannot satisfy it.

Red-proofed by restoring `In San Francisco`:

> `Expectation failed: !((SpeciesCopy.cityCountLabel → "In San Francisco").contains(marker → "San Francisco") → true)`

### R49 — `This season` is a heading over three clocks, and the note says so (task #177, delegated)

*Written under the delegated design authority for #177, from the three queries that actually feed the block. Checked against R41 and E205 first: the heading is a static micro-label over a content block, not a filter, so R41's categorical ban does not reach it.*

*Written under the delegated design authority for #177, which covers this tooltip's wording and
where it lives. UNNUMBERED — the orchestrator splices the number at merge.*

---

#### First: R41 does not reach this, and that was checked before anything was written

R41 forbids any message accompanying a **filter**, categorically, with three sanctioned channels
(R23.1: chip fill, a count on the chip, the spoken value) and no fourth. The brief was right to make
this a gate, so it is answered first.

**`This season` is not a filter.** It is a static micro-label — `AlmanacCopy.seasonLabel`, drawn by
`AlmanacView.seasonBlock` — over a block of up to three C10 rows on screen 12. There is no chip, no
selection, no toggle, no state, and nothing the reader can set. R41's own test is *"does text appear
because a filter did something?"*; nothing on this block responds to a filter, because the almanac
has none. E205 confirms the scope by showing what R41 actually reached: `MapFilterStatus`, a capsule
on the map glass under the chip row, which rendered *only* when `filter.isActive` or
`filter.decade != nil`.

The almanac already carries two permanent explanatory sentences that nobody has read R41 against —
`areaNote` (R29) and `outOfRangeBody` (E182) — because they explain a *surface*, not a narrowing.
This note is the third of that kind.

If a future reader disagrees: the test to apply is not "is there explanatory text on screen" but
"did a filter cause it". Nothing here did.

#### What the heading is actually over

Read from the code that computes the rows, not from the heading and not from the ticket:

| row | what bounds it | is it "this season"? |
|---|---|---|
| **First bloom of the year** | `visits.captured_at >= AlmanacWindow.yearStart` — January 1 of the current calendar year | **No — year-to-date.** In December it is still March's sighting. Its own drawn title already says `of the year`. |
| **The elder** | `ORDER BY t.planted_on LIMIT 1` — **no window at all** | **No — nothing.** The same tree in January as in July, every year, until an older record arrives. |
| **Newest neighbors** | `t.planted_on BETWEEN` `AlmanacWindow.currentSpring` — March 1 to May 31 of the current year | **No — a fixed window.** It does not draw before March, and from June to December it keeps saying `planted this spring` about trees planted in the spring that ended. |

**So none of the three is scoped to the current season, and one of them is not scoped to time at
all.** The heading is the only thing on the block claiming a season.

That is the unflattering finding the brief anticipated, and the note says it rather than papering
over it.

#### The ruling

**A one-line note under the micro-label, assembled from the rows that actually drew, naming each
row's own window and stating plainly that they differ.**

With all three rows present it reads:

> Each row keeps its own window: the first bloom is this year's earliest, the elder is the oldest on
> file in any season, and the newest neighbors were planted March to May.

##### Why a line under the heading rather than a tap-to-reveal tooltip

The ticket said "tooltip"; where it lives was delegated. Three reasons for the line:

1. **The app has no tooltip idiom.** There is no popover, no info button, no disclosure control
   anywhere in `Cypress/DesignSystem/Components/`. Building one for this would be inventing UI for a
   screen whose states are already over-specified, and R43's discipline — build from the app's
   existing vocabulary — points the other way.
2. **The screen already does this exact job in this exact form.** `areaNote` is a muted sentence
   directly under the header saying which promise a pill is making, because "the pill alone is too
   quiet" (R29). This note is that argument applied one heading down, and it is drawn in `areaNote`'s
   type and colour (`CypressFont.body125`, `CypressColor.textMuted`) for that reason.
3. **The fact reframes rows the reader is looking at now.** A reader who believes `The elder` is a
   seasonal pick has already misread the block; hiding the correction behind a tap serves the reader
   who already suspected something was off, which is not the reader who needs it.

##### Why it is assembled rather than written whole

`AlmanacCopy`'s own header rule: *"Every sentence with a number in it is assembled rather than
templated wholesale, so that the parts which are not true can be left out."* The note obeys it. A
clause about the bloom is never written when no bloom drew, and with one row the note states that
row's window and makes no claim about windows differing. It is `nil` exactly when `seasonRows` is
empty — the block does not draw then, and a note explaining three absent rows is the
heading-over-nothing defect with a sentence attached.

##### The months come from the constant

`March to May` is read from `AlmanacWindow.springMonths` through the reader's calendar and locale,
not written out, so moving the window moves the sentence. The read and its description cannot drift.

#### What this ruling does not do

- **It does not rename the heading.** `This season` is drawn verbatim in SCREENS.md 12 §2. Renaming
  a drawn micro-label is a mock departure, and #177's delegation covers the explanatory text, not
  the heading. **This is flagged deliberately: the honest conclusion of the analysis above is that
  the heading is a poor name for its contents, and a note is a smaller repair than a rename.** If
  the owner wants the heading itself reconsidered, the material is here and the change is one string.
- **It does not change any window.** Not the elder's absence of one, not the bloom's year-to-date
  bound, and not the March–May span that keeps drawing until December. Each is arguably worth its
  own ticket; none is copy, and #177 is a copy ticket.
- **It does not mention that the bloom row is computed from this device's contributions alone.**
  True, and material, but the `Almanac` type has a standing decision about it — the almanac "is
  honest but small until there is a server, and it says so by rendering nothing rather than by
  apologising." Adding an apology here would reverse that decision on one block. Considered and
  excluded, recorded so it is not re-opened by accident.

#### What holds it

Four tests in `CypressTests/AlmanacPresentationTests`, plus the note joining `renderedStrings` so
the suite's existing sweeps (no zeroes, nothing counting contributions) now cover it:

- `theSeasonNoteDrawsOnlyWithItsRows` — nil with no area and with no rows; present when a row drew.
- `theElderAloneIsNotDescribedAsSeasonal` — with only the elder, the note names neither spring month
  and does not mention the bloom. Asserted as *absence of the other rows' windows*, so a blanket
  "this season" claim cannot satisfy it.
- `theNoteAccountsForEveryDrawnRow` — all three subjects named, and the note states the windows differ.
- `thePlantingClauseTracksTheWindowConstant` — the clause names the months `AlmanacWindow.springMonths`
  actually bounds the read by.

Each was red-proofed, and one of the red-proofs found a real defect: read off a `Calendar` built by
identifier, `standaloneMonthSymbols` produced `M03 to M05`, because it reads the *calendar's* locale
and such a calendar carries none. The note now takes the reader's locale as its own parameter, as
every other sentence in `AlmanacCopy` already did.

### R50 — A record that never held a tree is withdrawn, not killed (task #125, delegated)

*Written under the delegated design authority for #125. `RULINGS R46` decided the kind and left
three questions open in its own words — "what the kind means, what raises it, and what confirming it
writes". This answers them, and refuses the answer R46 floated.*

R46 settled that "this tree does not exist at all" is its own `review_flags.kind`, `never_existed`,
and not a use of `.appearsRemoved`. AppSchema v14 widened the CHECK; `ReviewFlag.Kind` gained no
case, so the value was a reservation nothing could write. This is the rest of it.

---

#### The question R46 left open, and the answer it guessed at

R46 wrote: *"`TreeStatus.vacantSite` already exists and may be the truthful confirmed state, in which
case the kind belongs on the status seam and the existing queue rather than beside it."*

**It is not the truthful confirmed state, and the kind does not belong on the status seam.**

A vacant site is a planting *site* with its tree missing. R7 gave it a hollow ring rather than the
removed pin's grey dot precisely so the map would not say a tree had stood there; the drawing asserts
*a place a tree could go*. The records #125 exists for do not have one. R46's own motivating cases
are a row in the middle of a building, a duplicate two metres from another pin, and a community add
that was a mis-tap — and there is no planting site at any of them. Writing `vacantSite` would replace
one false assertion with a quieter one, which is the move R7 refused for the vacant site and R19
refused for the standing dead tree. It would be strange to make that argument three times and then
decline to make it a fourth in the case where the assertion is not merely imprecise but false.

The second reason is the seam. `ReviewFlag.Kind.confirmedStatus` is derived from `resolution`, and
`statusReviewKinds` is derived from `confirmedStatus != nil` — E170's property, that one exhaustive
switch serves both the raise and the resolve. Pointing `neverExisted` at any status is the one-line
change that makes the kind resolvable, and it would enrol record defects in the lead's *status*
queue, where a confirmation writes `tree_status_overrides`. E170's defect was a queue that could not
see half of what was raised; this would be the inverse and worse — the queue would look right while
the trees moved.

#### Decided

**Confirming a `never_existed` report withdraws the *record*. The `community_trees` row is
soft-deleted and `trees.status` is never touched.**

`ReviewFlag.Kind.Resolution` gains a fourth arm, `.recordWithdrawal`, beside `.status`,
`.speciesAssertion` and `.byHand`. `confirmedStatus` stays nil for it, `statusReviewKinds` does not
grow, and `recordReviewKinds` is derived from the same switch — R45's shape for the species seam,
applied a second time for the same reason.

`.byHand` was the other candidate and is refused. `.byHand` means nothing is written, and it fits the
two kinds that hold it: `removedButActive` is the weekly diff saying a person should look, and
`duplicateSuspected` has no surface raising it. A kind a *person* raises from a *screen* must have a
verb that closes it, or it is E170's defect with a politer name.

A soft delete rather than a `DELETE`, on two grounds. Every read in `CommunityTreeStore` already
filters `deleted_at IS NULL`, so one column takes the pin, the profile and the species routes away in
one write without a single reader learning a new rule. And the row survives: under D16 a confirmed
"this was never here" is a fact the merged national inventory wants — precisely the fact R46
distinguished from a dated lifecycle event — and an erased row cannot be published.

#### Community rows only, and the refusal is the substance rather than the shortfall

**A `never_existed` report against a city row is refused with `.forbidden`.**

A city row lives in the ATTACHed read-only seed. Nothing on this device can withdraw one, and there
is no suppression path parallel to `tree_status_overrides` for a row that should not be in the
inventory at all. So a report raised against a city row is a report nothing present can resolve —
which is the state E170 exists about, shipped deliberately. R45 refuses `flagWrongSpecies` on a city
row in the same words and for the same reason: *shipping the raise ahead of the read path would be
shipping it.*

This is the largest limit on #125 and it should be read as one. The owner's ask was about the map,
and the map is overwhelmingly the city's rows. What lands is the half that can be honestly closed.

**The other half is a ticket, and it is the same ticket R45 already named.** A community
counter-claim over an inventory row needs a suppression path parallel to `tree_status_overrides`,
and reading it back touches the map, the profile, the almanac and the export. R45 named it for
species; `never_existed` is its second customer, which is an argument for building it once rather
than for smuggling half of it in here.

#### Who reports and who resolves

**Everybody reports. Only a lead resolves.**

R45's arm 1 — "your own claim is yours to correct" — has no counterpart here, and the reason is R45's
own finding rather than a choice: **`community_trees` records no author at all.** No `user_id`, no
`device_id`, no owner column. So no record on this device is anybody's to take back, and R45's arm 3
applies verbatim — a record owned by nobody is nobody's to withdraw without asking.

The lead gate is `userRole.canConfirmReviewFlag` (moderator, admin, coordinator — DECISIONS §3.7),
the gate the status queue already uses, on the write, so a surface drawn in error cannot withdraw a
record. In the local beta the role is granted through the You tab's DEBUG affordance, which is how
every `appears_removed` flag is resolved today; this seam inherits that route rather than inventing
one.

Both verbs exist. `withdrawRecord` confirms, `dismissRecordReview` keeps the record — E170's
argument that a queue whose only verb is "agree" is not a review.

#### The surface

**The tree's own profile, under the species controls. No queue.**

R45's reason holds unchanged: the report is answered where the thing being disputed is, and a second
section in the You tab would be a moderation product. The three controls form a ladder down one
record — name what it is, say the name is wrong, say there is nothing here to name — and the last
rung belongs beside the first two rather than on a card of its own.

`RecordDefectOffer` carries the decision on the profile payload, `SpeciesCorrectionOffer`'s shape and
for its reason: the answer needs the viewer's role and an open-flag read, and a presentation holding
either would be holding something it cannot see. A city row is `.unavailable` rather than
`.reportable` — a control that exists only to be refused is worse than no control.

**Withdrawing closes the screen.** `LocalAPI.treeProfile` now refuses a withdrawn community row, so
the alternative is not a stale profile but a failure sentence reading "this tree could not be found"
at the person who just withdrew it. The view pops.

#### The copy, which had to be written against the build rather than against the architecture

The obvious sentence was the one two neighbouring surfaces already use — *"This goes to a community
reviewer. The city is not notified."* It is not available, and the reason arrived mid-ticket from the
owner.

**There is no contribution sync.** #158 is unbuilt and unscheduled; beta is about five people with no
accounts. The outbox drains through `APIOutboxTransport` into `LocalAPI`, which writes this phone's
own tables. Nothing uploads and nothing downloads anybody's rows. A report therefore reaches no other
reader, ever, during beta.

So *"this goes to a community reviewer"* names a destination the report does not arrive at, which is
structurally the sentence §3 constraint 3 forbids — D16(a) made the city version permanent — with a
different noun. The rule underneath both is that the app never says it did a thing it did not do.

The notice reads:

> This is kept on this phone and shows on this record. The city is not notified, and Cypress cannot
> yet carry a report to anybody else’s phone.

It says where the report stays and what it does there, then states the two limits plainly. E126 is
why the second half is said out loud rather than left as a silence for the reader to fill in.

The negation is spelled `The city is not notified` and **not** `Nothing is sent to the city`. The
first draft used the second, and the suite's own guard caught it: the guard is a substring check for
the forbidden claim, and a claim's negation contains the claim.

Two more words are chosen rather than defaulted. The control says **"Report that there is no tree
here"**, not "report this tree as missing" — *missing* is what a removal is, and the whole of R46 is
that the two must not be said with one word. The verb says **"Withdraw this record"**, not *delete*
(which would promise an erasure that does not happen) and not *remove* (which is
`TreeStatus.removed`'s word, and lending it to the one act that must never read as a removal would
undo R46 in the label).

#### What this deliberately does not build

Named so the next round does not read the absence as an oversight.

- **No queue, no reputation, no voting.** R45's list, unchanged, for R45's reasons. This is a report
  path, not a verification tier.
- **No withdrawal of a city row.** Above; it is a ticket.
- **Nothing through the outbox.** The flag is a local write, like `flagWrongSpecies`. When
  `POST /trees/{id}/review-flags` exists the chain is the right shape to send.
- **No `duplicate_suspected` route.** A duplicate is one of R46's motivating cases and it arrives
  here as "there is no tree at *this* record", which is true of the duplicate pin. Giving
  `duplicateSuspected` its own raise as well would be two controls for one observation; it stays
  `.byHand` and unraised.

#### The pending errata beside this

`ERRATA E211` — why **#120** did not land: the
retracted schema claim was retracted correctly and a different, live schema blocker is underneath it.

`ERRATA E212` — two shipped sentences make the
promise this ruling refused to make, on screen 05 and on the species control. Flagged, not changed:
they are R45's and E170's own words and belong to whoever owns those.

### R51 — The two §9b cards that were reading one city's vocabulary against another's rows (task #186)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `p1/round8-b`. Latest numbered at time of writing: R49, E209.*

---

#### What was decided

Two decisions, both under the standing delegation for copy and behaviour the mocks do not cover.

**1 · `CityRecordPresentation.listedAsText` declines outside `sf`.** It is a reading of DataSF's
`PlantType` — a column that says `Tree` on almost every row, so "suppress the agreement and draw the
disagreement" is the right rule for it. San Jose's `plant_type` is not that column; it is `GROWSPACE`
(`SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS`), a growing-space category. The rule declines rather
than being taught the other vocabulary.

**2 · A card is not drawn for a value that states no value.** `N/A`, `Unassigned`, and a string with
no letter or digit in it (San Francisco's bare `:`) draw nothing, on the `Site` card on screens 03/14
and 19 and on every card in the §9b section.

#### Why R24 settles the first one, rather than a new judgment

R24 already says it: *a derivation over a publisher's own vocabulary is qualified by the id space it
was written for, and must decline outside it*, and the test is **"was this rule written from this
publisher's documentation"** — not "does it return something sensible for the new source". For
`GROWSPACE` it was not. This is the same shape as `pruningNote(idSpace:)` and
`LandContext.inferred(from:idSpace:)`, and it is applied here in the same words.

R24 was written about a function that *answered confidently and wrongly* for all 52,788 San Jose
rows. This is the identical failure one column to the left, and R24's own "what it does not decide"
paragraph names it: *whether the six `city_record` columns should be holding another publisher's
differently-meaning columns at all.* That deeper question is still open (see the pending errata and
#134); nothing here answers it.

##### Why the card is not taught San Jose's vocabulary instead

Because Cypress has not read San Jose's published metadata for `GROWSPACE`. Writing a branch that
renders `Park Strip`, `Well/Pit`, `Tree Lawn` and `Open/Unrestricted` under some label would mean
this app stating what those codes mean in San Jose's asset system on the strength of one adapter's
column list. DECISIONS constraint 15 forbids exactly that, and R24 is the same rule for derivations.
A San Jose reader gets one fewer card, and that is the honest outcome rather than a gap to fill.

#### Why the second decision is *not* an R24 case, which matters

`N/A` is not San Jose's dialect. It is what a data-entry form emits for "no answer", in any city, and
recognising it is not a reading of any publisher's vocabulary — which is why it carries no id-space
guard and applies everywhere, including to San Francisco's own `:`.

The argument is `plotSizeText`'s, already settled in this file for `Width 0ft` on 17,254 rows: **a
basin zero feet wide is not a measurement of a basin, it is the shape "not measured" takes in a form
that wanted a number.** `N/A` is that shape in a form that wanted a word. A card is a claim that the
city answered; drawing the placeholder is Cypress asserting an answer the city did not give.

Nothing is corrected, merged, re-ranked or filled. Real values pass through verbatim: `Park Strip`
and `Sidewalk: Curb side : Cutout` are printed as the city wrote them, because knowing that `N/A` is
not a place requires no opinion about what `Park Strip` is.

#### What a San Jose reader is left with, checked rather than assumed

E126's half that governs here is *a surface with nothing on it must say why*. It is **not engaged**,
and that was measured rather than hoped: every one of the 52,788 San Jose rows carries `caretaker`,
and 50,630 carry `legal_status`, so the section still draws its cards, its header and its provenance
line on every row. Photographed on the simulator before and after on record `#100002`
(945 W JULIAN ST): the two `N/A` cards go, `Legal status — Private`, `Cared for by — General Fund`
and `From the City of San Jose Street Tree inventory, July 31, 2026.` stay.

This is `pruningNote`'s argument reused, and it is the reason no new copy was written. **No sentence
was invented for this state, because the state is not "we cannot tell you" — it is "the city did not
record this", which this screen already renders by drawing nothing** (E9; and `recognitionTip`,
`watchForText`, `badge`). A card reading `City lists this as — Not recorded` would be the first
`Unknown` on a screen whose whole grammar is absence, and it would be a claim about *this tree* where
the true claim is about the column.

#### What this does not decide

- **What San Jose's `GROWSPACE` should be labelled**, or whether it should reach a card at all under
  a label of its own. It is a real signal — R24's own text calls it "a far better signal for where a
  San Jose tree stands than `OWNEDBY`" — and it now reaches the reader only through the `Site` card,
  verbatim, on the rows where it states something.
- **Whether the six `city_record` columns should hold another publisher's columns at all.** Open, and
  the subject of #134.
- **The other two E209 members.** `SharePresentation.ShareCopy.city` (Shape A, needs a source for a
  short civic name no table carries) and `MapKitBasemap.defaultCentre` (Shape B, needs a per-city
  centre the manifest does not carry) are untouched and still want their own tickets.

### R52 — A photograph nobody owns says so, in one sentence, on both surfaces that show it

**Unnumbered.** Written from a branch (`p1/round9-a`, task **#131**); the orchestrator splices the
real number at merge and rewrites the two code sites that cite this filename —
`TreePhotosCopy.nobodysToRemove` and `PhotoViewerView.captionBlock`.

**Raised by:** #131. **Delegated authority:** the copy and the surface were #131's to decide.
**Follows:** E126 (a surface showing nothing must say why), R21 (a control is withheld only where the
surface would have to choose), E173 (which found this state and deliberately left it silent rather
than invent copy in passing), E212 (the destination constraint).

---

#### The state

A photograph whose contributor deleted their account through the door that keeps the work
(`AccountDeletionChoice.leaveRecords`, #70/#73/#74) is still shown on this device and is correctly
excluded from `TreeProfile.deletablePhotoIDs`. `PhotoOwnershipTests` has pinned that gating since
#78 and D9 makes ownership device-scoped. **The gating is right.** What was wrong is that neither
surface said anything: on screen 20 the row simply had one control fewer than the row above it, and
in the viewer the bottom-trailing corner was simply empty.

It is rare and it is reachable: sign in, contribute a photograph, delete the account choosing to
leave the work behind — which is the *default* door.

#### The ruling

> A control withheld because the **record** cannot support it — as opposed to one withheld because
> the surface would have to choose which record it means — is an absence the surface must explain,
> in the same place and the same breath as the absence. E126's rule about an empty screen covers a
> missing action, and R21's exemption does not: R21 withholds a control where the *subject* is
> ambiguous, and says nothing about a subject that is perfectly clear and simply nobody's.
>
> The explanation is **one string on every surface that shows that record**, for the reason R21
> already gives about the control itself: a second wording is a second answer to one question, and
> the two will disagree.

#### The copy

    Nothing on this photo says whose it is. The account that added it was deleted, so it is
    nobody's to remove—signing in again does not change that.

`TreePhotosCopy.nobodysToRemove`. Written against the running app on a 440 pt iPhone 16 Pro Max,
where it wraps to two lines on both surfaces, and not drafted from the ticket — which is what #131
asked for, and what E173 refused to do in passing.

Clause by clause, because each is answering a constraint:

- **"Nothing on this photo says whose it is"** is the leaving door's own promise read back from the
  other side. `AccountDeletionCopy.leaveRecordsBody` ships *"with nothing left on them saying they
  were yours"*; this is the same fact seen by whoever is now looking at the photograph. Stating the
  fact about the record first makes the missing control read as a property of the photograph rather
  than of the reader.
- **"The account that added it was deleted"** is passive and gives the person no noun. The reader
  may well *be* them — the reachable path runs through this phone — and "the contributor has left"
  makes a stranger of somebody who might be looking at their own work. Nobody is told they did
  anything wrong, because nobody did: this is the door working exactly as designed. #131 required
  that.
- **"nobody's to remove"** is E173's phrase and is what is actually true. Not "you cannot delete
  this", which is a claim about the reader's permission; the record has no owner, so there is no one
  for a deletion to be made on behalf of.
- **"signing in again does not change that"** is the only clause that is not a description, and it
  is the one #131 required: it must not imply the photograph can be recovered. Without it a reader
  reasonably tries the one thing that looks like it would help. It is true —
  `ContributionStore.claimDevice` matches on `device_id = :device`, and an anonymized row has no
  `device_id` to match — and it is the same fact `leaveRecordsBody` already ships as *"if you make a
  new account here, they do not come back to you"*.

**What it does not say, deliberately.** Nothing about where the photograph goes, who else can see
it, the city, or a reviewer. ERRATA **E212** records two shipped sentences that promise a reader
somebody else is at the other end of a contribution, and there is no contribution sync — #158 is
unbuilt. This sentence claims nothing beyond this phone and offers no route back, because there is
not one.

#### The surfaces

**Screen 20 (the browser)** — under the caption, full width, in the faint register the filtered-empty
sentence already uses. Not in the thumb row: that is a row of 44 pt glyphs and a sentence cannot join
it without becoming a caption to them. It is drawn per row, on the row it is true of, and one row
only — a note at the top of the list would tell a reader that *something* here is nobody's without
telling them which photograph.

**The viewer** — stacked above the caption pill in the bottom-leading corner, in a rounded rectangle
on the same fill the caption uses, so the two read as one family. This is the one place the design
departs from *say it where the control would have been*: measured on the device, the sentence is two
full-width lines, and two full-width lines in the bottom-trailing corner either collide with the
caption in the other corner or squeeze into a narrow column over the middle of the photograph. It is
still diagonally opposite the close button, which is the geometry the delete had. **E126 requires the
surface to say why; it does not require the sentence to stand exactly where the button stood.**

#### How the surfaces know

Not by subtraction. `TreeProfile` gains **`anonymizedPhotoIDs`**, read from the columns
(`user_id IS NULL AND device_id IS NULL`) in the same transaction as the photographs.

Today "shown and not deletable" happens to coincide with "ownerless", because `ownPhotoIDs` is every
row this device holds and nothing brings anybody else's down. It coincides only for that reason. A
stranger's photograph would be shown-and-not-deletable without being nobody's, and a screen telling
somebody a photograph belongs to no one must read the column that says so rather than infer it from
a permission. `AnonymizedPhotoNoticeTests` pins the distinction with a row owned by another account.

`TreePhotosModel.isNobodysToRemove` also asks that the delete really is absent, and the disagreement
case is ruled here too: **if the two ever disagree, the control wins and the sentence is not drawn.**
A screen saying a record is nobody's while offering the button that removes it is worse than either
alone.

#### What was not built

The sentence is drawn on the two surfaces where a photograph is the subject. It is **not** on screen
03's hero, and that is R21's exemption applying unchanged: the hero is whichever photograph
`PhotoHero.choose` ranked this frame, so its subject moves under a vote, and a sentence about
ownership under a moving subject is a sentence about the wrong photograph.

### R53 — The map says why it drew nothing, and the trigger is the emptiness rather than a park (task #190)

**Unnumbered.** Written on branch `p1/round10-a` under the delegated design authority #190 grants
for the copy and the surface. Everything below was decided from the running app on iPhone 16 Pro
Max `DE8E11AE-…`, from the shipped seed, and from the code — not from the brief. Where the brief
turned out to be wrong or unbuildable, this says so.

---

#### What this rules

Screen 01 gains a fifth standing state. When a read completes for the current viewport, nothing is
narrowing the map, and the answer holds nothing to draw, the bottom slot draws a `MapLocationNotice`
reading:

> **No trees on record here**
> Cypress draws a city street-tree inventory, and this ground is not on it. Trees may well stand
> here, unlisted.

The decision is `MapInventoryNotice.isOwed`; the words are `MapInventoryCopy`; the drawing is the
`.nothing` arm of `MapHomeView.standingNotice`.

---

#### 1 · The problem, confirmed on the phone before anything was written

Golden Gate Park at street zoom draws **no pins at all** — only Apple's basemap canopy artwork,
which is the picture of the problem: the basemap knows there are trees there and the inventory does
not. One pan north across Fulton Street and the pins start on the first block and do not stop. The
screenshots are in the branch report.

`ERRATA E126` governs — a screen showing nothing must say why — and this is the one place on screen
01 where E126 was not discharged. It is also the likeliest place a first-time reader opens the app.

The cause is `ERRATA E214`: San Francisco has never counted its park trees. Rec & Park publishes no
tree inventory at any status, and the census the `sf_city` list descends from excluded park trees by
design. There is no ingest gap to close and nothing to retry.

---

#### 2 · The trigger, and why it is not a park

**Decided: the trigger is "a settled, un-narrowed read returned nothing to draw."** Four gates, all
of them load-bearing, each with its own test and its own red-proof.

##### 2.1 The brief's preferred trigger — "inside an RPD polygon" — is unbuildable, twice over

The brief asked whether the seed carries the Rec & Park polygons or only the 41 analysis
neighborhoods. **Only the 41**, and the answer is worse than that for a geometric trigger:

- `Fixtures/seed/cypress-seed.sqlite` holds one polygon table, `neighborhoods` — 41 rows, dataset
  `j2bu-swwd` per `seed_meta.neighborhoods_dataset_id`. There is no Rec & Park property geometry in
  the file at all. Adding it would be a seed change, which #190 forbids.
- **And the app never reads the polygons it does have.** `SpeciesQueries.resolveNeighborhood`
  answers "which area is this coordinate in" through the **nearest inventoried tree's**
  `neighborhood_id`, deliberately, so that no ray-cast of ours can disagree with the city's own
  assignment (`ERRATA E44`). That mechanism is nil where there is no inventoried tree within 400 m
  — which is precisely the coordinates this notice exists for. **The app's only way to name where
  you are is to ask a tree, and there is no tree.**

So a park-shaped or neighbourhood-shaped trigger is not a design option that was declined on taste.
It is not available.

##### 2.2 It would also have been wrong

`Golden Gate Park` *is* one of the 41 analysis neighborhoods (as are `Lincoln Park`, `McLaren Park`
and `Presidio`), so a neighbourhood-keyed notice was superficially buildable and is exactly the lie
the brief warned about: Dolores Park, Lake Merced and the other 236 Rec & Park properties are not
neighborhoods and would get nothing. E214's citywide measurement — 1,922 of 145,837 SF rows on Rec &
Park land, 1.3 %, all edge effects — is a fact about *every* park, not about one.

##### 2.3 What the emptiness trigger actually covers, measured on the shipped seed

| screenful | rows in the seed | notice |
|---|---:|---|
| Golden Gate Park interior, one street-zoom screenful around Stow Lake | **0** | draws |
| Presidio core | **0** | draws |
| Lake Merced | **0** | draws |
| Pacific west of the Sunset | **0** | draws |
| Oakland | **0** | draws |
| San Jose outside the shipped downtown window | **0** | draws |
| Dolores Park and one block of ring | 413 | silent |

**The last row is the honest limit of this ruling and is stated rather than hidden.** Dolores Park
is sixteen acres ringed by dense street-tree frontage, so a street-zoom screenful over it is never
empty and the notice never fires there. That is correct behaviour for a trigger that answers "this
screen has nothing on it": the screen does have something on it. It is not a park detector and does
not claim to be one. A reader standing in the middle of Dolores Park sees pins on Dolores Street and
18th Street, which is a truthful picture of a street-tree inventory.

##### 2.4 The other three gates

- **Settled.** `MapModel.content` opens at `.pins([])`, the same value an answered-and-empty
  viewport produces. Without the gate the notice would post for the opening publish of every launch,
  over any street in the city. `MapOpening.patience` exists for the same hazard.
- **Not failed.** `ERRATA E126`'s own defect was a screen drawing its empty state for a read that
  never finished. "Nothing is on record here" is a claim about the record; a read that threw has
  learned nothing about the record.
- **Markers, not trees.** The gate reads `MapContent.markerCount`. One cluster badge standing for
  29,390 trees is not an empty screen.

---

#### 3 · R41 reaches this surface, and the finding is that it should

#190 asked whether `RULINGS R41`'s ban reaches the chosen surface, and said that if it does, that is
a finding rather than an obstacle. **It does, and the finding is recorded here rather than routed
around.**

R41's test is *"does text appear because a filter did something?"* A bare "no rows in view" trigger
answers **yes**: a species chip, a decade, a membership set or a typed word that matches nothing
empties the map exactly as standing in Golden Gate Park does, and a sentence posted then would be
the fourth filter-adjacent message to be ruled out — after #142's growing notice, the R31
correction's empty-filter box, and `MapFilterStatus` (`ERRATA E205`). It is also the precise state
task #165 settled the other way, on the owner's direct instruction: *"if nothing matches, fine."*

**So the narrowing gate is R41 applied, not R41 read down.** Nothing here shelters filter-triggered
text under a new mechanism. What draws is a fact about the *inventory*, on a map nobody has
narrowed, and it disappears the moment anybody narrows it — including the case where the filter is
what emptied the map. E126's carve-out is not being stretched either: this is not a location notice
and does not claim to be one; it is a new state that meets R41's test by never being caused by a
filter.

`CypressUITests/MapFilterAccessibilityTests.testNoTextAccompaniesAFilter` already holds this from
the other side, and holds it causally rather than temporally: text is a violation only when it is
present with a filter on and absent with it off. This notice is absent with a filter on, by
construction.

**A consequence worth naming for whoever revisits R41.** If R41 were ever relaxed, the honest
version of this notice for a filtered empty map is a *different sentence* — "nothing here matches
what you asked for" is not "this ground is not on the inventory" — and it must not be this one
wearing a wider trigger.

---

#### 4 · The surface: the existing bottom-slot notice, not a new component

**Decided: `MapLocationNotice`, in screen 01's bottom slot, as a fifth occupant.** #190 asked that
what already exists be checked before anything is added. It does exist, it is the right shape, and
building a second card would put two kinds of standing notice on one screen.

- SCREENS.md 01 lists `empty/no-GPS state` among its **NOT SPECIFIED** states. That is the same door
  `MapOpening.Standing` and `MapLocationNotice` were built through under ARCHITECTURE §8 rule 8, so
  DECISIONS constraint 21 does not make this a stop-and-ask; the state is named by the spec as one
  the spec does not draw.
- The component already takes a title, a message and an *optional* action, so a notice with nothing
  to press needs no change to it. Not one line of `MapLocationNotice` was touched.

##### 4.1 Precedence: the location states win

Where both could speak, the location notice draws and this one does not. This follows E126's own
precedent on screen 12 — a missing fix wins over a failed read, because "the prompt is the one that
has an action behind it". Three of the four location states are about the reader's own device and
two carry a Settings button; this one is a standing fact about the record with nothing to press.
They are barely rivals in practice: a reader with a fix gets `.nothing` from `MapOpening.standing`,
which is the arm this draws in.

##### 4.2 No button, deliberately

E126 asks an emptied surface to say why **and** offer a way out, and its examples are a retry for a
failed read and `Clear filters` for a narrowed one. Neither exists here: nothing failed and there is
nothing to clear. The one thing a reader *can* do — put a tree on the map themselves, which per E214
is the only route to a populated Golden Gate Park that exists today — is the `What tree is this?`
FAB, the largest control on the screen, sitting directly above this card whether it draws or not.
Repeating it in prose would be a second, weaker copy of a control already in the reader's eye, and
`ERRATA E183 §2` is a standing warning about what a button on this card costs at accessibility
sizes.

---

#### 5 · The copy, and what each clause is answerable for

> **No trees on record here**
> Cypress draws a city street-tree inventory, and this ground is not on it. Trees may well stand
> here, unlisted.

- **"on record", not "here".** The subject is the record, not the ground. `No trees here` is the one
  thing this notice must never say.
- **"a city street-tree inventory"** is the inventory's own published name rather than a
  characterisation invented for this screen. All three inventories `Tools/inventory_contract.py`
  registers are named one: `SF Public Works street tree inventory`, `DataSF Street Tree List`,
  `City of San Jose Street Tree inventory`. **This is the sentence's one dependency on the world,
  and it is stated so the next reader can check it:** the day an inventory is registered that is not
  a street-tree list, this clause becomes false and the sentence needs rewriting. It deliberately
  does not name *which* inventory — that is true of whichever file R43 has attached, and threading
  the attached name out to screen 01 is precisely the plumbing E205 has just finished deleting.
- **"this ground is not on it"** states a boundary of the record's extent. No verb the reader could
  have got wrong, no state that resolves.
- **"Trees may well stand here, unlisted."** The half #190 is actually about. `may well` is
  load-bearing and is not a hedge to be tidied away later: the trigger fires over the Pacific and
  outside a downloaded city's window as well as in the park, and `Trees stand here` would be a
  stronger sentence and a false one in those places.

**What it does not say, and why.** No date, no "yet", no "soon", no "we are working on it". Rec &
Park publishes no tree inventory at any status and no parks phase of the Urban Forest Plan has ever
published data (E214), so a promise would be `ERRATA E212`'s invented destination claim wearing a
different noun. A test refuses eight such words by name. It also refuses seven words that would make
a documented boundary of a municipal dataset read as a fault — `error`, `failed`, `could not`,
`unable`, `try again`, `loading`, `problem` — because this is closer to a map legend than to a
failure.

**No civic content is invented** (DECISIONS constraint 15). Every fact in the sentence is either the
inventory's own name or a tautology about the record: if the city had counted these trees there
would be rows, and there are none.

---

#### 6 · AX5, and the errata family this ticket sits inside

`ERRATA E183 §2` measured `MapLocationNotice` at AX5 taller than a 390 pt display, laid out from its
bottom edge, growing up past `y = 0` with E126's way out above the top of the screen. That defect is
a layout ruling nobody has taken and it is **not fixed here** — it is the same open question R23
left ("whether the chrome is now too tall") and R14, R22 and R25 §6 have each answered separately
for their own surface. #190 is not the ticket to answer it in.

**But this ticket must not deepen it, and the first draft of the copy did.** Measured through
`AX5ReflowTests.ax5Size` at accessibility5 on the 393 pt phone the sweep photographs:

| card | height at AX5 |
|---|---:|
| first draft (`…; the inventory has never listed them.`) | **502.3 pt** |
| tallest location notice already shipping in this slot | **456.7 pt** |
| shipped copy (`Trees may well stand here, unlisted.`) | under the budget |

So the copy was shortened until it fit under the tallest card already in the slot, and
`MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` holds that budget rather than a number invented
here — a copy edit that spends the line back fails instead of shipping. Photographed at AX5 on the
running phone as well: on a 440 pt device the whole card is on the glass, title on two lines,
message on six, above the tab bar.

---

#### 7 · What was checked and left alone

- **No migration, no seed change, no `inventory_contract.py` registration.** E214's rule stands: the
  correct response to a source that does not exist is to add nothing.
- **`MapLocationNotice`, `MapFilterCopy`, `MapSearchStatus`, `MapSpeciesLegend`, the drawer** — all
  untouched. E205's audit of every filter surface is still accurate.
- **`LandContext`** — untouched, and E214 is right that `.cityPark` already exists and needs no
  fourth case.

---

#### 8 · One correction to the brief's numbers, for the record

#190 quotes E214's measurement — **65** seed rows inside Rec & Park's own Golden Gate Park polygon,
all of them DPW-maintained street trees. That is not reproducible from anything the app ships,
because the RPD polygon is not in the seed. Measured against the polygon the seed *does* carry — the
`Golden Gate Park` **analysis neighborhood** — the count is **90** rows, of which **79** carry
`legal_status = 'DPW Maintained'` and **53** name `Rec/Park` as caretaker. (The remaining 11 are
`Permitted Site`, `Property Tree` and `Significant Tree`, all `Private`.)

The two numbers are not in conflict: they are two different polygons, and E214 says which one it
used. It is recorded here only so that the next reader who queries the seed and gets 90 does not
conclude that E214 is wrong. **Neither number is reachable by the app at runtime**, which is §2.1's
whole point.

### R54 — A name the ingest could not read is not drawn as a name, and one sentence says whose word it is (task #185, delegated)

*Written under the delegated design authority for #185. `RULINGS R47` named this ticket as what it
deliberately left open, so this is the half of #103 that a filter could not reach.*

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge
and rewrites the citations in `Cypress/Core/Models/Species.swift`,
`Cypress/Data/Store/SpeciesQueries.swift`, `Cypress/Features/Species/SpeciesPresentation.swift`,
`Cypress/Features/Species/SpeciesView.swift`,
`Cypress/Features/TreeProfile/TreeProfilePresentation.swift`,
`Cypress/Features/TreeProfile/TreeProfileView.swift`,
`Cypress/Features/Memorial/MemorialPresentation.swift`, `Cypress/Features/Map/MapModel.swift`,
`Cypress/Features/Visit/VisitShortlist.swift` and `CypressTests/UnreadSpeciesNameTests.swift`.*

---

**What was delegated.** R47 removed the five unreadable species from the suggestion list and the
add-tree picker, on E126's principle that a row a reader cannot interpret is worse than a row that
is not there, and it said in its own closing section what that fix could not do: *"you cannot omit a
tree's own species from its own page."* So seven trees went on drawing `:: Magnolia` where their
species name is drawn. The fix is copy, and the delegation is where the copy goes and what it says.

---

#### The measurement, taken from the shipped seed and not from the ticket

Five species rows carry the marker, standing under seven trees out of 198,625. Every count below was
re-read from `Cypress/Resources/cypress-seed.sqlite` and is asserted in
`UnreadSpeciesNameTests.theCatalogueStillCarriesUnreadNames`, so a rebuild that moves them fails a
test rather than leaving this copy addressed to nobody.

| `scientific_name` | `common_name` | trees | where they stand |
| --- | --- | ---: | --- |
| `:: Magnolia` | `Magnolia` | 3 | 3555 20th St · 365 Bartlett St · 3310 25th St |
| `:: 9662` | `9662` | 1 | 110 GOUGH ST |
| `:: Chitalpatashkentensis` | `Chitalpatashkentensis` | 1 | 200 OCTAVIA ST |
| `:: Magnolia Little Gem` | `Magnolia Little Gem` | 1 | 446 Bartlett St |
| `:: Podocarpus Gracilor` | `Podocarpus Gracilor` | 1 | 36 REY ST |

All seven are `sf`, all `alive`, all `city_import`. `seed_meta.stub_rows` is `7`; every one has
`species_map.confidence = 0.3`.

#### The fact the ticket does not state, and it is the one the answer turns on

**`common_name` on these rows is sound. `scientific_name` is not.**

`Tools/inventory_adapters.py::parse_qspecies` reads DataSF's one-column convention
`Scientific name :: Common name`. When the scientific half is empty it returns
`("stub", s, common, 0.3)` — where `s` is **the whole raw string, separator and all**, and `common`
is the common half, unaltered. So on all five rows:

- `scientific_name` = `:: Magnolia` — the parser's leftovers, stored in a column that says "name".
- `common_name` = `Magnolia` — **what the city actually wrote**, verbatim.

That asymmetry is why this is not "hide the species". There is exactly one field to withhold and one
field to quote, and the sentence is what turns the second into a quotation instead of a claim.

It also survives the ugly case. `:: 9662`'s wording is `9662` — and the tree it stands over is
DataSF `TreeID` 9662, which the profile draws two blocks lower as `CITY RECORD #9662`. The city
pasted a record number into a species cell. A reader can see that for themselves once the screen
says where the word came from; they could not before.

---

#### The ruling

**1 · No surface in the app prints a scientific name the ingest never read.**

`Species.scientificNameIsUnread` in `Core`, off `Species.unreadScientificNameMarker`, which
`SpeciesQueries.stubNameMarker` now reads rather than restating — the SQL filter R47 installed and
the screens this ruling changes must be filtering on one string or they will drift. Applied at every
site that draws the value **as** a scientific name: 07's hero Latin line, 03/14's subtitle, the
memorial subtitle, the map card's meta line, and the visit shortlist's second line.

Not applied to the three fallback chains that would print it as a *display name of last resort*
(`VisitCandidate.displayName`, `SitePresentation.neighbourTitle`, `VisitAddTreeCopy.candidateName`).
Those are unreachable for a stub: `parse_qspecies` classifies `:: <nothing>` as a placeholder rather
than a stub, so a stub always has a common half to reach first. Left alone deliberately — a guard on
an unreachable branch is a guard nothing can red-proof.

**2 · Where the line was, one sentence says whose word the name above it is. Both screens.**

The ticket asks where the copy goes and offers three answers. It goes on **both**, and the reason is
that the two screens have different subjects, not that hedging is safer.

- **03/14 · the tree profile.** `The city files this tree as “Magnolia” and its record gives no
  scientific name.` This is the screen a reader hits: a map pin, a card, a profile. It sits in the
  identity block directly under the subtitle, which is `speciesClaim`'s placement argument unchanged
  — the subtitle is where a species is *stated*, so the account of why its Latin half is missing
  belongs against it. In the app's own voice, not as a `city record` card: it is a sentence *about*
  the record, and the badge would attribute Cypress's reading of the column to San Francisco
  (`landContextNote`'s argument, one block up).
- **07 · the species page.** `“Magnolia” is the city's own wording. The record it comes from gives
  no scientific name.` Reachable from a grove tile once somebody has met one of the seven trees.
  It draws immediately under the hero, in the reading order the missing Latin line held.

**Two strings and not one shared constant.** 03 has a tree in front of it and can say *this tree*.
07 has a wording standing over one record or three, and can say neither *this tree* nor *these
trees* without counting — so its sentence is written about the wording, which is number-neutral and
is what the reader is looking at anyway.

**`files … as` and not `calls` or `names`.** One of the five wordings is a work-order number. A verb
of naming would make the sentence assert that `9662` is this tree's name; a verb of filing describes
what a municipal inventory did with a cell, which is all that is known, and it holds for `9662` and
for `Magnolia` alike. It borrows the grammar of `CityRecordCopy.plantTypeLabel` — `City lists this
as` — because the app already has one voice for reading a city column out without adopting it. The
typographic quotes are load-bearing rather than decorative: they are what marks the word as somebody
else's.

**3 · Dropping the line in silence was considered and refused.** Every other species draws three
hero lines and these would draw two, with nothing saying which fact went missing. That is E126's own
defect wearing better manners — an unreadable state replaced by an uninterpretable one — and it
leaves `9662` standing as the least readable string on the screen with no account of where it came
from. E126 requires an emptied surface to say why.

**4 · Nothing here guesses at the taxon.** `:: Podocarpus Gracilor` is probably *Podocarpus
gracilor* and `:: Chitalpatashkentensis` is probably *Chitalpa tashkentensis* — the seed carries
`Chitalpa tashkentensis 'Pink Dawn'` two rows away — and neither screen says so. That is the
synonymy R47 refused, from a client holding one query's worth of rows, and DECISIONS constraint 15
forbids it outright.

**5 · Two preview surfaces withhold the name and get no sentence, and that is the same ruling and
not an exception to it.** `MapTreeCard.meta` and the visit shortlist's second line are `·`-joined
previews that already drop any clause they have no fact for — no species, no fix, no visit. A
dropped clause there reads as every other absence on the same line, and the profile each opens is
one tap away carrying the whole account. E126 governs a *surface that has been emptied*; a preview
line that is one clause shorter has not been emptied.

**6 · The seven trees keep everything else.** Pins, profiles, photographs, check-ins, the count card
on 07 (`In this inventory · 3`) and the nearby list. This ruling withholds one string and adds one
sentence. R47 kept the pins and this keeps the rest.

---

#### What was looked at, running

Both screens on iPhone 16e `3A1F212D-…`, deep-linked through a temporary `DebugDeepLink` case that
was **removed before commit** (E126's own method).

- 03 over `8b95154d-…` (3555 20th St): `Magnolia` / *SF Public Works street tree inventory* / *The
  city files this tree as “Magnolia” and its record gives no scientific name.* / `Show me where this
  is`. The subtitle used to read `:: Magnolia · SF Public Works street tree inventory`.
- 03 over `98bc455f-…` (110 GOUGH ST): `9662`, the same sentence quoting `9662`, with `CITY RECORD
  #9662` in the grid below it.
- 07 over `31f44959-…`: `FIELD GUIDE` / `Magnolia`, no Latin line, the sentence under the hero, and
  `IN THIS INVENTORY · 3`.

---

#### What this does not settle

**The `Field guide` eyebrow still sits over a page that is not a field-guide entry.** Left as it is:
it is equally true of the 529 uncurated species that carry a name, a family and nothing else, and
changing it would be a decision about screen 07's identity rather than about these five rows.

**A stub with no `::` in it would slip the predicate.** `parse_qspecies` also mints a stub from a
source string carrying no separator at all, and that name has no prefix to test. None ship, and
`SeedStubNamingTests.theMarkerAndTheProvenanceFlagAgree` is what says so — it proves the marker and
`species_map.is_stub` select the same rows in the seed as built, and it is the test that will go red
if a future ingest ever mints one. The predicate is deliberately not widened to guess: a rule for
"does this string look like a name" is exactly what the ingest already tried and got wrong.

**The corpus still carries one plant under several spellings.** `Arbutus 'Marina'`, `Arbutus marina`
and `Arbutus ‘Marina’` are three rows for one tree, `ERRATA E208` records it, and the survey and the
ruling on it are `RULINGS R55` (task #184). Nothing here touches
it: those rows are readable names, and this is about a row that is not a name at all.

### R55 — One plant under several spellings is a corpus repair, not a list behaviour — and only its last tier is a synonymy claim (task #184, delegated)

*Written under the delegated design authority for #184, which covers the (a)/(b) call and the copy
that would follow it. `RULINGS R47` named this ticket as what #103 left open and `ERRATA E208 §2`
records the defect.*

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge.*

**Status: decided and surveyed, NOT implemented.** No code and no seed in this branch changes because
of it. §6 says exactly why, and what the implementing branch has to be given.

---

#### What was delegated

#184 asks for one of two answers: **(a)** an explicit synonymy table with a stated source, extending
the existing corrections mechanism, or **(b)** a decision that the suggestion list groups visually
without asserting the rows are the same species.

**The answer is (a)** — and the survey below is why the question as posed is one question too few.
The duplicates are not one problem needing one table. They are **three tiers**, and only the third
is a synonymy claim at all. Tiers 1 and 2 are one string spelled several ways, which no source needs
to adjudicate; tier 3 is two names for one taxon, which no amount of string handling can reach.

---

#### 1 · The survey, measured against the shipped seed

All figures from `Cypress/Resources/cypress-seed.sqlite` (198,625 trees; 731 species rows, 726 once
R47's five unreadable rows are set aside), computed by normalising `scientific_name` and grouping.
The seed's own key is `normalise_species_key` — lowercase, collapse whitespace — which is why none of
these merged at build time.

| tier | the rule that would merge them | families | rows | rows that would go | trees under them |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | quote **glyph**, letter case, internal whitespace | 10 | 20 | 10 | 4,935 |
| 1+2 | …and quote **presence**, including unbalanced quotes | 15 | 34 | 19 | 5,646 |
| 1+2+3a | …and the hybrid marker `x` / `×` | 25 | 55 | 30 | 16,601 |
| 3b | two epithets, one taxon | *not reachable by any rule over the string* | | | |

**Tier 1 — the same characters, different Unicode.** `Acer rubrum 'October Glory'` ·
`Acer rubrum ‘October Glory’`. Also `Zelkova serrata 'Musashino'` against
`Zelkova serrata 'Musashino’`, which opens with a straight quote and closes with a typographic one —
one keystroke, in one cell, in one city's spreadsheet.

**Tier 2 — the quotes themselves, and the damage around them.**
`Arbutus 'Marina'` · `Arbutus marina` · `Arbutus ‘Marina’`.
`Magnolia grandiflora 'Little Gem'` · `‘Little Gem’` · `"Little Gem"` · `'Little Gem"`.
`Carpinus betulus 'Fastigiata'` against `Carpinus betulus ' Fastigiata'` — a leading space *inside*
the quotes. `Cedrus atlantica Glauca` against `Cedrus atlantica 'Glauca'`.
`Robinia pseudoacacia 'Umbraculifera'` against the same with no closing quote.

**Tier 3a — the hybrid marker.** `Platanus x hispanica` · `Platanus hispanica`;
`Acer x freemanii` · `Acer freemanii`; `Aesculus x carnea` · `Aesculus carnea`;
`Ulmus 'Frontier'` · `Ulmus x 'Frontier'`. Ten more families like them.

**Tier 3b — the one the ticket named, and the only true synonymy in the corpus.**
`Platanus × acerifolia` and `Platanus × hispanica` are two names for the London plane. Nothing in
either string says so. In the seed that costs `Columbia` **five rows**:

| row | trees | common name |
| --- | ---: | --- |
| `Platanus acerifolia 'Columbia'` | 1,075 | — |
| `Platanus x hispanica 'Columbia'` | 234 | `Columbia Hybrid Plane Tree` |
| `Platanus hispanica 'columbia'` | 20 | — |
| `Platanus x acerifolia ‘Columbia’` | 2 | — |
| `Platanus x acerifolia 'Columbia'` | 1 | — |

Tiers 1–3a collapse those five to **two**. Only a synonymy claim collapses the two to one.

---

#### 2 · Why (b) is refused, and the refusal is measured rather than argued

(b) would fix the dropdown and leave everything else. But **the split is not a list defect; it is a
corpus defect that the list happens to expose**, and three other surfaces are already wrong because
of it:

- **Screen 07's count card is understated on every family.** `In this inventory · 3,824` for
  `Arbutus 'Marina'`; the corpus holds 3,835. `Columbia Hybrid Plane Tree` says **234**; the London
  planes named Columbia number **1,332**. That is `RULINGS R48`'s defect exactly — a label over a
  population it does not name — reappearing from a different cause, and (b) does not touch it.
- **Curated content follows one row and abandons the rest.** In 22 of the 25 families some rows
  carry a common name and others carry none, and it is not always the big one:
  `Platanus acerifolia 'Columbia'` holds 1,075 trees and has no common name at all, while the row
  with the name holds 234. A reader who lands on the larger row gets a page headed with a Latin
  string; the smaller row gets `Columbia Hybrid Plane Tree`.
- **The map legend and the species-narrowed map split too.** `MapSpeciesPalette` colours by species
  id, so one plant takes two swatches and two legend entries, and tapping one narrows the map to a
  fraction of its own trees.

A grouping that renders rows together while the ids stay apart would have to be re-derived on each
of those surfaces, in four places, from four different values — and each would be free to disagree.
The one place the corpus's own identity is decided is `Tools/build_seed.py`, which is where R47 sent
the safe half of #103 for the same reason.

---

#### 3 · The ruling

**Tiers 1 and 2 are a key change in the builder, and they are not synonymy.** The claim being made
is "these strings are one string" — that a straight apostrophe and U+2019 are the same character for
indexing, that `Little Gem"` is `'Little Gem'` with a typo, that a space inside quotes is not part
of a cultivar epithet. No outside source is needed to say so and none could: this is the *same
assertion the seed already makes* when `normalise_species_key` lowercases and collapses whitespace,
extended by three more classes of the same kind of noise. It is stated as a rule in one function
with its own doc comment, and it is testable by listing what it merges.

**Tier 3a — the hybrid marker — is admitted, and it is the boundary case.** The `×` in
`Platanus × hispanica` denotes a hybrid and is conventionally disregarded when names are indexed or
alphabetised; `Acer freemanii` is not a second taxon, it is `Acer × freemanii` written without the
sign. This is one step further than tiers 1–2 because it appeals to a nomenclatural convention
rather than to a keyboard. It is still not a synonymy: it merges two spellings of *one* name, not two
names. **If the implementing branch wants to be conservative, this is the tier to drop** — it is 10
families and 11 rows, and dropping it costs nothing that tiers 1–2 buy.

**Tier 3b requires an explicit table with a per-entry citation, and it is the only tier that does.**
The mechanism already exists in shape: `QSPECIES_NAME_CORRECTIONS` in `Tools/inventory_adapters.py`
is a hand-written table whose one entry carries its source in the comment above it (SelecTree
tree-detail/1107, `match_method fuzzy_name_edit_distance_1_to_"platanus racemosa"`), and whose
header states the rule this ruling is bound by: *"Only entries an outside source already resolved
belong here … What must NOT go here: a vernacular-only string merged onto a binomial by judgment."*
A synonymy table is a sibling of it, not an extension: the corrections table maps a raw qSpecies
string to a name, and this maps an accepted name to a name it supersedes. One entry today:

    Platanus × acerifolia  →  Platanus × hispanica     [source required]

**The source must be named per entry, and this ruling does not name it.** POWO (Kew) and the GBIF
Backbone both state the relationship, and neither has been read by anybody on this branch. Writing
the citation from memory is precisely the failure the corrections table's own header refuses, and it
is what `Fixtures/species/leaf_retention.yaml` already avoids by carrying `match_method` and a source
id beside each row. **An implementing branch that cannot produce a citation must ship tiers 1–3a and
leave the two Columbia rows apart** — that is a smaller and honest result, and it still takes the
`Columbia` family from five rows to two.

**The direction of a merge is by tree count, not by which name is "better".** The row with the most
trees wins its family and keeps its `scientific_name` verbatim; the losers' trees are re-pointed and
their rows do not enter the file. Any common name or curated content present on exactly one row of a
family travels with the winner, which is what fixes the `Columbia` split above.

---

#### 4 · The trap, restated so it cannot be walked into

**No dedupe here strips a cultivar.** `Arbutus 'Marina'`, `Ceanothus 'Ray Hartman'` and
`Ulmus 'Frontier'` are real, wanted rows and stay distinct from `Arbutus unedo`, `Ceanothus
thyrsiflorus` and `Ulmus parvifolia`. Every rule above normalises how a cultivar epithet is
*punctuated*; none removes one. A rule that merged `Arbutus 'Marina'` into `Arbutus` was explicitly
refuted as a fix for #103 and is not reintroduced by any tier.

**A premise in the #184 brief is wrong and is corrected here.** The brief states that R47 records
"175 cultivars kept as distinct species on purpose". R47 records no such number — the word
*cultivars* appears in it twice, both times in the singular, describing what the builder's swap
reads. The measured figure is **194** species rows carrying a quoted cultivar epithet (`SELECT
count(*) FROM species WHERE scientific_name NOT LIKE ':: %' AND scientific_name LIKE any quote`).
The substance of the warning is right and unchanged; the citation and the number are not.

---

#### 5 · What a merge moves, and what it must not

`species.uuid = uuid5(NS_SPECIES, normalise_species_key(scientific_name))` — E208 closes by warning
that a merge changes species uuids, "the thing the seed is careful never to move". That warning is
about the wrong half of the change and it is worth being exact, because taken at face value it would
stop tiers 1–2 for no reason.

**Mint each surviving row's uuid from its own verbatim name, exactly as today, and use the normalised
key only to decide which rows share a family.** Then no surviving uuid moves: `Arbutus 'Marina'`
keeps `uuid5(NS_SPECIES, "arbutus 'marina'")` and the 194 cultivar rows keep theirs. What
disappears is 19 to 30 loser uuids, which is unavoidable and is the point of the ticket. A design
that normalised the *minting* input instead would move all 194 — including every row a grove entry,
a favourite or a `species_assertions` chain already points at — and there is no reason to.

---

#### 6 · Why this branch stops here, stated plainly

Tiers 1–3a are a rebuild: `python3 Tools/build_seed.py --source city --sj-extent downtown`, a new
103 MB artifact into `Fixtures/seed/` and `Cypress/Resources/`, a new sha256 replacing
`d3e3d229…`, and new values for `seed_meta.species_count` (731 today), `distinct_qspecies` and the
per-family counts. `CypressTests/SeedCorpus.swift` pins several of those constants, `SeedCorpus`
comments cite the pre-#103 figures, and every live branch reading the seed inherits the new file at
merge. That is an announced, scheduled corpus change with a rebuild verification of its own — not
something to land beside a copy fix, and #184's own ticket says the same.

**What the implementing branch needs, and this ruling supplies:** the tier boundaries, the exact 25
families and 55 rows (reproducible from the query in §1), the merge direction, the uuid rule in §5,
the cultivar trap in §4, and the one synonymy entry that needs a citation before it can be written.
What it still owes: that citation, or the decision to ship without tier 3b.

---

#### What this does not settle

**`Magnolia grandiflora 'Sam Sommers'` (4 trees) beside `Magnolia grandiflora 'Samuel Sommer'`
(260).** E208 lists it with the quote variants and it does not belong there: `Sam Sommers` and
`Samuel Sommer` are different words, not different punctuation, and merging them is an edit-distance
judgment about a person's name. It is the same class as `patanus racemosa` — which the corrections
table admits only because an outside source already resolved it — and it needs the same treatment,
one row at a time, with a citation. No tier above touches it. `Magnolia 'Samuel Sommer'` (2 trees,
no `grandiflora`) is a third case again: a cultivar attached to a bare genus, which may or may not be
the same plant, and which nothing in the string settles.

**Whether the app should say anything about a merge having happened.** It should not, and no copy is
specified: a corpus that holds one row per plant is the state every other species on screen 07 is
already in, and a sentence explaining an absence nobody can see would be the fabricated state
DECISIONS constraint 21 forbids.
