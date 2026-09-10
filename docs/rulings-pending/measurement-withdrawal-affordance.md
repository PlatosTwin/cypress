# Rulings pending — withdrawing a reading, as built (F27, 2026-09-09)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge. Nothing in `Cypress/`, `CypressTests/` or `CypressUITests/` cites this filename —
the code comments name the report (F27) and the rules they turn on.

**This is the implementation half of the entry in `measurements-round.md` titled "Withdrawing a
measurement: the design, and why no code ships with it".** That entry was written blocked on a
writable-schema migration its round was not authorized to write. The migration seat was granted for
this round, `AppSchema` v21 is written, and the design it described is built. What follows is only
the decisions the design left open, plus the two places the implementation departed from it and why.

---

### R??? — Screen 11's withdraw control, and the three questions the design did not answer

**Date:** 2026-09-09. **Proposed by:** this branch, implementing F27. **Status:** awaiting the owner.

#### What was already decided and is not revisited here

The blocked entry ruled the shape: a new `OutboxItem.Kind`, a `MeasurementWithdrawal` payload beside
`PhotoWithdrawal`, `LocalAPI.withdrawMeasurement(id:)` tombstoning and queueing in one transaction,
a row-level affordance on screen 11's growth log in `TreePhotosView`'s idiom, and a row title on
screen 17. All of that is built as written, including both of its refusals — the payload
discriminator and the local-only ship — which it argued at length and which nothing here weakens.

#### 1. The copy — **NOT SPECIFIED**, proposed under DECISIONS constraint 21

SCREENS.md 11 §5 draws a log row as value · method · role · date, and no control on it. So every
string is this branch's, written in the shape of screen 20's deletion copy, clause for clause, with
the consequence swapped for the one a reading has:

> **Withdraw this reading?**
> The reading comes off the growth chart and out of the record on this phone. This cannot be undone.
> *(and, on the last reading of its kind)* It is the only Trunk diameter · DBH reading on this tree,
> so that chart goes with it.
> **Withdraw reading** · **Keep it**

- **A question in the title**, because the tap that opened the dialog withdrew nothing. Screen 20's
  reason, in the same words.
- **The chart is named first**, which is what the blocked entry asked for: "copy would need to say
  what withdrawal does to a chart, which the photo copy has no equivalent of".
- **"on this phone"**, exactly as screen 20 says it, and for the harder of that clause's two
  reasons. v21 *does* give the withdrawal a queue row, so unlike a photo deletion this act can leave
  the device — but only once a drain reaches a service, and E212 records two shipped sentences that
  promised a reader somebody was at the other end. The screen claims what it has done; screen 17 is
  where the queue speaks for itself.
- **The second sentence only for the last of its kind**, because a chart card really does disappear
  then (`chart(for:)` draws none for a kind with no point) and that is a visible change to the
  screen the reader is standing on. Read before the tap off the loaded profile, and reported after
  it by `WithdrawnMeasurement.leftTheKindWithNoReading`; one test asserts both halves so the promise
  and the outcome cannot drift.
- **The verb is on the button.** E136's rule for the account sheet, applied to a smaller thing.

#### 2. The control is **not** gated on `acceptsNewContributions` — a departure, argued

The blocked entry did not reach this and the obvious answer is wrong. R15's `Add a reading` link one
block down *is* gated that way (E95): adding a reading to a record the city has closed is a new
contribution to a tree that is gone. **Taking one back is not a contribution at all** — it is the
person unmaking their own — and the app already settles the question one table over: screen 20 draws
its delete on a photograph of a removed tree, gated on `deletablePhotoIDs` and nothing else. A
memorial's readings are still readings, and a mistyped one on a tree that has since been felled is
exactly the reading somebody would want to withdraw. Gating it would make the withdrawal one-way for
anybody whose tree was later removed, which is E89's argument about the favorite heart in another
costume.

#### 3. The trash mark is `PhotoTrashGlyph`, reused rather than redrawn — a departure, argued

`PhotoGlyphs.swift` said "no screen outside Photos uses them". Screen 11 now does. The alternatives
were both worse:

- **Redrawing a trash can in `Features/GrowthHistory`** is two sets of coordinates for one mark.
  E163 is the errata about two marks in this app that drifted; four subpaths of hand-authored
  geometry is exactly the thing not to have twice.
- **Renaming it, or moving it into `DesignSystem/Components`**, is a rename of a shared identifier,
  which CLAUDE.md says breaks every other live branch even when correctly scoped. Three other
  branches were open.

So the mark is reused, the file's own locality sentence is corrected to say screen 11 draws it too,
and **the rename is left for a quiet round** — it is on the chip backlog rather than in this diff.
A reviewer who thinks the name should have moved now is disagreeing with the timing, not the fact.

#### 4. The failure sentence is three sentences, chosen by `APIError.retryable` — **NOT SPECIFIED**

Added in the review round, because the first version had one sentence for every failure: *"That
reading could not be withdrawn. It is still here. Try again."* It asserts two facts and ends with an
instruction, and each of the three is false for some reachable failure:

- **`.forbidden`** — reachable with a stale control, because `withdrawableMeasurementIDs` is read
  when the screen loads and the leaving door can unlink a reading between that read and the tap.
  Retrying cannot succeed, so the screen was telling the reader to do the one thing guaranteed not
  to work. It now reads *"That reading is not yours to withdraw. It is still here."* — the reading
  really is still there, so that half stays.
- **`.notFound`** — already withdrawn on another surface, or the row is gone. *"It is still here"*
  is false in exactly this direction, so it is not said: *"That reading is no longer here to
  withdraw."*
- **Everything else**, including a transport throw that is not an `APIError` at all, keeps the
  original sentence and its `Try again.`

**Chosen by `APIError.retryable`, not by a list of cases.** That property is already the binding
answer everywhere else — `OutboxRetryPolicy` schedules from it, screen 17 offers its retry button on
it — so a sentence that invites a retry follows the same property rather than holding a second
opinion beside it. `MeasurementWithdrawalTests.aRefusalIsNotToldToRetry` iterates
`APIError.allCases`, so a code added to the taxonomy later has to land somewhere deliberate.

The same round also stopped a failure sentence outliving the read that follows it: `withdrawError`
was cleared only at the start of the next withdrawal, so a refusal survived `reload()` and stood
over a screen freshly read from the record.

#### 5. What is deliberately absent

- **No sentence where the control is not drawn.** Screen 20 has `nobodysToRemove` because a
  photograph is a subject somebody is looking at and asking about. A line of prose under each of a
  dozen log rows would be a wall of text about permissions on a screen that is a record.
- **No edit path.** F27's other half. `MeasurementWithdrawalAccess.swift`'s header carries the
  argument; the blocked entry made it first.

#### What holds it

`MeasurementWithdrawalTests` — fourteen tests: the act, the six readers that stop counting a
withdrawn reading, both refusals, the control/permission agreement, the payload round trip, screen
17's row, the last-of-its-kind pair, the failure copy above, and the debug seam a withdrawal used to
break for good on a device. Every one red-proved by breaking the code and reading the failure.
`SchemaV21Tests` holds the migration.
