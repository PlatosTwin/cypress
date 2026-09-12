# The OpenGraph card, rasterized — and two things found on the way

*Unnumbered; written on branch `web/og-raster`, based on `web/w1-tree-page` (#175). The
orchestrator splices these under their real numbers at merge.*

---

### The page declared the card's type and never its size

`src/layouts/Base.astro` published `og:image` and `og:image:type` and stopped there.
`src/lib/ogCard.ts` has stated `CARD_WIDTH = 1200` and `CARD_HEIGHT = 630` since the card was
written, and `og.svg.ts` served exactly that — so the code and the markup did not *disagree*, which
is why nothing caught it. **The markup was silent.**

That is not cosmetic for the consumers this card exists for. A crawler that lays out a preview
before it has fetched the image sizes it from the tags: Slack's unfurl and LinkedIn's post composer
both do, and both fall back to a small square or a link-sized thumbnail when the tags say nothing.
The card was correctly 1200×630 and was being previewed as if nobody knew that.

The repair makes `width` and `height` **required** on `Base.astro`'s `openGraph.image`, not
optional — an optional one is the same omission with a default in front of it — and W1 passes
`CARD_WIDTH`/`CARD_HEIGHT` rather than two literals, so the tags cannot drift from the drawing.
`web/test/ogRaster.test.ts` asserts the shell emits all four tags and that the page hands it the
card's own constants.

**What was checked and is fine:** the `twitter:card` value. `summary_large_image` wants a raster at
or above 300×157 with a 2:1-ish aspect, and 1200×630 satisfies it — it was, however, being
advertised alongside an `og:image` of a type Twitter does not decode, which made the tag a promise
about nothing.

---

### `web.yml`'s `paths:` parser stopped at the first entry with a comment after it

`web/test/pack-versions.test.ts` reads the workflow's two `paths:` filters and asserts that every
out-of-`web/` file the suite opens is on both. Its line parser matched
`- '‹path›'` **anchored at end of line**. `web.yml` writes one entry as

```yaml
      - 'Cypress/DesignSystem/Tokens/**'   # web/test/tokens.test.ts re-renders these to CSS
```

which matches no entry, is not a comment line either, and therefore **ended the block** — dropping
that path and the six below it. The suite reported `SeedDatabase.swift` as missing from a filter
that lists it twice, and `web` on #175 was red on that, on the base branch, before this round
touched anything.

Two things are worth keeping from it.

**The failure was legible as the wrong thing.** The message said "add it to BOTH paths: lists", and
the lists were already correct. A guard whose failure message describes a repair that is already
made is a guard reporting on its own parser, and the only tell was that the file plainly contained
the string.

**The specimen did not carry the shape the file carried.** `pathBlocks` had a calibration test —
written first, answer known first, with two traps in it — and it passed, because neither trap was
*this* trap. A calibration is only as good as the shapes it includes, and the cheapest way to keep
it honest is to put the real file's own oddities into the specimen when they appear. The specimen
now has a trailing comment in it, and reverting the regex fails the specimen before it fails
anything about the repository.

---

### resvg draws nothing, silently, for a family it cannot resolve

The rasterizer is `@resvg/resvg-js`, rendering with `loadSystemFonts: false` — the setting that
makes the card identical on a laptop, on `ubuntu-latest` and in the Debian container, because what
it draws is a function of four files and not of what the host happens to have installed.

Under that setting a font family the renderer cannot find produces **no glyphs and no error**. Not
a fallback face, not a warning on stderr, not a non-zero anything: a 1200×630 gradient with no words
on it, served `200 OK`, with the right content type and the right dimensions. Every ordinary
assertion about that response passes.

So two things exist that would not otherwise:

- `MissingCardFonts`, thrown before a render is attempted, naming the directory and the files. The
  endpoint turns it into a `500` with `x-cypress-refusal: rasterizer` and logs the reason. Verified
  by running the built image with `CYPRESS_CARD_FONT_DIR` pointed at an empty directory.
- `web/test/support/png.ts`, which decodes the served PNG and counts **luma steps** in each of the
  card's four text bands. The obvious measure does not work: three of the four runs are drawn at a
  `fill-opacity` below 1, so counting ink-colored pixels finds none of them — and finds the pale
  corner of the gradient instead, reporting text where there is none and none where there is. A
  glyph edge is a step and `W1_HERO` is smooth everywhere. Measured on the real card: **0** steps
  across a 1080×300 window of pure gradient, and **1,700 to 4,800** in each text band.

The font files themselves are a checked-in copy under `web/fonts/`, because resvg 2.6.2 takes fonts
as paths on disk and the image is built from a context of `web/`. That is the `tokens.css` bargain
applied to binaries, and it carries the same hazard: a copy goes stale in silence. It is hashed
against `Cypress/Resources/Fonts/` by the suite, and the five sources are on both of `web.yml`'s
`paths:` filters, so a re-hinted face starts this suite rather than surfacing later as some
unrelated web commit's fault.
