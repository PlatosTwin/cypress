package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/apple"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ── Community trees (migration 007) ────────────────────────────────────────────────────────────
//
// Every assertion that carries a promise to *somebody else* is made as somebody else, through the
// handler: the dedupe is asked by a stranger, the move is attempted by a stranger. The columns are
// read too, because the reads that serve these trees to other people are S2's and do not exist in
// this PR — but a column alone would pass in a world where the column moved and nothing obeyed it.

// San Francisco, where the corpus is. One degree of latitude is ~111.32 km.
const ctLat, ctLon = 37.7601, -122.5050

func north(metres float64) float64 { return ctLat + metres/111_320.0 }

func stamp8601(at time.Time) string { return at.UTC().Format(time.RFC3339) }

// addTreeAt is `TreeAddition` as the client encodes it, at a chosen time.
func addTreeAt(tree uuid.UUID, lat, lon float64, occurredAt time.Time) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "add_tree", "tree_uuid": tree,
		"occurred_at": stamp8601(occurredAt),
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `",` +
			`"coordinate":{"latitude":` + jsonNumber(lat) + `,"longitude":` + jsonNumber(lon) + `},` +
			`"placement":"gps","occurredAt":"` + stamp8601(occurredAt) + `"}`),
	}
}

// correctionItem is `TreeLocationCorrection` as §3A pins it.
func correctionItem(tree, correction uuid.UUID, lat, lon float64, occurredAt time.Time) map[string]any {
	key := uuid.New()
	return map[string]any{
		"client_uuid": key, "kind": "location_correction", "tree_uuid": tree,
		"occurred_at": stamp8601(occurredAt),
		"payload": jsonBody(map[string]any{
			"id": correction, "clientUUID": key, "treeID": tree,
			"coordinate": map[string]any{"latitude": lat, "longitude": lon},
			"placement":  "contributor_placed", "locationAccuracyM": 3.0,
			"occurredAt": stamp8601(occurredAt),
		}),
	}
}

// treeWithdrawalItem is `TreeWithdrawal` as decision 8's kind pins it.
func treeWithdrawalItem(tree uuid.UUID) map[string]any {
	key := uuid.New()
	return map[string]any{
		"client_uuid": key, "kind": "tree_withdrawal", "tree_uuid": tree,
		"occurred_at": stamp8601(time.Now()),
		"payload": jsonBody(map[string]any{
			"clientUUID": key, "treeID": tree, "occurredAt": stamp8601(time.Now()),
		}),
	}
}

func visitItem(tree uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": tree,
		"occurred_at": stamp8601(time.Now()), "payload": json.RawMessage(`{}`),
	}
}

// signInAs signs in as a distinct Apple subject, optionally claiming a device, with a license
// answer: a version string accepts, nil sends the explicit null that records a decline.
func signInAs(t *testing.T, h *harness, subject string, device *uuid.UUID, license *string) sessionResponse {
	t.Helper()
	h.apple.identity = apple.Identity{Subject: subject, Email: subject + "@b.test", Nonce: sha256Hex(harnessNonce)}
	body := map[string]any{
		"identity_token": "an-identity-token", "authorization_code": "an-authorization-code",
		"nonce": harnessNonce, "device_uuid": device, "license_version": license,
	}
	recorder := h.do(t, http.MethodPost, Prefix+"/auth/oidc", "", body)
	if recorder.Code != http.StatusOK {
		t.Fatalf("sign-in as %s returned %d: %s", subject, recorder.Code, recorder.Body.String())
	}
	var session sessionResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	return session
}

func accepted() *string { version := "odbl-1.0"; return &version }

type treeState struct {
	Exists     bool
	Lat, Lon   float64
	Placement  string
	AccuracyM  *float64
	SpeciesID  *uuid.UUID
	UserID     *uuid.UUID
	DeviceID   *uuid.UUID
	Published  bool
	Anonymized bool
	Deleted    bool
}

func stateOf(t *testing.T, h *harness, tree uuid.UUID) treeState {
	t.Helper()
	var s treeState
	err := h.store.Pool().QueryRow(context.Background(), `
		SELECT lat, lon, placement, location_accuracy_m, species_id, user_id, device_id,
		       published_at IS NOT NULL, anonymized_at IS NOT NULL, deleted_at IS NOT NULL
		  FROM community_trees WHERE id = $1
	`, tree).Scan(&s.Lat, &s.Lon, &s.Placement, &s.AccuracyM, &s.SpeciesID, &s.UserID, &s.DeviceID,
		&s.Published, &s.Anonymized, &s.Deleted)
	if errors.Is(err, pgx.ErrNoRows) {
		return s
	}
	if err != nil {
		t.Fatal(err)
	}
	s.Exists = true
	return s
}

type eventRow struct {
	ID          uuid.UUID
	Kind        string
	ClientUUID  *uuid.UUID
	ActorUser   *uuid.UUID
	ActorDevice *uuid.UUID
	OccurredAt  time.Time
	Anonymized  bool
}

func eventsOf(t *testing.T, h *harness, tree uuid.UUID) []eventRow {
	t.Helper()
	rows, err := h.store.Pool().Query(context.Background(), `
		SELECT id, kind, contribution_client_uuid, actor_user_id, actor_device_id, occurred_at,
		       anonymized_at IS NOT NULL
		  FROM community_tree_events WHERE tree_id = $1
		 ORDER BY recorded_at, occurred_at, kind
	`, tree)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var events []eventRow
	for rows.Next() {
		var e eventRow
		if err := rows.Scan(&e.ID, &e.Kind, &e.ClientUUID, &e.ActorUser, &e.ActorDevice,
			&e.OccurredAt, &e.Anonymized); err != nil {
			t.Fatal(err)
		}
		events = append(events, e)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return events
}

func eventsOfKind(events []eventRow, kind string) []eventRow {
	var matched []eventRow
	for _, e := range events {
		if e.Kind == kind {
			matched = append(matched, e)
		}
	}
	return matched
}

func deviceRowID(t *testing.T, h *harness, deviceUUID uuid.UUID) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT id FROM devices WHERE device_uuid = $1`, deviceUUID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func isTombstoned(t *testing.T, h *harness, tree uuid.UUID) bool {
	t.Helper()
	var found bool
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)`, tree).Scan(&found); err != nil {
		t.Fatal(err)
	}
	return found
}

// headOf is the chain's head row id.
func headOf(t *testing.T, h *harness, tree uuid.UUID) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT id FROM community_tree_locations WHERE tree_id = $1 AND superseded_by IS NULL
	`, tree).Scan(&id); err != nil {
		t.Fatalf("reading the head of %s: %v", tree, err)
	}
	return id
}

func supersededBy(t *testing.T, h *harness, row uuid.UUID) *uuid.UUID {
	t.Helper()
	var next *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT superseded_by FROM community_tree_locations WHERE id = $1`, row).Scan(&next); err != nil {
		t.Fatalf("reading chain row %s: %v", row, err)
	}
	return next
}

// postTree is `POST /trees`; it returns the status code and the candidate ids when it conflicts.
func postTree(t *testing.T, h *harness, bearer string, tree uuid.UUID, lat, lon float64) (int, []uuid.UUID) {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/trees", bearer, map[string]any{
		"client_uuid": tree, "lat": lat, "lon": lon,
	})
	var ids []uuid.UUID
	if recorder.Code == http.StatusConflict {
		var body struct {
			Detail struct {
				Candidates []struct {
					Tree struct {
						ID uuid.UUID `json:"id"`
					} `json:"tree"`
				} `json:"candidates"`
			} `json:"detail"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		for _, candidate := range body.Detail.Candidates {
			ids = append(ids, candidate.Tree.ID)
		}
	}
	return recorder.Code, ids
}

func mustApply(t *testing.T, result syncResult, what string) {
	t.Helper()
	if result.Status != "applied" {
		t.Fatalf("%s: status = %q (%s: %s), want applied", what, result.Status, codeOf(result.Error), result.Message)
	}
}

func mustFail(t *testing.T, result syncResult, code apierr.Code, what string) {
	t.Helper()
	if result.Status != "failed" || codeOf(result.Error) != string(code) {
		t.Fatalf("%s: status = %q (%s: %s), want failed/%s", what, result.Status, codeOf(result.Error),
			result.Message, code)
	}
}

// assertPublicationInvariant is migration 007's half-two, the half no CHECK can hold: a published
// tree belongs to an account that has accepted the license, or to nobody (anonymized).
func assertPublicationInvariant(t *testing.T, h *harness) {
	t.Helper()
	var violations int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT count(*) FROM community_trees t LEFT JOIN users u ON u.id = t.user_id
		 WHERE t.published_at IS NOT NULL
		   AND NOT (t.anonymized_at IS NOT NULL
		            OR (t.user_id IS NOT NULL AND u.license_version IS NOT NULL))
	`).Scan(&violations); err != nil {
		t.Fatal(err)
	}
	if violations != 0 {
		t.Fatalf("%d published tree(s) belong to an account that has not accepted the license "+
			"(decision 7) — the invariant 007's header says the code keeps", violations)
	}
}

// ── Publication ────────────────────────────────────────────────────────────────────────────────

// TestASignedInTreeIsPublishedTheMomentItLands is decision 1's first half: "a tree added while
// signed in is visible to everyone … instantly". A stranger's dedupe is the witness.
func TestASignedInTreeIsPublishedTheMomentItLands(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.adder.1", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "signed-in add")

	state := stateOf(t, h, tree)
	if !state.Published {
		t.Fatal("a tree added by an account that accepted the license is not published")
	}
	events := eventsOf(t, h, tree)
	if len(eventsOfKind(events, "added")) != 1 || len(eventsOfKind(events, "published")) != 1 {
		t.Fatalf("events = %+v, want one added and one published", events)
	}

	stranger := h.registerDeviceToken(t, uuid.New())
	code, candidates := postTree(t, h, stranger, uuid.New(), north(3), ctLon)
	if code != http.StatusConflict || len(candidates) != 1 || candidates[0] != tree {
		t.Fatalf("a stranger 3 m away got %d with candidates %v; the published tree should be the one "+
			"candidate everybody sees", code, candidates)
	}
	assertPublicationInvariant(t, h)
}

// TestASignedOutTreeGoesLiveAtSignIn is decision 1's second half: "a tree added signed out stays on
// the adder's phone until they sign in; then it goes live for everyone at once".
func TestASignedOutTreeGoesLiveAtSignIn(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	deviceToken := h.registerDeviceToken(t, device)
	tree := uuid.New()
	mustApply(t, h.syncOne(t, deviceToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "signed-out add")

	if stateOf(t, h, tree).Published {
		t.Fatal("control: a tree added signed out is published before anybody signed in")
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	if code, candidates := postTree(t, h, stranger, uuid.New(), north(40), ctLon); code != http.StatusOK {
		t.Fatalf("fixture: a stranger's unrelated tree 40 m away was refused %d %v", code, candidates)
	}

	account := signInAs(t, h, "ct.adder.2", &device, accepted())

	state := stateOf(t, h, tree)
	if !state.Published || state.UserID == nil || *state.UserID != account.UserID || state.DeviceID != nil {
		t.Fatalf("after sign-in the tree is %+v; want it the account's and published", state)
	}
	published := eventsOfKind(eventsOf(t, h, tree), "published")
	if len(published) != 1 {
		t.Fatalf("%d published events, want 1", len(published))
	}
	if published[0].ActorUser == nil || *published[0].ActorUser != account.UserID ||
		published[0].ActorDevice == nil || *published[0].ActorDevice != deviceRowID(t, h, device) {
		t.Fatalf("the published event names %v / %v; want the account and the claimed device",
			published[0].ActorUser, published[0].ActorDevice)
	}
	code, candidates := postTree(t, h, stranger, uuid.New(), north(3), ctLon)
	if code != http.StatusConflict || len(candidates) != 1 || candidates[0] != tree {
		t.Fatalf("after sign-in a stranger 3 m away got %d %v; the tree should now be visible", code, candidates)
	}
	assertPublicationInvariant(t, h)
}

// TestADeclinedLicenseKeepsTreesOffTheMapUntilItIsAccepted is decision 7, both directions of time:
// neither the claim nor a signed-in add publishes for an account that declined, and a later
// acceptance publishes both.
func TestADeclinedLicenseKeepsTreesOffTheMapUntilItIsAccepted(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	deviceToken := h.registerDeviceToken(t, device)
	claimed, added := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, deviceToken, addTreeAt(claimed, ctLat, ctLon, time.Now())), "signed-out add")

	account := signInAs(t, h, "ct.decliner", &device, nil)
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(added, north(50), ctLon, time.Now())), "signed-in add")

	for name, tree := range map[string]uuid.UUID{"the claimed tree": claimed, "the signed-in tree": added} {
		state := stateOf(t, h, tree)
		if state.Published {
			t.Fatalf("%s is published for an account that declined the license", name)
		}
		if state.UserID == nil || *state.UserID != account.UserID {
			t.Fatalf("%s is not the account's: %+v", name, state)
		}
		if n := len(eventsOfKind(eventsOf(t, h, tree), "published")); n != 0 {
			t.Fatalf("%s has %d published events and was never published", name, n)
		}
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	if code, candidates := postTree(t, h, stranger, uuid.New(), north(3), ctLon); code != http.StatusOK {
		t.Fatalf("a stranger was refused %d over %v — a declined account's tree is visible to the dedupe",
			code, candidates)
	}
	assertPublicationInvariant(t, h)

	recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", account.AccessToken,
		map[string]any{"device_uuid": device, "license_version": "odbl-1.0"})
	if recorder.Code != http.StatusOK {
		t.Fatalf("claim returned %d: %s", recorder.Code, recorder.Body.String())
	}
	for name, tree := range map[string]uuid.UUID{"the claimed tree": claimed, "the signed-in tree": added} {
		if !stateOf(t, h, tree).Published {
			t.Fatalf("%s is still unpublished after the account accepted the license", name)
		}
		if n := len(eventsOfKind(eventsOf(t, h, tree), "published")); n != 1 {
			t.Fatalf("%s has %d published events after acceptance, want 1", name, n)
		}
	}
	assertPublicationInvariant(t, h)
}

// TestDecliningAfterAcceptingTakesTheTreesBackOff is the direction decision 7 does not spell out and
// the invariant does: an account that accepted, published, and then signed in again with the box
// clear no longer holds public trees.
func TestDecliningAfterAcceptingTakesTheTreesBackOff(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.changer", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	if !stateOf(t, h, tree).Published {
		t.Fatal("control: the tree was not published under an accepted license")
	}

	again := signInAs(t, h, "ct.changer", nil, nil)
	if again.UserID != account.UserID {
		t.Fatal("fixture: the second sign-in is a different account")
	}
	if stateOf(t, h, tree).Published {
		t.Fatal("the account declined the license and its tree is still published")
	}
	if n := len(eventsOfKind(eventsOf(t, h, tree), "unpublished")); n != 1 {
		t.Fatalf("%d unpublished events, want 1", n)
	}
	assertPublicationInvariant(t, h)
}

// ── The cross-half fixture (the R79 lesson) ────────────────────────────────────────────────────

// locationCorrectionFixture is `server/testdata/sync_location_correction.json`, the request C1's
// encoder must produce byte-for-byte in structure. Its values are read from the file rather than
// restated, so the file is the one statement of them.
type locationCorrectionFixture struct {
	Items []struct {
		ClientUUID uuid.UUID `json:"client_uuid"`
		TreeUUID   uuid.UUID `json:"tree_uuid"`
		OccurredAt time.Time `json:"occurred_at"`
		DeviceID   uuid.UUID `json:"device_id"`
		Payload    struct {
			ID         uuid.UUID `json:"id"`
			Coordinate struct {
				Latitude  float64 `json:"latitude"`
				Longitude float64 `json:"longitude"`
			} `json:"coordinate"`
			Placement         string  `json:"placement"`
			LocationAccuracyM float64 `json:"locationAccuracyM"`
		} `json:"payload"`
	} `json:"items"`
}

func readLocationCorrectionFixture(t *testing.T) ([]byte, locationCorrectionFixture) {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/sync_location_correction.json")
	if err != nil {
		t.Fatalf("reading the fixture: %v", err)
	}
	var fixture locationCorrectionFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("the fixture is not the shape this test reads: %v", err)
	}
	if len(fixture.Items) != 1 {
		t.Fatalf("the fixture carries %d items, want 1", len(fixture.Items))
	}
	return raw, fixture
}

// postRaw posts exactly these bytes to `POST /sync` — no re-encoding, so what arrives is the file.
func postRaw(t *testing.T, h *harness, bearer string, body []byte) syncResult {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, Prefix+"/sync", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer "+bearer)
	recorder := httptest.NewRecorder()
	h.handler.ServeHTTP(recorder, request)
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

// seedFixtureTree registers the fixture's device and adds the fixture's tree from it, five minutes
// before the correction, so the correction becomes the head.
func seedFixtureTree(t *testing.T, h *harness, fixture locationCorrectionFixture) string {
	t.Helper()
	item := fixture.Items[0]
	token := h.registerDeviceToken(t, item.DeviceID)
	mustApply(t, h.syncOne(t, token, addTreeAt(item.TreeUUID, ctLat, ctLon, item.OccurredAt.Add(-5*time.Minute))),
		"seeding the fixture's tree")
	return token
}

// TestTheLocationCorrectionFixtureMovesThePin posts the fixture's bytes through the real handler
// against Postgres. It is the Go half of the cross-half test; C1's Swift half encodes the same
// values through production code and compares against the same file.
func TestTheLocationCorrectionFixtureMovesThePin(t *testing.T) {
	h := newHarness(t)
	raw, fixture := readLocationCorrectionFixture(t)
	item := fixture.Items[0]
	token := seedFixtureTree(t, h, fixture)

	mustApply(t, postRaw(t, h, token, raw), "the fixture")

	if head := headOf(t, h, item.TreeUUID); head != item.Payload.ID {
		t.Fatalf("the head is %s, want the fixture's correction %s", head, item.Payload.ID)
	}
	if next := supersededBy(t, h, item.TreeUUID); next == nil || *next != item.Payload.ID {
		t.Fatalf("the root (id = the tree's id) is superseded by %v, want the correction", next)
	}
	state := stateOf(t, h, item.TreeUUID)
	if state.Lat != item.Payload.Coordinate.Latitude || state.Lon != item.Payload.Coordinate.Longitude ||
		state.Placement != item.Payload.Placement || state.AccuracyM == nil ||
		*state.AccuracyM != item.Payload.LocationAccuracyM {
		t.Fatalf("the tree's cached position is %+v; want the fixture's", state)
	}

	events := eventsOfKind(eventsOf(t, h, item.TreeUUID), "location_corrected")
	if len(events) != 1 {
		t.Fatalf("%d location_corrected events, want 1", len(events))
	}
	event := events[0]
	if event.ID != item.Payload.ID {
		t.Errorf("event id = %s, want the correction's own id", event.ID)
	}
	if event.ClientUUID == nil || *event.ClientUUID != item.ClientUUID {
		t.Errorf("event names item %v, want %s", event.ClientUUID, item.ClientUUID)
	}
	if event.ActorDevice == nil || *event.ActorDevice != deviceRowID(t, h, item.DeviceID) || event.ActorUser != nil {
		t.Errorf("event actor = %v / %v, want the fixture's device and no account", event.ActorUser, event.ActorDevice)
	}
	if !event.OccurredAt.Equal(item.OccurredAt) {
		t.Errorf("event occurred_at = %s, want the item's %s", event.OccurredAt, item.OccurredAt)
	}
}

// TestTheLocationCorrectionFixtureIsCalibrated is the fixture test's own control: the same bytes
// with the correction's `id` renamed are refused, for the reason a client that drifted would be.
// Without it the test above would pass just as happily against a handler that ignored `id`.
func TestTheLocationCorrectionFixtureIsCalibrated(t *testing.T) {
	h := newHarness(t)
	raw, fixture := readLocationCorrectionFixture(t)
	token := seedFixtureTree(t, h, fixture)

	if n := bytes.Count(raw, []byte(`"id":`)); n != 1 {
		t.Fatalf("the fixture carries %d `\"id\":` keys, want exactly the correction's one", n)
	}
	drifted := bytes.Replace(raw, []byte(`"id":`), []byte(`"correctionID":`), 1)

	result := postRaw(t, h, token, drifted)
	mustFail(t, result, apierr.ValidationFailed, "the fixture with id renamed to correctionID")
	if result.Message != "That item named no correction." {
		t.Fatalf("refused with %q; the refusal should name the missing correction id", result.Message)
	}
	if head := headOf(t, h, fixture.Items[0].TreeUUID); head != fixture.Items[0].TreeUUID {
		t.Fatalf("a refused correction moved the head to %s", head)
	}
}

// ── location_correction ────────────────────────────────────────────────────────────────────────

// TestOnlyTheAdderMovesThePin is decision 5.
func TestOnlyTheAdderMovesThePin(t *testing.T) {
	h := newHarness(t)
	adder := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")

	strangerDevice := h.registerDeviceToken(t, uuid.New())
	strangerAccount := signInAs(t, h, "ct.stranger", nil, accepted())
	for name, bearer := range map[string]string{"a stranger's device": strangerDevice, "a stranger's account": strangerAccount.AccessToken} {
		result := h.syncOne(t, bearer, correctionItem(tree, uuid.New(), north(4), ctLon, time.Now()))
		mustFail(t, result, apierr.Forbidden, name+" moving somebody else's pin")
	}
	if state := stateOf(t, h, tree); state.Lat != ctLat {
		t.Fatalf("a refused move moved the tree to %v", state.Lat)
	}
	if head := headOf(t, h, tree); head != tree {
		t.Fatalf("a refused move wrote a chain row: the head is %s", head)
	}

	// The control: the adder may.
	mustApply(t, h.syncOne(t, adder, correctionItem(tree, uuid.New(), north(4), ctLon, time.Now())), "the adder's move")
}

// TestAMoveOntoAnotherVisibleTreeIsAConflict is §3A's `conflict`, scoped as §3F scopes the dedupe:
// a published tree refuses the move, another device's unpublished tree does not.
func TestAMoveOntoAnotherVisibleTreeIsAConflict(t *testing.T) {
	h := newHarness(t)
	publisher := signInAs(t, h, "ct.publisher", nil, accepted())
	published := uuid.New()
	mustApply(t, h.syncOne(t, publisher.AccessToken, addTreeAt(published, ctLat, ctLon, time.Now())), "published tree")

	hidden := uuid.New()
	mustApply(t, h.syncOne(t, h.registerDeviceToken(t, uuid.New()),
		addTreeAt(hidden, north(100), ctLon, time.Now())), "another device's unpublished tree")

	mover := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, mover, addTreeAt(tree, north(50), ctLon, time.Now().Add(-time.Hour))), "the mover's tree")

	mustFail(t, h.syncOne(t, mover, correctionItem(tree, uuid.New(), north(4), ctLon, time.Now().Add(-30*time.Minute))),
		apierr.Conflict, "a move to 4 m from a published tree")
	if state := stateOf(t, h, tree); state.Lat != north(50) {
		t.Fatalf("a refused move moved the tree to %v", state.Lat)
	}

	mustApply(t, h.syncOne(t, mover, correctionItem(tree, uuid.New(), north(103), ctLon, time.Now())),
		"a move to 3 m from a tree the mover cannot see")
}

// TestALateOlderCorrectionLandsAlreadySuperseded is §3A's ordering: the head is the greatest
// `(occurred_at, id)`, and a correction that arrives after a newer one is spliced in behind it —
// already superseded, the tree's position untouched, and without the dedupe, since nobody will ever
// be shown that position. The late one is aimed 3 m from a published tree to prove the last part.
func TestALateOlderCorrectionLandsAlreadySuperseded(t *testing.T) {
	h := newHarness(t)
	publisher := signInAs(t, h, "ct.neighbour", nil, accepted())
	mustApply(t, h.syncOne(t, publisher.AccessToken, addTreeAt(uuid.New(), north(200), ctLon, time.Now())), "neighbour")

	adder := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	base := time.Date(2026, 9, 28, 12, 0, 0, 0, time.UTC)
	mustApply(t, h.syncOne(t, adder, addTreeAt(tree, ctLat, ctLon, base)), "add")

	newer, older := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, adder, correctionItem(tree, newer, north(20), ctLon, base.Add(2*time.Hour))), "the newer move")
	mustApply(t, h.syncOne(t, adder, correctionItem(tree, older, north(203), ctLon, base.Add(time.Hour))), "the late older move")

	if head := headOf(t, h, tree); head != newer {
		t.Fatalf("the head is %s; want the newer correction %s — a late arrival took over the tree", head, newer)
	}
	if state := stateOf(t, h, tree); state.Lat != north(20) {
		t.Fatalf("the tree sits at %v; want the newer correction's position", state.Lat)
	}
	if next := supersededBy(t, h, tree); next == nil || *next != older {
		t.Fatalf("the root is superseded by %v; want the late correction spliced in after it", next)
	}
	if next := supersededBy(t, h, older); next == nil || *next != newer {
		t.Fatalf("the late correction is superseded by %v; want the newer one", next)
	}
	if n := len(eventsOfKind(eventsOf(t, h, tree), "location_corrected")); n != 2 {
		t.Fatalf("%d location_corrected events, want both corrections recorded", n)
	}
}

// TestAMoveOfATreeThisServiceDoesNotHoldIsNotFound is §3A's `not_found`: never received, and
// withdrawn.
func TestAMoveOfATreeThisServiceDoesNotHoldIsNotFound(t *testing.T) {
	h := newHarness(t)
	adder := h.registerDeviceToken(t, uuid.New())
	mustFail(t, h.syncOne(t, adder, correctionItem(uuid.New(), uuid.New(), ctLat, ctLon, time.Now())),
		apierr.NotFound, "a move of a tree that never arrived")

	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")
	mustApply(t, h.syncOne(t, adder, treeWithdrawalItem(tree)), "withdraw")
	mustFail(t, h.syncOne(t, adder, correctionItem(tree, uuid.New(), north(3), ctLon, time.Now())),
		apierr.NotFound, "a move of a withdrawn tree")
}

// TestTheLocationCorrectionRefusals are the malformed items, each `validation_failed` — none of
// them can be fixed by sending it again.
func TestTheLocationCorrectionRefusals(t *testing.T) {
	h := newHarness(t)
	adder := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")

	valid := func() map[string]any {
		return map[string]any{
			"id": uuid.New(), "clientUUID": uuid.New(), "treeID": tree,
			"coordinate": map[string]any{"latitude": north(5), "longitude": ctLon},
			"placement":  "gps", "locationAccuracyM": 2.0,
		}
	}
	item := func(payload map[string]any) map[string]any {
		return map[string]any{
			"client_uuid": uuid.New(), "kind": "location_correction", "tree_uuid": tree,
			"occurred_at": stamp8601(time.Now()), "payload": jsonBody(payload),
		}
	}
	for _, c := range []struct {
		name   string
		mutate func(map[string]any)
		want   string
	}{
		{"no correction id", func(p map[string]any) { delete(p, "id") }, "That item named no correction."},
		{"another tree", func(p map[string]any) { p["treeID"] = uuid.New() }, "That item disagrees with itself about which tree it moves."},
		{"no coordinate", func(p map[string]any) { delete(p, "coordinate") }, "That item named no location."},
		{"off the map", func(p map[string]any) { p["coordinate"] = map[string]any{"latitude": 91.0, "longitude": 0.0} }, "That location is not on the map."},
		{"no placement", func(p map[string]any) { delete(p, "placement") }, "That placement is not one this service accepts."},
		{"unknown placement", func(p map[string]any) { p["placement"] = "guessed" }, "That placement is not one this service accepts."},
		{"negative accuracy", func(p map[string]any) { p["locationAccuracyM"] = -1.0 }, "That location accuracy is not a distance."},
	} {
		payload := valid()
		c.mutate(payload)
		result := h.syncOne(t, adder, item(payload))
		mustFail(t, result, apierr.ValidationFailed, c.name)
		if result.Message != c.want {
			t.Errorf("%s: refused with %q, want %q", c.name, result.Message, c.want)
		}
	}
	// The control: the valid payload applies, so the refusals above are about their one change.
	mustApply(t, h.syncOne(t, adder, item(valid())), "the valid payload")
}

// ── Species, arm 1 ─────────────────────────────────────────────────────────────────────────────

// TestTheAddersSpeciesActsNameTheTreeAndNobodyElsesDo is §3B: materialized for the adder, recorded
// and `applied` for anybody else — never `forbidden`.
func TestTheAddersSpeciesActsNameTheTreeAndNobodyElsesDo(t *testing.T) {
	h := newHarness(t)
	adder := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")

	species := func(kind string, species uuid.UUID, at time.Time) map[string]any {
		return map[string]any{
			"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree, "occurred_at": stamp8601(at),
			"payload": jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "speciesID": species}),
		}
	}

	stranger := h.registerDeviceToken(t, uuid.New())
	mustApply(t, h.syncOne(t, stranger, species("species_claim", uuid.New(), time.Now().Add(-50*time.Minute))), "a stranger's claim")
	if stateOf(t, h, tree).SpeciesID != nil {
		t.Fatal("a stranger's claim named somebody else's tree")
	}

	first := uuid.New()
	mustApply(t, h.syncOne(t, adder, species("species_claim", first, time.Now().Add(-40*time.Minute))), "the adder's claim")
	if got := stateOf(t, h, tree).SpeciesID; got == nil || *got != first {
		t.Fatalf("after the adder's claim the species is %v, want %s", got, first)
	}

	mustApply(t, h.syncOne(t, stranger, species("species_correction", uuid.New(), time.Now().Add(-30*time.Minute))), "a stranger's correction")
	if got := stateOf(t, h, tree).SpeciesID; got == nil || *got != first {
		t.Fatalf("a stranger's correction moved the species to %v", got)
	}

	second := uuid.New()
	mustApply(t, h.syncOne(t, adder, species("species_correction", second, time.Now().Add(-20*time.Minute))), "the adder's correction")
	mustApply(t, h.syncOne(t, adder, species("species_correction", uuid.New(), time.Now().Add(-35*time.Minute))), "a late older correction")
	if got := stateOf(t, h, tree).SpeciesID; got == nil || *got != second {
		t.Fatalf("the species is %v, want the adder's newest correction %s", got, second)
	}
	events := eventsOf(t, h, tree)
	if len(eventsOfKind(events, "species_named")) != 1 || len(eventsOfKind(events, "species_corrected")) != 1 {
		t.Fatalf("events = %+v, want one species_named and one species_corrected", events)
	}
}

// ── tree_withdrawal ────────────────────────────────────────────────────────────────────────────

// TestTheAdderWithdrawsATreeNobodyElseBuiltOn is decision 8's permitted case. The adder's own visit
// does not count as somebody else's work.
func TestTheAdderWithdrawsATreeNobodyElseBuiltOn(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.withdrawer", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, adder.AccessToken, visitItem(tree)), "the adder's own visit")

	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(tree)), "the withdrawal")

	if state := stateOf(t, h, tree); !state.Deleted {
		t.Fatalf("the withdrawn tree is %+v; want it deleted", state)
	}
	if n := len(eventsOfKind(eventsOf(t, h, tree), "withdrawn")); n != 1 {
		t.Fatalf("%d withdrawn events, want 1", n)
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	if code, candidates := postTree(t, h, stranger, uuid.New(), north(2), ctLon); code != http.StatusOK {
		t.Fatalf("a withdrawn tree still refuses a stranger's add: %d %v", code, candidates)
	}
	// A replay of the withdrawal under a new key is a success that changes nothing.
	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(tree)), "a second withdrawal")
}

// TestAWithdrawalAfterSomebodyElseBuiltOnItIsAConflict is decision 8's refusal: another identity's
// live visit, or live photograph, keeps the tree up.
func TestAWithdrawalAfterSomebodyElseBuiltOnItIsAConflict(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.built.on", nil, accepted())
	stranger := h.registerDeviceToken(t, uuid.New())

	visited, photographed := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(visited, ctLat, ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(photographed, north(50), ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, stranger, visitItem(visited)), "a stranger's visit")
	beginPhotoFor(t, h, stranger, photographed)

	for name, tree := range map[string]uuid.UUID{"a visit": visited, "a photograph": photographed} {
		result := h.syncOne(t, adder.AccessToken, treeWithdrawalItem(tree))
		mustFail(t, result, apierr.Conflict, "withdrawing a tree a stranger left "+name+" on")
		if state := stateOf(t, h, tree); state.Deleted || !state.Published {
			t.Fatalf("a refused withdrawal changed the tree: %+v", state)
		}
	}
}

// TestOnlyTheAdderWithdraws is decision 8's "the adder may".
func TestOnlyTheAdderWithdraws(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.only.adder", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")

	mustFail(t, h.syncOne(t, h.registerDeviceToken(t, uuid.New()), treeWithdrawalItem(tree)),
		apierr.Forbidden, "a stranger withdrawing somebody else's tree")
	if stateOf(t, h, tree).Deleted {
		t.Fatal("a stranger's refused withdrawal took the tree down")
	}
}

// TestAWithdrawalThatArrivesBeforeItsTreeIsHonoured is the arrival-order hole: the withdrawal
// drains first (the add was in backoff), answers `applied` because there is nothing here yet, and
// the add must then arrive withdrawn rather than publish a tree its adder already took back.
func TestAWithdrawalThatArrivesBeforeItsTreeIsHonoured(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.early.withdrawal", nil, accepted())
	tree := uuid.New()

	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(tree)), "the early withdrawal")
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "the late add")

	if state := stateOf(t, h, tree); !state.Deleted {
		t.Fatalf("the add arrived after its own withdrawal and the tree is %+v; want it withdrawn", state)
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	if code, _ := postTree(t, h, stranger, uuid.New(), north(2), ctLon); code != http.StatusOK {
		t.Fatalf("a tree withdrawn before it arrived refuses a stranger's add: %d", code)
	}
}

// ── The two deletion doors ─────────────────────────────────────────────────────────────────────

func deleteMe(t *testing.T, h *harness, bearer, choice string) {
	t.Helper()
	recorder := h.do(t, http.MethodDelete, Prefix+"/me", bearer,
		map[string]any{"choice": choice, "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("DELETE /me (%s) returned %d: %s", choice, recorder.Code, recorder.Body.String())
	}
}

// actorRowsNaming counts chain rows and events that still name an account or a device.
func actorRowsNaming(t *testing.T, h *harness, user, device uuid.UUID) int {
	t.Helper()
	var n int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT (SELECT count(*) FROM community_tree_locations WHERE actor_user_id = $1 OR actor_device_id = $2)
		     + (SELECT count(*) FROM community_tree_events    WHERE actor_user_id = $1 OR actor_device_id = $2)
	`, user, device).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// TestLeaveRecordsAnonymizesAPublishedTreeAndNamesNobody is §2's `leaveRecords`: the tree stays up
// with nobody's name on it — including the device the account claimed, whose signed-out add is on
// the chain as that device — and nobody may move or withdraw it afterwards.
func TestLeaveRecordsAnonymizesAPublishedTreeAndNamesNobody(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	deviceToken := h.registerDeviceToken(t, device)
	signedOut, signedIn := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, deviceToken, addTreeAt(signedOut, ctLat, ctLon, time.Now().Add(-time.Hour))), "signed-out add")

	account := signInAs(t, h, "ct.leaver", &device, accepted())
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(signedIn, north(50), ctLon, time.Now().Add(-time.Hour))), "signed-in add")
	mustApply(t, h.syncOne(t, account.AccessToken, correctionItem(signedIn, uuid.New(), north(55), ctLon, time.Now())), "a move")
	deviceRow := deviceRowID(t, h, device)
	if actorRowsNaming(t, h, account.UserID, deviceRow) == 0 {
		t.Fatal("control: nothing names the account or its device before the deletion")
	}

	deleteMe(t, h, account.AccessToken, "leaveRecords")

	for name, tree := range map[string]uuid.UUID{"the signed-out tree": signedOut, "the signed-in tree": signedIn} {
		state := stateOf(t, h, tree)
		if !state.Exists || !state.Published || !state.Anonymized || state.UserID != nil || state.DeviceID != nil {
			t.Fatalf("%s after leaveRecords is %+v; want it standing, published and nobody's", name, state)
		}
	}
	if n := actorRowsNaming(t, h, account.UserID, deviceRow); n != 0 {
		t.Fatalf("%d chain rows or events still name the deleted account or the device it claimed", n)
	}

	// The device token outlives the account; the device is still not the adder.
	mustFail(t, h.syncOne(t, deviceToken, correctionItem(signedOut, uuid.New(), north(3), ctLon, time.Now())),
		apierr.Forbidden, "moving an anonymized tree")
	mustFail(t, h.syncOne(t, deviceToken, treeWithdrawalItem(signedOut)),
		apierr.Forbidden, "withdrawing an anonymized tree")
	assertPublicationInvariant(t, h)
}

// TestLeaveRecordsDeletesATreeNobodyElseCouldEverSee: an unpublished tree (its account declined the
// license) would, anonymized, be a row no account could ever publish, move, withdraw or erase.
func TestLeaveRecordsDeletesATreeNobodyElseCouldEverSee(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.private.leaver", nil, nil)
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")

	deleteMe(t, h, account.AccessToken, "leaveRecords")

	if stateOf(t, h, tree).Exists || !isTombstoned(t, h, tree) {
		t.Fatal("an unpublished tree survived its account's deletion, or left no tombstone")
	}
}

// TestEraseEverythingDeletesATreeNobodyElseBuiltOn is decision 6's second arm: deleted everywhere,
// tombstoned, and a late add naming it does not bring it back.
func TestEraseEverythingDeletesATreeNobodyElseBuiltOn(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.eraser", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")

	deleteMe(t, h, account.AccessToken, "eraseEverything")

	if stateOf(t, h, tree).Exists {
		t.Fatal("eraseEverything left a tree nobody else had built on")
	}
	if !isTombstoned(t, h, tree) {
		t.Fatal("the erased tree has no tombstone, so no cache can learn it is gone")
	}
	var chain int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT (SELECT count(*) FROM community_tree_locations WHERE tree_id = $1)
		     + (SELECT count(*) FROM community_tree_events WHERE tree_id = $1)
	`, tree).Scan(&chain); err != nil {
		t.Fatal(err)
	}
	if chain != 0 {
		t.Fatalf("%d chain rows or events outlived the erased tree", chain)
	}

	late := h.registerDeviceToken(t, uuid.New())
	h.syncOne(t, late, addTreeAt(tree, ctLat, ctLon, time.Now()))
	if code, _ := postTree(t, h, late, tree, ctLat, ctLon); code != http.StatusOK {
		t.Fatalf("POST /trees naming the erased id answered %d", code)
	}
	if stateOf(t, h, tree).Exists {
		t.Fatal("a late add naming an erased tree brought it back")
	}
}

// TestEraseEverythingKeepsATreeOthersBuiltOnAnonymized is decision 6's first arm.
func TestEraseEverythingKeepsATreeOthersBuiltOnAnonymized(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.eraser.shared", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, h.registerDeviceToken(t, uuid.New()), visitItem(tree)), "a stranger's visit")

	deleteMe(t, h, account.AccessToken, "eraseEverything")

	state := stateOf(t, h, tree)
	if !state.Exists || !state.Anonymized || !state.Published || state.UserID != nil {
		t.Fatalf("a tree somebody else visited is %+v after eraseEverything; want it standing, "+
			"published and nobody's", state)
	}
	if isTombstoned(t, h, tree) {
		t.Fatal("a tree that stayed up was tombstoned")
	}
	assertPublicationInvariant(t, h)
}

// ── The dedupe's scope (§3F) ───────────────────────────────────────────────────────────────────

// TestTheDedupeNoLongerSeesAnotherDevicesUnpublishedTree closes the candidate leak and the refusal
// against a tree nobody could see — through both doors, `POST /trees` and `add_tree`.
func TestTheDedupeNoLongerSeesAnotherDevicesUnpublishedTree(t *testing.T) {
	h := newHarness(t)
	owner := h.registerDeviceToken(t, uuid.New())
	hidden := uuid.New()
	mustApply(t, h.syncOne(t, owner, addTreeAt(hidden, ctLat, ctLon, time.Now())), "the unpublished tree")

	// Its owner still sees it: the control that the query is scoping, not simply blind.
	code, candidates := postTree(t, h, owner, uuid.New(), north(3), ctLon)
	if code != http.StatusConflict || len(candidates) != 1 || candidates[0] != hidden {
		t.Fatalf("the tree's own device got %d %v at 3 m; it should see its own tree", code, candidates)
	}

	stranger := h.registerDeviceToken(t, uuid.New())
	code, candidates = postTree(t, h, stranger, uuid.New(), north(3), ctLon)
	if code != http.StatusOK {
		t.Fatalf("POST /trees 3 m from another device's unpublished tree answered %d with candidates %v "+
			"— its position leaked to a stranger", code, candidates)
	}
	mustApply(t, h.syncOne(t, h.registerDeviceToken(t, uuid.New()), addTreeAt(uuid.New(), north(-3), ctLon, time.Now())),
		"add_tree 3 m from another device's unpublished tree")
}

// ── The operator takedown ──────────────────────────────────────────────────────────────────────

// TestCommunityTreeTakedownNeedsTheOperator mirrors `TestTakedownRequiresTheOperatorCredential`: the
// route is behind `Server.operator`, and nothing but the operator token passes.
func TestCommunityTreeTakedownNeedsTheOperator(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.taken.down", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	path := Prefix + "/operator/community-trees/" + tree.String() + "/take-down"

	for name, bearer := range map[string]string{
		"no credential":         "",
		"a wrong token":         "not-the-operator-token",
		"the adder's session":   account.AccessToken,
		"a device's credential": h.registerDeviceToken(t, uuid.New()),
	} {
		recorder := h.do(t, http.MethodPost, path, bearer, nil)
		if recorder.Code != http.StatusForbidden {
			t.Fatalf("%s: takedown answered %d, want 403", name, recorder.Code)
		}
		if decodeEnvelope(t, recorder).Error.Code != string(apierr.Forbidden) {
			t.Fatalf("%s: the refusal is not `forbidden`", name)
		}
	}
	if stateOf(t, h, tree).Deleted {
		t.Fatal("a refused takedown took the tree down")
	}

	for attempt := 1; attempt <= 2; attempt++ {
		if recorder := h.do(t, http.MethodPost, path, "the-operator-token", nil); recorder.Code != http.StatusOK {
			t.Fatalf("operator takedown %d answered %d: %s", attempt, recorder.Code, recorder.Body.String())
		}
	}
	if !stateOf(t, h, tree).Deleted {
		t.Fatal("the operator's takedown left the tree up")
	}
	if n := len(eventsOfKind(eventsOf(t, h, tree), "taken_down")); n != 1 {
		t.Fatalf("%d taken_down events after two takedowns, want 1", n)
	}
	if recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+uuid.New().String()+"/take-down",
		"the-operator-token", nil); recorder.Code != http.StatusNotFound {
		t.Fatalf("taking down an id that names nothing answered %d, want 404", recorder.Code)
	}
}

// ── The session's device ───────────────────────────────────────────────────────────────────────

// TestASignedInActIsRecordedAgainstTheSessionsDevice is the orchestrator's ruling: the session
// binds the device at `/auth/oidc`, a refresh carries it, and the audit log records it — not the
// device an item claims to come from.
func TestASignedInActIsRecordedAgainstTheSessionsDevice(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	h.registerDeviceToken(t, device)
	session := signInAs(t, h, "ct.session.device", &device, accepted())

	refreshed := h.do(t, http.MethodPost, Prefix+"/auth/refresh", "", map[string]any{"refresh_token": session.RefreshToken})
	if refreshed.Code != http.StatusOK {
		t.Fatalf("refresh returned %d", refreshed.Code)
	}
	var rotated sessionResponse
	if err := json.Unmarshal(refreshed.Body.Bytes(), &rotated); err != nil {
		t.Fatal(err)
	}

	tree := uuid.New()
	item := addTreeAt(tree, ctLat, ctLon, time.Now())
	item["device_id"] = uuid.New() // an unverified claim about some other phone
	mustApply(t, h.syncOne(t, rotated.AccessToken, item), "a signed-in add after a refresh")

	added := eventsOfKind(eventsOf(t, h, tree), "added")
	if len(added) != 1 {
		t.Fatalf("%d added events, want 1", len(added))
	}
	want := deviceRowID(t, h, device)
	if added[0].ActorDevice == nil || *added[0].ActorDevice != want {
		t.Fatalf("the added event names device %v; want the one the session was bound to at sign-in (%s)",
			added[0].ActorDevice, want)
	}
	if added[0].ActorUser == nil || *added[0].ActorUser != session.UserID {
		t.Fatalf("the added event names account %v, want %s", added[0].ActorUser, session.UserID)
	}
}

// ── The invariant no CHECK can hold ────────────────────────────────────────────────────────────

// TestNoPublishedTreeBelongsToAnAccountThatDeclined walks every path that moves either side of the
// invariant — a signed-out add, a claim, a signed-in add, acceptance, decline, a re-acceptance, a
// deletion — and checks the whole table after each.
func TestNoPublishedTreeBelongsToAnAccountThatDeclined(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	deviceToken := h.registerDeviceToken(t, device)
	mustApply(t, h.syncOne(t, deviceToken, addTreeAt(uuid.New(), ctLat, ctLon, time.Now())), "signed-out add")
	assertPublicationInvariant(t, h)

	account := signInAs(t, h, "ct.invariant", &device, nil)
	assertPublicationInvariant(t, h)
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(uuid.New(), north(50), ctLon, time.Now())), "declined add")
	assertPublicationInvariant(t, h)

	for i, license := range []*string{accepted(), nil, accepted(), nil} {
		signInAs(t, h, "ct.invariant", &device, license)
		assertPublicationInvariant(t, h)
		mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(uuid.New(), north(100+50*float64(i)), ctLon, time.Now())), "add")
		assertPublicationInvariant(t, h)
	}

	// The control: the walk ended on a decline, so trees are unpublished and none is published. A
	// walk that published nothing, or unpublished nothing, would have held the invariant vacuously.
	var published, unpublished int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT count(*) FILTER (WHERE published_at IS NOT NULL), count(*) FILTER (WHERE published_at IS NULL)
		  FROM community_trees
	`).Scan(&published, &unpublished); err != nil {
		t.Fatal(err)
	}
	if published != 0 || unpublished != 6 {
		t.Fatalf("after the walk %d trees are published and %d unpublished; want 0 and 6", published, unpublished)
	}
	var republished int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM community_tree_events WHERE kind = 'unpublished'`).Scan(&republished); err != nil {
		t.Fatal(err)
	}
	if republished == 0 {
		t.Fatal("control: nothing was ever unpublished, so the decline path was never exercised")
	}

	deleteMe(t, h, account.AccessToken, "leaveRecords")
	assertPublicationInvariant(t, h)
}
