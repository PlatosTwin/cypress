package api

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// `DELETE /me` reports what it did to each tree the account added (`ROADMAP` 104 and 105), so the
// phone can act on the service's answer instead of its own guess. These tests read the answer the
// handler sends, next to the rows it left, for the three cases the phone gets wrong on its own.

// treesAnswer is the `community_trees` object of `DELETE /me`'s body.
type treesAnswer struct {
	Deleted    []uuid.UUID
	Anonymized []uuid.UUID
}

// deleteMeAnswer deletes the account and returns the body's `community_trees`. It fails the test
// when the key is missing or either list is `null`, because the phone reads a missing key as "an
// older service" and falls back to its own rule.
func deleteMeAnswer(t *testing.T, h *harness, bearer, choice string) treesAnswer {
	t.Helper()
	recorder := h.do(t, http.MethodDelete, Prefix+"/me", bearer,
		map[string]any{"choice": choice, "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("DELETE /me (%s) returned %d: %s", choice, recorder.Code, recorder.Body.String())
	}
	var body struct {
		CommunityTrees *struct {
			Deleted    *[]uuid.UUID `json:"deleted"`
			Anonymized *[]uuid.UUID `json:"anonymized"`
		} `json:"community_trees"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.CommunityTrees == nil || body.CommunityTrees.Deleted == nil || body.CommunityTrees.Anonymized == nil {
		t.Fatalf("DELETE /me (%s) did not report both tree lists: %s", choice, recorder.Body.String())
	}
	return treesAnswer{Deleted: *body.CommunityTrees.Deleted, Anonymized: *body.CommunityTrees.Anonymized}
}

// TestTheLeavingDoorReportsAnUnpublishedTreeDeleted is `ROADMAP` 104. The account declined the
// license, so its tree was never published, and decision 12 deletes it under `leaveRecords` too. The
// answer must name it under `deleted`, because the phone cannot see publication and otherwise keeps
// a pin the service dropped. A second account's published tree is the control: the same door
// reports it under `anonymized`.
func TestTheLeavingDoorReportsAnUnpublishedTreeDeleted(t *testing.T) {
	h := newHarness(t)

	private := signInAs(t, h, "ct.answer.private", nil, nil)
	unpublished := uuid.New()
	mustApply(t, h.syncOne(t, private.AccessToken, addTreeAt(unpublished, ctLat, ctLon, time.Now())), "add")
	if stateOf(t, h, unpublished).Published {
		t.Fatal("fixture: a declined account's tree is published")
	}

	answer := deleteMeAnswer(t, h, private.AccessToken, "leaveRecords")
	if !slices.Equal(answer.Deleted, []uuid.UUID{unpublished}) || len(answer.Anonymized) != 0 {
		t.Fatalf("leaveRecords over an unpublished tree answered %+v; want it under deleted", answer)
	}
	if stateOf(t, h, unpublished).Exists {
		t.Fatal("the answer says deleted, and the tree is still here")
	}

	public := signInAs(t, h, "ct.answer.public", nil, accepted())
	published := uuid.New()
	mustApply(t, h.syncOne(t, public.AccessToken, addTreeAt(published, north(80), ctLon, time.Now())), "add")
	answer = deleteMeAnswer(t, h, public.AccessToken, "leaveRecords")
	if !slices.Equal(answer.Anonymized, []uuid.UUID{published}) || len(answer.Deleted) != 0 {
		t.Fatalf("leaveRecords over a published tree answered %+v; want it under anonymized", answer)
	}
	if state := stateOf(t, h, published); !state.Exists || !state.Anonymized {
		t.Fatalf("the answer says anonymized, and the tree is %+v", state)
	}
}

// TestTheErasingDoorReportsATreeAStrangerBuiltOnKept is `ROADMAP` 105(a). A stranger's visit that
// never reached the adder's phone still keeps the tree (decision 6). The answer must name it under
// `anonymized`, because the phone does not hold that visit and would otherwise delete the tree.
func TestTheErasingDoorReportsATreeAStrangerBuiltOnKept(t *testing.T) {
	h := newHarness(t)
	account := signInAs(t, h, "ct.answer.shared", nil, accepted())
	met, unmet := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(met, ctLat, ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(unmet, north(80), ctLon, time.Now())), "add")
	mustApply(t, h.syncOne(t, h.registerDeviceToken(t, uuid.New()), visitItem(met)), "a stranger's visit")

	answer := deleteMeAnswer(t, h, account.AccessToken, "eraseEverything")

	if !slices.Equal(answer.Anonymized, []uuid.UUID{met}) {
		t.Fatalf("eraseEverything answered %+v; want the tree a stranger visited under anonymized", answer)
	}
	if !slices.Equal(answer.Deleted, []uuid.UUID{unmet}) {
		t.Fatalf("eraseEverything answered %+v; want the tree nobody else met under deleted", answer)
	}
	if state := stateOf(t, h, met); !state.Exists || !state.Anonymized {
		t.Fatalf("the answer says anonymized, and the tree is %+v", state)
	}
	if stateOf(t, h, unmet).Exists {
		t.Fatal("the answer says deleted, and the tree is still here")
	}
}

// TestTheErasingDoorReportsATreeOnlyTheClaimedDeviceVisitedDeleted is `ROADMAP` 105(b). The device
// added the tree and visited it before signing in; the claim made both the account's. The service
// therefore erases the visit and then the tree. The phone can still hold that visit as the
// device's, which its own rule reads as "somebody else", so the answer must name the tree under
// `deleted`.
func TestTheErasingDoorReportsATreeOnlyTheClaimedDeviceVisitedDeleted(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	deviceToken := h.registerDeviceToken(t, device)
	tree := uuid.New()
	mustApply(t, h.syncOne(t, deviceToken, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "signed-out add")
	mustApply(t, h.syncOne(t, deviceToken, visitItem(tree)), "the device's own visit")

	account := signInAs(t, h, "ct.answer.claimed", &device, accepted())

	// The control: after the claim, the visit is the account's and the tree is published.
	var owner *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT user_id FROM contributions WHERE tree_uuid = $1 AND kind = 'visit'
	`, tree).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	if owner == nil || *owner != account.UserID {
		t.Fatalf("fixture: the claim did not move the device's visit onto the account (owner %v)", owner)
	}
	if !stateOf(t, h, tree).Published {
		t.Fatal("fixture: the claimed tree is not published")
	}

	answer := deleteMeAnswer(t, h, account.AccessToken, "eraseEverything")

	if !slices.Equal(answer.Deleted, []uuid.UUID{tree}) || len(answer.Anonymized) != 0 {
		t.Fatalf("eraseEverything answered %+v; want the tree only the claimed device visited under deleted", answer)
	}
	if stateOf(t, h, tree).Exists {
		t.Fatal("the answer says deleted, and the tree is still here")
	}
}

// TestDeleteMeGolden pins `DELETE /me`'s body. The phone's `GoldenWireFixtureTests` decodes the same
// file, so the two halves of the contract cannot drift (server/testdata/README.md).
func TestDeleteMeGolden(t *testing.T) {
	encoded, err := json.Marshal(deletionBody("leaveRecords", store.DeletionReport{
		Contributions:   4,
		Photos:          1,
		Tombstones:      2,
		TreesDeleted:    []uuid.UUID{uuid.MustParse("d1e7e7ed-0104-4c2a-9b6e-000000000104")},
		TreesAnonymized: []uuid.UUID{uuid.MustParse("a0a0a0a0-0105-4c2a-9b6e-000000000105")},
	}))
	if err != nil {
		t.Fatal(err)
	}
	compareGolden(t, "delete_me.json", encoded)
}

// TestDeleteMeSendsEmptyTreeListsAsArrays: an account that added no tree gets `[]`, never `null`.
// The phone tells a current service from an older one by the key, so a `null` here would read as a
// broken answer rather than "nothing to do".
func TestDeleteMeSendsEmptyTreeListsAsArrays(t *testing.T) {
	encoded, err := json.Marshal(deletionBody("eraseEverything", store.DeletionReport{}))
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		CommunityTrees map[string]json.RawMessage `json:"community_trees"`
	}
	if err := json.Unmarshal(encoded, &body); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"deleted", "anonymized"} {
		if got := string(body.CommunityTrees[key]); got != "[]" {
			t.Fatalf("community_trees.%s is %q for an account with no trees; want []: %s", key, got, encoded)
		}
	}
}
