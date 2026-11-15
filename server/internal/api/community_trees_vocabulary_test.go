package api

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// ── The seams this round adds between the two halves, read off the Swift source ────────────────
//
// `TestTheDisputeTreeSourcesMatchTheSwiftVocabulary`'s pattern: the vocabulary is read from the
// client's *text* in this repository rather than restated, because a test that declares the answer
// it checks proves only that its author transcribed it. Nothing here compiles Swift, so each of
// these sees a raw value renamed, added or removed — and is blind to what a built
// client actually puts on the wire, which is the Swift half of the fixture test's job (C1).
//
// No harness: these must not skip on a machine with no Postgres.

// kindsAwaitingTheirClient are the kinds this service accepts whose `OutboxItem.Kind` case the
// client has not declared yet. It is `kindsAwaitingTheirMigration`'s arrangement pointed the other
// way: the service ships first (S1 and S2 deploy before any client PR merges, so a TestFlight build
// can never queue a kind the service refuses), and C1 adds the cases. The value is the case C1 must
// declare, **name and raw value both**, and the test below holds C1 to it the moment it lands.
var kindsAwaitingTheirClient = map[string]string{
	"location_correction": "locationCorrection",
	"tree_withdrawal":     "treeWithdrawal",
}

// TestTheOutboxKindsMatchTheSwiftVocabulary holds `syncKinds` to `OutboxItem.Kind`.
//
// Both directions. A Swift case this service refuses is `validation_failed` on the first attempt,
// never retried. A kind this service accepts that no client case declares is either a kind awaiting
// C1 — listed above, and checked for its spelling the day it arrives — or dead.
//
// `syncKinds` is in turn held to the migrations' CHECK by `TestSyncAcceptsEveryDeclaredContributionKind`,
// so Swift → `syncKinds` → CHECK is one chain.
func TestTheOutboxKindsMatchTheSwiftVocabulary(t *testing.T) {
	declared := swiftNestedEnumCases(t, "../../../Cypress/Core/Models/OutboxItem.swift", "Kind")
	if len(declared) < 19 {
		t.Fatalf("read %d cases from OutboxItem.Kind, which has at least 19 — the extractor or the enum moved: %v",
			len(declared), declared)
	}
	raws := map[string]string{}
	for name, raw := range declared {
		raws[raw] = name
		if !syncKinds[raw] {
			t.Errorf("OutboxItem.Kind.%s = %q and POST /sync refuses it: every such item fails "+
				"validation_failed on its first attempt and is never retried", name, raw)
		}
	}
	for kind := range syncKinds {
		if _, ok := raws[kind]; ok {
			continue
		}
		if caseName, awaited := kindsAwaitingTheirClient[kind]; awaited {
			t.Logf("`%s` is accepted ahead of its client case (C1 declares OutboxItem.Kind.%s = %q)", kind, caseName, kind)
			continue
		}
		t.Errorf("POST /sync accepts %q, which no OutboxItem.Kind case declares — nothing can send it", kind)
	}
	// The day C1 lands, the case it declared must be the one pinned here, under the raw value the
	// service reads. A case with the right name and another raw value is the R79 defect again.
	for kind, caseName := range kindsAwaitingTheirClient {
		if raw, ok := declared[caseName]; ok && raw != kind {
			t.Errorf("OutboxItem.Kind.%s = %q; the service reads %q", caseName, raw, kind)
		}
		if _, ok := raws[kind]; ok {
			t.Logf("`%s` is declared by the client now, so its kindsAwaitingTheirClient entry excuses nothing and can be deleted", kind)
		}
	}
}

// TestTheSwiftReadersAreCalibrated proves the reader against a specimen whose answer is known.
// Without it the test above passes vacuously on a reader that matches nothing.
func TestTheSwiftReadersAreCalibrated(t *testing.T) {
	specimen := `
public struct Other: CoreEntity {
    public enum Kind: String, Codable {
        case wrong = "wrong"
    }
}

public struct OutboxItem: CoreEntity {
    /// A doc comment that mentions case decoy = "not_a_case" in prose.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case visit = "visit"
        /// case decoy = "not_a_case", in a doc comment inside the body.
        case addTree = "add_tree"

        public var treatment: Int {
            switch self {
            case .visit: return 1
            case .addTree: return 2
            }
        }
    }

    public let kind: Kind
}
`
	path := filepath.Join(t.TempDir(), "specimen.swift")
	if err := os.WriteFile(path, []byte(specimen), 0o644); err != nil {
		t.Fatal(err)
	}
	got := swiftNestedEnumCases(t, path, "Kind")
	want := map[string]string{"visit": "visit", "addTree": "add_tree"}
	if len(got) != len(want) {
		t.Fatalf("read %v from a specimen whose answer is %v", got, want)
	}
	for name, raw := range want {
		if got[name] != raw {
			t.Fatalf("read %v from a specimen whose answer is %v", got, want)
		}
	}
}

var swiftNamedCaseLine = regexp.MustCompile(`^\s*case\s+(\w+)\s*=\s*"([^"]+)"`)

// swiftNestedEnumCases reads `case name = "raw"` lines out of the **last** `enum <name>: String`
// declared inside `struct OutboxItem` — or, in general, the enum declared after the line
// `struct OutboxItem`, ending at the closing brace at the declaration's own indentation. Nested
// enums close on an indented brace, which `swiftEnumRawValues`' column-zero rule cannot see.
func swiftNestedEnumCases(t *testing.T, path, name string) map[string]string {
	t.Helper()
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v — this guard fails rather than skipping", path, err)
	}
	lines := strings.Split(string(source), "\n")
	declaration := regexp.MustCompile(fmt.Sprintf(`^(\s*)(public\s+)?enum %s: String\b`, name))
	insideOutboxItem := false
	for i, line := range lines {
		if strings.Contains(line, "struct OutboxItem") {
			insideOutboxItem = true
		}
		if !insideOutboxItem {
			continue
		}
		match := declaration.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		closing := match[1] + "}"
		cases := map[string]string{}
		for _, body := range lines[i+1:] {
			if strings.TrimRight(body, " \t\r") == closing {
				return cases
			}
			if found := swiftNamedCaseLine.FindStringSubmatch(body); found != nil {
				cases[found[1]] = found[2]
			}
		}
		t.Fatalf("enum %s in %s never closes at its own indentation", name, path)
	}
	t.Fatalf("did not find `enum %s: String` inside `struct OutboxItem` in %s", name, path)
	return nil
}
