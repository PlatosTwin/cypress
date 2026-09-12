/**
 * The OpenGraph card for one tree, as a raster — `/‹id-space›/tree/‹uuid›/og.png`.
 *
 * **This is the one the `<meta property="og:image">` points at**, and the reason it exists is in
 * `src/lib/ogRaster.ts`: Facebook, X, LinkedIn, Slack, Discord, iMessage and Telegram do not
 * decode `image/svg+xml`, so the SVG card beside this file was correct where it was honored and
 * invisible in the one place §W1's caption asks for — the group-chat preview.
 *
 * It resolves exactly the way the page and `og.svg` do, through `resolveTreePage`, and it
 * rasterizes the string `treeCardSVG` returns rather than drawing a second card. One model, one
 * drawing, two encodings.
 *
 * `og.svg.ts` stays. It is the drawing this file rasterizes, it is what a browser or an `<img>`
 * renders at any size, and it is the artifact to open when a card looks wrong — a vector one can
 * read beats a raster one can only squint at.
 *
 * The cache header matches `og.svg.ts` for the reason given there: a published pack lives at a
 * versioned, write-once path (R37.2), so the city record behind this card does not change under a
 * reader.
 */
import type { APIRoute } from 'astro';

import { CARD_PNG_CONTENT_TYPE, treeCardPNG } from '../../../../lib/ogRaster.ts';
import { packLibrary, resolveTreePage } from '../../../../lib/packLibrary.ts';

export const GET: APIRoute = ({ params }) => {
  const resolution = resolveTreePage(params.idSpace ?? '', params.uuid ?? '', packLibrary());
  if (!resolution.ok) {
    // The same three-and-one split the page and `og.svg` make, for the same reason: a server
    // holding no packs must not tell a crawler the tree is gone.
    const refusal = resolution.refusal;
    return new Response(null, {
      status: refusal.kind === 'noPacks' ? 503 : 404,
      headers: { 'x-cypress-refusal': refusal.kind },
    });
  }

  // A render that cannot find its fonts throws, and that is deliberate — see `MissingCardFonts`.
  // It surfaces as a 500 rather than as a card with no words on it, and the reason is logged
  // where an operator will find it, because a crawler will not read a response body.
  let png: Buffer;
  try {
    png = treeCardPNG(resolution.model);
  } catch (error) {
    console.error(`og.png: ${resolution.model.path} could not be rasterized`, error);
    return new Response(null, { status: 500, headers: { 'x-cypress-refusal': 'rasterizer' } });
  }

  return new Response(new Uint8Array(png), {
    headers: {
      'content-type': CARD_PNG_CONTENT_TYPE,
      'cache-control': 'public, max-age=31536000, immutable',
    },
  });
};
