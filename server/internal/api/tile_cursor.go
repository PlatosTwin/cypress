package api

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── The tile cursor is sealed ──────────────────────────────────────────────────────────────────
//
// **Why it cannot be plain.** A tile cursor is a keyset position: the `updated_at` of the last tree
// served, to the microsecond. The adversarial review of #190 showed what that gives a stranger when
// the cursor is readable (base64 JSON): the exact second an adder stood at a tree (a signed-in add),
// the moment somebody signed in (a claim publishes and bumps it), and the moment an account was
// deleted (a tombstone's time). And because the server took any well-formed cursor back, a forged
// one at `(T − 1µs)` served a tree while one at `(T)` did not, so a binary search recovered those
// times for every tree in every tile. That undid the day-precision ruling for every community-tree
// date on the wire.
//
// **What it is now.** AES-256-GCM over a fixed-width binary record, with a random nonce and the
// canonical tile as additional data:
//
//   - **Unreadable.** A stranger learns nothing from the bytes. The plaintext is a fixed 34 bytes, so
//     the length does not vary with the timestamp either (RFC 3339 trims trailing zeros, which the
//     JSON form's length leaked).
//   - **Unforgeable.** Only this service can make a cursor it will accept. Any cursor it did not
//     make, or one with a single bit changed, fails authentication and is `validation_failed`.
//   - **Bound to its tile.** Tile A's cursor presented for tile B fails authentication too, so a
//     position learned in one tile cannot be replayed against another.
//
// What remains is inherent to a live feed and is not a leak of the past: somebody polling a tile
// every second sees a new tree appear within a second of its arrival, and can watch when a fresh
// tree's position settles 25 s later. Both are observations of the present that the poller could
// make by looking, not recoveries of a stored time.
//
// **The key.** Derived with HKDF-SHA256 from `SESSION_SIGNING_KEY`, the service's existing required
// secret (≥ 32 bytes), under an info string used for nothing else, so the derived key is
// independent of the signing key. No new secret is needed. Rotating `SESSION_SIGNING_KEY` already
// signs every account out; it also makes every stored tile cursor `validation_failed`, and the
// client answers that by dropping the cursor and taking a fresh snapshot.

// cursorKeyInfo is HKDF's info string. It names the purpose and a version, so a second use of the
// same secret can never derive this key by accident.
const cursorKeyInfo = "cypress-sync/community-tile-cursor/v1"

// cursorAAD prefixes the tile in the additional data, for the same reason.
const cursorAAD = "cypress-sync/community-tile-cursor/v1 tile="

// DeriveCursorKey is the 32-byte AES-256-GCM key for tile cursors, derived from the service's
// session signing secret. main.go calls it at boot; the tests call it with their own signing key.
func DeriveCursorKey(secret []byte) ([]byte, error) {
	if len(secret) < 32 {
		return nil, errors.New("the cursor key's source secret must be at least 32 bytes")
	}
	return hkdf.Key(sha256.New, secret, nil, cursorKeyInfo, 32)
}

// tileCursor is what a sealed cursor carries. `Since` is set only while a snapshot is being paged:
// removals at or before it are not reported, because a first fetch holds nothing to remove.
type tileCursor struct {
	At    time.Time
	ID    uuid.UUID
	Since *time.Time
}

func (c tileCursor) key() store.TileKey { return store.TileKey{At: c.At, ID: c.ID} }

// cursorPlaintextLen is version (1) + at (8) + id (16) + flags (1) + since (8).
const cursorPlaintextLen = 34

const cursorVersion = 1

var errBadTileCursor = apierr.New(apierr.ValidationFailed, "That page marker is not valid.")

// errCursorKeyMissing fails the request closed: a service that could not seal would otherwise
// have to hand out a readable cursor or none.
var errCursorKeyMissing = errors.New("the tile cursor key is not configured")

func (s *Server) cursorAEAD() (cipher.AEAD, error) {
	if len(s.CursorKey) != 32 {
		return nil, errCursorKeyMissing
	}
	block, err := aes.NewCipher(s.CursorKey)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// sealTileCursor encrypts a cursor for one tile.
func (s *Server) sealTileCursor(tile string, c tileCursor) (string, error) {
	aead, err := s.cursorAEAD()
	if err != nil {
		return "", err
	}
	plain := make([]byte, cursorPlaintextLen)
	plain[0] = cursorVersion
	binary.BigEndian.PutUint64(plain[1:9], uint64(c.At.UnixMicro()))
	copy(plain[9:25], c.ID[:])
	if c.Since != nil {
		plain[25] = 1
		binary.BigEndian.PutUint64(plain[26:34], uint64(c.Since.UnixMicro()))
	}
	nonce := make([]byte, aead.NonceSize())
	source := s.cursorNonces
	if source == nil {
		source = rand.Reader
	}
	if _, err := io.ReadFull(source, nonce); err != nil {
		return "", err
	}
	sealed := aead.Seal(nonce, nonce, plain, []byte(cursorAAD+tile))
	return base64.RawURLEncoding.EncodeToString(sealed), nil
}

// openTileCursor authenticates and decrypts a cursor presented for one tile. Anything this service
// did not seal for this tile — forged, altered, truncated, or another tile's — is
// `validation_failed`.
func (s *Server) openTileCursor(tile, raw string) (tileCursor, error) {
	aead, err := s.cursorAEAD()
	if err != nil {
		return tileCursor{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", err)
	}
	sealed, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil || len(sealed) < aead.NonceSize() {
		return tileCursor{}, errBadTileCursor
	}
	nonce, body := sealed[:aead.NonceSize()], sealed[aead.NonceSize():]
	plain, err := aead.Open(nil, nonce, body, []byte(cursorAAD+tile))
	if err != nil || len(plain) != cursorPlaintextLen || plain[0] != cursorVersion {
		return tileCursor{}, errBadTileCursor
	}
	var c tileCursor
	c.At = time.UnixMicro(int64(binary.BigEndian.Uint64(plain[1:9]))).UTC()
	copy(c.ID[:], plain[9:25])
	switch plain[25] {
	case 0:
	case 1:
		since := time.UnixMicro(int64(binary.BigEndian.Uint64(plain[26:34]))).UTC()
		c.Since = &since
	default:
		return tileCursor{}, errBadTileCursor
	}
	return c, nil
}
