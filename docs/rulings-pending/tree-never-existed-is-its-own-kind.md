# R— (pending) — "this tree does not exist at all" is its own review kind, not a removal

Decided for task **#125**, which asked only for the decision this round; #125's surface and its
resolution path land later. Nothing was built here beyond one string in a CHECK constraint that
AppSchema v14 was rebuilding anyway.

**Decided: a new `review_flags.kind` value, `never_existed`. It does not reuse `.appearsRemoved`.**

## Why not reuse it

Because of what confirming `.appearsRemoved` *writes*. `ReviewFlag.Kind.confirmedStatus` maps it to
`TreeStatus.removed`, and this product has settled what that means: `acceptsNewContributions` goes
false, the profile becomes a memorial record (screen 19), and the map pin is spoken as "Removed
tree, memorial" (E170, R19). A record that never had a tree behind it would get a memorial page for
a tree that never lived.

That is the map asserting something untrue, which is the argument R7 made when it refused to let the
vacant site borrow `.removed`'s drawing, and the argument R19 restated for the standing dead tree.
The same argument decides this one; it would be strange to make it twice and then not make it a
third time in the case where the assertion is not merely imprecise but false.

The second reason is downstream. D16 makes the merged national inventory the product rather than a
seed-building convenience, and `removed` and `never_existed` are different facts to publish into it:
one is a lifecycle event that happened on a date, the other is a row that should not be in the
inventory. A consumer that cannot tell them apart mis-states a city's history, and the whole point of
the merged table is that it does not.

## The argument against, and why it loses

A reporter standing at the site often cannot tell "the tree is gone" from "there was never a tree
here", and asking people to distinguish what they cannot observe is the mistake D3 was written about.

It loses because the cases that motivate #125 are the ones where the reporter *can* tell: a record in
the middle of a building, a duplicate two metres from another pin, a community add that was a
mis-tap. A stump, an empty basin, fresh cut — that is a removal, and screen 05 already offers it. The
two are distinguishable exactly where it matters, and where they are not, a reporter picks "removed"
and is right often enough that nothing is lost.

## What landed, and what did not

Only the CHECK value, in AppSchema v14's rebuild of `review_flags`. SQLite cannot widen a CHECK in
place, so the alternative was an entire migration of its own for one string.

`ReviewFlag.Kind` gains **no case**. #125 owns what the kind means, what raises it, and what
confirming it writes — which is a real open question, since `TreeStatus.vacantSite` already exists
and may be the truthful confirmed state, in which case the kind belongs on the status seam and the
existing queue rather than beside it. Until #125 lands, nothing can write `never_existed`: the store
binds `Kind.rawValue` and there is no case to bind. The widened CHECK is a reservation, not a
reachable state, and `ReviewFlagKindTests` asserts both halves — that the column accepts the value
and that the enum does not yet offer it.
