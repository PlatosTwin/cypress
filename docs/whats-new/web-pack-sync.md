# `internal:`, for the reason W-B's and W-C's notes gave, one milestone later.
#
# The web app reads published city packs out of a directory and nothing put them there. This adds
# the step that does: `web/scripts/sync-packs.mjs`, run on the machine, filling the mounted volume
# from the same public catalog the phone installs cities from — hashed against the catalog's sha256
# before a file is put in place, idempotent on a second run, and refusing a pack published past the
# generation this build reads.
#
# No tester can reach any of it. Nothing is deployed, the volume it fills does not exist yet, and
# `ShareCopy.publicURLPrefix` still points at a hostname a third party owns, so every share link in
# the wild is as dead today as it was yesterday. No Swift changed and no build is minted.
#
# The note that is not `internal:` is the one written on the day a tester can open a share link and
# see a tree.

internal: the web server's pack directory can be filled and refreshed from the published catalog, with every file verified against its published hash before it is put in place.
