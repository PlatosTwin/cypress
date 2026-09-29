package store

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The claim approving what it adopts, and migration 006 doing the same for claims that already ran.
//
// The handler-level promise — a stranger's `GET /trees/{id}` — is in
// `internal/api/photo_adoption_test.go`. These pin which rows move and which must not, which is a
// property of two WHERE clauses and two CASE arms, and so is asserted against the rows themselves.

// photoRow is the part of a `photos` row the approval can move, plus `updated_at`, which is what
// shows a row was *written* rather than merely left holding the same values.
type photoRow struct {
	State     string
	Reason    *string
	UserID    *uuid.UUID
	DeviceID  *uuid.UUID
	UpdatedAt time.Time
}

func readPhotoRow(t *testing.T, pool *pgxpool.Pool, id uuid.UUID) photoRow {
	t.Helper()
	var row photoRow
	if err := pool.QueryRow(context.Background(), `
		SELECT moderation_state, approval_reason, user_id, device_id, updated_at FROM photos WHERE id = $1
	`, id).Scan(&row.State, &row.Reason, &row.UserID, &row.DeviceID, &row.UpdatedAt); err != nil {
		t.Fatalf("reading photo %s: %v", id, err)
	}
	return row
}

func reasonString(reason *string) string {
	if reason == nil {
		return "<nil>"
	}
	return *reason
}

func beginAsDevice(t *testing.T, store *Store, deviceID uuid.UUID) uuid.UUID {
	t.Helper()
	photo := NewPhoto{
		ID: uuid.New(), TreeUUID: uuid.New(), ShotType: "full_tree",
		CapturedAt: time.Now().UTC(), StorageKey: "photos/" + uuid.New().String() + ".jpg",
	}
	begun, err := store.BeginPhoto(context.Background(), photo, DeviceOwner(deviceID))
	if err != nil {
		t.Fatalf("beginning photo: %v", err)
	}
	if begun.Moderation != "pending" {
		t.Fatalf("fixture: a device begin is %q, want pending", begun.Moderation)
	}
	return photo.ID
}

// insertPhoto writes a row directly, for states no handler reaches in one step.
func insertPhoto(t *testing.T, pool *pgxpool.Pool, userID, deviceID *uuid.UUID, state string,
	reason *string, deleted, anonymized bool) uuid.UUID {
	t.Helper()
	id := uuid.New()
	past := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	var deletedAt, anonymizedAt *time.Time
	if deleted {
		deletedAt = &past
	}
	if anonymized {
		anonymizedAt = &past
	}
	if _, err := pool.Exec(context.Background(), `
		INSERT INTO photos (id, tree_uuid, user_id, device_id, shot_type, moderation_state,
		                    approval_reason, captured_at, storage_key, deleted_at, anonymized_at,
		                    created_at, updated_at)
		VALUES ($1, $2, $3, $4, 'leaf', $5, $6, $7, $8, $9, $10, $7, $7)
	`, id, uuid.New(), userID, deviceID, state, reason, past,
		"photos/"+id.String()+".jpg", deletedAt, anonymizedAt); err != nil {
		t.Fatalf("inserting fixture photo (%s): %v", state, err)
	}
	return id
}

func ptr[T any](value T) *T { return &value }

// ── The claim ──────────────────────────────────────────────────────────────────────────────────

func TestClaimApprovesTheDevicesPendingPhotograph(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-adopt")
	deviceUUID, deviceID := makeDevice(t, store)
	photo := beginAsDevice(t, store, deviceID)

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	row := readPhotoRow(t, store.pool, photo)
	if row.UserID == nil || *row.UserID != user.ID || row.DeviceID != nil {
		t.Fatalf("fixture: the claim did not adopt the photograph (user %v, device %v)",
			row.UserID, row.DeviceID)
	}
	if row.State != "approved" {
		t.Fatalf("an adopted photograph is %q after the claim, want approved — the account now "+
			"owns it and it is still private to its contributor", row.State)
	}
	if reasonString(row.Reason) != string(AutoApprovedLaunch) {
		t.Fatalf("approval_reason = %s, want %s — an approval without its rule is the backlog the "+
			"column exists to keep identifiable", reasonString(row.Reason), AutoApprovedLaunch)
	}
}

func TestClaimLeavesARejectedPhotographRejected(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-rejected")
	deviceUUID, deviceID := makeDevice(t, store)
	photo := beginAsDevice(t, store, deviceID)
	if err := store.RejectPhoto(context.Background(), photo); err != nil {
		t.Fatal(err)
	}

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	row := readPhotoRow(t, store.pool, photo)
	if row.UserID == nil || *row.UserID != user.ID {
		t.Fatal("fixture: the rejected photograph was not adopted, so the claim never had the " +
			"chance to approve it and this test would pass for the wrong reason")
	}
	if row.State != "rejected" || row.Reason != nil {
		t.Fatalf("after the claim a taken-down photograph holds %q / %s, want rejected / <nil> — "+
			"a sign-in is not an appeal", row.State, reasonString(row.Reason))
	}
}

func TestClaimLeavesAnotherDevicesPendingPhotographAlone(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-neighbor")
	deviceUUID, deviceID := makeDevice(t, store)
	_, otherDeviceID := makeDevice(t, store)
	mine := beginAsDevice(t, store, deviceID)
	theirs := beginAsDevice(t, store, otherDeviceID)
	before := readPhotoRow(t, store.pool, theirs)

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	if readPhotoRow(t, store.pool, mine).State != "approved" {
		t.Fatal("control: the claimed device's own photograph was not approved, so the other " +
			"device's staying pending proves nothing")
	}
	after := readPhotoRow(t, store.pool, theirs)
	if after.State != "pending" || after.Reason != nil {
		t.Fatalf("another device's photograph is %q / %s after this device's claim, want pending",
			after.State, reasonString(after.Reason))
	}
	if after.UserID != nil || after.DeviceID == nil || *after.DeviceID != otherDeviceID {
		t.Fatalf("another device's photograph changed hands: user %v, device %v", after.UserID, after.DeviceID)
	}
	if !after.UpdatedAt.Equal(before.UpdatedAt) {
		t.Error("another device's photograph was written by this device's claim")
	}
}

func TestClaimDoesNotApproveAWithdrawnPhotograph(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-withdrawn")
	deviceUUID, deviceID := makeDevice(t, store)
	photo := beginAsDevice(t, store, deviceID)
	if err := store.DeletePhotoByContributor(context.Background(), photo, DeviceOwner(deviceID)); err != nil {
		t.Fatal(err)
	}

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	row := readPhotoRow(t, store.pool, photo)
	if row.UserID == nil || *row.UserID != user.ID {
		t.Fatal("fixture: the withdrawn photograph was not adopted, so the claim never had the " +
			"chance to approve it")
	}
	if row.State != "pending" || row.Reason != nil {
		t.Fatalf("a photograph its contributor withdrew is %q / %s after the claim, want pending — "+
			"approving it records an approval of something taken back", row.State, reasonString(row.Reason))
	}
}

// TestClaimDoesNotApproveAnAnonymizedPhotograph is defense in depth, and says so.
//
// No code path leaves an anonymized photograph carrying a device for this sweep to match, but not
// because anonymization clears `device_id`: the two anonymization statements in `sync.go` set
// `user_id = NULL` and leave `device_id` alone. They match only account-owned rows, and
// `photos_owner` forbids an account-owned row from also naming a device, so the rows they
// anonymize never had one. The row below is storable (no CHECK on `photos` forbids it) and
// unreachable, and it is here so that broadening the sweep's WHERE cannot quietly adopt — and now
// approve — a photograph somebody asked to be unlinked from.
func TestClaimDoesNotApproveAnAnonymizedPhotograph(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-anonymized")
	deviceUUID, deviceID := makeDevice(t, store)
	photo := insertPhoto(t, store.pool, nil, &deviceID, "pending", nil, false, true)

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	row := readPhotoRow(t, store.pool, photo)
	if row.State != "pending" || row.UserID != nil {
		t.Fatalf("an anonymized photograph is %q, owned by %v, after the claim — want pending and "+
			"unowned", row.State, row.UserID)
	}
}

// TestClaimLeavesAnApprovedPhotographsReasonAlone pins "only pending moves".
//
// A device-owned approved row is not reachable today (a device begin is always pending), which is
// why it is inserted directly. What it pins is that the CASE arms key on the state and do not
// stamp every adopted row with the launch reason.
func TestClaimLeavesAnApprovedPhotographsReasonAlone(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-screened")
	deviceUUID, deviceID := makeDevice(t, store)
	photo := insertPhoto(t, store.pool, nil, &deviceID, "approved",
		ptr(string(ScreenedAndPassed)), false, false)

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	row := readPhotoRow(t, store.pool, photo)
	if row.UserID == nil || *row.UserID != user.ID {
		t.Fatal("fixture: the approved photograph was not adopted")
	}
	if row.State != "approved" || reasonString(row.Reason) != string(ScreenedAndPassed) {
		t.Fatalf("an already-approved photograph holds %q / %s after the claim, want approved / %s",
			row.State, reasonString(row.Reason), ScreenedAndPassed)
	}
}

// ── Migration 006 ──────────────────────────────────────────────────────────────────────────────

// storeAtVersionBefore opens a fresh database migrated up to, and not including, the named file —
// the state production is in when a deploy carrying that file boots.
func storeAtVersionBefore(t *testing.T, name string) (*Store, migrationFile) {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), testDatabaseURL(t, "cypress_test_store_before"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	store := &Store{pool: pool, now: func() time.Time { return time.Now().UTC() }}

	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(context.Background(), schemaMigrationsDDL); err != nil {
		t.Fatal(err)
	}
	for _, file := range files {
		if file.Name == name {
			version, err := store.SchemaVersion(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if version != file.Version-1 {
				t.Fatalf("fixture: the database is at %03d, want %03d", version, file.Version-1)
			}
			return store, file
		}
		if err := store.applyOne(context.Background(), file); err != nil {
			t.Fatal(err)
		}
	}
	t.Fatalf("no migration is named %q", name)
	return nil, migrationFile{}
}

// TestMigration006ApprovesExactlyTheAdoptedPendingSet runs 006 the way a deploy does — against a
// database at 005 holding a row of every kind — and requires that exactly one kind moved.
//
// "Moved" is read off `updated_at` as well as the values, so a row the UPDATE rewrote with the same
// state (an approved row re-stamped `auto_approved_launch`, say) counts as touched. The predicate is
// claimed to be exact, and exact means it writes nothing else.
func TestMigration006ApprovesExactlyTheAdoptedPendingSet(t *testing.T) {
	store, file := storeAtVersionBefore(t, "approve_adopted_photos")
	pool := store.pool

	account := makeUser(t, store, "apple-sub-006")
	_, device := makeDevice(t, store)
	launch := ptr(string(AutoApprovedLaunch))
	screened := ptr(string(ScreenedAndPassed))

	type fixture struct {
		name       string
		id         uuid.UUID
		wantMoved  bool
		wantState  string
		wantReason *string
	}
	fixtures := []fixture{
		// The one set that must move: adopted by a claim while pending, live.
		{name: "adopted while pending", wantMoved: true, wantState: "approved", wantReason: launch,
			id: insertPhoto(t, pool, &account.ID, nil, "pending", nil, false, false)},
		{name: "account begin, approved at upload", wantState: "approved", wantReason: launch,
			id: insertPhoto(t, pool, &account.ID, nil, "approved", launch, false, false)},
		{name: "account-owned, approved by a screen", wantState: "approved", wantReason: screened,
			id: insertPhoto(t, pool, &account.ID, nil, "approved", screened, false, false)},
		{name: "account-owned, taken down", wantState: "rejected",
			id: insertPhoto(t, pool, &account.ID, nil, "rejected", nil, false, false)},
		{name: "adopted while pending, then withdrawn", wantState: "pending",
			id: insertPhoto(t, pool, &account.ID, nil, "pending", nil, true, false)},
		// Unreachable through the code (anonymization clears user_id in the same statement) and
		// storable — the row that pins the `anonymized_at IS NULL` arm.
		{name: "account-owned pending, anonymized", wantState: "pending",
			id: insertPhoto(t, pool, &account.ID, nil, "pending", nil, false, true)},
		// The real anonymized shape: the leaving door's.
		{name: "anonymized by an account deletion", wantState: "pending",
			id: insertPhoto(t, pool, nil, nil, "pending", nil, true, true)},
		{name: "anonymous device, never claimed", wantState: "pending",
			id: insertPhoto(t, pool, nil, &device, "pending", nil, false, false)},
		{name: "anonymous device, taken down", wantState: "rejected",
			id: insertPhoto(t, pool, nil, &device, "rejected", nil, false, false)},
		// A device row deleted out from under its photograph (`ON DELETE SET NULL`).
		{name: "ownerless pending", wantState: "pending",
			id: insertPhoto(t, pool, nil, nil, "pending", nil, false, false)},
	}

	before := map[uuid.UUID]photoRow{}
	for _, f := range fixtures {
		before[f.id] = readPhotoRow(t, pool, f.id)
	}

	if err := store.Migrate(context.Background()); err != nil {
		t.Fatalf("applying %03d_%s.sql to a database holding every kind of row: %v",
			file.Version, file.Name, err)
	}

	moved := 0
	for _, f := range fixtures {
		after := readPhotoRow(t, pool, f.id)
		wasMoved := !after.UpdatedAt.Equal(before[f.id].UpdatedAt)
		if wasMoved {
			moved++
		}
		if wasMoved != f.wantMoved {
			t.Errorf("%s: written = %v, want %v", f.name, wasMoved, f.wantMoved)
		}
		if after.State != f.wantState || reasonString(after.Reason) != reasonString(f.wantReason) {
			t.Errorf("%s: %q / %s after 006, want %q / %s", f.name,
				after.State, reasonString(after.Reason), f.wantState, reasonString(f.wantReason))
		}
		if (after.UserID == nil) != (before[f.id].UserID == nil) || (after.DeviceID == nil) != (before[f.id].DeviceID == nil) {
			t.Errorf("%s: 006 changed who owns the photograph", f.name)
		}
	}
	if moved != 1 {
		t.Errorf("006 wrote %d rows, want exactly 1", moved)
	}
}

// TestAnAccountsLivePhotographCannotBeStoredPending is the constraint 006 adds, and the reason an
// adoption path that forgets to approve fails loudly instead of privatizing a photograph for good.
//
// The control comes first: the same insert with `deleted_at` set is accepted, so the refusal is
// this constraint's and not a foreign key's or a missing column's.
func TestAnAccountsLivePhotographCannotBeStoredPending(t *testing.T) {
	store := testStore(t)
	account := makeUser(t, store, "apple-sub-constraint")
	past := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	insert := func(deletedAt *time.Time) error {
		id := uuid.New()
		_, err := store.pool.Exec(context.Background(), `
			INSERT INTO photos (id, tree_uuid, user_id, shot_type, moderation_state, captured_at,
			                    storage_key, deleted_at)
			VALUES ($1, $2, $3, 'leaf', 'pending', $4, $5, $6)
		`, id, uuid.New(), account.ID, past, "photos/"+id.String()+".jpg", deletedAt)
		return err
	}

	if err := insert(&past); err != nil {
		t.Fatalf("control: a withdrawn account photograph could not be stored pending: %v", err)
	}
	err := insert(nil)
	if err == nil {
		t.Fatal("Postgres stored a live, account-owned photograph as pending; the next adoption " +
			"path that forgets to approve will make photographs private for good and nothing will say so")
	}
	if !strings.Contains(err.Error(), "photos_owned_live_photograph_is_not_pending") {
		t.Fatalf("refused, but not by the constraint 006 adds: %v", err)
	}
}
