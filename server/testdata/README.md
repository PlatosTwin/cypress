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
