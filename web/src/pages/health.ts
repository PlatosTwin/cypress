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
 * **There are three options here and not two**, which is the correction adversarial review made to
 * this paragraph: fail the check on every unready state, fail it on none, or fail it on the two
 * that are genuine deploy faults (`unconfigured`, `unreadable`) while tolerating the one that is
 * expected (`empty`). The middle one is the serious option and the first version of this comment
 * never named it, having argued only against the first.
 *
 * **What rules out failing on `empty`, and only on `empty`:** a Fly `[[http_service.checks]]` gates
 * the release. `flyctl deploy` waits for it and rolls back a machine that never passes. The volume
 * is EMPTY the moment it is created and is filled by a sync that needs the machine to exist first,
 * so a check that failed on `empty` would make the deploy that creates the machine impossible, and
 * the failure would present as a rollback rather than as anything naming a volume. That argument
 * is decisive and it is about `empty` alone — it says nothing about the other two, because on a
 * first deploy neither of them happens: `CYPRESS_PACK_DIR` is set in `fly.toml` from the start, and
 * Fly attaches the volume before the machine boots, so the state a first deploy passes through is
 * `empty`.
 *
 * **So why not the middle option?** Three reasons, and none of them is "a health check should never
 * fail":
 *
 *  1. **Both faults are already caught earlier, cheaper, and before merge.**
 *     `web/test/toolchain.test.ts` refuses a `fly.toml` with no `[env] CYPRESS_PACK_DIR` and
 *     refuses one whose value disagrees with `[mounts] destination`. `unconfigured` in production
 *     means someone shipped an image from a `fly.toml` CI had already refused. A check would be a
 *     second detector, firing later and costing a rollback, for something the suite finds first.
 *  2. **What is left of `unreadable` is improbable, and its reachability has already moved once.**
 *     Fly attaches the volume before the machine starts; a failed attach is a machine that does not
 *     boot, and there is nothing to health-check. More to the point: until the fix that accompanies
 *     this comment, `unreadable` was ALSO produced by a single unstattable entry — a dangling
 *     symlink, or a file pruned between the listing and the look, which is a routine refresh — so a
 *     check that failed on it would have rolled the machine back in the middle of a normal publish.
 *     That was not visible from here, and it is the argument against binding a status code to a
 *     state whose reachability can change underneath it.
 *  3. **The cost lands exactly where it hurts.** `min_machines_running = 0` and one machine: a
 *     failing check takes that machine out of the proxy, and takes `/health` with it. The page that
 *     says which of the four states you are in becomes unreachable at the moment somebody needs to
 *     read it. `flyctl checks list` keeps the last output so it is not a total loss, but the live
 *     surface is gone, and it is replaced by Fly's error page rather than by this body and by
 *     `x-cypress-refusal`.
 *
 * **Decided: 200 in every state.** The status code says "this process is up and serving HTTP" —
 * the only thing a process can honestly assert about itself with a number — and the BODY says
 * whether it is holding packs. `ready` is the field a deploy script greps; `state` and `detail` are
 * what a human reads. A monitor that wants paging on an unfilled volume reads `.ready`, which is
 * one `jq` away and is not ambiguous the way a 503 shared with six other causes would be. And the
 * per-request distinction already exists where it belongs: `resolveTreePage` returns `noPacks` and
 * `[uuid].astro` and `og.png.ts` answer 503 with `x-cypress-refusal: noPacks`, so a reader asking
 * for a tree on an unfilled machine is correctly told the server cannot answer *that*.
 *
 * **What would change the answer**, stated so the next person has a test rather than a re-argument:
 * if this app ever runs more than one machine, reason 3 weakens — there is then somewhere to fail
 * over to — and the middle option deserves re-deciding. If `unconfigured` or `unreadable` ever
 * becomes reachable in a way CI cannot catch, so does reason 1. The accepted cost meanwhile is
 * real and is named here rather than hidden: a deploy can go green over a machine that answers 500
 * on every tree URL, and the thing that catches it is a human or a monitor reading `.ready`.
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
