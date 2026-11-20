# Why this is an `internal:` line and not the obvious sentence.
#
# The obvious sentence — "a reading you withdraw now disappears on your other devices" — would be
# true of this code and false of anything a tester can reach, for two independent reasons, and the
# README forbids exactly that: say only what shipped.
#
#   1. The phone half is PR #154 (`AppSchema` v21), which is open. Until it merges no build can
#      even queue a `measurement_withdrawal`, so there is nothing for this service to receive.
#   2. This pull request is code and tests. `cypress-sync` is not redeployed by merging it, and
#      migration 004 runs at boot — so until somebody deploys, the deployed service still refuses
#      the kind exactly as it does today.
#
# When both have happened, the line belongs in a note of its own, made at the moment it became
# true. That is the mechanism `nyc-street-trees-live.md` used and the reason it exists.

internal: the sync service learns the `measurement_withdrawal` kind and tombstones the reading it names; no tester-visible change until #154 merges and the service is deployed.
