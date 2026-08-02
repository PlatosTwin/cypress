# PENDING — The photo/note extras are the fields, on both contribution surfaces (tasks #168, #169)

Owner direction (task #168, verbatim, device, screenshots on file): "Care is still fucked.
Screen is half-sized which is weird, and also means that when you go to type the keyboard runs
over the area you're typing. Also to add a photo there's no option to take one (or multiple);
all it allows is adding from your library, which is inefficient. Also the behavior of clicking
on 'Photo or note' and then getting a new textbox that says 'Anything worth remembering' is
awkward." And for screen 05 (task #169): "Check-in page has a gap: the add photos/notes does
nothing. It should allow you to TAKE A PHOTO or SELECT A PHOTO, and then of course to add
notes."

The half-height and keyboard halves were already closed by #146's sheet mechanism (R39) —
verified on the running screen before this work started, not assumed. What this ruling records
is the interaction redesign of the optional slot itself, delegated authority, written from the
screens as built.

**The rule: the extras are the fields.** On 09 and on 05, the optional photo/note slot renders
its fields directly — no reveal step, no control that turns into a different control when
tapped. Concretely, on both screens (`ContributionExtras`, one component, so the two surfaces
are one design):

1. **The note field is simply there** — screen 04's field in the light register, prompt
   `Anything worth remembering?` verbatim, 1–3 line growth, set into the draft at save, trimmed,
   blank stored as NULL. The two-step "tap 'Photo or note' → get a textbox" is gone; it was the
   reported awkwardness, and a field a contributor can see is a promise the slot keeps by
   standing there.

2. **Two photo sources, side by side, each doing what its label says** (R39's destination-button
   rule): `Take a photo` opens the in-app camera; `Add from library` is the system picker,
   multi-select. The camera is `ContributionCameraView` — the same `VisitCameraController`
   session, preview layer, shutter, ✕ and library fallback screen 04 runs, with none of 04's
   visit surface (ghost, framings, phenology). Reused, not reinvented; on a device with no
   camera (and on every simulator) it falls back to the library picker with screen 04's own
   sentence, so the button never goes dead.

3. **Photos are plural and each is its own fact.** The camera stays up across shutter taps
   ("take one (or multiple)" is one open-close; a czFlash and a tray count line receipt each
   frame). Attachments render as thumbnails, each wearing its own ✕ — removal is per photograph
   and reversible, like every field on these surfaces. Each attachment is staged to its own path
   (fresh UUID through `VisitPhotoStaging`, so E148's metadata strip applies and no two share a
   path — a shared path would let the drain take siblings out of the outbox row).

4. **The C15 well survives as words, not as a control.** On 09 its verbatim copy
   (`Photo or note (optional)`) captions the block; on 05 its copy
   (`Add photos · notes (optional)`) becomes the slot's micro-label in the card's own section
   chrome. That is where "optional" keeps being said, and it is the minimal call on a layout the
   mocks never drew opened — nothing else on screen 05 moves (constraint 21). 09's caption keeps
   the mock's singular "Photo" although the slot now takes several; the word is the mock's,
   verbatim, and re-writing it was judged a larger invention than leaving it.

**What survives of #147.** Everything below the surface: the wiring E185 records — staging
through `VisitPhotoStaging` as `.other`, `CareLogDraft`/`CareEvent.note`, the unchanged writers,
no migration — plus the note-at-save timing and the trim. What #168 removed of #147's design:
the one-way reveal (`isEditingExtras`), the single-photo replace-on-repick semantics, the
library-only source, and the `Photo attached` / `Remove` text row (thumbnails carry both facts
now). #147's reachability diagnosis was right; the owner's walk showed its interaction was not.

**Screen 05's slot is wired with the same block (task #169, E25's closure).** `CheckInDraft` has
carried `note` and `photos` since M1 and `CheckInOutboxWriter` always wrote both; only the
entrance was missing. `CheckInModel` gained the same `note`/`attachPhoto`/`removePhoto` surface
as the care log's model. The saved check-in is asserted as stored rows, not UI:
`CheckInExtrasTests` pins the durable outbox row (one `.observation` item carrying both
binaries on distinct paths) and the post-drain rows on the tree (observation with the trimmed
note; two `photos` rows, `.other`, `visitID == nil`, real files behind their storage keys).

**Copy designed here** (NOT SPECIFIED anywhere in the mocks): `Take a photo`,
`Add from library`, the camera tray's `Done`, `That frame could not be captured. Try again.`,
and the tray receipt `N photo(s) added`. Each states a fact and stops; all swept by the same
ARCHITECTURE §5.4 / D1 word tests the sheets' other copy passes.
