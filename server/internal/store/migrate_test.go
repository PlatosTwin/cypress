package store

import (
	"context"
	"strings"
	"testing"
)

// The migration runner. These run against a real Postgres for the same reason everything else in
// this package does: what is being asserted is what the database ends up containing.

// TestAFreshDatabaseGetsEveryMigration is the ordinary path.
func TestAFreshDatabaseGetsEveryMigration(t *testing.T) {
	store := testStore(t) // Open() migrates.

	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	applied, err := store.appliedVersions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(applied) != len(files) {
		t.Fatalf("%d migrations applied, %d embedded", len(applied), len(files))
	}
	for index, file := range files {
		if applied[index] != file.Version {
			t.Fatalf("applied[%d] = %d, want %d", index, applied[index], file.Version)
		}
	}

	version, err := store.SchemaVersion(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if version != files[len(files)-1].Version {
		t.Fatalf("SchemaVersion = %d, want %d", version, files[len(files)-1].Version)
	}

	// And the schema is actually there — a tracking table full of rows over an empty database is
	// the failure this whole mechanism would be worst at noticing.
	var exists bool
	err = store.pool.QueryRow(context.Background(), `
		SELECT EXISTS (SELECT 1 FROM information_schema.columns
		                WHERE table_name = 'community_trees' AND column_name = 'land_context')
	`).Scan(&exists)
	if err != nil {
		t.Fatal(err)
	}
	if !exists {
		t.Fatal("community_trees.land_context is missing; the migrations recorded work they did not do")
	}
}

// TestMigrateIsIdempotent pins the property every boot depends on: the machine auto-stops and
// starts several times a day, and each start runs this.
func TestMigrateIsIdempotent(t *testing.T) {
	store := testStore(t)

	before, err := store.appliedVersions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for attempt := 1; attempt <= 3; attempt++ {
		if err := store.Migrate(context.Background()); err != nil {
			t.Fatalf("boot %d re-ran a migration: %v", attempt+1, err)
		}
	}
	after, err := store.appliedVersions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != len(before) {
		t.Fatalf("after three more boots %d migrations are recorded, was %d", len(after), len(before))
	}
}

// TestOnlyPendingMigrationsRun is "a database at version N applies only N+1 onwards".
//
// Simulated by deleting the last recorded version and re-running: the runner must attempt exactly
// that file and nothing before it. If it re-ran from 001 the `CREATE TABLE` would fail, which is
// what makes this observable rather than a claim about intent.
func TestOnlyPendingMigrationsRun(t *testing.T) {
	store := testStore(t)
	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	last := files[len(files)-1]

	// Pretend the newest migration never ran. Its objects are still there, so re-applying it must
	// be what fails — and re-applying 001 would fail too, which is the point: whichever it tries,
	// it tells us which one it tried.
	_, err = store.pool.Exec(context.Background(),
		`DELETE FROM schema_migrations WHERE version = $1`, last.Version)
	if err != nil {
		t.Fatal(err)
	}

	err = store.Migrate(context.Background())
	if err == nil {
		t.Fatalf("re-applying %03d against a database that already has its objects succeeded; "+
			"either it was skipped (so pending detection is broken) or the file is not creating "+
			"what it claims", last.Version)
	}
	if !strings.Contains(err.Error(), last.Name) {
		t.Fatalf("the failure names %q; it should name the migration it actually attempted (%03d_%s): %v",
			err.Error(), last.Version, last.Name, err)
	}
	// And it must not have reached for anything earlier.
	for _, earlier := range files[:len(files)-1] {
		if strings.Contains(err.Error(), earlier.Name) {
			t.Errorf("the runner attempted %03d_%s, which was already applied", earlier.Version, earlier.Name)
		}
	}
}

// TestABuildOlderThanTheDatabaseRefusesToBoot is the rollback case.
func TestABuildOlderThanTheDatabaseRefusesToBoot(t *testing.T) {
	store := testStore(t)
	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	ahead := files[len(files)-1].Version + 1

	_, err = store.pool.Exec(context.Background(),
		`INSERT INTO schema_migrations (version) VALUES ($1)`, ahead)
	if err != nil {
		t.Fatal(err)
	}

	err = store.Migrate(context.Background())
	if err == nil {
		t.Fatal("a build whose database has a migration it does not know about booted anyway; " +
			"that is a rollback onto a newer schema and this binary's queries are not written for it")
	}
	if !strings.Contains(err.Error(), "rollback onto a newer schema") {
		t.Errorf("refused, but the message does not explain why: %v", err)
	}
}

// TestAGapInTheRecordedHistoryRefusesToBoot is the hand-edited tracking table.
func TestAGapInTheRecordedHistoryRefusesToBoot(t *testing.T) {
	store := testStore(t)
	files, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	if len(files) < 1 {
		t.Skip("needs at least one migration")
	}

	// Record a version far ahead *and* remove 001, so what is recorded has a hole in it. The
	// "ahead" check would also fire here, so the gap is made the only explanation by using a
	// version the runner does know about — which needs two files. With one, assert the shape the
	// runner will have when there are more.
	_, err = store.pool.Exec(context.Background(), `DELETE FROM schema_migrations WHERE version = 1`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.pool.Exec(context.Background(),
		`INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING`, 2)
	if err != nil {
		t.Fatal(err)
	}

	err = store.Migrate(context.Background())
	if err == nil {
		t.Fatal("a tracking table with a hole in it booted; what the database contains cannot be " +
			"inferred from a history that is not a history")
	}
	// Either refusal is correct here — version 2 is both unknown to a one-file build and a gap.
	// What must not happen is a silent boot.
	if !strings.Contains(err.Error(), "gap") && !strings.Contains(err.Error(), "rollback onto a newer schema") {
		t.Errorf("refused, but for an unexpected reason: %v", err)
	}
}

// ── The file-level validation, which needs no database ─────────────────────────────────────────

func TestEmbeddedMigrationsAreWellFormed(t *testing.T) {
	files, err := loadMigrations()
	if err != nil {
		t.Fatalf("the embedded migrations do not load: %v", err)
	}
	if len(files) == 0 {
		t.Fatal("no migrations are embedded")
	}
	for index, file := range files {
		if file.Version != index+1 {
			t.Errorf("migration %d is numbered %03d; they must be contiguous from 001", index, file.Version)
		}
		if strings.TrimSpace(file.SQL) == "" {
			t.Errorf("%03d_%s.sql is empty", file.Version, file.Name)
		}
	}
}

// TestTheFilenameRuleIsCalibrated runs the parser against names whose answers are known.
//
// A regex that matched everything would let a mis-named file be treated as a migration; one that
// matched nothing would make `loadMigrations` return an empty set, and the "no migrations are
// embedded" guard is what stops that becoming a silently empty schema.
func TestTheFilenameRuleIsCalibrated(t *testing.T) {
	accepted := map[string]int{
		"001_initial.sql":          1,
		"002_add_land_context.sql": 2,
		"017_photos_backfill.sql":  17,
	}
	for name, version := range accepted {
		match := migrationFilename.FindStringSubmatch(name)
		if match == nil {
			t.Errorf("%s was rejected and should be accepted", name)
			continue
		}
		if match[1] != pad(version) {
			t.Errorf("%s parsed its version as %q", name, match[1])
		}
	}
	for _, name := range []string{
		"1_initial.sql",       // not fixed-width, so it would sort wrongly in a directory listing
		"001-initial.sql",     // hyphen
		"001_Initial.sql",     // capital
		"001_initial.SQL",     // extension case
		"initial.sql",         // no version
		"migrations.go",       // this package's own source
		"001_initial.sql.bak", // an editor's leftover
	} {
		if migrationFilename.MatchString(name) {
			t.Errorf("%s was accepted and should be rejected", name)
		}
	}
}

func pad(version int) string {
	switch {
	case version < 10:
		return "00" + itoa(version)
	case version < 100:
		return "0" + itoa(version)
	default:
		return itoa(version)
	}
}

func itoa(value int) string {
	if value == 0 {
		return "0"
	}
	var digits []byte
	for value > 0 {
		digits = append([]byte{byte('0' + value%10)}, digits...)
		value /= 10
	}
	return string(digits)
}
