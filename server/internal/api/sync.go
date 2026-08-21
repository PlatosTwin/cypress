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

// syncKinds is every kind this service accepts on `POST /sync`.
//
// The first six are BUILD-PLAN §4's. The ten after them are spec §3.4's nine mutations — the
// review-dismissal pair is one entry in that list and two kinds here, for the reason
// `002_community_mutation_kinds.sql` gives.
//
// **A kind in this map is accepted, recorded, and — for nine of the ten — not materialized.** That
// is not a shortfall against the older kinds: five of the six above have no materialized table
// either, and `contributions` is the record. `add_tree` is the exception and says why in
// `store.Mutation.CommunityTree`.
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
//   - **`photo_withdrawal` is different, and the earlier version of this comment said otherwise.**
//     This service has all three pieces already: the `photos` table (`001_initial.sql`, read by
//     `store.PhotosForTree` into every `GET /trees/{id}`), the store method
//     `Store.DeletePhotoByContributor(ctx, id, owner)` — which takes exactly the `owner` this
//     handler holds — and the route `DELETE /photos/{id}` (`photos.go`), whose header cites RULINGS
//     R72 ruling 5 and ERRATA E147: "the person who took it has to be able to take it back."
//     Wiring it here would be one branch beside `insertCommunityTree`.
//
//     **It is deferred because there is nothing here yet to withdraw.** No photograph reaches this
//     service in the shipping build: `OutboxSendSink` carries no photo method, and the apply sink's
//     `uploadPhoto` is `APIOutboxTransport` over `LocalAPI`, which moves the file inside the app
//     container. A withdrawal sent today would name bytes this service has never held. Wiring the
//     upload and wiring this deletion are one round and it is not this one.
//
//     **The round that wires photo upload must wire `DeletePhotoByContributor` in the same change**,
//     because the moment uploads work this path is wrong *and tells the contributor otherwise*: the
//     row drains, reaches `done`, and screen 17 reads "Photo removed" as sent while
//     `GET /photos/{id}` keeps serving the bytes to every other device. That is this project's
//     signature failure applied to a deletion. Recorded in
//     `docs/errata-pending/outbox-kind-vocabulary-drift.md`; no test asserts anything about a
//     `photo_withdrawal` reaching this service today, in either direction.
var syncKinds = map[string]bool{
	"visit": true, "observation": true, "measurement": true,
	"care_event": true, "favorite_toggle": true, "private_reminder": true,
	"add_tree": true, "species_claim": true, "species_correction": true,
	"wrong_species_report": true, "never_existed_report": true,
	"species_review_dismissal": true, "record_review_dismissal": true,
	"photo_vote": true, "photo_withdrawal": true, "hazard_redirect": true,
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

	occurredAt := item.OccurredAt
	if occurredAt.IsZero() {
		occurredAt = s.Store.Now()
	}

	outcome, err := s.Store.Apply(r.Context(), store.Mutation{
		ClientUUID:    item.ClientUUID,
		Kind:          item.Kind,
		TreeUUID:      item.TreeUUID,
		Payload:       item.Payload,
		OccurredAt:    occurredAt,
		IsFavorite:    isFavorite,
		CommunityTree: addition,
	}, owner)

	switch {
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
