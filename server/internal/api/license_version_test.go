package api

import (
	"context"
	"net/http"
	"os"
	"regexp"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── Only a known license version is an acceptance (the #187 verification's L2) ──────────────────

// TestOnlyAKnownLicenseVersionIsAnAcceptance: an empty string, an unknown version, and the right
// version in the wrong case publish nothing, through either door that records consent, and a
// value like that already stored (written before this rule) does not count either. The control is
// the real version, which publishes and is what the `published` event records.
func TestOnlyAKnownLicenseVersionIsAnAcceptance(t *testing.T) {
	h := newHarness(t)
	for i, version := range []string{"", "odbl-9.9", "ODBL-1.0"} {
		spot := float64(200 * (i + 1))
		// At sign-in.
		signedIn := signInAs(t, h, "ct.l2.oidc."+version, nil, &version)
		tree := uuid.New()
		mustApply(t, h.syncOne(t, signedIn.AccessToken, addTreeAt(tree, north(spot), ctLon, time.Now())), "add")
		if stateOf(t, h, tree).Published {
			t.Errorf("license_version %q at sign-in published the account's tree", version)
		}

		// At a device claim, over trees added signed out.
		deviceUUID := uuid.New()
		device := h.registerDeviceToken(t, deviceUUID)
		claimed := uuid.New()
		mustApply(t, h.syncOne(t, device, addTreeAt(claimed, north(spot+50), ctLon, time.Now())), "signed-out add")
		account := h.signIn(t, nil)
		if recorder := h.do(t, http.MethodPost, Prefix+"/devices/claim", account.AccessToken,
			map[string]any{"device_uuid": deviceUUID, "license_version": version}); recorder.Code != http.StatusOK {
			t.Fatalf("claim with %q answered %d: %s", version, recorder.Code, recorder.Body.String())
		}
		if stateOf(t, h, claimed).Published {
			t.Errorf("license_version %q at a device claim published the claimed tree", version)
		}
	}

	// An account that declined and holds a private tree, then sends a non-version: the acceptance
	// sweep must not run, or it would publish the tree with that string as its license.
	for i, version := range []string{"", "odbl-9.9"} {
		subject := "ct.l2.sweep." + itoa(i)
		decliner := signInAs(t, h, subject, nil, nil)
		private := uuid.New()
		mustApply(t, h.syncOne(t, decliner.AccessToken, addTreeAt(private, north(float64(1300+100*i)), ctLon, time.Now())), "declined add")
		signInAs(t, h, subject, nil, &version)
		if stateOf(t, h, private).Published {
			t.Errorf("a declining account's private tree was published by license_version %q", version)
		}
	}

	// A value stored before this rule, by the old consent parser.
	stored := signInAs(t, h, "ct.l2.stored", nil, accepted())
	execSQL(t, h, `UPDATE users SET license_version = '' WHERE id = $1`, stored.UserID)
	tree := uuid.New()
	mustApply(t, h.syncOne(t, stored.AccessToken, addTreeAt(tree, north(1000), ctLon, time.Now())), "add under a stored \"\"")
	if stateOf(t, h, tree).Published {
		t.Error(`an account whose stored license_version is "" published a tree`)
	}

	// The control: the version the client sends publishes, and the event names it.
	control := signInAs(t, h, "ct.l2.control", nil, accepted())
	live := uuid.New()
	mustApply(t, h.syncOne(t, control.AccessToken, addTreeAt(live, north(1100), ctLon, time.Now())), "control add")
	var recorded *string
	if err := h.store.Pool().QueryRow(context.Background(), `
		SELECT after->>'license_version' FROM community_tree_events WHERE tree_id = $1 AND kind = 'published'
	`, live).Scan(&recorded); err != nil {
		t.Fatalf("control: no published event: %v", err)
	}
	if !stateOf(t, h, live).Published || recorded == nil || *recorded != *accepted() {
		t.Fatalf("control: the known version did not publish, or the event recorded %v", recorded)
	}
}

// clientLicenseVersion reads `LicenseConsent.currentVersion` out of the client's source.
var clientLicenseVersion = regexp.MustCompile(`(?m)^\s*public static let currentVersion = "([^"]*)"`)

// TestTheServerKnowsTheClientsLicenseVersion: the version the shipped client sends is one this
// service honors. When legal review moves the client's constant, this goes red until the service
// learns the new version in the same change — otherwise every new acceptance would silently be
// recorded as a decline, and nobody's tree would go live.
func TestTheServerKnowsTheClientsLicenseVersion(t *testing.T) {
	source, err := os.ReadFile("../../../Cypress/Core/AccountLinkRecord.swift")
	if err != nil {
		t.Fatal(err)
	}
	matches := clientLicenseVersion.FindAllStringSubmatch(string(source), -1)
	if len(matches) != 1 {
		t.Fatalf("found %d declarations of LicenseConsent.currentVersion, want exactly 1: the extractor "+
			"is not reading what it thinks it is", len(matches))
	}
	if version := matches[0][1]; !store.IsKnownLicenseVersion(version) {
		t.Fatalf("the client sends license_version %q, which this service does not count as an acceptance", version)
	}
	// Calibration: the extractor finds a declaration where one is, and the rule refuses what it
	// should, so a green here is about the client's constant and not about the reader.
	if got := clientLicenseVersion.FindStringSubmatch(`    public static let currentVersion = "x-1"`); got == nil || got[1] != "x-1" {
		t.Fatalf("the extractor does not read a declaration: %v", got)
	}
	if store.IsKnownLicenseVersion("") {
		t.Fatal(`"" is a known license version`)
	}
}
