package api

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The owner's 2026-09-28 ruling, measured at the two reads it names: a report that a city tree's
// record is wrong (`data_dispute`) must not enroll that tree in the reporter's map "Yours" filter
// or their Grove, and taking the report back (`data_dispute_withdrawal`) must not leave it there
// either. Before `store.TreeMembershipKinds` (`internal/store/reads.go`), both reads filtered only
// `kind <> 'private_reminder'`, so a dispute enrolled its tree the moment it synced — the defect
// `data_dispute_test.go`'s header used to record rather than assert against. This file is what
// closes that gap: it asks `GET /me/grove` and `GET /me/map-membership?kind=yours` directly, the
// same discipline `measurement_withdrawal_test.go` states for the reason it states it — the tally
// and the membership set are what a person sees, not a row's `deleted_at`.
//
// A visit is the control throughout, because a dispute alone answering "not enrolled" would also be
// the answer if these reads were broken in the other direction — refusing everybody. Every test
// here that expects "not enrolled" also proves a visit, on the same tree, would have enrolled it.

// visitItem is one `visit`, the plainest kind that has always counted as meeting a tree.
func visitItem(tree uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{}`),
	}
}

// yoursIDs reads `GET /me/map-membership?kind=yours` back as a set.
func yoursIDs(t *testing.T, h *harness, bearer string) map[uuid.UUID]bool {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/map-membership?kind=yours", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/map-membership?kind=yours: status = %d, body = %s",
			recorder.Code, recorder.Body.String())
	}
	var response struct {
		TreeIDs []uuid.UUID `json:"tree_ids"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	ids := make(map[uuid.UUID]bool, len(response.TreeIDs))
	for _, id := range response.TreeIDs {
		ids[id] = true
	}
	return ids
}

// groveTreeIDs reads `GET /me/grove` back as a set of tree ids.
func groveTreeIDs(t *testing.T, h *harness, bearer string) map[uuid.UUID]bool {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/grove: status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Entries []struct {
			TreeUUID uuid.UUID `json:"tree_uuid"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	ids := make(map[uuid.UUID]bool, len(response.Entries))
	for _, entry := range response.Entries {
		ids[entry.TreeUUID] = true
	}
	return ids
}

// TestADisputeAloneDoesNotEnrollTheTreeAsYoursOrInTheGrove is the ruling's headline: raising a
// dispute and nothing else must leave the tree out of both reads, so the report screen's own copy
// — "Nothing on the map changes" — stays true.
func TestADisputeAloneDoesNotEnrollTheTreeAsYoursOrInTheGrove(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	item := disputeItem(dispute, tree, []string{"wrong_location"})
	if result := h.syncOne(t, session.AccessToken, item); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if yours := yoursIDs(t, h, session.AccessToken); yours[tree] {
		t.Fatal("a lone dispute enrolled its tree in the Yours map filter — " +
			"the report screen promises nothing on the map changes")
	}
	if grove := groveTreeIDs(t, h, session.AccessToken); grove[tree] {
		t.Fatal("a lone dispute enrolled its tree in the Grove")
	}
}

// TestAVisitStillEnrollsTheTree is the control for the test above: a real encounter with a tree
// must still land it in both reads, so a dispute-only exclusion is not hiding a read that refuses
// everything.
func TestAVisitStillEnrollsTheTree(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	if result := h.syncOne(t, session.AccessToken, visitItem(tree)); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if yours := yoursIDs(t, h, session.AccessToken); !yours[tree] {
		t.Fatal("a visit did not enroll its tree in the Yours map filter")
	}
	if grove := groveTreeIDs(t, h, session.AccessToken); !grove[tree] {
		t.Fatal("a visit did not enroll its tree in the Grove")
	}
}

// TestADisputeAndAVisitEnrollTheTreeOnce covers the case a pure kind-exclusion could get wrong in
// either direction: a dispute must not subtract from a tree's membership earned some other way, and
// the `UNION`/`DISTINCT` in both reads must not double the tree because two different kinds now
// touch it.
func TestADisputeAndAVisitEnrollTheTreeOnce(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, visitItem(tree)); result.Status != "applied" {
		t.Fatalf("recording the visit: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	if result := h.syncOne(t, session.AccessToken, disputeItem(dispute, tree, []string{"wrong_species"})); result.Status != "applied" {
		t.Fatalf("recording the dispute: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if yours := yoursIDs(t, h, session.AccessToken); !yours[tree] {
		t.Fatal("the visited, disputed tree is missing from the Yours map filter")
	}
	recorder := h.do(t, http.MethodGet, Prefix+"/me/map-membership?kind=yours", session.AccessToken, nil)
	var membership struct {
		TreeIDs []uuid.UUID `json:"tree_ids"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &membership); err != nil {
		t.Fatal(err)
	}
	count := 0
	for _, id := range membership.TreeIDs {
		if id == tree {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("tree appears %d times in the Yours set, want 1 — a visit and a dispute on the "+
			"same tree must not duplicate it", count)
	}

	grove := groveTreeIDs(t, h, session.AccessToken)
	if !grove[tree] {
		t.Fatal("the visited, disputed tree is missing from the Grove")
	}
	if len(grove) != 1 {
		t.Fatalf("the grove has %d entries, want 1 — a visit and a dispute on the same tree must "+
			"not produce two grove rows", len(grove))
	}
}

// TestADisputeThenItsWithdrawalLeavesNothingBehind covers the case that failed before this round in
// a second way: the residue. Before `store.TreeMembershipKinds`, a dispute enrolled the tree AND the
// withdrawal did not clear the enrollment, because neither read filtered on kind. Now the raise
// should never enroll the tree in the first place, and the withdrawal must not either.
func TestADisputeThenItsWithdrawalLeavesNothingBehind(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, disputeItem(dispute, tree, []string{"wrong_metadata"})); result.Status != "applied" {
		t.Fatalf("raising: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	if result := h.syncOne(t, session.AccessToken, disputeWithdrawalItem(dispute, tree)); result.Status != "applied" {
		t.Fatalf("withdrawing: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if yours := yoursIDs(t, h, session.AccessToken); yours[tree] {
		t.Fatal("a dispute plus its withdrawal left the tree in the Yours map filter")
	}
	if grove := groveTreeIDs(t, h, session.AccessToken); grove[tree] {
		t.Fatal("a dispute plus its withdrawal left the tree in the Grove")
	}
}
