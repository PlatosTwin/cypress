// Package storage presigns S3 PUTs against the project's Tigris bucket.
//
// ── Why SigV4 is written out rather than imported ──────────────────────────────────────────────
// The AWS SDK for Go is several modules and a large transitive tree, and this service needs one
// operation from it: a presigned PUT URL. R72 decided the stack partly on "two direct dependencies,
// no runtime to patch, a static binary", and adding the SDK to mint a signature would spend that.
// SigV4 query-string signing is a documented, stable algorithm and it is ~70 lines of HMAC.
//
// ── What this package does not do ──────────────────────────────────────────────────────────────
// It provisions nothing. `server/README.md` records the bucket that exists — `cypress-cities`,
// created 2026-08-01 — and the credentials Fly set as app secrets. Whether photographs share that
// bucket or get their own is a deployment decision, taken with the owner, and this package reads
// whatever `BUCKET_NAME` names.
//
// The client PUTs the binary straight to storage rather than through this service (spec §1.1
// step 4), which is what keeps a 256 MB machine out of the path of a multi-megabyte upload.
package storage

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Config is the bucket's coordinates, all from the environment.
//
// These are the names `flyctl storage create` already set as app secrets on `cypress-sync`
// (server/README.md). They are not in this repository and must never be.
type Config struct {
	AccessKeyID     string // AWS_ACCESS_KEY_ID
	SecretAccessKey string // AWS_SECRET_ACCESS_KEY
	Endpoint        string // AWS_ENDPOINT_URL_S3, e.g. https://fly.storage.tigris.dev
	Region          string // AWS_REGION
	Bucket          string // BUCKET_NAME
}

// Validate reports the first missing field.
func (c Config) Validate() error {
	switch {
	case c.AccessKeyID == "":
		return errors.New("AWS_ACCESS_KEY_ID is not set")
	case c.SecretAccessKey == "":
		return errors.New("AWS_SECRET_ACCESS_KEY is not set")
	case c.Endpoint == "":
		return errors.New("AWS_ENDPOINT_URL_S3 is not set")
	case c.Region == "":
		return errors.New("AWS_REGION is not set")
	case c.Bucket == "":
		return errors.New("BUCKET_NAME is not set")
	}
	return nil
}

// Presigner mints presigned URLs.
type Presigner struct {
	config Config
	now    func() time.Time
}

// NewPresigner builds one.
func NewPresigner(config Config) *Presigner {
	return &Presigner{config: config, now: func() time.Time { return time.Now().UTC() }}
}

// WithClock replaces the clock. Test seam — a signature is a function of the minute it was made in,
// so a test that could not fix the clock could only assert that the output was long.
func (p *Presigner) WithClock(now func() time.Time) *Presigner {
	return &Presigner{config: p.config, now: now}
}

// PresignPut returns a URL the client may PUT the binary to, valid for lifetime.
//
// The window is short by design and it is not the 72 h grace period: `PhotoUploadTicket`'s 72 h is
// how long the *record* waits for bytes before being garbage-collected, whereas this is how long
// the *permission* lasts. A client that took longer asks for another ticket, which costs one round
// trip and keeps a leaked URL from being useful for three days.
func (p *Presigner) PresignPut(key string, lifetime time.Duration) (string, error) {
	if err := p.config.Validate(); err != nil {
		return "", err
	}
	endpoint, err := url.Parse(p.config.Endpoint)
	if err != nil {
		return "", fmt.Errorf("AWS_ENDPOINT_URL_S3 is not a URL: %w", err)
	}

	now := p.now().UTC()
	stamp := now.Format("20060102T150405Z")
	day := now.Format("20060102")
	scope := strings.Join([]string{day, p.config.Region, "s3", "aws4_request"}, "/")

	// Path-style addressing (`/bucket/key`) rather than virtual-host style. Tigris serves both, and
	// path style keeps the signed host equal to the configured endpoint — a mismatch between the
	// host in the signature and the host in the request is the standard way this fails, and it
	// fails as an opaque SignatureDoesNotMatch.
	canonicalURI := "/" + p.config.Bucket + "/" + strings.TrimPrefix(key, "/")

	query := url.Values{}
	query.Set("X-Amz-Algorithm", "AWS4-HMAC-SHA256")
	query.Set("X-Amz-Credential", p.config.AccessKeyID+"/"+scope)
	query.Set("X-Amz-Date", stamp)
	query.Set("X-Amz-Expires", fmt.Sprintf("%d", int(lifetime.Seconds())))
	query.Set("X-Amz-SignedHeaders", "host")

	canonicalRequest := strings.Join([]string{
		"PUT",
		canonicalURI,
		query.Encode(),
		"host:" + endpoint.Host + "\n",
		"host",
		// Presigned URLs sign the payload as UNSIGNED-PAYLOAD: the bytes are not known here, and
		// the whole point of handing the client a URL is that this service never sees them.
		"UNSIGNED-PAYLOAD",
	}, "\n")

	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		stamp,
		scope,
		hex.EncodeToString(sha256sum([]byte(canonicalRequest))),
	}, "\n")

	signingKey := hmacSHA256(
		hmacSHA256(
			hmacSHA256(
				hmacSHA256([]byte("AWS4"+p.config.SecretAccessKey), []byte(day)),
				[]byte(p.config.Region)),
			[]byte("s3")),
		[]byte("aws4_request"))

	query.Set("X-Amz-Signature", hex.EncodeToString(hmacSHA256(signingKey, []byte(stringToSign))))

	return endpoint.Scheme + "://" + endpoint.Host + canonicalURI + "?" + query.Encode(), nil
}

func hmacSHA256(key, data []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(data)
	return mac.Sum(nil)
}

func sha256sum(data []byte) []byte {
	sum := sha256.Sum256(data)
	return sum[:]
}
