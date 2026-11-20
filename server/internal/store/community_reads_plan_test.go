package store

import (
	"context"
	"strings"
	"testing"
)

// TestTheProductionTileQueriesUseTheirIndexes is the #190 verification's V5: it plans the tile's
// **production** query texts, `tileSnapshotQuery` and `tileDeltaQuery` themselves, rather than
// hand-written shapes of their arms. `TestTheTileIndexesServeTheirQueries` proves 007 offers the
// indexes; this proves the queries that ship still take them, so an edit that makes one arm
// unindexable (an `OR $n IS NULL`, a predicate the partial index no longer implies) goes red here
// instead of turning into a scan of every community tree on every tile request.
//
// The plan is the **generic** one, the plan pgx's statement cache can settle on and the one the
// review measured at 403 ms when it degraded. Sequential scans are disabled so an empty test table
// cannot make the choice for the planner: with them off, a query whose arm can still use its index
// plans an index scan, and one that cannot plans a (disabled) sequential scan anyway, which is
// what this test looks for.
func TestTheProductionTileQueriesUseTheirIndexes(t *testing.T) {
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
	indexes := []string{
		"idx_community_trees_public_position",
		"idx_community_tree_locations_public_position",
		"idx_withdrawn_community_trees_public",
	}
	for name, query := range map[string]string{
		"tileSnapshotQuery": tileSnapshotQuery,
		"tileDeltaQuery":    tileDeltaQuery,
	} {
		// The simple protocol, straight to the connection: EXPLAIN (GENERIC_PLAN) takes the query's
		// $n placeholders unbound, which pgx's extended protocol would try to bind.
		results, err := tx.Conn().PgConn().Exec(ctx, `EXPLAIN (GENERIC_PLAN) `+query).ReadAll()
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		var lines []string
		for _, result := range results {
			for _, row := range result.Rows {
				lines = append(lines, string(row[0]))
			}
		}
		plan := strings.Join(lines, "\n")
		if len(lines) == 0 {
			t.Fatalf("%s: EXPLAIN returned no plan", name)
		}
		for _, index := range indexes {
			if !strings.Contains(plan, index) {
				t.Errorf("%s: the generic plan does not use %s:\n%s", name, index, plan)
			}
		}
		if strings.Contains(plan, "Seq Scan") {
			t.Errorf("%s: the generic plan scans a table:\n%s", name, plan)
		}
	}
}
