#!/usr/bin/env python3
"""
appstore_connect.py -- the two App Store Connect questions CI has to ask, and nothing else.

    next-build-number      the highest CFBundleVersion this app has ever uploaded, plus one
    expire-others <build>  expire every OTHER build, leaving <build> the only one testable

WHY THIS EXISTS AT ALL. `xcrun altool` can upload but cannot answer either question, and both
have bitten already: the repo's committed CURRENT_PROJECT_VERSION is 1 while App Store Connect
holds 3, so an archive built from the repo's own number is rejected as a duplicate -- late,
with a message about the build already existing rather than about anything the developer did.
The number therefore has to come from App Store Connect, which is the only place that knows it.

CREDENTIALS. Read from the environment, never from arguments -- an argument is visible in `ps`
and in CI logs. Required:

    ASC_KEY_ID        the key's 10-character identifier
    ASC_ISSUER_ID     the issuer UUID
    ASC_PRIVATE_KEY   the .p8 contents, PEM including the BEGIN/END lines

Nothing here prints, echoes or persists any of them, and the JWT is held only in memory. If a
call fails, the HTTP status and the API's own error text are printed; the token is not.

DEPENDENCIES. PyJWT and cryptography, both pip-installable on a GitHub macOS runner. Kept out
of the app -- this is release tooling, and ARCHITECTURE's zero-dependency rule is about what
ships, not about what builds it.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "app.cypress.Cypress"


def fail(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def token() -> str:
    try:
        import jwt  # PyJWT
    except ImportError:
        fail("PyJWT is not installed (pip install pyjwt cryptography)", 3)
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    private = os.environ.get("ASC_PRIVATE_KEY")
    missing = [n for n, v in
               (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer),
                ("ASC_PRIVATE_KEY", private)) if not v]
    if missing:
        fail(f"missing environment: {', '.join(missing)}", 3)
    now = int(time.time())
    return jwt.encode(
        # 20 minutes is Apple's ceiling for this audience; we ask for 15.
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, bearer: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {bearer}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:2000]
        fail(f"{method} {url} -> HTTP {error.code}\n{detail}", 4)
    except urllib.error.URLError as error:
        fail(f"{method} {url} -> {error.reason}", 4)
    return {}


def app_id(bearer: str) -> str:
    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID})
    found = call("GET", f"/apps?{query}", bearer).get("data", [])
    if not found:
        fail(f"no app in App Store Connect with bundle id {BUNDLE_ID}", 5)
    return found[0]["id"]


def all_builds(bearer: str, app: str) -> list[dict]:
    """Every build, newest first, following pagination rather than assuming one page."""
    builds: list[dict] = []
    query = urllib.parse.urlencode(
        {"filter[app]": app, "limit": "200", "sort": "-version"})
    url = f"/builds?{query}"
    while url:
        page = call("GET", url, bearer)
        builds.extend(page.get("data", []))
        url = page.get("links", {}).get("next", "")
    return builds


def cmd_next_build_number() -> None:
    bearer = token()
    builds = all_builds(bearer, app_id(bearer))
    # `version` on a build IS CFBundleVersion. Compared numerically, not as a string:
    # sorted as text, "10" precedes "9" and CI would hand back a number already used.
    highest = 0
    for build in builds:
        raw = build.get("attributes", {}).get("version", "")
        try:
            highest = max(highest, int(raw))
        except (TypeError, ValueError):
            # A non-integer build number is not ours to interpret; skip it rather than
            # crash, but say so, because it means this rule needs revisiting.
            print(f"note: ignoring non-integer build number {raw!r}", file=sys.stderr)
    print(highest + 1)


def cmd_expire_others(keep: str) -> None:
    """Expire every build except `keep`, so exactly one is testable (owner's request)."""
    try:
        keep_n = int(keep)
    except ValueError:
        fail(f"build number must be an integer, got {keep!r}", 2)
    bearer = token()
    builds = all_builds(bearer, app_id(bearer))
    if not any(b.get("attributes", {}).get("version") == str(keep_n) for b in builds):
        # Refuse rather than expire everything: an expiry pass that cannot find the build
        # it is protecting would leave the app with no testable build at all.
        fail(f"build {keep_n} is not in App Store Connect yet; refusing to expire "
             "anything, because that would leave no testable build", 6)
    expired = 0
    for build in builds:
        attributes = build.get("attributes", {})
        version = attributes.get("version")
        if version == str(keep_n) or attributes.get("expired"):
            continue
        call("PATCH", f"/builds/{build['id']}", bearer,
             {"data": {"type": "builds", "id": build["id"],
                       "attributes": {"expired": True}}})
        print(f"expired build {version}")
        expired += 1
    print(f"kept build {keep_n}; expired {expired} other(s)")


def main() -> None:
    if len(sys.argv) < 2:
        fail(__doc__.strip().splitlines()[2], 2)
    command = sys.argv[1]
    if command == "next-build-number":
        cmd_next_build_number()
    elif command == "expire-others":
        if len(sys.argv) != 3:
            fail("usage: appstore_connect.py expire-others <build-number>", 2)
        cmd_expire_others(sys.argv[2])
    else:
        fail(f"unknown command {command!r}", 2)


if __name__ == "__main__":
    main()
