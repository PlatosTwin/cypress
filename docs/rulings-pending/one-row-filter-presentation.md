# The filter row is one horizontally scrolling line

**Unnumbered — pending splice by the orchestrator, as a correction to the row presentation R23
recorded ("two wrapped chip rows") and #145 inherited. Owner directive, verbatim, task #166
(2026-08-01):**

> More filters should be on the same line as Yours and In bloom and Needs care; one row for
> filters, that's it.

## The decision

Screen 01's filter row — `Yours · In bloom · Needs care · More filters`, plus `Clear filters`
when anything is on — is **one horizontally scrolling line**. It never wraps to a second line
and never forms a separate cluster, at any Dynamic Type size. Chips past the trailing edge are
reached by dragging the row.

The wrap it replaces was chosen against a real hazard — "a horizontal scroller on top of a map
is a gesture competing with the pan underneath it" (R23's words, borrowed from the legend) —
and that hazard is real but narrow: the scroller only owns drags that *start on the row*, one
line of chips at the top of the chrome, and the owner judged the second line of chips the worse
cost. The directive wins; the trade is recorded rather than relitigated.

## What is unchanged

- **The expandable control keeps its box** (#145): `Favorites` and `Year` stay behind
  `More filters`, and the opened drawer is still a block *under* the row that wraps internally —
  the owner's "one row" is about the chips, not about the box a chip opens.
- R23.1's three channels for a narrowing set behind the shut control (fill, count, spoken
  names).
- The legend still wraps (`FlowRow` survives there and in the drawer); its constraint was never
  part of this directive.

## What holds it (verified red-then-green on the assigned simulator)

`CypressUITests/MapFilterAccessibilityTests` pins the contract at the default size and at AX5:
every row chip reports the same line, nothing clips on the vertical axis, and every chip —
including the ones past the edge at AX5 — can be scrolled onto the glass and pressed. The AX5
wrap test this file used to carry asserted the opposite fact and was inverted, not deleted.
