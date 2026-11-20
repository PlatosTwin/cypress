# Why this is an `internal:` line and not the obvious sentence.
#
# The obvious sentence — "you can now report that the city's record of a tree is wrong" — is true of
# this code and false of anything a tester can reach. This PR is part 1 of R79: the migration, the
# record, the two verbs, and the profile offer that says a city row is disputable. **There is no
# control on any screen.** The dispute sheet is PR-C of the same round, and drawing an action here
# without it would mean inventing the sheet behind it, which DECISIONS constraint 21 makes a
# stop-and-ask.
#
# So a tester who installs this build sees a city tree's profile exactly as it looked before. When
# the sheet ships, the line belongs in a note of its own, made at the moment it became true.

internal: adds the city-inventory dispute record, its schema and its two queue kinds; no tester-visible change until the dispute sheet ships.
