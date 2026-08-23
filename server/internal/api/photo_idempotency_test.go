package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// `POST /photos/begin` idempotency — migration 003, and the blocker ERRATA E264 names against a
// photo send path.
//
// The property under test is **the count of `photos` rows**, not the shape of the response. A begin
// that answered correctly twice while creating two photographs would have satisfied any assertion
// about its own JSON, and that is exactly the defect: the client cannot see the duplicate, the
// contributor sees the picture twice on the tree, and nothing on either row says they are the same
// one.

func beginWithKey(t *testing.T, h *harness, bearer string, tree uuid.UUID, key *uuid.UUID) beginPhotoResponse {
	t.Helper()
	body := map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	}
	if key != nil {
		body["client_uuid"] = *key
	}
	recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", bearer, body)
	if recorder.Code != http.StatusOK {
		t.Fatalf("photos/begin: status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var response beginPhotoResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func photoCount(t *testing.T, h *harness, tree uuid.UUID) int {
	t.Helper()
	var n int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT COUNT(*) FROM photos WHERE tree_uuid = $1`, tree).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// TestBeginWithTheSameKeyMakesOnePhotograph is the headline: the retry a flap forces is safe.
func TestBeginWithTheSameKeyMakesOnePhotograph(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()

	first := beginWithKey(t, h, session.AccessToken, tree, &key)
	second := beginWithKey(t, h, session.AccessToken, tree, &key)

	if first.PhotoID != second.PhotoID {
		t.Fatalf("photo_id = %v then %v; a replayed begin must land on the row it already made",
			first.PhotoID, second.PhotoID)
	}
	if n := photoCount(t, h, tree); n != 1 {
		t.Fatalf("photos rows = %d, want 1 — the replay created a second photograph, which is the "+
			"defect migration 003 exists to close", n)
	}
}

// TestReplayedBeginPresignsTheRowsOwnKey guards the ordering bug the handler comment describes: a
// presign minted against the *new* id would hand the client a URL for an object no row names, and
// the photograph would be collected after 72 h as never arrived.
//
// The storage key is the photo id, so a destination that does not mention the returned `photo_id` is
// signing something else.
func TestReplayedBeginPresignsTheRowsOwnKey(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()

	first := beginWithKey(t, h, session.AccessToken, tree, &key)
	second := beginWithKey(t, h, session.AccessToken, tree, &key)

	var storedKey string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT storage_key FROM photos WHERE id = $1`, first.PhotoID).Scan(&storedKey); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(second.Destination, storedKey) {
		t.Fatalf("the replay's destination %q does not sign the row's own storage key %q — the "+
			"bytes would land where nothing reads them", second.Destination, storedKey)
	}
}

// TestBeginWithoutAKeyIsUnchanged is the compatibility arm. A build that predates the send path
// sends no key; it must still be able to begin an upload, and it gets the old non-idempotent
// behaviour rather than an error.
func TestBeginWithoutAKeyIsUnchanged(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	first := beginWithKey(t, h, session.AccessToken, tree, nil)
	second := beginWithKey(t, h, session.AccessToken, tree, nil)

	if first.PhotoID == second.PhotoID {
		t.Fatal("two keyless begins returned one id; without a key there is nothing to dedupe on " +
			"and inventing one would silently merge two different photographs")
	}
	if n := photoCount(t, h, tree); n != 2 {
		t.Fatalf("photos rows = %d, want 2", n)
	}
}

// TestOneAccountsKeyDoesNotCollideWithAnothers is why the two unique indexes are partial and scoped
// to the owner rather than global. A global key would let one account's begin be refused by a row it
// cannot see — somebody else's uuid becoming a denial of service against a photograph, and a leak
// that the key exists.
func TestOneAccountsKeyDoesNotCollideWithAnothers(t *testing.T) {
	h := newHarness(t)
	mine := h.signIn(t, nil)
	theirs := h.registerDeviceToken(t, uuid.New())
	tree, key := uuid.New(), uuid.New()

	first := beginWithKey(t, h, mine.AccessToken, tree, &key)
	second := beginWithKey(t, h, theirs, tree, &key)

	if first.PhotoID == second.PhotoID {
		t.Fatal("two contributors sharing a client key were given one photograph")
	}
	if n := photoCount(t, h, tree); n != 2 {
		t.Fatalf("photos rows = %d, want 2 — each contributor's key is their own", n)
	}
}
