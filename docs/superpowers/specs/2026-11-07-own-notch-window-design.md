# Mantel's own notch window, new animation and monitor support

Date: 7 Nov 2026. Status: approved by the owner on 7 Nov 2026.

## Why

Mantel draws everything through DynamicNotchKit 1.1.0, an outside library (MIT, about 1,600 lines). Only `NotchController.swift` uses it. Two problems:

1. **Risk.** If a macOS update breaks the library, Mantel waits on someone else's fix.
2. **It can't do what we want next.** On screens without a notch, the library has no small resting state, so on a monitor Mantel only "peeks" briefly at a new song. The hover panel, clipboard and timer can't be reached there.

The owner chose to write Mantel's own window rather than copy the library in. Ideas can be taken from it, but its code isn't copied. It's also a chance to change the animation.

## Goals

- Remove DynamicNotchKit completely (`Package.swift`, `Package.resolved`, imports, and the README line that says Mantel is built on it). The owner chose no credit line.
- On the laptop's notch, everything works as it does today, apart from the new animation.
- New open/close animation: "E · Snap with a flash" (details below).
- Mantel works on screens without a notch (monitors), via an invisible hover area at the top centre and a small black tab.
- Two new switches in Settings.
- The "what the notch shows" rules move into a separate, tested piece (the review tidy-up item from before).

## Non-goals

- No new features inside the panel. The tabs, music card, meeting card, clipboard, timer and battery views stay as they are.
- No changes to updates, signing or the release workflow.
- No keyboard shortcut for the clipboard (a separate weakness, for later).

## Anti-goals (a failure even if it technically works)

- A fake black notch drawn on the monitor when nothing is happening.
- Mantel stealing keyboard focus. ⌘V after clicking a clipboard row must still paste into the app you were in.
- Mantel blocking clicks on the menu bar or on windows, outside the visible black shape and the small hover area.
- Asking for any new macOS permission.
- The panel flickering or flashing on every small change.

## What the owner decided

### Animation: "E · Snap with a flash"

The approved mockup is `.superpowers/brainstorm/*/content/animation-v2.html`, card E. Its values are the reference:

- **Opening** takes about 0.22 s, with a fast ease-out curve (`cubic-bezier(.2,0,0,1)`) and no overshoot, bounce or blur. The black shape grows from the notch to the panel size. In the first ~15% of the movement, an amber flash lights up at the notch edge (a bright amber shadow), then settles into the soft amber glow behind the panel. Content slides up about 6 pt and fades in, finishing just after the shape lands.
- **Closing** takes about 0.17 s, with an ease-in curve. Content fades first, then the shape shrinks back into the notch, and the glow goes out.
- The **same crisp style** is used for every shape change: hidden, small side pieces and full panel.
- The **flash only plays when opening from nothing** (hidden to panel, or hidden to a meeting/alert). Going from the side pieces to the panel, or switching tabs, has no flash.
- On the Music tab, when album colours are on, the flash and glow use the album colour instead of amber, matching today's tab glow.
- The battery sweep and "Time's up" stay exactly as they are.

### Monitors (screens without a notch)

- **No fake notch.** When nothing is happening, the top of the monitor is empty.
- **Hover the top centre** to open the full panel, which drops down from the top edge with the same animation. It has the same size and look as on the laptop, with rounded bottom corners.
- **A small black tab** hangs from the top centre while music plays, a timer runs, or both. It shows album art, the song title and the time left (the approved mockup is `monitor-idle.html`, option 4). It follows the same rules as the laptop's side pieces, so pausing the music hides it just as it does today.
- **Alerts** (meeting countdown, "Time's up", battery) appear on the screen of the active app: on the laptop's notch if the front app is there, or at the top centre of the monitor if it's there.
- Works on every screen without a notch at once. Only one panel is ever open, on the screen being hovered.
- The laptop screen works exactly as now.
- This replaces today's six-second "peek" on screens without a notch.

### Settings → Features, new "Monitors" section

- **Use Mantel on screens without a notch.** On by default. Off means the monitor never shows Mantel: no hover, no alerts, no tab. Alerts then go to the laptop's notch, as they do today. **One exception (owner's decision):** when no screen has a notch (for example, lid closed), meeting countdowns still appear at the top centre of the main screen, because missing a meeting is worse. That's today's behaviour. Nothing else shows in that case.
- **Show a small tab while music or a timer runs.** On by default. It's indented under the first switch and greyed out when that one is off. Off means hovering and alerts still work, but there's no tab.

## What the library does today, which the new window must keep

1. **The window.** A borderless, non-activating `NSPanel` at `.screenSaver` level, on all Spaces, stationary, clear background, no system shadow. It can become key (so the panel can take typing if ever needed), and Mantel sets `becomesKeyOnlyIfNeeded = true` after every show.
2. **Click-through.** Only the black shape takes clicks. Everything else in the window lets clicks through.
3. **Notch size.** Measured from `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` and `safeAreaInsets.top`. A screen "has a notch" when both areas exist.
4. **The shape.** The top corners curve outwards into the menu bar and the bottom corners are rounded. Compact radii are top 6, bottom 14; expanded radii are top 15, bottom 20. The corner radii animate.
5. **The side pieces.** Leading and trailing views beside the notch, each measured. The shape shifts sideways by half their width difference, so the notch stays centred over the camera.
6. **Hover.** It's reported when the pointer is over the black shape. While hovering the compact notch, it grows to the menu bar height. The shadow deepens on hover (0.8 opacity, radius 20; otherwise 0.5/10 when expanded, none when compact).
7. **Hiding waits for the pointer.** A hide is held off while the pointer is still over the shape.
8. **The idle state.** An empty notch-sized black shape sits exactly over the real notch, so hovering the notch works when nothing is playing.
9. **Screen changes.** When displays change (plugging in a monitor, changing resolution), the window is rebuilt for the new layout.
10. **Fades.** The window fades in over 0.15 s when shown and fades out over 0.15 s after the closing animation. The new design may drop these if the shape animation already hides any glitches.

The controller's own timing stays the same: hover dwell 0.3 s, leave delay 0.5 s, battery flash 3 s, the battery clock starting once the compact view is on screen, music polling only while the panel is open, and "Time's up" timing starting when it's actually shown. Today the library hides the notch between the side pieces and the panel (a 0.25 s gap). The new window changes shape directly instead.

## Constraints

- macOS 14 or later, Swift/SwiftUI, SwiftPM, built by `build.sh`. No new dependencies.
- No new permissions. Finding the active app's screen must work without Screen Recording or Accessibility (for example, window bounds from `CGWindowListCopyWindowInfo`, which don't need permission, or the screen with the mouse as a fallback).
- Hover on monitors must not need Accessibility either.
- The app ID `local.notch.app` and the signing setup don't change.
- Test-first for the logic. All existing tests keep passing.
- UK English in anything a user sees.

## The tidy-up: a tested decision piece

Move the decision rules out of `NotchController.evaluate()` into a pure type: inputs in, "what to show and on which screen" out. Today's order is battery flash > meeting > "Time's up" > music > idle. The new monitor rules are the switches, the tab, which screen gets alerts, and which screen gets the panel. Unit tests cover today's rules first (so the move is proven safe), then the new monitor rules. Screen geometry (notch frame, panel frame, hover area) also becomes pure functions of plain numbers, so it can be tested without a real screen.

## Calls I made (the owner can overrule)

- **Two parts, in order.** Part 1: our own window plus the new animation, on the laptop only, behaving exactly as today. Part 2: monitor support and the two switches. Each part is finished and tested on its own, and I'll ask before releasing either.
- **Battery alerts on a monitor** show as the small tab with the same sweep, for 3 s, even when the tab switch is off, because they're alerts and alerts always show.
- **Full-screen apps on a monitor.** The top edge also brings down the macOS menu bar there. I'll test it. If the two clash, Mantel stays out of full-screen apps on the monitor (alerts included) and the README says so.
- **What the tab shows.** Music and timer: album art, song title and time left. Music only: album art and song title. Timer only: the amber dot and time left. It respects the existing "Show music card" and "Show album art" switches.
- **Hovering the tab** opens the panel, just like hovering the empty top centre.
- **Mockups folder.** `.superpowers/` goes into `.gitignore`.

## Left to the builder

- How the window is structured (one panel per screen, or one that moves), as long as the behaviour above holds.
- How hover on the monitor's top centre is detected (tracking area on a small invisible panel, or polling the pointer position), within the no-permission constraint.
- The exact hover area size. It's about the panel's width and a few points tall at the very top edge.
- Exact SwiftUI animation values that match the mockup on real hardware. Tuned with screenshots while the owner hovers.

## How it's checked

- Unit tests for the decision piece and the geometry.
- On the real Mac, with screenshots: notch idle, hover open/close, side pieces, meeting, battery flash, "Time's up". On the monitor: empty top, tab, hover open, alerts on the active screen, both switches.
- ⌘V after clicking a clipboard row.
- Unplugging and plugging in the monitor while Mantel runs.
- Anything that couldn't be tested gets said, not assumed.
