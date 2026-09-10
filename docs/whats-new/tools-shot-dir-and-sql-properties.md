internal: names the grove's SQL so its census pins by property, and corrects the screenshot-directory instructions; no tester-visible change.

# Two backlog items, neither of which touches a screen.
#
# 1. `ContributionStore.groveRecordsSQL`, `ContributionStore.ownHeroPhotoCandidatesSQL` and
#    `CommunityTreeStore.treesSQL` are hoisted out of their methods, so
#    `GroveStatementCensusTests` pins all seven of a grove read's statements to the properties
#    that name them instead of deriving four by probe. The second, byte-identical copy of the
#    tallies text inside `heroPhotoIDs(treeIDs:connection:)` is gone with them. No statement text
#    changed — the census's own set assertion is what proves that, since it compares what the app
#    prepares against the properties byte for byte.
#
# 2. The four screenshot suites' doc comments said to pass `CYPRESS_SHOT_DIR` on the `xcodebuild`
#    command line. That is a build-setting override, it reaches no process, and it fails by doing
#    nothing. The spelling that works is an exported `TEST_RUNNER_CYPRESS_SHOT_DIR`; it is argued
#    once in `Tools/run_tests.sh`'s header with the evidence, and `ShotDirectoryConventionTests`
#    keeps the key the writers read and the name the prose exports in agreement.
