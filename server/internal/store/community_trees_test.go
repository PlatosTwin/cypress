package store

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ── Migration 007 against rows that already exist ──────────────────────────────────────────────
//
// Every other test in this package opens a database migrated to the head and then writes rows, so
// none of them ever runs 007's UPDATEs and INSERT … SELECTs over anything. This one stops at 006,
// writes the four kinds of tree production can hold, applies 007, and reads what it did.

func storeAtVersion(t *testing.T, name string, below int) *Store {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), testDatabaseURL(t, name))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	s := &Store{pool: pool, now: func() time.Time { return time.Now().UTC() }}
	if _, err := pool.Exec(context.Background(), schemaMigrationsDDL); err != nil {
		t.Fatal(err)
	}
	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	for _, file := range files {
		if file.Version >= below {
			break
		}
		if err := s.applyOne(context.Background(), file); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func migrationFileVersion(t *testing.T, version int) migrationFile {
	t.Helper()
	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	for _, file := range files {
		if file.Version == version {
			return file
		}
	}
	t.Fatalf("no migration %03d", version)
	return migrationFile{}
}

func TestMigration007BackfillsTheTreesThatAlreadyExist(t *testing.T) {
	s := storeAtVersion(t, "cypress_test_backfill_007", 7)
	ctx := context.Background()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := s.pool.Exec(ctx, sql, args...); err != nil {
			t.Fatalf("%s: %v", strings.Fields(sql)[0], err)
		}
	}

	accepter, decliner, device := uuid.New(), uuid.New(), uuid.New()
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'a', 'odbl-1.0', now())`, accepter)
	exec(`INSERT INTO users (id, apple_subject) VALUES ($1, 'd')`, decliner)
	exec(`INSERT INTO devices (id, device_uuid) VALUES ($1, $2)`, device, uuid.New())

	liveAt := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	accepted, declined, deviceOwned, orphan := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	insert := func(id uuid.UUID, user, dev *uuid.UUID) {
		exec(`INSERT INTO community_trees (id, lat, lon, placement, user_id, device_id, created_at, updated_at)
		      VALUES ($1, 37.76, -122.5, 'gps', $2, $3, $4, $5)`, id, user, dev, liveAt.Add(-time.Hour), liveAt)
	}
	insert(accepted, &accepter, nil)
	insert(declined, &decliner, nil)
	insert(deviceOwned, nil, &device)
	insert(orphan, nil, nil)
	addKey := uuid.New()
	exec(`INSERT INTO contributions (client_uuid, kind, tree_uuid, user_id, payload, occurred_at)
	      VALUES ($1, 'add_tree', $2, $3, '{}', $4)`, addKey, accepted, accepter, liveAt.Add(-time.Hour))

	if err := s.applyOne(ctx, migrationFileVersion(t, 7)); err != nil {
		t.Fatalf("007 over existing rows: %v", err)
	}

	type backfilled struct {
		PublishedAt  *time.Time
		AnonymizedAt *time.Time
		Root         int
		Added        int
		Published    int
		RootKey      *uuid.UUID
	}
	read := func(id uuid.UUID) backfilled {
		t.Helper()
		var b backfilled
		if err := s.pool.QueryRow(ctx, `
			SELECT t.published_at, t.anonymized_at,
			       (SELECT count(*) FROM community_tree_locations l WHERE l.id = t.id AND l.tree_id = t.id AND l.superseded_by IS NULL),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'added' AND e.id = t.id),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'published'),
			       (SELECT l.contribution_client_uuid FROM community_tree_locations l WHERE l.id = t.id)
			  FROM community_trees t WHERE t.id = $1
		`, id).Scan(&b.PublishedAt, &b.AnonymizedAt, &b.Root, &b.Added, &b.Published, &b.RootKey); err != nil {
			t.Fatal(err)
		}
		return b
	}

	for name, c := range map[string]struct {
		id         uuid.UUID
		published  bool
		anonymized bool
	}{
		"an accepting account's tree": {accepted, true, false},
		"a declining account's tree":  {declined, false, false},
		"a device's tree":             {deviceOwned, false, false},
		"a deleted account's orphan":  {orphan, false, true},
	} {
		b := read(c.id)
		if (b.PublishedAt != nil) != c.published {
			t.Errorf("%s: published_at = %v, want published %v", name, b.PublishedAt, c.published)
		}
		if c.published && !b.PublishedAt.Equal(liveAt) {
			t.Errorf("%s: published at %v, want its updated_at %v", name, b.PublishedAt, liveAt)
		}
		if (b.AnonymizedAt != nil) != c.anonymized {
			t.Errorf("%s: anonymized_at = %v, want anonymized %v", name, b.AnonymizedAt, c.anonymized)
		}
		if b.Root != 1 || b.Added != 1 {
			t.Errorf("%s: %d root locations and %d added events keyed on the tree id, want 1 and 1", name, b.Root, b.Added)
		}
		wantPublished := 0
		if c.published {
			wantPublished = 1
		}
		if b.Published != wantPublished {
			t.Errorf("%s: %d published events, want %d", name, b.Published, wantPublished)
		}
	}
	if key := read(accepted).RootKey; key == nil || *key != addKey {
		t.Errorf("the root location names item %v, want the add_tree that carried it (%s)", key, addKey)
	}
}

// TestTheTreeConstraintsRefuseWhatTheCodeMustNeverWrite red-proofs the two CHECKs 007 adds, each
// against the write it exists to refuse, with a control write that must pass.
func TestTheTreeConstraintsRefuseWhatTheCodeMustNeverWrite(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()
	user := makeUser(t, s, "ct-constraints")
	_, deviceID := makeDevice(t, s)
	accountTree, deviceTree := uuid.New(), uuid.New()
	for id, owner := range map[uuid.UUID]Owner{accountTree: UserOwner(user.ID), deviceTree: DeviceOwner(deviceID)} {
		if _, err := s.AddTree(ctx, NewCommunityTree{ID: id, Lat: 37.76, Lon: -122.5, Placement: "gps"}, owner, Actor{}); err != nil {
			t.Fatal(err)
		}
	}

	for _, c := range []struct {
		name, sql, constraint string
		id                    uuid.UUID
	}{
		{"a device's tree published", `UPDATE community_trees SET published_at = now() WHERE id = $1`,
			"community_trees_published_is_not_device_owned", deviceTree},
		{"an account's tree left ownerless without being anonymized", `UPDATE community_trees SET user_id = NULL WHERE id = $1`,
			"community_trees_owner", accountTree},
		{"an anonymized tree that still names its account", `UPDATE community_trees SET anonymized_at = now() WHERE id = $1`,
			"community_trees_owner", accountTree},
		{"a tree with two owners", `UPDATE community_trees SET device_id = (SELECT id FROM devices LIMIT 1) WHERE id = $1`,
			"community_trees_owner", accountTree},
	} {
		_, err := s.pool.Exec(ctx, c.sql, c.id)
		if err == nil || !strings.Contains(err.Error(), c.constraint) {
			t.Errorf("%s: err = %v, want a violation of %s", c.name, err, c.constraint)
		}
	}
	// The control: the anonymization the deletion door performs is storable.
	if _, err := s.pool.Exec(ctx, `
		UPDATE community_trees SET user_id = NULL, anonymized_at = now() WHERE id = $1
	`, accountTree); err != nil {
		t.Fatalf("the leaving door's anonymization was refused: %v", err)
	}
}

// TestDeletingAnAccountTheCodeForgotIsRefused is `community_trees_owner` doing the job 007's header
// gives it: a `DELETE FROM users` that reached a tree nobody anonymized first fails, rather than
// leaving a tree nobody can move, withdraw or erase.
func TestDeletingAnAccountTheCodeForgotIsRefused(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()
	user := makeUser(t, s, "ct-forgotten")
	if _, err := s.AddTree(ctx, NewCommunityTree{ID: uuid.New(), Lat: 37.76, Lon: -122.5, Placement: "gps"},
		UserOwner(user.ID), Actor{}); err != nil {
		t.Fatal(err)
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, user.ID)
	if err == nil || !strings.Contains(err.Error(), "community_trees_owner") {
		t.Fatalf("a bare DELETE FROM users over an account with a tree answered %v; want the owner CHECK", err)
	}
	// And the deletion that does the job first succeeds.
	if _, err := s.DeleteAccount(ctx, user.ID, LeaveRecords, nil, ""); err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}
}
