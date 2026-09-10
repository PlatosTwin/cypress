# Reviewers: this branch DOES mint a build, and that is not an oversight. Tools/fetch_seed.sh
# runs in every CI job (.github/actions/prepare, release included) and places the seed the app
# bundles, so it is a build input by the same argument the workflow already makes about
# Tools/build_seed.py. The pinned bytes cannot change — they are verified by sha256 — but the
# script that chooses and places them did, so it ships. The rest of the harness round is #153,
# where the three non-shipping scripts are exempt.
internal: bounds the simulator boot, stops the collision guard matching its own caller, and gives an environment-refused run its own verdict; no app code changed.
