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

// beginAllowingFailure is `beginWithKey` without the status check.
//
// **N8 of #116's review.** The headline test used the fatal helper, so the obvious sabotage —
// disabling the idempotency lookup — went red at "status = 500" rather than at the row count the
// file header advertises as the property under test. It detected the regression through the wrong
// assertion, which is the difference between a test that measures a property and one that happens
// to notice. This helper lets the count be the thing that speaks.
func beginAllowingFailure(t *testing.T, h *harness, bearer string, tree uuid.UUID, key *uuid.UUID) (beginPhotoResponse, int) {
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
	var response beginPhotoResponse
	_ = json.Unmarshal(recorder.Body.Bytes(), &response)
	return response, recorder.Code
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

	// Deliberately non-fatal on status: the property is the row count, and a test that dies at the
	// status check reports the wrong thing when the dedupe breaks (N8).
	first, firstCode := beginAllowingFailure(t, h, session.AccessToken, tree, &key)
	second, secondCode := beginAllowingFailure(t, h, session.AccessToken, tree, &key)

	// The count first, because it is the property.
	if n := photoCount(t, h, tree); n != 1 {
		t.Fatalf("photos rows = %d, want 1 — the replay created a second photograph, which is the "+
			"defect migration 003 exists to close (statuses %d, %d)", n, firstCode, secondCode)
	}
	if firstCode != http.StatusOK || secondCode != http.StatusOK {
		t.Fatalf("begin statuses = %d, %d; want 200 twice — a replay must succeed, not merely "+
			"decline to duplicate", firstCode, secondCode)
	}
	if first.PhotoID != second.PhotoID {
		t.Fatalf("photo_id = %v then %v; a replayed begin must land on the row it already made",
			first.PhotoID, second.PhotoID)
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

// TestReplayForAWithdrawnPhotographIsRefused is #116's review F2.
//
// Before the fix the replay lookup had no `deleted_at` filter, so this sequence returned the
// tombstoned row **and a fresh presigned PUT**: a client still holding the upload would write the
// bytes and record a success, after its contributor had deleted the picture. Nothing in this
// service deletes an object, so those bytes would stay written.
//
// Driven entirely through the routes a client uses, because the defect lives in the seam between
// them and a store-level test would have been asserting my own reasoning about that seam.
func TestReplayForAWithdrawnPhotographIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()

	first := beginWithKey(t, h, session.AccessToken, tree, &key)

	deleted := h.do(t, http.MethodDelete, Prefix+"/photos/"+first.PhotoID.String(), session.AccessToken, nil)
	if deleted.Code != http.StatusOK {
		t.Fatalf("DELETE /photos/{id}: status = %d, body = %s", deleted.Code, deleted.Body.String())
	}

	replay, code := beginAllowingFailure(t, h, session.AccessToken, tree, &key)
	if code == http.StatusOK {
		t.Fatalf("the replay was answered 200 with destination %q — a client holding this upload "+
			"would PUT the bytes for a photograph its contributor withdrew, and nothing here "+
			"deletes an object afterwards", replay.Destination)
	}
	if code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", code)
	}

	// And no second photograph was minted in its place: resurrecting one would be the other wrong
	// answer, and the unique index would refuse it anyway.
	if n := photoCount(t, h, tree); n != 1 {
		t.Fatalf("photos rows = %d, want 1", n)
	}
}

// TestTheOwnerScopedUniqueIndexesRefuseADuplicateKey is #116's review N2.
//
// `store.BeginPhoto` calls the two partial unique indexes "the authority" against the race between
// its lookup and its insert, and nothing tested them: deleting both `CREATE UNIQUE INDEX`
// statements left all 145 server tests green.
//
// Asserted through behavior rather than by reading `pg_indexes`, so that renaming an index does not
// fail the test while dropping its *effect* does. The insert bypasses `BeginPhoto` deliberately —
// that method's own lookup would answer first, and then this would be testing the lookup again
// rather than the constraint underneath it.
func TestTheOwnerScopedUniqueIndexesRefuseADuplicateKey(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()

	begun := beginWithKey(t, h, session.AccessToken, tree, &key)

	var ownerID *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT user_id FROM photos WHERE id = $1`, begun.PhotoID).Scan(&ownerID); err != nil {
		t.Fatal(err)
	}
	if ownerID == nil {
		t.Fatal("fixture: the photograph is not account-owned, so the per-user index is not the one under test")
	}

	_, err := h.store.Pool().Exec(context.Background(), `
		INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, approval_reason,
		                    captured_at, storage_key, client_uuid, created_at, updated_at)
		VALUES ($1, $2, $3, 'full_tree', 'approved', 'auto_approved_launch', now(), $4, $5, now(), now())
	`, uuid.New(), tree, *ownerID, "photos/"+uuid.New().String()+".jpg", key)
	if err == nil {
		t.Fatal("a second row took the same client_uuid for the same account — the unique index " +
			"BeginPhoto calls its authority against the lookup/insert race is not there")
	}

	// The other index, and it must not be the same one answering twice: a *different* owner may
	// reuse the key, which is the whole reason the indexes are partial and owner-scoped rather than
	// global (one account's uuid must not be able to refuse another's begin).
	device := h.registerDeviceToken(t, uuid.New())
	if _, code := beginAllowingFailure(t, h, device, tree, &key); code != http.StatusOK {
		t.Fatalf("a second contributor was refused the same client key: status = %d — the indexes "+
			"have stopped being owner-scoped", code)
	}
}
