### E?? — #120's schema blocker was retracted from the wrong column, and the real one is still there

Task **#120** — make screen 06's neighborly note actually submit — was dispatched as unblocked. It is
not. **No code was written for it**, which is the finding rather than a shortfall.

#### What the ticket retracted, correctly

Older #120 text said `community_notes.kind` is a closed CHECK at `AppSchema.swift:305` needing a
migration. That was checked before dispatch and refuted: there is no `community_notes.kind` column.
The table's constrained column is `category TEXT NOT NULL CHECK (category IN
('needs_water','pest','vandalism'))` (`AppSchema.swift:287`), those three values are exactly the
three chips SCREENS.md 06 §3 draws, and `ReportPresentation.noteCategories` is
`CommunityNote.Category.allCases`. Line 305 is `review_flags.kind`, a different table. **That
retraction is right and this errata does not disturb it.** A neighborly note needs no migration to
hold its category.

#### What is still in the way, on the column nobody re-read

**`community_notes.user_id` is `NOT NULL` (AppSchema v1) and no migration has made it nullable.**
`CommunityNote.userID` is a non-optional `UUID` to match. Two independent consequences follow, and
either alone blocks the write.

**1 · There is no user id on any device the app runs on.** `LocalAPI.userID` is set only by
`setUserID`, whose sole caller in the repository is `FavoriteTests.swift:323`. Nothing in shipping
code calls it; D9 keeps first saves anonymous under a device id and the account ask arrives at screen
15, which is not built. So `attribution.userID` is nil on every install, and a `CommunityNote` cannot
be constructed at all. This is E23's situation for the private reminder, verbatim, one table over —
and E23 was closed by **AppSchema v3**, which made `private_reminders.user_id` nullable, added
`device_id` beside it, and put `CHECK ((user_id IS NULL) <> (device_id IS NULL))` across the pair.
v5 did it for `favorites`, v12 for `photos`. `community_notes` is the table that never got the
treatment.

**2 · The anonymizing door cannot honour a note.** DECISIONS §3.12 anonymizes attributed rows;
`RULINGS R3` refined it to *anonymize what the forest keeps, delete what only one person could ever
see*. A community note is public — the forest keeps it — so it must be anonymizable, and
`user_id NOT NULL` means it cannot be. `AccountDeletion.Outcome.communityNotesLeftAttributed` exists
for exactly this, and says so in its own words: it is "zero on every database the app can produce"
today "so that the day something does write one, the hole is a number somebody can see rather than a
silence" (E109). Writing notes is that day.

`ReportView.notePicker`'s own comment block (E131) states both halves and names the price: closing it
"needs a schema migration and a second pass over R3 — a decision-owner's call, not this errata's".

#### Why the work stopped rather than routing around it

Three routes were considered and each is worse than not shipping.

- **Write the device UUID into `user_id`.** It is a lie in a column two identity spaces already meet
  at, and it breaks `AccountDeletion` in the direction that matters: every predicate there is
  `user_id = :user`, so a device-owned note would be invisible to both doors — neither anonymized nor
  deleted — which is the E109 hole widened rather than closed.
- **Queue the note without storing it.** Every other mutation is durable locally first
  (ARCHITECTURE §4), and the payload still needs a `CommunityNote` with a `userID`.
- **Draw the CTA and let the write fail.** That is the control E131 removed, with a button on top.

**#120 needs a migration, and this round may not write one.** The shape is settled by three
precedents rather than open: v3's, applied to `community_notes` — `user_id` nullable, `device_id`
beside it, exclusive-ownership CHECK — plus one line in `claimDevice` for adoption, plus the
`OutboxPayload` case, and `AccountDeletion.anonymizeContributions` gains the `UPDATE` that turns
`communityNotesLeftAttributed` from a hole into a zero. It is one migration author's afternoon in a
round that has one.

#### And the copy #120 was dispatched to write is not writable either

Recorded here because it survives the migration and will be the next thing to go wrong.

The ticket's destination sentence was *"seen by the community, which can confirm it"*. **There is no
contribution sync.** #158 is unbuilt and unscheduled; the outbox drains through `APIOutboxTransport`
into `LocalAPI`, which writes this phone's own tables. Nothing uploads, nothing downloads, and beta
is about five people with no accounts. A note reaches no other reader.

So that sentence names a destination the note does not arrive at, which is structurally the claim
§3 constraint 3 forbids — permanent under D16(a) — with a different noun. The honest version is about
the note being kept, not about who sees it; #125's notice
(`TreeProfileCopy.neverExistedNotice`) is the worked example, and E126 is why the limit is stated
rather than left silent.
