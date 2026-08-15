#!/bin/bash
# Refuse to ship a product whose signature or profile is missing a required entitlement.
#
# Usage: Tools/verify_entitlements.sh <path to .ipa or .app>
#
# WHY THIS EXISTS. TestFlight builds 34 and 35 shipped without a working Sign in with Apple:
# the release archive was deliberately unsigned (CODE_SIGNING_ALLOWED=NO), and the export
# step builds the final signature from what the archived app's signature REQUESTS — for an
# unsigned archive that is nothing, so the product was re-signed with only the baseline
# entitlements and every green check stayed green. The entitlement was lost in a step whose
# exit code said success, which is this project's signature failure mode wearing a new coat.
#
# So this script asks the two questions that decide whether a capability works on a device,
# of the artifact that will actually be uploaded:
#   1. does the product's SIGNATURE carry each required entitlement (codesign -d)?  The
#      signature is what iOS enforces; a profile that authorizes an entitlement the
#      signature does not claim helps nothing — that is precisely builds 34/35, where the
#      embedded profile said applesignin and the signature said nothing.
#   2. does the embedded PROFILE authorize it (security cms -D)?  A signature claiming an
#      entitlement its profile does not authorize is rejected at install.
# Both must hold, for every entitlement in REQUIRED_ENTITLEMENTS below.
#
# Add to REQUIRED_ENTITLEMENTS when the app gains a capability; a key listed here can never
# again be lost silently between the Xcode project and TestFlight.
set -euo pipefail

# One entitlement per line. application-identifier is in every valid distribution
# signature, so its absence means the product was never distribution-signed at all —
# it is the canary for "this artifact never went through a real signing pass".
REQUIRED_ENTITLEMENTS=(
  "application-identifier"
  "com.apple.developer.applesignin"
)

die() { printf 'verify_entitlements: FAIL: %s\n' "$1" >&2; exit 1; }
say() { printf 'verify_entitlements: %s\n' "$1"; }

[ $# -eq 1 ] || die "usage: $0 <path to .ipa or .app>"
TARGET="$1"
[ -e "$TARGET" ] || die "no such file: $TARGET"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An .ipa is a zip with Payload/<name>.app inside; an .app is inspected in place.
case "$TARGET" in
  *.ipa)
    unzip -q "$TARGET" -d "$WORK/ipa" || die "could not unzip $TARGET"
    APP="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
    [ -n "$APP" ] || die "$TARGET holds no Payload/*.app — not an iOS app package"
    ;;
  *.app)
    APP="$TARGET"
    ;;
  *)
    die "expected a .ipa or .app, got: $TARGET"
    ;;
esac
say "inspecting $APP"

# ── 1. The signature's entitlements ────────────────────────────────────────────────────
# `codesign -d` fails outright on an unsigned bundle, which is itself the red verdict:
# an unsigned product cannot carry any entitlement.
if ! codesign -d --entitlements "$WORK/signature.plist" --xml "$APP" 2>"$WORK/codesign.err"; then
  cat "$WORK/codesign.err" >&2
  die "the product at $APP is not signed at all — no signature, so no entitlements. An unsigned archive reaching this point means the ad-hoc signing step upstream did not run."
fi
[ -s "$WORK/signature.plist" ] || die "the signature carries an EMPTY entitlements blob — the signing pass ran without any entitlements file (builds 34/35's exact defect)"

# ── 2. The embedded profile's authorized entitlements ──────────────────────────────────
PROFILE="$APP/embedded.mobileprovision"
[ -f "$PROFILE" ] || die "no embedded.mobileprovision in $APP — the product was never signed against a provisioning profile"
security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null \
  || die "could not decode $PROFILE"

# ── 3. Judge both against the required list ────────────────────────────────────────────
# plistlib rather than plutil keypaths: entitlement keys contain dots, which plutil's
# keypath syntax would read as nesting.
python3 - "$WORK/signature.plist" "$WORK/profile.plist" "${REQUIRED_ENTITLEMENTS[@]}" <<'PYEOF'
import plistlib, sys

sig_path, prof_path, *required = sys.argv[1:]
with open(sig_path, "rb") as f:
    signature = plistlib.load(f)
with open(prof_path, "rb") as f:
    profile = plistlib.load(f)
authorized = profile.get("Entitlements")
if not isinstance(authorized, dict):
    print("verify_entitlements: FAIL: the embedded profile has no Entitlements dict", file=sys.stderr)
    sys.exit(1)

print(f"verify_entitlements: profile: {profile.get('Name')!r}, expires {profile.get('ExpirationDate')}")

failures = []
for key in required:
    in_sig = key in signature
    in_prof = key in authorized
    print(f"verify_entitlements: {key}: signature={'yes' if in_sig else 'MISSING'} profile={'yes' if in_prof else 'MISSING'}")
    if not in_sig:
        failures.append(
            f"{key} is missing from the product's SIGNATURE. iOS enforces the signature, so this "
            f"capability will not work on any device no matter what the profile says. The archive's "
            f"app must request it: check that Cypress/Cypress.entitlements still declares it and "
            f"that the ad-hoc signing step ran on the archive before export."
        )
    if not in_prof:
        failures.append(
            f"{key} is missing from the embedded profile's Entitlements dict — the profile predates "
            f"the capability. If export did not regenerate it (-allowProvisioningUpdates), the one "
            f"portal action is: developer.apple.com -> Identifiers -> app.cypress.Cypress -> enable "
            f"the capability for {key}, then delete and regenerate the distribution profile."
        )

if failures:
    for f in failures:
        print(f"verify_entitlements: FAIL: {f}", file=sys.stderr)
    sys.exit(1)
print("verify_entitlements: every required entitlement is in the signature and authorized by the profile")
PYEOF
