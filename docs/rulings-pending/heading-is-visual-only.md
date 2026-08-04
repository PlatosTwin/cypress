# The direction cone is visual-only — heading never enters what VoiceOver says (task #155)

*Unnumbered: written on branch `heading-155`. The orchestrator splices it under the real next
number at merge. No code comment cites this file — the rule it records is stated where it is
enforced, in `MapHeadingTests`.*

**Orchestrator decision, task #155 (2026-08-03).** The reader's dot now draws a compass cone
showing which way the phone is pointing. The question this settles is whether that bearing also
reaches the spoken channel.

## The decision

**It does not.** `MapMarkerView`'s accessibility label for the reader's own dot stays exactly what
#100 made it — `Your location` — and says nothing about heading, in any state, at any accuracy.

The reason is what the spoken channel is for. #100 made the dot's label answer *where you are*: one
fact, stable while the reader stands still, spoken once when they move focus to it. A bearing is not
that kind of fact. It changes every time the reader turns their wrist, and a VoiceOver value that
rewrites itself several times a second does not inform anybody — it talks over the tree names, the
distances and the search results that the same screen is trying to speak. The reader who most needs
the map to be legible is the reader this would interrupt most.

The cone is therefore a **sighted-only affordance**, and that is stated as a limit rather than
hidden as an oversight: a reader who cannot see it loses nothing they previously had, because the
bare dot is exactly what the app shipped before #155 and exactly what it degrades to whenever the
magnetometer cannot be trusted.

## What this does not decide

Whether *some* heading-derived sentence belongs somewhere in the app — "the tree is behind you", a
turn instruction on screen 18's route — is a different question with a different answer, because
those are events rather than a continuously changing value. Nothing here forecloses one; this rules
only on the dot's own label.

## What holds it

`MapHeadingTests` — "the dot still says where you are, and says nothing about which way you face" —
asserts the label is `MapPin.Kind.gps.accessibilityLabel` on a marker view that is carrying a
heading. Red-proved by appending a bearing to the label: the test failed with
`"Your location, facing 137 degrees" == "Your location"`.
