// Package store is the Postgres layer: the schema, and every query the service runs.
//
// There is one implementation and it is the real one. No in-memory double stands behind this
// interface, because a double is where a guard goes green while the defect it names is present:
// the three semantics this ticket turns on — claim idempotency and its #174 guard, the tombstone
// that stops a deleted account resurrecting, and dedupe on `client_uuid` — are all *SQL*
// behaviours, and a Go map re-implementing them proves only that the Go map agrees with itself.
// `store_test.go` runs against a real Postgres or it does not run.
package store

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed schema.sql
var schemaSQL string

// SchemaVersion is this service's own counter. It is not either of the app's two schema-version
// spaces (see schema.sql's header) and it advances independently of both.
const SchemaVersion = 1

// Store holds the pool.
type Store struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

// Open connects and applies the schema.
func Open(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("connecting to Postgres: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pinging Postgres: %w", err)
	}
	store := &Store{pool: pool, now: func() time.Time { return time.Now().UTC() }}
	if err := store.Migrate(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return store, nil
}

// WithClock replaces the clock. Test seam.
func (s *Store) WithClock(now func() time.Time) *Store {
	return &Store{pool: s.pool, now: now}
}

// Now is the store's clock, exported so handlers stamp the same time the rows do.
func (s *Store) Now() time.Time { return s.now() }

// Close releases the pool.
func (s *Store) Close() { s.pool.Close() }

// Migrate applies schema.sql. Every statement is `IF NOT EXISTS`, so this is safe on every boot —
// which is what a single machine with no separate migration step needs.
func (s *Store) Migrate(ctx context.Context) error {
	if _, err := s.pool.Exec(ctx, schemaSQL); err != nil {
		return fmt.Errorf("applying schema: %w", err)
	}
	var version int
	err := s.pool.QueryRow(ctx, `SELECT coalesce(max(version), 0) FROM schema_meta`).Scan(&version)
	if err != nil {
		return fmt.Errorf("reading schema version: %w", err)
	}
	if version < SchemaVersion {
		_, err = s.pool.Exec(ctx, `INSERT INTO schema_meta (version) VALUES ($1)`, SchemaVersion)
		if err != nil {
			return fmt.Errorf("recording schema version: %w", err)
		}
	}
	return nil
}

// ErrNotFound is returned by every read that found nothing.
var ErrNotFound = errors.New("not found")

// IsUniqueViolation reports whether err is a Postgres unique-constraint failure.
func IsUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// Tx runs fn in a transaction, rolling back on error.
func (s *Store) Tx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// Pool exposes the pool for queries that do not need a transaction.
func (s *Store) Pool() *pgxpool.Pool { return s.pool }
