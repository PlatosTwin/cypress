package api

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// `GET /me/grove/species` against a history that holds rows it must not read, or cannot.
//
// The defect these pin: the read cast `payload->>'speciesID'` to `uuid` over every contribution
// kind, so one stored payload carrying a non-UUID `speciesID` — of any kind — failed the whole
// query and answered `500 server_error` on every later read of that identity's Species tab. The row
// is a stored contribution the phone cannot un-send, so the tab stayed broken until somebody
// deleted the row by hand. A valid `speciesID` on a kind that is not a sighting enrolled that
// species in "species you know", which is wrong more quietly.

// knownRow is one entry of the Species tab's wire answer.
type knownRow struct {
	SpeciesID string    `json:"species_id"`
	FirstMet  time.Time `json:"first_met"`
}

// speciesTab reads `GET /me/grove/species` and fails the test on anything but a 200, printing the
// body — a 500 here is the defect, and a red that does not say so is not a red-proof.
func speciesTab(t *testing.T, h *harness, bearer string) []knownRow {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove/species", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/grove/species returned %d, want 200: %s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Known []knownRow `json:"known"`
		Total int        `json:"total"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decoding the species tab: %v (%s)", err, recorder.Body.String())
	}
	if response.Total != len(response.Known) {
		t.Fatalf("total = %d but %d rows were sent; `total` must count the set it came with",
			response.Total, len(response.Known))
	}
	return response.Known
}

// deviceRowID is `devices.id` for an installation — the owner column a device's contributions carry.
func deviceRowID(t *testing.T, h *harness, deviceUUID uuid.UUID) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT id FROM devices WHERE device_uuid = $1`, deviceUUID).Scan(&id); err != nil {
		t.Fatalf("looking up the device row: %v", err)
	}
	return id
}

// storeRaw writes a contribution straight into the table, bypassing `POST /sync`.
//
// This is the production case the fix has to survive: rows written before the write path refused
// anything, which no deploy of this service can reach back and correct. Going through the handler
// would test only what the handler admits *today*.
func storeRaw(t *testing.T, h *harness, device uuid.UUID, kind string, payload string, at time.Time) {
	t.Helper()
	_, err := h.store.Pool().Exec(context.Background(), `
		INSERT INTO contributions (client_uuid, kind, tree_uuid, device_id, payload, occurred_at)
		VALUES ($1, $2, $3, $4, $5::jsonb, $6)
	`, uuid.New(), kind, uuid.New(), device, payload, at)
	if err != nil {
		t.Fatalf("storing a raw %s row: %v", kind, err)
	}
}

// sighting is one sighting-kind item carrying a species, posted through `POST /sync`.
//
// **No client sends this shape today** — `Visit`, `TreeObservation`, `TreeMeasurement` and
// `CareEvent` carry no `speciesID` — and that is stated rather than hidden, because it is the
// finding the fix turns on: see `store.MetSpeciesKinds`. The shape is the one the read interprets,
// and it is posted here so the test can assert a species is *present* rather than only that
// something is absent.
func sighting(kind string, species string, at time.Time) map[string]any {
	return map[string]any{
		"client_uuid": uuid.New(), "kind": kind, "tree_uuid": uuid.New(),
		"occurred_at": at,
		"payload":     json.RawMessage(`{"speciesID":"` + species + `"}`),
	}
}

// TestAPoisonedSpeciesIDDoesNotBreakTheSpeciesTab is the decisive test, and it goes through the
// handler.
//
// It reads the tab twice: once with only the sightings in the history, which calibrates the
// fixture and names the right answer, and once after a poisoned row of **every kind this service
// accepts** has been written beneath them. The second read must be the first read, exactly.
func TestAPoisonedSpeciesIDDoesNotBreakTheSpeciesTab(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	device := deviceRowID(t, h, deviceUUID)

	base := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	speciesA, speciesB, speciesC := uuid.New(), uuid.New(), uuid.New()

	// Species A twice, in the two spellings the client emits: Swift's `JSONEncoder` writes a `UUID`
	// uppercase, and a lowercase one is what every other writer produces. One species, first met
	// at the earlier of the two.
	for _, item := range []map[string]any{
		sighting("visit", strings.ToUpper(speciesA.String()), base.Add(2*time.Hour)),
		sighting("measurement", speciesB.String(), base.Add(3*time.Hour)),
		sighting("care_event", speciesC.String(), base.Add(4*time.Hour)),
		sighting("observation", speciesA.String(), base.Add(5*time.Hour)),
	} {
		if result := h.syncOne(t, deviceToken, item); result.Status != "applied" {
			t.Fatalf("a sighting was not applied: %q (%s)", result.Status, codeOf(result.Error))
		}
	}
	want := []knownRow{
		{SpeciesID: speciesA.String(), FirstMet: base.Add(2 * time.Hour)},
		{SpeciesID: speciesB.String(), FirstMet: base.Add(3 * time.Hour)},
		{SpeciesID: speciesC.String(), FirstMet: base.Add(4 * time.Hour)},
	}
	assertKnown := func(stage string, got []knownRow) {
		t.Helper()
		if len(got) != len(want) {
			t.Fatalf("%s: the tab has %d species, want %d: %+v", stage, len(got), len(want), got)
		}
		for i := range want {
			if got[i].SpeciesID != want[i].SpeciesID || !got[i].FirstMet.Equal(want[i].FirstMet) {
				t.Fatalf("%s: row %d = %s first met %s, want %s first met %s", stage, i,
					got[i].SpeciesID, got[i].FirstMet, want[i].SpeciesID, want[i].FirstMet)
			}
		}
	}
	assertKnown("before any poisoned row", speciesTab(t, h, deviceToken))

	// A poisoned row of every kind, dated **before** every sighting so that one leaking into the
	// answer would sort first rather than hide at the end.
	poisonedAt := base
	kinds := make([]string, 0, len(syncKinds))
	for kind := range syncKinds {
		kinds = append(kinds, kind)
	}
	slices.Sort(kinds)
	if len(kinds) < 19 {
		t.Fatalf("syncKinds lists %d kinds; this fixture was written against nineteen", len(kinds))
	}
	for _, kind := range kinds {
		storeRaw(t, h, device, kind, `{"speciesID":"not-a-uuid"}`, poisonedAt)
	}
	// Every other way a value can fail to be a UUID, on a kind the read does interpret. Each of
	// these would have failed the old cast or — for the braced and unhyphenated forms, which
	// Postgres's own `uuid` input accepts — been counted in a spelling no client writes.
	for _, payload := range []string{
		`{"speciesID":""}`,
		`{"speciesID":12345}`,
		`{"speciesID":{"id":"` + uuid.New().String() + `"}}`,
		`{"speciesID":["` + uuid.New().String() + `"]}`,
		`{"speciesID":true}`,
		`{"speciesID":null}`,
		`{"speciesID":"zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"}`,
		`{"speciesID":" ` + uuid.New().String() + `"}`,
		`{"speciesID":"{` + uuid.New().String() + `}"}`,
		`{"speciesID":"` + strings.ReplaceAll(uuid.New().String(), "-", "") + `"}`,
		`"a payload that is a bare string"`,
		`["a payload that is an array"]`,
	} {
		storeRaw(t, h, device, "visit", payload, poisonedAt)
	}

	assertKnown("after a poisoned row of every kind", speciesTab(t, h, deviceToken))
}

// TestOnlyASightingPutsASpeciesInTheTab is the quieter half: a *valid* species id on a kind that is
// not a sighting must not enrol that species.
//
// The kinds the client really sends a `speciesID` on are `add_tree`, `species_claim` and
// `species_correction`, and every one of them is a person *naming* a community tree's species. The
// client's own Species tab refuses those by rule — `GroveQueries.knownSpecies` reads city-inventory
// trees only, because a self-asserted species on a community tree would let a contributor raise
// their own ring by adding a tree — so a server that counted them would put species on the tab at
// refresh that the phone's first paint had just left off. The rest are here because nothing about
// a report, a vote or a dispute is an encounter with a species either.
func TestOnlyASightingPutsASpeciesInTheTab(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	device := deviceRowID(t, h, deviceUUID)

	base := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	met := uuid.New()
	if result := h.syncOne(t, deviceToken, sighting("visit", met.String(), base.Add(time.Hour))); result.Status != "applied" {
		t.Fatalf("the sighting was not applied: %q (%s)", result.Status, codeOf(result.Error))
	}

	// Stated here rather than read from `store.MetSpeciesKinds`, so that widening that list is a
	// change this test notices instead of one it silently follows.
	sightingKinds := []string{"visit", "observation", "measurement", "care_event"}
	named := map[string]string{}
	for kind := range syncKinds {
		if slices.Contains(sightingKinds, kind) {
			continue
		}
		species := uuid.New().String()
		named[species] = kind
		storeRaw(t, h, device, kind, `{"speciesID":"`+species+`"}`, base)
	}
	// The two real payloads, through the handler, so this is not only a statement about rows
	// written behind its back.
	tree := uuid.New()
	claimed := uuid.New()
	named[claimed.String()] = "species_claim (through POST /sync)"
	if result := h.syncOne(t, deviceToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "species_claim", "tree_uuid": tree, "occurred_at": base,
		"payload": json.RawMessage(`{"treeID":"` + strings.ToUpper(tree.String()) + `",` +
			`"speciesID":"` + strings.ToUpper(claimed.String()) + `"}`),
	}); result.Status != "applied" {
		t.Fatalf("the claim was not applied: %q (%s)", result.Status, codeOf(result.Error))
	}

	known := speciesTab(t, h, deviceToken)
	for _, row := range known {
		if kind, found := named[row.SpeciesID]; found {
			t.Fatalf("a %s enrolled species %s in the Species tab; only a sighting is meeting a species",
				kind, row.SpeciesID)
		}
	}
	if len(known) != 1 || known[0].SpeciesID != met.String() {
		t.Fatalf("the tab = %+v, want exactly the one species the visit met (%s)", known, met)
	}
}

// TestASpeciesStatementMustNameASpecies is the write-side half, for the two kinds whose payload
// *is* a species id and whose record is worth nothing without one.
func TestASpeciesStatementMustNameASpecies(t *testing.T) {
	h := newHarness(t)
	deviceToken := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()

	for _, kind := range []string{"species_claim", "species_correction"} {
		// The control: exactly what `SpeciesStatement` encodes — `JSONEncoder` writes a `UUID`
		// uppercase — including the fields this service does not read.
		valid := `{"clientUUID":"` + strings.ToUpper(uuid.New().String()) + `",` +
			`"treeID":"` + strings.ToUpper(tree.String()) + `",` +
			`"speciesID":"` + strings.ToUpper(uuid.New().String()) + `",` +
			`"attribution":{"deviceID":"` + strings.ToUpper(uuid.New().String()) + `"},` +
			`"occurredAt":"2026-09-01T10:00:00Z"}`
		if result := h.syncOne(t, deviceToken, map[string]any{
			"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree,
			"occurred_at": time.Now().UTC(), "payload": json.RawMessage(valid),
		}); result.Status != "applied" {
			t.Fatalf("%s in the client's own shape: %q (%s), want applied", kind, result.Status, codeOf(result.Error))
		}

		for _, payload := range []string{
			`{"treeID":"` + tree.String() + `","speciesID":"not-a-uuid"}`,
			`{"treeID":"` + tree.String() + `","speciesID":12345}`,
			`{"treeID":"` + tree.String() + `"}`,
			`{"treeID":"` + tree.String() + `","speciesID":null}`,
			`{"treeID":"` + tree.String() + `","speciesID":"00000000-0000-0000-0000-000000000000"}`,
		} {
			result := h.syncOne(t, deviceToken, map[string]any{
				"client_uuid": uuid.New(), "kind": kind, "tree_uuid": tree,
				"occurred_at": time.Now().UTC(), "payload": json.RawMessage(payload),
			})
			if result.Status != "failed" || result.Error == nil || *result.Error != apierr.ValidationFailed {
				t.Fatalf("%s with %s: %q (%s), want failed validation_failed",
					kind, payload, result.Status, codeOf(result.Error))
			}
		}
	}
}
