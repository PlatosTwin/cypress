// Package api is the HTTP surface: routing, authentication, and the handlers.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/apierr"
	"github.com/PlatosTwin/cypress/server/internal/apple"
	"github.com/PlatosTwin/cypress/server/internal/ratelimit"
	"github.com/PlatosTwin/cypress/server/internal/storage"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/tokens"
	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// Prefix is the API's one and only mount point. `RemoteAPI.baseURL` is documented as `/api/v1`.
const Prefix = "/api/v1"

// AppleAuth is the part of Apple this service needs, as an interface so the tests can supply a
// local one. The production implementation is `*apple.Client` plus `*apple.Verifier`.
type AppleAuth interface {
	Verify(ctx context.Context, identityToken string) (apple.Identity, error)
	ExchangeAuthorizationCode(ctx context.Context, code string) (string, error)
	Revoke(ctx context.Context, refreshToken string) error
}

// Server holds everything the handlers need.
type Server struct {
	Store     *store.Store
	Apple     AppleAuth
	Signer    *tokens.Signer
	Presigner *storage.Presigner
	Log       *slog.Logger
	GitSHA    string
	// OperatorToken authorizes the takedown route. Operator surfaces are a web deliverable by
	// ARCHITECTURE §8, so this service exposes the action and not a console.
	OperatorToken string

	limiter *ratelimit.Limiter
	// readLimiter is the public read's own bucket, at its own budget.
	//
	// **Separate from `limiter`, because the two callers are not alike.** `limiter` is sized for a
	// phone draining an outbox — burst 60, one token a second — and the public web is server-side
	// rendered, so every reader in the world arrives from one address: the rendering machine's.
	// Putting that on the phone budget would throttle the whole site to one page per second, which
	// is `clientKey`'s own warning arriving from the other direction. Two instances rather than one
	// so neither can spend the other's tokens.
	readLimiter *ratelimit.Limiter
}

// Handler builds the router.
func (s *Server) Handler() http.Handler {
	if s.limiter == nil {
		s.limiter = ratelimit.New()
	}
	if s.readLimiter == nil {
		s.readLimiter = ratelimit.NewPublicRead()
	}
	mux := http.NewServeMux()

	// Not under Prefix: infrastructure, not API.
	mux.HandleFunc("GET /health", s.health)

	// ── Auth and identity ──────────────────────────────────────────────────────────────────────
	mux.Handle("POST "+Prefix+"/auth/oidc", s.public(s.authOIDC))
	mux.Handle("POST "+Prefix+"/auth/refresh", s.public(s.authRefresh))
	mux.Handle("POST "+Prefix+"/devices/register", s.public(s.registerDevice))
	mux.Handle("POST "+Prefix+"/devices/claim", s.authenticated(s.claimDevice))
	mux.Handle("DELETE "+Prefix+"/me", s.authenticated(s.deleteMe))

	// ── Writes ─────────────────────────────────────────────────────────────────────────────────
	mux.Handle("POST "+Prefix+"/sync", s.authenticated(s.sync))
	mux.Handle("POST "+Prefix+"/trees", s.authenticated(s.addTree))
	mux.Handle("POST "+Prefix+"/photos/begin", s.authenticated(s.beginPhoto))
	mux.Handle("POST "+Prefix+"/photos/{id}/received", s.authenticated(s.photoReceived))
	mux.Handle("DELETE "+Prefix+"/photos/{id}", s.authenticated(s.deletePhoto))

	// ── Class R reads ──────────────────────────────────────────────────────────────────────────
	mux.Handle("GET "+Prefix+"/me/grove", s.authenticated(s.grove))
	mux.Handle("GET "+Prefix+"/me/grove/species", s.authenticated(s.groveSpecies))
	mux.Handle("GET "+Prefix+"/me/grove/{treeID}/favorite", s.authenticated(s.isFavorite))
	mux.Handle("GET "+Prefix+"/me/journal", s.authenticated(s.journal))
	mux.Handle("GET "+Prefix+"/me/map-membership", s.authenticated(s.mapMembership))
	mux.Handle("GET "+Prefix+"/trees/{id}", s.authenticated(s.treeProfile))
	mux.Handle("GET "+Prefix+"/photos/{id}", s.authenticated(s.photoData))

	// ── The public read ────────────────────────────────────────────────────────────────────────
	// No credential, and the only route here that answers one contributor's record to another
	// person. What it may say is `docs/rulings-pending/public-tree-read.md`; the mechanism is
	// `public.go`'s allow-list over `contributions.kind`.
	mux.Handle("GET "+Prefix+"/public/trees/{id}", s.publicRead(s.publicTree))

	// ── Operator ───────────────────────────────────────────────────────────────────────────────
	// R72 ruling 5's non-negotiable half: "Auto-approve without a takedown is the version of this
	// rule that must not ship."
	mux.Handle("POST "+Prefix+"/operator/photos/{id}/reject", s.operator(s.rejectPhoto))

	return withTimeout(s.recoverPanics(mux))
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.Log, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "cypress-sync",
		"git_sha": s.GitSHA,
	})
}

// ── Identity plumbing ──────────────────────────────────────────────────────────────────────────

// caller is who a request authenticated as.
type caller struct {
	// UserID is set for a signed-in account.
	UserID *uuid.UUID
	// DeviceID is set for the anonymous device credential. **This is `devices.id`** — the row key
	// this database minted, which is what goes into `contributions.device_id` and `photos.device_id`
	// and therefore what `ownsPhoto` compares against. It is this database's vocabulary.
	DeviceID *uuid.UUID
	// DeviceUUID is the same installation in the **client's** vocabulary: `devices.device_uuid`, the
	// value the phone keeps in `app_state.device_uuid` and sends as an item's `device_id`.
	//
	// It exists because `applyOne` had to answer "is this item this caller's?" about a value in that
	// vocabulary and had only the row key to answer with, so it compared the two and refused every
	// anonymous item — permanently, since `forbidden` is not retryable. `RegisterDevice` and
	// `ClaimDevice` do this translation with `WHERE device_uuid = $1`; this field is the same
	// translation, done once per request on the credential rather than once per item.
	DeviceUUID *uuid.UUID
}

func (c caller) owner() store.Owner {
	if c.UserID != nil {
		return store.Owner{UserID: c.UserID}
	}
	return store.Owner{DeviceID: c.DeviceID}
}

func (c caller) isUser() bool { return c.UserID != nil }

type handlerFunc func(http.ResponseWriter, *http.Request, caller) error
type publicFunc func(http.ResponseWriter, *http.Request) error

func (s *Server) public(next publicFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.limiter.Allow(clientKey(r)) {
			apierr.Write(w, s.Log, apierr.New(apierr.RateLimited, "Too many requests. Try again shortly."))
			return
		}
		if err := next(w, r); err != nil {
			apierr.Write(w, s.Log, err)
		}
	})
}

// publicRead is `public` on the read budget.
//
// A separate wrapper rather than a parameter on `public`, so which bucket a route spends is visible
// at the route table instead of at the call site. Everything else is identical: no credential is
// resolved, and a refusal is `rate_limited`, which is retryable.
func (s *Server) publicRead(next publicFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.readLimiter.Allow(clientKey(r)) {
			apierr.Write(w, s.Log, apierr.New(apierr.RateLimited, "Too many requests. Try again shortly."))
			return
		}
		if err := next(w, r); err != nil {
			apierr.Write(w, s.Log, err)
		}
	})
}

// authenticated resolves the bearer token, and is where spec §5.8's defect is designed out.
//
// ── A 401 must mean "the session", never "the item" ────────────────────────────────────────────
//
// `APIError.unauthorized.retryable` is false and `OutboxRetryPolicy.nextState` reads exactly that,
// so a `unauthorized` on an item moves it to `.failed` immediately — terminal, with screen 17
// printing "Sign in to send this" to somebody who is signed in (ERRATA E261 §3). The client's half
// of the fix is refresh-and-replay-once. This is the server's half:
//
//   - A missing, malformed or expired bearer token fails **here**, before any item is looked at, as
//     a single `unauthorized` on the whole request. That is the one the client refreshes on.
//   - No handler below may answer `unauthorized` for an item. An item that is not this identity's
//     to send is `forbidden` — see the sync handler, where that distinction is made per item and
//     stated in the same words.
//
// The two are different codes to the client's retry policy and they mean different things to a
// person: one is "your session lapsed, we fixed it, nothing was lost", the other is "this item was
// never yours to send".
func (s *Server) authenticated(next handlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.limiter.Allow(clientKey(r)) {
			apierr.Write(w, s.Log, apierr.New(apierr.RateLimited, "Too many requests. Try again shortly."))
			return
		}
		identity, err := s.resolveCaller(r)
		if err != nil {
			apierr.Write(w, s.Log, err)
			return
		}
		if err := next(w, r, identity); err != nil {
			apierr.Write(w, s.Log, err)
		}
	})
}

func (s *Server) operator(next publicFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		presented := bearer(r)
		if s.OperatorToken == "" || presented == "" ||
			!tokens.EqualHash(tokens.HashOpaque(presented), tokens.HashOpaque(s.OperatorToken)) {
			// `forbidden`, not `unauthorized`: an operator route is not a session the client
			// refreshes, and returning the code the transport retries on would have it replay a
			// takedown it has no credential for.
			apierr.Write(w, s.Log, apierr.New(apierr.Forbidden, "Not permitted."))
			return
		}
		if err := next(w, r); err != nil {
			apierr.Write(w, s.Log, err)
		}
	})
}

var errNoSession = apierr.New(apierr.Unauthorized, "Your session has expired.")

func (s *Server) resolveCaller(r *http.Request) (caller, error) {
	presented := bearer(r)
	if presented == "" {
		return caller{}, errNoSession
	}

	// An access token first: it is the common case.
	claims, err := s.Signer.Verify(presented)
	if err == nil {
		id, parseErr := uuid.Parse(claims.ID)
		if parseErr != nil {
			return caller{}, errNoSession
		}
		switch claims.Subject {
		case tokens.SubjectUser:
			// **One lookup, so the token cannot outlive the account by fifteen minutes.** Without
			// it a deleted account's access token still answered `GET /me/grove` with an empty
			// grove — which reads as "you have contributed nothing", not as "this account is gone"
			// — and a straggling `/sync` item took `server_error`, which is *retryable*, so it
			// burned the full 48 h backoff instead of the `duplicate` the tombstone gives.
			sessionID, sessionErr := uuid.Parse(claims.SessionID)
			if sessionErr != nil {
				return caller{}, errNoSession
			}
			live, lookupErr := s.Store.SessionIsLive(r.Context(), sessionID)
			if lookupErr != nil {
				return caller{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", lookupErr)
			}
			if !live {
				return caller{}, errNoSession
			}
			return caller{UserID: &id}, nil
		case tokens.SubjectDevice:
			// **No `DeviceUUID`, and that is deliberate rather than an omission.** Nothing mints a
			// signed device token — `registerDevice` issues an opaque one and this branch is
			// unreachable today — so there is no fact here to say which vocabulary `id` is in, and
			// guessing would put the same mismatch back one level down. Left nil, `applyOne`
			// refuses an item that names a device, which is the safe direction: whoever makes this
			// branch reachable has to decide what `id` means and set the field, and until then no
			// item is authorized by a claim nothing can check.
			return caller{DeviceID: &id}, nil
		default:
			// Fails closed. `Verify` already rejects an unknown subject, so this is unreachable —
			// and it used to *fall through* to the device-token lookup below, which made it a
			// second, weaker copy of a rule already held. A rule stated twice is a rule that can
			// disagree with itself.
			return caller{}, errNoSession
		}
	}
	if errors.Is(err, tokens.ErrExpired) {
		return caller{}, errNoSession
	}

	// A device token is opaque and checked against its row. D9 makes the anonymous queue the normal
	// case, so this path is not an exception — it is how a phone drains before there is an account.
	deviceID, deviceUUID, lookupErr := s.Store.DeviceTokenOwner(r.Context(), tokens.HashOpaque(presented))
	if lookupErr == nil {
		return caller{DeviceID: &deviceID, DeviceUUID: &deviceUUID}, nil
	}
	if !errors.Is(lookupErr, store.ErrNotFound) {
		return caller{}, apierr.Wrap(apierr.ServerError, "Something went wrong on our end.", lookupErr)
	}
	return caller{}, errNoSession
}

func bearer(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if value, ok := strings.CutPrefix(header, "Bearer "); ok {
		return strings.TrimSpace(value)
	}
	return ""
}

// clientKey is what the rate limiter buckets on.
//
// Fly puts the caller's address in `Fly-Client-IP`; `RemoteAddr` behind the proxy is the proxy.
// Getting this wrong would put every request in one bucket and rate-limit the whole app as if it
// were one phone, which is a denial of service written by hand.
//
// ── What actually protects this, stated because the public read makes it load-bearing ─────────
//
// **This header is supplied by the request, and the only thing that makes it trustworthy is that
// Fly's proxy overwrites it before the app ever sees it.** The adversarial review of the public
// read round measured the consequence: after exhausting a bucket, 25 of 25 requests carrying a
// self-chosen `Fly-Client-IP` were served, each allocating its own bucket. That is not a live
// exploit — nothing reaches this process except through the proxy — but until this round every
// route behind it also required a credential, and the public tree read requires none. The
// protection is now entirely "the proxy rewrote it", and that is worth writing down rather than
// being true by luck.
//
// Two things narrow it here rather than one comment pretending to:
//
//   - **A value that is not an IP address is not used.** A forged header could otherwise be any
//     string, so an attacker had an unbounded key space to allocate buckets in. `net.ParseIP`
//     costs nothing and takes that from 2^128 arbitrary strings to addresses.
//   - **The bucket map is bounded** — `ratelimit.maxBuckets`. Even with valid forged addresses the
//     memory this can be made to hold is capped, which is what matters on a 256 MB machine.
//
// Neither makes the header trustworthy, and neither is claimed to. **The fix is to stop trusting
// it unless the connection came from the proxy**, which is a trust-boundary change to a deployed
// service that nothing here can verify against a real Fly request — the review could not confirm
// the proxy's rewrite from a request it watched arrive either, only from documentation. It also
// bears directly on the owner's open question about whether this endpoint should be reachable
// from the open internet at all or only from the SSR machine, and answering it the other way
// makes this moot. `docs/ROADMAP.md` carries it, tied to that question.
func clientKey(r *http.Request) string {
	if ip := r.Header.Get("Fly-Client-IP"); net.ParseIP(ip) != nil {
		return ip
	}
	host, _, found := strings.Cut(r.RemoteAddr, ":")
	if !found {
		return r.RemoteAddr
	}
	return host
}

// ── Helpers ────────────────────────────────────────────────────────────────────────────────────

// maxBodyBytes caps a request body. A sync batch of a few dozen small mutations is kilobytes; the
// photo binary never comes through here (it goes straight to storage), so nothing legitimate is
// near this.
const maxBodyBytes = 4 << 20

func decodeBody(r *http.Request, into any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes))
	// Unknown fields are refused rather than ignored: this service and the client are versioned
	// together, and a field the server silently drops is a contribution silently not recorded.
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return apierr.Wrap(apierr.ValidationFailed, "That request could not be read.", err)
	}
	return nil
}

// decodeBodyLeniently ignores unrecognized keys.
//
// For `POST /sync`'s envelope, where strictness has the wrong blast radius: an additive top-level
// key would fail the whole batch with `validation_failed`, which is non-retryable, so a client
// following the taxonomy would lose its entire queue over a field it added. The strictness that
// matters — a dropped field silently losing a contribution — is applied inside each item, where the
// cost of being wrong is one row.
func decodeBodyLeniently(r *http.Request, into any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes))
	if err := decoder.Decode(into); err != nil {
		return apierr.Wrap(apierr.ValidationFailed, "That request could not be read.", err)
	}
	return nil
}

func writeJSON(w http.ResponseWriter, log *slog.Logger, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil && log != nil {
		log.Error("failed to encode response", "cause", err)
	}
}

func (s *Server) recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				s.Log.Error("panic", "path", r.URL.Path, "value", recovered)
				apierr.Write(w, s.Log, apierr.New(apierr.ServerError, "Something went wrong on our end."))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func parsePathUUID(r *http.Request, name string) (uuid.UUID, error) {
	id, err := uuid.Parse(r.PathValue(name))
	if err != nil {
		return uuid.Nil, apierr.New(apierr.ValidationFailed, "That identifier is not valid.")
	}
	return id, nil
}

// requestTimeout bounds a handler. One shared-cpu-1x machine cannot afford a query holding a
// connection open indefinitely.
//
// It is applied by `withTimeout` below, wrapping the whole router. It was previously declared with
// this comment and referenced by nothing, which is the kind of claim that reads as a guarantee
// while being a decoration — `go vet` does not flag an unused const, so nothing else was going to
// say so.
const requestTimeout = 20 * time.Second

func withTimeout(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), requestTimeout)
		defer cancel()
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
