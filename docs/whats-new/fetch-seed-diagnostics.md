# Reviewers: Tools/fetch_seed.sh runs in every CI job and places the seed the app bundles, so it
# is a build input and this change mints a build. The pinned seed bytes do not change; they are
# verified by sha256. Only the script that fetches and places them changed.
internal: the seed fetch script now names the reason for every failure instead of stopping silently; no app code changed.
