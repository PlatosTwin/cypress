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
  — `In bloom` because every `seasonal` is `{}` (R23 already says so), and `Needs care` because
  `MapPinKind.needsCare` is `status == .declining` and the seed carries only `alive` (174,425) and
  `vacant_site` (24,200). R23 left the first open on the grounds that the curated species pipeline is
  what fixes it. The second is the same shape of question and the owner has just re-confirmed both
  chips by name, so neither is touched here. **It is recorded because it was not written down
  anywhere**, and because a chip that cannot match is a chip guaranteed to produce an empty-state
  card.
