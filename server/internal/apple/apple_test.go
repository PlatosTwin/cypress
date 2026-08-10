package apple

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
)

// ── Nothing here touches Apple ─────────────────────────────────────────────────────────────────
//
// A test that fetched `https://appleid.apple.com/auth/keys` would be measuring Apple's uptime and
// this machine's network, and it would pass by being skipped on a machine that had neither. So the
// fixture is a locally-minted RSA key, served from an `httptest` JWKS endpoint, verified through
// the same `oidc.NewVerifier` the production path ends at.

const testBundleID = "app.cypress.Cypress"

type jwksFixture struct {
	key    *rsa.PrivateKey
	keyID  string
	issuer string
	server *httptest.Server
}

func newJWKSFixture(t *testing.T) *jwksFixture {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generating test key: %v", err)
	}
	fixture := &jwksFixture{key: key, keyID: "test-key-1"}

	mux := http.NewServeMux()
	mux.HandleFunc("/keys", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kty": "RSA",
			"kid": fixture.keyID,
			"use": "sig",
			"alg": "RS256",
			"n":   base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
			"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
		}}})
	})
	fixture.server = httptest.NewServer(mux)
	fixture.issuer = fixture.server.URL
	t.Cleanup(fixture.server.Close)
	return fixture
}

func (f *jwksFixture) verifier() *Verifier {
	keySet := oidc.NewRemoteKeySet(context.Background(), f.server.URL+"/keys")
	return NewVerifierWithKeySet(f.issuer, testBundleID, keySet)
}

// mint signs an RS256 identity token with the fixture's key.
func (f *jwksFixture) mint(t *testing.T, claims map[string]any) string {
	t.Helper()
	return f.mintWithHeader(t, map[string]string{"alg": "RS256", "kid": f.keyID, "typ": "JWT"}, claims)
}

func (f *jwksFixture) mintWithHeader(t *testing.T, header map[string]string, claims map[string]any) string {
	t.Helper()
	encoding := base64.RawURLEncoding
	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)
	signingInput := encoding.EncodeToString(headerJSON) + "." + encoding.EncodeToString(claimsJSON)
	digest := sha256.Sum256([]byte(signingInput))
	signature, err := rsa.SignPKCS1v15(rand.Reader, f.key, 5 /* crypto.SHA256 */, digest[:])
	if err != nil {
		t.Fatalf("signing: %v", err)
	}
	return signingInput + "." + encoding.EncodeToString(signature)
}

func validClaims(fixture *jwksFixture) map[string]any {
	now := time.Now()
	return map[string]any{
		"iss":   fixture.issuer,
		"aud":   testBundleID,
		"sub":   "001234.abcdef.5678",
		"iat":   now.Unix(),
		"exp":   now.Add(10 * time.Minute).Unix(),
		"email": "someone@privaterelay.appleid.com",
		"nonce": "the-app-generated-nonce",
	}
}

func TestVerifyAcceptsAWellFormedToken(t *testing.T) {
	fixture := newJWKSFixture(t)
	identity, err := fixture.verifier().Verify(context.Background(), fixture.mint(t, validClaims(fixture)))
	if err != nil {
		t.Fatalf("a well-formed token was rejected: %v", err)
	}
	if identity.Subject != "001234.abcdef.5678" {
		t.Errorf("subject = %q", identity.Subject)
	}
	if identity.Email != "someone@privaterelay.appleid.com" {
		t.Errorf("email = %q", identity.Email)
	}
	if identity.Nonce != "the-app-generated-nonce" {
		t.Errorf("nonce = %q", identity.Nonce)
	}
}

// TestVerifyRejectsTheWrongAudience is the one that matters most.
//
// The audience *is* the check that this token was minted for this app. Without it any Apple
// identity token from any app would sign somebody in here, which is a complete authentication
// bypass that looks exactly like working code.
func TestVerifyRejectsTheWrongAudience(t *testing.T) {
	fixture := newJWKSFixture(t)
	claims := validClaims(fixture)
	claims["aud"] = "com.someone.else.App"

	_, err := fixture.verifier().Verify(context.Background(), fixture.mint(t, claims))
	if err == nil {
		t.Fatal("a token minted for another app was accepted")
	}
	if !strings.Contains(err.Error(), "audience") && !strings.Contains(err.Error(), "aud") {
		t.Errorf("rejected, but not for the audience: %v", err)
	}
}

func TestVerifyRejectsTheWrongIssuer(t *testing.T) {
	fixture := newJWKSFixture(t)
	claims := validClaims(fixture)
	claims["iss"] = "https://accounts.google.com"

	if _, err := fixture.verifier().Verify(context.Background(), fixture.mint(t, claims)); err == nil {
		t.Fatal("a token from another issuer was accepted")
	}
}

func TestVerifyRejectsAnExpiredToken(t *testing.T) {
	fixture := newJWKSFixture(t)
	claims := validClaims(fixture)
	claims["exp"] = time.Now().Add(-time.Hour).Unix()
	claims["iat"] = time.Now().Add(-2 * time.Hour).Unix()

	if _, err := fixture.verifier().Verify(context.Background(), fixture.mint(t, claims)); err == nil {
		t.Fatal("an expired token was accepted")
	}
}

// TestVerifyRejectsAnUnsignedToken pins the algorithm check.
//
// `alg: none` is the canonical JWT forgery, and the reason `SupportedSigningAlgs` is named
// explicitly in NewVerifier rather than left to a library default.
func TestVerifyRejectsAnUnsignedToken(t *testing.T) {
	fixture := newJWKSFixture(t)
	encoding := base64.RawURLEncoding
	headerJSON, _ := json.Marshal(map[string]string{"alg": "none", "typ": "JWT"})
	claimsJSON, _ := json.Marshal(validClaims(fixture))
	forged := encoding.EncodeToString(headerJSON) + "." + encoding.EncodeToString(claimsJSON) + "."

	if _, err := fixture.verifier().Verify(context.Background(), forged); err == nil {
		t.Fatal("an `alg: none` token was accepted")
	}
}

// TestVerifyRejectsAForeignSignature proves the JWKS is actually consulted.
//
// The token is well formed and claims the fixture's key id, but is signed with a different key. A
// verifier that parsed claims without checking the signature would pass every test above and this
// is the one that catches it.
func TestVerifyRejectsAForeignSignature(t *testing.T) {
	fixture := newJWKSFixture(t)
	attacker := newJWKSFixture(t)
	attacker.keyID = fixture.keyID
	forged := attacker.mint(t, validClaims(fixture))

	if _, err := fixture.verifier().Verify(context.Background(), forged); err == nil {
		t.Fatal("a token signed with a key not in the JWKS was accepted")
	}
}

// ── The client secret ──────────────────────────────────────────────────────────────────────────

func testAppleConfig(t *testing.T) Config {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return Config{
		TeamID:        "TEAMID1234",
		KeyID:         "KEYID56789",
		PrivateKeyPEM: string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		BundleID:      testBundleID,
	}
}

// TestClientSecretIsAVerifiableES256JWT checks the residue no library mints.
//
// Every field is Apple's requirement rather than a convention: `iss` is the Team ID, `sub` is the
// bundle id, `aud` is Apple's issuer, and the signature is the raw r||s pair rather than the ASN.1
// sequence — which Apple rejects with a bare `invalid_client`, the same thing it says about a wrong
// team id.
func TestClientSecretIsAVerifiableES256JWT(t *testing.T) {
	config := testAppleConfig(t)
	client := NewClient(config)

	secret, err := client.clientSecret()
	if err != nil {
		t.Fatalf("minting: %v", err)
	}
	parts := strings.Split(secret, ".")
	if len(parts) != 3 {
		t.Fatalf("the secret has %d segments, want 3", len(parts))
	}

	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		t.Fatal(err)
	}
	var header map[string]string
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		t.Fatal(err)
	}
	if header["alg"] != "ES256" {
		t.Errorf("alg = %q, want ES256", header["alg"])
	}
	if header["kid"] != config.KeyID {
		t.Errorf("kid = %q, want %q", header["kid"], config.KeyID)
	}

	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	var claims map[string]any
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		t.Fatal(err)
	}
	if claims["iss"] != config.TeamID {
		t.Errorf("iss = %v, want the Team ID %q", claims["iss"], config.TeamID)
	}
	if claims["sub"] != config.BundleID {
		t.Errorf("sub = %v, want the bundle id %q", claims["sub"], config.BundleID)
	}
	if claims["aud"] != Issuer {
		t.Errorf("aud = %v, want %q", claims["aud"], Issuer)
	}
	expiry, ok := claims["exp"].(float64)
	if !ok {
		t.Fatal("no exp")
	}
	if until := time.Until(time.Unix(int64(expiry), 0)); until <= 0 || until > 6*30*24*time.Hour {
		t.Errorf("exp is %v away; Apple's ceiling is six months and a past one is useless", until)
	}

	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatal(err)
	}
	if len(signature) != 64 {
		t.Fatalf("the signature is %d bytes, want the 64-byte r||s pair — an ASN.1 signature here "+
			"reaches Apple as a bare invalid_client", len(signature))
	}

	// And it verifies against the public half, which is what "signed" has to mean.
	block, _ := pem.Decode([]byte(config.PrivateKeyPEM))
	parsed, _ := x509.ParsePKCS8PrivateKey(block.Bytes)
	private := parsed.(*ecdsa.PrivateKey)
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(signature[:32])
	s := new(big.Int).SetBytes(signature[32:])
	if !ecdsa.Verify(&private.PublicKey, digest[:], r, s) {
		t.Fatal("the client secret does not verify against its own key")
	}
}

// TestPrivateKeyAcceptsFlattenedNewlines covers how a secret store actually delivers a `.p8`.
func TestPrivateKeyAcceptsFlattenedNewlines(t *testing.T) {
	config := testAppleConfig(t)
	flattened := strings.ReplaceAll(config.PrivateKeyPEM, "\n", `\n`)
	if _, err := parsePrivateKey(flattened); err != nil {
		t.Fatalf("a PEM whose newlines were flattened to \\n was rejected: %v", err)
	}
}

func TestValidateNamesTheMissingVariable(t *testing.T) {
	for name, config := range map[string]Config{
		"APPLE_TEAM_ID":     {KeyID: "k", PrivateKeyPEM: "p", BundleID: "b"},
		"APPLE_KEY_ID":      {TeamID: "t", PrivateKeyPEM: "p", BundleID: "b"},
		"APPLE_PRIVATE_KEY": {TeamID: "t", KeyID: "k", BundleID: "b"},
		"APPLE_BUNDLE_ID":   {TeamID: "t", KeyID: "k", PrivateKeyPEM: "p"},
	} {
		err := config.Validate()
		if err == nil {
			t.Errorf("a config missing %s validated", name)
			continue
		}
		if !strings.Contains(err.Error(), name) {
			t.Errorf("missing %s reported as %q; the message has to name the variable to set", name, err)
		}
	}
}

// ── Exchange and revoke ────────────────────────────────────────────────────────────────────────

func TestExchangeStoresTheRefreshTokenDeletionNeeds(t *testing.T) {
	var seen url.Values
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		seen = r.PostForm
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"refresh_token":"apple-refresh-abc","access_token":"a","id_token":"b"}`))
	}))
	defer fake.Close()

	client := NewClient(testAppleConfig(t)).WithEndpoint(fake.URL)
	token, err := client.ExchangeAuthorizationCode(context.Background(), "the-code")
	if err != nil {
		t.Fatalf("exchanging: %v", err)
	}
	if token != "apple-refresh-abc" {
		t.Errorf("refresh token = %q", token)
	}
	if seen.Get("grant_type") != "authorization_code" {
		t.Errorf("grant_type = %q", seen.Get("grant_type"))
	}
	if seen.Get("code") != "the-code" {
		t.Errorf("code = %q", seen.Get("code"))
	}
	if seen.Get("client_id") != testBundleID {
		t.Errorf("client_id = %q", seen.Get("client_id"))
	}
	if seen.Get("client_secret") == "" {
		t.Error("no client_secret; Apple authenticates both calls with it")
	}
}

// TestExchangeWithoutARefreshTokenIsAFailure pins R72 ruling 2's consequence.
//
// A 200 carrying no refresh token is the shape that would otherwise pass silently and leave an
// account `DELETE /me` cannot revoke — discovered at deletion, where it cannot be fixed.
func TestExchangeWithoutARefreshTokenIsAFailure(t *testing.T) {
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"a","id_token":"b"}`))
	}))
	defer fake.Close()

	client := NewClient(testAppleConfig(t)).WithEndpoint(fake.URL)
	if _, err := client.ExchangeAuthorizationCode(context.Background(), "the-code"); err == nil {
		t.Fatal("an exchange that returned no refresh token was treated as a success")
	}
}

func TestRevokeSendsTheStoredToken(t *testing.T) {
	var seen url.Values
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		seen = r.PostForm
		w.WriteHeader(http.StatusOK)
	}))
	defer fake.Close()

	client := NewClient(testAppleConfig(t)).WithEndpoint(fake.URL)
	if err := client.Revoke(context.Background(), "apple-refresh-abc"); err != nil {
		t.Fatalf("revoking: %v", err)
	}
	if seen.Get("token") != "apple-refresh-abc" {
		t.Errorf("token = %q", seen.Get("token"))
	}
	if seen.Get("token_type_hint") != "refresh_token" {
		t.Errorf("token_type_hint = %q", seen.Get("token_type_hint"))
	}
}
