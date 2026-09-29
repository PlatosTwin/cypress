# Errata pending — `GroveSpeciesKnown`'s unscoped cast (server, 2026-09-10)

Unnumbered, per CLAUDE.md "Numbering and shared files". One entry. Found by PR #159's adversarial
reviewer, reproduced independently by that PR's author against a throwaway Postgres 16.15 before
this was written. **It is not PR #159's defect** — it has been reachable since `species_claim`
became a kind in `002_community_mutation_kinds.sql` — and it is filed here because that PR admits a
new payload family into the same unfiltered read.

---

### E??? — One non-UUID `speciesID` in any payload permanently 500s that identity's Species tab

`store.GroveSpeciesKnown` (`server/internal/store/reads.go`) answers `GET /me/grove/species`:

```sql
SELECT (payload->>'speciesID')::uuid AS species_id, min(occurred_at) AS first_met
  FROM contributions
 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
   AND deleted_at IS NULL
   AND payload->>'speciesID' IS NOT NULL
 GROUP BY species_id
 ORDER BY first_met ASC
```

Owner and `deleted_at`, and **no filter on `kind`**. So the cast is applied to every payload that
carries a key spelled `speciesID`, whatever kind of contribution it belongs to, and the cast can
fail. When it does, the whole query fails, the handler answers `500 server_error`, and — because the
offending row is a stored contribution the phone cannot un-send — that identity's Species tab is
broken for good.

**Reproduced, three arms, against Postgres 16.15 in Docker (destroyed afterwards):**

| arm | item | `GET /me/grove/species` |
|---|---|---|
| valid id on a dispute | `data_dispute` payload with a top-level `"speciesID":"<uuid>"` | `200 {"known":[{"species_id":"d376bb09-…"}],"total":1}` |
| invalid id on a dispute | same, `"speciesID":"not-a-uuid"` | `500 {"error":{"code":"server_error","message":"Something went wrong on our end.","retryable":true}}` |
| invalid id on an existing kind | `species_claim` payload `{"speciesID":"also-not-a-uuid"}` | `500`, identical |

The third arm is the one that fixes the blame: this is a live defect in the current service, not
something PR #159 introduces. Both bad items were answered `applied` by `POST /sync` — the write
path validates nothing about `speciesID` for either kind — so the row is stored and the read stays
broken until somebody deletes it in SQL.

**The valid-id arm is a defect too, and quieter.** A dispute is a complaint about a species, not an
encounter with one. A top-level `speciesID` that parses enrols that species in "species you have
met", recorded because the person said the city had it wrong.

**004 reasoned about exactly this hazard, one file away, and designed around it.**
`server/migrations/004_measurement_withdrawal_kind.sql` chose `upper(payload ->> 'id')` over
`(payload->>'id')::uuid` for its two indexes and its two lookups, and said why in as many words: a
cast "can *error* here rather than merely miss … nothing in the standard promises Postgres evaluates
the `kind` qual before the cast. A payload of some other kind carrying a non-UUID `id` would then
fail the whole request."

**That is a related worry and not this defect, and the two are worth keeping apart.** 004 was
guarding against a planner evaluating a cast *ahead of* a `kind` qual that would have excluded the
row — an ordering that neither this PR's author nor its second reviewer could reproduce on
Postgres 16, in three shapes each, and which PR #159's prose now marks unverified where it is
cited. This entry needs no such ordering: `GroveSpeciesKnown` has **no `kind` qual at
all**, so its cast reaches every kind's payload by construction. What the two share is the remedy,
which is why 004 is worth citing here at all — comparing extracted text never errors on a value it
was not meant to read, whatever the planner does. The unsafe instance 004 cites by name —
`GroveSpeciesKnown` — was left as it was, and 004's own note is the reason nobody should call this
one unforeseeable.

**Two things are worth separating in whatever round fixes it.**

1. *The 500 is a query-shape defect.* Narrowing the read to the kinds whose `speciesID` means "I met
   this species", or filtering to values that parse, or both. `kind IN (…)` is the smaller change
   and it is the one that stops a new kind from breaking the read by accident; a `WHERE payload->>
   'speciesID' ~ '^[0-9a-fA-F-]{36}$'` guard alone would leave the meaning question open.
2. *Who belongs in "species you have met" is a product question*, and it is R79's to answer for
   disputes now that a dispute can name a species. This entry does not decide it.

**What PR #159 does instead, since neither belongs in a payload-validation round:** its wire contract
forbids a top-level `speciesID` on a dispute payload — a suggested species travels as
`suggestions["species_id"]`, where nothing casts it — and says so beside `dataDisputePayload` in
`server/internal/api/sync.go`, together with the general rule that not every payload read in this
service is kind-scoped — three of the four are, and this one is not — so a new top-level key must be
checked against all of them before it is minted. That is a contract the client keeps, not a gate:
the payload decode is lenient by design, so nothing in the handler could refuse the key even if it
wanted to.

---

### Fixed (server, 2026-09-28, branch `server/grove-species-known-scope`)

**Reproduced first, through the handler, on main at `bb4d08f`** against a throwaway Postgres 16.14:
one `GET /me/grove/species` answered `200` with the three right species, and after a row carrying
`{"speciesID":"not-a-uuid"}` was written beneath them, the next read answered
`500 {"error":{"code":"server_error",…}}`.

**What the read now does.** `store.GroveSpeciesKnown` never casts in SQL. It selects
`lower(payload->>'speciesID')` where `jsonb_typeof(payload->'speciesID') = 'string'`, groups on that
text, and parses each group in Go with `uuid.Parse`, skipping what does not parse. Nothing in that
SQL can error on a value it reads — `->`, `->>` and `jsonb_typeof` answer NULL for an absent key or
a non-object payload, and `lower` is total — so **rows already poisoned in production are harmless
whatever their kind**, with no migration and no deletion. That claim does not rest on the kind
filter below: with the filter removed, the poisoned-row test still passes (measured, arm 2 below).

**Which kinds it reads, and the premise this corrected.** It is scoped to `store.MetSpeciesKinds` =
`visit`, `observation`, `measurement`, `care_event` — the four kinds the client's own Species tab
unions (`GroveQueries.ownContributions`). Two facts decided that, both read from the client rather
than assumed:

1. **The kinds that really carry a `speciesID` are `add_tree`, `species_claim` and
   `species_correction`, and all three are a person *naming* a community tree's species.** The
   client refuses exactly those by rule: `GroveQueries.knownSpecies` reads city-inventory trees
   only, because a self-asserted species on a community-added tree would let a contributor raise
   their own ring by adding a tree. So the "quieter" arm above was wider than disputes: every
   species a person named on a community tree was put on their Species tab at refresh, after the
   phone's own paint had left it off.
2. **No sighting kind carries a `speciesID` in any client payload** — `Visit`, `TreeObservation`,
   `TreeMeasurement` and `CareEvent` have no such field. So against today's clients the scoped read
   answers an empty list, and the phone's local half is the whole Species tab. That is the correct
   answer to the question as the client defines it, and it was already the answer for everyone who
   never named a community tree's species. The cross-device half of the tab — a species met on
   another phone of the same account — is therefore still unanswered by the service; the phone
   could derive it from `GET /me/grove`'s tree ids and its own city file. That is a client
   question for another round, not a regression of this one.

The second item answers this entry's product question for disputes as a side effect: a dispute is
not a sighting, so no dispute can enrol a species, top-level `speciesID` or not.

**This is a tester-visible change, accepted by the owner (2026-09-28), not a change "nothing a
tester sees."** Item 1 above is a fact about the *past*: what item 2 says is true only of a tester
who never named a community tree's species. Anyone who did — through `add_tree`, `species_claim`
or `species_correction` — had that species added to their Species tab on the next refresh, before
this round. After this round's deploy, the next refresh drops it, because the read now answers an
empty list for those three kinds. A species that a tester's own refreshed tab was showing
yesterday can be gone today, and the ring's numerator can drop by the same species. Saying the
species "the phone's own tab already left off" are the ones affected is true only of the very
first paint, before any refresh ever ran — the release note in `docs/whats-new/` states the effect
a tester will actually notice, and is not `internal:` for that reason.

**The write path.** `species_claim` and `species_correction` now refuse a `speciesID` that is absent
or not a canonical UUID, `validation_failed`. That is terminal for the phone's queue, and it is safe
here for a checkable reason: `SpeciesStatement.speciesID` is a non-optional Swift `UUID` that
`JSONEncoder` can only write in the canonical form, and `RemoteAPI.sync` decodes every row through
`OutboxPayload.decode` before sending — a malformed one never leaves the phone. `add_tree` already
refused the same malformation through its typed decode, so the three kinds that carry a
`speciesID` now agree. The sighting kinds are not tightened: they carry no `speciesID`, and the read
tolerates anything they could hold.

**Tests** (`server/internal/api/grove_species_test.go`, all through the handler):
`TestAPoisonedSpeciesIDDoesNotBreakTheSpeciesTab` (a poisoned row of all nineteen kinds, plus
twelve other non-UUID shapes on a `visit`, beneath three real sightings; two reads, equal),
`TestOnlyASightingPutsASpeciesInTheTab`, `TestASpeciesStatementMustNameASpecies`,
`TestASpeciesStatementKeyIsMatchedExactly` (the three case-folded-key shapes, both kinds, and a
check that the refused item was never stored).
`TestWithheldKindsProduceTheEmptyAnswer` posted a species claim with no species and now sends one.

**Red-proofs, each read for its message:**

| arm | `TestAPoisoned…` | `TestOnlyASighting…` |
|---|---|---|
| main's unscoped cast restored by file copy | red: `GET /me/grove/species returned 500, want 200: {"error":{"code":"server_error",…}}`, on the read *after* the poison (the calibration read before it passed) | red: `a never_existed_report enrolled species …` |
| text-and-parse kept, kind filter removed | green | red: `a species_claim (through POST /sync) enrolled species …` |
| kind filter kept, cast put back in SQL | red: the same 500 | green |

and the write-side refusal disabled: `species_claim with {…"speciesID":"not-a-uuid"}: "applied"
(<none>), want failed validation_failed`. Each half is load-bearing on its own.

**The write-side refusal matched the key case-insensitively, and that has been tightened.**
`encoding/json` matches a struct field's tag case-insensitively when no exact match exists, so a
struct decode of `speciesID` also accepted `speciesid` and `SPECIESID` — keys no real client sends
and `store.GroveSpeciesKnown`'s `payload ->> 'speciesID'` never reads, because `jsonb` matching is
exact. Each of `{"speciesid":"<uuid>"}`, `{"SPECIESID":"<uuid>"}` and
`{"speciesID":null,"speciesid":"<uuid>"}` was answered `applied` and stored a row with
`payload->>'speciesID' IS NULL` — the exact worthless, un-actionable record this refusal exists to
keep out, just reached by a spelling the check didn't compare against. Fixed by decoding into
`map[string]json.RawMessage` and looking up the exact key `"speciesID"`, in
`speciesStatementSpeciesID` (`server/internal/api/sync.go`). Red-proofed by reverting to a
case-insensitive struct decode: `TestASpeciesStatementKeyIsMatchedExactly` went red on
`species_claim with {"treeID":"…","speciesid":"…"}: "applied" (<none>), want failed
validation_failed`, restored by copying the file back and reconfirmed green.

**Counts,** `go test -json ./...` against a throwaway Postgres 18, counted from the JSON events
(subtests included): main `bb4d08f` 222 passed, 0 skipped, 0 failed; this branch, after both the
scope fix and the key-matching fix, 226 passed, 0 skipped, 0 failed. With
`CYPRESS_TEST_DATABASE_URL` unset, main reports 68 passed and 147 skipped; this branch reports
68 passed and 151 skipped — both while every package prints `ok`. The two no-database figures are
different trees' counts, not the same reading stated twice: this branch's four new tests
(`TestAPoisonedSpeciesIDDoesNotBreakTheSpeciesTab`, `TestOnlyASightingPutsASpeciesInTheTab`,
`TestASpeciesStatementMustNameASpecies`, `TestASpeciesStatementKeyIsMatchedExactly`) all need the
database, so they move from "doesn't exist" to "skipped" rather than to "passed" when it is absent.
