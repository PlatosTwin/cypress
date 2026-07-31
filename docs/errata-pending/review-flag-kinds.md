### `appears_dead` raised a flag nothing could ever resolve

Task #58. One defect with four surfaces, all of them downstream of the same shape: **the code that
raised a review flag switched over two cases, and the code that resolved one hard-coded a single
case.** Everything else here follows from that asymmetry, including the two things that were missing
rather than wrong.

---

**What was raised.** `ObservationStatus.reviewFlagKind` returned `.appearsDead` *and*
`.appearsRemoved`; `LocalAPI.apply` inserted a `review_flags` row for either; screen 05 drew
`Appears dead` and `Removed?` side by side with identical affordances. Two of the check-in card's
four status segments opened a review.

**What could be resolved.** One. `openRemovalReviews` named `.appearsRemoved` in its own body, and
`confirmRemoval` guarded `flag.kind == .appearsRemoved` before writing `.removed`. The You tab's
queue had one section and one verb.

So every `appears_dead` flag anybody has ever raised on this app went into a table no surface read,
and stayed `open` forever. Nothing was lost and nothing was corrupted — which is exactly why a green
suite never noticed. `ModerationTests` proved the whole loop end to end for `appears_removed` and
said nothing about the other half of the vocabulary the same enum offered.

This is RULINGS R12's consequence. E124-B built the local moderation route and discharged R12 for
`appears_removed`; the dead half was left where R12 found it.

**Two absences on the same fault line.** Neither is a separate mistake — both are what "nobody
followed those two segments past the tap" looks like from a different angle:

- `ObservationStatus.opensReviewFlag` was documented as "the two cases that trigger a confirmation
  dialog and a review flag" and **had no caller in shipping code at all** (only
  `SQLiteStoreTests.swift:135`). The flag half happened; the dialog half was documentation of a
  feature that did not exist, and screen 05 moved the segment on one tap with nothing asked.
- `ReviewFlag.Status.dismissed` has existed since the model was written and **nothing wrote it**. A
  lead who thought a report was wrong could only leave it open. A queue whose only verb is "agree"
  is not a review, and the list could only ever grow in one direction.

---

**Fixed by putting the two sides on one switch.**

`ReviewFlag.Kind.confirmedStatus` is the seam: `appears_removed` → `.removed`, `appears_dead` →
`.deadReported`, and nil for the three kinds that are not status claims. The raise and the resolve
both read it, so a kind that can be raised and not confirmed is now a compile error rather than a
flag that sits open forever. `openReviewFlags` takes `kinds:` and the queue asks for
`statusReviewKinds`, derived from the same switch. `confirmRemoval` became `confirmReview` and takes
the status off the flag; `dismissReview` is the second verb, writing `.dismissed` and **no status
override** — dismissing says the reported change did not happen, and `tree_status_overrides` must not
start carrying rows that mean "somebody looked".

**No migration and no new enum case.** `TreeStatus.deadReported` has existed since `Tree.swift` was
written — its own header records the BUILD-PLAN-over-PRODUCT decision that put it there — and the
`tree_status_overrides` table from AppSchema v7 already carries any `TreeStatus`. The dead path goes
through the seam E124-B built for removal, unchanged.

**A confirmed death is not a removal, and the app now says so on three surfaces.**
`TreeStatus.deadReported.acceptsNewContributions` is `true`, deliberately: a dead street tree is
still standing over a pavement, and reporting it is the single most useful thing a passer-by can do.
So it is *not* routed to screen 19. It keeps its profile, its REPORT and CARE cells and its pin, and
what changed is that all three stop being silent about it:

| surface | before | after |
| --- | --- | --- |
| profile | identical to a live tree with no check-ins | `DEAD` badge and a Callout: reported dead, a reviewer confirmed, still standing so still worth reporting |
| map pin | grey dot spoken as `Removed tree, memorial` | grey dot spoken as `Dead tree, still standing` |
| queue row | `Reported removed` / `Confirm removed` | `Reported dead` / `Confirm dead`, beside `Dismiss` |

The pin's *drawn* half is deliberately unchanged. `MapPin.Kind` is a closed catalogue whose sixth
entry took a ruling (R7), and whether a standing dead tree deserves its own drawn pin is a design
decision this errata has no standing to make. It is the same split E107 made for the vacant site: fix
the words, leave the drawing for whoever owns the catalogue. The badge borrows the removed pair's
grey for the same reason — the two badges never say the same word, and there is no fifth badge colour
to invent.

**Screen 05 says where a report goes.** Both flagging segments now draw
`This goes to a community reviewer to confirm. The city is not notified.`, and `opensReviewFlag` gates
it. The register is `AccountAskCopy.noticeUnavailable`'s — name what is true today, then end on the
plain limit. The temptation to imply otherwise is strongest exactly here, because somebody reporting
a dead tree is reasonably hoping an official will come; DECISIONS §3.3 forbids "sent to the city"
copy and R12 exists because that gap was noticed once already.

**And the moderation queue stopped claiming it from the other end.** `ModerationCopy.confirmMessage`
used to close on *"This is how the city record is corrected."* That is the forbidden claim in the
passive voice, on the one screen where a lead is most likely to believe it — confirming a flag writes
one row on this phone. Both kinds' messages now end on `The city is not notified.`

**`opensReviewFlag` was wired, not deleted.** The ruling allowed either. Wiring it, because the
property is right about the product: those two segments are the only ones on a 60-second card whose
effect leaves the phone and lands in front of another person, and "appears dead" is a claim worth a
second tap. `CheckInModel` holds the proposed status in `pendingStatus` and never touches the draft
until the dialog returns, so cancelling leaves the card exactly as it was — a dialog that backed out
onto the segment it had proposed would be worse than no dialog. The other two segments stay one tap:
`Declining` has no consequence outside this phone, and taxing the common path buys nothing.

**The harness grew a slot, and the awkwardness is the point.** `DebugDeepLink`'s standing rule is that
a case which writes persistent state must not write it onto a tree another case reads. `.memorial`
marches outward on its own because a removed tree drops out of every `standingTree` scan afterwards;
a tree marked dead **stays in**, because `deadReported.acceptsNewContributions` is `true`. So
`.deadProfile` needed its own slot (three quarters out, between `.measure`'s middle and the photo
cases' far end) or `.memorial` would have marked this very record removed on the next run —
photographing a memorial where the previous case had just proved a dead tree keeps its profile.
`.moderationReview` now seeds **both** kinds on two trees: a queue seeded with removals only would
photograph the exact state that hid this defect.

---

**Tests.** `ModerationTests` was parameterised over `ObservationStatus.allCases.filter(\.opensReviewFlag)`
rather than over a hand-written pair, so a third flagging segment added to the card cannot slip past
it. The role gate is now proven on the write for both roles × both kinds × both verbs — eight
refusals, each checked to leave the flag open and the tree unmoved. `ReviewFlagNoticeTests` covers
screen 05's dialog and the copy, asserting the city sentences as properties of the words rather than
as equalities, because the failure mode is somebody rewriting them warmly.

Every one of them was watched failing before it was believed. Restricting `openReviewFlags` back to
`[.appearsRemoved]`, pointing `appears_dead`'s `confirmedStatus` at `.removed`, and dropping
`dismissReview`'s role gate turned the suite red in exactly the places those three things are
watched; the same for `select(status:)`, the badge ordering, the pin label and the moderation copy.

**Two real fixes came out of doing that**, which is the argument for doing it at all:

- `openReviews()[0]` is how this suite reached the flag, and under the very defect being fixed the
  queue comes back empty. The subscript killed the test *process* — `Fatal error: Index out of
  range` — and xcodebuild then reported `Test run with 0 tests in 2 suites passed`. A crash is not a
  failure: it takes the rest of the run with it and reports as the wrong thing entirely, which on
  this project is the exact shape of a suite ratifying a defect. It is `#require` now.
- The pin-label override was written as "if the status is `deadReported`, say so", which quietly
  outranked DECISIONS §3.16. A community-added tree confirmed dead would have lost the community's
  words. It fires on the drawn memorial pin only, so the *lie* is fixed and the precedence is not
  widened — `Community-added tree` is incomplete, not untrue, and that is a different problem.

---

**Driven on the device, not inferred.** Screen 05: tapping `Appears dead` raises `Report this tree as
dead? / A community reviewer checks this before the tree's status changes. Nothing is sent to the
city.`; Cancel leaves the card on `Alive` with no notice line; `Report it` selects the segment and
draws the notice under it. The You tab, seeded with both kinds, drew `Reported dead · Confirm dead`
above `Reported removed · Confirm removed`, each with its own `Dismiss`. Confirming the dead one
resolved it out of the queue, and the tree behind it — Kwanzan Flowering Cherry, 50 Hancock St, a
real seed record, SF #238248 — then drew the `DEAD` badge, the `Confirmed dead:` Callout, a live
`Be the first to photograph this tree`, `Check in · under a minute`, and all four quad cells
including REPORT. Not screen 19.
