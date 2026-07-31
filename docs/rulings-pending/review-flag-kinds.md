### A confirmed-dead tree says so in words; whether it gets its own drawn pin is still open

Raised by task #58 / ERRATA E170, which made `dead_reported` reachable from the app for the first
time. Two questions arrived with it. One is answered here; the other is deliberately not, and this
entry exists so the second does not get answered by accident.

---

**Decided: `dead_reported` shares the removed *drawing* and shares none of its *words*.**

The grey pin and the grey badge say "there is no living tree at this site", which is true of a
removed tree and true of a standing dead one. `MapPin.Kind` is a closed catalogue — its sixth entry,
the vacant-site pin, took RULINGS R7 — and `StatusBadge` has four colour pairs and no fifth. So the
drawing is borrowed and no new visual vocabulary is invented.

Every *word* is separate, and that is not a compromise:

- badge `Dead`, never `Removed`
- pin spoken as `Dead tree, still standing`, never `Removed tree, memorial`
- profile Callout saying a reviewer confirmed it and that it is still worth reporting
- queue row `Reported dead` / `Confirm dead`, beside the removal's own pair

The rule this encodes: **two statuses may share a drawing while sharing no sentence.** A reader who
sees only colour learns "not a living tree here", which is right. A reader who reads or listens
learns which of the two, which is what actually changes what they should do — a removed tree needs
nothing from anybody, and a dead one standing over a pavement needs reporting.

**Not decided: whether a standing dead tree deserves a pin of its own.**

There is a real case for one. A dead street tree is the highest-consequence record on the map, it is
the only grey pin you can still act on, and R7's argument for the vacant site — that borrowing
`.removed` made the map assert something untrue — applies here in a weaker form: the map is not
asserting removal, but it is declining to distinguish a hazard from a memorial.

It is left open for the reason E107 left the same half open: a new pin is a design decision against a
closed catalogue, and an errata fixing a data-layer defect has no standing to make one. E170 fixed
what the pin *says*, which needed no catalogue change; what it *draws* waits for whoever owns C19.

**If it is taken up**, the shape is `MapPinKind.kind(for:)`, which already switches
`case .deadReported, .removed: return .removed` — one line, and `MapPinCopy.deadReportedLabel` is
already the override that would move onto the new case's `accessibilityLabel`. What must not happen
is the reverse: routing `deadReported` to screen 19 to make the map tidy. That takes the REPORT
button off the one status where a hazard report matters most, and `ModerationTests` asserts against
it.
