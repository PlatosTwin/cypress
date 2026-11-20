package api

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"testing"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// ── Decision 14a: the photograph's local capture date ──────────────────────────────────────────
//
// `server/testdata/photos_begin.json` is the request C1 encodes `POST /photos/begin` against. Its
// `captured_at` is 23:30 UTC on the 28th and its `captured_on` is the 29th: a phone east of UTC
// (Tokyo, say) took it on the morning of the 29th, local time. That is the case the field exists
// for — the UTC date would show strangers the wrong day — so the fixture is that case.

// readPhotosBeginFixture is the fixture as a map, so a test can drop or change one key.
func readPhotosBeginFixture(t *testing.T) ([]byte, map[string]any) {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/photos_begin.json")
	if err != nil {
		t.Fatalf("reading the fixture: %v", err)
	}
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("the fixture is not a JSON object: %v", err)
	}
	if body["captured_on"] != "2026-09-29" || body["captured_at"] != "2026-09-28T23:30:00Z" {
		t.Fatalf("calibration: the fixture no longer carries the east-of-UTC case this file reads: %v", body)
	}
	return raw, body
}

// storedCapturedOn is the row's `captured_on` as text, or nil.
func storedCapturedOn(t *testing.T, h *harness, photo uuid.UUID) *string {
	t.Helper()
	var day *string
	if err := h.store.Pool().QueryRow(context.Background(),
		`SELECT to_char(captured_on, 'YYYY-MM-DD') FROM photos WHERE id = $1`, photo).Scan(&day); err != nil {
		t.Fatal(err)
	}
	return day
}

func beginRaw(t *testing.T, h *harness, bearer string, body any) (int, beginPhotoResponse, string) {
	t.Helper()
	recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", bearer, body)
	var ticket beginPhotoResponse
	if recorder.Code == http.StatusOK {
		if err := json.Unmarshal(recorder.Body.Bytes(), &ticket); err != nil {
			t.Fatal(err)
		}
	}
	return recorder.Code, ticket, recorder.Body.String()
}

// TestThePhotosBeginFixtureStoresItsLocalCaptureDate pins the wire name `captured_on` and its
// spelling: the fixture's bytes, posted unchanged, store the phone's date, not the UTC one.
func TestThePhotosBeginFixtureStoresItsLocalCaptureDate(t *testing.T) {
	h := newHarness(t)
	raw, _ := readPhotosBeginFixture(t)
	code, ticket, body := beginRaw(t, h, h.registerDeviceToken(t, uuid.New()), json.RawMessage(raw))
	if code != http.StatusOK {
		t.Fatalf("the fixture was refused %d: %s", code, body)
	}
	if day := storedCapturedOn(t, h, ticket.PhotoID); day == nil || *day != "2026-09-29" {
		t.Fatalf("the fixture's captured_on stored as %v, want the phone's 2026-09-29", day)
	}
}

// TestAPhotoWithNoCaptureDateKeepsTodaysBehaviour: absent and null both store NULL, which is every
// build before the C1 round.
func TestAPhotoWithNoCaptureDateKeepsTodaysBehaviour(t *testing.T) {
	h := newHarness(t)
	device := h.registerDeviceToken(t, uuid.New())
	for name, mutate := range map[string]func(map[string]any){
		"absent":        func(b map[string]any) { delete(b, "captured_on") },
		"explicit null": func(b map[string]any) { b["captured_on"] = nil },
	} {
		_, body := readPhotosBeginFixture(t)
		body["client_uuid"] = uuid.New()
		mutate(body)
		code, ticket, answer := beginRaw(t, h, device, body)
		if code != http.StatusOK {
			t.Fatalf("%s: a begin with no capture date was refused %d: %s", name, code, answer)
		}
		if day := storedCapturedOn(t, h, ticket.PhotoID); day != nil {
			t.Fatalf("%s: stored captured_on %q, want NULL", name, *day)
		}
	}
}

// TestACaptureDateIsAWellFormedDayWithinOneDayOfTheCaptureTime is the validation: exactly
// YYYY-MM-DD, a real calendar date, at most one day from captured_at's UTC date. The fixture's
// UTC date is the 28th, so the 27th and the 29th are accepted and the 26th and the 30th are not.
func TestACaptureDateIsAWellFormedDayWithinOneDayOfTheCaptureTime(t *testing.T) {
	h := newHarness(t)
	device := h.registerDeviceToken(t, uuid.New())
	for _, day := range []string{"2026-09-27", "2026-09-28", "2026-09-29"} {
		_, body := readPhotosBeginFixture(t)
		body["client_uuid"] = uuid.New()
		body["captured_on"] = day
		code, ticket, answer := beginRaw(t, h, device, body)
		if code != http.StatusOK {
			t.Fatalf("captured_on %q, within a day of the UTC date, was refused %d: %s", day, code, answer)
		}
		if stored := storedCapturedOn(t, h, ticket.PhotoID); stored == nil || *stored != day {
			t.Fatalf("captured_on %q stored as %v", day, stored)
		}
	}
	var before int
	if err := h.store.Pool().QueryRow(context.Background(), `SELECT count(*) FROM photos`).Scan(&before); err != nil {
		t.Fatal(err)
	}
	for _, day := range []any{
		"2026-09-26", "2026-09-30", // two days either side
		"2026-9-29", "2026-09-31", "29/09/2026", "", "2026-09-29T00:00:00Z", " 2026-09-29", 20260929,
	} {
		_, body := readPhotosBeginFixture(t)
		body["client_uuid"] = uuid.New()
		body["captured_on"] = day
		recorder := h.do(t, http.MethodPost, Prefix+"/photos/begin", device, body)
		if recorder.Code != http.StatusBadRequest || decodeEnvelope(t, recorder).Error.Code != string(apierr.ValidationFailed) {
			t.Fatalf("captured_on %#v answered %d %s, want 400 validation_failed", day, recorder.Code, recorder.Body.String())
		}
	}
	var after int
	if err := h.store.Pool().QueryRow(context.Background(), `SELECT count(*) FROM photos`).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if after != before {
		t.Fatalf("refused begins stored %d photographs", after-before)
	}
}
