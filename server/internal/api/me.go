package api

import (
	"net/http"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// deleteRequest is what `DELETE /me` carries.
type deleteRequest struct {
	// Choice is `AccountDeletionChoice`'s raw value. **It travels on the wire and there is no
	// server default**: R3's acceptance criterion is that deleting *more* than somebody expected is
	// the failure mode, and the copy on the sheet is the whole defense. A server that picked a door
	// would be overriding the one control the person was given.
	Choice string `json:"choice"`
	// PendingClientUUIDs are the keys still in the client's outbox at the moment of deletion.
	//
	// They are tombstoned even though this service has never seen them, and that is the point: a
	// contribution lives in the queue between being written and being applied, so an item queued on
	// Tuesday against an account deleted on Wednesday arrives on Thursday. The mark has to be
	// waiting for it. The client knows these keys because the queue is its own — this is the same
	// reason `AppSchema` v13 keys its tombstone on `client_uuid` rather than adding a column.
	PendingClientUUIDs []uuid.UUID `json:"pending_client_uuids"`
}

// deleteMe applies the choice, writes the tombstones, and revokes with Apple.
//
// ── Why the revocation is not best-effort ──────────────────────────────────────────────────────
//
// Apple requires an app offering Sign in with Apple to call the revocation endpoint at deletion
// (R72 ruling 2). It is attempted before the rows go, because after them the stored refresh token
// is gone and there is nothing left to revoke with. A failure is logged and the deletion **still
// proceeds**: refusing to delete somebody's account because a third party is having an outage
// breaks R3's promise in order to keep Apple's, and the person asked for the deletion, not for a
// dependency on Apple's uptime.
//
// **What the outage path must not do is throw the credential away**, and it previously did:
// `DELETE FROM users` takes `apple_refresh_token` with it, so a failed revocation left the person
// deleted here and still granted at Apple, with nothing left that could ever put that right. The
// unrevoked token is now parked in `pending_apple_revocations` — a table holding a token and
// nothing that could say whose it was — so the obligation outlives the row it came from.
func (s *Server) deleteMe(w http.ResponseWriter, r *http.Request, who caller) error {
	if !who.isUser() {
		// A device has no account to delete. `forbidden`, not `unauthorized` — the device's session
		// is valid, it simply cannot perform this.
		return apierr.New(apierr.Forbidden, "Sign in to delete your account.")
	}

	var request deleteRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	choice := store.DeletionChoice(request.Choice)
	if !choice.Valid() {
		// No fallback to `.leaveRecords`. Defaulting here would silently pick the *keeping* door
		// for somebody who may have chosen the erasing one, and "we kept what you asked us to
		// delete" is the failure R3 spends its copy on.
		return apierr.New(apierr.ValidationFailed, "That deletion choice is not one this service accepts.")
	}

	user, err := s.Store.UserByID(r.Context(), *who.UserID)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	var unrevoked store.UnrevokedAppleToken
	if user.AppleRefreshToken != "" {
		if revokeErr := s.Apple.Revoke(r.Context(), user.AppleRefreshToken); revokeErr != nil {
			s.Log.Error("Apple revocation failed; parking the token and proceeding",
				"user_id", user.ID, "cause", revokeErr)
			unrevoked = store.UnrevokedAppleToken(user.AppleRefreshToken)
		}
	}

	report, err := s.Store.DeleteAccount(r.Context(), user.ID, choice, request.PendingClientUUIDs, unrevoked)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	writeJSON(w, s.Log, http.StatusOK, map[string]any{
		"deleted":       true,
		"choice":        request.Choice,
		"contributions": report.Contributions,
		"photos":        report.Photos,
		"tombstones":    report.Tombstones,
	})
	return nil
}
