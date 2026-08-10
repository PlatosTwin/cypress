### Four things building the sync service found (task #158 step 2)

The Go service in `server/` replacing the R36 placeholder, under RULINGS **R72**. None of these is
part of what the owner ruled; they are facts about the code and the deployment that outlive the
implementation round, and three of them are defects that would have shipped.

---

#### 1. The placeholder image had no CA certificates, and the first symptom would have been a broken sign-in

`server/Dockerfile` built `FROM scratch`. That was correct for what it held — a placeholder that
answered `501` and made no outbound call — and it is wrong the moment the service verifies an Apple
identity token, because `scratch` carries no trust store.

The failure mode is the reason this is worth an entry rather than a commit message. It is **not** a
boot failure: the machine starts, `/health` answers, `flyctl deploy` reports success, and the first
`GET https://appleid.apple.com/.well-known/openid-configuration` fails with
`x509: certificate signed by unknown authority`. So the tell arrives at the *first person who tries
to sign in*, wearing the costume of an auth bug — and every layer is behaving exactly as written.

Fixed here by copying `/etc/ssl/certs/ca-certificates.crt` out of the build stage. Recorded because
the same trap is waiting for any future `scratch` image in this repository, and because "it deployed
green" is not evidence about a code path nothing exercised at deploy time.

#### 2. `coreos/go-oidc/v3` requires Go ≥ 1.25, so the toolchain floor moved

The placeholder pinned `go 1.23` and `golang:1.23-alpine`. `coreos/go-oidc/v3` at v3.20.0 declares
`go >= 1.25.0`, and adding it silently upgraded the `go` directive in `server/go.mod`.

Nothing in R72's argument turns on this — "no runtime to patch" is about not shipping an
interpreter, not about the compiler version — but the Dockerfile's base image and the module's `go`
line have to move together, and a mismatch between them is a build failure with a message about
language versions rather than about the image. Both are now `1.25`, and the Dockerfile says why.

#### 3. The client has no wire encoder for `/sync`, so this service is the first definition of that contract

`OutboxPayload`'s coding comment (`Cypress/Data/Outbox/OutboxPayload.swift`) states it plainly:
keys stay the Swift property names, dates are ISO-8601, and *"the wire mapping to §6's snake_case
belongs in `RemoteAPI`, not here."* `RemoteAPI` is the stub, so **that mapping does not exist
anywhere in the app**.

The consequence for sequencing: the request and response shapes in `server/internal/api/` are the
first and currently only statement of what `POST /sync`, `POST /photos/begin` and the Class R reads
look like on the wire. One piece of the contract *is* pinned on both sides —
`APIError.Envelope`'s `{error: {code, message, retryable}}`, and
`server/internal/apierr/apierr_test.go` reads `Cypress/Core/APIError.swift` directly so the two
taxonomies cannot drift silently. Everything else is pinned on one side only.

That is not a defect in either half; it is a gap that looks closed because both halves compile. The
step that closes it is #158 step 4, and whoever writes `RemoteAPI`'s bodies should treat these
handlers as the specification rather than re-deriving one — or, better, add the encoder-side guard
that `apierr` already has.

#### 4. A guard can be green because the invariant is held somewhere better, and the difference is only visible under a red-proof

`ClaimDevice`'s sweep carries `AND anonymized_at IS NULL`, mirroring the client's
`notAnonymized(table)` clause: a row a deletion unlinked must not be adoptable by the next person to
sign in on that phone. Removing that predicate leaves its test **green**.

Chasing it rather than accepting the green found the reason, and the reason is reassuring: an
account deletion clears `device_id` as well as `user_id` **on `contributions`**, so an anonymized
contribution never matches `WHERE device_id = $3` in the first place. The predicate is defense in
depth over a case the deletion has already made unreachable.

Stated precisely, because the first draft of this entry overreached: that is true of `contributions`
and **not** of `photos`, where the deletion sets `deleted_at`, `user_id` and `anonymized_at` and
leaves any `device_id` standing. The conclusion survives by a different route there — a photograph
with `deleted_at` set is invisible under both of `Photo`'s predicates whoever ends up owning it — but
it is a different argument, and a sentence that covered both with one mechanism was wrong about one
of them. It earns its keep only if the sweep is *also* broadened —
drop the device scope and the predicate together and it does go red, from the
`contributions_owner` CHECK, because setting `user_id` on a row carrying `anonymized_at` satisfies
neither arm of it.

So the invariant is held three deep: the deletion makes it unreachable, the predicate makes it
explicit, the CHECK makes it unstorable. **The entry is the method, not the finding.** A red-proof
that stays green has two readings — the guard is decorative, or the guard is a backstop behind
something stronger — and they are indistinguishable until the defect is localized by mutating one
thing at a time. This project's standing rule is that a guard must be able to fail; the corollary
found here is that a guard which *cannot* be made to fail is a question, not a pass. The pair of
mutations is recorded in the test itself so the next reader inherits the answer instead of the
question.
