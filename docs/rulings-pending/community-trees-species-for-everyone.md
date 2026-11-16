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

### R??? — Species on a tree somebody else added: the service author's design choices

Recorded so a reviewer can see each one and the orchestrator can ask the owner where it should.

1. **A report counts against the species it disputed.** The service fixes the disputed species when
   it receives the report: the payload's new optional `disputedSpeciesID`, or else the species in
   force at that moment. A report counts while that is still the tree's species and it came after
   the last clear. So **the namer's own correction does not clear reports**, as the brief asked, but
   a report about the old name stops counting once that name is gone, because the line "Somebody
   has reported this species as wrong." would otherwise sit under a name nobody reported. If the
   namer changes the name back, those reports count again. Only the adder and the operator **clear**
   reports. The owner may want to be asked whether a namer's change should leave the line on.
2. **A report from the namer of the species in force does not count** (correct it instead), and a
   report on a tree with no species does not count. The adder's own report does not count.
3. **The adder's `species_claim` on a tree a contributor named is the adder's correction.** Builds 88
   and older, and any adder's phone that has not learned the contributor's name, send a claim. It
   writes `species_corrected` by the adder and clears the reported state.
4. **Between two people, the act the service commits later wins; a phone's clock is compared only
   with the same identity's earlier statements** (one outbox can drain out of order). Before 009 the
   adder's correction was compared with every species event's `occurred_at`; it is now compared
   only with the adder's own.
5. **Existing reports do not light the mark at deploy.** Only reports received after 009 can count.
   No backfill.
6. **The operator's species id is not checked**, because the service holds no species catalog.
