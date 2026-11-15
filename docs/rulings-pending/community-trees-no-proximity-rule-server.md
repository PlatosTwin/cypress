# Rulings pending: what the service answers after the 10 m rule stopped refusing (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. It records the service half of
`community-trees-no-proximity-rule.md` (the owner's ruling of 2026-11-14); it is the author's
design reading of that ruling, not a new owner ruling.

---

### R??? — The service has no proximity refusal, and `conflict` no longer means "a tree is near"

**What the service does now.** `POST /trees`, the `add_tree` kind of `POST /sync`, and the
`location_correction` kind of `POST /sync` do not look at other trees' positions. A tree or a moved
pin within 10 m of another tree is recorded like any other.

**What `conflict` (409) can still mean.**

- On `POST /trees`: nothing. The route answers `200` with `applied` or `duplicate`. Otherwise it
  answers an error envelope: `rate_limited` (the `authenticated` wrapper's limiter),
  `unauthorized` (no live session or device token), `validation_failed` (a body that cannot be
  read, or a missing id, an off-map coordinate, or a placement or land context outside the
  vocabulary), or `server_error`.
- On `add_tree` and on `location_correction`: nothing. Each item still gets one of the per-item
  results every kind can get: `forbidden` when the item names another account or device, or a
  signed-out caller sends an item with a user id; `validation_failed`; and `server_error`.
  `location_correction` can also be refused with `forbidden` (the caller is not the adder) or
  `not_found` (a tree the caller cannot see, or one this service does not hold). A replay of
  either kind is `duplicate`.
- On `tree_withdrawal`: "Other people have added to this tree, so it stays on the map." (decision 8).
  This is now the only `conflict` that a community-tree kind returns. The only other `conflict` in
  the service is the device claim's "This device is already linked to another account."

**The error envelope has no `detail` any more.** `detail.candidates` existed only to carry the
proximity candidates. No route sends it, so `apierr.Error.Detail` was removed. The envelope is
`{"error": {"code", "message", "retryable"}}` on every route.
The fixture `proximity_conflict.json` under `server/testdata/` is no longer produced or checked by
any Go test. The service round left it in place because the Swift suite read it; the phone-side
branch (`feat/no-proximity-refusal-phone`) deletes it with the Swift test that read it.

**What stops a duplicate now.** Only identity, never distance:

- A second send of the same `add_tree` item (the same `client_uuid`, for example after a lost
  response) hits the contribution dedupe and answers `duplicate`.
- An `add_tree` for the same tree id under a new `client_uuid` answers `applied`, because its
  contribution is new, and makes no second tree: `insertCommunityTree` keys on the tree id
  (`ON CONFLICT (id) DO NOTHING`) and checks the erase tombstone.
- A second `POST /trees` with the same tree id makes no second tree, for the same reason, and
  answers `duplicate`.
- A tree sent again under a **new** tree id is a second tree. Before 2026-11-14 the 10 m rule
  refused it; now nothing does. The phone mints the tree id once per add, so this happens only if a
  person adds the same tree twice, which the owner's ruling accepts.

**Old phones.** An installed build still refuses on the phone (`LocalAPI.addTree`,
`LocalAPI.correctLocation`) before it queues anything, but it checks only the trees in its own
local data: the city file and the community trees it has fetched. It can therefore send an add, or
a move, within 10 m of a community tree it has never fetched. The old service refused that with
`conflict`; the new service applies it. That is the outcome the owner's ruling intends. Such a
build still decodes a `ProximityConflict`; it will no longer receive one.
