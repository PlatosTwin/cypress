package api

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The Class R reads. What these return that a phone cannot is the *other devices of the same
// account* — which is why R36 puts the community and account layers on the live side, and why the
// client's fallback to its local answer is degraded rather than wrong (spec §3.1).

func (s *Server) grove(w http.ResponseWriter, r *http.Request, who caller) error {
	entries, err := s.Store.Grove(r.Context(), who.owner())
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	rows := make([]map[string]any, 0, len(entries))
	for _, entry := range entries {
		rows = append(rows, map[string]any{
			"tree_uuid":       entry.TreeUUID,
			"last_visited_at": stampOrNil(entry.LastVisitedAt),
			"is_favorite":     entry.IsFavorite,
			// `GroveRecord`, in its own keys. camelCase inside a snake_case response on purpose —
			// it reconstructs a client type, so it speaks that type's synthesized names (wire.go).
			"record": wireGroveRecord{
				Visits:       entry.Record["visits"],
				CheckIns:     entry.Record["checkIns"],
				Measurements: entry.Record["measurements"],
				CareEvents:   entry.Record["careEvents"],
			},
			// #176's hero: the photograph the row draws instead of the accent tile. A photo fact
			// the phone cannot answer for a photograph it never wrote.
			"hero_photo_id": entry.HeroPhotoID,
		})
	}
	// `total` is stated because this read counted the whole set rather than a page. `Series` exists
	// on the client to make "a page counted as a total" unwritable (ERRATA E38), and the server side
	// of that contract is: say the total only where it is one.
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"entries": rows, "total": len(rows)})
	return nil
}

func (s *Server) groveSpecies(w http.ResponseWriter, r *http.Request, who caller) error {
	known, err := s.Store.GroveSpeciesKnown(r.Context(), who.owner())
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	rows := make([]map[string]any, 0, len(known))
	for _, entry := range known {
		rows = append(rows, map[string]any{"species_id": entry.SpeciesID, "first_met": stamp(entry.FirstMet)})
	}
	// The neighborhood half — screen 08's ring denominator — is a fact about the *city's inventory*,
	// which is Class L and lives in the installed city file (R36). It is deliberately not answered
	// here: `GrovePresentation` intersects the two, and a server that guessed at the denominator
	// would be answering a question it has no table for.
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"known": rows, "total": len(rows)})
	return nil
}

func (s *Server) isFavorite(w http.ResponseWriter, r *http.Request, who caller) error {
	treeID, err := parsePathUUID(r, "treeID")
	if err != nil {
		return err
	}
	favorite, storeErr := s.Store.IsFavorite(r.Context(), who.owner(), treeID)
	if storeErr != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", storeErr)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"is_favorite": favorite})
	return nil
}

func (s *Server) mapMembership(w http.ResponseWriter, r *http.Request, who caller) error {
	kind := r.URL.Query().Get("kind")
	if kind != "yours" && kind != "favorites" {
		// The two cases of `MapMembership`, spelled the American way on the owner's instruction
		// (R23.1). An unknown kind is a validation failure rather than an empty set, because an
		// empty set is a *claim* — screen 01 would draw a map on which this reader owns and hearts
		// nothing, which is the exact #76 hazard the client-side default already caused once.
		return apierr.New(apierr.ValidationFailed, "That membership kind is not one this service answers.")
	}
	ids, err := s.Store.MapMembership(r.Context(), who.owner(), kind)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	if ids == nil {
		ids = []uuid.UUID{}
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"kind": kind, "tree_ids": ids})
	return nil
}

// journalCursor is the opaque `(occurred_at, client_uuid)` pair.
//
// Opaque so that the pagination key is not a promise: a client that parsed an offset out of it
// would break the day the ordering changes. Encoded rather than signed — it names nothing private,
// and forging one can only reveal rows the caller's own identity clause already allows.
type journalCursor struct {
	OccurredAt time.Time `json:"o"`
	ClientUUID uuid.UUID `json:"c"`
}

func (s *Server) journal(w http.ResponseWriter, r *http.Request, who caller) error {
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 200 {
			return apierr.New(apierr.ValidationFailed, "That page size is not one this service answers.")
		}
		limit = parsed
	}

	var cursorAt *time.Time
	var cursorID *uuid.UUID
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		if err != nil {
			return apierr.New(apierr.ValidationFailed, "That page marker is not valid.")
		}
		var cursor journalCursor
		if err := json.Unmarshal(decoded, &cursor); err != nil {
			return apierr.New(apierr.ValidationFailed, "That page marker is not valid.")
		}
		cursorAt = &cursor.OccurredAt
		cursorID = &cursor.ClientUUID
	}

	entries, err := s.Store.Journal(r.Context(), who.owner(), cursorAt, cursorID, limit)
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}

	rows := make([]map[string]any, 0, len(entries))
	for _, entry := range entries {
		rows = append(rows, map[string]any{
			"client_uuid": entry.ClientUUID,
			"kind":        entry.Kind,
			"tree_uuid":   entry.TreeUUID,
			"occurred_at": stamp(entry.OccurredAt),
			"payload":     json.RawMessage(entry.Payload),
		})
	}

	var next string
	if len(entries) == limit {
		last := entries[len(entries)-1]
		encoded, err := json.Marshal(journalCursor{OccurredAt: last.OccurredAt, ClientUUID: last.ClientUUID})
		if err != nil {
			return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
		}
		next = base64.RawURLEncoding.EncodeToString(encoded)
	}

	// No `total`. This is a page, and `Page<Element>` is a page — stating a total here is the
	// mistake ERRATA E38 records, and it is the reason `grove` above may state one and this may not.
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"items": rows, "next_cursor": next})
	return nil
}

// treeProfile answers the community half, and only the community half.
//
// The city-layer half — the tree's position, its species, its inventory row — is Class L and is
// answered from the installed city file (R36). This route returning it as well would put the map's
// own data on the network for no gain, which is the argument spec §1.2 makes at length.
//
// This is the **R-required** grade: for `grove` a local fallback is a complete answer for what this
// device did, but here the local answer is missing precisely the thing the read is for. "The photo
// propagates to all other users" *is* this response carrying a photograph the reading device never
// wrote.
func (s *Server) treeProfile(w http.ResponseWriter, r *http.Request, who caller) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	community, storeErr := s.Store.TreeCommunityHalf(r.Context(), id, who.owner())
	if storeErr != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", storeErr)
	}

	type shown struct {
		photo store.PhotoRecord
		own   bool
		at    Timestamp
	}
	visible := make([]shown, 0, len(community.Photos))
	for _, photo := range community.Photos {
		own := ownsPhoto(photo, who)
		// The single predicate, server side: publicly visible to anyone, or visible to its own
		// contributor. Nothing else is drawn (ERRATA E37, E215).
		if !photo.IsPubliclyVisible() && !(own && photo.IsVisibleToItsContributor()) {
			continue
		}
		visible = append(visible, shown{photo: photo, own: own, at: servedCapturedAt(photo, own)})
	}
	// **Listed by what this caller is served, not by the stored time** (the #190 verification's N1).
	// The store reads the photographs in `captured_at` order, and `captured_at` is a value any caller
	// chooses for their own photographs at begin. Listed in that order, a stranger who is served only
	// a date could place their own photographs at chosen times and read, from which side of each one
	// another person's photograph fell, the time the served value hides — to the minute in eleven
	// begins. Sorted by the served value, then the id, the order says nothing the values do not.
	sort.SliceStable(visible, func(i, j int) bool {
		a, b := time.Time(visible[i].at), time.Time(visible[j].at)
		if !a.Equal(b) {
			return a.After(b)
		}
		return bytes.Compare(visible[i].photo.ID[:], visible[j].photo.ID[:]) > 0
	})

	photos := make([]map[string]any, 0, len(visible))
	ownPhotoIDs := make([]uuid.UUID, 0)
	deletablePhotoIDs := make([]uuid.UUID, 0)
	for _, row := range visible {
		photos = append(photos, servedPhotoFields(row.photo, row.at, map[string]any{
			"photo_id":  row.photo.ID,
			"shot_type": row.photo.ShotType,
			// Sent so the client can tell "everyone sees this" from "only you do" without
			// re-deriving it — which is what makes screen 15's promise legible on screen.
			"is_publicly_visible": row.photo.IsPubliclyVisible(),
		}))
		if row.own {
			ownPhotoIDs = append(ownPhotoIDs, row.photo.ID)
			// `deletePhoto` must be reachable wherever a photograph is shown (R72 ruling 5), so the
			// set that drives that affordance ships with the photographs rather than after them.
			deletablePhotoIDs = append(deletablePhotoIDs, row.photo.ID)
		}
	}

	// ── S2's three additions (§3D), additive: every key above is unchanged ─────────────────────
	//
	// `community_tree` is the tree itself when the id names a community tree this caller may see —
	// published, or added by the caller, and not withdrawn, taken down or erased — and null
	// otherwise. It is the only way a phone can open the profile of a tree somebody else added: the
	// tree is in no city pack and in none of this phone's own tables (§0). A community tree hidden
	// from this caller produced a zero `community` above, so everything in this body is byte-for-byte
	// what an id this service has never heard of produces.
	//
	// `added_by_you` is §4's rule, answered by the service because the phone cannot always answer it
	// (a tree added on the same account's other phone). `is_published` is whether anybody but the
	// adder can see it — false for the adder's own tree under a declined license, or added signed out
	// and not yet claimed.
	var tree *wireTree
	addedByYou, isPublished := false, false
	if community.Tree != nil {
		served := communityWireTree(*community.Tree, community.Tree.AddedByViewer)
		tree = &served
		addedByYou, isPublished = community.Tree.AddedByViewer, community.Tree.Published
	}

	writeJSON(w, s.Log, http.StatusOK, map[string]any{
		"tree_uuid":           id,
		"photos":              photos,
		"photo_count":         len(photos),
		"visit_count":         community.VisitCount,
		"own_photo_ids":       ownPhotoIDs,
		"deletable_photo_ids": deletablePhotoIDs,
		"community_tree":      tree,
		"added_by_you":        addedByYou,
		"is_published":        isPublished,
	})
	return nil
}
