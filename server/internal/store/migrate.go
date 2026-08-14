package store

import (
	"context"
	"fmt"
	"io/fs"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/PlatosTwin/cypress/server/migrations"
	"github.com/jackc/pgx/v5"
)

// The migration runner.
//
// ── Why this exists at all, given nothing is deployed ──────────────────────────────────────────
//
// The schema was applied with `CREATE TABLE IF NOT EXISTS` on every boot, which is not a migration
// mechanism — it is a mechanism for *creating* a schema and silently declining to *change* one. The
// round that added `community_trees.address` and `land_context` made that concrete: against a
// database created at the previous head, boot succeeded and the first `POST /trees` failed at
// runtime on `column "land_context" does not exist`. Nothing was deployed, so nothing broke; the
// point is that the **next** schema change is the one that bites, and the first deploy is the last
// moment this is free.
//
// ── What it refuses to do ──────────────────────────────────────────────────────────────────────
//
// Three refusals, all at boot, all before a single statement runs. Each is a state where continuing
// would leave the database in a shape nobody can reason about, and where the honest answer is a
// service that will not start rather than one that starts and is subtly wrong:
//
//   - **A gap in the files** (001, 003 with no 002). Applying 003 would produce a database that no
//     other database matches, and the missing file is more likely to be an un-added file than a
//     deliberate hole.
//   - **An applied version this build does not have** (the database is ahead of the binary). That
//     is a rollback onto a newer schema, and the old binary's queries are not written for it.
//   - **A gap in what has been applied** (001 and 003 recorded, 002 not). Only reachable by editing
//     the tracking table by hand, and it means the recorded history is not a history.
//
// No dependency: one embedded FS, `pgx`, and about a hundred lines. R72 priced the stack at two
// direct dependencies and a migration library would have been a third for something this size.

// migrationFile is one numbered file.
type migrationFile struct {
	Version int
	Name    string
	SQL     string
}

// migrationFilename is `NNN_name.sql`. The number is fixed-width so the files sort in the order
// they run when a person lists the directory.
var migrationFilename = regexp.MustCompile(`^(\d{3})_([a-z0-9_]+)\.sql$`)

// loadMigrations reads and validates the embedded files.
func loadMigrations() ([]migrationFile, error) {
	entries, err := fs.ReadDir(migrations.Files, ".")
	if err != nil {
		return nil, fmt.Errorf("reading the embedded migrations: %w", err)
	}

	var loaded []migrationFile
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		match := migrationFilename.FindStringSubmatch(entry.Name())
		if match == nil {
			// Loud rather than skipped: a file named `002-initial.sql` or `2_initial.sql` that is
			// silently ignored is a migration that does not run, on a mechanism whose whole job is
			// that migrations run.
			return nil, fmt.Errorf(
				"migrations/%s is not named NNN_name.sql; a file the runner cannot parse is a "+
					"migration that would silently never run", entry.Name())
		}
		version, err := strconv.Atoi(match[1])
		if err != nil {
			return nil, fmt.Errorf("migrations/%s: %w", entry.Name(), err)
		}
		if version < 1 {
			return nil, fmt.Errorf("migrations/%s: versions start at 001", entry.Name())
		}
		body, err := migrations.Files.ReadFile(entry.Name())
		if err != nil {
			return nil, fmt.Errorf("reading migrations/%s: %w", entry.Name(), err)
		}
		if strings.TrimSpace(string(body)) == "" {
			return nil, fmt.Errorf("migrations/%s is empty", entry.Name())
		}
		loaded = append(loaded, migrationFile{Version: version, Name: match[2], SQL: string(body)})
	}

	sort.Slice(loaded, func(i, j int) bool { return loaded[i].Version < loaded[j].Version })

	if len(loaded) == 0 {
		return nil, fmt.Errorf("no migrations are embedded; the schema would be created by nothing")
	}
	for index, file := range loaded {
		want := index + 1
		if file.Version != want {
			return nil, fmt.Errorf(
				"the migrations are not contiguous: expected %03d and found %03d (%s). A gap is "+
					"almost always an un-added file, and applying past one produces a database no "+
					"other database matches", want, file.Version, file.Name)
		}
	}
	return loaded, nil
}

// schemaMigrationsDDL creates the tracking table.
//
// The one statement in the system that is still `IF NOT EXISTS`, necessarily: it is what records
// whether anything else has run.
const schemaMigrationsDDL = `
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    INTEGER PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`

// Migrate applies every pending migration, in order, each inside its own transaction.
//
// Per-migration transactions rather than one for the lot: Postgres makes DDL transactional, so a
// migration that fails half way leaves no trace of itself, and the ones before it stay applied and
// recorded. The alternative — one transaction over all of them — would roll back work that
// succeeded and is unrelated to the failure.
//
// The `schema_migrations` row is written inside the same transaction as the statements it records,
// so "applied" and "recorded" cannot come apart.
func (s *Store) Migrate(ctx context.Context) error {
	files, err := loadMigrations()
	if err != nil {
		return err
	}

	if _, err := s.pool.Exec(ctx, schemaMigrationsDDL); err != nil {
		return fmt.Errorf("creating schema_migrations: %w", err)
	}

	applied, err := s.appliedVersions(ctx)
	if err != nil {
		return err
	}

	known := map[int]bool{}
	for _, file := range files {
		known[file.Version] = true
	}
	for _, version := range applied {
		if !known[version] {
			return fmt.Errorf(
				"the database has migration %03d applied and this build does not have it. That is "+
					"a rollback onto a newer schema, and this binary's queries are not written for "+
					"it — refusing to start rather than running them", version)
		}
	}
	for index, version := range applied {
		if version != index+1 {
			return fmt.Errorf(
				"schema_migrations records %v, which has a gap. The recorded history is not a "+
					"history, so what the database actually contains cannot be inferred", applied)
		}
	}

	for _, file := range files {
		if len(applied) >= file.Version {
			continue
		}
		if err := s.applyOne(ctx, file); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) appliedVersions(ctx context.Context) ([]int, error) {
	rows, err := s.pool.Query(ctx, `SELECT version FROM schema_migrations ORDER BY version ASC`)
	if err != nil {
		return nil, fmt.Errorf("reading schema_migrations: %w", err)
	}
	defer rows.Close()
	var applied []int
	for rows.Next() {
		var version int
		if err := rows.Scan(&version); err != nil {
			return nil, err
		}
		applied = append(applied, version)
	}
	return applied, rows.Err()
}

func (s *Store) applyOne(ctx context.Context, file migrationFile) error {
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, file.SQL); err != nil {
			return fmt.Errorf("applying %03d_%s.sql: %w", file.Version, file.Name, err)
		}
		_, err := tx.Exec(ctx,
			`INSERT INTO schema_migrations (version, applied_at) VALUES ($1, $2)`,
			file.Version, s.now())
		return err
	})
	if err != nil {
		return err
	}
	return nil
}

// SchemaVersion reports the highest applied migration, for the boot log.
func (s *Store) SchemaVersion(ctx context.Context) (int, error) {
	var version int
	err := s.pool.QueryRow(ctx,
		`SELECT coalesce(max(version), 0) FROM schema_migrations`).Scan(&version)
	return version, err
}
