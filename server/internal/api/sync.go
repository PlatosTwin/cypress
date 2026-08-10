package api

import (
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
	// IsFavorite is read only for `favorite_toggle`.
	IsFavorite bool `json:"is_favorite"`
}

// syncResult is `SyncResult`, whose three statuses these are.
//
// `duplicate` is a **success**. It is not an error with a friendly name: it means the server deduped
// on `client_uuid` and changed nothing, which is precisely the answer that lets a client replay a
// batch after a flap without creating a second visit.
type syncResult struct {
	ClientUUID uuid.UUID     `json:"client_uuid"`
	Status     string        `json:"status"`
	Error      *apierr.Code  `json:"error,omitempty"`
	Message    string        `json:"message,omitempty"`
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
	var request struct {
		Items []syncItem `json:"items"`
	}
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if len(request.Items) > maxSyncBatch {
		return apierr.New(apierr.ValidationFailed, "That batch was too large.")
	}

	owner := who.owner()
	results := make([]syncResult, 0, len(request.Items))

	for _, item := range request.Items {
		results = append(results, s.applyOne(r, item, who, owner))
	}

	writeJSON(w, s.Log, http.StatusOK, map[string]any{"results": results})
	return nil
}

func (s *Server) applyOne(r *http.Request, item syncItem, who caller, owner store.Owner) syncResult {
	failed := func(code apierr.Code, message string) syncResult {
		return syncResult{ClientUUID: item.ClientUUID, Status: "failed", Error: &code, Message: message}
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
		IsFavorite: item.IsFavorite,
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
	ClientUUID  uuid.UUID `json:"client_uuid"`
	Lat         float64   `json:"lat"`
	Lon         float64   `json:"lon"`
	DisplayName string    `json:"display_name"`
}

// proximityCandidate is one row of the list `ProximityConflict` carries.
type proximityCandidate struct {
	ID        uuid.UUID `json:"id"`
	Lat       float64   `json:"lat"`
	Lon       float64   `json:"lon"`
	Name      string    `json:"display_name"`
	DistanceM float64   `json:"distance_m"`
}

// addTree runs the 10 m proximity dedupe (BUILD-PLAN §6, `TreeDraft.proximityDedupeRadiusM`).
//
// A trip returns `conflict` **with the candidate list**, which is the whole reason the code is
// non-retryable: `ProximityConflict` carries the candidates so the UI can show them, and the item
// "fails immediately instead of spending 48 h on an answer only the user can give."  A `conflict`
// with no candidates would be a dead end wearing the same code.
//
// The candidates travel as a sibling of `error` in the body rather than inside it, because
// `APIError.Envelope`'s nested container decodes exactly `code`, `message` and `retryable` — adding
// a fourth key inside would mean changing a decoder this PR is forbidden from touching.
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

	candidates, err := s.Store.TreesWithin(r.Context(), request.Lat, request.Lon, store.ProximityDedupeRadiusM)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if len(candidates) > 0 {
		// The dedupe is "10 m, any species", so a candidate that is this very submission replayed
		// would trip it. Checking the key first keeps a retry from being told it collided with
		// itself.
		detail := make([]proximityCandidate, 0, len(candidates))
		for _, candidate := range candidates {
			detail = append(detail, proximityCandidate{
				ID: candidate.ID, Lat: candidate.Lat, Lon: candidate.Lon,
				Name: candidate.Name, DistanceM: candidate.DistanceM,
			})
		}
		conflict := apierr.New(apierr.Conflict, "There is already a tree recorded here.")
		conflict.Detail = map[string]any{"candidates": detail}
		return conflict
	}

	id, outcome, err := s.Store.AddTree(
		r.Context(), request.ClientUUID, request.Lat, request.Lon, request.DisplayName, who.owner())
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	status := "applied"
	if outcome == store.Duplicate {
		status = "duplicate"
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"id": id, "status": status})
	return nil
}
