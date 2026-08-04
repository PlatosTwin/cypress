# The photo viewer carries a door to screen 20, in the screen's control vocabulary

*Unnumbered: written on branch `photo-browser-probe`. The orchestrator splices it under the real
next number at merge. No code comment cites this file — the reasoning is stated where it is
enforced, in `PhotoViewerView`'s header and in `PhotoBrowserReachabilityTests`.*

**Decision (2026-08-03), answering a field report.** Screen 20 is **NOT SPECIFIED** and so is the
viewer; both were designed under ARCHITECTURE §8 rule 8. Where a door between them goes is therefore
a decision, not a spec reading, and this is it.

## What was reported

> when i click on the tree photo from a tree page, i can get to the view where I see all photos and
> can thumbs up/down them, change between all/full/trunk/leaf only very ocassionally, and sometimes
> not at all, instead seeing only the hero photo and no other photos and no option at all to thumbs
> up/down

## The decision

**`PhotoViewerView` gains one control, `All photos of this tree`, which closes the cover and pushes
`Route.photos` over the tree the viewer already holds.**

Three things it deliberately is not:

1. **Not a change to what the hero's tap does.** The photograph opening the photograph is ERRATA
   E142, from its own field report — "clicking on photo from tree page should show full view,
   current is horizontal which cuts off photos taken in vertical orientation". Giving the hero back
   to the browser would answer this report by reopening that one.

2. **Not a bigger, louder pill on screen 03.** The pill is a genuine control with a 44 pt target and
   it is not going away, but E173 already wrote down why it cannot be the *only* door: mono 10.5 in
   a translucent capsule, drawn two inches from `Best photo · Oct 2025` in the same treatment, reads
   as a caption. Enlarging a caption produces a bigger caption.

3. **Not a thumb on the viewer.** Voting is screen 20's, because the vote is a comparison — the
   explainer there is "The photo with the most thumbs up leads this tree's page" — and a thumb on a
   photograph seen alone invites a judgment about a set the reader cannot see. What the viewer owes
   is a way *to* the set, which is what it now has.

## Why in the control vocabulary and not the caption vocabulary

The viewer's own controls are solid `heroBackFill` circles with `textBody` glyphs — `Close`, and the
delete E173 added. Its caption is a translucent `heroMetaPillFill` capsule in mono. The new door
takes the **first** treatment in capsule form, and that is the substance of the ruling rather than
styling: the defect being repaired is a control that read as a label, and a repair drawn as a label
would repeat it. It sits above the caption, bottom-leading, in the corner where this screen already
puts words about the picture, and diagonally clear of the destructive control.

## Why it is drawn unconditionally

Gating it on "this tree has more than one photograph" was considered and rejected. The count comes
from a read that has not finished when the cover appears, so the control would arrive late and move
the caption under a thumb already travelling; and the gate would be wrong anyway on a tree with one
photograph, because the thumbs are on the other side of this control and one photograph is a thing
somebody may want to vote on. The door needs only the tree id, which the route carries.

## What holds it

`CypressUITests/PhotoBrowserReachabilityTests` walks the reported path — deep link to screen 03 with
photographs, press the photograph, press the door — and asserts the three clauses of the report as
presences on the other side: a second photograph, a hittable thumbs up, and all four subject
segments. Red-proved by removing the one line that draws the door, which restores the defect exactly;
both cases failed on "there was no way on from it to the tree's other photographs".
