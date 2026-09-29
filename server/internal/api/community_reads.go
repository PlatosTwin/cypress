package api

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── Community trees: the reads (PR S2 of the community-trees round) ─────────────────────────────
//
// Three routes serve other people's community trees to a phone: the tile (the map's layer and the
// add screen's dedupe), the profile's additions (`GET /trees/{id}`, in reads.go) and the history.
// Who may see which tree is one predicate in the store (`communityTreeFor`); this file is the wire.

// ── The shared wire form ───────────────────────────────────────────────────────────────────────

// communityWireTree is a community tree as `Tree` (wire.go's mirror), for the tile and the profile.
//
// **`address` travels only to the tree's adder** (§3C's recommendation, taken). Nothing on the
// phone sets it, so it is null today for every tree, and a modified client could otherwise publish
// free text beside somebody else's map pin. The tile is caller-independent, so it never carries one.
//
// **`createdAt` and `updatedAt` are truncated to the UTC day.** This is the orchestrator's history
// ruling ("dates on the wire truncated to the day") applied to the one other place a community
// tree's dates travel. `createdAt` is the moment the adder stood at the tree, to the second, for a
// GPS-placed pin; `updatedAt` is, among other things, the moment the adder signed in (a claim
// publishes and bumps it). A history that said "a day" beside a tile that said "18:41:46" would
// have withheld nothing. The phone never needs more: the cursor, not `updatedAt`, is how it knows
// what changed, and the adder's own rows are authored on the phone and win the merge (§5).
func communityWireTree(tree store.CommunityTreeRecord, withAddress bool) wireTree {
	var address *string
	if withAddress {
		address = tree.Address
	}
	return wireTree{
		ID:                tree.ID,
		Source:            "community",
		Coordinate:        wireCoordinate{Latitude: tree.Lat, Longitude: tree.Lon},
		Address:           address,
		Status:            "alive",
		SpeciesCurrentID:  tree.SpeciesID,
		VerificationState: "unverified",
		Placement:         tree.Placement,
		StatedLandContext: tree.LandContext,
		CreatedAt:         stamp(dayOf(tree.CreatedAt)),
		UpdatedAt:         stamp(dayOf(tree.UpdatedAt)),
	}
}

// dayOf truncates to midnight UTC — the precision every community-tree date is served at.
func dayOf(t time.Time) time.Time {
	year, month, day := t.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

// ── GET /community-trees?tile=14/x/y&cursor=&limit= ────────────────────────────────────────────

// communityTileZoom is §3C's one zoom. A phone asks for the tiles its viewport covers at 14 (about
// 1.9 km across at the corpus's latitude); any other zoom is `validation_failed`, which is a read
// failure the client falls back from locally, never a red row.
const communityTileZoom = 14

// communityTileMaxLimit caps a page (§3C: `limit ≤ 100`), and is also the default.
const communityTileMaxLimit = 100

// communityTileSettle is how far behind "now" the cursor is allowed to be, and it is the whole of
// what makes a keyset over `updated_at` safe.
//
// **The race.** Every writer stamps `updated_at` with the store's clock at the start of its
// transaction and commits later. A reader can see a row stamped 12:00:05 that committed first, then
// a row stamped 12:00:03 commits. A cursor that had advanced to 12:00:05 would never return the
// second row — a tree that never reaches that phone, with nothing to say so. That is the silent drop
// `Journal`'s own comment calls the failure this app's `Series` type exists to prevent.
//
// **The bound.** Every request's context carries `requestTimeout` (server.go), and every writer of
// `community_trees` and `withdrawn_community_trees` runs inside a request (`/sync`, `POST /trees`,
// the claim, `DELETE /me`, the takedown), so a transaction that stamped `t` has committed or died by
// `t + requestTimeout`. A row stamped at or before `now − settle` is therefore final.
//
// **What the cursor does with it.** Everything committed is served — nothing waits on the settle, so
// a tree appears at the other phone's next refresh ("instantly", decision 1) — but the returned
// cursor never moves past `now − settle`. A row newer than that is served again on the next fetch,
// which the client's upsert-by-id absorbs. Five seconds of margin over the timeout covers a COMMIT
// already in flight at the deadline.
//
// **The assumption this rests on: one machine, one clock.** The stamp (`updated_at`, a tombstone's
// `withdrawn_at`) and the horizon are both read from the Go clock of the machine serving the
// request, and the argument above compares them. `fly.toml` runs exactly one machine today. If
// `cypress-sync` ever runs two, the worst clock skew between them must be added to this margin, or
// a row stamped by a machine whose clock runs behind can land behind a cursor another machine
// already moved past it — the silent drop this constant exists to prevent.
const communityTileSettle = requestTimeout + 5*time.Second

// maxUUID is the greatest uuid, so `(horizon, maxUUID)` sorts after every row stamped at the horizon.
var maxUUID = uuid.MustParse("ffffffff-ffff-ffff-ffff-ffffffffffff")

// parseTile reads `14/x/y`. The tile scheme is the web map one every basemap uses (OSM "slippy"
// tiles): at zoom z the world is 2^z columns west to east and 2^z rows north to south, in Web
// Mercator. The canonical echo is returned so the response names the tile in one spelling.
func parseTile(raw string) (string, store.TileBounds, error) {
	invalid := apierr.New(apierr.ValidationFailed, "That tile is not one this service answers.")
	parts := strings.Split(raw, "/")
	if len(parts) != 3 {
		return "", store.TileBounds{}, invalid
	}
	var numbers [3]int
	for i, part := range parts {
		value, err := strconv.Atoi(part)
		// `Atoi` accepts a sign; a tile coordinate has none.
		if err != nil || strings.ContainsAny(part, "+-") {
			return "", store.TileBounds{}, invalid
		}
		numbers[i] = value
	}
	zoom, x, y := numbers[0], numbers[1], numbers[2]
	if zoom != communityTileZoom {
		return "", store.TileBounds{}, apierr.New(apierr.ValidationFailed,
			fmt.Sprintf("Community trees are served at zoom %d only.", communityTileZoom))
	}
	n := 1 << communityTileZoom
	if x < 0 || x >= n || y < 0 || y >= n {
		return "", store.TileBounds{}, invalid
	}
	bounds := store.TileBounds{
		West:  float64(x)/float64(n)*360 - 180,
		East:  float64(x+1)/float64(n)*360 - 180,
		North: tileRowLatitude(y, n),
		South: tileRowLatitude(y+1, n),
	}
	return fmt.Sprintf("%d/%d/%d", zoom, x, y), bounds, nil
}

// tileRowLatitude is the latitude of the northern edge of row `y` of `n`, in degrees.
func tileRowLatitude(y, n int) float64 {
	return math.Atan(math.Sinh(math.Pi*(1-2*float64(y)/float64(n)))) * 180 / math.Pi
}

// communityTileResponse is §3C's body. Server-owned, so snake_case; the trees inside are `Tree`.
type communityTileResponse struct {
	Tile             string      `json:"tile"`
	Trees            []wireTree  `json:"trees"`
	WithdrawnTreeIDs []uuid.UUID `json:"withdrawn_tree_ids"`
	NextCursor       string      `json:"next_cursor"`
	HasMore          bool        `json:"has_more"`
}

// communityTrees is `GET /community-trees`: the community layer for one tile, as a snapshot (no
// cursor) or as a delta since a cursor this route returned. Authenticated; a device credential is
// enough (§3C) — a phone that has never signed in still draws everybody's published trees.
//
// The body is the same for every caller. What it serves and what it reports as removed is
// `store.CommunityTreeTile`'s comment; how the cursor moves is `communityTileSettle`'s.
func (s *Server) communityTrees(w http.ResponseWriter, r *http.Request, _ caller) error {
	query := r.URL.Query()
	tile, bounds, err := parseTile(query.Get("tile"))
	if err != nil {
		return err
	}
	limit := communityTileMaxLimit
	if raw := query.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > communityTileMaxLimit {
			return apierr.New(apierr.ValidationFailed, "That page size is not one this service answers.")
		}
		limit = parsed
	}

	horizon := s.Store.Now().Add(-communityTileSettle)
	var (
		input tileCursor
		after *store.TileKey
	)
	if raw := query.Get("cursor"); raw != "" {
		input, err = s.openTileCursor(tile, raw)
		if err != nil {
			return err
		}
		key := input.key()
		after = &key
	} else {
		// A snapshot: the client holds nothing for this tile, so removals up to now are nothing it
		// could act on. Removals after this moment are reported on every page, so a tree served
		// on page one and withdrawn before page three is not left standing.
		since := horizon
		input.Since = &since
	}

	entries, more, err := s.Store.CommunityTreeTile(r.Context(), store.TileQuery{
		Bounds: bounds, After: after, WithdrawnSince: input.Since, Limit: limit,
	})
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	body := communityTileResponse{Tile: tile, Trees: []wireTree{}, WithdrawnTreeIDs: []uuid.UUID{}}
	next := input
	for _, entry := range entries {
		if entry.Tree != nil {
			body.Trees = append(body.Trees, communityWireTree(*entry.Tree, false))
		} else {
			body.WithdrawnTreeIDs = append(body.WithdrawnTreeIDs, entry.Key.ID)
		}
		// Entries are in keyset order, so the settled ones are a prefix.
		if !entry.Key.At.After(horizon) {
			next.At, next.ID = entry.Key.At, entry.Key.ID
		}
	}
	if !more {
		// Everything after the input cursor was read. Every row stamped at or before the horizon is
		// final, so the cursor may stand at the horizon even where this tile had nothing to say —
		// which keeps a quiet tile's next delta from re-reading every tombstone since the
		// beginning. And a snapshot that has been read to the end is a snapshot no longer.
		floor := store.TileKey{At: horizon, ID: maxUUID}
		if next.key().Less(floor) {
			next.At, next.ID = floor.At, floor.ID
		}
		next.Since = nil
	}
	// More is worth asking for only if the cursor moved; if every row on a full page is newer than
	// the horizon, the next refresh will get them again, and a loop now would get nothing new.
	body.HasMore = more && input.key().Less(next.key())
	body.NextCursor, err = s.sealTileCursor(tile, next)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, body)
	return nil
}

// ── GET /trees/{id}/history ────────────────────────────────────────────────────────────────────

// historyEventLimit is §3E's cap. `complete` says whether the answer is all of it.
const historyEventLimit = 200

// servedHistoryKinds is the set of `community_tree_events.kind` values this route may serve.
//
// **An allow-list, for `publicKinds`' reason.** The event vocabulary is 007's CHECK and it will
// widen; under an allow-list a new kind is invisible on the wire until somebody writes down why it
// should be shown. `TestEveryHistoryEventKindIsClassified` reads the vocabulary out of the
// migrations and fails when a kind is in neither map.
var servedHistoryKinds = map[string]bool{
	"added":              true,
	"published":          true,
	"location_corrected": true,
	"species_named":      true,
	"species_corrected":  true,
}

// withheldHistoryKinds is every other event kind, with the reason.
//
// S1's two kinds beyond the design's five can never appear on a history anybody may read: a
// withdrawn or taken-down tree answers `not_found` (§3E), so its `withdrawn` or `taken_down` event
// has no response to be in. They are withheld here as well, so that stays true if the not-found
// rule is ever relaxed. (S1 also wrote an `unpublished` kind until decision 10 made the license
// one-way; its fix round removed the kind from 007's CHECK, and
// `TestEveryHistoryEventKindIsClassified` is what said so here.)
var withheldHistoryKinds = map[string]string{
	"withdrawn":  "a withdrawn tree's history answers not_found (§3E), so there is no response for it to be in",
	"taken_down": "a taken-down tree's history answers not_found (§3E), so there is no response for it to be in",
}

// historyEventsServed is `servedHistoryKinds` as the query's argument, in a stable order.
func historyEventsServed() []string {
	kinds := make([]string, 0, len(servedHistoryKinds))
	for kind := range servedHistoryKinds {
		kinds = append(kinds, kind)
	}
	return kinds
}

// historyEvent is §3E's event. Server-owned and snake_case; `from_coordinate` / `to_coordinate` are
// `Coordinate` (wire.go) and nothing else here mirrors a client type.
//
// **No actor field, and no field an actor could hide in** (the orchestrator's ruling; decision 4):
// the store type it is built from does not select the actor columns.
type historyEvent struct {
	ID             uuid.UUID       `json:"id"`
	Kind           string          `json:"kind"`
	OccurredAt     Timestamp       `json:"occurred_at"`
	FromCoordinate *wireCoordinate `json:"from_coordinate"`
	ToCoordinate   *wireCoordinate `json:"to_coordinate"`
	FromSpeciesID  *uuid.UUID      `json:"from_species_id"`
	ToSpeciesID    *uuid.UUID      `json:"to_species_id"`
	Placement      *string         `json:"placement"`
}

type historyResponse struct {
	TreeUUID uuid.UUID      `json:"tree_uuid"`
	Events   []historyEvent `json:"events"`
	Complete bool           `json:"complete"`
}

func coordinateOf(p store.HistoryPosition) *wireCoordinate {
	if p.Lat == nil || p.Lon == nil {
		return nil
	}
	return &wireCoordinate{Latitude: *p.Lat, Longitude: *p.Lon}
}

// treeHistory is `GET /trees/{id}/history` (§3E): a community tree's audit log, anonymously.
//
// `not_found` for a city tree (there is no log), for somebody else's unpublished tree, and for a
// withdrawn, taken-down or erased one — one answer for all of them, so it says nothing about which.
// The adder reads the history of their own unpublished tree.
//
// Newest first, capped at 200. Every date is truncated to the UTC day: the wire carries no more
// than the screen shows. The client must decode `kind` and `placement` tolerantly, with an unknown
// case, so a kind this list admits later does not fail the whole response.
func (s *Server) treeHistory(w http.ResponseWriter, r *http.Request, who caller) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	events, complete, err := s.Store.CommunityTreeHistory(r.Context(), id, who.owner(),
		historyEventsServed(), historyEventLimit)
	if errors.Is(err, store.ErrHistoryNotFound) {
		return apierr.New(apierr.NotFound, "That tree has no history here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	body := historyResponse{TreeUUID: id, Events: make([]historyEvent, 0, len(events)), Complete: complete}
	for _, event := range events {
		body.Events = append(body.Events, historyEvent{
			ID:             event.ID,
			Kind:           event.Kind,
			OccurredAt:     stamp(dayOf(event.OccurredAt)),
			FromCoordinate: coordinateOf(event.Before),
			ToCoordinate:   coordinateOf(event.After),
			FromSpeciesID:  event.Before.SpeciesID,
			ToSpeciesID:    event.After.SpeciesID,
			Placement:      event.After.Placement,
		})
	}
	writeJSON(w, s.Log, http.StatusOK, body)
	return nil
}
