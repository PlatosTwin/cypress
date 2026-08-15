package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"slices"
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

	// **Dropped and recreated, not reused.** The schema is applied with `CREATE TABLE IF NOT
	// EXISTS`, so a database left over from a previous run keeps whatever shape it had — and a
	// changed column would then be tested in its old form, silently, which is a green that means
	// nothing. Building it from scratch every run is the only way the schema under test is the
	// schema in the file.
	if _, err := admin.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)"); err != nil {
		t.Fatalf("dropping %s: %v", name, err)
	}
	if _, err := admin.Exec(context.Background(), "CREATE DATABASE "+name); err != nil {
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
	// The nonce is required by construction (N10), so the harness carries a real pair: the raw
	// value the app would keep, and the SHA-256 hex Apple echoes into the identity token.
	fake := &fakeApple{
		identity: apple.Identity{
			Subject: "001234.abcdef.5678", Email: "a@b.test", Nonce: sha256Hex(harnessNonce),
		},
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

// syncOne posts a single item and returns its verdict.
func (h *harness) syncOne(t *testing.T, bearer string, item map[string]any) syncResult {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/sync", bearer, map[string]any{"items": []any{item}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("sync returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(response.Results))
	}
	return response.Results[0]
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
		"nonce":              harnessNonce,
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

// TestADeviceMaySendItemsThatNameItself is the case every green test in this file omitted.
//
// ── Why it did not exist, and what that cost ───────────────────────────────────────────────────
//
// `syncItem.device_id` is the phone's own installation id — `app_state.device_uuid`, the value it
// registered with. `caller.DeviceID` was `devices.id`, the row key this database mints in
// `RegisterDevice`. `applyOne` compared the two, so the predicate was true for **every** anonymous
// item that named itself, and `forbidden` is not retryable: the client's whole queue moved to
// `failed` on its first drain and screen 17 printed "This account is not allowed to send that."
//
// Nothing here caught it, and the reason is the shape worth remembering — stated from the file
// rather than from memory, because the first draft of this paragraph cited two tests that have
// never existed in this repository.
//
// Four tests sync successfully under a device credential — `TestGroveAndMembershipAnswerTheCallers
// OwnRows`, `TestAnUnknownFieldFailsOnlyItsOwnItem`, `TestAnUnknownEnvelopeKeyDoesNotFailTheBatch`,
// `TestSyncDedupesAndTombstonesBothAnswerDuplicate` — and **every one of them omits `device_id`**.
// The whole suite contained exactly one item that carried one: the fifth of five in
// `TestNoHandlerAnswersUnauthorizedPerItem`, which sends `uuid.New()`, a stranger's. And that test
// asserts only that the code is **not `unauthorized`** — which is true with the defect and true
// without it, so it could not discriminate even about the case it did send.
//
// `TestAnItemThatIsNotYoursIsForbiddenNotUnauthorized` is the nearest neighbour by name and is not
// this case either: it sends somebody else's **`user_id`** under a device credential, exercising the
// user arm of the same switch.
//
// So the suite covered "no device id", never covered "my own device id" — the only one a real client
// sends — and covered "somebody else's" only in a form that could not tell the two implementations
// apart. A guard green with its defect present, because the case that would fail it was never
// written.
//
// It was found by pointing the shipping client at the deployed service (#158's wiring round) and
// isolating it with three probes on one credential: own `device_uuid` → forbidden, a stranger's →
// forbidden *identically*, omitted → applied. Two different inputs answering the same way is what
// said the comparison could not be about ownership at all.
//
// All three probes are asserted here, together, because the middle one is what makes the first a
// measurement: a fix that simply stopped checking `device_id` would pass the own-id case and fail
// the stranger's.
func TestADeviceMaySendItemsThatNameItself(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)

	mine, stranger, silent := uuid.New(), uuid.New(), uuid.New()
	items := []map[string]any{
		// The real client's shape: this device, naming itself.
		{"client_uuid": mine, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
			"device_id": deviceUUID},
		// Somebody else's installation. Still refused, and refused for a reason that is about
		// ownership rather than about vocabulary.
		{"client_uuid": stranger, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
			"device_id": uuid.New()},
		// No claim at all — the shape the rest of this file uses, unchanged by the repair.
		{"client_uuid": silent, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`)},
	}

	recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": items})
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}
	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != len(items) {
		t.Fatalf("got %d results for %d items", len(response.Results), len(items))
	}
	byKey := map[uuid.UUID]syncResult{}
	for _, result := range response.Results {
		byKey[result.ClientUUID] = result
	}

	own := byKey[mine]
	if own.Status != "applied" {
		reason := "no error"
		if own.Error != nil {
			reason = string(*own.Error) + ": " + own.Message
		}
		t.Fatalf("an item naming its own device was %q (%s), want applied — a phone that names "+
			"itself is doing exactly what D9 asks, and `forbidden` here fails its whole queue "+
			"terminally on the first drain", own.Status, reason)
	}

	other := byKey[stranger]
	if other.Status != "failed" || other.Error == nil || *other.Error != apierr.Forbidden {
		t.Fatalf("an item naming somebody else's device was %q, want failed/forbidden — the "+
			"ownership check must still refuse, or this repair removed it rather than fixing it",
			other.Status)
	}

	quiet := byKey[silent]
	if quiet.Status != "applied" {
		t.Fatalf("an item claiming no device was %q, want applied", quiet.Status)
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
	h.apple.identity = apple.Identity{
		Subject: "009999.zzzz.0000", Email: "second@b.test", Nonce: sha256Hex(harnessNonce),
	}
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

// TestSignInOnAPhoneHeldByAnotherAccountIsRefused is F3 of PR #84's review, made un-regressable.
//
// `POST /auth/oidc` performs the claim inline when the body carries a `device_uuid`, and it used to
// swallow `ErrClaimedByAnotherAccount` and answer 200 with a session anyway. Nothing here ever
// clears `devices.user_id` — a sign-out is not a request this service receives — so the reachable
// sequence is ordinary: A signs in on a phone and signs out, B signs in. The service kept every
// contribution on A, handed B a session, and B's client then moved its own local rows to B. Two
// sides, one phone, and no agreement about who owns the work.
//
// The assertions are in two halves on purpose. The refusal is the visible one; **that the work
// stayed with A** is the one that says the guard did its job rather than merely returned an error.
func TestSignInOnAPhoneHeldByAnotherAccountIsRefused(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()

	// A's phone, with something on it worth arguing over.
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	key := uuid.New()
	h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": key, "kind": "visit", "tree_uuid": uuid.New(),
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
	})
	first := h.signIn(t, &deviceUUID)

	// B, on the same phone. A different Apple subject, so this is a different account.
	h.apple.identity = apple.Identity{
		Subject: "007777.yyyy.1111", Email: "third@b.test", Nonce: sha256Hex(harnessNonce),
	}
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "an-identity-token", "authorization_code": "an-authorization-code",
		"nonce": harnessNonce, "device_uuid": deviceUUID, "license_version": "odbl-1.0",
	})

	if recorder.Code == http.StatusOK {
		t.Fatal("a second account signed in on a phone the first still holds, and got a session. " +
			"The service keeps the work on the first account while the client moves its local rows " +
			"to the second, and screen 15 draws success over the disagreement")
	}
	envelope := decodeEnvelope(t, recorder)
	if envelope.Error.Code != string(apierr.Conflict) {
		t.Fatalf("code = %q, want conflict — the same code and sentence POST /devices/claim "+
			"already answers with, because it is the same guard tripping", envelope.Error.Code)
	}
	if envelope.Error.Retryable {
		t.Error("the refusal is retryable; re-sending cannot change whose device this is")
	}

	// The half that matters: nothing moved.
	var owner *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT user_id FROM contributions WHERE client_uuid = $1`, key).Scan(&owner); err != nil {
		t.Fatalf("reading the contribution back: %v", err)
	}
	if owner == nil || *owner != first.UserID {
		t.Fatalf("the visit ended up owned by %v, want the first account %v — the refusal was "+
			"returned after the sweep had already run", owner, first.UserID)
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
		"nonce": harnessNonce, "device_uuid": nil, "license_version": nil,
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

// TestDeletionProceedsWhenApplesRevocationFails covers the outage case, and what it must not lose.
//
// The previous version of this test queried `count(*) FROM users` into a string, compared it to
// "0" inside an `err == nil` guard, and its only consequence was `t.Log` — so it could not fail,
// and it was the guard for the claim that the token survives a failed revocation. It did not.
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

	var users int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM users WHERE id = $1`, session.UserID).Scan(&users); err != nil {
		t.Fatal(err)
	}
	if users != 0 {
		t.Fatalf("the account survived the deletion (%d rows)", users)
	}

	// The obligation outlives the row. R72 ruling 2 makes the revocation a requirement, not an
	// attempt; discarding the token would leave the person deleted here and still granted at Apple,
	// with nothing that could ever put it right.
	var parked string
	err := h.store.Pool().QueryRow(context.Background(),
		`SELECT coalesce(max(refresh_token), '') FROM pending_apple_revocations`).Scan(&parked)
	if err != nil {
		t.Fatal(err)
	}
	if parked != "apple-refresh-abc" {
		t.Fatalf("after a failed revocation the parked token is %q, want the stored refresh token. "+
			"Without it nothing can ever retry, and Apple still holds a live grant.", parked)
	}
}

// TestSuccessfulRevocationParksNothing is the other arm: the queue is for failures only.
func TestSuccessfulRevocationParksNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
		map[string]any{"choice": "leaveRecords", "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d", recorder.Code)
	}

	var parked int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM pending_apple_revocations`).Scan(&parked); err != nil {
		t.Fatal(err)
	}
	if parked != 0 {
		t.Fatalf("a successful revocation parked %d tokens; the queue would never drain", parked)
	}
}

// ── B1: the door on the wire is the door that is applied ───────────────────────────────────────

// TestTheChoiceOnTheWireIsTheChoiceApplied is the end-to-end version, per door.
//
// Spec §6.3: "The choice travels on the wire; it is not a server default." The previous tests
// proved the choice was *parsed* (`TestDeletionRefusesAnUnknownChoice`) and that the store erases
// when handed the constant (`TestDeletionEraseEverythingRemovesTheRows`, which calls the store
// directly and never crosses the handler). Nothing proved the handler passed the person's answer
// through — substituting `choice = store.LeaveRecords` immediately before the store call left the
// whole suite green, which is a server that keeps everything somebody asked to have erased.
func TestTheChoiceOnTheWireIsTheChoiceApplied(t *testing.T) {
	for _, door := range []struct {
		choice        string
		wantRowsAfter int
		wantAnonymous bool
		why           string
	}{
		{"leaveRecords", 1, true,
			"the leaving door keeps contributions on the trees they were made about, with the name taken off"},
		{"eraseEverything", 0, false,
			"the erasing door deletes them outright"},
	} {
		t.Run(door.choice, func(t *testing.T) {
			h := newHarness(t)
			session := h.signIn(t, nil)

			key, tree := uuid.New(), uuid.New()
			sync := h.do(t, http.MethodPost, Prefix+"/sync", session.AccessToken,
				map[string]any{"items": []any{map[string]any{
					"client_uuid": key, "kind": "visit", "tree_uuid": tree,
					"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
				}}})
			if sync.Code != http.StatusOK {
				t.Fatalf("sync returned %d: %s", sync.Code, sync.Body.String())
			}

			recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
				map[string]any{"choice": door.choice, "pending_client_uuids": []uuid.UUID{}})
			if recorder.Code != http.StatusOK {
				t.Fatalf("deletion returned %d: %s", recorder.Code, recorder.Body.String())
			}

			var rows int
			if err := h.store.Pool().QueryRow(context.Background(),
				`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&rows); err != nil {
				t.Fatal(err)
			}
			if rows != door.wantRowsAfter {
				t.Fatalf("%s: %d rows remain, want %d — %s",
					door.choice, rows, door.wantRowsAfter, door.why)
			}

			if door.wantAnonymous {
				var ownerUser, ownerDevice *uuid.UUID
				var anonymizedAt *time.Time
				err := h.store.Pool().QueryRow(context.Background(),
					`SELECT user_id, device_id, anonymized_at FROM contributions WHERE client_uuid = $1`, key).
					Scan(&ownerUser, &ownerDevice, &anonymizedAt)
				if err != nil {
					t.Fatal(err)
				}
				if ownerUser != nil || ownerDevice != nil {
					t.Error("the surviving row still names an owner")
				}
				if anonymizedAt == nil {
					t.Error("the surviving row is ownerless but unmarked")
				}
			}
		})
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
		"client_uuid": uuid.New(), "lat": lat, "lon": lon, "address": "1 Main St",
	})
	if first.Code != http.StatusOK {
		t.Fatalf("first tree returned %d: %s", first.Code, first.Body.String())
	}

	second := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat + 5.0/111_320.0, "lon": lon, "address": "1 Main St",
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

// ── B2: a byte-identical retry of POST /trees ──────────────────────────────────────────────────

// TestReplayingATreeIsDuplicateNotAConflictWithItself is the flap-replay case §6.1 exists for.
//
// The dedupe is "10 m, any species", so a retry of the same submission matches the row it created
// moments ago at zero metres. Answering `conflict` there is not a near-miss: the code is
// non-retryable, so the item fails terminally and screen 17 offers the contributor a resolution
// sheet listing their own submission.
func TestReplayingATreeIsDuplicateNotAConflictWithItself(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	const lat, lon = 37.7601, -122.5050
	body := map[string]any{
		"client_uuid": uuid.New(), "lat": lat, "lon": lon, "address": "1 Main St",
	}

	first := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, body)
	if first.Code != http.StatusOK {
		t.Fatalf("first submission returned %d: %s", first.Code, first.Body.String())
	}
	var firstBody struct {
		ID     uuid.UUID `json:"id"`
		Status string    `json:"status"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &firstBody); err != nil {
		t.Fatal(err)
	}
	if firstBody.Status != "applied" {
		t.Fatalf("first submission = %q, want applied", firstBody.Status)
	}

	replay := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, body)
	if replay.Code != http.StatusOK {
		envelope := decodeEnvelope(t, replay)
		t.Fatalf("the replay returned %d %s — it collided with the row it had just created; "+
			"conflict is non-retryable, so the item fails terminally and the contributor is shown "+
			"their own submission as a duplicate candidate",
			replay.Code, envelope.Error.Code)
	}
	var replayBody struct {
		ID     uuid.UUID `json:"id"`
		Status string    `json:"status"`
	}
	if err := json.Unmarshal(replay.Body.Bytes(), &replayBody); err != nil {
		t.Fatal(err)
	}
	if replayBody.Status != "duplicate" {
		t.Fatalf("the replay = %q, want duplicate — a success that changes nothing", replayBody.Status)
	}
	if replayBody.ID != firstBody.ID {
		t.Errorf("the replay reported id %v, the original %v", replayBody.ID, firstBody.ID)
	}
}

// TestATreeIdIsTheClientsOwnId is M4: one identity, or the reads disagree.
func TestATreeIdIsTheClientsOwnId(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	treeID := uuid.New()

	added := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": treeID, "lat": 37.7601, "lon": -122.5050, "address": "2 Main St",
	})
	if added.Code != http.StatusOK {
		t.Fatalf("add returned %d: %s", added.Code, added.Body.String())
	}
	var addBody struct {
		ID uuid.UUID `json:"id"`
	}
	if err := json.Unmarshal(added.Body.Bytes(), &addBody); err != nil {
		t.Fatal(err)
	}
	if addBody.ID != treeID {
		t.Fatalf("POST /trees answered id %v for a tree the client called %v; a second identity "+
			"means the reads disagree about which one names the tree", addBody.ID, treeID)
	}

	membership := h.do(t, http.MethodGet, Prefix+"/me/map-membership?kind=yours", deviceToken, nil)
	var response struct {
		TreeIDs []uuid.UUID `json:"tree_ids"`
	}
	if err := json.Unmarshal(membership.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, id := range response.TreeIDs {
		if id == treeID {
			found = true
		}
	}
	if !found {
		t.Fatalf("map membership returned %v, which does not include the tree the contributor "+
			"added (%v) — screen 01 would draw it under an id no other route answers to",
			response.TreeIDs, treeID)
	}

	// And the id it reports is one the profile route actually answers to.
	profile := h.do(t, http.MethodGet, Prefix+"/trees/"+treeID.String(), deviceToken, nil)
	if profile.Code != http.StatusOK {
		t.Fatalf("the profile route returned %d for the id membership reported", profile.Code)
	}
}

// TestProximityConflictCandidatesCarryAWholeTree is M3.
//
// `ProximityConflict.candidates` is `[NearbyTree]`, which wraps a whole `Tree` — a candidate list of
// bare ids cannot build one, and a community-added tree is by definition absent from the installed
// city file, so the phone cannot fill the gap locally either.
func TestProximityConflictCandidatesCarryAWholeTree(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	const lat, lon = 37.7601, -122.5050
	if got := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat, "lon": lon, "address": "1 Main St",
	}); got.Code != http.StatusOK {
		t.Fatalf("first tree returned %d: %s", got.Code, got.Body.String())
	}

	second := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat + 5.0/111_320.0, "lon": lon, "address": "1 Main St",
	})
	if second.Code == http.StatusOK {
		t.Fatal("a tree 5 m from another was accepted")
	}

	var body struct {
		Detail struct {
			// The keys are `NearbyTree`'s and `Tree`'s **synthesized Swift property names** — see
			// internal/api/wire.go for why a snake_case body would decode `speciesCurrentID` as a
			// silent nil rather than throwing.
			Candidates []wireNearbyTree `json:"candidates"`
		} `json:"detail"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &body); err != nil {
		t.Fatalf("the conflict body does not decode into NearbyTree's shape: %v\n%s",
			err, second.Body.String())
	}
	if len(body.Detail.Candidates) != 1 {
		t.Fatalf("got %d candidates, want 1", len(body.Detail.Candidates))
	}

	candidate := body.Detail.Candidates[0]
	if candidate.Tree.ID.IsNil() {
		t.Error("the candidate carries no tree id; NearbyTree.id is tree.id")
	}
	if candidate.Tree.Source != "community" {
		t.Errorf("source = %q, want community — this table holds nothing else", candidate.Tree.Source)
	}
	if candidate.Tree.VerificationState != "unverified" {
		t.Errorf("verification_state = %q, want unverified — a community submission is neither a "+
			"city row nor org-confirmed", candidate.Tree.VerificationState)
	}
	// **Membership, not emptiness.** The guard this replaces asked whether the string was empty,
	// which is one way a decoder throws; the way that was actually happening was a value outside
	// the vocabulary (`"unknown"`), on every candidate. The vocabulary is read off Tree.swift in
	// `TestTreePlacementMatchesTheSwiftVocabulary`; here it is enough that the value is one of them.
	declaredPlacements := swiftEnumRawValues(t, "../../../Cypress/Core/Models/Tree.swift", "TreePlacement")
	if !slices.Contains(declaredPlacements, candidate.Tree.Placement) {
		t.Errorf("placement = %q, which is not a TreePlacement raw value %v — Tree.placement is "+
			"non-optional, so every candidate would fail to decode", candidate.Tree.Placement, declaredPlacements)
	}
	declaredStatuses := swiftEnumRawValues(t, "../../../Cypress/Core/Models/Tree.swift", "TreeStatus")
	if !slices.Contains(declaredStatuses, candidate.Tree.Status) {
		t.Errorf("status = %q, which is not a TreeStatus raw value %v", candidate.Tree.Status, declaredStatuses)
	}
	if candidate.Tree.Coordinate.Latitude == 0 || candidate.Tree.Coordinate.Longitude == 0 {
		t.Error("the tree carries no coordinate")
	}
	// The keys themselves, on the bytes: `Coordinate`'s stored properties are `latitude` and
	// `longitude`, and no key strategy turns `lat` into `latitude`.
	// **Every key `Tree` declares, on the bytes.** A Go struct with the right tags proves the
	// handler agrees with this test author's transcription; the point of listing them here is that
	// the list is checked against the Swift declaration by
	// `TestWireTreeCoversEveryTreeProperty` below, so neither side is the author's memory.
	for _, key := range swiftStoredPropertyNames(t, "../../../Cypress/Core/Models/Tree.swift", "Tree") {
		if !bytes.Contains(second.Body.Bytes(), []byte(`"`+key+`"`)) {
			t.Errorf("the body does not carry %q; Tree's synthesized CodingKeys expect exactly that "+
				"spelling, and no key strategy produces it from a snake_case body", key)
		}
	}
	for _, key := range []string{`"distanceM"`, `"speciesScientificName"`, `"speciesCommonName"`, `"tell"`} {
		if !bytes.Contains(second.Body.Bytes(), []byte(key)) {
			t.Errorf("the body does not carry %s; NearbyTree's synthesized CodingKeys expect it", key)
		}
	}
	for _, absent := range []string{`"lat"`, `"lon"`, `"distance_m"`, `"verification_state"`,
		`"species_current_id"`, `"neighborhood_id"`, `"created_at"`} {
		if bytes.Contains(second.Body.Bytes(), []byte(absent)) {
			t.Errorf("the body still carries %s, which no Swift CodingKey matches — and because the "+
				"matching property is optional it would decode as a silent nil rather than throwing", absent)
		}
	}
	if candidate.DistanceM <= 0 || candidate.DistanceM > 10 {
		t.Errorf("distance_m = %v, want a real distance inside the 10 m radius", candidate.DistanceM)
	}
	// Present-and-null rather than absent: the client decodes an optional, and a missing key is a
	// different thing from a stated "we do not know".
	if candidate.Tell != nil {
		t.Error("a tell was invented; IDTip comes from the curated pipeline and the seed leaves it empty")
	}
	if candidate.SpeciesScientificName != nil || candidate.SpeciesCommonName != nil {
		t.Error("species names were invented; this service holds no species table")
	}
	for _, key := range []string{"speciesScientificName", "speciesCommonName", "tell"} {
		if !bytes.Contains(second.Body.Bytes(), []byte(`"`+key+`"`)) {
			t.Errorf("%s is absent rather than null; the client decodes an optional, and absent is "+
				"a different fact from stated-as-unknown", key)
		}
	}
}

// ── B3: is_favorite must not be fabricated ─────────────────────────────────────────────────────

func TestFavoriteToggleReadsTheStateFromThePayload(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	tree := uuid.New()

	// The client's own payload, verbatim — `FavoriteToggle` encodes `isFavorite`, and the top-level
	// mirror is absent because nothing on the client knows to write it yet.
	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "favorite_toggle", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{"isFavorite":true,"treeID":"` + tree.String() + `"}`),
	})
	if result.Status != "applied" {
		t.Fatalf("status = %q, want applied", result.Status)
	}

	var stored bool
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT is_favorite FROM favorites WHERE tree_uuid = $1`, tree).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if !stored {
		t.Fatal("the payload said the tree is a favorite and the row says it is not; as a plain " +
			"bool the absent top-level field wrote false and answered `applied`, so the heart went " +
			"off and nothing errored")
	}
}

func TestFavoriteToggleWithNoStateAnywhereIsRefused(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "favorite_toggle", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{"treeID":"` + tree.String() + `"}`),
	})
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed — a missing required field must be an error, not a "+
			"fabricated false", result.Status)
	}
	if result.Error == nil || *result.Error != apierr.ValidationFailed {
		t.Fatalf("error = %v, want validation_failed", result.Error)
	}

	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM favorites WHERE tree_uuid = $1`, tree).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 0 {
		t.Fatal("a refused toggle still wrote a favorite row")
	}
}

func TestFavoriteToggleDisagreeingWithItselfIsRefused(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "favorite_toggle", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(), "is_favorite": false,
		"payload": json.RawMessage(`{"isFavorite":true}`),
	})
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed — two sources disagreeing about a toggle is a malformed "+
			"item, not something to resolve by precedence", result.Status)
	}
}

// ── B4: one bad item does not fail the batch ───────────────────────────────────────────────────

// TestAnUnknownFieldFailsOnlyItsOwnItem is the handler's own header, made true.
//
// "Why every item gets an answer and the request does not fail… A batch that failed as a whole
// would give every row the same verdict." Strict decoding at batch scope meant one additive field
// on one item returned 400 with no results at all, and `validation_failed` is non-retryable, so a
// client following the taxonomy failed its entire queue terminally.
func TestAnUnknownFieldFailsOnlyItsOwnItem(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	goodKey, badKey := uuid.New(), uuid.New()
	recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{"items": []any{
		map[string]any{
			"client_uuid": goodKey, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
		},
		map[string]any{
			"client_uuid": badKey, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
			"schema_version": 2,
		},
	}})

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — one unrecognized field on one item must not fail the "+
			"batch; the good item gets no verdict and the whole queue dies terminally", recorder.Code)
	}
	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != 2 {
		t.Fatalf("got %d results for 2 items", len(response.Results))
	}

	byKey := map[uuid.UUID]syncResult{}
	for _, result := range response.Results {
		byKey[result.ClientUUID] = result
	}
	if byKey[goodKey].Status != "applied" {
		t.Errorf("the well-formed item = %q, want applied", byKey[goodKey].Status)
	}
	bad, found := byKey[badKey]
	if !found {
		t.Fatal("the malformed item got no verdict naming it; a result the client cannot match to a " +
			"queue row is one it has to discard")
	}
	if bad.Status != "failed" {
		t.Errorf("the malformed item = %q, want failed", bad.Status)
	}
}

// ── B6: the nonce ──────────────────────────────────────────────────────────────────────────────

func TestNonceMustMatchWhenTheTokenCarriesOne(t *testing.T) {
	h := newHarness(t)
	raw := "the-app-generated-nonce"
	h.apple.identity = apple.Identity{
		Subject: "001234.abcdef.5678", Email: "a@b.test", Nonce: sha256Hex(raw),
	}
	_ = harnessNonce

	// The happy arm: the raw nonce, hashed here, matching the claim.
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "t", "authorization_code": "c", "nonce": raw,
		"device_uuid": nil, "license_version": nil,
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("a matching nonce was refused: %d %s", recorder.Code, recorder.Body.String())
	}

	// The bypass the previous guard allowed: omit the field and the comparison was skipped.
	for name, nonce := range map[string]any{
		"omitted":  "",
		"wrong":    "some-other-nonce",
		"the hash": sha256Hex(raw),
	} {
		recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
			"identity_token": "t", "authorization_code": "c", "nonce": nonce,
			"device_uuid": nil, "license_version": nil,
		})
		if recorder.Code == http.StatusOK {
			t.Errorf("a %s nonce was accepted against a token carrying a nonce claim; anyone "+
				"holding a captured identity token replays it this way", name)
			continue
		}
		if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.Unauthorized) {
			t.Errorf("%s nonce: code = %q, want unauthorized", name, code)
		}
	}
}

// TestNonceIsRequiredWhenTheCallerSendsOne pins the other direction.
func TestNonceIsRequiredWhenTheCallerSendsOne(t *testing.T) {
	h := newHarness(t)
	h.apple.identity = apple.Identity{Subject: "001234.abcdef.5678", Nonce: ""}

	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "t", "authorization_code": "c", "nonce": "a-nonce-the-token-does-not-carry",
		"device_uuid": nil, "license_version": nil,
	})
	if recorder.Code == http.StatusOK {
		t.Fatal("the caller presented a nonce and the token carried none, and it was accepted")
	}
}

// ── M1: re-registration retires the previous credential ────────────────────────────────────────

func TestReRegisteringADeviceRetiresTheOldToken(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()

	first := h.registerDeviceToken(t, deviceUUID)
	if got := h.do(t, http.MethodGet, Prefix+"/me/grove", first, nil); got.Code != http.StatusOK {
		t.Fatalf("the first token did not work: %d", got.Code)
	}

	second := h.registerDeviceToken(t, deviceUUID)
	if second == first {
		t.Fatal("re-registration returned the same token")
	}

	stale := h.do(t, http.MethodGet, Prefix+"/me/grove", first, nil)
	if stale.Code != http.StatusUnauthorized {
		t.Fatalf("the superseded token still answers %d; two holders would share one installation's "+
			"queue with nothing to say so", stale.Code)
	}
	if got := h.do(t, http.MethodGet, Prefix+"/me/grove", second, nil); got.Code != http.StatusOK {
		t.Fatalf("the new token does not work: %d", got.Code)
	}
}

// ── M2: an idempotent sweep must not withdraw consent ──────────────────────────────────────────

func TestClaimWithoutALicenseFieldLeavesConsentStanding(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	h.registerDeviceToken(t, deviceUUID)
	session := h.signIn(t, nil)

	claim := func(body map[string]any) {
		t.Helper()
		recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", session.AccessToken, body)
		if recorder.Code != http.StatusOK {
			t.Fatalf("claim returned %d: %s", recorder.Code, recorder.Body.String())
		}
	}
	consentOnRecord := func() *string {
		t.Helper()
		var version *string
		if err := h.store.Pool().QueryRow(context.Background(),
			`SELECT license_version FROM users WHERE id = $1`, session.UserID).Scan(&version); err != nil {
			t.Fatal(err)
		}
		return version
	}

	claim(map[string]any{"device_uuid": deviceUUID, "license_version": "odbl-1.0"})
	if got := consentOnRecord(); got == nil || *got != "odbl-1.0" {
		t.Fatalf("consent after the first claim = %v, want odbl-1.0", got)
	}

	// §6.2 has the client re-invoking this after every batch that applied anything — for reasons
	// entirely unrelated to consent.
	claim(map[string]any{"device_uuid": deviceUUID})
	if got := consentOnRecord(); got == nil || *got != "odbl-1.0" {
		t.Fatalf("a claim that said nothing about the licence left consent as %v; an omitted field "+
			"is not a declined consent, and a sweep re-run for other reasons silently withdrew it", got)
	}

	// An explicit null *is* a decision, and is recorded as one.
	claim(map[string]any{"device_uuid": deviceUUID, "license_version": nil})
	if got := consentOnRecord(); got != nil {
		t.Fatalf("an explicit null left consent as %v; a declined consent must be storable", got)
	}
}

// ── M5: the grove's record keys are GroveRecord's ──────────────────────────────────────────────

func TestGroveRecordUsesTheClientsFieldNames(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	for _, kind := range []string{"visit", "observation", "measurement", "care_event"} {
		h.syncOne(t, deviceToken, map[string]any{
			"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree,
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
		})
	}

	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", deviceToken, nil)
	var grove struct {
		Entries []struct {
			TreeUUID    uuid.UUID      `json:"tree_uuid"`
			Record      map[string]int `json:"record"`
			HeroPhotoID *uuid.UUID     `json:"hero_photo_id"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &grove); err != nil {
		t.Fatal(err)
	}
	if len(grove.Entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(grove.Entries))
	}

	record := grove.Entries[0].Record
	// `GroveRecord`'s own field names. Its comment says `checkIns` is "named for the control, not
	// for the `observations` table" — a response spelling it `observations` maps three of four and
	// silently drops check-ins to zero.
	for _, key := range []string{"visits", "checkIns", "measurements", "careEvents"} {
		if record[key] != 1 {
			t.Errorf("record[%q] = %d, want 1 (record = %v)", key, record[key], record)
		}
	}
	if _, found := record["observations"]; found {
		t.Error("the record still carries `observations`, which GroveRecord has no field for")
	}
}

func TestGroveCarriesTheHeroPhoto(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
	})

	begin := h.do(t, http.MethodPost, Prefix+"/photos/begin", session.AccessToken, map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	var ticket beginPhotoResponse
	if err := json.Unmarshal(begin.Body.Bytes(), &ticket); err != nil {
		t.Fatal(err)
	}

	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", session.AccessToken, nil)
	var grove struct {
		Entries []struct {
			HeroPhotoID *uuid.UUID `json:"hero_photo_id"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &grove); err != nil {
		t.Fatal(err)
	}
	if len(grove.Entries) != 1 {
		t.Fatalf("got %d entries", len(grove.Entries))
	}
	if grove.Entries[0].HeroPhotoID == nil || *grove.Entries[0].HeroPhotoID != ticket.PhotoID {
		t.Fatalf("hero_photo_id = %v, want %v — #176's hero is a photo fact the phone cannot answer "+
			"for a photograph it never wrote", grove.Entries[0].HeroPhotoID, ticket.PhotoID)
	}
}

// ── M6: a photograph must arrive, not a key ────────────────────────────────────────────────────

func TestPhotoDataAnswersAFetchableURL(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	begin := h.do(t, http.MethodPost, Prefix+"/photos/begin", session.AccessToken, map[string]any{
		"tree_uuid": uuid.New(), "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	var ticket beginPhotoResponse
	if err := json.Unmarshal(begin.Body.Bytes(), &ticket); err != nil {
		t.Fatal(err)
	}

	reader := h.registerDeviceToken(t, uuid.New())
	recorder := h.do(t, http.MethodGet, Prefix+"/photos/"+ticket.PhotoID.String(), reader, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("photo read returned %d: %s", recorder.Code, recorder.Body.String())
	}
	var body struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.URL == "" {
		t.Fatal("no URL; a storage key alone fetches nothing — uploads are presigned PUTs, so the " +
			"bucket is not anonymously readable")
	}
	parsed, err := url.Parse(body.URL)
	if err != nil {
		t.Fatalf("the URL does not parse: %v", err)
	}
	if parsed.Query().Get("X-Amz-Signature") == "" {
		t.Error("the URL is not presigned; an anonymous GET against the S3 endpoint returns 403")
	}
	if !bytes.Contains(recorder.Body.Bytes(), []byte(ticket.PhotoID.String())) {
		t.Error("the response does not name the photograph it is about")
	}
}

// ── M9: refresh, over the wire ─────────────────────────────────────────────────────────────────

func TestRefreshRotatesAndAReuseKillsTheFamily(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	refresh := func(token string) *httptest.ResponseRecorder {
		return h.do(t, http.MethodPost, Prefix+"/auth/refresh", "",
			map[string]any{"refresh_token": token})
	}

	first := refresh(session.RefreshToken)
	if first.Code != http.StatusOK {
		t.Fatalf("refresh returned %d: %s", first.Code, first.Body.String())
	}
	var rotated sessionResponse
	if err := json.Unmarshal(first.Body.Bytes(), &rotated); err != nil {
		t.Fatal(err)
	}
	if rotated.RefreshToken == session.RefreshToken {
		t.Fatal("the refresh token did not rotate")
	}
	if got := h.do(t, http.MethodGet, Prefix+"/me/grove", rotated.AccessToken, nil); got.Code != http.StatusOK {
		t.Fatalf("the rotated access token does not work: %d", got.Code)
	}

	// The replay. This is the canonical signal that a refresh token leaked.
	replay := refresh(session.RefreshToken)
	if replay.Code != http.StatusUnauthorized {
		t.Fatalf("replaying a spent refresh token returned %d, want 401", replay.Code)
	}

	// And the successor must not survive it: whoever holds it would otherwise keep a 60-day
	// session, and the legitimate holder could not tell.
	after := refresh(rotated.RefreshToken)
	if after.Code == http.StatusOK {
		t.Fatal("after a detected reuse the successor still refreshes; the theft is invisible and " +
			"the thief keeps a 60-day session")
	}
	if got := h.do(t, http.MethodGet, Prefix+"/me/grove", rotated.AccessToken, nil); got.Code != http.StatusUnauthorized {
		t.Fatalf("after a detected reuse the successor's access token still answers %d", got.Code)
	}
}

// ── N4: an access token must not outlive the account ───────────────────────────────────────────

func TestAnAccessTokenDoesNotOutliveTheAccount(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	if got := h.do(t, http.MethodGet, Prefix+"/me/grove", session.AccessToken, nil); got.Code != http.StatusOK {
		t.Fatalf("the session did not work before deletion: %d", got.Code)
	}

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
		map[string]any{"choice": "eraseEverything", "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d", recorder.Code)
	}

	after := h.do(t, http.MethodGet, Prefix+"/me/grove", session.AccessToken, nil)
	if after.Code != http.StatusUnauthorized {
		t.Fatalf("a deleted account's access token still answers %d — an empty grove reads as "+
			"'you have contributed nothing', not as 'this account is gone'", after.Code)
	}
}

// harnessNonce is the raw nonce every harness sign-in presents.
const harnessNonce = "the-harness-nonce"

func sha256Hex(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

// TestEveryRequestCarriesADeadline is N1: the timeout was declared, commented as though it bounded
// a handler, and referenced by nothing.
//
// `go vet` does not flag an unused constant, so nothing else was going to say so — and a constant
// with a comment explaining what it protects reads exactly like a protection.
func TestEveryRequestCarriesADeadline(t *testing.T) {
	var deadline time.Time
	var hadDeadline bool

	handler := withTimeout(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		deadline, hadDeadline = r.Context().Deadline()
	}))
	handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/health", nil))

	if !hadDeadline {
		t.Fatal("the request context carries no deadline; one shared-cpu-1x machine cannot afford " +
			"a query holding a connection open indefinitely, which is what requestTimeout claims to stop")
	}
	if until := time.Until(deadline); until <= 0 || until > requestTimeout+time.Second {
		t.Errorf("the deadline is %v away, want about %v", until, requestTimeout)
	}
}

// ── B7: the placement the client sends is the placement it reads back ──────────────────────────

// TestPlacementRoundTripsAndDefaultsToTheDraftsDefault is the end-to-end half of B7.
//
// `community_trees.placement` was never written by any path, so `NearbyTree.Placement` was always
// `""` and the handler substituted `"unknown"` — not a `TreePlacement`, on every candidate, always.
// Writing it is the fix; reading it back through a *different* route than the one that wrote it is
// what makes the fix visible.
func TestPlacementRoundTripsAndDefaultsToTheDraftsDefault(t *testing.T) {
	for name, submitted := range map[string]any{
		"contributor_placed": "contributor_placed",
		"gps":                "gps",
		"absent":             nil,
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			deviceToken := h.registerDeviceToken(t, uuid.New())

			const lat, lon = 37.7601, -122.5050
			body := map[string]any{
				"client_uuid": uuid.New(), "lat": lat, "lon": lon,
				"address": "1 Main St", "species_id": nil, "land_context": nil,
			}
			if submitted != nil {
				body["placement"] = submitted
			}
			if got := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, body); got.Code != http.StatusOK {
				t.Fatalf("add returned %d: %s", got.Code, got.Body.String())
			}

			// Read it back as a dedupe candidate, which is the only route that surfaces it.
			second := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
				"client_uuid": uuid.New(), "lat": lat + 5.0/111_320.0, "lon": lon,
				"address": nil, "species_id": nil, "land_context": nil,
			})
			if second.Code == http.StatusOK {
				t.Fatal("the second tree did not trip the dedupe")
			}

			var envelope struct {
				Detail struct {
					Candidates []wireNearbyTree `json:"candidates"`
				} `json:"detail"`
			}
			if err := json.Unmarshal(second.Body.Bytes(), &envelope); err != nil {
				t.Fatal(err)
			}
			if len(envelope.Detail.Candidates) != 1 {
				t.Fatalf("got %d candidates", len(envelope.Detail.Candidates))
			}

			want := defaultTreePlacement
			if submitted != nil {
				want = submitted.(string)
			}
			got := envelope.Detail.Candidates[0].Tree.Placement
			if got != want {
				t.Fatalf("placement round-tripped as %q, want %q", got, want)
			}
			declared := swiftEnumRawValues(t, "../../../Cypress/Core/Models/Tree.swift", "TreePlacement")
			if !slices.Contains(declared, got) {
				t.Fatalf("placement %q is not a TreePlacement raw value %v", got, declared)
			}
		})
	}
}

// TestAnInvalidPlacementIsRefused stops the vocabulary being widened from the wire.
func TestAnInvalidPlacementIsRefused(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	recorder := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": 37.7601, "lon": -122.505,
		"address": nil, "placement": "unknown", "species_id": nil, "land_context": nil,
	})
	if recorder.Code == http.StatusOK {
		t.Fatal("`unknown` was accepted as a placement; it is not a TreePlacement raw value and " +
			"Tree.placement is non-optional, so every candidate carrying it fails to decode")
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.ValidationFailed) {
		t.Fatalf("code = %q, want validation_failed", code)
	}
}

// TestTheAddressIsTheClientsAddress is N13.
//
// `Tree.address` is the city's street address. A person-chosen name arriving in it would render as
// an address on the resolution sheet, and `TreeDraft` has no name field to send one from anyway.
func TestTheAddressIsTheClientsAddress(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	const lat, lon = 37.7601, -122.5050

	h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat, "lon": lon,
		"address": "123 Judah St", "species_id": nil, "land_context": "street",
	})
	second := h.do(t, http.MethodPost, Prefix+"/trees", deviceToken, map[string]any{
		"client_uuid": uuid.New(), "lat": lat + 5.0/111_320.0, "lon": lon,
		"address": nil, "species_id": nil, "land_context": nil,
	})

	var envelope struct {
		Detail struct {
			Candidates []wireNearbyTree `json:"candidates"`
		} `json:"detail"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	// Indexed only after checking. A bare `[0]` panics the whole package when an injection makes
	// the list empty, which turns a red-proof's message into a stack trace and takes every other
	// test in the binary down with it.
	if len(envelope.Detail.Candidates) != 1 {
		t.Fatalf("got %d candidates, want 1: %s", len(envelope.Detail.Candidates), second.Body.String())
	}
	candidate := envelope.Detail.Candidates[0]
	if candidate.Tree.Address == nil || *candidate.Tree.Address != "123 Judah St" {
		t.Fatalf("address = %v, want the street address the client sent", candidate.Tree.Address)
	}
	if candidate.Tree.StatedLandContext == nil || *candidate.Tree.StatedLandContext != "street" {
		t.Fatalf("statedLandContext = %v, want street", candidate.Tree.StatedLandContext)
	}
}

// ── N8: the envelope is lenient too ────────────────────────────────────────────────────────────

func TestAnUnknownEnvelopeKeyDoesNotFailTheBatch(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	key := uuid.New()
	recorder := h.do(t, http.MethodPost, Prefix+"/sync", deviceToken, map[string]any{
		"batch_id": "an-additive-top-level-key",
		"items": []any{map[string]any{
			"client_uuid": key, "kind": "visit", "tree_uuid": uuid.New(),
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{}`),
		}},
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an additive envelope key failed the whole batch "+
			"non-retryably, which is the same blast radius the per-item fix was for", recorder.Code)
	}
	var response struct{ Results []syncResult }
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Results) != 1 || response.Results[0].Status != "applied" {
		t.Fatalf("results = %+v, want the item applied", response.Results)
	}
}

// ── N10: a sign-in with no nonce anywhere is refused ───────────────────────────────────────────

func TestASignInWithNoNonceAnywhereIsRefused(t *testing.T) {
	h := newHarness(t)
	h.apple.identity = apple.Identity{Subject: "001234.abcdef.5678", Nonce: ""}

	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", map[string]any{
		"identity_token": "t", "authorization_code": "c", "nonce": "",
		"device_uuid": nil, "license_version": nil,
	})
	if recorder.Code == http.StatusOK {
		t.Fatal("a sign-in with no nonce on either side was accepted; that window depends on the " +
			"client remembering to set one, and this PR is the contract it will be written against")
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.Unauthorized) {
		t.Fatalf("code = %q, want unauthorized", code)
	}
}
