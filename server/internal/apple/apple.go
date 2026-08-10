// Package apple is Sign in with Apple: verifying an identity token, exchanging the authorization
// code, and revoking at deletion.
//
// R72 ruling 2 is why the exchange is here at all. Apple requires an app offering Sign in with
// Apple to call the revocation endpoint when an account is deleted, and `/auth/revoke` needs a
// token that exists only if the authorization code was exchanged at sign-in. So the client sends
// the code, this package exchanges it, and the refresh token is stored against the user — without
// which `DELETE /me` cannot keep the promise RULINGS R3 already ships.
//
// ── The hand-written residue ───────────────────────────────────────────────────────────────────
// The spec's §8.2 survey found that neither candidate ecosystem mints Apple's client secret, and
// that finding is what made the auth argument a wash and tipped R72 to Go. `clientSecret` below is
// that residue: an ES256 JWT this service signs with the `.p8` key, `iss` = Team ID, `sub` = bundle
// id, `aud` = https://appleid.apple.com, six-month maximum expiry. It is written out rather than
// pulled in, because pulling in a JOSE library to mint one token would have added the dependency
// the survey said nobody has.
//
// Everything on the verification side is `coreos/go-oidc`, which refetches on an unknown key id
// behind a single flight — Apple's rotation with no cron — and checks algorithm, issuer, audience
// and expiry.
package apple

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
)

// Issuer is Apple's OIDC issuer.
const Issuer = "https://appleid.apple.com"

// clientSecretLifetime is under Apple's six-month ceiling with room to spare. The secret is minted
// per call rather than cached: it costs one ECDSA signature and a cached one is a credential with
// a lifetime to get wrong.
const clientSecretLifetime = 30 * time.Minute

// Config is everything this package needs, all of it from the environment.
//
// No value here has a default and none is ever written into the repository. A missing one is a
// startup failure (see Validate), not a runtime surprise on the first sign-in.
type Config struct {
	// TeamID is the Apple Developer team (`iss` of the client secret).
	TeamID string
	// KeyID is the `.p8` key's id (`kid` of the client secret header).
	KeyID string
	// PrivateKeyPEM is the `.p8` file's contents, PKCS#8.
	PrivateKeyPEM string
	// BundleID is the audience an identity token must carry, and the client secret's `sub`.
	// `app.cypress.Cypress`, read from `Cypress.xcodeproj`.
	BundleID string
}

// Validate reports the first missing field.
func (c Config) Validate() error {
	switch {
	case c.TeamID == "":
		return errors.New("APPLE_TEAM_ID is not set")
	case c.KeyID == "":
		return errors.New("APPLE_KEY_ID is not set")
	case c.PrivateKeyPEM == "":
		return errors.New("APPLE_PRIVATE_KEY is not set")
	case c.BundleID == "":
		return errors.New("APPLE_BUNDLE_ID is not set")
	}
	return nil
}

// Identity is what a verified identity token says.
type Identity struct {
	// Subject is Apple's stable `sub` for this user and this team. It is the account's identity
	// here: an email can change and, with Hide My Email, was never the person's to begin with.
	Subject string
	Email   string
	// Nonce as presented, for the caller to compare against what the app generated.
	Nonce string
}

// Verifier verifies Apple identity tokens.
type Verifier struct {
	verifier *oidc.IDTokenVerifier
}

// NewVerifier discovers Apple's configuration and pins the audience to the bundle id.
//
// Audience is checked by `oidc.Config.ClientID`; issuer and expiry by the verifier; algorithm by
// `SupportedSigningAlgs`, whose default is RS256 — the only algorithm Apple signs identity tokens
// with. It is named explicitly rather than left to the default, so that a library default moving
// underneath this service is a compile-time-visible change here rather than a silent widening of
// what this endpoint will accept.
func NewVerifier(ctx context.Context, bundleID string) (*Verifier, error) {
	provider, err := oidc.NewProvider(ctx, Issuer)
	if err != nil {
		return nil, fmt.Errorf("discovering Apple's OIDC configuration: %w", err)
	}
	return &Verifier{verifier: provider.Verifier(&oidc.Config{
		ClientID:             bundleID,
		SupportedSigningAlgs: []string{oidc.RS256},
	})}, nil
}

// NewVerifierWithKeySet builds a verifier over a caller-supplied key set and issuer.
//
// This is how the tests verify a token without reaching Apple: a locally-minted RSA key, a local
// JWKS endpoint, and the same `oidc.NewVerifier` the production path ends at. A test that called
// Apple would be testing Apple's uptime, and would pass on a machine with no network by being
// skipped.
func NewVerifierWithKeySet(issuer, bundleID string, keySet oidc.KeySet) *Verifier {
	return &Verifier{verifier: oidc.NewVerifier(issuer, keySet, &oidc.Config{
		ClientID:             bundleID,
		SupportedSigningAlgs: []string{oidc.RS256},
	})}
}

// Verify checks the token and returns what it says.
func (v *Verifier) Verify(ctx context.Context, rawIDToken string) (Identity, error) {
	token, err := v.verifier.Verify(ctx, rawIDToken)
	if err != nil {
		return Identity{}, fmt.Errorf("verifying Apple identity token: %w", err)
	}
	var claims struct {
		Email string `json:"email"`
		Nonce string `json:"nonce"`
	}
	if err := token.Claims(&claims); err != nil {
		return Identity{}, fmt.Errorf("reading identity token claims: %w", err)
	}
	if token.Subject == "" {
		return Identity{}, errors.New("Apple identity token carries no subject")
	}
	return Identity{Subject: token.Subject, Email: claims.Email, Nonce: claims.Nonce}, nil
}

// Client talks to Apple's token endpoints.
type Client struct {
	config   Config
	http     *http.Client
	endpoint string
	now      func() time.Time
}

// NewClient builds a client against Apple's real endpoints.
func NewClient(config Config) *Client {
	return &Client{
		config:   config,
		http:     &http.Client{Timeout: 15 * time.Second},
		endpoint: Issuer,
		now:      time.Now,
	}
}

// WithEndpoint points the client at a different host. Test seam; nothing in production calls it.
func (c *Client) WithEndpoint(endpoint string) *Client {
	clone := *c
	clone.endpoint = strings.TrimSuffix(endpoint, "/")
	return &clone
}

// WithClock replaces the clock used to stamp the client secret. Test seam.
func (c *Client) WithClock(now func() time.Time) *Client {
	clone := *c
	clone.now = now
	return &clone
}

// ExchangeAuthorizationCode trades the code the app forwarded for Apple's refresh token.
//
// The refresh token is the only reason this call exists, and it is stored against the user for
// exactly one purpose: Revoke, at deletion.
func (c *Client) ExchangeAuthorizationCode(ctx context.Context, code string) (refreshToken string, err error) {
	secret, err := c.clientSecret()
	if err != nil {
		return "", err
	}
	form := url.Values{
		"client_id":     {c.config.BundleID},
		"client_secret": {secret},
		"code":          {code},
		"grant_type":    {"authorization_code"},
	}
	body, err := c.post(ctx, "/auth/token", form)
	if err != nil {
		return "", err
	}
	var response struct {
		RefreshToken string `json:"refresh_token"`
		Error        string `json:"error"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return "", fmt.Errorf("decoding Apple's token response: %w", err)
	}
	if response.Error != "" {
		return "", fmt.Errorf("Apple refused the authorization code: %s", response.Error)
	}
	if response.RefreshToken == "" {
		return "", errors.New("Apple returned no refresh token; deletion could not revoke")
	}
	return response.RefreshToken, nil
}

// Revoke calls Apple's revocation endpoint with the stored refresh token.
//
// Called by `DELETE /me`. Apple's endpoint is documented to answer 200 with an empty body on
// success, and it is idempotent for an already-revoked token, so a deletion replayed after a
// crash does not fail on this step.
func (c *Client) Revoke(ctx context.Context, refreshToken string) error {
	secret, err := c.clientSecret()
	if err != nil {
		return err
	}
	form := url.Values{
		"client_id":       {c.config.BundleID},
		"client_secret":   {secret},
		"token":           {refreshToken},
		"token_type_hint": {"refresh_token"},
	}
	_, err = c.post(ctx, "/auth/revoke", form)
	return err
}

func (c *Client) post(ctx context.Context, path string, form url.Values) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+path, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := c.http.Do(request)
	if err != nil {
		return nil, fmt.Errorf("calling Apple %s: %w", path, err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("reading Apple's %s response: %w", path, err)
	}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		// Apple's body on an error is small and carries no user data — it is an OAuth error code.
		return nil, fmt.Errorf("Apple %s returned %d: %s", path, response.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

// clientSecret mints the ES256 JWT Apple authenticates both calls with.
func (c *Client) clientSecret() (string, error) {
	key, err := parsePrivateKey(c.config.PrivateKeyPEM)
	if err != nil {
		return "", err
	}
	now := c.now().UTC()

	header, err := json.Marshal(map[string]string{"alg": "ES256", "kid": c.config.KeyID, "typ": "JWT"})
	if err != nil {
		return "", err
	}
	claims, err := json.Marshal(map[string]any{
		"iss": c.config.TeamID,
		"iat": now.Unix(),
		"exp": now.Add(clientSecretLifetime).Unix(),
		"aud": Issuer,
		"sub": c.config.BundleID,
	})
	if err != nil {
		return "", err
	}

	encoding := base64.RawURLEncoding
	signingInput := encoding.EncodeToString(header) + "." + encoding.EncodeToString(claims)
	digest := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return "", fmt.Errorf("signing Apple client secret: %w", err)
	}

	// JOSE wants the raw pair, each left-padded to the curve's byte length — not the ASN.1
	// sequence `ecdsa.SignASN1` produces. Apple rejects the ASN.1 form with a bare
	// `invalid_client`, which is the same thing it says about a wrong team id, so getting this
	// wrong costs an afternoon rather than an error message.
	const coordinateBytes = 32
	signature := make([]byte, 2*coordinateBytes)
	r.FillBytes(signature[:coordinateBytes])
	s.FillBytes(signature[coordinateBytes:])

	return signingInput + "." + encoding.EncodeToString(signature), nil
}

func parsePrivateKey(pemText string) (*ecdsa.PrivateKey, error) {
	// Fly secrets travel as single-line values, so a `.p8` set with literal `\n` for its newlines
	// is the normal way this arrives rather than an accident. Restore them before parsing; a PEM
	// block with no line breaks decodes to nothing and the error would name the key, not the
	// escaping.
	pemText = strings.ReplaceAll(pemText, `\n`, "\n")
	block, _ := pem.Decode([]byte(pemText))
	if block == nil {
		return nil, errors.New("APPLE_PRIVATE_KEY is not a PEM block")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parsing APPLE_PRIVATE_KEY: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("APPLE_PRIVATE_KEY is a %T, not an ECDSA key", parsed)
	}
	return key, nil
}
