package api

import (
	"errors"
	"net/http"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
)

// takeDownCommunityTree is the operator takedown for a community tree.
//
// R72 ruling 5, "the way down ships with the way up", applied to the layer the community-trees round
// makes public: once somebody other than the adder has a live contribution or photograph on a tree,
// its adder can no longer withdraw it (decision 8), and this route is what remains. A route, not a
// screen — operator surfaces are a web deliverable (ARCHITECTURE §8).
//
// Authentication is `rejectPhoto`'s, by construction rather than by copy: both are mounted behind
// `Server.operator`, which compares the bearer against `OperatorToken` and answers `forbidden` to
// anything else.
//
// The tree stops being served at every reader's next refresh: `deleted_at` is what every read of the
// community layer filters on, and S2's tile delta reports it as withdrawn. Idempotent — a tree that
// is already down answers the same success.
func (s *Server) takeDownCommunityTree(w http.ResponseWriter, r *http.Request) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	err = s.Store.TakeDownCommunityTree(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That tree is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"taken_down": true})
	return nil
}
