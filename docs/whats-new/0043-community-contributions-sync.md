# Backfill, and the only one there will ever be.
#
# Build 43 shipped with no "What to Test" at all — no build before this mechanism existed had
# one. These lines describe what landed in build 43 (ticket #s34, `outbox.kind` widened to
# spec §3.4's nine mutations) so that the first build to carry notes covers the gap instead of
# opening with a changelog that skips a release.
#
# It is a backfill and not a claim that build 43 was announced: nothing here is dated, and a
# tester reading it on build 44 reads it as "this is what the app can do now", which is true.
#
# Checked against the code rather than against the ticket, because a changelog is a claim:
#   - `Cypress/Core/Models/OutboxItem.swift` — the ten cases
#   - `server/internal/api/sync.go` — `syncKinds` accepts all ten
#   - the same file's header — nine of the ten are RECORDED and not materialized, which is why
#     the last line below is here and is not an apology

Trees you add now sync to the server instead of only living on this device.
Naming a tree's species, correcting a name, and reporting a wrong species or a record with no tree behind it now sync as well.
Photo votes, removing a photo you took, and logging a hazard you passed on to 311 now sync too.
Each of these shows up in the sync queue under its own name, so you can see what has been sent and what is still waiting.
For now the server records these contributions rather than acting on them — your corrections and votes will not change what other people see yet.
