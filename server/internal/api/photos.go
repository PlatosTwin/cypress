package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// presignLifetime is how long an upload target is good for. See storage.Presigner.PresignPut on
// why this is not the 72 h grace period.
const presignLifetime = 30 * time.Minute

type beginPhotoRequest struct {
	TreeUUID        uuid.UUID  `json:"tree_uuid"`
	VisitClientUUID *uuid.UUID `json:"visit_client_uuid"`
	// ShotType is the chip the contributor tapped on screen 04. It travels with the binary because
	// it is not recoverable from anything else, and `photos.shot_type` is append-only — a guess
	// here is permanent (see `OutboxPhoto`).
	ShotType   string    `json:"shot_type"`
	CapturedAt time.Time `json:"captured_at"`
	Width      *int      `json:"width"`
	Height     *int      `json:"height"`
	// PublicLat/Lon are snapped to the 25 m public grid before they reach here (A7, BUILD-PLAN §10).
	PublicLat *float64 `json:"public_lat"`
	PublicLon *float64 `json:"public_lon"`
	// ClientUUID is the binary's own id on the phone (`OutboxPhoto.id`), and the key this route
	// dedupes on — see `003_photo_idempotency_key.sql` for the defect that closes.
	//
	// Optional, so a client that predates the send path is unchanged: it sends no key, gets no
	// idempotency, and behaves exactly as it did. A begin with no key is not an error, it is the old
	// contract.
	ClientUUID *uuid.UUID `json:"client_uuid"`
}

// beginPhotoResponse is `PhotoUploadTicket`: `{photo_id, presigned_put_url}` (BUILD-PLAN §6).
type beginPhotoResponse struct {
	PhotoID     uuid.UUID `json:"photo_id"`
	Destination string    `json:"presigned_put_url"`
	// Moderation and ApprovalReason are returned so the upload's own log says which rule published
	// it. The client does not read them; `isPubliclyVisible` is unchanged.
	Moderation     string `json:"moderation_state"`
	ApprovalReason string `json:"approval_reason,omitempty"`
}

var shotTypes = map[string]bool{"full_tree": true, "trunk": true, "leaf": true, "other": true}

// beginPhoto reserves the photo id and returns an upload destination.
//
// The binary goes straight to storage, not through this service (spec §1.1 step 4) — which is what
// keeps a multi-megabyte PUT off a 256 MB machine, and is why the answer is a URL rather than an
// upload route.
func (s *Server) beginPhoto(w http.ResponseWriter, r *http.Request, who caller) error {
	var request beginPhotoRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.TreeUUID.IsNil() {
		return apierr.New(apierr.ValidationFailed, "That photo named no tree.")
	}
	if !shotTypes[request.ShotType] {
		return apierr.New(apierr.ValidationFailed, "That photo's framing is not one this service accepts.")
	}
	if request.CapturedAt.IsZero() {
		return apierr.New(apierr.ValidationFailed, "That photo had no capture time.")
	}

	photoID := uuid.New()
	// The key is the id, so nothing about a contributor, a tree's real position or a filename from
	// a phone appears in a URL that will be handed out.
	storageKey := "photos/" + photoID.String() + ".jpg"

	// **The store runs before the presign, which reverses the original order and is the point.** With
	// an idempotency key a begin can be a replay, and a replay's row already has a storage key — the
	// one the *first* call minted. Presigning `storageKey` first would, on a replay, hand back a URL
	// for an object no row names: the client would PUT its bytes there, `received` would close the
	// grace window on a row whose own key is still empty, and the photograph would be collected
	// after 72 h as never arrived. So the row decides the key and the presign follows it.
	begun, err := s.Store.BeginPhoto(r.Context(), store.NewPhoto{
		ID:              photoID,
		TreeUUID:        request.TreeUUID,
		VisitClientUUID: request.VisitClientUUID,
		ShotType:        request.ShotType,
		CapturedAt:      request.CapturedAt,
		Width:           request.Width,
		Height:          request.Height,
		PublicLat:       request.PublicLat,
		PublicLon:       request.PublicLon,
		StorageKey:      storageKey,
		ClientUUID:      request.ClientUUID,
	}, who.owner())
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	// A **fresh** destination on a replay, deliberately: a presign expires, and the reason a client
	// is calling begin a second time is that time passed. Returning the original URL would answer
	// the retry with something already dead.
	destination, err := s.Presigner.PresignPut(begun.StorageKey, presignLifetime)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	response := beginPhotoResponse{PhotoID: begun.ID, Destination: destination, Moderation: "pending"}
	if who.isUser() {
		response.Moderation = "approved"
		response.ApprovalReason = string(store.AutoApprovedLaunch)
	}
	writeJSON(w, s.Log, http.StatusOK, response)
	return nil
}

// photoReceived closes the 72 h grace window once the client's PUT has landed.
func (s *Server) photoReceived(w http.ResponseWriter, r *http.Request, who caller) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	photo, err := s.Store.Photo(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if !ownsPhoto(photo, who) {
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}
	if err := s.Store.MarkPhotoBytesReceived(r.Context(), id); err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"received": true})
	return nil
}

// photoData is `GET /photos/{id}`.
//
// This is the R-required grade of spec §3.1 and the acceptance criterion's last mile: the bytes a
// device never wrote.
//
// ── What it answers, and why it is not the binary ──────────────────────────────────────────────
//
// A **presigned GET URL**, not the bytes: a 256 MB machine that streams every photograph on every
// profile read is the one way this service falls over under success. It previously answered a bare
// `storage_key`, which fetches nothing — uploads are presigned PUTs, so the bucket is not
// anonymously readable, and a key on its own is a string the client cannot do anything with. The
// symmetry with `PhotoUploadTicket`, which hands the client a `destination` URL for writing, is the
// shape to keep: a URL for reading.
//
// Not a 302 redirect, because `photoData(id:)` returns `Data` and the client decides when to fetch;
// handing back a URL lets it cache, defer on cellular, and fail that fetch separately from this
// call.
//
// ── Whose photograph may be read ───────────────────────────────────────────────────────────────
//
// `TreeProfile.isPhotoVisible(_:own:)` is the single predicate over the two visibility rules
// (ERRATA E215), and this is the server-side half of it: a publicly visible photograph is readable
// by anyone, and one that is not is readable by its own contributor. A photograph that is neither
// answers `not_found` rather than `forbidden` — a refusal would confirm the row exists to somebody
// who is not allowed to know that.
func (s *Server) photoData(w http.ResponseWriter, r *http.Request, who caller) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	photo, err := s.Store.Photo(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	own := ownsPhoto(photo, who)
	switch {
	case photo.IsPubliclyVisible():
	case own && photo.IsVisibleToItsContributor():
	case photo.ModerationState == "rejected":
		// The one case that is not a silence. `moderation_rejected` has a sentence in the client
		// and has never been thrown; it becomes reachable exactly here, and the client is already
		// correct for it.
		return apierr.New(apierr.ModerationRejected, "That photo was removed.")
	default:
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}

	source, err := s.Presigner.PresignGet(photo.StorageKey, presignLifetime)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{
		"photo_id":    photo.ID,
		"url":         source,
		"expires_in":  int(presignLifetime.Seconds()),
		"shot_type":   photo.ShotType,
		"captured_at": stamp(photo.CapturedAt),
	})
	return nil
}

// deletePhoto is `deletePhoto(id:)` — a contributor taking their own photograph back.
//
// Under R72 ruling 5 this stops being a convenience and becomes the first line: the ruling requires
// the way down to ship with the way up, and this is the contributor's half of it. ERRATA E147
// argues it in the terms the auto-approve rule creates — "a photograph can hold a face, a license
// plate or the inside of somebody's front garden, and the person who took it has to be able to take
// it back."
func (s *Server) deletePhoto(w http.ResponseWriter, r *http.Request, who caller) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	err = s.Store.DeletePhotoByContributor(r.Context(), id, who.owner())
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"deleted": true})
	return nil
}

// rejectPhoto is the operator takedown.
//
// R72 ruling 5, verbatim: "Auto-approve without a takedown is the version of this rule that must
// not ship." It costs the client nothing — the photograph stops being drawn on every other device
// at its next `treeProfile` read, with no app change, no new screen and no migration.
//
// Operator-only. There is no in-app report path and #158 does not invent one: no `ReviewFlag.Kind`
// is about a photograph, and a photo vote is a ranking signal rather than a report.
func (s *Server) rejectPhoto(w http.ResponseWriter, r *http.Request) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	err = s.Store.RejectPhoto(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That photo is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"moderation_state": "rejected"})
	return nil
}

func ownsPhoto(photo store.PhotoRecord, who caller) bool {
	if who.UserID != nil && photo.UserID != nil && *photo.UserID == *who.UserID {
		return true
	}
	if who.DeviceID != nil && photo.DeviceID != nil && *photo.DeviceID == *who.DeviceID {
		return true
	}
	return false
}
