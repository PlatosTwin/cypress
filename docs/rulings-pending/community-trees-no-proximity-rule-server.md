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

- On `POST /trees`: nothing. The route answers `200` with `applied` or `duplicate`, or a
  `validation_failed`, `unauthorized` or `server_error` envelope.
- On `add_tree` and on `location_correction`: nothing. A move can still be refused with `forbidden`
  (not the adder), `not_found` (a tree the caller cannot see, or one this service does not hold) or
  `validation_failed`.
- On `tree_withdrawal`: "other people have added to this tree, so it stays on the map" (decision 8).
  This is now the only `conflict` the community-tree kinds return.

**The error envelope has no `detail` any more.** `detail.candidates` existed only to carry the
proximity candidates. No route sends it, so `apierr.Error.Detail` was removed. The envelope is
`{"error": {"code", "message", "retryable"}}` on every route.
`server/testdata/proximity_conflict.json` is no longer produced or checked by any Go test; it is
left in place because the Swift suite reads it, and the phone-side round decides its fate.

**What stops a duplicate now.** Only identity, never distance:

- A second send of the same `add_tree` item (the same `client_uuid`, for example after a lost
  response) hits the contribution dedupe and answers `duplicate`.
- A second send of the same tree id, on either door, hits `community_trees`' primary key
  (`ON CONFLICT (id) DO NOTHING`) or the erase tombstone and makes no second tree. On
  `POST /trees` it answers `duplicate`.
- A tree sent again under a **new** tree id is a second tree. Before 2026-11-14 the 10 m rule
  refused it; now nothing does. The phone mints the tree id once per add, so this happens only if a
  person adds the same tree twice, which the owner's ruling accepts.

**Old phones.** An installed build still refuses on the phone (`LocalAPI.addTree`,
`LocalAPI.correctLocation`) before it queues anything, so it is stricter than the service and
never sends something the service now treats differently. Such a build still decodes a
`ProximityConflict` if it gets one; it will no longer get one.
