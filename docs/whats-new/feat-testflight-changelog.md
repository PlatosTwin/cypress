# This branch builds the mechanism; it does not change the app. The archive it mints is
# byte-identical to build 43's — `Tools/appstore_connect.py` is not in the ships predicate's
# exempt set, so the merge takes a build number anyway (the deny-list direction, deliberate).
#
# This is exactly the case the escape hatch exists for, and it is the first user of it.

internal: adds the TestFlight release-note mechanism and its CI check; nothing in the app changed.
