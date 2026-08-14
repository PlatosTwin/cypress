### E??? — The sync service answers halves, and spec §3.1's "the remote implementation exists" is not true of Class L

*Found while implementing `RemoteAPI`'s bodies for #158 step 4 (wave 2b), by reading
`server/internal/api/server.go`'s route table rather than the documentation about it.*

`docs/design-proposals/2026-08-09-task158-live-layer.md` §3.1 describes Class L as "answered from
the installed city file; **the remote implementation exists, is tested, and is not on the hot
path**." Checked against the service that was actually built, the second clause is false, and the
falseness is deliberate on the server's side rather than an omission: `server/README.md`'s own "What
this service is not" says "the city layer — the map's pan loop, species, the almanac — is answered on
the phone from the installed city file and **never reaches here**."

The route table mounts eighteen routes. None is city-layer. So there is no Class L remote
implementation to write, and a body that called `GET /species/{id}` would take Go's `http.ServeMux`
404 — which is not an `{error: {code, message, retryable}}` envelope — and dress it as a species that
is not there. `RemoteAPI` refuses instead, with the reason attached (`RemoteSurface`), which is what
spec §3.3 means by "a refusal is an implementation, an inherited default is not".

**The same check found a second, larger thing, and it changes what "Class R goes remote" means.**
The service answers the *community and account half* of every read it serves, and every whole
`CypressAPI` type needs the city file as well. So the router **joins**; it does not switch. Eight
instances, each one a place where a naive "route it remote" would have returned a value that looks
like an answer:

| Read | What the service sends | What the client type needs and does not get |
|---|---|---|
| `grove()` | `tree_uuid`, favorite, last visit, `GroveRecord`, hero photo | `GroveEntry.displayName`, `GroveEntry.coordinate` — both city-layer, and the coordinate is not optional |
| `groveSpecies()` | `species_id`, `first_met` | `KnownSpecies`' two names and `firstMetAddress`; `GroveSpecies.neighborhood`, the ring's denominator, which `reads.go` declines to guess at under D16 |
| `treeProfile(id:)` | photographs, own/deletable sets, visit count | the `Tree` itself, its species, its inventory row |
| `journal(cursor:limit:)` | `client_uuid`, kind, `tree_uuid`, `occurred_at`, raw `payload` | `JournalEntry.treeDisplayName` **and `summary`** — see below |
| `deletePhoto(id:)` | `{"deleted": true}` | `PhotoDeletion`'s `treeID` and its four counts |
| `addTree(_:)` | `{id, status}` | every other column of `Tree` (recoverable from the draft, which is the authority) |
| `deleteAccount(_:)` | three counters | `AccountDeletion.Outcome`'s other seventeen fields |
| `addTree(_:)`, on `conflict` | `detail.candidates` | — see the transport-seam item below |

`RoutedAPI` joins the first three. The rest are recorded here rather than papered over, and four of
them want a decision or a server round:

1. **The journal cannot be joined by the client at all.** `JournalEntry.summary` is built by the
   `UNION ALL` in `ContributionStore.journal` out of the local tables' own columns and humanized by
   `LocalAPI.humanize`; the service sends the raw mutation and no summary. Rebuilding the sentence
   on the client would be a second implementation of one fact in a second language, and writing a
   different sentence would be inventing copy the mocks do not have (DECISIONS constraint 21). The
   journal therefore routes local and reports itself degraded on every read. **Closing it is a
   server round that sends the summary.**

2. **`ProximityConflict.candidates` do not survive the transport seam.** The service sends them, as
   a sibling of `error` because `APIError.Envelope`'s nested container decodes exactly `code`,
   `message` and `retryable`. `AuthorizedTransport.send` returns the 2xx body or throws the taxonomy
   code, so by the time a `conflict` reaches `RemoteAPI.addTree` the body is gone and the method
   throws the bare `.conflict`. It costs nothing today — §3.4 keeps `addTree` routed local, where
   the candidates come from the installed inventory — and it must be fixed by the round that wires
   the method, by widening the session seam to carry the error body once rather than by re-sending
   the draft.

3. **`GET /trees/{id}` sends `is_publicly_visible` and not `moderation_state`.** `true` pins
   `approved` exactly; `false` is `pending` or `rejected` and there is no third fact on the payload.
   The client maps `false` to `.pending`. Every visibility predicate in the app answers identically
   on both readings — a rejected photograph reaches that response only for its own contributor,
   whose rule is `deletedAt == nil` either way — so nothing is drawn wrongly, but it is a guess
   where the wire could carry a fact. One field on one payload closes it.

4. **`DELETE /me`'s three counters cannot fill `AccountDeletion.Outcome`.** `RemoteAPI` writes
   `contributions` and `photos` onto the pair the *door* names — anonymized under `leaveRecords`,
   deleted under `eraseEverything` — and leaves the rest at zero, because writing a count into the
   wrong pair would tell somebody their records were destroyed when they were kept. `tombstones` has
   no field at all and is deliberately not mapped onto `discardedOutboxItems`: one counts marks the
   service wrote, the other counts what the local half discarded.

**None of this is a defect in the server.** Every one of these shapes is argued in
`server/internal/api` in R36's own terms, and the argument is right: a route that returned the city
half as well "would put the map's own data on the network for no gain". What is wrong is the
sentence in the spec that let a brief say "implement the 32 method bodies" as though thirty-two
network calls were available. **The rule this yields, for the rounds after it:** on this
architecture a Class R read is a *join*, and any round that treats one as a switch will return a
whole client type most of whose fields it invented.
