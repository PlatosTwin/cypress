package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── ROADMAP 144, the review's findings (F1, F2, F3, F5) ───────────────────────────────────────

// TestAnAccountsOlderCorrectionDoesNotUndoItsSignedOutNewerOne is F1, in the reviewer's steps: the
// phone adds and names a tree signed out, corrects it to Y (two minutes after base), signs in with
// that device, and then an older correction X (one minute after base) drains under the account. Y
// must stand, as it does on main. Red if `supersededByOwnStatement` sees only the account's own acts.
func TestAnAccountsOlderCorrectionDoesNotUndoItsSignedOutNewerOne(t *testing.T) {
	h := newHarness(t)
	device := uuid.New()
	signedOut := h.registerDeviceToken(t, device)
	tree := uuid.New()
	base := time.Now().Add(-time.Hour)
	mustApply(t, h.syncOne(t, signedOut, addTreeAt(tree, ctLat, ctLon, base)), "the signed-out add")
	a, x, y := uuid.New(), uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, signedOut, speciesItem("species_claim", tree, a, base)), "naming A")
	mustApply(t, h.syncOne(t, signedOut, speciesItem("species_correction", tree, y, base.Add(2*time.Minute))), "correcting to Y")

	account := signInAs(t, h, "sp.f1.adder", &device, accepted())
	if state := stateOf(t, h, tree); state.UserID == nil || *state.UserID != account.UserID {
		t.Fatalf("fixture: the sign-in did not move the tree to the account: %+v", state)
	}
	mustApply(t, h.syncOne(t, account.AccessToken, speciesItem("species_correction", tree, x, base.Add(time.Minute))),
		"the older correction X, drained under the account")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, y) {
		t.Fatalf("the species is %v; the account's older correction X undid its newer signed-out Y %s", got, y)
	}
}

// TestAKeepClearsOnlyTheReportsTheAdderSaw is F2's probe: report 1, the adder is served its flag,
// report 2 lands, and the adder's keep naming report 1 must leave report 2 counting. The adder is
// then served report 2's flag, and a keep naming it clears the rest.
func TestAKeepClearsOnlyTheReportsTheAdderSaw(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.f2.adder")
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
	first := signInAs(t, h, "sp.f2.first", nil, accepted()).AccessToken
	second := signInAs(t, h, "sp.f2.second", nil, accepted()).AccessToken
	third := h.registerDeviceToken(t, uuid.New())

	f1, f2 := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, first, reportItem(tree, f1, nil)), "report 1")
	if served := speciesViewOf(t, h, adder.AccessToken, tree).FlagID; served == nil || *served != f1 {
		t.Fatalf("fixture: the adder is served %v, want report 1's flag %s", served, f1)
	}
	mustApply(t, h.syncOne(t, second, reportItem(tree, f2, nil)), "report 2, after the adder looked")
	mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, f1)), "the adder's keep naming report 1")

	view := speciesViewOf(t, h, adder.AccessToken, tree)
	if !view.Reported || !speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("a keep naming report 1 cleared report 2, which the adder never saw")
	}
	if view.FlagID == nil || *view.FlagID != f2 {
		t.Fatalf("after the keep the adder is served %v, want report 2's flag %s", view.FlagID, f2)
	}
	mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, f2)), "the adder's keep naming report 2")
	if speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("a keep naming the newest report left the species marked")
	}
}

// TestAKeepNamingNoReportChangesNothing is F2's other case: a flag no counting report carries (an
// older build's local flag, or nothing at all) is answered `applied` and clears nothing.
func TestAKeepNamingNoReportChangesNothing(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.f2b.adder")
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
	reporter := signInAs(t, h, "sp.f2b.reporter", nil, accepted()).AccessToken
	mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), "a report")

	mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, uuid.New())), "a keep naming an unknown flag")
	noFlag := keepItem(tree, uuid.New())
	noFlag["payload"] = jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree})
	mustApply(t, h.syncOne(t, adder.AccessToken, noFlag), "a keep with no flag")
	if !speciesViewOf(t, h, h.registerDeviceToken(t, uuid.New()), tree).Reported {
		t.Fatal("a keep naming no counting report cleared the mark")
	}
}

// TestNamedByYouIsFalseOnceTheNamerStopsSharing is F3: the profile says "you may correct this" only
// while the correction would apply. A namer who later declines the license is told false, and the
// correction they would send indeed changes nothing.
func TestNamedByYouIsFalseOnceTheNamerStopsSharing(t *testing.T) {
	h := newHarness(t)
	_, tree := publishedTree(t, h, "sp.f3.adder")
	namer := signInAs(t, h, "sp.f3.namer", nil, accepted())
	named := uuid.New()
	mustApply(t, h.syncOne(t, namer.AccessToken, speciesItem("species_claim", tree, named, time.Now())), "naming")
	if !speciesViewOf(t, h, namer.AccessToken, tree).NamedByYou {
		t.Fatal("control: the sharing namer is not told the naming is theirs")
	}

	declined := signInAs(t, h, "sp.f3.namer", nil, nil)
	if declined.UserID != namer.UserID {
		t.Fatal("fixture: the second sign-in is a different account")
	}
	if speciesViewOf(t, h, declined.AccessToken, tree).NamedByYou {
		t.Fatal("a namer who stopped sharing is still offered the correction")
	}
	mustApply(t, h.syncOne(t, declined.AccessToken, speciesItem("species_correction", tree, uuid.New(), time.Now())), "their correction")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, named) {
		t.Fatalf("a namer who stopped sharing corrected the species to %v", got)
	}
}

// TestAClearNeverStampsItselfBeforeAReportItCameAfter is F5, made deterministic with the store's
// clock: a report recorded at T2, then an operator clear whose own clock reads T1 < T2 (it started
// earlier and waited for the lock). The clear came after the report, so the report must not count.
// Red if `clearSpeciesReports` takes the earlier of the two moments. The reverse order is the
// report's own guard: a clear at T3, then a report whose clock reads T2 < T3, must count.
func TestAClearNeverStampsItselfBeforeAReportItCameAfter(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.f5.adder")
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
	reporter := signInAs(t, h, "sp.f5.reporter", nil, accepted()).AccessToken
	third := h.registerDeviceToken(t, uuid.New())
	clear := func() {
		t.Helper()
		recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+"/species-reports/clear", operatorToken, nil)
		if recorder.Code != http.StatusOK {
			t.Fatalf("the operator's clear answered %d: %s", recorder.Code, recorder.Body.String())
		}
	}
	t1, t2, t3 := time.Now().Add(time.Hour), time.Now().Add(2*time.Hour), time.Now().Add(3*time.Hour)

	atClock(h, t2, func() { mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), "a report at T2") })
	atClock(h, t1, clear)
	if speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("a clear stamped at its own earlier clock left a report it came after counting")
	}

	atClock(h, t3, clear)
	atClock(h, t2, func() {
		mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), "a report at T2 after a clear at T3")
	})
	if !speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("a report that came after a clear does not count because its clock read earlier")
	}
}
