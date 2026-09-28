package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// A photograph taken signed out, and what signing in does to who can see it.
//
// `POST /photos/begin` approves a photograph at upload only for a signed-in account (R72 ruling 5),
// so one begun by an anonymous device is `pending`: drawn for its contributor and nobody else. Screen
// 15 promises that an account "lets them join each tree's public timeline", and the claim that runs
// at sign-in is what has to keep that promise for photographs the service already holds. Until the
// owner's 2026-09-28 ruling it did not: `ClaimDevice` moved the row onto the account and left it
// `pending`, and nothing else in the service ever approved it (the only other writer of its state,
// the operator's `RejectPhoto`, only takes photographs down).
//
// **Every assertion that carries the promise is made as a different caller, through the handler.**
// The promise is "somebody else can see it", and `moderation_state` is not the thing a stranger is
// shown. A test that read the column would pass in a world where the column moved and the read
// still filtered the photograph out, which is exactly the shape of the defect being closed.

// strangerSees reads `GET /trees/{id}` as `bearer` and reports whether `photo` is on the timeline,
// and if so whether the response calls it publicly visible.
func strangerSees(t *testing.T, h *harness, bearer string, tree, photo uuid.UUID) (present, public bool) {
	t.Helper()
	recorder := h.do(t, http.MethodGet, Prefix+"/trees/"+tree.String(), bearer, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("GET /trees/%s: status = %d, body = %s", tree, recorder.Code, recorder.Body.String())
	}
	var body struct {
		Photos []struct {
			PhotoID           uuid.UUID `json:"photo_id"`
			IsPubliclyVisible *bool     `json:"is_publicly_visible"`
		} `json:"photos"`
		OwnPhotoIDs []uuid.UUID `json:"own_photo_ids"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, own := range body.OwnPhotoIDs {
		if own == photo {
			t.Fatal("fixture: the reader owns this photograph, so it is not a stranger and its view " +
				"proves nothing about the public timeline")
		}
	}
	for _, entry := range body.Photos {
		if entry.PhotoID == photo {
			if entry.IsPubliclyVisible == nil {
				t.Fatal("the photograph is listed with no is_publicly_visible field; the client derives " +
					"\"public\" from nothing else")
			}
			return true, *entry.IsPubliclyVisible
		}
	}
	return false, false
}

// TestAPhotographTakenSignedOutJoinsThePublicTimelineAtSignIn is the decisive test.
//
// Anonymous begin → absent for a stranger. Sign in claiming the device → present for the same
// stranger, and called public. The first half is the control: without it a test that found the
// photograph afterwards could be finding a service that shows every photograph to everybody.
func TestAPhotographTakenSignedOutJoinsThePublicTimelineAtSignIn(t *testing.T) {
	h := newHarness(t)
	tree := uuid.New()
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	stranger := h.registerDeviceToken(t, uuid.New())

	photo := beginPhotoFor(t, h, deviceToken, tree)

	if present, _ := strangerSees(t, h, stranger, tree, photo); present {
		t.Fatal("control: a photograph begun by an anonymous device is already on a stranger's " +
			"timeline before anybody signed in, so nothing below could be attributed to the claim")
	}

	// Sign in *claiming this device* — `POST /auth/oidc` with `device_uuid`, the shipping path.
	h.signIn(t, &deviceUUID)

	present, public := strangerSees(t, h, stranger, tree, photo)
	if !present {
		t.Fatal("after its contributor signed in, a photograph they took signed out is still absent " +
			"from another person's timeline — screen 15 promised an account lets it join")
	}
	if !public {
		t.Fatal("the photograph reached a stranger's timeline marked is_publicly_visible: false")
	}
}

// TestAPhotographTakenSignedOutJoinsThePublicTimelineAtAClaim is the same promise through the other
// door: an account already signed in on this phone, then `POST /devices/claim`.
func TestAPhotographTakenSignedOutJoinsThePublicTimelineAtAClaim(t *testing.T) {
	h := newHarness(t)
	tree := uuid.New()
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	stranger := h.registerDeviceToken(t, uuid.New())

	photo := beginPhotoFor(t, h, deviceToken, tree)
	if present, _ := strangerSees(t, h, stranger, tree, photo); present {
		t.Fatal("control: the photograph is public before any claim")
	}

	session := h.signIn(t, nil)
	claim := h.do(t, http.MethodPost, Prefix+"/devices/claim", session.AccessToken,
		map[string]any{"device_uuid": deviceUUID})
	if claim.Code != http.StatusOK {
		t.Fatalf("claim: status = %d, body = %s", claim.Code, claim.Body.String())
	}

	present, public := strangerSees(t, h, stranger, tree, photo)
	if !present || !public {
		t.Fatalf("after POST /devices/claim a stranger sees present=%v public=%v, want both true",
			present, public)
	}
}

// TestAnOperatorTakedownSurvivesTheContributorSigningIn is the one approval the claim must never
// make. R72 ruling 5's takedown is not optional, and a sign-in is not an appeal.
func TestAnOperatorTakedownSurvivesTheContributorSigningIn(t *testing.T) {
	h := newHarness(t)
	tree := uuid.New()
	deviceUUID := uuid.New()
	deviceToken := h.registerDeviceToken(t, deviceUUID)
	stranger := h.registerDeviceToken(t, uuid.New())

	photo := beginPhotoFor(t, h, deviceToken, tree)
	takedown := h.do(t, http.MethodPost,
		Prefix+"/operator/photos/"+photo.String()+"/reject", "the-operator-token", nil)
	if takedown.Code != http.StatusOK {
		t.Fatalf("takedown: status = %d, body = %s", takedown.Code, takedown.Body.String())
	}

	h.signIn(t, &deviceUUID)

	if present, _ := strangerSees(t, h, stranger, tree, photo); present {
		t.Fatal("a photograph an operator took down is back on a stranger's timeline because its " +
			"contributor signed in")
	}
	var state string
	var reason *string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT moderation_state, approval_reason FROM photos WHERE id = $1`, photo,
	).Scan(&state, &reason); err != nil {
		t.Fatal(err)
	}
	if state != "rejected" || reason != nil {
		t.Fatalf("after the sign-in the row holds %q / %v, want rejected with no approval reason",
			state, reason)
	}
}
