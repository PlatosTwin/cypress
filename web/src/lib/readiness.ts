/**
 * Is this process holding packs, and which — the one question a deploy needs answered.
 *
 * `src/lib/packLibrary.ts` already distinguishes three situations a caller must never let collapse
 * into each other, and its header says why:
 *
 *   * `CYPRESS_PACK_DIR` unset — the caller is handed `null`. A deployment that did not finish.
 *   * the directory named and not readable — no volume mounted, or a path inside it that is not
 *     there. Also a deployment that did not finish, and a DIFFERENT repair.
 *   * the directory readable and holding no pack this build can open — a volume mounted and not
 *     yet filled. The sync has not run, or it ran and wrote nothing.
 *
 * and then the state a reader wants: packs open, for these id spaces, with these refusals.
 *
 * Four states rather than three, because the middle one is two repairs wearing one name: a missing
 * mount is `flyctl volumes`, an empty one is running the sync. A human curling this has to be able
 * to tell them apart, which is the whole requirement.
 *
 * ── What is NOT in the body ──────────────────────────────────────────────────────────────────
 *
 * This surface is anonymous and unauthenticated — the same audience as the tree page, which is to
 * say everybody. So it prints no absolute path and no environment value. The directory
 * `CYPRESS_PACK_DIR` names is deployment topology; the id spaces and the pack count are already
 * public, being the URLs the site answers on. A file that refused to open is reported by its
 * BASENAME, and its reason is swept for the pack directory before it is printed, because those
 * reasons come from `openPack` and from `node:sqlite` and this module does not get to assume what
 * a future one of them will interpolate. The unredacted error goes to the machine's log, where an
 * operator with `flyctl logs` can read it and a crawler cannot.
 *
 * `redactDirectory` is that sweep, and it is exported so a test can calibrate it against a string
 * whose answer is known rather than against whatever `node:sqlite` happens to say today.
 */
import { basename } from 'node:path';

import {
  packDirectoryFromEnvironment,
  packLibrary,
  PACK_DIRECTORY_VARIABLE,
  type PackLibrary,
} from './packLibrary.ts';

/** Which Fly app answered. `cypress-sync`'s own `/health` states its service name the same way. */
export const SERVICE = 'cypress-web';

export type ReadinessState =
  /** `CYPRESS_PACK_DIR` is unset. The image was deployed without the environment it needs. */
  | 'unconfigured'
  /** The variable is set and the directory it names could not be read. No volume, or no path. */
  | 'unreadable'
  /** The directory read, and holds no pack this build can open. A volume nobody has filled. */
  | 'empty'
  /** Packs are open. `idSpaces` says which URLs this process can answer. */
  | 'serving';

/** A file in the pack directory that did not open, named the way a public body may name it. */
export interface ReadinessProblem {
  /** The basename. The directory it sat in is deployment topology and is not printed. */
  readonly file: string;
  /** Why it refused, with any occurrence of the pack directory swept out of it. */
  readonly reason: string;
}

export interface ReadinessReport {
  readonly service: string;
  /** True when this process holds at least one pack, so some URL on it can be answered. */
  readonly ready: boolean;
  readonly state: ReadinessState;
  /** One sentence naming the state and its repair, for the human who ran `curl`. */
  readonly detail: string;
  /** The id spaces answerable from the open packs, sorted — the `‹id-space›` of a public URL. */
  readonly idSpaces: readonly string[];
  /** How many packs opened. Five of the seven published today are New York. */
  readonly packs: number;
  /** Files that refused to open. Never dropped, in any state, `serving` included. */
  readonly problems: readonly ReadinessProblem[];
}

/**
 * Every occurrence of `directory` in `text`, replaced by a placeholder.
 *
 * Deliberately a sweep over the finished string, and not a promise that each message was built
 * carefully. The reasons on `PackLibrary.problems` are whatever `openPack`, `node:sqlite` and a
 * future contributor put there; a redaction that trusted them would be a comment asserting an
 * invariant nobody had checked.
 */
export function redactDirectory(text: string, directory: string): string {
  if (directory.length === 0) return text;
  return text.split(directory).join('<pack-dir>');
}

/**
 * What this process would answer about itself right now.
 *
 * It reads the SAME `packLibrary()` the pages read rather than re-opening the directory, because
 * the question is what this process is holding and not what the filesystem holds. The packs are
 * opened once and kept for the life of the process (see `packLibrary.ts`), so a volume filled
 * after that open is a machine that needs replacing — and an endpoint that re-read the directory
 * would report the good news while every page went on serving 404s.
 */
export function readinessReport(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): ReadinessReport {
  const nothing = { idSpaces: [], packs: 0, problems: [] } as const;

  const directory = packDirectoryFromEnvironment(environment);
  if (directory === null) {
    return {
      service: SERVICE,
      ready: false,
      state: 'unconfigured',
      detail: `${PACK_DIRECTORY_VARIABLE} is not set, so this process was never told where the `
        + 'packs are. Set it in fly.toml [env], to the path [mounts] destination names.',
      ...nothing,
    };
  }

  let library: PackLibrary | null;
  try {
    library = packLibrary(environment);
  } catch (error) {
    // The path is in the error and the error is not in the response. An operator reads it with
    // `flyctl logs`; a crawler gets the sentence below.
    console.error(`/health: ${PACK_DIRECTORY_VARIABLE} could not be read`, error);
    return {
      service: SERVICE,
      ready: false,
      state: 'unreadable',
      detail: `the directory ${PACK_DIRECTORY_VARIABLE} names could not be read — the volume is `
        + 'not mounted, or that path inside it does not exist. The error, with the path, is in '
        + "this machine's log.",
      ...nothing,
    };
  }
  if (library === null) {
    // Unreachable: `packLibrary` returns null only for an unset variable, which the first branch
    // already answered. Stated rather than asserted away with a `!`, which would be this file
    // promising something about another module's control flow.
    return {
      service: SERVICE,
      ready: false,
      state: 'unconfigured',
      detail: `${PACK_DIRECTORY_VARIABLE} read as unset on the second look`,
      ...nothing,
    };
  }

  const held = library;
  const problems = held.problems.map((problem) => ({
    file: basename(problem.path),
    reason: redactDirectory(problem.reason, held.directory),
  }));
  const idSpaces = [...held.byIdSpace.keys()].sort();
  // Appended to the detail rather than folded into `ready`. A pack that refused to open is a whole
  // city missing and is invisible in a count that went up — but it does not stop the process
  // answering for the cities it did open, and a `ready: false` meaning both would send an operator
  // to the wrong repair.
  const alsoRefused = problems.length === 0
    ? ''
    : ` ${problems.length} file(s) in that directory did not open — see problems.`;

  if (held.packs.length === 0) {
    return {
      service: SERVICE,
      ready: false,
      state: 'empty',
      detail: 'the pack directory is readable and holds no pack this build can open — the volume '
        + `is mounted and has not been filled.${alsoRefused}`,
      idSpaces,
      packs: 0,
      problems,
    };
  }

  return {
    service: SERVICE,
    ready: true,
    state: 'serving',
    detail: `${held.packs.length} pack(s) open, answering for ${idSpaces.join(', ')}.${alsoRefused}`,
    idSpaces,
    packs: held.packs.length,
    problems,
  };
}
