# Getting Cypress onto five other phones

*Task #187. First written 2026-08-02; **substantially rewritten 2026-08-03 because its founding
premise was wrong.** Everything under "Measured" was run here and the command is given. Anything
about Apple's requirements is written from general knowledge with a May 2026 cutoff and **has not
been checked against App Store Connect today** — Apple changes these, and a checklist quoting a
stale rule is worse than none.*

## The correction that matters most

This ticket was filed as *"nothing in the plan gets the app onto five other phones."* **That was
false.** The owner already has an App Store Connect record for `app.cypress.Cypress` and has
uploaded builds to TestFlight before. The distribution pipeline is not unbuilt work — it exists and
has been used.

What misled the audit: the repo contains **no distribution tooling at all** — no `ExportOptions.plist`,
no fastlane, no CI, nothing in the git history — and `CURRENT_PROJECT_VERSION` is still `1`. Those
are the marks of a project that has never shipped a build. They are not, and the lesson is the
project's own: *a fact absent from the repo is not a fact absent from the world.* The repo is
evidence about the repo.

## Settled by the owner, 2026-08-03

| | |
|---|---|
| **Testers** | **Internal.** Five people join the App Store Connect team as Users. **No Beta App Review**, so a build is testable minutes after processing. |
| **Membership** | **Live.** Team `G44ZKP35ZH`, already configured in the project with automatic signing. |
| **App Store Connect** | Account exists; record for this app exists; builds have been uploaded. |
| **Privacy policy** | **Not required for this path, and the earlier claim that it was is withdrawn.** Internal testers are team members, no review runs, and nothing forces the App Information page to be complete — the owner has been testing through TestFlight without one. It becomes required at App Store submission, and (worth confirming rather than taking from this document) for external TestFlight, since that path does go through review. |

The same applies to the **App Privacy questionnaire**: enforced at submission, not at internal
upload. Worth completing anyway, because the honest answer is short — see §2 — but it blocks
nothing.

## Measured on this tree (`319345b`)

| Fact | How |
|---|---|
| **The Release configuration builds.** `** BUILD SUCCEEDED **`, one warning and it is the known non-source `appintentsmetadataprocessor` line. | `xcodebuild build -scheme Cypress -configuration Release -sdk iphonesimulator` into a fresh DerivedData |
| **All four debug seams are absent from the Release binary** — `CYPRESS_LOCATION`, `CYPRESS_SCREEN`, `CYPRESS_MAP_PROBE`, `CYPRESS_SHOT_DIR`, zero string matches each. This re-proves #39/E117 **against the current tree**, which matters because `CYPRESS_LOCATION` landed with #121 *after* the last time anyone checked. A location override reachable in a shipped build would let launch state move the map. | `strings Cypress.app/Cypress` |
| **`PrivacyInfo.xcprivacy` ships inside the built `.app`.** A manifest that does not ship is worse than none, because it reads as done. | `ls Cypress.app/PrivacyInfo.xcprivacy` |
| **Bundle identity.** `app.cypress.Cypress`, `MARKETING_VERSION = 0.1`, `CURRENT_PROJECT_VERSION = 1`, iPhone only, portrait only, iOS 17 minimum. | `project.pbxproj` |
| **Export compliance is answered.** `ITSAppUsesNonExemptEncryption = false`, so the per-build prompt is skipped. | `Info.plist` |
| **No user data leaves the device.** `RemoteAPI` is a stub and is **never instantiated anywhere in the app**; the only `URLSession` traffic is `CityDownloader` GETting published city files, which uploads nothing. | `grep -rn "RemoteAPI(" Cypress` returns nothing |

## 1 · The one thing that will probably bite on the next upload

**`CURRENT_PROJECT_VERSION` is `1`, and every TestFlight upload needs a build number not already
used for this app.** If build 1 has been uploaded before, the next archive is rejected as a
duplicate — a confusing, late failure with a message about the build already existing.

Whatever the previous uploads used, that number is not in the repo, so **the committed project and
App Store Connect disagree about where the build number is.** Check the highest build number in
TestFlight and set `CURRENT_PROJECT_VERSION` above it before archiving.

**Not done here on purpose:** `CLAUDE.md` forbids editing `Cypress.xcodeproj/project.pbxproj`
(the tree is a `PBXFileSystemSynchronizedRootGroup`). The bump is one field in Xcode's Build
Settings — *Current Project Version* — or an explicit instruction to edit that one line.

Worth considering once, rather than every round: **an `xcconfig` holding the version fields**, so
the build number lives in a text file that can be edited without touching the project, and so
"what shipped" is answerable from the repo. That is a small ticket, not this one.

## 2 · The App Privacy answer, if you fill it in

**"Data Not Collected."** Apple's *collect* means transmitted off the device. Photographs,
precise location, check-ins, measurements, notes and the whole contribution outbox stay in this
phone's SQLite; there is no sync (#158 unbuilt) and `RemoteAPI` is never constructed.

Two things to state rather than let a reviewer discover:

- The app **uses** precise location and the camera — that is what the three usage strings are for.
  Using is not collecting under Apple's definition, but the labels should not read as coy about it.
- Community-tree photographs are stripped of EXIF and GPS on write (#92). That is a real
  protection the app performs and is worth saying out loud.

## 3 · Adding the five testers (internal path)

App Store Connect → **Users and Access** → invite each person by Apple ID. Any role that includes
access to the app works; **Developer** or **App Manager** grants more than testing needs, so
prefer the narrowest role that still shows them the app. Then TestFlight → **Internal Testing** →
add them to a group and enable the build.

Each tester installs **TestFlight** from the App Store, accepts the emailed invitation, and the
build appears there. No review, no public link, no privacy policy.

## 4 · Feedback

TestFlight's built-in feedback needs nothing built: a tester screenshots inside the TestFlight app
and it arrives in App Store Connect. **What it needs is that the five people know it exists** —
most do not. One paragraph in the invitation is the whole solution. There is no in-app feedback
surface and building one for five people would be waste.

## 5 · The real remaining gap, and it is not distribution

**Nothing has run on a physical device this whole stretch.** Every green line in this repo's recent
history is a Simulator green line, and `CLAUDE.md`'s own rule is that map performance and camera
flows only tell the truth on the phone. E139 is the worked example of a defect that only existed on
hardware.

With the membership live this is unblocked. It wants one deliberate pass on a real iPhone:
the map at street zoom and pinched out, a full camera session (full / trunk / leaf), a check-in,
and the location dot while walking. **That pass is also the only way to verify #155's heading
indicator** — the Simulator has no magnetometer and `simctl` cannot simulate heading, so the
compass cone is device-only truth by construction.

## Nothing on the owner's Apple account has been touched

No provisioning, no purchase, no account change has been made here, and none will be without
explicit instruction.
