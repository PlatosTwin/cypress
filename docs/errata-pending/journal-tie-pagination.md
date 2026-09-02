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

## What the test asserts, and why it is a comparison

`JournalPaginationTieTests` compares **paginating** against **one unpaginated read of the same
statement** — not against a written-down expected ordering. It therefore stays true if the ordering
rule is ever changed deliberately, and it cannot pass by agreeing with itself. The property it pins
is the only one paging owes the reader: the pages, concatenated, are the list.

The suite also carries the two tests that pass on a build with the defect and say so in their own
comments — one asserts the fixture really contains a straddling tie (so the pair above cannot go
vacuously green), one is the negative control for an over-correction that would make the cursor
inclusive and return the tie twice.
