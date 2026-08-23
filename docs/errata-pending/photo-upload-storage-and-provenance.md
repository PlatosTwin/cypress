# Two facts found wiring `photo_withdrawal`, both about what happens to a photograph's *bytes*

Unnumbered, per CLAUDE.md "Numbering and shared files". Task: the E264 photo-upload round.
Neither of these is the upload itself, which is stopped on an owner decision — both are things
that are true about the code as it stands and would have been inherited silently.

## 1 · Nothing in `server/` ever deletes an object from the bucket, and a tombstone is not a deletion

`DeletePhotoByContributor`, the operator takedown `RejectPhoto`, and the sync-path
`withdrawPhoto` this round added all do the same thing to the bytes: **nothing**. They write
`photos.deleted_at` or move `moderation_state`, and `storage_key` keeps naming an object that is
still in the bucket. Grepped for and absent across the whole service: any `DeleteObject`, any
presigned DELETE, any sweeper. The client's own `deletePhoto` nulls `storage_key`; the server's
does not.

Through the API this is currently harmless and deliberate-looking — `photoData` evaluates
visibility before it presigns, so a tombstoned photograph gets no URL minted for it — and a
soft delete that keeps the row is the house verb. **The harm is entirely a property of which
bucket the object is in**, which is the decision this round stopped on:

- On a **private** bucket, "no URL is minted" is the whole story and the orphaned object is a
  storage-cost and retention question, not a privacy one.
- On **`cypress-cities`, which is public-read**, it is not. That bucket serves anonymous reads
  for every key on its dedicated domain (`server/README.md` records this, measured 2026-08-01).
  The key is `photos/<photo-uuid>.jpg` and the uuid travels to every device that reads the tree
  profile. So a photograph put there would be **anonymously fetchable by uuid, bypassing
  `photoData`'s visibility check entirely — before deletion, after deletion, and after an
  operator takedown**. R72 ruling 5's "the way down ships with the way up" would be false: the
  way down would remove the photograph from the app and from nothing else.

This is why the bucket is not a deployment detail that can be settled later by setting
`BUCKET_NAME`. `presign.go` says whether photographs share the cities bucket "is a deployment
decision, taken with the owner"; the point recorded here is that one of the two answers also
requires code that does not exist — object deletion, and a sweeper for the 72 h grace window
that `bytes_received_at` already tracks and nothing collects.

**The account purge is already correct at the row level and cannot be correct at the byte level.**
Checked rather than assumed: `Store.Anonymize`'s two doors both handle photographs, and both write
`UPDATE photos SET deleted_at = …, user_id = NULL, anonymized_at = …` — including
`EraseEverything`, which `DELETE`s contributions outright. So the deletion round's obligation on
`photos` rows is discharged and does not need re-building.

What no door does — because no code anywhere does it — is remove the object. **"Erase everything"
does not erase the photograph's bytes**, and on a public-read bucket those bytes stay anonymously
fetchable by uuid after the account is gone. That is the sharpest form of the decision in this
section, and it is the only part of the purge that is still owed. The enumeration a byte-purge
needs is already there — every `storage_key` for a user is one indexed query on `photos.user_id` —
so what is missing is the delete, not the query, and not the schema.

## 2 · The client can delete a photograph the server will refuse to withdraw, and the two rules cannot currently agree

RULINGS **R82** gave the client's removal predicate a third arm, `taken_on_device`: a photograph
this installation took stays this installation's to unmake whatever account holds it. That arm is
the repair for E277 and it is correct.

The server's `photos` table has `user_id` and `device_id` and **no provenance column**
(`001_initial.sql`). So the two predicates are not the same rule and cannot be made the same rule
without a migration nobody has ruled on:

| | client (R82) | server |
|---|---|---|
| owned by the signed-in account | deletable | withdrawable |
| owned by this device | deletable | withdrawable |
| taken on this installation, owned by an account not signed in | **deletable** | **refused** |

The third row is exactly E277's stranded photograph — reachable, not theoretical, and the case
R82 exists to fix. Locally it is deleted; the withdrawal reaches `POST /sync` and comes back
`forbidden`, which screen 17 draws as a terminal failure.

**That refusal is the deliberate answer of the two available, not the right answer.** The
alternative — treating "not this identity's" as a quiet success, the way `DeletePhotoByContributor`
collapses it into `ErrNotFound` so a refusal cannot confirm a row exists — would tell the
contributor "Photo removed" while the service kept serving the bytes to everybody else, which is
ERRATA **E280** precisely. Given a choice between a visible wrong answer and an invisible one,
this round took the visible one and recorded it here.

Closing it properly is a decision with two candidates, and neither is this round's to take:
give the server a provenance column so it can evaluate R82's third arm, or rule that the account
arm is the only one that crosses the network and give screen 17 a sentence for a local-only
deletion. The second needs new copy on a shipped screen, which is DECISIONS constraint 21.

### 2a · The order of the two checks inside `withdrawPhoto`, and why it stays

`withdrawPhoto` tests `deleted_at` **before** it tests ownership, so once a photograph is tombstoned
the ownership gate is never consulted. #113's review measured the consequence: a stranger's
withdrawal of somebody else's already-tombstoned photograph answers `applied`, and a `contributions`
row is recorded saying that device withdrew it. In a codebase where "the contribution row *is* the
record" is load-bearing, that deserves to be written down rather than left as an accident of
statement order.

**Ruled: the order stays** (orchestrator, under overnight authority, on the review's N1).

Swapping the two checks is not a free win, and the case it breaks is the legitimate one. After
`Anonymize` runs, an account's photographs have `user_id = NULL` — the leaving door's whole promise.
A withdrawal that account queued *before* deleting is still in the queue and still due to drain, and
under ownership-first it would meet a row it no longer owns and be told `forbidden`: a permanent red
row on screen 17, shown to the one person unambiguously entitled to that deletion, for doing it in
an order the app itself supports.

What the current order costs is bounded and quiet by comparison. The stranger's `applied` is true in
every respect a client can observe — the photograph is genuinely not served, to them or to anyone —
and what it leaves behind is a no-op contribution row about an act that changed nothing. One side of
the trade is a real person losing a real deletion; the other is a spurious row in a table nothing
consults for authorization. The order is chosen for the first.

Latent today: no photograph reaches the service, so no withdrawal can be refused for this reason
yet. It becomes reachable on the first day uploads work, which is why it is written down now.
