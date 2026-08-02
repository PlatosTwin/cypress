# The blank-screenshot guard failed open in more ways than the one on record (task #93)

UNNUMBERED — orchestrator splices under the real next number at merge.

E145 recorded that `drawHierarchy` past ~8,192 px of backing store returns a fully transparent
image, and that a guard (`ScreenSweepShots.isNotBlank`) was written against it. Working #93
established that the guard's untrustworthiness was wider than its own comment admitted:

1. **All three unreadable-thumbnail exits returned "not blank"** — already on record in the
   guard's own doc comment, confirmed in code.
2. **The byte scan included row padding.** It compared every byte of the raw `CFData` buffer
   against the first four bytes (`bytes[index % 4]`), so any `CGImage` whose `bytesPerRow`
   exceeds `width × 4` would have its padding garbage counted as image content — a genuinely
   uniform capture declared "not blank". Latent rather than observed (the 16 × 16 renderer
   thumbnail happens to be unpadded RGBA), but it is the fail-open direction. The `% 4` also
   silently assumed 4 bytes per pixel.
3. **The older harness, `DynamicTypeScreenshotTests.render`, had no blank guard at all.** Its
   consumers (`DynamicTypeScreenshotTests` itself, `OwnerWalkShots`, `FavoriteAppearanceShots`)
   asserted only `rendered != nil`, and a `UIImage` of nothing is not nil — every blank mode
   E145 describes would have passed all three suites. The brief's framing "the blank-screenshot
   guard fails open" undersold this: for the majority of shot suites by age, there was no guard
   to fail.
4. **Both harnesses swallowed PNG write failures** (`try? data.write`) and `render` printed its
   `SHOT <path>` line regardless, so a failed write still left a passing test pointing a
   reviewer at a file that does not exist.

Fixed by `CypressTests/ShotBlankGuard.swift` (fails closed: unreadable ⇒ blank; per-pixel walk
that skips row padding; explicit unique-color floor of 4 over a 16 × 16 scale-1 thumbnail;
writes confirmed against the bytes on disk), shared by both harnesses, with
`ShotBlankGuardTests` standing up every blank mode plus end-to-end refusals through each
harness and a content positive-control.

One scope note: the ticket's list of blank modes includes "app not launched / wrong foreground
app / springboard shot". Those are `XCUIScreenshot` failure modes and no such screenshotting
exists in this repo — every shot suite renders SwiftUI views in-process through an off-screen
`UIHostingController` window; `CypressUITests` takes no screenshots. The in-process modes
(transparent past the backing-store ceiling, uniform fill, zero-size, unreadable readback,
zero-byte/failed PNG write) are the complete set here, and all are guarded and tested.
