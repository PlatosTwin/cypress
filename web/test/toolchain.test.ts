import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  atLeast,
  dockerfileNodeVersions,
  engineFloor,
  engineRange,
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
    assert.deepEqual(dockerfileNodeVersions('FROM golang:1.25-alpine AS build'), []);
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
});
