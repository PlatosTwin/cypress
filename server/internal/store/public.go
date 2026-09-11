package store

import (
	"context"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The public read. Everything in this file is answered to somebody with no account, on a page a
// search engine will index, so it is the one place in this service where the *absence* of a column
// from a query is load-bearing rather than tidy.
//
// The contract is `docs/rulings-pending/public-tree-read.md`. Three of its clauses are structural
// here rather than remembered:
//
//  1. **One kind is read and sixteen are not.** `contributions.kind` is a closed CHECK vocabulary
//     of seventeen values (the migrations, last declaration wins); this query names `measurement`
//     explicitly and can therefore never widen by accident. The api package holds
//     the classification of all seventeen and a test that fails when one is unclassified — an
//     allow-list, because a deny-list on a public surface is how `testflight.yml` came to classify a
//     new top-level directory as "run everything and ship a build".
//  2. **One value per field, never a list.** A state is publishable; a dated series of a person's
//     acts at a fixed place is a movement record, which PRODUCT's non-goals answer with one word.
//     `DISTINCT ON` and `LIMIT 1` are that rule, in SQL.
//  3. **Nothing is cast and nothing is echoed.** Every value extracted from a payload comes back as
//     text and is validated in Go by the caller, and the columns that would identify a contributor
//     are not selected at all. See `PublicReading` for both reasons.

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
	Readings []PublicReading
	// Favorites is how many distinct **accounts** currently hold this tree as a favorite.
	//
	// Device-only favorites are excluded, and that is an owner ruling rather than a query detail —
	// see the query. The count reaches the wire only above `belovedFloor` (api package); below the
	// floor the number is discarded here and nothing downstream can publish it.
	Favorites int
}

// PublicTreeCommunityHalf reads it.
//
// Two queries rather than one union: they select different shapes, and a union that made them one
// would have to widen both to the other's columns — which is exactly how a query starts selecting a
// column nobody meant to publish.
func (s *Store) PublicTreeCommunityHalf(ctx context.Context, treeUUID uuid.UUID) (PublicTreeCommunity, error) {
	var half PublicTreeCommunity

	// ── The vitality rating is not read here, and the reason is a missing route ────────────────
	//
	// **This function used to read the latest `observation`'s rating and it no longer does.** The
	// round's ruling closed ROADMAP open question 2 — *what a withdrawn or moderated record does to
	// an indexed public page* — with "a withdrawal removes a fact from a page, it does not remove a
	// page", and the adversarial review proved that sentence false for exactly one of the three
	// values published: a withdrawal against an `observation` answers `applied` and the rating stays
	// on the page.
	//
	// It is not a bug in `withdrawMeasurement`. **There is no observation withdrawal at all.**
	// `contributions.kind`'s vocabulary carries `measurement_withdrawal` and `photo_withdrawal` and
	// no counterpart for the `observation` that holds the rating; `contributions` has no
	// `moderation_state` and no operator takedown, so nobody — the contributor, the operator —
	// can take a published rating back. Adding the kind is a migration, this round has no migration
	// author, and CLAUDE.md gives one author per round: so the endpoint publishes less rather than
	// the ruling claiming more.
	//
	// The rating comes back in the round that adds the withdrawal kind. Until then the page draws
	// nothing where a rating would be, which is the house style rather than a degradation.

	// How many distinct **account-backed** owners currently hold this tree as a favorite.
	//
	// **This is the one publishable fact in this system whose takedown route is complete**, which is
	// why it is here while the rating is not. Un-favoriting is an ordinary toggle that writes
	// `is_favorite = false` through the same upsert (R2 gave the heart a real off state), and
	// account deletion runs `DELETE FROM favorites WHERE user_id = $1` under **both** doors — the
	// leaving door included, because `favorites_owner` makes an ownerless favorite unstorable and
	// 001's own comment says that is why they are deleted unconditionally rather than kept.
	//
	// `is_favorite` rather than row existence: the table holds tombstones, and an un-favorited tree
	// is not one anybody would say they have (`MapMembership`'s own rule, verbatim).
	//
	// ── `user_id IS NOT NULL`, and it is the whole of an owner ruling ──────────────────────────
	//
	// **This was `count(*)` over every favorite row, and it was farmable by somebody with no
	// account at all.** `favorites_owner` makes each row exactly one owner, *user or device*;
	// `POST /devices/register` takes no credential and mints a fresh device — therefore a fresh
	// owner — per UUID it is handed. Three unauthenticated calls and three toggles set `beloved`
	// on any tree in the inventory. The delta review of this round's PR demonstrated it, and the
	// comment that stood here called the floor "slightly weaker than it reads, never stronger",
	// which undersold it: the real property was that an *owner could be minted without a person or
	// an account existing*, and farmability is D1's whole stated reason for banning public counts.
	//
	// The owner ruled on 2026-09-10 that only account-backed favorites count toward the public
	// floor. A device-only favorite keeps working exactly as it does now — it is stored, it syncs,
	// it draws the heart, and `claimDevice` still re-homes it onto an account at sign-in
	// (`identity.go`) at which point it begins to count. It simply does not reach the public page
	// on its own. Minting an account costs Sign in with Apple, which is a real identity Apple
	// rate-limits; minting a device costs an HTTP request.
	//
	// `count(DISTINCT user_id)` rather than `count(*)` over the same predicate. The two are equal
	// under `idx_favorites_user_tree` — one row per user per tree — and the `DISTINCT` is written
	// anyway so the statement says what it counts rather than relying on an index elsewhere in the
	// file to make an ambiguous statement unambiguous.
	//
	// The remaining honest limitation is now the opposite one, and it is smaller: the count is of
	// **accounts**, so one person with two Apple IDs is two. It can no longer be moved by anybody
	// without an account.
	err := s.pool.QueryRow(ctx, `
		SELECT count(DISTINCT user_id)
		  FROM favorites
		 WHERE tree_uuid = $1
		   AND is_favorite
		   AND user_id IS NOT NULL
	`, treeUUID).Scan(&half.Favorites)
	if err != nil {
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
