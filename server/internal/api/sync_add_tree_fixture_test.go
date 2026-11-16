package api

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// addTreeFixture is `server/testdata/sync_add_tree.json`, the `add_tree` request the phone's encoder
// must produce in structure (`LocationCorrectionFixtureTests` holds the Swift half). Its values are
// read from the file rather than restated, so the file is the one statement of them.
type addTreeFixture struct {
	Items []struct {
		ClientUUID uuid.UUID `json:"client_uuid"`
		TreeUUID   uuid.UUID `json:"tree_uuid"`
		OccurredAt time.Time `json:"occurred_at"`
		DeviceID   uuid.UUID `json:"device_id"`
		Payload    struct {
			TreeID     uuid.UUID `json:"treeID"`
			AddedOn    string    `json:"addedOn"`
			Coordinate struct {
				Latitude  float64 `json:"latitude"`
				Longitude float64 `json:"longitude"`
			} `json:"coordinate"`
			Placement string `json:"placement"`
		} `json:"payload"`
	} `json:"items"`
}

// TestTheAddTreeFixtureStoresItsLocalAddedDay posts the fixture's bytes through the real handler
// against Postgres, as the device that queued it, and reads back what was stored.
//
// The fixture is the west-of-UTC case: 23:30 on 2026-10-14 in San Francisco is 06:30 UTC on the
// 15th. A service that ignored or misnamed `addedOn` would store the 15th, the instant's UTC date,
// so the stored day says which key the service read.
func TestTheAddTreeFixtureStoresItsLocalAddedDay(t *testing.T) {
	raw, err := os.ReadFile("../../testdata/sync_add_tree.json")
	if err != nil {
		t.Fatalf("reading the fixture: %v", err)
	}
	var fixture addTreeFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("the fixture is not the shape this test reads: %v", err)
	}
	if len(fixture.Items) != 1 {
		t.Fatalf("the fixture carries %d items, want 1", len(fixture.Items))
	}
	item := fixture.Items[0]
	if item.Payload.AddedOn == "" {
		t.Fatal("the fixture carries no addedOn")
	}
	if utcDay := item.OccurredAt.UTC().Format(time.DateOnly); utcDay == item.Payload.AddedOn {
		t.Fatalf("the fixture's addedOn %s is its instant's UTC date: it cannot tell the key was read",
			item.Payload.AddedOn)
	}

	h := newHarness(t)
	token := h.registerDeviceToken(t, item.DeviceID)
	mustApply(t, postRaw(t, h, token, raw), "the fixture")

	var (
		addedOn  time.Time
		lat, lon float64
		place    string
	)
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT added_on, lat, lon, placement FROM community_trees WHERE id = $1`, item.TreeUUID,
	).Scan(&addedOn, &lat, &lon, &place); err != nil {
		t.Fatalf("the fixture's tree was not stored: %v", err)
	}
	if got := addedOn.Format(time.DateOnly); got != item.Payload.AddedOn {
		t.Fatalf("added_on = %s, want the fixture's addedOn %s", got, item.Payload.AddedOn)
	}
	if lat != item.Payload.Coordinate.Latitude || lon != item.Payload.Coordinate.Longitude ||
		place != item.Payload.Placement {
		t.Fatalf("the tree is at %v,%v (%s), want the fixture's", lat, lon, place)
	}

	// The same bytes again, as a phone replays a batch after a flap: matched on `client_uuid`, and
	// no second tree.
	if result := postRaw(t, h, token, raw); result.Status != "duplicate" {
		t.Fatalf("a replay of the fixture answered %s, want duplicate", result.Status)
	}
}
