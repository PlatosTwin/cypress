# `internal:`, and the reason is narrower than W-C's and W-D's: those rounds built something a
# tester could not reach. This one builds nothing a tester could reach even after it merges.
#
# W-E is "it is on the internet", and this pull request is the half of it that lives in the
# repository: the volume, the pack directory, a health check, and `GET /health`. **Merging it
# deploys nothing.** The `cypress-web` app does now exist on Fly — the orchestrator created it while
# this round was open — and it is empty: no machines, no volume, nothing deployed to it, answering
# on no hostname. No agent ran `flyctl`; the orchestrator does the rest afterwards, against this
# file. (An earlier draft of this paragraph said the app did not exist, which was true when it was
# written and stopped being true mid-round.)
#
# Also not tester-visible, and worth saying because it looks like it might be: the site's domain is
# now `cypressatlas.org` (owner ruling, 2026-09-13, superseding `cypressgrove.app`). No certificate
# and no DNS in this round — the owner's framing is that the site will not land there live for a
# while — so the name appears in prose and in `fly.toml` and resolves to nothing. No Swift changed;
# `ShareCopy.publicURLPrefix` still points at a hostname that is not the owner's, so every share
# card in the wild is as dead today as it was yesterday.
#
# The note that is not `internal:` is still the one after the deploy actually runs and a share link
# starts resolving — which needs the Swift change as well as the machine.

internal: the web app's Fly deployment is written down and testable — a mounted pack volume, a health endpoint that says whether the packs arrived. Nothing is deployed.
