package store

import (
	"context"
	"os"
	"regexp"
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

	// Two accepters on either side of the tree's updated_at: the late one went live at its
	// acceptance, not before it (review of #187, F2).
	liveAt := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	acceptedLater := liveAt.Add(19 * 24 * time.Hour)
	accepter, lateAccepter, decliner, device := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	// L2: before this round any string was stored as a consent, so a pre-007 row can hold ''. It is
	// not an acceptance, and its tree must not be published.
	emptyVersion := uuid.New()
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'e', '', $2)`, emptyVersion, liveAt.Add(-48*time.Hour))
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'a', 'odbl-1.0', $2)`, accepter, liveAt.Add(-48*time.Hour))
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'l', 'odbl-1.0', $2)`, lateAccepter, acceptedLater)
	exec(`INSERT INTO users (id, apple_subject) VALUES ($1, 'd')`, decliner)
	exec(`INSERT INTO devices (id, device_uuid) VALUES ($1, $2)`, device, uuid.New())

	accepted, acceptedLate, declined, deviceOwned, orphan := uuid.New(), uuid.New(), uuid.New(), uuid.New(), uuid.New()
	nonVersion := uuid.New()
	insert := func(id uuid.UUID, user, dev *uuid.UUID) {
		exec(`INSERT INTO community_trees (id, lat, lon, placement, user_id, device_id, created_at, updated_at)
		      VALUES ($1, 37.76, -122.5, 'gps', $2, $3, $4, $5)`, id, user, dev, liveAt.Add(-time.Hour), liveAt)
	}
	insert(accepted, &accepter, nil)
	insert(acceptedLate, &lateAccepter, nil)
	insert(declined, &decliner, nil)
	insert(nonVersion, &emptyVersion, nil)
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
		EventAt      *time.Time
		License      *string
		// Decision 13: the root is the head at publication for every tree 007 publishes, so it is
		// public exactly when the tree is, the publication carries its position, and no `added`
		// event is public.
		RootPublic   bool
		EventLat     *float64
		PublicAdded  int
		PublicEvents int
	}
	read := func(id uuid.UUID) backfilled {
		t.Helper()
		var b backfilled
		if err := s.pool.QueryRow(ctx, `
			SELECT t.published_at, t.anonymized_at,
			       (SELECT count(*) FROM community_tree_locations l WHERE l.id = t.id AND l.tree_id = t.id AND l.superseded_by IS NULL),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'added' AND e.id = t.id),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'published'),
			       (SELECT l.contribution_client_uuid FROM community_tree_locations l WHERE l.id = t.id),
			       (SELECT max(e.occurred_at) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'published'),
			       (SELECT max(e.after ->> 'license_version') FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'published'),
			       (SELECT l.was_public FROM community_tree_locations l WHERE l.id = t.id),
			       (SELECT max((e.after ->> 'lat')::float8) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'published'),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.kind = 'added' AND e.in_public_history),
			       (SELECT count(*) FROM community_tree_events e WHERE e.tree_id = t.id AND e.in_public_history)
			  FROM community_trees t WHERE t.id = $1
		`, id).Scan(&b.PublishedAt, &b.AnonymizedAt, &b.Root, &b.Added, &b.Published, &b.RootKey,
			&b.EventAt, &b.License, &b.RootPublic, &b.EventLat, &b.PublicAdded, &b.PublicEvents); err != nil {
			t.Fatal(err)
		}
		return b
	}

	for name, c := range map[string]struct {
		id          uuid.UUID
		published   bool
		anonymized  bool
		publishedAt time.Time
	}{
		"an accepting account's tree":            {accepted, true, false, liveAt},
		"a tree whose account accepted after it": {acceptedLate, true, false, acceptedLater},
		"a declining account's tree":             {declined, false, false, time.Time{}},
		"an account holding license_version ''":  {nonVersion, false, false, time.Time{}},
		"a device's tree":                        {deviceOwned, false, false, time.Time{}},
		"a deleted account's orphan":             {orphan, false, true, time.Time{}},
	} {
		b := read(c.id)
		if (b.PublishedAt != nil) != c.published {
			t.Errorf("%s: published_at = %v, want published %v", name, b.PublishedAt, c.published)
		}
		if c.published && !b.PublishedAt.Equal(c.publishedAt) {
			t.Errorf("%s: published at %v, want %v — the later of its updated_at and its account's "+
				"acceptance", name, b.PublishedAt, c.publishedAt)
		}
		if c.published && (b.EventAt == nil || !b.EventAt.Equal(*b.PublishedAt) || b.License == nil || *b.License != "odbl-1.0") {
			t.Errorf("%s: the published event is at %v naming license %v; want it at published_at %v "+
				"naming odbl-1.0 (decision 10)", name, b.EventAt, b.License, b.PublishedAt)
		}
		if b.RootPublic != c.published || b.PublicAdded != 0 {
			t.Errorf("%s: root was_public=%v and %d public added events; want the root public exactly "+
				"when the tree is published, and no added event public (decision 13)", name, b.RootPublic, b.PublicAdded)
		}
		if c.published && (b.EventLat == nil || *b.EventLat != 37.76 || b.PublicEvents != 1) {
			t.Errorf("%s: the publication places the tree at %v with %d public events; want its root "+
				"(37.76) and the publication alone public", name, b.EventLat, b.PublicEvents)
		}
		if !c.published && b.PublicEvents != 0 {
			t.Errorf("%s: never published and %d events are public", name, b.PublicEvents)
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

// TestMigration007RunsOverEveryKindOfRowProductionHolds is 007 against a database shaped like the
// one it will meet: every contribution kind 005 admits, a live session, an account deleted before
// 007 (whose tree the foreign key already left ownerless), and a tree whose account accepted weeks
// after it was claimed. It checks the backfill against the published-at-acceptance record, and
// that the post-007 writers work on backfilled rows.
func TestMigration007RunsOverEveryKindOfRowProductionHolds(t *testing.T) {
	s := storeAtVersion(t, "cypress_test_realistic_007", 7)
	ctx := context.Background()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := s.pool.Exec(ctx, sql, args...); err != nil {
			t.Fatalf("%s: %v", strings.Join(strings.Fields(sql)[:3], " "), err)
		}
	}

	claimedAt := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	acceptedLater := time.Date(2026, 9, 20, 12, 0, 0, 0, time.UTC)
	early, late, decliner, deleted := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'early', 'odbl-1.0', $2)`, early, claimedAt.Add(-time.Hour))
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'late', 'odbl-1.0', $2)`, late, acceptedLater)
	exec(`INSERT INTO users (id, apple_subject) VALUES ($1, 'decliner')`, decliner)
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'gone', 'odbl-1.0', now())`, deleted)
	devA, devB := uuid.New(), uuid.New()
	exec(`INSERT INTO devices (id, device_uuid, user_id) VALUES ($1, $2, $3)`, devA, uuid.New(), early)
	exec(`INSERT INTO devices (id, device_uuid) VALUES ($1, $2)`, devB, uuid.New())
	exec(`INSERT INTO sessions (id, user_id, refresh_token_hash, issued_at, expires_at) VALUES ($1, $2, '\x01', now(), now() + interval '1 day')`, uuid.New(), early)

	trees := map[string]uuid.UUID{}
	insert := func(name string, user, dev *uuid.UUID, placement string) {
		id := uuid.New()
		trees[name] = id
		exec(`INSERT INTO community_trees (id, lat, lon, placement, land_context, user_id, device_id, created_at, updated_at)
		      VALUES ($1, 37.76, -122.5, $2, 'private_property', $3, $4, $5, $6)`, id, placement, user, dev, claimedAt.Add(-24*time.Hour), claimedAt)
	}
	insert("early accepter", &early, nil, "gps")
	insert("late accepter", &late, nil, "contributor_placed")
	insert("decliner", &decliner, nil, "gps")
	insert("device", nil, &devB, "gps")
	insert("orphan", &deleted, nil, "gps")
	exec(`DELETE FROM users WHERE id = $1`, deleted) // pre-007: ON DELETE SET NULL leaves both owners NULL

	kinds := []string{"visit", "observation", "measurement", "care_event", "favorite_toggle", "private_reminder",
		"add_tree", "species_claim", "species_correction", "wrong_species_report", "never_existed_report",
		"species_review_dismissal", "record_review_dismissal", "photo_vote", "photo_withdrawal", "hazard_redirect",
		"measurement_withdrawal", "data_dispute", "data_dispute_withdrawal"}
	for _, kind := range kinds {
		exec(`INSERT INTO contributions (client_uuid, kind, tree_uuid, device_id, payload, occurred_at) VALUES ($1, $2, $3, $4, '{}', now())`,
			uuid.New(), kind, trees["device"], devB)
	}

	if err := s.applyOne(ctx, migrationFileVersion(t, 7)); err != nil {
		t.Fatalf("007 over realistic rows: %v", err)
	}

	for name, want := range map[string]struct{ published, anonymized bool }{
		"early accepter": {true, false}, "late accepter": {true, false}, "decliner": {false, false},
		"device": {false, false}, "orphan": {false, true},
	} {
		var published, anonymized bool
		var heads, added int
		if err := s.pool.QueryRow(ctx, `
			SELECT published_at IS NOT NULL, anonymized_at IS NOT NULL,
			       (SELECT count(*) FROM community_tree_locations WHERE tree_id = $1 AND superseded_by IS NULL),
			       (SELECT count(*) FROM community_tree_events WHERE tree_id = $1 AND kind = 'added')
			  FROM community_trees WHERE id = $1`, trees[name]).Scan(&published, &anonymized, &heads, &added); err != nil {
			t.Fatal(err)
		}
		if published != want.published || anonymized != want.anonymized || heads != 1 || added != 1 {
			t.Errorf("%s: published=%v anonymized=%v heads=%d added=%d; want %v, %v, 1, 1",
				name, published, anonymized, heads, added, want.published, want.anonymized)
		}
	}

	// Decision 10's record: every published tree has a published event at its published_at naming
	// the version accepted, and no publication predates its account's acceptance.
	var unrecorded, early007 int
	if err := s.pool.QueryRow(ctx, `
		SELECT
		  (SELECT count(*) FROM community_trees t
		    WHERE t.published_at IS NOT NULL
		      AND NOT EXISTS (SELECT 1 FROM community_tree_events e
		                       WHERE e.tree_id = t.id AND e.kind = 'published' AND e.occurred_at = t.published_at
		                         AND e.after ->> 'license_version' IS NOT NULL)),
		  (SELECT count(*) FROM community_trees t JOIN users u ON u.id = t.user_id
		    WHERE t.published_at < u.license_accepted_at)
	`).Scan(&unrecorded, &early007); err != nil {
		t.Fatal(err)
	}
	if unrecorded != 0 || early007 != 0 {
		t.Errorf("after the backfill %d published trees have no licensed published event at their "+
			"published_at, and %d were published before their account accepted", unrecorded, early007)
	}

	// The post-007 writers work on backfilled rows.
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if err := applyLocationCorrection(ctx, tx, LocationCorrection{ID: uuid.New(), TreeID: trees["early accepter"],
		Lat: 37.7601, Lon: -122.5, Placement: "gps"}, newTreeAct{Owner: UserOwner(early), OccurredAt: time.Now()}, time.Now()); err != nil {
		t.Errorf("moving a backfilled tree: %v", err)
	}
}

// TestAnAcceptanceCannotSlipPastAnOpenInsert drives the interleaving by hand with the production
// functions: a signed-in insert reads the account's answer ("declined") and stays open; an
// acceptance arrives on another connection. Without a lock on the users row the acceptance
// commits first, its publish sweep cannot see the uncommitted tree, and the insert then commits a
// private tree under an account that has accepted — until some later acceptance. With FOR SHARE
// the acceptance waits for the insert, and its sweep publishes the tree.
//
// The test waits until the acceptance has either returned or is observed waiting on a lock in
// pg_stat_activity before it commits the insert, so the outcome does not depend on scheduling.
func TestAnAcceptanceCannotSlipPastAnOpenInsert(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()
	user := makeUser(t, s, "ct-acceptance-race")
	if err := s.RecordLicenseConsent(ctx, user.ID, nil, nil); err != nil {
		t.Fatal(err)
	}

	insert, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer insert.Rollback(ctx)
	tree := uuid.New()
	now := time.Now().UTC()
	if _, err := insertCommunityTree(ctx, insert, NewCommunityTree{ID: tree, Lat: 37.76, Lon: -122.5, Placement: "gps"},
		newTreeAct{Owner: UserOwner(user.ID), OccurredAt: now}, now); err != nil {
		t.Fatal(err)
	}

	version := "odbl-1.0"
	done := make(chan error, 1)
	go func() { done <- s.RecordLicenseConsent(ctx, user.ID, &version, nil) }()

	var acceptErr error
	returned, waited := false, false
	for i := 0; i < 600 && !returned && !waited; i++ {
		select {
		case acceptErr = <-done:
			returned = true
		case <-time.After(100 * time.Millisecond):
			var waiting int
			if err := s.pool.QueryRow(ctx, `
				SELECT count(*) FROM pg_stat_activity
				 WHERE datname = current_database() AND wait_event_type = 'Lock'
				   AND query LIKE '%UPDATE users SET license_version%'
			`).Scan(&waiting); err != nil {
				t.Fatal(err)
			}
			waited = waiting > 0
		}
	}
	if !returned && !waited {
		t.Fatal("after 60 s the acceptance had neither returned nor been seen waiting on a lock")
	}
	if err := insert.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if !returned {
		acceptErr = <-done
	}
	if acceptErr != nil {
		t.Fatal(acceptErr)
	}

	var published bool
	var events int
	if err := s.pool.QueryRow(ctx, `
		SELECT published_at IS NOT NULL,
		       (SELECT count(*) FROM community_tree_events WHERE tree_id = $1 AND kind = 'published'
		           AND after ->> 'license_version' = 'odbl-1.0')
		  FROM community_trees WHERE id = $1`, tree).Scan(&published, &events); err != nil {
		t.Fatal(err)
	}
	if !published || events != 1 {
		t.Fatalf("the account accepted and its tree is published=%v with %d licensed published events "+
			"(the acceptance returned before the insert committed: %v) — the acceptance's sweep ran "+
			"while the insert was open, and the insert had read the old decline", published, events, returned)
	}
	if returned {
		t.Fatal("the acceptance committed while an insert that read the account's answer was still open")
	}
}

// TestTheTileIndexesServeTheirQueries pins the contract 007 offers S2's tile (the #190 review's F5):
// each arm of the tile has a partial index whose predicate the arm's own WHERE implies, and the
// planner uses it for a **generic** plan — the one pgx's statement cache can settle on, and the one
// the review measured degrading to sequential scans. Sequential scans are disabled so an empty
// test table cannot make the choice for the planner; what is asserted is that the index is usable
// for the query shape, which is the half of the contract that lives in this migration.
func TestTheTileIndexesServeTheirQueries(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SET LOCAL enable_seqscan = off`); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct{ arm, index, query string }{
		{"the position arm (live and soft-removed once-public trees)", "idx_community_trees_public_position", `
			SELECT id FROM community_trees
			 WHERE published_at IS NOT NULL
			   AND lat BETWEEN $1 AND $2 AND lon BETWEEN $3 AND $4`},
		{"the chain arm (positions the public saw)", "idx_community_tree_locations_public_position", `
			SELECT DISTINCT tree_id FROM community_tree_locations
			 WHERE was_public
			   AND lat BETWEEN $1 AND $2 AND lon BETWEEN $3 AND $4`},
		{"the removal list (once-public tombstones)", "idx_withdrawn_community_trees_public", `
			SELECT id FROM withdrawn_community_trees
			 WHERE was_public AND (withdrawn_at, id) > ($1, $2)
			 ORDER BY withdrawn_at, id LIMIT $3`},
	} {
		// The simple protocol, straight to the connection: EXPLAIN (GENERIC_PLAN) takes the query's
		// $n placeholders unbound, which pgx's extended protocol would try to bind.
		results, err := tx.Conn().PgConn().Exec(ctx, `EXPLAIN (GENERIC_PLAN) `+c.query).ReadAll()
		if err != nil {
			t.Fatalf("%s: %v", c.arm, err)
		}
		var plan []string
		for _, result := range results {
			for _, row := range result.Rows {
				plan = append(plan, string(row[0]))
			}
		}
		if !strings.Contains(strings.Join(plan, "\n"), c.index) {
			t.Errorf("%s: the generic plan does not use %s:\n%s", c.arm, c.index, strings.Join(plan, "\n"))
		}
	}
}

// TestTheBackfillsAcceptedVersionIsOneTheLivePathAccepts ties 007's backfill to the live path. The
// backfill names the versions it counts as an acceptance as SQL literals, and the live path decides
// through `accountLicense` (S2's L2 fix adds `knownLicenseVersions` there). The two must agree: a
// tree the backfill publishes for a version must be one a live acceptance of that version would
// publish, or a tree published by the migration would be one the service itself would refuse to.
//
// It reads the literals out of the migration file, calibrated against the one it must find, and
// drives each through the production writers.
func TestTheBackfillsAcceptedVersionIsOneTheLivePathAccepts(t *testing.T) {
	raw, err := os.ReadFile("../../migrations/007_community_trees.sql")
	if err != nil {
		t.Fatal(err)
	}
	literals := regexp.MustCompile(`(?m)^\s+AND u\.license_version = '([^']*)';`).FindAllStringSubmatch(string(raw), -1)
	if len(literals) != 1 || literals[0][1] != "odbl-1.0" {
		t.Fatalf("calibration: 007's backfill names %v as accepted versions; this test expects the one "+
			"it was written against, 'odbl-1.0' — read the migration before changing either", literals)
	}

	s := testStore(t)
	ctx := context.Background()
	for _, literal := range literals {
		version := literal[1]
		user := makeUser(t, s, "backfill-agrees-"+version)
		if err := s.RecordLicenseConsent(ctx, user.ID, &version, nil); err != nil {
			t.Fatal(err)
		}
		tree := uuid.New()
		if _, err := s.AddTree(ctx, NewCommunityTree{ID: tree, Lat: 37.76, Lon: -122.5, Placement: "gps"}, UserOwner(user.ID), Actor{}); err != nil {
			t.Fatal(err)
		}
		var published bool
		if err := s.pool.QueryRow(ctx, `SELECT published_at IS NOT NULL FROM community_trees WHERE id = $1`, tree).Scan(&published); err != nil {
			t.Fatal(err)
		}
		if !published {
			t.Errorf("007's backfill publishes for license_version %q, and a live acceptance of it "+
				"does not publish: the two paths disagree about what an acceptance is", version)
		}
	}
}

// TestAPhotosCaptureDateIsHeldToItsDay is 007's `photos_captured_on_is_the_captured_day`: the
// handler's one-day rule restated where no writer can skip it, with the boundary rows as controls.
func TestAPhotosCaptureDateIsHeldToItsDay(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()
	_, deviceID := makeDevice(t, s)
	insert := func(capturedOn string) error {
		id := uuid.New()
		_, err := s.pool.Exec(ctx, `
			INSERT INTO photos (id, tree_uuid, device_id, shot_type, moderation_state, captured_at,
			                    storage_key, created_at, updated_at, captured_on)
			VALUES ($1, $2, $3, 'full_tree', 'pending', '2026-09-28T23:30:00Z', $5, now(), now(), $4::date)
		`, id, uuid.New(), deviceID, capturedOn, "photos/"+id.String()+".jpg")
		return err
	}
	for _, day := range []string{"2026-09-27", "2026-09-28", "2026-09-29"} {
		if err := insert(day); err != nil {
			t.Fatalf("control: captured_on %s, within a day of the UTC date, was refused: %v", day, err)
		}
	}
	for _, day := range []string{"2026-09-26", "2026-09-30"} {
		err := insert(day)
		if err == nil || !strings.Contains(err.Error(), "photos_captured_on_is_the_captured_day") {
			t.Errorf("captured_on %s, two days from the UTC date: err = %v, want the CHECK", day, err)
		}
	}
}
