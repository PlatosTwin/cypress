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

- **A person who declined and then reinstalled the app** (ROADMAP chip 148, branch
  `feat/account-license-readback`). Both session answers of the service (`POST /auth/oidc` and
  `POST /auth/refresh`) now carry the account's stored answer as `license_version`: the version
  accepted, or `null`. The phone keeps it in the stored session and writes it back at launch, with
  no request, and after each refresh. So after a reinstall the "did not agree" line and the row show
  again. This needs `cypress-sync` deployed with that branch; until then the service sends no key,
  and the phone behaves as before (no line, no row). A session stored by an older build carries no
  answer either, so on such a phone the line and the row come back only after the first refresh.
- **Two behaviors the orchestrator chose for that change (2026-11-16), to be confirmed by the
  owner.** Each is one named constant in `LocalAPI`, easy to flip.
  1. **When the service's answer differs from the phone's stored answer, the phone shows the
     service's** (`serviceLicenseAnswerWins`). For example, an account that agreed on one phone and
     then declined at a sign-in on a second phone reads "did not agree" on the first phone after its
     next refresh.
  2. **A restored phone whose account has no acceptance on the service shows the "did not agree"
     line and the "Share my tree records" row** (`serviceNoAcceptanceReadsAsDeclined`). The service
     cannot tell "declined" from "never asked" (both are a `NULL` `license_version`). Every in-app
     sign-in since 2026-08-14 sent an answer, so "never asked" is an account from before then.
- **Re-consent when the license version changes.** `docs/RULINGS.md` names it as open ("re-consent
  when the license version moves"). This row does not settle it: an account that agreed to an older
  version reads as having agreed, so the row does not show for it.

#### Known limits and review findings (facts, not rulings)

- **A conflict after the service has agreed.** On the service, `POST /devices/claim` records the
  answer and publishes the account's trees (`RecordLicenseConsent`, its own transaction) before it
  runs `ClaimDevice`. If `ClaimDevice` answered `conflict` (409), the service would have agreed while
  the phone shows "That did not go through." Checked in `server/internal/api/auth.go` and
  `server/internal/store`: a sign-in whose device belongs to another account is refused with
  `conflict` before any session is minted, only `ClaimDevice` sets a device's account, and only an
  account deletion clears it, which ends that account's session too. So a phone that holds this
  account's live session holds a device this account owns, and the conflict is judged unreachable.
  Not handled.
- **Nobody has seen the confirmation alert on a screen.** The screenshot suite cannot draw an iOS 26
  alert faithfully off-screen (its background, dimming, and message are missing from the capture). A
  unit test reads the alert's labels and proves its title, message, "Share", and "Cancel" are there
  at the default text size and at the largest accessibility size.
- **Found in review, and fixed: a sign-out while the request was in flight.** The account can end
  while the request is in flight (`DataLayer.boot`'s `onSessionEnded` signs the phone out when
  another request's refresh is refused). The first build then wrote the phone after the service's
  yes, and that write signed the phone back in to an account with no stored session. Now the phone
  is written only when both its database and its stored session still name the account. Otherwise
  the You tab shows the signed-out Account section and no failure line. The service has still
  recorded the agreement.
- **Two smaller additions from review.** The failure line is announced to VoiceOver with its own
  words, once per failed try. The confirmation closes if the account is signed out while it is up,
  as the deletion sheet does.
