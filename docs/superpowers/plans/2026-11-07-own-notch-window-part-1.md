# Own notch window, part 1: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace DynamicNotchKit with Mantel's own notch window and the "E · Snap with a flash" animation, with the laptop notch behaving exactly as today.

**Architecture:** The decision rules move out of `NotchController.evaluate()` into a pure `NotchDecision`, and the notch geometry into a pure `NotchGeometry`, both unit-tested. A new `NotchPresenter` owns one click-through `NSPanel` and a SwiftUI `NotchSurface`. It offers the same `expand/compact/hide` + `isHovering` surface the controller uses from the library today, so the controller change is a swap. Part 2 (monitors) builds on these pieces and isn't in this plan.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, SwiftPM, Swift Testing, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-07-own-notch-window-design.md`

## Global Constraints

- macOS 14 or later, no new dependencies, no new permissions.
- App ID `local.notch.app` and signing unchanged.
- Test-first for logic. All 135 existing tests keep passing (`swift test`).
- Controller timings unchanged: hover dwell 0.3 s, leave delay 0.5 s, battery flash 3 s, peek 6 s.
- Window: borderless, `.nonactivatingPanel`, level `.screenSaver`, `[.canJoinAllSpaces, .stationary]`, clear, no system shadow, `canBecomeKey` true, `becomesKeyOnlyIfNeeded = true`.
- Shape radii: compact top 6 / bottom 14, expanded top 15 / bottom 20.
- Animation E: open 0.22 s `timingCurve(0.2, 0, 0, 1)`; close 0.17 s `timingCurve(0.4, 0, 1, 1)`; no bounce, no blur.
- Commit messages carry no AI attribution.

## Review Focus

1. **Hover flicker at the edge.** The compact shape grows to menu bar height on hover. The pointer must not cause an enter/exit loop at the bottom edge. Expected: one enter and one exit per real move. Checked by hand in Task 6, step 3.
2. **Hovering in and out mid-animation.** Quick in/out while it opens or closes must end in the right final state, with no stuck open panel. Expected: it settles to the latest wanted state. Covered by `presenterEndsInLatestState` (Task 4) plus a hand check.
3. **Displays changing while shown.** Plugging or unplugging a monitor, or changing resolution, while the notch is showing. Expected: it reappears at the notch, not mid-screen or on the wrong display. Checked by hand in Task 6, step 6.
4. **Clicks outside the black shape.** Menu bar items beside the notch and windows under the large transparent panel. Expected: they get every click. Covered by `hitAreaIsOnlyTheShape` (Task 4) plus a hand check.
5. **Keyboard focus.** ⌘V right after clicking a clipboard row. Expected: it pastes into the app that was in front. Checked by hand in Task 6, step 5.

---

### Task 1: Tested decision rules (`NotchDecision`)

Moves today's rules out of `evaluate()` unchanged and proves them with tests.

**Files:**
- Create: `Sources/Notch/NotchDecision.swift`
- Create: `Tests/NotchTests/NotchDecisionTests.swift`
- Modify: `Sources/Notch/NotchController.swift` (private `Mode` enum and the mode-picking part of `evaluate()`)

**Interfaces:**
- Produces:
  - `enum NotchMode: Equatable { case hidden, musicCompact, musicExpanded, idle, idleExpanded, meeting, battery, timerDone }`
  - `struct NotchInputs: Equatable { var hasReminder, musicShowsCard, screenHasNotch, hoverExpanded, peeking, timerDoneShowing, batteryFlashing: Bool }`. Every field defaults to `false`.
  - `enum NotchDecision { static func mode(for: NotchInputs) -> NotchMode; static func keepsHoverExpanded(_: NotchInputs) -> Bool }`. The second returns false whenever today's code sets `hoverExpanded = false`: a reminder, "Time's up", or no notch with no music.

- [ ] **Step 1: Write the failing tests** in `NotchDecisionTests.swift`, one `@Test` each:
  - `batteryBeatsEverything`: all flags true → `.battery`
  - `meetingBeatsMusicAndHover`: hasReminder, musicShowsCard, screenHasNotch, hoverExpanded → `.meeting`
  - `timeIsUpBeatsMusic`: timerDoneShowing, musicShowsCard, screenHasNotch → `.timerDone`
  - `meetingBeatsTimeIsUp`: hasReminder, timerDoneShowing → `.meeting`
  - `musicCompactOnNotch`: musicShowsCard, screenHasNotch → `.musicCompact`
  - `musicExpandedWhenHovered`: plus hoverExpanded → `.musicExpanded`
  - `idleNotchWhenNothingPlays`: screenHasNotch → `.idle`; plus hoverExpanded → `.idleExpanded`
  - `peekWithoutNotch`: musicShowsCard, peeking → `.musicExpanded`; without peeking → `.hidden`
  - `hiddenWithoutNotchOrMusic`: all false → `.hidden`
  - `hoverResetRules`: `keepsHoverExpanded` is false for hasReminder, for timerDoneShowing, and for no notch with no music; true for screenHasNotch + hoverExpanded

- [ ] **Step 2: Run them to see them fail**
  Run `swift test --filter NotchDecisionTests`. Expected: build failure, "cannot find 'NotchDecision' in scope".

- [ ] **Step 3: Implement `NotchDecision.mode(for:)` and `keepsHoverExpanded(_:)`**, copying the order from `evaluate()`: battery > meeting > timerDone > music (notch: compact/expanded by hover; no notch: expanded while peeking, else hidden) > idle (notch) > hidden.

- [ ] **Step 4: Run them to see them pass**
  Run `swift test --filter NotchDecisionTests`. Expected: all pass.

- [ ] **Step 5: Make `evaluate()` build `NotchInputs` and call `NotchDecision`**
  Delete the private `Mode` enum (use `NotchMode`). Keep the reminder bookkeeping (`state.event`, `currentReminder`, `dismissed` pruning) in the controller.

- [ ] **Step 6: Check nothing else changed**
  Run `swift test` (expected: 135 + new tests pass) and `./build.sh` (expected: builds).

- [ ] **Step 7: Commit** with the message "Move notch decision rules into a tested NotchDecision".

### Task 2: Tested geometry (`NotchGeometry`)

**Files:**
- Create: `Sources/Notch/NotchGeometry.swift`
- Create: `Tests/NotchTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:
  - `struct NotchMetrics: Equatable { let notchSize: CGSize; let menubarHeight: CGFloat; let hasNotch: Bool }`
  - `enum NotchGeometry`, with:
    - `static func metrics(screenFrame: CGRect, visibleFrame: CGRect, leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?, topInset: CGFloat) -> NotchMetrics`
    - `static func windowFrame(screenFrame: CGRect) -> CGRect`
    - `static func compactOffset(leading: CGFloat, trailing: CGFloat) -> CGFloat`
  - `extension NSScreen { var notchMetrics: NotchMetrics }`, a thin wrapper that passes the real values in.

- [ ] **Step 1: Write the failing tests:**
  - `notchFromAuxiliaryAreas`: frame 0,0,1512,982; aux widths 650 and 650; topInset 32 → notchSize 212×32, hasNotch true
  - `noNotchWithoutAuxiliaryAreas`: aux nil → hasNotch false, notchSize 0 × menubarHeight
  - `menubarHeightFromVisibleFrame`: frame maxY 982, visible maxY 958 → 24
  - `windowIsTopCentreHalfScreen`: frame 0,0,1512,982 → 378,491,756,491
  - `windowOnSecondScreenUsesItsOrigin`: frame 1512,−200,1920,1080 → x 1992, y 340, 960×540
  - `compactOffsetCentresOverCamera`: (40, 60) → 10; (60, 40) → −10

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchGeometryTests`. Expected: "cannot find 'NotchGeometry'".

- [ ] **Step 3: Implement.** The notch width is `screenFrame.width − left − right`, the height is `topInset`, and the offset is `(trailing − leading) / 2`. The window is half the screen's width and height, centred, touching the top.

- [ ] **Step 4: Run them to see them pass.** Run `swift test --filter NotchGeometryTests`. Expected: all pass.

- [ ] **Step 5: Commit** with the message "Add tested notch geometry".

### Task 3: Shape and motion (`NotchShape`, `NotchMotion`)

**Files:**
- Create: `Sources/Notch/NotchShape.swift`
- Create: `Sources/Notch/NotchMotion.swift`
- Create: `Tests/NotchTests/NotchShapeTests.swift`

**Interfaces:**
- Produces:
  - `struct NotchShape: Shape { var topRadius: CGFloat; var bottomRadius: CGFloat }`, with `animatableData` as `AnimatablePair(topRadius, bottomRadius)`. The top corners curve outwards (quad curves into the top edge), and the bottom corners are rounded, as in the spec item 4.
  - `enum NotchPresentation: Equatable { case hidden, compact, expanded }`
  - `enum NotchMotion`, with:
    - `static let open: Animation`: 0.22 s, `timingCurve(0.2, 0, 0, 1)`
    - `static let close: Animation`: 0.17 s, `timingCurve(0.4, 0, 1, 1)`
    - `static let openDuration: TimeInterval = 0.22` and `static let closeDuration: TimeInterval = 0.17`
    - `static let flashLead: TimeInterval = 0.033`, which is 15% of the opening
    - `static func flashes(from: NotchPresentation, to: NotchPresentation) -> Bool`
    - `static func radii(for: NotchPresentation) -> (top: CGFloat, bottom: CGFloat)`: compact and hidden give 6/14, expanded gives 15/20

- [ ] **Step 1: Write the failing tests:**
  - `flashOnlyWhenOpeningFromNothing`: hidden→expanded true, hidden→compact true, compact→expanded false, expanded→compact false, expanded→hidden false
  - `radiiMatchSpec`: compact (6, 14), expanded (15, 20)
  - `shapeFillsRectBottomAndInsetsTop`: a path in 0,0,200,100 with radii 15/20 has bounds equal to the rect; it contains (100, 99); it doesn't contain (2, 50), because that point is outside the top-corner inset

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchShapeTests`. Expected: "cannot find 'NotchMotion'".

- [ ] **Step 3: Implement both files.**

- [ ] **Step 4: Run them to see them pass.**

- [ ] **Step 5: Commit** with the message "Add notch shape and E animation values".

### Task 4: The window and presenter (`NotchPresenter`)

**Files:**
- Create: `Sources/Notch/NotchPresenter.swift`, containing `NotchPanel` (NSPanel subclass), `NotchHostingView` (hit-test filter) and `NotchPresenter`
- Create: `Sources/Notch/NotchSurface.swift`, the SwiftUI view
- Create: `Tests/NotchTests/NotchPresenterTests.swift`

**Interfaces:**
- Consumes: `NotchMetrics`, `NotchGeometry.windowFrame`, `NotchGeometry.compactOffset`, `NotchShape`, `NotchMotion`, `NotchPresentation`.
- Produces:
  - `@MainActor final class NotchPresenter<Expanded: View, Leading: View, Trailing: View>: ObservableObject`, with:
    - `init(expanded: @escaping () -> Expanded, leading: @escaping () -> Leading, trailing: @escaping () -> Trailing, glow: @escaping () -> Color)`
    - `@Published private(set) var isHovering: Bool`
    - `@Published private(set) var presentation: NotchPresentation`
    - `func expand(on: NSScreen) async`
    - `func compact(on: NSScreen) async`
    - `func hide() async`
    - `var window: NSPanel?`
  - `static func shapeRect(presentation:metrics:contentSize:windowSize:) -> CGRect`, a pure function used by the hit test

Behaviour to build. Each item maps to a spec item in "What the library does today":
- **The window** (spec items 1 and 9): built on show, sized by `windowFrame`, closed on hide, and rebuilt on `NSApplication.didChangeScreenParametersNotification` when not hidden.
- **Click-through** (item 2): `NotchHostingView.hitTest` returns nil outside `shapeRect`.
- **Hover** (item 6): `.onHover` on the shape area sets `isHovering`. While compact and hovered, the shape's height becomes `menubarHeight`. Shadow: hovered 0.8/20, expanded 0.5/10, compact none.
- **Hiding waits** (item 7): `hide()` waits in 0.1 s steps while `isHovering`.
- **Idle and compact** (items 5 and 8): the leading and trailing views are measured with `onGeometryChange`, and the shape is offset by `compactOffset`. With no side content, the shape is exactly the notch size.
- **Direct changes:** compact↔expanded animates the shape straight to the new state with `NotchMotion.open`, with no hide in between and no flash.
- **Flash:** when `NotchMotion.flashes` is true, `glow()` drives a shadow that goes to 0.9 opacity, radius 18, within `flashLead`, then eases to 0.35/30 by the end of the opening. The expanded content slides up 6 pt and fades in over `openDuration × 1.4`, starting at 40% of the way. Closing fades the content over `closeDuration × 0.5` first.
- **Waiting:** each async call returns after its duration (`openDuration` or `closeDuration`), so the controller's `reconcile()` loop keeps working.

- [ ] **Step 1: Write the failing tests:**
  - `hitAreaIsOnlyTheShape`: for expanded content 404×220 in a 756×491 window, `shapeRect` is centred at the top and is 404 + 2×15 wide; a point 5 pt outside it isn't inside. For compact on a 212×32 notch with sides of 40 and 60, the rect is `212 + 40 + 60 + 2×6` wide, offset by 10.
  - `presenterEndsInLatestState`: on a fresh presenter, start `expand`, then immediately `compact`, then `hide` without awaiting the first two, and await the last. `presentation` ends as `.hidden` and `window` is nil. Use `NSScreen.screens[0]`. The test only reads state and doesn't depend on display contents.

- [ ] **Step 2: Run them to see them fail.** Run `swift test --filter NotchPresenterTests`. Expected: "cannot find 'NotchPresenter'".

- [ ] **Step 3: Implement `NotchPanel`, `NotchHostingView`, `NotchSurface` and `NotchPresenter`** as described above.

- [ ] **Step 4: Run them to see them pass,** then run the full `swift test`.

- [ ] **Step 5: Commit** with the message "Add Mantel's own notch window and presenter".

### Task 5: Switch over and remove the library

**Files:**
- Modify: `Sources/Notch/NotchController.swift`
- Modify: `Package.swift`, `Package.resolved`, `README.md:83`

**Interfaces:**
- Consumes: `NotchPresenter`, `NotchDecision`, `NSScreen.notchMetrics`.

- [ ] **Step 1: Swap `DynamicNotch` for `NotchPresenter`** in `start()`, with the same three view builders. `glow` returns `(state.tab == .music && state.content == .panel ? music.accent : nil) ?? MantelStyle.glow`. Hover is read from `presenter.$isHovering`. `keepKeyboardInFrontApp()` sets `becomesKeyOnlyIfNeeded` on `presenter.window`. `hasNotchInset` becomes `notchMetrics.hasNotch`. Remove `import DynamicNotchKit`.

- [ ] **Step 2: Remove the dependency.** Delete the `dependencies` entry and the target's product dependency from `Package.swift`, delete `Package.resolved` (no dependencies remain), and delete the README's "Mantel is built on DynamicNotchKit" line.

- [ ] **Step 3: Check it builds clean.**
  Run `grep -rn DynamicNotch Sources Package.swift README.md` (expected: no output). Then run `swift test` (expected: all pass) and `./build.sh` (expected: builds `build/Mantel.app`).

- [ ] **Step 4: Commit** with the message "Use Mantel's own notch window; remove DynamicNotchKit".

### Task 6: Check on the real Mac and tune

Done with the owner hovering, while screenshots are taken with `screencapture -x -R` of the top of the screen.

- [ ] **Step 1:** Quit the installed Mantel, then run `open build/Mantel.app`.
- [ ] **Step 2: Idle notch.** Screenshot it with nothing playing. Expected: nothing visible beyond the real notch.
- [ ] **Step 3: Hover opens and closes.** Owner hovers. Expected: it opens after the short wait, with an amber flash then the glow, and no bounce. It closes 0.5 s after leaving. Hover along the bottom edge of the compact notch and look for flicker (Review Focus 1). Quick in/out ends closed (Review Focus 2).
- [ ] **Step 4: Each mode.** Check music compact (side pieces centred over the camera), the music panel with an album-colour flash, a meeting (use a test event 5 min ahead in a test calendar), the battery flash (`NOTCH_FAKE_BATTERY`), and "Time's up" (a 5-minute timer, or the timer test hook if there is one).
- [ ] **Step 5: Focus and clicks.** Click a clipboard row, then press ⌘V in TextEdit. Expected: it pastes. Click menu bar items beside the notch. Expected: they open.
- [ ] **Step 6: Displays.** Plug in or unplug the monitor while the side pieces show. Expected: the notch is still right on the laptop.
- [ ] **Step 7: Tune** any value that looks off against `animation-v2.html` card E, re-run `swift test`, then commit "Tune notch animation on real hardware".
- [ ] **Step 8:** Write down anything that couldn't be checked, for the hand-over.
