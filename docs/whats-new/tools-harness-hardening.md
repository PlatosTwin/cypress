# Reviewers: nothing here reaches the app, and nothing here can. The files changed are
# Tools/run_tests.sh, Tools/verify_test_log.sh and a new Tools/test_harness_guards.sh — all three
# exempt from minting a build (NO_ARCHIVE), because the scheme's only buildable is the app and
# project.pbxproj has no shell-script build phase. Tools/fetch_seed.sh IS a build input and its
# diagnostics were moved to tools/fetch-seed-diagnostics for that reason.
internal: bounds the simulator boot, stops the collision guard matching its own caller, and gives an environment-refused run its own verdict; no app code changed.
