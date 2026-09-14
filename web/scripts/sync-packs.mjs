#!/usr/bin/env node
//
// Fill (and refresh) a directory of published city packs from the public catalog.
//
//   npm run packs          (web/) sync CYPRESS_PACK_DIR from the public bucket
//   npm run packs -- --prune
//   node scripts/sync-packs.mjs --dir /data/packs --base-url http://127.0.0.1:8080
//
// `src/lib/packLibrary.ts` opens a directory of packs and serves pages out of it. **Nothing put
// the packs in that directory**: the phone downloads its own from the same catalog, the publisher
// writes to the bucket, and between those two there was no step that fills a server's disk. This
// is that step, run on the machine — `fly ssh console`, then this — and it is a script rather than
// a startup task on purpose: 713 MB over a cold network is not something a health check should be
// waiting on, and a server that fetches its own data at boot fails to start when the bucket has a
// bad minute.
//
// ── What it refuses, and why each refusal is worth its line ──────────────────────────────────
//
// **No default directory.** `packLibrary.ts` explains at length why it has none: a default makes
// "the volume is not mounted" look exactly like "the volume is mounted and empty", and those are a
// deployment that did not finish and an ordinary 404. This has the same rule with a sharper edge —
// a default here would write 713 MB onto the machine's root disk while the volume sat empty beside
// it — so the destination comes from `--dir` or `CYPRESS_PACK_DIR` and from nowhere else. The
// directory must already exist, too: creating it is the same mistake one step earlier, because a
// mount point that is not mounted is an ordinary empty directory and `mkdir -p` is delighted to
// fill it.
//
// **A generation this build does not read.** `NEWEST_KNOWN_PACK_SCHEMA_VERSION` is the number
// `pack.ts` refuses a file over, so a pack published past it is one this server would download in
// full and then decline to open. Refused here, by the catalog entry, before a byte moves.
//
// **An unknown envelope format.** `decodeManifest` refuses one outright before it looks at a
// single city, which is exactly what should happen: this build does not know what the rest of the
// object means.
//
// **Bytes that are not the bytes the catalog names.** Every pack streams to a temporary file in
// the destination directory, is hashed while it streams, and is compared against BOTH `bytes` and
// `sha256` before `rename()` puts it at its final path. Nothing is ever written to the final path
// directly. The temporary name is `.<id>.sqlite.part-<pid>-<random>` — deliberately not ending in
// `.sqlite`, because `packLibrary.packFiles` opens every `*.sqlite` in the directory and a
// half-downloaded pack that a running server opens is the precise failure this guards. `rename()`
// within one directory is atomic, so a reader sees the old file or the new one and never a
// fragment.
//
// **A path or an id out of the catalog that is not a plain relative name.** `bucket.ts` owns that
// rule and says why; the short version is that a remote object should not be able to choose where
// its reader writes.
//
// ── Retried, and not retried ─────────────────────────────────────────────────────────────────
//
// A transport failure — a refused connection, a 5xx, a stalled socket — is retried a bounded
// number of times with a short delay, because a flaky network is the ordinary reason a 199 MB
// download dies. **A body that arrived complete and failed verification is NOT retried.** The
// object either matches the catalog or it does not, and re-downloading 199 MB to be told the same
// thing is a way to turn one clear message into three slow ones. The stall timeout is per chunk
// rather than per request for the same reason: a large pack on a slow link is not a hung
// connection, and a whole-request deadline cannot tell them apart.
//
// ── Idempotent, and what identifies a file ───────────────────────────────────────────────────
//
// A pack already present at the right size and hash is skipped and said to be skipped, so a second
// run is legible and a refresh downloads only what changed. The layout is flat — `<id>.sqlite`,
// one file per pack id — which is what `packLibrary` indexes and which means **the published
// version string is not recorded on disk**. That is a deliberate trade and `bucket.ts`'s
// `packFileName` carries the argument: two versions of one city under one directory would both
// open and both answer for the same id space. The hash in the catalog is what identifies the
// bytes, and it is checked on every run, so "is this the current publish?" is answered by running
// this script and reading what it skipped.
//
// ── Two operational notes ────────────────────────────────────────────────────────────────────
//
// It runs as whatever user the shell is. The image's runtime stage is `USER node` and this is run
// from a root `fly ssh console` session; nothing here chowns anything, creates anything outside
// the destination directory, or assumes a user — a file it writes is owned by whoever ran it, and
// the server only ever reads.
//
// `node:sqlite`'s experimental warning appears on stderr because `packLibrary.ts` is imported for
// `CYPRESS_PACK_DIR`'s one definition. This script opens no database.
//
// Zero dependencies, like the rest of `web/`: global `fetch`, `node:crypto`, `node:fs`,
// `node:stream`. Node ≥ 24 strips the types from the `.ts` imports with no build step, the same
// thing `npm test` and `scripts/export-tokens.mjs` rely on. The JSDoc types are not decoration:
// `tsconfig.json` sets `checkJs`, so this file is typechecked with the same strictness as the
// `.ts` beside it and an unannotated parameter fails `npm run typecheck`.


import { createHash, randomBytes } from 'node:crypto';
import {
  createReadStream,
  createWriteStream,
  lstatSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
} from 'node:fs';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { setTimeout as sleep } from 'node:timers/promises';

import {
  manifestURL,
  normalizedBaseURL,
  packFileName,
  packURL,
  PUBLIC_BUCKET_BASE_URL,
} from '../src/lib/pack/bucket.ts';
import { decodeManifest } from '../src/lib/pack/manifest.ts';
import { NEWEST_KNOWN_PACK_SCHEMA_VERSION } from '../src/lib/pack/versions.ts';
import { PACK_DIRECTORY_VARIABLE, packDirectoryFromEnvironment } from '../src/lib/packLibrary.ts';

/** @typedef {import('../src/lib/pack/manifest.ts').ManifestCity} ManifestCity */
/** @typedef {{ directory: string | null, baseURL: string | null, prune: boolean, help: boolean }} Options */
/**
 * What is at a pack's destination path today.
 * @typedef {{ state: 'absent' | 'occupied' | 'current' | 'wrongSize' | 'wrongHash',
 *             bytes?: number, sha256?: string }} Existing
 */

/** The environment variable that points this at something other than the public bucket. */
const BASE_URL_VARIABLE = 'CYPRESS_PACK_BASE_URL';

/** Attempts per object, transport failures only. Three is one retry more than "the wifi blinked". */
const ATTEMPTS = 3;
/** Delay before retry N, multiplied by the attempt number. Not a backoff schedule, a pause. */
const RETRY_DELAY_MS = 500;
/** How long a transfer may go without delivering a chunk before it is treated as hung. */
const STALL_MS = 30_000;

/** A body that arrived whole and is not what the catalog described. Never retried. */
class VerificationError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = 'VerificationError';
  }
}

/** @returns {string} */
function usage() {
  return [
    'usage: node scripts/sync-packs.mjs [--dir <path>] [--base-url <url>] [--prune]',
    '',
    `  --dir <path>       where the packs go. Required, or set ${PACK_DIRECTORY_VARIABLE}.`,
    '                     The directory must already exist; this never creates it.',
    `  --base-url <url>   where they come from. Defaults to ${PUBLIC_BUCKET_BASE_URL}`,
    `                     (or ${BASE_URL_VARIABLE}).`,
    '  --prune            delete *.sqlite files the catalog does not list, and any',
    '                     temporary file left by an interrupted run. Off by default.',
    '',
    'Exit: 0 all good; 1 something was refused or failed; 2 the arguments or the',
    'destination are wrong, before any work started.',
  ].join('\n');
}

/**
 * A refusal before any work: bad arguments, no destination, nowhere to write.
 * @param {string} message
 * @returns {never}
 */
function refuse(message) {
  console.error(`SYNC-PACKS: FAILED ${message}`);
  console.error(usage());
  process.exit(2);
}

/**
 * A failure of the run itself: the catalog would not load, or would not decode.
 * @param {string} message
 * @returns {never}
 */
function fail(message) {
  console.error(`SYNC-PACKS: FAILED ${message}`);
  process.exit(1);
}

/** @param {unknown} error @returns {string} */
function reason(error) {
  return error instanceof Error ? error.message : String(error);
}

/**
 * @param {readonly string[]} argv
 * @returns {Options}
 */
function parseArguments(argv) {
  /** @type {Options} */
  const options = { directory: null, baseURL: null, prune: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const raw = argv[index] ?? '';
    const split = raw.indexOf('=');
    const flag = raw.startsWith('--') && split > 0 ? raw.slice(0, split) : raw;
    const inline = raw.startsWith('--') && split > 0 ? raw.slice(split + 1) : null;
    /** @param {string} name @returns {string} */
    const valueFor = (name) => {
      if (inline !== null) return inline;
      const next = argv[index + 1];
      if (next === undefined || next.startsWith('--')) refuse(`${name} needs a value`);
      index += 1;
      return next;
    };
    switch (flag) {
      case '-h':
      case '--help':
        options.help = true;
        break;
      case '--prune':
        options.prune = true;
        break;
      case '--dir':
        options.directory = valueFor('--dir');
        break;
      case '--base-url':
        options.baseURL = valueFor('--base-url');
        break;
      default:
        // Refused rather than ignored: an unrecognized flag is usually a misspelled one, and a
        // misspelled `--prune` that silently does nothing is worse than a stop.
        refuse(`unknown argument ${JSON.stringify(raw)}`);
    }
  }
  return options;
}

/**
 * One GET whose deadline is "this transfer has stopped moving" rather than "this transfer is
 * taking a while" — the distinction a 199 MB pack on a slow link depends on.
 *
 * The timer is re-armed around every chunk. `onChunk` may be async; it is awaited, so back
 * pressure from the disk reaches the socket instead of piling up in memory.
 *
 * @param {string} url
 * @param {(chunk: Uint8Array) => void | Promise<void>} onChunk
 * @returns {Promise<void>}
 */
async function fetchWithStallTimeout(url, onChunk) {
  const controller = new AbortController();
  /** @type {ReturnType<typeof setTimeout> | null} */
  let timer = null;
  const arm = () => {
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => {
      controller.abort(new Error(`no data for ${STALL_MS} ms`));
    }, STALL_MS);
  };
  arm();
  try {
    const response = await fetch(url, { signal: controller.signal, redirect: 'follow' });
    if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`.trim());
    if (response.body === null) throw new Error('the response carried no body');
    const reader = response.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      arm();
      if (value !== undefined) await onChunk(value);
    }
  } finally {
    if (timer !== null) clearTimeout(timer);
    // Releases the socket whether this returned or threw. Harmless after a body that finished.
    controller.abort();
  }
}

/**
 * Runs `attempt` until it succeeds or the attempts run out, retrying transport failures only.
 *
 * A `VerificationError` is rethrown immediately: the object either matches the catalog or it does
 * not, and asking again gets the same answer more slowly.
 *
 * @template T
 * @param {string} what
 * @param {() => Promise<T>} attempt
 * @returns {Promise<T>}
 */
async function withRetries(what, attempt) {
  /** @type {unknown} */
  let last = null;
  for (let number = 1; number <= ATTEMPTS; number += 1) {
    try {
      return await attempt();
    } catch (error) {
      if (error instanceof VerificationError) throw error;
      last = error;
      if (number === ATTEMPTS) break;
      console.error(
        `sync-packs: ${what} attempt ${number}/${ATTEMPTS} failed (${reason(error)}); retrying`,
      );
      await sleep(RETRY_DELAY_MS * number);
    }
  }
  throw last instanceof Error ? last : new Error(`${what} failed: ${String(last)}`);
}

/** @param {string} url @returns {Promise<string>} */
async function fetchText(url) {
  return withRetries(`GET ${url}`, async () => {
    /** @type {Uint8Array[]} */
    const parts = [];
    await fetchWithStallTimeout(url, (chunk) => {
      parts.push(chunk);
    });
    return Buffer.concat(parts).toString('utf8');
  });
}

/** The sha256 of a file already on disk, streamed rather than read into memory. */
/** @param {string} path @returns {Promise<string>} */
async function hashFile(path) {
  const hash = createHash('sha256');
  await pipeline(createReadStream(path), hash);
  return hash.digest('hex');
}

/**
 * What is at `path` today, measured against what the catalog says should be there.
 *
 * Size before hash because size is a stat and a hash is 82 MB of reading, and a file whose size is
 * wrong is already known to be the wrong bytes.
 *
 * @param {string} path
 * @param {ManifestCity} city
 * @returns {Promise<Existing>}
 */
async function inspectExisting(path, city) {
  let info;
  try {
    info = lstatSync(path);
  } catch {
    return { state: 'absent' };
  }
  if (!info.isFile()) return { state: 'occupied' };
  if (info.size !== city.bytes) return { state: 'wrongSize', bytes: info.size };
  const sha256 = await hashFile(path);
  if (sha256 !== city.sha256.toLowerCase()) return { state: 'wrongHash', sha256 };
  return { state: 'current' };
}

/**
 * Streams one pack to a temporary file, hashing as it goes. Returns what actually arrived —
 * the caller compares that against the catalog, and only then renames.
 *
 * @param {string} url
 * @param {string} temporaryPath
 * @returns {Promise<{ bytes: number, sha256: string }>}
 */
async function downloadToTemporary(url, temporaryPath) {
  const hash = createHash('sha256');
  let bytes = 0;
  // `wx` — refuse a temporary path that already exists rather than truncating a file some other
  // run is writing. With the random suffix, a collision is a bug and not a race.
  const file = createWriteStream(temporaryPath, { flags: 'wx' });
  try {
    await fetchWithStallTimeout(url, async (chunk) => {
      hash.update(chunk);
      bytes += chunk.length;
      if (!file.write(chunk)) {
        await new Promise((resolve, reject) => {
          file.once('drain', () => resolve(undefined));
          file.once('error', reject);
        });
      }
    });
  } finally {
    await new Promise((resolve, reject) => {
      file.on('error', reject);
      file.end(() => resolve(undefined));
    });
  }
  return { bytes, sha256: hash.digest('hex') };
}

/**
 * `*.sqlite` files the catalog does not list, and temporary files an earlier run left behind.
 *
 * Never a directory, never a symlink, never anything but a plain file this script could itself
 * have written: `--prune` deletes what this returns, so it must not be able to name something it
 * did not put there.
 *
 * @param {string} directory
 * @param {ReadonlySet<string>} expected
 * @returns {{ entry: string, path: string, reason: string }[]}
 */
function unlistedEntries(directory, expected) {
  /** @type {{ entry: string, path: string, reason: string }[]} */
  const found = [];
  for (const entry of readdirSync(directory).sort()) {
    const path = join(directory, entry);
    let info;
    try {
      info = lstatSync(path);
    } catch {
      continue;
    }
    if (!info.isFile()) continue;
    if (entry.startsWith('.') && entry.includes('.sqlite.part-')) {
      found.push({ entry, path, reason: 'a temporary file from an interrupted run' });
      continue;
    }
    if (entry.startsWith('.') || !entry.endsWith('.sqlite')) continue;
    if (expected.has(entry)) continue;
    found.push({ entry, path, reason: 'the catalog does not list it' });
  }
  return found;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const directory = options.directory ?? packDirectoryFromEnvironment();
  if (directory === null) {
    refuse(
      `no destination directory. Pass --dir <path> or set ${PACK_DIRECTORY_VARIABLE}. There is no `
        + 'default on purpose: a default would write the packs somewhere other than the volume and '
        + 'leave the volume looking mounted and empty.',
    );
  }
  let destination;
  try {
    destination = statSync(directory);
  } catch {
    refuse(
      `${directory} does not exist. This never creates the destination: an unmounted mount point `
        + 'is an ordinary empty directory, and filling one is how 713 MB lands on the root disk '
        + 'while the volume sits empty beside it.',
    );
  }
  if (!destination.isDirectory()) refuse(`${directory} is not a directory`);

  let base;
  try {
    base = normalizedBaseURL(
      options.baseURL ?? process.env[BASE_URL_VARIABLE] ?? PUBLIC_BUCKET_BASE_URL,
    );
  } catch (error) {
    refuse(reason(error));
  }

  // Cache-busted for `publish_cities.py`'s reason, stated where it reads the live catalog: a
  // catalog read through a cache can be older than the objects it is being compared against.
  const catalog = `${manifestURL(base)}?cb=${Date.now()}`;
  console.log(`sync-packs: catalog ${catalog}`);
  console.log(`sync-packs: destination ${directory}`);

  /** @type {import('../src/lib/pack/manifest.ts').Manifest} */
  let manifest;
  try {
    manifest = decodeManifest(await fetchText(catalog));
  } catch (error) {
    fail(`the catalog at ${catalog} is not usable: ${reason(error)}`);
  }
  console.log(
    `sync-packs: manifest_format ${manifest.format}, ${manifest.cities.length} pack(s) listed`,
  );

  /** @type {Set<string>} */
  const expected = new Set();
  let downloaded = 0;
  let skipped = 0;
  let pruned = 0;
  let refused = 0;
  let bytesDownloaded = 0;
  let bytesInPlace = 0;

  /** @param {ManifestCity} city @param {string} detail */
  const decline = (city, detail) => {
    refused += 1;
    console.error(`sync-packs: REFUSED ${city.id}: ${detail}`);
  };

  for (const city of manifest.cities) {
    let name;
    try {
      name = packFileName(city.id);
    } catch (error) {
      decline(city, reason(error));
      continue;
    }
    // Listed is listed: a pack refused below is still a pack the catalog names, so `--prune` must
    // not delete a copy of it that an earlier, happier run left in place.
    expected.add(name);

    if (city.schemaVersion > NEWEST_KNOWN_PACK_SCHEMA_VERSION) {
      decline(
        city,
        `the catalog publishes it at pack generation ${city.schemaVersion} and this build reads up `
          + `to ${NEWEST_KNOWN_PACK_SCHEMA_VERSION}. Teach the read layer the new generation before `
          + 'syncing it; downloading it would only produce a file the server declines to open.',
      );
      continue;
    }

    let url;
    try {
      url = packURL(base, city.path);
    } catch (error) {
      decline(city, reason(error));
      continue;
    }

    const target = join(directory, name);
    const existing = await inspectExisting(target, city);
    if (existing.state === 'current') {
      skipped += 1;
      bytesInPlace += city.bytes;
      console.log(
        `sync-packs: skipped ${city.id} (${city.version}, ${city.bytes} bytes, sha256 matches)`,
      );
      continue;
    }
    if (existing.state === 'occupied') {
      decline(city, `${target} exists and is not a regular file; refusing to replace it`);
      continue;
    }
    if (existing.state !== 'absent') {
      const why = existing.state === 'wrongSize'
        ? `${existing.bytes} bytes on disk, ${city.bytes} in the catalog`
        : 'sha256 differs from the catalog';
      console.log(`sync-packs: replacing ${city.id} (${why})`);
    }

    const temporary = join(
      directory,
      `.${name}.part-${process.pid}-${randomBytes(4).toString('hex')}`,
    );
    try {
      const measured = await withRetries(`GET ${url}`, async () => {
        // Every attempt starts from an empty temporary file. A resumed-into file would mix two
        // responses and hash to something that is neither.
        rmSync(temporary, { force: true });
        const result = await downloadToTemporary(url, temporary);
        if (result.bytes !== city.bytes) {
          throw new VerificationError(
            `the server sent ${result.bytes} bytes and the catalog says ${city.bytes}`,
          );
        }
        if (result.sha256 !== city.sha256.toLowerCase()) {
          throw new VerificationError(
            `sha256 ${result.sha256}, and the catalog says ${city.sha256.toLowerCase()}`,
          );
        }
        return result;
      });
      // The rename is the publish. Until this line the destination holds the old file or no file,
      // and a server reading the directory has never seen a fragment.
      renameSync(temporary, target);
      downloaded += 1;
      bytesDownloaded += measured.bytes;
      bytesInPlace += measured.bytes;
      console.log(
        `sync-packs: downloaded ${city.id} (${city.version}, ${measured.bytes} bytes, sha256 verified)`,
      );
    } catch (error) {
      // Whatever went wrong, the partial file goes with it. Nothing half-written is left behind,
      // and the destination path was never touched.
      rmSync(temporary, { force: true });
      decline(city, reason(error));
    }
  }

  for (const candidate of unlistedEntries(directory, expected)) {
    if (options.prune) {
      rmSync(candidate.path, { force: true });
      pruned += 1;
      console.log(`sync-packs: pruned ${candidate.entry} (${candidate.reason})`);
    } else {
      console.log(
        `sync-packs: unlisted ${candidate.entry} (${candidate.reason}); --prune removes it`,
      );
    }
  }

  // One line a human and a grep can both read, always printed, always the last thing. The exit
  // code says the same thing, and CLAUDE.md's rule about exit codes is why it is not the only
  // thing that does.
  const verdict = refused === 0 ? 'OK' : 'FAILED';
  console.log(
    `SYNC-PACKS: ${verdict} downloaded=${downloaded} skipped=${skipped} pruned=${pruned} `
      + `refused=${refused} bytes-downloaded=${bytesDownloaded} bytes-in-place=${bytesInPlace} `
      + `dir=${directory}`,
  );
  if (refused > 0) process.exitCode = 1;
}

try {
  await main();
} catch (error) {
  // An exception here is a bug in this script rather than a refusal it modeled. It still has to
  // leave a line the same grep finds, or a failed run looks like a run that never happened.
  console.error(`SYNC-PACKS: FAILED ${error instanceof Error ? error.stack : String(error)}`);
  process.exitCode = 1;
}
