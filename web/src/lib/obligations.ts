/**
 * The attribution obligations that travel with a source's data, rendered where the data is.
 *
 * # Why a public page has one of these at all
 *
 * R36's third binding consequence: **any data served or published must carry its source's
 * attribution obligations**, and it names New York's verbatim disclaimer as the first. R78 settles
 * how: ruling 2 puts the text on the surface that offers the data and is the constraint-21
 * sign-off for putting it there, and **ruling 3 says the manifest's machine-readable
 * `attribution` array does not discharge the obligation** — the text has to be rendered and
 * human-visible. `web/README.md` carried that forward into this round in one line: the obligation
 * follows the data.
 *
 * A public tree page is the surface where a stranger meets an NYC tree, so it is squarely inside
 * ruling 2's "the site where the application can be accessed": the page IS the application there.
 *
 * # Why the text is here and not in the pack
 *
 * `Tools/publish_cities.py` writes a per-inventory receipt — `inventory_<tag>_{name,url,
 * snapshot_on,licen[cs]e,id_space}` — and **no disclaimer key**, measured on the pinned seed's
 * `seed_meta`. So a page cannot read this obligation out of the file it is serving; it has to know
 * it. That is the same bargain every other port in `web/src/lib` makes, and it is guarded the same
 * way: `test/obligations.test.ts` parses `CityDownloadsPresentation.swift` at run time and requires
 * these strings to equal the ones the app renders, which are themselves checked against
 * `docs/operations/nyc-data-obligations.md` by the iOS suite. Two hops, each mechanical, and no
 * transcription anywhere.
 *
 * **`NYC_DISCLAIMER_REQUIRED` is quoted, not written.** The Swift's own comment calls it "the only
 * string in this app that must not be edited". The same applies to this copy of it: it is the
 * City's sentence, and a house-style pass over it would break the obligation it discharges. If it
 * looks wrong, it is still right.
 */

import { idSpaces } from './idSpaces.ts';

/** New York's id space. One space; the five boroughs are packs inside it. */
export const NYC_ID_SPACE = 'us-ny-nyc';

/** `CityDownloadsCopy.nycDisclaimerHeading`. */
export const NYC_DISCLAIMER_HEADING = 'Data disclaimer';

/** `CityDownloadsCopy.nycDisclaimerRequired` — the City's text, verbatim. Do not edit. */
export const NYC_DISCLAIMER_REQUIRED =
  'The City of New York can not vouch for the accuracy or completeness of data provided by this '
  + 'web site or application or for the usefulness or integrity of the web site or application. '
  + 'This site provides applications using data that has been modified for use from its original '
  + 'source, NYC.gov, the official web site of the City of New York.';

/** `CityDownloadsCopy.nycDisclaimerAttribution` — ours, and not required by the terms. */
// The straight apostrophe in `Recreation's` is the Swift's, and this file matches it rather than
// applying the project's usual typographic one: the whole value of this constant is that a machine
// can prove it equal to the app's, and a prettier apostrophe would break that to no reader's gain.
export const NYC_DISCLAIMER_ATTRIBUTION =
  "New York City tree data is drawn from the NYC Department of Parks and Recreation's Forestry "
  + 'Tree Points and Forestry Planting Spaces datasets (NYC Open Data), used under the NYC.gov '
  + 'Data Mine Terms of Use.';

/** A block of text a page must render because of where its data came from. */
export interface SourceObligation {
  readonly heading: string;
  /**
   * Paragraphs, in order. The first is the one the terms require verbatim; anything after it is
   * this project's own, and is kept separate so that editing ours can never reach theirs.
   */
  readonly paragraphs: readonly string[];
}

/**
 * What a page serving this id space must carry, or `null` when the source imposes nothing.
 *
 * Keyed on the **id space** rather than on the inventory, because both NYC inventories sit in one
 * space and a pack narrowed to a borough still carries it. The space is looked up in the registry
 * first so that a typo returns "no obligation" for a space that does not exist — which is a
 * refusal the caller already has — rather than silently matching nothing.
 */
export function sourceObligation(idSpace: string): SourceObligation | null {
  if (!Object.hasOwn(idSpaces, idSpace)) return null;
  if (idSpace !== NYC_ID_SPACE) return null;
  return {
    heading: NYC_DISCLAIMER_HEADING,
    paragraphs: [NYC_DISCLAIMER_REQUIRED, NYC_DISCLAIMER_ATTRIBUTION],
  };
}
