package api

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"sort"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The `measurement_withdrawal` half of `POST /sync` — report F27's other side.
//
// **Every assertion here is about whether the reading is still being counted**, not about
// `contributions.deleted_at`. That is the same discipline `photo_withdrawal_test.go` states and it
// matters more here, not less: the failure ERRATA E280 describes is a client being told a thing was
// removed while the service goes on serving it, and a test that read the column would pass in
// exactly that world, because the column is not what would be wrong. What a person sees is the
// number in `GET /me/grove` and the row in `GET /me/journal`, so that is what these ask.

// measurementItem is one `measurement`, in the client's own payload shape.
//
// `TreeMeasurement` is `Codable` with synthesized keys, so the payload's keys are the Swift property
// names and `id` is the reading's own id — distinct from `clientUUID`, which is the item's. The two
// being different values is the whole reason a withdrawal cannot be matched on the envelope's key.
func measurementItem(tree, reading uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "measurement", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"id":"` + reading.String() + `","treeID":"` + tree.String() + `",` +
			`"clientUUID":"` + uuid.New().String() + `","kind":"dbh",` +
			`"capturedAt":"2026-09-01T10:00:00Z"}`),
	}
}

// withdrawReading posts one `measurement_withdrawal` in the client's own payload shape
// (`MeasurementWithdrawal`, `CommunityMutations.swift`). A fresh key every call, like `withdraw`.
func withdrawReading(t *testing.T, h *harness, bearer string, tree, reading uuid.UUID) syncResult {
	t.Helper()
	return h.syncOne(t, bearer, withdrawalItem(tree, reading))
}

func withdrawalItem(tree, reading uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "measurement_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"clientUUID":"` + uuid.New().String() + `",` +
			`"measurementID":"` + reading.String() + `","treeID":"` + tree.String() + `",` +
			`"kind":"dbh","occurredAt":"2026-09-01T11:00:00Z"}`),
	}
}

// readingsCounted answers the only question these tests care about: how many readings this identity
// is told it has on this tree.
//
// `GET /me/grove` rather than the table, for the reason in the file header. It returns -1 when the
// tree is absent from the grove entirely, which is a third answer and not a zero — an entry with a
// zero tally and no entry at all are different claims, and collapsing them would let a test pass on
// a grove that lost the tree.
func readingsCounted(t *testing.T, h *harness, bearer string, tree uuid.UUID) int {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/grove: status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Entries []struct {
			TreeUUID uuid.UUID `json:"tree_uuid"`
			Record   struct {
				Measurements int `json:"measurements"`
			} `json:"record"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	for _, entry := range response.Entries {
		if entry.TreeUUID == tree {
			return entry.Record.Measurements
		}
	}
	return -1
}

// journalNames reports whether the personal timeline still carries this contribution.
func journalNames(t *testing.T, h *harness, bearer string, key uuid.UUID) bool {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/journal", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/journal: status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Items []struct {
			ClientUUID uuid.UUID `json:"client_uuid"`
		} `json:"items"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	for _, item := range response.Items {
		if item.ClientUUID == key {
			return true
		}
	}
	return false
}

// TestWithdrawalStopsTheServiceCountingTheReading is the round's headline. Before it, the item came
// back `validation_failed` — "That item's kind is not one this service accepts" — so a reader who
// withdrew a reading watched it vanish on the phone and watched the queue row report a refusal.
func TestWithdrawalStopsTheServiceCountingTheReading(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, reading := uuid.New(), uuid.New()

	item := measurementItem(tree, reading)
	if result := h.syncOne(t, session.AccessToken, item); result.Status != "applied" {
		t.Fatalf("recording the reading: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}
	// The control. Without it this test could pass on a reading that was never counted at all,
	// which is the shape of red-proof this project keeps catching too late.
	if counted := readingsCounted(t, h, session.AccessToken, tree); counted != 1 {
		t.Fatalf("precondition: the grove counts %d readings, want 1 — this test could not tell a "+
			"working withdrawal from a broken tally", counted)
	}
	key := item["client_uuid"].(uuid.UUID)
	if !journalNames(t, h, session.AccessToken, key) {
		t.Fatal("precondition: the journal does not carry the reading before the withdrawal")
	}

	if result := withdrawReading(t, h, session.AccessToken, tree, reading); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if counted := readingsCounted(t, h, session.AccessToken, tree); counted == 1 {
		t.Fatal("the service is still counting a withdrawn reading — screen 17 reads " +
			"\"withdrawn\" while GET /me/grove goes on reporting the number (ERRATA E280)")
	}
	if journalNames(t, h, session.AccessToken, key) {
		t.Fatal("the journal still carries a withdrawn reading")
	}
}

// TestWithdrawalOfSomebodyElsesReadingIsRefusedAndChangesNothing is the guard on the answer that
// would be easiest to get wrong, because the wrong answer is the quiet one: a `applied` here would
// have screen 17 say the reading was withdrawn while its author's grove goes on counting it.
func TestWithdrawalOfSomebodyElsesReadingIsRefusedAndChangesNothing(t *testing.T) {
	h := newHarness(t)
	owner := h.signIn(t, nil)
	stranger := h.registerDeviceToken(t, uuid.New())
	tree, reading := uuid.New(), uuid.New()

	if result := h.syncOne(t, owner.AccessToken, measurementItem(tree, reading)); result.Status != "applied" {
		t.Fatalf("recording the reading: status = %q, want applied", result.Status)
	}

	result := withdrawReading(t, h, stranger, tree, reading)
	if result.Status != "failed" || codeOf(result.Error) != "forbidden" {
		t.Fatalf("status = %q, error = %s; want failed/forbidden — a success here would report a "+
			"withdrawal that did not happen", result.Status, codeOf(result.Error))
	}
	if result.Error.Retryable() {
		t.Fatal("forbidden must not be retryable; a retry cannot change this answer")
	}
	if counted := readingsCounted(t, h, owner.AccessToken, tree); counted != 1 {
		t.Fatalf("the owner's grove counts %d readings after a refused withdrawal, want 1", counted)
	}
}

// TestWithdrawalOfAReadingThisServiceNeverHeldIsAppliedAndChangesNothing: a phone that never drained
// the reading still drains the withdrawal. Failing it would put a red row on screen 17 forever for
// a reading the person has already taken back.
func TestWithdrawalOfAReadingThisServiceNeverHeldIsAppliedAndChangesNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	item := withdrawalItem(tree, uuid.New())
	if result := h.syncOne(t, session.AccessToken, item); result.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	// The record of the act is the point — it is what the late arrival then reads.
	var stored string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT kind FROM contributions WHERE client_uuid = $1`, item["client_uuid"]).Scan(&stored); err != nil {
		t.Fatalf("the withdrawal was answered applied but not recorded: %v", err)
	}
	if stored != "measurement_withdrawal" {
		t.Fatalf("stored kind = %q, want measurement_withdrawal", stored)
	}
}

// TestMeasurementWithdrawalIsIdempotentAcrossAReplay covers the flap: a drain that does not hear the
// answer sends the item again, and the second pass must not become a failure on screen 17.
func TestMeasurementWithdrawalIsIdempotentAcrossAReplay(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, reading := uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, measurementItem(tree, reading)); result.Status != "applied" {
		t.Fatalf("recording the reading: status = %q, want applied", result.Status)
	}
	item := withdrawalItem(tree, reading)

	if first := h.syncOne(t, session.AccessToken, item); first.Status != "applied" {
		t.Fatalf("first pass: status = %q (%s), want applied", first.Status, codeOf(first.Error))
	}
	second := h.syncOne(t, session.AccessToken, item)
	if second.Status != "duplicate" {
		t.Fatalf("second pass: status = %q (%s), want duplicate", second.Status, codeOf(second.Error))
	}
	if counted := readingsCounted(t, h, session.AccessToken, tree); counted == 1 {
		t.Fatal("the replay resurrected a withdrawn reading")
	}
}

// TestWithdrawalOfAnAlreadyWithdrawnReadingIsApplied covers the third of `withdrawMeasurement`'s
// three answers, which the replay test above cannot reach.
//
// **Why it cannot**, which is the lesson #113's review paid for on the photograph side: the replay
// reuses one `client_uuid`, so the *contribution dedupe* answers `duplicate` before the store's
// withdrawal is ever called. What that test measures is the dedupe's idempotency, not this arm's.
// A fresh key makes the arm reachable, and the path is the ordinary one rather than a contrivance —
// `MeasurementWithdrawal` is queued already applied, so a second withdrawal of the same reading from
// a second device of the same account carries a key this service has never seen.
func TestWithdrawalOfAnAlreadyWithdrawnReadingIsApplied(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, reading := uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, measurementItem(tree, reading)); result.Status != "applied" {
		t.Fatalf("recording the reading: status = %q, want applied", result.Status)
	}
	if first := withdrawReading(t, h, session.AccessToken, tree, reading); first.Status != "applied" {
		t.Fatalf("first withdrawal: status = %q (%s), want applied", first.Status, codeOf(first.Error))
	}

	second := withdrawReading(t, h, session.AccessToken, tree, reading)
	if second.Status != "applied" {
		t.Fatalf("status = %q (%s), want applied — the reading is already withdrawn, so a second "+
			"withdrawal is a success that changes nothing; refusing puts a permanent red row on "+
			"screen 17 for a withdrawal that already worked", second.Status, codeOf(second.Error))
	}
}

// TestMeasurementWithdrawalNamingTheWrongTreeIsRefused mirrors the check `add_tree` and
// `photo_withdrawal` both make: picking one of two disagreeing ids would file the withdrawal against
// a tree the reading is not on.
func TestMeasurementWithdrawalNamingTheWrongTreeIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, other, reading := uuid.New(), uuid.New(), uuid.New()

	if result := h.syncOne(t, session.AccessToken, measurementItem(tree, reading)); result.Status != "applied" {
		t.Fatalf("recording the reading: status = %q, want applied", result.Status)
	}

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "measurement_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload": json.RawMessage(`{"measurementID":"` + reading.String() + `",` +
			`"treeID":"` + other.String() + `","kind":"dbh"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
	if counted := readingsCounted(t, h, session.AccessToken, tree); counted != 1 {
		t.Fatalf("a malformed withdrawal removed the reading anyway; the grove counts %d", counted)
	}
}

// TestMeasurementWithdrawalWithNoReadingIsRefused closes the arm where the payload decodes but names
// nothing. Without it a nil id would reach the store, match no row, and come back `applied` — a
// success reported for an item that identified nothing.
func TestMeasurementWithdrawalWithNoReadingIsRefused(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	result := h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "measurement_withdrawal", "tree_uuid": tree,
		"occurred_at": time.Now().UTC(),
		"payload":     json.RawMessage(`{"treeID":"` + tree.String() + `","kind":"dbh"}`),
	})
	if result.Status != "failed" || codeOf(result.Error) != "validation_failed" {
		t.Fatalf("status = %q, error = %s; want failed/validation_failed", result.Status, codeOf(result.Error))
	}
}

// ── The arrival order, which is the case photographs do not have ───────────────────────────────

// TestAReadingThatArrivesAfterItsWithdrawalIsNotCounted is the hole the client's own queue opens.
//
// `OutboxStore.dueItems` orders by `seq` over what is **due**, and an item in backoff is not due. So
// a `measurement` that failed once lands *after* the withdrawal that took it back — and without the
// guard the withdrawal answered `applied`, screen 17 said the reading was withdrawn, and twenty
// minutes later the number came back into `GET /me/grove` and stayed there.
func TestAReadingThatArrivesAfterItsWithdrawalIsNotCounted(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree, reading := uuid.New(), uuid.New()

	// The withdrawal first, against a reading this service has never seen.
	if result := withdrawReading(t, h, session.AccessToken, tree, reading); result.Status != "applied" {
		t.Fatalf("the withdrawal: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	// Then the reading itself, drained late.
	late := measurementItem(tree, reading)
	if result := h.syncOne(t, session.AccessToken, late); result.Status != "applied" {
		t.Fatalf("the late reading: status = %q (%s), want applied — the item is well-formed and "+
			"must not be refused; it is the *effect* that has to be nil", result.Status, codeOf(result.Error))
	}

	if counted := readingsCounted(t, h, session.AccessToken, tree); counted > 0 {
		t.Fatalf("the grove counts %d readings after one that had already been withdrawn arrived; "+
			"screen 17 said it was withdrawn and the number came back", counted)
	}
	if journalNames(t, h, session.AccessToken, late["client_uuid"].(uuid.UUID)) {
		t.Fatal("the journal carries a reading that had already been withdrawn")
	}
}

// TestAStrangersWithdrawalDoesNotSilenceALaterReading is the negative control for the test above,
// and it is what makes the guard a gate rather than a switch.
//
// Reading ids travel in every `GET /me/journal` payload. If the arrival-order lookup were not scoped
// to the same owner, anyone could file a withdrawal naming somebody else's reading id and have that
// person's next drain arrive already tombstoned — a stranger silencing a number by getting there
// first.
func TestAStrangersWithdrawalDoesNotSilenceALaterReading(t *testing.T) {
	h := newHarness(t)
	author := h.signIn(t, nil)
	stranger := h.registerDeviceToken(t, uuid.New())
	tree, reading := uuid.New(), uuid.New()

	// The stranger withdraws a reading nothing here holds: applied, and it changes nothing.
	if result := withdrawReading(t, h, stranger, tree, reading); result.Status != "applied" {
		t.Fatalf("the stranger's withdrawal: status = %q (%s), want applied", result.Status, codeOf(result.Error))
	}

	if result := h.syncOne(t, author.AccessToken, measurementItem(tree, reading)); result.Status != "applied" {
		t.Fatalf("the reading: status = %q, want applied", result.Status)
	}
	if counted := readingsCounted(t, h, author.AccessToken, tree); counted != 1 {
		t.Fatalf("the author's grove counts %d readings, want 1 — a stranger's withdrawal "+
			"tombstoned a reading that was never theirs", counted)
	}
}

// ── The map and the CHECK, which is the drift this whole round is ──────────────────────────────

// checkedKinds reads the vocabulary out of the live constraint.
//
// `conname LIKE 'contributions_kind%'` rather than the current name spelled out: every widening of
// this column takes a *new* constraint name by 001's rule, so a test naming one would have to be
// edited by the next migration and would silently match nothing if it were not.
func checkedKinds(t *testing.T, h *harness) []string {
	t.Helper()
	var definition string
	err := h.store.Pool().QueryRow(context.Background(), `
		SELECT pg_get_constraintdef(oid) FROM pg_constraint
		 WHERE conrelid = 'contributions'::regclass AND contype = 'c'
		   AND conname LIKE 'contributions_kind%'
	`).Scan(&definition)
	if err != nil {
		t.Fatalf("reading the kind constraint: %v", err)
	}
	literals := regexp.MustCompile(`'([a-z_]+)'`).FindAllStringSubmatch(definition, -1)
	var kinds []string
	for _, match := range literals {
		kinds = append(kinds, match[1])
	}
	// Calibration, not decoration: a regexp that matched nothing would make the comparison below
	// trivially satisfiable in one direction and would look exactly like a passing test.
	if len(kinds) == 0 {
		t.Fatalf("no kind literals parsed out of %q; this test is measuring nothing", definition)
	}
	return kinds
}

// TestTheHandlersVocabularyAndTheColumnsAgree is the gate on the defect this round exists to close.
//
// `syncKinds` and the `CHECK` are two statements of one vocabulary, kept in step by hand across a Go
// file and a SQL file that no build compiles together. They had drifted: `measurement_withdrawal`
// was in the client's `AppSchema` v21 and in neither of these, so a drain that reached the service
// was refused. Nothing here noticed, because every test that touches a kind names it.
//
// Both directions, and neither is redundant. A kind the map accepts and the column refuses is a
// `server_error` on a well-formed item — retried for 48 h and then failed. A kind the column accepts
// and the map refuses is the state this round found: `validation_failed`, non-retryable, on the
// first attempt.
func TestTheHandlersVocabularyAndTheColumnsAgree(t *testing.T) {
	h := newHarness(t)

	inTheColumn := map[string]bool{}
	for _, kind := range checkedKinds(t, h) {
		inTheColumn[kind] = true
	}

	var missingFromTheColumn, missingFromTheMap []string
	for kind := range syncKinds {
		if !inTheColumn[kind] {
			missingFromTheColumn = append(missingFromTheColumn, kind)
		}
	}
	for kind := range inTheColumn {
		if !syncKinds[kind] {
			missingFromTheMap = append(missingFromTheMap, kind)
		}
	}
	sort.Strings(missingFromTheColumn)
	sort.Strings(missingFromTheMap)

	if len(missingFromTheColumn) > 0 {
		t.Errorf("syncKinds accepts %v, which contributions.kind refuses: a well-formed item would "+
			"come back server_error and be retried for 48 h", missingFromTheColumn)
	}
	if len(missingFromTheMap) > 0 {
		t.Errorf("contributions.kind admits %v, which syncKinds refuses: the item fails "+
			"validation_failed on the first attempt and is never retried", missingFromTheMap)
	}
}

// TestEveryKindTheHandlerAcceptsIsStorable is the same agreement measured against the database
// rather than against the constraint's text.
//
// It is not a duplicate of the test above, and the difference is the point: that one parses a string
// out of `pg_get_constraintdef`, which is a claim about a claim. This one asks the column, by
// writing every kind the handler accepts and letting the CHECK answer.
//
// The rows are inserted anonymized — `anonymized_at` set, both owners NULL — which is the one arm of
// `contributions_owner` that needs no `devices` or `users` row, so the test exercises the kind
// vocabulary and nothing else.
func TestEveryKindTheHandlerAcceptsIsStorable(t *testing.T) {
	h := newHarness(t)
	now := time.Now().UTC()

	for kind := range syncKinds {
		_, err := h.store.Pool().Exec(context.Background(), `
			INSERT INTO contributions
			    (client_uuid, kind, tree_uuid, payload, occurred_at, anonymized_at,
			     created_at, updated_at)
			VALUES ($1, $2, $3, '{}'::jsonb, $4, $4, $4, $4)
		`, uuid.New(), kind, uuid.New(), now)
		if err != nil {
			t.Errorf("the handler accepts %q and the column refuses it: %v", kind, err)
		}
	}

	// The control that keeps the loop honest: the column must still refuse something. Without it a
	// CHECK that had been dropped altogether would pass every assertion above.
	_, err := h.store.Pool().Exec(context.Background(), `
		INSERT INTO contributions
		    (client_uuid, kind, tree_uuid, payload, occurred_at, anonymized_at, created_at, updated_at)
		VALUES ($1, 'species_withdrawal', $2, '{}'::jsonb, $3, $3, $3, $3)
	`, uuid.New(), uuid.New(), now)
	if err == nil {
		t.Fatal("contributions.kind accepted a kind nothing defines; the CHECK is not a gate")
	}
}
