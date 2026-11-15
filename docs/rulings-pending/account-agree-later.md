# Rulings pending: agreeing to share tree records after declining at sign-in (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

Every answer below is the owner's, given in an AskUserQuestion dialog on 2026-11-15. Each string in
quotation marks is the exact string the owner saw and chose. The branch
`feat/share-my-tree-records` builds all four.

It answers the first item under "What these answers do not settle" in
`community-trees-answers-2026-11-15.md`: there was no control that let a signed-in reader who
declined to share agree later. There is one now.

---

### R??? — "Share my tree records": a way to agree later, on the You tab

1. **Whether a person who declined at sign-in can agree later, and where.** Offered: "Add a row on
   the You tab (Recommended)"; "Tell them to sign in again"; "Leave it for a later build".
   **Chosen: "Add a row on the You tab".** The row is in the You tab's Account section, signed-in
   state, directly under the line "You did not agree to share your tree records under the open
   database license." It shows only when that line shows: signed in, and the stored answer is
   "declined". It does not show for a person who agreed, for a signed-out person, or when the phone
   does not know the answer.
2. **The row's words.** Offered: "Share my tree records (Recommended)"; "Agree to share tree
   records"; "Change my answer". **Chosen: "Share my tree records".** Second line: "Under the open
   database license. Anyone may use the data". The app ships no license text, so the row offers no
   link to one.
3. **What a tap does.** Offered: "Ask to confirm first (Recommended)"; "Agree when tapped".
   **Chosen: "Ask to confirm first".** A tap opens a confirmation. Title: "Share my tree records?"
   Body: "Everyone using Cypress will see the trees you have added. This cannot be undone." Buttons:
   "Share" and "Cancel". "Cancel" changes nothing. "Share" asks the service first, and only when the
   service records the answer does the phone record it. The line then reads "You agreed to share your
   tree records under the open database license." and the row is gone. The service makes every
   community tree the account owns public in the same step.
4. **What the You tab says when agreeing fails** (no connection, or the service refused). Offered:
   "That did not go through. (Recommended)"; "With a hint" ("That did not go through. Check your
   connection and try again."); "No message". **Chosen: "That did not go through."** One line under
   the row. The row stays so the person can tap again. Nothing is written on the phone. The line
   clears when a later try succeeds. While a request is in flight the row takes no taps; there are
   no new words for that state.

---

#### What this row does not cover (facts, not rulings)

- **A person who declined and then reinstalled the app.** After a reinstall the phone no longer
  knows the answer (the restore clears it), so the "did not agree" line does not show and neither
  does the row. That person still has no way to agree from the app.
- **Re-consent when the license version changes.** `docs/RULINGS.md` names it as open ("re-consent
  when the license version moves"). This row does not settle it: an account that agreed to an older
  version reads as having agreed, so the row does not show for it.
