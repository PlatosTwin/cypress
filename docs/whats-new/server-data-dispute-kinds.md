# Why this is an `internal:` line and not the obvious sentence.
#
# The obvious sentence — "you can now tell us the city's record is wrong" — would be true of this
# code and false of anything a tester can reach. The README forbids exactly that, and names this
# case: do not describe "a mutation the server records but does not act on". This service records
# a dispute and adjudicates nothing, by ruling.
#
#   1. The phone half is `AppSchema` v22 (branch `feat/r79-city-disputes`), which is open. Until it
#      merges no build can queue a `data_dispute`, so there is nothing here to receive.
#   2. There is no UI on either branch. The dispute sheet on screen 03 is a separate pull request,
#      and R79's badge, its "trees with data issues" filter and its missing-tree entry point are
#      each later still.
#   3. Merging this does not redeploy `cypress-sync`, and migration 005 runs at boot — so until
#      somebody deploys, the deployed service refuses both kinds exactly as it does today.
#
# When all of that has happened, the line belongs in a note of its own, written at the moment it
# became true.

internal: the sync service learns the `data_dispute` and `data_dispute_withdrawal` kinds and refuses a withdrawal of somebody else's dispute; no tester-visible change until the phone half merges, a screen exists, and the service is deployed.
