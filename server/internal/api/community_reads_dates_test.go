package api

import (
	"encoding/json"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── What day a stranger is told (the #190 verification's V1 and the #187 verification's L1) ────

// atClock runs fn with the store's clock pinned to `at`, for every handler it drives.
func atClock(h *harness, at time.Time, fn func()) {
	previous := h.server.Store
	h.server.Store = h.store.WithClock(func() time.Time { return at })
	defer func() { h.server.Store = previous }()
	fn()
}

// servedDays is each history event's kind and served day, newest first.
func servedDays(t *testing.T, body historyBody) [][2]string {
	t.Helper()
	var out [][2]string
	for _, event := range body.Events {
		var kind, at string
		if err := json.Unmarshal(event["kind"], &kind); err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(event["occurred_at"], &at); err != nil {
			t.Fatal(err)
		}
		out = append(out, [2]string{kind, at})
	}
	return out
}

// TestAStrangerIsToldATreeWasAddedTheDayItWentLive is V1, both ways a tree waits before going
// live: added signed out and then claimed, and added under a declined license and then accepted.
// A stranger's tile and profile say it was created the day it went live, which is the day its
// public history says it was added; the adder's own profile keeps the day they really added it.
// Before this, both said the private add's day, which told every stranger how long the adder had
// been signed out or declining, beside a history that contradicted it.
func TestAStrangerIsToldATreeWasAddedTheDayItWentLive(t *testing.T) {
	const privateDay, liveDay = "2026-03-14T00:00:00Z", "2026-03-20T00:00:00Z"
	private := time.Date(2026, 3, 14, 13, 37, 42, 0, time.UTC)
	live := time.Date(2026, 3, 20, 9, 12, 5, 0, time.UTC)
	for _, path := range []string{"signed out, then claimed", "declined, then accepted"} {
		t.Run(path, func(t *testing.T) {
			h := newHarness(t)
			tree := uuid.New()
			subject := "ct.v1." + itoa(len(path))
			if path == "signed out, then claimed" {
				deviceUUID := uuid.New()
				device := h.registerDeviceToken(t, deviceUUID)
				atClock(h, private, func() {
					mustApply(t, h.syncOne(t, device, addTreeAt(tree, ctLat, ctLon, private)), "private add")
				})
				atClock(h, live, func() { signInAs(t, h, subject, &deviceUUID, accepted()) })
			} else {
				decliner := signInAs(t, h, subject, nil, nil)
				atClock(h, private, func() {
					mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(tree, ctLat, ctLon, private)), "declined add")
				})
				atClock(h, live, func() { signInAs(t, h, subject, nil, accepted()) })
			}

			stranger := h.registerDeviceToken(t, uuid.New())
			profile := profileOf(t, h, stranger, tree)
			if profile.CommunityTree == nil {
				t.Fatalf("fixture: the tree did not go live: %s", profile.raw)
			}
			tile, _, _ := tileOf(ctLat, ctLon)
			served := readTile(t, h, stranger, tile, "", 0, settled).tree(tree)
			if served == nil {
				t.Fatal("fixture: the tile does not serve the live tree")
			}
			_, history := readHistory(t, h, stranger, tree)
			days := servedDays(t, history)
			if len(days) == 0 || days[len(days)-1] != [2]string{"added", liveDay} {
				t.Fatalf("fixture: the public history's oldest event is %v, want added on %s", days, liveDay)
			}
			if served.CreatedAt != liveDay || profile.CommunityTree.CreatedAt != liveDay {
				t.Fatalf("a stranger is told the tree was created on %s (tile) and %s (profile); its public "+
					"history says it was added on %s, the day it went live", served.CreatedAt,
					profile.CommunityTree.CreatedAt, liveDay)
			}
			// The adder keeps the real day: it is their own record, and it is on their phone anyway.
			// (A fresh session: the one minted on the pinned clock expired months ago.)
			adder := signInAs(t, h, subject, nil, accepted()).AccessToken
			if own := profileOf(t, h, adder, tree); own.CommunityTree == nil || own.CommunityTree.CreatedAt != privateDay {
				t.Fatalf("the adder's own profile says created %v, want the day they added it, %s",
					own.CommunityTree, privateDay)
			}
		})
	}
}

// TestNoPublicEventIsDatedBeforeTheTreeWentLive is L1. A declining account adds a tree on 03-14, a
// move and a naming are queued on its phone on 03-15 while the tree is still private, and the
// account accepts on 03-16, which publishes the tree. The queued acts arrive afterwards. S1
// records them as public, because the pin did move and the name did change in public, but their
// own day is a day of the tree's private life. The history serves each at the later of its own day
// and the day the tree went live, and orders them by that: above "added", never below it. The
// control is a move made on 03-18, after going live, which keeps its own day.
func TestNoPublicEventIsDatedBeforeTheTreeWentLive(t *testing.T) {
	h := newHarness(t)
	d := func(day int) time.Time { return time.Date(2026, 3, day, 10, 0, 0, 0, time.UTC) }
	subject := "ct.l1.adder"
	decliner := signInAs(t, h, subject, nil, nil)
	tree := uuid.New()
	atClock(h, d(14), func() {
		mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(tree, ctLat, ctLon, d(14))), "private add")
	})
	atClock(h, d(16), func() { signInAs(t, h, subject, nil, accepted()) })
	session := signInAs(t, h, subject, nil, accepted())
	mustApply(t, h.syncOne(t, session.AccessToken, correctionItem(tree, uuid.New(), north(40), ctLon, d(15))), "a move queued while private")
	mustApply(t, h.syncOne(t, session.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "species_claim", "tree_uuid": tree,
		"occurred_at": stamp8601(d(15)),
		"payload":     jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "speciesID": uuid.New()}),
	}), "a naming queued while private")
	mustApply(t, h.syncOne(t, session.AccessToken, correctionItem(tree, uuid.New(), north(80), ctLon, d(18))), "a move after going live")

	stranger := h.registerDeviceToken(t, uuid.New())
	code, history := readHistory(t, h, stranger, tree)
	if code != http.StatusOK {
		t.Fatalf("history answered %d", code)
	}
	got := servedDays(t, history)
	want := [][2]string{
		{"location_corrected", "2026-03-18T00:00:00Z"},
		{"species_named", "2026-03-16T00:00:00Z"},
		{"location_corrected", "2026-03-16T00:00:00Z"},
		{"added", "2026-03-16T00:00:00Z"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("the public history is %v, want %v: nothing before the day the tree went live, and "+
			"nothing listed below its \"added\"", got, want)
	}
}
