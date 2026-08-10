package storage

import (
	"net/url"
	"strings"
	"testing"
	"time"
)

// TestAWSPublishedQueryStringVector is the only assertion here whose expected value comes from
// outside this repository.
//
// AWS documents a worked example of SigV4 query-string signing ("Authenticating Requests: Using
// Query Parameters"): the well-known example credentials, `us-east-1`, `s3`, `20130524T000000Z`, a
// 86400-second expiry, `GET` on `examplebucket`/`test.txt` in virtual-host form, with
// `UNSIGNED-PAYLOAD`. The signature it publishes is the constant below.
//
// This matters because R72 priced the stack partly on writing SigV4 out instead of importing the
// AWS SDK, and the corresponding cost is a test. A signature is either exactly right or opaquely
// wrong — Tigris answers `SignatureDoesNotMatch` and tells you nothing about which of the nine
// inputs you mis-transcribed — so a test that recomputed the expectation with the same code would
// only prove the code agrees with itself.
func TestAWSPublishedQueryStringVector(t *testing.T) {
	const publishedSignature = "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"

	signed := signQuery(signInput{
		Method:          "GET",
		Scheme:          "https",
		Host:            "examplebucket.s3.amazonaws.com",
		CanonicalURI:    "/test.txt",
		AccessKeyID:     "AKIAIOSFODNN7EXAMPLE",
		SecretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
		Region:          "us-east-1",
		Now:             time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC),
		Lifetime:        86400 * time.Second,
	})

	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatalf("the signed URL does not parse: %v", err)
	}
	got := parsed.Query().Get("X-Amz-Signature")
	if got != publishedSignature {
		t.Fatalf("signature = %s\nwant       %s\n(AWS's published query-string example; a mismatch "+
			"means the canonical request, the scope or the signing key is mis-transcribed, and "+
			"Tigris would report only SignatureDoesNotMatch)", got, publishedSignature)
	}
}

func testPresigner(t *testing.T) *Presigner {
	t.Helper()
	return NewPresigner(Config{
		AccessKeyID:     "AKIAIOSFODNN7EXAMPLE",
		SecretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
		Endpoint:        "https://fly.storage.tigris.dev",
		Region:          "auto",
		Bucket:          "cypress-cities",
	}).WithClock(func() time.Time { return time.Date(2026, 8, 9, 12, 0, 0, 0, time.UTC) })
}

// TestPresignedURLsAreStableAndDistinctPerMethod pins the two things a caller depends on.
func TestPresignedURLsAreStableAndDistinctPerMethod(t *testing.T) {
	presigner := testPresigner(t)

	put, err := presigner.PresignPut("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	get, err := presigner.PresignGet("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}

	// Deterministic under a fixed clock: a signature that moved between two identical calls would
	// mean something unrepeatable is in the canonical request.
	again, err := presigner.PresignPut("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if put != again {
		t.Error("two identical PUT presigns under a fixed clock differ")
	}

	// The method is signed, so a PUT URL cannot be replayed as a GET.
	if signatureOf(t, put) == signatureOf(t, get) {
		t.Error("PUT and GET share a signature; the method is not in the canonical request, and a " +
			"presigned upload target would double as a read")
	}
}

// TestPathStyleKeepsTheSignedHostEqualToTheEndpoint pins the addressing choice.
func TestPathStyleKeepsTheSignedHostEqualToTheEndpoint(t *testing.T) {
	signed, err := testPresigner(t).PresignPut("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Host != "fly.storage.tigris.dev" {
		t.Errorf("host = %q, want the configured endpoint's host", parsed.Host)
	}
	if parsed.Path != "/cypress-cities/photos/abc.jpg" {
		t.Errorf("path = %q, want path-style /bucket/key", parsed.Path)
	}
	if parsed.Query().Get("X-Amz-SignedHeaders") != "host" {
		t.Errorf("signed headers = %q", parsed.Query().Get("X-Amz-SignedHeaders"))
	}
}

// TestKeyAndExpiryChangeTheSignature is the negative control for the vector above.
//
// A signing function that ignored its inputs would still match a golden vector computed with those
// same inputs. This is what says the inputs are actually reaching the signature.
func TestKeyAndExpiryChangeTheSignature(t *testing.T) {
	presigner := testPresigner(t)

	base, err := presigner.PresignPut("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	otherKey, err := presigner.PresignPut("photos/def.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	otherExpiry, err := presigner.PresignPut("photos/abc.jpg", 31*time.Minute)
	if err != nil {
		t.Fatal(err)
	}

	if signatureOf(t, base) == signatureOf(t, otherKey) {
		t.Error("two different object keys signed identically")
	}
	if signatureOf(t, base) == signatureOf(t, otherExpiry) {
		t.Error("two different expiries signed identically")
	}

	later := presigner.WithClock(func() time.Time { return time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC) })
	otherDay, err := later.PresignPut("photos/abc.jpg", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if signatureOf(t, base) == signatureOf(t, otherDay) {
		t.Error("two different days signed identically; the credential scope is not reaching the key")
	}
}

func TestPresignRefusesAnIncompleteConfig(t *testing.T) {
	for name, config := range map[string]Config{
		"AWS_ACCESS_KEY_ID":     {SecretAccessKey: "s", Endpoint: "https://e", Region: "r", Bucket: "b"},
		"AWS_SECRET_ACCESS_KEY": {AccessKeyID: "a", Endpoint: "https://e", Region: "r", Bucket: "b"},
		"AWS_ENDPOINT_URL_S3":   {AccessKeyID: "a", SecretAccessKey: "s", Region: "r", Bucket: "b"},
		"AWS_REGION":            {AccessKeyID: "a", SecretAccessKey: "s", Endpoint: "https://e", Bucket: "b"},
		"BUCKET_NAME":           {AccessKeyID: "a", SecretAccessKey: "s", Endpoint: "https://e", Region: "r"},
	} {
		_, err := NewPresigner(config).PresignPut("photos/a.jpg", time.Minute)
		if err == nil {
			t.Errorf("a config missing %s presigned anyway", name)
			continue
		}
		if !strings.Contains(err.Error(), name) {
			t.Errorf("missing %s reported as %q; the message has to name the variable", name, err)
		}
	}
}

func signatureOf(t *testing.T, signed string) string {
	t.Helper()
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	return parsed.Query().Get("X-Amz-Signature")
}
