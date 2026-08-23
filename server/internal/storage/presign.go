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
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Config is the bucket's coordinates, all from the environment.
//
// These are the names `flyctl storage create` already set as app secrets on `cypress-sync`
// (server/README.md). They are not in this repository and must never be.
type Config struct {
	AccessKeyID     string // …AWS_ACCESS_KEY_ID
	SecretAccessKey string // …AWS_SECRET_ACCESS_KEY
	Endpoint        string // …AWS_ENDPOINT_URL_S3, e.g. https://fly.storage.tigris.dev
	Region          string // …AWS_REGION
	Bucket          string // …BUCKET_NAME
	// VarPrefix is what the five variables above are actually called, minus their common tail. Empty
	// for the original set; `PhotoVarPrefix` for the photo bucket. It exists so a refusal names the
	// variable somebody has to go and set.
	VarPrefix string
}

// Validate reports the first missing field, naming the environment variable it came from.
//
// **The names are built from `VarPrefix` rather than written as literals**, because there are two
// buckets now and telling somebody to set `AWS_ACCESS_KEY_ID` when the empty one is
// `PHOTOS_AWS_ACCESS_KEY_ID` sends them to change the credential that was already working — and that
// credential is the seed publish's.
func (c Config) Validate() error {
	// **Whitespace-only counts as unset.** A secret set to a stray space or a newline is the shape a
	// copy-paste from a dashboard produces, and treating it as configured would let the service boot
	// and then fail every presign at runtime — handing a contributor `server_error` for a deployment
	// mistake, which is exactly what the boot refusal exists to prevent.
	//
	// **Checked here, trimmed in `PhotoConfig`.** The first version of this trimmed a local copy on
	// a value receiver, so the caller kept the padded value and `NewPresigner` was handed it anyway:
	// a padded secret passed validation and then broke every presign, which is the outcome this
	// comment claimed to prevent (#116 review N15). Validation does not mutate what it validates —
	// the reading happens where the value is read from the environment, and this only refuses.
	c = c.trimmed()
	switch {
	case c.AccessKeyID == "":
		return errors.New(c.VarPrefix + "AWS_ACCESS_KEY_ID is not set")
	case c.SecretAccessKey == "":
		return errors.New(c.VarPrefix + "AWS_SECRET_ACCESS_KEY is not set")
	case c.Endpoint == "":
		return errors.New(c.VarPrefix + "AWS_ENDPOINT_URL_S3 is not set")
	case c.Region == "":
		return errors.New(c.VarPrefix + "AWS_REGION is not set")
	case c.Bucket == "":
		return errors.New(c.VarPrefix + "BUCKET_NAME is not set")
	}
	return nil
}

// PhotoVarPrefix is what every photo-storage variable is called, minus the rest of its name:
// `PHOTOS_AWS_ACCESS_KEY_ID`, `PHOTOS_BUCKET_NAME`, and so on.
//
// ── Why photographs may not share the seed bucket's variables ──────────────────────────────────
//
// **The overwrite hazard.** `AWS_ACCESS_KEY_ID` and its four companions on `cypress-sync` are the
// **`cypress-cities`** bucket's, set automatically by `flyctl storage create` when that bucket was
// made, and the seed-publish relay in `server/README.md` depends on them. A `flyctl storage create`
// run for a photo bucket sets those same names again, in place. Publishing would then be signing
// with the photo bucket's keys — and it would break silently, because publishing is not something
// this service does, so nothing here would go red.
//
// **The visibility hazard, which stands even without the first.** `cypress-cities` is public-read:
// it serves anonymous GETs for every key on its dedicated domain. A photograph stored there is
// fetchable by uuid with no credential at all, so `photoData`'s visibility check — the thing that
// keeps a `pending` photograph private to its contributor, and a withdrawn one gone — would be
// decoration. Photographs need a bucket that is not public-read; that is a different bucket, which
// is a different set of keys.
const PhotoVarPrefix = "PHOTOS_"

// PhotoConfig reads the photo bucket's coordinates.
//
// A named constructor rather than a flag on `Config`, so the prefix cannot be forgotten at a call
// site: there is exactly one way to build a photo presigner and it is spelled here.
func PhotoConfig(getenv func(string) string) Config {
	return Config{
		AccessKeyID:     getenv(PhotoVarPrefix + "AWS_ACCESS_KEY_ID"),
		SecretAccessKey: getenv(PhotoVarPrefix + "AWS_SECRET_ACCESS_KEY"),
		Endpoint:        getenv(PhotoVarPrefix + "AWS_ENDPOINT_URL_S3"),
		Region:          getenv(PhotoVarPrefix + "AWS_REGION"),
		Bucket:          getenv(PhotoVarPrefix + "BUCKET_NAME"),
		VarPrefix:       PhotoVarPrefix,
	}.trimmed()
}

// trimmed returns the config with surrounding whitespace removed from every value.
//
// Not exported: there is exactly one place a `Config` is built from the environment and it applies
// this, so a second caller would mean a second source of these values.
func (c Config) trimmed() Config {
	return Config{
		AccessKeyID:     strings.TrimSpace(c.AccessKeyID),
		SecretAccessKey: strings.TrimSpace(c.SecretAccessKey),
		Endpoint:        strings.TrimSpace(c.Endpoint),
		Region:          strings.TrimSpace(c.Region),
		Bucket:          strings.TrimSpace(c.Bucket),
		VarPrefix:       c.VarPrefix,
	}
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
	return p.presign(http.MethodPut, key, lifetime)
}

// PresignGet returns a URL the client may GET the binary from, valid for lifetime.
//
// `GET /photos/{id}` hands this back rather than the bytes. The bucket is not anonymously readable
// on the S3 API endpoints — `server/README.md` records that anonymous GET there returns 403 even
// with the bucket public — so a storage key on its own fetches nothing and a presigned read is what
// makes a photograph a device never wrote actually arrive.
func (p *Presigner) PresignGet(key string, lifetime time.Duration) (string, error) {
	return p.presign(http.MethodGet, key, lifetime)
}

func (p *Presigner) presign(method, key string, lifetime time.Duration) (string, error) {
	if err := p.config.Validate(); err != nil {
		return "", err
	}
	endpoint, err := url.Parse(p.config.Endpoint)
	if err != nil {
		return "", fmt.Errorf("AWS_ENDPOINT_URL_S3 is not a URL: %w", err)
	}

	// Path-style addressing (`/bucket/key`) rather than virtual-host style. Tigris serves both, and
	// path style keeps the signed host equal to the configured endpoint — a mismatch between the
	// host in the signature and the host in the request is the standard way this fails, and it
	// fails as an opaque SignatureDoesNotMatch.
	canonicalURI := "/" + p.config.Bucket + "/" + strings.TrimPrefix(key, "/")

	return signQuery(signInput{
		Method:          method,
		Scheme:          endpoint.Scheme,
		Host:            endpoint.Host,
		CanonicalURI:    canonicalURI,
		AccessKeyID:     p.config.AccessKeyID,
		SecretAccessKey: p.config.SecretAccessKey,
		Region:          p.config.Region,
		Now:             p.now().UTC(),
		Lifetime:        lifetime,
	}), nil
}

// signInput is everything one presigned URL depends on.
//
// The signing is split out from `presign` so it can be tested against **AWS's own published
// example** — the documented `GET /test.txt` query-string vector, which uses virtual-host
// addressing this service does not. A signature is either exactly right or opaquely wrong
// (`SignatureDoesNotMatch` tells you nothing about which of nine things you got wrong), so the only
// test worth having is one whose expected value comes from outside this file.
type signInput struct {
	Method          string
	Scheme          string
	Host            string
	CanonicalURI    string
	AccessKeyID     string
	SecretAccessKey string
	Region          string
	Now             time.Time
	Lifetime        time.Duration
}

// signQuery performs SigV4 query-string signing and returns the full URL.
func signQuery(in signInput) string {
	stamp := in.Now.Format("20060102T150405Z")
	day := in.Now.Format("20060102")
	scope := strings.Join([]string{day, in.Region, "s3", "aws4_request"}, "/")

	query := url.Values{}
	query.Set("X-Amz-Algorithm", "AWS4-HMAC-SHA256")
	query.Set("X-Amz-Credential", in.AccessKeyID+"/"+scope)
	query.Set("X-Amz-Date", stamp)
	query.Set("X-Amz-Expires", fmt.Sprintf("%d", int(in.Lifetime.Seconds())))
	query.Set("X-Amz-SignedHeaders", "host")

	canonicalRequest := strings.Join([]string{
		in.Method,
		in.CanonicalURI,
		query.Encode(),
		"host:" + in.Host + "\n",
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
				hmacSHA256([]byte("AWS4"+in.SecretAccessKey), []byte(day)),
				[]byte(in.Region)),
			[]byte("s3")),
		[]byte("aws4_request"))

	query.Set("X-Amz-Signature", hex.EncodeToString(hmacSHA256(signingKey, []byte(stringToSign))))

	return in.Scheme + "://" + in.Host + in.CanonicalURI + "?" + query.Encode()
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
