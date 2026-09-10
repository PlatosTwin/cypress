package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// The public read. Everything in this file is answered to somebody with no account, on a page a
// search engine will index, so it is the one place in this service where the *absence* of a column
// from a query is load-bearing rather than tidy.
//
// The contract is `docs/rulings-pending/public-tree-read.md`. Three of its clauses are structural
// here rather than remembered:
//
//  1. **Two kinds are read and fifteen are not.** `contributions.kind` is a closed CHECK vocabulary
//     of seventeen values (the migrations, last declaration wins); these queries name `measurement`
//     and `observation` explicitly and can therefore never widen by accident. The api package holds
//     the classification of all seventeen and a test that fails when one is unclassified — an
//     allow-list, because a deny-list on a public surface is how `testflight.yml` came to classify a
//     new top-level directory as "run everything and ship a build".
//  2. **One value per field, never a list.** A state is publishable; a dated series of a person's
//     acts at a fixed place is a movement record, which PRODUCT's non-goals answer with one word.
//     `DISTINCT ON` and `LIMIT 1` are that rule, in SQL.
//  3. **Nothing is cast and nothing is echoed.** Every value extracted from a payload comes back as
//     text and is validated in Go by the caller, and the columns that would identify a contributor
//     are not selected at all. See `PublicReading` for both reasons.

// PublicVitalityRow is the latest live vitality rating for a tree, unparsed.
//
// `Rating` is text because `(payload->>'vitality')::int` can **error** rather than merely miss:
// this query is filtered by `kind` and casts in the projection, and nothing in the standard promises
// Postgres evaluates the qual before the cast — the hazard `004_measurement_withdrawal_kind.sql`
// records for `::uuid` and avoids the same way. A payload of the right kind carrying a non-numeric
// `vitality` would otherwise fail the whole request. Parsed and range-checked by the caller, which
// publishes nothing when it does not parse.
type PublicVitalityRow struct {
	Rating     string
	OccurredAt time.Time
}

// PublicReading is one live measurement, unparsed, as the public read needs it.
//
// **What is not here is the point.** `contributions.payload` for a `measurement` is the whole of
// `TreeMeasurement`, which carries `userID`, `deviceID`, `clientUUID` and `gpsAccuracyM` — the
// contributor's identifiers and how accurately their phone believed it was standing at that tree.
// The query names four values out of the payload and the row type has nowhere to put a fifth, so
// publishing one would take an edit to this struct rather than an oversight in a handler.
//
// `OccurredAt` is the **column**, not the payload's `capturedAt`. They are the same fact and this
// service already reads it from the column everywhere else (`Grove`, `Journal`); a second copy of
// one fact is a second place for it to be wrong.
type PublicReading struct {
	// Kind is `dbh` or `height` — `MeasurementKind`'s two raw values.
	Kind        string
	Value       string
	UnitEntered string
	Method      string
	OccurredAt  time.Time
}

// PublicTreeCommunity is everything this service will say about one tree to somebody with no
// account.
//
// Every field is optional and an absent field is drawn as nothing, which is the house style rather
// than a degradation: "render nothing where knowledge is absent". A tree this database has never
// heard of and a tree whose every contribution has been withdrawn produce the same zero value, and
// the api package asserts that they produce the same *bytes* — see the ruling's §9 for why the
// answer here is a uniform 200 rather than the `not_found` the photo read gives.
type PublicTreeCommunity struct {
	Vitality *PublicVitalityRow
	Readings []PublicReading
}

// PublicTreeCommunityHalf reads it.
//
// Two queries rather than one union: they select different shapes, and a union that made them one
// would have to widen both to the other's columns — which is exactly how a query starts selecting a
// column nobody meant to publish.
func (s *Store) PublicTreeCommunityHalf(ctx context.Context, treeUUID uuid.UUID) (PublicTreeCommunity, error) {
	var half PublicTreeCommunity

	// The latest live rating. `deleted_at IS NULL` is the withdrawal filter every read in this
	// service already applies; an **anonymized** row is deliberately still read, because
	// `AccountDeletionChoice.leaveRecords` unlinks a contribution from its author and keeps the
	// record — that is what the leaving door promises, and the record is what this page is made of.
	var vitality PublicVitalityRow
	err := s.pool.QueryRow(ctx, `
		SELECT payload ->> 'vitality', occurred_at
		  FROM contributions
		 WHERE tree_uuid = $1
		   AND kind = 'observation'
		   AND deleted_at IS NULL
		   AND payload ->> 'vitality' IS NOT NULL
		 ORDER BY occurred_at DESC, client_uuid DESC
		 LIMIT 1
	`, treeUUID).Scan(&vitality.Rating, &vitality.OccurredAt)
	switch {
	case err == nil:
		half.Vitality = &vitality
	case errors.Is(err, pgx.ErrNoRows):
		// Nothing to say. Not an error, and not a zero: a zero rating is a claim about a tree.
	default:
		return PublicTreeCommunity{}, err
	}

	// The latest live reading **per measurement kind**: one answer for the height and one for the
	// diameter, each the most recent by `occurred_at`, whatever method took it.
	//
	// ── What this does not do, stated because a comment here claimed the opposite ──────────────
	//
	// This comment used to read *"Per series, never blended — D7 keeps estimated and measured
	// apart"*. **That was false about this query and it is corrected rather than deleted.**
	// `DISTINCT ON (payload ->> 'kind')` groups on `MeasurementKind` — `dbh | height` — and
	// `MeasurementSeries` is a different axis entirely, `measured | estimated`, reached through
	// `MeasurementMethod.series`. Nothing here separates them, so a newer `estimate` **does**
	// supersede an older `tape` in this response. The adversarial review of this round's PR proved
	// it: a 90 cm estimate replaced a 64 cm taped reading on the public page.
	//
	// ── Why that is the behavior kept, rather than the defect fixed ────────────────────────────
	//
	// Because it is the behavior the app already has, and a second answer would be worse than this
	// one. `TreeProfilePresentation.latestMeasurement` is the client's whole rule —
	// `filter { kind, not deleted }.max { capturedAt }` — with no method or series term;
	// `MeasureModel.previousMeasurement` is a verbatim second copy of it, and
	// `GrowthHistoryPresentation.chart(for:)` re-merges both series to label its newest and oldest
	// points. **No ruling, decision or erratum in this repository states a precedence between an
	// estimate and a measurement.** D7 and PRODUCT's non-goal are rules about a *chart line* — the
	// non-goal's rationale cell is five words, "Never share a chart line" — and E103 extends them to
	// a spoken summary; none of the three is about which single number is current.
	//
	// So ranking methods here would be this service authoring a product rule the app does not have,
	// and the page would then print `64 cm taped` where the phone prints `90 cm est.` for the same
	// tree on the same day. That is the two-copies failure this file already refuses for unit
	// conversion, arriving through a different door.
	//
	// **What makes it honest is that the method travels.** D7's actual obligation is that no number
	// is published without how it was obtained, and `publicReadingFrom` refuses a reading whose
	// method it does not recognize. A superseding estimate reaches the page carrying `est.`, which
	// is what `MeasuredValue` enforces on the client at the type level: there is no view in the
	// design system that renders a `Quantity`'s number alone, and there is no shape in this response
	// that can carry one either.
	//
	// The open product question — *one tree, one current height: should the method count?* — is
	// `docs/ROADMAP.md`'s, because it is four call sites' question and not this endpoint's.
	// `TestANewerEstimateSupersedesAnOlderTapedReading` pins the answer this round shipped, so
	// changing it is a decision somebody takes rather than a diff nobody notices.
	//
	// The tiebreak is `client_uuid DESC` rather than nothing, so two readings sharing an
	// `occurred_at` resolve the same way on every request. The client's `max` returns whichever came
	// first out of an `ORDER BY captured_at` with no secondary key, which is arbitrary; a public page
	// that changed its answer between two refreshes would be its own defect.
	//
	// The `IN` is a second allow-list, over `MeasurementKind`'s two raw values, so a payload
	// claiming some third kind cannot introduce a third row into a response whose shape is fixed.
	rows, err := s.pool.Query(ctx, `
		SELECT DISTINCT ON (payload ->> 'kind')
		       payload ->> 'kind',
		       payload -> 'quantity' ->> 'value',
		       payload -> 'quantity' ->> 'unitEntered',
		       payload -> 'quantity' ->> 'method',
		       occurred_at
		  FROM contributions
		 WHERE tree_uuid = $1
		   AND kind = 'measurement'
		   AND deleted_at IS NULL
		   AND payload ->> 'kind' IN ('dbh', 'height')
		 ORDER BY payload ->> 'kind', occurred_at DESC, client_uuid DESC
	`, treeUUID)
	if err != nil {
		return PublicTreeCommunity{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var reading PublicReading
		// Every one of the four is nullable in JSON and therefore a pointer's worth of doubt. They
		// are scanned into pointers so a payload missing `quantity` is a reading this service
		// declines to publish rather than a failed request — a malformed contribution must not be
		// able to take the page down.
		var value, unit, method *string
		if err := rows.Scan(&reading.Kind, &value, &unit, &method, &reading.OccurredAt); err != nil {
			return PublicTreeCommunity{}, err
		}
		if value == nil || unit == nil || method == nil {
			continue
		}
		reading.Value, reading.UnitEntered, reading.Method = *value, *unit, *method
		half.Readings = append(half.Readings, reading)
	}
	if err := rows.Err(); err != nil {
		return PublicTreeCommunity{}, err
	}
	return half, nil
}
