package store

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ── Why these run against a real Postgres and skip loudly without one ──────────────────────────
//
// Every behaviour this file asserts is a property of SQL: a `WHERE` clause that stops matching once
// it has run, an `ON CONFLICT DO NOTHING`, a partial unique index, a `CHECK`. A Go double
// re-implementing them would prove that the double agrees with itself, which is the shape of guard
// this project has repeatedly caught going green while the defect it named was present.
//
// So: `CYPRESS_TEST_DATABASE_URL`, or nothing. `t.Skip` rather than a silent pass, because a suite
// that reports success having run none of this is worse than one that reports nothing.

// testDatabaseURL gives this test binary a database of its own.
//
// `go test` runs packages in parallel, and two binaries sharing one database deadlock each other
// between `CREATE TABLE IF NOT EXISTS` and `TRUNCATE`. That failure has nothing to do with the
// code under test and everything to do with the harness, which is the most expensive kind of red
// to debug — so it is designed out rather than worked around with `-p 1`.
func testDatabaseURL(t *testing.T, name string) string {
	t.Helper()
	base := os.Getenv("CYPRESS_TEST_DATABASE_URL")
	if base == "" {
		t.Skip("CYPRESS_TEST_DATABASE_URL is not set; these assertions are about SQL and will not " +
			"be faked. Start a Postgres and set it.")
	}
	admin, err := pgx.Connect(context.Background(), base)
	if err != nil {
		t.Fatalf("connecting to %s: %v", base, err)
	}
	defer admin.Close(context.Background())

	// **Dropped and recreated, not reused.** The schema is applied with `CREATE TABLE IF NOT
	// EXISTS`, so a database left over from a previous run keeps whatever shape it had — and a
	// changed column would then be tested in its old form, silently, which is a green that means
	// nothing. Building it from scratch every run is the only way the schema under test is the
	// schema in the file.
	if _, err := admin.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)"); err != nil {
		t.Fatalf("dropping %s: %v", name, err)
	}
	if _, err := admin.Exec(context.Background(), "CREATE DATABASE "+name); err != nil {
		t.Fatalf("creating %s: %v", name, err)
	}

	parsed, err := url.Parse(base)
	if err != nil {
		t.Fatalf("parsing CYPRESS_TEST_DATABASE_URL: %v", err)
	}
	parsed.Path = "/" + name
	return parsed.String()
}

func testStore(t *testing.T) *Store {
	t.Helper()
	store, err := Open(context.Background(), testDatabaseURL(t, "cypress_test_store"))
	if err != nil {
		t.Fatalf("opening the test database: %v", err)
	}
	t.Cleanup(store.Close)

	_, err = store.pool.Exec(context.Background(), `
		TRUNCATE anonymized_contributions, favorites, contributions, community_trees, photos,
		         device_tokens, sessions, devices, users RESTART IDENTITY CASCADE
	`)
	if err != nil {
		t.Fatalf("truncating: %v", err)
	}
	return store
}

func makeUser(t *testing.T, store *Store, subject string) User {
	t.Helper()
	user, err := store.UpsertUserForApple(context.Background(), subject, subject+"@example.test", "refresh-"+subject)
	if err != nil {
		t.Fatalf("creating user: %v", err)
	}
	return user
}

func makeDevice(t *testing.T, store *Store) (deviceUUID, deviceID uuid.UUID) {
	t.Helper()
	deviceUUID = uuid.New()
	id, err := store.RegisterDevice(context.Background(), deviceUUID)
	if err != nil {
		t.Fatalf("registering device: %v", err)
	}
	return deviceUUID, id
}

func applyVisit(t *testing.T, store *Store, key, tree uuid.UUID, owner Owner, at time.Time) ApplyOutcome {
	t.Helper()
	outcome, err := store.Apply(context.Background(), Mutation{
		ClientUUID: key, Kind: "visit", TreeUUID: tree,
		Payload: json.RawMessage(`{"note":"a visit"}`), OccurredAt: at,
	}, owner)
	if err != nil {
		t.Fatalf("applying visit: %v", err)
	}
	return outcome
}

// ── Dedupe on client_uuid ──────────────────────────────────────────────────────────────────────

func TestApplyDedupesOnClientUUID(t *testing.T) {
	store := testStore(t)
	_, deviceID := makeDevice(t, store)
	key, tree := uuid.New(), uuid.New()
	now := time.Now().UTC().Truncate(time.Millisecond)

	if got := applyVisit(t, store, key, tree, DeviceOwner(deviceID), now); got != Applied {
		t.Fatalf("first apply = %v, want Applied", got)
	}
	if got := applyVisit(t, store, key, tree, DeviceOwner(deviceID), now); got != Duplicate {
		t.Fatalf("replay = %v, want Duplicate — this is what makes OutboxChaosTests' "+
			"zero-duplicates assertion hold across a flap", got)
	}

	var count int
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("the replay stored %d rows, want 1", count)
	}
}

// ── The tombstone: an item accepted after deletion must not resurrect the account ──────────────

func TestItemArrivingAfterDeletionIsDuplicateNotResurrection(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-tombstone")
	_, deviceID := makeDevice(t, store)

	// The straddle the client's `anonymized_contributions` exists for: queued Tuesday, account
	// deleted Wednesday, drained Thursday. The key exists before the row does, which is the whole
	// reason the tombstone is keyed on it rather than being a column.
	queuedKey, tree := uuid.New(), uuid.New()

	if _, err := store.DeleteAccount(context.Background(), user.ID, LeaveRecords, []uuid.UUID{queuedKey}, ""); err != nil {
		t.Fatalf("deleting account: %v", err)
	}

	tombstoned, err := store.IsTombstoned(context.Background(), queuedKey)
	if err != nil {
		t.Fatal(err)
	}
	if !tombstoned {
		t.Fatal("the deletion did not tombstone a key it was told was still queued; " +
			"the mark has to be waiting when the drain arrives")
	}

	_, applyErr := store.Apply(context.Background(), Mutation{
		ClientUUID: queuedKey, Kind: "visit", TreeUUID: tree,
		Payload: json.RawMessage(`{}`), OccurredAt: time.Now().UTC(),
	}, DeviceOwner(deviceID))
	if !errors.Is(applyErr, ErrTombstoned) {
		t.Fatalf("apply after deletion = %v, want ErrTombstoned (which the handler answers as "+
			"`duplicate`: a success that changes nothing)", applyErr)
	}

	var stored int
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, queuedKey).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != 0 {
		t.Fatalf("a tombstoned item stored %d rows; a stranger's withdrawn record is back in play", stored)
	}
}

func TestDeletionLeaveRecordsAnonymizesRatherThanDeletes(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-leave")
	key, tree := uuid.New(), uuid.New()
	applyVisit(t, store, key, tree, UserOwner(user.ID), time.Now().UTC())

	if _, err := store.DeleteAccount(context.Background(), user.ID, LeaveRecords, nil, ""); err != nil {
		t.Fatalf("deleting: %v", err)
	}

	var ownerUser, ownerDevice *uuid.UUID
	var anonymizedAt *time.Time
	err := store.pool.QueryRow(context.Background(),
		`SELECT user_id, device_id, anonymized_at FROM contributions WHERE client_uuid = $1`, key).
		Scan(&ownerUser, &ownerDevice, &anonymizedAt)
	if err != nil {
		t.Fatalf("the leaving door removed the row; it is meant to stay on its tree with the "+
			"name taken off: %v", err)
	}
	if ownerUser != nil || ownerDevice != nil {
		t.Error("the row still names an owner after the leaving door")
	}
	if anonymizedAt == nil {
		t.Error("the row is ownerless but not marked anonymized; that state is exactly what the " +
			"tombstone exists to distinguish from `never had an account`")
	}
}

func TestDeletionEraseEverythingRemovesTheRows(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-erase")
	key, tree := uuid.New(), uuid.New()
	applyVisit(t, store, key, tree, UserOwner(user.ID), time.Now().UTC())

	if _, err := store.DeleteAccount(context.Background(), user.ID, EraseEverything, nil, ""); err != nil {
		t.Fatalf("deleting: %v", err)
	}
	var count int
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM contributions WHERE client_uuid = $1`, key).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatal("the erasing door left the row standing")
	}
	// And it is still tombstoned, so a replay of the same key does not put it back.
	tombstoned, err := store.IsTombstoned(context.Background(), key)
	if err != nil {
		t.Fatal(err)
	}
	if !tombstoned {
		t.Fatal("an erased row left no tombstone; a queued replay would re-insert it")
	}
}

// ── The claim: idempotency, and the #174 guard ─────────────────────────────────────────────────

func TestClaimDeviceIsIdempotent(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-claim")
	deviceUUID, deviceID := makeDevice(t, store)

	key, tree := uuid.New(), uuid.New()
	applyVisit(t, store, key, tree, DeviceOwner(deviceID), time.Now().UTC())

	for attempt := 1; attempt <= 3; attempt++ {
		if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
			t.Fatalf("claim attempt %d: %v — the client re-invokes this after every batch that "+
				"applied anything, so it must be safe to run repeatedly", attempt, err)
		}
	}

	var ownerUser *uuid.UUID
	var ownerDevice *uuid.UUID
	err := store.pool.QueryRow(context.Background(),
		`SELECT user_id, device_id FROM contributions WHERE client_uuid = $1`, key).
		Scan(&ownerUser, &ownerDevice)
	if err != nil {
		t.Fatal(err)
	}
	if ownerUser == nil || *ownerUser != user.ID {
		t.Fatalf("after the claim the row's user_id is %v, want %v", ownerUser, user.ID)
	}
	if ownerDevice != nil {
		t.Error("the device link survived the claim; adoption is a move rather than an addition, " +
			"so the row must carry strictly less about the device afterwards than before")
	}

	var rows int
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM contributions`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Fatalf("three claims produced %d rows; the sweep inserted something", rows)
	}
}

// TestClaimRefusesADeviceHeldByAnotherAccount is the #174 guard.
//
// The client's version of this defect: `device.user_id` outlives the sign-in, so the claim row is
// history rather than authority, and re-claiming against it adopted rows it should not have. The
// server has the same trap by the same mechanism — `devices.user_id` is never cleared by a
// sign-out, because a sign-out is not a request this service receives.
func TestClaimRefusesADeviceHeldByAnotherAccount(t *testing.T) {
	store := testStore(t)
	first := makeUser(t, store, "apple-sub-first")
	second := makeUser(t, store, "apple-sub-second")
	deviceUUID, deviceID := makeDevice(t, store)

	if err := store.ClaimDevice(context.Background(), deviceUUID, first.ID); err != nil {
		t.Fatalf("first claim: %v", err)
	}

	// A row written on this phone *after* the first account signed out. Under the defect #174
	// records, the next claim adopts it for whoever asks.
	key, tree := uuid.New(), uuid.New()
	applyVisit(t, store, key, tree, DeviceOwner(deviceID), time.Now().UTC())

	err := store.ClaimDevice(context.Background(), deviceUUID, second.ID)
	if !errors.Is(err, ErrClaimedByAnotherAccount) {
		t.Fatalf("a second account's claim returned %v, want ErrClaimedByAnotherAccount", err)
	}

	var ownerUser *uuid.UUID
	var ownerDevice *uuid.UUID
	if err := store.pool.QueryRow(context.Background(),
		`SELECT user_id, device_id FROM contributions WHERE client_uuid = $1`, key).
		Scan(&ownerUser, &ownerDevice); err != nil {
		t.Fatal(err)
	}
	if ownerUser != nil {
		t.Fatalf("the refused claim still re-homed the row onto %v — this is #174 exactly", *ownerUser)
	}
	if ownerDevice == nil || *ownerDevice != deviceID {
		t.Error("the row lost its device without gaining an account")
	}
}

// TestClaimDoesNotAdoptAnonymizedRows pins the other half of the same guard.
//
// A row unlinked by a deletion has no owner by design. It must not be adoptable by the next person
// to sign in on this phone — which is the client's `notAnonymized(table)` clause, and is why the
// tombstone distinguishes "anonymized by a deletion" from "never had an account".
//
// ── What red-proofing this actually found, recorded so the next reader does not re-derive it ───
//
// Removing `AND anonymized_at IS NULL` from the sweep leaves this test **green**, and that is not
// the test being weak — it is the invariant being held somewhere better. Anonymization clears
// `device_id` as well as `user_id`, so an anonymized row never matches `WHERE device_id = $3` in
// the first place; the predicate is defense in depth over a case the deletion has already made
// unreachable.
//
// It earns its keep the moment the sweep is broadened. Dropping the device scope *and* the
// predicate together does go red — and it goes red from `contributions_owner`, because setting
// `user_id` on a row carrying `anonymized_at` satisfies neither arm of that CHECK. So the ordering
// is: the deletion makes it unreachable, the predicate makes it explicit, and the CHECK makes it
// unstorable. The assertion below is the backstop for all three, and fires only if every one of
// them is removed.
func TestClaimDoesNotAdoptAnonymizedRows(t *testing.T) {
	store := testStore(t)
	first := makeUser(t, store, "apple-sub-anon-first")
	second := makeUser(t, store, "apple-sub-anon-second")
	deviceUUID, _ := makeDevice(t, store)

	key, tree := uuid.New(), uuid.New()
	applyVisit(t, store, key, tree, UserOwner(first.ID), time.Now().UTC())
	if _, err := store.DeleteAccount(context.Background(), first.ID, LeaveRecords, nil, ""); err != nil {
		t.Fatalf("deleting: %v", err)
	}

	if err := store.ClaimDevice(context.Background(), deviceUUID, second.ID); err != nil {
		t.Fatalf("claim: %v", err)
	}

	var ownerUser *uuid.UUID
	if err := store.pool.QueryRow(context.Background(),
		`SELECT user_id FROM contributions WHERE client_uuid = $1`, key).Scan(&ownerUser); err != nil {
		t.Fatal(err)
	}
	if ownerUser != nil {
		t.Fatalf("a withdrawn record was adopted by %v; a stranger's deleted contribution is now "+
			"attributed to whoever signed in next", *ownerUser)
	}
}

// TestClaimResolvesTheFavoriteCollision is ERRATA E89's case.
//
// Two rows can be the same record: the device favorited a tree the account had already favorited
// elsewhere. A plain UPDATE would hit the unique index and abort the whole claim, which means
// sign-in fails for the contributor whose grove overlaps most.
func TestClaimResolvesTheFavoriteCollision(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-fav")
	deviceUUID, deviceID := makeDevice(t, store)
	tree := uuid.New()

	earlier := time.Now().UTC().Add(-time.Hour).Truncate(time.Millisecond)
	later := time.Now().UTC().Truncate(time.Millisecond)

	toggle := func(key uuid.UUID, owner Owner, state bool, at time.Time) {
		t.Helper()
		if _, err := store.Apply(context.Background(), Mutation{
			ClientUUID: key, Kind: "favorite_toggle", TreeUUID: tree,
			Payload: json.RawMessage(`{"isFavorite":true}`), OccurredAt: at, IsFavorite: state,
		}, owner); err != nil {
			t.Fatalf("applying toggle: %v", err)
		}
	}

	// The account hearted it an hour ago from another phone; this device un-hearted it just now.
	toggle(uuid.New(), UserOwner(user.ID), true, earlier)
	toggle(uuid.New(), DeviceOwner(deviceID), false, later)

	if err := store.ClaimDevice(context.Background(), deviceUUID, user.ID); err != nil {
		t.Fatalf("the claim aborted on the favorite collision: %v", err)
	}

	var rows int
	var state bool
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*), bool_or(is_favorite) FROM favorites WHERE user_id = $1 AND tree_uuid = $2`,
		user.ID, tree).Scan(&rows, &state); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Fatalf("after the claim the account holds %d rows for one tree, want 1", rows)
	}
	if state {
		t.Error("the earlier heart won; a toggle resolves by time — whichever the person said last " +
			"is what they meant")
	}
}

// ── The approval-reason obligation ─────────────────────────────────────────────────────────────

func TestSignedInPhotoIsApprovedWithAReason(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-photo")
	photo := NewPhoto{
		ID: uuid.New(), TreeUUID: uuid.New(), ShotType: "full_tree",
		CapturedAt: time.Now().UTC(), StorageKey: "photos/a.jpg",
	}
	if err := store.BeginPhoto(context.Background(), photo, UserOwner(user.ID)); err != nil {
		t.Fatalf("beginning photo: %v", err)
	}
	stored, err := store.Photo(context.Background(), photo.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.ModerationState != "approved" {
		t.Fatalf("a signed-in account's photo is %q, want approved (R72 ruling 5)", stored.ModerationState)
	}
	if stored.ApprovalReason == nil || *stored.ApprovalReason != string(AutoApprovedLaunch) {
		t.Fatalf("approval_reason = %v, want auto_approved_launch — without it the backlog is "+
			"unidentifiable, which the ruling calls unrecoverable after the fact", stored.ApprovalReason)
	}
	if !stored.IsPubliclyVisible() {
		t.Error("the photograph is approved but not publicly visible")
	}
}

func TestAnonymousDevicePhotoStaysPendingAndPrivate(t *testing.T) {
	store := testStore(t)
	_, deviceID := makeDevice(t, store)
	photo := NewPhoto{
		ID: uuid.New(), TreeUUID: uuid.New(), ShotType: "trunk",
		CapturedAt: time.Now().UTC(), StorageKey: "photos/b.jpg",
	}
	if err := store.BeginPhoto(context.Background(), photo, DeviceOwner(deviceID)); err != nil {
		t.Fatalf("beginning photo: %v", err)
	}
	stored, err := store.Photo(context.Background(), photo.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.ModerationState != "pending" {
		t.Fatalf("an anonymous device's photo is %q, want pending: first-party means the signed-in "+
			"account, not the device", stored.ModerationState)
	}
	if stored.IsPubliclyVisible() {
		t.Error("an unapproved photograph is publicly visible")
	}
	if !stored.IsVisibleToItsContributor() {
		t.Error("it must stay visible to the person who took it (ERRATA E37)")
	}
}

// TestApprovedWithoutAReasonIsUnstorable proves the obligation is the engine's job.
//
// The column could have been "remembered" by whoever writes the next approval path. The CHECK is
// what makes forgetting it impossible, and this asserts the CHECK rather than the handler.
func TestApprovedWithoutAReasonIsUnstorable(t *testing.T) {
	store := testStore(t)
	_, err := store.pool.Exec(context.Background(), `
		INSERT INTO photos (id, tree_uuid, shot_type, moderation_state, captured_at, storage_key)
		VALUES ($1, $2, 'leaf', 'approved', now(), 'photos/no-reason.jpg')
	`, uuid.New(), uuid.New())
	if err == nil {
		t.Fatal("Postgres accepted an approved photograph with no approval_reason; the backlog " +
			"cursor is optional and the ruling says it must not be")
	}
}

func TestOperatorTakedownMovesAPhotoToRejected(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-takedown")
	photo := NewPhoto{
		ID: uuid.New(), TreeUUID: uuid.New(), ShotType: "full_tree",
		CapturedAt: time.Now().UTC(), StorageKey: "photos/c.jpg",
	}
	if err := store.BeginPhoto(context.Background(), photo, UserOwner(user.ID)); err != nil {
		t.Fatal(err)
	}
	if err := store.RejectPhoto(context.Background(), photo.ID); err != nil {
		t.Fatalf("rejecting: %v", err)
	}
	stored, err := store.Photo(context.Background(), photo.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.ModerationState != "rejected" {
		t.Fatalf("moderation_state = %q, want rejected", stored.ModerationState)
	}
	if stored.IsPubliclyVisible() {
		t.Error("a rejected photograph is still publicly visible; the takedown bought nothing")
	}
	if stored.ApprovalReason != nil {
		t.Error("a rejected photograph still carries an approval reason")
	}
}

// ── The proximity dedupe ───────────────────────────────────────────────────────────────────────

func TestProximityDedupeTripsWithinTenMetres(t *testing.T) {
	store := testStore(t)
	_, deviceID := makeDevice(t, store)

	// San Francisco, where the corpus is. One degree of latitude is ~111.32 km, so 5 m is ~4.5e-5°.
	const lat, lon = 37.7601, -122.5050
	if _, err := store.AddTree(context.Background(), NewCommunityTree{
		ID: uuid.New(), Lat: lat, Lon: lon, Placement: "gps",
	}, DeviceOwner(deviceID)); err != nil {
		t.Fatal(err)
	}

	fiveMetresNorth := lat + 5.0/111_320.0
	near, err := store.TreesWithin(context.Background(), fiveMetresNorth, lon, ProximityDedupeRadiusM)
	if err != nil {
		t.Fatal(err)
	}
	if len(near) != 1 {
		t.Fatalf("a tree 5 m away produced %d candidates, want 1", len(near))
	}
	if near[0].DistanceM > ProximityDedupeRadiusM {
		t.Errorf("the candidate is %.1f m away, beyond the %.0f m radius", near[0].DistanceM, ProximityDedupeRadiusM)
	}

	// And 25 m away does not trip it, which is the half that proves the query is measuring
	// distance rather than returning everything.
	twentyFiveMetresNorth := lat + 25.0/111_320.0
	far, err := store.TreesWithin(context.Background(), twentyFiveMetresNorth, lon, ProximityDedupeRadiusM)
	if err != nil {
		t.Fatal(err)
	}
	if len(far) != 0 {
		t.Fatalf("a tree 25 m away produced %d candidates, want 0", len(far))
	}
}

// ── Session rotation ───────────────────────────────────────────────────────────────────────────

func TestRefreshTokenRotatesAndTheOldOneIsSpent(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-session")

	first := []byte("hash-one-------------------------")
	second := []byte("hash-two-------------------------")
	third := []byte("hash-three-----------------------")
	expiry := time.Now().UTC().Add(time.Hour)

	if _, err := store.CreateSession(context.Background(), user.ID, first, expiry); err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.RotateSession(context.Background(), first, second, expiry); err != nil {
		t.Fatalf("first rotation: %v", err)
	}
	// A replay of a rotated token is a *reuse*, not merely a spent token: it means two parties
	// hold it. The store revokes the whole family on the way out.
	_, _, err := store.RotateSession(context.Background(), first, third, expiry)
	if !errors.Is(err, ErrSessionReused) {
		t.Fatalf("replaying a rotated refresh token returned %v, want ErrSessionReused", err)
	}

	// The successor is dead too. Leaving it live would let whoever triggered the reuse keep a
	// 60-day session while the legitimate holder noticed nothing.
	fourth := []byte("hash-four------------------------")
	if _, _, err := store.RotateSession(context.Background(), second, fourth, expiry); !errors.Is(err, ErrSessionSpent) {
		t.Fatalf("after a detected reuse the successor rotated with %v, want ErrSessionSpent", err)
	}
}
