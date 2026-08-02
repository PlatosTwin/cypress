# The journal subtitle that spoke in raw values (#170)

**Unnumbered — pending splice by the orchestrator.**

Owner report, 2026-08-01: check in, flag the tree as removed, a lead dismisses the flag — and in
the Yours tab the check-in's row is subtitled `appears_removed`.

## Where the words come from

Journal subtitles are `entry.summary`. `ContributionStore.journal` builds the observation arm's
summary in SQL — `COALESCE(status, '')` plus an optional `· vitality N` suffix — so the column
carries `ObservationStatus` raw values verbatim. `LocalAPI.humanize` existed for exactly this
step and handled exactly one kind: care events (decoding the stored JSON action array). Every
observation went to the screen raw. The dismissal is not the writer — `dismissReview` tombstones
the flag and touches no observation, and the check-in row stays in the contributor's journal
regardless of what moderation decided — dismissal is just the flow in which the owner ends up
reading the raw value under his own check-in.

## The fix

`LocalAPI.humanize` now covers `.observation`: underscores in the stored summary become spaces,
which humanizes every status on this path (`appears_removed` → "appears removed",
`appears_dead` → "appears dead") and leaves `alive`, `declining` and the vitality suffix as they
were — underscores appear in no other part of the stored shape.

Pinned by `CypressTests/ModerationTests.swift` `dismissedReportJournalRowIsHumanized`, which
walks the owner's exact flow (check-in through the outbox → flag → lead dismisses → journal
read) for both flagging kinds and asserts the exact sentence.
