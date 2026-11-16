# Rulings pending: species on a community tree somebody else added (ROADMAP 144, the service half)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

This adds to `community-trees-answers-2026-11-15.md` (second entry, answers 3 and 4), which this
round builds. The service half is on branch `feat/species-for-everyone-server`, migration 009.

---

### R??? — Species on a tree somebody else added: the owner's answers of 2026-11-16

Each answer below is the owner's, given in a question dialog on 2026-11-16. The quoted strings are
the exact ones the owner saw and chose.

1. **Who counts.** Q: "On a community tree somebody else added, who can name its species or report
   its species as wrong, so that the answer counts for everyone?" **Chosen: "Only people who
   share".** "Signed in and agreed to share tree records. For everyone else the two controls do not
   show on someone else's tree." Not chosen: "Anyone who can see the tree".
   *The service holds it so:* a naming, a correction or a report from anybody but the adder changes
   anything only when it comes from an account whose stored license version is accepted and known.
   From anybody else it is recorded and answered `applied`, and it changes nothing. It is never
   refused.
2. **Clearing a report.** Q: "When the profile of a tree you added shows "Somebody has reported this
   species as wrong.", can you clear that line without changing the species?" **Chosen: "Yes, with
   "Keep the species"".** "The adder taps the existing "Keep the species" control and the line
   clears for everyone. A later report brings it back." Not chosen: "No, only a correction clears
   it".
3. **The namer's own answer.** Q: "A person names the species of a tree somebody else added, and the
   name now shows for everyone. Can that person later correct their own answer?" **Chosen: "Yes,
   until the adder corrects it".** "The person who named it can change their answer until the adder
   steps in." (The recommended option, "No, only the adder", was not chosen.)
   *The service holds it so:* the namer is the account in `community_trees.species_namer_user_id`.
   The adder's correction, the adder's "Keep the species", and the operator's correction each set it
   to NULL, and so does the namer's account deletion. A naming with no namer can be changed only by
   the adder and the operator. No phone's clock decides any of this.
4. **The namer's account erase.** Q: "A person names the species of a tree somebody else added, and
   later deletes their account with the erase option. What should happen to that species name?"
   **Chosen: "The species stays".** "The name stays for everyone, with nothing that links it to the
   person." Not chosen: "The tree loses its species".
   *The service holds it so:* under both deletion doors the species stays, the naming loses its
   namer, and the actor columns of every event the account made come off, on every tree.
5. **The note under "Report the species as wrong".** Chosen: **"Name the adder"**: on a community
   tree somebody else added, the note reads exactly
   `This goes to the person who added the tree and to a reviewer. The city is not notified.`
   City trees keep `This goes to a community reviewer. The city is not notified.` (Phone half only;
   recorded here so the answers are in one place.)

### R??? — Species on a tree somebody else added: the orchestrator's choices (not asked of the owner)

These are the orchestrator's choices, not the owner's.

1. **A race between two first answers.** The first naming the service commits wins. The later one
   is recorded and changes nothing, and its sender is told nothing: the answer is `applied`.
2. **History wording does not change.** The history keeps serving the adder's acts as
   `species_named` and `species_corrected`, which every build maps to "Species named" and "Species
   corrected". Anybody else's acts are served under new kinds (`species_named_by_contributor`,
   `species_corrected_by_contributor`, `species_corrected_by_operator`), which the C3 build drops
   rather than labels "You …" on the adder's phone, and each event carries `by_you`. A later phone
   build maps the new kinds to the same two labels.
3. **The operator corrects a species through an operator route**, guarded like the takedown, not a
   screen: `POST /operator/community-trees/{id}/species` and
   `POST /operator/community-trees/{id}/species-reports/clear`.
4. **"The later committed act wins" holds against the operator too.** Between two people the
   service applies acts in the order it commits them, and never compares two phones' clocks, or a
   phone's clock with the service's. So an adder's correction that waited in the adder's outbox
   (made before the operator's correction, sent after it) replaces the operator's species when it
   arrives. The adder may correct at any time anyway, so this changes who can act, never only when.
   (Adjudicated after the review of 2026-11-16.)
5. **"Keep the species" clears only the reports the adder saw.** The adder's dismissal names a
   report by its `flagID`, which the adder's phone takes from the profile's
   `species_report_flag_id`. The keep clears that report and every earlier one, never a later one,
   so a report made after the adder tapped still counts while the keep waits in the outbox (the
   owner's "A later report brings it back."). A keep whose `flagID` names no counting report
   changes nothing and is still answered `applied`. Builds before the phone half of ROADMAP 144
   send the `flagID` of a flag row on their own phone, which is never a counting report on a tree
   that phone's account added (the adder's own reports do not count), so their keeps change
   nothing. (Adjudicated after the review of 2026-11-16.)
6. **A keep ends the namer's right to correct only when it acts.** The owner's words are "until the
   adder corrects it" and "until the adder steps in". An adder who kept the species against a
   report they were shown has stepped in; a keep that matched no report decided nothing.
7. **`species_named_by_you` follows the rule exactly.** It is true only while the namer's
   correction would apply: the caller is the namer in force and still shares. A namer who later
   declines the license is told false, so the phone draws no control that silently does nothing.

### R??? — Pending with the owner

1. **A namer's change of name and the reported line.** Today (the build on this branch): a report
   disputes the name in force when it was made, so a namer's correction to another name makes
   "Somebody has reported this species as wrong." go away, and a correction back to the reported
   name brings it back. The owner is being asked whether the line should instead stay until the
   adder or the operator acts. The current behavior is kept until the answer comes;
   `materializeSpecies`' namer arm is the one place it would change.

### R??? — Species on a tree somebody else added: the service author's design choices

Recorded so a reviewer can see each one and the orchestrator can ask the owner where it should.

1. **A report counts against the species it disputed.** The service fixes the disputed species when
   it receives the report: the payload's new optional `disputedSpeciesID`, or else the species in
   force at that moment. A report counts while that is still the tree's species and it came after
   the last clear. So **the namer's own correction does not clear reports**, as the brief asked, but
   a report about the old name stops counting once that name is gone, because the line "Somebody
   has reported this species as wrong." would otherwise sit under a name nobody reported. If the
   namer changes the name back, those reports count again. Only the adder and the operator **clear**
   reports. The owner is being asked about this (see "Pending with the owner" above).
2. **A report from the namer of the species in force does not count** (correct it instead), and a
   report on a tree with no species does not count. The adder's own report does not count.
3. **The adder's `species_claim` on a tree a contributor named is the adder's correction.** Builds 88
   and older, and any adder's phone that has not learned the contributor's name, send a claim. It
   writes `species_corrected` by the adder and clears the reported state.
4. **Between two people, the act the service commits later wins; a phone's clock is compared only
   with the same identity's earlier statements** (one outbox can drain out of order). Before 009 the
   adder's correction was compared with every species event's `occurred_at`; it is now compared
   only with the adder's own. For a signed-in adder "its own" includes the signed-out acts of every
   device the account claimed, because a phone that named a tree signed out and then signed in can
   still drain an older correction under the account (the review's F1).
5. **Existing reports do not light the mark at deploy.** Only reports received after 009 can count.
   No backfill.
6. **The operator's species id is not checked**, because the service holds no species catalog.

### R??? — Species on a tree somebody else added: the phone half (branch `feat/species-for-everyone-phone`)

The owner's fifth answer above (the note under "Report the species as wrong") is built here, as
`TreeProfileCopy.reportSpeciesNoticeOthersTree`. It is the only new string. The rest are the phone
author's design choices, recorded so a reviewer can check each one.

1. **Who sees a control** follows the service exactly (`SpeciesAnswerFacts` in
   `Cypress/Data/API/SpeciesClaim.swift`). The adder: "Correct the species", and with a counting
   report the line, "Correct the species" and "Keep the species". The namer, while sharing: "Correct
   the species", and with a counting report the line and "Correct the species", with no keep (a new
   offer, `reportedYoursToCorrect`). Anybody else who shares: the claim on an unnamed tree and the
   report on a named one. Everybody else: no control. The reported line is drawn to every reader,
   because it is a fact about the tree and not a control. A phone whose sharing answer is `unknown`
   (a reinstall, ROADMAP 148) gets no control on somebody else's tree.
2. **The phone-only arms are gone.** "The author of the claim in force" and "a lead, in answer to a
   report" (R45) could correct and keep on a community tree, and the service applied neither. Both
   are removed from `correctSpecies` and `dismissSpeciesReview`. The adder may now correct any
   species, including one owned by nobody on this phone.
3. **A cached tree keeps one writer.** Naming, the namer's correction and a report on a tree in the
   community cache go into this phone's own tables (`species_assertions`, `review_flags`) and the
   outbox; the cache itself is written only by the tile refresher. The reader's own answer is laid
   over the cache's species while it is in force: still queued, or the cache has no species, or the
   cache holds the reader's species or the one their correction replaced. Otherwise the cache wins.
   With the service's answer in hand, the profile shows the service's species once nothing of the
   reader's is queued.
4. **The service's answer wins over the phone's**, except over an act of the reader's that is still
   queued: a queued naming or correction keeps the reader's species and correction control, a queued
   report keeps the line, and the adder's queued correction ends the line. **The adder's queued keep
   does not end the line**: the service clears only up to the report the keep names, so the line
   goes when a later read says so. A service without the keys (release v16) leaves every answer the
   phone's.
5. **The adder's phone takes the service's species** onto its own row (`adoptServedSpecies`), owned
   by nobody in the chain, from a profile read and, for an unnamed row only, from a tile page. Never
   while any species act on that tree is queued on this phone, never over a species this phone
   wrote after it asked, and never a species missing from this phone's catalog.
6. **The adder's keep of a report raised on another phone** names the service's
   `species_report_flag_id`. The phone holds no row for that report; `RoutedAPI` remembers which
   tree each served flag is about, from the profile read that drew the control.
7. **Every report names the species it disputes** (`disputedSpeciesID`). On a cached tree a second
   report is refused only while the first is still queued; once it is sent, the service decides
   whether it still counts, and a new one may be raised after the adder's keep.
8. **History rows**: "You" is the service's `by_you` for each row. Without it, a kind only the adder
   makes is the reader's when the reader added the tree, and the three new kinds are never "You".
9. **No phone migration and no new `CypressAPI` requirement.** `RoutedAPI` reaches `LocalAPI`
   through an injected seam (`CommunitySpeciesSeam`), as it does for photographs.
