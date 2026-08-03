# Getting Cypress onto five other phones

*Task #187. Written 2026-08-02 against `main` at `e7e63b7`. Everything under "Measured" was run
here and the command is given; everything under "Needs confirming" is written from general
knowledge of Apple's requirements and **has not been checked against App Store Connect today** —
Apple changes these, and a checklist that quotes a stale rule is worse than no checklist.*

Beta is **about five people, no accounts** (owner, 2026-08-02). That scope decides more of this
document than anything else: five people fit inside TestFlight's *internal* path, which skips Beta
App Review entirely, and the app's own account ask is already gated off (`BetaCapability
.accountsAreLocalOnly == true`).

---

## Measured on this tree

| Fact | How |
|---|---|
| **The Release configuration builds.** `** BUILD SUCCEEDED **`, one warning and it is the known non-source `appintentsmetadataprocessor` line. | `xcodebuild build -scheme Cypress -configuration Release -sdk iphonesimulator` into a fresh DerivedData |
| **The DEBUG deep-link harness is absent from the Release binary.** Zero matches for `deeplink` / `cypress-debug` in the built `Cypress.app` binary's strings. #39's guard still holds, now against a real Release build rather than a compile-time assertion. | `strings Cypress.app/Cypress` |
| **A signing team is already configured.** `DEVELOPMENT_TEAM = G44ZKP35ZH`, `CODE_SIGN_STYLE = Automatic`. | `Cypress.xcodeproj/project.pbxproj` |
| **Bundle identity is set and stable.** `app.cypress.Cypress`, `MARKETING_VERSION = 0.1`, `CURRENT_PROJECT_VERSION = 1`, `TARGETED_DEVICE_FAMILY = 1` (iPhone only), `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, portrait only. | same |
| **Export compliance is already answered.** `ITSAppUsesNonExemptEncryption = false` is in `Info.plist`, so the per-build prompt is skipped. | `Cypress/Resources/Info.plist` |
| **Three usage-description strings exist and read as prose, not boilerplate.** Location-when-in-use, camera, photo-library-add. | same |
| **No user data leaves the device.** `RemoteAPI` is a stub and is **never instantiated anywhere in the app** — the only `URLSession` traffic is `CityDownloader` doing GETs against `https://cypress-cities.t3.tigrisbucket.io`, which uploads nothing. | `grep -rn "RemoteAPI(" Cypress` returns nothing |
| **There is no `PrivacyInfo.xcprivacy` in the project.** | `find . -name "*.xcprivacy"` |
| **There is no in-app feedback or support surface.** No `mailto:`, no support address, nothing. | `grep -rln "support@\|mailto" Cypress` |

---

## What is missing, in the order it blocks things

### 1. A privacy manifest — `PrivacyInfo.xcprivacy`

The app calls `UserDefaults.standard` in shipping code (`VisitSaveLedger`, `MapOpeningCamera`),
which is a **required-reason API**. It calls none of the other three families — no file timestamps,
no disk space, no system boot time (checked; zero matches). So the manifest is small:

- `NSPrivacyAccessedAPITypes`: one entry, `NSPrivacyAccessedAPICategoryUserDefaults`, reason
  `CA92.1` (access to the app's own defaults, no app group).
- `NSPrivacyTracking`: `false`. `NSPrivacyTrackingDomains`: empty.
- `NSPrivacyCollectedDataTypes`: **empty**, and that is not a shortcut — see §2.

The file drops into `Cypress/Resources/`; the target is a `PBXFileSystemSynchronizedRootGroup`, so
no `project.pbxproj` edit is needed or permitted. **This is engineering, not an account action, and
it should go through a branch and a verified run like anything else.** It is the one item on this
list an agent can simply do.

### 2. Privacy nutrition labels — the answer is "Data Not Collected", and it is honest

Apple's "collected" means transmitted off the device. Cypress transmits nothing: photographs,
location, notes, check-ins and the whole contribution outbox drain through `APIOutboxTransport`
into `LocalAPI`, which writes this phone's own SQLite. There is no sync (#158 is unbuilt), and
`RemoteAPI` is never constructed.

Two things to say out loud rather than let a reviewer discover:

- The app **uses** precise location and the camera — that is what the three usage strings are for.
  Using is not collecting under Apple's definition, but the labels and the usage strings should not
  read as though the app were coy about it.
- Community-tree photographs are stripped of EXIF and GPS on write (#92). Worth stating in the
  privacy policy because it is a real protection the app performs.

**Confirm this against Apple's current definitions before answering the questionnaire.** An
over-claim ("we collect location") is as wrong as an under-claim and is harder to walk back.

### 3. A privacy policy, and somewhere to put it

App Store Connect wants a URL. There is no policy text and nowhere hosting it. The content is
short given §2 — it is mostly "nothing leaves your phone", plus what the city downloads are and
where they come from. The owner already runs Fly apps and a Tigris bucket, so a static page is
cheap; that is a hosting decision, not an engineering one.

### 4. The App Store Connect record

`app.cypress.Cypress` needs registering, which needs an **App Store Connect app name that is
unique across the entire store**. "Cypress" is a common word and a well-known JavaScript testing
framework; assume it is taken and have a second choice ready. `CFBundleDisplayName` (what shows
under the icon on the phone) is separate and stays "Cypress" regardless.

### 5. Internal vs external testers — the decision that sets the timeline

- **Internal**: testers are added as Users on the App Store Connect team. **No Beta App Review**, so
  a build is testable within minutes of processing. The cost is that each tester needs an Apple ID
  added to the team, which is more friction for them and more access than "a person testing an app"
  usually warrants.
- **External**: testers get a public or emailed link and need no team membership. The first build
  needs **Beta App Review**, which has real latency and is the reason this ticket exists.

Five people fit either. Internal is faster; external is less intrusive for the testers. **Owner's
call**, and it is the single decision that determines whether distribution takes an afternoon or a
week.

### 6. A way for a tester to say what they saw

TestFlight has built-in feedback: a tester screenshots and sends it from the TestFlight app, and it
arrives in App Store Connect. It requires nothing built. What it requires is that the five people
**know it exists** — most people do not. A one-paragraph note sent with the invitation is probably
the whole solution. There is no in-app feedback surface today and I would not build one for five
people.

---

## Two things nobody has ticketed that will show up on a real phone

- **The seed is ~103 MB**, so the install is large. iOS prompts before large downloads over
  cellular. Not a blocker; worth telling testers so a stalled download does not read as a broken
  app.
- **The map and the camera flows have only ever been fully verified on Simulator** for this round.
  `CLAUDE.md` already says map performance and camera flows tell the truth only on the physical
  phone. Before five people walk around SF with this, it should run on a real device once —
  which needs the same signing setup as everything above, so it falls out of step 4 for free.

---

## What the owner has to do, shortest path

1. **Confirm the Developer Program membership on team `G44ZKP35ZH` is active.** The team ID is
   already in the project, so this is probably a renewal check rather than a $99 purchase — but a
   lapsed membership presents as a signing failure much later, and checking now is free.
2. **Decide internal or external** (§5).
3. **Decide the App Store Connect name** (§4).
4. **Say where a privacy policy can live** (§3).

Nothing on this list has been actioned. No provisioning, purchase, or account change has been made
or will be without explicit instruction.
