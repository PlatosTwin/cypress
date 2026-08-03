# R— (pending) — a species claim is corrected by whoever made it; everybody else reports it

Raised by tasks **#86** ("a species claim cannot be corrected once made") and **#124** ("flag a
manually-added tree's species as wrong"), which are one question asked from two sides. Open since
**#15** and **#58**. R19's precedent puts an answer of this kind in a ruling rather than an errata:
nothing here is a defect being repaired, it is a rule being chosen, and a rule chosen inside a bug
fix is a rule nobody reviewed.

The question: **who may supersede whose species assertion, with no moderator present?**

---

## What was actually true before this round, and what was not

Verified against the code rather than the tickets, because two premises in these four tickets did
not survive the check.

- `species_assertions` existed **only in the read-only bundled seed** (`Tools/build_seed.py`), with
  the city's one `city_import` row per tree. `AppSchema` had no copy. That absence, not a missing
  screen, is why `SpeciesClaim` refuses a correction: there was nowhere to put one.
- The only writable species anywhere was `community_trees.species_current`, a bare TEXT column with
  no foreign key available to it, and the only edit to it that needs no history is the one where
  there is nothing to supersede. Hence `LocalAPI.claimSpecies`' two refusals — community rows only,
  first claim wins — the second of them written into the SQL as `WHERE species_current IS NULL`, so
  that two callers cannot both see NULL and the second one win.
- `ReviewFlag.Kind.wrongSpecies` has existed in the enum and in the `review_flags` CHECK since they
  were written, and **nothing raised it and nothing could resolve it**. `confirmedStatus` returns
  nil for it, so `confirmReview` and `dismissReview` throw `.validationFailed`;
  `ModerationTests` asserts exactly that. The vocabulary was there and the loop was not.
- **`community_trees` records no author at all** — no `user_id`, no `device_id`, no `client_uuid`
  owner. `TreeProfilePresentation.speciesNamedByContributor` says "a contributor", not "the
  contributor", and says why: the record cannot name which person. So on the day this ruling is
  written, **no species claim on this device is attributable to anybody**.

That last fact is the ruling's hinge and it is not in any ticket.

---

## Decided

**An assertion may be superseded without review only by the identity that made it. Every other
correction is a claim against somebody else's statement, and it is recorded as one — a
`wrong_species` review flag — never as a silent overwrite.**

Three arms, and the third is the one that pays for the first two.

### 1. Your own claim is yours to correct, with no moderator, for ever (#86)

`tree_names`' rule — "one active name per tree; first namer wins" (BUILD-PLAN §4, binding through
D15) — is the precedent `SpeciesClaim` reached for, and it was reached for slightly wrongly. That
rule exists to stop one contributor discarding another's statement. Where the two are the same
person there is no other statement to protect, and refusing is not protection, it is a refusal to
let somebody admit a mistake about a tree they were standing in front of.

Identity is `Attribution`: the signed-in account when there is one, this device otherwise (D9). Both
arms, because on this app an anonymous contributor is a real contributor and the account arrives at
the third save. The predicate is `ContributionOwner.isOwned(by:)`, which is `PhotoOwner`'s, already
carrying "delete your own photograph" — one predicate for "this record is mine to act on", not two
that will drift.

Nothing is overwritten even here. The claim keeps its row, gains `superseded_by`, and the correction
is appended. The history is what `species_assertions` is for, and a self-correction is history like
any other.

### 2. Somebody else's claim is not yours to overwrite, with or without a moderator (#124)

You report it. `flagWrongSpecies` raises a `wrong_species` flag and changes nothing else:
`species_current` still says what the namer said, because a report is a disagreement on the record
and not a decision. A person who thinks the species is wrong now has a move that is neither "shrug"
nor "overwrite a stranger", which is what #124 asked for.

Refused when the claim is your own — you correct it, and a screen offering both would be offering a
worse version of the same act. Refused when a report is already open: BUILD-PLAN §6's "two offline
users flagging the same tree produce two flags on one thread, not a conflict" governs the **sync
merge** between devices that could not see each other, and this is a local write by somebody looking
at the open report on their screen.

### 3. A claim owned by **nobody** is nobody's to overwrite either

This is the arm the migration forces and the one worth arguing.

Every species claimed before AppSchema v14 has no recorded author, because `community_trees` never
had a column for one. The v14 backfill could have written this device's id into those rows — every
community tree in the database really was added on this phone, since `LocalAPI.addTree` is the only
writer and nothing syncs anyone else's rows down — and AppSchema v12's backfill reasoned in exactly
that way for `photos`.

It is refused here, and the difference between the two cases is the whole of it. v12 was retro-fitting
who *took a photograph*; being wrong over-attributes a JPEG on the owner's own screen. This column
decides **who may overwrite somebody's statement without asking**, and a claim attributed to this
device by assumption hands that authority to whoever is holding the phone. The honest value is the
one the database can support, and the database supports "unknown".

So a pre-v14 claim is `.nobody`'s, `isOwned(by:)` is false for everybody — the same answer it already
gives for a photograph whose author deleted their account — and correcting one goes through the
report route. The cost is real and small: a handful of beta rows lose the one-tap fix and keep a
two-tap one. The alternative was to write a fact the record does not hold.

### Resolution: correcting the species **is** confirming the report

There is no second verb to forget. `correctSpecies` appends the correction and moves any open
`wrong_species` flag on that tree to `confirmed`, in one transaction. `dismissSpeciesReview` is the
other half — the report answered by leaving the species alone, nothing appended, on E170's argument
that a queue whose only verb is "agree" is not a review.

Who may answer a report:

- **a lead** (`canConfirmReviewFlag`: moderator, admin, coordinator — DECISIONS §3.7), and for
  `correctSpecies` **only in answer to a report that exists**. The role is authority to resolve
  somebody's report, not a licence to rewrite any species at will. A lead with an opinion and no
  report in front of them is a contributor and takes arm 1's route;
- **the author of the disputed claim**, for both verbs. This is what keeps the loop closed on a
  phone with no lead on it. Without it, "with no moderator present" would have an answer this
  project has already paid for once: a kind that can be raised and never resolved (E170).

"No moderator present" is otherwise not a special case. The local beta grants the lead role through
the You tab's DEBUG affordance, which is how every `appears_removed` flag is resolved today; this
seam inherits that route rather than inventing one.

---

## What this deliberately does not build

Named so the next round does not read the absence as an oversight.

- **No queue.** The report is answered on the tree's own profile, where the species is. A second
  section in the You tab would be a moderation product, and `openReviews` serves
  `statusReviewKinds` — deriving it from `confirmedStatus != nil`, which is nil for `wrongSpecies`
  and must stay nil.
- **No reputation, no voting, no confidence weighting.** `confidence` is a column because BUILD-PLAN
  §4 has one; nothing on device writes it. A rule that counted agreements would need a model of who
  is agreeing, and this is a correction path, not a verification tier (C-M5 is Phase 2, DECISIONS
  §2.4).
- **No correction of a city row's species.** `claimSpecies` already refuses one with `.forbidden`
  and `correctSpecies` refuses it the same way. A community counter-claim over an inventory row is
  what D16 actually wants — the community layered on the merged national inventory — but reading it
  back needs a species-override path parallel to `tree_status_overrides`, touching the map, the
  profile, the almanac and the export. That is a ticket, not a clause. **Raising `wrong_species` on
  a city row is refused too, and refused deliberately**: a report nothing can resolve is the E170
  defect, and shipping the raise ahead of the read path would be shipping it.
- **Nothing goes through the outbox.** `claimSpecies` never did; assertions follow it. When
  `POST /trees/{id}/species-assertions` exists, the chain is already the right shape to send.

---

## The seam, and why it is beside E170's rather than inside it

`ReviewFlag.Kind` now answers `resolution` — `.status(TreeStatus)`, `.speciesAssertion`, or
`.byHand` — and `confirmedStatus` is derived from it instead of switching a second time.
`statusReviewKinds` is unchanged and still derived from `confirmedStatus != nil`, so the lead queue
does not gain a species report, and `speciesReviewKinds` is derived from the same switch for the
seam that does serve it.

E170's property is preserved exactly: one exhaustive switch that both the raise and the resolve
read, so a kind that can be raised and not resolved is a compile error. What is *not* done is the
tempting one-liner — pointing `wrongSpecies.confirmedStatus` at some status to make it resolvable.
Confirming a wrong-species report must never write `trees.status`. A species correction that quietly
marked a tree removed would not be a repeat of E170; it would be the worse version of it, because
the queue would look right while the trees moved.
