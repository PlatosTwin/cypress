### R?? — A record that never held a tree is withdrawn, not killed (task #125, delegated)

*Written under the delegated design authority for #125. `RULINGS R46` decided the kind and left
three questions open in its own words — "what the kind means, what raises it, and what confirming it
writes". This answers them, and refuses the answer R46 floated.*

R46 settled that "this tree does not exist at all" is its own `review_flags.kind`, `never_existed`,
and not a use of `.appearsRemoved`. AppSchema v14 widened the CHECK; `ReviewFlag.Kind` gained no
case, so the value was a reservation nothing could write. This is the rest of it.

---

#### The question R46 left open, and the answer it guessed at

R46 wrote: *"`TreeStatus.vacantSite` already exists and may be the truthful confirmed state, in which
case the kind belongs on the status seam and the existing queue rather than beside it."*

**It is not the truthful confirmed state, and the kind does not belong on the status seam.**

A vacant site is a planting *site* with its tree missing. R7 gave it a hollow ring rather than the
removed pin's grey dot precisely so the map would not say a tree had stood there; the drawing asserts
*a place a tree could go*. The records #125 exists for do not have one. R46's own motivating cases
are a row in the middle of a building, a duplicate two metres from another pin, and a community add
that was a mis-tap — and there is no planting site at any of them. Writing `vacantSite` would replace
one false assertion with a quieter one, which is the move R7 refused for the vacant site and R19
refused for the standing dead tree. It would be strange to make that argument three times and then
decline to make it a fourth in the case where the assertion is not merely imprecise but false.

The second reason is the seam. `ReviewFlag.Kind.confirmedStatus` is derived from `resolution`, and
`statusReviewKinds` is derived from `confirmedStatus != nil` — E170's property, that one exhaustive
switch serves both the raise and the resolve. Pointing `neverExisted` at any status is the one-line
change that makes the kind resolvable, and it would enrol record defects in the lead's *status*
queue, where a confirmation writes `tree_status_overrides`. E170's defect was a queue that could not
see half of what was raised; this would be the inverse and worse — the queue would look right while
the trees moved.

#### Decided

**Confirming a `never_existed` report withdraws the *record*. The `community_trees` row is
soft-deleted and `trees.status` is never touched.**

`ReviewFlag.Kind.Resolution` gains a fourth arm, `.recordWithdrawal`, beside `.status`,
`.speciesAssertion` and `.byHand`. `confirmedStatus` stays nil for it, `statusReviewKinds` does not
grow, and `recordReviewKinds` is derived from the same switch — R45's shape for the species seam,
applied a second time for the same reason.

`.byHand` was the other candidate and is refused. `.byHand` means nothing is written, and it fits the
two kinds that hold it: `removedButActive` is the weekly diff saying a person should look, and
`duplicateSuspected` has no surface raising it. A kind a *person* raises from a *screen* must have a
verb that closes it, or it is E170's defect with a politer name.

A soft delete rather than a `DELETE`, on two grounds. Every read in `CommunityTreeStore` already
filters `deleted_at IS NULL`, so one column takes the pin, the profile and the species routes away in
one write without a single reader learning a new rule. And the row survives: under D16 a confirmed
"this was never here" is a fact the merged national inventory wants — precisely the fact R46
distinguished from a dated lifecycle event — and an erased row cannot be published.

#### Community rows only, and the refusal is the substance rather than the shortfall

**A `never_existed` report against a city row is refused with `.forbidden`.**

A city row lives in the ATTACHed read-only seed. Nothing on this device can withdraw one, and there
is no suppression path parallel to `tree_status_overrides` for a row that should not be in the
inventory at all. So a report raised against a city row is a report nothing present can resolve —
which is the state E170 exists about, shipped deliberately. R45 refuses `flagWrongSpecies` on a city
row in the same words and for the same reason: *shipping the raise ahead of the read path would be
shipping it.*

This is the largest limit on #125 and it should be read as one. The owner's ask was about the map,
and the map is overwhelmingly the city's rows. What lands is the half that can be honestly closed.

**The other half is a ticket, and it is the same ticket R45 already named.** A community
counter-claim over an inventory row needs a suppression path parallel to `tree_status_overrides`,
and reading it back touches the map, the profile, the almanac and the export. R45 named it for
species; `never_existed` is its second customer, which is an argument for building it once rather
than for smuggling half of it in here.

#### Who reports and who resolves

**Everybody reports. Only a lead resolves.**

R45's arm 1 — "your own claim is yours to correct" — has no counterpart here, and the reason is R45's
own finding rather than a choice: **`community_trees` records no author at all.** No `user_id`, no
`device_id`, no owner column. So no record on this device is anybody's to take back, and R45's arm 3
applies verbatim — a record owned by nobody is nobody's to withdraw without asking.

The lead gate is `userRole.canConfirmReviewFlag` (moderator, admin, coordinator — DECISIONS §3.7),
the gate the status queue already uses, on the write, so a surface drawn in error cannot withdraw a
record. In the local beta the role is granted through the You tab's DEBUG affordance, which is how
every `appears_removed` flag is resolved today; this seam inherits that route rather than inventing
one.

Both verbs exist. `withdrawRecord` confirms, `dismissRecordReview` keeps the record — E170's
argument that a queue whose only verb is "agree" is not a review.

#### The surface

**The tree's own profile, under the species controls. No queue.**

R45's reason holds unchanged: the report is answered where the thing being disputed is, and a second
section in the You tab would be a moderation product. The three controls form a ladder down one
record — name what it is, say the name is wrong, say there is nothing here to name — and the last
rung belongs beside the first two rather than on a card of its own.

`RecordDefectOffer` carries the decision on the profile payload, `SpeciesCorrectionOffer`'s shape and
for its reason: the answer needs the viewer's role and an open-flag read, and a presentation holding
either would be holding something it cannot see. A city row is `.unavailable` rather than
`.reportable` — a control that exists only to be refused is worse than no control.

**Withdrawing closes the screen.** `LocalAPI.treeProfile` now refuses a withdrawn community row, so
the alternative is not a stale profile but a failure sentence reading "this tree could not be found"
at the person who just withdrew it. The view pops.

#### The copy, which had to be written against the build rather than against the architecture

The obvious sentence was the one two neighbouring surfaces already use — *"This goes to a community
reviewer. The city is not notified."* It is not available, and the reason arrived mid-ticket from the
owner.

**There is no contribution sync.** #158 is unbuilt and unscheduled; beta is about five people with no
accounts. The outbox drains through `APIOutboxTransport` into `LocalAPI`, which writes this phone's
own tables. Nothing uploads and nothing downloads anybody's rows. A report therefore reaches no other
reader, ever, during beta.

So *"this goes to a community reviewer"* names a destination the report does not arrive at, which is
structurally the sentence §3 constraint 3 forbids — D16(a) made the city version permanent — with a
different noun. The rule underneath both is that the app never says it did a thing it did not do.

The notice reads:

> This is kept on this phone and shows on this record. The city is not notified, and Cypress cannot
> yet carry a report to anybody else’s phone.

It says where the report stays and what it does there, then states the two limits plainly. E126 is
why the second half is said out loud rather than left as a silence for the reader to fill in.

The negation is spelled `The city is not notified` and **not** `Nothing is sent to the city`. The
first draft used the second, and the suite's own guard caught it: the guard is a substring check for
the forbidden claim, and a claim's negation contains the claim.

Two more words are chosen rather than defaulted. The control says **"Report that there is no tree
here"**, not "report this tree as missing" — *missing* is what a removal is, and the whole of R46 is
that the two must not be said with one word. The verb says **"Withdraw this record"**, not *delete*
(which would promise an erasure that does not happen) and not *remove* (which is
`TreeStatus.removed`'s word, and lending it to the one act that must never read as a removal would
undo R46 in the label).

#### What this deliberately does not build

Named so the next round does not read the absence as an oversight.

- **No queue, no reputation, no voting.** R45's list, unchanged, for R45's reasons. This is a report
  path, not a verification tier.
- **No withdrawal of a city row.** Above; it is a ticket.
- **Nothing through the outbox.** The flag is a local write, like `flagWrongSpecies`. When
  `POST /trees/{id}/review-flags` exists the chain is the right shape to send.
- **No `duplicate_suspected` route.** A duplicate is one of R46's motivating cases and it arrives
  here as "there is no tree at *this* record", which is true of the duplicate pin. Giving
  `duplicateSuspected` its own raise as well would be two controls for one observation; it stays
  `.byHand` and unraised.

#### The pending errata beside this

`docs/errata-pending/community-note-write-still-blocked.md` — why **#120** did not land: the
retracted schema claim was retracted correctly and a different, live schema blocker is underneath it.

`docs/errata-pending/report-destination-copy-outruns-the-build.md` — two shipped sentences make the
promise this ruling refused to make, on screen 05 and on the species control. Flagged, not changed:
they are R45's and E170's own words and belong to whoever owns those.
