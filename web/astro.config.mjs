// @ts-check
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

// SSR, self-hosted, Node adapter (W-4 / W-8, docs/design-proposals/2026-09-10-web-version.md).
//
// `output: 'server'` rather than static, and it is not a preference: W-C renders a tree page from
// a published city pack opened through `node:sqlite` on the machine, and there is no build-time
// list of a million URLs to prerender. `mode: 'standalone'` makes the build emit its own HTTP
// server (`dist/server/entry.mjs`) instead of a middleware handler, which is what the Dockerfile
// runs and what Fly's health check talks to.
//
// The host and port are read from HOST/PORT at RUNTIME by the standalone entry, not from here.
// They are set in the Dockerfile and in fly.toml so that one value governs the container, the
// health check and the process.
export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
});
