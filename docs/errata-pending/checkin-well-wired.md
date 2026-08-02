# PENDING — Screen 05's optional well is wired; E25's waiting state ends (task #169)

**The report.** Owner, task #169: "Check-in page has a gap: the add photos/notes does nothing.
It should allow you to TAKE A PHOTO or SELECT A PHOTO, and then of course to add notes."

**This is E25's designed-for moment, arriving.** E25 recorded, deliberately, that 05's C15 well
was drawn with no editor behind it — "when the editor is designed, the view is the only file
that changes" — because `CheckInDraft` carried `note: String?` and `photos: [OutboxPhoto]` from
M1 and `CheckInOutboxWriter.enqueue` always wrote both through the outbox. That prediction was
almost exactly right: the view changed, and the model gained the entrance surface the view
binds (`note`, `attachPhoto`, `removePhoto` — the same members `CareLogModel` grew under #147/
#168, staged through `VisitPhotoStaging` as `.other`, fresh UUID per file). The writer, the
payload shape and the schema did not move. No migration: `observations.note` and the photo path
exist as shipped.

**The entrance is the pattern task #168 built for screen 09** — fields directly visible, take
*or* pick, several photos, per-photo removal — recorded in the pending ruling
`contribution-extras.md` (splice: cite that ruling's final number here). The well's copy
`Add photos · notes (optional)` becomes the slot's micro-label; nothing else on screen 05 moves
(constraint 21).

**Proof is stored rows, not UI.** `CheckInExtrasTests`: the enqueue leaves one durable
`.observation` outbox row carrying the trimmed note on its payload and both binaries on
distinct staged paths, before any drain; through the model and the drain, the tree gains one
observation with the note and two `photos` rows (`.other`, `visitID == nil`) with real files
behind their storage keys. Every new test was proven able to fail by mutation.

E25 itself stays true as history — it recorded the well's inert state and why. This entry is
its closure: the trail is E25 → (09: E185, #147, redesigned #168) → (05: this entry, #169).
