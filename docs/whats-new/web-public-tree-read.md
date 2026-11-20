# Why this is an `internal:` line and not the obvious sentence.
#
# The obvious sentence — "anyone can now open a tree's page without an account" — would be true of
# this code and false of anything a tester can reach, for three independent reasons, and the README
# forbids exactly that: say only what shipped.
#
#   1. Nothing consumes the endpoint. The page that will read it is milestone W-C, which is not
#      written; `web/` on main is scaffolding that says so on its own index.
#   2. This pull request is code, tests and rulings. `cypress-sync` is not redeployed by merging
#      it, so until somebody deploys, the deployed service still answers 404 on this route.
#   3. No Swift changed, so the app is unaffected and no tester's build moves.
#
# When a page renders from it on a deployed service, that is a tester-visible change and it earns a
# note of its own, written at the moment it became true.

internal: the sync service answers what is publicly true about one tree with no credential; nothing reads it yet and no build is minted.
