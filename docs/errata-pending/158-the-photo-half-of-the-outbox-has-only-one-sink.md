### The photo half of the outbox has only one sink, and the reason is a file that no longer exists (task #158)

Ticket #158 step 1 splits the outbox drain into an **apply** sink and a **send** sink (RULINGS R72
§1, `docs/design-proposals/2026-08-09-task158-live-layer.md` §2.1 and §6.1). The JSON half now has
both. The **photo binaries have only the apply sink**, and this entry is why, because the omission
is the kind that looks like an oversight and would be quietly inherited otherwise.

#### The fact

`OutboxQueue.drain` hands each `OutboxPhoto` to the apply sink, which in the shipping composition
root is `APIOutboxTransport` over `LocalAPI`. `LocalAPI.uploadPhoto` (`Cypress/Data/API/LocalAPI.swift`)
strips the metadata out of the staged file into the app container and then **removes the source**:

```swift
try PhotoBinary.writeStrippingMetadata(from: source, to: ticket.destination)
try manager.removeItem(at: source)
```

So by the moment a send sink could run, there is nothing at `OutboxPhoto.path` to send. And the
obvious repair — keep the staged file until both sinks have taken it — does not work either:
`LocalAPI.beginPhotoUpload` inserts a **new `photos` row per call**, so re-running the apply half
after a send failure would write the photograph twice. The drain's zero-duplicates property is
exactly what that would break.

Sending binaries therefore needs three things this step does not have: a source the remote can still
read after ingest (the container copy, keyed by `photos.id`, which the outbox row does not carry),
per-photo completion tracking rather than the per-row flag pair `AppSchema` v15 adds, and a decision
about whether a binary that failed to send should hold its row out of `done`. That is a design, a
migration and a ticket of its own.

#### What was done about it instead of a comment

`OutboxSendSink` (`Cypress/Data/Outbox/OutboxQueue.swift`) declares `sync` and **no** photo method.
A future author wiring a real server has to add one; they cannot inherit a silent no-op. That choice
is the direct lesson of ERRATA **E125**, where two methods declared only in a protocol extension
dispatched statically, every screen reached the extension's `throw`, and the whole suite was green
while no photograph rendered anywhere in the app. A protocol requirement that does not exist is
loud. A protocol requirement satisfied by a default that returns nothing is not.

The acceptance criterion R72 restates in the owner's words — *"when I add a photo on my device, the
photo propagates to all other users"* — is therefore **not** satisfied by step 1, and step 1 does not
claim it is. Step 1 is the seam: the local write is now separable from the send, which is the thing
that had to be true before anything could be pointed at a server at all.

#### The related fact, worth keeping beside it

`markDoneIfComplete` takes `requiringRemoteSend:` as a parameter rather than reading a column,
because whether a send is owed is a property of the composition root and not of the row. v15's
`done` CHECK deliberately does not name `remote_sent`: every outbox row on every installed build is
locally applied and has never been sent anywhere, so a `done` predicate requiring a send would have
made the migration reject the rows it was migrating, and would have stranded every queued
contribution on every phone until a server existed.
