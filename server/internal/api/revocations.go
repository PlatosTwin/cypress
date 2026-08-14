package api

import (
	"context"
	"log/slog"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/store"
)

// AppleRevocationTTL bounds how long an un-revoked token is kept.
//
// ── Why there is a bound at all ────────────────────────────────────────────────────────────────
//
// The parked token is not inert. An Apple refresh token, plus the client secret this same service
// mints, exchanges at Apple's token endpoint for an `id_token` carrying that person's `sub` and
// email — so `pending_apple_revocations` is a pointer to the identity of everyone whose deletion
// hit an Apple outage, held after a screen that promised erasure. RULINGS R3 makes that copy the
// promise, so an unbounded queue would be the promise quietly broken by an error path.
//
// ── Why thirty days ───────────────────────────────────────────────────────────────────────────
//
// It has to be long enough that the thing it exists for actually happens: Apple outages are hours,
// key rotations are noticed in days, and the drain retries every tick throughout. Thirty days is
// far past any of those and is the shortest round number that is obviously past them — a week could
// plausibly be spent on one holiday weekend plus a slow operator response, and a year would be
// retention wearing a compliance costume. If a revocation has not succeeded in thirty days it is
// not going to succeed by waiting, and the honest thing is to stop holding the credential and say
// so loudly.
const AppleRevocationTTL = 30 * 24 * time.Hour

// appleRevocationInterval is how often the drain runs. Cheap: a query against an empty table on
// almost every tick.
const appleRevocationInterval = 15 * time.Minute

// appleRevocationBatch caps one pass, so a backlog cannot hold the single machine.
const appleRevocationBatch = 50

// DrainAppleRevocations makes one pass over the parked tokens.
//
// This is the half of B5's fix that makes it an obligation discharged rather than an obligation
// recorded. R72 ruling 2 requires the revocation call; parking the token without ever retrying it
// would leave `attempts` and `last_attempted_at` as columns nothing could ever write, and the queue
// as a table nothing reads.
//
// Three outcomes per row, and each is final in its own way:
//
//   - Apple accepts → the row is deleted. The obligation is discharged and the credential is gone.
//   - Apple refuses → `attempts` and `last_attempted_at` move, and the row waits for the next tick.
//   - The row is past AppleRevocationTTL → it is deleted **and the abandonment is logged at error
//     level**, because a revocation that will now never happen is an operator's problem and must
//     not disappear quietly. Deleting it is not giving up on the obligation; it is refusing to keep
//     an identity pointer forever in the name of one.
//
// Returns what it did, for the tests and for the boot log.
func DrainAppleRevocations(ctx context.Context, dataStore *store.Store, apple AppleAuth, log *slog.Logger) (revoked, failed, abandoned int) {
	// Expiry first: a row past its TTL must not be handed to Apple again on the way out. Retrying
	// it would be one more exchange of a credential this pass exists to stop holding.
	expired, err := dataStore.ExpireAppleRevocations(ctx, AppleRevocationTTL)
	if err != nil {
		log.Error("expiring parked Apple revocations", "cause", err)
	}
	for _, row := range expired {
		abandoned++
		// Error level, and it names the age and the attempt count rather than the token. Somebody
		// has to be able to tell Apple's support, or the owner, that a deletion's revocation was
		// never accepted — and nobody can tell that from a row that was silently dropped.
		log.Error("ABANDONED an Apple token revocation past its retention limit; "+
			"the account was deleted here and may still be granted at Apple",
			"first_failed_at", row.FirstFailedAt.Format(time.RFC3339),
			"attempts", row.Attempts,
			"ttl", AppleRevocationTTL.String())
	}

	pending, err := dataStore.PendingAppleRevocations(ctx, appleRevocationBatch)
	if err != nil {
		log.Error("reading parked Apple revocations", "cause", err)
		return revoked, failed, abandoned
	}

	for _, row := range pending {
		if err := apple.Revoke(ctx, row.RefreshToken); err != nil {
			failed++
			if recordErr := dataStore.RecordAppleRevocationAttempt(ctx, row.RefreshToken); recordErr != nil {
				log.Error("recording a revocation attempt", "cause", recordErr)
			}
			continue
		}
		revoked++
		if deleteErr := dataStore.DeleteAppleRevocation(ctx, row.RefreshToken); deleteErr != nil {
			// The revocation succeeded and the row did not go. Loud, because the next pass will
			// present an already-revoked token — harmless at Apple, but the row would otherwise sit
			// here until its TTL looking like a failure.
			log.Error("a revocation succeeded but its row could not be deleted", "cause", deleteErr)
		}
	}

	if revoked > 0 || failed > 0 || abandoned > 0 {
		log.Info("drained parked Apple revocations",
			"revoked", revoked, "failed", failed, "abandoned", abandoned)
	}
	return revoked, failed, abandoned
}

// RunAppleRevocationDrain runs the drain on boot and then on a tick, until ctx is done.
//
// On boot as well as on the tick because the machine `auto_stop_machines = 'stop'`s when idle: it
// spends most of its life stopped, so a timer alone would fire rarely and unpredictably, while a
// boot pass runs every time anybody touches the service.
func RunAppleRevocationDrain(ctx context.Context, dataStore *store.Store, apple AppleAuth, log *slog.Logger) {
	DrainAppleRevocations(ctx, dataStore, apple, log)

	ticker := time.NewTicker(appleRevocationInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			DrainAppleRevocations(ctx, dataStore, apple, log)
		}
	}
}
