package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// `GET /trees/{id}` and the one id a contributor's phone holds for its own photograph (report F30).
//
// The phone keeps its own `photos.id` and sends it as the begin's `client_uuid`; this service mints
// `photo_id` and the phone never keeps that. So the profile route has to hand the contributor back
// the key, or the phone cannot tell its own photograph from somebody else's and draws it twice. And
// it must hand it to **nobody else** — these tests pin both halves, and the golden file pins the
// bytes the Swift decoder reads (`CypressTests/GoldenWireFixtureTests`).

// The fixed values the golden fixture is built from. Every id is distinct and recognisable, so a
// leak reads as a named value in a failure message rather than as a UUID nobody can place.
var (
	fixtureTree        = uuid.MustParse("5a1e7c0d-0000-4000-8000-00000000f030")
	fixtureCaller      = uuid.MustParse("0a0a0a0a-0000-4000-8000-00000000ca11")
	fixtureStranger    = uuid.MustParse("0b0b0b0b-0000-4000-8000-000000057a9e")
	ownApprovedID      = uuid.MustParse("11111111-0000-4000-8000-0000000000a1")
	ownApprovedKey     = uuid.MustParse("11111111-0000-4000-8000-00000000c1e1")
	ownPendingID       = uuid.MustParse("22222222-0000-4000-8000-0000000000b2")
	strangerApprovedID = uuid.MustParse("33333333-0000-4000-8000-0000000000c3")
	strangerKey        = uuid.MustParse("33333333-0000-4000-8000-00000000c1e3")
	strangerPendingID  = uuid.MustParse("44444444-0000-4000-8000-0000000000d4")
)

// fixtureCommunity is one tree's photographs in every state the route distinguishes: the caller's
// own approved photo with a key, the caller's own pending photo from a begin that carried none, a
// stranger's approved photo that **has** a key (so a leak is possible and therefore detectable), and
// a stranger's pending photo, which nobody but its contributor may see at all.
//
// The two approved rows also carry the phone's `captured_on` (decision 14a), so the one file pins
// where this route's two rules meet: the owner's row is served its exact time **and** its key, the
// stranger's is served noon UTC of its date and **no** key.
func fixtureCommunity() store.TreeCommunity {
	at := time.Date(2026, 9, 24, 19, 12, 5, 481000000, time.UTC)
	day := time.Date(2026, 9, 24, 0, 0, 0, 0, time.UTC)
	key, stranger := ownApprovedKey, strangerKey
	caller, other := fixtureCaller, fixtureStranger
	return store.TreeCommunity{
		VisitCount: 2,
		Photos: []store.PhotoRecord{
			{ID: ownApprovedID, TreeUUID: fixtureTree, UserID: &caller, ShotType: "full_tree",
				ModerationState: "approved", CapturedAt: at, CapturedOn: &day, ClientUUID: &key},
			{ID: ownPendingID, TreeUUID: fixtureTree, UserID: &caller, ShotType: "leaf",
				ModerationState: "pending", CapturedAt: at.Add(-time.Hour)},
			{ID: strangerApprovedID, TreeUUID: fixtureTree, UserID: &other, ShotType: "full_tree",
				ModerationState: "approved", CapturedAt: at.Add(-2 * time.Hour), CapturedOn: &day,
				ClientUUID: &stranger},
			{ID: strangerPendingID, TreeUUID: fixtureTree, UserID: &other, ShotType: "trunk",
				ModerationState: "pending", CapturedAt: at.Add(-3 * time.Hour)},
		},
	}
}

func fixtureBody(t *testing.T) []byte {
	t.Helper()
	caller := fixtureCaller
	encoded, err := json.Marshal(treeProfileBody(fixtureTree, fixtureCommunity(), signedInAs(caller)))
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func signedInAs(user uuid.UUID) caller { return caller{UserID: &user} }

// TestTreeProfileGolden writes `tree_profile.json` from the handler's own body builder, so the file
// the Swift decode test reads is what this service emits — not a transcription of it.
func TestTreeProfileGolden(t *testing.T) {
	compareGolden(t, "tree_profile.json", fixtureBody(t))
}

// TestTreeProfileTellsTheContributorTheirOwnKeyAndNobodyElse is the two-sided rule, on the bytes.
func TestTreeProfileTellsTheContributorTheirOwnKeyAndNobodyElse(t *testing.T) {
	var body struct {
		Photos []map[string]any `json:"photos"`
	}
	if err := json.Unmarshal(fixtureBody(t), &body); err != nil {
		t.Fatal(err)
	}
	rows := map[string]map[string]any{}
	for _, row := range body.Photos {
		rows[row["photo_id"].(string)] = row
	}

	// Calibration: the stranger's approved row is present, so the absence below is the absence of a
	// key on a row that was sent — not the absence of the row.
	stranger, ok := rows[strangerApprovedID.String()]
	if !ok {
		t.Fatalf("the stranger's approved photograph is missing, so nothing below can see a leak: %v", rows)
	}
	if _, pendingLeaked := rows[strangerPendingID.String()]; pendingLeaked {
		t.Fatalf("a stranger's pending photograph was served to somebody else")
	}

	own, ok := rows[ownApprovedID.String()]
	if !ok {
		t.Fatalf("the caller's own approved photograph is missing: %v", rows)
	}
	if got := own["client_uuid"]; got != ownApprovedKey.String() {
		t.Fatalf("the caller's own photograph carries client_uuid %v, want %v — without it the "+
			"phone cannot recognise its own photograph and draws it twice (F30)", got, ownApprovedKey)
	}

	pending, ok := rows[ownPendingID.String()]
	if !ok {
		t.Fatalf("the caller's own pending photograph is missing — it is visible to its contributor")
	}
	if value, present := pending["client_uuid"]; !present || value != nil {
		t.Fatalf("an own row from a keyless begin must carry client_uuid: null, got %v (present %v)",
			value, present)
	}

	if value, present := stranger["client_uuid"]; present {
		t.Fatalf("a stranger's row carries client_uuid %v — another person's key was served", value)
	}
	if bytes.Contains(fixtureBody(t), []byte(strangerKey.String())) {
		t.Fatalf("the stranger's key %v appears somewhere in the body", strangerKey)
	}

	// Decision 14a on the same rows: the owner keeps the exact time the key-and-second link on the
	// phone (`RoutedAPI.refreshedTreeProfile`) matches against; the stranger is served only the day.
	if got := own["captured_at"]; got != "2026-09-24T19:12:05Z" {
		t.Fatalf("the caller's own photograph is served captured_at %v, want its exact time", got)
	}
	if got := stranger["captured_at"]; got != "2026-09-24T12:00:00Z" {
		t.Fatalf("a stranger's photograph is served captured_at %v, want noon UTC of its captured_on", got)
	}
	if got := stranger["captured_on"]; got != "2026-09-24" {
		t.Fatalf("a stranger's photograph is served captured_on %v, want 2026-09-24", got)
	}
}

// TestTheProfileEchoesTheKeyTheBeginCarried is the same rule end to end, against Postgres: the key
// a signed-in contributor's begin carried comes back on their own profile, and a different device
// reading the same tree sees the photograph without it.
func TestTheProfileEchoesTheKeyTheBeginCarried(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()
	ticket := beginWithKey(t, h, session.AccessToken, tree, &key)

	row := func(bearer string) map[string]any {
		t.Helper()
		recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
		if recorder.Code != http.StatusOK {
			t.Fatalf("profile returned %d: %s", recorder.Code, recorder.Body.String())
		}
		var body struct {
			Photos []map[string]any `json:"photos"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		for _, photo := range body.Photos {
			if photo["photo_id"] == ticket.PhotoID.String() {
				return photo
			}
		}
		t.Fatalf("the photograph %v is not on the profile at all: %s", ticket.PhotoID, recorder.Body.String())
		return nil
	}

	if got := row(session.AccessToken)["client_uuid"]; got != key.String() {
		t.Fatalf("the contributor's own profile carries client_uuid %v, want the begin's key %v", got, key)
	}

	stranger := row(h.registerDeviceToken(t, uuid.New()))
	if value, present := stranger["client_uuid"]; present {
		t.Fatalf("another device was served the contributor's key %v", value)
	}
}
