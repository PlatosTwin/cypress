# Rulings

Five questions that were design's to answer and had no answer. On 2026-07-21 the project owner
delegated all five to me explicitly, in writing, and asked that a call be made on each. This file is
that call.

**These are rulings, not discoveries.** Everything in `ERRATA.md` is a conflict found between
documents that already existed. Everything here is a decision made where no document said anything,
under authority that was granted rather than assumed. Each entry says what it overrules, so that a
designer arriving later can find every place their intent was substituted for and reverse it in one
pass.

The distinction that governs the color entries, carried forward from E8:

- a **transcribed** value is a hex read out of `SCREENS.md` — it may not be changed;
- a **derived** value was computed by the light→dark transform — it may be corrected;
- an **overruled** value was transcribed and is being changed anyway, under this delegation.

R1 is the only overrule in the app. It touches three tokens.

---

## R1 — The caption ramp is retinted, not reassigned (closes E106)

**The finding.** `text.faint` fails WCAG AA in both appearances: 2.90:1 on the screen and 3.16:1 on a
card in light, 3.42 and 2.98 dark, against a 4.5 floor for text. It is not one badge. It is every
mono micro-label, every timestamp, and every meta line in the app — 61 call sites across 24 files.
`text.faintAlt`, the footnote color, fails the same way at 3.67 / 3.42.

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

**Corrected, not overruled — which is a different thing and must stay labeled as one.**

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

**The finding.** A favorite can be written and cannot be removed. C8's `Favorite` cell is drawn once,
in one state; nothing in the mock set un-favorites a tree; `RootView` writes `isFavorite: true` and
never `false`.

**The ruling: C8's first cell gets a selected appearance, and a second tap removes the favorite.**

Of the two closures E101 offers — a selected state on C8, or a surface that lists favorites and can
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
  is a *different statement* and needs its own key, or un-favoriting silently no-ops.
- **A memorial can still be favorited.** Settled under E89 and unchanged: the gate that refuses the
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
for keeping them: the record outlives the account. A private reminder and a favorite have no such
value. Nobody but their owner can read them, and after anonymization nobody at all can — an
ownerless favorite is a row that no query returns and no person can remove. Keeping it is not
privacy-preserving, it is litter that happens to be unreachable.

So: anonymize what the forest keeps, delete what only one person could ever see. This is not an
exception to §3.12; it is what §3.12 means by *contribution*, made explicit.

**The deletion confirmation must enumerate both.** A person deleting an account should be told that
their reminders and favorites go with it, before it happens, in the same sentence that tells them
their observations stay. Deleting more than someone expected is the failure mode this ruling creates,
and copy is the whole defense against it.

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
how favorites (E89) and private reminders (E23) work.

---

## R5 — The denominator is 215, and it stays 3%

**The finding.** E47 established that screen 08's species denominator is 215 — the true count of
distinct species in the neighborhood — and not the 40 the mock's fixture implies. A contributor who
has met seven species therefore sees `7 of 215` and a progress ring at 3%.

**The ruling: no change. The number is right and the ring is right.**

The temptation is to find a friendlier denominator — species seen by anyone nearby, or a milestone
ladder where 7 is most of the way to 10. Both are mechanics that nobody designed, invented to make a
true number feel better. 3% of a neighborhood's species is what one contributor has met, and 56 of
those 215 species are represented by a *single tree* in the whole neighborhood.

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

### R7 — a vacant planting site gets a hollow ring, not the gray dot that means "removed"

C19 has no vacant-site pin, so the basins currently draw as the gray dot for a removed tree (12,518
of them when this was ruled — San Francisco alone; 24,200 across both cities today, E206). That
is not a styling gap, it is the map asserting that something was there and is gone — the same lie
E107 and E113 spent two entries removing everywhere else. It is the last surface still telling it.

**A hollow ring: the existing pin geometry, outline only, no fill**, in the dashed-border family the
vacant-site screen and the empty photo well already speak (`borderDashedStrong`). Nothing is added to
the palette. An empty outline reads as "nothing here" without needing a color to be learned, and it
cannot be confused with a filled dot at any size — which a second gray could.

### R8 — the two failing contrast pairs are fixed by lightness, and C23 gains a non-color encoding

R1 fixed the text ramp and deliberately left the C10 locked glyph and the C23 chart series, both under
3:1, because a glyph and a data encoding are drawn decisions rather than a ramp. Delegated now, the
answer is R1's method: **lightness-only moves in OKLCh, holding chroma and hue**, so the marks stay
recognizably themselves.

C23 gets one thing more. If the series cannot all reach 3:1 by lightness without becoming hard to tell
apart, **the series carry a dash pattern as well as a color**. A chart that distinguishes its lines
only by hue is unreadable to a color-blind reader at *any* contrast ratio, so the redundant encoding
is owed regardless — and it is what makes the lightness moves affordable.

### R9 — one amber border color

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
the light and dark borders very nearly the same color, so the component stops changing character
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
planting sites in the neighborhood are empty**, because that is the one true and useful thing the app
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
that no one will ever action, and the app currently says nothing about that. Whatever acknowledgment
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
default-size proportion, not a round number), the size class at which the behavior switches on (not
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
   meters, and nothing downstream was positioned to notice: 16's sanity pill compares a draft against
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
honest — once the Height card opens a height form, "Add a reading" inside a box labeled `Height`
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
`top:68px` and says of its behavior only that "search opens species/street/neighborhood search",
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
worked is labeled `return`, which reads as "insert a newline" rather than "I am finished". Nothing
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
  ARCHITECTURE §6 requires — grown leftwards and outwards from the glyph rather than centered around
  it, and drawn as an overlay so that growing it cannot change the bar's ~45 pt height. It clears the
  text and **keeps focus**: clearing is the start of the next query far more often than it is the end
  of searching, and a ✕ that did both would do neither predictably.
- **The return key is relabeled**, `Search` instead of `return` (`submitLabel(.search)`). This costs
  no pixels and changes nothing about what the key *does* — it changes what it says, which is the
  whole of what was wrong with it. There is deliberately **no** `onSubmit` resigning focus: it was
  written, measured, found to change nothing, and removed. A line that appears to cause behavior it
  merely coincides with is how a comment ends up ratifying a defect.
- **A `Done` above the keyboard**, because a relabeled key is still a key on a keyboard, and "no way
  to exit" is a report about what a person could *find*. It lives on the keyboard, so nothing screen
  01 positions moves.

The glyph is hand-drawn — a ring with an ✕ inside it, at C20's own 1.8 stroke and in C20's own glyph
color, so the bar carries the same line weight at both ends. There are no SF Symbols and no icon
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
implementation), and whether a query short enough to match most of the catalog should narrow the
map at all — one character now matches 555 of 577 species, and the status line says so under E38
rather than the bar refusing to search. Both belong to whoever revisits screen 01's search surface.

## The owner's own decisions, recorded here so they are not re-opened

These are **not** delegated rulings — they were made by the project owner directly, and are written
down for the same reason the rulings are: so a later reader can find the decision rather than
rediscover the question.

**2026-07-26 · anonymized means anonymous, permanently (#74).** Deleting an account offers two doors,
and the default leaves records unattributed. Anonymizing cleared `user_id` but kept `device_id`, so
D9's device-scoped ownership let `claimDevice` re-adopt those rows onto the next account signed in on
that phone — a real re-identification on a shared or handed-down device. The owner ruled for a
**tombstone**: rows anonymized by a deletion are marked and `claimDevice` skips them forever.
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
   once the map colors them, so a black-box test can read the viewport's census off the
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

The gray pin and the gray badge say "there is no living tree at this site", which is true of a
removed tree and true of a standing dead one. `MapPin.Kind` is a closed catalog — its sixth entry,
the vacant-site pin, took RULINGS R7 — and `StatusBadge` has four color pairs and no fifth. So the
drawing is borrowed and no new visual vocabulary is invented.

Every *word* is separate, and that is not a compromise:

- badge `Dead`, never `Removed`
- pin spoken as `Dead tree, still standing`, never `Removed tree, memorial`
- profile Callout saying a reviewer confirmed it and that it is still worth reporting
- queue row `Reported dead` / `Confirm dead`, beside the removal's own pair

The rule this encodes: **two statuses may share a drawing while sharing no sentence.** A reader who
sees only color learns "not a living tree here", which is right. A reader who reads or listens
learns which of the two, which is what actually changes what they should do — a removed tree needs
nothing from anybody, and a dead one standing over a pavement needs reporting.

**Not decided: whether a standing dead tree deserves a pin of its own.**

There is a real case for one. A dead street tree is the highest-consequence record on the map, it is
the only gray pin you can still act on, and R7's argument for the vacant site — that borrowing
`.removed` made the map assert something untrue — applies here in a weaker form: the map is not
asserting removal, but it is declining to distinguish a hazard from a memorial.

It is left open for the reason E107 left the same half open: a new pin is a design decision against a
closed catalog, and an errata fixing a data-layer defect has no standing to make one. E170 fixed
what the pin *says*, which needed no catalog change; what it *draws* waits for whoever owns C19.

**If it is taken up**, the shape is `MapPinKind.kind(for:)`, which already switches
`case .deadReported, .removed: return .removed` — one line, and `MapPinCopy.deadReportedLabel` is
already the override that would move onto the new case's `accessibilityLabel`. What must not happen
is the reverse: routing `deadReported` to screen 19 to make the map tidy. That takes the REPORT
button off the one status where a hazard report matters most, and `ModerationTests` asserts against
it.

**Closed by R64** (2026-08-05): words-only, for now — no drawn pin is commissioned for the
confirmed-dead tree or the vacant site.

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

**The rule this generalizes to.** *An id space is the numbering an inventory's publisher keys its own
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
clipped gray box and every field was below a fold nothing on the screen admitted to. The owner's
report — that it is not clear there is content below the photo — was an understatement of the AX5 case.

**The ruling, in two parts.**

**1 · A bound on the photograph takes width, never height, and never ratio.** The well is the frame of
the photograph it holds, so it is always exactly the photograph's shape; when there is not room for it
at the gutter's width it takes less width and is centered. This is the point E162 missed when it refused
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
Favorites, species, year.** Design was delegated. This is what was decided and why, including the two
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
  notice. Two ways out, both labeled.
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
already names the ≤4 colored species, already sits in the chrome, already costs the space it costs.
Tapping an entry narrows the map to that species; tapping it again clears; the selected entry takes the
filter row's own selected fill so the state is said in the language the chips beside it use. Zero new
screen space, and the two surfaces cannot disagree because there is one of them.

A species outside the four is reached the way it always was — typed into C20 — and `MapModel.speciesIDs`
**intersects** the two rather than letting either win. Typing "plane" and then tapping the London Plane
legend chip leaves London Planes; neither control silently undoes the other.

#### 3 · Yours and Favorites are id sets, not predicates, and they suspend A1

What this device has visited, photographed, checked in on, measured or added lives in `main`; the seed
knows none of it and no `WHERE` clause over `trees` could. So the set is resolved first
(`CypressAPI.mapMembership(_:)`, one read per press of the chip, not per pan) and rides on the viewport
the way `speciesIDs` already does — which also means a changed membership is a *different viewport* and
the existing fetch debounce sees it.

Three rules fall out and all three are load-bearing:

- **`[]` means "narrowed to nothing", never "not narrowed".** A reader with no favorites who taps
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
  not made, because it would take the legend's job as a *key* (explaining pin color when nothing is
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
and the warning did not generalize because nothing had ever asked it to.

**Why nil and not a San Jose branch.** Writing one would be a design decision taken in passing, on a
vocabulary nobody has studied, inside a change about schema. And the branch somebody would write is
probably the wrong one: `GROWSPACE` (`Park Strip`, `Well/Pit`, `Median`, `Tree Lawn`) is a far better
signal for where a San Jose tree stands than `OWNEDBY`, and choosing between them deserves its own
look. Meanwhile nil draws nothing, which is what E9 already established for a species with no sourced
leaf retention: **absence renders as absence, and a default is the bug.**

**The rule this generalizes to, and it is the point of the entry.** *A derivation over a publisher's
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

**What was already specified, quoted rather than summarized.** `SCREENS.md` §2 draws C20 as a pill
with a leading magnifier, a placeholder and nothing else. Screen 01 lists the bar at `top:68px` as
item 11 of its structure, says of its behavior only that "search opens species/street/neighborhood
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
(task #108) made the catalog match a word anywhere in either name with a rank; no matching is
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
| `.none` | every match is on screen and the catalog's answer was not itself a page | *nothing* — the list is the answer |
| `.exactly(n)` | more matched, and the catalog counted them all | "Showing 6 of 21 matching species. Keep typing to narrow it." |
| `.atLeast(n)` | the catalog returned a full page, so the total is unknown *and unknowable from here* | "Showing 6 of at least 100 matching species. Keep typing to narrow it." |

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
rather than photographed, so it would add four colors over a map whose own species palette is already
four colors, for no information. **A count of trees:** a per-species count is a read of a
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
01's chrome is two absolutely positioned blocks, and the bottom one — recenter, FAB, tree card — was
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
catalog and could pick up anything else containing the phrase. A subsequent keystroke releases the
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
  street and neighborhood search under E134 because the bar cannot do either, and both are
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
favorite does — with a real off state that leaves nothing behind (R2). Un-adopting is not a failure
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
  already sets the precedent — caretakers are shown only at ≥3 distinct people. Favorites are private
  (R2, D11), so a threshold of one would publish a private bookmark and a threshold of two would make
  it inferable by anyone who knows they are the other. The floor must be high enough that no individual
  is recoverable from the state.
- **The set is shown unordered and rotating, not ranked.** A neighborhood's beloved trees is a handful
  of trees to go and see, drawn from those over the floor, and the order carries no meaning. If the set
  is larger than the view, it rotates rather than truncates to the "top" — E38 applies, and a page is
  not a total.
  **← SUPERSEDED the same day by R27.1 below. The owner overruled it. Do not build to this bullet.**

**What this costs, stated rather than buried:** the owner asked "most favorites? most photos?" and the
answer is neither, in the superlative sense. There is no "most". A reader who wants to know which tree
in the Mission is the single most loved will not find out, and that is the intended outcome, because
every mechanism that answers it is a leaderboard wearing a different noun.
**← This paragraph is the part the owner rejected, and they were right. See R27.1.**

**Deliberately not decided here:** the numeric floor (it wants the real distribution of favorites per
tree, which nobody has looked at yet — count it before choosing it); whether photographs and favorites
should count toward the same state or two different ones; and whether "neighborhood" here means the
analysis-neighborhood geometry already in `Fixtures/raw/sf_analysis_neighborhoods.geojson` or the
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
generalized a constraint on one noun to a different noun and called the result principle. The owner's
correction also supplies the purpose R27 had lost sight of: **the app exists to bring people to trees.**
A discovery surface that refuses to say which tree is worth the walk is not being principled, it is
being useless.

**The ruling.**

**1 · A neighborhood's beloved trees is an ordered list, and it says which is first.** Rank by how many
distinct people have favorited the tree. Show the ordering. Showing the number too is permitted and
preferred — ranking while coyly hiding the count is the worst of both, since the reader infers a number
anyway and cannot tell how thin the margin is.

**2 · The floor from R27 survives untouched, and its job is privacy, not modesty.** Favorites are
private (R2, D11). A tree below the floor must not appear in the ranking at all, because at a count of
one the surface publishes somebody's private bookmark and at two it is inferable to whoever knows they
are the other. The floor is a k-anonymity threshold; DECISIONS' existing precedent is ≥3 distinct
people. It is not negotiable downward for a sparser neighborhood — a neighborhood with nothing above
the floor shows nothing and says why (E126), rather than lowering the bar to fill the screen.

**3 · No person is named, counted, or reachable through the list.** The ranking is over trees. Nothing
in it links to who favorited anything, no contributor appears, and there is no route from a beloved
tree to the set of people who love it. D1 and D11 are untouched by this ruling and remain absolute.

**4 · The one panel finding that survives is real, and the owner's own framing answers it.** The
round-2 panel's objection (DECISIONS §2.6) was that ranked attention routes toward Grandmother Cypress
and away from the young street trees that most need eyes. That is a genuine failure mode and this
ruling does not dismiss it — but the owner asked for a surface that brings people to **"new and
interesting"** trees, which is not the same as the same famous tree every time. So the list is
**personalized by exclusion**: a tree you have already favorited, photographed or visited drops out of
your own view of it. The ranking is global and honest; what it shows *you* is the part of it you have
not met. This costs nothing in integrity — the order is unchanged, nothing is fabricated, and the
reader who wants the famous one can search for it — and it converts the panel's objection into the
feature the owner asked for.

**5 · Favorites only.** The owner was explicit that photo counts are not wanted here. One signal, one
meaning: *how many people chose to keep this tree*. Do not blend photographs, visits or care events
into a composite score — a composite is unreadable, unfalsifiable, and is the shape that eventually
grows into a leaderboard.

**Still open, inherited from R27:** the numeric floor, which wants the real distribution of favorites
per tree before it is chosen — count it, do not guess it; and whether "neighborhood" means the
analysis-neighborhood geometry in `Fixtures/raw/sf_analysis_neighborhoods.geojson` or the viewport the
reader is looking at. **New and open:** whether the ranking is stable enough to be worth ordering at
local-beta volumes. With a handful of devices, first place may be a tree with four favorites and second
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
centered on the reader moves as they walk. "Walk the nine" becomes a claim about where somebody was
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

**The spelling.** The owner named the word: *favorites*, not *favorites*. `MapMembership.favorites`,
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

The owner named "favorites", not "favorites". This change spells it American in the two files it
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
shows indoors and a phone in daylight does not. The channels that survive grayscale — border
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
that survives grayscale, so the state now carries in fill-luminance, border width and weight —
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
  vitality RATING — a judgment that is meaningless against a bare deciduous canopy — and its
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

**Amended 2026-08-03 by `RULINGS R60`:** the version grammar gained a `build_id` segment. The immutability rule below is unchanged and is *why* the amendment was needed — see R60 before publishing anything.

**2. Versioned paths are immutable; only `manifest.json` is ever rewritten.** Objects
land at `cities/<id>/<version>/<id>.sqlite`, written once; the update check on device
is string equality on `version`. Files upload before the manifest that names them.

**3. City files are narrowed copies, not rebuilt files.** The publisher byte-copies
the fused seed and DELETEs the other city out (then VACUUMs), so schema fidelity is
by construction. What survives: the city's `trees`, its `species_assertions` and
R*Tree entries, only its `id_spaces`/`inventories` rows, only referenced
`neighborhoods` — but `species`/`species_map` stay WHOLE, because the species
catalog and its curated content are shared authored work, not city data, and
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
   button cannot be built as labeled — `excludedActivityTypes` cannot exclude third-party
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
alternative — having one dimension clear the other — is the single-select behavior R23 §1 was
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
  somebody's report, not a license to rewrite any species at will. A lead with an opinion and no
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
the middle of a building, a duplicate two meters from another pin, a community add that was a
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

Two rows, one plant, and the reader has no way to tell which to press. The second line is labeled
by position as the scientific name; `:: Arbutus 'Marina'` is not a scientific name, it is our
parser's failure quoted back at someone looking for a tree.

**The builder half went first, and it changed the size of this question.** `Tools/build_seed.py`'s
BOTANICAL/COMMON swap now reads a miscased genus and a quoted cultivar, so fifty-eight of those
sixty-five trees merged into the species they were always naming and seven duplicate rows left the
catalog. **Five stub species and seven trees remain**, and they are the residue that cannot be
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
   any single city name is a mislabel; swapping which city is mislabeled is not a fix. Scoping the
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
   type and color (`CypressFont.body125`, `CypressColor.textMuted`) for that reason.
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
  apologizing." Adding an apology here would reverse that decision on one block. Considered and
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
removed pin's gray dot precisely so the map would not say a tree had stood there; the drawing asserts
*a place a tree could go*. The records #125 exists for do not have one. R46's own motivating cases
are a row in the middle of a building, a duplicate two meters from another pin, and a community add
that was a mis-tap — and there is no planting site at any of them. Writing `vacantSite` would replace
one false assertion with a quieter one, which is the move R7 refused for the vacant site and R19
refused for the standing dead tree. It would be strange to make that argument three times and then
decline to make it a fourth in the case where the assertion is not merely imprecise but false.

The second reason is the seam. `ReviewFlag.Kind.confirmedStatus` is derived from `resolution`, and
`statusReviewKinds` is derived from `confirmedStatus != nil` — E170's property, that one exhaustive
switch serves both the raise and the resolve. Pointing `neverExisted` at any status is the one-line
change that makes the kind resolvable, and it would enroll record defects in the lead's *status*
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

The obvious sentence was the one two neighboring surfaces already use — *"This goes to a community
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

Two decisions, both under the standing delegation for copy and behavior the mocks do not cover.

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
recognizing it is not a reading of any publisher's vocabulary — which is why it carries no id-space
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

- **What San Jose's `GROWSPACE` should be labeled**, or whether it should reach a card at all under
  a label of its own. It is a real signal — R24's own text calls it "a far better signal for where a
  San Jose tree stands than `OWNEDBY`" — and it now reaches the reader only through the `Site` card,
  verbatim, on the rows where it states something.
- **Whether the six `city_record` columns should hold another publisher's columns at all.** Open, and
  the subject of #134.
- **The other two E209 members.** `SharePresentation.ShareCopy.city` (Shape A, needs a source for a
  short civic name no table carries) and `MapKitBasemap.defaultCentre` (Shape B, needs a per-city
  center the manifest does not carry) are untouched and still want their own tickets.

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

So a park-shaped or neighborhood-shaped trigger is not a design option that was declined on taste.
It is not available.

##### 2.2 It would also have been wrong

`Golden Gate Park` *is* one of the 41 analysis neighborhoods (as are `Lincoln Park`, `McLaren Park`
and `Presidio`), so a neighborhood-keyed notice was superficially buildable and is exactly the lie
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
empty and the notice never fires there. That is correct behavior for a trigger that answers "this
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
  characterization invented for this screen. All three inventories `Tools/inventory_contract.py`
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

**The layout question §6 left standing is answered by R65** (2026-08-05): the card scrolls once
it runs out of room.

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

### R55 — One plant under several spellings is a corpus repair, not a list behavior — and only its last tier is a synonymy claim (task #184, delegated)

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
R47's five unreadable rows are set aside), computed by normalizing `scientific_name` and grouping.
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
- **The map legend and the species-narrowed map split too.** `MapSpeciesPalette` colors by species
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
thyrsiflorus` and `Ulmus parvifolia`. Every rule above normalizes how a cultivar epithet is
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

**Mint each surviving row's uuid from its own verbatim name, exactly as today, and use the normalized
key only to decide which rows share a family.** Then no surviving uuid moves: `Arbutus 'Marina'`
keeps `uuid5(NS_SPECIES, "arbutus 'marina'")` and the 194 cultivar rows keep theirs. What
disappears is 19 to 30 loser uuids, which is unavoidable and is the point of the ticket. A design
that normalized the *minting* input instead would move all 194 — including every row a grove entry,
a favorite or a `species_assertions` chain already points at — and there is no reason to.

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

### R56 — American spellings: what the guard checks, and what it cannot (task #140)

#### The ruling

**One named word list, `BritishSpelling.forms` in `CypressTests/BritishSpellingGuardTests.swift`, is
the project's definition of "British". Two tests read it, from opposite ends:**

1. `BritishSpellingGuardTests.everyAppStringLiteralIsAmerican` — reads the **app target's own source
   off disk** and checks **every string literal in it**.
2. `AlmanacGeographyTests.fallbackSaysWhatItIs` — E182's original check, kept, now reading the same
   list, over three strings **screen 12 composes at runtime**.

Neither subsumes the other, and that is the whole design: the first is broad and static, the second
is narrow and dynamic. A guard with only the first would miss a sentence assembled from two innocent
halves; a guard with only the second would miss every screen nobody thought to add.

#### Why a source scan rather than the obvious alternatives

The phrase in the ticket is "every user-visible string in the app". Three ways to reach it were
considered and two were rejected:

- **Reflect over the 44 `*Copy` types.** Swift has no reflection over static members, so each type
  would need a hand-maintained `static var allStrings`. A string added tomorrow is not in it, and
  the guard's completeness becomes a thing somebody has to remember — which is the chore #140 exists
  to end.
- **Scan the built binary.** Attractive, and wrong: Swift stores literals of 15 UTF-8 bytes or fewer
  inline as instruction immediates rather than in `__TEXT,__cstring`. `"Not centred"` is 11 bytes. A
  byte scan of the binary would have passed clean over the exact string this ticket started from.
- **Scan the source.** `#filePath` is this test file's absolute path at compile time, and a
  simulator test process is an ordinary macOS process that can read the host filesystem back. So the
  guard walks `<root>/Cypress/**/*.swift` and reads it.

The scan is a small character scanner, not a regex: `"` inside a `//` comment, an escaped `\"`, and
`"""` blocks all occur in this codebase and all defeat the regex versions of this.

#### What the guard checks

Every string literal in the app target — a **superset** of the user-visible strings. It also sweeps
SQL, log lines and gate messages, deliberately: over-covering means no list of "which literals are
copy" has to exist, so nothing depends on a future author classifying their string correctly.

#### What the guard does **not** check, stated because a guard that claims more than it checks is
worse than one that states its limits

1. **Strings the app reads out of the database.** `species.id_tips` carries **18 rows of British
   botanical prose in the shipped seed** — "Dark grey to red-brown bark", "the coloured-leaf
   records", "Smooth pale grey trunk". These *are* user-visible and this guard cannot see them. They
   were left alone on purpose: `Fixtures/species/curated.yaml` cites a fetched source per value and
   its own header forbids hand-editing (DECISIONS constraint 15, BUILD-PLAN §15), and the text is
   already baked into a published 108 MB seed that #140 cannot regenerate and re-verify. **This is
   open work, not a closed question** — see "Residue" below.
2. **Strings composed at runtime** by a `Formatter`, or joined from fragments where no fragment is
   British alone. E182's runtime check covers exactly three such strings on one screen.
3. **Identifiers and comments.** Renamed by hand in #140 passes 2 and 3, and deliberately not
   guarded. A symbol-level guard needs a permanent exception list: `Alegreya` (the body font)
   carries `grey`, `flameTree` carries `meTre`, and `optimistic`, `specialist`, `organism`,
   `capitalism`, `realistic`, `generalist` and `initialisms` each carry an `-ise` stem. Every one of
   those was a live false positive during this ticket. The cost of maintaining that list forever is
   higher than the cost of a stray British identifier, which no reader ever sees.
4. **The test targets.** `CypressTests` and `CypressUITests` were rewritten but are not swept: their
   strings are not shipped, and `AlmanacGeographyTests` has to be able to hold British specimens.

#### The word list is a list, not a dictionary

It catches the forms it names. Every form this repo carried at #140 is in it, plus the rest of each
family so the next one written is caught too. Two rules govern additions:

- **Word boundaries only where a bare substring strikes correct English**, and each one is covered
  by `theWordListLeavesCorrectEnglishAlone`. A false positive disables a guard faster than a false
  negative does.
- **`-ise` stems are named individually and require a verb ending.** A blanket `-ise` rule strikes
  `advertise`, `surprise`, `exercise`, `comprise`, `premise`, `expertise` and `otherwise`; a stem
  without an ending strikes `optimistic` and `specialist`.

`towards` is **not** on the list: it is standard American English alongside `toward`.

#### The guard cannot pass by seeing nothing

`theGuardCanSeeTheSource` fails — never skips — if the source tree is not where `#filePath` says, if
fewer than 150 files are swept, if fewer than 3,000 literals are read, or if fewer than 300 of them
are sentence-shaped. A skip would read as "checked and clean". `theScannerReadsWhatItSaysItReads`
pins the scanner against a specimen with a comment, an escape, an interpolation and a `"""` block;
`everyPatternCompiles` catches a pattern that silently matches nothing.

#### Residue — the deliberate exceptions

Two string literals in the app target are allowlisted in `AppSourceLiterals.contractual`, each
because it crosses into data this repo did not write:

| literal | why |
| --- | --- |
| `case_normalised_columns` | a `seed_meta` key `Tools/build_seed.py` writes into the published seed |
| `Dark grey to red-brown bark, …` | an `id_tips` row quoted verbatim from `curated.yaml`, present verbatim in the shipped seed |

Not guarded and not corrected, all reported rather than forced:

- `Fixtures/species/curated.yaml` — **20 British spellings in botanical prose** (18 `grey`, 2
  `colour`), which reach the reader as the **18 `species.id_tips` rows in the shipped seed** that
  carry 20 British spellings between them. **The one piece of genuinely user-visible British text
  #140 did not fix.** Correcting it is an edit to a file whose header forbids hand-editing, plus a
  seed rebuild and a re-verification; it belongs to whoever owns the next seed build.
- `licence` in `curated.yaml` (404) and `leaf_retention.yaml` (1,688) is **not** prose and is not a
  defect: it is the field name inside each `citations` block, naming the licence of a fetched
  source. Counted here only so the next reader does not mistake ~2,000 matches for ~2,000 defects.
- `Tools/*.py` (81 matches). They build and validate the published seed; a spelling change there is
  a change to the toolchain behind a binary this ticket cannot regenerate and re-verify.
- `Fixtures/raw/**` and `Fixtures/ca_survey/**` — fetched source documents.
- `docs/ERRATA.md` and `docs/RULINGS.md`: prose corrected, **123 inline-code spans left as they
  were**. Some are quoted machine output — the `XCTAssertEqual` line comparing `"Not centred"`
  against `"Centred on you"` is a real 2026 failure — and rewriting one would make the record claim
  a string that was never printed. The rest are period-correct symbol names, which a historical
  record is entitled to.
- `CLAUDE.md` (1 match, the word "colour" in the verification section). Standing rules; not an
  agent's file to edit.

### R57 — The no-SF-Symbols policy stands, and is now written down and tested (task #130)

Ticket #130. Delegated design authority; decided against the code and the running screen on an
iPhone 16 Pro Max, at default type and at AX5.

**The ruling: option 1. Every glyph in Cypress is a `Shape` drawn in this repo. No SF Symbols, no
icon font, no exceptions — not for close, not for trash, not for a thumb.** The five call sites are
drawn. The policy is stated at app scope in `ShareDestinationGlyph.swift` and enforced by
`CypressTests/DrawnGlyphGuardTests.swift`.

#### 1 · What the ticket got right, and the three things it did not

The five call sites were real and are exactly as listed. Three corrections, all of which changed how
the decision had to be written:

- **The policy had never been written at app scope anywhere.** `ShareDestinationGlyph` cited
  "SCREENS.md §2 C16" for it. C16 is the `BottomTabBar` component, and its "Icons (all hand-drawn,
  no icon font)" is a bullet introducing *that bar's own four icons* — Map, My Grove, Journal, You.
  `RULINGS` R16 then cited `ShareDestinationGlyph` as "the statement of the policy". So the
  app-wide rule everyone was enforcing rested on a citation loop that bottomed out in one
  component's spec. **This is why neither option was "restore the rule": the rule had to be written
  for the first time either way**, and the only question was which rule to write.
- **Five call sites, but seven distinct symbols.** `TreePhotosPresentation.glyph(_:filled:)`
  returned four names — `hand.thumbsup`, `hand.thumbsup.fill`, `hand.thumbsdown`,
  `hand.thumbsdown.fill` — from one call site. A gate that counted call sites would have let a line
  add symbols without adding a hit. The gate counts *uses of the API*, and its own control asserts
  the token list is populated.
- **`ShareDestinationGlyph`'s policy paragraph is at lines 18–20, not 16–18**, and none of the five
  sites is dead code: the library shutter is reached from both `VisitCameraView` and
  `ContributionCameraView`.

#### 2 · Why the policy stands

The brief framed this as a real choice, and the honest case for narrowing — E163's receipt that
hand-drawing costs path defects — was weighed. Three things decided it.

**The record is one-sided, and it is a record of practice, not of prose.** Every design decision
this project has taken on a glyph refused a symbol *while these five sat in the tree*: R16 drew the
search bar's ✕ by hand rather than take `xmark.circle`; R39 drew `Share…` as a tray and arrow rather
than take `square.and.arrow.up`; R2 refused to invent a heart and counted doing so as a "**sixth**
violation of the drawn-glyph policy the project is already carrying five of"; the #166 site-kind
ruling chose a `Menu` partly because it "draws no SF Symbol (adding nothing to #130's five debts)".
The five were never an exception anybody granted. They are the un-ruled residue of one corner of the
app — Photos and the visit camera — and the project has been routing around them, in writing, for
months. Narrowing the policy would have ratified an oversight as a decision.

**One of the five was already solved twice over.** The app ships two hand-drawn ✕ marks —
`VisitCloseGlyph` (the camera's) and `CypressClearGlyph` (C20's, a ring with an ✕ in it). The photo
viewer's close button reached for `xmark` anyway. Any "closed set of system-conventional
affordances" would have had to include close, and including it would have meant permitting a symbol
for a mark this repo had already drawn, twice, on screens a person reaches in the same session.

**The cost did not materialize — and that was checked before it was claimed, not after.** The five
marks were drawn as SVG at the same coordinates the Swift uses and rasterized at 17, 24 and 53 pt,
stroke and fill, before a line of Swift was written. All five read. Four of them are straight lines,
rounded rectangles and one ellipse — none needs the arc-chaining that broke AirDrop and Copy link in
E163. The thumb is the only hard one, and it is one closed subpath.

E163's actual lesson is narrower than "hand-drawing is expensive": both of its defects were a path
API that *appends to a current point* being used as though it started a fresh one. Every subpath in
the new marks opens with its own `move(to:)`, and each file says so and cites E163 by number, so the
next reader knows what to check for rather than being told the code is fine.

#### 3 · What is drawn, and the one construction worth recording

`Cypress/Features/Photos/PhotoGlyphs.swift` — `PhotoTrashGlyph`, `PhotoThumbGlyph`,
`PhotoCloseGlyph`. `Cypress/Features/Visit/VisitCameraView.swift` — `VisitLibraryGlyph`. Each lives
beside the screen that uses it rather than in `DesignSystem/Components`, which is the arrangement
`ShareDestinationGlyph` and 14's camera glyph already state and give the reason for: C1–C30 is a
closed catalog and no other screen uses these.

**One thumb serves all four states.** A downvote is the same mark turned a half turn
(`rotationEffect`), and the reader's own vote fills the path instead of stroking it. There is one
set of numbers, so the two directions cannot drift apart and the filled state cannot disagree with
the outline. Which vote turns it is `TreePhotosPresentation.thumb(_:filled:)`, a value a test can
call — E164's rule that a mapping only the renderer can reach is a mapping no test can check.

**The stroke scales with the box.** All marks are authored in a 24×24 box at stroke 1.8, the app's
own line weight, and drawn at 17 pt. A 1.8 pt line left unscaled in a 17 pt frame is the weight of a
2.5 pt line in the box it was drawn in — the difference between a mark and a blob. `stroke(for:)`
carries this and a test pins it.

**The library shutter keeps its second card.** A single framed picture says "a photo"; the stack
says "*pick* one", which is the distinction that button is drawing against the camera shutter beside
it, and the reason the old comment gave for choosing `photo.on.rectangle` in the first place.

#### 4 · What was looked at

Screens 20 (photo browser), the viewer, and the visit camera's library shutter, on the running app,
at default type and at AX5 — recorded in the ticket report with screenshots. The marks are drawn at
a fixed point size and do not scale with Dynamic Type, which is the behavior the SF Symbols they
replace also had (`.font(.system(size:))` is a fixed size); AX5 changes the rows around them, not
the marks. **This is a deliberate limit, not an oversight, and it is the obvious thing to revisit:**
a 17 pt mark beside body text at 53 pt is small, and it was small before #130 too. Whoever takes
that up should take it up for every drawn mark in the app at once rather than for these five, which
is why it is not taken here.

#### 5 · The gate

`DrawnGlyphGuardTests` reads every `.swift` file in the app target off disk through `#filePath` —
the walk is `BritishSpellingGuardTests`' (R56), reused rather than duplicated — and fails on
`systemName:` or `systemImage:` appearing in code. It blanks comments and string-literal interiors
first, which is load-bearing: #130 deliberately writes the token `Image(systemName:)` into prose in
`MapChrome`, `ShareDestinationGlyph` and `PhotoGlyphs` to record what was removed and why. A control
asserts those prose mentions still exist *and* are not counted, so the day the scanner stops
stripping comments, the control fails rather than the gate — and the next reader fixes the scanner
instead of deleting a gate that has started crying wolf.

Provenance controls, in the same shape R56 established: the guard fails if it cannot find the source
tree and if it sweeps fewer than 150 files, because this project's signature failure is a green
result from a check that ran on nothing.

**What it cannot check:** a symbol reached through a name built at runtime, or a UIKit view
configured without ever spelling `systemName`. The gate covers the spellings SwiftUI and UIKit
actually offer and claims nothing beyond them.

#### 6 · What this overrules

Nothing. It writes down a rule the project has been enforcing in every ruling since R2 and states
it at the scope it was always being applied at. It corrects two comments that asserted the rule as a
fact about the code while the code disagreed (`MapChrome`'s "two calls, both inside a photo picker"
— it was five, in three files, none in a picker) and two that cited `SCREENS.md §2 C16` for an
app-wide claim C16 does not make (`ShareDestinationGlyph`, `ComponentSupport`).

`SCREENS.md` is **not** amended. C16's bullet is correct about C16; the error was in citing it, not
in what it says. R16's citation of it is left as written — the ruling record is not rewritten after
the fact — and the correction is recorded here and in the two code comments that carried it forward.

### R58 — A UI test drives the app's location state; it does not detect it (task #121, delegated)

*Pending. Cite this file as `RULINGS R58` until the
orchestrator splices a number; #121 delegated the shape of the state-driving mechanism.*

#### The ruling

**`CYPRESS_LOCATION` in the launch environment replaces the composition root's one shared
`MapLocationProvider` with a pinned double reporting exactly the availability it names.** The
grammar is `DebugLocationOverride.parse`:

    CYPRESS_LOCATION=denied                   the reader said no
    CYPRESS_LOCATION=servicesOff              Location Services off device-wide
    CYPRESS_LOCATION=notAsked                 the sheet has not been shown
    CYPRESS_LOCATION=waitingForFix            allowed, no fix yet
    CYPRESS_LOCATION=37.78485,-122.4215       a fix, at DebugLocationOverride.defaultAccuracyM
    CYPRESS_LOCATION=37.78485,-122.4215,25    a fix, at a stated accuracy

All five of `MapLocationProvider.Availability` are reachable. The named values are spelled exactly
as the enum's own cases, so there is one vocabulary rather than two.

Every test that used to skip on ambient simulator state is now unconditional:

| test | launches with |
|---|---|
| `MapRecenterUITests.testPressingItWithLocationDeniedExplainsRatherThanDoingNothing` | `denied` |
| `AlmanacGroupTapTests` (2 cases) | `37.78485,-122.4215` |
| `MapCenteredStateUITests` (2 cases) | `37.7599,-122.4148` |
| `MapPanTabSwitchUITests` (2 cases) | `37.7599,-122.4148` |

**`CypressUITests` now reports `0 tests skipped`, where a healthy device previously reported 4.**

#### A refuted premise, and it is the reason the count is 4 and not 2

**The ticket names two `XCTSkip` guards. There are six**, and the four it does not name are the same
class and the same words:

    MapCenteredStateUITests.testTheMapOpensOnTheReaderWithoutBeingAsked
    MapCenteredStateUITests.testTheControlSaysCenteredOnceTheMapIsOnYou
    MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack
    MapPanTabSwitchUITests.testAnUntouchedCameraStillCentersOnTheReaderAfterTheRoundTrip

    Test skipped - this simulator never gave Cypress a fix (the control reads "Finding you"),
    so there is nothing the map could have opened on

They were the *only* skips left after the two named ones were fixed, and they are load-bearing:
`testTheMapOpensOnTheReaderWithoutBeingAsked` is the whole of #115's claim — "opening the app should
open on where you're located, 100% of the time" — and on every ordinary fixless simulator it had been
declining to check it, inside a green number, since it was written. Its own doc comment says so:
"The skip below is honest and it is also a hole." Fixing the two named tests and leaving these would
have left the ticket's actual subject — a green run that does not say what it did not check — exactly
where it was.

All four pass with a pinned fix. Their guards are now failures rather than skips: `MissingPinnedFix`,
which is thrown only when a launch that *stated* a fix reports itself fixless — a defect in the seam
or the wiring, never a fact about the machine.

#### The problem this fixes, stated narrowly

The two skips were **honest** and **correctly reasoned**. Both were documented at their site with
`MapSearchUITests`' argument — *a skip says "not checked here", which is true, where a failure would
say "broken", which is not* — and both could genuinely fire, which distinguishes them from #101's
guard that never could. Nothing here contradicts that reasoning.

The residual problem is about **reporting**. A skipped test is invisible in the line this project
judges a run by: `Test run with N tests passed` counts a test that declined to run exactly the same
as one that ran and passed. `MapRecenterUITests`' refusal test skipped whenever location was *not*
denied — which is the state of every simulator anybody has ever handed this suite — so the permission
refusal path, the sentence naming the limit and the Settings button, was unexercised in every
ordinary run, under a green number, and nobody reading that number would know.

The cure for a test that detects state is to let it drive the state. Both candidate fixes in the
ticket were available; this is the first and preferred one, and it turns two conditional tests into
two unconditional ones rather than making a skip louder.

#### What the seam proves, and what it does not

**It proves the app's behavior in each location state. It does not prove CoreLocation's behavior in
producing that state.** A pinned provider never talks to `CLLocationManager`: no delegate is
attached, `start()` and `stop()` are no-ops, and `authorization` is derived from the availability
rather than read. So `CYPRESS_LOCATION=denied` exercises everything downstream of "the app believes
location is denied" — the standing notice, the recenter refusal, the Settings affordance — and
nothing upstream of it.

What is therefore *not* covered, and was not covered by the skipping version either: that iOS
actually reports `.denied` after a revoke, that `MapLocationProvider.apply(authorization:)` maps the
status correctly, and that the Springboard permission sheet appears and can be answered. The first
two are `CypressTests/MapLocationChurnTests`' subject, driving `manager.delegate` directly. The
third is not tested anywhere and this ruling does not claim it is.

`xcrun simctl privacy <udid> revoke location app.cypress.Cypress` remains the way to put a device in
the real state, and remains worth doing by hand before believing anything about the permission
boundary itself.

#### Why the composition root and not the view

`RootView` owns the one shared provider (ARCHITECTURE §3), and every screen that reads a fix —
01, 05, 07, 12, 16, and the visit flow — reads that one. Pinning it there means one substitution
reaches all of them, and `MapHomeView`'s own comment about why it must not construct a provider
stays true. Substituting per screen would have been six seams and six chances for them to disagree.

#### Why `authorization` is derived rather than named separately

`.denied` with an `authorizedWhenInUse` status is not a state iOS can be in. A seam that let a test
construct one would be a seam for testing states the app will never see, and a failure found in such
a state is not a defect. The mapping is `notAsked → notDetermined`, `denied → denied`,
`servicesOff → restricted`, `waitingForFix`/`located → authorizedWhenInUse`.

#### Why a coordinate is a first-class value, and why the default accuracy is 8 m

`AlmanacGroupTapTests` needs the *presence* of a fix, not its absence, so "denied or fixless" would
not have made it unconditional. The default accuracy is 8 m because D6 excludes a reading worse than
15 m from growth charting: a pinned fix reporting a pessimistic accuracy would silently empty every
chart built on it, putting the app in a state no reader is ever in. A caller who wants the other side
of that gate says so with a third field.

#### The one cost, and how it is contained

**A pinned coordinate moves screen 01's camera, and that camera outlives the run.** `MapCameraMemory`
writes it out on the way to the background and the next run's E216 preflight reads it back — so a
test that pinned a fix over the ocean would leave the device refusing the following run. Both named
fixtures are inside the inventory's coverage and the counts were measured over the same ±250 m box
`Tools/run_tests.sh count_camera_trees` uses:

    37.78485, -122.4215   Western Addition                   780 trees
    37.7596,  -122.4269   Mission Dolores, the map's default  553 trees
    37.7599,  -122.4148   the map tests' own coordinate       501 trees

`DebugLocationFixtures` carries the first two, with the measurement; the third is the coordinate
`MapCenteredStateUITests`' skip message already named and stays a literal in that file. A new
coordinate must be measured the same way before it is pinned.

#### One fallout, worth reading before the next agent changes a pinned coordinate

Pinning moved the camera this suite leaves behind, and one existing test failed on the new one:

    AccessibilityTreeTests.testNoUnlabeledButtonsOnLaunch
      Failed to determine hittability of "City tree, Southern Magnolia" Button:
      Activation point invalid and no suggested hit points based on element frame

**`XCUIElement.isHittable` does not return `false` for an element XCUITest cannot compute an
activation point for — it raises.** Screen 01 is a full-bleed `Map` whose pins are SwiftUI
annotations MapKit hosts and places itself, and one at the edge of the basemap can be in the tree
with a frame that has no interior. Whether any pin is in that state is a function of where the
camera is, which is device state — so the test failed on a device left pointed at one block and not
on one left pointed at another. E202's shape, wearing an accessibility failure's clothes.

Repaired where it belongs: the loop asks the *frame* first and skips an element with no interior,
which is the same judgment `isHittable` was being asked for, expressed in a way that cannot raise.
Red-proofed by blanking `MapRecenterButton`'s `accessibilityLabel` — the assertion still fires:
`an interactive control at (330.0, 608.7, 44.0, 44.0) has no accessibility label`.

The general lesson for this seam: **a pinned coordinate is a change to the whole suite's device
state, not a local decision inside one test file.**

#### An invalid value is a banner, never a fallback

`CYPRESS_LOCATION=Denied` does not quietly become the real provider. It draws
`LOCATION OVERRIDE FAILED · Denied · expected denied | servicesOff | …` over the app, which is
`DebugDeepLink.Failure`'s rule applied to the same class of mistake: a seam that fell back would let
a test assert the denied refusal path against a simulator with a perfectly good fix, and it would
then fail somewhere else entirely — or pass.

#### On `Tools/verify_test_log.sh` and the skip count (E216)

**Surfaced, deliberately not refused against a recorded expectation.** The script now prints
`VERIFY-NOTE: XCTest skipped=N` and, in a run of both targets, appends the XCTest summary to the
`VERIFY-OK` line — which it previously dropped entirely, because Swift Testing's line wins and
XCTest's `with M tests skipped` clause went with it.

Refusing on movement was considered and rejected. The expectation would have to live somewhere, and
there is nowhere honest to put it: the legitimate count changes whenever a test is added, removed, or
— as in this very ticket — stops skipping, so the number would be edited on most branches and would
spend its life either wrong or stale. A wrong expectation refuses runs that are fine, and a guard
that refuses good runs is a guard somebody switches off. E216's insight is real and worth keeping —
*a UI log whose skip count changed between two runs of the same tree is reporting a device change,
not a code change* — but it is an insight a reader applies, not a threshold a script enforces. What
the reader needs is the number in front of them, beside the device that produced it. That is now
what they get.

#### The proof

- `CypressTests/DebugLocationOverrideTests` — the grammar, every refusal, and that a pinned provider
  cannot be moved by `start()`.
- Red-proofed on the device, iPhone 16e `3A1F212D-…`, by breaking each half in turn:
  - the app's refusal path made inert (`case .explainRefusal: recenterAnswer = nil`) →
    `XCTAssertTrue failed - pressing the recenter control with location denied changed nothing on
    screen`
  - the state the tests used to skip on, driven deliberately (`CYPRESS_LOCATION=waitingForFix` for
    the refusal test, `notAsked` for the almanac) → both go **red** where they used to go
    **skipped**: `launched with location denied and screen 01 drew no standing notice about it` and
    `screen 12 drew "See your neighborhood" on a launch that pinned a fix … so the almanac never
    received a coordinate`.
- The four unnamed tests, red-proofed the same way (`pinnedFix` set to `notAsked`): all four failed
  with `caught error: "screen 01's recenter control reads "Cypress has not been given your location"
  on a launch that pinned a fix at notAsked … this is not a machine without a fix, it is a fix that
  did not arrive"`, where they had previously skipped.
- Before: `Executed 82 tests, with 4 tests skipped and 0 failures`. After: **0 skipped**.

### R59 — The AX5 primary-CTA probe: what it asserts, and the two things it cannot see (task #173, delegated)

*Pending. Cite this file as `RULINGS R59` until the orchestrator
splices a number; #173 delegated the shape of the probe.*

#### The ruling

**`CypressUITests/PrimaryCTAReachabilityTests` launches each deep-linkable screen that has a primary
CTA at `UICTContentSizeCategoryAccessibilityXXXL`, and asserts of that control:**

1. it **exists** in the accessibility tree;
2. it is **reachable** — hittable where it is, or hittable within eight swipes;
3. it is **enabled**, after the screen's own arming step where it has one;
4. it can be brought **wholly onto the glass** — the frame inside the app's frame;
5. it is **drawn** — the frame has a width and a height;
6. its label carries **no ellipsis except as a final character**.

One `test…` method per screen, so a failure names the screen and one broken screen does not hide the
ten behind it. `testEveryTargetInTheTableIsProbed` guards the table against a target being added with
no method to call it — a row this suite would report on and never visit, which is
`Test run with 0 tests passed` in another costume.

This is the structural closure E196 asked for and could not build in-process: **SwiftUI populates no
UIKit accessibility tree under `UIHostingController`**, so a "the CTA is in the AX5 tree" assertion
was built for #144, watched fail on every screen, and removed. `CypressTests/AccessibilityTests`'
header records the dead end. **The sweep photographs; this asserts.**

#### The scope, stated as a list rather than left as a gap

Eleven screens, each with the CTA literal it is judged on:

| deep link | CTA | armed by |
|---|---|---|
| `treeProfile` | `Be the first to photograph this tree` / `Visit · say hello with a photo` | — |
| `photoHero` | the same pair, warm | — |
| `checkIn` | `Save check-in` | — |
| `measure` | `Save measurement` | tap `3` |
| `careLog` | `Done` | tap `Watered` |
| `report` | `Save a private reminder for yourself` | tap `Hanging limb` |
| `site` | `Show me where this is` | — |
| `memorial` | `Show me where this is` | — |
| `growthHistory` | `Add a reading` | — |
| `share` | `Copy link` | — |
| `pinAdjust` | `Use this spot` | — |

Two CTA labels because `TreeProfilePresentation.ctaTitle` is genuinely two-valued on whether the
tree is cold, and which one a device sees depends on what previous runs wrote onto it.

**The deep-linkable screens deliberately absent, and why** — because a table with a hole in it and no
note beside the hole is how a probe comes to be believed about screens it never visited:

- `outbox`, `activity`, `journalList`, `grove` — no primary CTA exists. These are readers and lists
  whose only controls are navigation chrome, a wifi toggle, and empty states.
- `species` — its content forks on whether there is a fix, between a list of nearby trees with
  runtime names and a `LocationPrompt`. Neither is a CTA.
- `journal` — its CTA (`Walk the …`) is real but conditional on a coverage gap existing in the
  resolved neighborhood, which is a property of the seed and the fix rather than of the screen. It is
  asserted by `AlmanacGroupTapTests`, which since #121 pins its own fix and no longer skips.
- `deadProfile`, `speciesClaim`, `speciesUnclaimed`, `recordDefect`, `anonymizedPhotos`,
  `communityPhotos`, `photos`, `you`, `moderationReview` — either the same `TreeProfileView` CTA the
  two profile rows already judge, or a screen whose loudest control is a per-row action with a
  runtime-composed label. Adding them would grow the run without adding a distinct geometry.

The arming steps are not workarounds. Screen 16's save is disabled until a reading is entered and
screen 09's `Done` until a care chip is on — specified states (PROTOTYPE-FLOW §1.3/§1.4) — and screen
06 draws no CTA at all until a hazard is chosen. A probe that read the disabled control and called it
reachable would assert the opposite of its own name.

#### The honesty note: what "not ellipsized" can and cannot mean here

**`XCUIElement.label` is the accessibility label — the string SwiftUI was handed — and not the glyphs
that were drawn.** A `Text` rendering `Continue with Goo…` on the glass reports its whole string to
XCUITest. Measured on this run: `treeProfile`'s CTA reports
`Be the first to photograph this tree` in full at AX5, in a frame 192 pt tall — the ramp wrapped it
across five lines and the label is unchanged either way, which is exactly the property that makes
truncation invisible to this API.

So check 6 catches **only truncation that happened before rendering**: a presentation layer that
shortened its own copy, or a label built from an already-elided string. **It does not catch visual
mid-word clipping inside a button whose frame is on screen**, which is precisely what E196 items 5
(screen 10's `Mes sa…`), 6 (screen 15's `Continue with Goo…`) and 7 (screen 07's `Cupressac eae`)
are. No XCUITest API on this platform exposes the rendered text. **Those defects remain the sweep's
job and a person's eye**, and this probe does not close them.

The trailing-position exemption is not a loophole. `Share…` is a real CTA on screen 10 and its
ellipsis is copy, not damage; an ellipsis anywhere else in a label is a string that was cut. That is
the only distinction the API leaves room for.

What check 4 *does* catch, and a picture makes easy to miss, is a CTA pushed off the edge of the
glass — E196 items 1 and 3, content wider than the phone, centered and clipped rather than wrapped.
No amount of vertical scrolling repairs that, so it spends the budget and fails.

#### Two design corrections, both made after watching the probe report defects that did not exist

Recorded because each one *looked* like a finding, and filing either would have been worse than not
looking.

1. **Existence is polled inside the scroll loop, not before it.** The first version waited for the
   CTA to exist and only then scrolled it into view, on the reasonable premise that an off-screen
   element is still in the accessibility tree. At AX5 that premise is false here: screens 03 and 11
   hold their CTA in a scroll the ramp makes several screens long, and the control is not in the tree
   until the scroll is dragged near it. Both reported `no button labeled … is in the accessibility
   tree` — a true sentence about the query and a false one about the app.
2. **"On the glass" means *can be brought* on, not *is* on.** Screen 16's CTA is inside a
   `ScrollView`; `isHittable` asks only whether the centre point receives the tap, so the loop
   stopped with the button's bottom 56 pt below the glass and check 4 failed on a state one more
   swipe would have fixed. Where a CTA in a scroll happens to sit is not a fact about the layout.

And one assertion deliberately **not** made: a 44 pt minimum tap target. Several controls here reach
44 through `cypressHitArea(_:)`, which puts a `Color.clear` of at least 44 × 44 in the *background*
with its own `contentShape`. A SwiftUI background does not enlarge the view it sits behind, so the
element's accessibility frame stays the size of the drawn label while the region that receives the
tap is larger — screen 11's `Add a reading` is a 13 pt bold link with exactly that arrangement.
Asserting 44 pt on the reported frame would measure the wrong rectangle. Tap targets are #183's
question, answered at the value level with a tolerance, where the real geometry is in scope.

#### What the probe found on its first run

A defect in the deep-link harness itself, not in any screen: `DebugDeepLink` resolved records from
`LocalAPI.treesNear`, which returns the **seed's** status, while every screen it opens reads
`LocalAPI.treeProfile`, which lays the device's **local status overrides** on top. See the pending
errata `ERRATA E217`. `CYPRESS_SCREEN=treeProfile` had
been opening a *removed* tree — no primary CTA, no check-in — on any device that had ever opened
screen 19, and `DeepLinkVoiceOverTests` passed throughout because it checks that the controls which
*are* there carry labels.

That is the case for this probe in one paragraph: the property it asserts is the one the AX5 pictures
were being read for, and nothing else in the repository asks a deep-linked screen whether the control
it exists to have pressed is on it.

#### The proof

- Green on the final tree: `Executed 12 tests, with 0 failures`, iPhone 16e `3A1F212D-…`, 390 pt.
- Red-proofed twice on the device, both messages read rather than the colour:
  - **a renamed CTA** (`CheckInCopy.saveCTA` → `REDPROOF save check-in`) →
    `checkIn: no button labeled "Save check-in" is in the accessibility tree at AX5, after 8 swipes
    down the screen. What is there instead: "REDPROOF save check-in", "Back", "Alive", …` — the
    diagnostic list naming the renamed control is what turns this failure from a riddle into a report.
  - **a CTA pushed off the glass** (`.offset(x: 60)` on screen 16's `ctaBlock`) →
    `measure: the primary CTA "Save measurement" could not be brought entirely onto the glass at AX5
    in 8 swipes — its frame is (78.0, 377.7, 354.0, 138.0) and the screen is (0.0, 0.0, 390.0,
    844.0)`.

### R60 — A published city file's version names the build that made it, not only the city it describes (task #197, amends R37.2)

*Written 2026-08-03 under the delegated design authority, from the bucket and the publisher rather
than from a ticket, after `ERRATA E219` found the published files a day older than the ingest fix
that corrected them. Owner approved the grammar change before it was made, because the app reads
this manifest (#157) and it is a published contract, not an internal decision.*

#### The defect in R37.2's grammar

R37.2 set `version = "s<schema_version>-r<content_rev>"` and made that the immutable path segment.
**Both fields describe the city's data, and neither describes the build.**

- `schema_version` moves when `Fixtures/seed/schema.sql` changes shape.
- `content_rev` is the newest upstream snapshot date among the city's own inventories — a fact about
  when *San Francisco* last updated its inventory.

So an **ingest** change — a corrected adapter, a new species-name rule — produces different bytes
while both fields stand still. The publisher is deterministic over a given seed, which is a virtue;
it is precisely what makes two *different* seeds collide on one version string.

That is not hypothetical. Task #103's BOTANICAL/COMMON fix landed a day after the publish, and the
bucket kept serving 15 stub species where the seed had 5, and 738 species rows where it had 731.
Both artifacts declared `generated_at 2026-07-20` and 198,625 trees. **Same claimed provenance,
different data — which is the whole argument that `generated_at` is not a version.**

Republishing under the old grammar offered only two moves, and both are wrong:

1. **Overwrite the path** — breaks R37.2's own immutability guarantee, and clients comparing version
   strings for equality would see no change and never re-download the correction.
2. **Advance `content_rev`** — states that the city republished its inventory. It did not. The app
   renders that date to readers as "city record as of", so this is a lie with a surface.

#### The rule

    version = "s<schema_version>-r<content_rev>-<build_id>"

`build_id` is the **first 8 hex of the source seed's sha256**. Everything R37 relied on survives:

- **Still derived, never wall-clock.** The same seed yields the same `build_id` and therefore the
  same path, so the publisher's determinism check — run twice, compare sha256 — still passes. Verified
  on this change: two independent runs produced byte-identical files.
- **Still immutable.** A new build takes a new path. The old objects are never rewritten; only
  `manifest.json` is, which R37.2 already permits.
- **Now self-describing.** The path states which seed build it came from, which is exactly the fact
  whose absence caused E219. `source_seed.build_id` is carried in the manifest beside the full hash
  so the two can be checked against each other.

#### Why the reader is safe

`CityManifest` treats `version` as an **opaque string compared by equality** (R43), and
`schema_version` is a separate integer. So lengthening the grammar cannot break parsing, and a
changed value reads as "update available" — which is the behavior wanted. **Never shorten or reorder
the grammar without re-reading `CityManifest` first**; the safety here is a property of that reader,
not of the format.

#### What this does not fix

A reader who already installed `s14-r2026-07-31` keeps it until they refresh the manifest. There is
no recall. That is inherent to immutable paths and is the cost R37 accepted knowingly; it is
recorded here so the next reader does not mistake it for an oversight.

### R61 — The direction cone is visual-only — heading never enters what VoiceOver says (task #155)

**Orchestrator decision, task #155 (2026-08-03).** The reader's dot now draws a compass cone
showing which way the phone is pointing. The question this settles is whether that bearing also
reaches the spoken channel.

## The decision

**It does not.** `MapMarkerView`'s accessibility label for the reader's own dot stays exactly what
#100 made it — `Your location` — and says nothing about heading, in any state, at any accuracy.

The reason is what the spoken channel is for. #100 made the dot's label answer *where you are*: one
fact, stable while the reader stands still, spoken once when they move focus to it. A bearing is not
that kind of fact. It changes every time the reader turns their wrist, and a VoiceOver value that
rewrites itself several times a second does not inform anybody — it talks over the tree names, the
distances and the search results that the same screen is trying to speak. The reader who most needs
the map to be legible is the reader this would interrupt most.

The cone is therefore a **sighted-only affordance**, and that is stated as a limit rather than
hidden as an oversight: a reader who cannot see it loses nothing they previously had, because the
bare dot is exactly what the app shipped before #155 and exactly what it degrades to whenever the
magnetometer cannot be trusted.

## What this does not decide

Whether *some* heading-derived sentence belongs somewhere in the app — "the tree is behind you", a
turn instruction on screen 18's route — is a different question with a different answer, because
those are events rather than a continuously changing value. Nothing here forecloses one; this rules
only on the dot's own label.

## What holds it

`MapHeadingTests` — "the dot still says where you are, and says nothing about which way you face" —
asserts the label is `MapPin.Kind.gps.accessibilityLabel` on a marker view that is carrying a
heading. Red-proved by appending a bearing to the label: the test failed with
`"Your location, facing 137 degrees" == "Your location"`.

### R62 — The Journal tab's `City` segment — three cards, a derived city, and no name for it (delegated)

*Written under the standing delegation for copy and behavior the mocks do not cover — SCREENS.md
draws no mock for this segment at all, so ARCHITECTURE §5 rule 8 sends it to the nearest specified
thing, which is screen 12, the almanac.*

*Spliced 2026-08-04. The pending note asked the orchestrator to rewrite code comments citing its
filename in six files; there were none to rewrite — the branch's last commit had already removed
them, and `grep` across `Cypress/`, `CypressTests/` and `CypressUITests/` found no reference to this
ruling at all. Recorded because the instruction outlived the work it described, which is the same
way a confident comment goes stale.*

*Raised by the owner: "on Journal, we should have a City tab with similar but not identical stats
and views to what's on the neighborhood view. Should be insightful, interesting, educative, not pure
data porn and not overwhelming." Two changes narrowed the brief after the first pass: card 4 ("what
the record doesn't know") is cut outright, and card 3 became the five oldest trees on file rather
than one elder. Both are reflected below as the shipped design, not as a revision history.*

---

#### What was decided

The Journal tab gains a third segment, `City` (`JournalSegment.city`), alongside `Yours` and
`Neighborhood`. It draws three cards over the whole city the reader is standing in, plus the
almanac's own kind of closing footnote:

1. **`Your streets, against the city`** — the two or three species markedly more common near the
   reader than across the whole city, as a sentence: *"Monterey cypress is 18% of the trees near you
   and 4% citywide."* This is the reason the segment exists — the one comparison neither the almanac
   (which never looks past its own neighborhood) nor the species page's citywide count (RULINGS R48,
   which deliberately does not scope by city) can make on its own.
2. **`Who lives here · N species`** — the whole city's composition, in the almanac's own shape:
   `AlmanacPresentation.composition(_:locale:)`, reused rather than re-derived, so the remainder-row
   discipline ("Everyone else" computed from unrounded shares) cannot drift between the two cards a
   reader is meant to set side by side.
3. **`The oldest on file`** — the five oldest standing trees in the city whose planting the city
   recorded, each carrying the almanac's own hedge, *"in the city record since"*, never "planted in".

Card 4 — a card about how much of the record carries no planting date, and how many mapped sites are
empty — was designed, argued for, and cut on the owner's explicit instruction before it was built.
Nothing about it ships: no query, no copy, no test, no slot left for it. It is not mourned here beyond
this one sentence, because the standing instruction for a cut feature is silence, not a eulogy.

---

#### Why the screen describes a derived city, and never names one

**The bundled inventory is fused across two cities under one attached database, and nothing in it
carries a display name for a city — only for a city's *inventory*.** `id_spaces.id` is a bare key
(`sf`, `us-ca-sj`); `inventories.name` is the *inventory's* published name (`"City of San Jose Street
Tree inventory"`), the same string `CityRecordPresentation`'s provenance line already prints per tree.
Composing "San Francisco" or "San Jose" from either of those would be the same guess three prior
rulings already closed the door on, each time a screen stated a specific city's name over data that
either was not that city's, or was more than one city's:

- **R28** found a San Jose tree profile saying "San Francisco" four times, because a subtitle, a
  record-number prefix and a section header had all been written for the one city that used to be the
  only one there was.
- **R48** found a species page's citywide count spanning both cities under San Francisco's name alone
  — for Crape Myrtle, 97 San Francisco trees and 3,649 San Jose ones, told to every reader as `In San
  Francisco · 3,746`.
- **R51** found a tree-profile card reading San Francisco's `PlantType` vocabulary against San Jose's
  differently-meaning `GROWSPACE` column, because a rule written from one publisher's documentation
  does not carry to a second publisher's.

**A screen literally titled `City`, presenting three aggregate cards over a fused two-city bundle,
is the shape those three defects were each an instance of — the fourth would be the worst one, because
every number on it is citywide by construction rather than a single tree's mistake.** So the ruling
here is not "derive the city carefully and then name it correctly." It is: *derive which city the
reader's queries are scoped to, and never turn that fact into a name at all.*

**The derivation itself is a fact read off a row, not a guess about a coordinate.**
`CityQueries.resolveIDSpace(near:radiusM:)` finds the nearest inventoried tree within
`AlmanacLimits.fallbackRadiusM` (the same 1,200 m the almanac's own fallback area uses, RULINGS R29)
and reads its `id_space`. That is the same shape `SpeciesQueries.resolveNeighborhood(near:)` already
uses to answer "which neighborhood" without a boundary-file lookup, applied one level up. A reader
whose nearest tree is more than that radius away resolves no city at all, and the segment renders the
almanac's own kind of out-of-range state — a title and a body sentence, no button, never a guessed
city name standing in for "we don't know."

**What this rules out, deliberately, is `CityManifest.displayName`.** It exists — "a civic fact
entered by hand at publish," keyed by the same `id_space` — and it is the one place in this app that
*does* carry a proper city name. It was not used here, for one reason that outweighs the convenience:
it is fetched from a network manifest (`GET manifest.json`), and every other read behind this segment
is a synchronous local database query that works with the phone in airplane mode, on a first launch,
with Cities never opened. Wiring a cosmetic label to a network fetch on an otherwise fully local-first
screen would make the segment's *header* the one part of it that can fail differently from its
*content*, and it would do that for a two-word label. The segment's own name, `City` — a category, like
the almanac's own `Neighborhood`, never a place — carries the whole weight instead.

**Nothing downstream of `resolveIDSpace` is allowed to forget the predicate, either.** Every read that
follows — `CityQueries.speciesMix(idSpace:)`, `CityQueries.oldestOnFile(idSpace:)` — takes the resolved
`id_space` and predicates every row on it. `CityQueriesTests.speciesMixDoesNotSpanBothCities` and
`.cityAPIScopesCompositionToOneCity` assert this the same way R48's own test does: not "the count is
non-nil" but "the count equals a direct SQL read scoped to one city, and is strictly less than the
fused total" — a marker-based proof rather than a value that could pass by coincidence.

---

#### Why card 1 is the one built well, and what makes it render nothing

The owner's brief is explicit that this card is the reason the segment exists, so its floors are named
rather than folded into an `if`. All three are **NOT SPECIFIED** — no source states a number — and are
recorded where they are used, `Cypress/Data/API/City.swift`'s `CityLimits`:

- `minimumLocalTreesForContrast` (20) — the local scope has to hold a real sample before any
  comparison is drawn from it. Deliberately looser than the almanac's own cold-start floor for
  composition (which asks only that the read came back non-empty), because a *comparison*, unlike a
  listing, can be actively misleading at a tiny sample in a way a listing of what little there is
  cannot: two trees near the reader is a true fact stated as two trees, but stated as "100% of the
  trees near you" it is a claim about a street from a sample of two.
- `minimumLocalSpeciesCount` (3) — a candidate species needs at least this many of its own trees
  nearby, so one planting cannot read as a pattern. Chosen under A8's own floor of three for a
  headcount of *people*, and deliberately not the same floor for the same reason it differs: this
  counts trees, which carries none of the privacy weight a floor on distinct visitors carries, so there
  was no reason to set it lower than the number this codebase already treats as "small enough to name."
- `minimumDivergencePoints` (5) and `maximumDivergentSpecies` (3) — the gap has to clear rounding noise
  between two independently-rounded percentages, and the card names at most three, which is
  `AlmanacMetrics.compositionNamedRows`'s own cap for "the most common," reused here for "the most
  different."

Below any of these, card 1 renders nothing — not a zero, not a smaller version of the sentence — the
same discipline `AlmanacPresentation` names A9 for. `CityPresentationTests` proves each floor on both
sides: a sample below the floor with an enormous divergence still renders nothing
(`contrastNeedsARealLocalSample`), a real sample with a genuine zero-point gap renders nothing
(`contrastNeedsARealGap`), and a species with too few local trees is excluded even when its percentage
gap alone would qualify (`contrastNeedsARealPerSpeciesSample`) — three tests, because a single
"renders nothing below threshold" assertion would not say *which* threshold it was proving.

---

#### Why card 3 is five trees and not one, and what that costs

The coordinator's own instruction, given after the first pass: *"Card 3 becomes the FIVE oldest on
file, not one elder... with five of them on screen instead of one, that distinction gets easier for a
reader to misread, so the card's own copy has to carry it rather than relying on a per-row phrase."*

**The hedge is unchanged and is carried twice.** Every row's subtitle is `"in the city record since
{year}"` — `AlmanacCopy.elderSubtitle`'s own phrase, applied per row exactly as the almanac's single
elder carries it (`CityCopy.recordSince`, tested by `rowsCarryTheHedge`). But the almanac could rely on
that one phrase because it is one row; five rows read, at a skim, as "five old trees" rather than "five
old *dates*," so the card also states the distinction once for itself, in `CityCopy.recordNote`:
*"These are the oldest planting dates on file, not the oldest trees — most of the record carries no
planting date at all."* DataSF fills a planting date on a minority of rows (measured at 70,067 of
195,309 for San Francisco alone, RULINGS' own figure for the almanac's elder — re-measured rather than
re-quoted here, since San Jose's own fraction is unmeasured and this card is honest about the shape of
the gap rather than a number this ruling would then have to keep in step with the seed).

**Three exclusions, named because each one is a specific way this list could have misled:**

- **Vacant sites.** `CityQueries.oldestOnFile` requires `status IN ('alive','declining')` — the same
  `standing` predicate `AlmanacQueries` names for the identical reason. Measured against the shipped
  seed rather than assumed: San Francisco's own raw-oldest-dated row (`1955-09-19`) is a vacant
  planting site, one day ahead of the oldest *standing* tree (`1955-10-20`) — the two share a
  `planted_year` of 1955, which is why the exclusion has to be checked at `planted_on` grain to be
  proven at all. `CityQueriesTests.oldestOnFileExcludesVacantSites` reads the true raw-oldest row by
  identity, not by year, for exactly that reason, and records that the precondition held for at least
  one city rather than assuming it does.
- **Stub species (RULINGS R47, R54).** A tree whose species the ingest could not read carries a sound
  `common_name` (`"9662"`, `"Magnolia"`) and an unsound `scientific_name` (`":: 9662"`,
  `":: Magnolia"`); this query's own `COALESCE(s.common_name, s.scientific_name)` already keeps the
  `":: "` marker off the screen, which is precisely why a name-shaped test of this exclusion would pass
  whether or not it did anything (`CityQueriesTests.oldestOnFileExcludesStubSpecies`'s own header notes
  this and checks by tree identity instead). **The decision made here, which R47/R54 left to whoever
  needed it next: a dated stub-species tree is skipped and the next oldest non-stub tree takes its
  place, rather than being named by its position without a species.** Naming a row `"5th oldest"` with
  no identity would be inventing a rank this app does not otherwise draw (DECISIONS constraint 1);
  silently keeping the tree's place but printing nothing where its subject would go is the empty-title
  problem `IconTextRow`'s own subtitle-vs-title distinction exists to avoid (a title, unlike a
  subtitle, cannot be absent without reserving a blank line). Skipping and backfilling costs nothing a
  reader can notice — the list is still five real, nameable trees — and it is the stricter of the two
  options on a surface five times more exposed than the almanac's own single elder row.
- **The tie at the boundary.** `CityQueries.oldestOnFile` is handed one row more than the card draws
  (`CityLimits.oldestRowLimit + 1`), so `CityPresentation` can tell whether the sixth-oldest row shares
  the fifth's planting year. When it does, the list of five was drawn from a larger tied group by an
  arbitrary tiebreak, and presenting it as *the* five oldest overstates what the query proved.
  `CityCopy.recordNote(tiedAtBoundary:)` appends *"At least one more tree on file shares the last one's
  year."* rather than letting the untied phrasing stand. `CityPresentationTests.tiedBoundarySoftensTheNote`
  and `.untiedSixthRowDrawsPlainly` prove both directions, and
  `.fewerThanFiveShowsWhatExists` proves the third case — fewer than five dated trees at all, which
  draws exactly what exists with no tie logic to apply, since there is no sixth row to compare.

---

#### What this does not decide

- **Whether San Jose's own undated fraction should ever be measured and stated.** Card 4 would have
  needed it and is cut; nothing here computes or claims it.
- **A fourth card, discussed separately with the owner.** Not built, not slotted for, not named here
  beyond this sentence recording that this ruling does not cover it.
- **Whether `CityManifest.displayName` should ever reach an on-device, offline-safe cache** — which
  would reopen the question this ruling answers by *not* using the network manifest here. If that ever
  lands, the honest shape is a cached display name with its own staleness story, decided together with
  whoever needs it, not inherited from this segment's refusal to use the network copy.

---

#### What holds it

`CypressTests/CityQueriesTests.swift` — the real-seed half: `speciesMixDoesNotSpanBothCities` and
`cityAPIScopesCompositionToOneCity` (the fused-bundle guarantee), `oldestOnFileExcludesVacantSites`
(checked at `planted_on` grain, by identity, against a measured precondition),
`oldestOnFileExcludesStubSpecies` (checked by tree identity rather than by name, for the reason its own
header states), and `sanFranciscoResolvesSF` / `sanJoseResolvesItsOwnSpace` /
`outsideBothCitiesResolvesNothing` (the derivation's own distance bound).

`CypressTests/CityPresentationTests.swift` — the synthetic-fixture half: every `CityLimits` floor
proven on both sides, the tie/no-tie/fewer-than-five three-way split for card 3, the subject fallback
chain (`rowTitleFallsBackInOrder`), and `noCopyNamesACity`, which reads every string `CityCopy` owns
plus one representative dynamic sentence from each card and asserts none of them contain `"San
Francisco"`, `"San Jose"`, `"DataSF"` or either raw `id_space` key — markers rather than a fixed
string, the same discipline `SecondCityGeographyTests.theCountCardNamesThePopulationItCounted` uses for
R48, so that swapping one hardcoded city for another could not satisfy it.

Every test above was red-proofed by hand before this change was committed: the `id_space` predicate
removed from `speciesMix` (both fused-bundle tests failed with `sfTotal == sjTotal == 173538`, the
whole attached inventory, read through both `CityQueries` directly and `LocalAPI.city(near:)`); the
`standing` predicate removed from `oldestOnFile` (the vacant-site test failed with the card's own top
row equal to the vacant site's own uuid); the stub-species clause removed (the exclusion test failed
with the stub tree's uuid present in the result set); the local-sample floor removed from
`CityPresentation.contrast` (a ten-tree sample rendered `"Species 1 is 100% of the trees near you and
1% citywide."`); and the tie-boundary comparison replaced with a constant `false` (the softened note
never appeared). Each was restored immediately after its failure was read and confirmed to say what it
was expected to say.

### R63 — The photo viewer carries a door to screen 20, in the screen's control vocabulary (the photo viewer's door)

**Decision (2026-08-03), answering a field report.** Screen 20 is **NOT SPECIFIED** and so is the
viewer; both were designed under ARCHITECTURE §8 rule 8. Where a door between them goes is therefore
a decision, not a spec reading, and this is it.

## What was reported

> when i click on the tree photo from a tree page, i can get to the view where I see all photos and
> can thumbs up/down them, change between all/full/trunk/leaf only very ocassionally, and sometimes
> not at all, instead seeing only the hero photo and no other photos and no option at all to thumbs
> up/down

## The decision

**`PhotoViewerView` gains one control, `All photos of this tree`, which closes the cover and pushes
`Route.photos` over the tree the viewer already holds.**

Three things it deliberately is not:

1. **Not a change to what the hero's tap does.** The photograph opening the photograph is ERRATA
   E142, from its own field report — "clicking on photo from tree page should show full view,
   current is horizontal which cuts off photos taken in vertical orientation". Giving the hero back
   to the browser would answer this report by reopening that one.

2. **Not a bigger, louder pill on screen 03.** The pill is a genuine control with a 44 pt target and
   it is not going away, but E173 already wrote down why it cannot be the *only* door: mono 10.5 in
   a translucent capsule, drawn two inches from `Best photo · Oct 2025` in the same treatment, reads
   as a caption. Enlarging a caption produces a bigger caption.

3. **Not a thumb on the viewer.** Voting is screen 20's, because the vote is a comparison — the
   explainer there is "The photo with the most thumbs up leads this tree's page" — and a thumb on a
   photograph seen alone invites a judgment about a set the reader cannot see. What the viewer owes
   is a way *to* the set, which is what it now has.

## Why in the control vocabulary and not the caption vocabulary

The viewer's own controls are solid `heroBackFill` circles with `textBody` glyphs — `Close`, and the
delete E173 added. Its caption is a translucent `heroMetaPillFill` capsule in mono. The new door
takes the **first** treatment in capsule form, and that is the substance of the ruling rather than
styling: the defect being repaired is a control that read as a label, and a repair drawn as a label
would repeat it. It sits above the caption, bottom-leading, in the corner where this screen already
puts words about the picture, and diagonally clear of the destructive control.

## Why it is drawn unconditionally

Gating it on "this tree has more than one photograph" was considered and rejected. The count comes
from a read that has not finished when the cover appears, so the control would arrive late and move
the caption under a thumb already travelling; and the gate would be wrong anyway on a tree with one
photograph, because the thumbs are on the other side of this control and one photograph is a thing
somebody may want to vote on. The door needs only the tree id, which the route carries.

## What holds it

`CypressUITests/PhotoBrowserReachabilityTests` walks the reported path — deep link to screen 03 with
photographs, press the photograph, press the door — and asserts the three clauses of the report as
presences on the other side: a second photograph, a hittable thumbs up, and all four subject
segments. Red-proved by removing the one line that draws the door, which restores the defect exactly;
both cases failed on "there was no way on from it to the tree's other photographs".

### R64 — C19: vacant sites and standing-dead trees stay words-only — no drawn pin glyphs (owner ruling, 2026-08-05)


R19 left one question open: a confirmed-dead tree says so in words, but whether it — and the vacant
site — gets its own drawn pin was deliberately not decided there.

The owner decided it on 2026-08-05, asked directly with both options and their costs in front of
them: **words-only, for now.** No new pin glyphs are commissioned for vacant sites or standing-dead
trees; both states continue to say what they are in the sheet, in words, exactly as R19 shipped
them. The stated ground was zero designer dependency — the alternative was blocking on commissioned
glyph designs — and the decision is explicitly *for now*: it closes R19's open question without
foreclosing a future round from reopening it with designs in hand.

What this means for agents: a ticket that proposes adding a vacant-site or standing-dead pin glyph
is proposing to overturn an owner ruling, not filling a gap. Reopening it is the owner's call, the
same as the call recorded here.

### R65 — MapLocationNotice scrolls at AX5 rather than growing off the screen (owner decision 2026-08-05, task #235)

**Answers the open question R53 §6 and ERRATA E183 §2 both left standing.** E183 §2 measured
`MapLocationNotice` at AX5 taller than a 390 pt phone: laid out from `bottomChrome`'s bottom edge,
it grows *upward past `y = 0`*, taking E126's own way out (a trailing button) off the top of the
screen with it. R53 §6 measured the same defect against its own new copy, kept the shipped copy
under the tallest card already in the slot so as not to deepen it, and said explicitly: "That
defect is a layout ruling nobody has taken and it is not fixed here — it is the same open question
R23 left." R14, R22 and R25 §6 each answered the analogous question for their own surface; screen
01's bottom card had no answer of its own until now.

**The owner ruled, 2026-08-05: the card scrolls once it runs out of room, rather than growing past
the top of the screen.**

**What was built.** `MapLocationNotice` (`Cypress/Features/Map/MapChrome.swift`) takes an optional
`maxHeight: CGFloat?`. `nil` is the card's old, unbounded shape, unchanged — every call site had
this until this ticket, and `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` still measures it
that way on purpose, to compare notices against each other rather than against a screen. When a
budget is given, the card is wrapped in a `ScrollView` capped with `.frame(maxHeight:)`, following
the same idiom `MapSuggestionList` already ships (`ScrollView { … }.frame(maxHeight:
availableHeight * share)`) — nothing new was invented for this.

`MapHomeView` is the one caller that passes a budget, computed by
`MapLayout.noticeMaxHeight(availableHeight:)`: the screen's own `GeometryReader`-measured height,
minus a reservation for everything `bottomChrome`'s `VStack` stacks above the notice slot at the
worst case either control ever measures — `MapRecenterButton` and `IdentifyFAB` at
`.accessibility5` (98 pt and 137 pt respectively, measured through `AX5ReflowTests.ax5Size`, not
assumed), plus their gaps and the gap to the tab bar. The reservation is deliberately
conservative — it is not a live measurement of the controls' actual height on every layout pass —
so at ordinary sizes the budget is far larger than any card ever needs and nothing about ordinary
rendering changes; at AX5 it keeps the notice from ever claiming more room than the slot has left
above the recenter control and the FAB.

**Not fixed as part of this ruling:** the exact copy budgets R53 §6 tuned against the shipped
`MapInventoryCopy` sentence, and E183 §2's own note that the row above the card (the filter chips)
is unaffected. Scrolling is the backstop for whatever copy any of the five call sites ever carries;
it does not change what any of them say.

**Tests**, `CypressTests/AX5ReflowTests.swift`:
- `bottomChromeControlsMatchTheReservedBudgetAtAX5` — pins the two measured constants
  (`MapLayout.locateButtonHeightAX5`, `.fabHeightAX5`) against a fresh measurement, so a change to
  either control's AX5 footprint fails loudly instead of quietly under-reserving the budget.
- `mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5` — offered half its own unbounded AX5
  height as a budget, the card must not measure taller than that budget (plus a 1 pt rounding
  tolerance for `ScrollView`'s own line-height quantization). Hosted bare (no window, no settle
  loop) rather than through `AX5ReflowTests.ax5Size`: that helper's window-plus-settle-loop
  sequence was watched reporting a `ScrollView`'s full unclamped content height instead of its
  frame's cap (a 200 pt-capped `ScrollView` measured 254 pt through `ax5Size`'s exact sequence and
  200 pt through a bare `UIHostingController` never mounted in a window), so it is not the
  instrument this claim can be measured with.
- `mapLocationNoticeUnchangedAtOrdinarySizeWithAMaxHeight` — at the default dynamic type size, a
  generous `maxHeight` (a full phone's height) produces the identical measured size to no
  `maxHeight` at all.

Red-proved: with the `ScrollView`/`.frame(maxHeight:)` wrapper removed from `MapLocationNotice.body`
(returning the plain `card` unconditionally), `mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5`
failed with `(bounded.height → 357.0) <= (budget + tolerance → 179.5)` — the card reported its full,
unbounded height regardless of the budget it was given — then the wrapper was restored.

### R66 — `MapLayout.locateButtonHeightAX5` and `.fabHeightAX5` are corrected to the bare footprints ERRATA E243 measured (owner ruling, 2026-08-06, task #246)

**The owner ruled, 2026-08-06, verbatim: "correct them."**

ERRATA E243 (task #30) found that `MapLayout.locateButtonHeightAX5 = 98` and `.fabHeightAX5 = 137`
were never measurements of `MapRecenterButton` and `IdentifyFAB` — each was the control's real AX5
footprint (44 pt and 83 pt) plus the 54 pt top safe-area inset that `AX5ReflowTests.ax5Size`'s
measuring window inherited from whichever simulator it happened to run on. That entry fixed the
test harness (`ax5Size` now subtracts the inherited inset, making the measurement
device-independent) but left the two shipped constants untouched, on the reasoning that they feed
`bottomSlotReservedAboveAX5` → `MapLayout.noticeMaxHeight(availableHeight:)`, which
`MapLocationNotice`'s AX5 scroll budget documents itself as deliberately conservative rather than
exact (RULINGS R53 §6). E243 flagged, but declined to take, the ~108 pt of scroll budget the
over-reservation was costing the notice, calling correcting the constants downward "a decision for
the owner, not for a ticket about a red simulator."

**This ruling answers that open question, for these two constants specifically: correct them.**
This supersedes R53 §6's conservative stance *only* for `locateButtonHeightAX5` and `.fabHeightAX5`
— nothing else R53 §6 or E183 §2 established about the notice's scroll behavior, or about
`MapLocationNotice` scrolling rather than growing off the screen (RULINGS R65), changes.

**What changed** (`Cypress/Features/Map/MapKitBasemap.swift`):
- `locateButtonHeightAX5`: `98` → `CypressSpacing.minTapTarget` (`44`). `MapRecenterButton` is a
  fixed `minTapTarget` square and measures exactly that at `.accessibility5`, device-independently
  — asserted by `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`.
- `fabHeightAX5`: `137` → `83`, `IdentifyFAB`'s real AX5 footprint, measured through
  `AX5ReflowTests.ax5Size` after E243's fix to that helper, device-independently on both the
  iPhone 16 Pro and the iPhone 16e. Verified directly for this ruling by temporarily setting
  `fabHeightAX5` to `1` and reading the resulting `AX5ReflowTests` failure message:
  `(fab.height → 83.0) <= (MapLayout.fabHeightAX5 → 1.0)`.

`bottomSlotReservedAboveAX5` and `noticeMaxHeight(availableHeight:)` are unchanged in shape — they
still sum the same six terms — but now sum to a smaller number, so `MapLocationNotice` at AX5
renders taller before it must scroll, on every one of the five call sites that pass a budget
through `MapHomeView`.

**Comments corrected**, not merely the numbers: the doc comments on both constants used to explain
the 98 and 137 as (in one case) iOS growing the control's minimum hit target across the
accessibility range, and (in both) a deliberately-left margin over the real footprint. Neither
claim was true before this ruling and neither is repeated after it — the comments now say what
E243 measured and cite it, without naming any document that has not been numbered yet.

**Tests.** `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`'s two `<=` guards (kept
as `<=`, not tightened to `==`, so a control that grows past its reservation in the future still
fails loudly) and its exact `recenter.height == CypressSpacing.minTapTarget` check all pass
unmodified against the corrected constants — they were already written against the bare footprints,
not the old inflated numbers. Red-proofed by temporarily adding `.padding(.top, 10)` to
`IdentifyFAB`'s body (inflating its real AX5 footprint to 93 pt, past the corrected 83 pt
reservation) and rerunning: one issue, on the intended expectation —
`Expectation failed: (fab.height → 93.0) <= (MapLayout.fabHeightAX5 → 83.0)` — restored, green
again.

Full `CypressTests`: `Test run with 1256 tests in 124 suites passed`. Full `CypressUITests`, iPhone
16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`: `** TEST SUCCEEDED **`,
`Executed 92 tests, with 0 failures`, `XCTest skipped=0`. Warnings certified on a fresh
DerivedData build-for-testing (`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`,
`source=0` warnings, `files-checked=2` (both changed files actually compiled).

**On the running screen**, AX5, `CYPRESS_LOCATION=denied` (screen 01's longest standing notice):
with the old constants the notice's visible body text ran seven lines before the card's bottom
edge; with the corrected constants the same notice, same device, same launch state, ran ten to
eleven lines before the same cutoff — more of the sentence readable without scrolling, which is the
108 pt of budget this ruling gives back. **Both figures are this ruling's change in isolation.**
Task #250's `topChromeReservedAX5(topInset:)`, below, subtracts `topInset + 157` from that same
budget — more than the 108 this ruling adds — so the *shipped* notice at AX5 scrolls sooner than it
did before either change (six lines, measured in review). The errata entry cited next carries that
arithmetic and its receipts. See
ERRATA **E248** for a discovered side
effect of the larger notice: in that same denied-location state, the recenter control (first in
`bottomChrome`'s stack, so pushed furthest by the taller notice below it) lost hittability,
occluded by the filter chip row above it — an existing, separately-documented overlap
(`MapHomeView.chrome`'s own comment on the top/bottom chrome blocks overlapping "at accessibility
sizes, where they already did") that this ruling's correction measurably worsened for this one
control, in this one state. That was not a defect in what this ruling asked for — the two constants
say what E243 measured, exactly, and are untouched by what follows.

**Task #250 fixed the reachability question, in the same PR, rather than leaving it for a separate
ticket as first planned.** `MapLayout.noticeMaxHeight` gained a second reservation
(`topChromeReservedAX5(topInset:)`) for the room the search bar and filter chip row need, so the
notice's AX5 budget stops short of where the recenter control would rise back into that chrome. The
two constants this ruling corrected (`locateButtonHeightAX5`, `.fabHeightAX5`) are unchanged by
that fix. See the errata entry above for the mechanism and the receipts.

### R67 — The one thing R41's carve-out now holds: an empty `Needs care` map says so, once (task #247)

**Owner instruction, verbatim, 2026-08-06:**

> Leave as is, but we can add a quick and light pop-up toast or the like (as long as it dismisses
> quick and doesn't pollute the map permanently) that says no trees need care.

## What this decides, and what it deliberately leaves alone

R41 is categorical — "no message ever accompanies a filter", its test being *"does text appear
because a filter did something?"* — and it names exactly one permitted form for anything judged
genuinely essential: a **single-dismiss popup**, "shown once, dismissed with one tap, never
recurring for the same cause, never persistent on the glass". R41 then judged that nothing in the
product qualified.

The owner has now judged that one state does, and has chosen a briefer form than the one R41
sanctioned: the popup dismisses itself rather than waiting for a tap. **That is the owner refining
their own ruling**, so no delegated authority is being used here and R41's carve-out is not being
read down by anyone.

**"Leave as is" is the first half of the instruction and it binds.** Task #165's settlement stands
untouched — "if nothing matches, fine", the empty map is the whole answer, and the `Clear filters`
chip is the way out. Nothing about the filter row, the chips, or the empty-map behavior changes.
E205's audit of the filter surfaces stays clean.

## The state, exactly

E244 is what made this state reachable. Until #240 the two condition chips did nothing at all to a
clustered map — the predicate was applied to the pins already fetched, and at zoom ≤ 15 there are
no pins to apply it to. E244 moved both into the `WHERE` clause, so `Needs care` now empties the
map honestly. It closed with the product question open in its own words: "whether `Needs care` is
worth a chip at all while the seed carries zero `declining` rows is a product question this task
did not answer". This is the owner's answer: keep the chip, and say the one thing the empty screen
means.

`MapNeedsCareToast.isOwed` opens on four facts and nothing else:

1. the whole `MapFilter` equals `.needsCare` — the chip on and **nothing else narrowing anything**;
2. the search bar is off;
3. the last read did not throw (`MapInventoryNotice.isOwed`'s argument, and E126's);
4. the map has **zero markers** to draw — `markerCount`, so cluster badges count, which is the
   whole of E244.

**Condition 1 is an honesty gate, not merely a scoping one.** `Needs care` beside a decade draws an
empty map for a reason nobody can attribute: a tree on this block may well need care and simply not
have been planted in the 2010s. "No trees need care" would then claim more than the query asked. The
sentence is true of exactly one query, so it is shown for exactly that query — which also means
`In bloom`, `Yours`, `Favorites`, `Year`, `Site` and the legend species all keep R41's silence,
enforced by `CypressTests/MapNeedsCareToastTests`.

## The copy

> **No trees need care**

The owner's own words with a capital and nothing added. It carries no count (R41 names a count among
the surfaces forbidden beside a filter), no "here" (that would be a claim about the ground rather
than the record — the distinction `MapInventoryCopy` spends its comment on), and no explanatory
second clause about what `declining` means or why the inventory holds none, which would be invented
prose under DECISIONS constraint 15. **Flagged for the owner's approval in the PR; it is close to
their own sentence and they hold the veto.**

## The re-arm rule, which is the half the instruction is really about

**One activation of the chip, one answer.** The gate is armed when `Needs care` is switched on, and
disarmed by the first read that *finishes* after that — with trees, with nothing, **or with an
error** — whether or not it produced a toast. Any other change to the filter, and any change to the
search, takes a toast already up off the screen.

**A press whose read failed has had its answer, and the answer was the error state.** This was
missed on the first pass and found in review of PR #46: the disarm was reached only from `fetch()`'s
success path, so a read that threw left the arm live indefinitely, and the next unrelated successful
read — a plain pan, chip untouched, screens and minutes later — collected it and posted the toast.
The sentence then answered the pan rather than the press, which is precisely the pollution this rule
exists to prevent, reached through a transient network failure instead of directly.
`noteReadFinished` is called from all three terminal paths now; `isOwed`'s `!readFailed` guard is
what stops the failed read from *also* showing something, which is "a failed read is not an empty
answer" (E126) applied to the arm as well as to the gate.

**A cancelled read is deliberately not a finished one.** Every cancellation in `fetch()` means a
newer fetch has already superseded it, so the press's answer is the read that actually lands. An
answer spends the press; being overtaken does not.

The alternative — post whenever the state holds — fires on every pan and every zoom across an empty
filtered map. That is a toast that never stops arriving, which is the permanent pollution the
instruction excludes in its own words. What is left is a toast that is the **answer to the press**:
the reader asked what needs care around here, and the map answers once. Panning afterwards is a new
question about the ground, not a second press of the chip, and the empty map is already its whole
answer (task #165).

## The form

- **Three seconds**, then it removes itself. The owner asked for "quick" and for something that
  "dismisses quick" and named no number; three seconds is the smallest commitment that satisfies
  both halves. `MapModel.defaultNeedsCareToastDuration` is the one place a later ruling changes it.
- **In the flow, immediately under the filter chips** — not an overlay over the map. It therefore
  cannot cover the chips, the legend, or anything in the bottom block at ordinary sizes, and the
  argument is `MapSuggestionList`'s one control up: an overlay leaves what it covers reachable by an
  assistive technology and invisible to everyone else.
- **It takes no touches** (`allowsHitTesting(false)`). There is nothing to press — the dismissal is
  time — so a pan that starts on those few points still pans the map.
- **Announced.** `MapHomeView` posts it as an `AccessibilityNotification.Announcement`, the same
  mechanism the recenter control and `VisitPinAdjustView`'s nudge pad use: it reports without
  stealing focus. The card also stays a real element in the tree for the reader sweeping the chrome
  inside that window.
- **Reduce Motion switches the fade off** rather than shortening it, through `cypressAnimation`.

## What it costs at AX5, stated rather than glossed

Photographed on the running app (iPhone 16e, 390 pt) at `accessibility5`: the toast is one line, it
sits under the chip row, and it draws over part of the `What tree is this?` FAB for its three
seconds. **That collision is pre-existing and this takes no new ground.** At AX5 the bottom block has
already climbed into the chip row — the recenter control sits behind the `Needs care` chip and the
FAB behind the row above it — which is the E183 §2 family, an open defect, and R53 §6 is the owner
ruling that governs that slot. The species legend chip occupies *exactly* the same band permanently
today; the toast borrows it for three seconds. Widening the fix to the bottom block's AX5 layout
would be taking a design decision this task has no standing to take (constraint 21).

## Not taken

- **No general toast mechanism.** `MapToast` has one caller and its own comment says why it must
  keep one: R41 is categorical precisely because each previous filter message "survived under a
  different mechanism". Whether any other state deserves this form is the owner's, not a
  precedent set here.
- **No tap-to-dismiss and no queue.** Neither is in the instruction and both are surface nobody
  asked for.

## What holds it

`CypressTests/MapNeedsCareToastTests` — eleven tests, six on the gate (including one that fails if
any other narrowing can open it), one on the words, four driving the real `MapModel` through the
real fetch path for the arming, the auto-dismissal, the re-arm rule, and a read that throws. Every answer comes from a fake
API, so **nothing here depends on the shipped seed's zero `declining` rows staying zero.** Section 4
of `CypressUITests/MapFilterAccessibilityTests` carries a note recording that R41's structural guard
does not drive the one narrowing that produces this, and what a fourth case added there must expect.

### R68 — Task #14's four residual design questions, decided (closes the design half of E85, E60, E119/E122)

**2026-08-06.** Four questions that were design's to answer. A design agent measured each on the
real app and the real seed and wrote them up as options with renders and computed ratios
(`docs/design-proposals/2026-08-06-task14.md`, written on the throwaway branch
`design/14-proposals` — a camera rig whose code shipped nothing, and which no longer exists. The
document itself was landed on main 2026-08-08, so this citation resolves). The project owner read
that document and answered, verbatim:

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
written up in ERRATA **E249**.

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

### R69 — The vitality rubric — three candidates, and the owner's decision

**Decision, 2026-08-07: the owner chose Candidate A.** Candidates B and C were not chosen. §0 below
records the decision and the condition on it; §§1–7 are the deliberation as it was written before the
decision and are kept unchanged, because the reasoning is what an advisor will be handed.

The original framing of this document follows. It was written before the decision and says, correctly
for its moment, that nothing in it is a decision — that is now true of §§1–7 only:

> Drafted for owner decision, following the pattern that closed E48's empty-grove copy (E239): draft
> candidates, the owner approves or redlines one, and the approved text ships verbatim. **Nothing here
> is a decision.** PRODUCT §3 calls the shipped scale "draft v0 — needs urban forestry advisor sign-off
> before launch" and DECISIONS §2.5 P-C1 calls the choice OPEN; no candidate below removes that
> requirement, and the one thing this document tries hardest to do is say which horticultural claims
> each candidate would be asking an advisor to underwrite.

---

#### 0. The decision

**On 2026-08-07 the owner chose Candidate A**: ratify the current draft as a documented collapse of
the USFS i-Tree / Nowak crown-condition classes, with the band boundaries repaired. The five sentences
in §3, Candidate A, are the approved text.

**Candidate B was not chosen.** **Candidate C was not chosen.** Their write-ups stay in §3 unchanged:
they are the record of what was weighed, and §5's list of what needs an advisor's signature is partly
built out of them.

Two things the decision does **not** do, both restated from §4 because they are conditions and not
decoration:

- It does **not** discharge PRODUCT §3's "needs urban forestry advisor sign-off before launch", and it
  does not close DECISIONS §2.5 P-C1. §5 is the list the advisor is being asked to underwrite, and
  item 1 — that five Cypress classes are a faithful collapse of the seven i-Tree / Nowak classes — is
  the one Candidate A rests on entirely.
- It does **not** move E30. The five per-class reference photographs are still the M2 entry gate and
  still do not exist. §4's second condition stands: pursue NRS-194's Figures 8 and 9 regardless.

##### The decision is gated on ticket #260

**Implementing Candidate A is blocked until #260 is resolved.** Candidate A is a repair of **PRODUCT
§3's** boundaries, and RULINGS R13 currently says `SCREENS.md`, not `PRODUCT.md`, is the wording
authority for exactly these five sentences. Landing Candidate A into `Vitality.swift` before that
conflict is settled would be writing repaired PRODUCT text into the app under a standing ruling that
says PRODUCT text is not what ships.

#260 is the investigation §6 asked for when it said "somebody who was there should say which". Its
findings are ERRATA **E258**, and the two facts that bear on this decision are:

- The two tables have disagreed since 1c469cf, because `PRODUCT.md` transcribes `SPEC-PHASE1.md` §6
  and `SCREENS.md` transcribes the `Cypress Screens.dc.html` design export, and those two handoff
  artifacts disagree. Neither distilled document is a transcription error, and neither table has
  changed since.
- R13's holding is sound but its worked example is wrong, and R13's own meaning/wording split puts the
  dieback bands on PRODUCT's side — a band is a class's operational definition, not its phrasing. The
  recommendation to the owner is therefore to correct R13's example rather than reverse the ruling,
  and to land Candidate A's sentences in **PRODUCT §3, `SCREENS.md` 05 §3 and `Vitality.swift`
  together**, closing the fork instead of adjudicating it. That is what §1 already required of
  whichever candidate won.

##### One correction to §1's arithmetic, carried over from #260

§1's first defect ("the bands own their endpoints twice") is right in substance and overstated in
detail, and §5 item 2 repeats the overstatement. Read literally, "under 10%" excludes 10 and "over
50%" excludes 50, so:

- **25 percent** is genuinely double-owned — row 3's `10 to 25%` and row 2's `25 to 50%` are both
  inclusive.
- **0 percent** is genuinely double-owned — row 5's `no visible dieback` and row 4's `under 10%`. This
  was not previously reported.
- **10 percent** belongs to row 3 alone; **50 percent** belongs to row 2 alone.

So the shipped table has one ambiguous interior boundary and one ambiguous endpoint, not three
ambiguous boundaries. **This does not change the recommendation or the repair.** Candidate A's bands —
`No dead wood visible` / `1 to 10%` / `11 to 25%` / `26 to 50%` / `Over half` — were checked against
every integer from 0 to 100 and are exhaustive and non-overlapping, which the shipped table is not.

§1's second defect (row 3's discoloration clause against the seasonality gate) was re-checked against
`Vitality.isRatingPermitted` and `Species.leafOnMonths` and holds exactly as written. One thing #260
adds: E33 records that every `seasonal` in the shipped seed is empty, so every deciduous species takes
the documented April–October fallback, which contains October — the problem is live today, not latent.

---

#### 1. What the question actually is

##### The standing record

DECISIONS §2.5 P-C1 states the stake in one sentence: **every observation collected before the rubric
exists is permanently un-normalizable.** DECISIONS §2.8 lists it as blocking Phase 1 data collection.
PRODUCT §11's open-questions list asks it as a binary — adopt USFS urban FIA crown classes wholesale,
or ship a simplified five-class derivative validated against them. `docs/ROADMAP.md`'s "Also
outstanding" section repeats that the source documents themselves flag this as the highest-value
unresolved question.

##### What ships today, read from the code rather than from the docs

`Cypress/Core/Rubric/Vitality.swift` is the whole rubric. Five cases, `severeDecline = 1` … `thriving
= 5`; `label` and `anchor` carry the copy; `rubric` carries the order, worst first. Nothing else in
the app authors a class label or an anchor sentence — `CheckInPresentation.vitalityRows` maps
`Vitality.rubric`, and `VitalityRow` has no initializer that accepts copy. The seam the ROADMAP
promised is real and I checked it: **replacing the anchor sentences is an edit to one file.**

The anchor sentences the app draws are PRODUCT §3's, verbatim:

| Level | Label | Anchor as shipped |
|---|---|---|
| 1 | Severe decline | Mostly bare in season; over 50% dieback; survival doubtful |
| 2 | Poor | Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious |
| 3 | Fair | Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable |
| 4 | Good | Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback) |
| 5 | Thriving | Full, dense canopy for the season; vigorous new growth; no visible dieback |

**Found while reading, and it needs its own correction independently of anything decided here.**
RULINGS R13 ruled that `SCREENS.md` owns the exact words under each vitality level and that "its
wording is what ships"; `PRODUCT.md` stays the authority on the rubric's *meaning*. `SCREENS.md` 05 §3
draws five different, shorter anchor lines (`Mostly bare crown, major dead limbs`; `Large dead
sections, 25–50% dieback`; `Noticeably thin, 10–25% dieback`; `Canopy mostly full, isolated dead
twigs`; `Dense canopy, vigorous new growth`). **The app ships PRODUCT's five, not SCREENS.md's five.**
R13 was recorded on 2026-07-24, three days after screen 05 was built, and the code was never brought
across; R13's own text quotes PRODUCT's level-1 sentence while ruling that SCREENS.md owns the
wording, so the ruling may itself have been written against the wrong table. Whichever candidate is
approved, the approved text has to land in **both** documents and the code, and the divergence should
be recorded as an erratum rather than quietly overwritten.

##### What replacing the placeholder touches, measured

- **Free.** The five anchor sentences. `ReadingOrderAccessibilityTests
  .testCheckInVitalityRowsReadInRubricOrder` matches rows by `hasPrefix` on the *title* only, so
  anchor phrasing is genuinely not pinned by any test. This is what the brief means by "never
  phrasing-dependent", and it holds.
- **Cheap but not free.** The five class **labels**. They exist in two places
  (`Vitality.label` and `CypressColor.Vitality.name`, the design-token gradient enum) and are
  hardcoded as five literals in `ReadingOrderAccessibilityTests`. A rename is three edits.
- **Expensive.** Renaming class 5. `StatusBadge.Kind.thriving` draws a `THRIVING` badge on screens
  01, 03, D1 and D2 whenever the latest observation is class 5, and that badge is documented in
  `SCREENS.md` §2 as one of exactly three. Renaming the top class renames a badge on the map.
- **A stop-and-report.** Changing the *number* of classes. `AppSchema`'s `observations.vitality` is
  `CHECK (vitality IS NULL OR vitality BETWEEN 1 AND 5)`, `SCREENS.md` §1.2 specifies exactly five
  reference-swatch gradients in light and dark, and `CypressColor.Vitality` has five cases. Per
  CLAUDE.md, a task that turns out to need a migration stops and reports. R13 also puts a level added
  or redefined in PRODUCT's hands, not SCREENS.md's.

##### What choosing a rubric does *not* unblock

**E30.** BUILD-PLAN §8 and DECISIONS constraint 19 make the five per-class reference photographs an M2
entry gate — the check-in screen does not ship without them. There are no such assets in the
repository; what draws today is SCREENS.md §1.2's gradient placeholder, and D3 makes color secondary
coding only, so the swatch carries none of the calibration the photograph is there to provide. **The
words were never the gate. The photographs are.** Section 4 says what I think follows from that.

##### Two defects in the shipped text that any candidate should fix

1. **The bands own their endpoints twice.** "under 10%", "10 to 25%", "25 to 50%", "over 50%": a
   rater who reads exactly 25 percent dieback has two rows that both fit, and a rater who reads
   exactly 10 percent has two more. The source these bands derive from does not do this (see §3,
   Candidate A). *(Overstated — see §0's correction. 25 percent and 0 percent are double-owned; 10 and
   50 are not. The defect and the repair stand.)*
2. **Row 3 asks about discoloration in a month when discoloration is normal.** The anchor says
   "Noticeable thinning or discoloration". `Vitality.isRatingPermitted` suppresses the section only
   for a deciduous species out of leaf, and `Species.leafOnMonths` is derived so that
   `fall_color_months` sit *inside* the leaf-on window (E33). A red maple in October is therefore
   ratable, in leaf, and noticeably discolored, and the shipped anchor points its rater at row 3. No
   candidate below keeps "discoloration" unqualified in a row that a seasonal color change satisfies.

A third, softer point: row 1 ends "survival doubtful", which is a **prognosis**, not an observation.
Screen 05 records what somebody saw. The register everywhere else in this app is to say the true thing
and stop (R12's lineage, `CheckInCopy.reviewNotice`, E239's empty grove). A volunteer predicting
whether a tree lives is a different act from a volunteer counting dead limbs, and the schema stores
one integer either way.

---

#### 2. What the seed can support — a premise refuted

The brief offers "a rubric driven by what the seed data can already distinguish" as one of three
possible approaches. **The seed can distinguish nothing about tree condition, so this is not an
available axis.** Read from `Fixtures/seed/cypress-seed.sqlite`:

- `trees` has no condition, dieback, vigor or vitality column of any kind. Its `status` CHECK admits
  five values, and the shipped file contains exactly two: 174,425 `alive` and 24,200 `vacant_site`.
  (This is the same fact that keeps screen 19 out of `ReadingOrderAccessibilityTests`.)
- The six DataSF passthrough columns are free text about legal status, caretaker and permits.
  `city_raw` is NULL on all 198,625 rows.
- The quantitative columns that do exist are not condition: `dbh_city_cm_min`/`max` on 166,984 rows
  and `planted_year` on 38,184.
- Vitality lives only in `observations`, which is the *writable* database, created empty on first
  launch. Every vitality integer that will ever exist is one a volunteer is about to produce.

So the rubric's job is not to describe data the project has. It is to **manufacture** the only
condition data this project will ever hold, which is exactly why P-C1 calls pre-rubric observations
permanently un-normalizable.

One thing the seed *can* support, and Candidate C uses it: species identity and neighbors.
`leaf_retention` is populated for 468 of 731 species, covering 157,088 of the 174,425 alive trees, and
the species screen already counts others nearby. A rubric that asks "compared with the same species
nearby" is answerable from data the app already holds.

---

#### 3. The candidates

Each is given worst-to-best, which is `Vitality.rubric`'s order and is asserted by
`ReadingOrderAccessibilityTests`.

---

##### Candidate A — ratify draft v0 as a documented collapse of the i-Tree / USFS crown-condition classes, with its boundaries repaired

**The approach.** Change as little as possible and make the existing derivation explicit and correct.
PRODUCT §3 already describes the scale as a "simplified derivative of USFS urban crown-condition
classes", and that claim checks out: the seven-class condition scale used by i-Tree Eco and published
in the urban-forestry literature by Nowak and colleagues runs excellent (<1 percent crown dieback),
good (1–10), fair (11–25), poor (26–50), critical (51–75), dying (76–99), dead (100). Draft v0 is that
scale with critical and dying merged and dead removed:

| i-Tree / Nowak class | percent dieback | Cypress row |
|---|---|---|
| excellent | under 1 | 5 · Thriving |
| good | 1–10 | 4 · Good |
| fair | 11–25 | 3 · Fair |
| poor | 26–50 | 2 · Poor |
| critical + dying | 51–99 | 1 · Severe decline |
| dead | 100 | not a vitality class — the `Appears dead` status segment |

That is a clean collapse, not an invention. What is wrong with the shipped text is the transcription:
the source's bands do not overlap and Cypress's do, and two of Cypress's sentences carry clauses the
source does not (discoloration, and a survival prognosis).

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Severe decline` | `Over half the crown is dead wood or bare in season; major limbs dead` |
| 2 | `2 · Poor` | `26 to 50% of the crown is dead wood or bare; large dead sections` |
| 3 | `3 · Fair` | `11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf` |
| 4 | `4 · Good` | `1 to 10% of the crown is dead wood; canopy otherwise full` |
| 5 | `5 · Thriving` | `No dead wood visible; canopy full for the season` |

**What it costs.**

- *Of the volunteer:* a percentage estimate of crown dieback, from the sidewalk, with no card and no
  training. This is the real price. In the source protocol the same estimate is made by two observers
  from different viewpoints against a printed density-transparency card.
- *What it can distinguish:* five levels of dead wood as a fraction of the crown, and nothing else. It
  cannot distinguish a tree that is thin from drought from a tree that is thin from pruning, cannot
  see a hollow trunk (the structure chips carry that separately), and deliberately says nothing about
  leaf color.
- *What it needs that the project does not have:* an advisor's ratification that merging critical and
  dying into one row does not destroy a distinction a city needs, and a decision on which side of 10,
  25 and 50 the boundaries fall. The five reference photographs (E30) remain missing.
- *What it commits the project to:* percent crown dieback as the measured quantity, permanently, and
  therefore to joinability with any city's own i-Tree Eco run. That joinability is the concrete cash
  value of P-C1's "normalizable".
- *Mechanically:* zero label changes, zero test changes, zero token changes, no migration. One `Core`
  file, plus the SCREENS.md/PRODUCT reconciliation §1 describes.

---

##### Candidate B — adopt USFS GTR NRS-194's crown vigor classes whole, inverted

**The approach.** Stop deriving and adopt a published federal field guide verbatim. Roman et al.
(2020), *Urban Tree Monitoring: A Field Guide*, Gen. Tech. Rep. NRS-194, USDA Forest Service Northern
Research Station, §2.11 and Table 10, defines **crown vigor** as five classes from a visual
examination of the crown, reflecting the proportion of the crown showing fine-twig dieback, foliage
discoloration and/or defoliation, plus major branch loss. Class 1 is healthy (under 10 percent
cumulative, no major branch mortality), class 2 is slightly unhealthy (10–25 percent), class 3
moderately unhealthy (26–50), class 4 severely unhealthy (over 50, foliage still present), class 5
dead. It explicitly excludes trunk condition and structural stability, and it is written for urban
forest managers, interns and **citizen scientists** — the same audience as this app.

It runs the opposite direction from Cypress, so it inverts. Inverted, its five classes fill Cypress's
five rows exactly, with no invention and no schema change.

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Dead` | `No green leaves, no live buds, no green tissue under the bark` |
| 2 | `2 · Severely unhealthy` | `Over half the crown shows dead twigs, discolored or missing leaves; some foliage still present` |
| 3 | `3 · Moderately unhealthy` | `26 to 50% of the crown shows dead twigs, discolored or missing leaves` |
| 4 | `4 · Slightly unhealthy` | `10 to 25% of the crown shows dead twigs, discolored or missing leaves` |
| 5 | `5 · Healthy` | `Under 10%; no major branch loss and no large broken branches` |

**What it costs.**

- *Of the volunteer:* the same percentage estimate as Candidate A, over a **compound** quantity —
  dieback, discoloration and defoliation added together. Harder to hold in the head, and it reopens
  the October problem: a deciduous tree in fall color is discolored by definition, and NRS-194's
  users are assumed to be running a defined monitoring season that this app does not have.
- *What it can distinguish:* the same five bands, plus a dead tree — which is the collision. Screen
  05 already has an `Appears dead` segment two sections above the rubric, and it is a different kind
  of statement: `ObservationStatus.appearsDead` opens a `review_flags` row for a community reviewer
  (E170, `CheckInCopy.reviewNotice`), while a vitality integer opens nothing. A card that asks the
  same question twice with two different consequences is a card that will get two different answers.
  E29 and DECISIONS constraint 7 exist because these two vocabularies have already been confused once.
- *What it needs that the project does not have:* an advisor's confirmation that the inversion is the
  right presentation for a volunteer app, and a resolution for the dead-row collision. It needs
  **less** botanical sourcing than any other candidate, because the sentences are a federal
  publication, and US Government works are not under copyright.
- *What it commits the project to:* NRS-194's vocabulary in the app's own voice. "Slightly unhealthy"
  and "moderately unhealthy" are clinical where Cypress is warm, and there is no room to soften them
  without ceasing to be the standard.
- *Mechanically:* all five labels change. That is `Vitality.label`, `CypressColor.Vitality.name`,
  five literals in `ReadingOrderAccessibilityTests` — **and** `StatusBadge`, because there is no
  longer a "Thriving" class for the `THRIVING` badge on screens 01, 03, D1 and D2 to key on. The badge
  is documented in `SCREENS.md` §2, so that is a stop-and-ask under DECISIONS constraint 21, not an
  edit. No migration.

**The reason to want B anyway, which is not about the words.** NRS-194 ships **per-class reference
photographs**: Figure 8 gives all five classes for young, recently planted trees; Figure 9 gives the
four live classes for mature street trees. That is the exact artifact E30 says does not exist and
DECISIONS constraint 19 makes an entry gate. Figure 9's photographs are credited to R.A. Hallett,
USDA Forest Service; Figure 8's are credited to B.S. Breger, "used with permission", which is a
permission granted to the Forest Service and not automatically to us. See §6.

---

##### Candidate C — what a volunteer can see from the sidewalk, with no percentages at all

**The approach.** Assume the percentage is the thing that goes wrong, and remove it. Anchor every row
on something a person can check by looking, without estimating a fraction: whole limbs with no leaves,
whether leaves reach the branch tips, whether this year's shoots are visible, and comparison with the
same species nearby. The last of these is the reference-tree device the ICP Forests crown-condition
manual uses for defoliation, and it is answerable from data the app already has (§2).

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Severe decline` | `More bare branches than leafy ones; whole limbs carry no leaves` |
| 2 | `2 · Poor` | `Several whole limbs are bare; wide gaps you can see sky through` |
| 3 | `3 · Fair` | `Thinner than others of the same species nearby; bare twig ends throughout` |
| 4 | `4 · Good` | `Leafy throughout; a few dead twigs at the branch tips` |
| 5 | `5 · Thriving` | `Leafy right out to the branch tips; this year's shoots easy to see` |

**What it costs.**

- *Of the volunteer:* the least of the three. No fraction, no card, no arithmetic. Row 3 asks for a
  comparison, which needs another tree of the same species in sight and is the one row that can fail
  to be answerable.
- *What it can distinguish:* honestly, fewer than five things. "More bare than leafy" and "several
  whole limbs bare" are not separated by any defined quantity, and rows 4 and 5 differ by the presence
  of new shoots, which is a shoot-extension judgment rather than a crown judgment — Bond (2010) and
  the CTLA guide both treat average shoot extension as its own parameter, not as the top of a crown
  scale.
- *What it needs that the project does not have:* **the most sourcing of the three.** Every one of
  these five sentences is a horticultural claim with no citation behind it, which is precisely what
  DECISIONS constraint 15 forbids inventing. It is also un-normalizable by construction: no mapping
  to i-Tree, to NRS-194, or to anything a city collects, which is the harm P-C1 names.
- *The evidence cuts against it.* Hallett and Hallett (2018) is the one published study of volunteers
  running exactly this protocol on exactly this population: 22 volunteers, mostly high-school
  students, two hours of training, checked against an expert on 59 living trees. Fine-twig dieback —
  the percentage — showed the *best* agreement of any variable. Crown transparency, computed from
  photographs, was the worst. That is evidence that the percentage is not the hard part, and that this
  candidate spends comparability to fix a problem smaller than it assumes.
- *Mechanically:* labels unchanged, so it is as cheap as Candidate A. One `Core` file.

---

#### 4. Recommendation

**Take Candidate A, and pursue Candidate B's photographs separately.** Reasoning, in the order that
decided it:

1. **P-C1 names the harm as un-normalizable data, and only A preserves the normalization PRODUCT
   already claims.** The scale's value to a city is that its numbers can be joined to that city's own
   i-Tree Eco run. C throws that away outright. B keeps a different normalization but pays for it with
   a dead row that collides with the Status control on the same card.
2. **The one measurement of volunteers doing this work says the percentage is not the failure mode.**
   Hallett and Hallett (2018) found best agreement on fine-twig dieback. Candidate C's whole premise
   is that the percentage is what breaks; the published evidence says otherwise.
3. **A is the only candidate with no stop-and-ask in it.** B renames a badge documented in SCREENS.md
   §2, which DECISIONS constraint 21 makes a stop-and-ask, and puts "Dead" on a card that already
   reports dead trees through a review flag. A touches one `Core` file.
4. **The words were never the gate.** E30 is the gate, and E30 is about photographs. Adopting a
   different set of sentences does not move it one inch, so the criterion for choosing between
   sentences should be "which is cheapest to be wrong about", and that is A.

Two conditions on that recommendation, and they are not decorative:

- **A is a recommendation about what to send an advisor, not a substitute for one.** PRODUCT §3 says
  draft v0 needs sign-off; §5 below lists exactly what the advisor is being asked to underwrite.
- **Go after NRS-194's Figures 8 and 9 regardless of which candidate wins.** They are published
  per-class reference photographs of urban street trees, from a federal field guide aimed at citizen
  scientists, in a five-class scale that maps onto ours by inversion. If those photographs can be
  cleared, E30's entry gate becomes a licensing question with an identified source rather than a
  photo shoot with no brief — and that is worth more to this project than any of the three sets of
  sentences above.

**Not recommended, and worth saying so explicitly: do not ship draft v0 unchanged.** The overlapping
boundaries and the October discoloration problem in §1 are defects in the current text whichever
rubric eventually wins, and both are cheap to fix now.

---

#### 5. What needs an authoritative botanical source

Named plainly, because flagging these is part of the deliverable. Each is a claim I am not qualified
to make and the project cannot presently stand behind.

1. **That five Cypress classes are a faithful collapse of the seven i-Tree / Nowak classes** — and
   specifically that merging critical (51–75 percent) and dying (76–99 percent) into one `Severe
   decline` row does not destroy a distinction a city needs. This underwrites Candidate A entirely.
2. **Where the boundaries fall.** 25 percent and 0 percent currently belong to two rows each; 10 and
   50 do not (§0's correction amends this item, which originally named 10, 25 and 50). The arithmetic
   problem is mine to point at; the fix is an advisor's to pick.
3. **Whether crown dieback alone is the right quantity, or whether discoloration and defoliation
   belong in it.** A uses dieback alone; B follows NRS-194 and adds the other two. These give
   different answers on the same tree in the same month.
4. **How seasonal leaf color interacts with the rating.** `Vitality.isRatingPermitted` gates only on
   leaf-on/leaf-off, and `fall_color_months` fall inside the leaf-on window by construction (E33). If
   the rubric mentions discoloration at all, either the gate needs a second condition or the anchor
   needs a seasonal qualifier. This is the same advisor who owes an answer on E7's invented
   April-to-October leaf-on fallback.
5. **Whether "vigorous new growth" belongs at the top of a crown scale.** It is a shoot-extension
   judgment, which Bond (2010) and the CTLA guide treat as a separate parameter. It appears in draft
   v0's row 5, in SCREENS.md 05 §3's row 5, and in Candidate C's row 5.
6. **Whether a volunteer should be asked for a prognosis at all.** "Survival doubtful" (draft v0, row
   1) is a prediction. Removing it, as all three candidates do, is itself a judgment an advisor should
   ratify rather than a copy edit.
7. **Every sentence in Candidate C.** None of them has a source. If C is chosen, all five need
   writing by somebody qualified, not redlining.

---

#### 6. What I could not resolve

- **The photograph licensing.** NRS-194 is a USDA Forest Service publication and the *text* of Table
  10 is a US Government work. The photographs are credited individually: Figure 9's four mature-street-
  tree images to R.A. Hallett, USDA Forest Service; Figure 8's five young-tree images to B.S. Breger,
  "used with permission". A permission granted to the Forest Service is not a permission granted to
  us. This needs a real answer before E30 leans on them.
- **The HTHC field guide itself.** "Tree Health Metrics: A Brief Field Guide" (R. Hallett), the
  Healthy Trees Healthy Cities protocol document, 404s at its Conservation Gateway URL. Secondary
  descriptions say its crown vigor classes are the same five as NRS-194 Table 10, which is consistent
  with Hallett being an author of both, but I could not read the guide directly and am not asserting
  it.
- **Whether an urban-forestry advisor is engaged.** PRODUCT §3, PRODUCT §11 and DECISIONS §2.5 all
  route this to one, and I have no visibility into whether that person exists yet. If they do not,
  that — not the choice between these three — is the blocking item.
- **The R13 divergence's history.** I established that the app draws PRODUCT's sentences, that
  SCREENS.md draws different ones, and that R13 says SCREENS.md's ship. I did not establish whether
  R13 was written knowing that, or whether it was written against PRODUCT's table by mistake. Somebody
  who was there should say which, because it determines whether this is a code defect or a ruling
  defect. **Answered by ticket #260** — see §0. Nobody was there; git was. The two tables came in
  disagreeing from two different handoff artifacts, R13 illustrated itself with a string that only the
  running app produces, and its holding survives while its example does not.
- **Anything requiring a build.** This is a documentation branch; nothing was compiled and no test was
  run. Every mechanical claim in §1 comes from reading `Vitality.swift`, `CheckInPresentation.swift`,
  `CheckInView.swift`, `StatusBadge.swift`, `CypressColor.swift`, `AppSchema.swift` and
  `ReadingOrderAccessibilityTests.swift`, and from querying the seed directly. The seed figures are
  from `Fixtures/seed/cypress-seed.sqlite` in this worktree and are reproducible with `sqlite3`.
- **Whether five is the right number at all.** Bond (2010) argues from Roloff that four classes suffice
  for urban work, and that finer resolution is misplaced precision — no evidence exists that tree
  health actually changes across a 5 percent dieback boundary. NRS-194 has four *live* classes.
  Cypress has five, pinned by a schema CHECK, five design tokens and a design export. Changing that
  number is a migration, and per CLAUDE.md this task stops and reports rather than proposing one. It
  is recorded here because it is a real question that an advisor may well raise, and the answer will
  cost more than any of the three candidates above.

---

#### 7. Sources

Every citation below was fetched and read for this document, not recalled.

- Roman, L.A.; van Doorn, N.S.; McPherson, E.G.; Scharenbroch, B.C.; Henning, J.G.; Östberg, J.P.A.;
  Mueller, L.S.; Koeser, A.K.; Mills, J.R.; Hallett, R.A.; Sanders, J.E.; Battles, J.J.; Boyer, D.J.;
  Fristensky, J.P.; Mincey, S.K.; Peper, P.J.; Vogt, J. 2020. *Urban tree monitoring: a field guide.*
  Gen. Tech. Rep. NRS-194. Madison, WI: USDA Forest Service, Northern Research Station. 48 p.
  Crown vigor is §2.11, Table 10, p. 28; reference photographs are Figures 8 (p. 29) and 9 (p. 30).
  <https://research.fs.usda.gov/treesearch/60818>
- Hallett, R.; Hallett, T. 2018. Citizen science and tree health assessment: how useful are the data?
  *Arboriculture & Urban Forestry* 44(6): 236–247. doi:10.48044/jauf.2018.021.
  <https://auf.isa-arbor.com/content/44/6/236>
- Bond, J. 2010. Tree condition: health. *Arborist News*, February 2010: 34–38. International Society
  of Arboriculture. Reviews CTLA and FIA, and argues for four classes in urban work.
- Schomaker, M.E.; Zarnoch, S.J.; Bechtold, W.A.; Latelle, D.J.; Burkman, W.G.; Cox, S.M. 2007.
  *Crown-condition classification: a guide to data collection and analysis.* Gen. Tech. Rep. SRS-102.
  Asheville, NC: USDA Forest Service, Southern Research Station. 78 p. This is the "USFS urban FIA
  crown classes" PRODUCT §11 names. <https://research.fs.usda.gov/treesearch/27730>
- Nowak, D.J.; Crane, D.E.; Stevens, J.C.; Hoehn, R.E.; Walton, J.T.; Bond, J. 2008. A ground-based
  method of assessing urban forest structure and ecosystem services. *Arboriculture & Urban Forestry*
  34(6): 347–358. The seven condition classes i-Tree Eco uses.
- ICP Forests. *Manual on methods and criteria for harmonized sampling, assessment, monitoring and
  analysis of the effects of air pollution on forests*, Part IV: Visual Assessment of Crown Condition.
  The reference-tree device Candidate C borrows. <https://www.icp-forests.org/>
- Healthy Trees, Healthy Cities, USDA Forest Service / The Nature Conservancy.
  <https://research.fs.usda.gov/nrs/nrs/centers/nyc/hthc>

Internal, cited by number as CLAUDE.md requires: DECISIONS §2.5 P-C1, §2.8, constraints 15, 19, 21;
PRODUCT §3, §11; SCREENS.md 05 §3 and §1.2; RULINGS R12, R13; ERRATA E7, E9, E28, E29, E30, E33, E170,
E239.

### R70 — Candidate A is the vitality rubric; the fork closes; R13's worked example is corrected

Ticket #261. The owner chose **Candidate A** from the candidates document, RULINGS **R69**, and
then ruled on the document conflict that blocked it (ticket #260, ERRATA **E258**): **close the
fork.** The five
anchor sentences below now stand identically in `docs/distilled/PRODUCT.md` §3,
`docs/distilled/SCREENS.md` 05 §3 and `Cypress/Core/Rubric/Vitality.swift`, landed in one commit, so
the two source tables and the app state one rubric.

| Level | Label | Anchor | Dieback band |
|---|---|---|---|
| 1 | `Severe decline` | `Over half the crown is dead wood or bare in season; major limbs dead` | 51–100% |
| 2 | `Poor` | `26 to 50% of the crown is dead wood or bare; large dead sections` | 26–50% |
| 3 | `Fair` | `11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf` | 11–25% |
| 4 | `Good` | `1 to 10% of the crown is dead wood; canopy otherwise full` | 1–10% |
| 5 | `Thriving` | `No dead wood visible; canopy full for the season` | 0% |

Labels, level numbers and rubric order are unchanged. The text is Candidate A's §3 table verbatim.

**A test, not a note, is what holds this.** `CypressTests/VitalityRubricTests.swift` parses the two
distilled tables out of the markdown at build time and asserts, level by level, that they and
`Vitality.anchor` state the same five sentences. A prose cross-reference asks a future reader to
notice; the test refuses to let the fork reopen at all, and names which of the three sources drifted
when one does.

#### 0. What was superseded, quoted here so it survives splicing

Both originals are reproduced verbatim below **because the two documents that carried them were
themselves unnumbered when this was written** — the candidates document and the #260 entry, now
RULINGS **R69** and ERRATA **E258** — and neither survives as a file of its own. Without this
section, the note each distilled document now carries would point at a record with no forwarding
address, which is the failure the note exists to prevent.

`docs/distilled/PRODUCT.md` §3 as it stood before this ruling, byte-identical to `SPEC-PHASE1.md` §6
(lines 174–178):

| Class | Label | Anchor (plain language) |
|---|---|---|
| 5 | Thriving | Full, dense canopy for the season; vigorous new growth; no visible dieback |
| 4 | Good | Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback) |
| 3 | Fair | Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable |
| 2 | Poor | Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious |
| 1 | Severe decline | Mostly bare in season; over 50% dieback; survival doubtful |

`docs/distilled/SCREENS.md` 05 §3 as it stood before this ruling, byte-identical to
`design_handoff_cypress/Cypress Screens.dc.html` inside the committed `Cypress.zip`, en dashes and
all:

| Level | Title | Anchor line |
|---|---|---|
| 1 | `1 · Severe decline` | `Mostly bare crown, major dead limbs` |
| 2 | `2 · Poor` | `Large dead sections, 25–50% dieback` |
| 3 | `3 · Fair` | `Noticeably thin, 10–25% dieback` |
| 4 | `4 · Good` | `Canopy mostly full, isolated dead twigs` |
| 5 | `5 · Thriving` | `Dense canopy, vigorous new growth` |

Neither table was a transcription error. Each distilled document transcribed a different handoff
artifact faithfully, and the two artifacts disagreed. A future transcription check that finds either
table above in its primary and this ruling's table in the distilled document has found the intended
state, not drift.

**Where this is deferred to:** `docs/distilled/PRODUCT.md` §3 and §11, and
`docs/distilled/SCREENS.md`'s ground rules and 05 §3 each cite this ruling for the superseded tables.
While it was unnumbered they named ticket #261 rather than a filename — CLAUDE.md forbids citing a
pending filename, and a ticket number stays resolvable either side of a splice; they now cite this
entry by number.

#### 1. R13's holding stands. R13's worked example does not, and is corrected here.

R13 ruled that `SCREENS.md` holds screen 05's anchor sentences and that "its wording is what ships",
reserving a class's *meaning* to `PRODUCT.md`. That holding is sound and is not disturbed.

R13 illustrated itself with:

> `1 · Severe decline · Mostly bare in season; over 50% dieback; survival doubtful`

**That string exists in no document and in no mock.** `1 · Severe decline` is `SCREENS.md`'s title
column; `Mostly bare in season; over 50% dieback; survival doubtful` was `PRODUCT.md` §3's anchor. It
is what `VitalityRow.title` and `VitalityRow.anchor` compose at runtime
(`CheckInPresentation.swift`) — the example was read off the running app in the belief that what the
app drew was screen 05's copy. The correction is to the example, not to the ruling.

**Replace R13's example with the composed row as it now reads:**

> `1 · Severe decline · Over half the crown is dead wood or bare in season; major limbs dead`

That string is again what the app composes, and it is now also what both source tables say, which is
the point of closing the fork: the example can no longer diverge from a document.

#### 2. Why the fork closed toward `PRODUCT.md`'s quantities rather than the export's wording

The two handoff artifacts disagreed from the day both were distilled; neither distilled document was
a transcription error. `SCREENS.md`'s export copy stated a dieback band on rows 2 and 3 and none on
rows 1, 4 and 5, so a rater holding an estimate of 5 percent or of 60 percent found no row naming a
number they could match. **A class's dieback band is its operational definition, and R13 puts
definitions in `PRODUCT.md`'s hands.** What the export owns here is the register — short, readable on
a sidewalk — not the quantity. Candidate A keeps a quantity in every row and is written in that
register.

Both documents now carry a note saying the rubric copy is this decision rather than a transcription,
because both declare themselves verbatim transcriptions of their primaries and a reader who does not
know that will re-file the ticket.

#### 3. What this ruling does NOT decide, and must not be read as deciding

- It does **not** discharge PRODUCT §3's "draft v0 — needs urban forestry advisor sign-off before
  launch", and it does **not** close `DECISIONS.md` §2.5 P-C1. A rubric was chosen; its horticulture
  was not certified.
- It does **not** move ERRATA E30. The five per-class reference photographs are still the M2 entry
  gate under DECISIONS constraint 19 and still do not exist. The words were never the gate.
- The list of claims that need an authoritative botanical source is §5 of RULINGS **R69** and is
  unchanged by this ruling. In short: that
  five Cypress classes are a faithful collapse of seven i-Tree / Nowak classes and that merging
  critical with dying loses nothing a city needs; which side of 10, 25 and 50 the boundaries fall;
  whether crown dieback alone is the quantity, or discoloration and defoliation belong in it; how
  seasonal leaf color interacts with the rating; whether "vigorous new growth" belongs at the top of a
  crown scale; and whether a volunteer should be asked for a prognosis at all. Removing "survival
  doubtful" and "vigorous new growth" from the shipped copy is itself a judgment an advisor should
  ratify rather than a copy edit.
- Pursuing NRS-194's Figures 8 and 9, and their licensing, stays open and stays worth more to E30
  than any set of sentences.

#### 4. Scope held

No label changed, so nothing reached `CypressColor.Vitality.name`, `StatusBadge.Kind.thriving` and
its two token pairs, the token and component galleries, or `SpeciesPresentation.nearbySubtitle` —
which lowercases `Vitality.label` into screen 07's `214 photos · thriving`, a verbatim `SCREENS.md`
copy string on a second screen. No token, no schema, no migration, and the number of classes is
unchanged, so `observations.vitality`'s `CHECK (… BETWEEN 1 AND 5)` and the five reference-swatch
gradients are untouched.

### R71 — The species legend's AX5 ceiling lands part-way down a chip, so a clamped legend looks clamped (owner decision, task #72)

The ceiling task #258 gave `MapSpeciesLegend` is a subtraction, and a subtraction has no opinion
about where in the chip stack its answer falls. On the phones where it binds it landed, by
arithmetic accident, exactly where a reader cannot tell that it bound: on a whole number of chips,
or a few points past one. The legend is **also the species filter** (#116), so the screen was
telling the reader "these are the species this map has colored" when the truth was "these are three
of them, scroll". The owner decided this ticket rather than leaving it. **The size of the peek was
delegated**; it is a quarter of a chip, and the argument for that number is below.

#### What the ceiling actually did, measured before anything was changed

`MapLayout.legendCeiling` is `screenHeight − topInset − 596` at AX5, and the legend it clips is four
chips of 59.67 pt with 8 pt between them — so where the ceiling lands inside that stack is decided
by two numbers nobody chose together. Swept over every screen height and top inset the app runs on
(`AX5ReflowTests.supportedScreenHeights × .supportedTopInsets`, 24 pairs), **8 of the 24 clip the
legend somewhere a reader cannot see**:

| screen | inset | ceiling | whole chips shown | of the next chip | what it looks like |
|---|---|---|---|---|---|
| 667 | 20 | 51.0 | 0 | 51.0 of 59.67 | one chip, near enough whole — 3 filters hidden |
| 844 | 47 | 201.0 | 3 | **0.0** | three chips and clean surface — 1 filter hidden |
| 844 | 54 | 194.0 | 2 | 58.67 | three chips, the third 1 pt short — 1 filter hidden |
| 844 | 62 | 186.0 | 2 | 50.67 | as above |
| 852 | 47 | 209.0 | 3 | **6.0** | a 6 pt sliver, reads as a rendering seam |
| 852 | 54 | 202.0 | 3 | **0.0** | three chips and clean surface |
| 852 | 62 | 194.0 | 2 | 58.67 | |
| 874 | 20 | 258.0 | 3 | 55.0 | |

The real pairings this bites on are the iPhone SE (667/20 → 51 pt, less than one chip) and the
iPhone 16e (844/47 → 201 pt, three whole chips and **no part of the fourth**). An iPhone 16 Pro
(874/54 → 224 pt) already shows 20.67 pt of its fourth chip, which is a third of one and legible as
cut — **the ticket's premise that 375, 390 and 402 all hide the fourth chip behind a ~6 pt sliver is
wrong on two of the three.** The 6 pt sliver is real, and it belongs to an 852 pt screen.

Rendered rather than argued: at 390 pt the before-shot is three whole capsules over clean surface,
with `Chinese Elm` — a filter the reader can tap — nowhere on the screen.

#### The rule

`MapLayout.quantizedLegendCeiling(_:isAccessibilitySize:)` moves the ceiling **down** to the nearest
height whose bottom edge falls between `legendPeek` and a chip less `legendPeek` into whichever chip
it cuts. Two claims in one number, and they are the same claim from both sides: a quarter of a chip
showing is a slice of capsule wide enough to read as a chip, and a quarter of it hidden is a cut
deep enough to read as a cut. At 0 pt of peek the reader is told the list ends; at 59 of a 59.67 pt
chip they are told the same thing.

**Down only.** Up is where `MapLocationNotice`'s floor and the identify FAB's clearance live — E248
and #258's defect, and the reason there is a ceiling at all. A rule that could raise the ceiling
would be re-opening the thing that work closed. Down costs the legend chips and gives the notice
room, and both are safe directions.

**Applied on the binding branch only**, not inside `legendCeiling`. Quantizing the raw ceiling would
move the number `legendMaxHeight` compares the legend's natural height against, and the two widest
phones — where the whole legend fits with points to spare — would acquire a `ScrollView` over the
map because a quantized ceiling happened to fall under a natural height that was never in question.
The five-phone boundary table in `theLegendCeilingBindsWhereTheArithmeticSaysItDoes` is unchanged by
this ticket, and that is deliberate.

`legendReserved` is now *derived from* `legendMaxHeight` rather than computed beside it. What the
legend occupies is the ceiling when it binds and its natural height when it does not, which is what
that function already decides; the two disagreeing by even the quantization's few points would be
the reservation under-reading the view, which is #258's defect in its original form.

#### Why a quarter of a chip, and not a half

The peek is bought with chips. The quantized ceiling is the **largest** height that satisfies the
rule, so the smaller the required peek, the more of the legend stays on the screen — and the rule
only fires when the ceiling is *outside* the band, so a generous threshold does not buy a bigger
peek where there already is one, it evicts a whole chip to make one.

Concretely: an 874 pt screen shows 20.67 pt of its fourth chip today. At a quarter-chip threshold
that is inside the band and is left alone. At a half-chip threshold it is not, and the ceiling would
drop a whole row — the reader would lose the *third* species' name in order to see more of a fourth
one they could already see. By the measure this ticket is about, which is how many of the four
filters the reader knows exist, that is a worse screen.

A quarter is the least that is legible, and the least is what a rule like this should ask for. The
renders are what settled it rather than the arithmetic: at 20.67 pt the fourth chip shows its
capsule top and the tops of its glyphs; at 45.67 pt (what the rule lands on when it fires) the
partly-shown chip's name is fully readable and only its capsule bottom is cut, which is the best
outcome available — the reader gets the name *and* the signal.

#### What it costs, on the five named phones

Measured through `MapLayout`, and the two clamped cases rendered at AX5 and looked at:

| phone | ceiling before | after | what the reader sees |
|---|---|---|---|
| iPhone SE 375 × 667 | 51.0 | **45.0** | one chip, now visibly cut instead of near-whole |
| iPhone 16e 390 × 844 | 201.0 | **181.0** | two whole chips and 45.67 pt of the third — its name readable, its capsule cut. Before: three whole chips, no fourth |
| iPhone 16 Pro 402 × 874 | 224.0 | 224.0 (unchanged) | three whole chips and 20.67 pt of the fourth |
| iPhone 16 Plus 430 × 932 | no ceiling | no ceiling | the whole legend, no scroller |
| iPhone 16 Pro Max 440 × 956 | no ceiling | no ceiling | as above |

The cost is on the 16e: one species name moves from *whole* to *cut but readable*, and in exchange
the reader learns there is a fourth filter. Every clamped chip stays pressable — the legend is still
a `ScrollView` and every chip is still a filter. `MapLocationNotice`'s budget grows by the same
points the legend gives up (they are complementary halves of one number), so nothing else on screen
01 loses anything.

#### The guard, and the shape of guard it deliberately is not

`AX5ReflowTests.theLegendCeilingAlwaysCutsAChipAtAX5` takes the ceiling from
**`MapLayout.legendMaxHeight`** — the same call `MapHomeView` makes — and the chip height and row
gap from **`MapSpeciesLegend` itself**, measured through `widestReflow` at every width in
`heightBoundWidths`. It recomputes neither. A probe carrying its own copy of the ceiling arithmetic
would keep passing at whatever the production code did, which is this repo's dominant test-suite
defect (CLAUDE.md: *could this guard pass while the defect it names is present?*).

**The doors tried**, and what closes each. Not the doors there are: this list shipped as a confident
"three ways", a reviewer opened a fourth, and a later review opened a fifth (below, still open). A
count is the one thing this list must not carry — **the completeness claim is what let the fourth
through, and it has now been wrong twice.** What follows is a record of what was tried, and the last
entry is a door known to be open.

- **Recomputing the ceiling.** Closed by reading it off `legendMaxHeight`; the red-proof below is the
  evidence, since the only difference between red and green is the production function.
- **A `nil` ceiling making every assertion vacuous.** If `legendMaxHeight` returns `nil` there is no
  clamp and nothing to cut, so the peek assertions are skipped — which would make "clamp nothing,
  ever" a way to pass. The `nil` branch therefore asserts the legend's *measured* height fits inside
  `legendCeiling`; a `nil` returned over a legend that does not fit is #258 back again and goes red.
- **The chips no longer being one per row**, which would make every row position in the test fiction.
  Asserted before anything is derived from it: a four-chip fixture must measure four chips and three
  gaps, or the test fails saying so.
- **The exemption for a screen too short to show a peek**, which was gated on the ceiling that came
  back rather than on the room the screen had — so a quantizer returning a sliver exempted itself.
  Found in review; the section below is the whole of it.
- **A `room` that under-reports, which is self-certifying** — and this one is **open**. Both bounds
  measure the ceiling against `legendCeiling`, so a `legendCeiling` that is itself wrong puts the
  same wrong number on both sides and both bounds hold. PR #63's reviewer mutated it to return
  `min(5, real)` at AX5 on `screenHeight <= 874` only, clamping the legend to a 5 pt strip on the SE,
  the 16e and the 16 Pro, and **the full unit suite stayed green.** Its first attempt, at every
  content size, *was* caught — by the boundary table's ordinary-size arm — so scoping the fault to
  AX5 is what slips past. The honest shape of the gap: **the boundary table guards the ceiling's
  nil-ness and nothing guards its magnitude.** The reviewer's proportionate fix, left here for
  whoever picks it up: extend `theLegendCeilingBindsWhereTheArithmeticSaysItDoes` from "does it bind"
  to "and by roughly how much" — the 16e's AX5 ceiling is at least two chips, say — as an anchor that
  does not recompute `MapLayout`'s own arithmetic. It is out of this ticket's scope and the
  orchestrator is filing it.

**The thresholds are looser than the production rule on purpose.** `MapLayout` reserves in bounds
(`legendChipHeightAX5` = 60, a bound on a chip that measures 59.67), so its landing drifts by up to
a point per row against the chip the view draws; the guard asserts a fifth of a chip where
production targets a quarter. A fifth of a chip is the perceptibility claim being defended.

#### Red-proof

The guard was written first and run against the unquantized tree, so its first run is the proof.
`AX5ReflowTests` at `612d8ca^`, iPhone 16 Pro Max `DE8E11AE-…`, `redproof-72.log`: **8 issues, one
per defective screen**, each naming its own screen and inset. Two of the eight verbatim:

    ✘ Expectation failed: (peek → 0.0) >= (leastVisible → 11.933333333333332)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the 201.0 pt ceiling ends 0.0 pt into the chip
      below 3 whole one(s) — a 0.0 pt sliver of a 59.66666666666666 pt chip is not a chip the reader
      can see, so 1 species filter(s) are hidden behind what looks like the end of the list (task #72)

    ✘ Expectation failed: (peek → 51.0) <= (chip - leastVisible → 47.73333333333333)
    ↳ a 667.0 pt screen with a 20.0 pt top inset: the 51.0 pt ceiling shows 0 whole chip(s) and 51.0
      pt of the next — of a 59.66666666666666 pt chip, so it reads as a complete list with 4
      filter(s) hidden under it. The ceiling has to cut a chip by at least 11.933333333333332 pt for
      the reader to see there is more (task #72); MapLayout.quantizedLegendCeiling is what moves it
      off the boundary

Both fired on the assertion they were written for and named the screen that produced them — the
failure message, not the color, is what was read. With the quantization in place the same suite is
`✔ Test run with 24 tests in 1 suite passed`, and the rest of `AX5ReflowTests` — the reservation
bound, the binding boundary, the clamp, the shortfall, the two blocks never meeting — is green
throughout both runs.

#### A door constructed here: the ceiling that is never handed out

A guard that only asserts the peek *when there is a ceiling* can be satisfied by never handing out a
ceiling — and "stop clamping the legend" is a plausible thing for a later change to do. So it was
built: `legendMaxHeight` was made to return `nil` unconditionally, and the suite run.

    ✘ a 667.0 pt screen with a 20.0 pt top inset: MapLayout.legendMaxHeight returned nil, so
      MapSpeciesLegend draws its full 262.66666666666663 pt unclamped — but the room below the chip
      row is only 51.0 pt, so it is drawing over the identify FAB again (task #258)

Red on the branch that would otherwise have been vacuous, and #258's own guards went red beside it.
The probe was reverted and the unit suite re-run on the restored tree.

#### The door the review found open (PR #63 review B1)

The doors above were the ones this branch thought to construct. The one it did not is **the one this
repo's dominant defect class predicts**: the guard's perceptibility floor was gated
`if ceiling >= chip`, which reads the *ceiling that came back* — the very thing a broken quantizer
controls. A `legendMaxHeight` patched to `min(quantizedLegendCeiling(…), 5)` draws a 5 pt strip with
no chip in it on all 24 pairs, hides all four species filters, and **passed**, because a ceiling
under one chip exempted itself from the only assertion that would have caught it.

The sweep already reached the unguarded region: a 667 pt screen at a 62 pt inset leaves 9 pt of
ceiling — under the guard's own `leastVisible` of 11.93 and under production's own `legendPeek` of
15 — and was green, silently. **That pair is synthetic, and the review's first account of it (and
this entry's) called it live.** 667 pt is the home-button iPhone SE, whose inset is 20, whose room is
51 and whose ceiling is 45 — healthy. The hole was real and reachable by the sweep; no shipping phone
was in it. The orchestrator filed task #73 on the shipping question.

**The fix is to gate the exemption on the input rather than the output.** Both bounds now read
`MapLayout.legendCeiling` — the room the screen actually had below the chip row — which no change to
the quantizer can fake:

- `peek >= min(leastVisible, room)`. A fifth of a chip wherever the screen has a fifth of a chip to
  give, and otherwise every point it does have. The quantizer only ever moves down, so "this screen
  is too short" is the one honest exemption, and it is now stated as that rather than inferred from
  the answer.
- `ceiling > room − (row + 1)`. Quantizing means landing on the nearest qualifying height *below*,
  so at most one row is what it can ever cost. Same probe from the other side, and it is what fails
  a ceiling pinned at any constant.

The reviewer proposed `rawCeiling < chip || ceiling >= chip` and invited a better one. That
assertion is red on a legitimate quantization: a raw ceiling of 65 pt is one whole chip and 5 pt of
gap — no peek at all — and the rule correctly moves it to 45, a cut first chip, which the proposal's
second arm forbids. No pair in the sweep is in that band today, so it is a latent false alarm rather
than a current one; the `min(leastVisible, room)` form closes the same hole without it, and the
row-cost assertion adds a bound the proposal does not have.

**Both red-proved, each on its own assertion.** The reviewer's own mutation, 28 issues:

    ✘ Expectation failed: (peek → 5.0) >= (min(leastVisible, room) → 11.933333333333332)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the 5.0 pt ceiling ends 5.0 pt into the chip below
      0 whole one(s) … This screen had 201.0 pt below the chip row to work with (task #72)

and a ceiling pinned at 45 — which *does* cut a chip, so the peek bounds accept it and only the
row-cost assertion fires, which is why that assertion earns its place:

    ✘ Expectation failed: (ceiling → 45.0) > (room - (row + 1) → 132.33333333333334)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the ceiling came back at 45.0 pt out of 201.0 pt of
      room — 156.0 pt given up, where quantizing to the nearest qualifying height can cost at most
      one row (67.66666666666666 pt)

**That pin does something this entry did not claim for it, and the review checked**: 45 pt is
*above* the room on the 667 pt screens, and a ceiling above the room fires
`theNoticeIsNeverGivenLessRoomThanItsOwnActionButtonNeeds` — 12 further issues, from a guard this
ticket did not write. The direction the quantizer must never move is therefore closed independently
of anything here.

#### A legend under one chip is unreported, and no guard speaks for it

Named here rather than left to a guard that cannot see it (review N1). An earlier draft of
`quantizedLegendCeiling`'s doc said a screen that short "is a `chromeBudgetShortfall` report rather
than a quantization problem". **That is false.** `chromeBudgetShortfall` asks whether the slack
covers `chipRowTop + noticeFloor`, which says nothing about the legend's share of what remains — and
`theChromeBudgetCanHouseBothOccupants` asserts it is 0 for every screen and inset the app runs on, so
by construction it never speaks for any of them. A 667 pt screen leaves 24 pt of legend at a 47 pt
inset, 17 at 54 and 9 at 62, with a shortfall of **0.0** at all three.

No shipping phone is in that region: 667 pt is the home-button iPhone SE, whose inset is 20 and whose
ceiling is 45. The sweep crosses heights with insets anyway, because a reservation correct only on
today's pairings is one device away from being wrong — which is exactly how this was found. Whether
a legend that short should exist at all is a product question this ticket does not answer; it is
**task #73**.

#### What the change costs the FAB's clearance: nothing, and structurally

An earlier draft of this branch's PR said the change "moves the top chrome further from the FAB".
**It does not, and the true property is the better one** (review N3). PR #63's reviewer measured it
on a running iPhone 16e at AX5: the legend's bottom edge moves 416 → 396 and the FAB's top edge
moves 485.33 → 465.33, so the clearance is **69.33 pt before and after**. `noticeMaxHeight` absorbs
the 20 pt the legend gives up, because the two are complementary halves of one number. The clearance
is not improved by this change; it is *preserved by construction*, which is what should be claimed
for it.

#### Verified on the merged tree

**main moved while this branch was in review** — PR #62 landed task #71, which rewrote
`Tools/run_tests.sh` and `Tools/verify_test_log.sh`, the instruments every number here was measured
with, and added `MapLayoutDefaultsAgreeTests`. The earlier revisions of this entry said "the branch
contains `origin/main`, so the branch tree **is** the merged tree", and that stopped being true the
moment #62 merged. main was merged in (clean; the two changes touch disjoint files) and everything
below was re-run on the merged tree at `head a332abc`, iPhone 16 Pro Max `DE8E11AE-…`,
`active-city=none`.

Worth its own line, because #71 changed what the harness *does* to the device: `run_tests.sh` now
parses the app's opening coordinate out of **`MapKitBasemap.swift`** — the file this ticket edits —
and refuses if that parse disagrees with `DebugLocationOverride.swift`'s. It did not refuse, and it
normalized the camera onto `37.7596,-122.4269` as designed, so this branch's edits to that file do
not disturb #71's parse. That is a fact about the merged tree that neither branch's own green could
have told anyone.

| log | what | result |
|---|---|---|
| `unit-merged-72.log` | `CypressTests`, merged tree | `✔ Test run with 1320 tests in 134 suites passed` |
| `ui-merged-72.log` | `CypressUITests`, merged tree | `Executed 99 tests, with 0 failures`, `XCTest skipped=0` |
| `warnings-merged-72.log` | **fresh** DerivedData, merged tree | `VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=448 files-checked=5` |
| `redproof-72.log` | the guard against the unquantized tree | 8 issues, one per defective screen |
| `vacuous-72.log` | the guard against an always-`nil` ceiling | red |
| `b1-probe-5pt.log` | the guard against `min(quantized…, 5)` (review B1) | 28 issues |
| `b1-probe-pinned.log` | the guard against a ceiling pinned at 45 | red on the row-cost bound only |

The pre-merge runs (`unit-r2-72.log`, `ui-r2-72.log`, `warnings-r2-72.log` at `head 068b83a`, 1318
tests in 133 suites; and round 1's at `cef0c26`) were green on the same three counts. They proved
the branch. Only the merged-tree runs above prove main — the count moves 1318 → 1320 because #71's
new suite arrives with the merge, which is the whole reason a branch's green is not a merge's.

The warnings certifier was calibrated before it was believed (E203): asked to certify a file the
build did not compile it answers `VERIFY-FAIL: cannot certify a warning count for:
NoSuchFileHere.swift — no SwiftCompile task for those files in this log`, so the count above is a
certification rather than a no-op.

#### What could not be verified here, and is worth a reviewer's device

The three phones this ticket is about are 375, 390 and 402 pt, and this agent was assigned the
iPhone 16 Pro Max (440), where **the ceiling does not bind at all**. The clamped legend was
therefore rendered rather than photographed on a running phone: `MapSpeciesLegend` at
`.accessibility5`, at each phone's own content width, hosted in a real window and drawn with
`drawHierarchy` through `ShotBlankGuard` (`ImageRenderer` was tried first and returned a blank white
image for every case, clamped or not — a control shot with no ceiling at all is what caught it).
That is the view under its real ceiling, and it is not screen 01 in the reader's hand.

### R72 — The live-layer sync API and account connectivity: scope, auth, stack, and how a photograph publishes

*Project owner, 2026-08-09, on ticket #158, ruling on the four questions
`docs/design-proposals/2026-08-09-task158-live-layer.md` put and on a fifth the spec surfaced while
answering them. The spec is the argument; this is what was decided.*

RULINGS **R36** settled which layer travels which way. This settles what gets built on top of it,
and it does not reopen R36.

---

#### 1 — The full `CypressAPI` surface becomes remote-capable; R36 still decides what travels

**Ruled: the whole protocol, not the write half.** "Full API surface" is readable two ways and the
spec refused to choose silently: **(a)** every method gains a real `RemoteAPI` implementation while
R36's routing decides what actually goes over the network, or **(b)** reads genuinely travel, which
would revise R36 and adopt shape B from `docs/investigations/api-hosting.md`.

**Reading (a) is what is built.** D16 says one database available over an API; R36 says which parts
of it travel which way; a complete protocol and a local-first routing are therefore not in tension.
(b) is not reached: R36 names its own trigger — cross-city queries outgrowing what a phone can hold —
and the app installs one city at a time.

**The acceptance criterion, in the owner's words:** *"we need to be in a spot where when I add a
photo on my device, the photo propagates to all other users."* It is a community-layer requirement
throughout, and R36 already rules the community layer live, so it is satisfied inside (a).

**What (a) costs and buys, decided with it:**

- Reads split three ways. City-layer reads stay local — the map's pan loop is a read every 200 ms and
  two performance campaigns bought it. Community and account reads go to the server. A read that
  falls back to the local answer must say that it did; an empty state is a claim, and this project
  has already drawn one over a failed read.
- `treeProfile`'s community half is **required**, not preferred: the criterion *is* somebody else's
  profile returning a photograph their device never wrote. The community delta therefore ships in
  #158 rather than in R36's later round.
- Writes keep the outbox and gain a second sink. The drain currently *is* the local commit, so
  "apply" and "send" must separate before anything is repointed at a server.

#### 2 — Sign in with Apple ships first; the email magic link is deferred to its own ticket

**Ruled: Apple first.** It is the only one of screen 15's three routes that needs no new UI — the
identity token arrives from a system framework, no field, no password, no address typed into
anything, and no third-party dependency on the client.

**The email magic link is deferred, and the reason is a fact rather than a preference:** screen 15
draws no text field, and a magic link needs an address. Supplying one means either a field on 15 —
which widens `AccountLinkRequest`, the one type in this app whose narrowness *is* the no-passwords
assertion, pinned by reflection — or a new sheet. Both are screens or states not in the mocks
(DECISIONS constraint 21), and neither should happen as a side effect of a sync-API ticket. Until
that ticket, `Use email` presents the existing "not yet" notice, which is the state ERRATA **E111**
already designed for.

**One consequence that is not optional.** Apple's account-deletion requirement means `DELETE /me`
must call Apple's revocation endpoint, which needs a token that exists only if the authorization code
was exchanged at sign-in. So the client sends the authorization code and the server stores the
refresh token. RULINGS **R3** already ships account deletion; without this it cannot keep the promise
Apple requires of it.

#### 3 — A magic link opened on a device other than the one that asked is refused

**Ruled: refuse.** Screen 15's headline is `Keep your three visits`, and the visits are on that
phone. A session minted on a laptop claims nothing and carries nothing across, while telling the
person they succeeded.

The link is bound to the requesting installation's device id and is single-use. Presented from
anywhere else the exchange returns `forbidden`, and the refusal is a **server-rendered page rather
than an app screen** — a browser is not the app, so the app cannot draw it. The requesting phone
changes no state and waits; there is no polling and no timeout to design.

**The rendezvous code was considered and declined**, priced at two new screens — a page that issues
and displays a code, and an in-app waiting state with a code field — plus a polling endpoint and a
second credential. Recorded so a later round starts from the price rather than from scratch. This
ruling binds the deferred email ticket; nothing in #158 implements it.

#### 4 — The service is written in Go, and this is a sanctioned deviation from BUILD-PLAN §3

**Ruled: Go + Postgres, one machine on `cypress-sync`.**

DECISIONS constraint 20 makes BUILD-PLAN §3's stack table binding without a written reason, and
`docs/ARCHITECTURE.md` §1 is the register of those reasons. Its backend row deviates on *not having a
backend*, not on the stack, so Fastify was the incumbent and Go owes a fifth row. The spec carries
that row for splicing; PostGIS is declined with it, because no server-side spatial query exists under
R36's local read path and carrying an extension for a query nothing makes is not continuity.

**The evidence, because the recommendation reversed on it.** The spec's first draft recommended
Fastify on the grounds that the riskiest surface in the ticket — verifying Apple's identity tokens —
had a more trodden path in Node, and it named its own tipping point: Go wins if a Go JWKS library
proves trustworthy. The survey found that `coreos/go-oidc` refetches on an unknown key id behind a
single flight (rotation with no cron) and checks algorithm, issuer, audience and expiry, with its
algorithm default already matching the only algorithm Apple signs with; that the widely-cited
alternative's advisory history lies entirely in encryption machinery this project never touches; and
that **neither ecosystem mints Apple's client secret**, so the hand-written residue is identical in
both. The delta the Fastify recommendation rested on does not exist. With auth a wash, two direct
dependencies, no runtime to patch, a static binary and a machine already deployed decide it.

**Where this ruling overrides the spec's own first recommendation, that is recorded rather than
tidied away**, and the same evidence names what would overturn it: the owner's own fluency. One
maintainer who reads TypeScript daily and Go rarely outweighs a smaller dependency tree, and that is
the single input the survey could not supply.

#### 5 — First-party photographs publish without screening at launch: a deliberate deviation

**Ruled by the owner, having been shown the cost in the same sentence, and recorded here as a
deviation rather than as a design that skips a step.**

**What the corpus asks for.** DECISIONS §4 puts nudity/person-safety screening and the face/plate
blur pipeline inside Phase 1 — they are its stated exception to what is not built — and BUILD-PLAN
§10 puts the blur at upload. **Neither exists.** Nothing in this repository raises
`Photo.blurApplied` or writes `.approved`.

**What was ruled.** A photograph from a signed-in account is approved on upload, unscreened and
unblurred, at launch. **The accepted cost:** an unscreened photograph can carry a face, a licence
plate, or the inside of somebody's front garden, and under this rule it reaches other people's
screens — the exact harm ERRATA **E147** cites as the reason a contributor may delete their own
photograph.

**First-party means the signed-in account, not the device.** The device credential is not an
attestation and a reinstall mints a new one, so a device-scoped rule gives a takedown nothing that
survives; an account carries Apple's verification and can have it withdrawn. It also makes screen
15's drawn sentence — *"An account backs them up and lets them join each tree's public timeline"* —
literally true, and leaves an anonymous contributor's photographs visible to them alone, which is
`isVisibleToItsContributor` behaving as ERRATA **E37** designed it. No screen changes.

**The way down ships with the way up.** `deletePhoto` already exists and is argued as a privacy
control in these very terms; under this rule it stops being a convenience and becomes the first line,
so it must be reachable wherever a photograph is shown. `Photo.moderationState` can move backwards
and `isPubliclyVisible` is evaluated at render time, so an operator takedown removes a photograph
from every other device at its next read with no app change, no new screen and no migration.
**Auto-approve without a takedown is the version of this rule that must not ship.**

**What does not exist, and #158 does not invent:** an in-app report-this-photograph control. No
`ReviewFlag` kind is about a photograph; adding one is a migration and the control is a screen not in
the mocks. And a photo **vote is not a report** — it feeds the hero selection, and reading a downvote
as a takedown request would let a popularity mechanism decide a safety question.

**The rule expires against the pipeline it stands in for.** The server records *why* a photograph is
approved, so "auto-approved at launch" and "screened and passed" stay distinguishable and the backlog
is re-runnable; `blur_applied = 0` is already a truthful cursor over every row in existence. When the
§4 pipeline lands it runs over that backlog and anything it fails moves to `.rejected`, which the
client already honors. **A photograph approved under this rule is not permanently exempt from the
mechanism DECISIONS §4 asks for.**

---

**One thing is named and still open**, and it is not part of this ruling: re-consent when the license
version moves. BUILD-PLAN §4 requires a text change to force it, the mechanism exists in
`User.hasAcceptedLicense(version:)`, and there is no surface to put it on — re-consent is neither the
account ask nor a setting. Named, not invented.

**No migration was authored.** #158 needs exactly one, in the writable database's counter, to let an
outbox row distinguish "applied locally" from "accepted by the server"; the spec names what it must
do and stops. The published city-file version is untouched.

### R73 — A UI test may drive screen 01's opening camera instead of inheriting it

*Pending. Cite this file as `RULINGS <this file>` until the orchestrator splices a number.*

#### The ruling

**`CYPRESS_MAP_CAMERA` in the launch environment replaces the camera screen 01 opens on, and
suppresses the write-back that would leave it on the device.** The grammar is
`DebugMapCameraOverride.parse`:

    CYPRESS_MAP_CAMERA=37.78485,-122.4215       at MapLayout.defaultSpanMeters
    CYPRESS_MAP_CAMERA=37.78485,-122.4215,300   300 m across

Anything else — one field, four fields, a word, a coordinate off the globe, a non-positive span, or
a span so wide `MapCameraMemory` would refuse to remember it — draws
`MAP CAMERA OVERRIDE FAILED · <raw> · <reason>` over the app rather than falling through, for
`DebugDeepLink.Failure`'s and R58's reason: a seam that quietly did nothing would leave a test
reading a screen drawn over whatever the last launch left, which is the state it exists to remove.

`#if DEBUG`, read from the process environment and not from `launchArguments` (which `UserDefaults`
also consumes), unreachable from the app — R58's three constraints, unchanged.

#### Why this is the same ruling as R58, one screen over

R58's argument was that **a test which detects state is cured by letting it drive the state**. It
applied that to location. The same sentence was true of the camera and nobody had said it:

- `MapOpeningCamera` remembers the camera the reader left, which is right for the product (#115) and
  means **every UI test inherits screen 01's camera from whatever ran before it** — the last test,
  the last run, or another agent's suite on a shared simulator;
- screens 09, 10 and 18 are presented *over* the map tab root rather than pushed, so screen 01's
  annotations stay in the accessibility tree behind them, and `DeepLinkHarness
  .assertEveryControlIsLabeled` walks `app.buttons`, which is every button in the app;
- `MapSpeciesLegend` draws nothing when it has colored nothing, so whether the legend is in the tree
  at all is a fact about how many trees the camera has in view.

So a test about a form's labels, and a test about AX5 chrome geometry, both had a hidden dependency
on where a map they never mention was pointed. Two CI failure families came out of it, and the
tests' own failure messages sent readers to E216 and to the harness — where there was nothing to
find, because nothing was wrong with the device.

#### How far it actually reaches, measured

**Four launch helpers pin. The rest of the suite still inherits, and still writes.** The ruling above
is a permission and a mechanism, not a property of `CypressUITests` — an earlier draft of this file
was titled as though the inheritance were gone suite-wide, and PR #66's reviewer measured that it is
not: `map.lastCamera` read off a device either side of a full UI run had *changed*, and the pinned
coordinate was never the value written.

Pinned: `DeepLinkHarness.launch`, `DeepLinkOverrideReset.run`,
`PrimaryCTAReachabilityTests.launchAtAX5`, `IdentifyFABReachabilityTests.launchAtAX5Denied`.

Not pinned, and launching screen 01 with the map in the tree: `AccessibilityTreeTests`,
`MapFilterAccessibilityTests`, `MapRecenterUITests`, `MapPanTabSwitchUITests`,
`AlmanacGroupTapTests`. Each opens on whatever the previous launch left and leaves one for the next.
`AccessibilityTreeTests.testNoUnlabeledButtonsOnLaunch` is the one worth naming, because it is where
the raise was first found: `isHittableWithoutRaising` means it no longer *fails*, but which
annotations it audits is still device state.

They were left unpinned on purpose rather than overlooked. `MapPanTabSwitchUITests` pans deliberately
and `AlmanacGroupTapTests` pins its own location fix, so pinning either without re-deriving what it
asserts could change the claim under it — and a pin applied to a class that never needed one is a
launch seam with no argument behind it, which is what the section below refuses.

#### What it deliberately does not do

**It does not put trees under the camera.** It moves the camera; the seed decides what is there.
`DebugMapCameraFixtures.westernAddition` is offered by name for that reason, and it is the *same
string* `DebugLocationFixtures.westernAddition` holds — one measured coordinate (780 trees in the
±250 m box) under two names, asserted equal by `DebugMapCameraOverrideTests`.

**`MapLayout.defaultCenter` is deliberately not offered.** The app's own fallback is Mission Dolores
Park, whose 120 × 261 m opening view contains no inventoried tree — `defaultSpanMeters`' doc comment
says so and every `CYPRESS-RUN` header stamps `viewport-trees=0` for it. It is the right place for
the app to open and the wrong place for a test that needs a pin, a species color or a legend.

**It does not replace `Tools/run_tests.sh`'s camera preflight (task #71), and the two are not the
same guarantee.** The preflight normalizes the device's stored camera once, before `xcodebuild`
starts. It cannot say anything about the camera the twentieth app launch inside a UI run inherits
from the nineteenth — and `IdentifyFABReachabilityTests` failed on exactly that gap, its first test
passing and its third failing on the same install, minutes apart. The preflight is about the device;
this is about the launch.

**It does not freeze the camera within a session.** `MapCameraMemory.sessionSnapshot` still tracks a
pan the test itself performs, so a pinned run does not quietly change what
`MapPanTabSwitchUITests` asserts about a pan surviving a tab switch (task #128).

#### The two decisions inside it that are not obvious

**A pinned run writes nothing.** `flush()` returns early. A seam that left its camera in
`map.lastCamera` would hand the *next* run — a run that pinned nothing — a remembered camera it
never chose, which is the inheritance this ruling removes rather than relocates. A test seam that
changes the state of the device it ran on is E216's and task #71's shape.

**A pinned camera is not a camera the reader left.** `hasRememberedCamera` answers `false` while
pinned, so `MapOpeningCopy.showing` produces the fallback sentence — "The map is over the middle of
the city." — rather than "The map is where you last left it." The two differ by five characters, the
location notice is the taller of them at AX5, and its height is what pushes the bottom chrome up
against the top chrome, which is precisely what `IdentifyFABReachabilityTests` measures. A pinned
launch is not a reader returning to a camera they chose; it is the state CI is actually in — a fresh
install with no history — with the camera aimed. Answering `false` keeps that class measuring the
longer sentence deterministically, where before its first test got one sentence and its third the
other, on the same install.

#### The cost, stated rather than left to be found

The app now carries a second DEBUG launch seam that changes what screen 01 shows. Both are inert
without their environment variable and both refuse loudly rather than fall through, but the surface
is bigger than it was, and a reader debugging a UI test's screen has two variables to check instead
of one. `MapOpeningCamera`'s `MapCameraMemory.shared` is the single place the pin is applied, and
the `#if DEBUG` is at that construction site rather than inside the type, so a Release build has no
branch to take.

### R74 — The copy round: screens 15, 17 and the You tab (owner rulings of 2026-08-14, corrected 2026-08-15)

*(Five rulings from 2026-08-14, each taken as an explicit choice among stated alternatives, **plus
two corrections the owner ruled on 2026-08-15** after the adversarial review of PR #88 — the
`moderation_rejected` sentence, and the rendering of where the stopped-versus-will-retry distinction
lives. Both corrections are marked in place and dated. Ruling 5 of the original round — session
restore — is **R75**. Implemented on `feat/copy-rulings`; the evidence for each, and the things the
round found that the rulings do not cover, are in ERRATA **E271**.)*

Every sentence below had gone false under the app while it was still being drawn. #158's wiring round
gave the outbox a send sink over `cypress-sync`, and #158 step 5 made `Continue with Apple` a real
exchange; between them they falsified a family of promises about where a volunteer's work lives. Each
was left standing on purpose, because copy is the owner's under DECISIONS constraint 21. These are
the answers.

**A terminally refused outbox item says `This couldn't be sent.`** Screen 17's row for an item the
service refused with a code the taxonomy says will not change — `forbidden` and its five siblings —
carries that sentence and no other. It replaces the composed `"<cause> This one will not go through
on its own."`, and it must stay distinguishable from the retryable `No connection.` state, which is a
row that is still trying. The eight per-code sentences remain for a row that is still retrying and
are no longer drawn for one the service has finished with; screen 17's footnote promise that an item
"says why" is narrowed by that, deliberately.

**`moderation_rejected` is the one exception, and it reads `This was reviewed and won't be shared.`**
*(Ruled verbatim by the owner on **2026-08-15**, narrowing the sentence above after PR #88's review
found it applied to six codes rather than one.)* The other five terminal codes — `forbidden`,
`validation_failed`, `conflict`, `not_found`, `unauthorized` — keep `This couldn't be sent.`, which
the reviewer checked sibling by sibling and found true of each. It is not true of this one: a
`moderation_rejected` item **reached the service**, the request was accepted, and a person read the
content and declined it. "This couldn't be sent." tells that volunteer their work never left the
phone, which is a false claim about where their field work is (ARCHITECTURE §5.4, DECISIONS
constraint 3 — the rule this whole round exists to enforce).

**The `stopped` state folds into the failed row, and there is no fourth drawn state.** ERRATA **E83**
invented `stopped` — the same amber C24 card as `retry`, its own mono word, and no control — because
`failed` means two different things and SCREENS.md 17 draws one treatment. The ruling reverses that
half of E83: SCREENS.md 17's "States drawn" line is `waiting`, `retry`, `synced`, and it stays three.
A refused item draws the failed row, control included. The rest of E83 stands: the taxonomy still
fails a non-retryable item immediately rather than burning 48 h of backoff on an answer that will not
change.

> **Where the distinction lives — the owner's correction of 2026-08-15, and the drafting error it
> corrects.** As first written, this ruling said *"The stopped-vs-will-retry distinction lives only
> in the outbox detail."* **There is no outbox detail.** SCREENS.md 17 draws a queue of rows, a wi-fi
> row, a synced section, a summary line and a footnote; there is no detail screen, no navigation off
> a row, and none is being built. The owner has acknowledged the phrase as a drafting error and ruled
> the rendering that replaces it:
>
> **The row's sentence is the distinction.** A terminal row reads its terminal sentence — ruling 1's,
> or the `moderation_rejected` sentence above — and a retryable row reads the retryable one. Same
> card, same furniture, same control; the words carry it.
>
> Two things follow, and both are the ruling rather than a reading of it. The retry control is *not*
> withheld from a refused row, because withholding it would put the distinction back onto the row's
> furniture. And the sentence has to **survive a retry tap** — a control that erases the only carrier
> of the distinction defeats the ruling, which is what PR #88's review found it doing (F1) and what
> the drain behind `OutboxViewState.retry(id:)` fixes.

**The You tab's account block says `Check-ins and notes sync to your grove. Photos stay on this phone
until you choose to share them.`** It replaces `AccountCopy.signedInBody`'s *"This account gathers
what you save here under one name on this device. Nothing is uploaded, and nothing about you is
public."*, whose middle clause was false in two independent ways. **One body for both arms** —
anonymous and signed-in — so the card is drawn in the signed-out arm too, which is the state the old
sentence was most wrong about and the one arm that never drew it. The claim that photographs do not
upload is true today; **the round that lands the photo sink revisits this sentence**, and the owner
said so as part of the ruling.

**Screen 15's deferred routes say `Google and email sign-in are coming later.`** It replaces
*"Accounts are not ready yet"*, which was written when no route on that screen worked and stopped
being true beside a `Continue with Apple` that signs people in. The notice's second sentence —
"Everything you have saved stays on this phone." — is §7's own promise and is untouched: the ruling
quoted the first clause and replaced that.

**Screen 15's Apple button draws the Apple logo as a vector shape.** Into the existing drawn control,
per Apple's Sign in with Apple custom-button guidelines, with the geometry taken from Apple's
published artwork rather than from memory — consistent with RULINGS **R57**, which makes every glyph
in this app a `Shape` drawn in this repository. **No SF Symbol and no
`ASAuthorizationAppleIDButton`.** The button's fill token and its label do not change.

R57 is amended by that last one only in what it now covers: the policy's own statement in
`ShareDestinationGlyph` argues in passing that Apple glyphs "would put three vendors' marks on one
row of a screen that draws its own", which was about screen 10's share row and is unaffected. Screen
15's mark is a vendor's own requirement on that vendor's own control, and it is the first drawn glyph
in the app whose geometry is not this project's to choose. What that costs is written up in the
errata entry: Apple's guidelines ask for the downloaded artwork file itself, and this is a
transcription of it.

### R75 — A surviving account session restores; a surviving device credential does not (owner ruling 5 of 2026-08-14)

*(Owner ruling 5 of 2026-08-14, implemented on `feat/session-restore`. What the round found on the
way, including the sign-out that kept the credential, is ERRATA **E272**.)*

---

#### The question

On iOS the Keychain survives app deletion. The app's SQLite database does not — it lives in the
container. So a reinstall pairs *surviving credentials* with a *fresh, empty database*, and the app
has to decide what a surviving credential means.

It was asked twice, because there are two credentials.

#### The two answers, which are opposite on purpose

**A surviving device credential reads as no credential at all** (PR #81, ERRATA **E269**). The
token is live and the service accepts it, but it
resolves to the `devices` row of an installation that no longer exists; every item the phone sends
names the new installation, and `applyOne` refuses all of them, permanently. The credential is
discarded and the installation re-registers.

**A surviving account session restores, silently.** The app boots signed in and the local account
state is rebuilt.

The recommendation on the table was to discard the session — symmetry with the device arm, and the
argument that a phone which silently resumes somebody's account after a delete-and-reinstall is
doing something the person did not ask for. The owner ruled the other way.

##### Why the two differ, stated so the next reader does not "fix" the asymmetry

A device credential is **per-installation**. It is a fact about a copy of the app, and a copy of the
app that has been deleted has no facts left; keeping it is keeping a claim about something that is
gone. An account session is **the person's**. An account is supposed to be portable — it is what
"backs up your trees" means on screen 15 — and the same Apple identity signing in again would
resolve to the same `users` row through `apple_subject` regardless. Discarding the session would
have made the person perform a sign-in whose only possible outcome is the state they were already
in.

Note also what the two arms are correcting. The device arm corrects a state that is **broken**:
every sync refused, forever, with no in-app recovery. The account arm corrects a state that is
**merely dishonest**: nothing is refused and nothing is lost, but the app draws a signed-out
installation while every request it makes goes out with the account's bearer and the service
attributes the work to that account. Different defects, different repairs.

#### What the ruling costs, and what it does not

**It costs no round trip.** "Rebuild the local account state from the server" turns out to need
almost nothing from the server. The one fact the restore requires is the account id, and the account
id is in the session itself (`SessionCredentials.userID`). The account surfaces — the grove, the
known species, favorites, map membership — are Class R reads that `RoutedAPI` already joins live on
every read, so they answer with the account's rows the moment the app knows it is signed in. The
restore is therefore synchronous, offline, and finished before the first frame, which keeps
`AppSession.bootstrap()`'s rule that a launch must not reach the network.

**It restores nothing it cannot know.** No route on this service reports an account's role, the
provider that signed it in, or the license consent it gave. None of the three is written. A role
defaults to `member` — a role is authority and the direction to fail in is the one that does not
grant it — and the provider and consent are left absent, which `AccountLinkRecord` already models
("a missing `provider` is an account claimed by something other than screen 15") and
`AccountCopy.licenseLine(for:)` already draws as no line at all. The alternative would have been the
app asserting somebody agreed to an open-database license on the strength of a reinstall.

**It needs no new drawn state** (DECISIONS constraint 21). The restored state is the ordinary
signed-in You tab, minus a line the mocks already permit to be absent.

**It needs no migration and no new `app_state` key.** The rule is stated as an equality —
`current_user_id` mirrors the Keychain session, and the session is the authority — so a launch killed
part-way through leaves a state the next launch reads and converges from. A "restore in progress"
flag would have been a third fact that could disagree with the two it was about.

#### The rule the ruling turned into, which runs in both directions

> **`app_state.current_user_id` mirrors the Keychain session. The session is the authority.**

The forward direction is the restore. The reverse direction is the refusal: when the service refuses
a surviving session — a revoked family, a deleted account, sixty days without a launch — the session
layer already discards it, and the local half has to follow, or the app draws an account with no
credential behind it. That is the same defect as the first one with the halves swapped, and the
ruling is not honored by fixing only one of them.

#### The input that is not about reinstalls at all

The rule reads three facts, not two, and the third is what an *existing* device needs. "No local
account beside a live session" describes the reinstall this ruling is about — and equally describes
every install whose owner tapped `Sign out` under the shipping build, because that sign-out cleared
`current_user_id` and left the Keychain alone. Those devices reach the rule on the first launch after
the update, with no reinstall involved, and a two-input rule signs them back into the account they
left.

`signed_out_user_id` tells the two apart: a session for the account this device recorded itself as
having left is a session that outlived a deliberate act. It is read only when the database names
nobody, which is the marker's own meaning — `LocalAPI.resumableUserID()` already guards on exactly
that.

The general shape is worth more than the instance. **A rule that infers intent from the absence of a
record has to ask what else produces that absence.** Here the answer was "a deliberate act by a
population that already exists", and the fact distinguishing them was already on disk.

#### What the ruling made mandatory elsewhere

The rule cannot ship alone, and this is the part worth carrying forward: **a restore is only as
correct as the acts that are supposed to end a session.** The You tab's sign-out forgot the Keychain
entirely — it cleared `current_user_id` and left the session standing — which was already wrong (the
bearer stayed the account's after the tap) and became load-bearing under this ruling, because the
mirror rule would have read the surviving item as authority and signed the person back in on the
next launch. A restore that resurrected deliberate sign-outs would be a worse defect than the one it
was written to close.

So signing out now forgets the session (keeping the *device* credential, so the anonymous queue goes
on draining), and deleting the account now forgets both. Neither had a caller before this round.

The general form, for whoever adds the next credential: **anything that ends an account locally must
end it in the Keychain, in the same act.** The mirror rule believes the Keychain, and it is right to.

### R76 — City data distribution: the published unit, the staged sequence, and what is deliberately left open (owner rulings of 2026-08-14)

*(Source: `docs/design-proposals/2026-08-14-city-data-distribution.md`, whose Decisions section
carries the same rulings as D1–D16 with the evidence behind each. Ruled by the owner on 2026-08-14,
each as an explicit choice among stated alternatives. Stage 0's implementation round, and the three
entries it corrects, are ERRATA **E275**.)*

**The published unit becomes a region, and a borough is the region for NYC.** Five borough packs
(54–169 MB raw at the proposal's estimates), plus a whole-NYC pack published beside them for the
reader with the disk and the patience. San Francisco and San Jose become cities with exactly one
region each — one shape everywhere, no NYC-only concept, no permanent branch in the publisher or the
Cities screen. Revisit the unit only if the real Queens number from the ingest lands materially above
~200 MB.

**Seed schema 17 is one generation with one author.** The region column and region dimension land in
the same generation as the standing-dead `kind`/`status` change the owner already ruled schema-first.
One migration round, one review; the NYC ingest targets a single settled schema. The manifest moves
`manifest_format` 1 → 2 in the same stage, and both formats publish side by side for one release
cycle — the format-1 manifest listing whole-city packs only — so unupdated installs do not lose the
catalog.

**The staged sequence is approved and Stage 0 starts now**, before the ingest picks a unit: the app
reads its own bundle's cities, content revisions and coverage by the publisher's own rule; the Cities
screen gains *included in the app* and *newer record available* row states (an amendment to R43 §3's
enumeration); the `Download` affordance disappears where it cannot keep its promise; offline rows
take their titles from `dim_city.display_name`; and `bbox`/`centroid` decoding lands in the same
change. The bundle row compares on `content_rev` alone — record-date parity, claimed as nothing more.

**The download path grows up now, not with Stage 1**: brotli on the wire inside `manifest_format` 1
(R37.4's reserved key; 4.56x measured on the published `sf` artifact), a background-identifier
`URLSession` initiated in the foreground, resume via ranged GETs, and a free-space precheck including
the `NSPrivacyAccessedAPICategoryDiskSpace` declaration it requires.

**The location-triggered offer fires from the Cities screen**, plus at most a one-time prompt after
the map is panned somewhere the attached inventory does not cover — not on launch. This supersedes
the owner's original "on open" phrasing by the owner's own ruling. The prompt's copy remains a
constraint-21 stop-and-ask when it is mocked.

**The freshness destination is deliberately open.** The owner declined to commit to either overlay
packs or R36's shape B; the choice is made after Stage 1's real download sizes are in hand, and
Stage 3's design begins by closing it rather than assuming overlays. Until then, regional packs are
the delta mechanism. The auto-refresh ticket R43 §6 deferred stays unwritten until after Stage 1.

**What does not move:** the fused seed keeps publishing with NYC out of it, so worktree and CI costs
are unchanged; the bundle stays R36's bootstrap (SF + San Jose), revisited deliberately at a natural
break rather than by drift; and the NYC notify-the-City and verbatim-disclaimer obligation is settled
before the first NYC publish — trial and beta packs included — not before the ingest.

**`CLAUDE.md`'s version-spaces bullet gains the third space, `manifest_format`**, under the same
discipline as the other two: named, its number struck from the prose, read from the code
(`Cypress/Data/Cities/CityManifest.swift` and `Tools/publish_cities.py`).

#### Addendum — four rulings taken later the same day, on the ingest's measured numbers

The `feat/nyc-ingest` extract completed after the rulings above and its measurements superseded the
proposal's estimates (Queens 175.7 MB measured — under the ~200 MB revisit line, so the borough unit
stands). Four further rulings, same day, same method:

**The s17 ruling stands with its premise corrected.** The owner chose schema-first for standing-dead
believing a new schema slot was needed; `trees.status` already carries `dead_reported` (R19), so
that work is an ingest-contract change on the Python side that may need no migration — and it still
rides the s17 round with the same author. What makes 16 → 17 a real generation is the region shape:
borough cannot ride `city_raw`, whose column family renders as `Cared for by …`, so it is a genuine
`trees.region` column plus region dimension. One round, one author, as originally intended.

**Orphan trees are assigned a borough by geometry at ingest.** The 22,995 standing trees (2.56%,
overwhelmingly the newest plantings) that join to no planting space get their borough by
point-in-polygon against the City's official borough boundaries, so the borough packs sum to the
whole city. Derived from official geometry, not invented; constraint 15 holds.

**The stale address source is used, deduped, and documented.** Forestry Planting Spaces (17 months
staler than Tree Points; 6,864 whole-row duplicates) is deduped deterministically and its own date
recorded in provenance, so the record never claims an address fresher than its source. Refresh when
the City republishes.

**The first NYC publish is gated on species coverage at 90% of rows.** Exact mappings cover 59% of
rows today; the publish — trial and beta packs included — waits until synonymy rulings take mapped
coverage to at least 90%, and the long tail lands through content-rev refreshes. The synonymy review
round is sized by this number.

### R77 — No backfill of pre-sync-path local data (owner ruling, 2026-08-15)

**Date:** 2026-08-15. **Decided by:** owner, via decision round (AskUserQuestion), option chosen: "No backfill."

#### Question put to the owner

Local data that predates the sync path cannot reach the server today:

- **Measurements and vitality check-ins** captured on builds before the outbox send sink landed
  settled locally as `done` without ever being sent; the drain selects `pending` (and manual
  retry selects `failed`), so a never-sent `done` row is never retried and nothing today can
  push it (see E264's surrounding record of the send-sink gap and its consequence that every
  pre-sink outbox row is locally applied and unsent).
- **Photos** have no send path at all, old or new — the binary reaches only the local apply
  sink (E264); a future send path is additionally blocked on the server's missing idempotency
  key for the photo-begin endpoint.

Rows captured *after* the send sink landed already sync anonymously at capture time under the
device token, and sign-in claims them server-side; those need no backfill and are not covered
by this ruling.

Options offered: (1) one opt-in backfill round after photo sync lands, covering JSON rows and
photos; (2) JSON-only backfill now, photos later; (3) no backfill.

#### Ruling

**No backfill.** Pre-sync-path local rows and pre-existing photo binaries stay on-device
permanently. Only data created going forward syncs. No opt-in backfill UI, no re-enqueue of
settled rows, no retroactive photo upload — not now and not as a later phase of the photo
send-path work.

#### Consequences

- The hard requirement on the outbox-bypassing-mutations round (task158 live-layer §3.4 scope)
  — that pre-existing local rows must never be retroactively enqueued — is **permanent policy**,
  not a provisional safety measure awaiting a backfill design.
- Any future photo send-path round (closing E264) scopes to **new photos only**. Its design
  must not sweep existing local photo rows into upload.
- Agents proposing sync-coverage improvements should not re-raise backfill; the owner has
  decided it. (Re-raising a decided item is itself a documented failure mode here.)

### R78 — NYC notify-the-City and disclaimer obligations: three rulings on how, not whether (D12; owner rulings, 2026-08-21)

**Date:** 2026-08-21. **Decided by:** owner, via decision round. Full grounding, sourcing, and
the drafts these rulings apply to are in `docs/operations/nyc-data-obligations.md`, PR #97
(`docs/nyc-tc-obligations`). D12 of
`docs/design-proposals/2026-08-14-city-data-distribution.md` already settled *that* both
obligations must be discharged before the first NYC publish, trial and beta packs included;
these three rulings settle *how*. They are numbered 1–3 within this entry and are cited as
**R78 ruling 1/2/3**, the form R72's five already use.

#### Ruling 1 — notify-the-City routing: both reachable channels, not one

**Question put to the owner.** The NYC.gov Data Mine terms require notifying "the City," via a
hyperlink on the terms page itself. That link (`nyc.gov/html/contact/contact.shtml`) is dead —
fetched 2026-08-21, it redirects to nyc.gov's generic "outdated or non-existing page." No
dedicated app-notification email or form exists anywhere reachable from NYC Open Data's current
site. Two candidates were found instead: the NYC Open Data general contact form
(`opendata.cityofnewyork.us/engage/`) and the per-dataset "Contact Dataset Owner" route on each
of the two Socrata dataset pages (routes to Parks & Recreation / DPR, the submitting agency).

**Ruling.** Use both. The same note text goes through the general contact form *and* the
per-dataset contact route on each of the two datasets (Forestry Tree Points `hn5i-inap`,
Forestry Planting Spaces `82zj-84is`) — three submissions across two distinct channels, none
treated as sufficient by itself. `opendata@cityofnewyork.us` (unverified) is not used.

**Consequence.** The draft note in `docs/operations/nyc-data-obligations.md` §3 is written to
be sent unmodified through all three; the owner sends it, this repo does not.

#### Ruling 2 — disclaimer surface: the in-app city-downloads screen, plus the listing text

**Question put to the owner.** The terms require the verbatim disclaimer "at the site where the
application can be accessed or downloaded." The repo has no existing "product page" concept —
no About/data-sources/attribution screen in the mocks (`docs/distilled/SCREENS.md`), and
CLAUDE.md constraint 21 makes adding one its own stop-and-ask.

**Ruling.** Both surfaces carry the verbatim text: (a) the in-app city-downloads screen
(`Cypress/Features/Cities/CityDownloadsView.swift` and kin — the actual surface offering an NYC
pack, whole-city or per-borough, trial packs included per D12), and (b) the TestFlight/App
Store listing, wherever the app itself is currently distributed. **This ruling is the
constraint-21 sign-off** for adding disclaimer copy to the city-downloads screen — it does not
need to be re-raised as a fresh stop-and-ask when that screen work is built.

**Consequence, binding on sequencing.** The in-app copy change is **not** part of PR #97 (a
docs-only change). It lands with the s17/NYC seed-schema and publish round (design proposal
§6.3) and must be live in that same round: that round cannot publish an NYC pack, trial or
beta, without the city-downloads-screen copy already shipped and the listing text already in
place.

#### Ruling 3 — the manifest's `attribution` array does not discharge the obligation alone

**Question put to the owner.** `Tools/publish_cities.py`'s manifest already carries a per-city
`attribution` array (`city-publishing.md`; R36 binding consequence (b)) — machine-readable
`inventory`/`name`/`url`/`snapshot_on`/`license` fields. Does that satisfy the terms' "include
the following disclaimers" requirement by itself?

**Ruling.** No. Human-visible text is required, on both surfaces named in Ruling 2 — for trial
packs exactly as for a general release. The manifest's `attribution` array remains
supplementary, structured provenance; it does not substitute for rendered, human-readable
disclaimer text.

#### Consequences that apply across all three

- Agents building the s17/NYC publish round should treat Ruling 2's sequencing as a hard
  precondition on that round's own "first NYC publish" gate, alongside D20's 90%-species-
  coverage gate — not as a separate, later ticket.
- Agents should not re-raise these three questions as open; they are decided. Any future
  question about *whether* the routes/surfaces in Rulings 1–2 are sufficient is a new question,
  not a re-litigation of these three.

### R79 — City-inventory data is disputable, and the disputes are stored app-side (owner ruling, 2026-08-21)

**Date:** 2026-08-21. **Decided by:** owner, via decision round.

#### Question put to the owner

The tree profile's flag controls ("Report the species as wrong", "Report that there is no tree
here") render only for community records. A city-inventory row is deliberately `.unavailable`:
`SpeciesClaim.swift`'s header records that the city's data sits in an ATTACHed read-only database,
and letting a contributor dispute it "would need an override table and a policy about what the
export then says, which is a larger decision than this." The owner was asked whether to add
city-row flagging to the roadmap, scope it as a near-term round, or leave city data undisputable.

#### Ruling

In the owner's words: "City data needs to be disputable via the UI. For now, we can just store it
in a separate DB, and later on we'll figure out how and whether to sync back to the city's DB."

#### Refinement, same day — the owner's spec

A second round the same day replaced the "same two flags, extended to city rows" framing.
City-tree and community-tree disputes are **not** the same surface:

**City trees.** The nature-of-issue list, offered as checkboxes (more than one may apply):

1. Pin in wrong location.
2. Wrong species.
3. Wrong other metadata — the owner's examples: a planted year that is clearly wrong, or the
   city recording a tree where the plot is actually empty.

Alongside the checkboxes: an option to enter **suggested values** for whatever is disputed, and a
free-text **notes / additional information** field.

Separately, a fourth defect class the profile screen cannot host because there is no record to
open: **a tree that IS on city property and IS NOT in the city database** — reported as a
missing-tree data defect, another instance of the same dispute machinery.

**Badges and filtering.** A tree carrying flags shows a **small badge displaying those flags**,
and the existing filters box gains a **"trees with data issues"** filter.

**Community trees.** Disputing **location and species only** — the existing species report stays,
a location dispute is added, and the city-tree metadata/suggested-values machinery does not apply.

**Addendum, same day — the community flagging view as shipped is not quality.** Two owner
reports: (1) the community-trees flagging view carries "a bunch of bad copy"; (2) a community
tree can be flagged but not unflagged by the person who flagged it, which the owner calls out as
wrong — possibly a placeholder nobody designed. (The shipped screen does have `withdraw` /
`keep` answers on an open report, gated by `canResolve`, but whatever they cover, the owner's
experience is that unflagging is not available — the gap between those two statements is itself
a design question.) The owner's instruction: the community flagging flow **goes through detailed
design before it is considered quality**. The dispute round therefore treats community flagging
as a design pass with owner decision rounds, not a copy touch-up: retractability by the flag's
author, the view's full copy (which also feeds the copy audit), and the report/withdraw/keep
state machine all get designed deliberately.

This spec is the owner's own UI direction and is the constraint-21 authority for these controls;
visual detail beyond what is written here still goes back to the owner at build time.

#### Consequences

- The "community rows only" deferral is reversed for *flagging*. The city inventory itself stays
  read-only; a dispute is a row in the app's writable database referencing the city tree, never a
  write to the attached city file.
- Whether or how disputes ever reach a city's own dataset is explicitly deferred — storing and
  showing the dispute is the scope; sync-back is a later, separate decision.
- The round that builds this needs the writable-schema migration seat after the §3.4 round's, and
  changes the tree profile's offer states so city rows stop answering `.unavailable`. The dispute
  row must carry: which issue kinds are checked, per-field suggested values, and free-text notes —
  richer than the existing boolean-shaped species/never-existed flags.
- The missing-tree defect (on city property, absent from the city DB) needs an entry point that is
  not a tree profile — likely the map. Where exactly it lives is a build-time question for the
  owner.
- Map/list rendering gains a flag badge on flagged trees and a "trees with data issues" entry in
  the filters box.
- Community trees converge on exactly two dispute modes: location and species.
- `SpeciesClaim.swift`'s header (and the parallel record-defect reasoning) must be rewritten by
  that round to cite this ruling's number once spliced.

### R80 — The beta-feedback round of 2026-08-21 (owner rulings on TestFlight tester reports)

**Date:** 2026-08-21. **Decided by:** owner, on TestFlight tester feedback.

#### Provenance of the feedback

App Store Connect pull, run **32497784558**, covering **builds 18–41**. Everything ruled below
comes from a tester's own words on a shipped build; nothing here is an agent's proposal that the
owner agreed to. The two build numbers that appear against specific defects (25, 37) are the
builds the reports were filed against, not the builds the defects were introduced in.

Six items were ruled **in scope** for the polish round and two were **deferred**. Both lists are
recorded, because a deferral is a decision and re-raising a decided item is a documented failure
mode in this project.

---

#### In scope

##### 1. The map card must never name a tree it has not read (defect, build 37)

> *"first tree tapped after app open shows 'Unidentified · 25 m N' for about a second, then
> corrects to the right species"*

**Ruled:** the bottom card on screen 01 must never show a wrong identity. A loading or placeholder
state is acceptable and so is awaiting resolution; a flash of wrong data is not.

The card is drawn synchronously from the pin so the tap feels answered, and the profile read lands
after it — that is the design and it is not what was ruled against. What was wrong is that
`MapCardSubject.title` had no value for *not knowing yet* and fell through to the literal
`"Unidentified"`, which is a claim about the species. "Still reading" and "read, and there is no
species" are now two values, and only the second says the word.

##### 2. The visit sheet paints its own ground under the keyboard (defect, build 25)

> the region behind and around the keyboard on the dark visit-logging sheet renders pure white

**Ruled:** fixed, in tokens, with no raw values (ARCHITECTURE §6). Screen 04 is dark regardless of
the system setting and the ground under the keyboard is part of that screen.

##### 3. Outbox stamps say the date once a list spans days

> synced rows read `1:49 pm` on a list whose rows are from different days

**Ruled, verbatim in effect:** *show the date instead of the time once the list spans more than one
day, otherwise the time.* It is a property of the list, not of the row: one answer for one list, so
that every stamp in it is the same kind of fact and the rows can be read against each other.

##### 4. The full-screen photo viewer gets pinch zoom

**Ruled in.** Standard pinch to zoom, pan while zoomed, and double tap to return to the whole
frame.

This **overrules the viewer's own recorded decision not to have one.** `PhotoViewerView`'s header
carried a section titled "Why there is no pinch-to-zoom", which closed: *"If somebody asks to look
closer, that is a second report and it can have its own entry."* Somebody asked. The section is
rewritten rather than deleted, and one of the three costs it named is now recorded as having been
wrong: it feared "a gesture that fights the cover's own dismiss drag", and this screen is presented
in a `fullScreenCover`, which has no interactive dismissal. That concern was `.sheet`'s.

##### 5. The capture screen gets pinch zoom

**Ruled in.** Pinch to zoom while shooting, through `AVCaptureDevice.videoZoomFactor` — the lens,
not a transform on the preview, so what is captured is what was aimed at.

The ceiling over the hardware's own is **NOT SPECIFIED** and was chosen in the implementation
(`VisitCameraController.preferredMaxZoom`); it exists so that a volunteer cannot attach an upscaled
smear to a record. If the owner wants a different number it is one constant.

##### 6a. Screen 18 offers three functions

**Ruled:** the visit-saved screen's control set is **next nearest, back to the map, back to this
tree**. This replaces `Next nearest` / `Done for today` / `See it on the tree's timeline`.

**The functions were ruled first and the copy was closed the same day** — see the addendum at the
foot of this entry. The strings shipped in this round (`VisitSavedCopy`) were the implementation's
draft; the owner chose them, so they are final.

Two of the three functions already existed under labels that named the mood of leaving rather than
the place being left for. `Done for today` called `goToMap()`, so a person who wanted the map for a
moment had to declare an end to their morning to reach it; `See it on the tree's timeline` pushes
the tree's *page*, of which the timeline is one band. The destinations have not moved.

`Route done · see your grove` is **not** a fourth control and is untouched: it is the primary CTA's
other state, for when the route is finished (PROTOTYPE-FLOW §1.6 rule 5).

##### 6b. The map gets MapKit's own compass

**Ruled:** a MapKit-native compass on screen 01, visible only when the camera is off north, tapping
it returns to north.

This **overrules the reasoning recorded at the call site**, which was that SCREENS.md 01 lists map
controls under **NOT SPECIFIED** so none should be added. What that reasoning missed is one line
below it: `isRotateEnabled = true`. A map that turns and does not say which way is north can be
left pointing somewhere the reader did not choose, with nothing on screen to undo it.

`MKMapView`'s own behavior for `showsCompass` is exactly the ruling — `MKCompassButton` fades in on
rotation, fades out at north, and its tap animates the camera back — so no glyph of ours is
involved and R57's no-SF-Symbols policy is not in question.

---

#### Deferred (decided, not forgotten)

##### Grove statistics: a date-range filter

A tester asked for a way to narrow the Grove's figures to a period. **Deferred**, not refused: it
is a real request and it is not beta-polish. It wants a design pass of its own — which figures a
range applies to, what the default range is, and what the screen says when a range contains
nothing — and none of that is drawn in SCREENS.md.

##### Coverage outside San Francisco: Marin, Sausalito, Mill Valley

Testers asked for trees in Marin County, Sausalito and Mill Valley. **Deferred, and reframed:** it
is not a defect and it is not a feature request the app can answer on its own terms. It is an
**inventory question for the distribution plan** — whether those jurisdictions publish a street
tree inventory this project may ingest, under what license, and whether a second and third city
file is what the seed/city download path should be spending its budget on next. It goes to whoever
owns the distribution plan, not to a UI round.

---

#### Consequences

- The two overrulings above (4 and 6b) are the reason this entry exists rather than a set of
  commit messages: both reversed a decision that was argued in a code comment, and a reader who
  finds the old reasoning in the history needs to be able to see that it was overruled on purpose
  and by whom.
- The copy for screen 18's two new controls was open when this entry was first written and was
  **closed the same day** — see the addendum below. It is recorded that way rather than edited out
  because two of the review round's arguments were made while it was still open.
- Nothing here authorizes a schema migration, and none was taken.

##### Two things the implementation chose, which are NOT SPECIFIED and replaceable

Recorded here so that a later reader can tell a chosen number from a ruled one, the way 5's
`preferredMaxZoom` already is.

- **The synced section's heading when its list spans days.** Ruling 3 is about the row stamps, and
  fixing them left `Synced earlier today` standing over rows stamped with two different dates —
  the app contradicting itself in its own words, which is half of what the original report was
  about. The heading now asks the same `spansDays` question the stamps do and says `Recently
  synced` when the answer is yes. The wording is the implementation's, on the same precedent §5's
  summary line already set (the mock's `this week` became `today` because a week is not a window
  this app can answer for). If the owner wants different words it is one string.
- **The compass's room on screen 01.** 6b ruled the compass in and said nothing about where it
  sits, which turned out to matter: at accessibility sizes a species legend chip covered it and
  took its taps. The legend now keeps a trailing column clear for it. That costs the legend width
  rather than height, which is why it was affordable — see `MapLayout`'s compass block.

---

#### Addendum, 2026-08-21 — the copy decision closed

The owner chose the implemented draft in a decision round: **`Back to the map`** and
**`Back to this tree`**, with `Next nearest` unchanged. Screen 18's copy is no longer open; a
later change to these strings is a new decision, not a continuation of this one.

### R81 — Every TestFlight build ships a changelog, and CI will not let a code change merge without its line (owner ruling, 2026-08-21)

**Owner ruling, 2026-08-21.** Every build uploaded to TestFlight carries a "What to Test" —
TestFlight's changelog field — compiled from **one tester-voice line per pull request**, in the
voice of somebody using the app: *"You can now pinch-zoom photos."* CI enforces it: a code change
cannot merge without its line.

Until this, builds went up through `xcrun altool` with no notes at all. `altool` cannot set that
field — it uploads a binary and knows nothing about the metadata hanging off it — so nobody had to
decide not to write one, and forty-three builds went to testers saying nothing.

---

#### The mechanism

**A note is a file, not a line in a shared file.** `docs/whats-new/<branch-or-topic>.md`, one
sentence — occasionally two or three. Blank lines and `#` comments are ignored, so a file can
carry an explanation for reviewers that testers never see. This is the pending-directory pattern
`docs/errata-pending/` already uses, for the same reason: a single `CHANGELOG.md` conflicts on
every branch that touches it, and this repository routinely has four open at once.

**"Already shipped" is read off git, and nothing writes a marker.** The release workflow already
tags the commit each build shipped from, `build-N` (#196). So:

> the notes for the build minted at `<at>` = the note files present at `<at>`, minus the note
> files present at `<since>`, minus anything git reports as a rename of one of those, where
> `<since>` is the newest `build-N` tag **strictly behind** `<at>`.

**An absent boundary is never inferred.** It legitimately means "the first build ever", and
shipping every note in the repository is then the right answer — but that is also exactly what a
**shallow clone** looks like, because `git merge-base --is-ancestor` answers a confident "no" past
a graft point rather than failing. Getting it wrong that way is worse than a duplicated changelog:
the notes ship *and* count as shipped, so the next build loses them too. So the compile refuses
whenever a build tag exists that it cannot explain having skipped — one that is neither out of
range, nor missing its commit object, nor merely sitting on the commit being built. Only a genuine
absence of reachable tags takes the first-build path.

"Strictly behind" is the whole of it, and it is not a refinement. The tag for the build being
minted is created right after the upload — so that the backstop below has something to read — and
the remediation for a job that dies in the twenty-minute processing wait is *Re-run failed jobs*.
On that second attempt "the newest tag" points at the very commit being built: the boundary
collapses, the changelog compiles to "No tester-visible changes in this build", and once that is
published the real lines sit at both tags and can never be recovered by any later compile, because
the backstop only stamps builds whose field is empty. **One false changelog would consume the
lines permanently.** Walking past any tag on `<at>` settles that, two builds from one commit, and
a tag somebody made by hand, all at once.

`Tools/whats_new.py compile` is that sentence and little else. The consequences are the
requirements rather than side effects of them:

- **No line ships twice.** A note keeps its identity across an edit (its path does not change) and
  across a rename (git reports the move, and the new path is subtracted too), so neither
  re-announces a sentence testers have read. The one gap, stated rather than left to be
  discovered: a rename that also *rewrites* the sentence falls below git's similarity threshold,
  reads as a delete plus a new file, and ships again — defensibly, since a rewritten sentence is a
  new statement. `docs/whats-new/README.md` tells authors to leave the filename alone when
  rewording.
- **A line can be withdrawn, by deleting its note before the build ships.** That is the retraction
  mechanism and the only one: the compile reads the notes *present* at the commit being built, so
  a deleted note contributes nothing. Deliberate rather than incidental, and every withdrawal is
  printed to the release log — a sentence vanishing silently would be the same class of defect as
  one appearing twice.
- **Nothing is lost to a merge that minted no build.** A prose-only merge moves no tag (`plan`'s
  ships predicate), so its notes are still unshipped and are picked up by the next real build.
  They accumulate across as many skipped merges as it takes.
- **A build's notes can be re-derived afterwards**, from `build-N` and its own boundary alone.
  That is what lets the backstop below stamp a build the release job could not reach — and what
  makes a **re-run** of a failed release job recompile the same set rather than a false empty one.
- **No bot commit to main, no state file, no token that can write a ref.** Two people running the
  compile a week apart on the same pair of revisions get the same bytes.

Ordering is newest note first; over App Store Connect's 4000-character limit the oldest lines drop
and the text ends `…and earlier improvements.` rather than simply stopping.

#### The escape hatch, and why it is not a loophole

**A line beginning `internal:` satisfies the check and is left out of the compiled notes.**

    internal: reworks the outbox retry policy; no tester-visible change.

A real code change with nothing for a tester to look at is common and honest — a workflow edit, a
refactor, a new test, this very change. The alternative to an escape hatch is not a better
changelog; it is an invented feature, which DECISIONS constraint 15 forbids and which a tester
would then go looking for.

It is not a way out of the rule. The rule is *"every code pull request states its tester-visible
effect"*; `internal:` states that the effect is none, in the diff, where a reviewer can disagree
with the judgment. A build whose every note is internal still ships a changelog — it says so in
plain words rather than going out blank.

#### Where CI refuses

`plan` in `.github/workflows/testflight.yml` runs `Tools/whats_new.py check` on every pull request
whose diff is not prose-only, and `gate` — the required status check — fails when it reports
missing. Three details are deliberate:

- **The check runs in `plan` but fails in `gate`.** Failing `plan` would skip `unit` and `ui`, and
  `gate` would then report only "plan did not succeed", burying the one sentence the author needs.
  As it is, the suite still runs and the author gets both answers in one round.
- **A note must be an ADDED file.** Editing a note another branch already wrote does not answer
  the check.
- **`gate` refuses an unrecognized value, not just a missing one.** If the check is renamed or
  crashes, `plan`'s output is the empty string — and a gate that only tested for `"missing"` would
  go green precisely when the enforcement stopped working. That is this repository's signature
  failure and it is guarded the same way `tests` is.

Prose-only pull requests need no line. They may carry one; it waits in the directory until the
next build that ships.

#### Publishing it

`Tools/appstore_connect.py set-whats-new` writes the compiled text to the build's
`betaBuildLocalizations` and then **reads it back and compares**, because a 200 that stored
something else is indistinguishable from success at the call site.

The release job compiles the notes immediately after checkout — before the archive, so a malformed
note costs ten seconds instead of forty minutes, and before the new tag exists, so the boundary
cannot collapse onto itself — and publishes them after the step that already waits for the build
to appear. **That step's existing twenty-minute bound is reused; no second wait is introduced.**

The one gap is a build that uploads and then processes slowly: the expiry step fails, the build
reaches testers anyway, and it carries no notes.
`.github/workflows/whats-new-backstop.yml` runs twice a day, finds any live build with an empty
"What to Test", and stamps it from that build's own tag. It writes nothing to the repository, and
it leaves a build alone — with a warning — in two cases rather than guessing:

- **no `build-N` tag**, so the build was not minted by this pipeline and nothing can say what is
  in it;
- **no `docs/whats-new/` at `build-N`**, so the build predates this mechanism. That case is worth
  spelling out because it is a lie rather than an error: a commit with no notes directory has an
  empty unshipped set, an empty set compiles to *"No tester-visible changes in this build"*, and
  for build 43 — which shipped the whole community-contribution sync — that sentence is false.
  Builds 1 to 43 are all of them. `whats_new.py compile` exits 8 there specifically, which is the
  one status the backstop treats as "leave it blank"; everything else is a red run.

#### Voice

American spellings (favorite, color, center, neighborhood). Plain sentences. Nothing invented, and
nothing claimed that has not been seen working — a changelog is a claim, and the standing rule
about unverified claims applies to it in full. `docs/whats-new/README.md` is what an author reads.

#### The backfill

`docs/whats-new/0043-community-contributions-sync.md` describes what build 43 shipped, so that the
first build carrying notes does not open on a changelog that skips a release. It is a backfill and
says so in its own comments: **build 43 itself had no notes and this does not pretend otherwise.**
Its lines were checked against `OutboxItem.Kind` and `server/internal/api/sync.go` rather than
against the ticket, which is where the last line — that the server records these contributions
rather than acting on them yet — comes from.

### R82 — Hero visibility follows provenance: a photograph taken on this installation is its own, whatever account holds it (owner ruling, 2026-08-22)

*(The question is ERRATA **E277**'s "Left for the owner" section — the second consumer of a
comparison `AppSchema` v16 repaired for the first. Put to the owner in a decision round on
2026-08-22 as an explicit choice between two stated options.)*

#### The question

v16 gave `photos` a provenance column, `taken_on_device`, and admitted it into the deletion gate:
a photograph this installation wrote stays this installation's to unmake even after `claimDevice`
handed it to an account and E270 made that account impossible to sign into again. That is what
repaired the stranding E277 reports.

That comparison has a second consumer and v16 did not follow it there.
`ContributionStore.heroPhotoIDs(treeIDs:attribution:)` computes its `is_own` column from the two
owner arms alone and hands the result to `TreeProfile.isPhotoVisible(_:own:)`, which is
`own ? isVisibleToItsContributor : isPubliclyVisible`. So the repaired photograph — deletable
again, still owned by an account nobody can sign into — arrives as `own: false`, is judged by
`isPubliclyVisible`, is `.pending`, and is **not drawn at all** in the species-guide nearby heroes
(07 §6). Nothing in the app can set `.approved`.

Two options were put to the owner: leave the two predicates deliberately different — deletion is
about permission, `is_own` is about attribution-for-visibility, and provenance is not attribution —
or put `is_own` on the same three-arm rule, which starts drawing photographs on a shipped screen
that are not drawn today.

#### The ruling

**Provenance counts.** A photograph taken on this installation is drawn among that installation's
own heroes whatever account owns it, on exactly the reasoning that made it deletable again. The two
predicates converge.

The standing fact underneath both is the one v16's backfill already reasoned from, and that
`LocalAPI.treeProfile` restates where it fills `ownPhotoIDs`: a row in `main.photos` was written by
this installation. Being shown your own photograph and being allowed to unmake it are the same
claim about who took it. Answering them differently is what produced a photograph the app will
delete for you and will not show you, which is not a distinction anybody was asking it to draw.

#### What this does not decide

- **`.nobody` keeps refusing.** The leaving door's promise (R3, ERRATA E157) is untouched.
  `PhotoOwner.permitsRemoval(by:takenOnDevice:)` refuses an ownerless row on its first line before
  it reads provenance, and the leaving door's statement — `AccountDeletion.anonymizeContributions`,
  the one shipping door there is — sets `taken_on_device = NULL` in the same `UPDATE` that takes the
  name off, so there is nothing left for a provenance arm to admit. `is_own` gains an arm, not an
  exception. (`LocalAPI.debugAnonymizePhoto` writes the same end state on one named row and is a
  test seam by its own header, not a second door.)
- **No schema version.** v16's column already carries what this needs. This ruling moves a
  predicate; it does not touch a table, and it must not be read as reserving a migration seat.
- **Moderation is not repealed.** `isPubliclyVisible` still governs every photograph that is not
  this installation's. What changes is which side of that fork a repaired row falls on.
- **The state E277 ends on is still unanswered.** A photograph that genuinely came from another
  installation draws with no delete control and no sentence. New copy on a shipped screen is a
  stop-and-ask (DECISIONS constraint 21) and it is not this ruling.

#### What it costs, stated rather than left to be found

Photographs begin appearing in 07 §6's nearby section that are not drawn today. On the phone E277
was reported from that is the entire point, and it is also the reason this needed the owner rather
than a refactor: it changes what a shipped screen shows. The round that builds it owes a test in
each direction — that a row carrying this device's provenance under a stranger's account is drawn,
and that an anonymized row is still not.

#### Sequencing

**Not implemented by the splice that recorded it.** A follow-up round adds the provenance arm to
`is_own` — the SQL in `ContributionStore.heroPhotoIDs`, whose doc comment and
`TreeProfile.isPhotoVisible`'s now cite this ruling as the settled answer rather than describing a
question nobody had answered.

**Built — PR #107, and this section is now history rather than a plan.** The round did not add a
fourth hand-written copy of the comparison: `heroPhotoIDs(treeIDs:attribution:)` *calls*
`ContributionStore.removalPredicate()`, the same string the three removal sites use, wrapped in
`COALESCE(…, 0)` because a SELECT column must resolve the NULL a `WHERE` can leave alone. The
convergence this ruling describes is therefore structural — one predicate, four callers — rather
than two statements kept in step by hand. The tests run in both directions the cost section asks
for, and one more pins the two rules admitting a single staged row.

### R83 — a republish advances `content_rev`; a same-day republish appends a counter

**Date:** 2026-08-24. **Decided by:** the owner. **Amends:** R37.2 as amended by R60 — the
publisher's `content_rev` contract, and nothing on the app side.

#### What went wrong

The corrective republish of 2026-08-22 went out the same day as the publish it corrected: source
seed `4f6ebaaa`, then `ac7b1ccc`. `Tools/publish_cities.py`'s `content_rev_for` derives the record
revision from the seed's **upstream inventory snapshot dates**, which is exactly what R37 asks for
and which is why they had not moved. Both publishes therefore carried `content_rev` `2026-08-22`,
and R60's `build_id` was the only part of the version string that differed.

That is fatal to update detection, because the app deliberately does **not** compare version strings
when they differ. `CityInstallState.installedIsCurrent` falls back to `content_rev` +
`schema_version` equality, and it does so for a good reason recorded in its own comment: R60's
`build_id` is a hash of the 108 MB fused seed, so re-running the publisher over a rebuilt seed
changes `version` for every city while changing no city's data, and comparing version strings would
offer every device on the catalogue an update to bytes it already holds. That fallback is correct.
What it cannot survive is two *genuinely different* publishes that agree on both fields.

With both revisions `2026-08-22` and both generations `17`, a phone holding
`s17-r2026-08-22-4f6ebaaa` is judged **current** against a live `s17-r2026-08-22-ac7b1ccc`. No
Update button is drawn, and there is no other route to the corrected data. Confirmed on the owner's
phone: Manhattan, `Installed · s17-r2026-08-22-4f6ebaaa`, no affordance, against a live
`s17-r2026-08-22-ac7b1ccc`.

#### The ruling

1. **A publish that changes a pack's data must advance that pack's `content_rev`.** It is the
   publisher's obligation, not the app's. The app's comparison is correct as written and does not
   change.

2. **Where the derived date cannot advance, a counter is appended.** The derived date is a fact
   about the upstream snapshot and cannot be moved to describe a publish; the counter is the part
   that describes the publish. `2026-08-22` → `2026-08-22.02` → `2026-08-22.03`. A bare date is the
   first publish of that record date; there is no `.01`.

3. **The identical corrected data is republished under a bumped revision**, so that devices from the
   superseded publish are offered the correction. Nothing derived from the seed can ask for this —
   the bytes are the ones already live — so it is an explicit operator action (`--republish`).

#### Two refinements this branch made, and why

**The counter is zero-padded to two digits (`.02`), where the decision's worked example wrote
`.2`.** The example's form breaks at the tenth same-day publish, and it breaks silently, in the one
comparison the app makes on this value that is not equality: `CityInstallState`'s `.bundledOutdated`
branch asks `publishedRev > bundledRev` **as a string**, on the stated grounds that "both revisions
are the ISO dates `content_rev_for` produces, where lexicographic order is date order". Un-padded,
`"2026-08-22.10" < "2026-08-22.2"`, and that sentence stops being true. Measured, not argued: with
the formatter un-padded the publisher's own suite reports the inversion by name —
`('2026-08-22.9', '2026-08-22.10')`. Zero-padded, string order and publish order are the same thing:

    "2026-08-22" < "2026-08-22.02" < … < "2026-08-22.99" < "2026-08-23"

The first inequality holds because a prefix sorts before its extension; the last because the `.` is
never reached — the day digits decide first. The hundredth same-day publish is **refused**, not
widened to three digits: `.100` would sort below `.99` and re-open the defect from the other end,
and a hundred publishes of one upstream snapshot is a runaway rather than a number to make room for.

**The counter goes only where the app compares, never where it parses.** `seed_meta.trees_snapshot_on`
keeps the bare derived date. The publisher previously wrote the revision into that key, and a
suffixed value there would break the app in two places — `InventorySource.snapshotDate` parses it
with a strict `yyyy-MM-dd` formatter and would go nil, and the seed contract in `DataGates` expects
exactly that value to be non-nil and names the key in its failure message, so **every published pack
would fail the contract gate**. The counter therefore lives in `publish_content_rev` and the
manifest's `content_rev` — the two fields `installedIsCurrent` actually reads — and nowhere else.
This separation is the whole of why the ruling's "publisher-side fix, no app change" holds. It is
also the honest reading: the upstream snapshot did not move, which is the entire reason a counter
was needed.

#### What this interacts with

- **R37.2** (`version` is the immutable path segment, write-once; only the catalogue is rewritten in
  place). A bumped revision produces a new version and therefore a new path, which is what R37.2
  provides for. The publisher now also *checks* this rather than trusting it: if the previous
  catalogue names the version this run is about to write with a different `sha256`, the run stops.
- **R60** (`build_id` appended to `version`). Unchanged. R60 made the *bytes* distinguishable in the
  path; this ruling makes the *revision* distinguishable in the field the app compares. R60 was
  necessary and was never sufficient, which is what 2026-08-22 demonstrated.
- **R43** (the Cities screen's affordances). Unchanged — no state is added or removed. A device from
  a superseded publish simply moves from `installed` to `update available`, which is what it should
  have said all along.

### R84 — City inventories become cumulative: the read layer serves the union of the bundled seed and every downloaded pack, and a bundled city is never a peer (owner rulings, 2026-08-24/25)

#### The decision

Recorded by the orchestrator, 2026-08-24, in response to App Store Connect feedback on the
downloads/cities screen. It is the owner's, not this round's, and it is not delegated design
authority for anything below it.

1. **The read layer serves the union of the bundled seed plus every downloaded city pack.** A
   reader who has downloaded Manhattan and Chicago sees both, together with everything the bundled
   seed carries.
2. **`Use` becomes add/remove of a pack from the active set**, not an exclusive switch.

##### The second half, recorded later the same day

Also the owner's, on seeing the Cities screen on a device:

> SF and SJC should not be showing Use if they ship by default — it is confusing and terrible UX
> to show what that screen shows.

3. **A city the built-in inventory covers never presents a `Use` affordance, and never appears as
   a second, parallel city entry beside the built-in card.** The bundled copy is always part of the
   union.
4. **A downloaded newer copy of a bundled city is an update to that city's data, not a peer
   inventory.** It is presented inside that city's own entry as an update state, and removing the
   downloaded copy returns the entry to the bundled record.
5. **The built-in card and any per-city entry may never contradict each other** — no `In use` above
   a sibling `Use`.

##### The state that was ruled out, confirmed against the code

The screen really does draw what the ruling describes, and it does so by a path worth naming
because the fix has to go through it. `CityInstallState.init` tests `installedVersion` **before**
it tests `bundled`, so the moment a downloaded copy of San Francisco exists the `bundled` argument
is never consulted: the row resolves to `.installedCurrent` or `.updateAvailable` and
`CityDownloadRow.decide` draws `Installed · <version>` with `Use` and `Remove` — beside a built-in
card that is simultaneously saying `Includes San Francisco and San Jose` and `In use`. The
`.bundled` and `.bundledOutdated` cases, which exist precisely to stop a bundled city being offered
as a download, are unreachable for any city that has ever been downloaded once.

#### What it supersedes

**RULINGS R43 §1 in full.** That section rules that "exactly one inventory is attached, always
under the `seed` schema name", names the choice as "the built-in inventory **or** one downloaded
city file", and records multi-city simultaneous attach as future work. The decision above reverses
each of those three sentences.

R43 §1's stated reason for the restriction is unchanged by the reversal and is the work this round
was asked to scope: attaching several files at once means union reads across N schemas, which is a
rewrite of the read layer. §§2–4 and §6 of R43 are not reversed, but three things inside them rest
on §1 and no longer stand on their own:

- **§3's affordance table.** `Use` / `In use` / `Remove` describe an exclusive switch. What a row
  offers, and what the built-in inventory's card offers, are open (see D2 below).
- **§4's active-choice mechanism.** "The active choice is a marker file (`cities/active-city`)
  holding the city id; absent means built-in" describes one id, and the set is now plural.
- **`CityInstallState.bundled` / `.bundledOutdated`.** Both are documented on the premise that "a
  downloaded copy shadows the bundled one through the existing `active-city` marker, with no new
  mechanism". Under a union there is no shadowing unless one is designed — and decision 4 above is
  that design: the shadow is per bundled city, and it is what makes a downloaded copy an update
  rather than a peer.

Decisions 3–5 additionally supersede the R43 §1-era `Use` / `In use` presentation **for bundled
cities specifically**, which is a narrower thing than decisions 1–2 supersede: R43 §1 is reversed
for downloaded packs by the union, and reversed for bundled cities by the rule that they were never
a separate choice to begin with.

#### What the code says the decision has to reckon with

Measured on this branch, 2026-08-24, against the checked-out tree and the live catalog. Nothing
here is a ruling; it is the ground the ruling has to be made on.

##### The bundle already contains both of the two packs that overlap it

`Cypress/Resources/cypress-seed.sqlite` holds **198,625** trees in two id spaces — `sf` (145,837)
and `us-ca-sj` (52,788) — and no others. The live `manifest-v2.json` (format 2, generated
2026-08-23) lists **seven** packs: `sf` (145,964), `us-ca-sj` (52,775), and the five New York
boroughs, which share the id space `us-ny-nyc` and total 898,643 trees. Total published, 1,097,382
trees in about 713 MB.

So the overlap is exact and it is not hypothetical: **the only two packs whose ground the bundle
also covers are `sf` and `us-ca-sj`**, and both are offered for download today, because the
published record date (2026-08-22) is later than the bundle's (2026-07-31) and
`CityInstallState.bundledOutdated` therefore draws the button. A literal union with no shadowing
rule draws every San Francisco tree twice.

The five borough packs never overlap the bundle, and no two packs overlap each other. **Pack-versus-
pack de-duplication is not needed; bundle-versus-pack de-duplication is.**

##### The mechanism the union would have to use

Only a `TEMP` view may reference an attached database — a view created in an attached in-memory
schema is refused outright (`view trees cannot reference objects in database inv0`). So a union
that leaves the existing SQL untouched has to live in `temp`, which means `SeedDatabase.schemaName`
becomes `temp` and every `\(seed).trees` in `Cypress/Data/Store/TreeQueries.swift` and its
neighbours keeps its text. Two sites in that file read `t.rowid`, which a view does not have; both
have an `id` that is a rowid alias in the current identity model.

Apple's system SQLite reports `SQLITE_LIMIT_ATTACHED` as **10** (3.51.0, macOS; not yet confirmed
on the simulator or a device). Bundle plus seven packs is eight, plus `main`. The cap is close
enough to today's catalog to need a stated answer (D5).

##### What it costs, measured

The whole-of-San-Francisco cluster query at 64 pt cells — the query
`SpatialIndexStrategy.default`'s own table was measured on, run the same way (sqlite3 CLI, macOS,
warm). The packs here are **synthetic**: the bundled seed narrowed by id space and vacuumed, not
the published files, which were not downloaded.

| arrangement | time | plan |
|---|---|---|
| the bundle alone, straight at the table | 59–61 ms | `SEARCH t USING COVERING INDEX idx_trees_lat_lon` |
| one arm, through a temp view | 60–61 ms | covering index kept |
| two arms, the second outside the viewport | 69 ms | covering index kept, both arms |
| eight arms, six outside the viewport | 158–165 ms | — |
| bundle + `sf` pack, no de-duplication | 157–170 ms | covering index kept; every cell counts double |
| de-duplicated by `id_space NOT IN ('sf')` on the bundle arm | 164 ms | index used, not covering |
| de-duplicated by `NOT EXISTS (… p.uuid = b.uuid)` | 289 ms | — |
| de-duplicated by rowid range on the bundle arm | 75–85 ms | covering index kept, both arms |

Four things follow, and the last one is the one that matters:

1. **A temp view costs nothing by itself.** One arm through a view is the bare table's time.
2. **Arms outside the viewport are nearly free.** Eight attached inventories cost what two do when
   six of them hold no row the camera can see, because the latitude range prunes them at the index.
   The read scales with rows in view, not with inventories attached — which is the opposite of what
   R43 §1 assumed, and it is why this is worth attempting at all.
3. **Duplication, not the union, is what costs.** The 157–170 ms row is the 59 ms row with twice
   the trees under the camera.
4. **How the duplicate rows are excluded decides whether this is affordable.** Rejecting them on
   `id_space` costs a table probe per rejected row and gives all the savings back. Rejecting them
   on `uuid` costs 4.8× the baseline. Rejecting them on a rowid range is answered from
   `idx_trees_lat_lon` itself, which carries `id`, so the covering index survives and the whole
   union lands at 75–85 ms against a 59–61 ms floor.

   The bundle's id ranges are in fact contiguous per id space today (`sf` is 1–145,837,
   `us-ca-sj` is 145,838–198,625, with no row of either space inside the other's range). **That is
   a property of one build of one file, not a contract** — `Tools/build_seed.py` promises nothing
   about it. It is measurable at open and checkable (a range is contiguous when its count equals
   its span), so it can be used where it holds and fallen back on where it does not; it must not
   be assumed.

The R\*Tree strategy also survives the union — the box constraints still reach the virtual table
through the view — but joining two compound views expands to N² arms in the plan. It is not the
default strategy and is not on the path a thumb drags.

##### Species are the identity problem the geometry is not

`trees.uuid` and `species.uuid` are `uuid5` of a source id and of a scientific name respectively,
so both are stable across builds and both are usable as cross-file keys. `trees.id` and
`species.id` are integers local to their file. Geometry can be re-keyed with a per-file offset;
`species.id` cannot be, because `trees.species_current` in one file must resolve to the *same*
species row as `species_current` in another, or the species list shows 731 species per attached
inventory and every group-by splits. Which file's catalog is canonical, and whether the
translation happens inside the view or at the query boundary, is D6.

#### Proposed: what the Cities screen becomes

Written under R43 §3's delegated-authority pattern, which is how that ruling's own affordance
table was produced: the screen has no mock, so the ruling is the mock. **These are proposals for
ratification, not decisions.** Anything the decisions above do not determine is in the list below
rather than settled here.

**One card per thing the reader can act on, and a bundled city is not one of them.**

- **The built-in card** keeps its title and its `Includes …` line and **draws no affordance at
  all** — not `Use`, not `In use`, not `Remove`. It cannot be switched off, so a control that
  says otherwise is the contradiction decision 5 forbids. `Ships with the app and cannot be
  removed` already says the operative fact and needs no button under it.
- **A bundled city gets one entry, nested under the built-in card**, in the `isCityGroup` idiom
  `CityDownloadSection` already draws for a city's packs. Never a peer card in `On this phone`,
  which is decision 3. (*"Nested under"* turned out to name more than one arrangement, and the
  `isCityGroup` idiom was the wrong one. The owner settled it on 2026-08-25 as containment inside
  the built-in card — see the ratified section below. This bullet is left as it was proposed.)
  Its state line is one of three:
  - `Included in the app · record as of <rev>` — the bundle's own copy is what the map draws;
  - `Included in the app · record as of <rev>` with `A newer record is available.` beneath and one
    `Update` button — the catalog is ahead, and the verb is `Update` rather than `Download`
    because decision 4 makes it one;
  - `Updated · record as of <rev>` with `Revert to the included copy` — a downloaded copy has
    replaced the bundled rows for this city.
- **`Remove` is not the word for undoing that update.** It reads as removing the city, and the
  city cannot be removed; what is removed is the newer copy, and the entry returns to the bundled
  record. That is decision 4's second clause and it needs its own verb.
- **A pack the bundle does not cover** — the five New York boroughs today — keeps its own card and
  loses `Use` and `In use` along with everything else. See D9: if downloaded means in the union,
  the only verbs the screen needs anywhere are `Download`, `Update`, `Remove` and `Cancel`, and
  `Use` leaves the vocabulary entirely.

#### Ratified by the owner, 2026-08-24/25

Recorded by the orchestrator from the owner's own window. Each of these was open in the list
below when this ruling was written; each is now settled, and the implementation is built on them.
Two items carry a later date than the rest and say so where they sit: D2 was **re-ruled** on
2026-08-25 after the first implementation of it drew nothing, and the copy for a refused file was
ratified the same day.

- **D9 — downloaded IS the active set.** A downloaded city is in the union; there is no separate
  active toggle. The screen's vocabulary is `Download`, `Update`, `Remove` and `Cancel`; `Use`
  and `In use` leave it entirely. The `active-city` marker is retired (`CityLibrary`), and a
  device carrying one from an older build has it deleted on the next launch.
- **D1 — shadowing at whole-city / id-space granularity.** A downloaded copy of a bundled city
  shadows every bundled row of that id space. **Bundle only**: a pack never shadows another pack,
  because the five New York boroughs share the id space `us-ny-nyc` and an id-space rule applied
  between packs would delete Brooklyn the moment Manhattan was installed.
- **D2 — the proposed screen, as proposed.** The built-in card draws no affordance at all;
  bundled cities belong to it rather than beside it, with the three state lines exactly as
  written; non-bundled packs keep their own cards. The copy lands verbatim.

  **Re-ruled 2026-08-25: the bundled cities are drawn *inside* the built-in card.** Recorded by
  the orchestrator from the owner's own window, after the first implementation was shown on a
  device. *"Nested under it"* had been read as a sibling group drawn one step quieter — the
  `isCityGroup` idiom — and that resolved to no drawn difference at all, because the flag reached
  the view through a single padding modifier sitting inside `if !section.title.isEmpty` and that
  group's title is empty by construction. `Built-in inventory`, `San Francisco` and `San Jose`
  came out as three cards of identical width and inset, which is the arrangement decision 3
  forbids.

  The ruling is containment, literally. **One card**: the built-in header, and each bundled
  city's entry within that card's own boundary. **Existing chrome only** — the card's rounded
  rectangle and border, a `borderCool` hairline between entries, tokens throughout; no new
  component, no new drawn geometry, nothing that would be a constraint-21 stop-and-ask. A bundled
  city is never drawn outside that card, and a pack the bundle does not cover is never drawn
  inside it. This holds in every row state, including the one that carries a full-width control
  (`Revert to the included copy`) and the one where the downloaded copy could not be read.

  Whether one rectangle encloses another is not a property of a value, so it is pinned on the
  device (`CityCardContainmentUITests`) rather than only in the presentation model — the earlier
  guard asserted the arrangement as data and stayed green while the screen drew peers.
- **D5 — the installed set is capped, with honest copy.** Headroom is checked at open against the
  platform's actual attach limit (`SQLITE_LIMIT_ATTACHED`, read off the live connection — never
  hard-coded), and at the cap the `Download` button is replaced by `Remove a city to download
  another.` An *update* is never withheld: it reuses the slot that city already holds.
- **D3 — the opening camera.** A location fix inside any live inventory wins; failing that, the
  camera this install was last left on; failing that, the largest downloaded inventory. With
  nothing downloaded it degrades to today's behavior exactly.
- **D4 — per-city aggregates stay per-city.** The Journal's `City` segment and the almanac keep
  resolving an id space from the nearest tree. No cross-inventory aggregate is opened.
- **D10 — `content_rev` in copy.** The rendered sentence strips any publisher counter suffix (a
  bare date), and **every comparison keeps the full opaque string**. The live catalog has
  carried revisions like `2026-08-22.02` on all seven packs since the republish of 2026-08-25, so
  both halves are exercised against the shipping shape rather than a fixture.
- **The copy for a file the read layer refused — ratified as shipped, 2026-08-25.** Recorded by
  the orchestrator from the owner's own window. Containment (above) is what makes a refused pack
  visible at all, and the screen state it produces is not in the mocks (DECISIONS constraint 21),
  so the two sentences the implementation had to write were put to the owner and are ruled
  verbatim, as written:

  - state line — `Couldn't be read`, drawn in the attention color the screen already gives a
    failed row (`isFailure`, `CypressColor.signalAmber`);
  - detail line — `The downloaded file couldn't be opened, so its trees are not on the map.`

  **No new affordance goes with them.** The sentence states the fact and the button already on
  the row states the remedy: `Revert to the included copy` for a bundled city whose downloaded
  copy failed, `Remove` for a pack the bundle does not carry. Either one clears the file and the
  state with it. That division is why the copy names neither verb — a sentence naming one of them
  would be wrong on the other row.

#### Proposed by this round, for the orchestrator to adjudicate

D6, D7 and D8 were delegated to the implementation. What follows is what was built and why.

##### D6 — the canonical species catalog

**Chosen: one canonical catalog, materialized at open into `temp.species`, keyed by
`species.uuid`, with a per-arm translation table mapping that arm's local `species_current` onto
it.** Every existing `JOIN species s ON s.id = t.species_current` and `GROUP BY s.id` keeps
working unchanged.

The premise was checked before it was built on. `Tools/build_seed.py` assigns `species.id` as
`len(species_by_key) + 1` in **first-encounter order while it streams its sources**, so two builds
over different city sets number the same species differently — the bundle is built from San
Francisco and San Jose, the packs are cut from a fused seed that also holds New York. The ids
cannot be assumed to agree, and `species.uuid` (a `uuid5` of the scientific name) can.

Two alternatives were rejected on measurement:

- **Leave species per-arm and re-key every join to `uuid`.** Correct, and it produces the ideal
  narrowed plan (`SEARCH s USING COVERING INDEX sqlite_autoindex_species_1` then
  `SEARCH t USING INDEX idx_trees_species_current`) — but it is fifteen join sites across five
  query files, and it moves a species list's grouping key in every one of them.
- **Offset species ids per arm, as tree ids are offset.** The join `s.id = t.species_current`
  then compares two arithmetic expressions and stops being sargable.

Measured against an arm whose species numbering was deliberately **permuted**: the narrowed
viewport still resolves through `idx_trees_species_current` on every arm, because the `LEFT JOIN`
converts to an inner one under the caller's `WHERE` and the planner drives from the translation
table. `CumulativeInventoryTests` carries that fixture, and its red-proof — assuming the two files
agree — names the pack's Ginkgo `Platanus acerifolia`.

##### D7 — `CityInstallState`'s shape

**Chosen: one new case, `.bundledUpdated(installedContentRev:updateAvailable:)`, and the bundle
tested before the installed copy.**

The ordering defect is fixed by asking `bundled` first. Reordering alone would have been the wrong
fix and would have hidden the downloaded copy instead: a bundled city *with* a downloaded copy is
a real state, it is the one decision 4 is about, and the enum had no case for it. The
`updateAvailable` flag is a payload rather than a fourth case because what the reader sees is one
city with one record and at most one offer.

`isBundledCity` is stated on the type beside `isOnDevice` and `allowsDownload`, so the screen's
sectioning, its buttons and its copy cannot reach different conclusions about the same city.

##### D8 — the removal lifecycle

**Chosen: a whole-layer reboot, and it is stated rather than hidden.** Adding or removing an arm
rebuilds the views over a different set of schemas and renumbers the canonical species catalog.
Dropping and recreating in place would have to get both right on a connection other code may be
mid-read on; booting again gets them right by construction and is the path every launch already
takes. `CityDownloadsModel` therefore calls `onInventoryChange()` on **every** completed install
and every removal, where it used to call it only when the active choice moved.

Two justifications for clearing the statement cache were written and then **withdrawn after
measurement** — SQLite re-prepares a cached statement when the schema changes under it, and it does
not refuse a `DETACH` for a statement that is merely prepared. The clear is kept as a defensive
measure and `InventoryUnion.tearDownEverything` records that it is one.

#### What this ruling does not decide

Collected for the orchestrator. Each is a question this round declined to answer for itself.

- **D1 — Shadowing granularity.** Decision 4 settles *that* a downloaded copy of a bundled city
  shadows the bundled rows. At what granularity is still open: id space, published region, or per
  tree. The bundled seed is s16-shaped — it carries `dim_city` and **no `dim_region`** — so it
  cannot be shadowed at region granularity without a seed rebuild. Id-space granularity is
  sufficient for today's catalog, because the only two packs that overlap the bundle are whole-city
  packs whose pack id *is* their id space; it would not be sufficient for a borough pack whose city
  the bundle carried.
- **D2 — The screen copy above.** **Ruled, and then re-ruled.** The three state lines, the
  `Update` verb for a bundled city and `Revert to the included copy` were ratified verbatim on
  2026-08-24/25; the arrangement they sit in was re-ruled on 2026-08-25 as containment inside the
  built-in card, after the first implementation of *"nested under it"* drew nothing. One thing was
  open that this list never named, because it did not exist until the round wrote it: what a
  downloaded file says when the read layer refuses it. That copy is ratified too. All of it is in
  the ratified section above; nothing about this screen is left proposed.
- **D9 — Is the active set the installed set?** Decision 1 says the union is "the bundled seed plus
  every downloaded city pack", which reads as *downloaded ⇒ in the union*. Decision 2 says `Use`
  becomes "add/remove of a pack from the active set", which reads as a set a pack can be out of
  while still on disk. Both cannot be true. **This round recommends the first**: downloading a pack
  is what puts it in the union, `Remove` is what takes it out, and there is no third state to
  explain — which is also the reading that makes the confusing screen the owner ruled out
  unconstructible. If the second is meant instead, `CityLibrary`'s marker becomes a set of ids and
  every row acquires a fourth state.
- **D10 — `content_rev` in copy.** The comparison already treats it as an opaque ordered string
  (`CityInstallState` compares `publishedRev > bundledRev` on `String`, and splits no version).
  The *copy* does not: `record as of <rev>` renders it as a date. With same-day republishes becoming
  visible to update detection, a rev that is no longer a bare date will read oddly in that sentence,
  and the sentence is what needs a decision, not the comparison.
- **D3 — What "active" means to the map and to the test harness.** `Tools/run_tests.sh` refuses a
  run on a leftover `active-city` marker and on a camera with no seed tree within 250 m of it
  (E202, E216). Both are single-inventory notions. The opening camera's choice among several live
  inventories is likewise undecided.
- **D4 — Citywide aggregates.** `Cypress/Data/Store/CityQueries.swift` resolves an id space from
  the nearest tree and predicates every count on it, which still holds under a union. Whether the
  Journal's `City` segment and the almanac should now be able to speak about more than the city the
  reader is standing in is a separate question, and this ruling does not open it.
- **D5 — The attach cap.** Ten attached databases. Bundle plus seven packs is eight, plus `main`.
  Is the installed set capped, and what does a row say at the cap?
- **D6 — The canonical species catalog.** See above.
- **D7 — `CityInstallState`'s shape.** Decision 4 settles what the states *mean*; it does not settle
  the type. The ordering defect named earlier — `installedVersion` tested before `bundled`, so a
  bundled city that has ever been downloaded can never reach `.bundled` again — has to be fixed
  whichever way the rest goes, and the fix is more than reordering two branches: a bundled city with
  a downloaded copy is a state the enum has no case for, and it is the state decision 4 is about.
- **D8 — Removal while contributing.** Removing a pack from the set has to rebuild the view and
  invalidate every cached prepared statement built against the old one. That is mechanical, but it
  is a lifecycle the current code has no equivalent of: today a switch reboots `DataLayer` whole.

### R85 — The Journal picks its area: a neighborhood or city can be chosen, the default states its provenance, and a coarse fix is never used to place the reader (owner rulings, 2026-08-30)

**Everything below is a proposal for the owner's ratification, not a decision.** SCREENS.md carries
no mock for a picker on any screen, so the round is written under DECISIONS constraint 21's
delegated-authority pattern — the same footing R43 §3's affordance table and the City segment itself
stand on. Each item states what was built, and the alternative that was weighed and can be taken
instead without redesigning the round.

**What is already decided and is not up for ratification here:** the owner's 2026-08-28 backlog item
("In journal view, add ability to select a different neighborhood and get the stats for that
neighborhood (and ditto for City)"), and that this round supersedes R84 **D4** for the Journal.

---

#### D1 — A non-local pick draws from the **live** inventories, and only those

**Built:** both lists come from the union R84 decision 1 already serves — the bundled seed plus every
downloaded pack currently attached. That is exactly the set the map draws and the set the Cities
screen calls installed, so what the picker offers is checkable by the reader against a screen they
have already seen.

**Why not the published catalog.** A city whose pack is not on the phone has no rows to aggregate.
Offering it would open a screen that can only say nothing — E182's state, reached deliberately.

**Alternative, if the owner wants it:** offer every city in the live `manifest-v2.json` and turn a
tap on an uninstalled one into a route to the Cities screen with that city's download queued. It is
a real product improvement and it is a different round: it puts a network fetch behind a Journal
segment that has never had one, and it needs its own answer for the offline case.

**Narrower alternative:** offer only the inventory the reader is standing in. This is the
conservative reading and it is what R84 D4 effectively said. It also fails the owner's ask — a
reader who downloaded Manhattan cannot read Manhattan without going there.

#### D2 — The mechanism is a sheet of chips, and it introduces no new component

**Built:** C17 `BottomSheet(style: .standard)`, titled by C1 `ScreenHeader`, holding C4 `Chip`s in a
`CypressChipFlow` — `.filterSelected` for the live choice, `.filterIdle` for the rest. That is
screen 01's map-filter row, verbatim, and it already carries the `.isSelected` accessibility trait.
The affordance that opens it is a `SecondaryOutlineButton(.compact)` labelled `Change`, under the
header.

**Presented by the composition root, through `RootView`'s single `.fullScreenCover` keyed on
`AppRouter.sheet`** — the way screens 09, 10 and 15 are. **This is a correction (PR #132 review,
F2).** The first version drew the same card as a `ZStack` layer inside the segment's own content
slot, which sits between the C5 segmented control and the tab bar and therefore covered neither: the
review tapped `City` *through* the scrim, the segment switched, and the sheet vanished with no
dismissal and no `onClose`. Through the cover the picker is **exactly as modal as 09, 10 and 15**,
which is what the finding asked for: with it up, the controls at both ends of the screen report
`isHittable == false`. Parity is the whole of the claim — driving screen 15's own cover as a control
shows the background still enumerated in the accessibility hierarchy behind it too, so the cover does
not buy this sheet a VoiceOver property the app's other sheets do not already have.

The selection the sheet writes therefore lives on `AppRouter` (`journalArea` / `journalCity`), beside
`journalSegment` and for a related reason: a `Route` is `Hashable` and cannot carry a closure back
into a feature's `@State`. It is destroyed with the router on any inventory change, which is what
keeps D7 true.

**Why not a list with a checkmark:** a second selection idiom for the same job, and the checkmark
would have to be drawn as a shape (R57 forbids SF Symbols) — a new glyph for a control the app
already has.

##### Two chips with one label (PR #132 review, F4) — **RATIFIED by the owner, 2026-08-30**

`InventoryUnionSQL` deliberately does not merge neighborhoods across arms — *"two cities may each
have a `Downtown`, and merging those would put San Jose's trees in a San Francisco neighborhood"* —
so under R84's union the picker can be handed two rows with one name and nothing to choose between.

**Ratified, and built:** qualify **only a name that actually collides**, in the app's own middle-dot
idiom — `Downtown · San Jose`. Qualifying unconditionally would print a city beside all 41 of San
Francisco's names when nobody is choosing between cities; qualifying nothing leaves two identical
chips. A record with no city name on file is left unqualified rather than given an empty suffix.

Today's bundle cannot reach it (41 distinct San Francisco names, and San Jose carries no polygons at
all). It becomes live the first time a downloaded pack carries a neighborhood set, which is the
configuration D1 exists to enable and which the five published NYC borough packs are one install
away from.

**Alternatives:** a per-city section in the sheet (more structure than a chip flow supports), or a
stated decision that the ambiguity is accepted.

**Alternative:** make the header pill itself the tap target, with a drawn caret. Tighter, and it
loses the sentence — see D3, which is the half of this round that answers the tester rather than the
owner.

**Not built, and offered as a possible amendment:** a `SearchBar` above the chips. 41 neighborhoods
is a scroll; a hundred would need search, and the component exists. Left out to keep the round's
surface small.

#### D3 — The default states its own provenance, always

**Built:** one muted sentence under the header, in `areaNote`'s type and color, on both segments.

- resolved from the reader's fix **through a polygon**, i.e. the nearest inventoried tree —
  **"Chosen from the tree nearest you in the city record."**
- resolved from the reader's fix **through R29's radius fallback**, where no polygon covers them —
  **"Centered on where you are."** — **RATIFIED by the owner, 2026-08-30**, verbatim
- picked by the reader, almanac — **"You're reading a place you're not in, so the section asking you
  to go and look is left out."**
- picked by the reader, City — **"You're reading a city you're not in, so the comparison with your
  own streets is left out."**

##### The third sentence, and why it exists (PR #132 review, F1 — blocking)

The first version had two sentences and keyed them on `AreaResolution`, which answers *"did the
reader choose this"* — the question the picker asks — and not *"what chose it"*, which is the
question this line answers. The two coincide for a polygon and come apart for the fallback, where no
tree was consulted at all.

**It was not an edge.** All **52,788** San Jose rows carry `neighborhood_id IS NULL`, so every reader
in the bundle's second city sat permanently under *"Chosen from the tree nearest you in the city
record."* printed directly above *"No neighborhood boundaries are on file for where you are, so this
almanac is drawn around you instead."* Two adjacent sentences about one area, and the new one was the
false one — this round's own thesis failing on itself.

The wording states what actually happened and stops: the reader's fix is the circle's center
(`AlmanacScope.radius(center:meters:)` is handed the coordinate), and *why* it is a circle is the
next line's job. **Deliberately not `nil`**, which was the review's other suggestion: D3's rule is
that the default accounts for itself always, and a blank where the account should be is how the
screen got into F17 to begin with.

**The alternative, if the owner prefers it:** drop the line for the fallback and let `areaNote` carry
the whole explanation. It reads slightly lighter and it costs D3 its "always".

**This is the half of the round that answers F17 rather than the backlog item.** The report asks why
the page "seems to default to" a neighborhood, and until now the screen said nothing at all: a name
in the header, as bare fact, with no account of where it came from and no way to disagree. The
sentence names the *mechanism* rather than the outcome, because the mechanism is the part that
explains a surprising name.

**Alternative:** state it only when the area is picked, and leave the default silent as it is today.
Half the round's cost, and it leaves the tester's actual question unanswered.

#### D4 — A picked area drops the blocks that are about the reader, and keeps the ones about the place

**Built:**

- **Almanac §4, `Where eyes are needed`, does not draw for a picked area.** It is the app's one
  directed ask (D1) and its second sentence is a claim about the reader's own walking distance
  (`AlmanacMetrics.walkRadiusM`). Both are about the reader; neither survives being pointed at a
  neighborhood across town.
- **City card 1, `Your streets, against the city`, does not draw for a picked city.** Its sentence
  is "…% of the trees near you and …% citywide" — two halves that would be measured over ground
  forty miles apart, which is R48's defect wearing a conjunction.
- Everything else is a fact about the place and is unchanged.
- **Distances inside a picked area are measured from the area, not from the reader.** The nearest
  vacant site and the newest plantings order from the neighborhood's own stored bounding-box center,
  so the list is the same for everybody who picks that name.

**Alternative:** keep §4 and card 1, and re-word them to say how far away they are. Honest, and it
turns the app's one directed ask into a suggestion that somebody drive across a city — which is a
product decision, not a copy one.

#### D5 — A fix too coarse to place the reader is not used to place the reader

**Built:** `AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM:)`. A fix whose stated accuracy
exceeds the radius its own resolution searches cannot pick out a tree inside that radius, so it is
not used at all; the segment draws **"Your location is too rough to place you."** and the picker.
An unknown accuracy is permitted, which leaves every preview and test unchanged.

**The bound is the caller's, and that is a correction (PR #132 review, F3).** The two segments do not
search the same distance — the almanac resolves through `SpeciesQueries.resolveNeighborhood` at
**400 m**, the City segment through `CityQueries.resolveIDSpace` at `AlmanacLimits.fallbackRadiusM`,
**1,200 m**. Keyed on 400 m for both, a fix good to 600 m blanked a City segment that could still
answer, and did answer on main. Each gate now takes the radius its own read runs over, and this
ruling's text says both numbers rather than one.

**This is the state F17 most likely came from** — see **ERRATA E282** for what is established and
what is not. Approximate location grants exactly this kind of fix, and the app
neither requests full accuracy nor reads `accuracyAuthorization`.

**The copy deliberately does not name the setting.** The app cannot tell an approximate grant from a
poor fix in a parking garage, and naming the wrong cause is how a true screen becomes a misleading
one.

**Alternative (the conservative one):** keep naming the nearest area whatever the accuracy, and rely
on D3's sentence plus the picker to let the reader correct it. This leaves a wrong name on screen by
default, which is the thing the report complained about, but it never blanks a screen that used to
have content on it.

**Second alternative:** ask iOS for temporary full accuracy at this point
(`requestTemporaryFullAccuracyAuthorization`). It is a system prompt with a purpose string, on a
screen that is not asking for anything else, and it is a bigger change than this round's shape.

#### D6 — The City segment names its city

**Built:** the header's trailing pill carries `dim_city.display_name`, read through
`id_spaces.city_id`, and carries nothing when the record has no name on file.

**This reverses three comments rather than a ruling** — see **ERRATA E284**. The rule they stated was true until seed schema 16 put the
name on disk. What stays forbidden is composing a name from an id space's key or an inventory's
title, which is what R28 and R48 actually closed.

**Alternative:** keep the bare `City` header and name the city only inside the picker. Safe, and it
means a reader who picked San Jose has no persistent indication of what they are looking at.

#### D7 — `Where I am` is always offered, and a stale pick falls back to it

**Built:** the first chip in both sheets is `Where I am`, present even while it is the live choice,
and a picked id the live inventories no longer carry (the reader removed a pack) resolves to the
reader's own area rather than to a named empty screen.

**Ratified 2026-08-30: it resets, and that is the decision.** The selection **does not survive
relaunch**. It lives on the
model for the life of the screen, like `AppRouter.journalSegment` before it was made addressable. A
reader who picks Manhattan, leaves the app and comes back is back on `Where I am`. That is
defensible — a stats screen whose default silently stopped being "here" is its own version of F17 —
but it is a choice, and it has now been made rather than left open.

The review confirmed there is no persistence path to leak through — no `@AppStorage`, no `app_state`
key, no `UserDefaults` write — and the move onto `AppRouter` (F2, above) keeps it that way: the
router is `@State` on `RootView`, which `CypressApp` keys on `ObjectIdentifier(data.store)`, so an
inventory change destroys the selection along with everything else built on the old layer. A pick
cannot outlive the inventory it was made against.

### R86 — The 390 pt chip row: `Clear filters` scrolls (owner ruling, 2026-08-30)

With a filter applied, screen 01's chip row is `Yours · In bloom · Needs care · More filters ·
Clear filters` — ~464 pt of chips against a 390 pt device, so one chip is always past the trailing
edge, reachable by dragging the row. Four arrangements were put to the owner with PR #130's
measurement (pinning `Clear filters` costs 88 pt and pushes `More filters` — the control R23.1 §2
gives three channels precisely so narrowing is visible from inside the map — off the edge at every
text size). **The owner chose (a): leave it.** `Clear filters` scrolls; the way out is one drag
away; and the filled chip at the leading edge — always visible — is the standing second escape,
since turning it off un-narrows the map without the row moving at all.

Shortening a label (option d) was offered and not taken. The ruling stands until the row's
composition changes — a sixth chip, or a narrower device class, reopens it.
