/**
 * Where the published packs are fetched FROM, and how a catalog entry becomes a URL and a filename.
 *
 * `manifest.ts` decodes the catalog and `pack.ts` opens a file; neither one knows where a file
 * comes from, on purpose — a decoder that fetches is a decoder whose test needs a network. This is
 * the piece between them, and it is string-in / string-out for the same reason: everything here is
 * asserted against specimens, and `scripts/sync-packs.mjs` is the I/O around it.
 *
 * ## Anonymous reads are served on one host and not on the others
 *
 * `PUBLIC_BUCKET_BASE_URL` is the bucket's dedicated public domain. It is not interchangeable with
 * the S3 API endpoints for the same bucket: `Tools/publish_cities.py` records, beside its own
 * `--base-url` default, that Tigris **denies anonymous GET on `fly.storage.tigris.dev` and
 * `t3.storage.dev` even when the bucket is public** (verified 2026-08-01). No machine here holds a
 * bucket credential and none is wanted — CLAUDE.md's publishing rule is that credentials live on
 * the relay and nowhere else — so the public domain is not a convenience, it is the only route a
 * reader has. `test/sync-packs.test.ts` asserts this constant against `LIVE_MANIFEST_URL` in the
 * Python at run time, which is the same bargain `versions.ts` strikes: derive nothing, prove the
 * copies agree.
 *
 * ## A path out of the catalog is remote data and is treated as such
 *
 * `manifest.ts` refuses to surface `base_url_hint` at all, because "a remote object that can
 * redirect its own reader is a different security property from one that cannot". A `path` is the
 * same question one level down: it is a string from that same remote object, and it is about to be
 * appended to a base URL and joined onto a local directory. So `packURL` and `packFileName` refuse
 * anything that is not a plain relative path of plain segments — no scheme, no leading slash, no
 * `..`, no backslash, nothing outside `[A-Za-z0-9._-]`. Every path the live catalog has ever
 * carried is `cities/<id>/<version>/<id>.sqlite`, which this admits; a path that could escape the
 * destination directory is refused with its own error rather than sanitized into something
 * plausible.
 */

/** The bucket's dedicated public domain — the one host that serves anonymous GET. */
export const PUBLIC_BUCKET_BASE_URL = 'https://cypress-cities.t3.tigrisbucket.io';

/** The catalog object, at the base URL's root. `manifest_format` 2 lives here. */
export const MANIFEST_OBJECT = 'manifest-v2.json';

/** A catalog string that could address something other than an object under the base URL. */
export class UnsafePackPathError extends Error {
  /** The string the catalog carried, kept verbatim so an operator can see what arrived. */
  readonly offered: string;

  constructor(offered: string, detail: string) {
    super(
      `the catalog offers a path this reader will not follow (${detail}): ${JSON.stringify(offered)}`,
    );
    this.name = 'UnsafePackPathError';
    this.offered = offered;
  }
}

/** One path segment the reader will follow: no separators, no dots-only, nothing exotic. */
const SAFE_SEGMENT = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/**
 * A base URL with its trailing slashes gone, refused unless it is `http(s)`.
 *
 * The scheme is checked because this value comes from an operator's argument or environment, and
 * the one mistake worth catching is a `file:` or a bare hostname: the first would read the local
 * disk through the same code path, and the second is not a URL at all.
 */
export function normalizedBaseURL(base: string): string {
  const trimmed = base.trim().replace(/\/+$/, '');
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw new Error(
      `"${base}" is not a URL. The base URL must be absolute, like ${PUBLIC_BUCKET_BASE_URL}`,
    );
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error(
      `"${base}" is ${parsed.protocol} and this fetches over http(s) only. A local directory of `
        + 'packs is copied, not synced.',
    );
  }
  return trimmed;
}

/** The catalog object's URL under a base. */
export function manifestURL(base: string = PUBLIC_BUCKET_BASE_URL): string {
  return `${normalizedBaseURL(base)}/${MANIFEST_OBJECT}`;
}

/**
 * The URL of one pack, from its catalog `path`.
 *
 * Composed by concatenation after the path is checked, deliberately rather than by
 * `new URL(path, base)`: URL resolution would quietly accept `../`, accept an absolute path, and
 * accept a whole URL as the "relative" argument — which is the one thing this must not do.
 */
export function packURL(base: string, path: string): string {
  const normalized = normalizedBaseURL(base);
  if (path.length === 0) throw new UnsafePackPathError(path, 'it is empty');
  if (path.includes('\\')) throw new UnsafePackPathError(path, 'it contains a backslash');
  if (path.startsWith('/')) throw new UnsafePackPathError(path, 'it is absolute');
  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(path)) {
    throw new UnsafePackPathError(path, 'it carries a scheme');
  }
  for (const segment of path.split('/')) {
    if (!SAFE_SEGMENT.test(segment)) {
      throw new UnsafePackPathError(
        path,
        `the segment ${JSON.stringify(segment)} is not a plain name`,
      );
    }
  }
  return `${normalized}/${path}`;
}

/**
 * The name one pack is written under in the destination directory — `<id>.sqlite`.
 *
 * **Flat, and the version is not in the name.** `packLibrary.openPackLibrary` reads one directory,
 * non-recursively, and opens every `*.sqlite` in it; the bucket's `cities/<id>/<version>/` shape
 * is not what it indexes. Keeping the version in the filename would be worse than losing it: two
 * versions of one city would both match `*.sqlite`, both open, and both answer for the same id
 * space, so a refresh would serve a tree out of yesterday's pack on whichever path sorted first.
 * One file per pack id, replaced in place, is the layout that cannot say two things at once. What
 * identifies the bytes is the sha256 in the catalog, which is checked on every run.
 */
export function packFileName(id: string): string {
  if (!SAFE_SEGMENT.test(id)) {
    throw new UnsafePackPathError(
      id,
      'a pack id becomes a filename and this one is not a plain name',
    );
  }
  return `${id}.sqlite`;
}

/**
 * The string a Python module-level `NAME = "..."` assigns.
 *
 * The sibling of `versions.ts`'s `pythonIntConstant`, and it exists for the same job: the tests
 * read the publisher's own constants out of the publisher rather than agreeing with a copy. Single
 * or double quoted, no escapes — the assignment it reads is a URL literal, and a parser that
 * understood escapes would be inventing capability for a case that does not occur.
 */
export function pythonStringConstant(source: string, name: string): string {
  const re = new RegExp(`^${name}\\s*=\\s*(?:"([^"\\n]*)"|'([^'\\n]*)')\\s*(?:#.*)?$`, 'm');
  const match = re.exec(source);
  const value = match?.[1] ?? match?.[2];
  if (value === undefined) {
    throw new Error(`no Python assignment "${name} = <string>" at module level in that source`);
  }
  return value;
}
