# Rulings pending — community trees, the server reads (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. No code comment cites this filename.

These record what **PR S2** (`server/community-trees-reads`) decided where the round's design (§3C,
§3D, §3E), the owner's decisions 1–12 and the orchestrator's rulings of 2026-09-28 left a choice.
Each is a ruling within delegated authority, logged for review. None reverses an existing ruling.
The owner should look at the first two.

---

### R??? — A community tree hidden from a caller is answered exactly as an id nobody sent

**Decided by:** PR S2. **Needs owner review:** no; it extends the public read's rule.

"Hidden" means: somebody else's unpublished tree, a tree its adder withdrew, a tree an operator took
down, and a tree the erase door deleted (tombstoned). The adder sees their own unpublished tree.
Nobody, the adder included, sees a withdrawn or taken-down one.

| Route | What a hidden tree gets |
|---|---|
| `GET /trees/{id}` | 200, and byte-for-byte the body an unknown id gets: no photographs, `visit_count` 0, `community_tree` null, `added_by_you` and `is_published` false. |
| `GET /public/trees/{id}` | 200, and byte-for-byte the empty answer (`public_tree_empty.json`'s shape). |
| `GET /photos/{id}` | 404 `not_found` for a photograph of a hidden tree, whoever took it. |
| `GET /trees/{id}/history` | 404 `not_found`, the same answer as a city tree's. |

Why not a `not_found` on the profile: the profile already answers 200 for every city tree, which
this service has never heard of. A `not_found` for a hidden community tree would be an oracle that
says "a community tree stands here, and you may not see it". The public read's §9 argument applies
unchanged.

Why the photograph read is included, though the brief named two routes: a stranger who read a
tree's photo ids before its adder withdrew it, or before an operator took it down, could otherwise
go on fetching the pictures. A takedown that leaves the photographs standing is not a takedown.

### R??? — Community-tree dates travel at day precision, in the tile and the profile too

**Decided by:** PR S2, extending the orchestrator's ruling "history dates on the wire truncated to
the day". **Needs owner review:** yes. It is a privacy call, and it changes what `Tree.createdAt`
means for a community tree.

`createdAt` and `updatedAt` on every community `Tree` served by the tile and the profile are
truncated to midnight UTC. For a GPS-placed pin, `createdAt` to the second is the moment the adder
stood at that tree. `updatedAt` is, among other things, the moment the adder signed in, because a
claim publishes the tree and bumps it. A history that says "a day" beside a tile that says
"18:41:46" would have withheld nothing.

The phone does not need more. The cursor, not `updatedAt`, is how it learns what changed. The
adder's own trees are authored on the phone and win the merge (§5). **C1 must not use a cached
community tree's `updatedAt` for ordering or change detection.**

### R??? — The tile delta's cursor trails the present by the request timeout

**Decided by:** PR S2. **Needs owner review:** no. It is a correctness mechanism with no visible
delay.

A keyset over `(updated_at, id)` loses rows. Every writer stamps `updated_at` at the start of its
transaction and commits later, so a row stamped 12:00:03 can commit after a row stamped 12:00:05
that a reader already passed. That row never reaches that phone, and nothing reports it.

The tile serves every committed row, so nothing is delayed. The `next_cursor` it returns, however,
never moves past `now − (requestTimeout + 5 s)` (25 s). Every writer of `community_trees` and
`withdrawn_community_trees` runs inside a request whose context dies at `requestTimeout`, so a row
stamped before that horizon has committed or never will. A row newer than the horizon is served
again on the next fetch, and the client's upsert by id absorbs it. When a page reads to the end,
the cursor moves up to the horizon even if the tile had nothing, so a quiet tile does not re-read
every tombstone on its next delta. `TestTheCursorNeverPassesARowThatMightStillCommit` stages the
race.

**Assumption, stated:** one machine, one clock. The service runs one machine on `cypress-sync`.
If it ever runs two, their clock skew must be added to the margin.

### R??? — What the tile serves, what it reports as removed, and what a first fetch is

**Decided by:** PR S2, within §3C.

- **Served as a tree:** published and not deleted. This is caller-independent: the adder's own
  unpublished trees are not in it, and `address` is always null.
- **Reported in `withdrawn_tree_ids`:** a tree that was public once and is not now. That covers a
  tree withdrawn by its adder, taken down by an operator, or published once and unpublished since.
  It also covers every erase-door tombstone. **A tree that was never published is never
  reported**, not even as an id to drop: no phone but its adder's ever held it, and a removal list
  still says a tree stood in this tile. After decision 10, "unpublished since" can arise only from
  rows written before S1's fix. The rule does not depend on it.
- **Tombstones are not scoped to a tile.** They carry no position (the erase door keeps nothing
  that could say whose tree it was), so every delta reports every tombstone after its cursor.
- **A first fetch (no cursor) is a snapshot:** it reports no removal older than itself, because a
  phone holding nothing for the tile has nothing to drop. A removal that happens while a snapshot
  is being paged is reported. The client must drop a tile's cursor and the trees fetched through
  it together, or not at all.
- **A pin moved out of a tile is served in the tile it left**, with its new coordinate, which lies
  outside that tile. Otherwise a phone that fetched only the old tile would keep the old pin
  forever. "In the tile" means the head is in it, or any earlier position in the location chain
  was. The client keys its cache on the tree id and must not assume a served tree lies inside the
  tile it came from.
- **Tile membership is half-open:** west and north edges are inclusive, east and south are
  exclusive. That matches `floor` in the standard tile formula, so a point on a shared edge
  belongs to exactly one tile.
- **Pages:** `limit` defaults to 100 and is at most 100. `has_more` is true only when the page
  overflowed **and** the cursor moved. A full page made entirely of rows newer than the horizon
  says `has_more: false`, and the next refresh picks those rows up.

### R??? — How S1's three extra event kinds appear on the history

**Decided by:** PR S2. The history serves an **allow-list** of event kinds: `added`, `published`,
`location_corrected`, `species_named`, `species_corrected`. This follows `publicKinds`: a kind added
later is invisible until somebody writes down why it should be shown.
`TestEveryHistoryEventKindIsClassified` reads the vocabulary out of the migrations and goes red on
an unclassified kind.

- `withdrawn` and `taken_down` never appear. A withdrawn or taken-down tree's history is
  `not_found` (§3E), so there is no response for those events to be in. They are withheld as well,
  so this stays true if the not-found rule is ever relaxed.
- `unpublished` is withheld. It records that the adder declined the open license, which is a fact
  about a person's consent, not about the tree. Decision 10 retires its writer. Rows written before
  that stay in the table and stay off the wire.

The client must still decode `kind` and `placement` with an unknown case, so a kind this list
admits later does not fail the whole response.
