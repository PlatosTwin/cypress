import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { PACK_DIRECTORY_VARIABLE } from '../src/lib/packLibrary.ts';
import {
  atLeast,
  declaredPorts,
  dockerfileNodeVersions,
  engineFloor,
  engineRange,
  flyTomlStrings,
  nvmrcVersion,
  runningNodeVersion,
} from '../src/lib/toolchain.ts';

const webRoot = new URL('../', import.meta.url);
const read = (name: string): string =>
  readFileSync(fileURLToPath(new URL(name, webRoot)), 'utf8');

describe('the version parsers', () => {
  // Specimens first, with answers known before the parser saw them. A parser asserted only
  // against the real files is a parser that agrees with whatever the files happen to say.
  it('reads an engines range and its floor', () => {
    const pkg = '{"engines":{"node":">=24.13.1 <25"}}';
    assert.equal(engineRange(pkg), '>=24.13.1 <25');
    assert.equal(engineFloor(pkg), '24.13.1');
  });

  it('refuses an engines range that pins no exact floor', () => {
    assert.throws(() => engineFloor('{"engines":{"node":"^24"}}'), /pins no exact version/);
  });

  it('refuses a package.json with no engines.node at all', () => {
    assert.throws(() => engineRange('{}'), /pins the runtime/);
  });

  it('reads .nvmrc with or without a leading v, and refuses a range', () => {
    assert.equal(nvmrcVersion('24.13.1\n'), '24.13.1');
    assert.equal(nvmrcVersion('v24.13.1'), '24.13.1');
    assert.throws(() => nvmrcVersion('lts/*'), /not an exact/);
  });

  it('finds every FROM node: version in a multi-stage file, in order', () => {
    const specimen = [
      '# a comment mentioning FROM node:99.99.99 that is not a directive',
      'FROM node:24.13.1-slim AS build',
      'RUN npm ci',
      'FROM node:24.13.2-slim',
    ].join('\n');
    assert.deepEqual(dockerfileNodeVersions(specimen), ['24.13.1', '24.13.2']);
  });

  it('finds nothing in a Dockerfile that is not on Node', () => {
    // `1.25.0`, not `1.25`, and the three digits are the whole point of the specimen. With
    // `1.25` this test passed against a deliberately broken matcher that accepted ANY image
    // name — it was rejecting the line for having a two-part version, not for being golang, so
    // it was green while the defect it names was present. Caught by red-proving it; the
    // specimen now differs from a Node line in exactly one thing, the image name.
    assert.deepEqual(dockerfileNodeVersions('FROM golang:1.25.0-alpine AS build'), []);
  });

  it('compares versions by number, not by string', () => {
    // The case a lexical compare gets wrong, which is the only case worth asserting.
    assert.equal(atLeast('24.9.0', '24.13.1'), false);
    assert.equal(atLeast('24.13.1', '24.9.0'), true);
    assert.equal(atLeast('24.13.1', '24.13.1'), true);
    assert.equal(atLeast('25.0.0', '24.13.1'), true);
  });
});

describe('this checkout pins one Node version everywhere', () => {
  const pkg = read('package.json');
  const floor = engineFloor(pkg);

  it('.nvmrc agrees with engines.node', () => {
    assert.equal(
      nvmrcVersion(read('.nvmrc')),
      floor,
      'web/.nvmrc and web/package.json engines.node name different Node versions, so CI and npm ' +
        'disagree about the runtime',
    );
  });

  it('every Dockerfile stage agrees with engines.node', () => {
    const versions = dockerfileNodeVersions(read('Dockerfile'));
    // The control. An empty list would make the loop below assert nothing at all, which is this
    // repository's dominant test-suite defect class.
    assert.ok(
      versions.length >= 2,
      `web/Dockerfile names ${versions.length} Node version(s); a multi-stage build has at least ` +
        'two, so this check is reading the wrong file or the wrong pattern',
    );
    for (const version of versions) {
      assert.equal(
        version,
        floor,
        `web/Dockerfile builds on Node ${version} but package.json pins ${floor} — the image is ` +
          'not the runtime CI certified',
      );
    }
  });

  it('the Node running this suite satisfies the floor', () => {
    const running = runningNodeVersion(process.version);
    assert.ok(
      atLeast(running, floor),
      `this suite is running on Node ${running}, below the pinned ${floor}`,
    );
  });

  it('every declared port agrees, across all four directives', () => {
    // Specimens first, with the answers known before the parser saw them — including the two
    // traps that made this worth writing: a comment naming the port, and a directive whose value
    // differs from the rest.
    assert.deepEqual(
      declaredPorts(
        [
          '# fly.toml states the same 8080 and must move with it',
          'ENV PORT=8080',
          'EXPOSE 8080',
          "  PORT = '8080'",
          '  internal_port = 8080',
          'ENV OTHER=9999',
        ].join('\n'),
      ),
      [8080, 8080, 8080, 8080],
    );

    const ports = [...declaredPorts(read('Dockerfile')), ...declaredPorts(read('fly.toml'))];
    // The control. `fly.toml`'s comment said the port appears THREE times in this repository;
    // it appears four, and it said so while promising a guard that was never written. A floor of
    // four is the finding, pinned.
    assert.equal(
      ports.length,
      4,
      `web/Dockerfile and web/fly.toml declare ${ports.length} port(s) between them (${ports.join(', ')}); `
        + 'this check expects the four directives ENV PORT, EXPOSE, PORT and internal_port. A fifth '
        + 'copy of the port needs adding here; a missing one means this is reading the wrong file '
        + 'or the wrong pattern, and is asserting nothing.',
    );
    for (const port of ports) {
      assert.equal(
        port,
        ports[0],
        `the declared ports disagree (${ports.join(', ')}) — the container listens on one and Fly's `
          + 'health check talks to another, which fails as a deploy that never becomes healthy '
          + 'rather than as anything that looks like a port problem.',
      );
    }
  });
});

describe('where the packs are, which fly.toml says twice', () => {
  // The same class of guard as the port check above, one table over: `[env] CYPRESS_PACK_DIR` is
  // what the process reads and `[mounts] destination` is where Fly attaches the volume, and the
  // two disagreeing is a machine that boots, passes its health check, mounts its volume, and
  // answers nothing.

  it('reads a table, and does not read the tables beside it', () => {
    // Specimen first, answers known before the parser saw it, carrying every trap that would make
    // a plausible parser wrong about the real file: a decoy in a comment before any table, a
    // trailing comment on the entry that matters, the SAME key set in another table, a
    // `[[double]]` header between the two tables that matter, and an unquoted value.
    const specimen = [
      "# CYPRESS_PACK_DIR = '/decoy-in-a-comment'",
      "app = 'cypress-web'",
      '[env]',
      "  HOST = '0.0.0.0'",
      "  CYPRESS_PACK_DIR = '/data/packs'   # and a comment after the entry",
      '[http_service]',
      '  internal_port = 8080',
      "  destination = '/not-the-mount'",
      '[[http_service.checks]]',
      "  path = '/health'",
      '[mounts]',
      "  source = 'cypress_packs'",
      "  destination = '/data/packs'",
    ].join('\n');

    assert.equal(flyTomlStrings(specimen, 'env').get('CYPRESS_PACK_DIR'), '/data/packs');
    assert.equal(flyTomlStrings(specimen, 'env').get('HOST'), '0.0.0.0');
    assert.equal(flyTomlStrings(specimen, 'mounts').get('destination'), '/data/packs');
    assert.equal(flyTomlStrings(specimen, 'mounts').get('source'), 'cypress_packs');
    // The trap a grep would fall into: the same key, a different table, a different answer.
    assert.equal(flyTomlStrings(specimen, 'http_service').get('destination'), '/not-the-mount');
    // The `[[double]]` header opens a table of its own rather than running into `[mounts]`.
    assert.equal(flyTomlStrings(specimen, 'http_service.checks').get('path'), '/health');
    assert.equal(flyTomlStrings(specimen, 'http_service.checks').has('source'), false);
    // An unquoted value is not a string, and a key before any table belongs to no table.
    assert.equal(flyTomlStrings(specimen, 'http_service').has('internal_port'), false);
    assert.equal(flyTomlStrings(specimen, 'env').has('app'), false);
    // And a table nobody wrote is empty rather than an error.
    assert.equal(flyTomlStrings(specimen, 'nothing').size, 0);
  });

  it('refuses a key set twice in one table rather than picking one', () => {
    assert.throws(
      () => flyTomlStrings(["[env]", "  A = 'x'", "  A = 'y'"].join('\n'), 'env'),
      /more than once/,
    );
  });

  it('the mount destination and CYPRESS_PACK_DIR are the same path', () => {
    const fly = read('fly.toml');
    const environment = flyTomlStrings(fly, 'env');
    const mounts = flyTomlStrings(fly, 'mounts');
    const packDirectory = environment.get(PACK_DIRECTORY_VARIABLE);
    const destination = mounts.get('destination');

    // The controls, all three, because every one of them is a way for the assertion below to pass
    // while asserting nothing. `PACK_DIRECTORY_VARIABLE` comes from `src/lib/packLibrary.ts`
    // rather than being spelled again here, so renaming the variable in the code goes red in this
    // file instead of shipping a deployment that sets a name nothing reads.
    assert.ok(
      packDirectory !== undefined,
      `web/fly.toml [env] sets no ${PACK_DIRECTORY_VARIABLE}, so the deployed process is handed no `
        + 'pack directory at all — or this is reading the wrong table and asserting nothing.',
    );
    assert.ok(
      destination !== undefined,
      'web/fly.toml declares no [mounts] destination, so no volume is attached — or this is '
        + 'reading the wrong table and asserting nothing.',
    );
    assert.ok(
      mounts.get('source') !== undefined,
      'web/fly.toml [mounts] names no source volume',
    );

    assert.equal(
      packDirectory,
      destination,
      `web/fly.toml mounts the volume at ${String(destination)} and tells the process the packs `
        + `are at ${String(packDirectory)}. Nothing at runtime notices: the volume attaches, the `
        + 'machine passes its health check, and every tree URL 404s or 500s with the data sitting '
        + 'on disk a directory away.',
    );
  });
});
