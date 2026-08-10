package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/apple"
	"github.com/PlatosTwin/cypress/server/internal/storage"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/tokens"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// fakeApple stands in for Apple. Verification itself is proved against a locally-minted JWKS in
// `internal/apple`; here the interesting thing is what the handlers do with the answer.
type fakeApple struct {
	identity     apple.Identity
	verifyErr    error
	exchangeErr  error
	refreshToken string
	revoked      []string
	revokeErr    error
}

func (f *fakeApple) Verify(context.Context, string) (apple.Identity, error) {
	return f.identity, f.verifyErr
}

func (f *fakeApple) ExchangeAuthorizationCode(context.Context, string) (string, error) {
	if f.exchangeErr != nil {
		return "", f.exchangeErr
	}
	return f.refreshToken, nil
}

func (f *fakeApple) Revoke(_ context.Context, token string) error {
	f.revoked = append(f.revoked, token)
	return f.revokeErr
}

type harness struct {
	server  *Server
	handler http.Handler
	apple   *fakeApple
	store   *store.Store
}

// testDatabaseURL gives this test binary a database of its own.
//
// `go test` runs packages in parallel, and two binaries sharing one database deadlock each other
// between `CREATE TABLE IF NOT EXISTS` and `TRUNCATE`. That failure has nothing to do with the
// code under test and everything to do with the harness, which is the most expensive kind of red
// to debug — so it is designed out rather than worked around with `-p 1`.
func testDatabaseURL(t *testing.T, name string) string {
	t.Helper()
	base := os.Getenv("CYPRESS_TEST_DATABASE_URL")
	if base == "" {
		t.Skip("CYPRESS_TEST_DATABASE_URL is not set; these assertions are about SQL and will not " +
			"be faked. Start a Postgres and set it.")
	}
	admin, err := pgx.Connect(context.Background(), base)
	if err != nil {
		t.Fatalf("connecting to %s: %v", base, err)
	}
	defer admin.Close(context.Background())

	// CREATE DATABASE cannot run in a transaction and has no IF NOT EXISTS, so an already-present
	// database is an expected error rather than a failure.
	if _, err := admin.Exec(context.Background(), "CREATE DATABASE "+name); err != nil &&
		!strings.Contains(err.Error(), "already exists") {
		t.Fatalf("creating %s: %v", name, err)
	}

	parsed, err := url.Parse(base)
	if err != nil {
		t.Fatalf("parsing CYPRESS_TEST_DATABASE_URL: %v", err)
	}
	parsed.Path = "/" + name
	return parsed.String()
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	dataStore, err := store.Open(context.Background(), testDatabaseURL(t, "cypress_test_api"))
	if err != nil {
		t.Fatalf("opening the test database: %v", err)
	}
	t.Cleanup(dataStore.Close)
	_, err = dataStore.Pool().Exec(context.Background(), `
		TRUNCATE anonymized_contributions, favorites, contributions, community_trees, photos,
		         device_tokens, sessions, devices, users RESTART IDENTITY CASCADE
	`)
	if err != nil {
		t.Fatalf("truncating: %v", err)
	}

	signer, err := tokens.NewSigner([]byte("a-test-signing-key-of-at-least-32-bytes"))
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeApple{
		identity:     apple.Identity{Subject: "001234.abcdef.5678", Email: "a@b.test"},
		refreshToken: "apple-refresh-abc",
	}
	server := &Server{
		Store:  dataStore,
		Apple:  fake,
		Signer: signer,
		Presigner: storage.NewPresigner(storage.Config{
			AccessKeyID: "AKIATEST", SecretAccessKey: "secret",
			Endpoint: "https://fly.storage.tigris.dev", Region: "auto", Bucket: "cypress-cities",
		}),
		Log:           slog.New(slog.NewTextHandler(io.Discard, nil)),
		GitSHA:        "test",
		OperatorToken: "the-operator-token",
	}
	return &harness{server: server, handler: server.Handler(), apple: fake, store: dataStore}
}

func (h *harness) do(t *testing.T, method, path, bearer string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(encoded)
	}
	request := httptest.NewRequest(method, path, reader)
	if bearer != "" {
		request.Header.Set("Authorization", "Bearer "+bearer)
	}
	recorder := httptest.NewRecorder()
	h.handler.ServeHTTP(recorder, request)
	return recorder
}

// envelopeOf decodes the error body under the client's rules.
type envelopeOf struct {
	Error struct {
		Code      string `json:"code"`
		Message   string `json:"message"`
		Retryable bool   `json:"retryable"`
	} `json:"error"`
	Detail map[string]any `json:"detail"`
}

func decodeEnvelope(t *testing.T, recorder *httptest.ResponseRecorder) envelopeOf {
	t.Helper()
	var envelope envelopeOf
	if err := json.Unmarshal(recorder.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("body is not an error envelope: %v (%s)", err, recorder.Body.String())
	}
	return envelope
}

// signIn drives the real `POST /auth/oidc` and returns the session.
func (h *harness) signIn(t *testing.T, deviceUUID *uuid.UUID) sessionResponse {
	t.Helper()
	body := map[string]any{
		"identity_token":     "an-identity-token",
		"authorization_code": "an-authorization-code",
		"nonce":              "",
		"device_uuid":        deviceUUID,
		"license_version":    "odbl-1.0",
	}
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", body)
	if recorder.Code != http.StatusOK {
		t.Fatalf("sign-in returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var session sessionResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	return session
}

func (h *harness) registerDeviceToken(t *testing.T, deviceUUID uuid.UUID) string {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/devices/register", "",
		map[string]any{"device_uuid": deviceUUID})
	if recorder.Code != http.StatusOK {
		t.Fatalf("device registration returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var response registerDeviceResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	return response.DeviceToken
}

// ── The 401-vs-item separation ─────────────────────────────────────────────────────────────────

// TestNoSessionFailsTheRequestNotTheItems is the first half of ERRATA E261 §3's fix.
//
// `APIError.unauthorized.retryable` is false, so an `unauthorized` reaching an *item* moves that
// item to `.failed` immediately — terminal, with screen 17 printing "Sign in to send this" to
// somebody who is signed in. The session is therefore checked once, before any item is looked at,
// and fails the whole request. That single 401 is the one the transport refreshes and replays on.
func TestNoSessionFailsTheRequestNotTheItems(t *testing.T) {
	h := newHarness(t)
	items := []map[string]any{{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": uuid.New(),
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
	}}

	recorder := h.do(t, http.MethodPost, Prefix+"/sync", "", map[string]any{"items": items})

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", recorder.Code)
	}
	envelope := decodeEnvelope(t, recorder)
	if envelope.Error.Code != string(apierr.Unauthorized) {
		t.Fatalf("code = %q, want unauthorized", envelope.Error.Code)
	}
	// And crucially: no per-item results. A body carrying `results` would mean the items were
	// judged, and every one of them would have been judged terminally.
	var body map[string]any
	_ = json.Unmarshal(recorder.Body.Bytes(), &body)
	if _, found := body["results"]; found {
		t.Fatal("the request answered per-item results for a session failure; every queued item " +
			"would be marked terminally failed by one expired access token")
	}
}

// TestAnItemThatIsNotYoursIsForbiddenNotUnauthorized is the second half.
//
// The distinction is not cosmetic. Both codes are non-retryable, so the item fails immediately
// either way — but `unauthorized` is the code the transport treats as "the session", and using it
// here would send a client off to refresh a perfectly good token and replay an item that will be
// refused again for the same real reason.
func TestAnItemThatIsNotYoursIsForbiddenNotUnauthorized(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	someoneElse := uuid.New()
	items := []map[string]any{{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": uuid.New(),
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
		// A device credential authorizes items carrying a deviceID and no userID, and that is all.
		"user_id": someoneElse,
	}}

	recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": items})
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a bad item is a per-item verdict, not a failed request", recorder.Code)
	}

	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(response.Results))
	}
	result := response.Results[0]
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed", result.Status)
	}
	if result.Error == nil {
		t.Fatal("no error code on a failed item")
	}
	if *result.Error == apierr.Unauthorized {
		t.Fatal("an item was refused with `unauthorized`: the client would refresh a working " +
			"session and replay an item that is not its to send (ERRATA E261 §3)")
	}
	if *result.Error != apierr.Forbidden {
		t.Fatalf("error = %q, want forbidden", *result.Error)
	}
}

// TestNoHandlerAnswersUnauthorizedPerItem is the standing version of the rule.
//
// The two tests above cover the cases that exist today. This one asserts the invariant over a
// spread of malformed and mis-owned items, so a handler that grows a new refusal cannot reach for
// `unauthorized` without failing here.
func TestNoHandlerAnswersUnauthorizedPerItem(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	items := []map[string]any{
		{"client_uuid": uuid.Nil, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`)},
		{"client_uuid": uuid.New(), "kind": "not_a_kind", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`)},
		{"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": uuid.Nil,
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`)},
		{"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`), "user_id": uuid.New()},
		{"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`), "device_id": uuid.New()},
	}

	recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": items})
	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != len(items) {
		t.Fatalf("got %d results for %d items", len(response.Results), len(items))
	}
	for index, result := range response.Results {
		if result.Error != nil && *result.Error == apierr.Unauthorized {
			t.Errorf("item %d was refused with `unauthorized`; a 401 must mean the session, never "+
				"the item", index)
		}
	}
}

// TestExpiredAccessTokenIsASessionFailure pins what the transport refreshes on.
func TestExpiredAccessTokenIsASessionFailure(t *testing.T) {
	h := newHarness(t)
	past := h.server.Signer.WithClock(func() time.Time { return time.Now().Add(-time.Hour) })
	expired, err := past.Mint(tokens.SubjectUser, uuid.New().String(), uuid.New().String(), tokens.AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}

	recorder := h.do(t, http.MethodPost, Prefix+"/sync", expired, map[string]any{"items": []any{}})
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", recorder.Code)
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.Unauthorized) {
		t.Fatalf("code = %q, want unauthorized", code)
	}
}

// ── Sync semantics over the wire ───────────────────────────────────────────────────────────────

func TestSyncDedupesAndTombstonesBothAnswerDuplicate(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	key := uuid.New()
	item := map[string]any{
		"client_uuid": key, "kind": "visit", "tree_uuid": uuid.New(),
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{"note":"hello"}`),
	}
	send := func() syncResult {
		t.Helper()
		recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken,
			map[string]any{"items": []any{item}})
		var response struct{ Results []syncResult }
		if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
			t.Fatal(err)
		}
		return response.Results[0]
	}

	if got := send().Status; got != "applied" {
		t.Fatalf("first send = %q, want applied", got)
	}
	if got := send().Status; got != "duplicate" {
		t.Fatalf("replay = %q, want duplicate — a success that changes nothing", got)
	}

	// Now the tombstone arm: a signed-in account deletes, and an item naming a tombstoned key
	// arrives afterwards.
	session := h.signIn(t, nil)
	tombstonedKey := uuid.New()
	deleteRecorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken, map[string]any{
		"choice":               "leaveRecords",
		"pending_client_uuids": []uuid.UUID{tombstonedKey},
	})
	if deleteRecorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d: %s", deleteRecorder.Code, deleteRecorder.Body.String())
	}

	item["client_uuid"] = tombstonedKey
	result := send()
	if result.Status != "duplicate" {
		t.Fatalf("an item arriving after the deletion = %q, want duplicate; anything else either "+
			"burns 48 h of backoff or puts a red row on screen 17 for a withdrawn record", result.Status)
	}
	if result.Error != nil {
		t.Fatalf("a tombstoned item carried the error code %q; it is a success", *result.Error)
	}
}

// ── The claim, over the wire ───────────────────────────────────────────────────────────────────

func TestClaimIsIdempotentAndRefusesAnotherAccountsDevice(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	// A visit made anonymously, before the account exists.
	key := uuid.New()
	h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": []any{map[string]any{
		"client_uuid": key, "kind": "visit", "tree_uuid": uuid.New(),
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
	}}})

	first := h.signIn(t, nil)
	for attempt := 1; attempt <= 3; attempt++ {
		recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", first.AccessToken,
			map[string]any{"device_uuid": deviceUUID, "license_version": "odbl-1.0"})
		if recorder.Code != http.StatusOK {
			t.Fatalf("claim attempt %d returned %d: %s", attempt, recorder.Code, recorder.Body.String())
		}
	}

	// A second account on the same phone. The #174 guard.
	h.apple.identity = apple.Identity{Subject: "009999.zzzz.0000", Email: "second@b.test"}
	second := h.signIn(t, nil)
	recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", second.AccessToken,
		map[string]any{"device_uuid": deviceUUID, "license_version": "odbl-1.0"})
	if recorder.Code == http.StatusOK {
		t.Fatal("a second account claimed a device already held by the first — this is #174")
	}
	envelope := decodeEnvelope(t, recorder)
	if envelope.Error.Code != string(apierr.Conflict) {
		t.Fatalf("code = %q, want conflict", envelope.Error.Code)
	}
	if envelope.Error.Retryable {
		t.Error("the refusal is retryable; re-sending cannot change whose device this is")
	}
}

// TestADeviceTokenCannotClaim pins the authority.
func TestADeviceTokenCannotClaim(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", deviceToken,
		map[string]any{"device_uuid": deviceUUID, "license_version": "odbl-1.0"})
	if recorder.Code == http.StatusOK {
		t.Fatal("a device claimed itself for an account it cannot prove it belongs to")
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.Forbidden) {
		t.Fatalf("code = %q, want forbidden — the device's session is valid, it simply cannot do "+
			"this, and answering 401 would send the client off to refresh a working token", code)
	}
}

// ── Sign-in, deletion and Apple's revocation ───────────────────────────────────────────────────

// TestSignInWithoutAnAuthorizationCodeIsRefused pins R72 ruling 2.
//
// Without the code there is no refresh token, and without that `DELETE /me` cannot call Apple's
// revocation endpoint. Refused here, where the person can try again, rather than discovered at
// deletion, where they cannot.
func TestSignInWithoutAnAuthorizationCodeIsRefused(t *testing.T) {
	h := newHarness(t)
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "an-identity-token", "authorization_code": "",
		"nonce": "", "device_uuid": nil, "license_version": nil,
	})
	if recorder.Code == http.StatusOK {
		t.Fatal("a sign-in with no authorization code succeeded; that account could never be " +
			"deleted the way Apple requires")
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.ValidationFailed) {
		t.Fatalf("code = %q, want validation_failed", code)
	}
}

func TestDeletionCallsApplesRevocation(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
		map[string]any{"choice": "leaveRecords", "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d: %s", recorder.Code, recorder.Body.String())
	}
	if len(h.apple.revoked) != 1 {
		t.Fatalf("Apple's revocation endpoint was called %d times, want 1 (R72 ruling 2)", len(h.apple.revoked))
	}
	if h.apple.revoked[0] != "apple-refresh-abc" {
		t.Errorf("revoked %q, want the stored refresh token", h.apple.revoked[0])
	}
}

// TestDeletionRefusesAnUnknownChoice pins that the door is the person's.
func TestDeletionRefusesAnUnknownChoice(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	for _, choice := range []string{"", "leave", "eraseeverything", "delete_all"} {
		recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
			map[string]any{"choice": choice, "pending_client_uuids": []uuid.UUID{}})
		if recorder.Code == http.StatusOK {
			t.Fatalf("choice %q was accepted; defaulting here silently picks a door for somebody "+
				"who may have chosen the other one", choice)
		}
	}
}

// TestDeletionProceedsWhenApplesRevocationFails covers the outage case.
func TestDeletionProceedsWhenApplesRevocationFails(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	h.apple.revokeErr = errors.New("Apple is having a day")

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
		map[string]any{"choice": "eraseEverything", "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d; refusing to delete an account because a third party is "+
			"having an outage breaks the promise R3 already ships", recorder.Code)
	}
	// The token is deliberately not cleared, so the revocation can be retried by an operator.
	var stored string
	err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM users WHERE id = $1`, session.UserID).Scan(&stored)
	if err == nil && stored != "0" {
		t.Log("user row state after a failed revocation:", stored)
	}
}

// ── The photo rules ────────────────────────────────────────────────────────────────────────────

func TestSignedInPhotoIsAutoApprovedAndDeviceIsNot(t *testing.T) {
	h := newHarness(t)

	session := h.signIn(t, nil)
	recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", session.AccessToken, map[string]any{
		"tree_uuid": uuid.New(), "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("begin returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var accountTicket beginPhotoResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &accountTicket); err != nil {
		t.Fatal(err)
	}
	if accountTicket.Moderation != "approved" {
		t.Fatalf("a signed-in account's photo is %q, want approved", accountTicket.Moderation)
	}
	if accountTicket.ApprovalReason != "auto_approved_launch" {
		t.Fatalf("approval_reason = %q, want auto_approved_launch", accountTicket.ApprovalReason)
	}
	if accountTicket.Destination == "" {
		t.Error("no presigned destination; the client has nowhere to PUT the binary")
	}

	deviceToken := h.registerDeviceToken(t, uuid.New())
	recorder = h.do(t, http.MethodPost, Prefix+"/photos/begin", deviceToken, map[string]any{
		"tree_uuid": uuid.New(), "visit_client_uuid": nil, "shot_type": "trunk",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	var deviceTicket beginPhotoResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &deviceTicket); err != nil {
		t.Fatal(err)
	}
	if deviceTicket.Moderation != "pending" {
		t.Fatalf("an anonymous device's photo is %q, want pending: first-party means the "+
			"signed-in account, not the device", deviceTicket.Moderation)
	}
}

// TestTakedownRemovesAPhotoFromEveryoneElsesProfile is R72 ruling 5's other half, end to end.
func TestTakedownRemovesAPhotoFromEveryoneElsesProfile(t *testing.T) {
	h := newHarness(t)
	tree := uuid.New()

	session := h.signIn(t, nil)
	recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", session.AccessToken, map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	var ticket beginPhotoResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &ticket); err != nil {
		t.Fatal(err)
	}

	// A second reader — a different device — sees it, which is the acceptance criterion's last mile.
	readerToken := h.registerDeviceToken(t, uuid.New())
	profile := func() map[string]any {
		t.Helper()
		r := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), readerToken, nil)
		if r.Code != http.StatusOK {
			t.Fatalf("profile returned %d: %s", r.Code, r.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(r.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return body
	}

	if count := profile()["photo_count"].(float64); count != 1 {
		t.Fatalf("another device sees %v photographs, want 1 — this is the acceptance criterion", count)
	}

	takedown := h.do(t, http.MethodPost,
		Prefix+"/operator/photos/"+ticket.PhotoID.String()+"/reject", "the-operator-token", nil)
	if takedown.Code != http.StatusOK {
		t.Fatalf("takedown returned %d: %s", takedown.Code, takedown.Body.String())
	}

	if count := profile()["photo_count"].(float64); count != 0 {
		t.Fatalf("after the takedown another device still sees %v photographs; auto-approve "+
			"without a working takedown is the version of the rule that must not ship", count)
	}
}

func TestTakedownRequiresTheOperatorCredential(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	for name, bearer := range map[string]string{
		"no credential":    "",
		"a user session":   session.AccessToken,
		"the wrong secret": "not-the-operator-token",
	} {
		recorder := h.do(t, http.MethodPost,
			Prefix+"/operator/photos/"+uuid.New().String()+"/reject", bearer, nil)
		if recorder.Code == http.StatusOK {
			t.Errorf("%s performed a takedown", name)
		}
		if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.Forbidden) {
			t.Errorf("%s: code = %q, want forbidden", name, code)
		}
	}
}

// ── The proximity conflict carries its candidates ──────────────────────────────────────────────

func TestProximityConflictCarriesTheCandidateList(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	const lat, lon = 37.7601, -122.5050
	first := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat, "lon": lon, "display_name": "A tree",
	})
	if first.Code != http.StatusOK {
		t.Fatalf("first tree returned %d: %s", first.Code, first.Body.String())
	}

	second := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat + 5.0/111_320.0, "lon": lon, "display_name": "The same tree",
	})
	if second.Code == http.StatusOK {
		t.Fatal("a tree 5 m from another was accepted; the 10 m dedupe did not trip")
	}

	envelope := decodeEnvelope(t, second)
	if envelope.Error.Code != string(apierr.Conflict) {
		t.Fatalf("code = %q, want conflict", envelope.Error.Code)
	}
	if envelope.Error.Retryable {
		t.Error("conflict is retryable; the item would spend 48 h on an answer only the user can give")
	}
	candidates, ok := envelope.Detail["candidates"].([]any)
	if !ok || len(candidates) == 0 {
		t.Fatal("the conflict carried no candidate list; ProximityConflict exists to show it, and a " +
			"conflict with nothing in it is a dead end wearing the same code")
	}
}

// ── Reads ──────────────────────────────────────────────────────────────────────────────────────

func TestGroveAndMembershipAnswerTheCallersOwnRows(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	tree := uuid.New()

	h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": []any{map[string]any{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
	}}})

	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", deviceToken, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("grove returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var grove struct {
		Entries []map[string]any `json:"entries"`
		Total   int              `json:"total"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &grove); err != nil {
		t.Fatal(err)
	}
	if grove.Total != 1 || len(grove.Entries) != 1 {
		t.Fatalf("grove has %d entries, want 1", len(grove.Entries))
	}

	// A different device sees none of it. D11: privacy is the shape of the query.
	otherToken := h.registerDeviceToken(t, uuid.New())
	recorder = h.do(t, http.MethodGet, Prefix+"/me/grove", otherToken, nil)
	if err := json.Unmarshal(recorder.Body.Bytes(), &grove); err != nil {
		t.Fatal(err)
	}
	if grove.Total != 0 {
		t.Fatalf("another device sees %d of this one's entries", grove.Total)
	}

	membership := h.do(t, http.MethodGet, Prefix+"/me/map-membership?kind=yours", deviceToken, nil)
	if membership.Code != http.StatusOK {
		t.Fatalf("membership returned %d", membership.Code)
	}
	var response struct {
		TreeIDs []uuid.UUID `json:"tree_ids"`
	}
	if err := json.Unmarshal(membership.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.TreeIDs) != 1 || response.TreeIDs[0] != tree {
		t.Fatalf("membership = %v, want [%v]", response.TreeIDs, tree)
	}
}

// TestUnknownMembershipKindIsRefusedRatherThanEmpty is the #76 hazard, server side.
//
// An empty set is a *claim*: screen 01 would draw a map on which this reader owns and hearts
// nothing, and nothing would throw or log. That is exactly what the client's inherited
// `mapMembership` default did before task #76.
func TestUnknownMembershipKindIsRefusedRatherThanEmpty(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	recorder := h.do(t, http.MethodGet, Prefix+"/me/map-membership?kind=favourites", deviceToken, nil)
	if recorder.Code == http.StatusOK {
		t.Fatal("an unrecognized membership kind answered rather than refused; an empty set here " +
			"draws a map on which this reader owns nothing")
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.ValidationFailed) {
		t.Fatalf("code = %q, want validation_failed", code)
	}
}

func TestHealthReportsTheSHA(t *testing.T) {
	h := newHarness(t)
	recorder := h.do(t, http.MethodGet, "/health", "", nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("health returned %d", recorder.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["git_sha"] != "test" {
		t.Errorf("git_sha = %v", body["git_sha"])
	}
	// The placeholder's tell is gone: this is no longer scaffolding.
	if _, found := body["placeholder"]; found {
		t.Error("health still reports `placeholder`")
	}
}
