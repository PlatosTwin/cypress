package api

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
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
	// Nonce is the **raw** nonce the app generated, not its hash.
	//
	// ── Which side hashes, pinned here so step 4 does not have to guess ────────────────────────
	//
	// The Apple recipe has the client generate a random nonce, pass **SHA-256 hex of it** to
	// `ASAuthorizationAppleIDRequest.nonce`, and keep the raw one. Apple then puts the hash in the
	// identity token's `nonce` claim. So the raw value is the only thing that proves possession,
	// and it is what travels here; **this service does the hashing** and compares against the
	// claim. A client that sent the hash instead would be forwarding the same value an attacker
	// who captured the token already has, which is the opposite of what the nonce is for.
	Nonce string `json:"nonce"`
	// DeviceUUID lets one round trip do the claim as well, which is what makes D9's "keep your
	// three visits" true at the moment the person taps the button.
	DeviceUUID *uuid.UUID `json:"device_uuid"`
	// LicenseVersion is `AccountLinkRecord`'s consent, and it is raw so that **absent and null stay
	// different facts** — see `consent` below.
	LicenseVersion json.RawMessage `json:"license_version"`
}

// consent reads a `license_version` field that may be absent, null, or a string.
//
// ── Why a `*string` was wrong ──────────────────────────────────────────────────────────────────
//
// Spec §5.6: a missing `licenseVersion` is a **declined** consent and must arrive as an explicit
// null rather than an omitted field the server defaults. A `*string` decodes both to `nil`, so the
// server could not tell "the person declined" from "this request is not about consent" — and §6.2
// has the client re-invoking `POST /devices/claim` after every batch that applied anything. A sweep
// re-run for reasons entirely unrelated to consent therefore withdrew it.
//
// Returns (value, present). `present` false means the key was not in the body at all: write nothing.
// `present` true with a nil value is the explicit null, which is a decision and is recorded.
func consent(raw json.RawMessage) (version *string, present bool, err error) {
	if len(raw) == 0 {
		return nil, false, nil
	}
	if string(raw) == "null" {
		return nil, true, nil
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, false, err
	}
	return &value, true, nil
}

// nonceMatches compares the raw nonce against the token's claim.
//
// Constant-time, and hex is lowercased before comparison because the claim's case is Apple's to
// choose and a case mismatch would read as a forgery.
func nonceMatches(raw, claim string) bool {
	if raw == "" || claim == "" {
		return false
	}
	sum := sha256.Sum256([]byte(raw))
	hashed := hex.EncodeToString(sum[:])
	return subtle.ConstantTimeCompare([]byte(hashed), []byte(strings.ToLower(claim))) == 1
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
	// ── The nonce, and why the check cannot be conditional on the request carrying one ─────────
	//
	// It is checked here rather than by the verifier because only the caller knows what the app
	// generated. It was previously guarded by `request.Nonce != ""`, which made the replay defense
	// **opt-out by the party it defends against**: anybody holding a captured identity token simply
	// omitted `nonce` and the comparison was skipped.
	//
	// So it fails closed. If the verified token carries a nonce claim, a matching raw nonce is
	// required; if the caller sends one, the token must carry its hash. Only a token with no claim
	// and a request with no nonce skips — and Apple always issues the claim when the app set one,
	// so that pair means "this sign-in never had a nonce", not "the check was waived".
	if identity.Nonce != "" || request.Nonce != "" {
		if !nonceMatches(request.Nonce, identity.Nonce) {
			return apierr.New(apierr.Unauthorized, "That sign-in could not be verified.")
		}
	}

	refreshToken, err := s.Apple.ExchangeAuthorizationCode(r.Context(), request.AuthorizationCode)
	if err != nil {
		return apierr.Wrap(apierr.Unauthorized, "That sign-in could not be completed.", err)
	}

	user, err := s.Store.UpsertUserForApple(r.Context(), identity.Subject, identity.Email, refreshToken)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	licenseVersion, licensePresent, err := consent(request.LicenseVersion)
	if err != nil {
		return apierr.New(apierr.ValidationFailed, "That request could not be read.")
	}
	if licensePresent {
		if err := s.Store.RecordLicenseConsent(r.Context(), user.ID, licenseVersion); err != nil {
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
	case errors.Is(err, store.ErrSessionReused):
		// The family has been revoked by the store. The wire answer is the same `unauthorized` a
		// spent token gets — the client cannot act on the difference, and telling a thief which of
		// their guesses was a real token is not information to hand out.
		s.Log.Warn("refresh token replayed after rotation; session family revoked")
		return apierr.New(apierr.Unauthorized, "Your session has expired.")
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

	// Re-registering retires whatever was live over this installation. It does not stop somebody
	// who knows the id from minting a credential — nothing can, and D9 requires that be cheap — but
	// it stops two holders sharing one queue *silently*: the real device's next call is a 401 and it
	// re-registers, which is a visible event rather than an invisible one.
	if err := s.Store.RevokeDeviceTokens(r.Context(), deviceID); err != nil {
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
	// LicenseVersion is what `AccountLinkRecord` carries. Absent, null and a version string are
	// three different facts here; see `consent`.
	LicenseVersion json.RawMessage `json:"license_version"`
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

	licenseVersion, licensePresent, parseErr := consent(request.LicenseVersion)
	if parseErr != nil {
		return apierr.New(apierr.ValidationFailed, "That request could not be read.")
	}

	if _, err := s.Store.RegisterDevice(r.Context(), request.DeviceUUID); err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	// Only when the key was actually sent. The sweep is idempotent and is re-run for reasons that
	// have nothing to do with consent; writing on every call made it withdraw one.
	if licensePresent {
		if err := s.Store.RecordLicenseConsent(r.Context(), *who.UserID, licenseVersion); err != nil {
			return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
		}
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
