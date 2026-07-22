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

What the selected cell is: the heart glyph fills, glyph and label take `accent`, the card fill takes
the same tinted surface a selected filter chip takes. **The label does not change.** It says
`Favorite` in both states because it is a noun naming the thing, not a verb naming the next tap —
`Unfavorite` would be a different word appearing under the same icon, which is how a control starts
lying about what it is.

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

## What is still design's, and was not delegated

- The C10 locked glyph and the C23 chart series (R1, above). Drawn decisions, both failing 3:1.
- The rubric wording on screen 05 — whether `PRODUCT.md` or `SCREENS.md` holds the anchor sentences.
- Everything constraint 21 covers. The one-time exception for the six entrances (E98) is spent.
