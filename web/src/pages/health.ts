/**
 * `GET /health` — what this process is holding, for a deploy and for a human with `curl`.
 *
 * **The path is `/health` because `cypress-sync` already answers on `/health`** (`server/
 * internal/api/server.go`, documented in `server/README.md` as "Liveness, and the git sha of the
 * running build"). Two Fly apps in one project answering the same operator question on two
 * different paths is a fact somebody has to remember; this way there is nothing to remember. It
 * was also free to choose: `fly.toml` declared no `[[http_service.checks]]` at all before W-E, so
 * nothing was pointed anywhere and no existing URL had to be honored. It cannot collide with the
 * tree route either — `/‹id-space›/tree/‹uuid›` is three segments and this is one.
 *
 * `/readyz` was the other candidate and was refused on the semantics, not the spelling: in the
 * convention that name comes from, a failing readiness probe means "take this instance out of
 * rotation", and that is exactly what this endpoint must NOT cause. See below.
 *
 * ── 200, always. Even `ready: false`. ────────────────────────────────────────────────────────
 *
 * The tempting answer is 503 while no pack is open, and it is wrong here for three reasons, in
 * descending order of how badly it bites:
 *
 *  1. **The first deploy could never go healthy.** A Fly `[[http_service.checks]]` gates the
 *     release: `flyctl deploy` waits for it and rolls back a machine that never passes. The volume
 *     this app mounts is EMPTY the moment it is created, and it is filled by a sync that needs the
 *     machine to exist first. A check that failed on "no packs yet" would make the deploy that
 *     creates the machine impossible, and the failure would present as a rollback rather than as
 *     anything naming a volume.
 *  2. **There is no second machine to fail over to.** `min_machines_running = 0` with
 *     `auto_start_machines`: this is one machine. Marking it unhealthy does not route a reader
 *     somewhere better, it routes them to Fly's own error page — replacing the app's explanation
 *     with a proxy's, and taking `x-cypress-refusal` and this body with it.
 *  3. **Per-request refusals already carry the distinction, and carry it in the right place.**
 *     `resolveTreePage` returns `noPacks` and `[uuid].astro` and `og.png.ts` answer 503 with
 *     `x-cypress-refusal: noPacks`. A reader asking for a tree on an unfilled machine is correctly
 *     told the server cannot answer *that*. Machine-level health is a different question from
 *     request-level availability, and this endpoint answers the first one.
 *
 * So the status code says "this process is up and serving HTTP" — which is the only thing a
 * process can honestly assert about itself with a number — and the BODY says whether it is holding
 * packs. `ready` is the field a deploy script greps; `state` and `detail` are what a human reads.
 * A monitor that wants paging on an unfilled volume reads `.ready`, which is one `jq` away and is
 * not ambiguous the way a 503 shared with six other causes would be.
 *
 * **If someone later points a check at this and wants it to fail on `ready: false`, reason 1 is
 * the thing to confront first.** It is not a preference.
 *
 * ── no-store ─────────────────────────────────────────────────────────────────────────────────
 *
 * The opposite of `og.png.ts`'s year-long immutable cache, and for the mirror-image reason: that
 * body is a function of a write-once published pack, this one is a function of the state of one
 * machine at one moment. A cached readiness answer is a readiness answer about some other process.
 */
import type { APIRoute } from 'astro';

import { readinessReport } from '../lib/readiness.ts';

export const GET: APIRoute = () => {
  // Indented, and with a trailing newline, because the audience includes somebody reading it in a
  // terminal. It is a handful of bytes on a route nothing hot calls.
  const body = `${JSON.stringify(readinessReport(), null, 2)}\n`;
  return new Response(body, {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
};
