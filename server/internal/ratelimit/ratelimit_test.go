package ratelimit

import (
	"strconv"
	"sync"
	"testing"
	"time"
)

// Spec §5.8 names rate limiting as *the* defense for `POST /devices/register` — the device
// credential "is not an attestation and does not claim to be: the defense against a flood is rate
// limiting." A defense with no tests is a claim.

func fixedClock() (*Limiter, func(time.Duration)) {
	now := time.Date(2026, 8, 9, 12, 0, 0, 0, time.UTC)
	var mu sync.Mutex
	limiter := New()
	limiter.now = func() time.Time {
		mu.Lock()
		defer mu.Unlock()
		return now
	}
	return limiter, func(d time.Duration) {
		mu.Lock()
		defer mu.Unlock()
		now = now.Add(d)
	}
}

func TestBurstIsAllowedThenRefused(t *testing.T) {
	limiter, _ := fixedClock()

	for i := 0; i < burst; i++ {
		if !limiter.Allow("1.2.3.4") {
			t.Fatalf("request %d of the burst was refused; the bucket is smaller than it claims", i+1)
		}
	}
	if limiter.Allow("1.2.3.4") {
		t.Fatal("the request after the burst was allowed; nothing is being limited")
	}
}

// TestTheBucketRefills pins the recovery, which is the half that makes `rate_limited` retryable
// honest: an item told to come back later must eventually get through.
func TestTheBucketRefills(t *testing.T) {
	limiter, advance := fixedClock()

	for i := 0; i < burst; i++ {
		limiter.Allow("1.2.3.4")
	}
	if limiter.Allow("1.2.3.4") {
		t.Fatal("not exhausted")
	}

	advance(refill)
	if !limiter.Allow("1.2.3.4") {
		t.Fatal("one refill period bought no token; a client following the backoff would never recover")
	}
	if limiter.Allow("1.2.3.4") {
		t.Fatal("one refill period bought more than one token")
	}
}

func TestRefillIsCappedAtBurst(t *testing.T) {
	limiter, advance := fixedClock()

	limiter.Allow("1.2.3.4")
	// A phone in a drawer for a day must not come back with a day's worth of tokens.
	advance(24 * time.Hour)

	allowed := 0
	for i := 0; i < burst*3; i++ {
		if limiter.Allow("1.2.3.4") {
			allowed++
		}
	}
	if allowed > burst {
		t.Fatalf("after a long idle the bucket allowed %d back-to-back requests, want at most %d", allowed, burst)
	}
}

// TestKeysAreIndependent is the assertion that would have caught the `Fly-Client-IP` mistake in the
// caller: one shared bucket would rate-limit the whole app as if it were one phone.
func TestKeysAreIndependent(t *testing.T) {
	limiter, _ := fixedClock()

	for i := 0; i < burst; i++ {
		limiter.Allow("1.2.3.4")
	}
	if limiter.Allow("1.2.3.4") {
		t.Fatal("the first key is not exhausted")
	}
	if !limiter.Allow("5.6.7.8") {
		t.Fatal("a second key was refused because the first was exhausted; every caller shares one bucket")
	}
}

// TestIdleBucketsAreEvicted pins the leak. Without eviction this map is keyed on every address that
// ever called, on a 256 MB machine.
func TestIdleBucketsAreEvicted(t *testing.T) {
	limiter, advance := fixedClock()

	for i := 0; i < 50; i++ {
		limiter.Allow(string(rune('a'+i%26)) + string(rune('0'+i/26)))
	}
	if len(limiter.buckets) == 0 {
		t.Fatal("no buckets were recorded")
	}

	advance(idleEviction + time.Minute)
	limiter.Allow("the-sweep-trigger")

	if len(limiter.buckets) != 1 {
		t.Fatalf("after the eviction window %d buckets remain, want only the one that just called",
			len(limiter.buckets))
	}
}

func TestConcurrentCallersDoNotRace(t *testing.T) {
	limiter := New()
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			limiter.Allow("1.2.3.4")
		}()
	}
	wg.Wait()
}

// TestTheBucketMapIsBoundedBetweenSweeps is N4 of the public-read round's adversarial review.
//
// `sweep` returns immediately unless thirty minutes have passed, so before `maxBuckets` the map
// grew without limit *inside* a window — one entry per distinct key, on a 256 MB machine, on the
// only route with no credential. The clock never advances here, so `sweep` cannot fire: whatever
// bounds the map is the pressure path and nothing else.
func TestTheBucketMapIsBoundedBetweenSweeps(t *testing.T) {
	frozen := time.Now()
	limiter := New().WithClock(func() time.Time { return frozen })

	for i := 0; i < maxBuckets*2; i++ {
		limiter.Allow(strconv.Itoa(i))
	}

	if len(limiter.buckets) > maxBuckets {
		t.Fatalf("%d buckets after %d distinct keys with the clock frozen, want at most %d — the "+
			"map grows without limit between sweeps", len(limiter.buckets), maxBuckets*2, maxBuckets)
	}
	// The control: it must not be bounded by having recorded nothing at all.
	if len(limiter.buckets) == 0 {
		t.Fatal("no buckets were recorded, so the bound above proves nothing about the bound")
	}
}

// TestPressureEvictsTheIdleAndKeepsTheRecent. A bound that emptied the map indiscriminately would
// hand every caller a fresh budget on demand — the flood succeeding by causing the defense.
//
// **The first version of this test was wrong and its red said so.** It tried to prove the property
// through a caller that had spent its burst, which cannot work: the bucket refills, so nobody stays
// exhausted while the clock moves, and the clock has to move for anything to become idle. It also
// created the flood at the current instant, where no key is evictable, so the fallback `clear` fired
// and took the caller with it — the test failed on its own construction rather than on the code. It
// asserts the discrimination directly instead.
func TestPressureEvictsTheIdleAndKeepsTheRecent(t *testing.T) {
	now := time.Now()
	limiter := New().WithClock(func() time.Time { return now })

	for i := 0; i < maxBuckets-1; i++ {
		limiter.Allow("idle-" + strconv.Itoa(i))
	}
	now = now.Add(2 * pressureEviction)

	limiter.Allow("the-recent-caller")
	if len(limiter.buckets) != maxBuckets {
		t.Fatalf("the control: %d buckets before the pressure insert, want exactly %d — this test "+
			"has to be *at* the cap for the next insert to trigger anything",
			len(limiter.buckets), maxBuckets)
	}

	limiter.Allow("the-key-that-triggers-the-bound")

	if _, kept := limiter.buckets["the-recent-caller"]; !kept {
		t.Errorf("the recent caller's bucket was evicted by pressure from %d idle keys; a caller "+
			"active within the last %v must keep its budget, or a flood buys everybody a reset",
			maxBuckets-1, pressureEviction)
	}
	if len(limiter.buckets) > 2 {
		t.Errorf("%d buckets remain, want the two recent ones — the idle keys were not evicted and "+
			"the bound is holding by emptying the map rather than by choosing", len(limiter.buckets))
	}
}
