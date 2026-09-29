# Tester-visible, not `internal:` — owner ruling 2026-09-28.
#
# The fix scopes `GET /me/grove/species` to sighting kinds only (`visit`, `observation`,
# `measurement`, `care_event`). Before this deploy, a species named on a community tree through
# `add_tree`, `species_claim` or `species_correction` was added to that tab on refresh, even
# though the phone's own first paint had already left it off. After this deploy the service
# answers an empty list for those kinds, so the refreshed tab drops back to matching the first
# paint — a species someone named that way, with no sighting of their own, disappears from the
# tab they can see, and the ring's numerator can drop by the same species. That is a change a
# tester can notice, so the note says so rather than calling it `internal:`.
#
# 169 characters, under the 200 the checker enforces.

My Grove's Species tab no longer counts a species you only named on a community tree. It now shows species you've met by visiting, observing, measuring, or logging care.
