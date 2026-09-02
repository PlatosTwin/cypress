# The heart answers from the phone (amends R2)

**Ruled by the owner, 2026-09-02. Settled — this is recorded, not reopened.**

## The finding

R2 gave C8's first cell an on-state and made it a toggle, and in doing so made the control's state a
fact **read** from the store rather than one remembered from the last tap. The code's paraphrase of
that is "the heart re-reads after every write" (`ProfileFavoriteWriter.storedState`), and the re-read
went to `RoutedAPI.isFavorite`, which was remote-first: it asked the service and fell back to the
phone.

So a round trip sat between a finger and the control settling. `TreeProfileModel.write()` paints the
tap optimistically, calls the writer, and then re-reads — and on an unreachable host that re-read
spent the whole of `URLSession`'s failure path before the heart came to rest, with nothing
configuring a timeout. The one screen where R2's whole point is that the control ends up agreeing
with what is stored was the screen that waited longest to find out.

This is the same defect the owner ruled on for My Grove on 2026-09-01, on a control rather than a
tab: a screen paints from the phone and merges the account's half when it arrives.

## The ruling

**Favorites go local-first. The tap and the read answer from the phone instantly. The R2 server
re-read still happens, and reconciles in the background instead of blocking the UI.**

`RoutedAPI.isFavorite(treeID:)` is now the phone's answer and records nothing in the read log — nil
is "the service was not consulted", which is what happened. `RoutedAPI.reconciledIsFavorite(treeID:)`
is the read that reaches the service, delivered behind the painted control, and it keeps the
old method's ordering exactly: the service wins when it answers, the phone answers otherwise, and
the outcome is recorded.

## What this amends, and what it leaves alone

It amends R2 in **where the answer comes from first**, and in nothing else. R2's substance is that
the heart is read rather than remembered, and that a write which did not land puts the control back.
Both still hold:

- The phone **is** the store R2 means. `LocalAPI.isFavorite` reads both ownership arms — this
  device's rows and the account's (E89) — which is the question the heart asks.
- `OutboxQueue.pendingFavoriteState` still answers ahead of it (#167). A toggle that is enqueued and
  not yet drained is the contributor's last word, and it still wins.
- A terminally failed toggle still falls through to the table, so the heart still goes back where the
  write did not land — R2's one required revert.

**The cross-device fact is not given up, only deferred.** A favorite set on another phone still
reaches this one; it arrives a beat after the paint rather than in front of it.

## The one thing that had to be added rather than moved

A reconcile that skipped the outbox would answer with the state *before* the tap — the service has
not heard the enqueued toggle yet — and would take the heart back off over a favorite the reader had
just set. That is the "it makes the user think their favoriting action got undone" report of #139,
#153 and #167, arriving from the one direction those three tickets did not close.

So `ProfileFavoriteWriter.reconciledState` asks the queue first and **declines to answer at all**
while the queue holds a toggle. Nil there means "nothing for the heart to learn", which is also what
a gate-shut build answers, and `TreeProfileModel` reads both as leave-the-control-alone.
`ClassRLocalFirstTests.theReconcileDefersToAPendingToggle` is that rule with its calibration: the
same writer with an empty queue must answer, or the deferral would be true because nothing ever
answers.

E184's tap counter is unchanged and still applies to the reconcile, which is now the slowest read on
the screen and therefore the one most likely to be holding a stale answer when a finger arrives.
