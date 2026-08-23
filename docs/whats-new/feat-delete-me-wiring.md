# The wiring round for `DELETE /me` (ERRATA E272, the owner's ruling of 2026-08-23).
#
# Deleting an account has always emptied this phone. Until this branch it stopped there: the
# service kept the account, because `RoutedAPI.deleteAccount` routed local and `AccountModel`
# was holding the local API rather than the router. Both halves are fixed here, so the tap now
# reaches `DELETE /me` first and deletes nothing anywhere if the service cannot be reached.
#
# TRUE AT MERGE, AND THE ONE THING THAT WOULD MAKE IT FALSE: the running `cypress-sync`
# deployment must serve `DELETE /me`. It does — verified on 2026-08-22 against
# `https://cypress-sync.fly.dev`, whose `/health` reports git_sha 5ea07cb, an ancestor of
# origin/main that contains `server/internal/api/me.go`; an unauthenticated
# `DELETE /api/v1/me` answers 401 rather than 404, so the route is mounted. The only server
# drift between that sha and origin/main is two comment-only hunks. **No deploy is required
# before this merges.** If that ever stops being true, this line is an overclaim and the
# README's deletion mechanism is how to take it back.

Deleting your account now removes it from our service too, not just from this phone. If it can't reach the service, nothing is deleted and it tells you so.
