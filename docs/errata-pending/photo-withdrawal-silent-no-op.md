# Errata pending: a photo withdrawal that withdrew nothing and said it had (server and client, 2026-09-28)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". It was found while fixing
report F30 on `fix/photo-identity-dedupe` (PR #194) and fixed in the same PR. The defect **shipped**:
it is live in production from the first build whose outbox sent photographs until this PR's server
half is deployed.

---

### E??? — `photo_withdrawal` named an id the service never issued, matched nothing, and answered `applied`

**What happened.** A person deletes a photograph on screen 20. The phone tombstones its row and
queues a `photo_withdrawal` whose `photoID` is the phone's own `photos.id`.
`store.withdrawPhoto` looked that id up as the service's own `photos.id`. The service mints that id
itself at `POST /photos/begin`, and the phone never keeps it, so the lookup found no row for any
photograph a phone had actually sent. Its first answer, *no row → success, changing nothing*, then
applied. As a result:

- screen 17 settled the row `done`, reading `Photo removed`;
- the photograph stayed `approved`, with `deleted_at` NULL;
- `GET /trees/{id}` kept listing it to every other device;
- `GET /photos/{id}` kept serving its bytes;
- on the contributor's own phone, `GET /trees/{id}` returned it as their own, so the photograph they
  had deleted came back onto their profile after the next refresh.

This is ERRATA **E280**'s failure: a service reporting a removal it did not perform. It was reached
by identity rather than by a missing `UPDATE`.

**Why no test saw it.** Every withdrawal test on the server named the service's own id
(`beginPhotoFor` returns `ticket.PhotoID`). That is the one id no client ever sends. The
"never held" case was justified by ERRATA E264 ("no photograph reaches this service"), and that
stopped being true when the send path shipped. The justification was not revisited, and every
withdrawal from then on landed in that arm. This is the "guards green while the defect is present"
family: the test's input was the thing that differed from production.

**The fix, in two halves, with no migration.**

1. *Server.* `withdrawPhoto` falls back to `withdrawPhotoByClientKey` when no row has the id. It
   reads every row carrying that `client_uuid` (migration 003) and tombstones only the rows the
   caller owns, using the same two columns as the lookup by id. If a live row carries the key and
   the caller owns none, the answer is `ErrNotOwned`, as the lookup by id already answered. Scoping
   the query to the caller instead would have turned that case back into a silent success. Since
   F30's fix, the phone's `photos.id` **is** the begin's `client_uuid`, so this covers every
   photograph sent from that build on.
2. *Client.* A photograph sent by build 77 or earlier has a local id unrelated to its key, and the
   key is gone from the phone (the `outbox_photos` row is deleted when the send completes). When a
   profile refresh has paired such a photograph with its service row unambiguously
   (`RoutedAPI.photoIdentityMatch`), the withdrawal names the service's `photo_id` instead, through
   `RoutedAPI.deletePhoto(id:)` and `LocalAPI.deletePhoto(id:servicePhotoID:)`.

**What the review of #194 changed.**

- *The pairing may only name a photograph that has left the phone (finding 1).* The review proved
  that pairing by framing and capture second, offered a photograph that had **not** been sent, could
  name the same account's other phone's photograph. The pair looked unambiguous because the unsent
  photograph has no copy on the service. Deleting the unsent one would then have withdrawn the other
  phone's photograph, and the service would have honored it, because the account owns it. The
  pairing is now offered only rows written by the outbox's apply with no send still owed
  (`ContributionStore.sentPhotoIDs`). That excludes the add-a-tree photograph, which is never sent.
- *A copy is the second its stamp names (finding 2).* The wire truncates to whole seconds, so a true
  copy is `0 ≤ local − service < 1`. The symmetric window paired the next second's photograph.
- *A withdrawal that arrives before its begin (finding 5).* The service answered it `applied`, with
  nothing to take down, and the later begin created a live row. A begin now looks for its owner's
  withdrawal of its key, and if it finds one the row is born deleted and the begin is refused as a
  replay after a withdrawal is (`photoWasWithdrawn`). The shipping client does not reach this order,
  so this is the service not relying on that.
- *A withdrawn photograph's copy is hidden only while its withdrawal is queued (finding 3, ruled by
  the orchestrator).* While a `photo_withdrawal` naming it is `pending`, its copy is hidden from its
  contributor, because the withdrawal is on its way. Once the service has answered it, a copy the
  service still serves **is still public**, and it shows on its contributor's profile again. That is
  deliberate. For every photograph in the open cases below, seeing it again is the only sign its
  contributor gets that it is still public. Deleting it again now works: the profile knows the
  service's id for a row it drew, and `RoutedAPI.deletePhoto(id:)` queues a withdrawal naming that
  id (`LocalAPI.withdrawServicePhoto`), which the service applies by id if the caller owns it. The
  same path lets a person delete their own photograph that another of their phones sent. The
  profile already offered that, through `deletable_photo_ids`, and the tap used to fail.

**What is still open.** These are earlier-build photographs whose withdrawal still names only the
local id and still withdraws nothing on the service:

- **Not refreshed in this process.** The pairing is kept in memory (`PhotoIdentityLedger`). Keeping
  it across launches needs a column, which is a migration.
- **Ambiguous.** Two photographs of one tree share a framing and a capture second: two photographs
  from one visit share their item's `createdAt`. Their service copies could pair either way round,
  and naming the wrong one would withdraw the photograph the person kept. Neither is named.
- **Already withdrawn before this build.** Their withdrawals were applied as no-ops and are `done`.
  Nothing re-sends them: RULINGS R77, and a re-send would be a backfill nobody ruled on. Those
  photographs remain public on the service, and the service alone cannot tell which ones they are.
  A `photo_withdrawal` contribution records only the phone's id and the tree, so an operator can
  find an owner who withdrew *a* photograph of a tree on which they still have live ones, but not
  *which* photograph. The capture time that would say which is on the contributor's phone, on the
  tombstoned row. Any repair needs a ruling before anyone runs it. What this PR does give these
  photographs is the finding-3 behavior above: once this build refreshes their tree, each one shows
  on its contributor's profile again, and deleting it there reaches the service.
- **A binary staged before the send path existed.** Its queue row was deleted at the apply
  (`sendable = 0`), so it reads as sent, although RULINGS R77 kept it on the phone, and it can be
  offered to the pairing. Telling the two apart needs a column.
