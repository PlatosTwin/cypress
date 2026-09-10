package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/ratelimit"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// `GET /api/v1/public/trees/{id}` — the only unauthenticated read this service answers.
//
// **Every assertion here is about what reaches a stranger**, not about what the query selected. The
// contract is `docs/rulings-pending/public-tree-read.md`, and its refusals are refusals *about the
// bytes*: a test that checked the SQL would pass in the world where a later projection put an
// identifier back, which is the world worth testing for. So the identity, count, timestamp and
// free-text guards below read the response body as a stranger would — as text.

// The fixtures are fixed so the golden files are stable, and named so a failure says which is which.
var (
	publicTreeID = uuid.MustParse("9f3a1c07-4d55-4a7e-9f10-2b6f0c1d5e42")
	// The identifiers a contributor's payload carries. Nothing in the response may contain them —
	// `TestNoContributorIdentifierReachesThePublicRead` searches the bytes for exactly these.
	publicContributorUser   = uuid.MustParse("c0ffee11-2233-4455-8677-889900aabbcc")
	publicContributorDevice = uuid.MustParse("dec1ce22-3344-4556-8778-99aabbccddee")
)

// publicNote is the free text a check-in can carry, and it is `SCREENS.md` §W1's own first
// visits-panel row — the one the ruling refuses. Seeded so the guard has a real string to look for.
const publicNote = "Fog dripping off the crown"

// measurementItemWithQuantity is a `measurement` in the client's own payload shape, carrying
// everything `TreeMeasurement` actually carries — including the three identifiers and the GPS
// accuracy that must never travel.
func measurementItemWithQuantity(tree uuid.UUID, kind string, value float64, unit, method, occurredAt string) map[string]any {
	payload := fmt.Sprintf(
		`{"id":%q,"treeID":%q,"userID":%q,"deviceID":%q,"clientUUID":%q,`+
			`"capturedAt":%q,"gpsAccuracyM":4.5,"kind":%q,`+
			`"quantity":{"value":%v,"unitEntered":%q,"method":%q},`+
			`"measurementHeightM":1.4,"verificationState":"unverified"}`,
		uuid.New(), tree, publicContributorUser, publicContributorDevice, uuid.New(),
		occurredAt, kind, value, unit, method)
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "measurement", "tree_uuid": tree,
		"occurred_at": occurredAt, "payload": json.RawMessage(payload),
	}
}

// observationItem is an `observation` in the client's own payload shape: a rating, and beside it the
// note, the status and the structure flags the ruling refuses.
func observationItem(tree uuid.UUID, vitality any, occurredAt string) map[string]any {
	payload := fmt.Sprintf(
		`{"id":%q,"treeID":%q,"userID":%q,"deviceID":%q,"clientUUID":%q,`+
			`"capturedAt":%q,"gpsAccuracyM":3.25,"status":"alive","vitality":%v,`+
			`"note":%q,"structureFlags":["lean"],"verificationState":"unverified"}`,
		uuid.New(), tree, publicContributorUser, publicContributorDevice, uuid.New(),
		occurredAt, vitality, publicNote)
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "observation", "tree_uuid": tree,
		"occurred_at": occurredAt, "payload": json.RawMessage(payload),
	}
}

// readPublicly asks the way a stranger asks. Deliberately **no bearer**: a credential passed here
// would prove nothing about the route a stranger reaches.
func (h *harness) readPublicly(t *testing.T, tree uuid.UUID) *httptest.ResponseRecorder {
	t.Helper()
	return h.do(t, http.MethodGet, Prefix+"/public/trees/"+tree.String(), "", nil)
}

func (h *harness) applyItem(t *testing.T, bearer string, item map[string]any) {
	t.Helper()
	if result := h.syncOne(t, bearer, item); result.Status != "applied" {
		t.Fatalf("seeding a %v: status = %q (%s), want applied — a guard on a row that was never "+
			"recorded proves nothing", item["kind"], result.Status, codeOf(result.Error))
	}
}

// seedOneTreeWithEverything records the three things the public read publishes, plus the things
// carried alongside them that it must not.
func seedOneTreeWithEverything(t *testing.T, h *harness, bearer string, tree uuid.UUID) {
	t.Helper()
	h.applyItem(t, bearer, measurementItemWithQuantity(tree, "height", 18, "m", "estimate", "2026-08-14T17:04:11Z"))
	h.applyItem(t, bearer, measurementItemWithQuantity(tree, "dbh", 64, "cm", "tape", "2026-07-02T09:12:00Z"))
	h.applyItem(t, bearer, observationItem(tree, 4, "2026-09-03T18:30:00Z"))
}

// ── What the page gets ─────────────────────────────────────────────────────────────────────────

// TestPublicTreeReturnsTheContributedState is the headline, and it is a golden file because the
// consumer is a different language.
//
// `server/testdata/` exists because a cross-language contract cannot be proved from one side. The
// comparison is byte-for-byte for the reason the other fixtures already carry: a structural
// comparison against a Go struct compares the handler to its author's transcription, which is the
// thing that was wrong twice.
func TestPublicTreeReturnsTheContributedState(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	seedOneTreeWithEverything(t, h, session.AccessToken, publicTreeID)

	recorder := h.readPublicly(t, publicTreeID)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "public_tree.json", recorder.Body.Bytes())
}

// TestTheEmptyAnswerIsAlsoAFixture. The web renders both, so both are pinned.
func TestTheEmptyAnswerIsAlsoAFixture(t *testing.T) {
	h := newHarness(t)
	compareGolden(t, "public_tree_empty.json", h.readPublicly(t, publicTreeID).Body.Bytes())
}

// TestTheBodyCarriesTheseFiveKeysAndNoOthers is the count refusal, asserted positively.
//
// The ruling's §1 forbids **every** count — photographs, visits, contributors, readings — and a test
// that searched for the word "count" would pass on a field called `photos_since`. So the whole
// top-level key set is pinned instead: a sixth key fails whatever it is called, and the author who
// adds one has to come here and say why.
func TestTheBodyCarriesTheseFiveKeysAndNoOthers(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	seedOneTreeWithEverything(t, h, session.AccessToken, publicTreeID)
	// And a tree with plenty to count, so a count-shaped field would have something to say.
	for _, day := range []string{"01", "02", "03"} {
		h.applyItem(t, session.AccessToken, map[string]any{
			"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": publicTreeID,
			"occurred_at": "2026-09-" + day + "T12:00:00Z", "payload": json.RawMessage(`{}`),
		})
	}

	var body map[string]json.RawMessage
	if err := json.Unmarshal(h.readPublicly(t, publicTreeID).Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(body))
	for key := range body {
		got = append(got, key)
	}
	sort.Strings(got)
	want := []string{"height", "tree_uuid", "trunk_dbh", "verification_state", "vitality"}
	if !slices.Equal(got, want) {
		t.Fatalf("the public body's keys are %v, want exactly %v — a new key on a public page is a "+
			"disclosure decision and belongs in the ruling before it belongs here", got, want)
	}
}

// TestOnlyTheLatestReadingPerMeasurementKindIsPublished pins the "a state, not a series" rule.
//
// A list of dated readings is the visits panel wearing a number: it is where a person was, three
// times over. One value per measurement kind is a fact about the tree. The two kinds are answered
// separately, so a fresh height cannot displace an older diameter.
//
// **This test was named `…PerSeriesIsPublished` and did not test series.** `MeasurementSeries` is
// `measured | estimated`; `MeasurementKind` is `dbh | height`, and the latter is what both this test
// and the query group on. The name is corrected rather than the assertion, because the assertion was
// the right one — and the axis the old name promised is tested for real, one test below.
func TestOnlyTheLatestReadingPerMeasurementKindIsPublished(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	h.applyItem(t, session.AccessToken, measurementItemWithQuantity(tree, "dbh", 60, "cm", "tape", "2024-05-01T10:00:00Z"))
	h.applyItem(t, session.AccessToken, measurementItemWithQuantity(tree, "dbh", 64, "cm", "tape", "2026-07-02T09:12:00Z"))
	h.applyItem(t, session.AccessToken, measurementItemWithQuantity(tree, "height", 18, "m", "estimate", "2026-08-14T17:04:11Z"))

	recorder := h.readPublicly(t, tree)
	body := decodePublic(t, recorder)
	if body.TrunkDBH == nil || body.TrunkDBH.Value != 64 {
		t.Fatalf("trunk_dbh = %+v, want the 2026 reading of 64", body.TrunkDBH)
	}
	if body.Height == nil || body.Height.Value != 18 {
		t.Fatalf("height = %+v, want the estimate of 18 — the two measurement kinds are answered "+
			"separately, so a later diameter must not displace a height", body.Height)
	}
	// `"value":60` rather than `60`, for the reason `TestWithheldKindsProduceTheEmptyAnswer` gives:
	// a bare two-digit string matches a random UUID often enough to be a coin flip.
	if strings.Contains(recorder.Body.String(), "2024-05") ||
		strings.Contains(recorder.Body.String(), `"value":60`) {
		t.Fatalf("a superseded reading is in the body; the public read publishes a state, not a "+
			"dated series of somebody's visits:\n%s", recorder.Body.String())
	}
}

// TestANewerEstimateSupersedesAnOlderTapedReading is the series axis, tested rather than asserted.
//
// **This is the case the adversarial review found, and the behavior is deliberate.** A 90 cm
// `estimate` taken after a 64 cm `tape` is what the page shows. `DISTINCT ON (payload ->> 'kind')`
// groups on `MeasurementKind` and not on `MeasurementSeries`, so nothing here ranks an instrument
// above a guess — and nothing on the phone does either:
// `TreeProfilePresentation.latestMeasurement` is `filter { kind }.max { capturedAt }` with no method
// term, `MeasureModel.previousMeasurement` is a second copy of it, and no ruling, decision or
// erratum in this repository states a precedence. D7 and PRODUCT's non-goal are rules about a chart
// line, and this response draws no chart.
//
// A server-side precedence rule would therefore be this service inventing a product rule, and the
// page would print `64 cm taped` where the phone prints `90 cm est.` for the same tree — the
// two-copies failure, not a fix for it.
//
// **What is asserted is the honesty the behavior rests on:** the superseding value arrives carrying
// its own method, so the reader is told it is an estimate. A published number without its method
// would be this service laundering a guess into a measurement, and that is what D7 actually forbids.
//
// If the answer to *one tree, one current height: should the method count?* ever changes, it changes
// here first, visibly, rather than in a `DISTINCT ON` nobody re-reads.
func TestANewerEstimateSupersedesAnOlderTapedReading(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()

	h.applyItem(t, session.AccessToken,
		measurementItemWithQuantity(tree, "dbh", 64, "cm", "tape", "2024-05-01T10:00:00Z"))
	h.applyItem(t, session.AccessToken,
		measurementItemWithQuantity(tree, "dbh", 90, "cm", "estimate", "2026-08-14T17:04:11Z"))

	body := decodePublic(t, h.readPublicly(t, tree))
	if body.TrunkDBH == nil {
		t.Fatal("trunk_dbh is absent; neither reading was published and this test has nothing to say")
	}
	if body.TrunkDBH.Value != 90 {
		t.Errorf("trunk_dbh = %+v, want the 2026 estimate of 90 — this endpoint takes the latest "+
			"reading per measurement kind and does not rank methods, because the client's own "+
			"`latestMeasurement` does not either. Ranking them here forks the answer between the "+
			"page and the phone; if that is now the intended behavior, it is a ruling first",
			body.TrunkDBH)
	}
	if body.TrunkDBH.Method != "estimate" {
		t.Errorf("trunk_dbh.method = %q, want \"estimate\" — a value that supersedes a taped reading "+
			"and does not say it is an estimate is the laundering D7 forbids", body.TrunkDBH.Method)
	}
	// And on the bytes, because the badge is what makes the above defensible rather than merely
	// consistent: a projection that dropped `method` would leave both assertions above intact if
	// they only read the decoded struct's other fields.
	if !strings.Contains(h.readPublicly(t, tree).Body.String(), `"method":"estimate"`) {
		t.Errorf("the body does not carry `\"method\":\"estimate\"`:\n%s",
			h.readPublicly(t, tree).Body.String())
	}
}

// TestAVitalityOutsideTheRubricIsPublishedAsNothing.
//
// `Vitality` is the anchored 1–5 class of the PRODUCT §3 rubric. A `vitality 7` rendered on a public
// page would be a claim about a tree that the rubric cannot make, so the honest answer is silence.
func TestAVitalityOutsideTheRubricIsPublishedAsNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	good := uuid.New()
	h.applyItem(t, session.AccessToken, observationItem(good, 4, "2026-09-03T18:30:00Z"))
	if body := decodePublic(t, h.readPublicly(t, good)); body.Vitality == nil || body.Vitality.Rating != 4 {
		t.Fatalf("the control: vitality = %+v, want 4 — without it this test cannot tell a working "+
			"range check from a read that never publishes a rating", body.Vitality)
	}

	for _, bad := range []any{7, 0, -1, `"thriving"`} {
		tree := uuid.New()
		h.applyItem(t, session.AccessToken, observationItem(tree, bad, "2026-09-03T18:30:00Z"))
		if body := decodePublic(t, h.readPublicly(t, tree)); body.Vitality != nil {
			t.Errorf("a vitality of %v was published as %+v", bad, body.Vitality)
		}
	}
}

// TestAnUnknownMethodOrUnitIsPublishedAsNothing.
//
// An unknown method has no badge, so the number would draw as though its provenance were known —
// which is D7's whole distinction, laundered. An unknown unit is not a length at all.
func TestAnUnknownMethodOrUnitIsPublishedAsNothing(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	good := uuid.New()
	h.applyItem(t, session.AccessToken, measurementItemWithQuantity(good, "dbh", 64, "cm", "tape", "2026-07-02T09:12:00Z"))
	if body := decodePublic(t, h.readPublicly(t, good)); body.TrunkDBH == nil {
		t.Fatal("the control: a well-formed taped reading was not published, so this test could not " +
			"tell a working vocabulary check from a read that publishes nothing")
	}

	for _, bad := range []struct{ unit, method string }{
		{"cm", "guessed"}, {"cm", ""}, {"furlong", "tape"}, {"", "tape"},
	} {
		tree := uuid.New()
		h.applyItem(t, session.AccessToken,
			measurementItemWithQuantity(tree, "dbh", 64, bad.unit, bad.method, "2026-07-02T09:12:00Z"))
		if body := decodePublic(t, h.readPublicly(t, tree)); body.TrunkDBH != nil {
			t.Errorf("a reading in %q by %q was published as %+v", bad.unit, bad.method, body.TrunkDBH)
		}
	}
}

// ── What the page must never get ───────────────────────────────────────────────────────────────

// TestNoContributorIdentifierReachesThePublicRead is D11's guard, on the bytes.
//
// `contributions.payload` for a measurement is the whole of `TreeMeasurement` — `userID`,
// `deviceID`, `clientUUID`, `gpsAccuracyM`. A handler that echoed the payload, or a later one that
// added "who" to make attribution possible, publishes a contributor's identifiers and how accurately
// their phone believed it was standing at that tree. `User.publicAttribution` is false by default and
// cannot be turned on anywhere in the app (E100), and **this service has no column for it at all**
// (`users`, `001_initial.sql`), so there is no state of the world in which a name here is authorized.
func TestNoContributorIdentifierReachesThePublicRead(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	seedOneTreeWithEverything(t, h, session.AccessToken, publicTreeID)

	body := h.readPublicly(t, publicTreeID).Body.String()
	// The control: the guard must be looking at a body that has something in it.
	if !strings.Contains(body, `"rating": 4`) && !strings.Contains(body, `"rating":4`) {
		t.Fatalf("nothing was published, so every assertion below would pass vacuously:\n%s", body)
	}
	for name, forbidden := range map[string]string{
		"the contributor's user id":   publicContributorUser.String(),
		"the contributor's device id": publicContributorDevice.String(),
		"the GPS accuracy":            "4.5",
		"the check-in's free text":    publicNote,
		"a structure flag":            "lean",
		"the reported status":         "alive",
	} {
		if strings.Contains(body, forbidden) {
			t.Errorf("%s (%q) is in the public body:\n%s", name, forbidden, body)
		}
	}
}

// TestNoDayLevelTimestampReachesThePublicRead is the ruling's §4, on the bytes.
//
// The value's date is part of the value; the *day* is where the contributor was, and on a tree with
// one contributor a dated value is that person's movement record with nothing to infer.
func TestNoDayLevelTimestampReachesThePublicRead(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	seedOneTreeWithEverything(t, h, session.AccessToken, publicTreeID)

	body := h.readPublicly(t, publicTreeID).Body.String()
	// Calibrated in the same breath: the pattern must find a month, or the day check below is asking
	// nothing of a body that carries no dates at all.
	if !regexp.MustCompile(`\d{4}-\d{2}`).MatchString(body) {
		t.Fatalf("the body carries no month at all, so this guard would pass vacuously:\n%s", body)
	}
	if day := regexp.MustCompile(`\d{4}-\d{2}-\d{2}`).FindString(body); day != "" {
		t.Fatalf("the body carries a day-precision date %q; the public read publishes months:\n%s", day, body)
	}
}

// TestNoHazardRedirectReachesThePublicRead is DECISIONS §3.4's invariant test, which until this
// round had no subject.
//
// §3.4, verbatim: *"Hazard categories never produce a public note, never produce a community-visible
// record, and never auto-stale. No public surface query may be able to return a hazard-category note
// (enforced by a schema invariant test)."* PRODUCT's non-goals: *"Hazards becoming public notes |
// Never."* This is the first public surface query this system has ever had.
func TestNoHazardRedirectReachesThePublicRead(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	tree := uuid.New()
	const hazardText = "large limb hanging over the sidewalk"

	// **The payload carries a `vitality` as well as the hazard**, and that is not padding. The first
	// version of this test seeded a hazard with only a category and a note, so the red-proof — the
	// store's `kind` filter widened to admit `hazard_redirect` — left it **green**: the widened query
	// still found nothing to publish, because a hazard payload had nothing the projection reads. A
	// guard that goes green while the defect it names is present is this project's dominant
	// test-suite defect, and it was present here until the red-proof said so.
	h.applyItem(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "hazard_redirect", "tree_uuid": tree,
		"occurred_at": "2026-09-05T08:00:00Z",
		"payload": json.RawMessage(fmt.Sprintf(
			`{"clientUUID":%q,"treeID":%q,"category":"limb_failure","note":%q,"vitality":2,`+
				`"kind":"dbh","quantity":{"value":31,"unitEntered":"cm","method":"tape"}}`,
			uuid.New(), tree, hazardText)),
	})

	recorder := h.readPublicly(t, tree)
	if strings.Contains(recorder.Body.String(), hazardText) ||
		strings.Contains(recorder.Body.String(), "limb_failure") {
		t.Fatalf("a hazard reached a public surface:\n%s", recorder.Body.String())
	}
	// And the whole answer is the empty one: a hazard must not even make the tree look
	// contributed-to.
	assertEmptyPublicBody(t, recorder.Body.Bytes(), tree)
}

// TestWithheldKindsProduceTheEmptyAnswer walks the allow-list from the outside.
//
// Each withheld kind is recorded on its own tree and the public read must say nothing about that
// tree. It is the claim `withheldKinds` makes in a map, asked of the running service — a map is a
// statement and this is a measurement.
//
// The four kinds not walked here have their own payload contracts and their own handlers
// (`add_tree`, `favorite_toggle`, `photo_withdrawal`, `measurement_withdrawal`); the classification
// test covers them, and `TestAbsentEmptyAndWithdrawnAreOneAnswer` exercises the withdrawal.
func TestWithheldKindsProduceTheEmptyAnswer(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	for _, kind := range []string{"visit", "care_event", "private_reminder", "species_claim",
		"species_correction", "wrong_species_report", "never_existed_report",
		"species_review_dismissal", "record_review_dismissal", "photo_vote", "hazard_redirect"} {
		tree := uuid.New()
		// The payload deliberately carries everything the published kinds carry, so a projection
		// that stopped filtering on `kind` would have something to publish and this would catch it.
		h.applyItem(t, session.AccessToken, map[string]any{
			"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree,
			"occurred_at": "2026-09-05T08:00:00Z",
			"payload": json.RawMessage(fmt.Sprintf(
				`{"clientUUID":%q,"treeID":%q,"note":"a leak canary","vitality":5,"kind":"dbh",`+
					`"quantity":{"value":99,"unitEntered":"cm","method":"tape"}}`, uuid.New(), tree)),
		})
		recorder := h.readPublicly(t, tree)
		// **The canaries are spelled with their keys, and that is not fussiness.** The first
		// version of this looked for the bare string `99`, which matched the random tree UUID of
		// two of the eleven kinds and reported a leak on a body that was empty. A canary loose
		// enough to match a coincidence is a false red today and a false green tomorrow.
		for _, canary := range []string{"a leak canary", `"value":99`, `"rating":5`} {
			if strings.Contains(recorder.Body.String(), canary) {
				t.Errorf("%s reached the public read (%q):\n%s", kind, canary, recorder.Body.String())
			}
		}
		assertEmptyPublicBody(t, recorder.Body.Bytes(), tree)
	}
}

// ── Absent, empty and withdrawn ────────────────────────────────────────────────────────────────

// TestAbsentEmptyAndWithdrawnAreOneAnswer is the ruling's §9, asserted on the bytes in three
// directions at once.
//
// The brief for this round asked that a missing or fully-private tree be indistinguishable from a
// non-existent one, pointing at the photo read's `not_found`. The posture is right and `not_found`
// is the wrong instrument here: a photo id is a private handle, while a tree UUID is public by
// design — `SharePresentation.publicURL` makes it the last path segment of every share link screen
// 10 has ever produced. There is no tree existence to protect, and a 404 would *answer* the question
// that actually matters — does this tree have contributions? — rather than avoid it.
//
// So all three states get 200 and the same body, compared after replacing each tree's own id, which
// is the caller's own input echoed back and can say nothing the caller did not already know.
func TestAbsentEmptyAndWithdrawnAreOneAnswer(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)

	neverHeardOf := uuid.New()

	nothingPublishable := uuid.New()
	h.applyItem(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "visit", "tree_uuid": nothingPublishable,
		"occurred_at": "2026-09-05T08:00:00Z", "payload": json.RawMessage(`{}`),
	})

	withdrawn := uuid.New()
	item := measurementItemWithQuantity(withdrawn, "dbh", 64, "cm", "tape", "2026-07-02T09:12:00Z")
	var payload struct {
		ID uuid.UUID `json:"id"`
	}
	if err := json.Unmarshal(item["payload"].(json.RawMessage), &payload); err != nil {
		t.Fatal(err)
	}
	h.applyItem(t, session.AccessToken, item)
	// The control. Without it this passes on a public read that never published anything.
	if before := decodePublic(t, h.readPublicly(t, withdrawn)); before.TrunkDBH == nil {
		t.Fatal("precondition: the reading was not public before it was withdrawn, so this test " +
			"could not tell a working withdrawal from a broken read")
	}
	if result := withdrawReading(t, h, session.AccessToken, withdrawn, payload.ID); result.Status != "applied" {
		t.Fatalf("withdrawing: status = %q (%s)", result.Status, codeOf(result.Error))
	}

	states := map[string]uuid.UUID{
		"a tree this database has never heard of": neverHeardOf,
		"a tree with nothing publishable":         nothingPublishable,
		"a tree whose reading was withdrawn":      withdrawn,
	}
	normalized := map[string][]byte{}
	for name, tree := range states {
		recorder := h.readPublicly(t, tree)
		if recorder.Code != http.StatusOK {
			t.Fatalf("%s: status = %d, want 200 — a status code that varies with the state of the "+
				"community half is the oracle this design exists to remove", name, recorder.Code)
		}
		normalized[name] = bytes.ReplaceAll(recorder.Body.Bytes(), []byte(tree.String()), []byte("THE-ID"))
	}
	var reference string
	for name := range normalized {
		if reference == "" {
			reference = name
			continue
		}
		if !bytes.Equal(normalized[reference], normalized[name]) {
			t.Fatalf("%s and %s answer differently:\n%s\n%s",
				reference, name, normalized[reference], normalized[name])
		}
	}
}

// ── The route's posture ────────────────────────────────────────────────────────────────────────

// TestThePublicReadNeedsNoCredentialAndIgnoresABadOne.
//
// No login is W-1's ruling, and PRODUCT's non-goals name login walls on browse as a thing not to
// build. The second half matters as much: a route that *rejected* a stale bearer would be one the
// web could not call after somebody's session went bad.
func TestThePublicReadNeedsNoCredentialAndIgnoresABadOne(t *testing.T) {
	h := newHarness(t)

	if recorder := h.readPublicly(t, uuid.New()); recorder.Code != http.StatusOK {
		t.Fatalf("with no credential: status = %d, want 200", recorder.Code)
	}
	recorder := h.do(t, http.MethodGet, Prefix+"/public/trees/"+uuid.New().String(), "not-a-token", nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("with a bad credential: status = %d, want 200 — this route resolves no caller", recorder.Code)
	}
}

// TestAMalformedIDIsAValidationFailure. A syntax error is not an existence oracle, so it may say so.
func TestAMalformedIDIsAValidationFailure(t *testing.T) {
	h := newHarness(t)
	recorder := h.do(t, http.MethodGet, Prefix+"/public/trees/not-a-uuid", "", nil)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", recorder.Code)
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.ValidationFailed) {
		t.Fatalf("code = %q, want validation_failed", code)
	}
}

// TestThePublicReadBoundsDownstreamStaleness.
//
// Sixty seconds is the ceiling on how long a withdrawn value can survive downstream, chosen against
// the takedown route: an operator who removes something expects minutes. The assertion is on the
// number rather than on the header's presence, because `max-age=86400` would pass a presence check
// and hold a taken-back value for a day.
func TestThePublicReadBoundsDownstreamStaleness(t *testing.T) {
	h := newHarness(t)
	// The literal is spelled out on both sides. Printing `publicCacheControl` in the failure message
	// made the red-proof read `Cache-Control = "public, max-age=86400", want "public,
	// max-age=86400"` — a tautology, because the message quoted the very constant that had been
	// changed. A failure message that cannot name the answer is not evidence of anything.
	const want = "public, max-age=60"
	got := h.readPublicly(t, uuid.New()).Header().Get("Cache-Control")
	if got != want {
		t.Fatalf("Cache-Control = %q, want %q — sixty seconds is the ceiling on how long a "+
			"withdrawn value may survive downstream", got, want)
	}
}

// TestThePublicReadHasItsOwnBudget is the denial of service written by hand, guarded against.
//
// The web is server-side rendered, so every reader in the world arrives from one address. On the
// device budget — burst 60, one token a second — that throttles the whole site to a page a second,
// which is `clientKey`'s own warning arriving from the other direction.
func TestThePublicReadHasItsOwnBudget(t *testing.T) {
	h := newHarness(t)
	if h.server.readLimiter == h.server.limiter {
		t.Fatal("the public read shares the device limiter; a flood on either would spend the other's tokens")
	}
	tree := uuid.New()
	for i := 0; i < 100; i++ {
		if recorder := h.readPublicly(t, tree); recorder.Code != http.StatusOK {
			t.Fatalf("request %d was refused with %d; the public read is on a phone's budget",
				i+1, recorder.Code)
		}
	}
}

// TestThePublicReadIsStillLimited is the other half. A budget that refuses nothing is not a budget.
func TestThePublicReadIsStillLimited(t *testing.T) {
	h := newHarness(t)
	h.server.readLimiter = ratelimit.NewWithBudget(3, time.Hour)
	h.handler = h.server.Handler()

	tree := uuid.New()
	for i := 0; i < 3; i++ {
		if recorder := h.readPublicly(t, tree); recorder.Code != http.StatusOK {
			t.Fatalf("request %d of the burst was refused", i+1)
		}
	}
	recorder := h.readPublicly(t, tree)
	if recorder.Code != http.StatusTooManyRequests {
		t.Fatalf("status after the burst = %d, want 429", recorder.Code)
	}
	if code := decodeEnvelope(t, recorder).Error.Code; code != string(apierr.RateLimited) {
		t.Fatalf("code = %q, want rate_limited", code)
	}
}

// ── The guards that read a declaration rather than restating it ────────────────────────────────

// TestEveryContributionKindIsClassified is the allow-list's mechanism.
//
// `contributions.kind` is a closed CHECK vocabulary and it has widened twice already (002, 004). A
// kind in neither `publicKinds` nor `withheldKinds` fails here, so the next author to widen it has
// to decide whether it is public — the ordering an allow-list buys and a deny-list does not. The
// vocabulary is read out of the migrations rather than restated, for the reason `golden_test.go`
// reads `TreePlacement` off `Tree.swift`: a test that declares its own answer proves only that the
// author transcribed it.
//
// ── This guard was green with the defect present, and that is why it reads a directory ─────────
//
// Until the adversarial review of this round's PR it read **one hardcoded path**,
// `../../migrations/004_measurement_withdrawal_kind.sql`. `loadMigrations`
// (`internal/store/migrate.go`) applies *every* `.sql` in that directory, and an applied migration
// is frozen (`migrations/migrations.go`) — so the only way an eighteenth kind can arrive is in a
// **new file**, which is exactly how the previous two arrivals came (002 added ten, 004 added one).
// The reviewer added an eighteenth kind as `005_*.sql` and this test stayed green with an
// unclassified kind live in the schema, while the control — the same kind added to 004 — went red.
// Guards that are green when the defect is present are this project's dominant test-suite defect
// class, and this was one.
//
// It now reads the vocabulary the way the server does: every migration, in version order, last
// declaration wins. `TestTheLiveSchemaAgreesWithTheMigrationFiles` asks the running database the
// same question through a different instrument, so a spelling this extractor cannot parse is caught
// by something that never parses SQL at all.
func TestEveryContributionKindIsClassified(t *testing.T) {
	declared, source := contributionKindsFromMigrations(t, "../../migrations")
	for _, kind := range declared {
		_, withheld := withheldKinds[kind]
		if !publicKinds[kind] && !withheld {
			t.Errorf("`%s` is a contribution kind (declared in %s) and the public read has not "+
				"decided about it. Add it to publicKinds with a ruling behind it, or to "+
				"withheldKinds with the reason.", kind, source)
		}
		if publicKinds[kind] && withheld {
			t.Errorf("`%s` is classified both ways", kind)
		}
	}
	for kind := range publicKinds {
		if !slices.Contains(declared, kind) {
			t.Errorf("the public read publishes `%s`, which is not a contribution kind", kind)
		}
	}
	for kind := range withheldKinds {
		if !slices.Contains(declared, kind) {
			t.Errorf("withheldKinds names `%s`, which is not a contribution kind", kind)
		}
	}
	// The count, asserted **after** the classification rather than before it, so an author who adds
	// an eighteenth kind reads the sentence about their kind first and this one as context. Kept
	// because it is the extractor's own calibration against the live tree: a reader that silently
	// began matching nothing would leave the loops above with nothing to say.
	if len(declared) != 17 {
		t.Errorf("read %d kinds from %s, want 17 — either the vocabulary grew (classify the new "+
			"one above) or the extractor moved: %v", len(declared), source, declared)
	}
	// And the decision itself, pinned: exactly two kinds are public. Widening this is a privacy
	// decision and must arrive with the ruling that took it, not as a still-passing test.
	if len(publicKinds) != 2 {
		t.Fatalf("the public read publishes %d kinds, want 2 (measurement, observation)", len(publicKinds))
	}
}

// TestSyncAcceptsEveryDeclaredContributionKind closes the third restatement of the same vocabulary.
//
// `syncKinds` (`sync.go`) is a hand-written copy of the CHECK, and until now nothing forced it to
// move when the CHECK moved. The failure mode is quiet in one direction and loud in the other: a
// kind in the CHECK but not in `syncKinds` is refused at ingest with `validation_failed` — which is
// how every one of 002's ten behaved before that round noticed — and a kind in `syncKinds` but not
// in the CHECK is a constraint violation at insert. Neither should be discoverable in production.
//
// Raised by the same review as B1, as the related finding it did not require fixing. It is three
// assertions on an extractor this file already has to own, so it is fixed here.
func TestSyncAcceptsEveryDeclaredContributionKind(t *testing.T) {
	declared, source := contributionKindsFromMigrations(t, "../../migrations")
	for _, kind := range declared {
		if !syncKinds[kind] {
			t.Errorf("`%s` is a contribution kind (declared in %s) and POST /sync refuses it; "+
				"the phone cannot deliver a row the schema accepts", kind, source)
		}
	}
	for kind := range syncKinds {
		if !slices.Contains(declared, kind) {
			t.Errorf("POST /sync accepts `%s`, which the CHECK does not; the insert would violate "+
				"the constraint", kind)
		}
	}
}

// TestTheLiveSchemaAgreesWithTheMigrationFiles reads the vocabulary from the running database.
//
// The two guards above parse SQL with a regular expression, which can only ever be as good as the
// spellings its author thought of. This one parses nothing: it asks Postgres, after every migration
// has been applied, what the constraint on `contributions.kind` actually is. If a future migration
// declares the vocabulary in a form the extractor cannot read, the extractor's answer and this one
// stop agreeing and the disagreement is the failure.
//
// Note Postgres does not store `kind IN (…)`; it normalizes to `kind = ANY (ARRAY[…])`, so the
// spelling read back here is genuinely not the spelling in the file.
func TestTheLiveSchemaAgreesWithTheMigrationFiles(t *testing.T) {
	h := newHarness(t)

	var definitions []string
	rows, err := h.store.Pool().Query(context.Background(), `
		SELECT pg_get_constraintdef(c.oid)
		  FROM pg_constraint c
		  JOIN pg_class t ON t.oid = c.conrelid
		 WHERE t.relname = 'contributions'
		   AND c.contype = 'c'
	`)
	if err != nil {
		t.Fatalf("reading pg_constraint: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var definition string
		if err := rows.Scan(&definition); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(definition, "kind") {
			definitions = append(definitions, definition)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if len(definitions) != 1 {
		t.Fatalf("found %d CHECK constraints mentioning `kind` on contributions, want exactly 1: %v",
			len(definitions), definitions)
	}

	var live []string
	for _, match := range sqlQuotedValue.FindAllStringSubmatch(definitions[0], -1) {
		live = append(live, match[1])
	}
	sort.Strings(live)

	declared, source := contributionKindsFromMigrations(t, "../../migrations")
	sort.Strings(declared)
	if !slices.Equal(live, declared) {
		t.Fatalf("the live schema's kinds are %v and %s declares %v — one of the two instruments "+
			"is wrong, and the extractor is the one that parses SQL with a regexp", live, source, declared)
	}
	for _, kind := range live {
		_, withheld := withheldKinds[kind]
		if !publicKinds[kind] && !withheld {
			t.Errorf("`%s` is a contribution kind in the live schema and the public read has not "+
				"decided about it", kind)
		}
	}
}

// TestContributionKindExtractorIsCalibrated proves the reader against an answer already known.
// Without it the guards above pass vacuously on an extractor that matches nothing.
//
// The specimen directory is the shape of the real one and each file is there for a case that has
// bitten: 001 declares the vocabulary **inline in a CREATE TABLE** (the real 001 does), 002 replaces
// it through `ADD CONSTRAINT` (the real 002 and 004 do), 003 touches something else entirely and
// must not blank the answer, and 004 carries the pattern **inside a comment**, which must not be
// mistaken for a declaration. The answer is 002's, because that is the last file that declares it —
// and it is deliberately *not* the first file's and *not* the last file's, so a reader that took
// either would be caught.
func TestContributionKindExtractorIsCalibrated(t *testing.T) {
	dir := t.TempDir()
	specimens := map[string]string{
		"001_initial.sql": `
CREATE TABLE contributions (
    client_uuid   UUID PRIMARY KEY,
    kind          TEXT NOT NULL CHECK (kind IN (
                      'visit', 'observation')),
    tree_uuid     UUID NOT NULL
);
`,
		"002_more_kinds.sql": `
ALTER TABLE contributions DROP CONSTRAINT contributions_kind_check;

ALTER TABLE contributions ADD CONSTRAINT contributions_kind_is_known CHECK (kind IN (
    'visit', 'observation',
    -- a comment mentioning 'not_a_kind' in prose
    'care_event'
));

CREATE INDEX something ON contributions (upper(payload ->> 'id')) WHERE kind = 'measurement';
`,
		"003_unrelated.sql": `
ALTER TABLE photos ADD COLUMN idempotency_key TEXT;
`,
		"004_prose_only.sql": `
-- This file talks about the constraint without declaring it. A reader that matched prose would
-- take CHECK (kind IN ('never_a_kind')) from this line and answer with it.
ALTER TABLE contributions ADD COLUMN moderation_note TEXT;
`,
		"README.md": "not a migration",
	}
	for name, body := range specimens {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	got, source := contributionKindsFromMigrations(t, dir)
	want := []string{"visit", "observation", "care_event"}
	if !slices.Equal(got, want) {
		t.Fatalf("the extractor read %v from a directory whose answer is %v — it must take the "+
			"*last* file that declares the vocabulary, skip a commented value, stop at the CHECK's "+
			"close so the trailing index's 'measurement' is not a kind, and not be fooled by prose",
			got, want)
	}
	if source != "002_more_kinds.sql" {
		t.Fatalf("the extractor says the vocabulary comes from %q, want 002_more_kinds.sql — a "+
			"guard that names the wrong file sends the next author to the wrong place", source)
	}
}

var sqlQuotedValue = regexp.MustCompile(`'([a-z_]+)'`)

// migrationFilename is `internal/store/migrate.go`'s own pattern. The runner refuses a file this
// does not match, so a file this skips is a file that never runs.
var migrationFilename = regexp.MustCompile(`^(\d{3})_[a-z0-9_]+\.sql$`)

// kindCheckBlock matches both spellings this vocabulary has ever been declared in: 001's inline
// column CHECK inside `CREATE TABLE contributions`, and 002's and 004's `ADD CONSTRAINT`. It is
// non-greedy so it stops at the CHECK's own close rather than running on to the next statement's.
var kindCheckBlock = regexp.MustCompile(`(?s)CHECK \(kind IN \((.*?)\)\)`)

// contributionKindsFromMigrations reads the CHECK's vocabulary out of a migrations directory the
// way `loadMigrations` reads the directory itself: every `NNN_name.sql`, in version order. The last
// file that declares the vocabulary wins, because an applied migration is frozen and a widening can
// therefore only arrive as a new file.
//
// It returns the values and the name of the file they came from, so a failure sends the next author
// to the file that actually decides it rather than to whichever one this test was written against.
func contributionKindsFromMigrations(t *testing.T, dir string) ([]string, string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("reading %s: %v — this guard fails rather than skipping", dir, err)
	}

	type numbered struct {
		Version int
		Name    string
	}
	var files []numbered
	for _, entry := range entries {
		match := migrationFilename.FindStringSubmatch(entry.Name())
		if match == nil {
			continue
		}
		version, err := strconv.Atoi(match[1])
		if err != nil {
			t.Fatalf("%s: %v", entry.Name(), err)
		}
		files = append(files, numbered{Version: version, Name: entry.Name()})
	}
	if len(files) == 0 {
		t.Fatalf("no NNN_name.sql files in %s; the vocabulary would be read from nothing", dir)
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Version < files[j].Version })

	var kinds []string
	var source string
	for _, file := range files {
		body, err := os.ReadFile(filepath.Join(dir, file.Name))
		if err != nil {
			t.Fatalf("reading %s: %v", file.Name, err)
		}
		// Whole-line SQL comments come out first, so neither a decoy in a file's prose header nor a
		// commented-out value inside the block can be read as a declaration. Only lines that *begin*
		// with `--` go, which is what the previous single-file reader did inside the block.
		var live [][]byte
		for _, line := range bytes.Split(body, []byte("\n")) {
			if bytes.HasPrefix(bytes.TrimSpace(line), []byte("--")) {
				continue
			}
			live = append(live, line)
		}
		blocks := kindCheckBlock.FindAllSubmatch(bytes.Join(live, []byte("\n")), -1)
		if len(blocks) == 0 {
			continue
		}
		// The last block in the last file that has one. Within a file the later statement is the
		// one that survives, for the same reason the later file is.
		var declared []string
		for _, match := range sqlQuotedValue.FindAllSubmatch(blocks[len(blocks)-1][1], -1) {
			declared = append(declared, string(match[1]))
		}
		kinds, source = declared, file.Name
	}
	if source == "" {
		t.Fatalf("no `CHECK (kind IN (…))` in any migration under %s", dir)
	}
	return kinds, source
}

// TestMeasurementMethodMatchesTheSwiftVocabulary — a reading whose method is outside the vocabulary
// is not published, so the vocabulary had better be the one Swift declares. A method this service
// did not recognize would silently drop every reading taken with it; a method Swift does not declare
// would be published with no badge behind it, drawing an unknown provenance as a known one.
func TestMeasurementMethodMatchesTheSwiftVocabulary(t *testing.T) {
	assertVocabularyMatches(t, "../../../Cypress/Core/Units/Quantity.swift",
		"MeasurementMethod", 4, measurementMethods)
}

// TestLengthUnitMatchesTheSwiftVocabulary — same rule: a number whose unit is unknown is not a length.
func TestLengthUnitMatchesTheSwiftVocabulary(t *testing.T) {
	assertVocabularyMatches(t, "../../../Cypress/Core/Units/Quantity.swift",
		"LengthUnit", 5, lengthUnits)
}

func assertVocabularyMatches(t *testing.T, path, name string, want int, accepted map[string]bool) {
	t.Helper()
	declared := swiftEnumRawValues(t, path, name)
	if len(declared) != want {
		t.Fatalf("read %d raw values from %s, want %d — the extractor or the enum moved: %v",
			len(declared), name, want, declared)
	}
	for _, value := range declared {
		if !accepted[value] {
			t.Errorf("%s declares %q and the public read will not publish a value carrying it", name, value)
		}
	}
	for value := range accepted {
		if !slices.Contains(declared, value) {
			t.Errorf("the public read accepts %q, which is not a %s raw value", value, name)
		}
	}
}

// TestVitalityRatingsMatchTheSwiftRubric reads the *Int*-backed enum, which the existing extractor
// cannot: `Vitality` is `public enum Vitality: Int`, the anchored 1–5 class of the PRODUCT §3 rubric.
func TestVitalityRatingsMatchTheSwiftRubric(t *testing.T) {
	declared := swiftIntEnumRawValues(t, "../../../Cypress/Core/Rubric/Vitality.swift", "Vitality")
	if len(declared) != 5 {
		t.Fatalf("read %d raw values from Vitality, want 5: %v", len(declared), declared)
	}
	for _, rating := range declared {
		if !vitalityRatings[rating] {
			t.Errorf("Vitality declares %d and the public read will not publish it", rating)
		}
	}
	for rating := range vitalityRatings {
		if !slices.Contains(declared, rating) {
			t.Errorf("the public read accepts %d, which is not a Vitality raw value", rating)
		}
	}
}

// TestSwiftIntEnumExtractorIsCalibrated proves the new reader against a known answer, including the
// two ways it could be wrong: bleeding into a neighbouring enum, and matching a `switch`'s cases.
func TestSwiftIntEnumExtractorIsCalibrated(t *testing.T) {
	specimen := `
public enum Other: Int, Codable {
    case one = 1
}

public enum Vitality: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    /// A doc comment mentioning case zero = 0 in prose.
    case severeDecline = 1
    case poor = 2

    public var label: String {
        switch self {
        case .severeDecline: return "Severe decline"
        case .poor: return "Poor"
        }
    }
}
`
	path := filepath.Join(t.TempDir(), "specimen.swift")
	if err := os.WriteFile(path, []byte(specimen), 0o644); err != nil {
		t.Fatal(err)
	}
	got := swiftIntEnumRawValues(t, path, "Vitality")
	if !slices.Equal(got, []int{1, 2}) {
		t.Fatalf("the extractor read %v from a specimen whose answer is [1 2]", got)
	}
	if other := swiftIntEnumRawValues(t, path, "Other"); !slices.Equal(other, []int{1}) {
		t.Fatalf("the extractor read %v for Other", other)
	}
}

var swiftIntCaseLine = regexp.MustCompile(`(?m)^\s*case\s+\w+\s*=\s*(\d+)`)

func swiftIntEnumRawValues(t *testing.T, path, name string) []int {
	t.Helper()
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v — this guard fails rather than skipping", path, err)
	}
	pattern := fmt.Sprintf(`(?s)public enum %s: Int[^{]*\{(.*?)\n\}`, name)
	block := regexp.MustCompile(pattern).FindSubmatch(source)
	if block == nil {
		t.Fatalf("did not find `public enum %s: Int` in %s", name, path)
	}
	var values []int
	for _, match := range swiftIntCaseLine.FindAllSubmatch(block[1], -1) {
		var parsed int
		if _, err := fmt.Sscanf(string(match[1]), "%d", &parsed); err != nil {
			t.Fatal(err)
		}
		values = append(values, parsed)
	}
	return values
}

// TestPublicBodyIsSnakeCaseThroughout holds this response on the documented side of `wire.go`'s
// split.
//
// The rule is: a payload that reconstructs a client-owned Swift type speaks that type's synthesized
// camelCase names; everything else speaks the API's snake_case. Nothing decodes this body into a
// Swift type — its consumer is the TypeScript web app — so it is snake_case, and an author who
// copies a key from `TreeMeasurement` finds out here rather than in a fixture the web depends on.
func TestPublicBodyIsSnakeCaseThroughout(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	seedOneTreeWithEverything(t, h, session.AccessToken, publicTreeID)

	keys := allJSONKeys(t, h.readPublicly(t, publicTreeID).Body.Bytes())
	if len(keys) < 8 {
		t.Fatalf("found %d keys in the body, which is fewer than it has: %v", len(keys), keys)
	}
	snake := regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
	// Calibrated first: the same pattern must reject a camelCase key, or it asserts nothing.
	if snake.MatchString("unitEntered") {
		t.Fatal("the snake_case pattern accepts a camelCase key; this guard proves nothing")
	}
	for _, key := range keys {
		if !snake.MatchString(key) {
			t.Errorf("the public body carries %q, which is not snake_case (wire.go's split)", key)
		}
	}
}

func allJSONKeys(t *testing.T, body []byte) []string {
	t.Helper()
	var decoded any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatal(err)
	}
	var keys []string
	var walk func(any)
	walk = func(node any) {
		switch typed := node.(type) {
		case map[string]any:
			for key, value := range typed {
				keys = append(keys, key)
				walk(value)
			}
		case []any:
			for _, value := range typed {
				walk(value)
			}
		}
	}
	walk(decoded)
	sort.Strings(keys)
	return keys
}

// ── Small helpers ──────────────────────────────────────────────────────────────────────────────

type publicBody struct {
	TreeUUID          uuid.UUID `json:"tree_uuid"`
	VerificationState string    `json:"verification_state"`
	Vitality          *struct {
		Rating        int    `json:"rating"`
		ObservedMonth string `json:"observed_month"`
	} `json:"vitality"`
	Height   *publicReading `json:"height"`
	TrunkDBH *publicReading `json:"trunk_dbh"`
}

func decodePublic(t *testing.T, recorder *httptest.ResponseRecorder) publicBody {
	t.Helper()
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var body publicBody
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("body is not a public read: %v (%s)", err, recorder.Body.String())
	}
	return body
}

func assertEmptyPublicBody(t *testing.T, raw []byte, tree uuid.UUID) {
	t.Helper()
	var body publicBody
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatal(err)
	}
	if body.TreeUUID != tree {
		t.Errorf("tree_uuid = %s, want the id that was asked for", body.TreeUUID)
	}
	if body.Vitality != nil || body.Height != nil || body.TrunkDBH != nil {
		t.Errorf("the body is not the empty answer: %s", raw)
	}
}
