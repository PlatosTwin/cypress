// Package ratelimit is the flood defense for the device credential.
//
// Spec §5.8 is explicit that `POST /devices/register` "is not an attestation and does not claim to
// be: the defense against a flood is rate limiting, and `rate_limited` is already in the taxonomy
// and already retryable." This is that defense, and its retryability is the reason it is a safe one
// — an honest client that trips it keeps its queued items alive on the backoff rather than losing
// them, which is what `APIError.rateLimited.retryable == true` buys.
//
// In memory, because there is one machine (R72). A second machine would need this in Postgres or
// Redis, and that is a deployment decision rather than a code one — noted here so the assumption is
// visible rather than discovered when the machine count changes.
package ratelimit

import (
	"sync"
	"time"
)

const (
	// burst is how many requests a key may make back to back. A drain sends one `POST /sync` with a
	// batch in it, plus a photo begin per binary, so a normal minute for one phone is single
	// digits.
	burst = 60
	// refill is how fast the bucket refills, per key.
	refill = time.Second
	// idleEviction is how long an untouched bucket is kept. Without it this map is a slow leak
	// keyed on every address that ever called.
	idleEviction = 30 * time.Minute
)

type bucket struct {
	tokens   float64
	lastSeen time.Time
}

// Limiter is a token bucket per key.
type Limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
	// sweptAt is when eviction last ran, so it is amortized rather than scheduled.
	sweptAt time.Time
}

// New builds a limiter on the wall clock.
func New() *Limiter {
	return &Limiter{buckets: map[string]*bucket{}, now: time.Now}
}

// WithClock replaces the clock. Test seam: a rate limiter tested on the wall clock either sleeps
// or asserts nothing.
func (l *Limiter) WithClock(now func() time.Time) *Limiter {
	return &Limiter{buckets: map[string]*bucket{}, now: now}
}

// Allow reports whether the key may proceed, and spends a token if so.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.sweep(now)

	existing, found := l.buckets[key]
	if !found {
		l.buckets[key] = &bucket{tokens: burst - 1, lastSeen: now}
		return true
	}

	elapsed := now.Sub(existing.lastSeen)
	existing.tokens += elapsed.Seconds() / refill.Seconds()
	if existing.tokens > burst {
		existing.tokens = burst
	}
	existing.lastSeen = now

	if existing.tokens < 1 {
		return false
	}
	existing.tokens--
	return true
}

func (l *Limiter) sweep(now time.Time) {
	if now.Sub(l.sweptAt) < idleEviction {
		return
	}
	l.sweptAt = now
	for key, existing := range l.buckets {
		if now.Sub(existing.lastSeen) > idleEviction {
			delete(l.buckets, key)
		}
	}
}
