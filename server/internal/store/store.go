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
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store holds the pool.
type Store struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

// Open connects and brings the schema up to date.
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

// ErrNotFound is returned by every read that found nothing.
var ErrNotFound = errors.New("not found")

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
