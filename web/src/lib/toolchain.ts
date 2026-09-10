/**
 * Where the Node version is written down, and how to read each one back.
 *
 * It is written down four times and there is no way to write it once: `package.json` `engines`
 * is what npm enforces, `.nvmrc` is what `actions/setup-node` reads in CI, and the Dockerfile's
 * two `FROM` lines are what actually runs in production. Four copies of one fact is the shape
 * this repository has already been bitten by twice (`.github/workflows/testflight.yml`'s deploy
 * deny-list, `server/Dockerfile`'s COPY allowlist), and in both cases the fix was the same:
 * derive nothing, assert that the copies agree.
 *
 * The drift this guards is not hypothetical and it is not loud. A Dockerfile pinned a minor
 * behind `engines` produces an image that boots, serves, and differs from CI on exactly the
 * things a minor changes — which for this project's runtime means `node:sqlite`, still marked
 * experimental and explicitly documented as free to change.
 *
 * Deliberately string-in / string-out with no I/O: the caller opens the files. A module that
 * reads its own repository is a module that cannot be tested without one.
 */

/** The `engines.node` range as written, e.g. `">=24.13.1 <25"`. */
export function engineRange(packageJson: string): string {
  const parsed: unknown = JSON.parse(packageJson);
  const engines: unknown =
    typeof parsed === 'object' && parsed !== null
      ? (parsed as Record<string, unknown>)['engines']
      : undefined;
  const node: unknown =
    typeof engines === 'object' && engines !== null
      ? (engines as Record<string, unknown>)['node']
      : undefined;
  if (typeof node !== 'string' || node.length === 0) {
    throw new Error('package.json declares no engines.node — nothing pins the runtime');
  }
  return node;
}

/**
 * The exact version the `engines` range floors at: `">=24.13.1 <25"` → `24.13.1`.
 *
 * A range is not a version, so this is the one number the other three copies are compared
 * against. A range with no `>=` floor pins nothing and is refused rather than defaulted.
 */
export function engineFloor(packageJson: string): string {
  const match = /(^|\s)>=\s*(\d+\.\d+\.\d+)(\s|$)/.exec(engineRange(packageJson));
  if (match?.[2] === undefined) {
    throw new Error(
      `engines.node is "${engineRange(packageJson)}", which has no >=x.y.z floor — it pins no exact version`,
    );
  }
  return match[2];
}

/** The version in `.nvmrc`, trimmed. A leading `v` is accepted and dropped. */
export function nvmrcVersion(nvmrc: string): string {
  const trimmed = nvmrc.trim().replace(/^v/, '');
  if (!/^\d+\.\d+\.\d+$/.test(trimmed)) {
    throw new Error(`.nvmrc reads "${nvmrc.trim()}", which is not an exact x.y.z version`);
  }
  return trimmed;
}

/**
 * Every Node version named by a `FROM node:<version>...` line in a Dockerfile, in file order.
 *
 * All of them, not the first: a multi-stage build whose builder and runtime disagree is the
 * defect, so a reader of this list has to see both to notice.
 */
export function dockerfileNodeVersions(dockerfile: string): readonly string[] {
  const found: string[] = [];
  for (const line of dockerfile.split('\n')) {
    const match = /^\s*FROM\s+node:(\d+\.\d+\.\d+)(?:-[\w.]+)?(?:\s|$)/i.exec(line);
    if (match?.[1] !== undefined) found.push(match[1]);
  }
  return found;
}

/**
 * Every port this file states, in file order, from the four directives that carry one.
 *
 * `Dockerfile`: `ENV PORT=<n>` and `EXPOSE <n>`. `fly.toml`: `PORT = '<n>'` and
 * `internal_port = <n>`. Comments are deliberately NOT matched — `fly.toml`'s own comment named
 * the number and the count of copies, said "three", and was wrong the day it was written. A
 * matcher that read comments would have agreed with it.
 *
 * Four copies of one fact is the shape this repository has been bitten by twice, and the fix is
 * the same both times: assert that the copies agree. `fly.toml` promised this guard ("the shape
 * of guard to extend if a fourth appears") without writing it, and by then there were four.
 */
export function declaredPorts(text: string): readonly number[] {
  const found: number[] = [];
  for (const line of text.split('\n')) {
    // A comment is not a directive. `#` is the comment character in both file formats.
    const code = line.replace(/#.*$/, '');
    const match =
      /^\s*ENV\s+PORT=(\d+)\s*$/i.exec(code)
      ?? /^\s*EXPOSE\s+(\d+)\s*$/i.exec(code)
      ?? /^\s*PORT\s*=\s*'(\d+)'\s*$/.exec(code)
      ?? /^\s*internal_port\s*=\s*(\d+)\s*$/.exec(code);
    if (match?.[1] !== undefined) found.push(Number(match[1]));
  }
  return found;
}

/** `process.version` (`v24.13.1`) as a bare `24.13.1`. */
export function runningNodeVersion(processVersion: string): string {
  return processVersion.replace(/^v/, '');
}

/** True when `version` is at least `floor`, comparing major, minor and patch numerically. */
export function atLeast(version: string, floor: string): boolean {
  const parts = (v: string): readonly number[] => {
    const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(v);
    if (m === null) throw new Error(`not an x.y.z version: "${v}"`);
    return [Number(m[1]), Number(m[2]), Number(m[3])];
  };
  const a = parts(version);
  const b = parts(floor);
  for (let i = 0; i < 3; i += 1) {
    const left = a[i] ?? 0;
    const right = b[i] ?? 0;
    if (left !== right) return left > right;
  }
  return true;
}
