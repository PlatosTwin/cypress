// Package apierr is the wire error taxonomy, and it is not this package's to invent.
//
// `Cypress/Core/APIError.swift` declares eight codes and a `retryable` property computed from the
// code itself, and `APIError.Envelope` decodes `{error: {code, message, retryable}}`. Every string
// and every boolean below was read from that file. The client treats its own table as binding and
// an unknown code decodes to `server_error`, so a code invented here would not fail loudly — it
// would arrive as a retryable server fault and an outbox item would sit on the backoff for 48 h
// over it. `TestTaxonomyMatchesTheClient` is what keeps the two tables the same table.
package apierr

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
)

// Code is one of the eight `APIError` raw values.
type Code string

const (
	Unauthorized       Code = "unauthorized"
	Forbidden          Code = "forbidden"
	NotFound           Code = "not_found"
	ValidationFailed   Code = "validation_failed"
	Conflict           Code = "conflict"
	ModerationRejected Code = "moderation_rejected"
	RateLimited        Code = "rate_limited"
	ServerError        Code = "server_error"
)

// All is the taxonomy in `APIError.allCases` order, so a test can compare the whole set rather
// than the codes somebody remembered to check.
var All = []Code{
	Unauthorized, Forbidden, NotFound, ValidationFailed,
	Conflict, ModerationRejected, RateLimited, ServerError,
}

// Retryable mirrors `APIError.retryable` exactly: only transient, server-side conditions.
//
// `conflict` is deliberately not retryable — `POST /trees`' proximity dedupe returns it with a
// candidate list only the person can resolve, and re-sending would not change the answer.
func (c Code) Retryable() bool {
	switch c {
	case RateLimited, ServerError:
		return true
	default:
		return false
	}
}

// Status is the HTTP status this code is served with.
//
// The status is a courtesy: the client reads the envelope's `code`, not the status line. It still
// has to be right, because a 401 is the one status the transport acts on structurally — it
// refreshes the session and replays the batch once (spec §5.8). Nothing but a lapsed or absent
// session may produce one; see the package comment on Unauthorized in auth.
func (c Code) Status() int {
	switch c {
	case Unauthorized:
		return http.StatusUnauthorized
	case Forbidden:
		return http.StatusForbidden
	case NotFound:
		return http.StatusNotFound
	case ValidationFailed:
		return http.StatusBadRequest
	case Conflict:
		return http.StatusConflict
	case ModerationRejected:
		return http.StatusUnprocessableEntity
	case RateLimited:
		return http.StatusTooManyRequests
	default:
		return http.StatusInternalServerError
	}
}

// Error carries a code, the sentence a person may see, and optional structured detail.
//
// Detail exists for exactly one case today — `conflict` from the 10 m proximity dedupe, which must
// carry the candidate list `ProximityConflict` is built to receive. It is a sibling of `error` in
// the body rather than a member of it, because `APIError.Envelope`'s nested container decodes
// `code`, `message` and `retryable` and would have to change to admit a fourth key.
type Error struct {
	Code    Code
	Message string
	Detail  any
	// Cause is logged and never serialized. A database error's text is not a person's business.
	Cause error
}

func (e *Error) Error() string {
	if e.Cause != nil {
		return string(e.Code) + ": " + e.Message + ": " + e.Cause.Error()
	}
	return string(e.Code) + ": " + e.Message
}

func (e *Error) Unwrap() error { return e.Cause }

// New builds an Error with no cause.
func New(code Code, message string) *Error {
	return &Error{Code: code, Message: message}
}

// Wrap builds an Error carrying an internal cause for the log.
func Wrap(code Code, message string, cause error) *Error {
	return &Error{Code: code, Message: message, Cause: cause}
}

// envelope is the wire shape, verbatim: `{error: {code, message, retryable}}`.
type envelope struct {
	Error  envelopeBody `json:"error"`
	Detail any          `json:"detail,omitempty"`
}

type envelopeBody struct {
	Code      Code   `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

// Write serializes err as the envelope and sets the status.
//
// A non-*Error reaches the client as `server_error` with a fixed sentence: an unclassified failure
// is a server fault by definition, and it is retryable, which is the answer that keeps a
// contributor's queued item alive rather than discarding it over a bug here.
func Write(w http.ResponseWriter, log *slog.Logger, err error) {
	var apiErr *Error
	if !errors.As(err, &apiErr) {
		apiErr = Wrap(ServerError, "Something went wrong on our end.", err)
	}
	if apiErr.Cause != nil && log != nil {
		log.Error("request failed", "code", apiErr.Code, "cause", apiErr.Cause)
	}

	body := envelope{
		Error: envelopeBody{
			Code: apiErr.Code,
			// `retryable` on the wire is the code's own property, never a per-response opinion.
			// The client prefers its local table anyway (`resolvedRetryable`); disagreeing with it
			// here would put a lie in a field nobody reads.
			Message:   apiErr.Message,
			Retryable: apiErr.Code.Retryable(),
		},
		Detail: apiErr.Detail,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(apiErr.Code.Status())
	if err := json.NewEncoder(w).Encode(body); err != nil && log != nil {
		log.Error("failed to encode error envelope", "cause", err)
	}
}
