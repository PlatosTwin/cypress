package api

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// syncItem is one outbox row on the wire.
//
// `client_uuid` is the idempotency key the client already mints and the client's own unique index
// already dedupes on (BUILD-PLAN §4 and §6, DECISIONS §3.8). This service dedupes on the same key,
// which is what makes `OutboxChaosTests`' zero-duplicates assertion hold across a flap.
type syncItem struct {
	ClientUUID uuid.UUID       `json:"client_uuid"`
	Kind       string          `json:"kind"`
	TreeUUID   uuid.UUID       `json:"tree_uuid"`
	OccurredAt time.Time       `json:"occurred_at"`
	Payload    json.RawMessage `json:"payload"`
	// UserID and DeviceID are what the payload claims about itself. They are checked against the
	// authenticated caller, never trusted.
	UserID   *uuid.UUID `json:"user_id"`
	DeviceID *uuid.UUID `json:"device_id"`
	// IsFavorite is read only for `favorite_toggle`, and it is a pointer because the zero value of
	// a `bool` is a *decision*.
	//
	// As a plain `bool` an item that omitted the field recorded `is_favorite = false` and answered
	// `applied`: the heart went off, the client was told it worked, and nothing anywhere errored.
	// Since these handlers are the first statement of the `/sync` contract, a step-4 client that
	// did not know to duplicate the field would have silently un-hearted everything.
	IsFavorite *bool `json:"is_favorite"`
}

// syncResult is `SyncResult`, whose three statuses these are.
//
// `duplicate` is a **success**. It is not an error with a friendly name: it means the server deduped
// on `client_uuid` and changed nothing, which is precisely the answer that lets a client replay a
// batch after a flap without creating a second visit.
type syncResult struct {
	ClientUUID uuid.UUID    `json:"client_uuid"`
	Status     string       `json:"status"`
	Error      *apierr.Code `json:"error,omitempty"`
	Message    string       `json:"message,omitempty"`
}

// favoritePayload is the shape of `FavoriteToggle` as the client encodes it
// (`Cypress/Data/Outbox/OutboxPayload.swift`: keys stay the Swift property names).
//
// **The payload is the authority.** It is the mutation the outbox promised to send verbatim, and it
// is the thing the client already writes without being told to; a top-level mirror is a second
// place for the same fact to be wrong. The mirror is still accepted, and must agree.
type favoritePayload struct {
	IsFavorite *bool `json:"isFavorite"`
}

// addTreePayload is the shape of `TreeAddition` as the client encodes it
// (`Cypress/Data/Outbox/CommunityMutations.swift`: keys stay the Swift property names).
//
// **`treeID` is the tree's id and `clientUUID` is the item's**, and they are different values on
// purpose — the client's `LocalAPI.addTree` mints a `Tree` and stores `TreeDraft.clientUUID` beside
// it, and every later record about the tree keys on the tree id. The handler checks `treeID`
// against the item's own `tree_uuid` and refuses a disagreement rather than picking one, because
// the wrong choice gives a community tree two identities — the defect `community_trees` in
// `001_initial.sql` records having already been fixed once.
//
// `clientUUID` is present in the payload and deliberately not read: the envelope's `client_uuid` is
// the key this service dedupes on and a second copy is a second place for one fact to be wrong.
type addTreePayload struct {
	TreeID      uuid.UUID  `json:"treeID"`
	Coordinate  wireLatLon `json:"coordinate"`
	Address     *string    `json:"address"`
	Placement   string     `json:"placement"`
	SpeciesID   *uuid.UUID `json:"speciesID"`
	LandContext *string    `json:"landContext"`
}

// wireLatLon is `Coordinate` as the client's `JSONEncoder` writes it.
type wireLatLon struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// photoWithdrawalPayload is `PhotoWithdrawal` as the client encodes it
// (`Cypress/Data/Outbox/CommunityMutations.swift`: keys stay the Swift property names).
//
// `clientUUID` and `attribution` are on the wire and deliberately not read here, for the reason
// `addTreePayload` gives about its own `clientUUID`: the envelope is the authority on the item's key
// and on who sent it, and a second copy of either is a second place for one fact to be wrong. The
// ownership gate this kind needs is applied against the *photograph's* row in `withdrawPhoto`, not
// against anything the payload claims about itself.
type photoWithdrawalPayload struct {
	PhotoID uuid.UUID `json:"photoID"`
	TreeID  uuid.UUID `json:"treeID"`
}

// measurementWithdrawalPayload is `MeasurementWithdrawal` as the client encodes it
// (`Cypress/Data/Outbox/CommunityMutations.swift`, report F27: keys stay the Swift property names).
//
// `clientUUID`, `attribution` and `occurredAt` are on the wire and deliberately not read, for the
// reason `photoWithdrawalPayload` gives about its own: the envelope is the authority on the item's
// key, on who sent it and on when it happened, and a second copy of any of them is a second place
// for one fact to be wrong.
//
// **`kind` is on the wire and deliberately not read either, for a different reason.** It is `dbh`
// or `height`, and the payload's own header says what it travels for: screen 17's row reads
// `Trunk · DBH withdrawn` rather than a bare `Reading withdrawn`. That is a fact about how the
// phone draws its own queue. This service already knows which series the reading was in — it is in
// the `measurement` payload being tombstoned — so reading the claim here would add nothing but the
// chance of disagreeing with the record.
type measurementWithdrawalPayload struct {
	MeasurementID uuid.UUID `json:"measurementID"`
	TreeID        uuid.UUID `json:"treeID"`
}

// measurementPayload is the one field of `TreeMeasurement` this service reads.
//
// The payload is stored whole and served back whole by `GET /me/journal`, so nothing here needs to
// understand a reading. `id` is read only so a reading can be matched against a withdrawal that
// arrived before it — `store.measurementWasWithdrawn` says why that order happens.
//
// Decoded leniently, and a missing or unreadable `id` is not a refusal: `measurement` has been
// accepted since 001 with no requirement on the shape of its body, and a new "that item named no
// reading" here would fail queues, non-retryably, over items this service accepts today.
type measurementPayload struct {
	ID uuid.UUID `json:"id"`
}

// dataDisputePayload is `DataDispute` as the client encodes it (R79, `AppSchema` v22: keys stay the
// Swift property names). The item this service is handed looks like
//
//	{"id":"…","clientUUID":"…","treeID":"…","treeSource":"city",
//	 "issues":["wrong_location","wrong_species"],
//	 "suggestions":{"lat":"37.3382","lon":"-121.8863"},
//	 "notes":"the trunk is across the path","occurredAt":"…"}
//
// **This is a proposal to the client half, not a shape matched to one.** v22 is not on any branch
// this file can be built against, so every key below is this round's offer and PR-A is entitled to
// push back on it — the server is the cheaper side to change, having no CI and no App Store queue.
// What PR-A must not do is differ *silently*: `issues` is decoded into `[]string`, and a v22 that
// encodes it as objects fails `json.Unmarshal`, which is `validation_failed`, which is **not
// retried** — the row goes `.failed` on its first attempt and sits red on screen 17 forever. Same
// for any UUID spelled outside the canonical 36-character hyphenated form (`internal/uuid`).
//
// **`id` is the dispute's own id and `clientUUID` is the item's**, different values by construction
// exactly as they are for a reading (see `measurementPayload`), and the reason to require `id` is
// the withdrawal below: a dispute recorded without one can never be named again by the person who
// raised it, and `store.disputeIsThisIdentitys` is the lookup that needs it. `clientUUID` and
// `occurredAt` are on the wire and not read *by this handler*, for the reason `photoWithdrawalPayload`
// gives about its own — the envelope is the authority on the item's key and on when it happened, and
// a second copy of either is a second place for one fact to be wrong.
//
// **`suggestions` and `notes` are on the wire and not read by this handler, and that is a decision.**
// `suggestions` is a JSON **object keyed by field name** — `{"lat":"37.3382","species_id":"…"}`, one
// value per field, exactly as in the example above and nowhere in this round an array of pairs. Each
// key is CHECKed on the client against a vocabulary v22 names and this file does not; enforcing that
// vocabulary from here would put one list in a Swift migration and another in a Go map, across two
// files no build compiles together — which is the drift `TestTheHandlersVocabularyAndTheColumnsAgree`
// exists because of, and here it would fail queues *non-retryably* on the first attempt. Nothing on
// this side adjudicates a dispute, so nothing on this side needs to understand a suggested value: the
// payload is stored whole, and the round that serves it back is the round that has to read it.
//
// ── The one prohibition on this payload: **no top-level `speciesID`** ──────────────────────────
//
// A disputed species travels as `suggestions["species_id"]`, where nothing interprets it. A
// top-level `speciesID` is forbidden, and the reason is not tidiness: **nothing in this service
// obliges a payload read to narrow on `kind` at all, and one of them does not.**
// `store.GroveSpeciesKnown` runs `(payload->>'speciesID')::uuid` over `contributions` filtered by
// owner and `deleted_at` and by nothing else, so
//
//   - a *valid* top-level `speciesID` on a dispute silently enrols that species in the person's
//     "species you have met" list — recorded because they complained about it;
//   - an *invalid* one makes their Species tab a permanent 500. The cast errors, the whole query
//     fails, and the row cannot be un-sent.
//
// Both arms were reproduced against a throwaway Postgres for this round. The defect is **not this
// round's** — a `species_claim` carrying a non-UUID `speciesID` does the same thing today, and it
// is written up in `docs/errata-pending/grove-species-known-unscoped-cast.md` — but `wrong_species`
// is one of three issue kinds here, which makes a suggested species the most natural thing for v22
// to send, and `speciesID` the obvious key to send it under. Nothing in this file could refuse it
// either: the payload decode is lenient by design, so this is a contract the client keeps.
//
// The general rule, for whoever adds the next key: before putting a name at the top level of a
// payload, grep `internal/store` for `payload ->>` and check whether an existing read already
// interprets that name. Four functions in `internal/store` do: `withdrawMeasurement` and
// `disputeIsThisIdentitys` read `payload ->> 'id'`, `measurementWasWithdrawn` reads
// `payload ->> 'measurementID'`, and `GroveSpeciesKnown` reads `payload ->> 'speciesID'`. The first
// three cannot fail on a value they were not meant to read, and the reason is not that they narrow
// on `kind`, though all three do: it is that they **compare the extracted text** under `upper()`
// and never cast it, so a payload of any kind carrying a non-UUID value simply misses. Do not lean
// on the `kind` qual as the safe-making part — `store.disputeIsThisIdentitys` records exactly what
// is and is not known about that. `GroveSpeciesKnown` both casts *and* reads every kind, and one
// is enough.
type dataDisputePayload struct {
	ID         uuid.UUID `json:"id"`
	TreeID     uuid.UUID `json:"treeID"`
	TreeSource *string   `json:"treeSource"`
	Issues     []string  `json:"issues"`
}

// dataDisputeWithdrawalPayload is `DataDisputeWithdrawal` as the client encodes it:
//
//	{"clientUUID":"…","disputeID":"…","treeID":"…","occurredAt":"…"}
//
// `disputeID` names the `data_dispute` this takes back — the raise's `id`, never the item key the
// raise travelled under, for the reason a measurement withdrawal names the reading rather than the
// queue row.
type dataDisputeWithdrawalPayload struct {
	DisputeID uuid.UUID `json:"disputeID"`
	TreeID    uuid.UUID `json:"treeID"`
}

// disputeIssueKinds is what a dispute can be about: `tree_dispute_issues.kind`'s CHECK in the
// client's v22, stated here because R79 fixes these three and this service refuses a fourth.
//
// It is the `treePlacements` pattern and not the `suggestions` one, and the difference is who chose
// the list. These three are the round's own contract, fixed in both halves at once; the suggestion
// `field` vocabulary is v22's to name and grow, which is why it is recorded rather than checked.
var disputeIssueKinds = map[string]bool{
	"wrong_location": true, "wrong_species": true, "wrong_metadata": true,
}

// disputeTreeSources is `tree_data_disputes.tree_source`'s CHECK.
//
// Both values are accepted here even though this round's client raises disputes on **city** rows
// only — a community row is `.forbidden` in `raiseDataDispute`, because a community tree's wrong
// species is still today's `flagWrongSpecies`. Writing that restriction into this service would
// mean a deploy to lift it, for a value this service records and does not act on. A source outside
// the pair is a different thing: a malformed item.
//
// **What is deferred is not the whole of what R79 says about community rows, and the difference is
// worth stating rather than glossed.** R79 gives community trees "location and species only", and
// that the "city-tree metadata/suggested-values machinery does not apply" — permanently, not for a
// round. So `{"treeSource":"community","issues":["wrong_metadata"],"suggestions":{…}}` is not a
// restriction awaiting a client that lifts it; it is contrary to the standing spec, and this
// service accepts and stores it. That is deliberate — a cross-field rule enforced from here is a
// second copy of R79 in a file no build compiles with the first, refusing well-formed items
// **non-retryably** when the two drift. The round that adjudicates is the round that must know
// these rows can exist.
var disputeTreeSources = map[string]bool{"city": true, "community": true}

// syncKinds is every kind this service accepts on `POST /sync`.
//
// The first six are BUILD-PLAN §4's. The ten after them are spec §3.4's nine mutations — the
// review-dismissal pair is one entry in that list and two kinds here, for the reason
// `002_community_mutation_kinds.sql` gives.
//
// **A kind in this map is accepted, recorded, and — for eight of the ten — not materialized.** That
// is not a shortfall against the older kinds: five of the six above have no materialized table
// either, and `contributions` is the record. Two are exceptions: `add_tree`, which says why in
// `store.Mutation.CommunityTree`, and `photo_withdrawal`, which says why below.
//
// The other nine are not one group and the reason differs:
//
//   - **Eight of them this service could not materialize if it wanted to.** A species claim or
//     correction needs an assertion chain with a supersession order and the two-armed authority
//     RULINGS R45 carries; the two reports and the two dismissals need review flags with a status
//     and an author's arm; a photo vote needs a per-photograph tally. None of those tables exists
//     here and none of those rules is one this service can evaluate — ARCHITECTURE §8 makes the
//     moderation surface a web deliverable. Recording the act and refusing to guess at its effect is
//     the honest half; guessing would move somebody's species on an unadjudicated say-so.
//
//   - **`photo_withdrawal` is the second that materializes, and it no longer waits on the upload.**
//     Two earlier versions of this comment were wrong in opposite directions: the first filed it
//     with the eight this service cannot evaluate, and the second — correcting that — deferred it
//     on the grounds that there is nothing here yet to withdraw. The second reasoning was sound and
//     its conclusion has expired. It ends with "the round that wires photo upload must wire
//     `DeletePhotoByContributor` in the same change", and this is that round.
//
//     It materializes through `store.Mutation.WithdrawnPhotoID`, in the same transaction as the
//     contribution, and it answers in three ways rather than two — see `store.withdrawPhoto`. The
//     one worth naming here is that a photograph which is present and **somebody else's** is
//     `forbidden` rather than a quiet success: an applied withdrawal is drawn on screen 17 as
//     "Photo removed", and saying that while `GET /photos/{id}` keeps serving the bytes is ERRATA
//     **E280**, this project's signature failure applied to a deletion.
//
//     **What is still true from the deferral:** a withdrawal arriving today names bytes this service
//     has never held, because the client's send path for binaries is not built (ERRATA E264 —
//     `OutboxSendSink` still carries no photo method). That is a success that changes nothing, and
//     it is the case `withdrawPhoto` handles first. Wiring it before the upload is deliberate: the
//     harmless direction to be early in is the one where the deletion works and the upload does not.
//
//   - **`measurement_withdrawal` is the seventeenth kind and the third that materializes** (report
//     F27, `004_measurement_withdrawal_kind.sql`). It is not one of spec §3.4's nine; it is the
//     other half of the client's `AppSchema` v21, whose author found this map and 002's `CHECK`
//     both stopping at sixteen and left the service side alone on purpose — `server/` has no CI and
//     should not travel in an app change.
//
//     It materializes through `store.Mutation.WithdrawnMeasurementID`, in the same transaction as
//     the contribution, and it answers in `withdrawPhoto`'s three ways. There is no equivalent of
//     E264's reprieve here, and that is the difference worth carrying: a photograph withdrawal
//     names bytes this service has never held, while a **reading** drains through this very handler
//     as kind `measurement`. Answering `applied` and leaving the number in `GET /me/grove` is not a
//     success that changes nothing — it is E280's sentence about a tally instead of a file.
//
//     Two consequences follow and both are in `internal/store/measurements.go`: the reading is
//     tombstoned through `contributions.deleted_at`, the column every read here already filters on
//     and nothing had ever written; and a reading that arrives *after* its own withdrawal is born
//     tombstoned, because the client's queue makes that order reachable.
//
//   - **`data_dispute` and `data_dispute_withdrawal` are the eighteenth and nineteenth, and
//     neither materializes** (R79, `005_data_dispute_kinds.sql`, client `AppSchema` v22). They are
//     a reader saying the *city's* record of a tree is wrong — the wrong place, the wrong species,
//     wrong metadata — with optional suggested values, and taking that back.
//
//     This is the paragraph above's list of eight rather than its list of three, and the reason is
//     the sharper one: this service **could** write a dispute table, and must not. Adjudicating a
//     dispute moves city inventory data on an unadjudicated say-so, which is the same sentence 002
//     wrote about a species claim, and the surface that adjudicates is a web deliverable
//     (ARCHITECTURE §8). So the `contributions` row is the record, exactly as it is for a visit.
//
//     **Which makes the withdrawal a row that tombstones nothing — and what that leaves standing
//     is the part to read carefully rather than copy.** Two earlier versions of the
//     `photo_withdrawal` paragraph above were wrong in opposite directions and this comment is
//     where both were written, so this is stated as measured rather than reasoned.
//
//     `GET /me/journal` **does** serve a dispute back, payload and all, and goes on serving it
//     after the withdrawal has applied. `store.Journal` selects `contributions` narrowed by owner,
//     by `deleted_at`, and by its keyset-pagination cursor, and by nothing else — in particular
//     there is **no filter on `kind`**, which is the part that matters here — and nothing here
//     writes `deleted_at` for a dispute, so the raise stays in the journal and the withdrawal's
//     own row joins it there. Reproduced against a throwaway Postgres by PR #159's reviewer and
//     again by its author; it is not an inference from the SQL.
//
//     **The position, rather than a claim that the question does not arise.** Two facts here, and
//     they are different sizes; conflating them is how this comment went wrong before.
//
//     The **residue** — the withdrawal's own row surfacing in the journal, and the tree kept in
//     `GET /me/grove` with zero tallies and in `GET /me/map-membership?kind=yours` — is
//     `photo_withdrawal`'s and `measurement_withdrawal`'s today, from one root cause: no reader
//     here filters on kind (`Grove`'s `mine` CTE and `MapMembership` exclude only
//     `private_reminder`). It is already open and already measured, as `docs/ROADMAP.md`'s chip
//     backlog item "Answer what a withdrawn-to-empty tree should look like, before
//     `GET /me/journal` goes remote". A dispute lands in that item unchanged.
//
//     What is **larger** for a dispute is that the withdrawn thing itself goes on being served:
//     those two kinds tombstone what they take back — `photos.deleted_at` and
//     `contributions.deleted_at` — and nothing tombstones a dispute, so the raise stays in the
//     journal beside its own retraction. **This round joins that item rather than answering it
//     one kind at a time**, and the reason is not that it does not matter: a tombstone written
//     here would settle for disputes, against the one read that exists, the question that item has
//     to settle for three kinds and for the reads the badge round adds — which is how three
//     answers drift apart. There is a real argument to be had on the other side, too, and it
//     belongs with that item: a personal journal is a history, and "I disputed this, then withdrew
//     it" may be honest history in a way a photograph still served to everybody is not.
//
//     **ERRATA E280 bites in the badge round, and what it owes there is a read gate and a
//     tombstone.** A withdrawn dispute becomes a claim somebody *else* is shown the moment a read
//     serves these rows to anyone but their raiser. Neither is written here on speculation: a read
//     gate against a read that does not exist is a gate nothing can prove.
//
//     **The withdrawal's own ownership is a different question and this round does answer it** —
//     see `store.disputeIsThisIdentitys`. Not for E280's reason, since the journal is owner-scoped
//     and a stranger's withdrawal never reaches the raiser, but because the `contributions` row is
//     the record: answering `applied` to "Bob withdrew Alice's dispute" stores a false statement,
//     and it is false whether or not anything serves it back.
//
//     **That gate closes the ordinary case and not every case, and the two it does not close are
//     written out under `store.disputeIsThisIdentitys` rather than left to be discovered.** A
//     withdrawal that reaches this service before the raise it names still applies, and so does one
//     from an identity that has first raised a twin dispute reusing the same id. Both are
//     reproduced; neither is reachable as this service stands, because a dispute id is minted on
//     the client and the only read that serves it back is owner-scoped. The arrival-order one is
//     the hole `measurementWasWithdrawn` closes one kind over, and this round joins the badge
//     round's item rather than solving it here — for the same reason the tombstone above is not
//     written here, and it leaves that round the same kind of residue to reconcile.
//
//     What *is* checked is the payload — see `dataDisputePayload` for which fields and, more
//     usefully, for why the suggested-value vocabulary is recorded rather than checked.
var syncKinds = map[string]bool{
	"visit": true, "observation": true, "measurement": true,
	"care_event": true, "favorite_toggle": true, "private_reminder": true,
	"add_tree": true, "species_claim": true, "species_correction": true,
	"wrong_species_report": true, "never_existed_report": true,
	"species_review_dismissal": true, "record_review_dismissal": true,
	"photo_vote": true, "photo_withdrawal": true, "hazard_redirect": true,
	"measurement_withdrawal": true,
	"data_dispute":           true, "data_dispute_withdrawal": true,
}

// maxSyncBatch caps one request. A drain sends what is due, and a phone that has been in a drawer
// can have a lot due; the cap is generous and exists so one request cannot hold the single machine
// for a minute.
const maxSyncBatch = 500

// sync applies a batch, per item.
//
// ── Why every item gets an answer and the request does not fail ────────────────────────────────
//
// The client's retry policy is per item: `OutboxRetryPolicy.nextState` reads the item's own error
// code and decides whether that row lives or dies. A batch that failed as a whole would give every
// row the same verdict, which is right for a transport failure and wrong for anything else.
//
// ── The one code that must not appear in here ──────────────────────────────────────────────────
//
// `unauthorized`. It is non-retryable, so an item carrying it is **terminally failed on the spot**,
// with screen 17 printing "Sign in to send this" — and if the session were the real problem, it
// would print that to somebody who is signed in, for every item at once (ERRATA E261 §3). The
// session is checked once, before this handler runs, and fails the whole request there.
//
// An item that genuinely is not this identity's to send is `forbidden`: also non-retryable, so the
// item still fails immediately rather than burning 48 h, but it says the true thing.
func (s *Server) sync(w http.ResponseWriter, r *http.Request, who caller) error {
	// **Items arrive raw and are decoded one at a time**, which is the whole of this handler's
	// promise that a batch does not fail as a whole. Decoding them with the envelope meant one
	// unrecognized field on one item returned `400 validation_failed` for the entire request, with
	// no `results` at all — so a good item got no verdict, and `validation_failed` being
	// non-retryable, a client following the taxonomy failed its whole queue terminally over one
	// additive field.
	//
	// **The envelope is decoded leniently for the same reason, one level up.** Strict decoding here
	// would mean an additive top-level key — a `batch_id`, a `schema_version` — failing the whole
	// queue non-retryably, which is the identical blast radius the item fix was for. Strictness is
	// kept exactly where a dropped field would silently lose a contribution: inside the item.
	var request struct {
		Items []json.RawMessage `json:"items"`
	}
	if err := decodeBodyLeniently(r, &request); err != nil {
		return err
	}
	if len(request.Items) > maxSyncBatch {
		return apierr.New(apierr.ValidationFailed, "That batch was too large.")
	}

	owner := who.owner()
	results := make([]syncResult, 0, len(request.Items))

	for _, raw := range request.Items {
		results = append(results, s.applyOne(r, raw, who, owner))
	}

	writeJSON(w, s.Log, http.StatusOK, map[string]any{"results": results})
	return nil
}

func (s *Server) applyOne(r *http.Request, raw json.RawMessage, who caller, owner store.Owner) syncResult {
	var item syncItem
	failed := func(code apierr.Code, message string) syncResult {
		return syncResult{ClientUUID: item.ClientUUID, Status: "failed", Error: &code, Message: message}
	}

	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&item); err != nil {
		// The key is read again leniently, so an item that failed to decode is still *named* in its
		// verdict. A result the client cannot match to a queue row is a result it has to discard.
		var identified struct {
			ClientUUID uuid.UUID `json:"client_uuid"`
		}
		_ = json.Unmarshal(raw, &identified)
		item.ClientUUID = identified.ClientUUID
		return failed(apierr.ValidationFailed, "That item could not be read.")
	}

	if item.ClientUUID.IsNil() {
		return failed(apierr.ValidationFailed, "That item had no identifier.")
	}
	if !syncKinds[item.Kind] {
		return failed(apierr.ValidationFailed, "That item's kind is not one this service accepts.")
	}
	if item.TreeUUID.IsNil() {
		return failed(apierr.ValidationFailed, "That item named no tree.")
	}
	if len(item.Payload) == 0 {
		return failed(apierr.ValidationFailed, "That item had no body.")
	}

	// ── Ownership, and the one place `forbidden` belongs ───────────────────────────────────────
	//
	// A device credential authorizes items carrying a deviceID and no userID, and that is the whole
	// of what it authorizes (spec §5.8). An account may send its own. Anything else is an item that
	// is not this identity's to send — which is exactly the sentence the client's copy already
	// means, and it is `forbidden`, never `unauthorized`.
	switch {
	case who.isUser():
		if item.UserID != nil && *item.UserID != *who.UserID {
			return failed(apierr.Forbidden, "That item belongs to a different account.")
		}
	default:
		if item.UserID != nil {
			return failed(apierr.Forbidden, "Sign in to send this.")
		}
		// **Against `DeviceUUID`, not `DeviceID`.** An item's `device_id` is the phone's own
		// installation id — `app_state.device_uuid`, the same value it registered with and the same
		// one it sends to `/devices/claim`. `who.DeviceID` is this database's row key for that
		// installation. The two are never equal, so comparing them refused **every** anonymous item
		// that named itself: `forbidden` is not retryable, `OutboxRetryPolicy` moved each one
		// straight to `failed`, and screen 17 printed "This account is not allowed to send that" to a
		// phone doing exactly what D9 asks of it. Measured against the deployed service, not
		// theorised: the identical item with `device_id` omitted applied and read straight back.
		//
		// A nil `DeviceUUID` refuses rather than waving the item through. It cannot happen on this
		// path — the opaque-token branch sets both fields or neither — and the unreachable arm is
		// still written closed, because the alternative reading of a missing credential fact is
		// "authorize it", which is the wrong direction to fail in.
		if item.DeviceID != nil && (who.DeviceUUID == nil || *item.DeviceID != *who.DeviceUUID) {
			return failed(apierr.Forbidden, "That item belongs to a different device.")
		}
	}

	isFavorite := false
	if item.Kind == "favorite_toggle" {
		var payload favoritePayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		switch {
		case payload.IsFavorite != nil:
			// The authority. If the mirror is present it must agree — two sources disagreeing about
			// a toggle is not something to resolve by precedence, it is a malformed item.
			if item.IsFavorite != nil && *item.IsFavorite != *payload.IsFavorite {
				return failed(apierr.ValidationFailed,
					"That item disagrees with itself about whether the tree is a favorite.")
			}
			isFavorite = *payload.IsFavorite
		case item.IsFavorite != nil:
			isFavorite = *item.IsFavorite
		default:
			return failed(apierr.ValidationFailed, "That item did not say whether the tree is a favorite.")
		}
	}

	// ── `add_tree` is the one kind that materializes, and the one that can be refused ──────────
	//
	// The key is looked up **first**, exactly as `POST /trees` does it and for the same reason
	// stated there: the dedupe is "10 m, any species", so a byte-identical replay after a flap
	// matches the row it created moments ago at zero metres, and answering `conflict` to that is a
	// terminal failure over a success. A tree this service already holds skips the proximity query
	// outright.
	//
	// A trip against **somebody else's** tree is `conflict`: non-retryable, so the item fails on the
	// spot instead of spending 48 h on an answer only a person can give, and screen 17 shows it.
	// The candidate list `POST /trees` returns beside the code has nowhere to travel in a per-item
	// verdict, so this refusal is the bare code — see the round's PR for the open question.
	var addition *store.NewCommunityTree
	if item.Kind == "add_tree" {
		var payload addTreePayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		if payload.TreeID != item.TreeUUID {
			return failed(apierr.ValidationFailed, "That item disagrees with itself about which tree it adds.")
		}
		lat, lon := payload.Coordinate.Latitude, payload.Coordinate.Longitude
		if lat < -90 || lat > 90 || lon < -180 || lon > 180 {
			return failed(apierr.ValidationFailed, "That location is not on the map.")
		}
		placement := payload.Placement
		if placement == "" {
			placement = defaultTreePlacement
		}
		if !treePlacements[placement] {
			return failed(apierr.ValidationFailed, "That placement is not one this service accepts.")
		}
		if payload.LandContext != nil && !landContexts[*payload.LandContext] {
			return failed(apierr.ValidationFailed, "That land context is not one this service accepts.")
		}

		existing, err := s.Store.CommunityTreeExists(r.Context(), item.TreeUUID)
		if err != nil {
			s.Log.Error("looking up a community tree", "tree_uuid", item.TreeUUID, "cause", err)
			return failed(apierr.ServerError, "Something went wrong on our end.")
		}
		if !existing {
			candidates, err := s.Store.TreesWithin(r.Context(), lat, lon, store.ProximityDedupeRadiusM)
			if err != nil {
				s.Log.Error("running the proximity dedupe", "tree_uuid", item.TreeUUID, "cause", err)
				return failed(apierr.ServerError, "Something went wrong on our end.")
			}
			if len(candidates) > 0 {
				return failed(apierr.Conflict, "There is already a tree recorded here.")
			}
		}

		addition = &store.NewCommunityTree{
			ID:          item.TreeUUID,
			Lat:         lat,
			Lon:         lon,
			Address:     payload.Address,
			SpeciesID:   payload.SpeciesID,
			Placement:   placement,
			LandContext: payload.LandContext,
		}
	}

	// ── `photo_withdrawal` — the second kind that materializes ─────────────────────────────────
	//
	// It is wired here because the round that wires photo *upload* had to wire it in the same
	// change, and this is that round. The obligation is ERRATA E280's and it is not stylistic: the
	// moment a photograph can reach this service, a withdrawal that only records itself becomes a
	// lie the contributor is shown. The row drains, reaches `done`, screen 17 reads "Photo removed",
	// and `GET /photos/{id}` keeps handing the bytes to every other device.
	//
	// `treeID` is checked against the envelope's `tree_uuid` for the reason `add_tree` checks its
	// own: a disagreement is a malformed item, and picking one of the two would file the withdrawal
	// against a tree the photograph does not belong to.
	var withdrawnPhotoID *uuid.UUID
	if item.Kind == "photo_withdrawal" {
		var payload photoWithdrawalPayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		if payload.PhotoID.IsNil() {
			return failed(apierr.ValidationFailed, "That item named no photo.")
		}
		if payload.TreeID != item.TreeUUID {
			return failed(apierr.ValidationFailed,
				"That item disagrees with itself about which tree it belongs to.")
		}
		withdrawnPhotoID = &payload.PhotoID
	}

	// ── `measurement_withdrawal` — the third kind that materializes ────────────────────────────
	//
	// The gates are `photo_withdrawal`'s, one table over, and the reasons are the same ones: an id
	// that names nothing would reach the store, match no row, and come back `applied` — a success
	// reported for an item that identified nothing; and a payload disagreeing with its envelope
	// about the tree would file the withdrawal against a tree the reading is not on.
	//
	// **Ownership is deliberately not checked here.** The envelope gate above has already refused an
	// item that is not this identity's to *send*; whether the **reading** is this identity's is a
	// question about a row, and it is asked where the row is — `store.withdrawMeasurement`. Checking
	// it against anything the payload claims about itself would be trusting the claim.
	var withdrawnMeasurementID *uuid.UUID
	if item.Kind == "measurement_withdrawal" {
		var payload measurementWithdrawalPayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		if payload.MeasurementID.IsNil() {
			return failed(apierr.ValidationFailed, "That item named no reading.")
		}
		if payload.TreeID != item.TreeUUID {
			return failed(apierr.ValidationFailed,
				"That item disagrees with itself about which tree it belongs to.")
		}
		withdrawnMeasurementID = &payload.MeasurementID
	}

	// ── `data_dispute` and `data_dispute_withdrawal` — validated, recorded, materializing nothing ──
	//
	// The gates are the ones the three kinds above already apply, and they are worth having on a kind
	// that materializes nothing for a reason that is easy to miss: the `contributions` row is not a
	// receipt, it is the **record**, and the round that builds the moderation surface reads exactly
	// these rows. An item admitted here without an id or without an issue is a dispute that arrives
	// on that screen naming nothing and cannot be acted on — a defect this service would have written
	// months earlier and nothing would have refused.
	//
	// A disagreement between `treeID` and the envelope's `tree_uuid` is refused rather than resolved,
	// for the reason `add_tree` gives about its own: picking one of two disagreeing ids would file
	// the dispute against a tree it is not about.
	//
	// **Ownership is checked, and it is checked where the rows are**, exactly as it is for a reading:
	// the envelope gate above has already refused an item that is not this identity's to *send*, and
	// whether the withdrawal's `disputeID` names a dispute **this identity raised** is a question
	// about rows in `contributions`, asked in `store.disputeIsThisIdentitys` and answered
	// `forbidden`. Checking it against anything the payload claims about itself would be trusting
	// the claim. A withdrawal naming a dispute this service has never held still applies — see that
	// function for why that is a success rather than a refusal.
	if item.Kind == "data_dispute" {
		var payload dataDisputePayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		if payload.ID.IsNil() {
			return failed(apierr.ValidationFailed, "That item named no dispute.")
		}
		if payload.TreeID != item.TreeUUID {
			return failed(apierr.ValidationFailed,
				"That item disagrees with itself about which tree it belongs to.")
		}
		// Absent means "they did not say", which is `landContext`'s rule one field over and not a
		// refusal; a value outside the pair is malformed. Both halves matter: `tree_source` is NOT
		// NULL in v22, so absence should not happen — and refusing on it would turn a client that
		// renamed one key into a queue of terminal failures over items nothing here acts on.
		if payload.TreeSource != nil && !disputeTreeSources[*payload.TreeSource] {
			return failed(apierr.ValidationFailed, "That tree source is not one this service accepts.")
		}
		if len(payload.Issues) == 0 {
			return failed(apierr.ValidationFailed, "That item said nothing was wrong.")
		}
		for _, issue := range payload.Issues {
			if !disputeIssueKinds[issue] {
				return failed(apierr.ValidationFailed, "That item names an issue this service does not know.")
			}
		}
	}

	var withdrawnDisputeID *uuid.UUID
	if item.Kind == "data_dispute_withdrawal" {
		var payload dataDisputeWithdrawalPayload
		if err := json.Unmarshal(item.Payload, &payload); err != nil {
			return failed(apierr.ValidationFailed, "That item's body could not be read.")
		}
		if payload.DisputeID.IsNil() {
			return failed(apierr.ValidationFailed, "That item named no dispute.")
		}
		if payload.TreeID != item.TreeUUID {
			return failed(apierr.ValidationFailed,
				"That item disagrees with itself about which tree it belongs to.")
		}
		withdrawnDisputeID = &payload.DisputeID
	}

	// The reading's own id, for the arrival-order guard and nothing else. A body that cannot be read
	// is passed through unchanged rather than refused — see `measurementPayload` for why this one
	// kind's body is not validated.
	var recordedMeasurementID *uuid.UUID
	if item.Kind == "measurement" {
		var payload measurementPayload
		if err := json.Unmarshal(item.Payload, &payload); err == nil && !payload.ID.IsNil() {
			recordedMeasurementID = &payload.ID
		}
	}

	occurredAt := item.OccurredAt
	if occurredAt.IsZero() {
		occurredAt = s.Store.Now()
	}

	outcome, err := s.Store.Apply(r.Context(), store.Mutation{
		ClientUUID:       item.ClientUUID,
		Kind:             item.Kind,
		TreeUUID:         item.TreeUUID,
		Payload:          item.Payload,
		OccurredAt:       occurredAt,
		IsFavorite:       isFavorite,
		CommunityTree:    addition,
		WithdrawnPhotoID: withdrawnPhotoID,

		WithdrawnMeasurementID: withdrawnMeasurementID,
		WithdrawnDisputeID:     withdrawnDisputeID,
		RecordedMeasurementID:  recordedMeasurementID,
	}, owner)

	switch {
	case errors.Is(err, store.ErrNotOwned):
		// The photograph is here and it is somebody else's. `forbidden` for the reason the ownership
		// gate above uses it — non-retryable, so the item fails now instead of spending 48 h on an
		// answer that will not change — and *not* a success, which is the whole point: reporting a
		// removal that did not happen is what E280 is about. See `store.ErrNotOwned` for why this is
		// reachable rather than theoretical (RULINGS R82's provenance arm has no column here).
		return failed(apierr.Forbidden, "That photo belongs to a different contributor.")
	case errors.Is(err, store.ErrMeasurementNotOwned):
		// The reading is here and it is somebody else's — the same refusal one table over, and a
		// separate sentence because the two are refusals about different things. Screen 17 prints
		// this, and "That photo belongs to a different contributor" on an item about a number would
		// be a message that cannot be acted on. See `store.ErrMeasurementNotOwned`.
		return failed(apierr.Forbidden, "That reading belongs to a different contributor.")
	case errors.Is(err, store.ErrDisputeNotOwned):
		// The dispute is here and somebody else raised it. Nothing is being protected from a reader
		// — `GET /me/journal` is owner-scoped — but answering `applied` would write "this identity
		// withdrew it" into the record the moderation round reads, which is a false statement
		// stored. `forbidden` for the same reason the two above use it: non-retryable, so the item
		// fails now rather than spending 48 h on an answer that will not change. See
		// `store.ErrDisputeNotOwned`.
		return failed(apierr.Forbidden, "That dispute belongs to a different contributor.")
	case errors.Is(err, store.ErrTombstoned):
		// The tombstone, answering exactly as the dedupe does. An item accepted after its account
		// was deleted must not resurrect it, and it must not be an *error* either: a retryable code
		// would have the client replay it for 48 h and a non-retryable one would put a red row on
		// screen 17 for a record the person already asked to have withdrawn. `duplicate` is a
		// success that changes nothing, which is the truth.
		return syncResult{ClientUUID: item.ClientUUID, Status: "duplicate"}
	case err != nil:
		s.Log.Error("applying mutation", "client_uuid", item.ClientUUID, "cause", err)
		return failed(apierr.ServerError, "Something went wrong on our end.")
	}

	if outcome == store.Duplicate {
		return syncResult{ClientUUID: item.ClientUUID, Status: "duplicate"}
	}
	return syncResult{ClientUUID: item.ClientUUID, Status: "applied"}
}

// ── `POST /trees` ──────────────────────────────────────────────────────────────────────────────

type addTreeRequest struct {
	// ClientUUID is the tree's id, not a separate idempotency key. A tree is addable offline and
	// carries visits before it ever syncs, so the client necessarily minted the id first; see
	// `community_trees` in `server/migrations/001_initial.sql`.
	ClientUUID uuid.UUID `json:"client_uuid"`
	Lat        float64   `json:"lat"`
	Lon        float64   `json:"lon"`
	// Address is `TreeDraft.address` — the street address. There is deliberately no display-name
	// field: `TreeDraft` has none, and `Tree` has nowhere to put one (a person-chosen name lives in
	// `TreeName` / `TreeProfile.activeName`).
	Address *string `json:"address"`
	// Placement is `TreePlacement`'s raw value. Absent means `TreeDraft.placement`'s own default.
	Placement *string `json:"placement"`
	// SpeciesID is `TreeDraft.speciesID`, optional because BUILD-PLAN §6 makes it optional: "a
	// required field does not collect better answers, it collects guesses."
	SpeciesID *uuid.UUID `json:"species_id"`
	// LandContext is `TreeDraft.landContext`. Nil means "they did not say" rather than any of the
	// four, and nothing here may substitute a plausible answer.
	LandContext *string `json:"land_context"`
}

// treePlacements is `TreePlacement`, whose raw values are frozen by `AppSchema` v10's CHECK.
//
// There are two and there is no unstated case. `Tree.placement` is non-optional on the client, so a
// value outside this set does not degrade — it throws the whole `Tree`, and with it the whole
// `[NearbyTree]` and the whole `ProximityConflict`.
var treePlacements = map[string]bool{"gps": true, "contributor_placed": true}

// defaultTreePlacement is `TreeDraft.placement`'s own default, so the default on the boundary and
// the default in the column say the same thing.
const defaultTreePlacement = "gps"

// landContexts is `LandContext` (`Cypress/Core/Models/CityRecord.swift`).
var landContexts = map[string]bool{
	"street": true, "city_park": true, "private_property": true, "other_public": true,
}

func candidateFrom(tree store.NearbyTree) wireNearbyTree {
	return wireNearbyTree{
		Tree: wireTree{
			ID:                tree.ID,
			Source:            "community",
			Coordinate:        wireCoordinate{Latitude: tree.Lat, Longitude: tree.Lon},
			Address:           tree.Address,
			Status:            "alive",
			SpeciesCurrentID:  tree.SpeciesID,
			VerificationState: "unverified",
			Placement:         tree.Placement,
			StatedLandContext: tree.LandContext,
			CreatedAt:         stamp(tree.CreatedAt),
			UpdatedAt:         stamp(tree.UpdatedAt),
		},
		DistanceM: tree.DistanceM,
	}
}

// addTree runs the 10 m proximity dedupe (BUILD-PLAN §6, `TreeDraft.proximityDedupeRadiusM`).
//
// ── The key is looked up first, and that ordering is the whole of it ───────────────────────────
//
// The dedupe is "10 m, any species", so a byte-identical retry — the flap-replay case §6.1 says
// `duplicate` exists for — matches the row it created moments ago at zero metres. Answering
// `conflict` there is not a near-miss: the code is non-retryable, so the item fails terminally and
// screen 17 offers the contributor a resolution sheet listing their own submission.
//
// A trip against somebody *else's* tree returns `conflict` **with the candidate list**, which is why
// the code is non-retryable in the first place: `ProximityConflict` carries the candidates so the
// UI can show them, and the item "fails immediately instead of spending 48 h on an answer only the
// user can give." A `conflict` with nothing in it would be a dead end wearing the same code.
//
// The candidates travel as a sibling of `error` in the body rather than inside it, because
// `APIError.Envelope`'s nested container decodes exactly `code`, `message` and `retryable`.
func (s *Server) addTree(w http.ResponseWriter, r *http.Request, who caller) error {
	var request addTreeRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.ClientUUID.IsNil() {
		return apierr.New(apierr.ValidationFailed, "That tree had no identifier.")
	}
	if request.Lat < -90 || request.Lat > 90 || request.Lon < -180 || request.Lon > 180 {
		return apierr.New(apierr.ValidationFailed, "That location is not on the map.")
	}

	placement := defaultTreePlacement
	if request.Placement != nil {
		placement = *request.Placement
	}
	if !treePlacements[placement] {
		return apierr.New(apierr.ValidationFailed, "That placement is not one this service accepts.")
	}
	if request.LandContext != nil && !landContexts[*request.LandContext] {
		return apierr.New(apierr.ValidationFailed, "That land context is not one this service accepts.")
	}

	// Before the proximity query, not after.
	existing, err := s.Store.CommunityTreeExists(r.Context(), request.ClientUUID)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if existing {
		writeJSON(w, s.Log, http.StatusOK, map[string]any{"id": request.ClientUUID, "status": "duplicate"})
		return nil
	}

	candidates, err := s.Store.TreesWithin(r.Context(), request.Lat, request.Lon, store.ProximityDedupeRadiusM)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if len(candidates) > 0 {
		detail := make([]wireNearbyTree, 0, len(candidates))
		for _, candidate := range candidates {
			detail = append(detail, candidateFrom(candidate))
		}
		conflict := apierr.New(apierr.Conflict, "There is already a tree recorded here.")
		conflict.Detail = map[string]any{"candidates": detail}
		return conflict
	}

	outcome, err := s.Store.AddTree(r.Context(), store.NewCommunityTree{
		ID:          request.ClientUUID,
		Lat:         request.Lat,
		Lon:         request.Lon,
		Address:     request.Address,
		SpeciesID:   request.SpeciesID,
		Placement:   placement,
		LandContext: request.LandContext,
	}, who.owner())
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	status := "applied"
	if outcome == store.Duplicate {
		status = "duplicate"
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"id": request.ClientUUID, "status": status})
	return nil
}
