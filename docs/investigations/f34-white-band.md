# F34: a white band under the tab bar (ROADMAP 101)

Investigation only, 2026-11-14. Not reproduced. No app code changed.

## The report

- Feedback id `AKlo-N-4tD6rsh0GaqUd7Rs`, 2026-09-30 22:03 UTC, build 82, iPhone17_5 (390 x 844 pt,
  3x), iOS 26.6.1, app up for 398 s, light appearance, mobile data.
- Comment: *"Strange empty white space has appeared below bottom menu after browsing the tabs for
  City and Neighborhood"*. "City" and "Neighborhood" are the Journal's two stats segments.
- Source: `asc-feedback` artifact of run 43331239955. The PNG is the durable copy; Apple's URL
  expires 2026-11-18.

## What the screenshot shows (measured on the pixels)

- The screen is **My Grove > Trees**, not the Journal. The tester had left the Journal.
- The tab bar's top hairline is at y = 2130 px (710 pt). Its fill ends at y = 2387 px (795.7 pt).
  The bar is 85.7 pt tall, which is its normal height.
- Below the bar, rows 2388-2531 px are `#FFFEFF`, plain white: a band of **about 48 pt**, not 60.
- The screen's own ground is `surfaceScreen` (`#F7F7F2`) everywhere else. The band is a different,
  whiter color, so it is not the Grove view's background. It is the ground of whatever hosts the
  view (the `NavigationStack` and its hosting controller, white in light mode).
- The top of the screen is in its normal place. The title "My Grove" sits where it sits in F38's
  screenshot (same device, build 82, My Grove > Species), and in F38 the bar runs to the bottom edge
  with its hairline at about 758 pt.
- So the whole tab root lost about 48 pt **at the bottom only**. The bar did not grow and did not
  move by itself; the view that holds it got shorter, and the host showed through underneath.

## The code that decides the bottom edge

- `BottomTabBar` is custom (C16). Each tab root draws its own copy at the foot of a `VStack`:
  `GroveView` (line 98), `JournalTabView` (line 214), `YouTabView` (line 104), `MapHomeView`
  (line 201).
- Grove, Journal and You all end with `.background(CypressColor.surfaceScreen)` and then
  `.ignoresSafeArea(.container, edges: .bottom)` (`GroveView.swift` lines 101-104). That opts out
  of the **container** inset only. Any other bottom inset, such as the keyboard region, still
  shortens the view, and its plain `.background` shortens with it. The host's white then shows
  below. This is the same shape the F8 fix (commit `a628550a`, `VisitCameraView.body`) describes
  and corrected on the camera screens.
- `MapHomeView` ignores every region (`.ignoresSafeArea()` at line 218), so the Map tab cannot show
  this band in the same way.
- The Journal's City and Neighborhood segments (`CityView`, `AlmanacView`) contain no text field,
  no `safeAreaInset`, and no `ignoresSafeArea`. Their only presentation is the area picker, which
  `RootView.presentedSheet` shows in the app's single `fullScreenCover` as a
  `BottomSheet(style: .standard)` with no text field.
- The only text field reachable from a tab root is the map's search bar (`SearchBar`,
  `MapSearch`, `MapChrome`).

## What was tried

| Step | Device | Result |
|---|---|---|
| Built build-for-test of this branch (main at `12eaaade`) with `Tools/run_tests.sh`, one UI test (`AreaPickerUITests/testTheCitySegmentPicksACityAndNamesIt`) | slot 2, `0FE2A014-…`, iPhone 17 Pro, iOS 26.5 | Build compiled. The test runner then hung on `DTServiceHubClient failed to bless service hub` (ROADMAP 112). No test ran. Run stopped by its own pid. |
| Installed the built `Cypress.app` with `simctl install`, launched with `CYPRESS_SCREEN=grove`, `journalCity`, `journal` and `CYPRESS_LOCATION` of Western Addition, screenshot with `simctl io` | same | Real screenshots (status bar, live content). On all three the bar runs to the bottom edge. No band. |
| Drive the app by hand (tap, swipe, keyboard, background) | same | **Not possible.** The simulator control tool has no grant for this device, and the owner was not there to give one. XCUITest hangs, so a probe test could not drive it either. |

What was **not** tried, for the reasons above: opening and closing the area picker, switching
segments and tabs, the map search keyboard, Larger Text, backgrounding, and the tester's own iOS
version (26.6.1) and screen size (390 x 844 pt).

## Candidate causes, ranked

1. **A bottom inset from a region other than `.container` reaches a tab root that only ignores
   `.container`.**
   - For: it explains every measured fact. The top stays, the bottom rises, the bar keeps its
     height, and the color below is the host's white, not `surfaceScreen`. The three non-map tab
     roots have exactly the pre-F8 shape. It is the "same visual family as F8" the roadmap names,
     with the same code shape.
   - Against: 48 pt is not a software keyboard's height, and nothing on the Journal or Grove
     screens raises a keyboard. The inset would have to be stale (left behind after a keyboard went
     away) or small (for example the bar iOS shows when a hardware keyboard is connected). Neither
     was observed.
2. **The `fullScreenCover` that presents the area picker leaves the presenting hierarchy's size or
   safe area wrong when it is dismissed.**
   - For: it is the one thing the tester's steps add ("browsing City and Neighborhood" means the
     picker, as the segments have no other presentation). A full-screen presentation removes the
     presenter's view and puts it back on dismissal, which is where a stale layout would come from.
   - Against: no reproduction, and no system defect of this kind is on record in this repo. The
     band was seen on My Grove, after at least one more tab switch, which rebuilds the tab root
     (`RootView.tabRoot` is a `switch`); a stale layout on the Journal view alone would not survive
     that, so the stale value would have to live above the tab root.
3. **Something else in the `NavigationStack` claims about 48 pt at the bottom** (a bottom bar or
   toolbar region).
   - For: 48-49 pt is the height UIKit gives a toolbar or tab bar.
   - Against: no screen sets a bottom toolbar; the tab roots only hide the navigation bar.

A fix that only paints the ground (`.background(surfaceScreen.ignoresSafeArea())`, as F8 did)
would turn the band cream instead of white, but the bar would still float 48 pt above the edge. It
would hide the symptom without removing the cause, so it was not made.

## What the owner could capture next time

- A **screen recording** from the last normal screen to the band, rather than one screenshot.
- Whether the map's search field was used in that session, and whether a hardware or Bluetooth
  keyboard was connected.
- Whether the area picker was opened, and how it was closed (a choice, a tap on the dimmed area,
  or a drag down).
- Whether the band stays after switching to Map and back, after leaving the app and coming back,
  and after force-quitting.
- Settings > Accessibility > Display & Text Size > Larger Text, and Settings > Display &
  Brightness > Display Zoom.

On our side, once local UI tests run again (ROADMAP 112), a probe test should walk the Journal's
City and Neighborhood segments, open and close the picker each of the three ways, use the map
search keyboard, switch tabs and background the app, and after each step compare the
`My Grove` tab button's `frame.maxY` with the window's height. A gap that grows by about 48 pt is
the reproduction, and the same assertion is the regression test.
