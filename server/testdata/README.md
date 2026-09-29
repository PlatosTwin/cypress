# `server/testdata/` — golden wire fixtures

One file per response shape that **reconstructs a client-owned Swift type**. They exist because a
cross-language contract cannot be proven from one side.

## What the Go tests do with these

`internal/api/golden_test.go` serializes a fixed value and compares it byte-for-byte against the
file. That catches a key being renamed, a field being dropped, a timestamp growing fractional
seconds — anything that changes the bytes.

**What it cannot catch is the thing that matters most**: whether Swift can decode them. A Go test
comparing Go output to a file a Go author wrote proves the handler agrees with that author's
transcription of `Tree`, not with `Tree`. That is exactly how `"placement":"unknown"` and
`{"lat":…,"lon":…}` shipped past a passing test.

## What step 4 must do — this is the other half of the contract

`RemoteAPI`'s implementation round (#158 step 4) **must add Swift decode tests against these exact
files**, in `CypressTests`, decoding each one into the type named below with a plain `JSONDecoder`
and `dateDecodingStrategy = .iso8601`. Not a copy of the JSON pasted into a Swift string literal —
these files, read off disk, so the two halves cannot drift.

| file | decodes into | notes |
|---|---|---|
| `proximity_conflict.json` | the whole error body; `detail.candidates` is `[NearbyTree]` | the shape `ProximityConflict` is built from |
| `grove.json` | `entries[].record` is `GroveRecord` | the rest of the object is server-owned and snake_case |
| `community_trees_tile.json` | `trees` is `[Tree]` | `GET /community-trees`, a first fetch (no cursor). The envelope (`tile`, `withdrawn_tree_ids`, `next_cursor`, `has_more`) is server-owned and snake_case. Tree `5b0c3f1e-…-1f2a3b4c5d01` has a species: assert its `speciesCurrentID` is **non-nil**, because a key drift decodes it as a silent nil. Find it by id, not by position: the order is `(updated_at, id)` and two trees here share a day. `address` is null for everyone on this route. `createdAt` and `updatedAt` are midnight UTC, because community-tree dates travel at day precision. |
| `community_trees_tile_delta.json` | `trees` is `[Tree]`; `withdrawn_tree_ids` is `[UUID]` | the same route, from the first fetch's cursor: one tree moved and renamed, one new, one withdrawn, one erased (a tombstone). Both lists are non-empty. A tree in `trees` can lie outside the tile (a pin moved out of it), so the cache keys on `id`. `next_cursor` is opaque, sealed, and always present: store it as a string and send it back unchanged, never parse it. |
| `tree_profile_community.json` | `community_tree` is `Tree?` | `GET /trees/{id}` for a published community tree, asked by a stranger. The six keys that existed before, plus `community_tree`, `added_by_you` and `is_published`. Assert `community_tree.speciesCurrentID` non-nil, and that `added_by_you` is false and `is_published` true. |
| `tree_history.json` | server-owned, snake_case; `from_coordinate` / `to_coordinate` are `Coordinate?` | `GET /trees/{id}/history`, newest first, dates truncated to the day, no actor field. `kind` and `placement` must decode tolerantly (an unknown case), because the vocabulary is an allow-list that can widen. The oldest event is `added`, at the position the tree went live at: the tree was moved while private, and neither that move nor its first position is served (decision 13). |
| `tree_profile_city.json` | `community_tree` is `Tree?` | `GET /trees/{id}` for a **city** tree with community data (photos, visits). `community_tree` is **null** and `added_by_you` / `is_published` are false. This is the ordinary case for most ids, not an error. |
| `tree_profile_unknown.json` | same | `GET /trees/{id}` for an id nobody has ever sent: the empty answer, `community_tree` null. |
| `tree_profile_hidden.json` | same | `GET /trees/{id}` for a community tree hidden from the caller (somebody else's unpublished tree, withdrawn, taken down or erased). **Byte-for-byte `tree_profile_unknown.json` with the id replaced**; the Go test asserts it, so the answer is not an oracle. |

## The two public-read fixtures decode into **nothing Swift**, and that is the point

`public_tree.json` and `public_tree_empty.json` are `GET /api/v1/public/trees/{id}`, the one
unauthenticated read. They are here for the same reason as the others — a cross-language contract
cannot be proved from one side — but the other language is **TypeScript**, not Swift: the web app
renders this page server-side and the phone has no use for the route at all (it reads its own
contributions locally and the city layer from the installed pack, R36).

So no Swift decode test is owed for these two, and they are **snake_case throughout**, which is the
documented rule rather than an exception to it. The rule below says a payload that reconstructs a
client-owned Swift type speaks that type's keys and everything else speaks the API's;
`TestPublicBodyIsSnakeCaseThroughout` is what holds these on the second side of it.

**What the web owes them instead:** the round that builds W1 reads these files as its own fixtures,
so a change to either moves both ends. `public_tree_empty.json` is not a curiosity — it is the answer
for a tree this database has never heard of, for a tree whose contributions are all withdrawn, for a
tree that simply has none, **and for a tree one or two accounts have favorited**, byte-identical in
all four. The page renders it, and it must render it as "nothing is known here" rather than as an
error.

`beloved_by` is `null` in that file and `3` in `public_tree.json`, and the difference is the whole
of the beloved floor: the number publishes only above it, so a null there means "fewer than three,
and this service will not say which". A web page that rendered `beloved_by` as `0` would be inventing
the fact the floor withholds. `public_tree.json` is seeded with three accounts **and one device**
favorite; it reads `3`, which is the owner ruling of 2026-09-10 visible in the fixture itself.

## The key convention, because it is not uniform and the non-uniformity is deliberate

A payload that reconstructs a client type speaks **that type's synthesized Swift property names**
(camelCase: `distanceM`, `speciesCurrentID`, `checkIns`). Everything else — envelopes, sync results,
request bodies — is snake_case.

The reason is in `internal/api/wire.go` and is worth knowing before "fixing" the inconsistency:
Swift's `.convertFromSnakeCase` maps `species_current_id` to `speciesCurrentId`, which does not
match `speciesCurrentID`, and because that property is optional the mismatch decodes as `nil`
**without throwing**. A uniformly snake_case body would therefore lose fields silently.

Timestamps are RFC3339 at second precision in UTC, because `JSONDecoder`'s `.iso8601` uses
`.withInternetDateTime` and rejects fractional seconds.

## The community-tree reads: what the client must not infer

These are contract, not incidental behavior. C1 and C2 build on them.

- **`community_tree: null` does not mean deleted.** It means "not a community tree this caller may
  see": a city tree, an unknown id, **or** a hidden one. The adder's own tree answers null to
  everybody else until it is published, including when the adder declined the open license (the
  claim then leaves it unpublished). **Never evict a local row on a null.** A cached community tree
  leaves the cache only through `withdrawn_tree_ids`.
- **`withdrawn_tree_ids` can name ids from anywhere in the world.** Erase-door tombstones carry no
  position, so every tile's delta reports every once-public tombstone after its cursor. Drop the ids
  you hold and ignore the rest; do not treat an unknown id as an error or as belonging to this tile.
- **A tree in `trees` can lie outside the tile** it came from (a pin moved out of it after going
  live). Key the cache on `id`.
- **A first fetch (no cursor) can report removals** from the last 25 seconds: a tree withdrawn while
  the snapshot was being paged, or just before it began. Apply them like any other.
- **The tile's `validation_failed` means the cursor is no longer good** (a server key rotated, a
  corrupted store, a cursor from another tile). Drop the stored cursor **and** the trees fetched
  through it, fall back to what is local, and take a fresh snapshot. It is not a reason to retry the
  same cursor.
- **The history's 404 means "no history"**, not an error to surface: a city tree, an unknown id, and
  a hidden tree all answer it alike. The adder's own unpublished tree answers 200 with no events: its
  private life is on the phone, not the server.
- **History starts at going live** (decision 13). The oldest event is `added`, at the position and on
  the day the tree was published. A move made while the tree was private is never served, in the
  history or in any tile.
