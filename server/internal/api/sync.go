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

var syncKinds = map[string]bool{
	"visit": true, "observation": true, "measurement": true,
	"care_event": true, "favorite_toggle": true, "private_reminder": true,
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
	// additive field. Strict decoding is kept; its blast radius is now one item.
	var request struct {
		Items []json.RawMessage `json:"items"`
	}
	if err := decodeBody(r, &request); err != nil {
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
		if item.DeviceID != nil && *item.DeviceID != *who.DeviceID {
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

	occurredAt := item.OccurredAt
	if occurredAt.IsZero() {
		occurredAt = s.Store.Now()
	}

	outcome, err := s.Store.Apply(r.Context(), store.Mutation{
		ClientUUID: item.ClientUUID,
		Kind:       item.Kind,
		TreeUUID:   item.TreeUUID,
		Payload:    item.Payload,
		OccurredAt: occurredAt,
		IsFavorite: isFavorite,
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
	// `community_trees` in schema.sql.
	ClientUUID  uuid.UUID `json:"client_uuid"`
	Lat         float64   `json:"lat"`
	Lon         float64   `json:"lon"`
	DisplayName string    `json:"display_name"`
}

// proximityCandidate is one row of `ProximityConflict.candidates`, which is `[NearbyTree]`.
//
// ── Why this is shaped like a whole tree and not like an id ────────────────────────────────────
//
// The client's `NearbyTree` (`Cypress/Data/API/CypressAPI.swift`) wraps a whole `Tree`, plus
// `distanceM`, `speciesScientificName`, `speciesCommonName` and a `tell`. A candidate list of bare
// ids cannot construct one, and the phone cannot fill the gap from the installed city file either:
// every candidate here is a **community-added** tree, which is by definition not in the city
// inventory. So whatever `RemoteAPI` needs to build the list has to arrive in this body.
//
// Three fields are fixed rather than stored, and each is fixed because the value is knowable:
//
//   - `source` is always `community`. This table holds nothing else.
//   - `verification_state` is always `unverified`. A community submission is neither a city row nor
//     org-confirmed, which is exactly what that case means.
//   - `tell` is always null. `IDTip` comes from the curated species pipeline (BUILD-PLAN §8), the
//     shipped seed leaves `species.id_tips` empty, and BUILD-PLAN §15 forbids inventing botany. The
//     field is present and null rather than absent, so the client decodes a `nil` tell rather than a
//     missing key.
//
// `species_scientific_name` and `species_common_name` are null for the same reason `tell` is: this
// service holds no species table — R36 keeps the inventory local — so it can carry the species *id*
// a contributor asserted and nothing more. The client resolves the names from its own city file,
// which is where they live.
type proximityCandidate struct {
	Tree      candidateTree `json:"tree"`
	DistanceM float64       `json:"distance_m"`

	SpeciesScientificName *string `json:"species_scientific_name"`
	SpeciesCommonName     *string `json:"species_common_name"`
	Tell                  *idTip  `json:"tell"`
}

// candidateTree is `Tree`, restricted to what a community row can truthfully answer.
//
// Every field the client's `Tree` requires is present; the ones this service has no column behind
// are explicitly null rather than omitted, so a decoder sees "not stated" instead of a missing key.
type candidateTree struct {
	ID                uuid.UUID  `json:"id"`
	ExternalRef       *string    `json:"external_ref"`
	IDSpace           *string    `json:"id_space"`
	Source            string     `json:"source"`
	Coordinate        coordinate `json:"coordinate"`
	Address           *string    `json:"address"`
	SiteType          *string    `json:"site_type"`
	NeighborhoodID    *uuid.UUID `json:"neighborhood_id"`
	Status            string     `json:"status"`
	SpeciesCurrentID  *uuid.UUID `json:"species_current_id"`
	PlantedYear       *int       `json:"planted_year"`
	DBHCityCmRange    *intRange  `json:"dbh_city_cm_range"`
	SiteLineage       *uuid.UUID `json:"site_lineage"`
	VerificationState string     `json:"verification_state"`
	Placement         string     `json:"placement"`
	CityRecord        *struct{}  `json:"city_record"`
	StatedLandContext *string    `json:"stated_land_context"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	DeletedAt         *time.Time `json:"deleted_at"`
}

type coordinate struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

type intRange struct {
	Min int `json:"min"`
	Max int `json:"max"`
}

type idTip struct {
	Icon string `json:"icon"`
	Text string `json:"text"`
}

func candidateFrom(tree store.NearbyTree) proximityCandidate {
	// `placement` is `TreePlacement`'s raw value; a row that never recorded one reads as the
	// vocabulary's own unstated case rather than as an empty string the client cannot decode.
	placement := tree.Placement
	if placement == "" {
		placement = "unknown"
	}
	var name *string
	if tree.DisplayName != "" {
		copied := tree.DisplayName
		name = &copied
	}
	return proximityCandidate{
		Tree: candidateTree{
			ID:                tree.ID,
			Source:            "community",
			Coordinate:        coordinate{Lat: tree.Lat, Lon: tree.Lon},
			Address:           name,
			Status:            "alive",
			SpeciesCurrentID:  tree.SpeciesID,
			VerificationState: "unverified",
			Placement:         placement,
			CreatedAt:         tree.CreatedAt,
			UpdatedAt:         tree.UpdatedAt,
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
		detail := make([]proximityCandidate, 0, len(candidates))
		for _, candidate := range candidates {
			detail = append(detail, candidateFrom(candidate))
		}
		conflict := apierr.New(apierr.Conflict, "There is already a tree recorded here.")
		conflict.Detail = map[string]any{"candidates": detail}
		return conflict
	}

	outcome, err := s.Store.AddTree(
		r.Context(), request.ClientUUID, request.Lat, request.Lon, request.DisplayName, who.owner())
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
