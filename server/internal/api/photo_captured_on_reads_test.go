package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── Decision 14a on the reads: others see the date the phone recorded, never the time ──────────

// capturedAtOnProfile is the `captured_at` `GET /trees/{id}` serves this caller for one photograph.
func capturedAtOnProfile(t *testing.T, h *harness, bearer string, tree, photo uuid.UUID) string {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
	var body struct {
		Photos []struct {
			PhotoID    uuid.UUID `json:"photo_id"`
			CapturedAt string    `json:"captured_at"`
		} `json:"photos"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, row := range body.Photos {
		if row.PhotoID == photo {
			return row.CapturedAt
		}
	}
	t.Fatalf("GET /trees/%s does not list photograph %s: %s", tree, photo, recorder.Body.String())
	return ""
}

// capturedAtOnPhoto is the `captured_at` `GET /photos/{id}` serves this caller.
func capturedAtOnPhoto(t *testing.T, h *harness, bearer string, photo uuid.UUID) string {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/photos/"+photo.String(), bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /photos/%s: %d %s", photo, recorder.Code, recorder.Body.String())
	}
	var body struct {
		CapturedAt string `json:"captured_at"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body.CapturedAt
}

// TestOthersSeeAPhotographsDateAndItsOwnerTheTime is decision 14a on both routes that serve
// `captured_at`. Three photographs taken in San Francisco — in the morning, in the evening (when the
// UTC date is already the next day), and on the evening of a month's last day — each carry the
// phone's local date. A stranger is served noon UTC of that date on the profile and on the
// photograph read, and none of the exact times appears anywhere in what the stranger receives. The
// photograph's owner is served the exact time on both. A photograph from a build that sent no
// `captured_on` keeps today's behavior: the exact time, for everyone.
func TestOthersSeeAPhotographsDateAndItsOwnerTheTime(t *testing.T) {
	h := newHarness(t)
	owner := signInAs(t, h, "ct.d14.owner", nil, accepted())
	stranger := signInAs(t, h, "ct.d14.stranger", nil, accepted())
	tree := uuid.New() // a city tree: decision 14 covers every tree's photographs

	cases := []struct {
		name, capturedAt string
		capturedOn       any
		toOthers         string
	}{
		{"a morning in San Francisco", "2026-03-14T17:00:00Z", "2026-03-14", "2026-03-14T12:00:00Z"},
		{"an evening in San Francisco, already the 15th in UTC", "2026-03-15T02:30:00Z", "2026-03-14", "2026-03-14T12:00:00Z"},
		{"the evening of March 31, already April in UTC", "2026-04-01T01:00:00Z", "2026-03-31", "2026-03-31T12:00:00Z"},
		{"a build that sent no captured_on", "2026-03-10T08:09:10Z", nil, "2026-03-10T08:09:10Z"},
	}
	for _, c := range cases {
		code, ticket, body := beginRaw(t, h, owner.AccessToken, map[string]any{
			"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
			"captured_at": c.capturedAt, "captured_on": c.capturedOn, "width": nil, "height": nil,
			"public_lat": nil, "public_lon": nil,
		})
		if code != http.StatusOK {
			t.Fatalf("%s: begin answered %d %s", c.name, code, body)
		}
		if recorder := h.do(t, http.MethodPost, Prefix+"/photos/"+ticket.PhotoID.String()+"/received",
			owner.AccessToken, nil); recorder.Code != http.StatusOK {
			t.Fatalf("%s: received answered %d", c.name, recorder.Code)
		}

		for route, got := range map[string]string{
			"GET /trees/{id}":  capturedAtOnProfile(t, h, stranger.AccessToken, tree, ticket.PhotoID),
			"GET /photos/{id}": capturedAtOnPhoto(t, h, stranger.AccessToken, ticket.PhotoID),
		} {
			if got != c.toOthers {
				t.Errorf("%s: %s serves a stranger captured_at %s, want %s", c.name, route, got, c.toOthers)
			}
		}
		for route, got := range map[string]string{
			"GET /trees/{id}":  capturedAtOnProfile(t, h, owner.AccessToken, tree, ticket.PhotoID),
			"GET /photos/{id}": capturedAtOnPhoto(t, h, owner.AccessToken, ticket.PhotoID),
		} {
			if got != c.capturedAt {
				t.Errorf("%s: %s serves the photograph's owner %s, want its exact time %s", c.name, route, got, c.capturedAt)
			}
		}
	}

	// Nothing a stranger receives carries a dated photograph's time of day.
	profile := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), stranger.AccessToken, nil).Body.Bytes()
	for _, clock := range []string{"T17:00:00Z", "T02:30:00Z", "T01:00:00Z"} {
		if bytes.Contains(profile, []byte(clock)) {
			t.Errorf("the stranger's profile carries a capture time %s: %s", clock, profile)
		}
	}
}
