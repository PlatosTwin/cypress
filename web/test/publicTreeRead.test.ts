import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { once } from 'node:events';
import type { AddressInfo } from 'node:net';

import {
  communityHalf,
  decodePublicTreeRead,
  decodeReading,
  publicAPIBase,
  publicTreeURL,
  PUBLIC_API_VARIABLE,
  PUBLIC_PAGE_MAX_AGE_S,
  PUBLIC_READ_TIMEOUT_MS,
  saysAnything,
  type CommunityHalf,
} from '../src/lib/publicTreeRead.ts';
import { repoFile } from './support/sources.ts';

/**
 * `src/lib/publicTreeRead.ts` against the service it decodes.
 *
 * ── Why this reads three files out of `server/` ──────────────────────────────────────────────
 *
 * A decoder tested against a body its own author typed is a decoder tested against a memory. The
 * three sources here are the ones the Go side proves itself with:
 *
 * - `server/testdata/public_tree.json` and `…_empty.json` are **golden files the handler is
 *   compared against byte-for-byte** (`TestPublicTreeReturnsTheContributedState`,
 *   `TestTheEmptyAnswerIsAlsoAFixture`), produced by the real handler over a real Postgres. The
 *   stub server below serves those bytes, so the three availability states are driven by what the
 *   service actually emits rather than by what this file thinks it emits.
 * - `server/internal/api/public.go` declares the shape once, in the `json:` tags. A golden file is
 *   one body; the struct is every body, and the two catch different drift — a key renamed on a
 *   field that happens to be null in both fixtures moves the struct and neither golden.
 *
 * All three are in `web.yml`'s `paths:` filters and in `READ_FROM_OUTSIDE_WEB`, so a Go-only
 * change to the contract runs this suite.
 *
 * ── And why there is a real HTTP server in here ──────────────────────────────────────────────
 *
 * The states this page has to survive are transport states: a refused connection, a socket that
 * never answers, a 500, a body that is not JSON. A stubbed `fetch` that resolves whatever it was
 * handed cannot produce any of them — it proves the decoder and nothing about `communityHalf`,
 * which is the function whose job is to never throw. `node:http` on an ephemeral port costs
 * milliseconds and exercises the real path, including `AbortSignal.timeout`.
 *
 * No port is chosen: `listen(0)` takes whatever the kernel gives, so this cannot collide with a
 * dev server or with another agent's suite.
 */

// ── The contract, read out of the Go ────────────────────────────────────────────────────────

/**
 * The `json:` tags of one Go struct, in declaration order.
 *
 * Comments are stripped first. The declarations in `public.go` carry more prose than code and a
 * doc comment quoting a tag would otherwise be read as a field — the same hazard `codeOnly` exists
 * for on the Swift side. Calibrated below against a specimen with exactly that trap in it.
 */
function goJSONTags(source: string, structName: string): readonly string[] {
  const withoutComments = source.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
  const header = new RegExp(String.raw`\btype\s+${structName}\s+struct\s*\{`).exec(withoutComments);
  assert.notEqual(header, null, `no \`type ${structName} struct {\` in the source`);
  const from = (header as RegExpExecArray).index;
  const body = withoutComments.slice(from);
  // The first `}` at column 0 closes a top-level type in gofmt'd source, which every file here is.
  const end = /\n\}/.exec(body);
  const scope = body.slice(0, end === null ? body.length : end.index);
  const tags: string[] = [];
  const pattern = /`json:"([^",]+)(?:,[^"]*)?"`/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(scope)) !== null) {
    if (match[1] !== undefined) tags.push(match[1]);
  }
  assert.notEqual(tags.length, 0, `\`type ${structName} struct\` declared no json tags`);
  return tags;
}

const goSource = repoFile('server/internal/api/public.go');
const golden = JSON.parse(repoFile('server/testdata/public_tree.json')) as unknown;
const goldenEmpty = JSON.parse(repoFile('server/testdata/public_tree_empty.json')) as unknown;
/** Both fixtures are about this tree, and every decode below has to be asked about it. */
const GOLDEN_UUID = '9f3a1c07-4d55-4a7e-9f10-2b6f0c1d5e42';

describe('the shape this page decodes is the shape the handler declares', () => {
  it('the tag parser reads a struct, stops at its end, and ignores prose', () => {
    // Specimen first, answers known before the parser saw it. Three traps: a tag quoted inside a
    // doc comment, a second struct below the first, and an `omitempty` suffix.
    const specimen = [
      '// A comment mentioning `json:"not_a_field"` in passing.',
      'type first struct {',
      '\tA string `json:"a"`',
      '\t// B used to be `json:"old_b"` and is not any more.',
      '\tB *int `json:"b,omitempty"`',
      '}',
      '',
      'type second struct {',
      '\tC string `json:"c"`',
      '}',
    ].join('\n');
    assert.deepEqual([...goJSONTags(specimen, 'first')], ['a', 'b']);
    assert.deepEqual([...goJSONTags(specimen, 'second')], ['c']);
  });

  it('the six keys the decoder requires are the six the response body declares', () => {
    const declared = [...goJSONTags(goSource, 'publicTreeRead')].sort();
    assert.deepEqual(
      declared,
      ['beloved', 'beloved_by', 'height', 'trunk_dbh', 'tree_uuid', 'verification_state'].sort(),
      'the public body`s fields have changed in Go. A new key on a public page is a disclosure '
        + 'decision (the ruling`s §1), and this page has to decide what it does with it before '
        + 'this test is updated.',
    );
    // The decoder's own list, proved by removing each key in turn from the golden body and
    // watching it refuse. A hard-coded list here would just be a second transcription.
    for (const key of declared) {
      const body = { ...(golden as Record<string, unknown>) };
      delete body[key];
      const outcome = decodePublicTreeRead(body, GOLDEN_UUID);
      assert.equal(outcome.ok, false, `a body with no \`${key}\` decoded anyway`);
      assert.match(outcome.ok ? '' : outcome.detail, new RegExp(`\`${key}\``));
    }
  });

  it('the four keys a reading declares are the four the reading decoder reads', () => {
    assert.deepEqual(
      [...goJSONTags(goSource, 'publicReading')].sort(),
      ['measured_month', 'method', 'unit_entered', 'value'],
    );
    const reading = (golden as { height: Record<string, unknown> }).height;
    for (const key of Object.keys(reading)) {
      const damaged = { ...reading };
      delete damaged[key];
      assert.equal(decodeReading(damaged), null, `a reading with no \`${key}\` decoded anyway`);
    }
  });

  it('the page caches no longer than the endpoint says it may', () => {
    // The ruling's §8b, as a number, read off the handler rather than restated: "the round that
    // renders the page may not cache beyond this". A page that outlived the endpoint's own
    // `max-age` would keep a withdrawn reading visible after its contributor took it back.
    const declared = /publicCacheControl = "public, max-age=(\d+)"/.exec(goSource);
    assert.notEqual(declared, null, 'server/internal/api/public.go no longer states its max-age');
    assert.ok(
      PUBLIC_PAGE_MAX_AGE_S <= Number((declared as RegExpExecArray)[1]),
      `the page caches for ${String(PUBLIC_PAGE_MAX_AGE_S)}s and the endpoint permits `
        + `${String((declared as RegExpExecArray)[1])}s`,
    );
  });
});

// ── The golden bodies ───────────────────────────────────────────────────────────────────────

describe('the handler`s own golden bodies decode to what §W1 draws', () => {
  it('decodes the full body — 18 m est., 64 cm taped, beloved by three', () => {
    const outcome = decodePublicTreeRead(golden, GOLDEN_UUID);
    assert.equal(outcome.ok, true);
    if (!outcome.ok) return;
    const read = outcome.read;
    assert.equal(read.height?.quantity.value, 18);
    assert.equal(read.height?.quantity.unitEntered, 'm');
    assert.equal(read.height?.quantity.method, 'estimate');
    assert.equal(read.height?.measuredMonth, '2026-08');
    assert.equal(read.trunkDBH?.quantity.value, 64);
    assert.equal(read.trunkDBH?.quantity.unitEntered, 'cm');
    assert.equal(read.trunkDBH?.quantity.method, 'tape');
    assert.equal(read.trunkDBH?.measuredMonth, '2026-07');
    assert.equal(read.beloved, true);
    assert.equal(read.belovedBy, 3);
    assert.equal(read.verificationState, 'unverified');
    assert.equal(saysAnything(read), true);
    // The SI reading is derived here rather than sent: the server does not convert, and this is
    // the ported `Quantity` doing it. 64 cm is 0.64 m and the entered value is untouched.
    assert.equal(read.trunkDBH?.quantity.siValue, 0.64);
  });

  it('decodes the empty body as a body that says nothing', () => {
    const outcome = decodePublicTreeRead(goldenEmpty, GOLDEN_UUID);
    assert.equal(outcome.ok, true);
    if (!outcome.ok) return;
    assert.equal(outcome.read.height, null);
    assert.equal(outcome.read.trunkDBH, null);
    assert.equal(outcome.read.beloved, false);
    assert.equal(outcome.read.belovedBy, null);
    assert.equal(saysAnything(outcome.read), false);
  });

  it('refuses an answer about a different tree', () => {
    const outcome = decodePublicTreeRead(golden, '00000000-0000-5000-8000-000000000000');
    assert.equal(outcome.ok, false);
    assert.match(outcome.ok ? '' : outcome.detail, /is about 9f3a1c07/);
  });

  it('accepts the uuid in either case, because the pack`s spelling is the one that travels', () => {
    assert.equal(decodePublicTreeRead(golden, GOLDEN_UUID.toUpperCase()).ok, true);
  });

  it('refuses a verification state this build cannot mark', () => {
    const verified = { ...(golden as Record<string, unknown>), verification_state: 'verified' };
    const outcome = decodePublicTreeRead(verified, GOLDEN_UUID);
    assert.equal(outcome.ok, false);
    assert.match(outcome.ok ? '' : outcome.detail, /verification_state/);
  });

  it('drops a reading whose method or unit is outside the Swift vocabulary', () => {
    // The server refuses these too (`publicReadingFrom`), so this is belt and braces — and it is
    // the branch that keeps an unbadgeable number off the page if the server ever stops.
    assert.equal(decodeReading({ value: 18, unit_entered: 'm', method: 'guess', measured_month: '2026-08' }), null);
    assert.equal(decodeReading({ value: 18, unit_entered: 'furlong', method: 'tape', measured_month: '2026-08' }), null);
    assert.equal(decodeReading({ value: 18, unit_entered: 'm', method: 'tape', measured_month: '2026-08-14' }), null);
    assert.equal(decodeReading({ value: 18, unit_entered: 'm', method: 'tape', measured_month: '2026-13' }), null);
    assert.equal(decodeReading({ value: '18', unit_entered: 'm', method: 'tape', measured_month: '2026-08' }), null);
    // And the control: the same object with nothing wrong with it decodes.
    assert.notEqual(decodeReading({ value: 18, unit_entered: 'm', method: 'tape', measured_month: '2026-08' }), null);
  });

  it('a dropped reading costs the reading and not the body', () => {
    const body = { ...(golden as Record<string, unknown>), height: { value: 18, unit_entered: 'm', method: 'guess', measured_month: '2026-08' } };
    const outcome = decodePublicTreeRead(body, GOLDEN_UUID);
    assert.equal(outcome.ok, true);
    if (!outcome.ok) return;
    assert.equal(outcome.read.height, null);
    assert.notEqual(outcome.read.trunkDBH, null);
  });

  it('drops the beloved pair when the state and the count disagree', () => {
    // Both directions. `beloved` with no number is a state whose evidence this page would have to
    // invent; a number with `beloved` false is a count below a k-anonymity floor, which is the one
    // disclosure the floor exists to prevent.
    const stateOnly = { ...(golden as Record<string, unknown>), beloved_by: null };
    const countOnly = { ...(golden as Record<string, unknown>), beloved: false };
    for (const body of [stateOnly, countOnly]) {
      const outcome = decodePublicTreeRead(body, GOLDEN_UUID);
      assert.equal(outcome.ok, true);
      if (!outcome.ok) continue;
      assert.equal(outcome.read.beloved, false);
      assert.equal(outcome.read.belovedBy, null);
      // The readings are untouched: one broken field does not cost the page the others.
      assert.notEqual(outcome.read.height, null);
    }
  });

  it('refuses a body that is not an object at all', () => {
    for (const body of [null, 42, 'a string', [1, 2, 3]]) {
      assert.equal(decodePublicTreeRead(body, GOLDEN_UUID).ok, false);
    }
  });
});

// ── The environment ─────────────────────────────────────────────────────────────────────────

describe('the base URL comes from the environment and there is no default host', () => {
  it('unset is unset, and says so rather than guessing a host', () => {
    const outcome = publicAPIBase({});
    assert.equal(outcome.ok, false);
    assert.match(outcome.ok ? '' : outcome.detail, /is not set/);
    // The property, stated as a property: no hostname appears anywhere in the module's source.
    // `AuthClient.defaultBaseURL` carries `https://cypress-sync.fly.dev/api/v1` and this must not.
    const source = repoFile('web/src/lib/publicTreeRead.ts');
    const outsideComments = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
    assert.equal(
      /https?:\/\/[a-z0-9.-]+/i.test(outsideComments),
      false,
      'src/lib/publicTreeRead.ts has a URL literal in its code. A default host would make "not '
        + 'configured" look exactly like "configured and answering nothing".',
    );
  });

  it('whitespace is not configuration', () => {
    assert.equal(publicAPIBase({ [PUBLIC_API_VARIABLE]: '   ' }).ok, false);
  });

  it('a value that is not an http URL is refused with the reason', () => {
    for (const junk of ['cypress-sync.fly.dev/api/v1', '/api/v1', 'ftp://host/api']) {
      const outcome = publicAPIBase({ [PUBLIC_API_VARIABLE]: junk });
      assert.equal(outcome.ok, false, `${junk} was accepted as a base URL`);
    }
  });

  it('a usable value comes back trimmed, with any trailing slash gone', () => {
    const outcome = publicAPIBase({ [PUBLIC_API_VARIABLE]: '  http://127.0.0.1:9/api/v1/  ' });
    assert.equal(outcome.ok, true);
    assert.equal(outcome.ok ? outcome.base : '', 'http://127.0.0.1:9/api/v1');
  });

  it('builds the route the server registers, lowercasing the uuid on the way', () => {
    assert.equal(
      publicTreeURL('http://127.0.0.1:9/api/v1', GOLDEN_UUID.toUpperCase()),
      `http://127.0.0.1:9/api/v1/public/trees/${GOLDEN_UUID}`,
    );
    // The path, read off the Go rather than transcribed: `mux.Handle("GET "+Prefix+"/public/trees/{id}"`.
    const route = repoFile('server/internal/api/server.go');
    assert.ok(
      route.includes('/public/trees/{id}'),
      'the server no longer registers GET /public/trees/{id} and this page is asking for a route '
        + 'that does not exist',
    );
  });
});

// ── The three availability states, over a real socket ───────────────────────────────────────

/** A server that answers every request the same way. Closed by `after` below. */
async function stub(
  handler: (request: IncomingMessage, response: ServerResponse) => void,
): Promise<{ base: string; server: Server }> {
  const server = createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address() as AddressInfo;
  return { base: `http://127.0.0.1:${String(address.port)}/api/v1`, server };
}

const running: Server[] = [];
after(() => {
  for (const server of running) server.close();
});

async function ask(base: string, uuid = GOLDEN_UUID, timeoutMs?: number): Promise<CommunityHalf> {
  return communityHalf(uuid, {
    environment: { [PUBLIC_API_VARIABLE]: base },
    ...(timeoutMs === undefined ? {} : { timeoutMs }),
  });
}

describe('the three availability states, driven by the handler`s own bytes', () => {
  it('reachable with data · the golden body arrives as `answered`', async () => {
    const paths: string[] = [];
    const { base, server } = await stub((request, response) => {
      paths.push(request.url ?? '');
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(repoFile('server/testdata/public_tree.json'));
    });
    running.push(server);
    const half = await ask(base);
    assert.equal(half.state, 'answered');
    if (half.state !== 'answered') return;
    assert.equal(half.read.trunkDBH?.quantity.value, 64);
    assert.equal(half.read.belovedBy, 3);
    // And it asked for the right URL. Without this the test would pass against a server that
    // answered the same bytes to every path, which is exactly what this stub is.
    assert.deepEqual(paths, [`/api/v1/public/trees/${GOLDEN_UUID}`]);
  });

  it('reachable with nothing · the empty body arrives as `empty`, not as a failure', async () => {
    const { base, server } = await stub((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(repoFile('server/testdata/public_tree_empty.json'));
    });
    running.push(server);
    const half = await ask(base);
    assert.equal(half.state, 'empty');
  });

  it('unreachable · a refused connection is `unavailable` and not a throw', async () => {
    // A port nothing is listening on, obtained by opening one and closing it — so the number is
    // known to be free rather than hoped to be, and nothing that is not ours is contacted.
    const { base, server } = await stub((_request, response) => response.end('{}'));
    server.close();
    await once(server, 'close');
    const half = await ask(base);
    assert.equal(half.state, 'unavailable');
    assert.match(half.state === 'unavailable' ? half.detail : '', /did not answer/);
  });

  it('unreachable · a server that never answers times out inside its budget', async () => {
    const { base, server } = await stub(() => {
      // Answers nothing, ever. The socket stays open, which is the failure a `catch` around a
      // `fetch` with no signal would wait out forever.
    });
    running.push(server);
    const started = Date.now();
    const half = await ask(base, GOLDEN_UUID, 120);
    const elapsed = Date.now() - started;
    assert.equal(half.state, 'unavailable');
    assert.ok(elapsed < 2000, `the timeout did not fire — waited ${String(elapsed)}ms`);
    assert.ok(PUBLIC_READ_TIMEOUT_MS > 0 && PUBLIC_READ_TIMEOUT_MS <= 5000);
  });

  it('unreachable · a 500 is `unavailable` and carries its status', async () => {
    const { base, server } = await stub((_request, response) => {
      response.writeHead(500);
      response.end('Something went wrong on our end.');
    });
    running.push(server);
    const half = await ask(base);
    assert.equal(half.state, 'unavailable');
    assert.match(half.state === 'unavailable' ? half.detail : '', /answered 500/);
  });

  it('unreachable · the 404 an undeployed route answers is `unavailable`', async () => {
    // This is the live state as this ships: `cypress-sync` serves `/health` and answers Go's bare
    // `404 page not found` for this route, because merging #163 did not redeploy it. The page
    // must render the city record and say it could not ask — not 500, and not "no measurements".
    const { base, server } = await stub((_request, response) => {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('404 page not found\n');
    });
    running.push(server);
    const half = await ask(base);
    assert.equal(half.state, 'unavailable');
    assert.match(half.state === 'unavailable' ? half.detail : '', /answered 404/);
  });

  it('unreachable · a 200 that is not JSON is `unavailable`', async () => {
    const { base, server } = await stub((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('<html>a proxy`s error page</html>');
    });
    running.push(server);
    const half = await ask(base);
    assert.equal(half.state, 'unavailable');
    assert.match(half.state === 'unavailable' ? half.detail : '', /unreadable JSON/);
  });

  it('unreachable · a well-formed answer about another tree is `unavailable`', async () => {
    const { base, server } = await stub((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(repoFile('server/testdata/public_tree.json'));
    });
    running.push(server);
    const half = await ask(base, '00000000-0000-5000-8000-000000000000');
    assert.equal(half.state, 'unavailable');
  });

  it('unconfigured · no variable means no request is made at all', async () => {
    let asked = false;
    const half = await communityHalf(GOLDEN_UUID, {
      environment: {},
      fetch: () => {
        asked = true;
        throw new Error('a request was made with no base URL configured');
      },
    });
    assert.equal(half.state, 'unconfigured');
    assert.equal(asked, false);
  });

  it('every state is one of five, and none of them is a rejected promise', async () => {
    const seen = new Set<string>();
    const { base, server } = await stub((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(repoFile('server/testdata/public_tree.json'));
    });
    running.push(server);
    seen.add((await ask(base)).state);
    seen.add((await communityHalf(GOLDEN_UUID, { environment: {} })).state);
    seen.add((await communityHalf(GOLDEN_UUID, {
      environment: { [PUBLIC_API_VARIABLE]: base },
      fetch: () => Promise.reject(new Error('the network is on fire')),
    })).state);
    assert.deepEqual([...seen].sort(), ['answered', 'unavailable', 'unconfigured']);
  });
});
