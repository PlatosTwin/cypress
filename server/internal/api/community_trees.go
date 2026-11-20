package api

import (
	"errors"
	"net/http"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// takeDownCommunityTree is the operator takedown for a community tree.
//
// R72 ruling 5, "the way down ships with the way up", applied to the layer the community-trees round
// makes public: once somebody other than the adder has a visit (or observation, measurement or care
// event) or a photograph on a tree, its adder can no longer withdraw it (decision 8), and this route is what remains. A route, not a
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

// operatorSetSpecies is `POST /operator/community-trees/{id}/species` with `{"species_id": "…"}`:
// the operator corrects a community tree's species for everyone. It ends any contributor's right to
// correct their own naming and clears the reported state; see `store.OperatorSetSpecies`.
//
// The body is decoded strictly: this route has one caller, the operator, and a typo in a key is
// better refused than read as "no species". The species id is not checked against a catalog,
// because the service holds none; `server/README.md` says so.
func (s *Server) operatorSetSpecies(w http.ResponseWriter, r *http.Request) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	var body struct {
		SpeciesID *uuid.UUID `json:"species_id"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if body.SpeciesID == nil || body.SpeciesID.IsNil() {
		return apierr.New(apierr.ValidationFailed, "That request named no species.")
	}
	err = s.Store.OperatorSetSpecies(r.Context(), id, *body.SpeciesID)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That tree is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"species_id": body.SpeciesID})
	return nil
}

// operatorClearSpeciesReports is `POST /operator/community-trees/{id}/species-reports/clear`: the
// reported state clears for everyone and the species stays. A later report brings it back.
func (s *Server) operatorClearSpeciesReports(w http.ResponseWriter, r *http.Request) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}
	err = s.Store.OperatorClearSpeciesReports(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return apierr.New(apierr.NotFound, "That tree is not here.")
	}
	if err != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	writeJSON(w, s.Log, http.StatusOK, map[string]any{"species_reports_cleared": true})
	return nil
}
