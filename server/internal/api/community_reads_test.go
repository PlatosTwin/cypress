package api

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
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

// ── Community trees: the reads (S2) ────────────────────────────────────────────────────────────
//
// Every privacy assertion here is made **as somebody else, through the handler**, and each is
// paired with a control that proves the thing being hidden is really there: a test that finds no
// photograph on a hidden tree proves nothing unless the adder, asking the same route, finds one.

// ── Helpers ────────────────────────────────────────────────────────────────────────────────────

// tileOf is the zoom-14 tile holding a point, computed here from the tile scheme's own formula
// rather than through `parseTile`, so a wrong box in the handler cannot agree with itself.
func tileOf(lat, lon float64) (tile string, x, y int) {
	n := float64(int(1) << 14)
	x = int(math.Floor((lon + 180) / 360 * n))
	rad := lat * math.Pi / 180
	y = int(math.Floor((1 - math.Log(math.Tan(rad)+1/math.Cos(rad))/math.Pi) / 2 * n))
	return "14/" + itoa(x) + "/" + itoa(y), x, y
}

func itoa(v int) string { return strconv.Itoa(v) }

// northEdgeOfRow is the latitude of the northern edge of zoom-14 row y.
func northEdgeOfRow(y int) float64 {
	n := float64(int(1) << 14)
	return math.Atan(math.Sinh(math.Pi*(1-2*float64(y)/n))) * 180 / math.Pi
}

// settled is a store clock that puts the tile's horizon at the real present, so every row written
// before the call is final and every row written after it is not — the relationship production
// has, with the settle window taken out of the test's running time.
func settled() time.Time { return time.Now().UTC().Add(communityTileSettle) }

type tileTree struct {
	ID                uuid.UUID      `json:"id"`
	Source            string         `json:"source"`
	Coordinate        wireCoordinate `json:"coordinate"`
	Address           *string        `json:"address"`
	Status            string         `json:"status"`
	SpeciesCurrentID  *uuid.UUID     `json:"speciesCurrentID"`
	VerificationState string         `json:"verificationState"`
	Placement         string         `json:"placement"`
	CreatedAt         string         `json:"createdAt"`
	UpdatedAt         string         `json:"updatedAt"`
}

type tileBody struct {
	Tile             string      `json:"tile"`
	Trees            []tileTree  `json:"trees"`
	WithdrawnTreeIDs []uuid.UUID `json:"withdrawn_tree_ids"`
	NextCursor       *string     `json:"next_cursor"`
	HasMore          bool        `json:"has_more"`
	raw              []byte
}

func (b tileBody) treeIDs() []uuid.UUID {
	ids := make([]uuid.UUID, 0, len(b.Trees))
	for _, tree := range b.Trees {
		ids = append(ids, tree.ID)
	}
	return ids
}

func (b tileBody) tree(id uuid.UUID) *tileTree {
	for i := range b.Trees {
		if b.Trees[i].ID == id {
			return &b.Trees[i]
		}
	}
	return nil
}

// requestTile is `GET /community-trees` with the store's clock swapped for this one request. The
// handler reads `s.Store` per request, so the swap is exactly as wide as the call.
func requestTile(t *testing.T, h *harness, bearer, tile, cursor string, limit int, clock func() time.Time) *httptest.ResponseRecorder {
	t.Helper()
	path := Prefix + "/community-trees?tile=" + tile
	if cursor != "" {
		path += "&cursor=" + cursor
	}
	if limit > 0 {
		path += "&limit=" + itoa(limit)
	}
	if clock != nil {
		previous := h.server.Store
		h.server.Store = h.store.WithClock(clock)
		defer func() { h.server.Store = previous }()
	}
	return h.do(t, http.MethodGet, path, bearer, nil)
}

func readTile(t *testing.T, h *harness, bearer, tile, cursor string, limit int, clock func() time.Time) tileBody {
	t.Helper()
	recorder := requestTile(t, h, bearer, tile, cursor, limit, clock)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET tile %s: status = %d, body = %s", tile, recorder.Code, recorder.Body.String())
	}
	var body tileBody
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.NextCursor == nil || *body.NextCursor == "" {
		t.Fatalf("next_cursor is absent or empty; §3C says it is always present: %s", recorder.Body.String())
	}
	if body.Trees == nil || body.WithdrawnTreeIDs == nil {
		t.Fatalf("trees or withdrawn_tree_ids is null rather than a list: %s", recorder.Body.String())
	}
	body.raw = recorder.Body.Bytes()
	return body
}

func takeDown(t *testing.T, h *harness, tree uuid.UUID) {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/operator/community-trees/"+tree.String()+"/take-down",
		"the-operator-token", nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("takedown answered %d: %s", recorder.Code, recorder.Body.String())
	}
}

func execSQL(t *testing.T, h *harness, sql string, args ...any) {
	t.Helper()
	if _, err := h.store.Pool().Exec(context.Background(), sql, args...); err != nil {
		t.Fatalf("%v\n%s", err, sql)
	}
}

// seedApprovedPhoto puts a publicly visible photograph on a tree, owned by an account.
func seedApprovedPhoto(t *testing.T, h *harness, tree, owner uuid.UUID) uuid.UUID {
	t.Helper()
	id := uuid.New()
	execSQL(t, h, `
		INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, approval_reason,
		                    captured_at, storage_key, bytes_received_at)
		VALUES ($1, $2, $3, 'full_tree', 'approved', 'auto_approved_launch', now(), $4, now())
	`, id, tree, owner, "photos/"+id.String())
	return id
}

// asUnknown fetches `path` for a UUID this service has never seen and re-spells the answer for
// `tree`, so the two can be compared byte for byte. The only thing an unknown id's body may differ
// in is the id the caller asked about.
func asUnknown(t *testing.T, h *harness, bearer, pathPrefix, pathSuffix string, tree uuid.UUID) []byte {
	t.Helper()
	unknown := uuid.New()
	recorder := h.do(t, http.MethodGet, pathPrefix+unknown.String()+pathSuffix, bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("an unknown id answered %d: %s", recorder.Code, recorder.Body.String())
	}
	return bytes.ReplaceAll(recorder.Body.Bytes(), []byte(unknown.String()), []byte(tree.String()))
}

// profileOf is `GET /trees/{id}`, decoded.
type profileBody struct {
	TreeUUID uuid.UUID `json:"tree_uuid"`
	Photos   []struct {
		PhotoID uuid.UUID `json:"photo_id"`
	} `json:"photos"`
	VisitCount    int       `json:"visit_count"`
	CommunityTree *tileTree `json:"community_tree"`
	AddedByYou    *bool     `json:"added_by_you"`
	IsPublished   *bool     `json:"is_published"`
	raw           []byte
}

func profileOf(t *testing.T, h *harness, bearer string, tree uuid.UUID) profileBody {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /trees/%s: status = %d, body = %s", tree, recorder.Code, recorder.Body.String())
	}
	var body profileBody
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.AddedByYou == nil || body.IsPublished == nil {
		t.Fatalf("added_by_you or is_published is missing: %s", recorder.Body.String())
	}
	body.raw = recorder.Body.Bytes()
	return body
}

func (p profileBody) hasPhoto(id uuid.UUID) bool {
	for _, photo := range p.Photos {
		if photo.PhotoID == id {
			return true
		}
	}
	return false
}

// ── The tile ───────────────────────────────────────────────────────────────────────────────────

// TestTheTileServesPublishedTreesAndNothingElse is §3C's first sentence, asked by a stranger: the
// published, live trees in the tile, and not a byte about anybody's unpublished one.
func TestTheTileServesPublishedTreesAndNothingElse(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.tile.adder", nil, accepted())
	published := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(published, ctLat, ctLon, time.Now())), "published add")
	species := uuid.New()
	execSQL(t, h, `UPDATE community_trees SET address = '1 Main St', species_id = $2, land_context = 'street' WHERE id = $1`,
		published, species)

	// A device's tree, and a declining account's: both unpublished (decisions 1 and 7).
	deviceTree, declinedTree := uuid.New(), uuid.New()
	device := h.registerDeviceToken(t, uuid.New())
	mustApply(t, h.syncOne(t, device, addTreeAt(deviceTree, north(30), ctLon, time.Now())), "device add")
	decliner := signInAs(t, h, "ct.tile.decliner", nil, nil)
	mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(declinedTree, north(60), ctLon, time.Now())), "declined add")
	// A published tree in another tile altogether.
	elsewhere := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(elsewhere, ctLat+0.2, ctLon, time.Now())), "elsewhere add")

	tile, _, _ := tileOf(ctLat, ctLon)
	if other, _, _ := tileOf(north(60), ctLon); other != tile {
		t.Fatalf("fixture: the unpublished trees are not in the tile under test (%s vs %s)", other, tile)
	}
	stranger := h.registerDeviceToken(t, uuid.New())
	body := readTile(t, h, stranger, tile, "", 0, nil)

	if !slices.Equal(body.treeIDs(), []uuid.UUID{published}) {
		t.Fatalf("the tile served %v, want only the published tree %s", body.treeIDs(), published)
	}
	for name, hidden := range map[string]uuid.UUID{"the device's": deviceTree, "the declining account's": declinedTree} {
		if bytes.Contains(body.raw, []byte(hidden.String())) {
			t.Fatalf("%s unpublished tree's id is in a stranger's tile body — its position leaks at "+
				"tile precision: %s", name, body.raw)
		}
	}
	if len(body.WithdrawnTreeIDs) != 0 {
		t.Fatalf("a first fetch reported removals %v", body.WithdrawnTreeIDs)
	}
	if body.Tile != tile {
		t.Fatalf("tile = %q, want the request echoed as %q", body.Tile, tile)
	}

	served := body.tree(published)
	if served.Address != nil {
		t.Fatalf("the tile served the adder's address %q to a stranger", *served.Address)
	}
	if served.SpeciesCurrentID == nil || *served.SpeciesCurrentID != species {
		t.Fatalf("speciesCurrentID = %v, want %s", served.SpeciesCurrentID, species)
	}
	if served.Source != "community" || served.Status != "alive" || served.VerificationState != "unverified" ||
		served.Placement != "gps" {
		t.Fatalf("fixed fields = %+v", served)
	}
	if served.Coordinate.Latitude != ctLat || served.Coordinate.Longitude != ctLon {
		t.Fatalf("coordinate = %+v, want the head", served.Coordinate)
	}
	for _, date := range []string{served.CreatedAt, served.UpdatedAt} {
		if !strings.HasSuffix(date, "T00:00:00Z") {
			t.Fatalf("a community tree's date travels as %q; the wire carries the day only", date)
		}
	}

	// The tile is caller-independent: the adder gets the same body, address and all withheld.
	if own := readTile(t, h, adder.AccessToken, tile, "", 0, nil); own.tree(published).Address != nil {
		t.Fatal("the tile served an address to the adder; it is caller-independent and serves none")
	}
}

// TestTheTileRefusesWhatItDoesNotAnswer: any zoom but 14, a malformed tile, a bad cursor, a page
// size out of range — each `validation_failed`, which the client falls back from locally.
func TestTheTileRefusesWhatItDoesNotAnswer(t *testing.T) {
	h := newHarness(t)
	device := h.registerDeviceToken(t, uuid.New())
	tile, x, y := tileOf(ctLat, ctLon)
	cases := map[string]string{
		"zoom 13":           "tile=13/" + itoa(x/2) + "/" + itoa(y/2),
		"zoom 15":           "tile=15/" + itoa(x*2) + "/" + itoa(y*2),
		"no tile":           "",
		"two parts":         "tile=14/" + itoa(x),
		"a word":            "tile=14/abc/" + itoa(y),
		"a negative column": "tile=14/-1/" + itoa(y),
		"a signed column":   "tile=14/+" + itoa(x) + "/" + itoa(y),
		"past the last row": "tile=14/" + itoa(x) + "/16384",
		"a bad cursor":      "tile=" + tile + "&cursor=not-base64-json",
		"limit 0":           "tile=" + tile + "&limit=0",
		"limit 101":         "tile=" + tile + "&limit=101",
		"limit a word":      "tile=" + tile + "&limit=many",
	}
	for name, query := range cases {
		recorder := h.do(t, http.MethodGet, Prefix+"/community-trees?"+query, device, nil)
		if recorder.Code != http.StatusBadRequest || decodeEnvelope(t, recorder).Error.Code != string(apierr.ValidationFailed) {
			t.Errorf("%s: answered %d %s, want 400 validation_failed", name, recorder.Code, recorder.Body.String())
		}
	}
	// The controls: the same tile at zoom 14, and at the edge row, are answered.
	for _, query := range []string{"tile=" + tile, "tile=14/" + itoa(x) + "/16383", "tile=" + tile + "&limit=100"} {
		if recorder := h.do(t, http.MethodGet, Prefix+"/community-trees?"+query, device, nil); recorder.Code != http.StatusOK {
			t.Errorf("%s: answered %d %s, want 200", query, recorder.Code, recorder.Body.String())
		}
	}
	if recorder := h.do(t, http.MethodGet, Prefix+"/community-trees?tile="+tile, "", nil); recorder.Code != http.StatusUnauthorized {
		t.Errorf("no credential: answered %d, want 401", recorder.Code)
	}
}

// TestTheDeltaReportsEveryWayATreeLeaves is the delta's promise: after a first fetch, a tree that
// leaves the public set is reported by id — withdrawn by its adder, taken down by an operator,
// erased with its account — and a tree that was never public is not reported even as an id.
// A moved tree comes back with its new position.
func TestTheDeltaReportsEveryWayATreeLeaves(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.delta.adder", nil, accepted())
	withdrawn, takenDown, moved, stays := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	for i, tree := range []uuid.UUID{withdrawn, takenDown, moved, stays} {
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, north(float64(20*i)), ctLon, time.Now().Add(-time.Hour))), "add")
	}
	eraser := signInAs(t, h, "ct.delta.eraser", nil, accepted())
	erased := uuid.New()
	mustApply(t, h.syncOne(t, eraser.AccessToken, addTreeAt(erased, north(100), ctLon, time.Now().Add(-time.Hour))), "eraser's add")
	device := h.registerDeviceToken(t, uuid.New())
	private := uuid.New()
	mustApply(t, h.syncOne(t, device, addTreeAt(private, north(120), ctLon, time.Now().Add(-time.Hour))), "private add")

	tile, _, _ := tileOf(ctLat, ctLon)
	stranger := h.registerDeviceToken(t, uuid.New())
	first := readTile(t, h, stranger, tile, "", 0, settled)
	if len(first.Trees) != 5 {
		t.Fatalf("the first fetch served %d trees, want the five published ones: %v", len(first.Trees), first.treeIDs())
	}

	mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(withdrawn)), "withdrawal")
	takeDown(t, h, takenDown)
	deleteMe(t, h, eraser.AccessToken, "eraseEverything")
	if !isTombstoned(t, h, erased) {
		t.Fatal("fixture: the erase door did not tombstone the eraser's tree")
	}
	mustApply(t, h.syncOne(t, adder.AccessToken, correctionItem(moved, uuid.New(), north(45), ctLon, time.Now())), "move")
	mustApply(t, h.syncOne(t, device, treeWithdrawalItem(private)), "the private tree's withdrawal")

	delta := readTile(t, h, stranger, tile, *first.NextCursor, 0, settled)
	gone := slices.Clone(delta.WithdrawnTreeIDs)
	want := []uuid.UUID{withdrawn, takenDown, erased}
	sortIDs(gone)
	sortIDs(want)
	if !slices.Equal(gone, want) {
		t.Fatalf("withdrawn_tree_ids = %v, want exactly the withdrawn, taken-down and erased trees %v "+
			"(and never the unpublished one, %s)", delta.WithdrawnTreeIDs, want, private)
	}
	if bytes.Contains(delta.raw, []byte(private.String())) {
		t.Fatal("a tree that was never published appears in a stranger's delta")
	}
	if !slices.Equal(delta.treeIDs(), []uuid.UUID{moved}) {
		t.Fatalf("the delta served %v, want only the moved tree %s", delta.treeIDs(), moved)
	}
	if got := delta.tree(moved).Coordinate.Latitude; got != north(45) {
		t.Fatalf("the moved tree came back at latitude %v, want its new head %v", got, north(45))
	}

	// And a delta from the delta's cursor is quiet: nothing is reported twice.
	if again := readTile(t, h, stranger, tile, *delta.NextCursor, 0, settled); len(again.Trees)+len(again.WithdrawnTreeIDs) != 0 {
		t.Fatalf("a second delta repeated %v / %v", again.treeIDs(), again.WithdrawnTreeIDs)
	}
	// A new first fetch reports no removals at all: a phone with nothing cached has nothing to drop.
	if fresh := readTile(t, h, h.registerDeviceToken(t, uuid.New()), tile, "", 0, settled); len(fresh.WithdrawnTreeIDs) != 0 ||
		!slices.Equal(fresh.treeIDs(), []uuid.UUID{stays, moved}) {
		t.Fatalf("a fresh first fetch served %v and reported %v, want [%s %s] and no removals",
			fresh.treeIDs(), fresh.WithdrawnTreeIDs, stays, moved)
	}
}

func sortIDs(ids []uuid.UUID) {
	sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
}

// TestAPinMovedOutOfATileIsReportedInTheTileItLeft: without it, a phone that fetched only the old
// tile keeps drawing the tree where it used to stand.
func TestAPinMovedOutOfATileIsReportedInTheTileItLeft(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.edge.adder", nil, accepted())
	oldTile, _, y := tileOf(ctLat, ctLon)
	edge := northEdgeOfRow(y)
	near := edge - 5/111_320.0
	across := edge + 15/111_320.0
	if tile, _, _ := tileOf(near, ctLon); tile != oldTile {
		t.Fatalf("fixture: %v is not in %s", near, oldTile)
	}
	newTile, _, _ := tileOf(across, ctLon)
	if newTile == oldTile {
		t.Fatalf("fixture: %v did not cross the edge", across)
	}
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, near, ctLon, time.Now().Add(-time.Hour))), "add")

	stranger := h.registerDeviceToken(t, uuid.New())
	first := readTile(t, h, stranger, oldTile, "", 0, settled)
	if !slices.Equal(first.treeIDs(), []uuid.UUID{tree}) {
		t.Fatalf("fixture: the old tile served %v", first.treeIDs())
	}
	mustApply(t, h.syncOne(t, adder.AccessToken, correctionItem(tree, uuid.New(), across, ctLon, time.Now())), "move across the edge")

	delta := readTile(t, h, stranger, oldTile, *first.NextCursor, 0, settled)
	served := delta.tree(tree)
	if served == nil {
		t.Fatalf("the tile the pin left said nothing about it (%s); the phone keeps the old pin", delta.raw)
	}
	if served.Coordinate.Latitude != across {
		t.Fatalf("the old tile served latitude %v, want the new head %v", served.Coordinate.Latitude, across)
	}
	if other := readTile(t, h, stranger, newTile, "", 0, settled); other.tree(tree) == nil {
		t.Fatal("the tile the pin moved into does not serve it")
	}
}

// TestTheCursorNeverPassesARowThatMightStillCommit is `communityTileSettle`'s race, staged.
//
// A row stamped earlier than one already served can commit after it. The cursor must not have moved
// past it, or that tree never reaches this phone.
func TestTheCursorNeverPassesARowThatMightStillCommit(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.settle.adder", nil, accepted())
	served := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(served, ctLat, ctLon, time.Now())), "add")

	tile, _, _ := tileOf(ctLat, ctLon)
	stranger := h.registerDeviceToken(t, uuid.New())
	// The real clock: the tree was stamped moments ago, well inside the settle window.
	first := readTile(t, h, stranger, tile, "", 0, nil)
	if first.tree(served) == nil {
		t.Fatal("fixture: a tree that has committed is not served; the settle must not delay it")
	}

	// The late committer: stamped a second before the served tree, visible only now.
	var stampedAt time.Time
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT updated_at FROM community_trees WHERE id = $1`, served).Scan(&stampedAt); err != nil {
		t.Fatal(err)
	}
	late := uuid.New()
	execSQL(t, h, `
		INSERT INTO community_trees (id, lat, lon, placement, user_id, published_at, created_at, updated_at)
		VALUES ($1, $2, $3, 'gps', $4, $5, $5, $5)
	`, late, north(40), ctLon, adder.UserID, stampedAt.Add(-time.Second))

	delta := readTile(t, h, stranger, tile, *first.NextCursor, 0, nil)
	if delta.tree(late) == nil {
		t.Fatalf("a tree stamped before one already served, committed after it, never arrived: "+
			"the cursor moved past a row that could still commit (%s)", delta.raw)
	}

	// The control: once the horizon passes both, the cursor moves past them and they stop coming.
	settledBody := readTile(t, h, stranger, tile, *delta.NextCursor, 0, settled)
	if quiet := readTile(t, h, stranger, tile, *settledBody.NextCursor, 0, settled); len(quiet.Trees) != 0 {
		t.Fatalf("after the horizon passed, the cursor still re-serves %v", quiet.treeIDs())
	}
}

// TestTheTilePagesWithoutLosingOrRepeatingATree: a limit smaller than the tile's trees pages through
// all of them, once each, and says when it is done.
func TestTheTilePagesWithoutLosingOrRepeatingATree(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.pages.adder", nil, accepted())
	var want []uuid.UUID
	for i := 0; i < 5; i++ {
		tree := uuid.New()
		want = append(want, tree)
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, north(float64(15*i)), ctLon, time.Now().Add(-time.Hour))), "add")
	}
	tile, _, _ := tileOf(ctLat, ctLon)
	stranger := h.registerDeviceToken(t, uuid.New())

	var got []uuid.UUID
	var more []bool
	cursor := ""
	for page := 0; page < 5; page++ {
		body := readTile(t, h, stranger, tile, cursor, 2, settled)
		got = append(got, body.treeIDs()...)
		more = append(more, body.HasMore)
		cursor = *body.NextCursor
		if !body.HasMore {
			break
		}
	}
	if !slices.Equal(more, []bool{true, true, false}) {
		t.Fatalf("has_more ran %v over five trees at two a page, want [true true false]", more)
	}
	sortIDs(got)
	sortIDs(want)
	if !slices.Equal(got, want) {
		t.Fatalf("paging served %v, want each of %v exactly once", got, want)
	}
}

// ── The profile's additions (§3D), and the leak S1 found ───────────────────────────────────────

// TestTheProfileCarriesTheCommunityTree: a stranger can now open somebody else's community tree,
// and only its adder is told the address or "added by you".
func TestTheProfileCarriesTheCommunityTree(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.profile.adder", nil, accepted())
	tree, species := uuid.New(), uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	execSQL(t, h, `UPDATE community_trees SET address = '1 Main St', species_id = $2 WHERE id = $1`, tree, species)
	stranger := h.registerDeviceToken(t, uuid.New())

	seen := profileOf(t, h, stranger, tree)
	if seen.CommunityTree == nil || seen.CommunityTree.ID != tree {
		t.Fatalf("a stranger's profile of a published community tree carries no tree: %s", seen.raw)
	}
	if seen.CommunityTree.Address != nil || *seen.AddedByYou || !*seen.IsPublished {
		t.Fatalf("stranger: address %v, added_by_you %v, is_published %v; want nil, false, true",
			seen.CommunityTree.Address, *seen.AddedByYou, *seen.IsPublished)
	}
	if seen.CommunityTree.SpeciesCurrentID == nil || *seen.CommunityTree.SpeciesCurrentID != species {
		t.Fatalf("speciesCurrentID = %v, want %s", seen.CommunityTree.SpeciesCurrentID, species)
	}

	own := profileOf(t, h, adder.AccessToken, tree)
	if own.CommunityTree == nil || own.CommunityTree.Address == nil || *own.CommunityTree.Address != "1 Main St" ||
		!*own.AddedByYou || !*own.IsPublished {
		t.Fatalf("the adder's profile: %s; want the address, added_by_you and is_published", own.raw)
	}

	// A tree the service has no community row for keeps its pre-S2 shape plus three nulls/falses.
	city := profileOf(t, h, stranger, uuid.New())
	if city.CommunityTree != nil || *city.AddedByYou || *city.IsPublished {
		t.Fatalf("a city tree's profile: %s", city.raw)
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(city.raw, &keys); err != nil {
		t.Fatal(err)
	}
	var got []string
	for key := range keys {
		got = append(got, key)
	}
	sort.Strings(got)
	want := []string{"added_by_you", "community_tree", "deletable_photo_ids", "is_published",
		"own_photo_ids", "photo_count", "photos", "tree_uuid", "visit_count"}
	if !slices.Equal(got, want) {
		t.Fatalf("GET /trees/{id} keys = %v, want the six existing keys plus the three additive ones %v", got, want)
	}
}

// hiddenCase is one way a community tree is hidden from somebody, set up with a photograph and a
// visit on it so that "nothing is served" is a claim about something that is there.
type hiddenCase struct {
	name   string
	tree   uuid.UUID
	photo  uuid.UUID
	viewer string
	// control is a caller who **can** see the tree before it was hidden (or, for the unpublished
	// case, still can), proving the photograph was really there to hide.
	control string
}

// hiddenCommunityTrees builds the four cases the brief names, plus the erase door.
func hiddenCommunityTrees(t *testing.T, h *harness) []hiddenCase {
	t.Helper()
	adder := signInAs(t, h, "ct.hidden.adder", nil, accepted())
	photographer := signInAs(t, h, "ct.hidden.photographer", nil, accepted())
	stranger := h.registerDeviceToken(t, uuid.New())

	var cases []hiddenCase

	// Somebody else's unpublished tree: added signed out. Its adder can see it; a stranger cannot.
	deviceUUID := uuid.New()
	deviceAdder := h.registerDeviceToken(t, deviceUUID)
	unpublished := uuid.New()
	mustApply(t, h.syncOne(t, deviceAdder, addTreeAt(unpublished, ctLat, ctLon, time.Now())), "unpublished add")
	cases = append(cases, hiddenCase{name: "somebody else's unpublished tree", tree: unpublished,
		photo: seedApprovedPhoto(t, h, unpublished, photographer.UserID), viewer: stranger, control: deviceAdder})

	// Withdrawn by its adder — hidden from the adder too.
	//
	// The withdrawn tree's photograph is the adder's own: decision 8 lets the adder withdraw only
	// while nobody else has built on the tree, and a stranger's photograph would be exactly that.
	for _, c := range []struct {
		name         string
		photographer uuid.UUID
		gone         func(uuid.UUID)
	}{
		{"a tree its adder withdrew", adder.UserID, func(tree uuid.UUID) {
			mustApply(t, h.syncOne(t, adder.AccessToken, treeWithdrawalItem(tree)), "withdrawal")
		}},
		{"a tree an operator took down", photographer.UserID, func(tree uuid.UUID) { takeDown(t, h, tree) }},
	} {
		tree := uuid.New()
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, north(float64(30*(len(cases)+1))), ctLon, time.Now())), c.name)
		photo := seedApprovedPhoto(t, h, tree, c.photographer)
		if !profileOf(t, h, stranger, tree).hasPhoto(photo) {
			t.Fatalf("control: %s showed no photograph to a stranger while it was up", c.name)
		}
		c.gone(tree)
		cases = append(cases, hiddenCase{name: c.name, tree: tree, photo: photo, viewer: adder.AccessToken})
		cases = append(cases, hiddenCase{name: c.name + " (asked by a stranger)", tree: tree, photo: photo, viewer: stranger})
	}

	// Erased with its account: the tree row is gone and the tombstone remains. A photograph left
	// under its id (the erase door deletes the eraser's own; this one is seeded after) must not be
	// served either.
	eraser := signInAs(t, h, "ct.hidden.eraser", nil, accepted())
	erased := uuid.New()
	mustApply(t, h.syncOne(t, eraser.AccessToken, addTreeAt(erased, north(200), ctLon, time.Now())), "eraser's add")
	deleteMe(t, h, eraser.AccessToken, "eraseEverything")
	if !isTombstoned(t, h, erased) {
		t.Fatal("fixture: the erased tree is not tombstoned")
	}
	cases = append(cases, hiddenCase{name: "an erased tree", tree: erased,
		photo: seedApprovedPhoto(t, h, erased, photographer.UserID), viewer: stranger})

	// A visit on every hidden tree, by the photographer, so the visit count has something to leak.
	for _, c := range cases {
		execSQL(t, h, `
			INSERT INTO contributions (client_uuid, kind, tree_uuid, user_id, occurred_at, payload)
			VALUES ($1, 'visit', $2, $3, now(), '{}')
			ON CONFLICT DO NOTHING
		`, uuid.New(), c.tree, photographer.UserID)
	}
	return cases
}

// TestAHiddenCommunityTreeAnswersAsAnUnknownId is the leak S1 found, closed: `GET /trees/{id}` for a
// community tree the caller may not see serves no photograph, no visit count and no tree — the body
// is byte-for-byte what an id this service has never heard of gets.
func TestAHiddenCommunityTreeAnswersAsAnUnknownId(t *testing.T) {
	h := newHarness(t)
	for _, c := range hiddenCommunityTrees(t, h) {
		got := profileOf(t, h, c.viewer, c.tree)
		if got.hasPhoto(c.photo) || got.VisitCount != 0 || got.CommunityTree != nil {
			t.Errorf("%s: GET /trees/{id} served photographs %v, visit count %d, tree %v to a caller "+
				"who may not see it", c.name, got.Photos, got.VisitCount, got.CommunityTree)
			continue
		}
		if want := asUnknown(t, h, c.viewer, Prefix+"/trees/", "", c.tree); !bytes.Equal(got.raw, want) {
			t.Errorf("%s: the body differs from an unknown id's, so it is an oracle for the tree:\n got %s\nwant %s",
				c.name, got.raw, want)
		}
		if c.control != "" {
			own := profileOf(t, h, c.control, c.tree)
			if !own.hasPhoto(c.photo) || own.CommunityTree == nil || *own.IsPublished || !*own.AddedByYou {
				t.Errorf("control, %s: its adder should see the tree unpublished with the photograph: %s", c.name, own.raw)
			}
		}
	}
}

// TestAHiddenCommunityTreesPhotographIsNotServed: the photo ids a stranger read off a profile
// before the tree came down must not go on fetching the pictures.
func TestAHiddenCommunityTreesPhotographIsNotServed(t *testing.T) {
	h := newHarness(t)
	for _, c := range hiddenCommunityTrees(t, h) {
		recorder := h.do(t, http.MethodGet, Prefix+"/photos/"+c.photo.String(), c.viewer, nil)
		if recorder.Code != http.StatusNotFound || decodeEnvelope(t, recorder).Error.Code != string(apierr.NotFound) {
			t.Errorf("%s: GET /photos/{id} answered %d %s, want 404 not_found", c.name, recorder.Code, recorder.Body.String())
		}
	}
	// The control: the same kind of photograph on a published tree is served to a stranger.
	adder := signInAs(t, h, "ct.photo.control", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, north(500), ctLon, time.Now())), "add")
	photo := seedApprovedPhoto(t, h, tree, adder.UserID)
	if recorder := h.do(t, http.MethodGet, Prefix+"/photos/"+photo.String(), h.registerDeviceToken(t, uuid.New()), nil); recorder.Code != http.StatusOK {
		t.Fatalf("control: a published tree's approved photograph answered %d to a stranger", recorder.Code)
	}
}

// TestTheHiddenCommunityTreeIsNotOnThePublicPage: the public read has no viewer, so every hidden
// state — unpublished included, whoever added it — is the empty answer, byte for byte.
func TestTheHiddenCommunityTreeIsNotOnThePublicPage(t *testing.T) {
	h := newHarness(t)
	session := h.signIn(t, nil)
	cases := hiddenCommunityTrees(t, h)
	for _, c := range cases {
		// Each seeding is a dozen requests from one address; a fresh bucket per tree keeps the
		// phone budget (burst 60) from refusing the fixture rather than the code under test.
		h.server.limiter = ratelimit.New()
		seedOneTreeWithEverything(t, h, session.AccessToken, c.tree)
	}
	h.server.limiter = ratelimit.New()
	for _, c := range cases {
		got := h.readPublicly(t, c.tree).Body.Bytes()
		if want := asUnknown(t, h, "", Prefix+"/public/trees/", "", c.tree); !bytes.Equal(got, want) {
			t.Errorf("%s: the public page says something about it:\n got %s\nwant %s", c.name, got, want)
		}
	}
	// The control: the same seeding on a published community tree publishes its readings.
	adder := signInAs(t, h, "ct.public.control", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, north(500), ctLon, time.Now())), "add")
	h.server.limiter = ratelimit.New()
	seedOneTreeWithEverything(t, h, session.AccessToken, tree)
	var body publicTreeRead
	if err := json.Unmarshal(h.readPublicly(t, tree).Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Height == nil || !body.Beloved {
		t.Fatalf("control: a published community tree's public page is empty: %+v", body)
	}
}

// ── The history (§3E) ──────────────────────────────────────────────────────────────────────────

type historyBody struct {
	TreeUUID uuid.UUID                    `json:"tree_uuid"`
	Events   []map[string]json.RawMessage `json:"events"`
	Complete *bool                        `json:"complete"`
	raw      []byte
}

func readHistory(t *testing.T, h *harness, bearer string, tree uuid.UUID) (int, historyBody) {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String()+"/history", bearer, nil)
	var body historyBody
	if recorder.Code == http.StatusOK {
		if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if body.Complete == nil {
			t.Fatalf("complete is missing: %s", recorder.Body.String())
		}
	}
	body.raw = recorder.Body.Bytes()
	return recorder.Code, body
}

func (b historyBody) kinds() []string {
	var kinds []string
	for _, event := range b.Events {
		var kind string
		_ = json.Unmarshal(event["kind"], &kind)
		kinds = append(kinds, kind)
	}
	return kinds
}

// TestTheHistoryIsAnonymousNewestFirstAndDayPrecise is §3E's shape, asked by a stranger.
func TestTheHistoryIsAnonymousNewestFirstAndDayPrecise(t *testing.T) {
	h := newHarness(t)
	deviceUUID := uuid.New()
	adder := signInAs(t, h, "ct.history.adder", &deviceUUID, accepted())
	tree, correction, species := uuid.New(), uuid.New(), uuid.New()
	base := time.Now().UTC().Add(-72 * time.Hour)
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, base)), "add")
	mustApply(t, h.syncOne(t, adder.AccessToken, correctionItem(tree, correction, north(12), ctLon, base.Add(24*time.Hour))), "move")
	mustApply(t, h.syncOne(t, adder.AccessToken, map[string]any{
		"client_uuid": uuid.New(), "kind": "species_claim", "tree_uuid": tree,
		"occurred_at": stamp8601(base.Add(48 * time.Hour)),
		"payload":     jsonBody(map[string]any{"clientUUID": uuid.New(), "treeID": tree, "speciesID": species}),
	}), "name")

	stranger := h.registerDeviceToken(t, uuid.New())
	code, body := readHistory(t, h, stranger, tree)
	if code != http.StatusOK {
		t.Fatalf("a stranger's history of a published tree answered %d: %s", code, body.raw)
	}
	// `published` is stamped by the server when the add landed (now), so it is the newest.
	if got := body.kinds(); !slices.Equal(got, []string{"published", "species_named", "location_corrected", "added"}) {
		t.Fatalf("kinds = %v, want newest first", got)
	}
	wantKeys := []string{"from_coordinate", "from_species_id", "id", "kind", "occurred_at", "placement",
		"to_coordinate", "to_species_id"}
	for _, event := range body.Events {
		var keys []string
		for key := range event {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		if !slices.Equal(keys, wantKeys) {
			t.Fatalf("an event carries keys %v, want exactly %v — no actor field, ever", keys, wantKeys)
		}
		var at string
		_ = json.Unmarshal(event["occurred_at"], &at)
		if !strings.HasSuffix(at, "T00:00:00Z") {
			t.Fatalf("occurred_at = %q; the wire carries the day only", at)
		}
	}
	for name, id := range map[string]uuid.UUID{
		"the adder's account": adder.UserID, "the adder's device row": deviceRowID(t, h, deviceUUID),
		"the adder's device uuid": deviceUUID,
	} {
		if bytes.Contains(body.raw, []byte(id.String())) {
			t.Fatalf("%s (%s) is in the history body", name, id)
		}
	}

	var move struct {
		ID   uuid.UUID       `json:"id"`
		From *wireCoordinate `json:"from_coordinate"`
		To   *wireCoordinate `json:"to_coordinate"`
		At   string          `json:"occurred_at"`
		Pl   *string         `json:"placement"`
	}
	encoded, _ := json.Marshal(body.Events[2])
	if err := json.Unmarshal(encoded, &move); err != nil {
		t.Fatal(err)
	}
	if move.ID != correction || move.From == nil || move.From.Latitude != ctLat || move.To == nil ||
		move.To.Latitude != north(12) || move.Pl == nil || *move.Pl != "contributor_placed" ||
		move.At != dayOf(base.Add(24*time.Hour)).Format(time.RFC3339) {
		t.Fatalf("the move reads %s", encoded)
	}
	var named struct {
		To *uuid.UUID `json:"to_species_id"`
	}
	_ = json.Unmarshal(mustJSON(t, body.Events[1]), &named)
	if named.To == nil || *named.To != species {
		t.Fatalf("the naming reads %s", mustJSON(t, body.Events[1]))
	}
	if !*body.Complete {
		t.Fatal("a four-event history says it is incomplete")
	}
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	encoded, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

// TestTheHistoryIsNotFoundWhereTheTreeIsNot: a city tree, somebody else's unpublished tree, and a
// withdrawn, taken-down or erased one — one `not_found` for all. Its adder reads the history of
// their own unpublished tree.
func TestTheHistoryIsNotFoundWhereTheTreeIsNot(t *testing.T) {
	h := newHarness(t)
	stranger := h.registerDeviceToken(t, uuid.New())
	if code, body := readHistory(t, h, stranger, uuid.New()); code != http.StatusNotFound {
		t.Errorf("a city tree's history answered %d: %s", code, body.raw)
	}
	for _, c := range hiddenCommunityTrees(t, h) {
		code, body := readHistory(t, h, c.viewer, c.tree)
		if code != http.StatusNotFound {
			t.Errorf("%s: history answered %d: %s", c.name, code, body.raw)
			continue
		}
		var envelope envelopeOf
		if err := json.Unmarshal(body.raw, &envelope); err != nil || envelope.Error.Code != string(apierr.NotFound) {
			t.Errorf("%s: the refusal is not not_found: %s", c.name, body.raw)
		}
		if c.control != "" {
			if code, body := readHistory(t, h, c.control, c.tree); code != http.StatusOK || len(body.Events) == 0 {
				t.Errorf("control, %s: its adder's history answered %d: %s", c.name, code, body.raw)
			}
		}
	}
}

// TestTheHistoryIsCappedAtTwoHundred and says so.
func TestTheHistoryIsCappedAtTwoHundred(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.cap.adder", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-500*time.Hour))), "add")
	// Two events already (added, published). 199 more is 201: one over.
	execSQL(t, h, `
		INSERT INTO community_tree_events (id, tree_id, kind, occurred_at, after)
		SELECT gen_random_uuid(), $1, 'location_corrected', now() - make_interval(hours => g),
		       jsonb_build_object('lat', 37.7601, 'lon', -122.505, 'placement', 'gps')
		  FROM generate_series(1, 199) AS g
	`, tree)
	stranger := h.registerDeviceToken(t, uuid.New())
	code, body := readHistory(t, h, stranger, tree)
	if code != http.StatusOK || len(body.Events) != historyEventLimit || *body.Complete {
		t.Fatalf("201 events: status %d, %d served, complete %v; want 200 served and complete false",
			code, len(body.Events), *body.Complete)
	}
	// The control: at exactly 200 the answer is whole.
	execSQL(t, h, `DELETE FROM community_tree_events WHERE id = (
		SELECT id FROM community_tree_events WHERE tree_id = $1 AND kind = 'location_corrected' LIMIT 1)`, tree)
	if _, body := readHistory(t, h, stranger, tree); len(body.Events) != historyEventLimit || !*body.Complete {
		t.Fatalf("200 events: %d served, complete %v; want all 200 and complete true", len(body.Events), *body.Complete)
	}
}

// TestTheHistoryServesOnlyTheKindsItClassifies: an `unpublished` row — which S1 writes today and
// decision 10 retires — is a fact about the adder's consent and does not reach the wire.
func TestTheHistoryServesOnlyTheKindsItClassifies(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.kinds.adder", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now().Add(-time.Hour))), "add")
	execSQL(t, h, `INSERT INTO community_tree_events (id, tree_id, kind, occurred_at) VALUES (gen_random_uuid(), $1, 'unpublished', now())`, tree)
	_, body := readHistory(t, h, h.registerDeviceToken(t, uuid.New()), tree)
	if slices.Contains(body.kinds(), "unpublished") {
		t.Fatalf("the history served an `unpublished` event: %v", body.kinds())
	}
	if !slices.Equal(body.kinds(), []string{"published", "added"}) {
		t.Fatalf("kinds = %v, want [published added]", body.kinds())
	}
}

// ── The event vocabulary, read from the migrations ─────────────────────────────────────────────

var eventKindCheck = regexp.MustCompile(`(?s)community_tree_events_kind_is_known\s+CHECK\s*\(\s*kind\s*=\s*ANY\s*\(\s*ARRAY\s*\[(.*?)\]`)
var quotedValue = regexp.MustCompile(`'([a-z_]+)'`)

// eventKindsFromMigrations reads `community_tree_events.kind`'s vocabulary, last declaration wins.
func eventKindsFromMigrations(t *testing.T, dir string) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(dir, "*.sql"))
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(files)
	var kinds []string
	for _, file := range files {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, block := range eventKindCheck.FindAllSubmatch(source, -1) {
			kinds = nil
			for _, match := range quotedValue.FindAllSubmatch(block[1], -1) {
				kinds = append(kinds, string(match[1]))
			}
		}
	}
	if len(kinds) == 0 {
		t.Fatalf("read no community_tree_events kinds from %s — the extractor or the constraint moved", dir)
	}
	return kinds
}

// TestEveryHistoryEventKindIsClassified is the allow-list's mechanism: a kind a later migration adds
// is in neither map, and this goes red naming it, rather than the history quietly serving it.
func TestEveryHistoryEventKindIsClassified(t *testing.T) {
	declared := eventKindsFromMigrations(t, "../../migrations")
	for _, kind := range declared {
		_, withheld := withheldHistoryKinds[kind]
		if servedHistoryKinds[kind] == withheld {
			t.Errorf("event kind %q is classified %v served / %v withheld; it must be exactly one",
				kind, servedHistoryKinds[kind], withheld)
		}
	}
	for kind := range servedHistoryKinds {
		if !slices.Contains(declared, kind) {
			t.Errorf("the history serves %q, which no migration declares", kind)
		}
	}
	for kind := range withheldHistoryKinds {
		if !slices.Contains(declared, kind) {
			t.Errorf("the history withholds %q, which no migration declares", kind)
		}
	}
}

// TestTheEventKindExtractorIsCalibrated: the reader against an answer known in advance, including a
// later file that widens the vocabulary and a contributions CHECK it must not read.
func TestTheEventKindExtractorIsCalibrated(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("007_a.sql", `kind TEXT NOT NULL CONSTRAINT community_tree_events_kind_is_known CHECK (kind = ANY (ARRAY[
	    'added', 'published'])),
	ALTER TABLE contributions ADD CONSTRAINT x CHECK (kind IN ('visit', 'photo_vote'));`)
	write("009_b.sql", `ALTER TABLE community_tree_events ADD CONSTRAINT community_tree_events_kind_is_known
	    CHECK (kind = ANY (ARRAY['added', 'published', 'a_new_kind']));`)
	if got := eventKindsFromMigrations(t, dir); !slices.Equal(got, []string{"added", "published", "a_new_kind"}) {
		t.Fatalf("the extractor read %v, want the last declaration [added published a_new_kind]", got)
	}
}

// ── The golden fixtures (server/testdata/README.md) ────────────────────────────────────────────
//
// Seeded by SQL with every id and time fixed, then read through the real handler against Postgres,
// the way `public_tree.json` is — so the files are what the route writes, not what a Go struct
// would marshal.

var (
	goldenTreeA      = uuid.MustParse("5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d01")
	goldenTreeB      = uuid.MustParse("5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d02")
	goldenErased     = uuid.MustParse("5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d03")
	goldenTreeC      = uuid.MustParse("5b0c3f1e-6a2d-4e8b-9c47-1f2a3b4c5d04")
	goldenSpecies    = uuid.MustParse("7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c")
	goldenSpeciesTwo = uuid.MustParse("7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7d")
	goldenPhoto      = uuid.MustParse("8c1cc8a2-ded9-4bd5-ae4f-af2b0174bf01")
	goldenMove       = uuid.MustParse("a0d4e5f6-1111-4c2d-8e3f-000000000003")
)

func goldenTime(text string) time.Time {
	parsed, err := time.Parse(time.RFC3339, text)
	if err != nil {
		panic(err)
	}
	return parsed
}

func fixedClock(text string) func() time.Time {
	at := goldenTime(text)
	return func() time.Time { return at }
}

// seedGoldenWorld is two published trees in one tile, before anything happens to them.
//
// Tree A has a species, a stated land context, and deliberately carries seconds in its dates, so
// the files prove the wire keeps the day only. Tree B has neither species nor land context.
func seedGoldenWorld(t *testing.T, h *harness) sessionResponse {
	t.Helper()
	adder := signInAs(t, h, "ct.golden.adder", nil, accepted())
	for _, tree := range []struct {
		id              uuid.UUID
		lat, lon        float64
		species         *uuid.UUID
		placement, land any
		at              string
	}{
		{goldenTreeA, 37.7601, -122.505, &goldenSpecies, "gps", "street", "2026-09-20T17:04:11Z"},
		{goldenTreeB, 37.7605, -122.5046, nil, "contributor_placed", nil, "2026-09-21T08:30:00Z"},
	} {
		at := goldenTime(tree.at)
		execSQL(t, h, `
			INSERT INTO community_trees (id, lat, lon, address, species_id, placement, land_context,
			                             user_id, published_at, created_at, updated_at)
			VALUES ($1, $2, $3, '1 Main St', $4, $5, $6, $7, $8, $8, $8)
		`, tree.id, tree.lat, tree.lon, tree.species, tree.placement, tree.land, adder.UserID, at)
		execSQL(t, h, `
			INSERT INTO community_tree_locations (id, tree_id, lat, lon, placement, actor_user_id, occurred_at, recorded_at)
			VALUES ($1, $1, $2, $3, $4, $5, $6, $6)
		`, tree.id, tree.lat, tree.lon, tree.placement, adder.UserID, at)
		execSQL(t, h, `
			INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at, after)
			VALUES ($1, $1, 'added', $2, $3, $3, jsonb_build_object('lat', $4::float8, 'lon', $5::float8,
			        'placement', $6::text, 'species_id', $7::uuid))
		`, tree.id, adder.UserID, at, tree.lat, tree.lon, tree.placement, tree.species)
		execSQL(t, h, `
			INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at)
			VALUES ($1, $2, 'published', $3, $4::timestamptz, $4::timestamptz + interval '1 second')
		`, uuid.MustParse("a0d4e5f6-1111-4c2d-8e3f-00000000000"+tree.id.String()[35:]), tree.id, adder.UserID, at)
	}
	return adder
}

// seedGoldenChanges is what happens after the first fetch: A is moved and renamed, B is withdrawn,
// a third tree is erased with its account (only its tombstone is left), and a new tree C is added.
func seedGoldenChanges(t *testing.T, h *harness, adder sessionResponse) {
	t.Helper()
	moved := goldenTime("2026-09-26T09:15:27Z")
	// One transaction: the chain's `superseded_by` is deferred for exactly this, and the head index
	// is not, so the old head stops being one before the new row exists (`applyLocationCorrection`).
	tx, err := h.store.Pool().Begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, statement := range []struct {
		sql  string
		args []any
	}{
		{`UPDATE community_tree_locations SET superseded_by = $2 WHERE id = $1`, []any{goldenTreeA, goldenMove}},
		{`INSERT INTO community_tree_locations (id, tree_id, lat, lon, placement, location_accuracy_m,
		                                       actor_user_id, occurred_at, recorded_at)
		  VALUES ($1, $2, 37.76021, -122.50497, 'contributor_placed', 3, $3, $4, $4)`,
			[]any{goldenMove, goldenTreeA, adder.UserID, moved}},
	} {
		if _, err := tx.Exec(context.Background(), statement.sql, statement.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(context.Background()); err != nil {
		t.Fatal(err)
	}
	execSQL(t, h, `
		INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at, before, after)
		VALUES ($1, $2, 'location_corrected', $3, $4, $4,
		        '{"lat": 37.7601, "lon": -122.505, "placement": "gps"}',
		        '{"lat": 37.76021, "lon": -122.50497, "placement": "contributor_placed", "location_accuracy_m": 3}')
	`, goldenMove, goldenTreeA, adder.UserID, moved)
	renamed := goldenTime("2026-09-27T08:00:00Z")
	execSQL(t, h, `
		INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at, before, after)
		VALUES ('a0d4e5f6-1111-4c2d-8e3f-000000000004', $1, 'species_corrected', $2, $3, $3,
		        jsonb_build_object('species_id', $4::uuid), jsonb_build_object('species_id', $5::uuid))
	`, goldenTreeA, adder.UserID, renamed, goldenSpecies, goldenSpeciesTwo)
	execSQL(t, h, `
		UPDATE community_trees SET lat = 37.76021, lon = -122.50497, placement = 'contributor_placed',
		       location_accuracy_m = 3, species_id = $2, updated_at = $3 WHERE id = $1
	`, goldenTreeA, goldenSpeciesTwo, renamed)

	execSQL(t, h, `UPDATE community_trees SET deleted_at = $2, updated_at = $2 WHERE id = $1`,
		goldenTreeB, goldenTime("2026-09-26T10:00:00Z"))
	execSQL(t, h, `INSERT INTO withdrawn_community_trees (id, withdrawn_at) VALUES ($1, $2)`,
		goldenErased, goldenTime("2026-09-26T11:00:00Z"))

	added := goldenTime("2026-09-26T12:00:00Z")
	execSQL(t, h, `
		INSERT INTO community_trees (id, lat, lon, placement, land_context, user_id, published_at, created_at, updated_at)
		VALUES ($1, 37.7603, -122.5052, 'gps', 'city_park', $2, $3, $3, $3)
	`, goldenTreeC, adder.UserID, added)
}

func goldenTile(t *testing.T) string {
	tile, _, _ := tileOf(37.7601, -122.505)
	for _, point := range [][2]float64{{37.7605, -122.5046}, {37.76021, -122.50497}, {37.7603, -122.5052}} {
		if other, _, _ := tileOf(point[0], point[1]); other != tile {
			t.Fatalf("fixture: %v is in %s, not %s", point, other, tile)
		}
	}
	return tile
}

func TestCommunityTreesTileGolden(t *testing.T) {
	h := newHarness(t)
	seedGoldenWorld(t, h)
	stranger := h.registerDeviceToken(t, uuid.New())
	recorder := requestTile(t, h, stranger, goldenTile(t), "", 0, fixedClock("2026-09-25T12:00:00Z"))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "community_trees_tile.json", recorder.Body.Bytes())
}

func TestCommunityTreesTileDeltaGolden(t *testing.T) {
	h := newHarness(t)
	adder := seedGoldenWorld(t, h)
	stranger := h.registerDeviceToken(t, uuid.New())
	tile := goldenTile(t)
	first := readTile(t, h, stranger, tile, "", 0, fixedClock("2026-09-25T12:00:00Z"))
	seedGoldenChanges(t, h, adder)
	recorder := requestTile(t, h, stranger, tile, *first.NextCursor, 0, fixedClock("2026-09-28T12:00:00Z"))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "community_trees_tile_delta.json", recorder.Body.Bytes())
}

func TestTreeProfileCommunityGolden(t *testing.T) {
	h := newHarness(t)
	seedGoldenWorld(t, h)
	photographer := signInAs(t, h, "ct.golden.photographer", nil, accepted())
	execSQL(t, h, `
		INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, approval_reason,
		                    captured_at, storage_key, bytes_received_at)
		VALUES ($1, $2, $3, 'full_tree', 'approved', 'auto_approved_launch', '2026-09-22T15:00:00Z',
		        'photos/golden', '2026-09-22T15:00:05Z')
	`, goldenPhoto, goldenTreeA, photographer.UserID)
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+goldenTreeA.String(), h.registerDeviceToken(t, uuid.New()), nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "tree_profile_community.json", recorder.Body.Bytes())
}

func TestTreeHistoryGolden(t *testing.T) {
	h := newHarness(t)
	adder := seedGoldenWorld(t, h)
	seedGoldenChanges(t, h, adder)
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+goldenTreeA.String()+"/history",
		h.registerDeviceToken(t, uuid.New()), nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", recorder.Code, recorder.Body.String())
	}
	compareGolden(t, "tree_history.json", recorder.Body.Bytes())
}
