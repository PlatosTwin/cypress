package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The `POST /sync` half of spec §3.4: the nine mutations that used to reach a contributor's phone
// and nothing else.
//
// Every test here posts the **client's own payload shape** — `CommunityMutations.swift` keys, which
// are the Swift property names — rather than a shape written to suit the handler. A test that
// invents its own wire format proves the handler agrees with the test.

// codeOf renders a per-item error code readably.
//
// `syncResult.Error` is a `*apierr.Code`, and `%v` on a pointer prints an address — which is what a
// failing assertion here printed on its first run, so the red said "error = 0x14000123abc, want
// validation_failed" and named neither the code it got nor the defect. A red-proof whose message
// cannot be read is not a red-proof.
func codeOf(code *apierr.Code) string {
	if code == nil {
		return "<none>"
	}
	return string(*code)
}

// communityKinds is the ten values 002 added, with a payload the client would actually send.
//
// Table-driven because the property under test is a property of the *set*: every one of them is
// accepted and recorded. Listing them by hand in ten tests would let the eleventh be added with no
// test, which is exactly how a kind ends up accepted by the CHECK and refused by the map.
func communityKinds(tree, photo, flag uuid.UUID) []struct {
	Kind    string
	Payload string
} {
	return []struct {
		Kind    string
		Payload string
	}{
		{"species_claim", `{"treeID":"` + tree.String() + `","speciesID":"` + uuid.New().String() + `"}`},
		{"species_correction", `{"treeID":"` + tree.String() + `","speciesID":"` + uuid.New().String() + `"}`},
		{"wrong_species_report", `{"treeID":"` + tree.String() + `","flagID":"` + flag.String() + `","kind":"wrong_species"}`},
		{"never_existed_report", `{"treeID":"` + tree.String() + `","flagID":"` + flag.String() + `","kind":"never_existed"}`},
		{"species_review_dismissal", `{"treeID":"` + tree.String() + `","flagID":"` + flag.String() + `"}`},
		{"record_review_dismissal", `{"treeID":"` + tree.String() + `","flagID":"` + flag.String() + `"}`},
		{"photo_vote", `{"treeID":"` + tree.String() + `","photoID":"` + photo.String() + `","vote":1}`},
		{"photo_withdrawal", `{"treeID":"` + tree.String() + `","photoID":"` + photo.String() + `"}`},
		{"hazard_redirect", `{"event":{"treeID":"` + tree.String() + `","category":"hanging_or_broken_limb","shownAt":"2026-08-20T10:00:00Z"}}`},
	}
}

// TestEveryCommunityKindIsAcceptedAndRecorded is the round's headline: before it, each of these
// came back `validation_failed` — "That item's kind is not one this service accepts" — and the
// client's queue could not have held one anyway.
func TestEveryCommunityKindIsAcceptedAndRecorded(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree, photo, flag := uuid.New(), uuid.New(), uuid.New()

	for _, kind := range communityKinds(tree, photo, flag) {
		key := uuid.New()
		result := h.syncOne(t, deviceToken, map[string]any{
			"client_uuid": key, "kind": kind.Kind, "tree_uuid": tree,
			"occurred_at": time.Now().UTC(),
			"payload":     json.RawMessage(kind.Payload),
		})
		if result.Status != "applied" {
			t.Fatalf("%s: status = %q (%s), want applied", kind.Kind, result.Status, codeOf(result.Error))
		}

		var storedKind string
		if err := h.store.Pool().QueryRow(context.Background(),
			`SELECT kind FROM contributions WHERE client_uuid = $1`, key).Scan(&storedKind); err != nil {
			t.Fatalf("%s: the item answered applied and no row is there: %v", kind.Kind, err)
		}
		if storedKind != kind.Kind {
			t.Fatalf("stored kind = %q, want %q", storedKind, kind.Kind)
		}
	}
}

// TestACommunityKindIsDedupedOnItsOwnKey pins that the new kinds inherit the dedupe every older
// kind has. `duplicate` is a success that changes nothing, which is what lets a drain replay a
// batch after a flap without recording a second correction.
func TestACommunityKindIsDedupedOnItsOwnKey(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	key := uuid.New()

	item := map[string]any{
		"client_uuid": key, "kind": "species_claim", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{"treeID":"` + tree.String() + `","speciesID":"` + uuid.New().String() + `"}`),
	}
	if first := h.syncOne(t, deviceToken, item); first.Status != "applied" {
		t.Fatalf("first status = %q, want applied", first.Status)
	}
	if second := h.syncOne(t, deviceToken, item); second.Status != "duplicate" {
		t.Fatalf("second status = %q, want duplicate", second.Status)
	}

	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Fatalf("%d rows for one key; the replay wrote a second correction", rows)
	}
}

// TestAnUnknownKindIsStillRefused is the calibration for the test above.
//
// Without it, "every kind was accepted" is consistent with a handler that accepts *anything* — and
// `syncKinds` is exactly the kind of gate that gets widened to `true` by accident. This is the
// control that says the gate is still a gate.
func TestAnUnknownKindIsStillRefused(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "species_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(), "payload": json.RawMessage(`{"treeID":"` + tree.String() + `"}`),
	})
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed", result.Status)
	}
	if result.Error == nil || *result.Error != apierr.ValidationFailed {
		t.Fatalf("error = %s, want validation_failed", codeOf(result.Error))
	}
}

// ── `add_tree`, the one that materializes ──────────────────────────────────────────────────────

func addTreeItem(tree uuid.UUID, lat, lon float64) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "add_tree", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `",` +
			`"coordinate":{"latitude":` + jsonNumber(lat) + `,"longitude":` + jsonNumber(lon) + `},` +
			`"placement":"gps","address":"1 Alameda"}`),
	}
}

func jsonNumber(value float64) string {
	encoded, _ := json.Marshal(value)
	return string(encoded)
}

// TestAddTreeThroughSyncPutsTheTreeOnTheMap is the difference between recording an act and
// materializing it. A tree recorded only as a contribution is invisible to every read of
// `community_trees`, so nobody else would ever see it.
func TestAddTreeThroughSyncPutsTheTreeOnTheMap(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	result := h.syncOne(t, deviceToken, addTreeItem(tree, 37.3382, -121.8863))
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	var lat, lon float64
	var address *string
	var placement string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT lat, lon, address, placement FROM community_trees WHERE id = $1`, tree,
	).Scan(&lat, &lon, &address, &placement); err != nil {
		t.Fatalf("the item answered applied and there is no tree: %v", err)
	}
	if lat != 37.3382 || lon != -121.8863 {
		t.Fatalf("stored at %v,%v; want the coordinate the payload carried", lat, lon)
	}
	if address == nil || *address != "1 Alameda" {
		t.Fatalf("address = %v, want the one the payload carried", address)
	}
	if placement != "gps" {
		t.Fatalf("placement = %q, want gps", placement)
	}
}

// TestAddTreeKeysTheTreeOnTheClientsTreeId is the two-identity defect, refused.
//
// `TreeAddition` carries `treeID` and the envelope carries `tree_uuid`, and they are the same fact
// said twice. The row must be keyed on it, because every later record — a visit, a photograph, a
// vote — names the tree by that id. A handler that keyed on `client_uuid` instead would give the
// tree an id nothing else in any table means, which `community_trees` in `001_initial.sql` records
// having already cost once.
func TestAddTreeKeysTheTreeOnTheClientsTreeId(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	item := addTreeItem(tree, 37.4, -121.9)
	if result := h.syncOne(t, deviceToken, item); result.Status != "applied" {
		t.Fatalf("status = %q, want applied", result.Status)
	}

	var stored uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT id FROM community_trees WHERE id = $1`, tree).Scan(&stored); err != nil {
		t.Fatalf("no tree under the client's tree id: %v", err)
	}

	// And the item's own key is not a second identity for the tree.
	var underTheKey int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM community_trees WHERE id = $1`, item["client_uuid"]).Scan(&underTheKey); err != nil {
		t.Fatal(err)
	}
	if underTheKey != 0 {
		t.Fatal("the tree is also stored under the item's client_uuid; that is the second identity")
	}
}

// TestAddTreeDisagreeingWithItselfIsRefused: two sources for one fact must agree or the item is
// malformed. Picking one silently is how a tree ends up somewhere nobody put it.
func TestAddTreeDisagreeingWithItselfIsRefused(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree, other := uuid.New(), uuid.New()

	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "add_tree", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"treeID":"` + other.String() + `",` +
			`"coordinate":{"latitude":37.4,"longitude":-121.9},"placement":"gps"}`),
	})
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed", result.Status)
	}
	if result.Error == nil || *result.Error != apierr.ValidationFailed {
		t.Fatalf("error = %s, want validation_failed", codeOf(result.Error))
	}

	for _, id := range []uuid.UUID{tree, other} {
		var rows int
		if err := h.store.Pool().QueryRow(context.Background(),
			`SELECT count(*) FROM community_trees WHERE id = $1`, id).Scan(&rows); err != nil {
			t.Fatal(err)
		}
		if rows != 0 {
			t.Fatal("a refused item still put a tree on the map")
		}
	}
}

// TestAddTreeThroughSyncAcceptsATreeBesideAnother is the owner's ruling of 2026-11-14 on the
// `add_tree` door: a tree two meters from another is a second tree, not a `conflict`.
func TestAddTreeThroughSyncAcceptsATreeBesideAnother(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())

	first := uuid.New()
	if result := h.syncOne(t, deviceToken, addTreeItem(first, 37.3382, -121.8863)); result.Status != "applied" {
		t.Fatalf("the first tree = %q, want applied", result.Status)
	}

	// Two meters away, which the retired 10 m rule refused.
	second := uuid.New()
	result := h.syncOne(t, deviceToken, addTreeItem(second, 37.33822, -121.88631))
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s: %s), want applied — a tree may stand within 10 m of another",
			result.Status, codeOf(result.Error), result.Message)
	}

	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM community_trees WHERE id IN ($1, $2)`, first, second).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 2 {
		t.Fatalf("%d trees recorded, want both", rows)
	}
}

// TestReplayingAnAddTreeIsDuplicateNotAConflictWithItself is a double send on the `add_tree` door:
// the phone sends the item, the response is lost, and the outbox sends the same item (the same
// `client_uuid`) again.
//
// The 10 m proximity dedupe is gone, so distance no longer stops a second copy. The contribution
// dedupe does: the replay answers `duplicate`, and one tree and one contribution exist.
func TestReplayingAnAddTreeIsDuplicateNotAConflictWithItself(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	item := addTreeItem(tree, 37.3382, -121.8863)
	if first := h.syncOne(t, deviceToken, item); first.Status != "applied" {
		t.Fatalf("first status = %q, want applied", first.Status)
	}
	second := h.syncOne(t, deviceToken, item)
	if second.Status != "duplicate" {
		t.Fatalf("status = %q (%s), want duplicate — the replay matched the row it created",
			second.Status, codeOf(second.Error))
	}

	var trees, contributions int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT (SELECT count(*) FROM community_trees),
		       (SELECT count(*) FROM contributions WHERE kind = 'add_tree')
	`).Scan(&trees, &contributions); err != nil {
		t.Fatal(err)
	}
	if trees != 1 || contributions != 1 {
		t.Fatalf("trees = %d, add_tree contributions = %d after one add sent twice; want 1 and 1",
			trees, contributions)
	}
}

// TestASecondAddTreeForTheSameTreeUnderANewKeyMakesNoSecondTree is the other double send on the
// `add_tree` door: the same tree id under a new `client_uuid` (an add queued twice under two keys).
//
// The contribution dedupe cannot see it, because the key is new, so the second item answers
// `applied`: its contribution row is recorded. The tree is not inserted again, because
// `insertCommunityTree` keys on the tree id (`ON CONFLICT (id) DO NOTHING`). With the 10 m rule
// gone, that is the only thing standing between this sequence and a second tree.
func TestASecondAddTreeForTheSameTreeUnderANewKeyMakesNoSecondTree(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	first := addTreeItem(tree, 37.3382, -121.8863)
	if result := h.syncOne(t, deviceToken, first); result.Status != "applied" {
		t.Fatalf("the first add_tree = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	second := addTreeItem(tree, 37.3382, -121.8863)
	if second["client_uuid"] == first["client_uuid"] {
		t.Fatal("fixture: the two items share a key; this test needs two")
	}
	if result := h.syncOne(t, deviceToken, second); result.Status != "applied" {
		t.Fatalf("the second add_tree under a new key = %q (%s), want applied — a new key is a new "+
			"contribution, and the tree insert under it is a no-op", result.Status, codeOf(result.Error))
	}

	var forTree, total int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT count(*) FILTER (WHERE id = $1), count(*) FROM community_trees
	`, tree).Scan(&forTree, &total); err != nil {
		t.Fatal(err)
	}
	if forTree != 1 || total != 1 {
		t.Fatalf("rows for the tree = %d, rows in community_trees = %d after one tree sent under two "+
			"keys; want 1 and 1", forTree, total)
	}
}

// TestAnAddTreeAndItsContributionLandTogether: the two rows are one transaction.
//
// If the contribution could land without the tree, a retry would hit the contribution dedupe,
// answer `duplicate`, and the tree would never be inserted by anything.
func TestAnAddTreeAndItsContributionLandTogether(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	item := addTreeItem(tree, 37.35, -121.87)
	if result := h.syncOne(t, deviceToken, item); result.Status != "applied" {
		t.Fatalf("status = %q, want applied", result.Status)
	}

	var contributions, trees int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT (SELECT count(*) FROM contributions WHERE client_uuid = $1),
		        (SELECT count(*) FROM community_trees WHERE id = $2)`,
		item["client_uuid"], tree).Scan(&contributions, &trees); err != nil {
		t.Fatal(err)
	}
	if contributions != 1 || trees != 1 {
		t.Fatalf("contributions = %d, trees = %d; want one of each", contributions, trees)
	}
}

// TestACommunityKindFromAnAccountIsRecordedAsTheAccounts: the anonymous-vs-signed-in behaviour the
// older kinds have, unchanged for the new ones.
//
// A device credential authorizes items that name a device and no user; an account's own items are
// recorded against the account. Nothing about §3.4's nine changes that gate, which is what makes
// `claimDevice` adopt one written before sign-in exactly as it adopts a favorite.
func TestACommunityKindFromAnAccountIsRecordedAsTheAccounts(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	session := h.signIn(t, &deviceUUID)
	tree := uuid.New()
	key := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": key, "kind": "photo_vote", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"user_id":     session.UserID,
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `","photoID":"` +
			uuid.New().String() + `","vote":-1}`),
	})
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	var userID *uuid.UUID
	var deviceID *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT user_id, device_id FROM contributions WHERE client_uuid = $1`, key,
	).Scan(&userID, &deviceID); err != nil {
		t.Fatal(err)
	}
	if userID == nil || *userID != session.UserID {
		t.Fatalf("user_id = %v, want the signed-in account", userID)
	}
	if deviceID != nil {
		t.Fatalf("device_id = %v; exactly one owner, always", deviceID)
	}
}

// TestACommunityKindFromAnotherAccountIsForbidden: the ownership gate applies to the new kinds too,
// and the code is `forbidden` rather than `unauthorized` (ERRATA E261 §3).
func TestACommunityKindFromAnotherAccountIsForbidden(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	session := h.signIn(t, &deviceUUID)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "never_existed_report", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"user_id":     uuid.New(),
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `","flagID":"` +
			uuid.New().String() + `","kind":"never_existed"}`),
	})
	if result.Status != "failed" {
		t.Fatalf("status = %q, want failed", result.Status)
	}
	if result.Error == nil || *result.Error != apierr.Forbidden {
		t.Fatalf("error = %s, want forbidden", codeOf(result.Error))
	}
}

// TestACommunityKindAfterDeletionIsDuplicateNotResurrection: the tombstone covers the new kinds,
// because it is keyed on `client_uuid` and consulted before the insert for every kind alike.
func TestACommunityKindAfterDeletionIsDuplicateNotResurrection(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	session := h.signIn(t, &deviceUUID)
	tree := uuid.New()
	key := uuid.New()

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken, map[string]any{
		"choice":               "eraseEverything",
		"pending_client_uuids": []any{key},
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d: %s", recorder.Code, recorder.Body.String())
	}

	deviceToken := h.registerDeviceToken(t, uuid.New())
	result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": key, "kind": "photo_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `","photoID":"` +
			uuid.New().String() + `"}`),
	})
	if result.Status != "duplicate" {
		t.Fatalf("status = %q, want duplicate — a tombstoned key must not resurrect an account, "+
			"and must not put a red row on screen 17 either", result.Status)
	}

	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 0 {
		t.Fatal("a tombstoned key wrote a contribution")
	}
}
