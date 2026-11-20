# `internal:` because no behavior changed. This adds a test and a classification type that the app
# never calls; both deletion doors do exactly what they did before, including the one gap the guard
# found (`species_assertions`), which is recorded and left for its own change.

internal: a test now derives every table that names a person from the live schema and fails when account deletion does not account for one.
