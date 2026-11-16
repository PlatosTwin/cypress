package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── ROADMAP 144's golden fixtures (server/testdata/README.md) ─────────────────────────────────
//
// New files only: every existing fixture keeps its keys and its list of history events, so no Swift
// test changes its count. Each file is written by the real handler against Postgres, over the golden
// world (`seedGoldenWorld`), with every id and time fixed.

var (
	goldenReportFlag   = uuid.MustParse("4e7a2c10-9b3d-4f5e-8a6c-1d2e3f4a5b01")
	goldenSpeciesThree = uuid.MustParse("7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7e")
)

// TestTreeProfileCommunityReportedGolden is tree A as its adder sees it after a sharing account
// reported its species: `species_reported` true, and the report's `flagID` for "Keep the species".
func TestTreeProfileCommunityReportedGolden(t *testing.T) {
	h := newHarness(t)
	adder := seedGoldenWorld(t, h)
	reporter := signInAs(t, h, "sp.golden.reporter", nil, accepted())
	item := reportItem(goldenTreeA, goldenReportFlag, &goldenSpecies)
	atClock(h, goldenTime("2026-09-24T12:00:00Z"), func() {
		mustApply(t, h.syncOne(t, reporter.AccessToken, item), "the report")
	})
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+goldenTreeA.String(), adder.AccessToken, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "tree_profile_community_reported.json", recorder.Body.Bytes())
}

// TestTreeProfileCommunityNamedByYouGolden is tree B, which its adder left unnamed, as the sharing
// account that named it sees it: the species, and `species_named_by_you` true.
func TestTreeProfileCommunityNamedByYouGolden(t *testing.T) {
	h := newHarness(t)
	seedGoldenWorld(t, h)
	namer := signInAs(t, h, "sp.golden.namer", nil, accepted())
	atClock(h, goldenTime("2026-09-22T10:00:00Z"), func() {
		mustApply(t, h.syncOne(t, namer.AccessToken,
			speciesItem("species_claim", goldenTreeB, goldenSpeciesThree, goldenTime("2026-09-22T10:00:00Z"))), "the naming")
	})
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+goldenTreeB.String(), namer.AccessToken, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "tree_profile_community_named_by_you.json", recorder.Body.Bytes())
}

// TestTreeHistoryContributorGolden is tree B's history as its namer reads it, with one event of each
// new kind and one of the adder's: a contributor named it, the namer corrected it, the operator
// corrected it, and the adder corrected it. Seeded as the writers record them (`after.by`, the
// actor columns), with fixed ids, because the writers mint event ids.
func TestTreeHistoryContributorGolden(t *testing.T) {
	h := newHarness(t)
	adder := seedGoldenWorld(t, h)
	namer := signInAs(t, h, "sp.golden.history.namer", nil, accepted())
	insert := func(id, kind string, actor *uuid.UUID, at string, before *uuid.UUID, after uuid.UUID, by string) {
		t.Helper()
		execSQL(t, h, `
			INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at, before, after, in_public_history)
			VALUES ($1, $2, $3, $4, $5, $5,
			        CASE WHEN $6::uuid IS NULL THEN NULL ELSE jsonb_build_object('species_id', $6::uuid) END,
			        jsonb_build_object('species_id', $7::uuid, 'by', $8::text), true)
		`, uuid.MustParse(id), goldenTreeB, kind, actor, goldenTime(at), before, after, by)
	}
	insert("a0d4e5f6-2222-4c2d-8e3f-000000000001", "species_named", &namer.UserID, "2026-09-22T10:00:00Z", nil, goldenSpecies, "contributor")
	insert("a0d4e5f6-2222-4c2d-8e3f-000000000002", "species_corrected", &namer.UserID, "2026-09-23T10:00:00Z", &goldenSpecies, goldenSpeciesTwo, "contributor")
	insert("a0d4e5f6-2222-4c2d-8e3f-000000000003", "species_corrected", nil, "2026-09-24T10:00:00Z", &goldenSpeciesTwo, goldenSpeciesThree, "operator")
	insert("a0d4e5f6-2222-4c2d-8e3f-000000000004", "species_corrected", &adder.UserID, "2026-09-25T10:00:00Z", &goldenSpeciesThree, goldenSpecies, "adder")

	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+goldenTreeB.String()+"/history", namer.AccessToken, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "tree_history_contributor.json", recorder.Body.Bytes())
}

// ── The request fixture ────────────────────────────────────────────────────────────────────────

// readSpeciesReportFixture is `server/testdata/sync_wrong_species_report.json` with its account id
// replaced by the signed-in reporter's, because the service mints account ids. The fixture's id is
// a placeholder that appears exactly twice (`user_id` and `attribution.userID`); the count is
// checked so a fixture edit cannot make the substitution silently partial.
func readSpeciesReportFixture(t *testing.T, userID uuid.UUID) []byte {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/sync_wrong_species_report.json")
	if err != nil {
		t.Fatalf("reading the fixture: %v", err)
	}
	placeholder := []byte("A0B1C2D3-E4F5-4A6B-8C7D-9E0F1A2B3C4D")
	if n := bytes.Count(raw, placeholder); n != 2 {
		t.Fatalf("the fixture's account id appears %d times, want 2", n)
	}
	return bytes.ReplaceAll(raw, placeholder, []byte(userID.String()))
}

type speciesReportFixture struct {
	Items []struct {
		TreeUUID uuid.UUID `json:"tree_uuid"`
		Payload  struct {
			FlagID            uuid.UUID `json:"flagID"`
			DisputedSpeciesID uuid.UUID `json:"disputedSpeciesID"`
		} `json:"payload"`
	} `json:"items"`
}

// TestTheWrongSpeciesReportFixtureMarksTheSpecies posts the phone half's report, bytes unchanged
// but for the account id, and the species it disputes is marked for everyone. Its control: the same
// bytes disputing another species mark nothing, so the test cannot pass on a handler that ignored
// `disputedSpeciesID`.
func TestTheWrongSpeciesReportFixtureMarksTheSpecies(t *testing.T) {
	for _, disputesTheSpeciesInForce := range []bool{true, false} {
		h := newHarness(t)
		reporter := signInAs(t, h, "sp.fixture.reporter", nil, accepted())
		raw := readSpeciesReportFixture(t, reporter.UserID)
		var fixture speciesReportFixture
		if err := json.Unmarshal(raw, &fixture); err != nil || len(fixture.Items) != 1 {
			t.Fatalf("the fixture is not one item of the shape this test reads: %v", err)
		}
		item := fixture.Items[0]

		adder := signInAs(t, h, "sp.fixture.adder", nil, accepted())
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(item.TreeUUID, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")
		inForce := item.Payload.DisputedSpeciesID
		if !disputesTheSpeciesInForce {
			inForce = uuid.New()
		}
		mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", item.TreeUUID, inForce, time.Now())), "naming")

		mustApply(t, postRaw(t, h, reporter.AccessToken, raw), "the fixture")
		view := speciesViewOf(t, h, adder.AccessToken, item.TreeUUID)
		if view.Reported != disputesTheSpeciesInForce {
			t.Fatalf("disputing the species in force = %v: reported = %v", disputesTheSpeciesInForce, view.Reported)
		}
		if disputesTheSpeciesInForce && (view.FlagID == nil || *view.FlagID != item.Payload.FlagID) {
			t.Fatalf("the adder is served flag %v, want the fixture's %s", view.FlagID, item.Payload.FlagID)
		}
	}
}
