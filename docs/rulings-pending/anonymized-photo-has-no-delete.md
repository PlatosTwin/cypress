# R?? — a photograph nobody owns says so, in one sentence, on both surfaces that show it

**Unnumbered.** Written from a branch (`p1/round9-a`, task **#131**); the orchestrator splices the
real number at merge and rewrites the two code sites that cite this filename —
`TreePhotosCopy.nobodysToRemove` and `PhotoViewerView.captionBlock`.

**Raised by:** #131. **Delegated authority:** the copy and the surface were #131's to decide.
**Follows:** E126 (a surface showing nothing must say why), R21 (a control is withheld only where the
surface would have to choose), E173 (which found this state and deliberately left it silent rather
than invent copy in passing), E212 (the destination constraint).

---

## The state

A photograph whose contributor deleted their account through the door that keeps the work
(`AccountDeletionChoice.leaveRecords`, #70/#73/#74) is still shown on this device and is correctly
excluded from `TreeProfile.deletablePhotoIDs`. `PhotoOwnershipTests` has pinned that gating since
#78 and D9 makes ownership device-scoped. **The gating is right.** What was wrong is that neither
surface said anything: on screen 20 the row simply had one control fewer than the row above it, and
in the viewer the bottom-trailing corner was simply empty.

It is rare and it is reachable: sign in, contribute a photograph, delete the account choosing to
leave the work behind — which is the *default* door.

## The ruling

> A control withheld because the **record** cannot support it — as opposed to one withheld because
> the surface would have to choose which record it means — is an absence the surface must explain,
> in the same place and the same breath as the absence. E126's rule about an empty screen covers a
> missing action, and R21's exemption does not: R21 withholds a control where the *subject* is
> ambiguous, and says nothing about a subject that is perfectly clear and simply nobody's.
>
> The explanation is **one string on every surface that shows that record**, for the reason R21
> already gives about the control itself: a second wording is a second answer to one question, and
> the two will disagree.

## The copy

    Nothing on this photo says whose it is. The account that added it was deleted, so it is
    nobody's to remove—signing in again does not change that.

`TreePhotosCopy.nobodysToRemove`. Written against the running app on a 440 pt iPhone 16 Pro Max,
where it wraps to two lines on both surfaces, and not drafted from the ticket — which is what #131
asked for, and what E173 refused to do in passing.

Clause by clause, because each is answering a constraint:

- **"Nothing on this photo says whose it is"** is the leaving door's own promise read back from the
  other side. `AccountDeletionCopy.leaveRecordsBody` ships *"with nothing left on them saying they
  were yours"*; this is the same fact seen by whoever is now looking at the photograph. Stating the
  fact about the record first makes the missing control read as a property of the photograph rather
  than of the reader.
- **"The account that added it was deleted"** is passive and gives the person no noun. The reader
  may well *be* them — the reachable path runs through this phone — and "the contributor has left"
  makes a stranger of somebody who might be looking at their own work. Nobody is told they did
  anything wrong, because nobody did: this is the door working exactly as designed. #131 required
  that.
- **"nobody's to remove"** is E173's phrase and is what is actually true. Not "you cannot delete
  this", which is a claim about the reader's permission; the record has no owner, so there is no one
  for a deletion to be made on behalf of.
- **"signing in again does not change that"** is the only clause that is not a description, and it
  is the one #131 required: it must not imply the photograph can be recovered. Without it a reader
  reasonably tries the one thing that looks like it would help. It is true —
  `ContributionStore.claimDevice` matches on `device_id = :device`, and an anonymized row has no
  `device_id` to match — and it is the same fact `leaveRecordsBody` already ships as *"if you make a
  new account here, they do not come back to you"*.

**What it does not say, deliberately.** Nothing about where the photograph goes, who else can see
it, the city, or a reviewer. ERRATA **E212** records two shipped sentences that promise a reader
somebody else is at the other end of a contribution, and there is no contribution sync — #158 is
unbuilt. This sentence claims nothing beyond this phone and offers no route back, because there is
not one.

## The surfaces

**Screen 20 (the browser)** — under the caption, full width, in the faint register the filtered-empty
sentence already uses. Not in the thumb row: that is a row of 44 pt glyphs and a sentence cannot join
it without becoming a caption to them. It is drawn per row, on the row it is true of, and one row
only — a note at the top of the list would tell a reader that *something* here is nobody's without
telling them which photograph.

**The viewer** — stacked above the caption pill in the bottom-leading corner, in a rounded rectangle
on the same fill the caption uses, so the two read as one family. This is the one place the design
departs from *say it where the control would have been*: measured on the device, the sentence is two
full-width lines, and two full-width lines in the bottom-trailing corner either collide with the
caption in the other corner or squeeze into a narrow column over the middle of the photograph. It is
still diagonally opposite the close button, which is the geometry the delete had. **E126 requires the
surface to say why; it does not require the sentence to stand exactly where the button stood.**

## How the surfaces know

Not by subtraction. `TreeProfile` gains **`anonymizedPhotoIDs`**, read from the columns
(`user_id IS NULL AND device_id IS NULL`) in the same transaction as the photographs.

Today "shown and not deletable" happens to coincide with "ownerless", because `ownPhotoIDs` is every
row this device holds and nothing brings anybody else's down. It coincides only for that reason. A
stranger's photograph would be shown-and-not-deletable without being nobody's, and a screen telling
somebody a photograph belongs to no one must read the column that says so rather than infer it from
a permission. `AnonymizedPhotoNoticeTests` pins the distinction with a row owned by another account.

`TreePhotosModel.isNobodysToRemove` also asks that the delete really is absent, and the disagreement
case is ruled here too: **if the two ever disagree, the control wins and the sentence is not drawn.**
A screen saying a record is nobody's while offering the button that removes it is worse than either
alone.

## What was not built

The sentence is drawn on the two surfaces where a photograph is the subject. It is **not** on screen
03's hero, and that is R21's exemption applying unchanged: the hero is whichever photograph
`PhotoHero.choose` ranked this frame, so its subject moves under a vote, and a sentence about
ownership under a moving subject is a sentence about the wrong photograph.
