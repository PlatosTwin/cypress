package api

import (
	"bytes"
	"net/http"
	"slices"
	"strconv"
	"testing"
	"time"

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
