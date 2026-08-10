// Package tokens mints and verifies the two credentials this service issues itself.
//
// **Access token** — a compact HMAC-SHA256 bearer, 15 minutes (spec §5.8). Self-describing so a
// read route costs no database round trip to authorize. Minted and verified here with `crypto/hmac`
// rather than a JWT library: the service verifies exactly one third-party token format (Apple's,
// which `coreos/go-oidc` owns) and mints exactly two of its own, and R72 prices the stack at two
// direct dependencies. A general-purpose JOSE parser is attack surface for parsing algorithms
// nobody here uses.
//
// **Refresh and device tokens** — 32 opaque random bytes, 60 days and rotating for the refresh
// (spec §5.8). Opaque because they are checked against a row anyway: rotation, revocation and
// `DELETE /me` all need the row, so signing them would buy nothing and would make a stolen one
// valid until its own expiry. Only the SHA-256 hash is stored, so a database copy is not a set of
// live sessions.
package tokens

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// AccessTokenLifetime is spec §5.8's 15 minutes.
const AccessTokenLifetime = 15 * time.Minute

// RefreshTokenLifetime is spec §5.8's 60 days.
//
// It is long for a reason specific to this app, recorded so nobody shortens it as a tidy-up:
// `APIError.unauthorized.retryable` is false and `OutboxRetryPolicy.nextState` reads exactly that,
// so a session that lapses between drains converts a whole queue to terminal failures (ERRATA
// E261 §3). The transport's refresh-and-replay is the fix; this number is what keeps the refresh
// itself available to a phone that was in a drawer for a month.
const RefreshTokenLifetime = 60 * 24 * time.Hour

// DeviceTokenLifetime is the anonymous device credential's life.
//
// It is not an attestation and does not claim to be (spec §5.8) — a reinstall mints a new one and
// nothing stops that. It exists so D9's anonymous queue can drain before there is an account, and
// the defense against a flood is the rate limiter, not this.
const DeviceTokenLifetime = 365 * 24 * time.Hour

// Subject is what an access token authorizes.
type Subject string

const (
	// SubjectUser is a signed-in account.
	SubjectUser Subject = "user"
	// SubjectDevice is an installation with no account: it may send items carrying a deviceID and
	// no userID, and nothing else.
	SubjectDevice Subject = "device"
)

// Claims is the access token body.
type Claims struct {
	Subject Subject `json:"sub_kind"`
	// ID is the user id or the device id, per Subject.
	ID string `json:"sub"`
	// SessionID ties a user access token to the refresh row it came from, so revoking the session
	// revokes the ability to mint more.
	SessionID string `json:"sid,omitempty"`
	IssuedAt  int64  `json:"iat"`
	ExpiresAt int64  `json:"exp"`
}

// ErrExpired is returned when a token verified cleanly but is past its expiry.
var ErrExpired = errors.New("token expired")

// ErrMalformed is returned when a token is not this service's shape or does not verify.
var ErrMalformed = errors.New("token malformed or signature invalid")

// Signer mints and verifies access tokens under one HMAC key.
type Signer struct {
	key []byte
	now func() time.Time
}

// NewSigner requires at least 32 bytes of key material.
//
// The length is checked rather than assumed because the key arrives from an environment variable,
// and a deploy that sets it to the empty string would otherwise produce a service that mints
// forgeable sessions and starts up perfectly happily.
func NewSigner(key []byte) (*Signer, error) {
	if len(key) < 32 {
		return nil, fmt.Errorf("session signing key must be at least 32 bytes, got %d", len(key))
	}
	return &Signer{key: key, now: time.Now}, nil
}

// WithClock replaces the signer's clock. Test seam.
func (s *Signer) WithClock(now func() time.Time) *Signer {
	return &Signer{key: s.key, now: now}
}

var b64 = base64.RawURLEncoding

// Mint returns a compact `payload.signature` bearer token.
func (s *Signer) Mint(subject Subject, id, sessionID string, lifetime time.Duration) (string, error) {
	now := s.now().UTC()
	claims := Claims{
		Subject:   subject,
		ID:        id,
		SessionID: sessionID,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(lifetime).Unix(),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	encoded := b64.EncodeToString(payload)
	return encoded + "." + s.sign(encoded), nil
}

// Verify checks the signature first and the expiry second, and the order matters: an unsigned
// token's claimed expiry is not a fact about anything.
func (s *Signer) Verify(token string) (Claims, error) {
	encoded, signature, ok := strings.Cut(token, ".")
	if !ok {
		return Claims{}, ErrMalformed
	}
	if !hmac.Equal([]byte(signature), []byte(s.sign(encoded))) {
		return Claims{}, ErrMalformed
	}
	payload, err := b64.DecodeString(encoded)
	if err != nil {
		return Claims{}, ErrMalformed
	}
	var claims Claims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return Claims{}, ErrMalformed
	}
	if claims.ID == "" || (claims.Subject != SubjectUser && claims.Subject != SubjectDevice) {
		return Claims{}, ErrMalformed
	}
	if s.now().UTC().Unix() >= claims.ExpiresAt {
		return claims, ErrExpired
	}
	return claims, nil
}

func (s *Signer) sign(encoded string) string {
	mac := hmac.New(sha256.New, s.key)
	mac.Write([]byte(encoded))
	return b64.EncodeToString(mac.Sum(nil))
}

// NewOpaque returns a 32-byte random secret and its SHA-256 hash.
//
// The caller stores the hash and returns the secret exactly once. There is no route that reads a
// stored token back, because there is nothing to read one back for.
func NewOpaque() (secret string, hash []byte, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, err
	}
	secret = b64.EncodeToString(raw)
	return secret, HashOpaque(secret), nil
}

// HashOpaque is the one-way mapping from a presented secret to the stored column.
func HashOpaque(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

// EqualHash compares in constant time.
func EqualHash(a, b []byte) bool { return subtle.ConstantTimeCompare(a, b) == 1 }
