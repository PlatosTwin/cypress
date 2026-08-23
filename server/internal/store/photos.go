package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ApprovalReason is why a photograph is approved. R72 ruling 5's non-optional bookkeeping.
type ApprovalReason string

const (
	// AutoApprovedLaunch is the launch rule: a first-party photograph, published unscreened and
	// unblurred, from a signed-in account.
	//
	// The value exists so the deviation stays legible as one. `.approved` alone cannot distinguish
	// this from a photograph a pipeline looked at, and a state you cannot distinguish is a backlog
	// you cannot re-run — which is unrecoverable after the fact, which is why the column ships
	// before the pipeline rather than with it.
	AutoApprovedLaunch ApprovalReason = "auto_approved_launch"
	// ScreenedAndPassed is what the DECISIONS §4 pipeline will write when it exists. Nothing in
	// this service writes it; it is declared so the column's vocabulary is complete rather than
	// growing a CHECK later.
	ScreenedAndPassed ApprovalReason = "screened_and_passed"
)

// NewPhoto is what `POST /photos/begin` reserves.
type NewPhoto struct {
	ID              uuid.UUID
	TreeUUID        uuid.UUID
	VisitClientUUID *uuid.UUID
	ShotType        string
	CapturedAt      time.Time
	Width           *int
	Height          *int
	PublicLat       *float64
	PublicLon       *float64
	StorageKey      string
	// ClientUUID is the binary's own client-minted id, and the key this service dedupes `begin` on
	// (`003_photo_idempotency_key.sql`). Nil from a client that does not send one — which is every
	// build before the send path — and such a begin is not idempotent, exactly as it never was.
	ClientUUID *uuid.UUID
}

// BegunPhoto is what a begin settled on: the row, and whether this call is the one that created it.
//
// `Existing` is not decoration. The handler presigns against the storage key that is actually on the
// row, and on a replay that is the **first** call's key rather than the one this call just
// generated. Presigning the fresh key would hand the client a URL to an object no `photos` row
// names, so the bytes would land somewhere nothing ever reads and the photograph would be collected
// after 72 h as "never arrived".
type BegunPhoto struct {
	ID         uuid.UUID
	StorageKey string
	Existing   bool
	// Moderation and ApprovalReason are the **row's**, not a recomputation from the caller.
	//
	// The handler used to synthesize them from `who` on every answer, which is right for an insert
	// and wrong for a replay: `ClaimDevice` re-homes a device's photographs onto an account without
	// touching `moderation_state`, so a device-begin, a sign-in that claims, then a replay reported
	// `approved`/`auto_approved_launch` while the row still held `pending`. The client evaluates
	// `isPubliclyVisible` from this payload, so the app claimed public visibility until the next
	// `treeProfile` read contradicted it (#116 r3).
	Moderation     string
	ApprovalReason *string
}

// BeginPhoto reserves the photo record and decides its moderation state on the spot.
//
// ── The auto-approve rule, and the one thing it turns on ───────────────────────────────────────
//
// R72 ruling 5: a photograph from a **signed-in account** is approved on upload. First-party means
// the account, not the device, and the ruling gives the reason — the device credential is not an
// attestation, a reinstall mints a new one, so a device-scoped rule gives an operator nothing to
// act against that survives. An account carries Apple's verification and can have it withdrawn.
//
// So an anonymous device's photograph stays `.pending` and is therefore visible to its contributor
// and to nobody else. That is `isVisibleToItsContributor` doing exactly what ERRATA E37 designed it
// to do, and it makes screen 15's drawn promise — "An account backs them up and lets them join each
// tree's public timeline" — literally true rather than needing new copy.
// ── Idempotency, and why the lookup comes first ────────────────────────────────────────────────
//
// With a `ClientUUID` this is retryable: the key is looked up before anything is inserted, and a
// begin that has already been answered returns the row it made. Migration 003 states the defect this
// closes — a begin whose answer went missing had no way to ask "did that land?", and asking again
// made a second photograph.
//
// The lookup is first rather than relying on `ON CONFLICT DO NOTHING`, because the two are not the
// same answer: the conflict arm tells you the insert did nothing, but not *which* row won, and the
// caller needs that row's storage key to presign against. `BegunPhoto.Existing` says why.
//
// Both run in one transaction, so a second call arriving between the lookup and the insert loses the
// race at the unique index rather than duplicating the row — the index is the authority, and the
// lookup is the fast path that also tells the caller what it needs.
func (s *Store) BeginPhoto(ctx context.Context, photo NewPhoto, owner Owner) (BegunPhoto, error) {
	state := "pending"
	var reason *ApprovalReason
	if owner.UserID != nil {
		state = "approved"
		auto := AutoApprovedLaunch
		reason = &auto
	}
	now := s.now()

	var begun BegunPhoto
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		if photo.ClientUUID != nil {
			var id uuid.UUID
			var key string
			var deletedAt *time.Time
			var moderation string
			var approvalReason *string
			err := tx.QueryRow(ctx, `
				SELECT id, storage_key, deleted_at, moderation_state, approval_reason FROM photos
				 WHERE client_uuid = $1
				   AND (($2::uuid IS NOT NULL AND user_id = $2)
				     OR ($3::uuid IS NOT NULL AND device_id = $3))
			`, photo.ClientUUID, owner.UserID, owner.DeviceID).Scan(&id, &key, &deletedAt, &moderation, &approvalReason)
			if err == nil {
				// ── A replay for a photograph that has since been withdrawn ──────────────────
				//
				// **Refused, and this is the honest one of the two available answers.** Without
				// this arm the replay returned the tombstoned row together with a *fresh presigned
				// PUT*, so a client still holding that upload would write the bytes and record the
				// send as a success — after the contributor had deleted the picture. That is
				// ERRATA E147's harm arriving through the one door that opens after the deletion
				// gate, and it is worse here than anywhere else because nothing in this service
				// deletes an object: bytes written after a withdrawal stay written (the obligation
				// this round records in `docs/errata-pending/`).
				//
				// The alternative — mint a fresh row and let the upload proceed — was considered
				// and is wrong twice. It resurrects something a person asked to be gone, and it
				// cannot work anyway: the unique index does not exclude tombstoned rows, so the key
				// is still taken and the insert would be refused.
				//
				// `ErrPhotoWithdrawn` rather than `ErrNotFound` so the caller can say the true
				// thing; the handler maps it to `not_found`, which is non-retryable, so the client
				// stops rather than spending 48 h re-asking for a photograph that is gone.
				// **`rejected` refuses on the same argument as `deleted_at`** (#116 review N16).
				// `RejectPhoto` is the operator takedown and it moves `moderation_state` without
				// setting `deleted_at`, so a replay after a takedown was still answered with a
				// fresh presigned PUT and the bytes landed — the same door F2 closed, reached from
				// the operator's side instead of the contributor's. It matters for exactly the
				// reason F2 does: nothing in this service deletes an object, so bytes written after
				// a takedown stay written.
				//
				// Both are the same answer to the caller because they are the same fact about the
				// upload: this photograph is not going to be published, so its bytes are not wanted.
				if deletedAt != nil || moderation == "rejected" {
					return ErrPhotoWithdrawn
				}
				begun = BegunPhoto{
					ID: id, StorageKey: key, Existing: true,
					Moderation: moderation, ApprovalReason: approvalReason,
				}
				return nil
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}

		_, err := tx.Exec(ctx, `
			INSERT INTO photos
			    (id, tree_uuid, visit_client_uuid, user_id, device_id, shot_type,
			     moderation_state, approval_reason, captured_at, width, height,
			     public_lat, public_lon, storage_key, client_uuid, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $16)
		`, photo.ID, photo.TreeUUID, photo.VisitClientUUID, owner.UserID, owner.DeviceID,
			photo.ShotType, state, reason, photo.CapturedAt, photo.Width, photo.Height,
			photo.PublicLat, photo.PublicLon, photo.StorageKey, photo.ClientUUID, now)
		if err != nil {
			return err
		}
		begun = BegunPhoto{
			ID: photo.ID, StorageKey: photo.StorageKey,
			Moderation: state, ApprovalReason: (*string)(reason),
		}
		return nil
	})
	return begun, err
}

// PhotoRecord is a stored photograph, as the read routes need it.
type PhotoRecord struct {
	ID              uuid.UUID
	TreeUUID        uuid.UUID
	UserID          *uuid.UUID
	DeviceID        *uuid.UUID
	ShotType        string
	ModerationState string
	ApprovalReason  *string
	BlurApplied     bool
	CapturedAt      time.Time
	StorageKey      string
	BytesReceivedAt *time.Time
	DeletedAt       *time.Time
}

// IsPubliclyVisible mirrors `Photo.isPubliclyVisible` exactly:
// `moderationState == .approved && deletedAt == nil`.
//
// Kept apart from IsVisibleToItsContributor deliberately (ERRATA E37): they are different
// questions and collapsing them is what E37 records the cost of.
func (p PhotoRecord) IsPubliclyVisible() bool {
	return p.ModerationState == "approved" && p.DeletedAt == nil
}

// IsVisibleToItsContributor mirrors `Photo.isVisibleToItsContributor`: `deletedAt == nil`.
func (p PhotoRecord) IsVisibleToItsContributor() bool { return p.DeletedAt == nil }

// Photo reads one record.
func (s *Store) Photo(ctx context.Context, id uuid.UUID) (PhotoRecord, error) {
	var photo PhotoRecord
	err := s.pool.QueryRow(ctx, `
		SELECT id, tree_uuid, user_id, device_id, shot_type, moderation_state, approval_reason,
		       blur_applied, captured_at, storage_key, bytes_received_at, deleted_at
		  FROM photos WHERE id = $1
	`, id).Scan(&photo.ID, &photo.TreeUUID, &photo.UserID, &photo.DeviceID, &photo.ShotType,
		&photo.ModerationState, &photo.ApprovalReason, &photo.BlurApplied, &photo.CapturedAt,
		&photo.StorageKey, &photo.BytesReceivedAt, &photo.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return PhotoRecord{}, ErrNotFound
	}
	return photo, err
}

// PhotosForTree returns the community timeline for a tree profile.
//
// Everything is returned, and the caller filters: `TreeProfile.isPhotoVisible(_:own:)` is the
// single predicate over the two visibility rules (ERRATA E215) and this query must not become a
// second one that can disagree with it.
func (s *Store) PhotosForTree(ctx context.Context, treeUUID uuid.UUID) ([]PhotoRecord, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, tree_uuid, user_id, device_id, shot_type, moderation_state, approval_reason,
		       blur_applied, captured_at, storage_key, bytes_received_at, deleted_at
		  FROM photos WHERE tree_uuid = $1 ORDER BY captured_at DESC
	`, treeUUID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var photos []PhotoRecord
	for rows.Next() {
		var photo PhotoRecord
		if err := rows.Scan(&photo.ID, &photo.TreeUUID, &photo.UserID, &photo.DeviceID,
			&photo.ShotType, &photo.ModerationState, &photo.ApprovalReason, &photo.BlurApplied,
			&photo.CapturedAt, &photo.StorageKey, &photo.BytesReceivedAt, &photo.DeletedAt); err != nil {
			return nil, err
		}
		photos = append(photos, photo)
	}
	return photos, rows.Err()
}

// MarkPhotoBytesReceived records that the binary landed, closing the 72 h grace window.
func (s *Store) MarkPhotoBytesReceived(ctx context.Context, id uuid.UUID) error {
	now := s.now()
	_, err := s.pool.Exec(ctx, `
		UPDATE photos SET bytes_received_at = $2, updated_at = $2 WHERE id = $1
	`, id, now)
	return err
}

// RejectPhoto is the operator takedown, and it is not optional.
//
// R72 ruling 5: "Auto-approve without a takedown is the version of this rule that must not ship."
// It costs the client nothing — `Photo.moderationState` is a `var` with a `.rejected` case and
// `isPubliclyVisible` is evaluated at render time from the payload — so a photograph flipped here
// stops being drawn on every other device at its next `treeProfile` read, with no app change, no
// new screen and no migration.
//
// The approval reason is cleared with the state, because a rejected row has no approval to explain
// and leaving a stale one would put "auto-approved at launch" on a photograph an operator removed.
//
// Operator-only, and there is deliberately no in-app route to it: no `ReviewFlag.Kind` is about a
// photograph, and a photo **vote is not a report** — reading a downvote as a takedown request would
// let a popularity mechanism decide a safety question.
func (s *Store) RejectPhoto(ctx context.Context, id uuid.UUID) error {
	now := s.now()
	tag, err := s.pool.Exec(ctx, `
		UPDATE photos
		   SET moderation_state = 'rejected', approval_reason = NULL, updated_at = $2
		 WHERE id = $1
	`, id, now)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ErrNotOwned is returned by the sync-path withdrawal when the photograph is here and is somebody
// else's.
//
// It exists because that path needs a **third** answer, and `DeletePhotoByContributor` only has
// two. There, "absent" and "not yours" are deliberately the same answer — `ErrNotFound`, so a
// refusal cannot confirm to a stranger that the row exists. A `photo_withdrawal` arriving on
// `POST /sync` is asked a different question, and collapsing the two answers would make it lie:
// "this service never held that photograph" is a success that changes nothing, while "it is here
// and it is not yours" must not be reported to the client as a removal. Screen 17 renders an
// applied withdrawal as "Photo removed"; answering that while `GET /photos/{id}` keeps serving the
// bytes is precisely the failure ERRATA E280 exists to prevent.
//
// The caller maps it to `forbidden` — non-retryable, so the item fails on the spot rather than
// spending 48 h on an answer that will not change.
var ErrNotOwned = errors.New("photo belongs to another contributor")

// ErrPhotoWithdrawn is returned when a begin replays a key whose photograph has been deleted.
//
// A separate error from ErrNotFound because the two are different facts and only one of them is
// about a key this service has seen: "there is no such photograph" and "there was, and its
// contributor took it back" lead to the same HTTP status by choice rather than by accident. See
// BeginPhoto for why the answer is a refusal and not a fresh row.
var ErrPhotoWithdrawn = errors.New("photo was withdrawn by its contributor")

// withdrawPhoto tombstones one photograph inside an already-open transaction.
//
// **It reads before it writes, which `DeletePhotoByContributor` does not have to.** That method can
// let one `UPDATE` carry both the ownership gate and the write, because it collapses "absent" and
// "not yours" into one answer anyway. This one has to tell those apart before it decides, so the
// row is fetched first and the three cases are separated explicitly:
//
//   - **no row** — nothing to withdraw. This is the shipping state ERRATA E264 describes: no
//     photograph reaches this service, so every withdrawal that arrives today lands here. It is a
//     success, and the contribution row is still recorded — the record of the act is the point.
//   - **already tombstoned** — success, changing nothing. A drain that replays a withdrawal after a
//     flap must not fail on the second pass.
//   - **present and not this identity's** — `ErrNotOwned`, above.
//
// **Ownership here is the two columns this service has, and that is not the same rule the client
// applies.** RULINGS R82 gave the client's removal predicate a third arm, `taken_on_device`, so a
// photograph this installation took stays its own to unmake whatever account holds it. This table
// has no provenance column — `001_initial.sql` gives `photos` a `user_id` and a `device_id` and
// nothing else — so a photograph taken on this device and owned by an account that is no longer
// signed in is deletable locally and `ErrNotOwned` here. That divergence is real, it is reachable,
// and it is recorded rather than guessed at: inventing a provenance column to match would be a
// migration nobody ruled on, and silently succeeding would be the E280 lie. See the round's PR.
func withdrawPhoto(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner, now time.Time) error {
	var userID, deviceID *uuid.UUID
	var deletedAt *time.Time
	err := tx.QueryRow(ctx, `
		SELECT user_id, device_id, deleted_at FROM photos WHERE id = $1
	`, id).Scan(&userID, &deviceID, &deletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if deletedAt != nil {
		return nil
	}

	owned := (owner.UserID != nil && userID != nil && *userID == *owner.UserID) ||
		(owner.DeviceID != nil && deviceID != nil && *deviceID == *owner.DeviceID)
	if !owned {
		return ErrNotOwned
	}

	_, err = tx.Exec(ctx, `
		UPDATE photos SET deleted_at = $2, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL
	`, id, now)
	return err
}

// DeletePhotoByContributor is `deletePhoto(id:)` — the contributor taking their own photograph back.
//
// Under the auto-approve rule this stops being a convenience and becomes the first line of the
// privacy argument ERRATA E147 makes for it: "a photograph can hold a face, a license plate or the
// inside of somebody's front garden, and the person who took it has to be able to take it back."
//
// Ownership is checked here rather than trusted from the caller, and a photograph that is not this
// identity's returns ErrNotFound rather than a refusal — a refusal would confirm the row exists to
// somebody who is not allowed to know that.
func (s *Store) DeletePhotoByContributor(ctx context.Context, id uuid.UUID, owner Owner) error {
	now := s.now()
	tag, err := s.pool.Exec(ctx, `
		UPDATE photos SET deleted_at = $2, updated_at = $2
		 WHERE id = $1 AND deleted_at IS NULL
		   AND (($3::uuid IS NOT NULL AND user_id = $3) OR ($4::uuid IS NOT NULL AND device_id = $4))
	`, id, now, owner.UserID, owner.DeviceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
