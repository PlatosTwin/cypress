package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── The order of photographs says no more than their served dates (the #190 verification's N1) ──

// beginPhotoAt begins a photograph with a chosen capture time and phone date; `receive` reports its
// bytes landed.
func beginPhotoAt(t *testing.T, h *harness, bearer string, tree uuid.UUID, at time.Time, on string, receive bool) uuid.UUID {
	t.Helper()
	code, ticket, body := beginRaw(t, h, bearer, map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": at, "captured_on": on, "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	if code != http.StatusOK {
		t.Fatalf("begin at %s: %d %s", at, code, body)
	}
	if receive {
		if recorder := h.do(t, http.MethodPost, Prefix+"/photos/"+ticket.PhotoID.String()+"/received",
			bearer, nil); recorder.Code != http.StatusOK {
			t.Fatalf("received: %d %s", recorder.Code, recorder.Body.String())
		}
	}
	return ticket.PhotoID
}

// bisect narrows [00:00, 24:00) on the target's day to under a minute, asking `newerThan(mid)`
// whether the target sorts above a probe placed at `mid`.
func bisect(newerThan func(time.Time) bool) (time.Time, time.Time, int) {
	lo, hi := time.Date(2026, 3, 14, 0, 0, 0, 0, time.UTC), time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC)
	steps := 0
	for hi.Sub(lo) > time.Minute {
		mid := lo.Add(hi.Sub(lo) / 2)
		if newerThan(mid) {
			lo = mid
		} else {
			hi = mid
		}
		steps++
	}
	return lo, hi, steps
}

// secretCapture is the adder's photograph's real capture time, 10:42 PDT. A stranger is served
// `2026-03-14T12:00:00Z` for it; the probes below may recover that, and nothing closer to this.
var (
	secretCapture = time.Date(2026, 3, 14, 17, 42, 0, 0, time.UTC)
	servedNoon    = time.Date(2026, 3, 14, 12, 0, 0, 0, time.UTC)
)

// assertRecoversOnlyTheServedDate: the bisection converged, on noon — the value it is served — and
// not on the capture time.
func assertRecoversOnlyTheServedDate(t *testing.T, what string, lo, hi time.Time, steps int) {
	t.Helper()
	if !lo.After(secretCapture) && !hi.Before(secretCapture) {
		t.Fatalf("%s: %d probes place the photograph in [%s, %s] UTC, around its capture time %s — the "+
			"order gives away the time the served date hides", what, steps, lo.Format("15:04:05"),
			hi.Format("15:04:05"), secretCapture.Format("15:04:05"))
	}
	if lo.After(servedNoon) || hi.Before(servedNoon) {
		t.Fatalf("%s: calibration: the probes converged on [%s, %s], neither the capture time nor the "+
			"served noon; they are not reading the order", what, lo.Format("15:04:05"), hi.Format("15:04:05"))
	}
}

// TestTheProfilesOrderGivesAStrangerOnlyTheServedDate is the verification's cheapest probe: an
// anonymous device begins photographs on the tree at chosen times — no bytes, so they stay pending
// and nobody else ever sees them — and reads, from the profile's order, which side of each probe the
// adder's photograph falls. Before the fix, eleven begins placed it within a minute of 17:42. Now
// the profile lists by the served value, so the probes find noon, which is what they are served.
func TestTheProfilesOrderGivesAStrangerOnlyTheServedDate(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.n1.profile.adder", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	target := beginPhotoAt(t, h, adder.AccessToken, tree, secretCapture, "2026-03-14", true)
	prober := h.registerDeviceToken(t, uuid.New())

	lo, hi, steps := bisect(func(mid time.Time) bool {
		probe := beginPhotoAt(t, h, prober, tree, mid, "2026-03-14", false)
		recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), prober, nil)
		var body struct {
			Photos []struct {
				PhotoID uuid.UUID `json:"photo_id"`
			} `json:"photos"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		for _, row := range body.Photos {
			switch row.PhotoID {
			case target:
				return true
			case probe:
				return false
			}
		}
		t.Fatalf("the profile lists neither the target nor the probe: %s", recorder.Body.String())
		return false
	})
	assertRecoversOnlyTheServedDate(t, "the profile's order", lo, hi, steps)
}

// TestTheGroveHeroGivesAStrangerOnlyTheServedDate is the same probe against the grove: a stranger
// who has visited the tree begins a photograph at a chosen time and sees whether the adder's
// photograph or their own is the hero, then takes the probe back.
func TestTheGroveHeroGivesAStrangerOnlyTheServedDate(t *testing.T) {
	h := newHarness(t)
	adder := signInAs(t, h, "ct.n1.grove.adder", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(tree, ctLat, ctLon, time.Now())), "add")
	target := beginPhotoAt(t, h, adder.AccessToken, tree, secretCapture, "2026-03-14", true)
	prober := signInAs(t, h, "ct.n1.grove.prober", nil, accepted())
	mustApply(t, h.syncOne(t, prober.AccessToken, visitItem(tree)), "the prober's visit")

	lo, hi, steps := bisect(func(mid time.Time) bool {
		probe := beginPhotoAt(t, h, prober.AccessToken, tree, mid, "2026-03-14", true)
		_, heroes := groveRows(t, h, prober.AccessToken)
		hero := heroes[tree]
		if recorder := h.do(t, http.MethodDelete, Prefix+"/photos/"+probe.String(), prober.AccessToken, nil); recorder.Code >= 300 {
			t.Fatalf("taking the probe back: %d %s", recorder.Code, recorder.Body.String())
		}
		if hero == nil || (*hero != target && *hero != probe) {
			t.Fatalf("the hero is %v, neither the target %s nor the probe %s", hero, target, probe)
		}
		return *hero == target
	})
	assertRecoversOnlyTheServedDate(t, "the grove's hero", lo, hi, steps)
}

// TestAPhotographCarriesThePhonesDateWhenItSentOne is the orchestrator's ruling on the
// verification's N2: `captured_on` travels beside `captured_at`, as the phone sent it, to the
// owner and to everybody else, on both routes; and it is absent — not null — when the phone sent
// none. It is what lets a client tell noon-of-a-date from an exact time.
func TestAPhotographCarriesThePhonesDateWhenItSentOne(t *testing.T) {
	h := newHarness(t)
	owner := signInAs(t, h, "ct.n2.owner", nil, accepted())
	stranger := h.registerDeviceToken(t, uuid.New())
	tree := uuid.New()
	dated := beginPhotoAt(t, h, owner.AccessToken, tree, time.Date(2026, 3, 15, 2, 30, 0, 0, time.UTC), "2026-03-14", true)
	code, ticket, body := beginRaw(t, h, owner.AccessToken, map[string]any{
		"tree_uuid": tree, "visit_client_uuid": nil, "shot_type": "full_tree",
		"captured_at": "2026-03-10T08:09:10Z", "width": nil, "height": nil,
		"public_lat": nil, "public_lon": nil,
	})
	if code != http.StatusOK {
		t.Fatalf("begin: %d %s", code, body)
	}
	undated := ticket.PhotoID
	if recorder := h.do(t, http.MethodPost, Prefix+"/photos/"+undated.String()+"/received", owner.AccessToken, nil); recorder.Code != http.StatusOK {
		t.Fatalf("received: %d", recorder.Code)
	}

	for who, bearer := range map[string]string{"the owner": owner.AccessToken, "a stranger": stranger} {
		profile := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
		var listed struct {
			Photos []map[string]json.RawMessage `json:"photos"`
		}
		if err := json.Unmarshal(profile.Body.Bytes(), &listed); err != nil {
			t.Fatal(err)
		}
		rows := map[string]map[string]json.RawMessage{}
		for _, row := range listed.Photos {
			var id uuid.UUID
			_ = json.Unmarshal(row["photo_id"], &id)
			rows[id.String()] = row
		}
		for photo, want := range map[uuid.UUID]string{dated: `"2026-03-14"`, undated: ""} {
			single := h.do(t, http.MethodGet, Prefix+"/photos/"+photo.String(), bearer, nil)
			var one map[string]json.RawMessage
			if err := json.Unmarshal(single.Body.Bytes(), &one); err != nil {
				t.Fatal(err)
			}
			for route, fields := range map[string]map[string]json.RawMessage{"GET /trees/{id}": rows[photo.String()], "GET /photos/{id}": one} {
				if fields == nil {
					t.Fatalf("%s: %s does not serve photograph %s", who, route, photo)
				}
				got, present := fields["captured_on"]
				switch {
				case want == "" && present:
					t.Errorf("%s: %s serves captured_on %s for a photograph whose phone sent none; "+
						"absent means absent, never null", who, route, got)
				case want != "" && !bytes.Equal(got, []byte(want)):
					t.Errorf("%s: %s serves captured_on %s, want the phone's date %s", who, route, got, want)
				}
			}
		}
	}
}

// TestPhotographsServedTheSameDateAreOrderedByIDNotByTime: the tiebreak is the id, not the stored
// time. Two strangers' photographs taken the same day are both served noon UTC; if the tie fell back
// to the capture time, the order would rank them by it, and a second identity's probes (served
// noon to the prober like the target) would bisect it again. The fixture gives the **earlier**
// photograph the **higher** id, so an order by time and an order by id disagree. Both the profile
// and the grove's hero must follow the id.
func TestPhotographsServedTheSameDateAreOrderedByIDNotByTime(t *testing.T) {
	h := newHarness(t)
	owner := signInAs(t, h, "ct.n1.tie.owner", nil, accepted())
	viewer := signInAs(t, h, "ct.n1.tie.viewer", nil, accepted())
	tree := uuid.New()
	mustApply(t, h.syncOne(t, viewer.AccessToken, visitItem(tree)), "the viewer's visit")
	morning := uuid.MustParse("ffffffff-0000-4000-8000-000000000001")
	evening := uuid.MustParse("00000000-0000-4000-8000-000000000002")
	for id, at := range map[uuid.UUID]string{morning: "2026-03-14T16:00:00Z", evening: "2026-03-15T01:00:00Z"} {
		execSQL(t, h, `
			INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, approval_reason,
			                    captured_at, captured_on, storage_key, bytes_received_at)
			VALUES ($1, $2, $3, 'full_tree', 'approved', 'auto_approved_launch', $4, '2026-03-14', $5, now())
		`, id, tree, owner.UserID, at, "photos/"+id.String())
	}

	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), viewer.AccessToken, nil)
	var body struct {
		Photos []struct {
			PhotoID    uuid.UUID `json:"photo_id"`
			CapturedAt string    `json:"captured_at"`
		} `json:"photos"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Photos) != 2 || body.Photos[0].CapturedAt != body.Photos[1].CapturedAt {
		t.Fatalf("fixture: want two photographs served the same noon: %s", recorder.Body.String())
	}
	if body.Photos[0].PhotoID != morning {
		t.Errorf("the profile lists %s first; two photographs served the same date must be ordered by id "+
			"(%s first), not by their capture times", body.Photos[0].PhotoID, morning)
	}
	if _, heroes := groveRows(t, h, viewer.AccessToken); heroes[tree] == nil || *heroes[tree] != morning {
		t.Errorf("the grove's hero is %v; between two photographs served the same date it must be the "+
			"higher id, %s, not the later capture", heroes[tree], morning)
	}
}
