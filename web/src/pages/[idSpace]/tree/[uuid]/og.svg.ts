/**
 * The OpenGraph card for one tree — `/‹id-space›/tree/‹uuid›/og.svg`.
 *
 * It resolves the same way the page does, through `resolveTreePage`, so the card and the page
 * cannot disagree about a tree: there is one model and both render it. That is §W1's caption's
 * requirement rather than a convenience — *"rendered from the same three ingredients so the
 * group-chat preview and the page agree."*
 *
 * **What this cannot do is written at length in `src/lib/ogCard.ts`**: the major social platforms
 * do not render an SVG `og:image`, so this endpoint is correct where it is honored and ignored
 * where it is not, and a rasterizer is a dependency decision with an owner.
 *
 * The cache header is a year and `immutable`, which is sound for the reason a pack is opened
 * `immutable=1`: a published pack lives at a versioned, write-once path (R37.2), so the city
 * record behind this card does not change under a reader. New data is a new pack and a new
 * process.
 */
import type { APIRoute } from 'astro';

import { CARD_CONTENT_TYPE, treeCardSVG } from '../../../../lib/ogCard.ts';
import { packLibrary, resolveTreePage } from '../../../../lib/packLibrary.ts';

export const GET: APIRoute = ({ params }) => {
  const resolution = resolveTreePage(params.idSpace ?? '', params.uuid ?? '', packLibrary());
  if (!resolution.ok) {
    // The same three-and-one split the page makes, for the same reason: a mounted-nothing server
    // must not tell a crawler that the tree is gone. An endpoint's `Response` IS returned
    // verbatim — headers included — which the page's cannot be; see the note there.
    const refusal = resolution.refusal;
    return new Response(null, {
      status: refusal.kind === 'noPacks' ? 503 : 404,
      headers: { 'x-cypress-refusal': refusal.kind },
    });
  }
  return new Response(treeCardSVG(resolution.model), {
    headers: {
      'content-type': CARD_CONTENT_TYPE,
      'cache-control': 'public, max-age=31536000, immutable',
    },
  });
};
