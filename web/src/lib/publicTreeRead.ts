/**
 * The community half of a tree, read from `GET /api/v1/public/trees/{id}`.
 *
 * W1's fact column is about half contributed data and W-C shipped the city half alone, because
 * when it was written there was no public read for the other half. There is one now — PR #163,
 * milestone W-G, whose contract is `docs/rulings-pending/public-tree-read.md` — and this module is
 * the page's side of it.
 *
 * ── What the endpoint actually returns, read out of the Go rather than remembered ────────────
 *
 * Six keys, all present, an absent value spelled `null` rather than omitted
 * (`server/internal/api/public.go`, and `TestTheBodyCarriesTheseSixKeysAndNoOthers` pins the set):
 *
 *     tree_uuid           the caller's own path parameter, echoed
 *     verification_state  fixed at `unverified` — PRODUCT's non-goal, machine-readable
 *     beloved             R27.1's state: ≥3 distinct account-backed favorite owners
 *     beloved_by          the number behind it, **only above the floor**; null below
 *     height              {value, unit_entered, method, measured_month} or null
 *     trunk_dbh           the same shape or null
 *
 * There is **no vitality rating** and there is no slot for one: §W1's `Status · Thriving ·
 * vitality 4` was removed from the response before it merged, because a published rating has no
 * takedown route (the ruling's §8). So this module cannot fill that row and does not pretend to.
 *
 * The server does **not** convert units: the number arrives as it was typed, in the unit it was
 * typed in, and the method travels with it because D7 makes a quantity without a method
 * unrepresentable. `src/lib/quantity.ts` is the ported `Quantity` and this decodes into it.
 *
 * ── The base URL comes from the environment and there is NO default host ─────────────────────
 *
 * `packLibrary.ts` states the discipline for `CYPRESS_PACK_DIR` and it is the same one here: *a
 * default would make "not configured" look exactly like "configured and answering nothing"*, and
 * those are a deployment that did not finish and a tree nobody has measured. The iOS app carries
 * `https://cypress-sync.fly.dev/api/v1` as a literal default (`AuthClient.defaultBaseURL`); this
 * deliberately does not copy it.
 *
 * ── Reachability is the normal case for failure, not an edge case ────────────────────────────
 *
 * **Measured on 2026-09-11, not assumed:** `https://cypress-sync.fly.dev/health` answers 200 while
 * `GET /api/v1/public/trees/<uuid>` answers Go's bare `404 page not found` — where a route that IS
 * registered but takes another verb answers `405` (`/api/v1/sync` and `/api/v1/devices/register`
 * both do). The route is not on the running build: merging #163 did not redeploy `cypress-sync`.
 *
 * So the unavailable path is the path this ships on, and the page has to be correct there. Every
 * failure below — unset variable, junk variable, DNS, connection refused, timeout, a non-200, a
 * body this build cannot read — lands on a named state, and the page renders the city record. A
 * network dependency that turns a working page into a 500 would be a regression, and there is no
 * `throw` anywhere in this file's request path.
 */
import {
  lengthUnits,
  makeQuantity,
  measurementMethods,
  type LengthUnit,
  type MeasurementMethod,
  type Quantity,
} from './quantity.ts';

/** The environment variable naming the API this page reads the community half from. */
export const PUBLIC_API_VARIABLE = 'CYPRESS_PUBLIC_API_BASE';

/**
 * How long one page render will wait for the community half, in milliseconds.
 *
 * The ruling does not set it, so this file does, and the number is argued from what the value is
 * worth: the community half is an addition to a page whose spine renders without it, so its budget
 * has to be small enough that a reader never waits for it. 1500 ms is generous for a call the
 * ruling sizes at "indexed reads, no writes, bounded output" on a machine in one region, and short
 * enough that a hung upstream costs a page a second and a half rather than a gateway timeout.
 *
 * There is **one attempt and no retry.** A retry on a public page multiplies crawler traffic
 * against the single shared-cpu-1x machine the ruling's §11 sizes its limiter for, and it doubles
 * the wait in exactly the case where the wait is already the problem.
 */
export const PUBLIC_READ_TIMEOUT_MS = 1500;

/**
 * The maximum a renderer of this page may let a contributed value survive downstream, in seconds.
 *
 * Not chosen here. It is the ruling's §8b — *"The round that renders the page may not cache beyond
 * this"* — and the number is the `max-age` the endpoint itself sends
 * (`publicCacheControl = "public, max-age=60"` in `server/internal/api/public.go`). It is the
 * ceiling on how long a withdrawn reading can still be on a page after its contributor took it
 * back, so the page sends it too.
 */
export const PUBLIC_PAGE_MAX_AGE_S = 60;

// ── The body ────────────────────────────────────────────────────────────────────────────────

/** One reading: §W1's `18 m` `est.` and `64 cm` `taped`, as the endpoint spells them. */
export interface PublicReading {
  /** The value with its entered unit and its method, D7's three-in-one. */
  readonly quantity: Quantity;
  /** `2026-08`. Month precision is the ruling's §4 and the day deliberately does not travel. */
  readonly measuredMonth: string;
}

/** The whole community half of one tree. */
export interface PublicTreeRead {
  /** Lowercased. The endpoint echoes the caller's path parameter; this is what came back. */
  readonly treeUUID: string;
  /** Fixed at `unverified` today. A value this build does not know refuses the whole body. */
  readonly verificationState: string;
  readonly beloved: boolean;
  /** Present only above R27.1's k-anonymity floor. Null below it, and never a zero. */
  readonly belovedBy: number | null;
  readonly height: PublicReading | null;
  readonly trunkDBH: PublicReading | null;
}

/**
 * What this render knows about the community half, as five distinguishable states.
 *
 * They are five rather than one nullable value because they are five different things and only one
 * of them is about the tree:
 *
 * - `notRequested` — this render did not ask. The default, and the honest state of a caller that
 *   renders the city record alone (the OpenGraph card does).
 * - `unconfigured` — `CYPRESS_PUBLIC_API_BASE` is unset or unusable. An operator's problem.
 * - `unavailable` — it was asked and there is no usable answer: refused, timed out, non-200, or a
 *   body this build cannot read. `detail` says which, in the process log.
 * - `empty` — it answered, and this tree has nothing publishable. **A fact about the tree**, and
 *   the only one of the three silences that is.
 * - `answered` — it answered with something.
 *
 * `empty` and `unavailable` are the pair that must never be collapsed: one says "nobody has
 * measured this tree", the other says "this page cannot say", and a page that drew them the same
 * way would assert the first every time the second was true.
 */
export type CommunityHalf =
  | { readonly state: 'notRequested' }
  | { readonly state: 'unconfigured'; readonly detail: string }
  | { readonly state: 'unavailable'; readonly detail: string }
  | { readonly state: 'empty' }
  | { readonly state: 'answered'; readonly read: PublicTreeRead };

/** The default: a render that did not ask draws exactly what W-C drew. */
export const COMMUNITY_NOT_REQUESTED: CommunityHalf = { state: 'notRequested' };

// ── Configuration ───────────────────────────────────────────────────────────────────────────

/** A base URL that is usable, or the reason it is not. Never a default host. */
export type PublicAPIBase =
  | { readonly ok: true; readonly base: string }
  | { readonly ok: false; readonly detail: string };

/**
 * The API base from the environment.
 *
 * The value is the API root including its version prefix — `https://cypress-sync.fly.dev/api/v1` —
 * because that is the string the rest of this system already says out loud
 * (`AuthClient.defaultBaseURL`, `server/internal/api`'s own `Prefix`), and a variable that named
 * the host alone would make the version a second place to be wrong.
 *
 * **A malformed value is reported, not defaulted and not thrown.** `openPackLibrary` throws when
 * `CYPRESS_PACK_DIR` names a directory that is not there, and that is right for the pack, which is
 * the page's spine. This is not the spine: a typo in this variable must not take down a page the
 * pack can render completely, so it lands on `unconfigured` with the reason and the page says it
 * cannot speak for the community half.
 */
export function publicAPIBase(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): PublicAPIBase {
  const configured = environment[PUBLIC_API_VARIABLE];
  if (configured === undefined || configured.trim().length === 0) {
    return {
      ok: false,
      detail: `${PUBLIC_API_VARIABLE} is not set, so this server reads no community half`,
    };
  }
  const trimmed = configured.trim();
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { ok: false, detail: `${PUBLIC_API_VARIABLE} is not a URL: ${trimmed}` };
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return {
      ok: false,
      detail: `${PUBLIC_API_VARIABLE} is ${parsed.protocol.replace(':', '')}, not http or https`,
    };
  }
  return { ok: true, base: trimmed.replace(/\/+$/, '') };
}

/** `<base>/public/trees/<uuid>` — the route `server/internal/api/server.go` registers. */
export function publicTreeURL(base: string, uuid: string): string {
  return `${base.replace(/\/+$/, '')}/public/trees/${encodeURIComponent(uuid.toLowerCase())}`;
}

// ── Decoding ────────────────────────────────────────────────────────────────────────────────

/** `2026-08`, and nothing looser. The ruling's §4 publishes a month and never a day. */
const MEASURED_MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

/**
 * The one `verification_state` this build knows how to draw.
 *
 * Fixed in the response today and shipped as a field so the page cannot render community numbers
 * as the city's by omission (PRODUCT's non-goals: *"Community layer is visually distinct and never
 * displays as official until verified"*). When a verification tier ships, this build will be one
 * that does not know how to mark a verified value — so it refuses the body rather than drawing a
 * verified reading as an unverified one, which is `statusLabel`'s rule for an unknown status.
 */
const KNOWN_VERIFICATION_STATE = 'unverified';

function isObject(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

/**
 * One reading, or null.
 *
 * **Null drops the reading and keeps the rest of the body**, which is the server's own behavior:
 * `publicReadingFrom` returns nil for a value that will not parse and for a method or unit outside
 * the Swift vocabulary, and the response then carries `null` for that field. A reading this build
 * cannot draw honestly — no badge for an unknown method, no length for an unknown unit — is not
 * drawn, and nothing else on the page is lost to it.
 */
export function decodeReading(raw: unknown): PublicReading | null {
  if (!isObject(raw)) return null;
  const value = raw['value'];
  const unit = raw['unit_entered'];
  const method = raw['method'];
  const month = raw['measured_month'];
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  if (typeof unit !== 'string' || !(lengthUnits as readonly string[]).includes(unit)) return null;
  if (typeof method !== 'string' || !(measurementMethods as readonly string[]).includes(method)) {
    return null;
  }
  if (typeof month !== 'string' || !MEASURED_MONTH.test(month)) return null;
  return {
    quantity: makeQuantity(value, unit as LengthUnit, method as MeasurementMethod),
    measuredMonth: month,
  };
}

/** Why a body was refused, or null when it decoded. */
export type DecodeOutcome =
  | { readonly ok: true; readonly read: PublicTreeRead }
  | { readonly ok: false; readonly detail: string };

/**
 * The body, decoded against the contract rather than against a memory of it.
 *
 * Every key the handler emits is **required to be present**, because the handler emits all six on
 * every answer and `TestTheBodyCarriesTheseSixKeysAndNoOthers` holds it there: a body missing one
 * is not this contract, and guessing at the missing half is how a page starts publishing a shape
 * nobody agreed to. Unknown extra keys are ignored rather than refused — the Go test forbids a
 * seventh, so one arriving means this build is older than the service, and the five keys it does
 * understand are still true.
 *
 * **Two of the six entries below are the only thing catching their own absence, and the other four
 * are belt to a brace.** Measured by removing each in turn: without `height` or `trunk_dbh` on the
 * list a body missing that key decodes as a body with no reading — the silent shape, where "the
 * service did not send it" becomes "nobody has measured this tree". The other four fall to a type
 * check a line or two below whatever this list does. The list stays whole because the rule it
 * states is "all six or this is not the contract", and a list that named only the two load-bearing
 * ones would read as though the other four were optional.
 *
 * ── The beloved pair is checked against each other, and that IS the k-anonymity property ─────
 *
 * `beloved` is true exactly when `beloved_by` carries a number, because the handler copies the
 * count **inside** the `if (body.Beloved)` branch and discards it below the floor. A body where
 * they disagree is a service whose floor is not doing what this page believes it does, so the
 * beloved half is dropped and the readings are kept. Rendering `beloved` with no number would be
 * this page inventing the state's evidence; rendering a number with `beloved` false would publish
 * a count below a k-anonymity floor, which is the single disclosure the floor exists to prevent.
 */
export function decodePublicTreeRead(raw: unknown, requestedUUID: string): DecodeOutcome {
  if (!isObject(raw)) {
    return { ok: false, detail: `the body is ${raw === null ? 'null' : typeof raw}, not an object` };
  }
  for (const key of [
    'tree_uuid', 'verification_state', 'beloved', 'beloved_by', 'height', 'trunk_dbh',
  ]) {
    if (!Object.hasOwn(raw, key)) return { ok: false, detail: `the body has no \`${key}\` key` };
  }
  const treeUUID = raw['tree_uuid'];
  if (typeof treeUUID !== 'string') {
    return { ok: false, detail: '`tree_uuid` is not a string' };
  }
  // The endpoint echoes the caller's own path parameter, so this confirms nothing about the tree —
  // what it catches is a response that belongs to a different request: a proxy serving a cached
  // body for another URL, or a base URL pointing at something that is not this service.
  if (treeUUID.toLowerCase() !== requestedUUID.toLowerCase()) {
    return {
      ok: false,
      detail: `the answer is about ${treeUUID}, and ${requestedUUID} was asked about`,
    };
  }
  const verificationState = raw['verification_state'];
  if (verificationState !== KNOWN_VERIFICATION_STATE) {
    return {
      ok: false,
      detail: `\`verification_state\` is ${JSON.stringify(verificationState)}; this build knows `
        + `only ${JSON.stringify(KNOWN_VERIFICATION_STATE)} and will not draw a state it cannot `
        + `mark`,
    };
  }
  const belovedRaw = raw['beloved'];
  if (typeof belovedRaw !== 'boolean') return { ok: false, detail: '`beloved` is not a boolean' };
  const belovedByRaw = raw['beloved_by'];
  if (belovedByRaw !== null && !Number.isInteger(belovedByRaw)) {
    return { ok: false, detail: '`beloved_by` is neither null nor a whole number' };
  }
  const agrees = belovedRaw === (belovedByRaw !== null);
  const beloved = agrees ? belovedRaw : false;
  const belovedBy = agrees ? (belovedByRaw as number | null) : null;
  return {
    ok: true,
    read: {
      treeUUID: treeUUID.toLowerCase(),
      verificationState,
      beloved,
      belovedBy,
      height: decodeReading(raw['height']),
      trunkDBH: decodeReading(raw['trunk_dbh']),
    },
  };
}

/** Whether a decoded body says anything at all. `false` is the `empty` state. */
export function saysAnything(read: PublicTreeRead): boolean {
  return read.beloved || read.height !== null || read.trunkDBH !== null;
}

// ── The request ─────────────────────────────────────────────────────────────────────────────

/** Injected by the suite so the three states are driven by a real server, not by a spy. */
export interface CommunityHalfOptions {
  readonly environment?: Readonly<Record<string, string | undefined>>;
  readonly timeoutMs?: number;
  readonly fetch?: typeof globalThis.fetch;
}

/**
 * One request for one tree, which never throws and never rejects.
 *
 * `fetch` from the standard library — `web/` has held zero extra runtime dependencies since W-A
 * and this round does not spend that.
 */
export async function communityHalf(
  uuid: string,
  options: CommunityHalfOptions = {},
): Promise<CommunityHalf> {
  const base = publicAPIBase(options.environment ?? process.env);
  if (!base.ok) return { state: 'unconfigured', detail: base.detail };

  const url = publicTreeURL(base.base, uuid);
  const request = options.fetch ?? globalThis.fetch;
  const timeoutMs = options.timeoutMs ?? PUBLIC_READ_TIMEOUT_MS;
  let response: Response;
  try {
    response = await request(url, {
      // No credentials, no cookies: this is the one unauthenticated read the service answers, and
      // a page that sent anything would be sending it to a host named by an environment variable.
      headers: { accept: 'application/json' },
      redirect: 'follow',
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const reason = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    return { state: 'unavailable', detail: `${url} did not answer — ${reason}` };
  }
  if (!response.ok) {
    return { state: 'unavailable', detail: `${url} answered ${String(response.status)}` };
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    return { state: 'unavailable', detail: `${url} answered unreadable JSON — ${reason}` };
  }
  const decoded = decodePublicTreeRead(body, uuid);
  if (!decoded.ok) return { state: 'unavailable', detail: `${url}: ${decoded.detail}` };
  return saysAnything(decoded.read)
    ? { state: 'answered', read: decoded.read }
    : { state: 'empty' };
}
