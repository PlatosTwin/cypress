# Rulings pending — community trees C1, made by the author under the brief (2026-10-01)

Unnumbered, per CLAUDE.md "Numbering and shared files". Each is the authoring agent's call, for the
orchestrator or owner to confirm or reverse. No code comment cites this filename.

---

### R??? — `tree_withdrawal` is reserved in the queue's vocabulary and has no verb yet

The service accepts `tree_withdrawal` (decision 8) and its Go guard expects a Swift `treeWithdrawal`
case. `outbox.kind`'s CHECK admits the value in v23 so that adding the verb later is not another
table rebuild, but C1 adds **no `OutboxItem.Kind` case and no verb**. The open question is the one the
verb has to answer: the service refuses a withdrawal once another identity has built on the tree
(`othersHaveBuiltOn`) and answers `conflict` after the phone has soft-deleted it locally, so whether
the phone withdraws first and reconciles, or waits for the answer, is a product call. Not made here.

### R??? — Every tree added before v23 has an adder of nobody, and a root position owned by nobody

The phone never recorded who added a tree. The migration declines to guess (R45 arm 3): the backfilled
root of each existing tree is owned by nobody, so nobody can move those pins, and the service agrees —
a tree it holds with no adder answers `forbidden` to everybody.

### R??? — Others' trees get no species, report, or dispute control, and the offers say so

The orchestrator's ruling "Others' trees: no species/report/dispute controls this round" is implemented
at the profile: for a tree that is only in the cache, `speciesCorrection` and `recordDefect` are
`.unavailable`, and `claimSpecies`, `correctSpecies`, `flagWrongSpecies` and `flagNeverExisted` keep
answering `notFound` for it (they read only trees this phone added). `correctLocation` answers
`forbidden` for a cached or city tree, matching `claimSpecies`'s distinction between "real and not
yours" and "no such tree".

### R??? — `OutboxPresentation` labels a `location_correction` "Location correction"

**NOT SPECIFIED** in SCREENS.md (constraint 21). The label is provisional and appears only on the
sync-status screen's row for a queued move. C3 owns the wording; the move has no UI of its own in C1.

### R??? — A pin move has no distance bound

`correctLocation` applies the 10 m dedupe against every other tree and nothing else. How far a pin may
move, and from where, is C3's question to the owner; the service applies no bound either.
