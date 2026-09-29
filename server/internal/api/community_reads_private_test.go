package api

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/ratelimit"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── What was never public stays unreported (the #190 review's F2, F3, and decision 13) ─────────

// TestANeverPublishedTreeIsNeverReportedWhenItsAccountGoes is F2, both doors. A declining
// account's tree in another city is tombstoned when the account goes (decision 12); before 007
// recorded whether a tombstoned tree had been public, every stranger's delta in every tile then
// named it. The control is a published tree erased the same way, which must be reported.
func TestANeverPublishedTreeIsNeverReportedWhenItsAccountGoes(t *testing.T) {
	for _, door := range []string{"leaveRecords", "eraseEverything"} {
		t.Run(door, func(t *testing.T) {
			h := newHarness(t)
			decliner := signInAs(t, h, "ct.f2.decliner."+door, nil, nil)
			private := uuid.New()
			mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(private, 40.7128, -74.0060, time.Now())), "declined add")
			eraser := signInAs(t, h, "ct.f2.eraser."+door, nil, accepted())
			public := uuid.New()
			mustApply(t, h.syncOne(t, eraser.AccessToken, addTreeAt(public, 40.7228, -74.0060, time.Now())), "published add")

			tile, _, _ := tileOf(ctLat, ctLon)
			stranger := h.registerDeviceToken(t, uuid.New())
			first := readTile(t, h, stranger, tile, "", 0, settled)

			deleteMe(t, h, decliner.AccessToken, door)
			deleteMe(t, h, eraser.AccessToken, "eraseEverything")
			if !isTombstoned(t, h, private) || !isTombstoned(t, h, public) {
				t.Fatal("fixture: both trees should be tombstoned")
			}

			delta := readTile(t, h, stranger, tile, *first.NextCursor, 0, settled)
			if bytes.Contains(delta.raw, []byte(private.String())) {
				t.Fatalf("a never-published tree, tombstoned by %s, is in a stranger's delta for a tile in another city: %v",
					door, delta.WithdrawnTreeIDs)
			}
			if !slices.Contains(delta.WithdrawnTreeIDs, public) {
				t.Fatalf("control: a published tree erased with its account is not reported: %v", delta.WithdrawnTreeIDs)
			}
			// Inside the settle window a fresh first fetch reports recent removals; still not this one.
			if fresh := readTile(t, h, h.registerDeviceToken(t, uuid.New()), tile, "", 0, nil); bytes.Contains(fresh.raw, []byte(private.String())) {
				t.Fatal("a fresh first fetch within the settle window reports the never-published tree")
			}
		})
	}
}

// TestATreeBornWithdrawnIsNeverReported is F3: the withdrawal drained before the add, so the tree
// arrived already withdrawn and nobody ever saw it. It must not be reported in its tile.
func TestATreeBornWithdrawnIsNeverReported(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.f3.adder", nil, accepted())
	tile, _, _ := tileOf(ctLat, ctLon)
	stranger := h.registerDeviceToken(t, uuid.New())
	first := readTile(t, h, stranger, tile, "", 0, settled)

	born, control := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(born)), "the withdrawal, first")
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(born, ctLat, ctLon, time.Now())), "the add, second")
	// The control: the same adder's tree withdrawn in the usual order was public, and is reported.
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(control, north(40), ctLon, time.Now())), "control add")
	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(control)), "control withdrawal")

	delta := readTile(t, h, stranger, tile, *first.NextCursor, 0, settled)
	if bytes.Contains(delta.raw, []byte(born.String())) {
		t.Fatalf("a tree born withdrawn is reported in its tile: %v", delta.WithdrawnTreeIDs)
	}
	if !slices.Contains(delta.WithdrawnTreeIDs, control) {
		t.Fatalf("control: a tree withdrawn after going live is not reported: %v", delta.WithdrawnTreeIDs)
	}
}

// TestPositionsHeldWhilePrivateStayPrivate is decision 13, through both reads that could show
// them. A phone adds a tree in tile A signed out, moves it to tile B, still signed out, then signs
// in and the claim publishes it. A stranger sees it added in tile B, where it went live. Tile A
// never mentions it, and the history names no position in tile A. A move made after going live is
// public, and a tile the tree leaves after going live does report it.
func TestPositionsHeldWhilePrivateStayPrivate(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	device := h.registerDeviceToken(t, deviceUUID)
	tree := uuid.New()
	private := 37.7400
	tileA, _, _ := tileOf(private, ctLon)
	tileB, _, _ := tileOf(ctLat, ctLon)
	if tileA == tileB {
		t.Fatal("fixture: the private position is in the tile the tree went live in")
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	firstA := readTile(t, h, stranger, tileA, "", 0, settled)

	mustApply(t, h.syncOne(t, device, addTreeAt(tree, private, ctLon, time.Now().Add(-2*time.Hour))), "device add")
	mustApply(t, h.syncOne(t, device, correctionItem(tree, uuid.New(), ctLat, ctLon, time.Now().Add(-time.Hour))), "private move")
	adder := signInAs(t, h, "ct.d13.adder", &deviceUUID, accepted())

	if delta := readTile(t, h, stranger, tileA, *firstA.NextCursor, 0, settled); bytes.Contains(delta.raw, []byte(tree.String())) {
		t.Fatalf("tile A, where the tree stood only while private, reports it in a delta: %s", delta.raw)
	}
	if snapshot := readTile(t, h, stranger, tileA, "", 0, settled); bytes.Contains(snapshot.raw, []byte(tree.String())) {
		t.Fatalf("tile A, where the tree stood only while private, serves it in a snapshot: %s", snapshot.raw)
	}
	b := readTile(t, h, stranger, tileB, "", 0, settled)
	if served := b.tree(tree); served == nil || served.Coordinate.Latitude != ctLat {
		t.Fatalf("control: tile B, where the tree went live, does not serve it there: %s", b.raw)
	}

	code, history := readHistory(t, h, stranger, tree)
	if code != http.StatusOK {
		t.Fatalf("history answered %d", code)
	}
	if bytes.Contains(history.raw, []byte(strconv.FormatFloat(private, 'f', -1, 64))) {
		t.Fatalf("the history shows a stranger the position the tree held while private: %s", history.raw)
	}
	if !slices.Equal(history.kinds(), []string{"added"}) {
		t.Fatalf("history kinds = %v, want only the public \"added\" (the move was private)", history.kinds())
	}

	// After going live, a move is public, in the history and in the tile it leaves.
	firstB := readTile(t, h, stranger, tileB, "", 0, settled)
	across := 37.7300
	tileC, _, _ := tileOf(across, ctLon)
	mustApply(t, h.syncOne(t, adder.AccessToken, correctionItem(tree, uuid.New(), across, ctLon, time.Now().Add(2*time.Second))), "public move")
	if delta := readTile(t, h, stranger, tileB, *firstB.NextCursor, 0, settled); delta.tree(tree) == nil {
		t.Fatalf("control: tile B, which the tree left after going live, does not report it: %s", delta.raw)
	}
	if tileC == tileB {
		t.Fatal("fixture: the public move did not leave tile B")
	}
	if _, history := readHistory(t, h, stranger, tree); !slices.Equal(history.kinds(), []string{"location_corrected", "added"}) {
		t.Fatalf("history kinds after a public move = %v, want [location_corrected added]", history.kinds())
	}
}

// ── The grove's hero passes the photograph's gate (the #190 verification's V2) ──────────────────

// groveRows is `GET /me/grove`'s entries by tree, raw, and their heroes.
func groveRows(t *testing.T, h *harness, bearer string) (map[uuid.UUID][]byte, map[uuid.UUID]*uuid.UUID) {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/me/grove", bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /me/grove: %d %s", recorder.Code, recorder.Body.String())
	}
	var body struct {
		Entries []json.RawMessage `json:"entries"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	rows, heroes := map[uuid.UUID][]byte{}, map[uuid.UUID]*uuid.UUID{}
	for _, raw := range body.Entries {
		var entry struct {
			TreeUUID uuid.UUID  `json:"tree_uuid"`
			Hero     *uuid.UUID `json:"hero_photo_id"`
		}
		if err := json.Unmarshal(raw, &entry); err != nil {
			t.Fatal(err)
		}
		rows[entry.TreeUUID], heroes[entry.TreeUUID] = raw, entry.Hero
	}
	return rows, heroes
}

// plantVisit gives an owner a grove row on a tree.
func plantVisit(t *testing.T, h *harness, tree uuid.UUID, owner store.Owner) {
	t.Helper()
	execSQL(t, h, `
		INSERT INTO contributions (client_uuid, kind, tree_uuid, user_id, device_id, occurred_at, payload)
		VALUES ($1, 'visit', $2, $3, $4, now(), '{}')
	`, uuid.New(), tree, owner.UserID, owner.DeviceID)
}

// TestTheGroveHeroPassesThePhotographGate: a grove draws a tree's photograph as its hero exactly
// where the photograph read would serve that tree's photographs, for every hidden state and the
// visible ones, for an account and for a device (the two branches of "added by"). It is also the
// check that the grove's SQL spelling of the rule (`treeHiddenFromViewerSQL`) agrees with
// `communityTreeFor`, state by state. And a photograph whose bytes never arrived is no hero, even
// when it is the newest.
func TestTheGroveHeroPassesThePhotographGate(t *testing.T) {
	h := newHarness(t)
	h.server.limiter = ratelimit.New()
	ctx := context.Background()
	cases := hiddenCommunityTrees(t, h)
	photographer := signInAs(t, h, "ct.v2.photographer", nil, accepted())

	// The viewers: an account that declined (so its own add stays private and visible only to it),
	// and a device that is signed out (the same, through the device branch).
	decliner := signInAs(t, h, "ct.v2.decliner", nil, nil)
	deviceUUID := uuid.New()
	device := h.registerDeviceToken(t, deviceUUID)
	deviceRow := deviceRowID(t, h, deviceUUID)

	viewers := []struct {
		name   string
		bearer string
		owner  store.Owner
	}{
		{"an account", decliner.AccessToken, store.Owner{UserID: &decliner.UserID}},
		{"a device", device, store.Owner{DeviceID: &deviceRow}},
	}

	// Visible to both: a published tree, and a city tree (an id no community tree has).
	adder := signInAs(t, h, "ct.v2.adder", nil, accepted())
	published := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(published, north(400), ctLon, time.Now())), "published add")
	city := uuid.New()
	// Each viewer's own unpublished tree: visible to that viewer only.
	ownByAccount, ownByDevice := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(ownByAccount, north(500), ctLon, time.Now())), "the account's private add")
	mustApply(t, h.syncOne(t, device, addTreeAt(ownByDevice, north(600), ctLon, time.Now())), "the device's private add")

	photos := map[uuid.UUID]uuid.UUID{}
	for _, c := range cases {
		photos[c.tree] = c.photo
	}
	for _, tree := range []uuid.UUID{published, city, ownByAccount, ownByDevice} {
		photos[tree] = seedApprovedPhoto(t, h, tree, photographer.UserID)
	}
	// On the published tree, a newer photograph whose bytes never arrived. It must not be the hero.
	execSQL(t, h, `
		INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, approval_reason,
		                    captured_at, storage_key)
		VALUES ($1, $2, $3, 'full_tree', 'approved', 'auto_approved_launch', now() + interval '1 hour', $4)
	`, uuid.New(), published, photographer.UserID, "photos/no-bytes")

	for _, viewer := range viewers {
		for tree := range photos {
			plantVisit(t, h, tree, viewer.owner)
		}
		_, heroes := groveRows(t, h, viewer.bearer)
		hiddenCount, shownCount := 0, 0
		for tree, photo := range photos {
			hidden, err := h.store.TreeIsHiddenFrom(ctx, tree, viewer.owner)
			if err != nil {
				t.Fatal(err)
			}
			hero, listed := heroes[tree]
			if !listed {
				t.Fatalf("%s: fixture: tree %s has no grove row", viewer.name, tree)
			}
			switch {
			case hidden && hero != nil:
				t.Errorf("%s: the grove draws photograph %s as the hero of tree %s, which is hidden from "+
					"this viewer (GET /photos/{id} answers 404 for it)", viewer.name, *hero, tree)
			case !hidden && (hero == nil || *hero != photo):
				t.Errorf("%s: control: tree %s is visible to this viewer and its hero is %v, want %s",
					viewer.name, tree, hero, photo)
			}
			if hidden {
				hiddenCount++
			} else {
				shownCount++
			}
		}
		// The rule is exercised both ways for each viewer: the four hidden states plus the other
		// viewer's private tree, and three visible trees including this viewer's own private one.
		if hiddenCount != 5 || shownCount != 3 {
			t.Fatalf("%s: fixture: %d hidden and %d visible trees, want 5 and 3", viewer.name, hiddenCount, shownCount)
		}
	}
}

// TestAStrangersWithdrawalLeavesTheGroveAsAnUnknownIdWould is the verification's reproduction. A
// stranger sends a withdrawal for a declining account's hidden tree, which has a photograph with
// its bytes, and one for an id nobody sent. Both answer alike (F6). Afterwards the stranger's
// grove must not tell them apart either: the two rows are the same row under two ids.
func TestAStrangersWithdrawalLeavesTheGroveAsAnUnknownIdWould(t *testing.T) {
	h := newHarness(t)
	decliner := signInAs(t, h, "ct.v2.hidden.adder", nil, nil)
	hidden := uuid.New()
	mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(hidden, ctLat, ctLon, time.Now())), "declined add")
	photo := receivedPhotoFor(t, h, decliner.AccessToken, hidden)
	unknown := uuid.New()

	stranger := signInAs(t, h, "ct.v2.stranger", nil, accepted())
	first := h.syncOne(t, stranger.AccessToken, treeWithdrawalItem(hidden))
	second := h.syncOne(t, stranger.AccessToken, treeWithdrawalItem(unknown))
	if first.Status != second.Status || codeOf(first.Error) != codeOf(second.Error) {
		t.Fatalf("fixture: the two withdrawals answered %s/%s and %s/%s", first.Status, codeOf(first.Error),
			second.Status, codeOf(second.Error))
	}
	rows, _ := groveRows(t, h, stranger.AccessToken)
	if bytes.Contains(rows[hidden], []byte(photo.String())) {
		t.Fatalf("the stranger's grove names the hidden tree's photograph %s: %s", photo, rows[hidden])
	}
	if rows[hidden] == nil || rows[unknown] == nil {
		t.Fatalf("fixture: the grove has no row for one of the ids: %v", rows)
	}
	if want := bytes.ReplaceAll(rows[unknown], []byte(unknown.String()), []byte(hidden.String())); !bytes.Equal(rows[hidden], want) {
		t.Fatalf("the grove tells a hidden tree from an unknown id:\n hidden  %s\n unknown %s", rows[hidden], rows[unknown])
	}
	// The control: the photograph is real, and its adder's own grove would draw it.
	plantVisit(t, h, hidden, store.Owner{UserID: &decliner.UserID})
	if _, heroes := groveRows(t, h, decliner.AccessToken); heroes[hidden] == nil || *heroes[hidden] != photo {
		t.Fatalf("control: the adder's own grove does not draw their photograph: %v", heroes[hidden])
	}
}
