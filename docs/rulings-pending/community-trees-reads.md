# Rulings pending — community trees, the server reads (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. No code comment cites this filename.

These record what **PR S2** (`server/community-trees-reads`) decided where the round's design (§3C,
§3D, §3E), the owner's decisions 1–14 and the orchestrator's rulings of 2026-09-28 left a choice.
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
| `GET /trees/{id}/history` | 404 `not_found`, the same answer as a city tree's. (The adder's own unpublished tree is not hidden from the adder; it answers 200 with no events, per the history ruling below.) |

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

**These are calendar days, and a client must render them as calendar days.** The wire form is
midnight UTC (`2026-03-20T00:00:00Z`). Formatted in the reader's own zone, as every photo date in
the shipped app is, midnight UTC is the **previous** day anywhere in the Americas. No shipped client
decodes any of these fields (the tile, `community_tree` and the history are all new, and
`TreeCommunityHalfResponse` ignores the keys it does not name), so the rendering is a C1/C2
contract, not a TestFlight hazard: format them with a UTC calendar, as screen 03's inventory date
(`TreeProfilePresentation`'s `yMMMMd`, fixed to UTC for exactly this reason) already does. The day
itself is the **UTC** day of the event. For an evening in the Americas that is the next local day,
which the history has shown since round 1; making it the local day needs the event's zone, which
the service does not hold (see the decision-14 erratum for the same limit on photographs).

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
- **Reported in `withdrawn_tree_ids`:** a tree that was public once and is not now: withdrawn by
  its adder or taken down by an operator (`published_at` is set and `deleted_at` is set; nothing
  unpublishes, decision 10), or erased with `withdrawn_community_trees.was_public`. **A tree that
  was never published is never reported**, not even as an id to drop: no phone but its adder's ever
  held it, and a removal list still says a tree stood in this tile. That includes a declining
  account's tree tombstoned when the account goes (decision 12) and a tree born withdrawn (its
  withdrawal drained before its add). Both read S1's columns; neither infers "was public" from the
  event log.
- **Tombstones are not scoped to a tile.** They carry no position (the erase door keeps nothing
  that could say whose tree it was), so every delta reports every once-public tombstone after its
  cursor.
- **A first fetch (no cursor) is a snapshot:** it reports no removal older than the settle horizon
  (`now − 25 s` when it began), because a phone holding nothing for the tile has nothing to drop.
  So a snapshot **can** report removals from the last 25 seconds, and one that happens while the
  snapshot is being paged is reported too. The client applies them like any other. The client must drop a tile's cursor and the trees fetched through
  it together, or not at all.
- **A pin moved out of a tile is served in the tile it left**, with its new coordinate, which lies
  outside that tile. Otherwise a phone that fetched only the old tile would keep the old pin
  forever. "In the tile" means the head is in it, or any earlier **public** position in the
  location chain was (`community_tree_locations.was_public`). A position the tree held only while
  private puts it in no tile: no phone ever drew it there (decision 13). The client keys its cache on the tree id and must not assume a served tree lies inside the
  tile it came from.
- **Tile membership is half-open:** west and north edges are inclusive, east and south are
  exclusive. That matches `floor` in the standard tile formula, so a point on a shared edge
  belongs to exactly one tile.
- **Two query texts, one contract.** The snapshot and the delta are separate SQL texts rather than
  one text with `($n IS NULL OR …)` arms, so each generic plan (the one pgx's statement cache can
  settle on) uses S1's partial indexes: `(lat, lon) WHERE published_at IS NOT NULL`,
  `(lat, lon) WHERE was_public`, and `(withdrawn_at, id) WHERE was_public`. Measured at 100k trees:
  about 0.3 ms warm and 2–4 ms cold, generic or custom (the errata entry has the numbers).
- **Pages:** `limit` defaults to 100 and is at most 100. `has_more` is true only when the page
  overflowed **and** the cursor moved. A full page made entirely of rows newer than the horizon
  says `has_more: false`, and the next refresh picks those rows up.

### R??? — The history starts where the tree went live, and serves an allow-list

**Decided by:** PR S2, implementing the owner's decision 13 ("history starts at going live") on
S1's representation. **Needs owner review:** no; it is the decision, applied.

The history serves only events with `community_tree_events.in_public_history`, and of those only
an **allow-list** of kinds. This follows `publicKinds`: a kind added later is invisible until
somebody writes down why it should be shown. `TestEveryHistoryEventKindIsClassified` reads the
vocabulary out of the migrations and goes red on an unclassified kind.

- **`published` is served, as `added`.** It is the tree's first public moment, and it carries the
  position the tree held when it went live. To a stranger that is when and where the tree was added.
  The license version it also records stays on the server.
- **`added` is withheld.** It is the private record of the tree's first position, which may be
  somewhere the tree never stood in public: a phone that added a tree signed out, moved it, and then
  signed in, published it at the second position. Moves made before going live (`location_corrected`
  events with `in_public_history` false) are withheld with it. Those positions are also in no tile.
- **`location_corrected`, `species_named` and `species_corrected`** are served when public.
- **`withdrawn` and `taken_down` never appear.** A withdrawn or taken-down tree's history is
  `not_found` (§3E), so there is no response for those events to be in. They are withheld as well,
  so this stays true if the not-found rule is ever relaxed.
- `unpublished` is gone from the vocabulary (S1 retired it with decision 10), so nothing classifies
  it.
- **The adder gets the same history as everyone else.** Their own record of the tree's private life
  is on their phone. A route whose answer depended on who asked would be two contracts under one
  name. So the adder's own **unpublished** tree answers 200 with no events.
- **No public event is dated before the tree went live** (the orchestrator's L1 ruling). An act the
  adder made while the tree was private can arrive after publication: a move or a naming queued on
  a phone that was signed out or declining. S1 records it as public, because the pin did move in
  public. The history serves it at `GREATEST(occurred_at, published_at)`, and orders by that date,
  then by `recorded_at`, so it sits above "added" and never below it. Its own earlier day, which
  would be a day of the tree's private life, is never served.

The client must still decode `kind` and `placement` with an unknown case, so a kind this list
admits later does not fail the whole response.

### R??? — The tile cursor is sealed, and its key is derived from the session signing secret

**Decided by:** PR S2 round 2, fixing the #190 review's F1. **Needs owner review:** no new secret
was needed; the key decision is logged here.

The review showed that a readable, forgeable cursor turned the day-precision ruling into nothing: a
cursor forged at `T − 1µs` served a tree and one at `T` did not, so a binary search recovered every
tree's exact stamp in every tile (the moment an adder stood at a tree, signed in, or deleted an
account). The cursor is now **AES-256-GCM** over a fixed 34-byte record (version, position,
since), with a random nonce and the canonical tile as additional data. It is unreadable, has one
length whatever it holds, and is refused as `validation_failed` if it was forged, altered,
truncated, sealed under another key, or sealed for another tile.

**The key** is HKDF-SHA256 of `SESSION_SIGNING_KEY` (the service's existing required secret, at
least 32 bytes), with the info string `cypress-sync/community-tile-cursor/v1` and no salt: 32 bytes.
The info string is used for nothing else, so the derived key is independent of the signing key. No
new Fly secret. Rotating `SESSION_SIGNING_KEY` already signs every account out; it now also turns
every stored tile cursor into `validation_failed`, which the client answers by dropping the cursor
and its trees and taking a fresh snapshot. A server with no key refuses the tile (500) rather than
hand out a readable cursor.

What the cursor cannot hide is the present: a stranger polling a tile every second sees a new tree
within a second of its arrival. That is an observation anyone could make by looking, not the
recovery of a stored time.

### R??? — A stranger is told a tree was added the day it went live

**Decided by:** the orchestrator's V1 ruling on decision 13, implemented in PR S2 round 3.

`createdAt` on a community `Tree` is **`published_at`**, at day precision, for everyone but the
adder: on the tile (which has no viewer and serves only published trees) and on the profile. The
adder's own profile keeps `created_at`, the day they really added it. So a tree added signed out in
March and claimed in September was, to a stranger, added in September. The history's "added" says
the same day, so the two can no longer disagree on one screen. Before this, `createdAt` told every
stranger how long the tree had sat private, which is how long its adder had been signed out or
declining.

`updatedAt` is unchanged: publication bumps it, so it is never before `published_at`.

### R??? — The grove's hero passes the photograph's gate, and has bytes

**Decided by:** the orchestrator's V2 ruling, implemented in PR S2 round 3.

`GET /me/grove`'s `hero_photo_id` is chosen only from photographs that `GET /photos/{id}` would
serve this caller, for a tree that caller may see. So no photograph of a community tree hidden from
the caller is a hero, whether the tree is somebody else's unpublished tree, withdrawn, taken down or
erased. A photograph whose bytes never arrived is never a hero either, including the caller's own
upload still in flight: a hero is something to draw.

Without the gate, a stranger's withdrawal of a hidden id answered `applied`, like any unknown id
(F6), and their grove then drew the hidden tree's photograph for it. That told the two apart
afterwards and served a hidden photograph's id. And anybody with a favorite on a tree that was
later withdrawn or taken down went on receiving its photograph's id.

The grove decides this for many trees in one query, so the rule is spelled a second time in SQL
(`treeHiddenFromViewerSQL`). `TestTheGroveHeroPassesThePhotographGate` checks that spelling
against `communityTreeFor` for every hidden state and the visible ones, for an account and for a
device.

### R??? — Only a known license version is an acceptance

**Decided by:** the orchestrator's L2 ruling. It is S1's code (`store/community_trees.go`,
`store/identity.go`), fixed in PR S2 round 3.

The service publishes under one license version, `odbl-1.0`, which is the client's
`LicenseConsent.currentVersion`. A consent naming anything else, `""` included, is recorded as a
**decline**, and a stored value that is not a known version (written before this rule) does not
count as acceptance either. Failing closed keeps the account's trees private. It does not unpublish
anything (decision 10).

An account that had accepted and then sends a non-version is therefore recorded as declining from
then on. That is the literal reading of the ruling; the alternative, refusing the request, would
fail a sign-in over a consent field.

`TestTheServerKnowsTheClientsLicenseVersion` reads the client's constant out of
`AccountLinkRecord.swift`. When legal review moves it, the service must learn the new version in
the same change, or every new acceptance silently becomes a decline.

**Not changed:** 007's backfill publishes accounts whose `license_version IS NOT NULL`. It is a
migration, and this PR does not touch migrations. The client's constant has been `odbl-1.0`
since it was written (`git log -S` on `AccountLinkRecord.swift` finds one value), so no other
version is expected in production. Still, S1 may want the backfill to say `= 'odbl-1.0'` before
007 ships.

### R??? — Decision 14a's served form: noon UTC of the phone's date, to everybody but the owner

**Decided by:** PR S2 round 4, pinning the form decision 14a left to S2 ("noon UTC of it, or a
date-only field").

`captured_at` on `GET /trees/{id}` and `GET /photos/{id}` is:
- **the exact time**, for the photograph's owner;
- **noon UTC of `captured_on`**, for everybody else, when the phone sent it;
- **the exact time**, for everybody, when it did not. Decision 14a keeps today's behavior for
  photographs from older builds.

**Why noon UTC and not a date-only field.** The shipped client decodes `captured_at` with
`.iso8601`, and a bare `2026-03-14` would fail that decoder and with it the whole profile. Every
surface formats the instant date-only in the reader's zone. Noon UTC is the phone's calendar date
for every reader from UTC−11 to UTC+11, which was measured through the client's own decoder and
formatters (the decision-14 erratum). Midnight would be the day before across the Americas.

The residue is readers at UTC+12 and beyond, who see the next day. New clients close it by
formatting other people's photograph dates with a UTC calendar (the testdata README).
`TestOthersSeeAPhotographsDateAndItsOwnerTheTime` covers both routes, owner and stranger, the
morning, the evening, the month end and a photograph with no date. `tree_profile_community.json`
pins the evening case.

