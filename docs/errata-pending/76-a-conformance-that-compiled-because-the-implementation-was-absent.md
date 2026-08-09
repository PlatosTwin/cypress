### A conformance that compiled *because* the implementation was absent, and the guard that ends it (task #76)

#### The defect

`CypressAPI` carries **31 requirements**. `RemoteAPI` declared **17** of them. The other 14 were
satisfied by `public extension CypressAPI` defaults spread over ten files, so the type conformed,
the build was green, and nothing anywhere said that more than a third of the boundary had no
implementation behind it. That is not a bug in the defaults — a default is exactly what it looks
like — it is a bug in what "conforms" is being read to mean. Under the owner's full-API-surface
ruling for #158 (`docs/design-proposals/2026-08-09-task158-live-layer.md` §1, §3.3), `RemoteAPI` is
declared complete, and the type system reports success *precisely because* the implementation is
absent.

Ten of the fourteen defaults throw `.notFound`, which is survivable: an error is a thing a screen
can render honestly. Four **return a value**, which is not:

| requirement | default | file |
| --- | --- | --- |
| `speciesGuide(id:near:)` | the field-guide entry with no population facts | `SpeciesGuide.swift` |
| `mapMembership(_:)` | `[]` | `MapMembership.swift` |
| `deviceContributions()` | `.none` | `DeviceContributions.swift` |
| `isFavorite(treeID:)` | derived from `grove()` | `CypressAPI.swift` |

Rendered, those are a species guide with no population line, a map on which the reader owns and
hearts no tree in the city, a device that has contributed nothing, and a heart that reads false.
None of them throws and none of them logs.

#### What the ticket's premises got right, and the one thing they did not

The counts hold exactly: 31 requirements, 17 declared, 14 inherited, ten throwing, four
value-returning. What is worth recording is that **two of the four were only accidentally loud.**
`speciesGuide`'s default body is `SpeciesGuide(species: try await species(id: id))` and
`isFavorite`'s is `try await grove().first { … }`, so on `RemoteAPI` as it stood both *did* throw —
by borrowing the refusal of a neighbouring stub one call down. That is an artifact of which methods
happened to be written first, and it evaporates at step 4 of the #158 plan, the moment `species(id:)`
and `grove()` become real network calls. Only `mapMembership` and `deviceContributions` answered
silently on the tree as it stood; the other two were scheduled to start.

This matters for sequencing rather than for blame: the window in which this defect is *invisible*
opens wider as the implementation proceeds, which is the concrete form of the spec's "before or
alongside, never after."

#### The fix

Two halves, and neither is an API implementation — #76 is the guard, #158 is the implementation.

1. **`RemoteAPI` now declares all 31 requirements.** Thirteen of the fourteen new bodies are
   `throw unimplemented` (`.serverError`, retryable, so an outbox item that reaches one survives on
   the backoff). The fourteenth is `deviceContributions()`, which returns `.none` — the spec's
   **Class D**, device-only and never remote — written down with its reason beside it rather than
   arrived at by having nothing to say.
2. **`CypressTests/APIConformanceGuardTests`**, six gates, all measured off the working tree:
   - the requirement set is **parsed out of `Cypress/Data/API/CypressAPI.swift`** on every run, never
     listed by hand;
   - every conformance in the app target that is *not* behind `#if DEBUG` must declare every
     requirement, compared on name, argument labels, parameter types and return type;
   - the set of such conformances must be the two this file names, so a third cannot land
     unclassified and a fixture cannot be smuggled out from behind `#if DEBUG`;
   - no member of a `public extension CypressAPI` may be anything other than a protocol requirement
     — **E125's mechanism**, guarded at the source;
   - a complete conformance erased to `any CypressAPI` must reach its own witnesses for all 31
     calls, which is the same erasure every screen performs and the one E125 says a test holding the
     concrete type cannot see;
   - and a calibration gate ahead of all of them, with two positive controls, two **negative**
     controls (`savePrivateReminder` and `outboxStatus` are named in prose inside the very file whose
     protocol body is parsed, and are not requirements), and the shared source-file floor.

Effects (`async`, `throws`) are deliberately **not** compared: a synchronous non-throwing witness
legally satisfies an `async throws` requirement, so comparing them would red a conformance that is
in fact complete.

#### The trap this guard had to avoid, and the case that was constructed to check it

A guard that enumerates a protocol's requirements from a hand-written list passes on the day somebody
adds a thirty-second requirement and forgets the list — green precisely when its condition is
present, which is this repository's dominant defect class. The existential probe **is** such a list:
Swift cannot generate calls from a protocol, so 31 call sites are written out by hand. It is tied
back to the parse — the probe records which requirement it reached, and the test asserts the observed
names cover the *parsed* requirement set — so an unprobed requirement fails the test rather than
quietly shrinking it.

Four defect cases were constructed and run, each red for the reason named:

- **the tree as it stood on main.** `RemoteAPI (Cypress/Data/API/RemoteAPI.swift) does not declare
  14 of 31 CypressAPI requirements and would inherit a protocol-extension default for each:` — and
  all fourteen listed by signature.
- **a witness whose signature does not match.** `RemoteAPI.mapMembership` returning `[UUID]` instead
  of `Set<UUID>` compiles, does not satisfy the requirement, and leaves the default in force. This
  is the case a label-only comparison would have passed. `… does not declare 1 of 31 … ·
  mapMembership(_: MapMembership) -> Set<UUID>`.
- **E125's shape.** `mapMembership` removed from the protocol, its extension default left in place:
  `1 member(s) of extension CypressAPI are not protocol requirements`, and, separately, from the live
  half — `mapMembership: returned a value — a protocol-extension default answered it`.
- **the drift case.** A thirty-second requirement added with a value-returning default and no probe:
  `LocalAPI … does not declare 1 of 32`, `RemoteAPI … does not declare 1 of 32`, and `1 CypressAPI
  requirement(s) have no call in this test, so nothing here can tell whether they dispatch:
  neighborhoodDigest.`

A fifth, on the classification rather than the count: `RemoteAPI` wrapped in `#if DEBUG` produces
`the app target's non-#if DEBUG CypressAPI conformances are ["LocalAPI"], and this file expects
["LocalAPI", "RemoteAPI"]`.

#### What it does not check, said out loud

That a declared method is *correct*. `throw .serverError` satisfies every gate here and should: the
whole reason the spec sequences #76 before #158 is that a conformance which compiles with fourteen
methods missing cannot tell anyone whether the fifteenth was written.

It does not police the fourteen `#if DEBUG` preview doubles or the seventeen test doubles. A default
answering `[]` in an Xcode canvas is a fixture; the same default reached from a shipped screen is the
defect, and `CypressAPI`'s own "two methods that were requirements and are not any more" note is the
argument for not taxing thirty-one fixtures to say so.

And it reads Swift with a small scanner rather than a real parser. It handles the declaration shapes
this repository writes; a shape it cannot read fails as a mismatch, which is red rather than green.
