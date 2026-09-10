package api

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The `data_dispute` / `data_dispute_withdrawal` half of `POST /sync` — R79's other side.
//
// Every item here is posted in the **client's own payload shape** (`AppSchema` v22's `DataDispute`
// and `DataDisputeWithdrawal`, whose keys are the Swift property names), for the reason
// `community_kinds_test.go` states: a test that invents its own wire format proves only that the
// handler agrees with the test.
//
// **What these assert, and what they deliberately do not.** Nothing materializes on this side, so
// there is no tally to read back the way `measurement_withdrawal_test.go` reads `GET /me/grove` —
// the record *is* the row. That makes one guard load-bearing rather than decorative:
// `TestADisputeMaterializesNothing` below is the ruling written as a test, and it is what a later
// round has to go red against before it can quietly start moving city data from here.

// disputePayload builds `DataDispute`'s body. Written as a struct and marshalled, rather than as a
// string, only because the suggestions map has to be a real JSON object in every case.
func disputePayload(dispute, tree uuid.UUID, issues []string, suggestions map[string]string, notes string) json.RawMessage {
	body := map[string]any{
		"id":          dispute,
		"clientUUID":  uuid.New(),
		"treeID":      tree,
		"treeSource":  "city",
		"issues":      issues,
		"suggestions": suggestions,
		"notes":       notes,
		"occurredAt":  "2026-09-10T10:00:00Z",
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		panic(err)
	}
	return encoded
}

// disputeItem is one raise, with a fresh item key every call.
func disputeItem(dispute, tree uuid.UUID, issues []string) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": disputePayload(dispute, tree, issues,
			map[string]string{"lat": "37.3382", "lon": "-121.8863"},
			"the trunk is across the path"),
	}
}

// disputeWithdrawalItem is one retraction, in `DataDisputeWithdrawal`'s shape.
func disputeWithdrawalItem(dispute, tree uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"clientUUID":"` + uuid.New().String() + `",` +
			`"disputeID":"` + dispute.String() + `","treeID":"` + tree.String() + `",` +
			`"occurredAt":"2026-09-10T11:00:00Z"}`),
	}
}

// storedPayload reads a contribution's body back out of the table, by item key.
func storedPayload(t *testing.T, h *harness, key uuid.UUID) (string, []byte) {
	t.Helper()
	var kind string
	var payload []byte
	err := h.store.Pool().QueryRow(context.Background(),
		`SELECT kind, payload FROM contributions WHERE client_uuid = $1`, key).Scan(&kind, &payload)
	if err != nil {
		t.Fatalf("the item answered applied and no row is there: %v", err)
	}
	return kind, payload
}

// TestADataDisputeIsAcceptedAndRecorded is the round's headline. Before it the item came back
// `validation_failed` — "That item's kind is not one this service accepts" — so a reader who
// disputed the city's record watched the queue row report a refusal.
func TestADataDisputeIsAcceptedAndRecorded(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	item := disputeItem(dispute, tree, []string{"wrong_location", "wrong_species"})
	result := h.syncOne(t, session.AccessToken, item)
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	kind, payload := storedPayload(t, h, item["client_uuid"].(uuid.UUID))
	if kind != "data_dispute" {
		t.Fatalf("stored kind = %q, want data_dispute", kind)
	}

	// The record is the whole of what this round ships, so the body has to survive: the moderation
	// surface reads these rows and nothing else. Read back as the dispute's own id, which is the
	// field a withdrawal will name.
	var stored struct {
		ID     uuid.UUID `json:"id"`
		Issues []string  `json:"issues"`
	}
	if err := json.Unmarshal(payload, &stored); err != nil {
		t.Fatalf("the stored payload does not decode: %v", err)
	}
	if stored.ID != dispute {
		t.Fatalf("stored dispute id = %s, want %s", stored.ID, dispute)
	}
	if len(stored.Issues) != 2 {
		t.Fatalf("stored issues = %v, want the two the payload carried", stored.Issues)
	}
}

// TestEveryIssueKindIsAcceptedOnItsOwn covers the vocabulary as a set. Listing two of the three in
// the headline above would let the third be refused with nothing noticing.
func TestEveryIssueKindIsAcceptedOnItsOwn(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	for _, issue := range []string{"wrong_location", "wrong_species", "wrong_metadata"} {
		tree := uuid.New()
		result := h.syncOne(t, session.AccessToken, disputeItem(uuid.New(), tree, []string{issue}))
		if result.Status != "applied" {
			t.Errorf("%s: status = %q (%s), want applied", issue, result.Status, codeOf(result.Error))
		}
	}
}

// TestADataDisputeWithdrawalIsAcceptedAndRecorded is the retraction, which R79 ships in the same
// round as the raise precisely so this surface does not arrive with the community flow's defect —
// a flag its own author cannot take back.
func TestADataDisputeWithdrawalIsAcceptedAndRecorded(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	if raise := h.syncOne(t, session.AccessToken, disputeItem(dispute, tree, []string{"wrong_species"})); raise.Status != "applied" {
		t.Fatalf("raising the dispute: status = %q (%s), want applied", raise.Status, codeOf(raise.Error))
	}

	item := disputeWithdrawalItem(dispute, tree)
	result := h.syncOne(t, session.AccessToken, item)
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	kind, payload := storedPayload(t, h, item["client_uuid"].(uuid.UUID))
	if kind != "data_dispute_withdrawal" {
		t.Fatalf("stored kind = %q, want data_dispute_withdrawal", kind)
	}
	var stored struct {
		DisputeID uuid.UUID `json:"disputeID"`
	}
	if err := json.Unmarshal(payload, &stored); err != nil {
		t.Fatalf("the stored payload does not decode: %v", err)
	}
	if stored.DisputeID != dispute {
		t.Fatalf("the withdrawal was recorded naming %s, want the dispute it takes back (%s)",
			stored.DisputeID, dispute)
	}
}

// TestAWithdrawalOfADisputeThisServiceNeverHeldIsApplied: a phone that never drained the raise still
// drains the retraction. Refusing would put a permanent red row on screen 17 for a dispute the
// person has already taken back — and there is nothing here to look the raise up in anyway.
func TestAWithdrawalOfADisputeThisServiceNeverHeldIsApplied(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	item := disputeWithdrawalItem(uuid.New(), tree)
	if result := h.syncOne(t, session.AccessToken, item); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	if kind, _ := storedPayload(t, h, item["client_uuid"].(uuid.UUID)); kind != "data_dispute_withdrawal" {
		t.Fatalf("stored kind = %q, want data_dispute_withdrawal", kind)
	}
}

// TestADisputeIsDedupedOnItsOwnKey pins that the new kinds inherit the dedupe every older kind has:
// a drain that does not hear the answer sends the item again, and the replay must not become a
// second dispute on the same tree.
func TestADisputeIsDedupedOnItsOwnKey(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()
	item := disputeItem(dispute, tree, []string{"wrong_metadata"})

	if first := h.syncOne(t, session.AccessToken, item); first.Status != "applied" {
		t.Fatalf("first pass: status = %q (%s), want applied", first.Status, codeOf(first.Error))
	}
	if second := h.syncOne(t, session.AccessToken, item); second.Status != "duplicate" {
		t.Fatalf("second pass: status = %q (%s), want duplicate", second.Status, codeOf(second.Error))
	}

	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`,
		item["client_uuid"]).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Fatalf("%d rows for one key; the replay recorded a second dispute", rows)
	}
}

// ── The ruling, written as a test ──────────────────────────────────────────────────────────────

// TestADisputeMaterializesNothing is R-c: the server records a dispute and does not act on it.
//
// It is here because the tempting shortcut is small and one-way. Adjudicating "the species is
// wrong" means moving a species on somebody's unadjudicated say-so, and the surface that adjudicates
// is a web deliverable (ARCHITECTURE §8) — so the row is the record, and a later round that starts
// writing a dispute table from this handler has to come here, read the ruling, and delete this test
// deliberately rather than by not noticing.
//
// Two assertions, and the second is the one that would catch the shortcut being taken by accident:
// no table server-side is named for a dispute, and one applied dispute writes one row in
// `contributions` and nothing anywhere else.
func TestADisputeMaterializesNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, disputeItem(dispute, tree, []string{"wrong_location"})); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	if result := h.syncOne(t, session.AccessToken, disputeWithdrawalItem(dispute, tree)); result.Status != "applied" {
		t.Fatalf("the withdrawal: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	var named []string
	rows, err := h.store.Pool().Query(context.Background(), `
		SELECT tablename FROM pg_tables
		 WHERE schemaname = 'public' AND tablename LIKE '%dispute%'
	`)
	if err != nil {
		t.Fatalf("listing tables: %v", err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		named = append(named, name)
	}
	rows.Close()
	if len(named) > 0 {
		t.Errorf("this service has grown %v. Nothing here may adjudicate a dispute: doing it moves "+
			"city data on an unadjudicated say-so, and the moderation surface is a web deliverable "+
			"(ARCHITECTURE §8). Read 005_data_dispute_kinds.sql before deleting this.", named)
	}

	// The calibration for the query above: it must find a table when one is there. Without it a
	// typo'd `LIKE` would pass this test forever, which is the shape of guard this project keeps
	// catching going green while the thing it named was present.
	var seen int
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%contribution%'
	`).Scan(&seen); err != nil {
		t.Fatal(err)
	}
	if seen == 0 {
		t.Fatal("the table query found no contributions table either; it is measuring nothing")
	}

	// One dispute and one withdrawal, and no other row anywhere.
	for _, table := range []string{"community_trees", "favorites", "photos", "anonymized_contributions"} {
		var count int
		if err := h.store.Pool().QueryRow(context.Background(),
			`SELECT count(*) FROM `+table).Scan(&count); err != nil {
			t.Fatalf("counting %s: %v", table, err)
		}
		if count != 0 {
			t.Errorf("a dispute wrote %d rows into %s", count, table)
		}
	}
	var contributions int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM contributions`).Scan(&contributions); err != nil {
		t.Fatal(err)
	}
	if contributions != 2 {
		t.Fatalf("contributions holds %d rows after a dispute and a withdrawal, want 2", contributions)
	}
}

// TestSuggestedValuesAreRecordedVerbatimAndNotChecked pins the other deliberate omission.
//
// The suggestion `field` vocabulary is CHECKed in the client's v22 and named there; this service
// records the pairs and does not know the list. That is not laziness — a second copy of a vocabulary
// in a file no build compiles with the first is exactly the drift
// `TestTheHandlersVocabularyAndTheColumnsAgree` exists because of, and here the drift would refuse
// well-formed disputes *non-retryably*. So a field this service has never heard of must travel
// through and come back out of the table unchanged.
func TestSuggestedValuesAreRecordedVerbatimAndNotChecked(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	dispute, tree := uuid.New(), uuid.New()

	item := map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": disputePayload(dispute, tree, []string{"wrong_metadata"},
			map[string]string{"a_field_this_service_has_never_heard_of": "42"},
			"notes the service does not read"),
	}
	if result := h.syncOne(t, session.AccessToken, item); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied — this service does not hold the field vocabulary "+
			"and must not refuse on it", result.Status, codeOf(result.Error))
	}

	_, payload := storedPayload(t, h, item["client_uuid"].(uuid.UUID))
	var stored struct {
		Suggestions map[string]string `json:"suggestions"`
		Notes       string            `json:"notes"`
	}
	if err := json.Unmarshal(payload, &stored); err != nil {
		t.Fatalf("the stored payload does not decode: %v", err)
	}
	if stored.Suggestions["a_field_this_service_has_never_heard_of"] != "42" {
		t.Fatalf("stored suggestions = %v, want the pair the payload carried", stored.Suggestions)
	}
	if stored.Notes != "notes the service does not read" {
		t.Fatalf("stored notes = %q, want the note the payload carried", stored.Notes)
	}
}

// ── The refusals ───────────────────────────────────────────────────────────────────────────────

// TestADisputeWithNoIdIsRefused closes the arm where the payload decodes and names no dispute.
//
// Without it the row would be recorded, answer `applied`, and arrive on the moderation surface as a
// dispute nothing can name — and no withdrawal could ever match it, because `disputeID` is the only
// handle its author has.
func TestADisputeWithNoIdIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"treeID":"` + tree.String() + `","treeSource":"city",` +
			`"issues":["wrong_location"]}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// TestADisputeWithNoIssuesIsRefused mirrors the client's own `.validationFailed` for an empty issue
// set. A dispute that says nothing is wrong is not a dispute, and recording one would put a row on
// the moderation surface with nothing to act on.
func TestADisputeWithNoIssuesIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken,
		disputeItemWithPayload(tree, disputePayload(uuid.New(), tree, []string{}, nil, "")))
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// TestADisputeWithAnUnknownIssueIsRefused is the gate on the vocabulary R79 fixes in both halves.
// It is the `treePlacements` refusal one field over, and the control that keeps
// `TestEveryIssueKindIsAcceptedOnItsOwn` from being consistent with a handler that accepts anything.
func TestADisputeWithAnUnknownIssueIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, disputeItemWithPayload(tree,
		disputePayload(uuid.New(), tree, []string{"wrong_location", "wrong_everything"}, nil, "")))
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed — one unknown issue beside "+
			"a known one must still refuse the item", result.Status, codeOf(result.Error))
	}
}

// TestADisputeWithAnUnknownTreeSourceIsRefused, and its sibling below, are the two halves of one
// rule: the pair is CHECKed, absence is not a refusal.
func TestADisputeWithAnUnknownTreeSourceIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, dispute := uuid.New(), uuid.New()

	result := h.syncOne(t, session.AccessToken, disputeItemWithPayload(tree,
		json.RawMessage(`{"id":"`+dispute.String()+`","treeID":"`+tree.String()+`",`+
			`"treeSource":"municipal","issues":["wrong_location"]}`)))
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// TestADisputeThatDoesNotSayTheTreeSourceIsApplied is `landContext`'s rule one field over: absent
// means they did not say, and nothing here substitutes an answer. It matters more than it looks —
// a refusal on absence turns a client that spells one key differently into a queue of terminal
// failures, over a value this service records and never acts on.
func TestADisputeThatDoesNotSayTheTreeSourceIsApplied(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, dispute := uuid.New(), uuid.New()

	result := h.syncOne(t, session.AccessToken, disputeItemWithPayload(tree,
		json.RawMessage(`{"id":"`+dispute.String()+`","treeID":"`+tree.String()+`",`+
			`"issues":["wrong_location"]}`)))
	if result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
}

// TestADisputeNamingTheWrongTreeIsRefused mirrors the check `add_tree`, `photo_withdrawal` and
// `measurement_withdrawal` all make: picking one of two disagreeing ids would file the dispute
// against a tree it is not about.
func TestADisputeNamingTheWrongTreeIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, other := uuid.New(), uuid.New()

	result := h.syncOne(t, session.AccessToken, disputeItemWithPayload(tree,
		disputePayload(uuid.New(), other, []string{"wrong_location"}, nil, "")))
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// TestAWithdrawalNamingNoDisputeIsRefused: without it a nil id would be recorded as a retraction of
// nothing, and answer `applied` for an item that identified nothing.
func TestAWithdrawalNamingNoDisputeIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{"treeID":"` + tree.String() + `"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// TestAWithdrawalNamingTheWrongTreeIsRefused is the disagreement check on the second kind.
func TestAWithdrawalNamingTheWrongTreeIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, other := uuid.New(), uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"disputeID":"` + uuid.New().String() + `",` +
			`"treeID":"` + other.String() + `"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// disputeItemWithPayload posts a raise whose body the caller wrote, for the refusal cases.
func disputeItemWithPayload(tree uuid.UUID, payload json.RawMessage) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     payload,
	}
}
