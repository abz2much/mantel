# Own notch window, part 2 (monitors): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Mantel work on screens without a notch: hover the top centre to open the panel, show a small black tab while music or a timer runs, send alerts to the active app's screen, and add two Settings switches.

**Architecture:** Part 1 has one `NotchPresenter`. Part 2 gives each screen its own presenter, wrapped in a `NotchStage` that owns that screen's reconcile loop and hover timing. Hover and click-through move from SwiftUI `onHover` to one `PointerWatcher` that polls the pointer position, which needs no permission. This also fixes the click band around an open panel. `NotchDecision` decides each screen's mode from plain flags, and pure helpers pick the alert screen and the hover zone. The controller recomputes everything on every change, including display changes, which fixes the lid-close and popup-stays-on-monitor gaps.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, CoreGraphics window list, SwiftPM, Swift Testing, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-07-own-notch-window-design.md` (the "Monitors" and "Settings" sections). Built on part 1: `docs/superpowers/plans/2026-11-07-own-notch-window-part-1.md`.

## Global Constraints

- No new permissions: no Accessibility, Screen Recording or Input Monitoring. Window bounds come from `CGWindowListCopyWindowInfo` (bounds and owner PID only; never read window names).
- No new dependencies. macOS 14+. App ID unchanged.
- Laptop notch behaviour unchanged from part 1, apart from hover and click-through now coming from the pointer poll.
- Hover dwell 0.3 s and leave delay 0.5 s, the same on every screen.
- Settings copy, exactly: section "Monitors"; toggle "Use Mantel on screens without a notch"; toggle "Show a small tab while music or a timer runs". Both default on. The second is indented and disabled when the first is off.
- With no notch screen and the first switch off, only meeting countdowns show, on the main screen. Nothing else shows.
- The six-second "peek" is removed.
- Test-first; all existing tests keep passing.

## Review Focus

1. **Two monitors plus the laptop.** Only one panel may be open at a time, and alerts go to one screen only. Covered by `alertsGoToOneScreenOnly` (Task 3).
2. **The active app's window straddling two screens.** It should pick the screen holding most of the window. Covered by `straddlingWindowPicksLargerShare` (Task 4).
3. **Pointer in the hover zone while a menu bar menu is open.** It must not fight the open menu. The watcher's timer runs in `.common` mode, and the panel only opens after the 0.3 s dwell. Checked by hand in Task 6.
4. **Lid closes while the side pieces or a popup are showing.** Nothing should be left behind on the monitor. Covered by `screensRebuiltOnDisplayChange` (Task 5) plus a hand check.
5. **Full-screen app on a monitor.** Hovering the top must not fight the macOS menu bar. Checked by hand in Task 6, with the fallback rule given there.

---

### Task 1: Pointer-driven hover and click-through

Replaces `onHover` with a polled pointer. It also adds the reviewer's two small fixes: the click band around an open panel, and `hide()` returning early.

**Files:**
- Create: `Sources/Notch/PointerWatcher.swift`
- Modify: `Sources/Notch/NotchPresenter.swift`, `Sources/Notch/NotchSurface.swift` (remove `.onHover` and `.contentShape`), `Sources/Notch/NotchGeometry.swift`
- Test: `Tests/NotchTests/NotchPresenterTests.swift`, `Tests/NotchTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:
  - `NotchGeometry.screenRect(windowRect: CGRect, windowFrame: CGRect) -> CGRect`, which converts a top-left-origin rect inside the window into AppKit screen coordinates
  - `NotchPresenter.pointerMoved(to point: CGPoint)`: sets `isHovering` to whether `point` is in the shape's screen rect, and sets `window.ignoresMouseEvents = !isHovering`
  - `NotchPresenter.shapeFrameOnScreen: CGRect` (`.zero` when hidden)
  - `@MainActor final class PointerWatcher { init(interval: TimeInterval = 0.05, onMove: @escaping (CGPoint) -> Void); func start(); func stop() }`: a `Timer` in `.common` mode reading `NSEvent.mouseLocation`, calling `onMove` only when the position changes

- [ ] **Step 1: Write the failing tests:**
  - `screenRectFlipsIntoScreenCoordinates`: windowRect (161, 0, 434, 220) in windowFrame (378, 491, 756, 491) → (539, 762, 434, 220)
  - `pointerOverShapeHoversAndTakesClicks` (`@MainActor`, enabled if there's a screen): expand, wait; `pointerMoved(to: shapeFrameOnScreen.center)` makes `isHovering` true and `window!.ignoresMouseEvents` false; `pointerMoved(to: CGPoint(x: shapeFrameOnScreen.minX - 10, y: shapeFrameOnScreen.midY))` makes `isHovering` false and `ignoresMouseEvents` true
  - `hideReturnsAtOnceWhenNothingShows`: on a fresh presenter, `await hide()` takes under 0.05 s (use `ContinuousClock`)

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter "NotchPresenterTests|NotchGeometryTests"`. Expected: compile errors for `screenRect` and `pointerMoved`.

- [ ] **Step 3: Implement.**
  - New windows start with `ignoresMouseEvents = true`.
  - `hide()` returns at once when `window == nil`.
  - Remove `setHovering`.
  - Keep `hitTest` as a second guard.

- [ ] **Step 4: Run them to see them pass,** then run the full `swift test`.

- [ ] **Step 5: Wire it up in `NotchController.start()`.** Create a `PointerWatcher` that calls `notch?.pointerMoved(to:)`, and start it. This is temporary: Task 5 replaces it with the per-screen version. Then run `./build.sh`.

- [ ] **Step 6: Commit** with the message "Drive notch hover and click-through from the pointer position".

### Task 2: Monitor settings

**Files:**
- Create: `Sources/Notch/MonitorSettings.swift`
- Modify: `Sources/Notch/SettingsView.swift` (Features tab, after the existing sections), `Sources/Notch/NotchApp.swift` (create the settings and pass them to `SettingsView` and `NotchController`)
- Test: `Tests/NotchTests/SettingsRulesTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor final class MonitorSettings: ObservableObject`, with:
    - `init(defaults: UserDefaults = .standard)`
    - `@Published var enabled: Bool` (key `"monitorsEnabled"`, default true)
    - `@Published var tabEnabled: Bool` (key `"monitorTabEnabled"`, default true)
    - `var showsTab: Bool { enabled && tabEnabled }`
  - `SettingsView` gains `@ObservedObject var monitors: MonitorSettings`
  - `NotchController.init` gains a `monitors: MonitorSettings` parameter

- [ ] **Step 1: Write the failing tests**, using `UserDefaults(suiteName: "test.\(UUID())")!`:
  - `monitorSettingsDefaultOn`: both true; `showsTab` true
  - `monitorSettingsPersist`: set both false, make a new `MonitorSettings` on the same defaults → both false
  - `tabHiddenWhenMonitorsOff`: enabled false, tabEnabled true → `showsTab` false

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter SettingsRulesTests`. Expected: "cannot find 'MonitorSettings'".

- [ ] **Step 3: Implement `MonitorSettings`** and the Settings section with the exact copy from Global Constraints. The second toggle has `.padding(.leading, 16)` and `.disabled(!monitors.enabled)`.

- [ ] **Step 4: Run them to see them pass,** then run `swift test` and `./build.sh`.

- [ ] **Step 5: Look at it.** Render the Features tab with the existing `Screenshots` test approach (or open Settings in the built app and run `screencapture`). Expected: the new section reads exactly as the copy says, with the second toggle indented.

- [ ] **Step 6: Commit** with the message "Add monitor settings".

### Task 3: Per-screen decision

**Files:**
- Modify: `Sources/Notch/NotchDecision.swift`
- Test: `Tests/NotchTests/NotchDecisionTests.swift` (existing tests updated: `peeking` is removed)

**Interfaces:**
- Produces:
  - `NotchMode` gains `.tab`, the monitor's resting tab.
  - `NotchInputs`: drop `peeking`; add `isAlertScreen: Bool`, `timerRunning: Bool`, `monitorsEnabled: Bool`, `tabEnabled: Bool`, `anyNotchScreen: Bool`. All default to false, except `isAlertScreen`, `monitorsEnabled` and `tabEnabled`, which default to true, so part 1's tests keep their meaning.
  - `NotchDecision.mode(for:)`, with the rules below. `keepsHoverExpanded` is unchanged in meaning, except that "nowhere to hover" now means: no notch, and monitors are off.
  - `struct ScreenInfo: Equatable { let id: Int; let hasNotch: Bool; let isMain: Bool }`
  - `NotchDecision.alertScreen(screens: [ScreenInfo], active: Int?, monitorsEnabled: Bool) -> Int?`

The rules for `mode(for:)`:
1. When the screen has no notch and monitors are off: `.meeting` if `hasReminder && !anyNotchScreen && isAlertScreen`, else `.hidden`.
2. Alerts (battery > meeting > timerDone) show only when `isAlertScreen`.
3. The resting state on a notch screen is as in part 1: musicCompact, musicExpanded, idle or idleExpanded.
4. The resting state on a monitor:
   - hoverExpanded → `.musicExpanded` if musicShowsCard, else `.idleExpanded`;
   - else `.tab` if tabEnabled and (musicShowsCard or timerRunning);
   - else `.hidden`.

The rules for `alertScreen`:
- The active screen, if it has a notch, or if monitors are on.
- Otherwise the notch screen.
- Otherwise the main screen, when monitors are off. Rule 1 then limits it to meetings.
- `nil` if there are no screens.

- [ ] **Step 1: Write the failing tests:**
  - `monitorRestsAsTabWhileMusicPlays`: musicShowsCard → `.tab`; timerRunning → `.tab`; tabEnabled false → `.hidden`; nothing → `.hidden`
  - `monitorHoverOpensPanel`: hoverExpanded → `.idleExpanded`; with music → `.musicExpanded`
  - `alertsOnlyOnAlertScreen`: hasReminder, screenHasNotch, isAlertScreen false → `.idle`; the same on a monitor with music → `.tab`
  - `monitorsOffHidesEverythingButLidClosedMeetings`: monitorsEnabled false, no notch: music → `.hidden`; hasReminder with anyNotchScreen true → `.hidden`; hasReminder with anyNotchScreen false and isAlertScreen → `.meeting`; timerDoneShowing with anyNotchScreen false → `.hidden`
  - `batteryOnMonitorShowsEvenWithTabOff`: batteryFlashing, tabEnabled false, monitor, isAlertScreen → `.battery`
  - `alertsGoToOneScreenOnly`: screens [notch 1, monitor 2, monitor 3], active 3 → 3; monitors off → 1; active nil → 1; [monitor 2 (main), monitor 3], monitors off, active 3 → 2; [] → nil

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchDecisionTests`. Expected: compile errors (`.tab`, `alertScreen`).

- [ ] **Step 3: Implement,** and update part 1's `peekWithoutNotch` test to the new rule. A monitor with music and monitors on gives `.tab`; rename it `musicOnMonitorShowsTab`.

- [ ] **Step 4: Run them to see them pass.** The controller won't compile until Task 5 if it still uses `peeking`. Remove `peekUntil`, `peekDuration` and the `onPlay` peek handler from `NotchController` now, so `swift test` passes.

- [ ] **Step 5: Commit** with the message "Decide each screen's notch mode, with monitor rules".

### Task 4: Active screen and hover zone

**Files:**
- Create: `Sources/Notch/ActiveScreen.swift`
- Modify: `Sources/Notch/NotchGeometry.swift`
- Test: `Tests/NotchTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:
  - `NotchGeometry.hoverZone(screenFrame: CGRect) -> CGRect`: centred, 464 wide (the panel's 404 plus 2 × 30), and 3 pt tall at the very top
  - `enum ActiveScreen`, with:
    - `static func pick(windowBounds: CGRect?, mouse: CGPoint, screens: [(id: Int, frame: CGRect)]) -> Int?`. `windowBounds` is already in AppKit coordinates. It returns the screen with the largest overlap with the window, or, with no window, the screen containing the mouse.
    - `static func flip(cgBounds: CGRect, primaryHeight: CGFloat) -> CGRect`, which converts CG window-list coordinates (top-left origin) to AppKit coordinates
    - `@MainActor static func current() -> Int?`, the live version: front app PID → first on-screen layer-0 window in `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` → `flip` → `pick`. Screens are identified by `screenNumber.intValue`.

- [ ] **Step 1: Write the failing tests:**
  - `hoverZoneIsTopCentreStrip`: frame (1512, −200, 1920, 1080) → (2240, 877, 464, 3)
  - `flipFromWindowListCoordinates`: cg (100, 50, 800, 600), primaryHeight 982 → (100, 332, 800, 600)
  - `activeScreenFromWindow`: screens [(1, laptop 0,0,1512,982), (2, 1512,−200,1920,1080)], window (1600, 100, 800, 600) → 2
  - `straddlingWindowPicksLargerShare`: window (1300, 100, 600, 400) → 2 (more of it is on 2)
  - `activeScreenFallsBackToMouse`: window nil, mouse (200, 300) → 1

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchGeometryTests`. Expected: compile errors.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them to see them pass,** then run the full suite.

- [ ] **Step 5: Commit** with the message "Find the active app's screen and the monitor hover zone".

### Task 5: One stage per screen, the monitor tab and display changes

**Files:**
- Create: `Sources/Notch/NotchStage.swift`, which holds the `NotchPresenting` protocol, `NotchStage`, and the presenter's conformance
- Create: `Sources/Notch/MonitorTabView.swift`
- Modify: `Sources/Notch/NotchController.swift`, `README.md` (features list: a short "On a monitor" paragraph and the two switches)
- Test: `Tests/NotchTests/NotchStageTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - `@MainActor protocol NotchPresenting: AnyObject`, with:
    - `var isHovering: Bool { get }`
    - `func expand(on: NSScreen) async`
    - `func compact(on: NSScreen) async`
    - `func hide() async`
    - `func pointerMoved(to: CGPoint)`
    - `var window: NSPanel? { get }`
  - `@MainActor final class NotchStage`, with:
    - `init(screenID: Int, presenter: NotchPresenting, onHoverExpandedChange: @escaping () -> Void)`
    - `var desired: NotchMode`
    - `private(set) var applied: NotchMode`
    - `var hoverExpanded: Bool`
    - `func apply(_ mode: NotchMode, on screen: NSScreen, perform: @escaping (NotchMode) async -> Void)`, which runs today's reconcile loop for this screen
    - `func pointerMoved(to: CGPoint, zone: CGRect?)`, which runs today's dwell and leave timing (0.3 s / 0.5 s). Hovering counts as the presenter's `isHovering`, or the point being inside `zone` (the monitor hover zone; `nil` on notch screens). Only the idle or resting modes (`.idle`, `.musicCompact`, `.tab`, `.hidden` on a monitor) can start a hover.
  - `struct MonitorTabView: View`, with `state: NotchState`, `music: MusicService`, `timer: TimerService`. It shows:
    - a battery alert: the existing `BatteryCompactSide` leading and trailing, side by side;
    - otherwise, art (if music and `showAlbumArt`), the song title (max 160 pt, one line), and the amber dot plus time left (if the timer is running), in that order, with 8 pt spacing.

How the controller works after this task:
- It keeps `stages: [Int: NotchStage]`, one per `NSScreen.screens` entry, rebuilt on `didChangeScreenParametersNotification`. Stages for screens that are gone are hidden and dropped. After that it calls `evaluate()`.
- **Presenters:** notch screens use `NotchPresenter<NotchRootView, CompactLeading, CompactTrailing>`. Monitors use `NotchPresenter<NotchRootView, MonitorTabView, EmptyView>`.
- **`evaluate()`:**
  1. Compute `alertScreen` once, from `ActiveScreen.current()`.
  2. For each stage, build `NotchInputs` and call `NotchDecision.mode`.
  3. If the hovered stage (at most one) hovers, clear `hoverExpanded` on all the others.
  4. Call `stage.apply`.
- **`perform`:** `.tab` maps to `compact(on:)`. The rest is as in part 1. The "Time's up" and battery-clock hooks run only on the alert screen's stage.
- **Pointer:** one `PointerWatcher` sends every move to every stage, with `zone` set to `NotchGeometry.hoverZone(screenFrame:)` for monitors when `monitors.enabled`, and `nil` otherwise.
- **Settings:** changes to `MonitorSettings` (`objectWillChange`) call `evaluate()`.
- **Glow colour:** set on every stage's presenter (the part 1 fix).

- [ ] **Step 1: Write the failing tests,** using a `FakePresenter: NotchPresenting` that records calls and has a settable `isHovering`:
  - `stageAppliesLatestMode`: apply `.idle`, then `.idleExpanded`, before the first finishes → the fake's last call is `expand`, and `applied == .idleExpanded`
  - `hoverZoneStartsHoverAfterDwell`: on a stage with desired `.hidden` (a monitor), `pointerMoved(to: zone.center, zone: zone)` → `hoverExpanded` is false at once and true after 0.35 s, and the callback fired
  - `leavingClosesAfterDelay`: then `pointerMoved(to: far away, zone: zone)` → still true at 0.3 s, false by 0.6 s
  - `screensRebuiltOnDisplayChange`: make `NotchController` stage-building testable as `static func stageIDs(for screens: [ScreenInfo], current: [Int]) -> (add: [Int], remove: [Int])`; [1, 2] with current [1, 3] → add [2], remove [3]

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchStageTests`. Expected: "cannot find 'NotchStage'".

- [ ] **Step 3: Implement** `NotchStage`, the protocol conformance, `MonitorTabView`, and the controller changes described above. Remove the controller's single-presenter fields and the temporary watcher from Task 1.

- [ ] **Step 4: Run them to see them pass,** then run `swift test` (all pass) and `./build.sh`.

- [ ] **Step 5: Update the README features list** with one short paragraph: on a monitor, hover the top centre; there's a small tab while music or a timer runs; alerts follow the active app; there are two switches in Settings → Features. Write it in plain UK English with full sentences.

- [ ] **Step 6: Commit** with the message "Show Mantel on monitors: per-screen stages, tab and alerts on the active screen".

### Task 6: Check on the real Mac with the monitor

Done with the owner, using `screencapture -x -R` on each screen's top centre. Quit the installed Mantel first, run `build/Mantel.app`, and use `NOTCH_FAKE_SPOTIFY=1` where noted.

- [ ] **Step 1:** Monitor idle with nothing playing. Expected: nothing at the top.
- [ ] **Step 2:** With fake music, expected: the laptop shows the side pieces and the monitor shows the tab with art and song. Start a 5-minute timer: the tab adds the amber dot and time.
- [ ] **Step 3:** Owner hovers the monitor's top centre. Expected: the panel drops down with the flash. Only one panel is open at a time, even when hovering the laptop notch right after (Review Focus 1). Open a menu bar menu on the monitor and rest the pointer at the top: no fight with the menu (Review Focus 3).
- [ ] **Step 4:** Alerts follow the active app. Run `NOTCH_FAKE_BATTERY=1` with a window focused on the monitor: the battery tab appears there. Focus a laptop window: the next flash shows at the notch.
- [ ] **Step 5:** Switches. Turn the tab off: hover still works, with no tab. Turn monitors off: nothing on the monitor; alerts go to the notch.
- [ ] **Step 6: Lid close and reopen** (Review Focus 4), with music playing. Expected: nothing stuck. The tab moves to or stays on the monitor, and the laptop pieces come back when it opens.
- [ ] **Step 7: Full-screen app on the monitor** (Review Focus 5). If hovering the top fights the menu bar, add this rule with a test first: `ActiveScreen.isFullScreen(windowBounds:screenFrame:)` is true when the window equals the screen frame. While true for the monitor's front window, that monitor's zone is `nil` and its alerts go to the notch screen. Tell the owner and update the README line.
- [ ] **Step 8:** Paste after clicking a clipboard row, on the monitor's panel. Click menu bar items beside an open panel on the laptop, with the panel opened by hovering then moved off within the leave delay.
- [ ] **Step 9:** Tune values if needed, re-run `swift test`, and commit "Tune monitor tab and hover on real hardware". Write down anything not checked.
