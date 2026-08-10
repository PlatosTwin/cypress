package tokens

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func testSigner(t *testing.T) *Signer {
	t.Helper()
	signer, err := NewSigner([]byte("a-test-signing-key-of-at-least-32-bytes"))
	if err != nil {
		t.Fatal(err)
	}
	return signer
}

func TestMintAndVerifyRoundTrip(t *testing.T) {
	signer := testSigner(t)
	token, err := signer.Mint(SubjectUser, "the-user", "the-session", AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := signer.Verify(token)
	if err != nil {
		t.Fatalf("a freshly minted token did not verify: %v", err)
	}
	if claims.Subject != SubjectUser || claims.ID != "the-user" || claims.SessionID != "the-session" {
		t.Errorf("claims round-tripped as %+v", claims)
	}
}

// TestATamperedPayloadDoesNotVerify is the whole point of signing them.
//
// The payload is base64 of readable JSON, so anybody holding a token can rewrite the subject. The
// signature is what stops that being a privilege escalation, and this is the assertion that proves
// the signature is checked rather than merely attached.
func TestATamperedPayloadDoesNotVerify(t *testing.T) {
	signer := testSigner(t)
	token, err := signer.Mint(SubjectUser, "the-user", "the-session", AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}
	payload, signature, _ := strings.Cut(token, ".")

	forged, err := signer.Mint(SubjectUser, "somebody-else", "the-session", AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}
	forgedPayload, _, _ := strings.Cut(forged, ".")

	// Somebody else's payload, this token's signature.
	if _, err := signer.Verify(forgedPayload + "." + signature); !errors.Is(err, ErrMalformed) {
		t.Fatalf("a token with a swapped payload verified as %v", err)
	}
	_ = payload
}

func TestAForeignKeyDoesNotVerify(t *testing.T) {
	mine := testSigner(t)
	theirs, err := NewSigner([]byte("a-different-key-also-at-least-32-bytes"))
	if err != nil {
		t.Fatal(err)
	}
	token, err := theirs.Mint(SubjectUser, "the-user", "s", AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := mine.Verify(token); !errors.Is(err, ErrMalformed) {
		t.Fatalf("a token signed with another key verified as %v", err)
	}
}

func TestExpiryIsReportedDistinctly(t *testing.T) {
	signer := testSigner(t)
	past := signer.WithClock(func() time.Time { return time.Now().Add(-time.Hour) })
	token, err := past.Mint(SubjectUser, "the-user", "s", AccessTokenLifetime)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := signer.Verify(token); !errors.Is(err, ErrExpired) {
		t.Fatalf("an expired token reported %v, want ErrExpired — the caller distinguishes "+
			"`your session lapsed` from `that is not a token`", err)
	}
}

// TestShortKeysAreRefused stops a deploy that set the variable to nothing from minting forgeable
// sessions and looking healthy doing it.
func TestShortKeysAreRefused(t *testing.T) {
	for _, key := range []string{"", "short", strings.Repeat("x", 31)} {
		if _, err := NewSigner([]byte(key)); err == nil {
			t.Errorf("a %d-byte signing key was accepted", len(key))
		}
	}
}

func TestLifetimesMatchTheSpec(t *testing.T) {
	if AccessTokenLifetime != 15*time.Minute {
		t.Errorf("access token lifetime = %v, want 15m (spec §5.8)", AccessTokenLifetime)
	}
	if RefreshTokenLifetime != 60*24*time.Hour {
		t.Errorf("refresh token lifetime = %v, want 60 days (spec §5.8)", RefreshTokenLifetime)
	}
}

func TestOpaqueSecretsAreDistinctAndHashStably(t *testing.T) {
	first, firstHash, err := NewOpaque()
	if err != nil {
		t.Fatal(err)
	}
	second, _, err := NewOpaque()
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatal("two opaque secrets collided")
	}
	if !EqualHash(firstHash, HashOpaque(first)) {
		t.Fatal("a secret does not hash to its own stored hash")
	}
	if EqualHash(firstHash, HashOpaque(second)) {
		t.Fatal("two different secrets hash the same")
	}
}
