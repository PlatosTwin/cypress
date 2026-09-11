# The public web surface (W-A, docs/design-proposals/2026-09-10-web-version.md).
#
# Node is pinned to an exact patch in BOTH stages, and `web/test/toolchain.test.ts` fails if
# either one drifts from `package.json` engines.node or from `.nvmrc`. The pin is not caution
# for its own sake: the read path this app is being built for is `node:sqlite`, which ships in
# the standard library and is documented as experimental and free to change. A floating tag is a
# runtime that can change under the one API the whole design rests on.
#
# `-slim` rather than `-alpine`: Astro's build reaches for prebuilt native binaries (esbuild,
# rollup) that are published for glibc and, on musl, either fall back to a slower path or need a
# toolchain in the image to build. Debian slim costs about 60 MB over alpine and removes the
# whole question. `scratch` — what `server/Dockerfile` uses — is not available here at all: this
# is an interpreted runtime, the interpreter has to be in the image.
FROM node:24.13.1-slim AS build
WORKDIR /app

# The manifest pair first, so editing a page does not re-resolve the dependency graph.
#
# `npm ci`, never `npm install`: it installs the lockfile exactly and fails if the lockfile and
# package.json disagree, which is the property that makes the image reproducible and makes the
# lockfile worth committing.
COPY package.json package-lock.json ./
RUN npm ci

# Everything else the build reads. Copied as a directory list rather than `COPY . .` for
# `server/Dockerfile`'s reason inverted: there the allowlist rotted and a missing package broke
# the build loudly; here the risk is the opposite one, a `.env` or a stray log being baked into
# a public image. `.dockerignore` beside this file is the second half of that.
COPY astro.config.mjs tsconfig.json ./
COPY src ./src

RUN npm run build

# `npm prune --omit=dev` rather than a second `npm ci --omit=dev` in the runtime stage: the tree
# is already resolved and on disk, and pruning it cannot pick a different version than the one
# just built against.
RUN npm prune --omit=dev

FROM node:24.13.1-slim
ENV NODE_ENV=production
# Read at runtime by the standalone entry that `@astrojs/node` emits. `0.0.0.0` and not the
# default localhost: a server bound to the loopback inside a container answers nothing from
# outside it, and the symptom is a health check that times out with the process plainly running.
# `fly.toml`'s `internal_port` states the same 8080 and must move with it.
ENV HOST=0.0.0.0
ENV PORT=8080
WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json

# The `node` user exists in the official image. v1 is a read surface with no writes and no
# credentials, so this buys little today; it costs nothing and it is the wrong thing to add
# later, under pressure, on the day the app first opens a volume.
USER node

EXPOSE 8080
CMD ["node", "./dist/server/entry.mjs"]
