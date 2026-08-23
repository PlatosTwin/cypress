# The round is E264's, and what it shipped is the deletion half, not the upload.
#
# There is deliberately no tester-visible line here, and the reason is exactly the one the
# README names: "do not describe a mutation the server records but does not act on". The
# service now genuinely acts on a `photo_withdrawal` — it tombstones the photograph and stops
# serving the bytes — but **no photograph reaches the service at all**, because the client's
# send path for binaries is not built (ERRATA E264, and the storage decision it waits on is
# stopped-on for the owner in this pull request). A tester cannot observe any difference.
#
# The line this round wanted to write — "photos you add now appear for everyone" — would have
# been the overclaim the README forbids, and it is the same overclaim the PR body explains was
# not reached. It gets written by the round that wires the upload, once there is a bucket to
# put a photograph in.

internal: wires `photo_withdrawal` through `POST /sync` so a withdrawal stops the service serving the photograph; no photo upload path exists yet, so nothing is tester-visible.
