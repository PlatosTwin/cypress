#!/bin/bash
# Refuse to ship a product whose signature or profile does not carry what the app declares.
#
# Usage: Tools/verify_entitlements.sh <path to .ipa or .app> <declared entitlements plist>
#        e.g. Tools/verify_entitlements.sh export/Cypress.ipa Cypress/Cypress.entitlements
#
# WHY THIS EXISTS. TestFlight builds 34 and 35 shipped without a working Sign in with Apple:
# the release archive was deliberately unsigned (CODE_SIGNING_ALLOWED=NO), and the export
# step builds the final signature from what the archived app's signature REQUESTS — for an
# unsigned archive that is nothing, so the product was re-signed with only the baseline
# entitlements and every green check stayed green. The entitlement was lost in a step whose
# exit code said success, which is this project's signature failure mode wearing a new coat.
#
# WHAT IT CHECKS, and where the list comes from. The required entitlements are DERIVED from
# the declared entitlements file passed as the second argument — the same file the Xcode
# project signs with (CODE_SIGN_ENTITLEMENTS) — never written out again here. A hand-kept
# copy of that list would be a third statement of a fact the repo already states twice, and
# the day a capability lands without the copy being edited, that capability ships unguarded
# with every job green: the exact argument plan's shard matrix already makes about
# Tools/ui-test-shards.txt (PR #89 review). For each declared key:
#   1. the product's SIGNATURE must carry it WITH THE DECLARED VALUE (codesign -d). The
#      signature is what iOS enforces, and presence alone is not enough: an applesignin
#      whose value is an empty array is a signature Sign in with Apple does not work under,
#      and a presence-only check blesses it (demonstrated against the first draft of this
#      script, PR #89 review). Equality, not membership.
#   2. the embedded PROFILE must authorize it (security cms -D): the key present, and a
#      list-valued declaration covered element-by-element. A signature claiming what its
#      profile does not authorize is rejected at install.
# Plus one baseline key, application-identifier, checked for presence in both. It is not in
# the declared file (Xcode derives it), but it is in every valid distribution signature, so
# its absence means the product was never distribution-signed at all — the canary for "this
# artifact never went through a real signing pass".
#
# Two fences on the DECLARED file itself, both fail-loud:
#   - a value containing `$(` is refused: the release pipeline signs the archive with plain
#     `codesign --entitlements`, which does not expand build-setting substitutions the way
#     Xcode's own signing does, so such a value would ship as the literal text and this
#     guard, comparing signature against declaration, would find them EQUAL — green, broken.
#   - an empty value (array, dict or string) is refused: it grants nothing on any device,
#     and under value-equality it would otherwise verify as a faithful copy of a broken
#     declaration.
set -euo pipefail

# Presence-only baseline, deliberately hand-kept and deliberately tiny: keys that are never
# in the declared file because the signing machinery itself supplies them.
BASELINE_ENTITLEMENTS=(
  "application-identifier"
)

die() { printf 'verify_entitlements: FAIL: %s\n' "$1" >&2; exit 1; }
say() { printf 'verify_entitlements: %s\n' "$1"; }

[ $# -eq 2 ] || die "usage: $0 <path to .ipa or .app> <declared entitlements plist>"
TARGET="$1"
DECLARED="$2"
[ -e "$TARGET" ] || die "no such file: $TARGET"
[ -f "$DECLARED" ] || die "no declared entitlements file at: $DECLARED"
# Lint before parse: a malformed declared file would otherwise exit through a Python
# traceback — closed, but mute about which input was broken (PR #89 review, round 3).
plutil -lint -s "$DECLARED" || die "the declared entitlements file is not a valid plist: $DECLARED"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An .ipa is a zip with Payload/<name>.app inside; an .app is inspected in place.
case "$TARGET" in
  *.ipa)
    unzip -q "$TARGET" -d "$WORK/ipa" || die "could not unzip $TARGET"
    [ -d "$WORK/ipa/Payload" ] || die "$TARGET has no Payload/ directory — not an iOS app package"
    # `|| true` because under `set -e` a failing $(find) would abort the assignment itself
    # and this script would die mute, without the diagnosis on the next line (PR #89 review).
    APPS="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' | sort || true)"
    APP_COUNT="$(printf '%s\n' "$APPS" | grep -c . || true)"
    # Exactly one, not "the first one found": a package holding two apps would otherwise be
    # judged entirely on whichever find returned first, and this script's whole job is
    # refusing to bless bytes it has not inspected (PR #89 review).
    [ "$APP_COUNT" -eq 1 ] || die "$TARGET holds $APP_COUNT Payload/*.app bundles, expected exactly one — refusing to judge a package by one of its members"
    APP="$APPS"
    ;;
  *.app)
    APP="$TARGET"
    ;;
  *)
    die "expected a .ipa or .app, got: $TARGET"
    ;;
esac
say "inspecting $APP"
say "declared entitlements: $DECLARED"

# ── 1. The signature's entitlements ────────────────────────────────────────────────────
# `codesign -d` fails outright on an unsigned bundle, which is itself the red verdict:
# an unsigned product cannot carry any entitlement.
if ! codesign -d --entitlements "$WORK/signature.plist" --xml "$APP" 2>"$WORK/codesign.err"; then
  cat "$WORK/codesign.err" >&2
  die "the product at $APP is not signed at all — no signature, so no entitlements. An unsigned archive reaching this point means the ad-hoc signing step upstream did not run."
fi
[ -s "$WORK/signature.plist" ] || die "the signature carries an EMPTY entitlements blob — a signing pass that requested nothing at all, which is upstream of even builds 34/35's defect (their signatures still carried the baseline keys)"

# ── 2. The embedded profile's authorized entitlements ──────────────────────────────────
PROFILE="$APP/embedded.mobileprovision"
[ -f "$PROFILE" ] || die "no embedded.mobileprovision in $APP — the product was never signed against a provisioning profile"
security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null \
  || die "could not decode $PROFILE"

# ── 3. Judge signature and profile against the declaration ─────────────────────────────
# plistlib rather than plutil keypaths: entitlement keys contain dots, which plutil's
# keypath syntax would read as nesting.
python3 - "$WORK/signature.plist" "$WORK/profile.plist" "$DECLARED" "${BASELINE_ENTITLEMENTS[@]}" <<'PYEOF'
import plistlib, sys

sig_path, prof_path, declared_path, *baseline = sys.argv[1:]
with open(sig_path, "rb") as f:
    signature = plistlib.load(f)
with open(prof_path, "rb") as f:
    profile = plistlib.load(f)
with open(declared_path, "rb") as f:
    declared = plistlib.load(f)
authorized = profile.get("Entitlements")
if not isinstance(authorized, dict):
    print("verify_entitlements: FAIL: the embedded profile has no Entitlements dict", file=sys.stderr)
    sys.exit(1)

print(f"verify_entitlements: profile: {profile.get('Name')!r}, expires {profile.get('ExpirationDate')}")
if not declared:
    print(f"verify_entitlements: NOTE: {declared_path} declares no entitlements — only the baseline keys are checked")

failures = []

def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for v in value:
            yield from strings_in(v)
    elif isinstance(value, dict):
        for v in value.values():
            yield from strings_in(v)

MISSING = object()
for key in sorted(declared):
    want = declared[key]

    # The two declaration fences — see the header comment for why each exists.
    if any("$(" in s for s in strings_in(want)):
        failures.append(
            f"{key} in {declared_path} contains a `$(` build-setting substitution, which the "
            f"release pipeline's plain `codesign --entitlements` pass does NOT expand — it would "
            f"ship as literal text and verify green here. Spell the value out, or move the "
            f"signing of this key into a pass that performs substitution."
        )
        print(f"verify_entitlements: {key}: DECLARATION REFUSED (substitution)")
        continue
    if want == [] or want == {} or want == "":
        failures.append(
            f"{key} in {declared_path} declares an EMPTY value, which grants nothing on any "
            f"device — a faithful copy of a broken declaration would verify green under "
            f"value-equality, so the declaration itself is refused. Declare a real value or "
            f"remove the key."
        )
        print(f"verify_entitlements: {key}: DECLARATION REFUSED (empty value)")
        continue

    got = signature.get(key, MISSING)
    if got is MISSING:
        sig_state = "MISSING"
        failures.append(
            f"{key} is missing from the product's SIGNATURE. iOS enforces the signature, so this "
            f"capability will not work on any device no matter what the profile says. The archive's "
            f"app must request it: check that {declared_path} still declares it and that the "
            f"ad-hoc signing step ran on the archive before export."
        )
    elif got != want:
        sig_state = f"WRONG VALUE {got!r}"
        failures.append(
            f"{key} is in the signature but its value {got!r} does not equal the declared "
            f"{want!r} — the entitlement was mangled between {declared_path} and the final "
            f"signing pass, and the capability cannot be assumed to work."
        )
    else:
        sig_state = "yes"

    if key not in authorized:
        prof_state = "MISSING"
        failures.append(
            f"{key} is missing from the embedded profile's Entitlements dict — the profile predates "
            f"the capability. If export did not regenerate it (-allowProvisioningUpdates), the one "
            f"portal action is: developer.apple.com -> Identifiers -> app.cypress.Cypress -> enable "
            f"the capability for {key}, then delete and regenerate the distribution profile."
        )
    elif isinstance(want, list) and isinstance(authorized[key], list) and not all(v in authorized[key] for v in want):
        prof_state = f"DOES NOT COVER {want!r} (authorizes {authorized[key]!r})"
        failures.append(
            f"{key}: the embedded profile authorizes {authorized[key]!r}, which does not cover the "
            f"declared {want!r} — the profile needs regenerating for the capability's current "
            f"configuration (same portal path as a missing key)."
        )
    else:
        prof_state = "yes"
    print(f"verify_entitlements: {key} = {want!r}: signature={sig_state} profile={prof_state}")

for key in baseline:
    in_sig = key in signature
    in_prof = key in authorized
    print(f"verify_entitlements: {key} (baseline): signature={'yes' if in_sig else 'MISSING'} profile={'yes' if in_prof else 'MISSING'}")
    if not in_sig:
        failures.append(
            f"{key} is missing from the product's signature — every valid distribution signature "
            f"carries it, so this artifact never went through a real distribution signing pass."
        )
    if not in_prof:
        failures.append(f"{key} is missing from the embedded profile's Entitlements dict — not a valid distribution profile.")

if failures:
    for f in failures:
        print(f"verify_entitlements: FAIL: {f}", file=sys.stderr)
    sys.exit(1)
print("verify_entitlements: every declared entitlement is in the signature with its declared value, and authorized by the profile")
PYEOF
