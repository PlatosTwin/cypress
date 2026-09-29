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

// `photo_withdrawal` naming the id the phone actually holds — the begin's `client_uuid`.
//
// ── The defect ─────────────────────────────────────────────────────────────────────────────────
//
// A phone's withdrawal names its own `photos.id`. This service mints a different one at begin and
// the phone never keeps it, so `withdrawPhoto` matched no row for any photograph a phone had sent,
// answered success, and left the photograph public while screen 17 read "Photo removed". Since
// report F30's fix the phone's id *is* the begin's key, and these tests pin that a withdrawal naming
// the key stops the photograph being served — and that nobody else's key withdraws anything.
//
// Every test runs the real handlers end to end: begin, `POST /sync`, and the three reads.

// beginSigned begins one photograph with a client key and returns the service's id for it.
func beginSigned(t *testing.T, h *harness, bearer string, tree, key uuid.UUID) uuid.UUID {
	t.Helper()
	return beginWithKey(t, h, bearer, tree, &key).PhotoID
}

// onTheProfile reports whether `GET /trees/{id}` lists the photograph for this reader.
func onTheProfile(t *testing.T, h *harness, bearer string, tree, photo uuid.UUID) bool {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /trees/%v returned %d: %s", tree, recorder.Code, recorder.Body.String())
	}
	var body struct {
		Photos []struct {
			PhotoID string `json:"photo_id"`
		} `json:"photos"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, row := range body.Photos {
		if row.PhotoID == photo.String() {
			return true
		}
	}
	return false
}

// publicBodyMentions reports whether the unauthenticated read mentions either id at all. It never
// carries a photograph by ruling (`public.go`), so this is a guard that the withdrawal did not make
// it start, calibrated by the route answering 200 — not a presence check.
func publicBodyMentions(t *testing.T, h *harness, tree uuid.UUID, ids ...uuid.UUID) bool {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/public/trees/"+tree.String(), "", nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /public/trees/%v returned %d — the guard below would be vacuous", tree, recorder.Code)
	}
	for _, id := range ids {
		if strings.Contains(recorder.Body.String(), id.String()) {
			return true
		}
	}
	return false
}

func deletedAt(t *testing.T, h *harness, photo uuid.UUID) *time.Time {
	t.Helper()
	var at *time.Time
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT deleted_at FROM photos WHERE id = $1`, photo).Scan(&at); err != nil {
		t.Fatal(err)
	}
	return at
}

// TestAWithdrawalNamingTheClientKeyStopsThePhotographBeingServed is the defect's own case: a
// signed-in contributor's approved photograph, seen by another device, withdrawn by the id the
// contributor's phone holds.
func TestAWithdrawalNamingTheClientKeyStopsThePhotographBeingServed(t *testing.T) {
	h := newHarness(t)
	owner := h.signIn(t, nil)
	reader := h.registerDeviceToken(t, uuid.New())
	tree, key := uuid.New(), uuid.New()
	photo := beginSigned(t, h, owner.AccessToken, tree, key)

	// The controls: before the withdrawal, every reader that should see it does.
	if !onTheProfile(t, h, reader, tree, photo) || !photoIsServed(t, h, reader, photo) {
		t.Fatal("precondition: another device does not see the photograph before the withdrawal, " +
			"so nothing below could tell a working withdrawal from a broken read")
	}
	if !onTheProfile(t, h, owner.AccessToken, tree, photo) || !photoIsServed(t, h, owner.AccessToken, photo) {
		t.Fatal("precondition: the contributor does not see their own photograph")
	}

	if result := withdraw(t, h, owner.AccessToken, tree, key); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if deletedAt(t, h, photo) == nil {
		t.Fatal("a withdrawal naming the photograph's client key left deleted_at unset — the " +
			"contributor is told \"Photo removed\" and the photograph is still public (F30's " +
			"companion defect)")
	}
	if onTheProfile(t, h, reader, tree, photo) {
		t.Fatal("GET /trees/{id} still lists the withdrawn photograph to another device")
	}
	if photoIsServed(t, h, reader, photo) {
		t.Fatal("GET /photos/{id} still serves the withdrawn photograph to another device")
	}
	if onTheProfile(t, h, owner.AccessToken, tree, photo) || photoIsServed(t, h, owner.AccessToken, photo) {
		t.Fatal("the withdrawn photograph is still served to its own contributor")
	}
	if publicBodyMentions(t, h, tree, photo, key) {
		t.Fatal("the public read mentions the withdrawn photograph")
	}
}

// TestAnAnonymousDevicesWithdrawalByClientKeyApplies is the device arm of the same rule: a pending
// photograph, visible only to the device that took it.
func TestAnAnonymousDevicesWithdrawalByClientKeyApplies(t *testing.T) {
	h := newHarness(t)
	device := h.registerDeviceToken(t, uuid.New())
	tree, key := uuid.New(), uuid.New()
	photo := beginSigned(t, h, device, tree, key)

	if !photoIsServed(t, h, device, photo) {
		t.Fatal("precondition: the device cannot fetch its own photograph")
	}
	if result := withdraw(t, h, device, tree, key); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	if deletedAt(t, h, photo) == nil || photoIsServed(t, h, device, photo) {
		t.Fatal("the device's withdrawal by its own key did not take")
	}
}

// TestAStrangerNamingSomebodyElsesClientKeyChangesNothing: the key finds the row, and the row is
// not the caller's, so the answer is the lookup-by-id's answer — `forbidden` — and nothing moves.
//
// The stranger is a device. A second *account* is not available here: the harness's `signIn` always
// presents the same Apple identity, so a second call is the same account — which a first draft of
// this test used as its "other account" and watched withdraw the photograph, correctly.
func TestAStrangerNamingSomebodyElsesClientKeyChangesNothing(t *testing.T) {
	h := newHarness(t)
	owner := h.signIn(t, nil)
	stranger := h.registerDeviceToken(t, uuid.New())
	tree, key := uuid.New(), uuid.New()
	photo := beginSigned(t, h, owner.AccessToken, tree, key)

	// `Errorf`, not `Fatalf`: the status and the tombstone are separate claims, and a red-proof
	// that only ever reached the first could not show the second guarding anything.
	result := withdraw(t, h, stranger, tree, key)
	if result.Status != "failed" || codeOf(result.Error) != "forbidden" {
		t.Errorf("status = %q, error = %s; want failed/forbidden — a success would report a "+
			"removal that did not happen", result.Status, codeOf(result.Error))
	}
	if deletedAt(t, h, photo) != nil {
		t.Fatal("a stranger's withdrawal tombstoned somebody else's photograph")
	}
	if !photoIsServed(t, h, stranger, photo) || !onTheProfile(t, h, stranger, tree, photo) {
		t.Fatal("a refused withdrawal stopped the photograph being served")
	}
}
