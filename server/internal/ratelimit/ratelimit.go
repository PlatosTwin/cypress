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

	// maxBuckets bounds the map between sweeps.
	//
	// `sweep` returns immediately unless thirty minutes have passed, so until this constant the
	// map could grow without limit *inside* a window — one entry per distinct key, on a
	// `shared-cpu-1x`/256 MB machine, reachable now on a route with no credential at all. Found by
	// the adversarial review of the public tree read.
	//
	// Fifty thousand buckets is single-digit megabytes at roughly a hundred bytes each. It is far
	// above any honest traffic this service will see for a long time — every phone in a local beta
	// is one key, and a crawler is one key — and far below what would trouble the machine.
	maxBuckets = 50_000

	// pressureEviction is the idle horizon used when the map is at `maxBuckets`, rather than
	// `idleEviction`. A minute is long enough that a caller in an active burst keeps its bucket and
	// short enough that a flood of one-request keys is mostly evictable.
	pressureEviction = time.Minute
)

// The budget above is one caller's, and it is sized for **a phone**. A second limiter exists for the
// public read, and it needs a different one for a reason that is a property of the deployment rather
// than of the endpoint: the public web is server-side rendered, so every reader in the world arrives
// from one address — the rendering machine's. Reusing this budget there would throttle the whole
// site to one page per second, which is `clientKey`'s own warning arriving from the other direction.
//
// So the budget became a field. `New` keeps the constants above and every existing caller is
// unchanged; `NewWithBudget` is what the public read uses.
const (
	// publicReadBurst and publicReadRefill size the public tree read: 120 back to back, then one
	// token per 50 ms — 20 per second sustained, per address.
	//
	// Sized against what the endpoint costs rather than against what a phone does. It is one
	// indexed read per field group on `idx_contributions_tree`, it writes nothing, it returns a
	// bounded body, and it holds no secret. Twenty per second is roughly a hundred times a reading
	// human and comfortably above a search engine crawling this site's own pages; it is far below
	// what would trouble Postgres, and it still holds the line that matters — one address cannot
	// monopolize the single machine R72 sizes this service to.
	publicReadBurst  = 120
	publicReadRefill = 50 * time.Millisecond
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
	// burst and refill are this limiter's budget. Fields rather than the package constants,
	// because two limiters with two callers need two sizings — see the constants above.
	burst  float64
	refill time.Duration
	// sweptAt is when eviction last ran, so it is amortized rather than scheduled.
	sweptAt time.Time
}

// New builds a limiter on the wall clock, at the device budget.
func New() *Limiter {
	return NewWithBudget(burst, refill)
}

// NewPublicRead builds the public read's limiter, at its own budget.
//
// A separate instance rather than a shared one so the two cannot spend each other's tokens: a flood
// of anonymous page reads must not exhaust the bucket a contributor's outbox drains through, and a
// busy drain must not throttle the website.
func NewPublicRead() *Limiter {
	return NewWithBudget(publicReadBurst, publicReadRefill)
}

// NewWithBudget builds a limiter with an explicit budget.
func NewWithBudget(burst float64, refill time.Duration) *Limiter {
	return &Limiter{buckets: map[string]*bucket{}, now: time.Now, burst: burst, refill: refill}
}

// WithClock replaces the clock. Test seam: a rate limiter tested on the wall clock either sleeps
// or asserts nothing.
//
// **The budget travels with it**, which is not decoration: this returns a *new* limiter, so a
// version that forgot to copy the two fields would hand back a limiter whose burst is zero and
// whose refill is never — refusing everything, in a test seam, which is the shape of harness bug
// that costs a day.
func (l *Limiter) WithClock(now func() time.Time) *Limiter {
	return &Limiter{buckets: map[string]*bucket{}, now: now, burst: l.burst, refill: l.refill}
}

// Allow reports whether the key may proceed, and spends a token if so.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.sweep(now)

	existing, found := l.buckets[key]
	if !found {
		if len(l.buckets) >= maxBuckets {
			l.evictUnderPressure(now)
		}
		l.buckets[key] = &bucket{tokens: l.burst - 1, lastSeen: now}
		return true
	}

	elapsed := now.Sub(existing.lastSeen)
	existing.tokens += elapsed.Seconds() / l.refill.Seconds()
	if existing.tokens > l.burst {
		existing.tokens = l.burst
	}
	existing.lastSeen = now

	if existing.tokens < 1 {
		return false
	}
	existing.tokens--
	return true
}

// evictUnderPressure bounds the map when it has reached `maxBuckets` inside a sweep window.
//
// **What this buys and what it does not, said plainly.** It buys a memory bound: the map cannot
// grow past the cap by much, whatever the key space. It does **not** buy a stronger rate limit —
// a caller who can mint distinct keys already gets a fresh bucket per key, with or without this,
// so evicting an idle bucket hands nothing away that was not already available. The failure this
// prevents is the machine running out of memory, which takes the whole service down for everybody;
// the failure it does not prevent is `clientKey`'s, and that one is `clientKey`'s to state.
//
// One pass at the shorter horizon. If that frees nothing — every bucket active within the minute,
// which at fifty thousand keys is a flood rather than a Tuesday — the map is emptied rather than
// grown: bounded memory is the property being defended, and a reset bucket is the same thing a
// fresh key already gets.
func (l *Limiter) evictUnderPressure(now time.Time) {
	for key, existing := range l.buckets {
		if now.Sub(existing.lastSeen) > pressureEviction {
			delete(l.buckets, key)
		}
	}
	if len(l.buckets) >= maxBuckets {
		clear(l.buckets)
	}
	l.sweptAt = now
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
