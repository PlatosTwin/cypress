package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// TestANonVersionAfterAnAcceptanceUnpublishesNothing is L2 read against decision 10. L2 records a
// license_version that is not a known version ("" or an unknown string) as a decline. Decision 10
// makes the license one-way: a decline after an acceptance must leave the trees published under
// that acceptance exactly as they are, and keep private only trees added after it. So an account
// that accepted, published, and then signs in sending a non-version keeps its public tree public,
// with no new history, and its next tree stays private.
func TestANonVersionAfterAnAcceptanceUnpublishesNothing(t *testing.T) {
	for i, nonVersion := range []string{"", "odbl-9.9"} {
		t.Run("license_version "+nonVersion, func(t *testing.T) {
			h := newHarness(t)
			subject := "ct.l2.oneway." + nonVersion
			account := signInAs(t, h, subject, nil, accepted())
			before, after := uuid.New(), uuid.New()
			mustApply(t, h.syncOne(t, account.AccessToken, addTreeAt(before, north(float64(200*i)), ctLon, time.Now())), "add")
			if !stateOf(t, h, before).Published {
				t.Fatal("control: the tree was not published under the accepted license")
			}

			version := nonVersion
			again := signInAs(t, h, subject, nil, &version)
			var stored *string
			if err := h.store.Pool().QueryRow(context.Background(),
				`SELECT license_version FROM users WHERE id = $1`, again.UserID).Scan(&stored); err != nil {
				t.Fatal(err)
			}
			if stored != nil {
				t.Fatalf("fixture: license_version %q was stored as %q; L2 records it as a decline", nonVersion, *stored)
			}

			if !stateOf(t, h, before).Published {
				t.Fatalf("decision 10: license_version %q after an acceptance unpublished a tree published under it", nonVersion)
			}
			if events := eventsOf(t, h, before); len(events) != 2 {
				t.Fatalf("the non-version answer wrote to the published tree's history: %+v", events)
			}
			stranger := h.registerDeviceToken(t, uuid.New())
			if code, candidates := postTree(t, h, stranger, uuid.New(), north(float64(200*i)+3), ctLon); code != http.StatusConflict ||
				len(candidates) != 1 || candidates[0] != before {
				t.Fatalf("after the non-version answer a stranger 3 m away got %d %v; the tree should still be seen", code, candidates)
			}

			mustApply(t, h.syncOne(t, again.AccessToken, addTreeAt(after, north(float64(200*i)+60), ctLon, time.Now())), "add after")
			if stateOf(t, h, after).Published {
				t.Fatalf("a tree added after license_version %q was published: L2 did not make it a decline", nonVersion)
			}
			assertPublicationInvariant(t, h)
		})
	}
}
