package api

import (
	"encoding/json"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// This file holds the types that **mirror client-owned Swift types**, and it is the one place in
// this service where the JSON keys are not the server's to choose.
//
// ── Why these are camelCase inside an otherwise snake_case API ─────────────────────────────────
//
// `Cypress/Core/Models/CoreEntity.swift` states the convention for the whole of `Core`: *"keys are
// the Swift property names. The snake_case column, jsonb, and wire names of BUILD-PLAN §4 and §6
// are produced by the coder's key-conversion strategy in `Data`."* None of these types declares
// `CodingKeys` and none has a custom `init(from:)` — every one is synthesized, so its keys are
// exactly its property names.
//
// **The key-conversion half of that convention cannot work for `Tree`, and this is the finding that
// decided the shape below.** Swift's `.convertFromSnakeCase` maps a JSON key to camelCase and then
// matches it against the synthesized `CodingKeys`. `species_current_id` becomes `speciesCurrentId`,
// which is not `speciesCurrentID`; `neighborhood_id` becomes `neighborhoodId`, which is not
// `neighborhoodID`. Both properties are **optional**, so the mismatch does not even throw — it
// decodes as `nil`, silently, and a tree arrives with its species missing and nothing reports it.
//
// So a snake_case body for these types is decodable only by a client that first adds explicit
// `CodingKeys` to a `Core` model — a change this PR cannot make and should not assume. Emitting the
// synthesized names instead means a plain `JSONDecoder` with one date strategy and **no key
// strategy at all** decodes them exactly, which is a contract that can be proven from the Swift
// side rather than hoped for.
//
// Server-owned shapes — the error envelope, the sync results, the request bodies — stay snake_case.
// The rule is: a payload that reconstructs a client type speaks that type's keys; everything else
// speaks the API's.
//
// `server/testdata/` holds a golden file per response type. Step 4 (`RemoteAPI`'s bodies) must add
// Swift decode tests against those exact files — that is how this contract gets pinned from both
// ends instead of from this side only.

// Timestamp is a `Date` on the wire, and its format is a decision rather than a default.
//
// Go's `time.Time` marshals as RFC3339**Nano** — `2026-08-09T18:41:46.832442-07:00`. The only date
// strategy stated anywhere in this app is `OutboxPayload`'s `.iso8601`
// (`Cypress/Data/Outbox/OutboxPayload.swift`), and `JSONDecoder.DateDecodingStrategy.iso8601` uses
// `ISO8601DateFormatter` with `.withInternetDateTime`, which **rejects fractional seconds**. A
// nanosecond timestamp would therefore have failed to decode on the client, on every response
// carrying a date, and this PR is the contract that decision gets frozen in.
//
// So: RFC3339, second precision, UTC. Decodable by `.iso8601` with no options set, and the same
// fixed-width UTC shape `SQLiteTimestamp` already writes on the client side.
type Timestamp time.Time

// MarshalJSON writes the second-precision UTC form.
func (t Timestamp) MarshalJSON() ([]byte, error) {
	return json.Marshal(time.Time(t).UTC().Truncate(time.Second).Format(time.RFC3339))
}

// UnmarshalJSON reads the same form back.
//
// Only the tests decode these — nothing in the service reads its own responses — but a type that
// can only be written is a type whose round trip nobody can assert.
func (t *Timestamp) UnmarshalJSON(data []byte) error {
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return err
	}
	parsed, err := time.Parse(time.RFC3339, text)
	if err != nil {
		return err
	}
	*t = Timestamp(parsed)
	return nil
}

// IsZero reports whether the timestamp is the zero value.
func (t Timestamp) IsZero() bool { return time.Time(t).IsZero() }

// stamp converts, and nil-preserves for the optional dates.
func stamp(t time.Time) Timestamp { return Timestamp(t) }

func stampOrNil(t *time.Time) *Timestamp {
	if t == nil {
		return nil
	}
	converted := Timestamp(*t)
	return &converted
}

// ── The mirrored types ─────────────────────────────────────────────────────────────────────────

// wireCoordinate is `Coordinate` (`Cypress/Core/Models/Geometry.swift`).
//
// Stored properties `latitude` and `longitude`; synthesized keys. **Not `lat`/`lon`** — those were
// this service's own invention and no key strategy rescues them, because `lat` is not a
// snake_cased `latitude`.
type wireCoordinate struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// wireIntRange is `IntRange` (`Cypress/Core/Models/Geometry.swift`).
//
// `lowerBound` inclusive, `upperBound` exclusive, matching Postgres `[)`. Synthesized keys — not
// `min`/`max`.
type wireIntRange struct {
	LowerBound int `json:"lowerBound"`
	UpperBound int `json:"upperBound"`
}

// wireIDTip is `IDTip` (`Cypress/Core/Models/Species.swift`).
type wireIDTip struct {
	Icon string `json:"icon"`
	Text string `json:"text"`
}

// wireTree is `Tree` (`Cypress/Core/Models/Tree.swift`), every property, in declaration order.
//
// `Tree` is `CoreEntity, SoftDeletable`, so `id`, `createdAt`, `updatedAt` and `deletedAt` are part
// of it. Optional properties are emitted as explicit `null` rather than omitted: the client decodes
// an optional either way, and a present null says "this service has no column behind that" while an
// absent key says nothing at all.
//
// The three fixed values are fixed because they are knowable for every row this table holds:
// `source` is always `community`, `verificationState` always `unverified` (neither a city row nor
// org-confirmed), and `cityRecord` always null (a community tree is not in the city's inventory,
// and `main.community_trees` has no columns behind it — `Tree`'s own comment says so).
type wireTree struct {
	ID          uuid.UUID      `json:"id"`
	ExternalRef *string        `json:"externalRef"`
	IDSpace     *string        `json:"idSpace"`
	Source      string         `json:"source"`
	Coordinate  wireCoordinate `json:"coordinate"`
	Address     *string        `json:"address"`
	SiteType    *string        `json:"siteType"`
	// `neighborhoodID`, not `neighborhoodId`. See this file's header for why that difference is
	// the whole reason these keys are camelCase.
	NeighborhoodID    *uuid.UUID    `json:"neighborhoodID"`
	Status            string        `json:"status"`
	SpeciesCurrentID  *uuid.UUID    `json:"speciesCurrentID"`
	PlantedYear       *int          `json:"plantedYear"`
	DBHCityCmRange    *wireIntRange `json:"dbhCityCmRange"`
	SiteLineage       *uuid.UUID    `json:"siteLineage"`
	VerificationState string        `json:"verificationState"`
	// `TreePlacement`, whose two raw values are frozen by `AppSchema` v10's CHECK. Non-optional on
	// the client, so anything outside `{gps, contributor_placed}` throws the whole `Tree`.
	Placement         string     `json:"placement"`
	CityRecord        *struct{}  `json:"cityRecord"`
	StatedLandContext *string    `json:"statedLandContext"`
	CreatedAt         Timestamp  `json:"createdAt"`
	UpdatedAt         Timestamp  `json:"updatedAt"`
	DeletedAt         *Timestamp `json:"deletedAt"`
}

// wireNearbyTree is `NearbyTree` (`Cypress/Data/API/CypressAPI.swift`).
//
// `id` is computed (`tree.id`) and therefore not a stored property, so it is not a coding key.
type wireNearbyTree struct {
	Tree                  wireTree   `json:"tree"`
	DistanceM             float64    `json:"distanceM"`
	SpeciesScientificName *string    `json:"speciesScientificName"`
	SpeciesCommonName     *string    `json:"speciesCommonName"`
	Tell                  *wireIDTip `json:"tell"`
}

// wireGroveRecord is `GroveRecord` (`Cypress/Data/API/GroveRecord.swift`).
//
// `checkIns` is named for the control rather than for the `observations` table — its own comment
// says so. This is the same camelCase-inside-snake_case case as `wireTree`, and for the same
// reason: it reconstructs a client type.
type wireGroveRecord struct {
	Visits       int `json:"visits"`
	CheckIns     int `json:"checkIns"`
	Measurements int `json:"measurements"`
	CareEvents   int `json:"careEvents"`
}
