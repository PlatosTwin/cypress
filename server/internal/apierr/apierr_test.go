package apierr

import (
	"encoding/json"
	"log/slog"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// clientSourcePath is `Cypress/Core/APIError.swift`, relative to this package.
//
// The test reads the client's own declaration rather than a copy of it. A hand-maintained fixture
// would agree with this package for exactly as long as somebody remembered to update both, and the
// failure it is guarding against — a code drifting apart on the two sides — is invisible at run
// time: `APIError.Envelope` decodes an unknown code to `.serverError` rather than throwing, so a
// server that renamed one would look like a server having an outage.
const clientSourcePath = "../../../Cypress/Core/APIError.swift"

var (
	caseLine      = regexp.MustCompile(`(?m)^\s*case\s+(\w+)\s*=\s*"([a-z_]+)"`)
	retryableTrue = regexp.MustCompile(`case\s+\.rateLimited,\s*\.serverError:\s*\n\s*return true`)
)

func readClientSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Clean(clientSourcePath))
	if err != nil {
		t.Fatalf("reading the client's APIError.swift: %v\n"+
			"This guard is worthless if it silently skips, so it fails instead. If the file moved, "+
			"move clientSourcePath with it.", err)
	}
	return string(data)
}

// TestTaxonomyParserIsCalibrated proves the extractor before anything is concluded from it.
//
// CLAUDE.md: calibrate the instrument before you trust the reading — "run it against a case whose
// answer you already know". A regex that matched nothing would make every conformance assertion
// below pass vacuously, which is this project's signature failure mode wearing a green tick.
func TestTaxonomyParserIsCalibrated(t *testing.T) {
	// Known answer 1: a hand-written specimen with three cases in the client's exact shape.
	specimen := `
public enum APIError: String, Error {
    case unauthorized = "unauthorized"
    case notFound = "not_found"
    case serverError = "server_error"
}`
	found := caseLine.FindAllStringSubmatch(specimen, -1)
	if len(found) != 3 {
		t.Fatalf("the extractor found %d cases in a specimen with 3; it is not measuring what it claims", len(found))
	}
	if found[1][2] != "not_found" {
		t.Fatalf("the extractor read the raw value as %q, want %q", found[1][2], "not_found")
	}

	// Known answer 2: a specimen with no cases must yield none, so a match is evidence rather than
	// an artifact of the pattern being too loose.
	if got := caseLine.FindAllStringSubmatch("public enum Empty: String {}", -1); len(got) != 0 {
		t.Fatalf("the extractor found %d cases in a specimen with none", len(got))
	}
}

// TestTaxonomyMatchesTheClient is the conformance itself.
func TestTaxonomyMatchesTheClient(t *testing.T) {
	source := readClientSource(t)
	matches := caseLine.FindAllStringSubmatch(source, -1)
	if len(matches) == 0 {
		t.Fatal("found no cases in the client's APIError.swift; the extractor or the file has changed")
	}

	client := map[string]bool{}
	for _, match := range matches {
		client[match[2]] = true
	}

	server := map[string]bool{}
	for _, code := range All {
		server[string(code)] = true
	}

	for code := range client {
		if !server[code] {
			t.Errorf("the client declares %q and this package does not; a server that never sends it "+
				"is fine, but one that cannot name it cannot answer it either", code)
		}
	}
	for code := range server {
		if !client[code] {
			t.Errorf("this package declares %q and the client does not: it would decode to "+
				"server_error, so an outbox item would sit on the backoff over it", code)
		}
	}
	if len(client) != len(All) {
		t.Errorf("the client declares %d codes, this package %d", len(client), len(All))
	}
}

// TestRetryableMatchesTheClient pins the half of the taxonomy that decides whether a queued
// contribution survives.
func TestRetryableMatchesTheClient(t *testing.T) {
	source := readClientSource(t)
	if !retryableTrue.MatchString(source) {
		t.Fatal("the client's `retryable` no longer returns true for exactly rateLimited and " +
			"serverError; this package's table must move with it")
	}
	for _, code := range All {
		want := code == RateLimited || code == ServerError
		if code.Retryable() != want {
			t.Errorf("%s.Retryable() = %v, want %v", code, code.Retryable(), want)
		}
	}
	// `conflict` gets its own assertion because it is the one a reader is most likely to "fix":
	// the proximity dedupe returns it with a candidate list only the person can resolve, so
	// re-sending cannot change the answer.
	if Conflict.Retryable() {
		t.Error("conflict must not be retryable: re-sending would not change the answer")
	}
}

// clientEnvelopeFixture is a body captured from this package and decoded by the client's rules.
//
// `APIError.Envelope.init(from:)` reads a root object with one key, `error`, holding a nested
// object with `code`, `message` and `retryable`. Anything else and the decode throws, which reaches
// a person as a failed sync with no reason attached.
type clientEnvelopeFixture struct {
	Error *struct {
		Code      *string `json:"code"`
		Message   *string `json:"message"`
		Retryable *bool   `json:"retryable"`
	} `json:"error"`
}

func TestEnvelopeDecodesUnderTheClientsRules(t *testing.T) {
	for _, code := range All {
		recorder := httptest.NewRecorder()
		Write(recorder, slog.Default(), New(code, "A sentence."))

		var decoded clientEnvelopeFixture
		if err := json.Unmarshal(recorder.Body.Bytes(), &decoded); err != nil {
			t.Fatalf("%s: body did not parse as JSON: %v", code, err)
		}
		if decoded.Error == nil {
			t.Fatalf("%s: no `error` key; the client's nestedContainer(forKey: .error) would throw", code)
		}
		if decoded.Error.Code == nil {
			t.Fatalf("%s: no `code`; the client decodes it non-optionally and would throw", code)
		}
		if *decoded.Error.Code != string(code) {
			t.Errorf("code = %q, want %q", *decoded.Error.Code, code)
		}
		if decoded.Error.Message == nil || *decoded.Error.Message != "A sentence." {
			t.Errorf("%s: message did not survive", code)
		}
		if decoded.Error.Retryable == nil {
			t.Fatalf("%s: no `retryable`", code)
		}
		if *decoded.Error.Retryable != code.Retryable() {
			t.Errorf("%s: retryable = %v, want %v", code, *decoded.Error.Retryable, code.Retryable())
		}
		if recorder.Code != code.Status() {
			t.Errorf("%s: status = %d, want %d", code, recorder.Code, code.Status())
		}
	}
}

// TestUnclassifiedErrorIsRetryable pins the answer that keeps a contributor's queued item alive
// when this service has a bug.
func TestUnclassifiedErrorIsRetryable(t *testing.T) {
	recorder := httptest.NewRecorder()
	Write(recorder, slog.Default(), errPlain("the pool is closed"))

	var decoded clientEnvelopeFixture
	if err := json.Unmarshal(recorder.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("body did not parse: %v", err)
	}
	if *decoded.Error.Code != string(ServerError) {
		t.Errorf("code = %q, want server_error", *decoded.Error.Code)
	}
	if !*decoded.Error.Retryable {
		t.Error("an unclassified failure must be retryable, or a bug here discards queued work")
	}
	// The cause must not travel. A database error's text is not a person's business, and it is the
	// standard way a table name or a connection string reaches a screen.
	if got := *decoded.Error.Message; got == "the pool is closed" {
		t.Errorf("the internal cause reached the client: %q", got)
	}
}

type errPlain string

func (e errPlain) Error() string { return string(e) }
