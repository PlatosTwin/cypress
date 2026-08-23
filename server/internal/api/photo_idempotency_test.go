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
// ── What the headline test actually pins, after two rounds of getting this wrong ──────────────
//
// It pins that **a replayed begin succeeds and lands on the row it already made**. It does not pin
// the count of `photos` rows, and the file said it did for two rounds (#116 N8, then N13).
//
// The count cannot be the property here, and the reason is worth keeping: with the unique indexes
// in place a broken dedupe cannot *duplicate*, it can only *refuse* — the second INSERT hits the
// index and returns 500. So under the obvious sabotage the count is 1, which is the right number
// for the wrong reason, and the assertion that speaks is the status check. That is correct
// behaviour for this test and it makes the count redundant, not load-bearing.
//
// The count survives here as a **control**, not as the property: it is what proves the two begins
// landed at all, calibrated first against a case whose answer is known (two different keys must
// make two rows). Where the row count genuinely *is* the property is the two index tests below,
// which insert past the lookup on purpose.

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

	// ── The counter is calibrated before it is believed ───────────────────────────────────────
	//
	// #116's review N13: under the obvious sabotage (lookup disabled, indexes intact) the count
	// *passes* — the surviving unique index turns the duplicate INSERT into a 500, so one row is
	// the right answer for the wrong reason, and the test then fails at the status check instead.
	// A count that cannot distinguish "deduped" from "refused" is not measuring idempotency.
	//
	// So the same instrument is run first against a case whose answer is known: two begins under
	// **different** keys must produce two rows. That is the only thing that separates "the dedupe
	// worked" from "nothing was inserted at all".
	control := uuid.New()
	_, controlA := beginAllowingFailure(t, h, session.AccessToken, control, nil)
	_, controlB := beginAllowingFailure(t, h, session.AccessToken, control, nil)
	if n := photoCount(t, h, control); n != 2 {
		t.Fatalf("control: two keyless begins produced %d rows, want 2 (statuses %d, %d) — begins "+
			"are not landing at all, so a count of 1 below would prove nothing about deduping",
			n, controlA, controlB)
	}

	first, firstCode := beginAllowingFailure(t, h, session.AccessToken, tree, &key)
	second, secondCode := beginAllowingFailure(t, h, session.AccessToken, tree, &key)

	// Both begins must have *succeeded* before a count of 1 means anything: one row because the
	// second was deduped is idempotency; one row because the second was refused is a broken replay
	// wearing the same number. This is the assertion the count leans on, stated before it.
	// **The property.** A replay must *succeed*; declining to duplicate by refusing is not
	// idempotency, and it is what a broken lookup actually does once the indexes are underneath it.
	if firstCode != http.StatusOK || secondCode != http.StatusOK {
		t.Fatalf("begin statuses = %d, %d; want 200 twice — a replayed begin must succeed and land "+
			"on the row it already made, not be refused by the index underneath the lookup",
			firstCode, secondCode)
	}
	// The control, not the property — see the file header. With the indexes in place a broken
	// dedupe refuses rather than duplicates, so this number cannot be what catches that; it is here
	// to show the two begins landed on one row rather than, say, none.
	if n := photoCount(t, h, tree); n != 1 {
		t.Fatalf("control: photos rows = %d, want 1", n)
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

// TestReplayAfterAnOperatorTakedownIsRefused is #116's review N16 — F2's door, reached from the
// operator's side instead of the contributor's.
//
// `RejectPhoto` moves `moderation_state` and deliberately does not set `deleted_at` (the takedown is
// a moderation verdict, not a deletion). The replay lookup only tested `deleted_at`, so a begin
// replayed after a takedown was answered 200 with a fresh presigned PUT and the bytes landed —
// which matters here for the same reason it matters for a withdrawal: nothing in this service
// deletes an object, so bytes written after a takedown stay written.
func TestReplayAfterAnOperatorTakedownIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, key := uuid.New(), uuid.New()

	first := beginWithKey(t, h, session.AccessToken, tree, &key)

	rejected := h.do(t, http.MethodPost,
		Prefix+"/operator/photos/"+first.PhotoID.String()+"/reject", "the-operator-token", nil)
	if rejected.Code != http.StatusOK {
		t.Fatalf("operator reject: status = %d, body = %s", rejected.Code, rejected.Body.String())
	}

	// The control that keeps this test honest: a takedown must NOT have set `deleted_at`, or this
	// would be re-testing F2 rather than the moderation arm.
	var deletedAt *time.Time
	var moderation string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT deleted_at, moderation_state FROM photos WHERE id = $1`, first.PhotoID,
	).Scan(&deletedAt, &moderation); err != nil {
		t.Fatal(err)
	}
	if deletedAt != nil {
		t.Fatal("a takedown now sets deleted_at, so this test is a duplicate of the withdrawal one")
	}
	if moderation != "rejected" {
		t.Fatalf("moderation_state = %q, want rejected", moderation)
	}

	replay, code := beginAllowingFailure(t, h, session.AccessToken, tree, &key)
	if code == http.StatusOK {
		t.Fatalf("the replay was answered 200 with destination %q — bytes would land for a "+
			"photograph an operator took down, and nothing here deletes an object", replay.Destination)
	}
	if code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", code)
	}
}

// TestTheDeviceScopedUniqueIndexRefusesADuplicateKey is #116's review N12.
//
// The pair test above never notices the **device-scoped** index: its first half exercises the
// per-user one and its second half asserts only that a different owner may reuse the key, which
// holds either way. (An earlier version of this comment said that test goes red "only when both
// indexes are dropped" — refuted by the review's own sabotage, which reds it by dropping the
// per-user index alone.) So the device index — the one protecting the anonymous, pre-sign-in
// contributor, the only owner an unclaimed install has — had no coverage of its own.
func TestTheDeviceScopedUniqueIndexRefusesADuplicateKey(t *testing.T) {
	h := newHarness(t)
	device := h.registerDeviceToken(t, uuid.New())
	tree, key := uuid.New(), uuid.New()

	begun := beginWithKey(t, h, device, tree, &key)

	var ownerID *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT device_id FROM photos WHERE id = $1`, begun.PhotoID).Scan(&ownerID); err != nil {
		t.Fatal(err)
	}
	if ownerID == nil {
		t.Fatal("fixture: the photograph is not device-owned, so the per-device index is not under test")
	}

	_, err := h.store.Pool().Exec(context.Background(), `
		INSERT INTO photos (id, tree_uuid, device_id, shot_type, moderation_state,
		                    captured_at, storage_key, client_uuid, created_at, updated_at)
		VALUES ($1, $2, $3, 'full_tree', 'pending', now(), $4, $5, now(), now())
	`, uuid.New(), tree, *ownerID, "photos/"+uuid.New().String()+".jpg", key)
	if err == nil {
		t.Fatal("a second row took the same client_uuid for the same device — " +
			"photos_client_uuid_per_device is not there, and an anonymous contributor's begin " +
			"has no dedupe underneath its lookup")
	}
}

// TestAReplayReportsTheRowsModerationStateNotTheCallers is #116 r3's replay-after-claim finding.
//
// The synthesis line was pre-existing; the replay path that exposes it is what this round ships.
// `ClaimDevice` re-homes a device's photographs onto the account without touching
// `moderation_state`, so the sequence below produced a response saying `approved` about a row that
// still held `pending`. The client evaluates `isPubliclyVisible` from this payload, so the app
// claimed the photograph was publicly visible until the next `treeProfile` read said otherwise.
//
// The assertion compares the response to **the row**, rather than to a literal, so it keeps holding
// if the launch rule's verdict for a fresh begin ever changes.
func TestAReplayReportsTheRowsModerationStateNotTheCallers(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	tree, key := uuid.New(), uuid.New()

	// Begun anonymously: `pending`, visible to its contributor and nobody else (R72 ruling 5).
	begun := beginWithKey(t, h, deviceToken, tree, &key)
	if begun.Moderation != "pending" {
		t.Fatalf("fixture: a device begin reported %q, want pending", begun.Moderation)
	}

	// Sign in *claiming this device*, which re-homes the photograph onto the account.
	session := h.signIn(t, &deviceUUID)

	var stored, storedReason *string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT moderation_state, approval_reason FROM photos WHERE id = $1`, begun.PhotoID,
	).Scan(&stored, &storedReason); err != nil {
		t.Fatal(err)
	}
	if stored == nil {
		t.Fatal("the photograph lost its moderation state")
	}

	replay, code := beginAllowingFailure(t, h, session.AccessToken, tree, &key)
	if code != http.StatusOK {
		t.Fatalf("the replay was refused: status = %d", code)
	}
	if replay.PhotoID != begun.PhotoID {
		t.Fatal("fixture: the claim did not re-home the photograph, so no replay happened")
	}
	if replay.Moderation != *stored {
		t.Fatalf("the replay reported %q while the row holds %q — the client reads "+
			"isPubliclyVisible from this, so it would claim a visibility the service does not have",
			replay.Moderation, *stored)
	}
	wantReason := ""
	if storedReason != nil {
		wantReason = *storedReason
	}
	if replay.ApprovalReason != wantReason {
		t.Fatalf("the replay reported approval_reason %q while the row holds %q",
			replay.ApprovalReason, wantReason)
	}
}
