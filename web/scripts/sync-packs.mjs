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
import { once } from 'node:events';
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

/**
 * An error that asking again cannot fix. `withRetries` rethrows one immediately.
 *
 * The distinction is the whole of the retry policy: a refused connection is worth another go and
 * a wrong answer is not.
 */
class TerminalError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = 'TerminalError';
  }
}

/** A body that arrived whole and is not what the catalog described. Never retried. */
class VerificationError extends TerminalError {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = 'VerificationError';
  }
}

/**
 * Local filesystem conditions that a retry can only repeat, more slowly and with more bytes.
 *
 * `ENOSPC` is the one that matters on a 713 MB fill into a sized volume: retried like a flaky
 * socket it would write the disk full three times over. The other four are the destination being
 * unwritable — permissions, a read-only mount, a path component that is not a directory — none of
 * which a second attempt changes.
 */
const LOCAL_DISK_CODES = new Set(['ENOSPC', 'EACCES', 'EROFS', 'ENOTDIR', 'EPERM', 'EDQUOT']);

/** @param {unknown} error @returns {boolean} */
function isLocalDiskError(error) {
  if (typeof error !== 'object' || error === null) return false;
  const code = /** @type {{ code?: unknown }} */ (error).code;
  return typeof code === 'string' && LOCAL_DISK_CODES.has(code);
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
      // Terminal, and a local disk failure is terminal too: see `LOCAL_DISK_CODES`.
      if (error instanceof TerminalError || isLocalDiskError(error)) throw error;
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
  // **The open is awaited, and that is a bug fix rather than tidiness.** `createWriteStream` opens
  // on a later tick; until something is listening, an `open(2)` failure — EACCES on a read-only
  // destination, EROFS, ENOTDIR — is emitted as an `'error'` event with no listener attached,
  // which Node throws from a tick this function's callers cannot catch. The process then died
  // with a stack trace and printed NO `SYNC-PACKS:` line at all, which is the one invariant this
  // script promises: a failed run has to leave a line the same grep finds. `events.once` attaches
  // the `'error'` listener synchronously, so the failure arrives here as a rejection and becomes
  // an ordinary refusal with a summary line after it. (A write failure *during* the transfer was
  // always handled, because `once(file, 'drain')` attaches one too — the hole was the open and
  // only the open.)
  const opened = once(file, 'open');
  let isOpen = false;
  try {
    await opened;
    isOpen = true;
    await fetchWithStallTimeout(url, async (chunk) => {
      hash.update(chunk);
      bytes += chunk.length;
      // `events.once` and not a hand-rolled pair of `file.once(...)` listeners: the hand-rolled
      // version removed its `drain` listener and left its `error` listener attached, so a pack big
      // enough to need back pressure retained one per drain — `MaxListenersExceededWarning` at 11,
      // and thousands by the end of a 199 MB download. Found by running this against the real
      // bucket; `test/sync-packs.test.ts` now streams 4 MB through it so a suite of small
      // specimens cannot hide it again. `once` removes both listeners however the wait ends.
      if (!file.write(chunk)) await once(file, 'drain');
    });
  } finally {
    // Nothing to close if it never opened, and `end()` on a stream that failed to open is a wait
    // with nothing to wake it. A flush failure — ENOSPC on the last write — still rejects here,
    // which is where a run into a full volume is supposed to hear about it.
    if (isOpen) {
      await new Promise((resolve, reject) => {
        file.on('error', reject);
        file.end(() => resolve(undefined));
      });
    } else {
      file.destroy();
    }
  }
  return { bytes, sha256: hash.digest('hex') };
}

/** The pid and the random tail of a temporary name this script writes. */
const TEMPORARY_NAME = /\.sqlite\.part-(\d+)-[0-9a-f]+$/;

/**
 * Whether a process id is one the operating system still knows about.
 *
 * `kill(pid, 0)` sends no signal and only asks. `EPERM` means it exists and is not ours, which is
 * still "alive" for this question; only `ESRCH` means nobody is there. Pid reuse can make this
 * answer "alive" about a different process, and that is the safe direction — the consequence is a
 * temporary file kept one run longer.
 *
 * @param {number} pid @returns {boolean}
 */
function processIsAlive(pid) {
  // A pid this cannot reason about is treated as alive, because the consequence of guessing
  // "alive" is one kept file and the consequence of guessing "dead" is somebody's transfer. `0`
  // is not a process, it is the caller's process group, and it is not asked about.
  if (!Number.isInteger(pid) || pid <= 0) return true;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    const code = typeof error === 'object' && error !== null
      ? /** @type {{ code?: unknown }} */ (error).code
      : undefined;
    // `ESRCH` is the only answer that means nobody is there. `EPERM` means it exists and belongs
    // to somebody else, which is still a running process.
    return code !== 'ESRCH';
  }
}

/**
 * Everything in the destination that is not a pack the catalog lists — what `--prune` may delete,
 * and, separately, what it may not delete but an operator should still be told about.
 *
 * **Two sets, and they differ on purpose.**
 *
 * *Deletable* is the narrow one: a plain file, never a symlink and never a directory, that this
 * script could itself have written — an unlisted `<id>.sqlite`, or a leftover temporary. `--prune`
 * removes exactly this, and the narrowness is the point: it must not be able to delete something
 * it did not put there.
 *
 * *Reportable* is the wider one, and it exists because the narrow set is not what the SERVER
 * opens. `packLibrary.packFiles` takes every name ending in `.sqlite` and stats it — **it does not
 * skip dot-files and it follows symlinks** — so a `.hidden.sqlite`, or a `link.sqlite` pointing
 * clean out of the destination, is a file the reader will serve and a file `--prune` will not
 * touch. Before this, it was also a file nothing mentioned, and the run said `OK`. Nothing this
 * script writes can produce either one, so this is about a directory somebody has poked at
 * looking clean when it is not.
 *
 * @param {string} directory
 * @param {ReadonlySet<string>} expected
 * @returns {{ entry: string, path: string, reason: string, deletable: boolean }[]}
 */
function unlistedEntries(directory, expected) {
  /** @type {{ entry: string, path: string, reason: string, deletable: boolean }[]} */
  const found = [];
  for (const entry of readdirSync(directory).sort()) {
    const path = join(directory, entry);
    let info;
    try {
      info = lstatSync(path);
    } catch {
      continue;
    }
    const temporary = TEMPORARY_NAME.exec(entry);
    if (info.isFile() && entry.startsWith('.') && temporary !== null) {
      // **A temporary file may belong to a run that is still going.** Deleting a live download's
      // file makes that run die on `rename` after transferring up to 199 MB, and the old message
      // asserted it had found an interrupted run, which it had not checked. Two cheap questions
      // answer it: is the pid in the name still a process, and was the file touched inside the
      // stall window? Either one means hands off.
      const pid = Number(temporary[1]);
      if (processIsAlive(pid)) {
        found.push({
          entry,
          path,
          reason: `a temporary file belonging to process ${pid}, which is still running`,
          deletable: false,
        });
        continue;
      }
      if (Date.now() - info.mtimeMs < STALL_MS) {
        found.push({
          entry,
          path,
          reason: 'a temporary file written moments ago; a run may still be holding it',
          deletable: false,
        });
        continue;
      }
      found.push({
        entry,
        path,
        reason: `a temporary file from process ${pid}, which is no longer running`,
        deletable: true,
      });
      continue;
    }
    if (!entry.endsWith('.sqlite')) continue;
    if (expected.has(entry)) continue;
    if (info.isFile() && !entry.startsWith('.')) {
      found.push({ entry, path, reason: 'the catalog does not list it', deletable: true });
      continue;
    }
    // Not deletable. Report it anyway if the server would open it, or trip over it.
    let target;
    try {
      target = statSync(path);
    } catch {
      found.push({
        entry,
        path,
        reason: 'the catalog does not list it and it cannot be resolved; the server reports a '
          + 'name ending in .sqlite that it cannot stat as a problem',
        deletable: false,
      });
      continue;
    }
    if (!target.isFile()) continue;
    found.push({
      entry,
      path,
      reason: info.isSymbolicLink()
        ? 'the catalog does not list it and it is a symlink; the server follows symlinks and '
          + 'would serve whatever it points at'
        : 'the catalog does not list it and it is a dot-file; the server does not skip those',
      deletable: false,
    });
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
  // **Two entries that would land on one file is a catalog this run refuses to act on.**
  // Not an arithmetic problem to paper over: whichever entry came second would overwrite the
  // first, the summary would count both — `bytes-in-place` genuinely double-counted, and the
  // README calls that line the one to read — and the volume would end up holding one city under a
  // name that claims to be two. Refused whole, before a byte moves, the same way an unknown
  // envelope format is. The comparison is case-insensitive as well as exact: the Fly volume is
  // case-sensitive, so `SF` and `sf` are two files there and one file on a developer's Mac, and
  // no catalog has ever published a pair that differs only in case.
  /** @type {Map<string, { id: string, name: string }[]>} */
  const byFileName = new Map();
  for (const city of manifest.cities) {
    let name;
    try {
      name = packFileName(city.id);
    } catch {
      // An id this build will not turn into a filename is declined per-pack below, with its own
      // message. It cannot collide with anything, because nothing is ever written for it.
      continue;
    }
    const key = name.toLowerCase();
    byFileName.set(key, [...(byFileName.get(key) ?? []), { id: city.id, name }]);
  }
  for (const [, entries] of byFileName) {
    if (entries.length < 2) continue;
    const ids = entries.map((each) => each.id).join(', ');
    const identical = entries.every((each) => each.name === entries[0]?.name);
    fail(
      identical
        ? `the catalog lists ${entries.length} entries whose pack ids are the same file on disk `
          + `(${ids} all become ${entries[0]?.name}). One of them would silently overwrite the `
          + 'other and the summary would count both, so nothing is synced from this catalog.'
        : `the catalog lists ${entries.length} pack ids that differ only in case (${ids}). They `
          + 'are two files on the volume and one file on a case-insensitive filesystem, so this '
          + 'refuses rather than behaving differently depending on where it runs.',
    );
  }

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
    if (!candidate.deletable) {
      console.log(
        `sync-packs: unlisted ${candidate.entry} (${candidate.reason}); --prune does NOT remove it`,
      );
      continue;
    }
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
