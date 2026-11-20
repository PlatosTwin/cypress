# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from the web round's orchestration session, 2026-09-10. Continues
# `docs/rulings-pending/web-round-owner-decisions.md`; these are the fourth question round, taken
# after the privacy round (PR #163) and the polygon investigation reported.

### The web round's fourth decision round (owner-ratified, 2026-09-10)

**8. The owner ratifies the refusal of §W1's recent-visits panel and its photo count.**

Both are drawn in a transcribed screen and in the mock, so refusing them is a deviation from the
owner's own specification — which is why it was put to the owner rather than settled by the author.

**Ratified as refused.** The grounds, each checked against its source rather than cited from memory:
a dated visit feed is public user location history, which `PRODUCT.md` marks **Never**; `contributions`
carries no moderation state, no takedown path and no screening — unlike `photos`, which has all three
— so its free text would be unscreenable on a search-indexed page; and its rows carry unadjudicated
claims (`appearsDead` / `appearsRemoved` open review flags, `StructureFlag`'s verbatim disclaimer).
The photo count fails R27.1 §2's three-person k-anonymity floor, and suppressing it below that floor
would itself disclose "fewer than three people" — R27.1 §5 already answered this exact count no, and
F16's refusal is the same rule.

**The cost was stated when the question was put and is accepted:** the visits panel is the warmest
thing on the page. Without it the fact column is six rows of numbers, and the human evidence that
anyone loves this tree is gone. **Decision 10 is what answers that**, and it is the reason this
refusal does not leave the page cold.

The deviation is an **errata entry** against §W1, not a silent omission.

**9. Tree naming gets its own round, done properly. It is not bolted on.**

§W1's H1 is `Grandmother Cypress` and **nothing in this system can produce it** — there is no name
column in the seed contract or in `AppSchema`. Three options were put: fall back to the species name
and ship; design naming properly as its own round; or add the column now and moderate later.

**The owner took the second, and refused the third explicitly by taking it.** A contributed, public,
search-indexed H1 in 42px serif is unmoderated free text on the most prominent element of the page,
and this system has **no moderation machinery for text at all**. "Handle abuse when it appears" was
put with that stated and was not chosen.

The round it creates — call it **W-H** — owes a naming design, a moderation path for text, and a
schema migration, and it is a design round under DECISIONS constraint 21 before it is a code round.

> **Interpretation taken by the orchestrator, stated because it is load-bearing and was not asked.**
> The ruling is about *how naming is built*, not about *when W1 ships*. **W-C is therefore not blocked
> on W-H.** The public tree page ships with the species name as its H1 — noting that `common_name` is
> null on real rows, so the fallback is often the scientific name — and gains contributed names when
> W-H lands. The alternative reading, that W1 waits for naming, would stall the entire web version
> behind a design round plus a migration seat, which is not what "run autonomously to make this
> happen" asks for. **Swapping the H1's source later is a small change; blocking on it is not.**
> Overturnable in one sentence.

**10. The beloved state ships on the public tree page — as a state, not a rank.**

R27.1 authorizes the mechanism and it is **the one count this project has ruled publishable**: trees
ordered by distinct favoriters, with a floor of at least three people. The orchestrator recommended
deferring it; **the owner overruled and took it**, which restores the discovery signal R27.1 exists
for — the owner's own words there being *"part of the point of the app is to bring people TO trees."*

**A tree page is a per-tree surface where a position in an ordering means nothing**, so the published
form is the state — *beloved* or not — never a rank and never the number behind it.

> **A dependency this ruling has and the question round did not price.** The floor is supposed to be
> chosen from the real distribution rather than picked, and R27.1 leaves it open pending exactly that
> measurement. **There may not yet be a distribution to measure**: contributions only recently began
> reaching the server at all, and the ROADMAP records that M5 shipped deliberately with no backend.
> The round that builds this must **measure first and say what it found**. If the production
> distribution is too thin to choose a floor from, it ships on R27.1's provisional three and says so
> in the ruling, rather than inventing a threshold and presenting it as measured. A floor chosen from
> no data is a number with a decimal point and nothing behind it.

**11. San Jose ships 295 of its 297 polygons. No migration.**

`neighborhoods.name` is `NOT NULL UNIQUE`; San Jose's layer 549 has 297 features and **295 distinct
names** — two `Commercial`, two `Guadalupe`, the Guadalupes 8 km apart. CLAUDE.md makes a migration a
stop-and-ask ("one migration author per round, named explicitly"), so it was one.

**The owner took the no-migration path.** 155 of 52,775 San Jose trees (0.29%) keep a null
`neighborhood_id` — a state the app already handles correctly, because it is every non-SF tree today.

Disambiguating the names at ingest was refused for the reason it was offered with: calling a
neighborhood something the city does not call it is **invented civic content under DECISIONS
constraint 15**, and it would put a fabricated name in front of readers.

**Recorded as a known, deliberate gap, and the constraint stays wrong.** Neighborhood names are not
globally unique and two Guadalupes are the proof; the `UNIQUE` will bite again on the next city with
a repeated name. The ingest round writes an errata entry saying which two polygons were dropped and
why, so the next person to find 295 where the city publishes 297 finds the decision rather than a
defect.

### Taken by the orchestrator under the autonomy grant, not by the owner

Both were W-G's recommendations, both reversible, both recorded so they can be overturned on the
merits rather than rediscovered.

**12. Published dates are truncated to the month.** The value's date is part of the value; the *day*
is where the contributor was. Year precision would lose real information — a reading from January and
one from December are a growing season apart, and the growth-charting work depends on the interval.
This is the same move as the 25 m photo grid: blunt the precision rather than withhold the fact.
*Known cost:* same-season readings are unorderable on the public surface, so a public growth chart
built later has month-resolution x-values. The richer alternative — day precision only above a
contributor floor — is more machinery than v1 needs and is recorded rather than taken.

**13. The public read is reachable from the open internet, with its own rate limiter**, rather than
locked to the Fly private network. It is the beginning of the API a researcher would cite, which
`PRODUCT.md` names as the real adoption path, and it is testable from anywhere. *Known cost:* it is
the only unauthenticated surface this service has. **Revisited at W-E with the deployment in front of
us**, deliberately, rather than settled by whichever deployment lands first.
