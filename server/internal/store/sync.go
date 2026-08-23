package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// Owner is who a mutation belongs to: exactly one of the two, always.
//
// It is a pair rather than two arguments so that "neither" and "both" are unrepresentable at the
// call site as well as in the table. The client's tables state the same rule as
// `CHECK ((user_id IS NULL) <> (device_id IS NULL))`, and the reason given there holds here: with
// both columns populated the owner is whatever a query decides to COALESCE first.
type Owner struct {
	UserID   *uuid.UUID
	DeviceID *uuid.UUID
}

// UserOwner builds an account-owned Owner.
func UserOwner(id uuid.UUID) Owner { return Owner{UserID: &id} }

// DeviceOwner builds a device-owned Owner.
func DeviceOwner(id uuid.UUID) Owner { return Owner{DeviceID: &id} }

// Mutation is one item of `POST /sync`.
type Mutation struct {
	ClientUUID uuid.UUID
	Kind       string
	TreeUUID   uuid.UUID
	Payload    []byte
	OccurredAt time.Time
	// IsFavorite is read only for kind `favorite_toggle`, which carries state rather than a verb
	// so replaying it is idempotent.
	IsFavorite bool
	// CommunityTree is set only for kind `add_tree`, and it is what makes that one of spec §3.4's
	// ten different from the other nine.
	//
	// Nine of them are recorded and not materialized, which is the contract five of the six older
	// kinds already have: the `contributions` row *is* the record. A tree cannot be, because a tree
	// has to be **findable** — `TreesWithin` is the 10 m proximity dedupe, it reads
	// `community_trees`, and a tree that existed only as a contribution is a tree the next
	// contributor standing under it would be invited to add again.
	//
	// Eight of those nine are recorded because this service *could not* materialize them; the ninth,
	// `photo_withdrawal`, now materializes through `WithdrawnPhotoID` below. The difference matters
	// to whoever adds the next branch beside this field, and it is spelled out beside `syncKinds` in
	// `internal/api/sync.go`.
	//
	// It travels inside the mutation so the two rows land in **one transaction**. Calling `AddTree`
	// beside `Apply` would leave a window in which the tree is on the map and the contribution that
	// says who added it is not, or the reverse — and the reverse is the one that matters, because
	// a retry would then hit the contribution dedupe and never insert the tree.
	CommunityTree *NewCommunityTree
	// WithdrawnPhotoID is set only for kind `photo_withdrawal`: the photograph the contributor took
	// back on their phone, which this service tombstones so it stops being served to everybody else.
	//
	// **It travels inside the mutation for the reason `CommunityTree` does, pointing the other way.**
	// The tombstone and the contribution that records the withdrawal land in one transaction, so
	// there is no window in which the photograph is gone and the record of who withdrew it is not —
	// and, more importantly, none in which the contribution is recorded, the client's retry is
	// therefore deduped away, and the photograph is *still being served*. That second window is the
	// one that matters here: it is ERRATA E280's failure reached by a different route, and a
	// separate call beside `Apply` would open it on any error between the two.
	//
	// It is a pointer rather than a bare id so that "this kind carries no photograph" stays
	// unrepresentable-by-accident, the same way `CommunityTree` does it.
	WithdrawnPhotoID *uuid.UUID
}

// ApplyOutcome is what happened to one mutation.
type ApplyOutcome int

const (
	// Applied means the row was inserted for the first time.
	Applied ApplyOutcome = iota
	// Duplicate means the key was already known. It is a **success that changes nothing** — the
	// same answer the client's unique index gives, and what makes `OutboxChaosTests`' zero-
	// duplicates assertion hold across a flap.
	Duplicate
)

// ErrTombstoned is returned when a mutation's key is in `anonymized_contributions`.
//
// The caller answers `duplicate`, not an error: a replayed item hitting the tombstone must be a
// success that changes nothing, exactly like the dedupe. Anything else and the client's retry
// policy either burns 48 h on it or fails it terminally, and both put a stranger's withdrawn
// record back in play.
var ErrTombstoned = errors.New("client_uuid is tombstoned")

// Apply inserts one mutation, deduping on client_uuid.
//
// ── The order of the two checks, which is the whole of the deletion guarantee ───────────────────
//
// The tombstone is consulted **before** the insert, in the same transaction. An item accepted after
// its account was deleted must not resurrect it, and the client already has the mechanism this
// mirrors: `anonymized_contributions` is written *before* the payload stops naming the account, and
// it is keyed on `client_uuid` precisely because that key exists before the row does. A contribution
// lives in the queue between being written and being applied; a deletion on Wednesday must be
// waiting for a drain on Thursday, and a column on this table could not be, because on Thursday the
// row is being inserted for the first time.
func (s *Store) Apply(ctx context.Context, mutation Mutation, owner Owner) (ApplyOutcome, error) {
	var outcome ApplyOutcome
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		var tombstoned bool
		err := tx.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM anonymized_contributions WHERE client_uuid = $1)
		`, mutation.ClientUUID).Scan(&tombstoned)
		if err != nil {
			return err
		}
		if tombstoned {
			return ErrTombstoned
		}

		now := s.now()
		tag, err := tx.Exec(ctx, `
			INSERT INTO contributions
			    (client_uuid, kind, tree_uuid, user_id, device_id, payload, occurred_at,
			     created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
			ON CONFLICT (client_uuid) DO NOTHING
		`, mutation.ClientUUID, mutation.Kind, mutation.TreeUUID,
			owner.UserID, owner.DeviceID, mutation.Payload, mutation.OccurredAt, now)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			outcome = Duplicate
			return nil
		}
		outcome = Applied

		if mutation.Kind == "favorite_toggle" {
			return upsertFavorite(ctx, tx, mutation, owner, now)
		}
		if mutation.CommunityTree != nil {
			return insertCommunityTree(ctx, tx, *mutation.CommunityTree, owner, now)
		}
		// **After the dedupe, deliberately.** A replayed withdrawal returns `Duplicate` above and
		// never reaches here, which is right: the first pass tombstoned the photograph, and a second
		// pass has nothing to add. `withdrawPhoto` is idempotent anyway — it treats an
		// already-tombstoned row as a success — so the two guards agree rather than depending on
		// each other.
		if mutation.WithdrawnPhotoID != nil {
			return withdrawPhoto(ctx, tx, *mutation.WithdrawnPhotoID, owner, now)
		}
		return nil
	})
	return outcome, err
}

// upsertFavorite keeps the materialized heart in step with the toggle stream.
//
// The toggle carries the resulting *state* and a timestamp, so the rule is "the later statement
// wins" and an out-of-order replay must not undo a newer decision. The `WHERE excluded.occurred_at
// > favorites.occurred_at` on the conflict arm is what makes that true rather than hoped for: a
// drain that delivers Tuesday's tap after Wednesday's leaves Wednesday standing.
func upsertFavorite(ctx context.Context, tx pgx.Tx, mutation Mutation, owner Owner, now time.Time) error {
	var conflictTarget string
	if owner.UserID != nil {
		conflictTarget = `(user_id, tree_uuid) WHERE user_id IS NOT NULL`
	} else {
		conflictTarget = `(device_id, tree_uuid) WHERE device_id IS NOT NULL`
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO favorites
		    (id, tree_uuid, user_id, device_id, client_uuid, is_favorite, occurred_at,
		     created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
		ON CONFLICT `+conflictTarget+` DO UPDATE SET
		    is_favorite = excluded.is_favorite,
		    client_uuid = excluded.client_uuid,
		    occurred_at = excluded.occurred_at,
		    updated_at  = excluded.updated_at
		 WHERE excluded.occurred_at > favorites.occurred_at
	`, uuid.New(), mutation.TreeUUID, owner.UserID, owner.DeviceID,
		mutation.ClientUUID, mutation.IsFavorite, mutation.OccurredAt, now)
	return err
}

// insertCommunityTree materializes an `add_tree` item, in the transaction that recorded it.
//
// `ON CONFLICT (id) DO NOTHING` and no reported outcome: the contribution insert above has already
// decided whether this item is new, on the key that decides it everywhere else. A tree that is
// already here is one this device sent before under a different `client_uuid` — the same act queued
// twice — and re-inserting it must not fail the item, but must not overwrite it either. Whoever got
// here first is the row.
//
// The statement is `AddTree`'s, run on this transaction's connection rather than the pool's. It is
// written out instead of calling that method because `AddTree` takes a `*Store` and a context and
// would open its own connection, which is exactly the second transaction this is here to avoid.
func insertCommunityTree(
	ctx context.Context,
	tx pgx.Tx,
	tree NewCommunityTree,
	owner Owner,
	now time.Time,
) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO community_trees
		    (id, lat, lon, address, species_id, placement, land_context,
		     user_id, device_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)
		ON CONFLICT (id) DO NOTHING
	`, tree.ID, tree.Lat, tree.Lon, tree.Address, tree.SpeciesID, tree.Placement, tree.LandContext,
		owner.UserID, owner.DeviceID, now)
	return err
}

// ── Deletion ───────────────────────────────────────────────────────────────────────────────────

// DeletionChoice is `AccountDeletionChoice`, whose two raw values these are.
//
// The choice travels on the wire and is applied to rows this service already accepted. It is not a
// server default: R3's acceptance criterion is that deleting *more* than somebody expected is the
// failure mode, and a default here would be this service deciding that question for them.
type DeletionChoice string

const (
	// LeaveRecords keeps contributions on the trees they were made about, with the name taken off.
	LeaveRecords DeletionChoice = "leaveRecords"
	// EraseEverything deletes them outright.
	EraseEverything DeletionChoice = "eraseEverything"
)

// Valid reports whether the wire value is one of the two doors.
func (c DeletionChoice) Valid() bool {
	return c == LeaveRecords || c == EraseEverything
}

// DeletionReport is what a deletion did, for the log and for the response.
type DeletionReport struct {
	Contributions int
	Photos        int
	Tombstones    int
}

// UnrevokedAppleToken is a token whose revocation has not yet succeeded.
//
// It is passed to DeleteAccount rather than read from the row inside it, because the caller is the
// only thing that knows whether Apple accepted the revocation, and the row is about to be gone.
type UnrevokedAppleToken string

// DeleteAccount applies the choice to everything this service holds for a user, and tombstones it.
//
// ── What is deleted under both doors, and why it is not a choice ───────────────────────────────
//
// Favorites and private reminders go unconditionally. `AccountDeletionChoice` argues it and the
// engine says the same thing in its own words: both carry `CHECK ((user_id IS NULL) <> (device_id
// IS NULL))`, so an ownerless row is unstorable, and offering to "keep" one would be offering to
// keep a thing nothing can display.
//
// ── The tombstone is written for keys this service has never seen ──────────────────────────────
//
// Not only for the rows being unlinked. The client's queue holds items that name this account and
// have not arrived; they will arrive after the deletion, and the mark has to be waiting. The
// caller passes those keys in `pendingKeys` — the client knows them, because they are its own
// outbox — and every one is tombstoned whether or not a row exists for it.
func (s *Store) DeleteAccount(
	ctx context.Context,
	userID uuid.UUID,
	choice DeletionChoice,
	pendingKeys []uuid.UUID,
	unrevoked UnrevokedAppleToken,
) (DeletionReport, error) {
	var report DeletionReport
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		now := s.now()

		// The tombstones go first, and the order is load-bearing: it mirrors the client's rule that
		// the mark is written *before* the payload stops naming the account, so a crash between the
		// two leaves a record that is unlinked-and-marked or neither, never unmarked-and-orphaned.
		keys := append([]uuid.UUID(nil), pendingKeys...)
		rows, err := tx.Query(ctx, `
			SELECT client_uuid FROM contributions WHERE user_id = $1
		`, userID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var key uuid.UUID
			if err := rows.Scan(&key); err != nil {
				rows.Close()
				return err
			}
			keys = append(keys, key)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		for _, key := range keys {
			// `DO NOTHING`: a deletion that runs twice, or a queued row whose stored twin was
			// already tombstoned, must be a no-op rather than a constraint failure inside a
			// deletion transaction.
			tag, err := tx.Exec(ctx, `
				INSERT INTO anonymized_contributions (client_uuid, anonymized_at)
				VALUES ($1, $2) ON CONFLICT (client_uuid) DO NOTHING
			`, key, now)
			if err != nil {
				return err
			}
			report.Tombstones += int(tag.RowsAffected())
		}

		// Favorites and reminders: gone under both doors.
		if _, err := tx.Exec(ctx, `DELETE FROM favorites WHERE user_id = $1`, userID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			DELETE FROM contributions WHERE user_id = $1 AND kind = 'private_reminder'
		`, userID); err != nil {
			return err
		}

		var tag interface{ RowsAffected() int64 }
		switch choice {
		case LeaveRecords:
			t, err := tx.Exec(ctx, `
				UPDATE contributions
				   SET user_id = NULL, device_id = NULL, anonymized_at = $2, updated_at = $2
				 WHERE user_id = $1
			`, userID, now)
			if err != nil {
				return err
			}
			tag = t
			// A photograph is not anonymizable the way a measurement is: the default door's promise
			// is about a record, and the bytes are the record. `Photo`'s own header makes the same
			// distinction, so the leaving door still removes the photograph while leaving the
			// numbers standing.
			photoTag, err := tx.Exec(ctx, `
				UPDATE photos SET deleted_at = $2, user_id = NULL, anonymized_at = $2, updated_at = $2
				 WHERE user_id = $1 AND deleted_at IS NULL
			`, userID, now)
			if err != nil {
				return err
			}
			report.Photos = int(photoTag.RowsAffected())

		case EraseEverything:
			t, err := tx.Exec(ctx, `DELETE FROM contributions WHERE user_id = $1`, userID)
			if err != nil {
				return err
			}
			tag = t
			photoTag, err := tx.Exec(ctx, `
				UPDATE photos SET deleted_at = $2, user_id = NULL, anonymized_at = $2, updated_at = $2
				 WHERE user_id = $1 AND deleted_at IS NULL
			`, userID, now)
			if err != nil {
				return err
			}
			report.Photos = int(photoTag.RowsAffected())

		default:
			return errors.New("unknown deletion choice")
		}
		report.Contributions = int(tag.RowsAffected())

		// Sessions and the device link go with the account. `ON DELETE CASCADE` would take the
		// sessions anyway; it is stated because the row order in a deletion should not depend on a
		// foreign key's mood.
		// **The obligation outlives the account, so the credential has to as well.**
		//
		// `DELETE FROM users` below takes `apple_refresh_token` with it. If Apple refused the
		// revocation — an outage, a rotated key — that would discard the only credential that could
		// ever satisfy R72 ruling 2's requirement, and the person would be told their account was
		// deleted while Apple still held a live grant. So the token is parked first, in a table that
		// holds a token and nothing that could say whose it was.
		if unrevoked != "" {
			if _, err := tx.Exec(ctx, `
				INSERT INTO pending_apple_revocations (refresh_token, first_failed_at, last_attempted_at)
				VALUES ($1, $2, $2)
				ON CONFLICT (refresh_token) DO UPDATE SET
					last_attempted_at = excluded.last_attempted_at,
					attempts = pending_apple_revocations.attempts + 1
			`, string(unrevoked), now); err != nil {
				return err
			}
		}

		if _, err := tx.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, userID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE devices SET user_id = NULL, updated_at = $2 WHERE user_id = $1
		`, userID, now); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
		return err
	})
	return report, err
}

// IsTombstoned reports whether a key has been withdrawn.
func (s *Store) IsTombstoned(ctx context.Context, key uuid.UUID) (bool, error) {
	var found bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM anonymized_contributions WHERE client_uuid = $1)
	`, key).Scan(&found)
	return found, err
}

// ── The parked revocations ─────────────────────────────────────────────────────────────────────

// ParkedRevocation is one un-revoked Apple token.
type ParkedRevocation struct {
	RefreshToken  string
	FirstFailedAt time.Time
	Attempts      int
}

// PendingAppleRevocations returns the oldest parked tokens, up to limit.
//
// Oldest first, so the row closest to its retention limit is retried before the ones with time
// left — the opposite order would spend a capped batch on new rows and let old ones expire
// un-retried.
func (s *Store) PendingAppleRevocations(ctx context.Context, limit int) ([]ParkedRevocation, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT refresh_token, first_failed_at, attempts
		  FROM pending_apple_revocations
		 ORDER BY first_failed_at ASC
		 LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var parked []ParkedRevocation
	for rows.Next() {
		var row ParkedRevocation
		if err := rows.Scan(&row.RefreshToken, &row.FirstFailedAt, &row.Attempts); err != nil {
			return nil, err
		}
		parked = append(parked, row)
	}
	return parked, rows.Err()
}

// RecordAppleRevocationAttempt moves `attempts` and `last_attempted_at` after a refusal.
//
// These two columns were unreachable before the drain existed: the `ON CONFLICT` arm that would
// have written them can only fire if the same token is parked twice, and it cannot be, because the
// `users` row it came from is deleted in the same transaction. So `attempts` was always 1 and
// `last_attempted_at` always equalled `first_failed_at` — state that looked like a retry record and
// recorded nothing.
func (s *Store) RecordAppleRevocationAttempt(ctx context.Context, token string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE pending_apple_revocations
		   SET attempts = attempts + 1, last_attempted_at = $2
		 WHERE refresh_token = $1
	`, token, s.now())
	return err
}

// DeleteAppleRevocation removes a discharged obligation.
func (s *Store) DeleteAppleRevocation(ctx context.Context, token string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM pending_apple_revocations WHERE refresh_token = $1`, token)
	return err
}

// ExpireAppleRevocations deletes everything past the retention limit and returns what it deleted.
//
// It returns the rows so the caller can log the abandonment: a revocation that will now never
// happen is an operator's problem, and a row that vanished on a timer with no line in the log is
// the compliance obligation disappearing quietly. The token itself is deliberately not returned —
// nothing downstream needs it, and it is the thing being disposed of.
func (s *Store) ExpireAppleRevocations(ctx context.Context, ttl time.Duration) ([]ParkedRevocation, error) {
	cutoff := s.now().Add(-ttl)
	rows, err := s.pool.Query(ctx, `
		DELETE FROM pending_apple_revocations
		 WHERE first_failed_at <= $1
		RETURNING '', first_failed_at, attempts
	`, cutoff)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var expired []ParkedRevocation
	for rows.Next() {
		var row ParkedRevocation
		if err := rows.Scan(&row.RefreshToken, &row.FirstFailedAt, &row.Attempts); err != nil {
			return nil, err
		}
		expired = append(expired, row)
	}
	return expired, rows.Err()
}
