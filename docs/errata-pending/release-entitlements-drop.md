# Unnumbered — the entitlements the project declared never reached TestFlight, and every step was green

Staged unnumbered per CLAUDE.md, "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `claude/epic-mcnulty-baf13b` while fixing the release
pipeline after TestFlight builds 34 and 35 shipped with Sign in with Apple broken on device
(instant failure, no sheet), while a locally archived dev-signed build of the same commit worked.
Everything below was reproduced locally on 2026-08-15 with real archives and exports on this
machine; nothing is inferred from documentation.

## 1. Export signs what the archive's signature requests — an unsigned archive requests nothing

`.github/workflows/testflight.yml` archives with `CODE_SIGNING_ALLOWED=NO` (deliberate; automatic
signing on the runner demands a Development identity it does not have, runs 31052462134 and
31054628357), and the Export step performs the only signing pass, authenticated by the ASC API
key. The trap: `xcodebuild -exportArchive` never reads the Xcode project. It builds the final
signature's entitlements from what the archived app's **existing signature** requests — and an
unsigned archive requests nothing, so `CODE_SIGN_ENTITLEMENTS` (`Cypress/Cypress.entitlements`,
added with the Sign in with Apple button) was processed by nobody.

Reproduced both directions on the same commit, same export options, dev signing:

- **Red**: archive with `CODE_SIGNING_ALLOWED=NO`, export → the product's signature carries only
  `application-identifier`, `com.apple.developer.team-identifier`, `get-task-allow`.
  `com.apple.developer.applesignin` is absent from the signature **even though the embedded
  profile authorizes it** — the profile is the ceiling, the signature's request is the floor, and
  iOS enforces the signature. This is builds 34 and 35 exactly.
- **Green**: ad-hoc-sign the app inside the archive
  (`codesign --force -s - --entitlements Cypress/Cypress.entitlements <app>`), same export → the
  entitlement is present in the exported signature, which `codesign -v --strict` accepts.

Builds 1–33 were unaffected only because the project had no entitlements file yet — there was
nothing to lose. The fix ships the ad-hoc pass as a release-job step: no certificate, no profile,
no new secret, and the export replaces it wholesale with the real Apple Distribution signature.
Signing the archive properly at build time was tried and refused: manual style with
`CODE_SIGN_IDENTITY=-` fails on `"Cypress" requires a provisioning profile`, with or without
`AD_HOC_CODE_SIGNING_ALLOWED=YES` and `PROVISIONING_PROFILE_REQUIRED=NO`.

## 2. `destination = upload` meant the shipped product was uninspectable, so the guard forced a split

With `destination = upload` the final .ipa exists only inside xcodebuild; nothing can look at it
before it reaches TestFlight, which is why this class of loss could ever be silent. The pipeline
now exports to disk (`destination = export`), runs `Tools/verify_entitlements.sh` against the
exact .ipa, and uploads those same bytes with `xcrun altool --upload-app`, authenticated by the
same API key (Xcode 26.6's altool documents API-key auth and the `$API_PRIVATE_KEYS_DIR` lookup,
which matches where the workflow already writes `AuthKey_<id>.p8`).

The guard's required list is **derived from `Cypress/Cypress.entitlements` itself** — the same
file the project signs with — plus one hand-kept baseline key, `application-identifier`, the
was-this-ever-distribution-signed canary that the signing machinery supplies rather than the
file. A hand-kept required list would have been a third copy of a fact the repo already states
twice, unenforced at exactly the moment the next capability lands; the shard matrix in the same
workflow already makes this argument about `Tools/ui-test-shards.txt`, and the PR #89 review
made it about the guard's first draft. Each declared key must appear in the product's signature
(`codesign -d --entitlements`) **with its declared value** — presence alone blessed an
`applesignin = <array/>` signature that Sign in with Apple does not work under, demonstrated
end-to-end against the first draft — and must be authorized by the embedded profile's
`Entitlements` dict (`security cms -D`), element-by-element for list values. Two fences red the
declaration itself: a value containing `$(` (the release pipeline's plain `codesign` pass does
not expand substitutions, so the literal would ship and compare equal) and an empty value (a
faithful copy of a broken declaration would otherwise verify green).

Calibrated on 2026-08-15, one green and eight reds, each red checked for its **reason** and not
just its color: the build-34-shaped .ipa (message blames the signature, not the profile), a bare
unsigned app, a signed app whose embedded profile predates the capability (message names the
portal action), a signature carrying `applesignin = []` (WRONG VALUE, plus the baseline canary),
a declared file saying `<array/>` (declaration refused), a declared file carrying
`$(AppIdentifierPrefix)` (declaration refused), an .ipa holding two `.app` bundles (refuses to
judge a package by one member), and an .ipa with no `Payload/` (which diagnoses itself rather
than dying mute on the `$(find)` under `set -e` — the first draft's silent-abort, caught in
review with a control).

A `--upload-app` against a live ASC key cannot run on this machine by design. The review
established the proving run is **this PR's own merge**: `Tools/ExportOptions.plist` and
`Tools/verify_entitlements.sh` are outside `plan`'s `NO_ARCHIVE` set, so the merge commit ships
automatically — it consumes the next build number and, if it reaches the expire step, expires
build 35. Nobody should wait for a `workflow_dispatch` that is not needed. The step order
protects the testers (export → guard → upload → expire → tag: any failure before upload leaves
build 35 testable), and an upload failure is a red job, not a silent one. What the merge run
must show: the ad-hoc readback listing `applesignin`, the export either regenerating the store
profile or failing loudly on it, the guard's per-key table, and the `ls -R` of the export
directory that settles whether an app-store-connect export writes a `Symbols/` directory —
plus the dSYMs artifact, kept for 30 days because the shipped binary is stripped and the
archive's dSYM (same UUID) is the only thing that can ever symbolicate it.

## 3. The cloud-managed distribution profile also predates the capability — and the fix converts that from silent to loud

The locally cached `iOS Team Store Provisioning Profile: app.cypress.Cypress` (generated
2026-07-30, before the entitlements file landed) has **no** `com.apple.developer.applesignin` in
its `Entitlements` dict, while the dev team profile regenerated 2026-08-14 has it — the App ID
capability is registered; the store profile is just stale. Builds 34 and 35 sailed past that
staleness because their empty signatures demanded nothing of the profile. With the archive now
requesting the entitlement, an offline export against the stale profile fails loudly:

    error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile:
    app.cypress.Cypress" doesn't include the com.apple.developer.applesignin entitlement.

In CI, `-allowProvisioningUpdates` plus the ASC key is expected to regenerate the store profile
during export (profiles are regenerable and uncapped — the certificate half was the #232
problem, not this). If it ever does not, the export or the guard goes red naming the one portal
action, instead of TestFlight receiving a build whose button does nothing.

## 4. The general lesson, for the next capability

A capability added to the project arrives at testers only if all three hold: the entitlements
file declares it, the shipped signature requests it, and the profile authorizes it. The project
and the device were checked here; the middle leg had no witness, and it is the only leg the
release pipeline manufactures itself. When the next capability lands (push, iCloud, App Groups),
there is nothing to remember: the guard derives its required keys and values from
`Cypress/Cypress.entitlements`, so the new key is guarded the moment it is declared. The two
exceptions are stated in the script itself — a declared value that needs `$(…)` substitution is
refused until the signing pass can expand it, and a machinery-supplied key that never appears in
the declared file (the `application-identifier` shape) belongs in the script's small baseline
list.
