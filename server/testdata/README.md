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
