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
// A taped diameter and an estimated height are properties of a tree that happen to have been
// established by a person; they survive having their author erased. A visit, a photograph, a care
// event, a count of any of them, a dated feed of any of them — these *are* their author, wearing a
// tree's name. That is why this file returns two readings and one boolean, and no list, no count, no
// photograph, no coordinate, no timestamp finer than a month, and no identifier of any contributor.
//
// **A second sentence had to be added after the round's adversarial review, and it is a constraint
// rather than a principle:** this endpoint publishes nothing it cannot also un-publish. §W1's
// vitality rating passes the sentence above and is still not here, because no route exists to take a
// published rating back — see the note on `publicTreeRead`. What a page may say and what a page can
// stop saying turned out to be two questions, and the ruling had answered only the first.
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

	// Beloved is R27.1's state, and it is a **bool** rather than a number. See `belovedFloor`.
	Beloved  bool           `json:"beloved"`
	Height   *publicReading `json:"height"`
	TrunkDBH *publicReading `json:"trunk_dbh"`
}

// ── What §W1's `Status` row does not get, and why the field is gone rather than nulled ─────────
//
// This struct carried `Vitality *publicVitality` — §W1's `Status · Thriving · vitality 4` — and the
// field is removed, not left as a permanent `null`. The adversarial review of this round's PR found
// that the ruling's §8 closed ROADMAP open question 2 on a mechanism covering two of the three
// values published: **a published rating has no takedown route at all.** There is no observation
// withdrawal in `contributions.kind`'s seventeen values, `contributions` has no `moderation_state`
// and no operator route, so neither the contributor nor an operator can take a rating off an indexed
// page. A withdrawal aimed at one answers `applied` and changes nothing, which is E280's sentence
// arriving on this table.
//
// Adding the kind is a **migration**, and CLAUDE.md gives one migration author per round; this round
// has none. So the endpoint narrows to what its own claim is true of, rather than the claim widening
// to what the endpoint does. The field is removed rather than nulled because a permanent `null` is a
// shape the web would build a slot for, and the honest statement is that this service has no
// publishable rating today — not that it has none for this tree.
//
// `docs/ROADMAP.md` carries the item that brings it back.

// belovedFloor is R27.1 §2's k-anonymity threshold, and the number is provisional.
//
// **The state, not the rank, and not the number.** The owner ruled on 2026-09-10 that the beloved
// state ships on the public tree page as a state. R27.1 §1 permits the count as well — *"Showing the
// number too is permitted and preferred"* — and this endpoint does not publish it, for two reasons
// worth writing down rather than inferring: §1's permission is about a *ranking*, where hiding the
// number while showing the order is the worst of both, and there is no ranking here; and the round's
// own ruling refuses every count on this page. Shipping the boolean is therefore less than R27.1
// permits, deliberately, and whether the number rides along is a question for the owner in the
// ruling rather than a decision taken here.
//
// **Why a boolean is safe here when the ruling refused one for photographs.** The ruling's §1 argues
// that a boolean is a count at one bit of resolution and that one bit is enough when a tree has one
// contributor. That is true of a photo count, which has no floor available to it — the number *is*
// §W1's headline fact, so suppressing it below a floor publishes "fewer than three people
// photographed this tree", the same disclosure with a step. It is not true here: the boolean is only
// ever `true` at three or more distinct owners, so it cannot publish one person's private bookmark,
// and `false` covers everything from nought to two indistinguishably. R27.1 §2 is exactly that
// argument and it is why the floor is a privacy mechanism rather than modesty.
//
// **Three is R27.1's provisional figure and this round did not improve on it.** R27.1 leaves the
// number open — *"the numeric floor, which wants the real distribution of favorites per tree before
// it is chosen — count it, do not guess it"* — and this round **did not measure the distribution**:
// the attempt to read it off the production database was refused before any query ran, and the
// number below is therefore R27.1's own ≥3 (DECISIONS' caretakers precedent) unchanged, not a
// measured one. That is stated plainly here and in the ruling rather than left to be assumed,
// because a guessed threshold presented as a measured one is the failure R27.1's own sentence is
// written against. It is not negotiable downward, and the round that measures it may raise it.
//
// The count behind it is a count of favorite *owners*, and one person on two devices is two of them
// — see `PublicTreeCommunityHalf`. The floor is therefore slightly weaker than it reads.
const belovedFloor = 3

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

// ── The allow-list over `contributions.kind` ───────────────────────────────────────────────────

// publicKinds is the set of contribution kinds any part of the public read may look at.
//
// **An allow-list, and the shape is the decision.** `contributions.kind` is a closed CHECK
// vocabulary of seventeen values — declared across the migrations, last declaration wins, which as
// of this round is `004_measurement_withdrawal_kind.sql` — and it has widened twice
// already. Under a deny-list the *next* kind would be public the day it was added, decided by
// nobody — which is precisely how `testflight.yml`'s path classifier came to treat a new top-level
// directory as "run the whole iOS suite and mint a TestFlight build". Under an allow-list a new kind
// is invisible until somebody writes down why it should not be.
//
// `withheldKinds` states the reason for each of the other fifteen, and
// `TestEveryContributionKindIsClassified` reads the vocabulary out of **every** migration — the way
// `loadMigrations` applies them — and fails when a value is in neither map. That test is the
// mechanism; this map is only the decision. It reads a directory rather than a filename because the
// single-file version of it was green with an unclassified kind live in the schema: a widening can
// only arrive as a new file, since an applied migration is frozen, and a new file was exactly what
// it could not see. `TestTheLiveSchemaAgreesWithTheMigrationFiles` asks the running database the
// same question without parsing any SQL at all.
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

	body := publicTreeRead{
		TreeUUID:          id,
		VerificationState: "unverified",
		// The comparison is `>=` and the count never leaves this line. A body that carried the
		// number would be a count of user actions on a public page whatever it was called.
		Beloved: half.Favorites >= belovedFloor,
	}
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
