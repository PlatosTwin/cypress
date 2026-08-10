// Package uuid is a 90-line UUID, written here rather than depended on.
//
// `github.com/google/uuid` would have been the obvious import and it is a fine library. It is not
// taken because R72 decided the stack partly on dependency count — "two direct dependencies, no
// runtime to patch, a static binary" is one of the three things that tipped Go past Fastify once
// the auth argument came out a wash. Spending a third of that budget on parsing and formatting
// sixteen bytes would be spending the ruling's own reason for the ruling.
//
// What this needs to do is exactly: parse the canonical hyphenated form, print it, mint a v4, and
// travel through pgx and encoding/json. That is the whole surface, and `uuid_test.go` pins it
// against the forms the client actually emits — `SQLiteValue`'s uppercase `uuidString` and
// `JSONEncoder`'s lowercase, which is the case split `AppSchema` v13 declares `COLLATE NOCASE` for.
package uuid

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
)

// UUID is the raw sixteen bytes.
type UUID [16]byte

// Nil is the all-zero UUID.
var Nil UUID

// New mints a version 4 UUID from crypto/rand.
func New() UUID {
	var u UUID
	if _, err := rand.Read(u[:]); err != nil {
		// crypto/rand on Linux and Darwin does not fail; if it does, nothing this service issues
		// afterwards is trustworthy and continuing would mint predictable identifiers.
		panic(fmt.Sprintf("uuid: crypto/rand failed: %v", err))
	}
	u[6] = (u[6] & 0x0f) | 0x40 // version 4
	u[8] = (u[8] & 0x3f) | 0x80 // RFC 4122 variant
	return u
}

// ErrInvalid is returned for anything that is not a canonical hyphenated UUID.
var ErrInvalid = errors.New("uuid: not a canonical hyphenated UUID")

// Parse accepts the canonical 36-character form in either case.
//
// Case-insensitivity is not a convenience: the client mints the same value in two spellings
// depending on which side of the outbox it came from, and the whole idempotency guarantee would
// otherwise turn on those two agreeing.
func Parse(text string) (UUID, error) {
	if len(text) != 36 || text[8] != '-' || text[13] != '-' || text[18] != '-' || text[23] != '-' {
		return Nil, ErrInvalid
	}
	var u UUID
	compact := text[0:8] + text[9:13] + text[14:18] + text[19:23] + text[24:36]
	if _, err := hex.Decode(u[:], []byte(compact)); err != nil {
		return Nil, ErrInvalid
	}
	return u, nil
}

// MustParse is Parse for constants in tests and for nothing else.
func MustParse(text string) UUID {
	u, err := Parse(text)
	if err != nil {
		panic(err)
	}
	return u
}

// String prints the canonical lowercase hyphenated form.
func (u UUID) String() string {
	buffer := make([]byte, 36)
	hex.Encode(buffer[0:8], u[0:4])
	buffer[8] = '-'
	hex.Encode(buffer[9:13], u[4:6])
	buffer[13] = '-'
	hex.Encode(buffer[14:18], u[6:8])
	buffer[18] = '-'
	hex.Encode(buffer[19:23], u[8:10])
	buffer[23] = '-'
	hex.Encode(buffer[24:36], u[10:16])
	return string(buffer)
}

// IsNil reports whether u is the zero value.
func (u UUID) IsNil() bool { return u == Nil }

// MarshalJSON writes the canonical string form.
func (u UUID) MarshalJSON() ([]byte, error) { return json.Marshal(u.String()) }

// UnmarshalJSON reads the canonical string form.
func (u *UUID) UnmarshalJSON(data []byte) error {
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return err
	}
	parsed, err := Parse(text)
	if err != nil {
		return err
	}
	*u = parsed
	return nil
}

// UUIDValue implements pgtype.UUIDValuer, which is how pgx encodes this into a `uuid` column.
func (u UUID) UUIDValue() (pgtype.UUID, error) {
	return pgtype.UUID{Bytes: u, Valid: true}, nil
}

// ScanUUID implements pgtype.UUIDScanner.
func (u *UUID) ScanUUID(v pgtype.UUID) error {
	if !v.Valid {
		return errors.New("uuid: cannot scan NULL into a non-pointer UUID")
	}
	*u = v.Bytes
	return nil
}
