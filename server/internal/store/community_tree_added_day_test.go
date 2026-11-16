package store

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── The "added" day (the owner's decision of 2026-11-15, migration 008) ─────────────────────────

func mustTime(t *testing.T, text string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, text)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func mustDay(t *testing.T, text string) *time.Time {
	t.Helper()
	parsed, err := time.Parse(time.DateOnly, text)
	if err != nil {
		t.Fatal(err)
	}
	return &parsed
}

// TestTheAddedDayRule is `addedDay` on its own, so it runs without a database: the phone's stated
// day within one day of the instant, the instant's UTC date otherwise, never later than the
// receipt, and the receipt day for a clock that cannot be believed.
func TestTheAddedDayRule(t *testing.T) {
	for _, c := range []struct {
		name               string
		stated             string // "" is none
		occurred, received string
		want               string
	}{
		{"no day: the instant's UTC date (a Pacific evening is the next day)", "", "2026-10-15T06:30:00Z", "2026-10-15T06:30:05Z", "2026-10-15"},
		{"west of UTC: the stated day, one before", "2026-10-14", "2026-10-15T06:30:00Z", "2026-10-15T06:30:05Z", "2026-10-14"},
		{"east of UTC: the stated day, one after the receipt's UTC date", "2026-10-15", "2026-10-14T22:00:00Z", "2026-10-14T22:00:05Z", "2026-10-15"},
		{"received months later: the phone's day", "2026-07-31", "2026-08-01T03:00:00Z", "2026-11-10T12:00:00Z", "2026-07-31"},
		{"two days off the instant: ignored", "2026-10-17", "2026-10-15T06:30:00Z", "2026-10-15T06:30:05Z", "2026-10-15"},
		{"two days before the instant: ignored", "2026-10-13", "2026-10-15T06:30:00Z", "2026-10-15T06:30:05Z", "2026-10-15"},
		{"an instant after the receipt: the receipt's day", "", "2026-12-25T12:00:00Z", "2026-10-15T12:00:00Z", "2026-10-15"},
		{"a stated day near the receipt beside a fast clock: believed", "2026-10-16", "2026-10-16T00:05:00Z", "2026-10-15T23:58:00Z", "2026-10-16"},
		{"a far-past instant: the receipt's day", "", "2001-01-01T12:00:00Z", "2026-10-15T12:00:00Z", "2026-10-15"},
		{"a far-past day with it: the receipt's day", "2001-01-01", "2001-01-01T12:00:00Z", "2026-10-15T12:00:00Z", "2026-10-15"},
		{"the first day is believed", "", "2026-07-21T00:00:00Z", "2026-10-15T12:00:00Z", "2026-07-21"},
		{"a stated first day, one before the instant's: believed", "2026-07-21", "2026-07-22T03:00:00Z", "2026-10-15T12:00:00Z", "2026-07-21"},
		{"the day before the first: the receipt's day", "", "2026-07-20T23:59:59Z", "2026-10-15T12:00:00Z", "2026-10-15"},
	} {
		t.Run(c.name, func(t *testing.T) {
			var stated *time.Time
			if c.stated != "" {
				stated = mustDay(t, c.stated)
			}
			got := addedDay(stated, mustTime(t, c.occurred), mustTime(t, c.received))
			if got.Format(time.DateOnly) != c.want || !got.Equal(*mustDay(t, c.want)) {
				t.Fatalf("addedDay(%q, %s, %s) = %s, want %s (midnight UTC)", c.stated, c.occurred, c.received,
					got.Format(time.RFC3339), c.want)
			}
		})
	}
}

// TestMigration008BackfillsTheAddedDay stops at 007, writes trees the way the code at 007 writes
// them (a tree row, its root location and its `added` event, each with the phone's instant, and
// `created_at` the receipt), applies 008, and reads what it did. It also checks the column is now
// required, that the receipt bound is a CHECK, and that 001's position index is gone.
func TestMigration008BackfillsTheAddedDay(t *testing.T) {
	s := storeAtVersion(t, "cypress_test_backfill_008", 8)
	ctx := context.Background()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := s.pool.Exec(ctx, sql, args...); err != nil {
			t.Fatalf("%s: %v", strings.Fields(sql)[0], err)
		}
	}
	user := uuid.New()
	exec(`INSERT INTO users (id, apple_subject, license_version, license_accepted_at) VALUES ($1, 'a', 'odbl-1.0', $2)`,
		user, mustTime(t, "2026-08-01T00:00:00Z"))

	// insert writes a tree as 007's code does. A zero `event` or `root` leaves that row out, for the
	// two fallbacks.
	insert := func(event, root, created, published string) uuid.UUID {
		id := uuid.New()
		var publishedAt *time.Time
		if published != "" {
			at := mustTime(t, published)
			publishedAt = &at
		}
		exec(`INSERT INTO community_trees (id, lat, lon, placement, user_id, published_at, created_at, updated_at)
		      VALUES ($1, 37.76, -122.5, 'gps', $2, $3, $4, $4)`, id, user, publishedAt, mustTime(t, created))
		if root != "" {
			exec(`INSERT INTO community_tree_locations (id, tree_id, lat, lon, placement, actor_user_id,
			                                            occurred_at, recorded_at, was_public)
			      VALUES ($1, $1, 37.76, -122.5, 'gps', $2, $3, $4, false)`, id, user, mustTime(t, root), mustTime(t, created))
		}
		if event != "" {
			exec(`INSERT INTO community_tree_events (id, tree_id, kind, actor_user_id, occurred_at, recorded_at,
			                                         after, in_public_history)
			      VALUES ($1, $1, 'added', $2, $3, $4, '{"lat": 37.76, "lon": -122.5, "placement": "gps"}', false)`,
				id, user, mustTime(t, event), mustTime(t, created))
		}
		return id
	}
	cases := []struct {
		name string
		id   uuid.UUID
		want string
	}{
		{"an evening add in the Americas: the UTC date",
			insert("2026-09-20T05:30:00Z", "2026-09-20T05:30:00Z", "2026-09-20T05:30:02Z", "2026-09-20T05:30:02Z"), "2026-09-20"},
		{"added signed out and claimed eleven days later: the add's day, not the claim's",
			insert("2026-08-30T18:00:00Z", "2026-08-30T18:00:00Z", "2026-08-30T18:00:01Z", "2026-09-10T09:00:00Z"), "2026-08-30"},
		{"received months after the add: the add's day",
			insert("2026-08-01T03:00:00Z", "2026-08-01T03:00:00Z", "2026-11-10T12:00:00Z", "2026-11-10T12:00:00Z"), "2026-08-01"},
		{"declined, so still private: dated all the same",
			insert("2026-09-03T12:00:00Z", "2026-09-03T12:00:00Z", "2026-09-03T12:00:00Z", ""), "2026-09-03"},
		{"a phone clock ahead of the receipt: the receipt's day",
			insert("2026-10-05T12:00:00Z", "2026-10-05T12:00:00Z", "2026-10-01T12:00:00Z", "2026-10-01T12:00:00Z"), "2026-10-01"},
		{"a phone clock before the app existed: the receipt's day",
			insert("1970-01-01T00:00:00Z", "1970-01-01T00:00:00Z", "2026-10-02T12:00:00Z", "2026-10-02T12:00:00Z"), "2026-10-02"},
		{"no added event: the root location's instant",
			insert("", "2026-09-02T12:00:00Z", "2026-09-05T12:00:00Z", "2026-09-05T12:00:00Z"), "2026-09-02"},
		{"neither: the receipt's day",
			insert("", "", "2026-09-07T12:00:00Z", "2026-09-07T12:00:00Z"), "2026-09-07"},
	}

	if err := s.applyOne(ctx, migrationFileVersion(t, 8)); err != nil {
		t.Fatalf("applying 008 over existing rows: %v", err)
	}
	for _, c := range cases {
		var got time.Time
		if err := s.pool.QueryRow(ctx, `SELECT added_on FROM community_trees WHERE id = $1`, c.id).Scan(&got); err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got.Format(time.DateOnly) != c.want {
			t.Errorf("%s: added_on = %s, want %s", c.name, got.Format(time.DateOnly), c.want)
		}
	}

	var nullable string
	var positionIndexes int
	if err := s.pool.QueryRow(ctx, `
		SELECT (SELECT is_nullable FROM information_schema.columns
		         WHERE table_name = 'community_trees' AND column_name = 'added_on'),
		       (SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_community_trees_position')
	`).Scan(&nullable, &positionIndexes); err != nil {
		t.Fatal(err)
	}
	if nullable != "NO" {
		t.Errorf("added_on is nullable (%s): a writer that forgets it would store a tree with no day", nullable)
	}
	if positionIndexes != 0 {
		t.Errorf("idx_community_trees_position is still there; 008 drops it")
	}

	// The receipt bound is the database's too: two days past the receipt's UTC date is refused, one
	// is not.
	tree := cases[0].id
	if _, err := s.pool.Exec(ctx, `UPDATE community_trees SET added_on = DATE '2026-09-21' WHERE id = $1`, tree); err != nil {
		t.Fatalf("one day past the receipt (east of UTC) was refused: %v", err)
	}
	_, err := s.pool.Exec(ctx, `UPDATE community_trees SET added_on = DATE '2026-09-22' WHERE id = $1`, tree)
	if err == nil || !strings.Contains(err.Error(), "community_trees_added_on_not_after_receipt") {
		t.Fatalf("two days past the receipt was not refused by community_trees_added_on_not_after_receipt: %v", err)
	}

	// And the head is reachable from here: nothing after 008 trips over these rows.
	if err := s.Migrate(ctx); err != nil {
		t.Fatalf("migrating to the head after 008: %v", err)
	}
}
