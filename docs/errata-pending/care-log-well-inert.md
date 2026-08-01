# The care log's photo/note well was drawn and inert, and everything under it worked (task #147)

**UNNUMBERED — pending. The orchestrator assigns the E number at merge and rewrites any code
comments that cite this filename.**

**The report.** Owner's device walk, 2026-07-31: "the care log has a space for photo/note but
neither can be added."

**Diagnosis: the drawn-but-inert class (the E59 shape), not a missing entrance (the E49 shape).**
Screen 09's C15 well rendered, said `Photo or note (optional)`, and answered no tap. E25 recorded
that state deliberately — "no picker and no note editor is specified behind it on 05 or 09" —
and everything beneath the drawing was already real:

- `CareLogDraft` has carried `note` and `photos` since it was written;
- `CareLogOutboxWriter.enqueue` has always put both on the outbox row (`CareEvent.note`, photos
  as `OutboxPhoto` binaries);
- `care_events.note` is a plain nullable TEXT column in the schema as shipped, and the photo path
  is the same `beginPhotoUpload`/`uploadPhoto` machinery every visit photo uses.

**No migration, checked before building.** The note is `care_events.note` — the closed
`community_notes.kind` CHECK vocabulary is never touched, because a care note is a column on the
care event, not a community note. The photo is staged through `VisitPhotoStaging` (so E148's
metadata strip applies), queued as `.other` — a value already in the `photos.shot_type` CHECK —
and uploaded by the existing drain. Schema v-current throughout.

**The fix.** The well is now the entrance it looked like: one tap opens it, in place on the
sheet, into screen 04's note field (light register) and a system photo picker. The save guard is
unchanged — a care event still requires at least one action (PROTOTYPE-FLOW §1.3), and the two
fields stay optional and reversible. `CareLogTests` round-trips both: the note read back off the
store trimmed, and the photo landed as an uploaded `photos` row (`shotType == .other`,
`visitID == nil`) with a real file behind its storage key.

**One loose end, named rather than hidden.** `care_events.photo_id` stays NULL: the drain's
`beginPhotoUpload` does not know which care event a binary belongs to (the upload request carries
`visitID` only), so the care photo is linked to the tree, not to the event row. The photograph is
reachable everywhere photographs are shown; a coordinator reading one care event cannot jump to
its photo. Extending `PhotoUploadRequest` with the care event id is an API-boundary change and a
separate decision.
