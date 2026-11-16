package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── The session answers carry the account's license answer (ROADMAP chip 148) ─────────────────
//
// A phone that was reinstalled keeps its Keychain session but loses the answer it stored. The
// service is the only side that still knows it, so both session answers carry it back.

// sessionLicenseKey reads `license_version` from a session answer's raw JSON. `present` is false
// when the key is missing, which is what an older service sends and what the phone reads as "not
// stated". A struct decode cannot tell a missing key from null, so this reads the raw object.
func sessionLicenseKey(t *testing.T, recorder *httptest.ResponseRecorder) (value *string, present bool) {
	t.Helper()
	if recorder.Code != http.StatusOK {
		t.Fatalf("the session answer was %d: %s", recorder.Code, recorder.Body.String())
	}
	var object map[string]json.RawMessage
	if err := json.Unmarshal(recorder.Body.Bytes(), &object); err != nil {
		t.Fatal(err)
	}
	raw, present := object["license_version"]
	if !present {
		return nil, false
	}
	if string(raw) == "null" {
		return nil, true
	}
	var version string
	if err := json.Unmarshal(raw, &version); err != nil {
		t.Fatalf("license_version is neither null nor a string: %s", raw)
	}
	return &version, true
}

func (h *harness) oidcAs(t *testing.T, subject string, device *uuid.UUID, license *string) *httptest.ResponseRecorder {
	t.Helper()
	signInAs(t, h, subject, device, license) // sets the fake identity and checks the 200
	// A second sign-in with no `license_version` key at all writes nothing, so it reads back the
	// answer the first one stored rather than echoing what this request sent.
	body := map[string]any{
		"identity_token": "an-identity-token", "authorization_code": "an-authorization-code",
		"nonce": harnessNonce,
	}
	return h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", body)
}

func TestSessionAnswersCarryTheAccountsLicenseAnswer(t *testing.T) {
	h := newHarness(t)

	// Calibration: the reader tells a missing key from a null and from a string.
	for _, specimen := range []struct {
		body    string
		present bool
		value   string
	}{{`{}`, false, ""}, {`{"license_version":null}`, true, ""}, {`{"license_version":"x"}`, true, "x"}} {
		recorder := httptest.NewRecorder()
		recorder.WriteString(specimen.body)
		value, present := sessionLicenseKey(t, recorder)
		if present != specimen.present || (value != nil) != (specimen.value != "") ||
			(value != nil && *value != specimen.value) {
			t.Fatalf("the reader read (%v, %v) from %s", value, present, specimen.body)
		}
	}

	// An acceptance at sign-in comes back, both on that sign-in and on a later one that sends
	// nothing about consent.
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "an-identity-token", "authorization_code": "an-authorization-code",
		"nonce": harnessNonce, "license_version": *accepted(),
	})
	if value, present := sessionLicenseKey(t, recorder); !present || value == nil || *value != *accepted() {
		t.Fatalf("a sign-in that accepted answered license_version (%v, present %v)", value, present)
	}
	if value, _ := sessionLicenseKey(t, h.oidcAs(t, "sl.accepted", nil, accepted())); value == nil || *value != *accepted() {
		t.Fatalf("a later sign-in of an accepting account answered %v", value)
	}

	// A decline: the key is present and null.
	if value, present := sessionLicenseKey(t, h.oidcAs(t, "sl.declined", nil, nil)); !present || value != nil {
		t.Fatalf("a declining account answered license_version (%v, present %v), want present and null", value, present)
	}

	// A stored value that is not a known version is not an acceptance.
	stored := signInAs(t, h, "sl.unknown", nil, accepted())
	execSQL(t, h, `UPDATE users SET license_version = 'odbl-9.9' WHERE id = $1`, stored.UserID)
	refreshed := h.do(t, http.MethodPost, Prefix+"/auth/refresh", "", map[string]any{"refresh_token": stored.RefreshToken})
	if value, present := sessionLicenseKey(t, refreshed); !present || value != nil {
		t.Fatalf("an account storing an unknown version refreshed with (%v, present %v), want null", value, present)
	}
}

// TestAFailedLicenseReadStillDeliversTheRotatedSession: the rotation commits before the license
// answer is read. If that read fails, the response must still carry the new refresh token, or the
// phone keeps a spent one and its next refresh signs the person out. The key is left out (the
// phone writes nothing), never sent as null (which would read as "did not agree").
//
// The read is made to fail at the database: `RotateSession` never reads `users`, and
// `UserByID` selects `license_version`, so renaming that column breaks only the read.
func TestAFailedLicenseReadStillDeliversTheRotatedSession(t *testing.T) {
	h := newHarness(t)
	session := signInAs(t, h, "sl.unread", nil, accepted())

	execSQL(t, h, `ALTER TABLE users RENAME COLUMN license_version TO license_version_hidden`)
	restored := false
	restore := func() {
		if !restored {
			execSQL(t, h, `ALTER TABLE users RENAME COLUMN license_version_hidden TO license_version`)
			restored = true
		}
	}
	t.Cleanup(restore)

	refreshed := h.do(t, http.MethodPost, Prefix+"/auth/refresh", "", map[string]any{"refresh_token": session.RefreshToken})
	if refreshed.Code != http.StatusOK {
		t.Fatalf("a refresh whose license read failed answered %d: %s; the rotation had committed, so "+
			"the phone keeps a spent token and its next refresh signs the person out", refreshed.Code, refreshed.Body.String())
	}
	if _, present := sessionLicenseKey(t, refreshed); present {
		t.Fatalf("a refresh whose license read failed sent license_version: %s", refreshed.Body.String())
	}
	var rotated sessionResponse
	if err := json.Unmarshal(refreshed.Body.Bytes(), &rotated); err != nil {
		t.Fatal(err)
	}
	if rotated.RefreshToken == "" || rotated.RefreshToken == session.RefreshToken || rotated.AccessToken == "" {
		t.Fatalf("the refresh did not deliver a new session: %s", refreshed.Body.String())
	}

	// The token it delivered is the live one: with the read working again, it refreshes, and the
	// answer is back.
	restore()
	again := h.do(t, http.MethodPost, Prefix+"/auth/refresh", "", map[string]any{"refresh_token": rotated.RefreshToken})
	if value, present := sessionLicenseKey(t, again); !present || value == nil || *value != *accepted() {
		t.Fatalf("the delivered refresh token did not refresh with the answer: (%v, present %v)", value, present)
	}
}

func TestARefreshCarriesALaterAcceptance(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	session := signInAs(t, h, "sl.later", &deviceUUID, nil)
	if session.LicenseVersion != nil {
		t.Fatalf("the declining sign-in answered %q", *session.LicenseVersion)
	}

	// The You tab's "Share my tree records" row: the agreement goes through the claim.
	if claim := h.do(t, http.MethodPost, Prefix+"/devices/claim", session.AccessToken,
		map[string]any{"device_uuid": deviceUUID, "license_version": *accepted()}); claim.Code != http.StatusOK {
		t.Fatalf("the claim answered %d: %s", claim.Code, claim.Body.String())
	}

	refreshed := h.do(t, http.MethodPost, Prefix+"/auth/refresh", "", map[string]any{"refresh_token": session.RefreshToken})
	if value, present := sessionLicenseKey(t, refreshed); !present || value == nil || *value != *accepted() {
		t.Fatalf("a refresh after a later acceptance answered (%v, present %v), want %q", value, present, *accepted())
	}
}
