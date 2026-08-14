# Unnumbered — the app goes live, and three sentences stop being true (task #158, the wiring round)

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `feat/158-wiring`, the round in which `DataLayer.boot`
stopped constructing a `LocalAPI` and started constructing a router with a server behind it.

Four findings. The first three are copy questions the owner has to answer and this branch
deliberately did not; the fourth is a defect in the service that only becomes reachable now.

---

## 1. Wiring the send sink makes screen 18's storage line false, and the mocks have no arm for the state it is now in

`Cypress/Features/Visit/VisitSaveLedger.swift`'s `storageLine` draws one of two sentences:

- ask resolved → **"Saving to this phone only. You can add an account any time."**
- otherwise → **"Saved to this phone. You can add an account later to back it up."**

Both were true while the outbox had one sink. They are not true now. `DataLayer.boot` wires
`APIOutboxSendSink` over `RemoteAPI`, and D9 makes the *anonymous* case the normal one rather than
the exception — `AppSession.authorization()` says why in one line: "a queue that could not drain
without an account is a queue that fills up." So an installation that has never opened screen 15 is
sending its visits to `cypress-sync` under a device credential, and the word "only" is a claim about
where somebody's work is that the app can no longer make.

**Why it was not simply rewritten.** PROTOTYPE-FLOW §1.4 gives three arms and every one of them keys
on `account`:

| arm | string |
| --- | --- |
| `linked` | `Backed up to your account · joins the public timeline when signal returns.` |
| `dismissed` | `Saving to this phone only. You can add an account any time.` |
| otherwise | `Saved to this phone. You can add an account later to back it up.` |

The brief for this round said both replacement strings already exist in the corpus and to use them
rather than invent any. **The strings do exist** — `AccountAskCopy.body` at
`Cypress/Features/AccountAsk/AccountAskPresentation.swift`, and the `linked` arm verbatim in
`docs/distilled/PROTOTYPE-FLOW.md` §1.4. What does not exist is the **state**. The `linked` arm needs
somebody signed in, and Sign in with Apple is blocked on an entitlement this repository cannot add
(`docs/errata-pending/158-the-session-lands-and-the-sign-in-sheet-cannot.md`, §2), so on every build
producible from this tree it is unreachable. The state the app is actually in is **anonymous, and
sent**, and the mocks enumerate four account states — `none`, `ask`, `linked`, `dismissed` — none of
which is it.

A fourth sentence is copy, and copy is not an engineer's to write (DECISIONS constraint 21). So the
line stands, wrong, with the reason written above it in the source, and this is the ask. Two prose
comments that asserted the opposite — `RootView.accountLink()`'s "screen 18's 'saving to this phone
only' stays true after it" and `VisitSavedView`'s "which stays true" — were corrected in the same
commit, because a confident comment is where bugs survive here.

## 2. Screen 15's copy went the other way, and that one *is* resolved — by deletion

`BetaCapability.accountsAreLocalOnly` and `AccountAskCopy.bodyLocalAccount` are gone.

ERRATA **E131** introduced them because SCREENS.md §2's drawn sentence — "An account backs them up
and lets them join each tree's public timeline" — made two promises a local account kept neither of,
and it substituted a sentence ending "**nothing is uploaded, and none of the services below has been
contacted**".

That substitute is the sentence this round makes false, and flatly: the outbox uploads, and
`cypress-sync` has been contacted before anybody reads the screen. Meanwhile both of §2's promises
became the service's actual behavior — `POST /devices/claim` re-homes this device's rows onto the
account, and `photos.go` auto-approves a photograph from a signed-in account where a device's stays
`pending`, which *is* joining the tree's timeline. So the constant ended the way `BetaCapability`'s
own header says a capability constant should end: **by deletion, with the drawn copy returning**, not
by a flip.

**The residual, stated rather than left to be found.** §2's first clause is "They live on this phone
right now", and after this round they live on this phone *and* on the service, unattributed to any
account. It is the mocks' own sentence and it is far closer to true than what it replaced, so it is
drawn; whether it wants a word changed is the same owner question as (1) and belongs with it.

## 3. Screen 17 says "No connection." to somebody with four bars, and SCREENS.md names no sentence that would fix it

Review of PR #77 flagged this and it becomes live here. `OutboxFailureReason.sentence(for:)`
(`Cypress/Data/Outbox/OutboxViewState.swift`) answers **"No connection."** for any error outside the
`APIError` taxonomy, and that fallback now catches two things it did not before:

- **`SessionError`.** `SessionTransport` deliberately converts every credential failure into a
  `SessionError` rather than `APIError.unauthorized`, because `unauthorized.retryable` is `false` and
  a lapsed session would otherwise move the whole queue to `.failed` in one pass and print "Sign in
  to send this." to somebody who is signed in (spec §5.8, ERRATA E261 §3). That design is right and
  this entry does not question it. Its leftover is the *sentence*: a refused refresh on a good
  connection renders as "No connection."
- **`SessionError.malformedResponse`.** A 2xx body this client cannot decode is a shape mismatch, and
  it also renders as "No connection." This is not hypothetical — it is how the first draft of
  `DataLayerWiringTests.theSendPathCannotProduceARemoteSurface` went red, with a fixture whose error
  envelope was the wrong shape.

**What SCREENS.md offers: nothing.** Screen 17's section (`docs/distilled/SCREENS.md`) names no
per-cause sentence at all. Its whole failure vocabulary is a row sub-label (`upload failed twice`), a
header pill already overruled by E81, and the footnote promise — *"Nothing here disappears silently.
An item that cannot sync says so, says why, and waits for you."* The eight per-code sentences the app
draws are engineer-authored against BUILD-PLAN §6's list of **codes**, which carries no copy.

So there is no honest sentence to pick, and the footnote is the thing being broken: the item does
wait, and it does say why, and the why is false. This is the ask. Note that the *retry* behavior is
correct in every case above — an item outside the taxonomy stays alive on the backoff, which is
exactly what a session failure should do — so this is a copy defect and not a queue defect.

## 4. The 72 h photo grace window is documented on both sides and swept by nothing, and `PhotosForTree` does not filter on it

Found while establishing whether the photo half of the outbox could be given its second sink this
round (it could not — see the PR body). It is a service defect independent of that question.

`POST /photos/begin` inserts a `photos` row and returns a presigned `PUT`.
`POST /photos/{id}/received` sets `bytes_received_at`, which `store.MarkPhotoBytesReceived`'s own
comment calls "closing the 72 h grace window", and `PhotoUploadTicket.binaryGracePeriod` says the
same on the client. **Nothing collects the rows where that window stays open.** There is no sweeper
anywhere in `server/` — no cron, no ticker, no `DeleteExpired` — and
`server/internal/store/photos.go`'s `PhotosForTree` selects every row for a tree with no predicate on
`bytes_received_at` at all.

The consequence: a `begin` whose `PUT` never lands leaves a **permanent phantom photograph** on that
tree for every reader. `GET /trees/{id}` returns it, `RoutedAPI.treeProfile` merges it into the
photo series, and `photoData(id:)` hands back a presigned GET for a storage key holding nothing —
which the client correctly turns into a failed read, on a photograph the profile said was there.

Two independent repairs, and it wants both: filter `PhotosForTree` (and `reads.go`'s hero-photo
query) on `bytes_received_at IS NOT NULL OR created_at > now() - 72h`, so an in-flight upload is
still its own contributor's and an abandoned one is nobody's; and sweep the abandoned rows and their
storage keys, because a row nothing will ever fetch is still a row.

**This is also the reason the photo send sink is not in this round.** Any retry of a failed binary
send must call `POST /photos/begin` again — the route mints a fresh id per call and takes no
idempotency key — so every retry leaves an abandoned row behind, and with no sweeper each one is a
phantom photograph rather than a row that quietly expires. The design ERRATA **E264** assigns to its
own ticket therefore has a server prerequisite that E264 did not know about.
