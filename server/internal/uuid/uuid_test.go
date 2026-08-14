package uuid

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestParseAcceptsBothSpellingsTheClientEmits is the reason this type is case-insensitive.
//
// A UUID reaches the client's own tables by two routes — `SQLiteValue`'s uppercase `uuidString` and
// `JSONEncoder`'s lowercase — which is why `AppSchema` v13 declares `COLLATE NOCASE` on the
// tombstone's key. The same two spellings reach this service, and the idempotency guarantee would
// otherwise turn on them agreeing.
func TestParseAcceptsBothSpellingsTheClientEmits(t *testing.T) {
	const lower = "3f2b1a4c-5d6e-4f70-8a9b-0c1d2e3f4a5b"
	upper := strings.ToUpper(lower)

	fromLower, err := Parse(lower)
	if err != nil {
		t.Fatalf("lowercase: %v", err)
	}
	fromUpper, err := Parse(upper)
	if err != nil {
		t.Fatalf("uppercase: %v", err)
	}
	if fromLower != fromUpper {
		t.Fatal("the two spellings parsed to different values; a replay would not dedupe")
	}
	if fromLower.String() != lower {
		t.Errorf("String() = %q, want the canonical lowercase %q", fromLower.String(), lower)
	}
}

func TestParseRejectsMalformedInput(t *testing.T) {
	for name, input := range map[string]string{
		"empty":         "",
		"too short":     "3f2b1a4c-5d6e-4f70-8a9b-0c1d2e3f4a5",
		"too long":      "3f2b1a4c-5d6e-4f70-8a9b-0c1d2e3f4a5bb",
		"no hyphens":    "3f2b1a4c5d6e4f708a9b0c1d2e3f4a5b",
		"wrong hyphens": "3f2b1a4c5-d6e-4f70-8a9b-0c1d2e3f4a5b",
		"non-hex":       "zzzzzzzz-5d6e-4f70-8a9b-0c1d2e3f4a5b",
		"sql injection": "'; DROP TABLE users; --------------",
	} {
		if _, err := Parse(input); err == nil {
			t.Errorf("%s (%q) parsed", name, input)
		}
	}
}

func TestNewIsVersion4AndDistinct(t *testing.T) {
	seen := map[UUID]bool{}
	for i := 0; i < 1000; i++ {
		value := New()
		if seen[value] {
			t.Fatalf("collision after %d values", i)
		}
		seen[value] = true
		if version := value[6] >> 4; version != 4 {
			t.Fatalf("version nibble = %d, want 4", version)
		}
		if variant := value[8] >> 6; variant != 0b10 {
			t.Fatalf("variant bits = %b, want 10", variant)
		}
	}
}

func TestJSONRoundTrip(t *testing.T) {
	original := New()
	encoded, err := json.Marshal(original)
	if err != nil {
		t.Fatal(err)
	}
	if string(encoded) != `"`+original.String()+`"` {
		t.Errorf("encoded as %s, want the quoted canonical form", encoded)
	}
	var decoded UUID
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded != original {
		t.Fatal("the value did not survive a JSON round trip")
	}
}

func TestUnmarshalRefusesAMalformedString(t *testing.T) {
	var decoded UUID
	if err := json.Unmarshal([]byte(`"not-a-uuid"`), &decoded); err == nil {
		t.Fatal("a malformed UUID decoded; it would reach a query as the zero value")
	}
}

func TestNilIsRecognizable(t *testing.T) {
	if !Nil.IsNil() {
		t.Fatal("Nil does not report itself as nil")
	}
	if New().IsNil() {
		t.Fatal("a minted UUID reports itself as nil")
	}
}
