package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// The golden fixtures. See `server/testdata/README.md` for what step 4 owes these files.
//
// The comparison is byte-for-byte on purpose. A structural comparison against a Go struct is a
// comparison against the transcription — which is the thing that was wrong twice, once as
// `{"lat":…,"lon":…}` and once as `"placement":"unknown"`, both under a passing test.

const goldenDir = "../../testdata"

// updateGolden regenerates the fixtures. Flipped by hand, never in CI: a fixture that regenerates
// itself is a fixture that cannot fail.
const updateGolden = false

func compareGolden(t *testing.T, name string, actual []byte) {
	t.Helper()
	path := filepath.Join(goldenDir, name)

	var pretty bytes.Buffer
	if err := json.Indent(&pretty, actual, "", "  "); err != nil {
		t.Fatalf("%s: output is not JSON: %v", name, err)
	}
	pretty.WriteString("\n")

	if updateGolden {
		if err := os.WriteFile(path, pretty.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
		t.Fatalf("%s regenerated; set updateGolden back to false", name)
	}

	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading the golden file %s: %v\nThis fixture is half of a cross-language "+
			"contract; the test fails rather than skips without it.", name, err)
	}
	if !bytes.Equal(bytes.TrimSpace(want), bytes.TrimSpace(pretty.Bytes())) {
		t.Errorf("%s does not match the golden file.\n--- want ---\n%s\n--- got ----\n%s\n\n"+
			"If this change is intended, the Swift decode tests that read this same file must move "+
			"with it (server/testdata/README.md).", name, want, pretty.Bytes())
	}
}

// fixedCandidate is a proximity candidate with every value pinned, so the fixture is stable.
func fixedCandidate() wireNearbyTree {
	// Deliberately carries fractional seconds, so the fixture proves they are dropped.
	created := time.Date(2026, 8, 9, 18, 41, 46, 832442000, time.UTC)
	address := "1 Main St"
	species := uuid.MustParse("7f3c1d22-5e6a-4b90-8c11-2d3e4f5a6b7c")
	land := "street"
	return candidateFrom(store.NearbyTree{
		ID:          uuid.MustParse("29323be5-1a2b-4c3d-8e4f-5a6b7c8d9e0f"),
		Lat:         37.7601,
		Lon:         -122.505,
		Address:     &address,
		SpeciesID:   &species,
		Placement:   "contributor_placed",
		LandContext: &land,
		CreatedAt:   created,
		UpdatedAt:   created,
		DistanceM:   4.994382259970141,
	})
}

func TestProximityConflictGolden(t *testing.T) {
	conflict := apierr.New(apierr.Conflict, "There is already a tree recorded here.")
	conflict.Detail = map[string]any{"candidates": []wireNearbyTree{fixedCandidate()}}

	recorder := httptest.NewRecorder()
	apierr.Write(recorder, slog.New(slog.NewTextHandler(io.Discard, nil)), conflict)
	compareGolden(t, "proximity_conflict.json", recorder.Body.Bytes())
}

func TestGroveGolden(t *testing.T) {
	visited := time.Date(2026, 8, 9, 18, 41, 46, 832442000, time.UTC)
	hero := uuid.MustParse("8c1cc8a2-ded9-4bd5-ae4f-af2b0174bfb3")
	body := map[string]any{
		"entries": []map[string]any{{
			"tree_uuid":       uuid.MustParse("602aa4b1-1ab6-471a-89ef-c85f5e63a5e2"),
			"last_visited_at": stampOrNil(&visited),
			"is_favorite":     true,
			"record":          wireGroveRecord{Visits: 3, CheckIns: 1, Measurements: 2, CareEvents: 0},
			"hero_photo_id":   &hero,
		}},
		"total": 1,
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	compareGolden(t, "grove.json", encoded)
}

// TestTimestampsCarryNoFractionalSeconds is N12, asserted on the bytes.
//
// `JSONDecoder`'s `.iso8601` uses `ISO8601DateFormatter` with `.withInternetDateTime`, which
// rejects fractional seconds — so Go's default RFC3339**Nano** would have failed to decode on the
// client, on every response carrying a date.
func TestTimestampsCarryNoFractionalSeconds(t *testing.T) {
	encoded, err := json.Marshal(stamp(time.Date(2026, 8, 9, 18, 41, 46, 832442000, time.FixedZone("PDT", -7*3600))))
	if err != nil {
		t.Fatal(err)
	}
	got := string(encoded)
	if got != `"2026-08-10T01:41:46Z"` {
		t.Fatalf("timestamp = %s, want a second-precision UTC RFC3339 string; anything with a "+
			"fractional part fails JSONDecoder's .iso8601 outright", got)
	}
	if regexp.MustCompile(`\.\d`).MatchString(got) {
		t.Error("the timestamp carries fractional seconds")
	}
}

// ── The guards that read the Swift declarations rather than restating them ─────────────────────

// TestTreePlacementMatchesTheSwiftVocabulary is B7's real guard.
//
// The guard it replaces checked `Placement == ""`, which is one way a decoder throws. The way that
// was actually happening is the other one — a value **outside** the vocabulary — and it was
// happening on every candidate, always. `Tree.placement` is non-optional, so `"unknown"` throws the
// whole `Tree`, the whole `[NearbyTree]`, and the whole `ProximityConflict`.
//
// The vocabulary is therefore read off `Tree.swift` rather than restated here, the way
// `internal/apierr` reads `APIError.swift`. A test that declares the answer it checks proves the
// author transcribed it, not that the client accepts it.
func TestTreePlacementMatchesTheSwiftVocabulary(t *testing.T) {
	declared := swiftEnumRawValues(t, "../../../Cypress/Core/Models/Tree.swift", "TreePlacement")
	if len(declared) != 2 {
		t.Fatalf("read %d raw values from TreePlacement, want 2 — the extractor or the enum moved: %v",
			len(declared), declared)
	}

	for _, value := range declared {
		if !treePlacements[value] {
			t.Errorf("TreePlacement declares %q and this service will not accept it", value)
		}
	}
	for value := range treePlacements {
		if !slices.Contains(declared, value) {
			t.Errorf("this service accepts %q, which is not a TreePlacement raw value; "+
				"Tree.placement is non-optional, so it throws the whole Tree", value)
		}
	}
	if !slices.Contains(declared, defaultTreePlacement) {
		t.Errorf("the default placement %q is not a TreePlacement raw value", defaultTreePlacement)
	}

	// And what a candidate actually carries is one of them — the assertion the old guard could not
	// make, because it only asked whether the string was empty.
	candidate := fixedCandidate()
	if !slices.Contains(declared, candidate.Tree.Placement) {
		t.Fatalf("a candidate carries placement %q, which is not one of %v — every candidate would "+
			"fail to decode", candidate.Tree.Placement, declared)
	}
}

// TestLandContextMatchesTheSwiftVocabulary is the same check for the other enum this service echoes.
func TestLandContextMatchesTheSwiftVocabulary(t *testing.T) {
	declared := swiftEnumRawValues(t, "../../../Cypress/Core/Models/CityRecord.swift", "LandContext")
	if len(declared) != 4 {
		t.Fatalf("read %d raw values from LandContext, want 4: %v", len(declared), declared)
	}
	for _, value := range declared {
		if !landContexts[value] {
			t.Errorf("LandContext declares %q and this service will not accept it", value)
		}
	}
	for value := range landContexts {
		if !slices.Contains(declared, value) {
			t.Errorf("this service accepts %q, which is not a LandContext raw value", value)
		}
	}
}

// TestSwiftEnumExtractorIsCalibrated proves the reader before anything is concluded from it.
//
// CLAUDE.md: run the instrument against a case whose answer you already know. An extractor that
// matched nothing would make both guards above pass vacuously.
func TestSwiftEnumExtractorIsCalibrated(t *testing.T) {
	specimen := `
public enum TreeStatus: String, Codable {
    case alive = "alive"
    case deadReported = "dead_reported"
}

public enum TreePlacement: String, Codable, Sendable, Hashable, CaseIterable {
    /// A doc comment that mentions a case = "not_a_case" in prose.
    case gps = "gps"
    case contributorPlaced = "contributor_placed"
}
`
	path := filepath.Join(t.TempDir(), "specimen.swift")
	if err := os.WriteFile(path, []byte(specimen), 0o644); err != nil {
		t.Fatal(err)
	}

	got := swiftEnumRawValues(t, path, "TreePlacement")
	want := []string{"gps", "contributor_placed"}
	if !slices.Equal(got, want) {
		t.Fatalf("the extractor read %v from a specimen whose answer is %v", got, want)
	}
	// It must not bleed into the neighbouring enum.
	if other := swiftEnumRawValues(t, path, "TreeStatus"); !slices.Equal(other, []string{"alive", "dead_reported"}) {
		t.Fatalf("the extractor read %v for TreeStatus", other)
	}
}

var swiftCaseLine = regexp.MustCompile(`(?m)^\s*case\s+\w+\s*=\s*"([a-z_]+)"`)

func swiftEnumRawValues(t *testing.T, path, name string) []string {
	t.Helper()
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v — this guard fails rather than skipping", path, err)
	}
	pattern := fmt.Sprintf(`(?s)public enum %s: String[^{]*\{(.*?)\n\}`, name)
	block := regexp.MustCompile(pattern).FindSubmatch(source)
	if block == nil {
		t.Fatalf("did not find `public enum %s: String` in %s", name, path)
	}
	var values []string
	for _, match := range swiftCaseLine.FindAllSubmatch(block[1], -1) {
		values = append(values, string(match[1]))
	}
	return values
}
