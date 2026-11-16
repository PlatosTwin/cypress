package api

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── ROADMAP 144: a species answer on somebody else's community tree counts for everyone ────────
//
// Migration 009. The rules are `store/species.go`'s header. Every promise to somebody else is read
// as somebody else, through the handler: a third account's profile, tile and history.

const operatorToken = "the-operator-token"

func speciesItem(kind string, tree, species uuid.UUID, at time.Time) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree, "occurred_at": stamp8601(at),
		"payload": jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "speciesID": species}),
	}
}

// reportItem is `ReviewReport`, with the phone half's optional `disputedSpeciesID` when non-nil.
func reportItem(tree, flag uuid.UUID, disputed *uuid.UUID) map[string]any {
	payload := map[string]any{"clientUUID": uuid.New(), "treeID": tree, "flagID": flag, "kind": "wrong_species"}
	if disputed != nil {
		payload["disputedSpeciesID"] = *disputed
	}
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "wrong_species_report", "tree_uuid": tree,
		"occurred_at": stamp8601(time.Now()), "payload": jsonBody(payload),
	}
}

// keepItem is `ReviewDismissal` for the species seam: "Keep the species".
func keepItem(tree, flag uuid.UUID) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": "species_review_dismissal", "tree_uuid": tree,
		"occurred_at": stamp8601(time.Now()),
		"payload":     jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "flagID": flag}),
	}
}

// speciesView is what one viewer's `GET /trees/{id}` says about the species.
type speciesView struct {
	Species    *uuid.UUID
	Reported   bool
	FlagID     *uuid.UUID
	NamedByYou bool
}

func speciesViewOf(t *testing.T, h *harness, bearer string, tree uuid.UUID) speciesView {
	t.Helper()
	profile := profileOf(t, h, bearer, tree)
	var body struct {
		Reported   *bool      `json:"species_reported"`
		FlagID     *uuid.UUID `json:"species_report_flag_id"`
		NamedByYou *bool      `json:"species_named_by_you"`
	}
	if err := json.Unmarshal(profile.raw, &body); err != nil {
		t.Fatal(err)
	}
	if body.Reported == nil || body.NamedByYou == nil {
		t.Fatalf("species_reported or species_named_by_you is missing: %s", profile.raw)
	}
	view := speciesView{Reported: *body.Reported, FlagID: body.FlagID, NamedByYou: *body.NamedByYou}
	if profile.CommunityTree != nil {
		view.Species = profile.CommunityTree.SpeciesCurrentID
	}
	return view
}

// publishedTree is a tree added and published by a sharing account.
func publishedTree(t *testing.T, h *harness, subject string) (sessionResponse, uuid.UUID) {
	t.Helper()
	adder := signInAs(t, h, subject, nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")
	if !stateOf(t, h, tree).Published {
		t.Fatal("fixture: the tree did not publish")
	}
	return adder, tree
}

type speciesEvent struct {
	Kind      string
	By        *string
	ActorUser *uuid.UUID
	Public    bool
	Before    *uuid.UUID
	After     *uuid.UUID
}

func speciesEventsOf(t *testing.T, h *harness, tree uuid.UUID) []speciesEvent {
	t.Helper()
	rows, err := h.store.Pool().Query(context.Background(), `
		SELECT kind, after ->> 'by', actor_user_id, in_public_history,
		       (before ->> 'species_id')::uuid, (after ->> 'species_id')::uuid
		  FROM community_tree_events
		 WHERE tree_id = $1 AND kind IN ('species_named', 'species_corrected', 'species_reported', 'species_reports_cleared')
		 ORDER BY recorded_at, id
	`, tree)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var events []speciesEvent
	for rows.Next() {
		var e speciesEvent
		if err := rows.Scan(&e.Kind, &e.By, &e.ActorUser, &e.Public, &e.Before, &e.After); err != nil {
			t.Fatal(err)
		}
		events = append(events, e)
	}
	return events
}

func sameSpecies(got *uuid.UUID, want uuid.UUID) bool { return got != nil && *got == want }

// ── Naming ─────────────────────────────────────────────────────────────────────────────────────

// TestASharingStrangersFirstClaimNamesTheTreeForEveryone is the owner's rule of 2026-11-15: the first
// answer on a tree with no species names it for everyone, marked as a contributor's. Red if
// `materializeSpecies` still answers only the adder.
func TestASharingStrangersFirstClaimNamesTheTreeForEveryone(t *testing.T) {
	h := newHarness(t)
	_, tree := publishedTree(t, h, "sp.name.adder")
	namer := signInAs(t, h, "sp.name.namer", nil, accepted())
	third := h.registerDeviceToken(t, uuid.New())

	tile, _, _ := tileOf(ctLat, ctLon)
	before := readTile(t, h, third, tile, "", 0, nil)

	species := uuid.New()
	mustApply(t, h.syncOne(t, namer.AccessToken, speciesItem("species_claim", tree, species, time.Now())), "the namer's claim")

	if got := speciesViewOf(t, h, third, tree); !sameSpecies(got.Species, species) {
		t.Fatalf("a third viewer's profile shows species %v, want the contributor's %s", got.Species, species)
	}
	if !speciesViewOf(t, h, namer.AccessToken, tree).NamedByYou {
		t.Fatal("the namer's profile does not say the naming is theirs")
	}
	if speciesViewOf(t, h, third, tree).NamedByYou {
		t.Fatal("a third viewer is told they named the tree")
	}
	// The tile delta serves it again, with the species, so every other phone learns it.
	delta := readTile(t, h, third, tile, *before.NextCursor, 0, nil)
	found := false
	for _, served := range delta.Trees {
		if served.ID == tree {
			found = sameSpecies(served.SpeciesCurrentID, species)
		}
	}
	if !found {
		t.Fatalf("the tile delta after the naming does not carry the tree with its species: %s", delta.raw)
	}

	events := speciesEventsOf(t, h, tree)
	if len(events) != 1 || events[0].Kind != "species_named" || events[0].By == nil ||
		*events[0].By != "contributor" || !events[0].Public || !sameSpecies(events[0].ActorUser, namer.UserID) {
		t.Fatalf("events = %+v, want one public species_named by the contributor", events)
	}

	// The history serves it under its own kind, with `by_you` for the namer only.
	_, theirs := readHistory(t, h, third, tree)
	_, own := readHistory(t, h, namer.AccessToken, tree)
	if got := theirs.kinds(); !slices.Equal(got, []string{"species_named_by_contributor", "added"}) {
		t.Fatalf("a third viewer's history kinds = %v", got)
	}
	if flags := own.byYou(); len(flags) != 2 || !*flags[0] || *flags[1] {
		t.Fatalf("the namer's by_you = %v, want true for the naming and false for the add", flags)
	}
	if flags := theirs.byYou(); len(flags) != 2 || *flags[0] || *flags[1] {
		t.Fatalf("a third viewer's by_you = %v, want false for both", flags)
	}
}

// TestOnlyPeopleWhoShareNameOrReport is the owner's rule of 2026-11-16, "Only people who share": a
// device and an account that declined the license are recorded, answered `applied`, and change
// nothing. The control is a sharing account doing the same thing.
func TestOnlyPeopleWhoShareNameOrReport(t *testing.T) {
	h := newHarness(t)
	adder, unnamed := publishedTree(t, h, "sp.share.adder")
	named := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(named, north(40), ctLon, time.Now())), "add")
	species := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", named, species, time.Now())), "the adder names it")

	device := h.registerDeviceToken(t, uuid.New())
	decliner := signInAs(t, h, "sp.share.decliner", nil, nil).AccessToken
	third := h.registerDeviceToken(t, uuid.New())
	for name, bearer := range map[string]string{"a device": device, "a declining account": decliner} {
		mustApply(t, h.syncOne(t, bearer, speciesItem("species_claim", unnamed, uuid.New(), time.Now())), name+"'s claim")
		mustApply(t, h.syncOne(t, bearer, reportItem(named, uuid.New(), nil)), name+"'s report")
		if got := stateOf(t, h, unnamed).SpeciesID; got != nil {
			t.Fatalf("%s named the tree %s", name, got)
		}
		if speciesViewOf(t, h, third, named).Reported {
			t.Fatalf("%s's report marked the species", name)
		}
	}
	sharer := signInAs(t, h, "sp.share.sharer", nil, accepted()).AccessToken
	mustApply(t, h.syncOne(t, sharer, reportItem(named, uuid.New(), nil)), "control: a sharer's report")
	if !speciesViewOf(t, h, third, named).Reported {
		t.Fatal("control: a sharing account's report did not mark the species")
	}
}

// TestTheFirstCommittedNamingWins is the orchestrator's choice: the first naming the service commits
// wins, and the phones' clocks do not decide. The second is answered `applied` and changes nothing.
func TestTheFirstCommittedNamingWins(t *testing.T) {
	h := newHarness(t)
	_, tree := publishedTree(t, h, "sp.race.adder")
	first := signInAs(t, h, "sp.race.first", nil, accepted()).AccessToken
	second := signInAs(t, h, "sp.race.second", nil, accepted()).AccessToken

	winner, loser := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, first, speciesItem("species_claim", tree, winner, time.Now())), "the first naming")
	// The second phone's clock says it named the tree an hour earlier. It arrived second.
	mustApply(t, h.syncOne(t, second, speciesItem("species_claim", tree, loser, time.Now().Add(-time.Hour))), "the second naming")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, winner) {
		t.Fatalf("the species is %v, want the first committed naming %s", got, winner)
	}
	if n := len(speciesEventsOf(t, h, tree)); n != 1 {
		t.Fatalf("%d species events, want 1", n)
	}
	if speciesViewOf(t, h, second, tree).NamedByYou {
		t.Fatal("the loser is told the naming is theirs")
	}
}

// TestANamingOnATreeTheSenderCannotSeeChangesNothing: an unpublished tree (its adder declined) and a
// withdrawn one answer a stranger's naming `applied` and keep no species. Red if the `hiddenFrom`
// check goes.
func TestANamingOnATreeTheSenderCannotSeeChangesNothing(t *testing.T) {
	h := newHarness(t)
	decliner := signInAs(t, h, "sp.hidden.decliner", nil, nil)
	private := uuid.New()
	mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(private, ctLat, ctLon, time.Now())), "add")
	adder, withdrawn := publishedTree(t, h, "sp.hidden.adder")
	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(withdrawn)), "withdrawal")

	sharer := signInAs(t, h, "sp.hidden.sharer", nil, accepted()).AccessToken
	for name, tree := range map[string]uuid.UUID{"an unpublished tree": private, "a withdrawn tree": withdrawn} {
		mustApply(t, h.syncOne(t, sharer, speciesItem("species_claim", tree, uuid.New(), time.Now())), name)
		if got := stateOf(t, h, tree).SpeciesID; got != nil {
			t.Fatalf("a sharer named %s: %s", name, got)
		}
	}
}

// ── Correcting ─────────────────────────────────────────────────────────────────────────────────

// TestTheNamerCorrectsTheirOwnAnswerUntilTheAdderActs is the owner's rule of 2026-11-16, "Yes, until
// the adder corrects it", in both of its endings: the adder's correction and the adder's keep.
// Nobody else's correction moves a contributor's naming.
func TestTheNamerCorrectsTheirOwnAnswerUntilTheAdderActs(t *testing.T) {
	for _, ending := range []string{"the adder corrects", "the adder keeps"} {
		t.Run(ending, func(t *testing.T) {
			h := newHarness(t)
			adder, tree := publishedTree(t, h, "sp.fix.adder."+ending)
			namer := signInAs(t, h, "sp.fix.namer."+ending, nil, accepted()).AccessToken
			other := signInAs(t, h, "sp.fix.other."+ending, nil, accepted()).AccessToken

			named, fixed := uuid.New(), uuid.New()
			mustApply(t, h.syncOne(t, namer, speciesItem("species_claim", tree, named, time.Now())), "naming")
			mustApply(t, h.syncOne(t, other, speciesItem("species_correction", tree, uuid.New(), time.Now())), "another sharer's correction")
			if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, named) {
				t.Fatalf("another sharer's correction moved the species to %v", got)
			}
			mustApply(t, h.syncOne(t, namer, speciesItem("species_correction", tree, fixed, time.Now())), "the namer's correction")
			if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, fixed) {
				t.Fatalf("the namer's own correction left the species at %v, want %s", got, fixed)
			}
			events := speciesEventsOf(t, h, tree)
			last := events[len(events)-1]
			if last.Kind != "species_corrected" || last.By == nil || *last.By != "contributor" || !last.Public {
				t.Fatalf("the namer's correction wrote %+v, want a public species_corrected by the contributor", last)
			}

			adderSpecies := fixed
			if ending == "the adder corrects" {
				adderSpecies = uuid.New()
				mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_correction", tree, adderSpecies, time.Now())), "the adder's correction")
			} else {
				mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, uuid.New())), "the adder's keep")
			}
			if speciesViewOf(t, h, namer, tree).NamedByYou {
				t.Fatal("the namer is still told the naming is theirs after the adder acted")
			}
			mustApply(t, h.syncOne(t, namer, speciesItem("species_correction", tree, uuid.New(), time.Now().Add(time.Hour))), "the namer's late correction")
			if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, adderSpecies) {
				t.Fatalf("after the adder acted the namer moved the species to %v", got)
			}
		})
	}
}

// TestTheAddersClaimOnAContributorsNamingCorrectsIt: builds 88 and older (and any adder phone that
// has not learned the contributor's name) send a claim. It is the adder's correction.
func TestTheAddersClaimOnAContributorsNamingCorrectsIt(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.claim.adder")
	namer := signInAs(t, h, "sp.claim.namer", nil, accepted()).AccessToken
	mustApply(t, h.syncOne(t, namer, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
	reporter := signInAs(t, h, "sp.claim.reporter", nil, accepted()).AccessToken
	mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), "a report")

	mine := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, mine, time.Now().Add(-48*time.Hour))), "the adder's claim")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, mine) {
		t.Fatalf("the adder's claim left the species at %v, want %s", got, mine)
	}
	events := speciesEventsOf(t, h, tree)
	last := events[len(events)-1]
	if last.Kind != "species_corrected" || last.By == nil || *last.By != "adder" {
		t.Fatalf("the adder's claim wrote %+v, want species_corrected by the adder", last)
	}
	if speciesViewOf(t, h, reporter, tree).Reported {
		t.Fatal("the adder's correction did not clear the reported state")
	}
	// And the adder's claim on the adder's own naming still changes nothing (the old rule).
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "a second claim")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, mine) {
		t.Fatalf("an adder's claim on the adder's own naming moved it to %v", got)
	}
}

// ── Reports ────────────────────────────────────────────────────────────────────────────────────

// TestAReportMarksTheSpeciesForEveryone is the owner's rule of 2026-11-15: the name stays, and every
// viewer is told somebody reported it. The adder alone gets the flag id. Five reports that must not
// count are the control: on an unnamed tree, the adder's own, one disputing a species the tree does
// not have, the namer's report of their own answer, and one whose `disputedSpeciesID` is not a uuid.
func TestAReportMarksTheSpeciesForEveryone(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.report.adder")
	_, unnamed := publishedTree(t, h, "sp.report.adder2")
	namer := signInAs(t, h, "sp.report.namer", nil, accepted()).AccessToken
	reporter := signInAs(t, h, "sp.report.reporter", nil, accepted()).AccessToken
	third := h.registerDeviceToken(t, uuid.New())

	species := uuid.New()
	mustApply(t, h.syncOne(t, namer, speciesItem("species_claim", tree, species, time.Now())), "naming")

	other := uuid.New()
	mustApply(t, h.syncOne(t, reporter, reportItem(unnamed, uuid.New(), nil)), "a report on an unnamed tree")
	mustApply(t, h.syncOne(t, adder.AccessToken, reportItem(tree, uuid.New(), nil)), "the adder's own report")
	mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), &other)), "a report disputing another species")
	mustApply(t, h.syncOne(t, namer, reportItem(tree, uuid.New(), nil)), "the namer's report of their own answer")
	malformed := reportItem(tree, uuid.New(), nil)
	malformed["payload"] = json.RawMessage(`{"treeID":"` + tree.String() + `","flagID":"` + uuid.New().String() +
		`","kind":"wrong_species","disputedSpeciesID":"not-a-uuid"}`)
	mustApply(t, h.syncOne(t, reporter, malformed), "a report with a malformed disputed species")
	for _, viewer := range []string{third, adder.AccessToken} {
		if speciesViewOf(t, h, viewer, tree).Reported || speciesViewOf(t, h, viewer, unnamed).Reported {
			t.Fatal("a report that must not count marked a species")
		}
	}

	flag := uuid.New()
	mustApply(t, h.syncOne(t, reporter, reportItem(tree, flag, &species)), "a sharer's report")
	theirs, adders := speciesViewOf(t, h, third, tree), speciesViewOf(t, h, adder.AccessToken, tree)
	if !theirs.Reported || !adders.Reported {
		t.Fatalf("after a report: third %v, adder %v; want both reported", theirs.Reported, adders.Reported)
	}
	if !sameSpecies(theirs.Species, species) {
		t.Fatalf("the report changed the species to %v", theirs.Species)
	}
	if theirs.FlagID != nil || adders.FlagID == nil || *adders.FlagID != flag {
		t.Fatalf("flag id: third %v, adder %v; want none and %s", theirs.FlagID, adders.FlagID, flag)
	}
	// The report is in no history.
	if _, history := readHistory(t, h, third, tree); slices.Contains(history.kinds(), "species_reported") {
		t.Fatal("the history serves a report")
	}
}

// TestTheMarkClearsAndComesBack: the adder's correction, the adder's keep, the operator's clear and
// the operator's correction each clear it; a stranger's keep does not; a later report brings it
// back each time.
func TestTheMarkClearsAndComesBack(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.clear.adder")
	reporter := signInAs(t, h, "sp.clear.reporter", nil, accepted()).AccessToken
	stranger := signInAs(t, h, "sp.clear.stranger", nil, accepted()).AccessToken
	third := h.registerDeviceToken(t, uuid.New())
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")

	report := func(what string) {
		t.Helper()
		mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), what)
		if !speciesViewOf(t, h, third, tree).Reported {
			t.Fatalf("%s did not mark the species", what)
		}
	}
	cleared := func(what string, want bool) {
		t.Helper()
		if got := !speciesViewOf(t, h, third, tree).Reported; got != want {
			t.Fatalf("after %s the mark is cleared = %v, want %v", what, got, want)
		}
	}
	operator := func(path string, body any) {
		t.Helper()
		recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+path, operatorToken, body)
		if recorder.Code != http.StatusOK {
			t.Fatalf("operator %s answered %d: %s", path, recorder.Code, recorder.Body.String())
		}
	}

	report("the first report")
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_correction", tree, uuid.New(), time.Now())), "the adder's correction")
	cleared("the adder's correction", true)

	report("a report after the correction")
	mustApply(t, h.syncOne(t, stranger, keepItem(tree, uuid.New())), "a stranger's keep")
	cleared("a stranger's keep", false)
	mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, uuid.New())), "the adder's keep")
	cleared("the adder's keep", true)

	report("a report after the keep")
	operator("/species-reports/clear", nil)
	cleared("the operator's clear", true)

	report("a report after the operator's clear")
	operator("/species", map[string]any{"species_id": uuid.New()})
	cleared("the operator's correction", true)

	report("a report after the operator's correction")
}

// ── The operator ───────────────────────────────────────────────────────────────────────────────

// TestTheOperatorSpeciesRoutes: guarded like the takedown, `not_found` for an id that names nothing,
// and the correction's event has no actor and is served as the operator's. It ends a namer's right
// to correct.
func TestTheOperatorSpeciesRoutes(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.op.adder")
	namer := signInAs(t, h, "sp.op.namer", nil, accepted()).AccessToken
	named := uuid.New()
	mustApply(t, h.syncOne(t, namer, speciesItem("species_claim", tree, named, time.Now())), "naming")

	paths := map[string]any{"/species": map[string]any{"species_id": uuid.New()}, "/species-reports/clear": nil}
	for path, body := range paths {
		for name, bearer := range map[string]string{
			"no credential": "", "a wrong token": "not-the-operator-token", "the adder's session": adder.AccessToken,
		} {
			recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+path, bearer, body)
			if recorder.Code != http.StatusForbidden || decodeEnvelope(t, recorder).Error.Code != string(apierr.Forbidden) {
				t.Fatalf("%s %s answered %d, want forbidden", name, path, recorder.Code)
			}
		}
		recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+uuid.New().String()+path, operatorToken, body)
		if recorder.Code != http.StatusNotFound {
			t.Fatalf("%s on an id that names nothing answered %d, want 404", path, recorder.Code)
		}
	}
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, named) {
		t.Fatalf("a refused operator call moved the species to %v", got)
	}
	recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+"/species", operatorToken,
		map[string]any{"species_id": nil})
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("an operator correction with no species answered %d, want 400", recorder.Code)
	}

	chosen := uuid.New()
	recorder = h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+"/species", operatorToken,
		map[string]any{"species_id": chosen})
	if recorder.Code != http.StatusOK {
		t.Fatalf("the operator's correction answered %d: %s", recorder.Code, recorder.Body.String())
	}
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, chosen) {
		t.Fatalf("the operator's correction left the species at %v", got)
	}
	events := speciesEventsOf(t, h, tree)
	last := events[len(events)-1]
	if last.Kind != "species_corrected" || last.By == nil || *last.By != "operator" || last.ActorUser != nil || !last.Public {
		t.Fatalf("the operator's correction wrote %+v, want a public species_corrected by the operator with no actor", last)
	}
	var actorDevice *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT actor_device_id FROM community_tree_events WHERE tree_id = $1 AND after ->> 'by' = 'operator'
	`, tree).Scan(&actorDevice); err != nil || actorDevice != nil {
		t.Fatalf("the operator's event names device %v (%v)", actorDevice, err)
	}
	if _, history := readHistory(t, h, h.registerDeviceToken(t, uuid.New()), tree); history.kinds()[0] != "species_corrected_by_operator" {
		t.Fatalf("history kinds = %v, want the operator's correction first", history.kinds())
	}
	mustApply(t, h.syncOne(t, namer, speciesItem("species_correction", tree, uuid.New(), time.Now().Add(time.Hour))), "the namer's correction")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, chosen) {
		t.Fatalf("the namer corrected after the operator: %v", got)
	}
}

// ── Account deletion ───────────────────────────────────────────────────────────────────────────

// TestAReportCountsUntilItsRecordIsErased: the reporter's "leave" keeps the report counting; the
// reporter's erase stops it.
func TestAReportCountsUntilItsRecordIsErased(t *testing.T) {
	for _, door := range []string{"leaveRecords", "eraseEverything"} {
		t.Run(door, func(t *testing.T) {
			h := newHarness(t)
			adder, tree := publishedTree(t, h, "sp.del.adder."+door)
			mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
			reporter := signInAs(t, h, "sp.del.reporter."+door, nil, accepted())
			mustApply(t, h.syncOne(t, reporter.AccessToken, reportItem(tree, uuid.New(), nil)), "a report")
			third := h.registerDeviceToken(t, uuid.New())
			if !speciesViewOf(t, h, third, tree).Reported {
				t.Fatal("fixture: the report does not count")
			}
			deleteMe(t, h, reporter.AccessToken, door)
			if got, want := speciesViewOf(t, h, third, tree).Reported, door == "leaveRecords"; got != want {
				t.Fatalf("after the reporter's %s the species is reported = %v, want %v", door, got, want)
			}
		})
	}
}

// TestTheAddersEraseDoesNotReopenClearedReports is why "cleared" is a column: the adder's keep is a
// contribution the erase door deletes, and the tree it cleared stays (anonymized, because somebody
// else visited it). Red if "cleared" were derived from the adder's rows.
func TestTheAddersEraseDoesNotReopenClearedReports(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.erase.adder")
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_claim", tree, uuid.New(), time.Now())), "naming")
	reporter := signInAs(t, h, "sp.erase.reporter", nil, accepted()).AccessToken
	mustApply(t, h.syncOne(t, reporter, visitItem(tree)), "the reporter's visit, which keeps the tree")
	mustApply(t, h.syncOne(t, reporter, reportItem(tree, uuid.New(), nil)), "a report")
	mustApply(t, h.syncOne(t, adder.AccessToken, keepItem(tree, uuid.New())), "the adder's keep")
	third := h.registerDeviceToken(t, uuid.New())
	if speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("fixture: the keep did not clear the report")
	}
	deleteMe(t, h, adder.AccessToken, "eraseEverything")
	if state := stateOf(t, h, tree); !state.Exists || !state.Anonymized {
		t.Fatalf("fixture: the tree is %+v, want it kept, anonymized", state)
	}
	if speciesViewOf(t, h, third, tree).Reported {
		t.Fatal("the adder's erase brought a cleared report back")
	}
}

// TestTheNamersEraseKeepsTheSpeciesAndNamesNobody is the owner's decision of 2026-11-16, "The species
// stays": the name stays for everyone, with nothing that links it to the person. Nobody but the
// adder and the operator can change it afterwards, and the history still says a contributor named
// it.
func TestTheNamersEraseKeepsTheSpeciesAndNamesNobody(t *testing.T) {
	h := newHarness(t)
	adder, tree := publishedTree(t, h, "sp.namer.adder")
	namer := signInAs(t, h, "sp.namer.namer", nil, accepted())
	species := uuid.New()
	mustApply(t, h.syncOne(t, namer.AccessToken, speciesItem("species_claim", tree, species, time.Now())), "naming")

	deleteMe(t, h, namer.AccessToken, "eraseEverything")

	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, species) {
		t.Fatalf("the namer's erase changed the species to %v", got)
	}
	var namerLeft *uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT species_namer_user_id FROM community_trees WHERE id = $1`, tree).Scan(&namerLeft); err != nil || namerLeft != nil {
		t.Fatalf("the tree still names its namer: %v (%v)", namerLeft, err)
	}
	if n := actorRowsNaming(t, h, namer.UserID, uuid.New()); n != 0 {
		t.Fatalf("%d chain rows or events still name the erased namer", n)
	}
	if _, history := readHistory(t, h, h.registerDeviceToken(t, uuid.New()), tree); history.kinds()[0] != "species_named_by_contributor" {
		t.Fatalf("history kinds = %v, want the contributor's naming kept", history.kinds())
	}
	// The adder can still correct it.
	fixed := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, speciesItem("species_correction", tree, fixed, time.Now())), "the adder's correction")
	if got := stateOf(t, h, tree).SpeciesID; !sameSpecies(got, fixed) {
		t.Fatalf("the adder could not correct an anonymized naming: %v", got)
	}
}
