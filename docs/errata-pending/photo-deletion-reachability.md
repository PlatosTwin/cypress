### E1?? — the delete that shipped, on the one screen nobody taps to reach it

The report, walking the app:

> Not sure if the feature to delete photos is still tbd, but I don't see that option, so hopefully
> it's tbd rather than 'shipped' but not actually.

#78 is COMPLETED and it is genuinely complete. **The control exists, works, and is reachable — and
it is not on the screen the gesture takes you to.** This is the third of the four things that report
could have been, and it is a defect rather than a misreading.

#### What was observed, before any code was read

Booted the simulator, installed a build from this worktree, and drove it. On `photoHero` — screen 03
over a tree with three photographs — the delete is exactly where E147 put it: screen 20, one amber
trash glyph per row, beside the two thumbs. It opens a confirmation naming the consequence, the verb
is on the button, and it works. E147's walkthrough was accurate and its tests were honest.

Then the other tap. **Tapping the photograph opens `PhotoViewerView`, which had no delete on it and
no route onward.** One photograph, full-frame, named in its own caption, with a close button in the
corner and nothing else. Somebody who taps their photograph in order to do something to it arrives
at a screen whose entire vocabulary is *look, then close*, and the only correct conclusion from
inside that screen is that the feature does not exist.

Both doors into the viewer are like this: the hero on 03 (`TreeProfileView.hero`) and a row on
screen 20 (`TreePhotosView.card`). So a person who is already standing on the surface that has the
delete, and taps the picture to see it properly before deciding, loses the control by looking closer.

#### Why the reasoning that excluded it was right about the hero and wrong about the viewer

E147 wrote down its exclusion:

> No delete affordance in the full-screen viewer or on the hero: screen 20 is the only surface that
> shows a tree's photographs as a set with per-photograph controls, and a delete on the hero would
> act on whichever photograph the rule happened to pick.

The second clause is true, and it is the reason not to put a delete on the hero: the hero is
whichever photograph `PhotoHero.choose` ranked first this frame, so a trash beside it is a control
whose subject changes under a vote. **The viewer is the opposite case.** It is handed a `photoID`.
It draws that photograph and no other, whole, with that photograph's own caption under it. There is
no rule and nothing for it to pick. The sentence was carried from the hero to the viewer in the same
breath, and the two were never the same screen.

The other half is timing. `PhotoViewerView` is E142, and it exists because of an earlier field
report — *"clicking on photo from tree page should show full view"*. E142 gave the photograph a tap,
and in doing so made "tap the photograph" the app's answer to *act on this photograph*. E147 landed
after it, and reasoned about the hero as though the tap still went nowhere.

#### The pill is a caption, and that is the rest of the answer

The one door to screen 20 is the hero's metadata pill, which reads `3 photos · since 2026`. It is a
button and it says so to VoiceOver, and `HeroPhotoHeader` grew its target to 44 pt on purpose. But
it is mono 10.5 in a translucent capsule in the corner of a photograph, which is the same treatment
this app gives `Best photo · Oct 2025` two inches away — a label. Nothing about it reads *there are
controls behind this*. So the delete sat behind a caption, one tap away from a screen whose obvious
tap goes somewhere else, and the owner's summary of that arrangement is the correct one.

#### The repair

`Route.photoViewer` gains the tree id. That is not bookkeeping: ownership is a fact about a tree's
photographs (`TreeProfile.deletablePhotoIDs`), so a viewer holding only a photograph's id **cannot
ask whether the person looking at it may delete it** — which is the mechanical reason this screen
could not have had the control when it was written. The route's own comment argues that it carries a
caption rather than an id to avoid a second read that could disagree with what is on screen; that
argument does not apply here, because this is not a word, it is the key the answer is read under.

The viewer then drives **the same `TreePhotosModel`** screen 20 drives, rather than a model of its
own. One implementation of "may this person delete this photograph, and what does removing it cost
the tree" — the community-add sentence included — instead of two that can drift. The control is the
same glyph in the same amber register opening the same confirmation with the same words, because a
person who has seen one of these has seen both.

Three smaller decisions, each with a reason:

1. **Bottom-trailing, diagonally opposite `Close`.** The destructive control is as far as the screen
   allows from the one that means *never mind*, and clear of the caption in the other corner.
2. **The viewer closes on a successful delete.** Its subject no longer exists; staying would draw
   *That photograph could not be opened* over the place it used to be, which reads as a failure
   rather than as the thing that was just asked for. The surface underneath re-reads itself — which
   is E127, and which E147's own harness defect was about.
3. **The failure is drawn over the photograph.** `TreePhotosModel.deleteError` must never be silent;
   here there is no list to put it above, and the photograph still being there is half the message.

#### The test, and how it was made to fail

`CypressUITests/PhotoDeletionReachabilityTests` — and it is a **UI test on purpose**. Every unit test
in `PhotoDeletionTests` passed throughout this defect and would have gone on passing: they assert
that `deletePhoto` removes a row and a file, which was always true. Nothing asserted that a person
holding the phone could get to it. A unit test on a presentation helper would have repeated exactly
the mistake that closed #78 green.

It drives the reported path. `communityPhotos` — the deep link E147 built precisely to have its
photograph deleted, on its own tree — then tap the hero photograph, then assert the delete is in the
tree, is hittable, opens a confirmation, and that taking the confirmation leaves the tree cold. It
does not stop at `isHittable`: this project has shipped a control that reported `true` and that no
finger could press, so the control is *used* and the surface underneath is read.

Made to fail on purpose by deleting the one overlay line that draws the control — which restores the
defect exactly as it stood, since nothing else about the deletion changed. Both cases went red, on
their own sentences:

```
PhotoDeletionReachabilityTests.swift:47: error: testTheHeroPhotographReachesADeleteThatWorks :
  XCTAssertTrue failed - the viewer opened over a photograph this device owns and offered no way
  to delete it — which is the whole of the owner's report on #78
PhotoDeletionReachabilityTests.swift:110: error: testAPhotographOpenedFromTheBrowserReachesTheSameDelete :
  XCTAssertTrue failed - the browser's own row opened a viewer with no delete on it, so looking
  closer at a photograph costs you the controls for it
     Executed 2 tests, with 4 failures (0 unexpected) in 29.254 seconds
```

The line restored, both green:

```
Test Case 'testAPhotographOpenedFromTheBrowserReachesTheSameDelete' passed (12.789 seconds).
Test Case 'testTheHeroPhotographReachesADeleteThatWorks' passed (11.538 seconds).
     Executed 2 tests, with 0 failures (0 unexpected) in 24.327 seconds
```

#### What was not built, and one thing seen in passing

The pill's own discoverability is untouched. It is now a second way to the same control rather than
the only way, which is the part of this that mattered; whether a mono-10.5 capsule over a photograph
should look like a door at all is a design question and not this entry's.

**The silent case is still silent, and it is now silent in two places.** An anonymised photograph —
one whose contributor left through the door that keeps their work — is still *shown*, correctly, and
has no delete on it, correctly. What neither screen 20 nor the viewer does is **say so**. The row
simply has one fewer control than the row above it, and the viewer simply has an empty corner. E126
requires a screen with nothing on it to say why, and the same logic covers an action that is absent
for a reason; "this photograph's contributor has left, and it is nobody's to remove" is a sentence
this app would normally write. It is deliberately not written here because it is a different defect
from the reported one and wants its own entry and its own copy — the state is reachable (sign in,
contribute, delete the account keeping the work), it is rare, and inventing the sentence in passing
is how copy gets written that nobody has read against the screen.

Seen while reading, and not fixed here: `TreePhotosModel.load` filters `profile.photos.items`, which
`LocalAPI` already narrows to what this installation wrote, while the hero pill's count comes from
the tree's whole photo count. On a tree carrying photographs from other people the pill would say
`214 photos` and screen 20 would draw its empty state. Nothing syncs anybody else's photographs down
today, so the two cannot disagree yet and this is latent rather than live — but it is the shape E126
is about, and it becomes real the day the service exists.
