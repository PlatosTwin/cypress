package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// M11: the parked revocations are drained, and the retention is bounded.
//
// B5 established that a failed revocation must not discard the token. This is the other half: a
// queue nothing reads is an obligation recorded rather than discharged, and an unbounded one is an
// indefinite pointer to the identity of everybody whose deletion hit an outage — held after a
// screen that promised erasure.

// parkOneRevocation drives a real deletion whose revocation fails, and returns the parked token.
func parkOneRevocation(t *testing.T, h *harness) string {
	t.Helper()
	session := h.signIn(t, nil)
	h.apple.revokeErr = errors.New("Apple is having a day")

	recorder := h.do(t, http.MethodDelete, Prefix+"/me", session.AccessToken,
		map[string]any{"choice": "eraseEverything", "pending_client_uuids": []uuid.UUID{}})
	if recorder.Code != http.StatusOK {
		t.Fatalf("deletion returned %d: %s", recorder.Code, recorder.Body.String())
	}

	parked, err := h.store.PendingAppleRevocations(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(parked) != 1 {
		t.Fatalf("%d tokens parked, want 1", len(parked))
	}
	return parked[0].RefreshToken
}

func countParked(t *testing.T, h *harness) int {
	t.Helper()
	parked, err := h.store.PendingAppleRevocations(context.Background(), 100)
	if err != nil {
		t.Fatal(err)
	}
	return len(parked)
}

// TestTheDrainDischargesTheObligation is the success path.
func TestTheDrainDischargesTheObligation(t *testing.T) {
	h := newHarness(t)
	token := parkOneRevocation(t, h)

	// Apple recovers.
	h.apple.revokeErr = nil
	h.apple.revoked = nil

	revoked, failed, abandoned := DrainAppleRevocations(
		context.Background(), h.store, h.apple, slog.Default())

	if revoked != 1 || failed != 0 || abandoned != 0 {
		t.Fatalf("drain reported revoked=%d failed=%d abandoned=%d, want 1/0/0", revoked, failed, abandoned)
	}
	if len(h.apple.revoked) != 1 || h.apple.revoked[0] != token {
		t.Fatalf("the drain revoked %v, want the parked token", h.apple.revoked)
	}
	if remaining := countParked(t, h); remaining != 0 {
		t.Fatalf("%d tokens still parked after a successful revocation; the queue would never "+
			"drain and the credential would be held to its TTL for nothing", remaining)
	}
}

// TestAFailedDrainRecordsTheAttempt pins the two columns that were previously unreachable.
//
// The `ON CONFLICT` arm that would have written them could only fire if the same token were parked
// twice, and it cannot be — the `users` row it came from is deleted in the same transaction. So
// `attempts` was always 1 and `last_attempted_at` always equalled `first_failed_at`: state shaped
// like a retry record that recorded nothing.
func TestAFailedDrainRecordsTheAttempt(t *testing.T) {
	h := newHarness(t)
	parkOneRevocation(t, h)

	// Apple stays down.
	revoked, failed, abandoned := DrainAppleRevocations(
		context.Background(), h.store, h.apple, slog.Default())
	if revoked != 0 || failed != 1 || abandoned != 0 {
		t.Fatalf("drain reported revoked=%d failed=%d abandoned=%d, want 0/1/0", revoked, failed, abandoned)
	}

	parked, err := h.store.PendingAppleRevocations(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(parked) != 1 {
		t.Fatalf("%d parked after a failed retry, want 1 — a refusal must not discard the token", len(parked))
	}
	if parked[0].Attempts != 2 {
		t.Fatalf("attempts = %d after one retry, want 2; the column records nothing otherwise",
			parked[0].Attempts)
	}

	// And again, so the count is a count rather than a flag.
	DrainAppleRevocations(context.Background(), h.store, h.apple, slog.Default())
	parked, err = h.store.PendingAppleRevocations(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if parked[0].Attempts != 3 {
		t.Fatalf("attempts = %d after two retries, want 3", parked[0].Attempts)
	}
}

// TestRetentionIsBoundedAndAbandonmentIsLoud is the TTL.
//
// A revocation that has not succeeded in `AppleRevocationTTL` is not going to succeed by waiting,
// and continuing to hold the credential would be an indefinite identity pointer standing on a
// promise of erasure. The row goes — and the abandonment is logged at error level, because a
// compliance obligation that will now never be met is an operator's problem and must not vanish
// quietly.
func TestRetentionIsBoundedAndAbandonmentIsLoud(t *testing.T) {
	h := newHarness(t)
	parkOneRevocation(t, h)

	// Age the row past the limit.
	_, err := h.store.Pool().Exec(context.Background(),
		`UPDATE pending_apple_revocations SET first_failed_at = $1`,
		time.Now().UTC().Add(-AppleRevocationTTL-time.Hour))
	if err != nil {
		t.Fatal(err)
	}

	var logged bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&logged, &slog.HandlerOptions{Level: slog.LevelInfo}))

	revoked, failed, abandoned := DrainAppleRevocations(context.Background(), h.store, h.apple, log)
	if abandoned != 1 {
		t.Fatalf("drain reported abandoned=%d (revoked=%d failed=%d), want 1", abandoned, revoked, failed)
	}
	if remaining := countParked(t, h); remaining != 0 {
		t.Fatalf("%d tokens still held past the retention limit", remaining)
	}

	// The expired row must not have been handed to Apple on the way out — retrying it would be one
	// more exchange of the credential this pass exists to stop holding.
	if len(h.apple.revoked) != 1 {
		t.Errorf("Apple was called %d times during the expiry pass; the deletion's own attempt is "+
			"the only one that should appear", len(h.apple.revoked))
	}

	if logged.Len() == 0 {
		t.Fatal("nothing was logged when a revocation was abandoned")
	}
	var sawError bool
	for _, line := range strings.Split(strings.TrimSpace(logged.String()), "\n") {
		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}
		if entry["level"] == "ERROR" && strings.Contains(entry["msg"].(string), "ABANDONED") {
			sawError = true
			if entry["attempts"] == nil {
				t.Error("the abandonment log does not say how many attempts were made")
			}
			if entry["first_failed_at"] == nil {
				t.Error("the abandonment log does not say how long it was held")
			}
		}
	}
	if !sawError {
		t.Fatalf("no ERROR-level abandonment line; a compliance obligation that will now never be "+
			"met disappeared quietly. Log was:\n%s", logged.String())
	}
}

// TestTheTTLIsDefensiblyLong is a bound on the bound.
//
// Not a style assertion: too short and the drain abandons obligations that a normal Apple outage or
// key rotation would have cleared, which is the failure the queue exists to prevent; too long and
// "bounded retention" is retention wearing a compliance costume.
func TestTheTTLIsDefensiblyLong(t *testing.T) {
	if AppleRevocationTTL < 7*24*time.Hour {
		t.Errorf("TTL is %v — shorter than a long weekend plus a slow operator response, so it "+
			"would abandon revocations that waiting would have cleared", AppleRevocationTTL)
	}
	if AppleRevocationTTL > 90*24*time.Hour {
		t.Errorf("TTL is %v — long enough that the bound is not really a bound, on a table that "+
			"points at the identity of people who were told their account was erased", AppleRevocationTTL)
	}
}
