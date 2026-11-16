package api

import (
	"os"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// The You tab's "Share my tree records" row sends `POST /devices/claim` with a body the client
// builds in `AuthClient.LicenseAcceptanceRequest`. `decodeBody` refuses an unknown field, so a key
// renamed on either side turns every later agreement into `validation_failed`, which the phone shows
// as "That did not go through." with nothing to say why. This test reads the client's key names and
// compares them with the json tags of `claimRequest`.

// licenseAcceptanceStruct finds the client's request type, up to its closing brace at the same
// four-space indent.
var licenseAcceptanceStruct = regexp.MustCompile(`(?s)\n    struct LicenseAcceptanceRequest: Encodable \{\n(.*?)\n    \}\n`)

// codingKeyRawValue reads `case name = "raw"` lines. A case with no raw value would encode under
// its own name; none exists in this type, and the count check below catches one being added.
var codingKeyRawValue = regexp.MustCompile(`(?m)^\s*case \w+ = "([^"]+)"\s*$`)
var codingKeyCase = regexp.MustCompile(`(?m)^\s*case \w+`)

// clientLicenseAcceptanceKeys returns the raw key names of the client's request type, sorted.
func clientLicenseAcceptanceKeys(t *testing.T, source string) []string {
	t.Helper()
	blocks := licenseAcceptanceStruct.FindAllStringSubmatch(source, -1)
	if len(blocks) != 1 {
		t.Fatalf("found %d LicenseAcceptanceRequest declarations, want exactly 1: the extractor is not "+
			"reading what it thinks it is", len(blocks))
	}
	block := blocks[0][1]
	var keys []string
	for _, match := range codingKeyRawValue.FindAllStringSubmatch(block, -1) {
		keys = append(keys, match[1])
	}
	if cases := len(codingKeyCase.FindAllString(block, -1)); cases != len(keys) {
		t.Fatalf("LicenseAcceptanceRequest has %d coding-key cases but %d raw values: a case without a "+
			"raw value is not read here", cases, len(keys))
	}
	sort.Strings(keys)
	return keys
}

// jsonFieldNames returns the json names of a struct type's fields, sorted.
func jsonFieldNames(value any) []string {
	kind := reflect.TypeOf(value)
	var names []string
	for i := 0; i < kind.NumField(); i++ {
		tag := kind.Field(i).Tag.Get("json")
		name, _, _ := strings.Cut(tag, ",")
		if name == "" || name == "-" {
			continue
		}
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// TestTheClientsLicenseAcceptanceBodyMatchesClaimRequest: the keys the phone sends to agree later
// are exactly the fields `claimDevice` decodes.
func TestTheClientsLicenseAcceptanceBodyMatchesClaimRequest(t *testing.T) {
	// Calibration first: the extractor reads a specimen whose answer is known, including a nested
	// type after the keys, and the reflection reads a struct whose tags are known.
	specimen := "\n    struct LicenseAcceptanceRequest: Encodable {\n" +
		"        let a: UUID\n" +
		"        enum CodingKeys: String, CodingKey {\n" +
		"            case a = \"alpha\"\n" +
		"            case b = \"beta_gamma\"\n" +
		"        }\n" +
		"    }\n" +
		"    struct Other: Encodable {\n" +
		"            case c = \"not_this\"\n" +
		"    }\n"
	if got := clientLicenseAcceptanceKeys(t, specimen); !reflect.DeepEqual(got, []string{"alpha", "beta_gamma"}) {
		t.Fatalf("the extractor read %v from the specimen, want [alpha beta_gamma]", got)
	}
	type tagged struct {
		A string `json:"alpha"`
		B string `json:"beta_gamma,omitempty"`
		C string `json:"-"`
	}
	if got := jsonFieldNames(tagged{}); !reflect.DeepEqual(got, []string{"alpha", "beta_gamma"}) {
		t.Fatalf("the reflection read %v from the specimen, want [alpha beta_gamma]", got)
	}

	source, err := os.ReadFile("../../../Cypress/Data/Auth/AuthClient.swift")
	if err != nil {
		t.Fatal(err)
	}
	client := clientLicenseAcceptanceKeys(t, string(source))
	server := jsonFieldNames(claimRequest{})
	if !reflect.DeepEqual(client, server) {
		t.Fatalf("the phone sends %v to POST /devices/claim and claimRequest decodes %v; decodeBody "+
			"refuses an unknown field, so every later license agreement would fail", client, server)
	}
}
