# `internal:`, and the reason is measurable rather than a judgement call.
#
# W1's fact column now carries the community half — §W1's `Height` row, a taped `Trunk · DBH`
# reading in place of the city's bucket, and a `Beloved` row — read from
# `GET /api/v1/public/trees/{id}` (#163).
#
# No tester can see any of it, for two independent reasons and either would be enough:
#
#   1. The web is not deployed (W-E). `cypress.app` serves nothing and every share card the app
#      has ever produced is still a dead link.
#   2. **The endpoint is not deployed either.** Merging #163 did not redeploy `cypress-sync`.
#      Measured on 2026-09-11: `/health` answers 200, and `GET /api/v1/public/trees/<uuid>`
#      answers Go's bare `404 page not found` — where a route that IS registered but takes another
#      verb answers `405`, which `/api/v1/sync` and `/api/v1/devices/register` both do.
#
# So the state this ships in is the one where the page renders the city record and says it could
# not ask. No Swift changed and no build is minted.

internal: the public tree page reads the community half — live height, taped diameter, beloved state — from the public API, and renders the city record alone when it cannot. Nothing is deployed.
