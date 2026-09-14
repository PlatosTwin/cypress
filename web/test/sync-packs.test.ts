import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from 'node:fs';
import { createServer, type Server } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  MANIFEST_OBJECT,
  manifestURL,
  normalizedBaseURL,
  packFileName,
  packURL,
  PUBLIC_BUCKET_BASE_URL,
  pythonStringConstant,
  UnsafePackPathError,
} from '../src/lib/pack/bucket.ts';
import { repositoryRoot } from '../src/lib/pack/localSeed.ts';
import {
  NEWEST_KNOWN_MANIFEST_FORMAT,
  NEWEST_KNOWN_PACK_SCHEMA_VERSION,
} from '../src/lib/pack/versions.ts';
import { PACK_DIRECTORY_VARIABLE } from '../src/lib/packLibrary.ts';

/**
 * `scripts/sync-packs.mjs`, against a bucket that exists only for the length of one test.
 *
 * **Nothing here touches the network.** A `node:http` server on an ephemeral port serves a catalog
 * this file wrote and two or three byte-sized objects, and the script is run as a child process
 * pointed at it with `--base-url`. That is the whole apparatus, and it is the apparatus rather than
 * a set of unit tests on purpose: the behaviors worth proving — a partial download leaving no file,
 * a second run asking for nothing, a refusal exiting nonzero — are behaviors of the program, and a
 * test of an extracted function would prove them about something that is not what runs on the
 * machine.
 *
 * **What this tier does NOT prove.** The "packs" are a few bytes of ASCII, not SQLite. The sync
 * never opens a pack — `packLibrary.ts` does, and `pack-real-seed.test.ts` is the tier that proves
 * a real 82 MB file opens — so what is downloaded here is checked for being *the bytes the catalog
 * described* and for nothing else. Said plainly because "the sync ran green" and "the server can
 * serve those packs" are two statements and only the first is in this file.
 *
 * **The child gets a deliberately empty environment**, `PATH` and whatever a case sets. An
 * inherited `CYPRESS_PACK_DIR` — which the author of this file has set in their own shell — would
 * make the "no destination" case pass while proving the opposite of its name.
 */

const webRoot = fileURLToPath(new URL('../', import.meta.url));
const SCRIPT = join(webRoot, 'scripts/sync-packs.mjs');

const temporaries: string[] = [];
const servers: Server[] = [];
after(() => {
  for (const server of servers) server.close();
  for (const path of temporaries) rmSync(path, { recursive: true, force: true });
});

function directory(): string {
  const path = mkdtempSync(join(tmpdir(), 'cypress-syncpacks-'));
  temporaries.push(path);
  return path;
}

// ── The fake bucket ──────────────────────────────────────────────────────────────────────────

interface FakeObject {
  /** The bytes this object serves, which a case may make disagree with what the catalog claims. */
  readonly body: Buffer;
  /** Respond 503 this many times before serving the body. A flaky link, deterministically. */
  failures?: number;
}

interface Bucket {
  readonly baseURL: string;
  /** Every path requested, in order, catalog included. Counted rather than parsed out of stdout. */
  readonly requests: string[];
}

async function bucket(catalog: string, objects: Map<string, FakeObject>): Promise<Bucket> {
  const requests: string[] = [];
  const server = createServer((request, response) => {
    const path = new URL(request.url ?? '/', 'http://127.0.0.1').pathname.replace(/^\//, '');
    requests.push(path);
    if (path === MANIFEST_OBJECT) {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(catalog);
      return;
    }
    const object = objects.get(path);
    if (object === undefined) {
      response.writeHead(404, { 'content-type': 'text/plain' });
      response.end('no such object');
      return;
    }
    if (object.failures !== undefined && object.failures > 0) {
      object.failures -= 1;
      response.writeHead(503, { 'content-type': 'text/plain' });
      response.end('come back later');
      return;
    }
    response.writeHead(200, { 'content-type': 'application/octet-stream' });
    response.end(object.body);
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address !== null && typeof address === 'object', 'the fake bucket did not bind a port');
  return { baseURL: `http://127.0.0.1:${address.port}`, requests };
}

/** A catalog entry, with every key `manifest.ts` requires and the overrides a case needs. */
function entry(id: string, body: Buffer, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const version = 's17-r2026-08-22.02-ac7b1ccc';
  return {
    id,
    display_name: `${id} display name`,
    coverage: 'full',
    tree_count: 3,
    schema_version: NEWEST_KNOWN_PACK_SCHEMA_VERSION,
    version,
    content_rev: '2026-08-22.02',
    bbox: { min_lat: 37.7, max_lat: 37.8, min_lon: -122.5, max_lon: -122.4 },
    centroid: { lat: 37.75, lon: -122.45 },
    region: { level: 'city', parent_city: id, parent_city_display_name: `${id} display name` },
    path: `cities/${id}/${version}/${id}.sqlite`,
    bytes: body.length,
    sha256: createHash('sha256').update(body).digest('hex'),
    ...overrides,
  };
}

function catalogOf(
  entries: readonly Record<string, unknown>[],
  overrides: Record<string, unknown> = {},
): string {
  return JSON.stringify({
    manifest_format: NEWEST_KNOWN_MANIFEST_FORMAT,
    generated_at: '2026-09-13T00:00:00+00:00',
    base_url_hint: 'https://a-host-this-reader-must-ignore.test',
    cities: entries,
    ...overrides,
  });
}

/** The objects a set of entries describes, each serving exactly the bytes it was built from. */
function objectsFor(pairs: readonly (readonly [Record<string, unknown>, Buffer])[]): Map<string, FakeObject> {
  return new Map(pairs.map(([city, body]) => [String(city['path']), { body }]));
}

interface Run {
  readonly code: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runSync(args: readonly string[], environment: Record<string, string> = {}): Promise<Run> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [SCRIPT, ...args], {
      cwd: webRoot,
      env: { PATH: process.env['PATH'] ?? '', ...environment },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString('utf8'); });
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString('utf8'); });
    child.on('error', reject);
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

/**
 * The pid of a process that has certainly exited, for the temporary-file cases.
 *
 * A literal like `999` is not the same thing and was the wrong specimen: low pids belong to real
 * daemons on macOS, so the "stale temporary" case was asserting against a pid that was alive. This
 * starts a process that does nothing, waits for it to go, and hands back its number.
 */
async function deadPid(): Promise<number> {
  const child = spawn(process.execPath, ['-e', '']);
  await new Promise<void>((resolve) => child.on('close', () => resolve()));
  return child.pid ?? 0;
}

/** Backdates a file past the stall window, so the "written moments ago" rule stops applying. */
function backdate(path: string): void {
  const longAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
  utimesSync(path, longAgo, longAgo);
}

/** The `*.sqlite` files in a directory, sorted — what `packLibrary.openPackLibrary` would open. */
function packsIn(path: string): string[] {
  return readdirSync(path).filter((name) => name.endsWith('.sqlite')).sort();
}

/** Everything in a directory, sorted — including the dot-files `packsIn` cannot see. */
function everythingIn(path: string): string[] {
  return readdirSync(path).sort();
}

const SF = Buffer.from('this stands in for 82 MB of San Francisco');
const SJ = Buffer.from('and this for San Jose');

// ── A clean fill, and a second run ───────────────────────────────────────────────────────────

describe('filling an empty directory', () => {
  it('writes one file per listed pack, with the bytes the catalog described', async () => {
    const sf = entry('sf', SF);
    const sj = entry('us-ca-sj', SJ);
    const served = await bucket(catalogOf([sf, sj]), objectsFor([[sf, SF], [sj, SJ]]));
    const into = directory();

    // Through the environment variable, and through the one `packLibrary.ts` exports rather than
    // a string spelled again here: if the server and the sync ever read different variables, this
    // fills a directory nobody serves and the test says so.
    const run = await runSync(['--base-url', served.baseURL], { [PACK_DIRECTORY_VARIABLE]: into });

    assert.equal(run.code, 0, `exit ${run.code}\n${run.stdout}\n${run.stderr}`);
    assert.deepEqual(packsIn(into), ['sf.sqlite', 'us-ca-sj.sqlite']);
    // The bytes, not the names. A file of the right length with the wrong content would pass a
    // size check and is exactly what the hash exists to catch.
    assert.deepEqual(readFileSync(join(into, 'sf.sqlite')), SF);
    assert.deepEqual(readFileSync(join(into, 'us-ca-sj.sqlite')), SJ);
    // Nothing else: no temporary file survived a successful run.
    assert.deepEqual(everythingIn(into), ['sf.sqlite', 'us-ca-sj.sqlite']);
    assert.match(run.stdout, /SYNC-PACKS: OK downloaded=2 skipped=0 pruned=0 refused=0/);
  });

  it('a second run downloads nothing, counted by the bucket and not read out of stdout', async () => {
    const sf = entry('sf', SF);
    const served = await bucket(catalogOf([sf]), objectsFor([[sf, SF]]));
    const into = directory();
    const argv = ['--dir', into, '--base-url', served.baseURL];

    const first = await runSync(argv);
    assert.equal(first.code, 0, first.stderr);
    const afterFirst = served.requests.filter((path) => path !== MANIFEST_OBJECT).length;
    assert.equal(afterFirst, 1, `the first run made ${afterFirst} object request(s), expected 1`);

    const second = await runSync(argv);
    assert.equal(second.code, 0, second.stderr);
    const afterSecond = served.requests.filter((path) => path !== MANIFEST_OBJECT).length;
    assert.equal(
      afterSecond,
      1,
      `the second run asked the bucket for the pack again (${afterSecond} object requests in `
        + 'total). A pack already present at the right size and hash must be skipped.',
    );
    assert.match(second.stdout, /SYNC-PACKS: OK downloaded=0 skipped=1/);
    // Still the right bytes: "skipped" must not be reachable by having deleted the file.
    assert.deepEqual(readFileSync(join(into, 'sf.sqlite')), SF);
  });

  it('replaces a file whose bytes are no longer the ones the catalog names', async () => {
    // A refresh: the same pack id, new content. The filename cannot say which version is there,
    // so the hash is the only thing that can, and this is the case that proves it is consulted.
    const republished = Buffer.from('a newer San Francisco, same id, different bytes');
    const sf = entry('sf', republished);
    const served = await bucket(catalogOf([sf]), objectsFor([[sf, republished]]));
    const into = directory();
    writeFileSync(join(into, 'sf.sqlite'), SF);

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.equal(run.code, 0, run.stderr);
    assert.deepEqual(readFileSync(join(into, 'sf.sqlite')), republished);
    assert.match(run.stdout, /SYNC-PACKS: OK downloaded=1 skipped=0/);
  });
});

// ── The refusals. The first two are the reason this script writes to a temporary name ────────

describe('bytes that are not the bytes the catalog described', () => {
  it('refuses a body whose sha256 is wrong, and leaves NOTHING in the directory', async () => {
    // The most important case in this file. The served body is the right LENGTH and the wrong
    // content, so a size check alone would accept it — which is how a corrupted pack reaches a
    // server that then answers 404 for a whole city with nothing saying why.
    const sf = entry('sf', SF);
    const corrupted = Buffer.from(SF);
    corrupted[0] = SF[0] === 0x61 ? 0x62 : 0x61;
    assert.equal(corrupted.length, SF.length, 'the specimen must be the same length to be the case');
    const served = await bucket(catalogOf([sf]), new Map([[String(sf['path']), { body: corrupted }]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0, 'a refused pack must exit nonzero');
    assert.deepEqual(
      everythingIn(into),
      [],
      'a pack that failed verification left a file behind — including, if this lists a dot-file, '
        + 'the partial download itself',
    );
    assert.match(run.stderr, /REFUSED sf: sha256/);
    assert.match(run.stdout, /SYNC-PACKS: FAILED downloaded=0 .* refused=1/);
  });

  it('refuses a short body the same way', async () => {
    const sf = entry('sf', SF);
    const truncated = SF.subarray(0, SF.length - 5);
    const served = await bucket(catalogOf([sf]), new Map([[String(sf['path']), { body: truncated }]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    assert.deepEqual(everythingIn(into), []);
    assert.match(run.stderr, new RegExp(`REFUSED sf: the server sent ${truncated.length} bytes`));
  });

  it('does not retry a body that arrived whole and failed verification', async () => {
    // Deliberate, and stated in the script: re-downloading 199 MB to be told the same thing turns
    // one clear message into three slow ones. Asserted on the request count, so a "retry the
    // hash" change cannot pass this file quietly.
    const sf = entry('sf', SF);
    const served = await bucket(
      catalogOf([sf]),
      new Map([[String(sf['path']), { body: Buffer.from('not it') }]]),
    );
    const run = await runSync(['--dir', directory(), '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    const attempts = served.requests.filter((path) => path !== MANIFEST_OBJECT).length;
    assert.equal(attempts, 1, `the pack was fetched ${attempts} times; verification is terminal`);
  });

  it('streams a pack bigger than one write buffer without leaking listeners', async () => {
    /**
     * Found by running the script against the real bucket, not by reading it.
     *
     * A 29 MB published pack synced correctly and printed
     * `MaxListenersExceededWarning: 11 error listeners added to [WriteStream]` while doing it: the
     * back-pressure wait attached an `error` listener per `drain` and only ever removed the
     * `drain` one, so a 199 MB pack would have retained thousands. Every fake pack in this file is
     * a few dozen bytes and writes in one go, so no case here had ever waited on a drain — which
     * is exactly the kind of hole a suite of small specimens leaves. This one is 4 MB for no
     * reason except to be larger than a write buffer.
     */
    const large = Buffer.alloc(4 * 1024 * 1024, 'cypress');
    const sf = entry('sf', large);
    const served = await bucket(catalogOf([sf]), objectsFor([[sf, large]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.equal(run.code, 0, run.stderr);
    assert.equal(
      createHash('sha256').update(readFileSync(join(into, 'sf.sqlite'))).digest('hex'),
      String(sf['sha256']),
    );
    assert.equal(
      run.stderr.includes('MaxListenersExceededWarning'),
      false,
      `the download leaked event listeners:\n${run.stderr}`,
    );
  });

  it('leaves a SYNC-PACKS line when the destination cannot be written to, instead of crashing', async () => {
    /**
     * The invariant the script states about itself: *a failed run has to leave a line the same
     * grep finds, or it looks like a run that never happened.* It did not hold for an `open(2)`
     * failure. `createWriteStream` opens on a later tick, and with nothing listening yet the
     * `'error'` event was thrown from a tick nothing could catch: a stack trace, **zero**
     * `SYNC-PACKS:` lines, and exit 1 — the same exit code an ordinary refusal gives, so even
     * that could not tell them apart.
     *
     * The case is also the retry rule: a destination that cannot be written to is not a flaky
     * socket, and asking twice writes the same EACCES twice.
     */
    const sf = entry('sf', SF);
    const served = await bucket(catalogOf([sf]), objectsFor([[sf, SF]]));
    const into = directory();
    chmodSync(into, 0o555);
    try {
      const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

      const summary = `${run.stdout}\n${run.stderr}`
        .split('\n')
        .filter((line) => line.startsWith('SYNC-PACKS:'));
      assert.equal(
        summary.length,
        1,
        `a run that could not write printed ${summary.length} SYNC-PACKS lines:\n${run.stderr}`,
      );
      assert.match(summary[0] ?? '', /^SYNC-PACKS: FAILED .*refused=1/);
      assert.equal(
        run.stderr.includes("Unhandled 'error' event"),
        false,
        `the open failure escaped as an unhandled event:\n${run.stderr}`,
      );
      assert.notEqual(run.code, 0);
      // Zero, not one: the temporary file is opened before the request is made, so a destination
      // that cannot be written to costs no transfer at all. And the retry rule is visible in what
      // is absent — a local disk failure prints no `attempt N/3 failed` notice, because asking
      // again would only write the same EACCES again.
      const attempts = served.requests.filter((path) => path !== MANIFEST_OBJECT).length;
      assert.equal(attempts, 0, `an unwritable destination still fetched ${attempts} time(s)`);
      assert.doesNotMatch(
        run.stderr,
        /attempt \d+\/\d+ failed/,
        'a local disk failure was retried like a flaky socket',
      );
    } finally {
      // Or the temporary directory cannot be removed, and every later run of this suite inherits
      // a directory it cannot clean.
      chmodSync(into, 0o755);
    }
  });

  it('retries a transport failure and then succeeds', async () => {
    const sf = entry('sf', SF);
    const served = await bucket(
      catalogOf([sf]),
      new Map([[String(sf['path']), { body: SF, failures: 1 }]]),
    );
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.equal(run.code, 0, `${run.stdout}\n${run.stderr}`);
    assert.deepEqual(readFileSync(join(into, 'sf.sqlite')), SF);
    const attempts = served.requests.filter((path) => path !== MANIFEST_OBJECT).length;
    assert.equal(attempts, 2, `the 503 was not retried (or was retried ${attempts} times)`);
  });
});

describe('catalogs this build will not act on', () => {
  it('refuses an unknown envelope format, before asking for a single object', async () => {
    const sf = entry('sf', SF);
    const served = await bucket(
      catalogOf([sf], { manifest_format: 99 }),
      objectsFor([[sf, SF]]),
    );
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    assert.match(run.stderr, /manifest_format 99/);
    assert.deepEqual(everythingIn(into), []);
    assert.deepEqual(
      served.requests.filter((path) => path !== MANIFEST_OBJECT),
      [],
      'an unreadable catalog must not lead to a download',
    );
  });

  it('refuses a pack published past the generation this build reads, and syncs the rest', async () => {
    // Both halves matter. The refusal is the point; "and syncs the rest" is what stops one future
    // pack from taking the whole volume offline.
    const future = entry('sf', SF, { schema_version: NEWEST_KNOWN_PACK_SCHEMA_VERSION + 1 });
    const sj = entry('us-ca-sj', SJ);
    const served = await bucket(catalogOf([future, sj]), objectsFor([[future, SF], [sj, SJ]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0, 'a refused pack must exit nonzero even when others landed');
    assert.deepEqual(packsIn(into), ['us-ca-sj.sqlite']);
    assert.match(
      run.stderr,
      new RegExp(`REFUSED sf: .*generation ${NEWEST_KNOWN_PACK_SCHEMA_VERSION + 1}`),
    );
    assert.deepEqual(
      served.requests.filter((path) => path !== MANIFEST_OBJECT),
      [String(sj['path'])],
      'the pack this build cannot read was downloaded anyway',
    );
  });

  it('refuses a catalog whose entries would land on one file, before anything is downloaded', async () => {
    // Two entries with one id. Whichever came second would overwrite the first, and the summary
    // counted both — `bytes-in-place` was 82 for one 41-byte file. Refused whole rather than
    // corrected, because a catalog that says this is wrong about something upstream.
    const first = entry('sf', SF);
    const second = entry('sf', SJ);
    const served = await bucket(catalogOf([first, second]), objectsFor([[first, SF]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    assert.match(run.stderr, /the same file on disk/);
    assert.deepEqual(everythingIn(into), [], 'a refused catalog wrote something');
    assert.deepEqual(served.requests.filter((path) => path !== MANIFEST_OBJECT), []);
  });

  it('refuses two pack ids that differ only in case', async () => {
    // Two files on the case-sensitive volume and one file on a developer's Mac. Refused so the
    // behavior does not depend on which machine is running it.
    const lower = entry('sf', SF);
    const upper = entry('SF', SJ);
    const served = await bucket(catalogOf([lower, upper]), objectsFor([[lower, SF], [upper, SJ]]));
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    assert.match(run.stderr, /differ only in case/);
    assert.deepEqual(everythingIn(into), []);
  });

  it('refuses a catalog path that could address something other than an object under the base URL', async () => {
    // The catalog is a remote object. `bucket.ts` refuses a path with a scheme, a leading slash or
    // a `..` segment; this is that rule reaching the program, with the traversal actually attempted.
    const sf = entry('sf', SF, { path: '../../../../../../tmp/escaped.sqlite' });
    const served = await bucket(catalogOf([sf]), new Map());
    const into = directory();

    const run = await runSync(['--dir', into, '--base-url', served.baseURL]);

    assert.notEqual(run.code, 0);
    assert.match(run.stderr, /REFUSED sf: .*will not follow/);
    assert.deepEqual(everythingIn(into), []);
    assert.deepEqual(served.requests.filter((path) => path !== MANIFEST_OBJECT), []);
  });
});

// ── Pruning ──────────────────────────────────────────────────────────────────────────────────

describe('what a refresh does to files the catalog no longer lists', () => {
  const unlisted = Buffer.from('a city that was published once');

  /** The name of the stale temporary, which must carry a pid that is really gone. */
  let stale = '';

  async function setUp(): Promise<{ into: string; baseURL: string }> {
    const sf = entry('sf', SF);
    const served = await bucket(catalogOf([sf]), objectsFor([[sf, SF]]));
    const into = directory();
    writeFileSync(join(into, 'retired-city.sqlite'), unlisted);
    // A note beside the packs, which --prune must never touch, and a temporary file from a run
    // that is genuinely over: its process has exited and it was last written two hours ago. Both
    // halves matter — a temporary whose pid is alive, or which was touched moments ago, is kept,
    // and there are cases below for each.
    writeFileSync(join(into, 'README.txt'), 'left here by an operator');
    stale = `.sf.sqlite.part-${await deadPid()}-deadbeef`;
    writeFileSync(join(into, stale), Buffer.from('half a download'));
    backdate(join(into, stale));
    return { into, baseURL: served.baseURL };
  }

  it('leaves it alone without --prune, and says it is there', async () => {
    const { into, baseURL } = await setUp();

    const run = await runSync(['--dir', into, '--base-url', baseURL]);

    assert.equal(run.code, 0, run.stderr);
    assert.deepEqual(packsIn(into), ['retired-city.sqlite', 'sf.sqlite']);
    assert.deepEqual(readFileSync(join(into, 'retired-city.sqlite')), unlisted);
    assert.ok(existsSync(join(into, stale)));
    assert.match(run.stdout, /unlisted retired-city\.sqlite .*--prune removes it/);
    assert.match(run.stdout, /pruned=0/);
  });

  it('names a file the server would open even when --prune will not remove it', async () => {
    /**
     * The reporting gap. `packLibrary.packFiles` takes every name ending in `.sqlite` and stats
     * it: **it does not skip dot-files and it follows symlinks.** `--prune` does neither — by
     * design, it must not delete what it did not write — so a `.hidden.sqlite` and a symlink
     * pointing clean out of the destination were files the server would serve, `--prune` would
     * not touch, and nothing mentioned at all. The run said `OK` over a directory that was not.
     *
     * The fix is reporting, not deletion: both are named, both survive `--prune`, and the line
     * says which it is.
     */
    const { into, baseURL } = await setUp();
    const outside = join(directory(), 'somewhere-else.sqlite');
    writeFileSync(outside, Buffer.from('a pack the operator put outside the volume'));
    symlinkSync(outside, join(into, 'link-to-outside.sqlite'));
    writeFileSync(join(into, '.hidden.sqlite'), Buffer.from('a pack in a dot-file'));

    const run = await runSync(['--dir', into, '--base-url', baseURL, '--prune']);

    assert.equal(run.code, 0, run.stderr);
    assert.match(run.stdout, /unlisted link-to-outside\.sqlite .*symlink.*--prune does NOT remove it/);
    assert.match(run.stdout, /unlisted \.hidden\.sqlite .*dot-file.*--prune does NOT remove it/);
    // Reported and still there — and the file the symlink points at is untouched, which is the
    // reason --prune does not follow one.
    assert.ok(existsSync(join(into, 'link-to-outside.sqlite')));
    assert.ok(existsSync(join(into, '.hidden.sqlite')));
    assert.ok(existsSync(outside));
  });

  it('keeps a temporary file whose process is still running, and says whose it is', async () => {
    // Reproduced by the reviewer with two concurrent runs: the pruning one deleted the
    // downloading one's temporary file, printed `a temporary file from an interrupted run` — which
    // it had not checked and which was false — and exited OK, while the other run died on
    // `rename` after transferring its bytes. `process.pid` here is a process that is certainly
    // alive: this one.
    const { into, baseURL } = await setUp();
    const live = `.us-ca-sj.sqlite.part-${process.pid}-abcd1234`;
    writeFileSync(join(into, live), Buffer.from('a download in flight'));

    const run = await runSync(['--dir', into, '--base-url', baseURL, '--prune']);

    assert.equal(run.code, 0, run.stderr);
    assert.ok(existsSync(join(into, live)), 'a live download\'s temporary file was deleted');
    assert.match(run.stdout, new RegExp(`unlisted \\${live} \\(a temporary file belonging to process ${process.pid}, which is still running\\)`));
  });

  it('keeps a temporary file written moments ago, whatever its pid says', async () => {
    // The second half of the same guard, for the window where a pid has gone but a file was just
    // written — and for the case the pid in the name has been reused by something unrelated.
    const { into, baseURL } = await setUp();
    const fresh = `.us-ca-sj.sqlite.part-${await deadPid()}-beef0000`;
    writeFileSync(join(into, fresh), Buffer.from('written just now'));

    const run = await runSync(['--dir', into, '--base-url', baseURL, '--prune']);

    assert.equal(run.code, 0, run.stderr);
    assert.ok(existsSync(join(into, fresh)));
    assert.match(run.stdout, /written moments ago/);
  });

  it('removes it with --prune, along with an interrupted download, and nothing else', async () => {
    const { into, baseURL } = await setUp();

    const run = await runSync(['--dir', into, '--base-url', baseURL, '--prune']);

    assert.equal(run.code, 0, run.stderr);
    assert.deepEqual(
      packsIn(into),
      ['sf.sqlite'],
      '--prune left something other than exactly the packs the catalog lists',
    );
    assert.equal(existsSync(join(into, stale)), false);
    // The file that is not a pack and not a temporary: --prune must never be a directory wipe.
    assert.ok(
      existsSync(join(into, 'README.txt')),
      '--prune deleted a file this script would never have written',
    );
    assert.deepEqual(readFileSync(join(into, 'README.txt'), 'utf8'), 'left here by an operator');
    assert.match(run.stdout, /pruned retired-city\.sqlite/);
    assert.match(run.stdout, /pruned=2/);
  });
});

// ── The destination, which has no default ────────────────────────────────────────────────────

describe('where the packs go', () => {
  /**
   * A base URL that cannot connect, passed to every case here that refuses before it fetches.
   *
   * **Not decoration.** Red-proving the case below — by making the script `mkdir -p` its
   * destination instead of refusing it — did not just turn the test red: the child then fell
   * through to its default base URL and began pulling 713 MB out of the live bucket, which is how
   * a suite that "never touches the network" touches the network. The refusals are what these
   * cases assert; the port is what makes a regression in them a failed connection instead of a
   * download.
   */
  const UNREACHABLE = 'http://127.0.0.1:9';

  it(`fails without --dir and without ${PACK_DIRECTORY_VARIABLE}, rather than defaulting anywhere`, async () => {
    const run = await runSync(['--base-url', UNREACHABLE]);

    assert.notEqual(run.code, 0, 'a run with no destination must not succeed');
    assert.match(run.stderr, new RegExp(PACK_DIRECTORY_VARIABLE));
    assert.match(run.stderr, /no destination directory/);
  });

  it('refuses a directory that does not exist rather than creating it', async () => {
    // `mkdir -p` on a mount point that is not mounted is how 713 MB lands on the root disk while
    // the volume sits empty beside it.
    const missing = join(directory(), 'not-mounted');
    const run = await runSync(['--dir', missing, '--base-url', UNREACHABLE]);

    assert.notEqual(run.code, 0);
    assert.equal(existsSync(missing), false, 'the destination was created');
    assert.match(run.stderr, /does not exist/);
  });

  it('refuses an argument it does not recognize', async () => {
    const run = await runSync(['--dir', directory(), '--base-url', UNREACHABLE, '--prume']);
    assert.notEqual(run.code, 0, 'a misspelled --prune that silently does nothing is worse');
    assert.match(run.stderr, /unknown argument/);
  });
});

// ── Where the packs come from ────────────────────────────────────────────────────────────────

describe('the production default', () => {
  const publishCities = readFileSync(`${repositoryRoot}Tools/publish_cities.py`, 'utf8');

  it('reads a Python string constant from its assignment and not from the prose around it', () => {
    // The specimen first, with the answer known before the parser saw it — `versions.ts`'s rule.
    const specimen = [
      '# LIVE_MANIFEST_URL = "https://wrong.example/manifest.json" in a comment',
      'LIVE_MANIFEST_URL = "https://right.example/manifest-v2.json"',
    ].join('\n');
    assert.equal(pythonStringConstant(specimen, 'LIVE_MANIFEST_URL'), 'https://right.example/manifest-v2.json');
    assert.equal(pythonStringConstant("X = 'single'", 'X'), 'single');
    assert.throws(() => pythonStringConstant('# X = "quoted"', 'X'), /no Python assignment/);
  });

  it('is the catalog URL the publisher itself writes to', () => {
    // The copies-agree bargain `versions.ts` strikes, for a URL instead of an integer. If the
    // bucket moves, this is what says the web did not move with it.
    assert.equal(
      manifestURL(),
      pythonStringConstant(publishCities, 'LIVE_MANIFEST_URL'),
      'web/src/lib/pack/bucket.ts and Tools/publish_cities.py name different catalogs',
    );
    assert.equal(manifestURL(), `${PUBLIC_BUCKET_BASE_URL}/${MANIFEST_OBJECT}`);
  });

  it('is what the script states when it is asked, and the only host it carries', async () => {
    const run = await runSync(['--help']);
    assert.equal(run.code, 0);
    assert.ok(
      run.stdout.includes(PUBLIC_BUCKET_BASE_URL),
      `the script's own usage does not name ${PUBLIC_BUCKET_BASE_URL} as its default`,
    );
    // And it names it by importing the constant rather than by spelling the host again: a second
    // copy is a second thing to move on the day the bucket does.
    const source = readFileSync(SCRIPT, 'utf8');
    assert.match(source, /PUBLIC_BUCKET_BASE_URL/);
    assert.equal(
      source.includes('tigrisbucket'),
      false,
      'scripts/sync-packs.mjs spells the bucket host itself instead of importing the constant',
    );
  });
});

describe('the URL and filename rules', () => {
  it('composes a pack URL under the base and trims a trailing slash', () => {
    assert.equal(
      packURL('https://example.test/', 'cities/sf/s17-r1-abc/sf.sqlite'),
      'https://example.test/cities/sf/s17-r1-abc/sf.sqlite',
    );
  });

  it('refuses a path that could address anything else', () => {
    // Each of these resolves somewhere other than "an object under the base URL" if it is handed
    // to `new URL(path, base)`, which is why the composition is not written that way.
    for (const offered of [
      '../../etc/passwd',
      '/etc/passwd',
      'https://elsewhere.test/sf.sqlite',
      'cities/../../sf.sqlite',
      'cities\\sf\\sf.sqlite',
      '',
    ]) {
      assert.throws(
        () => packURL('https://example.test', offered),
        UnsafePackPathError,
        `packURL accepted ${JSON.stringify(offered)}`,
      );
    }
  });

  it('refuses a base URL that is not http(s), and one that is not a URL', () => {
    assert.throws(() => normalizedBaseURL('file:///etc'), /http\(s\) only/);
    assert.throws(() => normalizedBaseURL('cypress-cities.t3.tigrisbucket.io'), /is not a URL/);
  });

  it('names a pack file by its id alone, and refuses an id that is not a plain name', () => {
    assert.equal(packFileName('us-ny-nyc-staten-island'), 'us-ny-nyc-staten-island.sqlite');
    for (const offered of ['../sf', 'sf/../..', '.hidden', '']) {
      assert.throws(() => packFileName(offered), UnsafePackPathError, `packFileName took ${offered}`);
    }
  });
});

// ── The image ────────────────────────────────────────────────────────────────────────────────

describe('the script reaches the deployed image', () => {
  const dockerfile = readFileSync(join(webRoot, 'Dockerfile'), 'utf8');
  /** The runtime stage: everything after the LAST `FROM`, which is the stage that ships. */
  const runtimeStage = dockerfile.slice(dockerfile.lastIndexOf('\nFROM '));

  it('copies scripts/ into the runtime stage', () => {
    // Without this the sync exists in the repository and not on the machine, which is where it is
    // needed and the only place it is ever run.
    assert.match(runtimeStage, /^COPY --from=build \/app\/scripts \.\/scripts$/m);
  });

  it('copies src/ too, because that is what the script imports', () => {
    // The failure this guards is specific: a script in the image whose imports are not is a script
    // that fails at `fly ssh console` time with `Cannot find module`, on the one night it matters.
    assert.match(runtimeStage, /^COPY --from=build \/app\/src \.\/src$/m);
  });

  it('imports nothing from outside the directories the image carries', () => {
    // The list above is an allowlist and `web/Dockerfile`'s own header says what happens to those:
    // "the allowlist rotted". So the check is not that two lines exist, it is that every relative
    // import this script makes resolves under a directory the runtime stage copies.
    const source = readFileSync(SCRIPT, 'utf8');
    const specifiers = [...source.matchAll(/^import\s[^']*'([^']+)'/gm)].map((match) => match[1]);
    const relative = specifiers.filter((specifier) => specifier?.startsWith('.'));
    assert.ok(
      relative.length >= 3,
      `found ${relative.length} relative import(s) in the script; it makes several, so this is `
        + 'reading the wrong file or the wrong pattern',
    );
    for (const specifier of relative) {
      assert.ok(
        specifier?.startsWith('../src/'),
        `scripts/sync-packs.mjs imports ${specifier}, which is not under a directory the runtime `
          + 'stage copies. Add it to web/Dockerfile, or stop importing it.',
      );
    }
  });
});
