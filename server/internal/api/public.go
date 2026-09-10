package api

import (
	"net/http"
	"strconv"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The public tree read — the only unauthenticated read this service answers, and the first surface
// anywhere in this system that shows one person's contribution to another person.
//
// Its contract is `docs/rulings-pending/public-tree-read.md`, decided field by field before this
// file was written. The one sentence the rest of it follows from:
//
//	The page publishes the state of the tree. It never publishes anybody's activity.
//
// A vitality rating and a taped diameter are properties of a tree that happen to have been
// established by a person; they survive having their author erased. A visit, a photograph, a care
// event, a count of any of them, a dated feed of any of them — these *are* their author, wearing a
// tree's name. That is why this file returns three values and no list, no count, no photograph, no
// coordinate, no timestamp finer than a month, and no identifier of any contributor.
//
// ── The keys are snake_case, and that is the documented rule rather than an exception ──────────
//
// `wire.go` states the split: a payload that reconstructs a client-owned Swift type speaks that
// type's synthesized camelCase property names, and everything else speaks the API's snake_case.
// **Nothing decodes this body into a Swift type.** Its consumer is the server-side-rendered web app
// (TypeScript), and the phone has no use for it — the phone reads its own contributions locally and
// the city layer from the installed pack (R36). So it falls on the snake_case side, and
// `TestPublicBodyIsSnakeCaseThroughout` holds it there.

// publicTreeRead is the response body.
//
// Every field is optional and an absent one is `null` rather than omitted, for `wireTree`'s reason:
// a present null says "this service has no answer behind that", an absent key says nothing at all.
// A page that draws nothing where knowledge is absent needs to be able to tell those apart.
type publicTreeRead struct {
	// TreeUUID echoes the caller's own path parameter. It confirms nothing — see the handler.
	TreeUUID uuid.UUID `json:"tree_uuid"`
	// VerificationState is fixed at `unverified`, and it is fixed because it is knowable for every
	// value this body can carry: nothing in this system verifies a contribution, the verification
	// tier is unbuilt, and `TreeMeasurement.verificationState` is `.unverified` on every row.
	//
	// It ships as a field rather than being left implicit because PRODUCT's non-goals require it:
	// *"Community-added trees shown as official inventory — the community layer is visually
	// distinct and never displays as official until verified."* This is the machine-readable half
	// of that obligation, so the page cannot render these numbers as the city's by omission.
	//
	// Fixed values in a response have `wireTree`'s precedent, which fixes `source` and
	// `verificationState` on the same argument. When a verification tier ships this must become a
	// per-value field read off the record, because verification is per-record (D12).
	VerificationState string `json:"verification_state"`

	Vitality *publicVitality `json:"vitality"`
	Height   *publicReading  `json:"height"`
	TrunkDBH *publicReading  `json:"trunk_dbh"`
}

// publicVitality is §W1's `Status` row — `Thriving · vitality 4`.
//
// The **rating** travels and the label does not. `Vitality` is an `Int`-backed enum whose `label` and
// anchor sentences are Core's, transcribed verbatim from the PRODUCT §3 rubric table; the web
// re-derives them from the ported rubric (W-B). A label rendered here would be a second copy of a
// table this project has already had to repair once for saying two things at once.
type publicVitality struct {
	Rating int `json:"rating"`
	// ObservedMonth is `2006-01`. See `publicMonth`.
	ObservedMonth string `json:"observed_month"`
}

// publicReading is §W1's `Height` and `Trunk · DBH` rows — `18 m` `est.`, `64 cm` `taped`.
//
// **All three of value, unit and method, always.** D7 is not negotiable: a quantity without a method
// does not compile on the client, and the method badge is the fact column's entire point — `est.`
// and `taped` are what separate a reading from a guess, and R1 spent a token retint on making the
// two distinguishable at 4.5:1. A value published without its method would be this service
// laundering an estimate into a measurement.
//
// **The server does not convert.** `Quantity` stores the number as typed in the unit it was typed in
// and derives SI rather than storing both; the web re-derives it the same way from the ported type.
// A unit table in Go would be a second implementation of a Core rule, which is the two-copies
// failure `CLAUDE.md`'s schema-version bullet exists because of.
type publicReading struct {
	Value       float64 `json:"value"`
	UnitEntered string  `json:"unit_entered"`
	Method      string  `json:"method"`
	// MeasuredMonth is `2006-01`. See `publicMonth`.
	MeasuredMonth string `json:"measured_month"`
}

// ── The vocabularies, read from Swift by the tests rather than restated here ───────────────────

// measurementMethods is `MeasurementMethod` (`Cypress/Core/Units/Quantity.swift`).
//
// A reading whose method is outside this set is not published at all. "Render nothing where
// knowledge is absent" is the house style and a public page is the worst place to begin guessing —
// and the specific harm is that an unknown method has no badge, so the number would draw as though
// its provenance were known. `TestMeasurementMethodMatchesTheSwiftVocabulary` reads the raw values
// off the declaration, the way `golden_test.go` already reads `TreePlacement` off `Tree.swift`.
var measurementMethods = map[string]bool{
	"tape": true, "caliper": true, "estimate": true, "laser": true,
}

// lengthUnits is `LengthUnit` (`Cypress/Core/Units/Quantity.swift`). Same rule, same reason: a
// number whose unit is unknown is not a length.
var lengthUnits = map[string]bool{
	"mm": true, "cm": true, "m": true, "in": true, "ft": true,
}

// vitalityRatings is `Vitality`'s five raw values (`Cypress/Core/Rubric/Vitality.swift`), which are
// `Int` rather than `String` — the anchored 1–5 class of the PRODUCT §3 rubric.
var vitalityRatings = map[int]bool{1: true, 2: true, 3: true, 4: true, 5: true}

// ── The allow-list over `contributions.kind` ───────────────────────────────────────────────────

// publicKinds is the set of contribution kinds any part of the public read may look at.
//
// **An allow-list, and the shape is the decision.** `contributions.kind` is a closed CHECK
// vocabulary of seventeen values (`004_measurement_withdrawal_kind.sql`) and it has widened twice
// already. Under a deny-list the *next* kind would be public the day it was added, decided by
// nobody — which is precisely how `testflight.yml`'s path classifier came to treat a new top-level
// directory as "run the whole iOS suite and mint a TestFlight build". Under an allow-list a new kind
// is invisible until somebody writes down why it should not be.
//
// `withheldKinds` states the reason for each of the other fifteen, and
// `TestEveryContributionKindIsClassified` reads the vocabulary out of the migration and fails when a
// value is in neither map. That test is the mechanism; this map is only the decision.
var publicKinds = map[string]bool{
	"measurement": true,
	"observation": true,
}

// withheldKinds is the other fifteen, each with the reason it is not public. The ruling argues them;
// these are the one-line forms, kept here so the classification cannot be silently incomplete.
var withheldKinds = map[string]string{
	"visit":                    "a dated visit at a fixed place is a public user location history — PRODUCT's non-goals: Never",
	"care_event":               "an account of a person's actions at a place, not a property of the tree",
	"favorite_toggle":          "favorites are private (R2, D11); the beloved state is R27.1's and its floor is still open",
	"private_reminder":         "private by name and by D4",
	"add_tree":                 "a community tree is in no published pack, so it has no page in v1",
	"species_claim":            "an unadjudicated assertion; 002 declines to materialize the chain",
	"species_correction":       "same, and a correction supersedes rather than overwrites — the order is the moderation deliverable's",
	"wrong_species_report":     "an unadjudicated accusation",
	"never_existed_report":     "an unadjudicated accusation",
	"species_review_dismissal": "moderation bookkeeping",
	"record_review_dismissal":  "moderation bookkeeping",
	"photo_vote":               "a count of user actions, and R72: a photo vote is not a report",
	"photo_withdrawal":         "a removal; its effect is visible, the act is not",
	"measurement_withdrawal":   "a removal; its effect is visible, the act is not",
	// DECISIONS §3.4, verbatim: "Hazard categories never produce a public note, never produce a
	// community-visible record, and never auto-stale. **No public surface query may be able to
	// return a hazard-category note (enforced by a schema invariant test).**" PRODUCT's non-goals
	// say it in three words: "Hazards becoming public notes | Never." Until this round there was no
	// public surface query in this system, so that invariant test had no subject. It has one now —
	// `TestNoHazardRedirectReachesThePublicRead`.
	"hazard_redirect": "DECISIONS §3.4 and PRODUCT's non-goals: a hazard never becomes a public note",
}

// ── The handler ────────────────────────────────────────────────────────────────────────────────

// publicCacheControl bounds how long a withdrawn value can survive downstream.
//
// Sixty seconds, chosen against the takedown route rather than against traffic: an operator who
// removes something expects minutes, not hours. It is not zero because the alternative is 1.1
// million public URLs of crawler traffic reaching one shared-cpu-1x machine uncached, and it is not
// longer because nothing downstream may hold a contributed value after its contributor has taken it
// back. The round that renders the page may not cache beyond this.
const publicCacheControl = "public, max-age=60"

// publicTree answers the community half of one tree to somebody with no account.
//
// ── Absent, empty and fully withdrawn are one answer, and it is not `not_found` ────────────────
//
// `DeletePhotoByContributor` answers `ErrNotFound` for a photograph that is somebody else's, because
// "a refusal would confirm the row exists to somebody who is not allowed to know that". The posture
// is right and the instrument is wrong here, because the two identifiers are not alike: a photo id
// is a private handle, while a **tree UUID is public by design** — it is in every published pack,
// and `SharePresentation.publicURL` builds every share link this app has ever produced as
// `ShareCopy.publicURLPrefix + tree.id.uuidString.lowercased()`, so the id is the last path segment
// of a link people paste into group chats. There is no tree existence to protect.
//
// What must not be detectable is the state of the *community half* — whether this tree has
// contributions that are all withdrawn, or none, or is not a tree at all. A 404 would answer that
// question rather than avoid it. So every syntactically valid UUID gets 200 and a body of the same
// shape, and the body for a tree with nothing publishable is **byte-identical** to the body for a
// UUID this database has never seen. `TestAbsentEmptyAndWithdrawnAreOneAnswer` asserts that on the
// bytes, in three directions at once.
//
// A malformed id is `validation_failed` — a syntax error is not an existence oracle, and
// `parsePathUUID` is what every other route answers with.
func (s *Server) publicTree(w http.ResponseWriter, r *http.Request) error {
	id, err := parsePathUUID(r, "id")
	if err != nil {
		return err
	}

	half, storeErr := s.Store.PublicTreeCommunityHalf(r.Context(), id)
	if storeErr != nil {
		return apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", storeErr)
	}

	body := publicTreeRead{TreeUUID: id, VerificationState: "unverified"}
	body.Vitality = publicVitalityFrom(half.Vitality)
	for _, reading := range half.Readings {
		projected := publicReadingFrom(reading)
		if projected == nil {
			continue
		}
		switch reading.Kind {
		case "height":
			body.Height = projected
		case "dbh":
			body.TrunkDBH = projected
		}
	}

	w.Header().Set("Cache-Control", publicCacheControl)
	writeJSON(w, s.Log, http.StatusOK, body)
	return nil
}

// publicMonth is the one time format this response speaks: `2026-09`, in UTC.
//
// **The day does not travel, and that is the ruling's §4 rather than a formatting choice.** A
// value's date is part of the value — a diameter with no date is not a reading — but the *day* is
// where the contributor was, and on a tree with one contributor a dated value is that person's
// movement record with no inference required. Month precision keeps every use the fact has and
// drops the one it should not have, which is the move `Coordinate.snappedToPublicPhotoGrid` already
// makes for a public coordinate: blunt the precision rather than withhold the fact.
//
// UTC, for `Timestamp`'s reason — the service has one timezone on the wire and a month that shifted
// with the reader's would be two answers to one question.
func publicMonth(row store.PublicReading) string { return row.OccurredAt.UTC().Format("2006-01") }

func publicVitalityFrom(row *store.PublicVitalityRow) *publicVitality {
	if row == nil {
		return nil
	}
	// Parsed here rather than cast in SQL — see `PublicVitalityRow`. A rating that does not parse,
	// or that names a class the rubric does not have, is published as nothing: an out-of-range
	// number rendered as `vitality 7` would be a claim about a tree that the rubric cannot make.
	rating, err := strconv.Atoi(row.Rating)
	if err != nil || !vitalityRatings[rating] {
		return nil
	}
	return &publicVitality{
		Rating:        rating,
		ObservedMonth: row.OccurredAt.UTC().Format("2006-01"),
	}
}

func publicReadingFrom(row store.PublicReading) *publicReading {
	value, err := strconv.ParseFloat(row.Value, 64)
	if err != nil {
		return nil
	}
	// A method or a unit outside the Swift vocabulary means the number cannot be drawn honestly:
	// no badge for an unknown method, no length for an unknown unit. Nothing is published.
	if !measurementMethods[row.Method] || !lengthUnits[row.UnitEntered] {
		return nil
	}
	return &publicReading{
		Value:         value,
		UnitEntered:   row.UnitEntered,
		Method:        row.Method,
		MeasuredMonth: publicMonth(row),
	}
}
