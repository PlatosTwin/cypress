package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// User is an account row.
type User struct {
	ID                uuid.UUID
	AppleSubject      string
	Email             string
	Role              string
	LicenseVersion    *string
	AppleRefreshToken string
}

// UpsertUserForApple finds or creates the account behind a verified Apple subject.
//
// Keyed on `apple_subject`, never on the email: Hide My Email makes the address a relay this
// service should not treat as identity, and a person can change their real one.
func (s *Store) UpsertUserForApple(ctx context.Context, subject, email, refreshToken string) (User, error) {
	now := s.now()
	var user User
	err := s.pool.QueryRow(ctx, `
		INSERT INTO users (id, apple_subject, email, apple_refresh_token, created_at, updated_at)
		VALUES ($1, $2, nullif($3, ''), nullif($4, ''), $5, $5)
		ON CONFLICT (apple_subject) DO UPDATE SET
			-- Apple sends the email on first authorization only, so a later sign-in carrying none
			-- must not erase what the first one recorded.
			email = coalesce(nullif(excluded.email, ''), users.email),
			apple_refresh_token = coalesce(nullif(excluded.apple_refresh_token, ''), users.apple_refresh_token),
			updated_at = excluded.updated_at
		RETURNING id, apple_subject, coalesce(email, ''), role, license_version,
		          coalesce(apple_refresh_token, '')
	`, uuid.New(), subject, email, refreshToken, now).
		Scan(&user.ID, &user.AppleSubject, &user.Email, &user.Role, &user.LicenseVersion, &user.AppleRefreshToken)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

// UserByID reads an account.
func (s *Store) UserByID(ctx context.Context, id uuid.UUID) (User, error) {
	var user User
	err := s.pool.QueryRow(ctx, `
		SELECT id, apple_subject, coalesce(email, ''), role, license_version,
		       coalesce(apple_refresh_token, '')
		  FROM users WHERE id = $1
	`, id).Scan(&user.ID, &user.AppleSubject, &user.Email, &user.Role, &user.LicenseVersion, &user.AppleRefreshToken)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return user, err
}

// RegisterDevice exchanges a device UUID for its row, creating it on first sight.
func (s *Store) RegisterDevice(ctx context.Context, deviceUUID uuid.UUID) (uuid.UUID, error) {
	now := s.now()
	var id uuid.UUID
	err := s.pool.QueryRow(ctx, `
		INSERT INTO devices (id, device_uuid, created_at, updated_at)
		VALUES ($1, $2, $3, $3)
		ON CONFLICT (device_uuid) DO UPDATE SET updated_at = excluded.updated_at
		RETURNING id
	`, uuid.New(), deviceUUID, now).Scan(&id)
	return id, err
}

// RevokeDeviceTokens retires every live credential over a device.
//
// Called on re-registration. Spec §5.8's "not an attestation" covers somebody minting a credential
// for a *fresh* device id, which nothing can prevent and D9 requires be cheap. It does not cover
// re-issuing over a **live** installation: without this, `device_uuid` is a bearer secret with
// unlimited reissue and no revocation, and a second registration hands the caller read and write
// authority over the first one's contributions while leaving its token working.
//
// Retiring the old tokens does not stop somebody who knows the id from minting a new one. What it
// does is make the takeover *visible* — the real device's next call is a 401 and it re-registers —
// instead of two holders sharing one queue silently. The column was already in the schema and
// nothing wrote it.
func (s *Store) RevokeDeviceTokens(ctx context.Context, deviceID uuid.UUID) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE device_tokens SET revoked_at = $2 WHERE device_id = $1 AND revoked_at IS NULL
	`, deviceID, s.now())
	return err
}

// ── Sessions ───────────────────────────────────────────────────────────────────────────────────

// CreateSession stores a refresh token hash and returns the session id.
func (s *Store) CreateSession(ctx context.Context, userID uuid.UUID, hash []byte, expiresAt time.Time) (uuid.UUID, error) {
	id := uuid.New()
	_, err := s.pool.Exec(ctx, `
		INSERT INTO sessions (id, user_id, refresh_token_hash, issued_at, expires_at)
		VALUES ($1, $2, $3, $4, $5)
	`, id, userID, hash, s.now(), expiresAt)
	return id, err
}

// Session is a refresh-token row.
type Session struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	ExpiresAt time.Time
	RotatedAt *time.Time
	RevokedAt *time.Time
}

// RotateSession spends a refresh token and issues its successor, in one transaction.
//
// **The old row is marked rather than deleted**, so a second presentation of a spent token is a
// row that exists and says it was spent, not a row that is simply absent. Those are the same 401
// to the client and different facts to an operator reading the table after a theft.
func (s *Store) RotateSession(ctx context.Context, presentedHash, nextHash []byte, expiresAt time.Time) (Session, uuid.UUID, error) {
	var session Session
	var nextID uuid.UUID
	var reused bool
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		// FOR UPDATE, because two drains racing on one phone would otherwise both read an unspent
		// token and both mint a successor — and the loser's successor would be a live session
		// nobody holds.
		err := tx.QueryRow(ctx, `
			SELECT id, user_id, expires_at, rotated_at, revoked_at
			  FROM sessions WHERE refresh_token_hash = $1 FOR UPDATE
		`, presentedHash).Scan(&session.ID, &session.UserID, &session.ExpiresAt, &session.RotatedAt, &session.RevokedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		now := s.now()
		if session.RotatedAt != nil && session.RevokedAt == nil {
			// **A replayed refresh token is the canonical signal that one leaked.** Refusing the
			// replay alone leaves whoever holds the successor with a 60-day session, and the
			// legitimate holder cannot tell. Revoking the whole family logs both parties out and
			// makes the theft visible as a sign-in prompt rather than invisible as a shared
			// account. The `revoked_at` column was already here and nothing wrote it.
			if _, err := tx.Exec(ctx, `
				UPDATE sessions SET revoked_at = $2 WHERE user_id = $1 AND revoked_at IS NULL
			`, session.UserID, now); err != nil {
				return err
			}
			// **Return nil so the revocation commits.** Reporting the reuse as an error here would
			// roll it back — the transaction would refuse the replay and leave the whole family
			// live, which is the defense reading as though it had run. The condition is carried out
			// past the commit instead.
			reused = true
			return nil
		}
		if session.RevokedAt != nil || !now.Before(session.ExpiresAt) {
			return ErrSessionSpent
		}
		if _, err := tx.Exec(ctx, `UPDATE sessions SET rotated_at = $2 WHERE id = $1`, session.ID, now); err != nil {
			return err
		}
		nextID = uuid.New()
		_, err = tx.Exec(ctx, `
			INSERT INTO sessions (id, user_id, refresh_token_hash, issued_at, expires_at)
			VALUES ($1, $2, $3, $4, $5)
		`, nextID, session.UserID, nextHash, now, expiresAt)
		return err
	})
	if err == nil && reused {
		return session, uuid.Nil, ErrSessionReused
	}
	return session, nextID, err
}

// ErrSessionSpent is a refresh token that verified but is expired or revoked.
var ErrSessionSpent = errors.New("session spent")

// ErrSessionReused is a refresh token presented a second time after it was rotated.
//
// Distinct from ErrSessionSpent because it means something different: not "this is old" but "two
// parties hold this". Both answer `unauthorized` on the wire — the client cannot act on the
// difference — and they are kept apart so the log and the tests can.
var ErrSessionReused = errors.New("session reused after rotation")

// SessionIsLive reports whether a session row is still good.
//
// An access token is self-describing so a read costs no round trip — but it also cannot know that
// the account behind it was deleted ten seconds ago, and it stays valid for up to fifteen minutes
// after. In that window `GET /me/grove` answered `200 {"entries":[]}` for a deleted account, and a
// `/sync` item answered `server_error`, which is **retryable**, so a straggler burned the full 48 h
// backoff instead of taking the `duplicate` the tombstone gives keys that were declared pending.
//
// One indexed lookup on a primary key, on authenticated requests only. That is the price of the
// access token not being a fifteen-minute lie about whether an account exists.
func (s *Store) SessionIsLive(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	var live bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM sessions WHERE id = $1 AND revoked_at IS NULL AND expires_at > $2)
	`, sessionID, s.now()).Scan(&live)
	return live, err
}

// DeviceTokenOwner resolves a presented device token hash to its device.
//
// **It returns both identifiers, and the pair is the point.** `devices.id` is this database's row
// key, minted here by RegisterDevice. `devices.device_uuid` is the *client's* installation id (D9) —
// the value the phone keeps in `app_state.device_uuid`, registers with, sends to `/devices/claim` as
// `device_uuid`, and sends on every sync item as `device_id`. They are two identifiers for one
// installation in two vocabularies, and anything that compares one against the other refuses
// everything. `applyOne` in sync.go did exactly that, and returning only the row key is what left it
// no honest way not to.
func (s *Store) DeviceTokenOwner(ctx context.Context, hash []byte) (uuid.UUID, uuid.UUID, error) {
	var deviceID, deviceUUID uuid.UUID
	err := s.pool.QueryRow(ctx, `
		SELECT t.device_id, d.device_uuid
		  FROM device_tokens t
		  JOIN devices d ON d.id = t.device_id
		 WHERE t.token_hash = $1 AND t.revoked_at IS NULL AND t.expires_at > $2
	`, hash, s.now()).Scan(&deviceID, &deviceUUID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, uuid.Nil, ErrNotFound
	}
	return deviceID, deviceUUID, err
}

// CreateDeviceToken stores a device token hash.
func (s *Store) CreateDeviceToken(ctx context.Context, deviceID uuid.UUID, hash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO device_tokens (id, device_id, token_hash, issued_at, expires_at)
		VALUES ($1, $2, $3, $4, $5)
	`, uuid.New(), deviceID, hash, s.now(), expiresAt)
	return err
}

// ── The claim ──────────────────────────────────────────────────────────────────────────────────

// ClaimDevice re-homes a device's unattributed rows onto an account.
//
// This is `POST /devices/claim`, and it mirrors `ContributionStore.claimDevice` deliberately: a
// sweep keyed on device id whose WHERE clauses stop matching once they have run. Nothing inserts,
// nothing deletes, and rows belonging to a different account are not touched — which is what makes
// the client safe to re-invoke it after every batch that applied anything (spec §6.2), and what
// makes running it twice cost one indexed scan and no writes.
//
// ── The #174 guard ─────────────────────────────────────────────────────────────────────────────
//
// `caller` is the identity the request authenticated as, and the claim runs only if it is the one
// being claimed for. On the client the trap is that `device.user_id` outlives the sign-in — a
// sign-out clears the current user and leaves the claim row standing, so the row alone is history
// rather than authority, and re-claiming against it while signed out adopted rows it should not
// have. The server has the same trap by the same mechanism: `devices.user_id` is set here and is
// never cleared by a sign-out, because a sign-out is not a request this service receives.
//
// So the authority is the bearer token, never the stored column. A device claimed by account A
// cannot be swept for account B by anyone holding B's session, and B cannot sweep it by presenting
// A's device token either.
func (s *Store) ClaimDevice(ctx context.Context, deviceUUID uuid.UUID, caller uuid.UUID) error {
	return s.Tx(ctx, func(tx pgx.Tx) error {
		var deviceID uuid.UUID
		var claimedBy *uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id, user_id FROM devices WHERE device_uuid = $1 FOR UPDATE
		`, deviceUUID).Scan(&deviceID, &claimedBy)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}

		// The guard. A device already claimed by somebody else is not this caller's to sweep, and
		// saying so is the whole of #174's lesson: the stored claim is not authority.
		if claimedBy != nil && *claimedBy != caller {
			return ErrClaimedByAnotherAccount
		}

		now := s.now()

		// The four append-only kinds plus the two exclusively-owned ones, in one statement because
		// `contributions` is one table here where the client has six.
		//
		// `anonymized_at IS NULL` is the tombstone's half of the guard: a row unlinked by a
		// deletion has no owner by design, and must not be adoptable by the next person to sign in
		// on this phone. The client states the same rule as `notAnonymized(table)`.
		if _, err := tx.Exec(ctx, `
			UPDATE contributions
			   SET user_id = $1, device_id = NULL, updated_at = $2
			 WHERE device_id = $3 AND user_id IS NULL AND anonymized_at IS NULL
		`, caller, now, deviceID); err != nil {
			return err
		}

		// The photograph, adopted on the reminder's terms rather than the visit's (`AppSchema` v12,
		// ERRATA E136): the account gains the row and the device link is dropped in the same
		// statement, so a photograph never says both whose account it is and which phone took it.
		if _, err := tx.Exec(ctx, `
			UPDATE photos
			   SET user_id = $1, device_id = NULL, updated_at = $2
			 WHERE device_id = $3 AND user_id IS NULL AND anonymized_at IS NULL
		`, caller, now, deviceID); err != nil {
			return err
		}

		if _, err := tx.Exec(ctx, `
			UPDATE community_trees
			   SET user_id = $1, device_id = NULL, updated_at = $2
			 WHERE device_id = $3 AND user_id IS NULL
		`, caller, now, deviceID); err != nil {
			return err
		}

		if err := claimFavorites(ctx, tx, deviceID, caller, now); err != nil {
			return err
		}

		_, err = tx.Exec(ctx, `
			UPDATE devices SET user_id = $1, updated_at = $2 WHERE id = $3
		`, caller, now, deviceID)
		return err
	})
}

// ErrClaimedByAnotherAccount is the #174 guard tripping.
var ErrClaimedByAnotherAccount = errors.New("device is claimed by another account")

// claimFavorites is the half with a collision in it (ERRATA E89).
//
// A favorite is not append-only, so two rows can be the same record: the device favorited a tree
// the account had already favorited from somewhere else. After the claim only one owner exists, so
// one row has to carry both histories, and a plain UPDATE would hit `idx_favorites_user_tree` and
// abort the whole claim — meaning sign-in fails for the contributor whose grove overlaps most.
//
// Three statements, in this order, each an UPDATE or a narrowly-predicated DELETE whose WHERE stops
// matching once it has run — which is what keeps the sweep idempotent through the collision case
// as well as the simple one.
func claimFavorites(ctx context.Context, tx pgx.Tx, deviceID, userID uuid.UUID, now time.Time) error {
	// 1. The later statement wins. Where both owners hold a tree and the device's row is the more
	//    recent, its state, its key and its timestamp move onto the account's row. A favorite is a
	//    toggle resolved by time: whichever the person said last is what they meant.
	if _, err := tx.Exec(ctx, `
		UPDATE favorites AS account
		   SET is_favorite = device.is_favorite,
		       client_uuid = device.client_uuid,
		       occurred_at = device.occurred_at,
		       updated_at  = $3
		  FROM favorites AS device
		 WHERE device.device_id = $1
		   AND account.user_id  = $2
		   AND account.tree_uuid = device.tree_uuid
		   AND device.occurred_at > account.occurred_at
	`, deviceID, userID, now); err != nil {
		return err
	}

	// 2. The device's row is now redundant wherever the account already holds that tree — either
	//    because step 1 moved its content across, or because the account's was already the later.
	if _, err := tx.Exec(ctx, `
		DELETE FROM favorites AS device
		 WHERE device.device_id = $1
		   AND EXISTS (SELECT 1 FROM favorites AS account
		                WHERE account.user_id = $2 AND account.tree_uuid = device.tree_uuid)
	`, deviceID, userID); err != nil {
		return err
	}

	// 3. What is left has no counterpart, so it moves wholesale.
	_, err := tx.Exec(ctx, `
		UPDATE favorites SET user_id = $2, device_id = NULL, updated_at = $3 WHERE device_id = $1
	`, deviceID, userID, now)
	return err
}

// RecordLicenseConsent writes what the account agreed to, from `POST /devices/claim`.
//
// `version == nil` is a *declined* consent and is stored as one. It arrives as an explicit null on
// the wire rather than an omitted field, because `acceptsLicense` is derived from nil precisely so
// a Bool and a version string cannot disagree, and that property has to survive the wire (§5.6).
func (s *Store) RecordLicenseConsent(ctx context.Context, userID uuid.UUID, version *string) error {
	now := s.now()
	var acceptedAt *time.Time
	if version != nil {
		acceptedAt = &now
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE users SET license_version = $2, license_accepted_at = $3, updated_at = $4 WHERE id = $1
	`, userID, version, acceptedAt, now)
	return err
}
