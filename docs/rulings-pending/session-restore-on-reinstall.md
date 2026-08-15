# Unnumbered — a surviving account session restores; a surviving device credential does not

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Owner ruling 5 of 2026-08-14, implemented on `feat/session-restore`.

---

## The question

On iOS the Keychain survives app deletion. The app's SQLite database does not — it lives in the
container. So a reinstall pairs *surviving credentials* with a *fresh, empty database*, and the app
has to decide what a surviving credential means.

It was asked twice, because there are two credentials.

## The two answers, which are opposite on purpose

**A surviving device credential reads as no credential at all** (PR #81, the errata entry
`158-the-keychain-outlived-the-database.md`). The token is live and the service accepts it, but it
resolves to the `devices` row of an installation that no longer exists; every item the phone sends
names the new installation, and `applyOne` refuses all of them, permanently. The credential is
discarded and the installation re-registers.

**A surviving account session restores, silently.** The app boots signed in and the local account
state is rebuilt.

The recommendation on the table was to discard the session — symmetry with the device arm, and the
argument that a phone which silently resumes somebody's account after a delete-and-reinstall is
doing something the person did not ask for. The owner ruled the other way.

### Why the two differ, stated so the next reader does not "fix" the asymmetry

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

## What the ruling costs, and what it does not

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

## The rule the ruling turned into, which runs in both directions

> **`app_state.current_user_id` mirrors the Keychain session. The session is the authority.**

The forward direction is the restore. The reverse direction is the refusal: when the service refuses
a surviving session — a revoked family, a deleted account, sixty days without a launch — the session
layer already discards it, and the local half has to follow, or the app draws an account with no
credential behind it. That is the same defect as the first one with the halves swapped, and the
ruling is not honored by fixing only one of them.

## The input that is not about reinstalls at all

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

## What the ruling made mandatory elsewhere

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
