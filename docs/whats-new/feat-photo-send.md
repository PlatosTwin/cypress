# The send round builds the whole path and still cannot claim it to a tester, on purpose.
#
# Everything is here — `AppSchema` v18 gives each binary a row, `OutboxSendSink` carries
# `uploadPhoto`, and server migration 003 makes `POST /photos/begin` retryable — but the service
# refuses to boot without the photo bucket's credentials (`PHOTOS_AWS_*`), and that bucket does
# not exist yet. The orchestrator creates it and deploys; the commands are in this round's PR.
#
# Until that happens an upload fails and screen 17 shows a retry row. That is honest behaviour
# and it is not something to tell a tester about, so this note stays `internal:` — the README's
# "say only what shipped", where the thing that has not shipped is the far end.
#
# **The line this round wants is already drafted and deliberately not written here:**
#
#     Photos you add now upload with your notes, and appear on the tree for everyone.
#
# It goes in a new note by the round that verifies a photograph actually arriving in the bucket.
# Writing it today would be the overclaim `feat-nyc-publish.md` recorded making once already —
# a sentence true of the code and false of the deployment.
#
# ONE THING TO CHECK BEFORE THIS BUILD REACHES TESTERS: `AccountCopy.storageBody` now says
# "Photos you add from now on upload too". That sentence is in the app, not in this file, and it
# becomes true at deploy rather than at merge. If the bucket is not live, the app is making a
# promise the server cannot keep — the merge order in the PR (bucket, deploy, then this build)
# exists for that reason and is not a formality.

internal: builds the photo send path end to end (AppSchema v18, the send sink's photo method, server migration 003); it cannot upload until the photo bucket exists, so nothing is tester-visible yet.
