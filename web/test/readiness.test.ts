import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import type { APIRoute } from 'astro';

import { PACK_DIRECTORY_VARIABLE, resetPackLibraryCache } from '../src/lib/packLibrary.ts';
import { redactDirectory, type ReadinessReport } from '../src/lib/readiness.ts';
import { GET } from '../src/pages/health.ts';
import { buildPack, type Fixture } from './support/packFixture.ts';

/**
 * `/health`, driven through the route rather than around it.
 *
 * **Every state below is built on disk and then asked for, not handed to a stub.** The difference
 * matters more than usual here: what this endpoint is for is telling three deployment failures
 * apart, and a suite that constructed the three answers directly would prove that four literals
 * are different from each other. So there is a real directory with a real pack in it, a real
 * directory with a real file that is not a pack, a real empty directory, and a path that really is
 * not there — and the endpoint is asked, through `packLibrary()`, the same call the pages make.
 *
 * The pack is built at test time by executing `Fixtures/seed/schema.sql`, the way the rest of the
 * pack suite builds its specimens; CI has no published pack.
 */

const temporary: string[] = [];
const fixtures: Fixture[] = [];
const originalPackDirectory = process.env[PACK_DIRECTORY_VARIABLE];

after(() => {
  for (const fixture of fixtures) fixture.cleanup();
  for (const directory of temporary) rmSync(directory, { recursive: true, force: true });
  if (originalPackDirectory === undefined) delete process.env[PACK_DIRECTORY_VARIABLE];
  else process.env[PACK_DIRECTORY_VARIABLE] = originalPackDirectory;
  resetPackLibraryCache();
});

// The library is opened once per process and kept (`packLibrary.ts`), which is right in a server
// and fatal in a suite that changes the directory under it. Every test here starts from no cache.
beforeEach(() => {
  resetPackLibraryCache();
  delete process.env[PACK_DIRECTORY_VARIABLE];
});

function directory(): string {
  const path = mkdtempSync(join(tmpdir(), 'cypress-readiness-'));
  temporary.push(path);
  return path;
}

/** A built pack fixture, copied into `into` under `name`. The fixture keeps its own temp dir. */
function placePack(into: string, name: string): void {
  const fixture = buildPack(17);
  fixtures.push(fixture);
  copyFileSync(fixture.path, join(into, name));
}

interface Answer {
  readonly status: number;
  readonly contentType: string | null;
  readonly cacheControl: string | null;
  readonly text: string;
  readonly report: ReadinessReport;
}

/** One `GET /health`, with the body both as text and parsed. */
async function health(): Promise<Answer> {
  const response = await GET({} as Parameters<APIRoute>[0]);
  const text = await response.text();
  return {
    status: response.status,
    contentType: response.headers.get('content-type'),
    cacheControl: response.headers.get('cache-control'),
    text,
    report: JSON.parse(text) as ReadinessReport,
  };
}

describe('the redaction', () => {
  // Specimen first, answer known before the sweep saw it. A redaction asserted only against
  // whatever `node:sqlite` says today agrees with whatever `node:sqlite` says today.
  it('removes every occurrence of the directory, not the first', () => {
    assert.equal(
      redactDirectory('/data/packs/a.sqlite and /data/packs/b.sqlite', '/data/packs'),
      '<pack-dir>/a.sqlite and <pack-dir>/b.sqlite',
    );
  });

  it('leaves a message that does not name the directory alone', () => {
    assert.equal(redactDirectory('file is not a database', '/data/packs'), 'file is not a database');
  });

  it('does not shred the message when the directory is empty', () => {
    // `''` splits between every character. The guard is one line in the source and this is the
    // case that proves the line is there.
    assert.equal(redactDirectory('file is not a database', ''), 'file is not a database');
  });
});

describe('GET /health tells the deployment failures apart', () => {
  it('says `unconfigured` when CYPRESS_PACK_DIR is unset', async () => {
    const answer = await health();
    assert.equal(answer.report.state, 'unconfigured');
    assert.equal(answer.report.ready, false);
    assert.equal(answer.report.packs, 0);
    assert.deepEqual(answer.report.idSpaces, []);
    assert.match(answer.report.detail, new RegExp(PACK_DIRECTORY_VARIABLE));
  });

  it('says `unreadable` for a directory that is not there, and logs the path it could not read', async () => {
    const missing = join(tmpdir(), 'cypress-readiness-no-such-directory-7c21');
    process.env[PACK_DIRECTORY_VARIABLE] = missing;

    // The unredacted error is meant to reach the machine's log and nowhere else, so the log is the
    // other half of this assertion rather than noise to be silenced.
    const logged: string[] = [];
    const realError = console.error;
    console.error = (...parts: unknown[]): void => {
      logged.push(parts.map((part) => (part instanceof Error ? part.message : String(part))).join(' '));
    };
    let answer: Answer;
    try {
      answer = await health();
    } finally {
      console.error = realError;
    }

    assert.equal(answer.report.state, 'unreadable');
    assert.equal(answer.report.ready, false);
    assert.ok(
      logged.some((line) => line.includes(missing)),
      `the path was not written to the log; console.error saw ${JSON.stringify(logged)}`,
    );
  });

  it('says `empty` for a mounted volume nobody has filled', async () => {
    process.env[PACK_DIRECTORY_VARIABLE] = directory();
    const answer = await health();
    assert.equal(answer.report.state, 'empty');
    assert.equal(answer.report.ready, false);
    assert.equal(answer.report.packs, 0);
    assert.deepEqual(answer.report.problems, []);
  });

  it('says `serving`, with the id spaces and the count, when a pack is open', async () => {
    const into = directory();
    placePack(into, 'sf.sqlite');
    process.env[PACK_DIRECTORY_VARIABLE] = into;

    const answer = await health();
    assert.equal(answer.report.state, 'serving');
    assert.equal(answer.report.ready, true);
    assert.equal(answer.report.packs, 1);
    assert.deepEqual(answer.report.idSpaces, ['sf']);
    assert.deepEqual(answer.report.problems, []);
    assert.equal(answer.report.service, 'cypress-web');
  });

  it('reports a file that refused to open, and keeps serving the pack beside it', async () => {
    const into = directory();
    placePack(into, 'sf.sqlite');
    writeFileSync(join(into, 'half-copied.sqlite'), 'this is not a database');
    process.env[PACK_DIRECTORY_VARIABLE] = into;

    const answer = await health();
    assert.equal(answer.report.state, 'serving', 'a bad neighbor stopped the good pack being served');
    assert.equal(answer.report.ready, true);
    assert.equal(answer.report.packs, 1);
    assert.equal(answer.report.problems.length, 1);
    assert.equal(answer.report.problems[0]?.file, 'half-copied.sqlite');
    assert.match(answer.report.problems[0]?.reason ?? '', /not a database/);
    // The count is in the sentence too, for the reader who does not parse the JSON.
    assert.match(answer.report.detail, /did not open/);
  });

  it('an unfilled volume holding only junk is `empty` AND names the junk', async () => {
    // The pair to the test above, and the reason `problems` is not folded into `ready`: this
    // machine is unready and the reason is on the disk, not missing from it.
    const into = directory();
    writeFileSync(join(into, 'half-copied.sqlite'), 'this is not a database');
    process.env[PACK_DIRECTORY_VARIABLE] = into;

    const answer = await health();
    assert.equal(answer.report.state, 'empty');
    assert.equal(answer.report.ready, false);
    assert.equal(answer.report.problems.length, 1);
    assert.equal(answer.report.problems[0]?.file, 'half-copied.sqlite');
  });

  it('the four states really are four different answers', async () => {
    // The control. Every assertion above would hold if the endpoint returned one constant with a
    // different field read each time; this is the one that cannot.
    const states: string[] = [];

    resetPackLibraryCache();
    delete process.env[PACK_DIRECTORY_VARIABLE];
    states.push((await health()).report.state);

    resetPackLibraryCache();
    process.env[PACK_DIRECTORY_VARIABLE] = join(tmpdir(), 'cypress-readiness-no-such-directory-7c21');
    const realError = console.error;
    console.error = (): void => {};
    try {
      states.push((await health()).report.state);
    } finally {
      console.error = realError;
    }

    resetPackLibraryCache();
    process.env[PACK_DIRECTORY_VARIABLE] = directory();
    states.push((await health()).report.state);

    resetPackLibraryCache();
    const served = directory();
    placePack(served, 'sf.sqlite');
    process.env[PACK_DIRECTORY_VARIABLE] = served;
    states.push((await health()).report.state);

    assert.deepEqual(states, ['unconfigured', 'unreadable', 'empty', 'serving']);
    assert.equal(new Set(states).size, 4);
  });
});

describe('what GET /health is allowed to say to an anonymous reader', () => {
  it('prints no absolute path and no environment value, in the state that has both', async () => {
    const into = directory();
    placePack(into, 'sf.sqlite');
    writeFileSync(join(into, 'half-copied.sqlite'), 'this is not a database');
    process.env[PACK_DIRECTORY_VARIABLE] = into;

    const answer = await health();
    // The whole body, not a field: a path can only leak through a field somebody forgot to check.
    assert.equal(
      answer.text.includes(into),
      false,
      `the body names the pack directory:\n${answer.text}`,
    );
    // And the calibration, because the assertion above passes for free if `into` is somehow not in
    // any message to begin with. The unredacted reason DOES carry the path in the shape this
    // endpoint reports it — basename plus a swept reason — so proving the sweep fired means
    // proving the endpoint's own `file` field is a basename and not the path it came from.
    assert.equal(answer.report.problems[0]?.file, 'half-copied.sqlite');
    assert.equal(answer.report.problems[0]?.file.includes('/'), false);
  });

  it('answers 200 in every state, including the unready ones', async () => {
    // The decision this route's header argues for, pinned. A `[[http_service.checks]]` gates the
    // release: a 503 while the volume is empty makes the FIRST deploy — onto a volume that is
    // empty by construction — impossible to complete, and presents as a rollback naming nothing.
    process.env[PACK_DIRECTORY_VARIABLE] = directory();
    const unready = await health();
    assert.equal(unready.report.ready, false);
    assert.equal(unready.status, 200);

    resetPackLibraryCache();
    const served = directory();
    placePack(served, 'sf.sqlite');
    process.env[PACK_DIRECTORY_VARIABLE] = served;
    const ready = await health();
    assert.equal(ready.report.ready, true);
    assert.equal(ready.status, 200);
  });

  it('is JSON and is never cached', async () => {
    process.env[PACK_DIRECTORY_VARIABLE] = directory();
    const answer = await health();
    assert.match(answer.contentType ?? '', /^application\/json/);
    assert.equal(answer.cacheControl, 'no-store');
  });
});
