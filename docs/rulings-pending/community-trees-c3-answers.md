# Rulings pending: the owner's answers to the C3 questions (community trees, the UI round), 2026-11-14

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

Every answer below is the owner's, given in an AskUserQuestion dialog on 2026-11-14. Each string in
quotation marks is the exact string the owner saw and chose. Where the owner typed an answer, the
words are quoted as typed. Nothing here is built. C3 (`docs/ROADMAP.md`, "Community trees: the client
rounds") builds it, and DECISIONS constraint 21 is now satisfied for the surfaces listed here and for
no others.

Two related entries are in their own files: the old trees
(`community-trees-old-trees.md`) and the end of the 10 m rule
(`community-trees-no-proximity-rule.md`).

---

### R??? — Move pin: no distance limit, the draft strings stay, and how a move reads on the Outbox screen

1. **How far a pin may move.** Offered: no limit; 75 m from you; 75 m from the pin. The owner typed:
   *"can go anywhere, and also fine to go within 10m of another tree. sometimes they will be close
   together and that's fine"*. **A pin move has no distance limit, and it may land within 10 m of
   another tree.**
2. **The Move pin draft strings.** Offered: keep the drafts; use "Move the pin". **Chosen: keep the
   drafts.** The strings in `MovePinCopy` are ratified as they ship, except the two that state the
   10 m rule, which go with the rule (see `community-trees-no-proximity-rule.md`).
3. **The Outbox row label for a pin move.** Offered: "Pin moved"; "Move pin"; "Location correction".
   **Chosen: "Pin moved"**, as in "Pin moved · Grandmother Cypress". It has no second line.
4. **A refused move on the Outbox screen.** Offered: the same sentence as every other kind; the Move
   pin screen's own refusals. **Chosen: the same sentence**, "This couldn't be sent."

### R??? — The history of a community tree on its profile

1. **Where it appears.** Offered: the profile's activity list; its own list on the profile; the
   Activity screen. **Chosen: the profile's activity list.** History rows sit in the tree profile's
   existing activity list, mixed with visits and care by date. That list shows the four most recent
   rows, so older rows drop off.
2. **Which events.** Offered: all four; added and pin moves; added only. **Chosen: all four**: added,
   pin moved, species named, and species corrected. That is everything the service sends.
3. **How a pin move reads.** Offered: with distance; no distance; "Position corrected". **Chosen:
   with distance**: "Pin moved · 12 m north". The distance is in whole meters with one of eight
   compass directions, the words the Move pin screen already uses.
4. **Whether your own rows say "you".** Offered: no, the same for all; yes, on your own phone.
   **Chosen: yes, on your own phone.** Other readers still see no name (decision 4 of 2026-09-28
   stands for them).
5. **The rows, word for word.**

   | Event | Other readers | The person who did it, on their own phone |
   |---|---|---|
   | Added | "Added" | "You added this tree" |
   | Pin moved | "Pin moved · 12 m north" | "You moved the pin · 12 m north" |
   | Species named | "Species named" | "You named the species" |
   | Species corrected | "Species corrected" | "You corrected the species" |

   For the two species rows as other readers see them, the offer was "Species named" and "Species
   corrected", or "Species added" and "Species changed". **Chosen: "Species named" and "Species
   corrected".**
6. **The date on a row.** Offered: "Mar 20"; "Mar 2026". **Chosen: "Mar 20"**, month and day with no
   year, as the visit and care rows on the profile already read.
7. **When the history cannot be read, or is empty.** Offered: the Added row only; the Added row and a
   line. **Chosen: the Added row only.** The profile shows the "Added" row from what the phone knows
   and no message.

### R??? — A pin move in the Journal

Offered: "Moved the pin of X"; "Moved X"; no Journal row. **Chosen: "Moved the pin of X"**, as in
"Moved the pin of Grandmother Cypress".

### R??? — The note under the Add this tree button

1. **Signed in and sharing.** Offered: once it is sent; shared with everyone; drop the where.
   **Chosen:** "Recorded as community-added and unverified. Everyone using Cypress can see it once it
   is sent."
2. **Signed out, or not sharing.** Offered: until you sign in; for now; keep today's line.
   **Chosen:** signed out: "Recorded as community-added and unverified, on this phone. Everyone using
   Cypress can see it after you sign in." Signed in and not sharing: "Recorded as community-added and
   unverified, on this phone. Everyone using Cypress can see it after you agree to share your tree
   records."
3. **Private property.** Offered: do not mention it; only when chosen; always. **Chosen: do not
   mention it.** The line above the button already names private property when the reader chose it.
4. **The largest text sizes.** Offered: move into the scroll; stay pinned; shorter at large sizes.
   **Chosen: move into the scroll.** At the largest sizes the note moves up into the scrolling form
   and only the button stays pinned.

### R??? — Other people's community trees

1. **Their pins on the map.** Offered: the same dashed pin; a mark on your own. **Chosen: the same
   dashed pin** for every community tree, yours or anyone's.
2. **The controls on the profile of a tree someone else added.** Offered: all but species and
   reports; add the species controls; look only. **Chosen: add the species controls.** Such a
   profile has visit, check-in, care, favorite, share, and measure, as on a city tree, and also "Say
   what species you think this is" and "Report the species as wrong". Move pin never appears there
   (owner decision of 2026-11-12).
3. **Your own tree that is not shared yet.** Offered: only on this phone; "Not shared yet."; no line.
   **Chosen:** a line on the tree's profile. Signed out: "This tree is only on this phone. Everyone
   can see it after you sign in." Signed in and not sharing: "This tree is only on this phone.
   Everyone can see it after you agree to share your tree records."
4. **Adding a tree when another is already recorded within 10 m.** The rule that refused this is
   gone (see `community-trees-no-proximity-rule.md`). Offered: a note, then still add; add with no
   note. **Chosen: a note, then still add.** The "ALREADY ON RECORD" notice stays as a note that does
   not block, the list of nearby trees stays under it, and the Add this tree button stays active.
   For the wording, offered: the note with today's sentence "If one of these is the tree in front of
   you, open it." kept; two sentences. **Chosen: two sentences:** "Something is already on record
   within 10 m of here. Add this tree only if it is a different one."

### R??? — Places with no city inventory

1. **The map's "No trees on record here" card.** Offered: keep as is; name both kinds; also a card
   over added trees. **Chosen: name both kinds.** Same card and same trigger, new body: "Cypress
   draws a city street-tree inventory and trees people have added. Neither has a tree here."
2. **The empty "What tree is this?" list.** Offered: "Nothing on record is within 60 m of you…"; keep
   as is; name both kinds. **Chosen: name both kinds:** "No city tree and no added tree is within
   60 m of you. If there is a tree in front of you, it is not on the map yet."

---

#### What these answers do not settle (facts for the round that builds C3, not rulings)

- **The map card at the largest text size.** `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5`
  budgets the card's text. The new body is shorter than today's message ("Cypress draws a city
  street-tree inventory, and this ground is not on it. Trees may stand here without being listed."),
  but its words break differently. Measure it, and if it does not fit, ask the owner.
- **Species controls on other people's trees.** The service's rules for `species_claim` and
  `species_correction` are in `community-trees.md` (a claim names the tree only while its species is
  empty). Check what the phone and the service do today for a tree the reader did not add before
  showing the controls.
- **The "Added" date.** For a tree added before syncing existed, the owner chose the day it was added
  (`community-trees-old-trees.md`). Decision 13 of 2026-09-28 says others see a tree as added when
  it went public. The two rules now differ for a tree that waited on a signed-out phone. Bring this
  to the owner when the round reaches it; do not pick one.
- **Where the "only on this phone" line sits on the profile.** The owner chose the words and that it
  is one line on the profile. The round places it like the profile's other one-line notices and shows
  the owner a screenshot.
- **The UI suite runs with the remote gate off**, so C3 still needs the DEBUG seam that seeds the
  community cache (ROADMAP, C3).
