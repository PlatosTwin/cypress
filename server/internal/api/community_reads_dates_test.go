package api

import (
	"bytes"
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

// ── What day everybody is told a community tree was added ────────────────────────────────────
//
// The owner's decision of 2026-11-15: "the day the person added it on their phone", for every
// community tree and every viewer. It replaced the V1 ruling (strangers saw the day the tree went
// public, the adder the day the service received it). What it did not change is decision 13's
// position half and the L1 floor for every other event: where the tree stood, and what was done to
// it, while it was private stay private.
//
// Every date here is after 2026-07-21, the first day a tree can have been added
// (`store.earliestAddedDay`). A test dated before it would be reading the far-past clamp, which
// returns the receipt day, and could pass for the wrong reason.

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

// addTreeWithDay is `addTreeAt` with an `addedOn` value spliced into the payload exactly as given
// (a JSON literal: a quoted date, `null`, a number). An empty `addedOn` sends no key.
func addTreeWithDay(tree uuid.UUID, occurredAt time.Time, addedOn string) map[string]any {
	item := addTreeAt(tree, ctLat, ctLon, occurredAt)
	if addedOn != "" {
		payload := item["payload"].(json.RawMessage)
		item["payload"] = json.RawMessage(strings.TrimSuffix(string(payload), "}") + `,"addedOn":` + addedOn + `}`)
	}
	return item
}

// TestEverybodyIsToldTheDayTheTreeWasAddedOnThePhone is the owner's decision of 2026-11-15, through
// every way a tree reaches the public: added signed in but received days later (the shape of a tree
// that predates syncing), added signed out and claimed days later, and added under a declined
// license and accepted days later. A stranger's tile, a stranger's profile, the history's "added",
// the adder's own profile and the adder's own history all say the day it was added on the phone,
// not the day the service received it and not the day it went live.
func TestEverybodyIsToldTheDayTheTreeWasAddedOnThePhone(t *testing.T) {
	const addedDay = "2026-10-14T00:00:00Z"
	added := time.Date(2026, 10, 14, 13, 37, 42, 0, time.UTC)
	live := time.Date(2026, 10, 20, 9, 12, 5, 0, time.UTC)
	for _, path := range []string{"signed in, received days later", "signed out, then claimed", "declined, then accepted"} {
		t.Run(path, func(t *testing.T) {
			h := newHarness(t)
			tree := uuid.New()
			subject := "ct.addedday." + itoa(len(path))
			switch path {
			case "signed in, received days later":
				adder := signInAs(t, h, subject, nil, accepted())
				atClock(h, live, func() {
					mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, added)), "late add")
				})
			case "signed out, then claimed":
				deviceUUID := uuid.New()
				device := h.registerDeviceToken(t, deviceUUID)
				atClock(h, added, func() {
					mustApply(t, h.syncOne(t, device, addTreeAt(tree, ctLat, ctLon, added)), "private add")
				})
				atClock(h, live, func() { signInAs(t, h, subject, &deviceUUID, accepted()) })
			default:
				decliner := signInAs(t, h, subject, nil, nil)
				atClock(h, added, func() {
					mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(tree, ctLat, ctLon, added)), "declined add")
				})
				atClock(h, live, func() { signInAs(t, h, subject, nil, accepted()) })
			}

			var publishedAt time.Time
			if err := h.store.Pool().QueryRow(context.Background(),
				`SELECT published_at FROM community_trees WHERE id = $1`, tree).Scan(&publishedAt); err != nil {
				t.Fatalf("fixture: the tree did not go live: %v", err)
			}
			if !publishedAt.Equal(live) {
				t.Fatalf("fixture: the tree went live at %s, want %s, or this test cannot tell the two days apart",
					publishedAt, live)
			}

			stranger := h.registerDeviceToken(t, uuid.New())
			profile := profileOf(t, h, stranger, tree)
			tile, _, _ := tileOf(ctLat, ctLon)
			served := readTile(t, h, stranger, tile, "", 0, settled).tree(tree)
			if profile.CommunityTree == nil || served == nil {
				t.Fatalf("fixture: a stranger is not served the live tree (profile %s)", profile.raw)
			}
			_, history := readHistory(t, h, stranger, tree)
			days := servedDays(t, history)
			if len(days) != 1 || days[0] != [2]string{"added", addedDay} {
				t.Fatalf("a stranger's history is %v, want only added on %s, the day it was added on the phone",
					days, addedDay)
			}
			if served.CreatedAt != addedDay || profile.CommunityTree.CreatedAt != addedDay {
				t.Fatalf("a stranger is told the tree was created on %s (tile) and %s (profile); it was added "+
					"on the phone on %s", served.CreatedAt, profile.CommunityTree.CreatedAt, addedDay)
			}

			// The adder is told the same day, and reads the same history byte for byte. (A fresh
			// session: one minted on a pinned clock has expired by now.)
			adder := signInAs(t, h, subject, nil, accepted()).AccessToken
			own := profileOf(t, h, adder, tree)
			if own.CommunityTree == nil || own.CommunityTree.CreatedAt != addedDay || !*own.AddedByYou {
				t.Fatalf("the adder's own profile says created %v (added_by_you %v), want %s",
					own.CommunityTree, *own.AddedByYou, addedDay)
			}
			// Byte for byte except `by_you` (migration 009), the one key that says who is asking:
			// the "added" row is the adder's own act, and nobody else's.
			_, ownHistory := readHistory(t, h, adder, tree)
			if !bytes.Equal(ownHistory.withoutByYou(t), history.withoutByYou(t)) {
				t.Fatalf("the adder's history differs from a stranger's:\n%s\n%s", ownHistory.raw, history.raw)
			}
			if own, theirs := ownHistory.byYou(), history.byYou(); len(own) != 1 || own[0] == nil || !*own[0] ||
				len(theirs) != 1 || theirs[0] == nil || *theirs[0] {
				t.Fatalf("by_you is %v for the adder and %v for a stranger; want true and false", own, theirs)
			}
			assertPublicationInvariant(t, h)
		})
	}
}

// TestNoPrivateActIsDatedBeforeTheTreeWentLive is L1, under the decision of 2026-11-15. A declining
// account adds a tree on 10-14, a move and a naming are queued on its phone on 10-15 while the tree
// is still private, and the account accepts on 10-16, which publishes the tree. The queued acts
// arrive afterwards. S1 records them as public, because the pin did move and the name did change in
// public, but their own day is a day of the tree's private life. The owner made the add day public,
// not those days: each is served at the later of its own day and the day the tree went live, above
// "added", and "added" alone says 10-14. The control is a move made on 10-18, after going live,
// which keeps its own day.
func TestNoPrivateActIsDatedBeforeTheTreeWentLive(t *testing.T) {
	h := newHarness(t)
	d := func(day int) time.Time { return time.Date(2026, 10, day, 10, 0, 0, 0, time.UTC) }
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
		{"location_corrected", "2026-10-18T00:00:00Z"},
		{"species_named", "2026-10-16T00:00:00Z"},
		{"location_corrected", "2026-10-16T00:00:00Z"},
		{"added", "2026-10-14T00:00:00Z"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("the public history is %v, want %v: the add's own day, and no private act's day", got, want)
	}
}

// TestNoRowIsDatedBeforeTheAddedRow is the east-of-UTC case. A phone in Sydney adds a tree at 09:00
// on 10-15 local time (22:00 UTC on 10-14), signed in, so it goes live at once, and moves it an hour
// later (23:00 UTC on 10-14). The phone's day for both is 10-15. The add is served on 10-15; the
// move, whose UTC day is 10-14, is served no earlier than the add, so the history never lists a
// row dated before the "added" row below it.
func TestNoRowIsDatedBeforeTheAddedRow(t *testing.T) {
	h := newHarness(t)
	added, moved := goldenTime("2026-10-14T22:00:00Z"), goldenTime("2026-10-14T23:00:00Z")
	adder := signInAs(t, h, "ct.addedday.east", nil, accepted())
	tree := uuid.New()
	atClock(h, added, func() {
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeWithDay(tree, added, `"2026-10-15"`)), "add")
	})
	atClock(h, moved, func() {
		mustApply(t, h.syncOne(t, adder.AccessToken, correctionItem(tree, uuid.New(), north(40), ctLon, moved)), "move")
	})
	_, history := readHistory(t, h, h.registerDeviceToken(t, uuid.New()), tree)
	want := [][2]string{
		{"location_corrected", "2026-10-15T00:00:00Z"},
		{"added", "2026-10-15T00:00:00Z"},
	}
	if got := servedDays(t, history); !slices.Equal(got, want) {
		t.Fatalf("the public history is %v, want %v: newest first, and nothing dated before the add", got, want)
	}
}

// TestTheAddedDayRevealsNoPrivatePositionOrAct is decision 13's position half, which the decision
// of 2026-11-15 left alone. A signed-out phone adds a tree at P0 on 10-14, moves it to P1 and names
// it on 10-15, all received while the tree is private, and its account claims it on 10-20. The
// history serves exactly one event: "added", dated 10-14, standing at P1, the position the tree went
// public at, with no species and no "from" anything. The private move and the private naming are
// not served at all, and P0 appears nowhere in the body. The control is the adder's own chain,
// which still holds P0.
func TestTheAddedDayRevealsNoPrivatePositionOrAct(t *testing.T) {
	h := newHarness(t)
	d := func(day int) time.Time { return time.Date(2026, 10, day, 15, 0, 0, 0, time.UTC) }
	p0, p1 := north(-900), ctLat
	deviceUUID := uuid.New()
	device := h.registerDeviceToken(t, deviceUUID)
	tree := uuid.New()
	atClock(h, d(14), func() {
		mustApply(t, h.syncOne(t, device, addTreeAt(tree, p0, ctLon, d(14))), "private add")
	})
	atClock(h, d(15), func() {
		mustApply(t, h.syncOne(t, device, correctionItem(tree, uuid.New(), p1, ctLon, d(15))), "private move")
		mustApply(t, h.syncOne(t, device, map[string]any{
			"client_uuid": uuid.New(), "kind": "species_claim", "tree_uuid": tree,
			"occurred_at": stamp8601(d(15)),
			"payload":     jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "speciesID": uuid.New()}),
		}), "private naming")
	})
	atClock(h, d(20), func() { signInAs(t, h, "ct.addedday.private", &deviceUUID, accepted()) })

	if chain := chainRowsOf(t, h, tree); len(chain) != 2 || chain[0].Lat != p0 {
		t.Fatalf("control: the adder's chain is %+v; it should still hold the private root at %v", chain, p0)
	}
	events := eventsOf(t, h, tree)
	if len(eventsOfKind(events, "location_corrected")) != 1 || len(eventsOfKind(events, "species_named")) != 1 {
		t.Fatalf("control: the private move and naming are not recorded: %+v", events)
	}

	stranger := h.registerDeviceToken(t, uuid.New())
	code, history := readHistory(t, h, stranger, tree)
	if code != http.StatusOK || len(history.Events) != 1 {
		t.Fatalf("the history (%d) is %s; want exactly one event, the add", code, history.raw)
	}
	var added struct {
		Kind           string          `json:"kind"`
		OccurredAt     string          `json:"occurred_at"`
		FromCoordinate *wireCoordinate `json:"from_coordinate"`
		ToCoordinate   *wireCoordinate `json:"to_coordinate"`
		FromSpeciesID  *uuid.UUID      `json:"from_species_id"`
		ToSpeciesID    *uuid.UUID      `json:"to_species_id"`
		Placement      *string         `json:"placement"`
	}
	raw, err := json.Marshal(history.Events[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &added); err != nil {
		t.Fatal(err)
	}
	if added.Kind != "added" || added.OccurredAt != "2026-10-14T00:00:00Z" ||
		added.FromCoordinate != nil || added.ToCoordinate == nil ||
		added.ToCoordinate.Latitude != p1 || added.ToCoordinate.Longitude != ctLon ||
		added.FromSpeciesID != nil || added.ToSpeciesID != nil ||
		added.Placement == nil || *added.Placement != "contributor_placed" {
		t.Fatalf("the one event served is %s; want added on 2026-10-14 at %v,%v (the position at going "+
			"live, placed by the private move), with no from-position and no species", raw, p1, ctLon)
	}
	if strings.Contains(string(history.raw), jsonNumber(p0)) {
		t.Fatalf("the private root %v appears in the public history: %s", p0, history.raw)
	}
}

// TestTheAddedDayKey is `addedOn`, the phone's local date of the add, and every way the service
// treats it: believed when it is within one day of the add's instant, ignored when it is not, the
// instant's UTC date when it is absent or null, never later than the receipt, never before the
// project began, and refused only when it is not a date at all.
func TestTheAddedDayKey(t *testing.T) {
	at := func(text string) time.Time { return goldenTime(text) }
	// 23:30 Pacific (daylight) time on 10-14 is 06:30 UTC on 10-15.
	pacificEvening := at("2026-10-15T06:30:00Z")
	// 09:00 in Sydney on 10-15 is 22:00 UTC on 10-14.
	sydneyMorning := at("2026-10-14T22:00:00Z")
	for _, c := range []struct {
		name               string
		occurred, received time.Time
		addedOn            string // a JSON literal; "" sends no key
		want               string
	}{
		{"absent: the UTC date of the instant, which is the next day for a Pacific evening",
			pacificEvening, pacificEvening, "", "2026-10-15"},
		{"null is absent", pacificEvening, pacificEvening, "null", "2026-10-15"},
		{"present, west of UTC: the phone's day, one before the UTC date",
			pacificEvening, pacificEvening, `"2026-10-14"`, "2026-10-14"},
		{"present, east of UTC: the phone's day, one after the receipt's UTC date",
			sydneyMorning, sydneyMorning, `"2026-10-15"`, "2026-10-15"},
		{"a tree that predates syncing, received months later, keeps its phone's day",
			at("2026-08-01T03:00:00Z"), at("2026-11-10T12:00:00Z"), `"2026-07-31"`, "2026-07-31"},
		{"a day two days off the instant is not this add's day: the instant's UTC date",
			pacificEvening, pacificEvening, `"2026-10-17"`, "2026-10-15"},
		{"a far-future day is ignored", pacificEvening, pacificEvening, `"2027-01-01"`, "2026-10-15"},
		{"an instant after the receipt is a fast clock: the receipt day",
			at("2026-12-25T12:00:00Z"), at("2026-10-15T12:00:00Z"), "", "2026-10-15"},
		{"and its stated day, far from the receipt, is not believed either",
			at("2026-12-25T12:00:00Z"), at("2026-10-15T12:00:00Z"), `"2026-12-25"`, "2026-10-15"},
		{"a far-past instant is a wrong clock: the receipt day",
			at("2001-01-01T12:00:00Z"), at("2026-10-15T12:00:00Z"), "", "2026-10-15"},
		{"and its stated day with it", at("2001-01-01T12:00:00Z"), at("2026-10-15T12:00:00Z"), `"2001-01-01"`, "2026-10-15"},
		{"a far-past day beside an honest instant is ignored",
			at("2026-10-15T12:00:00Z"), at("2026-10-15T12:00:00Z"), `"2001-01-01"`, "2026-10-15"},
		{"the first day the app existed is believed",
			at("2026-07-21T12:00:00Z"), at("2026-10-15T12:00:00Z"), "", "2026-07-21"},
		{"the day before it is not", at("2026-07-20T12:00:00Z"), at("2026-10-15T12:00:00Z"), "", "2026-10-15"},
	} {
		t.Run(c.name, func(t *testing.T) {
			h := newHarness(t)
			adder := signInAs(t, h, "ct.addedon.key", nil, accepted())
			tree := uuid.New()
			atClock(h, c.received, func() {
				mustApply(t, h.syncOne(t, adder.AccessToken, addTreeWithDay(tree, c.occurred, c.addedOn)), "add")
			})
			stranger := h.registerDeviceToken(t, uuid.New())
			profile := profileOf(t, h, stranger, tree)
			if profile.CommunityTree == nil {
				t.Fatalf("fixture: the tree is not served to a stranger: %s", profile.raw)
			}
			if got := profile.CommunityTree.CreatedAt; got != c.want+"T00:00:00Z" {
				t.Fatalf("addedOn %s on an add at %s received %s is served as %s, want %s",
					c.addedOn, c.occurred.Format(time.RFC3339), c.received.Format(time.RFC3339), got, c.want)
			}
		})
	}

	// Not a date in exactly `YYYY-MM-DD`: a malformed item, refused, and no tree stored.
	h := newHarness(t)
	adder := signInAs(t, h, "ct.addedon.malformed", nil, accepted())
	for _, bad := range []string{`"2026-10-1"`, `"10/14/2026"`, `"2026-02-30"`, `""`, `" 2026-10-14"`, `20261014`} {
		tree := uuid.New()
		result := h.syncOne(t, adder.AccessToken, addTreeWithDay(tree, pacificEvening, bad))
		if result.Status != "failed" || codeOf(result.Error) != string(apierr.ValidationFailed) {
			t.Fatalf("addedOn %s answered %s (%s: %s), want failed/validation_failed", bad, result.Status,
				codeOf(result.Error), result.Message)
		}
		if stateOf(t, h, tree).Exists {
			t.Fatalf("addedOn %s was refused and the tree was stored anyway", bad)
		}
	}
}
