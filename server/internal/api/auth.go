package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/tokens"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// oidcRequest is what screen 15's Apple button sends.
//
// **`authorization_code` is required, not optional**, and that is R72 ruling 2 rather than a
// preference: Apple requires an app offering Sign in with Apple to call the revocation endpoint at
// account deletion, `/auth/revoke` needs a token, and the only way one exists is if the code was
// exchanged at sign-in. A sign-in accepted without it is an account `DELETE /me` cannot keep R3's
// promise for — so it is refused here, where the person can still try again, rather than
// discovered at deletion, where they cannot.
type oidcRequest struct {
	IdentityToken     string `json:"identity_token"`
	AuthorizationCode string `json:"authorization_code"`
	// Nonce is what the app generated, compared against the token's claim.
	Nonce string `json:"nonce"`
	// DeviceUUID lets one round trip do the claim as well, which is what makes D9's "keep your
	// three visits" true at the moment the person taps the button.
	DeviceUUID *uuid.UUID `json:"device_uuid"`
	// LicenseVersion is `AccountLinkRecord`'s consent. An explicit null is a *declined* consent
	// and is stored as one (spec §5.6).
	LicenseVersion *string `json:"license_version"`
}

type sessionResponse struct {
	AccessToken      string    `json:"access_token"`
	RefreshToken     string    `json:"refresh_token"`
	ExpiresAt        time.Time `json:"expires_at"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
	UserID           uuid.UUID `json:"user_id"`
}

func (s *Server) authOIDC(w http.ResponseWriter, r *http.Request) error {
	var request oidcRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.IdentityToken == "" {
		return apierr.New(apierr.ValidationFailed, "That sign-in was incomplete.")
	}
	if request.AuthorizationCode == "" {
		return apierr.New(apierr.ValidationFailed,
			"That sign-in was incomplete. Please try signing in again.")
	}

	identity, err := s.Apple.Verify(r.Context(), request.IdentityToken)
	if err != nil {
		// `unauthorized`: the credential presented did not verify. This is the session, which is
		// the only thing a 401 is ever allowed to be about.
		return apierr.Wrap(apierr.Unauthorized, "That sign-in could not be verified.", err)
	}
	// The nonce is checked here rather than by the verifier because only the caller knows what the
	// app generated. Skipping it would leave a verified token replayable by anyone who captured one.
	if request.Nonce != "" && identity.Nonce != request.Nonce {
		return apierr.New(apierr.Unauthorized, "That sign-in could not be verified.")
	}

	refreshToken, err := s.Apple.ExchangeAuthorizationCode(r.Context(), request.AuthorizationCode)
	if err != nil {
		return apierr.Wrap(apierr.Unauthorized, "That sign-in could not be completed.", err)
	}

	user, err := s.Store.UpsertUserForApple(r.Context(), identity.Subject, identity.Email, refreshToken)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	if request.LicenseVersion != nil || request.DeviceUUID != nil {
		if err := s.Store.RecordLicenseConsent(r.Context(), user.ID, request.LicenseVersion); err != nil {
			return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
		}
	}

	if request.DeviceUUID != nil {
		if _, err := s.Store.RegisterDevice(r.Context(), *request.DeviceUUID); err != nil {
			return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
		}
		if err := s.Store.ClaimDevice(r.Context(), *request.DeviceUUID, user.ID); err != nil &&
			!errors.Is(err, store.ErrClaimedByAnotherAccount) {
			return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
		}
	}

	session, err := s.mintSession(r, user.ID)
	if err != nil {
		return err
	}
	writeJSON(w, s.Log, http.StatusOK, session)
	return nil
}

func (s *Server) mintSession(r *http.Request, userID uuid.UUID) (sessionResponse, error) {
	refreshSecret, refreshHash, err := tokens.NewOpaque()
	if err != nil {
		return sessionResponse{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	now := s.Store.Now()
	refreshExpiry := now.Add(tokens.RefreshTokenLifetime)

	sessionID, err := s.Store.CreateSession(r.Context(), userID, refreshHash, refreshExpiry)
	if err != nil {
		return sessionResponse{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	access, err := s.Signer.Mint(tokens.SubjectUser, userID.String(), sessionID.String(), tokens.AccessTokenLifetime)
	if err != nil {
		return sessionResponse{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	return sessionResponse{
		AccessToken:      access,
		RefreshToken:     refreshSecret,
		ExpiresAt:        now.Add(tokens.AccessTokenLifetime),
		RefreshExpiresAt: refreshExpiry,
		UserID:           userID,
	}, nil
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// authRefresh rotates the refresh token and mints a new access token.
//
// This is the endpoint the transport's refresh-and-replay-once calls, so its failure mode matters:
// a refusal here is `unauthorized`, which the client turns into a *transport* failure for the batch
// rather than a per-item one — and `OutboxQueue.drain` already handles that by keeping every item
// alive on the backoff. That is the difference between a lapsed session costing a person nothing
// and it costing them their queue (ERRATA E261 §3).
func (s *Server) authRefresh(w http.ResponseWriter, r *http.Request) error {
	var request refreshRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.RefreshToken == "" {
		return apierr.New(apierr.Unauthorized, "Your session has expired.")
	}

	nextSecret, nextHash, err := tokens.NewOpaque()
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	now := s.Store.Now()
	refreshExpiry := now.Add(tokens.RefreshTokenLifetime)

	session, nextSessionID, err := s.Store.RotateSession(
		r.Context(), tokens.HashOpaque(request.RefreshToken), nextHash, refreshExpiry)
	switch {
	case errors.Is(err, store.ErrNotFound), errors.Is(err, store.ErrSessionSpent):
		return apierr.New(apierr.Unauthorized, "Your session has expired.")
	case err != nil:
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	access, err := s.Signer.Mint(
		tokens.SubjectUser, session.UserID.String(), nextSessionID.String(), tokens.AccessTokenLifetime)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	writeJSON(w, s.Log, http.StatusOK, sessionResponse{
		AccessToken:      access,
		RefreshToken:     nextSecret,
		ExpiresAt:        now.Add(tokens.AccessTokenLifetime),
		RefreshExpiresAt: refreshExpiry,
		UserID:           session.UserID,
	})
	return nil
}

type registerDeviceRequest struct {
	DeviceUUID uuid.UUID `json:"device_uuid"`
}

type registerDeviceResponse struct {
	DeviceToken string    `json:"device_token"`
	ExpiresAt   time.Time `json:"expires_at"`
}

// registerDevice exchanges `app_state.deviceUUID` for a device token.
//
// It authorizes `POST /sync` for items carrying a deviceID and no userID, and nothing else. It is
// **not an attestation** — a reinstall mints a new one and this endpoint cannot tell the difference
// — and it does not pretend to be one. D9 makes the anonymous queue the normal case ("first saves
// are anonymous and local-first under a device ID… the ask comes at the third save"), so a queue
// that could not drain without an account is a queue that fills up.
func (s *Server) registerDevice(w http.ResponseWriter, r *http.Request) error {
	var request registerDeviceRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.DeviceUUID.IsNil() {
		return apierr.New(apierr.ValidationFailed, "That request was missing a device identifier.")
	}

	deviceID, err := s.Store.RegisterDevice(r.Context(), request.DeviceUUID)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	secret, hash, err := tokens.NewOpaque()
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	expiresAt := s.Store.Now().Add(tokens.DeviceTokenLifetime)
	if err := s.Store.CreateDeviceToken(r.Context(), deviceID, hash, expiresAt); err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	writeJSON(w, s.Log, http.StatusOK, registerDeviceResponse{DeviceToken: secret, ExpiresAt: expiresAt})
	return nil
}

type claimRequest struct {
	DeviceUUID uuid.UUID `json:"device_uuid"`
	// LicenseVersion is what `AccountLinkRecord` carries. An explicit null is a declined consent
	// and must arrive as one rather than as an omitted field the server defaults (spec §5.6).
	LicenseVersion *string `json:"license_version"`
}

// claimDevice is the idempotent sweep.
//
// The client re-invokes its local equivalent after every batch that applied anything, because a
// mutation lives in the outbox between being written and being applied and that gap can straddle a
// sign-in. The server needs the identical rule and it must be idempotent for the same reason.
//
// **Only an account may claim.** A device token authenticates a device, and a device claiming
// itself for an account it cannot prove it belongs to is the #174 defect with an extra step: the
// authority is the session, never the stored `devices.user_id`.
func (s *Server) claimDevice(w http.ResponseWriter, r *http.Request, who caller) error {
	if !who.isUser() {
		// `forbidden`, not `unauthorized`. The device's session is perfectly valid — it is simply
		// not a credential that can perform this action, and answering 401 would send the client
		// off to refresh a token that is not the problem.
		return apierr.New(apierr.Forbidden, "Sign in to claim this device.")
	}

	var request claimRequest
	if err := decodeBody(r, &request); err != nil {
		return err
	}
	if request.DeviceUUID.IsNil() {
		return apierr.New(apierr.ValidationFailed, "That request was missing a device identifier.")
	}

	if _, err := s.Store.RegisterDevice(r.Context(), request.DeviceUUID); err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if err := s.Store.RecordLicenseConsent(r.Context(), *who.UserID, request.LicenseVersion); err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	err := s.Store.ClaimDevice(r.Context(), request.DeviceUUID, *who.UserID)
	switch {
	case errors.Is(err, store.ErrClaimedByAnotherAccount):
		// The #174 guard, surfaced. `conflict` rather than `forbidden`: nothing is wrong with this
		// caller's authority, the device simply already belongs to somebody, and re-sending will
		// not change that — which is what non-retryable means.
		return apierr.New(apierr.Conflict, "This device is already linked to another account.")
	case errors.Is(err, store.ErrNotFound):
		return apierr.New(apierr.NotFound, "That device is not registered.")
	case err != nil:
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	writeJSON(w, s.Log, http.StatusOK, map[string]any{"claimed": true})
	return nil
}
