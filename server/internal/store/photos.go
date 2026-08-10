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
func (s *Store) BeginPhoto(ctx context.Context, photo NewPhoto, owner Owner) error {
	state := "pending"
	var reason *ApprovalReason
	if owner.UserID != nil {
		state = "approved"
		auto := AutoApprovedLaunch
		reason = &auto
	}
	now := s.now()
	_, err := s.pool.Exec(ctx, `
		INSERT INTO photos
		    (id, tree_uuid, visit_client_uuid, user_id, device_id, shot_type,
		     moderation_state, approval_reason, captured_at, width, height,
		     public_lat, public_lon, storage_key, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $15)
	`, photo.ID, photo.TreeUUID, photo.VisitClientUUID, owner.UserID, owner.DeviceID,
		photo.ShotType, state, reason, photo.CapturedAt, photo.Width, photo.Height,
		photo.PublicLat, photo.PublicLon, photo.StorageKey, now)
	return err
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
