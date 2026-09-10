package api

import (
	"context"
	"encoding/json"
	"strings"
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
// **What these assert, and what they deliberately do not.** No dispute table exists on this side and
// no row outside `contributions` is written, so there is no tally to read back the way
// `measurement_withdrawal_test.go` reads `GET /me/grove` — the record *is* the row. That makes one
// guard load-bearing rather than decorative: `TestADisputeWritesNoTableAndNoRowOutsideContributions`
// below is the ruling written as a test, and it is what a later round has to go red against before it
// can quietly start moving city data from here.
//
// What no test in this file asserts is that the **reads** are unchanged, and that is a limit worth
// stating where somebody will look for it. A dispute enrols its tree in `GET /me/grove` and in
// `GET /me/map-membership?kind=yours`, and `GET /me/journal` serves a dispute back and goes on
// serving it after the withdrawal applies. All three are inherited — no reader here filters on kind
// — and all three belong to `docs/ROADMAP.md`'s chip "Answer what a withdrawn-to-empty tree should
// look like", not to this round. See the `data_dispute` paragraph beside `syncKinds`.

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

// ── Whose dispute it is ────────────────────────────────────────────────────────────────────────

// rowsForKey counts the contributions stored under one item key.
func rowsForKey(t *testing.T, h *harness, key uuid.UUID) int {
	t.Helper()
	var rows int
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	return rows
}

// TestAWithdrawalOfSomebodyElsesDisputeIsRefused is the ownership gate.
//
// Nothing is being kept from a reader here — `GET /me/journal` is owner-scoped, so Bob's withdrawal
// would only ever appear in Bob's own journal. What it prevents is a **false statement stored**: the
// `contributions` row is the record R79's moderation round reads, and "Bob withdrew this" about a
// dispute Alice raised is not true. `forbidden`, non-retryable, for the reason
// `measurement_withdrawal` refuses a reading that is somebody else's.
//
// The control is the same withdrawal from Alice, and it is not decoration: without it this case
// passes just as happily if the handler has been made to refuse every withdrawal, or if the kind has
// fallen out of `syncKinds` — two states in which the ownership rule is not being exercised at all.
func TestAWithdrawalOfSomebodyElsesDisputeIsRefused(t *testing.T) {
	h := newHarness(t)
	alice := h.signIn(t, nil)
	bob := h.registerDeviceToken(t, uuid.New())
	dispute, tree := uuid.New(), uuid.New()

	if raise := h.syncOne(t, alice.AccessToken, disputeItem(dispute, tree, []string{"wrong_species"})); raise.Status != "applied" {
		t.Fatalf("alice raising the dispute: status = %q (%s), want applied", raise.Status, codeOf(raise.Error))
	}

	stolen := disputeWithdrawalItem(dispute, tree)
	result := h.syncOne(t, bob, stolen)
	if result.Status != "failed" || codeOf(result.Error) != "forbidden" {
		t.Fatalf("bob withdrawing alice's dispute: status = %q, error = %s; want failed/forbidden",
			result.Status, codeOf(result.Error))
	}
	// The refusal has to leave nothing behind, because the row *is* the record: a stored
	// `data_dispute_withdrawal` owned by Bob is the false statement this gate exists to prevent, and
	// it would be just as false for having been reported as a failure to the phone.
	if rows := rowsForKey(t, h, stolen["client_uuid"].(uuid.UUID)); rows != 0 {
		t.Fatalf("the refused withdrawal left %d rows in contributions; the refusal must roll back", rows)
	}

	// The control: one identity over, the same withdrawal applies.
	own := disputeWithdrawalItem(dispute, tree)
	if result := h.syncOne(t, alice.AccessToken, own); result.Status != "applied" {
		t.Fatalf("alice withdrawing her own dispute came back %q (%s), want applied — this case "+
			"refused bob's item for some reason other than ownership, so it is measuring nothing",
			result.Status, codeOf(result.Error))
	}
}

// TestTheOwnershipLookupMatchesADisputeInEitherSpelling pins the `upper()` in the lookup.
//
// The payload is stored verbatim, and the client mints the same id in two spellings depending on
// which side of the outbox it came from — `SQLiteValue`'s uppercase and `JSONEncoder`'s lowercase,
// which is the case split `internal/uuid`'s own header records. A lookup comparing the extracted
// text with a plain `=` would find no match for a dispute raised in the other spelling, and "no
// match" is a **success** here: the gate would silently stop refusing.
func TestTheOwnershipLookupMatchesADisputeInEitherSpelling(t *testing.T) {
	h := newHarness(t)
	alice := h.signIn(t, nil)
	bob := h.registerDeviceToken(t, uuid.New())
	dispute, tree := uuid.New(), uuid.New()

	// Alice's raise carries the id in uppercase, as a row that came out of SQLite would.
	upperCased := strings.ToUpper(dispute.String())
	raise := map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"id":"` + upperCased + `","treeID":"` + tree.String() + `",` +
			`"treeSource":"city","issues":["wrong_location"]}`),
	}
	if result := h.syncOne(t, alice.AccessToken, raise); result.Status != "applied" {
		t.Fatalf("raising with an uppercase id: status = %q (%s), want applied",
			result.Status, codeOf(result.Error))
	}

	// The withdrawal names it in the lowercase `String()` spelling.
	if result := h.syncOne(t, bob, disputeWithdrawalItem(dispute, tree)); result.Status != "failed" ||
		codeOf(result.Error) != "forbidden" {
		t.Fatalf("bob withdrawing an uppercase-spelled dispute: status = %q, error = %s; "+
			"want failed/forbidden — the lookup missed the row across the two spellings",
			result.Status, codeOf(result.Error))
	}
	if result := h.syncOne(t, alice.AccessToken, disputeWithdrawalItem(dispute, tree)); result.Status != "applied" {
		t.Fatalf("alice withdrawing her own uppercase-spelled dispute came back %q (%s), want applied",
			result.Status, codeOf(result.Error))
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

// TestADisputeWritesNoTableAndNoRowOutsideContributions is R-c measured at the tables: the server
// records a dispute and writes nothing else.
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
//
// **The name is narrow on purpose, and the earlier one was not.** This case was called
// `TestADisputeMaterializesNothing`, which reads as "nothing this service serves changes" and is
// broader than anything it measures: it lists `pg_tables`, counts `pg_tables` a second time to
// calibrate that listing, and takes five row counts — four tables that must be empty and
// `contributions`, which must hold two — and never issues a single read. Two reads *do* change — a
// dispute puts the tree into `GET /me/grove` with an all-zero tally and into
// `GET /me/map-membership?kind=yours`, because `Grove`'s `mine` CTE and
// `MapMembership` filter only `kind <> 'private_reminder'`. That is inherited rather than introduced
// here (a `species_claim` does the same), it is the same root cause as the journal serving a
// withdrawn dispute, and it belongs to `docs/ROADMAP.md`'s chip "Answer what a withdrawn-to-empty
// tree should look like". A test that asserts more than it measures is this repo's most expensive
// defect shape, so the name says tables, because tables are what it reads.
func TestADisputeWritesNoTableAndNoRowOutsideContributions(t *testing.T) {
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

// ── The refusals, each with the twin that proves what refused it ───────────────────────────────

// jsonBody encodes a payload written as a map, so a case can take the valid body and break exactly
// one field of it.
func jsonBody(fields map[string]any) json.RawMessage {
	encoded, err := json.Marshal(fields)
	if err != nil {
		panic(err)
	}
	return encoded
}

// TestTheDisputeRefusals is table-driven, and every case posts **two** items: the malformed one,
// which must be refused, and its twin with the one offending field put back, which must apply.
//
// The twin is not symmetry for its own sake. A refusal test that asserts only
// `failed`/`validation_failed` passes just as happily when the *kind* is unknown to `syncKinds`,
// when the envelope is malformed, or when the handler has been made to refuse everything — three
// states in which the rule the case names is not being exercised at all, and each of which looks
// exactly like a passing test. That is this repo's most expensive test defect: a guard that stays
// green while the thing it guards is absent. The twin is the control that says the refused item was
// one field away from applying.
func TestTheDisputeRefusals(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, other := uuid.New(), uuid.New()

	// Both bases are valid items in the client's own shape. Each case breaks a copy.
	raise := func() map[string]any {
		return map[string]any{
			"id": uuid.New(), "clientUUID": uuid.New(), "treeID": tree,
			"treeSource": "city", "issues": []string{"wrong_location"},
			"suggestions": map[string]string{"lat": "37.3382"},
			"notes":       "the trunk is across the path",
			"occurredAt":  "2026-09-10T10:00:00Z",
		}
	}
	withdrawal := func() map[string]any {
		return map[string]any{
			"clientUUID": uuid.New(), "disputeID": uuid.New(), "treeID": tree,
			"occurredAt": "2026-09-10T11:00:00Z",
		}
	}

	for _, testCase := range []struct {
		name   string
		kind   string
		valid  func() map[string]any
		break_ func(map[string]any)
	}{
		{"a dispute that names no dispute", "data_dispute", raise,
			func(payload map[string]any) { delete(payload, "id") }},
		{"a dispute whose body names another tree", "data_dispute", raise,
			func(payload map[string]any) { payload["treeID"] = other }},
		{"a dispute that says nothing is wrong", "data_dispute", raise,
			func(payload map[string]any) { payload["issues"] = []string{} }},
		{"a dispute naming an issue nothing defines", "data_dispute", raise,
			func(payload map[string]any) { payload["issues"] = []string{"wrong_location", "wrong_everything"} }},
		{"a dispute whose tree source is neither of the two", "data_dispute", raise,
			func(payload map[string]any) { payload["treeSource"] = "municipal" }},
		{"a withdrawal that names no dispute", "data_dispute_withdrawal", withdrawal,
			func(payload map[string]any) { delete(payload, "disputeID") }},
		{"a withdrawal whose body names another tree", "data_dispute_withdrawal", withdrawal,
			func(payload map[string]any) { payload["treeID"] = other }},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			broken := testCase.valid()
			testCase.break_(broken)

			result := h.syncOne(t, session.AccessToken, map[string]any{
				"client_uuid": uuid.New(), "kind": testCase.kind, "tree_uuid": tree,
				"occurred_at": time.Now().UTC(), "payload": jsonBody(broken),
			})
			if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
				t.Fatalf("status = %q, error = %s; want failed/validation_failed",
					result.Status, codeOf(result.Error))
			}

			twin := h.syncOne(t, session.AccessToken, map[string]any{
				"client_uuid": uuid.New(), "kind": testCase.kind, "tree_uuid": tree,
				"occurred_at": time.Now().UTC(), "payload": jsonBody(testCase.valid()),
			})
			if twin.Status != "applied" {
				t.Fatalf("the corrected twin came back %q (%s), want applied — this case refused "+
					"the item for some reason other than the field it names, so it is measuring "+
					"nothing", twin.Status, codeOf(twin.Error))
			}
		})
	}
}

// TestADisputeThatDoesNotSayTheTreeSourceIsApplied is the other half of the tree-source rule, and
// it is `landContext`'s rule one field over: absent means they did not say, and nothing here
// substitutes an answer.
//
// It matters more than it looks. A refusal on absence turns a client that spells one key
// differently into a queue of terminal failures — `validation_failed` is not retryable — over a
// value this service records and never acts on.
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

// disputeItemWithPayload posts a raise whose body the caller wrote.
func disputeItemWithPayload(tree uuid.UUID, payload json.RawMessage) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "data_dispute", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     payload,
	}
}
