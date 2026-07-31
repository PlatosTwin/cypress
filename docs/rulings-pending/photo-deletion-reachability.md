## R?? — a control belongs on every surface that shows its subject unambiguously

**Raised by:** #126, reopening #78. **Supersedes** the second half of E147's "what was not built".

E147 put the photo delete on screen 20 alone and gave one reason for keeping it off the other two
surfaces at once: *"a delete on the hero would act on whichever photograph the rule happened to
pick"*. That reason is sound, and it is a reason about **ambiguity of subject**, not about screen 20
being the home of per-photograph controls. It was then applied to the full-screen viewer, which has
no ambiguity of subject at all — it is handed one `photoID` and draws that photograph and no other.

The ruling, stated so the next control does not repeat this:

> A control that acts on one record may be placed on **any** surface where that record is the
> unambiguous subject — and should be, when that surface is where a person's gesture lands. It is
> withheld only where the surface would have to *choose* which record it means. "This screen is the
> canonical home for these controls" is not by itself a reason to withhold one; a canonical home is
> a claim about where a control can always be found, not a claim that it may be found nowhere else.

Two consequences worth naming:

**The hero on screen 03 keeps its exemption**, and now for a stated reason rather than by
association. The hero is whichever photograph `PhotoHero.choose` ranked first this frame, so its
subject moves under a vote. That is the ambiguity the rule is about, and it is real.

**Duplication of a control is not duplication of its logic.** The viewer drives the same
`TreePhotosModel` screen 20 drives, so "may this person delete this, and what does removing it cost
the tree" has one implementation and one set of words. A second control reached by a second gesture
is a convenience; a second answer to the same question is a defect waiting for the two to disagree.

**The general shape.** This project has now twice shipped something correct that nobody could reach:
E110's `Back` that was in the tree and could not be tapped, and this. Both passed their tests. The
common failure is testing that a thing *is* rather than that a person can *get to it*, and the
correction is a test that starts at a launch and taps its way in.
