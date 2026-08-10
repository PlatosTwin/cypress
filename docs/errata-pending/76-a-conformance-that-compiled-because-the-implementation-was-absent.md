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
2. **`CypressTests/APIConformanceGuardTests`**, eight gates, all measured off the working tree:
   - the requirement set is **parsed out of `Cypress/Data/API/CypressAPI.swift`** on every run, never
     listed by hand;
   - every conformance in the app target that a release build compiles must declare every
     requirement, compared on name, argument labels, parameter types and return type. A conformance
     is a **type**, not a declaration: its own body and every `extension <TypeName>` in the app
     target contribute, minus anything a release build does not compile;
   - the set of such conformances must be the two this file names, so a third cannot land
     unclassified and a fixture cannot be smuggled out from behind `#if DEBUG`;
   - no member of a `public extension CypressAPI` — instance method, **`static` method, computed
     `var` or `subscript`** — may be anything other than a protocol requirement; **E125's
     mechanism**, guarded at the source;
   - a complete conformance erased to `any CypressAPI` must reach its own witnesses for all 31
     calls, which is the same erasure every screen performs and the one E125 says a test holding the
     concrete type cannot see, with the probe's hand-written call list checked **both ways** against
     the parse;
   - `LocalAPI` — the conformance the shipped app actually holds — erased to `any CypressAPI` over
     a seeded store carrying one device-added tree and one device-held favorite must answer
     `speciesGuide` with a population count, `mapMembership(.favorites)` and `(.yours)` with that
     tree, and `deviceContributions()` with something held. Each answer differs from the default's,
     so each assertion separates the witness from the inheritance;
   - and two calibration gates ahead of all of them: two positive controls, two **negative**
     controls (`savePrivateReminder` and `outboxStatus` are named in prose inside the very file whose
     protocol body is parsed, and are not requirements), the shared source-file floor, and the
     conditional-compilation classification checked branch by branch.

Effects (`async`, `throws`) are deliberately **not** compared: a synchronous non-throwing witness
legally satisfies an `async throws` requirement, so comparing them would red a conformance that is
in fact complete.

#### The half of it that was wrong, and how it was found

The first version of this guard shipped to review with all six gates green **and the defect present**,
which is the failure mode this repository names as its dominant one. `Parser.debugRegions` decided
whether a region was DEBUG-only by asking whether the `#if` line *contained* the substring `DEBUG`,
kept that verdict through `#else`, and was consulted only for the position of a **type declaration**.
Three shapes defeat that, and the reviewer demonstrated all three live rather than arguing them:

- `#if DEBUG … #else <conformance> #endif` — the `#else` branch is what a **release** build compiles,
  and it was being marked debug-only, so a release-only conformance was filed as a preview double and
  never asked to declare anything. It then inherited all fourteen defaults, `mapMembership → []` and
  `deviceContributions → .none` among them.
- `#if !DEBUG <conformance> #endif` — `contains("DEBUG")` matches the negation, same result.
- `#if DEBUG` **inside** a shipping conformance's body — the classification was never applied to
  members at all, so a requirement declared there counted as declared while the release build
  inherited the default. **This shape is already in the tree**: `LocalAPI.swift` carries a 330-line
  `#if DEBUG` region inside its conformance body.

With two of the three present, on a build that really recompiled, the whole suite reported green.

The fix is a real directive stack — `#if` pushes, `#elseif` replaces the top, `#else` replaces the top
with **false**, `#endif` pops, and a condition counts as debug-only only when it is *exactly* `DEBUG`
— applied to members as well as to declarations. Anything the scan cannot classify is treated as
release-compiled, which is the direction that fails loudly.

**The lesson is not "the parser had a bug".** The old comment on that function asserted the safe
direction as an obvious property — *"a conformance this misses is classified as shipping, which is the
direction that fails loudly"* — and that sentence was false for the three cases above. It was written
because it seemed self-evident, and this repository's rule is that a confident comment is where bugs
survive. The claim is now true because a gate makes it true:
`theDirectiveStackClassifiesEachBranch` feeds eleven directive shapes to the scanner and checks each
against an answer known before it ran, including a positive control, without which the whole gate
could pass by the scan marking nothing at all.

#### The trap this guard had to avoid, and the case that was constructed to check it

A guard that enumerates a protocol's requirements from a hand-written list passes on the day somebody
adds a thirty-second requirement and forgets the list — green precisely when its condition is
present, which is this repository's dominant defect class. The existential probe **is** such a list:
Swift cannot generate calls from a protocol, so 31 call sites are written out by hand. It is tied
back to the parse — the probe records which requirement it reached, and the test asserts the observed
names cover the *parsed* requirement set — so an unprobed requirement fails the test rather than
quietly shrinking it.

Eight defect cases were constructed and run, each red for the reason named — four before review, and
four more against the conditional-compilation family review found:

- **the tree as it stood on main.** `RemoteAPI (Cypress/Data/API/RemoteAPI.swift) does not declare
  14 of 31 CypressAPI requirements` — and all fourteen listed by signature.
- **a witness behind `#if DEBUG` inside a shipping conformance body** (the reviewer's shape (a)):
  `… does not declare 1 of 31 … · mapMembership(_: MapMembership) -> Set<UUID>`.
- **a conformance in an `#else` branch, and one under `#if !DEBUG`** (shapes (b) and (c)). Neither is
  compiled by the Debug test build at all, which is precisely why a *source* scan has to see them:
  `the app target's non-#if DEBUG CypressAPI conformances are ["LocalAPI", "ReleaseOnlyElseAPI",
  "ReleaseOnlyNegatedAPI", "RemoteAPI"]`, plus `… does not declare 31 of 31 …` for each.
- **a `var` and a `static func` in `extension CypressAPI`**, E125's mechanism in the two shapes the
  first version of gate 5 filtered out: `2 member(s) of extension CypressAPI are not protocol
  requirements: · static func makeDefault() -> Int · var apiFlavor`.
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

And one on the classification rather than the count: `RemoteAPI` wrapped in `#if DEBUG` produces
`the app target's non-#if DEBUG CypressAPI conformances are ["LocalAPI"], and this file expects
["LocalAPI", "RemoteAPI"]`.

One case was run the other way, to check that a correct conformance is not reported as broken: a real
`exportLatest` witness moved into `public extension RemoteAPI { … }` — which is what #158 will do to
that file once 31 bodies need `// MARK:` sections — leaves gate 3 **green**. Before review it did not:
it reported the method missing and diagnosed a protocol-extension default that was not in force.

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
The reviewer put eight reformattings through it — wrapped parameter lists, `where` clauses, attribute
prefixes — without producing a false green, which is evidence about those eight and not a proof about
the ninth. The one family that did break it was conditional compilation, and that family now has its
own gate.

**Three of the four value-returning defaults are checked live; the fourth cannot be, and the reason
is worth recording because the first version of this entry got it wrong.** That version claimed three
of the four were indistinguishable from the real implementation. They are — over an *empty* store,
which is a fact about the fixture and not about the requirements. Given one device-added tree and one
device-held favorite, `mapMembership(.favorites)`, `mapMembership(.yours)` and `deviceContributions()`
all separate from `[]` and `.none` at once. The claim was measured rather than argued in review, and
the correction matters in the direction that stings: those two are exactly the pair that answered
**silently on the tree as it stood**, so a gate covering only `speciesGuide` covered the case that
becomes dangerous at #158 step 4 and neither case that was live.

`isFavorite` is the one that genuinely does not separate, and that is a finding rather than a gap in
the fixture. Its default is `grove().first { … }?.isFavorite`, and `grove()` is `LocalAPI`'s own
witness — so the default reaches the real implementation and computes the right answer. There is
nothing for a test to catch, because the difference between the default and the witness is one
indexed SELECT against a whole-list read (#167): a cost, not an answer. Gate 4 is what holds
`isFavorite` to being declared, and gate 4 is a structural gate for exactly this reason.

**The erasure gate was red-proved too**, since three assertions passing in 37 ms is the kind of
number that deserves a control: deleting `LocalAPI`'s `mapMembership` and `deviceContributions` so
the extension defaults become the witnesses turns it red on all three —
`mapMembership(.favorites) came back without a tree this device has hearted (0 member(s))`,
the same for `.yours`, and `deviceContributions() reported nothing held`.
