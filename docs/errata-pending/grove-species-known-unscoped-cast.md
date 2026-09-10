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
