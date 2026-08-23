package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The `photo_withdrawal` half of `POST /sync` — the obligation ERRATA E280 left on the round that
// wires photo upload.
//
// **Every assertion here is about whether the photograph is still served**, not about
// `photos.deleted_at`. That is deliberate and it is the whole point of the entry these tests close:
// the failure E280 describes is the client being told "Photo removed" while `GET /photos/{id}`
// keeps handing the bytes to every other device. A test that read the column would have passed in
// exactly that world, because the column is not the thing that was wrong.

// beginPhotoFor starts one photograph and returns its id, as the client's own flow would.
func beginPhotoFor(t *testing.T, h *harness, bearer string, tree uuid.UUID) uuid.UUID {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", bearer, map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": time.Now().UTC(), "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("photos/begin: status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var ticket beginPhotoResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &ticket); err != nil {
		t.Fatal(err)
	}
	return ticket.PhotoID
}

// photoIsServed answers the only question these tests actually care about.
func photoIsServed(t *testing.T, h *harness, bearer string, id uuid.UUID) bool {
	t.Helper()
	return h.do(t, http.MethodGet, Prefix+"/photos/"+id.String(), bearer, nil).Code == http.StatusOK
}

// withdraw posts one `photo_withdrawal` in the client's own payload shape
// (`CommunityMutations.swift`: keys are the Swift property names).
func withdraw(t *testing.T, h *harness, bearer string, tree, photo uuid.UUID) syncResult {
	t.Helper()
	return h.syncOne(t, bearer, map[string]any{
		"client_uuid": uuid.New(), "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(
			`{"treeID":"` + tree.String() + `","photoID":"` + photo.String() + `"}`),
	})
}

// TestWithdrawalStopsTheServiceServingThePhotograph is the round's headline, and the sentence E280
// asks for: an applied withdrawal means the bytes stop being handed out, not merely that a
// contribution row was filed about them.
func TestWithdrawalStopsTheServiceServingThePhotograph(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()
	photo := beginPhotoFor(t, h, session.AccessToken, tree)

	// The control. Without this the test could pass on a photograph that was never served at all,
	// which is the shape of red-proof this project keeps catching too late.
	if !photoIsServed(t, h, session.AccessToken, photo) {
		t.Fatal("precondition: the photograph is not being served before the withdrawal, so this " +
			"test could not tell a working withdrawal from a broken GET")
	}

	if result := withdraw(t, h, session.AccessToken, tree, photo); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if photoIsServed(t, h, session.AccessToken, photo) {
		t.Fatal("the service is still serving a withdrawn photograph — screen 17 reads " +
			"\"Photo removed\" while every other device can still fetch it (ERRATA E280)")
	}
}

// TestWithdrawalOfSomebodyElsesPhotographIsRefusedAndChangesNothing is the guard on the answer that
// would be easiest to get wrong, because the wrong answer is the *quiet* one.
//
// `DeletePhotoByContributor` collapses "absent" and "not yours" into `ErrNotFound` on purpose, so
// that a refusal cannot confirm the row exists. Reusing that here would have made this case
// indistinguishable from the harmless one below — the item would come back `applied`, screen 17
// would say "Photo removed", and the photograph would still be served. See `store.ErrNotOwned`.
func TestWithdrawalOfSomebodyElsesPhotographIsRefusedAndChangesNothing(t *testing.T) {
	h := newHarness(t)
	owner := h.signIn(t, nil)
	stranger := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	photo := beginPhotoFor(t, h, owner.AccessToken, tree)

	result := withdraw(t, h, stranger, tree, photo)
	if result.Status != "failed" || codeOf(result.Error) != "forbidden" {
		t.Fatalf("status = %q, error = %s; want failed/forbidden — a success here would report a "+
			"removal that did not happen", result.Status, codeOf(result.Error))
	}

	if !photoIsServed(t, h, owner.AccessToken, photo) {
		t.Fatal("a refused withdrawal removed the photograph anyway")
	}
}

// TestWithdrawalOfAPhotographThisServiceNeverHeldIsAppliedAndChangesNothing is the case every
// withdrawal arriving today lands in, because no client send path for binaries exists (ERRATA
// E264). It must be a success: the contributor deleted the photograph on their phone and there is
// nothing here to take back, so failing it would put a red row on screen 17 forever.
func TestWithdrawalOfAPhotographThisServiceNeverHeldIsAppliedAndChangesNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	key := uuid.New()
	unknown := uuid.New()
	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": key, "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(
			`{"treeID":"` + tree.String() + `","photoID":"` + unknown.String() + `"}`),
	})
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	// The record of the act is the point — it is what a later reconciliation would read.
	var stored string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT kind FROM contributions WHERE client_uuid = $1`, key).Scan(&stored); err != nil {
		t.Fatalf("the withdrawal was answered applied but not recorded: %v", err)
	}
}

// TestWithdrawalIsIdempotentAcrossAReplay covers the flap: a drain that does not hear the answer
// sends the item again, and the second pass must not turn into a failure on screen 17.
func TestWithdrawalIsIdempotentAcrossAReplay(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()
	photo := beginPhotoFor(t, h, session.AccessToken, tree)

	key := uuid.New()
	item := map[string]any{
		"client_uuid": key, "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(
			`{"treeID":"` + tree.String() + `","photoID":"` + photo.String() + `"}`),
	}

	if first := h.syncOne(t, session.AccessToken, item); first.Status != "applied" {
		t.Fatalf("first pass: status = %q (%s), want applied", first.Status, codeOf(first.Error))
	}
	second := h.syncOne(t, session.AccessToken, item)
	if second.Status != "duplicate" {
		t.Fatalf("second pass: status = %q (%s), want duplicate", second.Status, codeOf(second.Error))
	}
	if photoIsServed(t, h, session.AccessToken, photo) {
		t.Fatal("the replay resurrected a withdrawn photograph")
	}
}

// TestWithdrawalNamingTheWrongTreeIsRefused mirrors the check `add_tree` makes on its own payload,
// and for the same reason: picking one of two disagreeing ids would file the withdrawal against a
// tree the photograph does not belong to.
func TestWithdrawalNamingTheWrongTreeIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, other := uuid.New(), uuid.New()
	photo := beginPhotoFor(t, h, session.AccessToken, tree)

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(
			`{"treeID":"` + other.String() + `","photoID":"` + photo.String() + `"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
	if !photoIsServed(t, h, session.AccessToken, photo) {
		t.Fatal("a malformed withdrawal removed the photograph anyway")
	}
}

// TestWithdrawalWithNoPhotoIsRefused closes the arm where the payload decodes but names nothing.
// Without it a nil id would reach `withdrawPhoto`, match no row, and come back `applied` — a
// success reported for an item that identified nothing.
func TestWithdrawalWithNoPhotoIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{"treeID":"` + tree.String() + `"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}
