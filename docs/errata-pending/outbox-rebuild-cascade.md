# Errata pending — rebuilding `outbox` (F27 / `AppSchema` v21, 2026-09-09)

Unnumbered, per CLAUDE.md "Numbering and shared files". Two entries, both measured this round while
writing the fifth rebuild of the `outbox` table. Neither is a defect that shipped — both are traps
the next author of a rebuild would otherwise walk into, and one of them was walked into here and
caught only by running a red-proof.

---

### E??? — The two pragmas that look like they save a table rebuild from its own cascade, and do not

`outbox_photos.outbox_id` is `ON DELETE CASCADE` against `outbox`. Every widening of the
`outbox.kind` `CHECK` is a rebuild, and a rebuild drops `outbox`. Under `PRAGMA foreign_keys = ON` —
which `SQLiteConnection` and `DatabaseQueue` both set on every connection — the implicit
`DELETE FROM` inside `DROP TABLE` performs the cascade, so **every staged binary in the queue is
deleted**. `AppSchema` v18's header records this from the round that first met it.

What v18 does not record, and what cost an hour here, is that the two obvious escapes both fail:

- **`PRAGMA defer_foreign_keys = ON`** is the tempting one, because it is the only relevant pragma
  that can be set *inside* a transaction — `PRAGMA foreign_keys` is documented as a no-op inside one,
  and `SchemaMigrator` wraps every migration in a transaction, so the standard `foreign_keys=OFF`
  procedure from SQLite's own ALTER TABLE documentation is unavailable to a migration here. It does
  not help: it defers constraint *checking*, and a cascade is an *action*. Measured on SQLite 3.51:
  one parent, one child, rebuild inside `BEGIN` with `defer_foreign_keys = ON`, `children=0`
  afterwards.
- **`PRAGMA legacy_alter_table = ON`** changes what `ALTER TABLE … RENAME` rewrites in other tables'
  `REFERENCES` clauses. The loss happens one statement earlier, at the `DROP`. Measured the same way,
  same result: `children=0`.

The only shape that works is v18's own, and v21 repeats it: park the child rows in a table with no
foreign key, empty the child, rebuild the parent, put the rows back, drop the parking table.
Measured: `children=1`, content intact, `PRAGMA foreign_key_check` clean.

**A second, quieter half.** The implicit delete inside `DROP TABLE` fires **no triggers**, so
v18's `outbox_photos_counted_out` never runs and `outbox.photos_outstanding` is copied to the new
table unchanged — every item goes on owing binaries that no longer exist, can never satisfy
`CHECK (state <> 'done' OR (local_applied = 1 AND photos_outstanding = 0))`, and can never settle.
That is a permanently wedged queue with no error anywhere. v21 recomputes the counter from the child
table at the end rather than reasoning about what the triggers did, and asserts it against
`outbox_photos` in `SchemaV21Tests`.

---

### E??? — A counter asserted against the fixture instead of against the table stays green while the counter drifts

`SchemaV21Tests.theStagedBinariesSurviveTheRebuild` was written asserting that each item's
`photos_outstanding` equals the number of binaries the fixture staged for it. That assertion is
green under exactly the defect above, and it was: the red-proof produced **one** issue where the
suite header predicted two.

The reason is worth stating because it generalizes. The rebuild copies `photos_outstanding` **before**
the drop cascades the children away, so after an unparked rebuild the number is the correct one and
the rows behind it are gone. Any assertion that compares the counter to what the test *put in*
therefore agrees with a database whose counter and contents disagree. Asked instead against
`outbox_photos` — the counter is the count — it fails immediately: `(outstanding → 2) == (live → 0)`.

This is the project's dominant test-suite defect (a guard green while its defect is present), and it
was found by running the red-proof rather than by reading the test. The general form of the question
is: **is this assertion comparing two things the defect changes together?** A counter and the fixture
that produced it move together under a cascade; a counter and the table it counts do not.

**Both assertions are load-bearing, in opposite directions, and the paragraphs above argue only one
of them.** PR #154's adversarial review measured the other half and reported it: with the parking
block removed but step 5's recompute *left in place*, the recompute drives `photos_outstanding` to 0
against a child table the cascade has already emptied — so `outstanding == live[id]` passes on
`0 == 0`, and it is `outstanding == staged[id]`, the fixture comparison this entry warns about, that
catches the loss: `(outstanding → 0) == (staged[id] → 2)`. Which of the two goes red depends on how
much of the parking block a given edit takes out, so neither may be dropped in favour of the other.
The table comparison catches a counter left too *high* by a cascade that fired no triggers; the
fixture comparison catches one recomputed too *low* against children that are already gone. The
lesson is not "assert against the table" — it is that a counter needs an assertion on each side of
it, because the two failures are not the same failure.

---

## Addendum, 2026-09-10 — the same trap now has a second parent in this schema

`AppSchema` v22 (`RULINGS R79`) adds `tree_data_disputes` with **two** `ON DELETE CASCADE` children,
`tree_dispute_issues` and `tree_dispute_suggestions`. Everything in the first entry above applies to
that parent unchanged: a rebuild of `tree_data_disputes` — which any widening of its `tree_source`
`CHECK` would be, since SQLite cannot widen one in place — drops the parent, the drop cascades, and
both children are emptied with no error anywhere. `defer_foreign_keys` does not help, for the reason
measured above.

Two things are different and both are worth writing down.

**There is no counter here, and that is the smaller half of the hazard rather than none of it.**
`outbox.photos_outstanding` is what made the v18/v21 loss *permanent* — a queue that can never
settle. A dispute has no derived count, so the failure mode is a plain silent deletion: every checked
issue and every suggested value gone, the parent rows intact, and a dispute that now says a person
objected to nothing in particular. That is quieter, not better.

**Widening the *children's* vocabularies is a different and much cheaper operation, and the round's
contract asked the question directly.** `tree_dispute_suggestions.field` and
`tree_dispute_issues.kind` are both CHECKs, so widening either needs a table rebuild — but the table
being rebuilt is a **child**, and a cascade runs parent to child. Dropping and recreating
`tree_dispute_suggestions` cascades nothing. So: widening the suggestion vocabulary is a migration
and is *not* free, and it is also not the dangerous rebuild. Rebuilding `tree_data_disputes` is.

`SchemaV22Tests.theCascadeIsRealOnThisSQLite` measures the cascade on this build's own SQLite,
inside a transaction, with `PRAGMA foreign_keys` asserted on first so the measurement cannot be
vacuous — because the whole thing standing between the next author of that rebuild and two emptied
tables is a paragraph in a comment, and this project's rule is that a confident comment is where
bugs survive. Red-proved by removing `ON DELETE CASCADE` from both children: the test reports
`(issues == 0 → false)`.
