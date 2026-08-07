#!/usr/bin/env python3
"""
appstore_connect.py -- the App Store Connect questions CI has to ask, and nothing else.

    next-build-number      the highest CFBundleVersion this app has ever uploaded, plus one
    expire-others <build>  expire every OTHER build, leaving <build> the only one testable
    status                 print every build's real state, which the web UI summarizes lossily
    feedback               every word a tester or customer has sent about this app

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

# `X | None` annotations are 3.10 syntax and this file already used them, which made it
# unimportable on the 3.9 that ships with macOS -- so the parsing could only ever be exercised on
# a runner, against live credentials. Deferring annotations costs nothing at runtime and makes
# the module loadable anywhere, which is what lets `feedback` be tested against fixtures.
from __future__ import annotations

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


def request_json(method: str, path: str, bearer: str, body: dict | None = None) -> dict:
    """One call. Raises urllib's own errors; `call` turns those into an exit, `try_call` into a
    note. The token goes in the header and is never included in any message raised from here."""
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {bearer}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


def call(method: str, path: str, bearer: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API}{path}"
    try:
        return request_json(method, path, bearer, body)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:2000]
        fail(f"{method} {url} -> HTTP {error.code}\n{detail}", 4)
    except urllib.error.URLError as error:
        fail(f"{method} {url} -> {error.reason}", 4)
    return {}


def try_call(method: str, path: str, bearer: str) -> tuple[dict | None, str]:
    """`call` that reports instead of exiting.

    `feedback` reads four unrelated corners of the API and one of them can be forbidden while the
    rest are readable — an API key with a limited role, or an app that has never been on the store.
    Losing the crash submissions because the reviews 403'd would be the worst possible outcome for
    a triage run, so each section records why it is empty and the run continues.
    """
    url = path if path.startswith("http") else f"{API}{path}"
    try:
        return request_json(method, path, bearer), ""
    except urllib.error.HTTPError as error:
        try:
            detail = error.read().decode(errors="replace")[:600].replace("\n", " ")
        except Exception:  # a 429 can arrive with no readable body; the status is the news
            detail = "(no body)"
        return None, f"HTTP {error.code} from {url}: {detail}"
    except urllib.error.URLError as error:
        return None, f"{url} unreachable: {error.reason}"


def paged(bearer: str, path: str, note: list[str]) -> tuple[list[dict], dict[str, dict]]:
    """Every page of a collection, following `links.next` rather than assuming one page.

    Returns the resources and an id -> resource map of everything `include=` sidecarred, since the
    API returns those in a sibling array rather than inline.

    A partial read is worse than a failed one here: 12 of 40 crash reports looks exactly like 12
    crash reports. A page that fails mid-collection appends to `note` and stops, so the caller can
    say the list is incomplete instead of publishing it as the whole truth.
    """
    items: list[dict] = []
    included: dict[str, dict] = {}
    url = path
    while url:
        page, error = try_call("GET", url, bearer)
        if page is None:
            note.append(f"list truncated after {len(items)} item(s): {error}")
            break
        items.extend(page.get("data", []))
        for side in page.get("included", []):
            included[side.get("id", "")] = side
        url = page.get("links", {}).get("next", "")
    return items, included


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


def cmd_status() -> None:
    """Print what App Store Connect actually holds, field by field.

    The TestFlight web UI collapses several independent states into one word per build, and the
    word it picks is not always the one that matters: "Ready to Submit" is the EXTERNAL testing
    state, and says nothing about whether internal testers can install the build. Nothing here
    interprets — it prints the API's own values so a question about a build's status can be
    answered from data instead of from a screenshot.
    """
    bearer = token()
    app = app_id(bearer)
    builds = all_builds(bearer, app)
    if not builds:
        print("no builds at all for", BUNDLE_ID)
        return
    print(f"{BUNDLE_ID}: {len(builds)} build(s), newest first\n")
    for build in builds:
        attributes = build.get("attributes", {})
        print(f"build {attributes.get('version')}  (id {build['id']})")
        print(f"  uploaded         {attributes.get('uploadedDate')}")
        print(f"  processingState  {attributes.get('processingState')}")
        print(f"  expired          {attributes.get('expired')}")
        print(f"  expirationDate   {attributes.get('expirationDate')}")
        print(f"  minOsVersion     {attributes.get('minOsVersion')}")
        print(f"  usesNonExemptEncryption {attributes.get('usesNonExemptEncryption')}")
        detail = call("GET", f"/builds/{build['id']}/buildBetaDetail", bearer).get("data")
        if detail:
            beta = detail.get("attributes", {})
            # The two states the UI merges into one column. INTERNAL is the one that decides
            # whether the five testers can install anything.
            print(f"  internalBuildState  {beta.get('internalBuildState')}")
            print(f"  externalBuildState  {beta.get('externalBuildState')}")
            print(f"  autoNotifyEnabled   {beta.get('autoNotifyEnabled')}")
        else:
            print("  buildBetaDetail  (none)")
        # Asked of /betaGroups filtered BY the build, not of /builds/<id>/betaGroups: that
        # relationship allows only CREATE and DELETE, and a GET on it is a 403 FORBIDDEN_ERROR.
        groups = call(
            "GET",
            f"/betaGroups?{urllib.parse.urlencode({'filter[builds]': build['id'], 'limit': '200'})}",
            bearer,
        ).get("data", [])
        if groups:
            for group in groups:
                g = group.get("attributes", {})
                print(f"  group            {g.get('name')!r} "
                      f"internal={g.get('isInternalGroup')} "
                      f"publicLink={bool(g.get('publicLinkEnabled'))} "
                      f"(id {group['id']})")
        else:
            print("  group            NONE -- no tester group holds this build")
        print()
    # Listed separately because a group with no build is invisible above, and an empty group is
    # exactly what a build stuck outside internal testing looks like from the other side.
    print("beta groups on this app:")
    for group in call("GET", f"/betaGroups?filter[app]={app}&limit=200", bearer).get("data", []):
        g = group.get("attributes", {})
        print(f"  {g.get('name')!r} internal={g.get('isInternalGroup')} "
              f"hasAccessToAllBuilds={g.get('hasAccessToAllBuilds')} "
              f"publicLinkEnabled={g.get('publicLinkEnabled')} (id {group['id']})")


# --------------------------------------------------------------------------------------------
# feedback
#
# WHAT THIS READS, and where the shapes came from. Every path, query parameter and attribute name
# below was taken from Apple's own documentation data (the JSON behind developer.apple.com) on
# 2026-08-07, not from memory:
#
#   GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions   what a tester wrote, plus their shot
#   GET /v1/apps/{id}/betaFeedbackCrashSubmissions        what a tester was doing when it crashed
#   GET /v1/betaFeedbackCrashSubmissions/{id}/crashLog    the log text for one of those
#   GET /v1/apps/{id}/customerReviews                     the public store reviews, if any
#   GET /v1/apps/{id}/appStoreVersions                    only to say whether reviews CAN exist
#
# Both feedback collections take include=build,tester, sort=-createdDate, limit<=200, and carry
# the same device attributes; the screenshot one adds `screenshots`, an array of pre-signed URLs
# with their own expirationDate.
#
# EMAIL IS DELIBERATELY DROPPED. Both submission resources carry the tester's `email`. This
# command never reads it into its output: the JSON is uploaded as a CI artifact that anyone with
# repo access can download for months, and a tester's address is not a fact triage needs. The
# opaque tester relationship id is kept instead, which is enough to tell two testers apart and
# to tie several reports to one person.
# --------------------------------------------------------------------------------------------

# The device fields both submission types share, in the order a human wants to read them.
SUBMISSION_ATTRIBUTES = (
    "createdDate", "comment", "deviceModel", "osVersion", "deviceFamily", "devicePlatform",
    "appPlatform", "architecture", "locale", "timeZone", "connectionType", "batteryPercentage",
    "appUptimeInMilliseconds", "diskBytesAvailable", "diskBytesTotal",
    "screenWidthInPoints", "screenHeightInPoints", "pairedAppleWatch", "buildBundleId",
)

# Asked for by name so a future attribute Apple adds cannot smuggle a tester's address into the
# artifact: `email` is simply never in the list.
SUBMISSION_FIELDS = ",".join(SUBMISSION_ATTRIBUTES + ("screenshots", "build", "tester"))

CRASH_LOG_LIMIT = 50          # newest N crash submissions get their log fetched
CRASH_LOG_MAX_CHARS = 100_000  # one iOS crash log is ~30-80 KB; this bounds a runaway artifact


def submission_record(item: dict, builds: dict[str, dict]) -> dict:
    """One submission, flattened to the fields triage reads, with its build resolved."""
    attributes = item.get("attributes", {})
    relationships = item.get("relationships", {})

    def related(name: str) -> str:
        return (relationships.get(name, {}).get("data") or {}).get("id", "")

    build_id = related("build")
    build = builds.get(build_id, {}).get("attributes", {})
    record = {key: attributes.get(key) for key in SUBMISSION_ATTRIBUTES}
    record["id"] = item.get("id")
    record["buildId"] = build_id
    record["buildVersion"] = build.get("version")
    record["buildUploadedDate"] = build.get("uploadedDate")
    record["testerId"] = related("tester")  # opaque; email is deliberately not read
    return record


def download(url: str, destination: str) -> str:
    """Fetch a pre-signed screenshot. No Authorization header — the URL carries its own, and
    sending the JWT to a CDN host would put it somewhere it does not belong."""
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            payload = response.read()
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
        return f"{destination}: not downloaded ({error})"
    with open(destination, "wb") as handle:
        handle.write(payload)
    return ""


def collect_feedback(bearer: str, app: str, screenshot_dir: str | None) -> dict:
    notes: list[str] = []
    report: dict = {
        "schemaVersion": 1,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "bundleId": BUNDLE_ID,
        "appId": app,
        "notes": notes,
    }

    # Builds first, so every submission can name the build it came from. `include=build` returns
    # the build resource too, but only for builds still present; this map is the fallback and is
    # cheap (one paginated list we already know how to read).
    builds = {b["id"]: b for b in all_builds(bearer, app)}

    common = {"limit": "200", "sort": "-createdDate", "include": "build,tester"}

    screenshot_query = urllib.parse.urlencode(
        dict(common, **{"fields[betaFeedbackScreenshotSubmissions]": SUBMISSION_FIELDS}))
    shots, shot_included = paged(
        bearer, f"/apps/{app}/betaFeedbackScreenshotSubmissions?{screenshot_query}", notes)
    builds.update({k: v for k, v in shot_included.items() if v.get("type") == "builds"})

    screenshot_records = []
    for item in shots:
        record = submission_record(item, builds)
        record["screenshots"] = [
            {"url": image.get("url"), "width": image.get("width"),
             "height": image.get("height"), "expirationDate": image.get("expirationDate")}
            for image in (item.get("attributes", {}).get("screenshots") or [])
        ]
        screenshot_records.append(record)

    # The screenshot URLs are pre-signed and expire (the resource says when), so a JSON kept for
    # comparison later points at nothing. Downloading makes the artifact self-contained.
    if screenshot_dir and screenshot_records:
        os.makedirs(screenshot_dir, exist_ok=True)
        for record in screenshot_records:
            for index, image in enumerate(record["screenshots"], start=1):
                name = f"{record['id']}-{index}.png"
                problem = download(image.get("url") or "", os.path.join(screenshot_dir, name))
                image["file"] = None if problem else name
                if problem:
                    notes.append(problem)

    crash_fields = ",".join(SUBMISSION_ATTRIBUTES + ("build", "tester"))
    crash_query = urllib.parse.urlencode(
        dict(common, **{"fields[betaFeedbackCrashSubmissions]": crash_fields}))
    crashes, crash_included = paged(
        bearer, f"/apps/{app}/betaFeedbackCrashSubmissions?{crash_query}", notes)
    builds.update({k: v for k, v in crash_included.items() if v.get("type") == "builds"})

    crash_records = []
    for position, item in enumerate(crashes):
        record = submission_record(item, builds)
        if position < CRASH_LOG_LIMIT:
            log, error = try_call(
                "GET", f"/betaFeedbackCrashSubmissions/{item['id']}/crashLog", bearer)
            text = ((log or {}).get("data", {}).get("attributes", {}) or {}).get("logText") or ""
            record["crashLogTruncated"] = len(text) > CRASH_LOG_MAX_CHARS
            record["crashLog"] = text[:CRASH_LOG_MAX_CHARS]
            if error:
                notes.append(f"crash log for {item['id']}: {error}")
        else:
            record["crashLog"] = None
            record["crashLogTruncated"] = False
            record["crashLogSkipped"] = True
        crash_records.append(record)

    # Whether public reviews are even possible. An app that has never been on the store returns an
    # empty review list, which reads identically to a released app nobody has reviewed; this is the
    # field that tells those two apart.
    versions, version_error = try_call(
        "GET",
        f"/apps/{app}/appStoreVersions?"
        + urllib.parse.urlencode(
            {"limit": "10",
             "fields[appStoreVersions]": "versionString,appStoreState,appVersionState,createdDate"}),
        bearer)
    if version_error:
        notes.append(f"appStoreVersions: {version_error}")
    # An empty list means "never submitted" only if the list was readable. Without this flag the
    # summary would report a forbidden read as a fact about the app.
    report["appStoreVersionsReadable"] = not version_error
    report["appStoreVersions"] = [
        dict(a.get("attributes", {}), id=a.get("id")) for a in (versions or {}).get("data", [])
    ]

    review_query = urllib.parse.urlencode(
        {"limit": "200", "sort": "-createdDate",
         "fields[customerReviews]": "rating,title,body,reviewerNickname,createdDate,territory"})
    reviews, _ = paged(bearer, f"/apps/{app}/customerReviews?{review_query}", notes)
    report["customerReviews"] = [
        dict(r.get("attributes", {}), id=r.get("id")) for r in reviews
    ]

    report["screenshotSubmissions"] = screenshot_records
    report["crashSubmissions"] = crash_records
    report["counts"] = {
        "screenshotSubmissions": len(screenshot_records),
        "crashSubmissions": len(crash_records),
        "customerReviews": len(report["customerReviews"]),
        "appStoreVersions": len(report["appStoreVersions"]),
        "builds": len(builds),
    }
    return report


def print_feedback(report: dict) -> None:
    counts = report["counts"]
    print(f"{BUNDLE_ID} (app {report['appId']}) as of {report['generatedAt']}")
    print(f"  screenshot submissions {counts['screenshotSubmissions']}")
    print(f"  crash submissions      {counts['crashSubmissions']}")
    print(f"  customer reviews       {counts['customerReviews']}")
    print()

    if report["appStoreVersions"]:
        print("App Store versions:")
        for version in report["appStoreVersions"]:
            print(f"  {version.get('versionString')}  appVersionState="
                  f"{version.get('appVersionState')}  appStoreState="
                  f"{version.get('appStoreState')}  created={version.get('createdDate')}")
    elif report.get("appStoreVersionsReadable"):
        print("App Store versions: NONE -- never submitted, so customerReviews cannot be "
              "anything but empty")
    else:
        print("App Store versions: UNREADABLE -- see notes. Empty reviews below prove nothing.")
    print()

    def show(record: dict, kind: str) -> None:
        print(f"[{kind}] {record.get('createdDate')}  build {record.get('buildVersion')}  "
              f"{record.get('deviceModel')} / iOS {record.get('osVersion')}  "
              f"{record.get('locale')}  tester {record.get('testerId')}")
        comment = (record.get("comment") or "").strip()
        print(f"  comment: {comment if comment else '(none)'}")
        if record.get("screenshots"):
            print(f"  screenshots: {len(record['screenshots'])}")
        if record.get("crashLog"):
            first = next((line for line in record["crashLog"].splitlines()
                          if line.strip()), "")
            print(f"  crash log: {len(record['crashLog'])} chars, first line {first[:120]!r}")
        print()

    for record in report["screenshotSubmissions"]:
        show(record, "screenshot")
    for record in report["crashSubmissions"]:
        show(record, "crash")
    for review in report["customerReviews"]:
        print(f"[review] {review.get('createdDate')}  {review.get('rating')}/5  "
              f"{review.get('territory')}  {review.get('reviewerNickname')}")
        print(f"  {review.get('title')}")
        print(f"  {review.get('body')}")
        print()

    if not (report["screenshotSubmissions"] or report["crashSubmissions"]
            or report["customerReviews"]):
        print("NO FEEDBACK OF ANY KIND. Every collection returned zero rows. That is a real "
              "answer -- it is what an app whose testers have sent nothing looks like -- and it "
              "is only meaningful if `notes` below is empty.")
        print()

    print(f"notes: {len(report['notes'])}")
    for note in report["notes"]:
        print(f"  {note}")


def cmd_feedback(arguments: list[str]) -> None:
    json_path = ""
    screenshot_dir = None
    while arguments:
        flag = arguments.pop(0)
        if flag == "--json" and arguments:
            json_path = arguments.pop(0)
        elif flag == "--screenshots" and arguments:
            screenshot_dir = arguments.pop(0)
        else:
            fail(f"usage: appstore_connect.py feedback [--json <path>] "
                 f"[--screenshots <dir>]  (got {flag!r})", 2)
    bearer = token()
    report = collect_feedback(bearer, app_id(bearer), screenshot_dir)
    if json_path:
        with open(json_path, "w") as handle:
            # sort_keys so two runs of the same data produce byte-identical files and a diff
            # between them is about the feedback rather than about dict ordering.
            json.dump(report, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"wrote {json_path}\n")
    print_feedback(report)


def main() -> None:
    if len(sys.argv) < 2:
        fail(__doc__.strip().splitlines()[2], 2)
    command = sys.argv[1]
    if command == "next-build-number":
        cmd_next_build_number()
    elif command == "status":
        cmd_status()
    elif command == "feedback":
        cmd_feedback(sys.argv[2:])
    elif command == "expire-others":
        if len(sys.argv) != 3:
            fail("usage: appstore_connect.py expire-others <build-number>", 2)
        cmd_expire_others(sys.argv[2])
    else:
        fail(f"unknown command {command!r}", 2)


if __name__ == "__main__":
    main()
