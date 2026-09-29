package api

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── The sealed tile cursor (the #190 review's F1) ──────────────────────────────────────────────

// updatedAtOf reads a tree's exact stamp — the value the cursor must not give away.
func updatedAtOf(t *testing.T, h *harness, tree uuid.UUID) time.Time {
	t.Helper()
	var at time.Time
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT updated_at FROM community_trees WHERE id = $1`, tree).Scan(&at); err != nil {
		t.Fatal(err)
	}
	return at
}

// plainCursor is the cursor as it was before sealing — base64url JSON of the keyset position — which
// is the attacker's best guess at the format and exactly what the review forged.
func plainCursor(at time.Time, id uuid.UUID) string {
	encoded, _ := json.Marshal(map[string]any{"t": at.UTC().Format(time.RFC3339Nano), "i": id})
	return base64.RawURLEncoding.EncodeToString(encoded)
}

func mustRefuseCursor(t *testing.T, h *harness, bearer, tile, cursor, what string) {
	t.Helper()
	recorder := requestTile(t, h, bearer, tile, cursor, 0, settled)
	if recorder.Code != http.StatusBadRequest || decodeEnvelope(t, recorder).Error.Code != string(apierr.ValidationFailed) {
		t.Fatalf("%s: the tile answered %d %s, want 400 validation_failed", what, recorder.Code, recorder.Body.String())
	}
}

// twoTreesInOneTile publishes two trees and returns the first page of one, as a stranger.
func twoTreesInOneTile(t *testing.T, h *harness) (stranger, tile string, first uuid.UUID, page tileBody) {
	t.Helper()
	adder := signInAs(t, h, "ct.cursor.adder", nil, accepted())
	for _, lat := range []float64{ctLat, north(20)} {
		mustApply(t, h.syncOne(t, adder.AccessToken, addTreeAt(uuid.New(), lat, ctLon, time.Now().Add(-time.Hour))), "add")
	}
	tile, _, _ = tileOf(ctLat, ctLon)
	stranger = h.registerDeviceToken(t, uuid.New())
	page = readTile(t, h, stranger, tile, "", 1, settled)
	if len(page.Trees) != 1 || !page.HasMore {
		t.Fatalf("fixture: a one-tree first page of two, got %v has_more %v", page.treeIDs(), page.HasMore)
	}
	return stranger, tile, page.Trees[0].ID, page
}

// TestTheTileCursorCarriesNoReadableTime: the cursor after one served tree is that tree's keyset
// position, and none of it — the id, the stamp as text, the stamp as the eight bytes it is sealed
// from — is in the bytes a stranger holds.
func TestTheTileCursorCarriesNoReadableTime(t *testing.T) {
	h := newHarness(t)
	stranger, tile, first, page := twoTreesInOneTile(t, h)
	stamped := updatedAtOf(t, h, first)

	raw, err := base64.RawURLEncoding.DecodeString(*page.NextCursor)
	if err != nil {
		t.Fatalf("the cursor is not base64url: %v", err)
	}
	micro := make([]byte, 8)
	binary.BigEndian.PutUint64(micro, uint64(stamped.UnixMicro()))
	for name, needle := range map[string][]byte{
		"the served tree's id":         first[:],
		"the served tree's id as text": []byte(first.String()),
		"its stamp as RFC 3339":        []byte(stamped.UTC().Format("2006-01-02T15:04:05")),
		"its stamp as microseconds":    micro,
	} {
		if bytes.Contains(raw, needle) {
			t.Fatalf("the cursor carries %s in the clear (%x)", name, raw)
		}
	}

	// The same position asked for twice is sealed twice, differently, at one length: nothing about
	// the stamp is in the length, and two cursors cannot be compared for equality of position.
	again := readTile(t, h, stranger, tile, "", 1, settled)
	if *again.NextCursor == *page.NextCursor {
		t.Fatal("two seals of one position are byte-identical; the nonce is not fresh")
	}
	if len(*again.NextCursor) != len(*page.NextCursor) {
		t.Fatalf("cursor lengths %d and %d differ for one position", len(*again.NextCursor), len(*page.NextCursor))
	}
	// The control: the cursor still works — page two is the other tree, and nothing is repeated.
	second := readTile(t, h, stranger, tile, *page.NextCursor, 1, settled)
	if len(second.Trees) != 1 || second.Trees[0].ID == first {
		t.Fatalf("control: page two served %v after %s", second.treeIDs(), first)
	}
}

// TestTheReviewersBinarySearchFindsNothing is the #190 review's attack, run as the review ran it:
// forge a cursor one microsecond before a tree's stamp and one at it, and read the difference.
// Before sealing, the first served the tree and the second did not, which recovered every stamp in
// every tile. Now neither is accepted, so there is no difference to read.
func TestTheReviewersBinarySearchFindsNothing(t *testing.T) {
	h := newHarness(t)
	stranger, tile, first, _ := twoTreesInOneTile(t, h)
	stamped := updatedAtOf(t, h, first)

	for name, forged := range map[string]string{
		"a JSON cursor one microsecond before the stamp": plainCursor(stamped.Add(-time.Microsecond), maxUUID),
		"a JSON cursor at the stamp":                     plainCursor(stamped, maxUUID),
		"a JSON cursor at the beginning of time":         plainCursor(time.Time{}, uuid.Nil),
	} {
		mustRefuseCursor(t, h, stranger, tile, forged, name)
	}

	// The sealed layout, guessed exactly but without the key: version, the stamp, the id, no since.
	guess := make([]byte, 12+cursorPlaintextLen+16)
	guess[12] = cursorVersion
	binary.BigEndian.PutUint64(guess[13:21], uint64(stamped.UnixMicro()))
	copy(guess[21:37], first[:])
	mustRefuseCursor(t, h, stranger, tile, base64.RawURLEncoding.EncodeToString(guess),
		"the sealed layout forged without the key")
}

// TestATamperedMovedOrForeignCursorIsRefused: one bit changed, a cursor presented for another tile,
// a truncated one, and one sealed under another key — each `validation_failed`.
func TestATamperedMovedOrForeignCursorIsRefused(t *testing.T) {
	h := newHarness(t)
	stranger, tile, _, page := twoTreesInOneTile(t, h)
	raw, _ := base64.RawURLEncoding.DecodeString(*page.NextCursor)

	flipped := bytes.Clone(raw)
	flipped[len(flipped)/2] ^= 0x01
	mustRefuseCursor(t, h, stranger, tile, base64.RawURLEncoding.EncodeToString(flipped), "one bit flipped")
	mustRefuseCursor(t, h, stranger, tile, base64.RawURLEncoding.EncodeToString(raw[:len(raw)-1]), "truncated")

	_, x, y := tileOf(ctLat, ctLon)
	neighbour := "14/" + itoa(x+1) + "/" + itoa(y)
	mustRefuseCursor(t, h, stranger, neighbour, *page.NextCursor, "tile A's cursor presented for tile B")

	otherKey, err := DeriveCursorKey([]byte("another-deployment's-signing-key-32+bytes"))
	if err != nil {
		t.Fatal(err)
	}
	other := &Server{CursorKey: otherKey}
	foreign, err := other.sealTileCursor(tile, tileCursor{At: time.Now().Add(-time.Hour), ID: maxUUID})
	if err != nil {
		t.Fatal(err)
	}
	mustRefuseCursor(t, h, stranger, tile, foreign, "a cursor sealed under another key")

	// The control: the untouched cursor, on its own tile, is accepted.
	if recorder := requestTile(t, h, stranger, tile, *page.NextCursor, 0, settled); recorder.Code != http.StatusOK {
		t.Fatalf("control: the genuine cursor answered %d %s", recorder.Code, recorder.Body.String())
	}
}

// TestTheCursorKeyIsDerivedAndRequired: the key is HKDF output, not the signing secret itself; it
// follows the secret; a short secret is refused; and a server with no key hands out no cursor at
// all rather than a readable one.
func TestTheCursorKeyIsDerivedAndRequired(t *testing.T) {
	secret := []byte("a-test-signing-key-of-at-least-32-bytes")
	key, err := DeriveCursorKey(secret)
	if err != nil {
		t.Fatal(err)
	}
	if len(key) != 32 {
		t.Fatalf("the cursor key is %d bytes, want 32 (AES-256)", len(key))
	}
	if bytes.Contains(secret, key) || bytes.Equal(key, secret[:32]) {
		t.Fatal("the cursor key is the signing secret itself, not a key derived from it")
	}
	if again, _ := DeriveCursorKey(secret); !bytes.Equal(again, key) {
		t.Fatal("the derivation is not deterministic, so a restart would invalidate every cursor")
	}
	if other, _ := DeriveCursorKey([]byte("a-different-signing-key-of-32-bytes!!")); bytes.Equal(other, key) {
		t.Fatal("two secrets derived one cursor key")
	}
	if _, err := DeriveCursorKey([]byte("short")); err == nil {
		t.Fatal("a secret under 32 bytes derived a key")
	}

	h := newHarness(t)
	h.server.CursorKey = nil
	tile, _, _ := tileOf(ctLat, ctLon)
	recorder := requestTile(t, h, h.registerDeviceToken(t, uuid.New()), tile, "", 0, settled)
	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("a server with no cursor key answered %d %s, want 500 and no cursor", recorder.Code, recorder.Body.String())
	}
}
