# The journal's pages, concatenated, were not the journal

**Status: fixed in the v19 index round (`perf/v19-index-round`). The failing test was written
first, on the round's branch point, and is `CypressTests/JournalPaginationTieTests.swift`.**

`ContributionStore.journal` ordered a page by `captured_at DESC` and paged on a cursor that was the
last row's `captured_at`, asking the next page for `captured_at < :cursor`. `captured_at` is not
unique. Two contributions in the same millisecond are ordinary — a walk through several trees, a
check-in and a measurement saved together, anything imported — and `SQLiteTimestamp` says so in its
own doc comment about the outbox's FIFO tie-break.

When a run of rows sharing one `captured_at` **straddled a page boundary**, the strict `<` stepped
over every remaining row of that run. They were not shown later. They were not shown at all, and
nothing on screen said so: a dropped row is indistinguishable from a row that was never written,
and the list it happens to is the contributor's own record of what they did.

`LocalAPI.wholeJournal` follows the same cursor, so `exportLatest(.csv)` — D12's subject-access
route — came back short for the same reason. That is E39's shape reached from a different cause: an
export that stops early is worse than one that fails, because the person holding it has no way to
tell it is short.

## Repro, measured on the round's branch point (`ecf8879`)

Forty visits on one tree, twelve of them sharing one `captured_at` at rows 6…17, paged at ten:

| read                                        | rows |
|---------------------------------------------|-----:|
| one unpaginated read (`limit` 100)          |   40 |
| the same rows across four pages of ten      |   32 |

Page one ends four rows into the tie; the cursor carries that timestamp; page two asks for rows
strictly older and the remaining **eight** are skipped. The same fixture at 240 rows with the tie
straddling `Page.maximumLimit` puts 232 rows in the CSV export instead of 240.

### And it shows up without a fixture built for it

Paging a scratch database of 16,000 randomly-timed contributions through to the end, at
`Page.maximumLimit`, the old form returned **14,324** rows and the new one **14,326**; at 32,000
rows, 28,648 against 28,652. Nothing in that generator was trying to produce a tie — two rows
landing on the same second out of sixteen thousand is just what happens — and two of them fell on
a page boundary. The defect does not need a pathological history to fire; it needs a long one.

## The second half, which is why an index round is where this surfaced

Within a tie the ordering had nothing to break on, so SQLite was free to return the tied rows in
whatever order the plan produced them — and **which rows a page shows was therefore a property of
the query plan, not of the data**. Reproduced with identical SQL differing only in which indexes
existed. Any index round could have changed what a person reads, silently, as a side effect of
being faster. That is not a trade this project gets to make without saying so, which is why the fix
landed in the same PR as the indexes rather than after them.

## The fix

A total order. `ORDER BY captured_at DESC, id DESC`, and the cursor becomes the pair — a
`ContributionStore.JournalCursor` carrying `(capturedAt, id)`, encoded into the opaque `String?`
that `Page.nextCursor` already was, so nothing above `LocalAPI` changed. The predicate is a
row-value comparison, `(captured_at, id) < (COALESCE(:cursorAt, char(0x10FFFF)),
COALESCE(:cursorID, char(0x10FFFF)))`, which `AppSchema` v19's `idx_<table>_captured(captured_at
DESC, id DESC)` answers as a seek.

`id` is a UUID and is unique across all four contribution tables, so the pair is a total order over
the union and not merely within an arm.

## The same defect a second time, one layer down — found in review

The tie-break fixed the drop only for databases whose `id` case matches the cursor's. It does not
for any other, and **PR #146's review found that before it shipped**:

- `UUID.uuidString` is always upper case, so the cursor `LocalAPI` re-emits is upper case;
- nothing in `AppSchema` constrains the case of a stored `id`, and this round's own
  `SchemaV19Tests` fixture writes lower-case ones deliberately;
- under BINARY, every upper-case hex letter (0x41–0x46) sorts *below* its lower-case twin
  (0x61–0x66).

So a lower-case row is "greater than" an upper-case cursor made from a row above it, `id < :cursorID`
excludes it, and it is dropped exactly as the timestamp-only cursor dropped ties. Measured: three
tied rows with ids `f1111111-…`, `e2222222-…`, `d3333333-…`, paged at `LIMIT 1`, returned **one**.

**The fix is `COLLATE NOCASE` in the three places that have to agree** — `idx_<table>_captured`, the
`ORDER BY`, and the row-value comparison's left operand. Since v19 had shipped nowhere, the
migration's DDL was amended in place rather than superseded by a v20.

The seek narrows for it, and that was measured rather than assumed, because a row-value comparison
whose collation differs from its index's can silently stop seeking:
`((captured_at,id)<(?,?))` becomes `SEARCH e USING INDEX idx_visits_captured (captured_at<?)` — the
`id` half is a filter instead of part of the range constraint. Still a seek, still early-terminating,
still exactly one temp b-tree in the plan and no per-arm sort. Page one at 16,000 rows with
mixed-case ids: **0.162 ms against BINARY's 0.161**. The `lower(id)` alternative with a matching
expression index measured the same and needs an expression index plus a normalization at the Swift
boundary, so it was not taken.

`JournalPaginationTieTests.theCursorIsCaseSafe` is the red-proof, and it is the only test in that
file that can see this precondition: the other four build their fixtures through
`ContributionStore.insert`, which takes a `UUID` and therefore always writes upper case.

## What the test asserts, and why it is a comparison

`JournalPaginationTieTests` compares **paginating** against **one unpaginated read of the same
statement** — not against a written-down expected ordering. It therefore stays true if the ordering
rule is ever changed deliberately, and it cannot pass by agreeing with itself. The property it pins
is the only one paging owes the reader: the pages, concatenated, are the list.

The suite also carries the two tests that pass on a build with the defect and say so in their own
comments — one asserts the fixture really contains a straddling tie (so the pair above cannot go
vacuously green), one is the negative control for an over-correction that would make the cursor
inclusive and return the tie twice.
