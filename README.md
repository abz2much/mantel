# Notch

A small macOS menu bar app that puts your next meeting and what's playing on Spotify into the MacBook notch.

<p align="center">
  <img src="docs/images/music-card.png" width="480" alt="Expanded music card with album art, glow, progress bar and controls">
</p>
<p align="center">
  <img src="docs/images/meeting.png" width="560" alt="Meeting popup counting down to a Zoom call with a Join button">
</p>
<p align="center">
  <img src="docs/images/compact.png" width="320" alt="Compact view: a tiny album cover and waveform either side of the notch">
</p>

<sub>Screenshots are rendered from the app's own views with made-up data.</sub>

## Features

### Meeting countdown

- Pops out of the notch **5 minutes before** a meeting (for 10 seconds), then again for the **final minute**, staying up until a minute after the start.
- A ring drains as the meeting gets closer. The countdown turns orange in the last minute and red in the last 10 seconds.
- **Join button** for Google Meet, Zoom and Microsoft Teams links, found in the event's URL, location or notes. It pulses as the meeting starts.
- **✕ hides only the reminder showing**: dismiss the 5-minute one and you still get the final-minute one.
- Skips meetings you've **declined**, all-day events and cancelled events.
- When two meetings overlap, the one that **hasn't started yet** wins.
- Tinted with the **calendar's colour**, so work and personal meetings look different.
- Choose which calendars to watch from the menu bar.

### Spotify card

- A small cover (or music note) sits beside the notch while Spotify plays. **Hover** to open the full card.
- Title and artist, with long titles **scrolling** instead of being cut off.
- **Play/pause, next and previous.**
- **Progress bar you can click or drag** to jump to any point in the song.
- Optional **album art** with a **glow** and accent colours taken from the cover.
- Smooth transitions between songs; the cover sits back slightly when paused.
- Hides itself after 2 minutes paused, and when Spotify quits.

### Without a notch

On a Mac or display without a notch there's no compact view. The music card shows briefly whenever a song starts, and meeting reminders work as normal.

## Requirements

- macOS 14 Sonoma or later. Made for MacBooks with a notch, but works on any Mac.
- The **Spotify desktop app**, for the music card.
- **Xcode 16 or later** (or its command line tools) to build it.

## Install

Notch isn't on the App Store, so you build it from source. It takes about a minute.

```sh
git clone https://github.com/abz2much/notch.git
cd notch
./build.sh
```

This builds `build/Notch.app`. Move it to Applications and open it:

```sh
mv build/Notch.app /Applications/
open /Applications/Notch.app
```

A calendar-with-clock icon appears in the menu bar. There's no Dock icon.

### Permissions

On first launch macOS asks for two permissions:

- **Calendars**: to read your events. Notch never creates, changes or deletes them.
- **Automation → Spotify**: to show the current track and control playback. Asked the first time Spotify is running.

If you said no by accident, the menu bar menu has a shortcut to the right System Settings page.

Because the app is signed locally, macOS may ask for these permissions again after you rebuild.

### Start at login

Add Notch in **System Settings → General → Login Items**.

## Using it

Click the menu bar icon to:

- choose which **calendars** to watch;
- turn the **music card** on or off;
- turn **album art** on or off;
- quit.

## Privacy

- **Calendar access is read-only.**
- **Notch never launches Spotify** and only talks to it while it's already running.
- **Album art is off by default.** When on, Notch downloads each cover from Spotify's image server (`i.scdn.co`) only, with no cookies. Nothing else goes online.
- Song titles and artists are never written to logs.

## Development

```sh
swift build        # build
swift test         # run the tests
NOTCH_FAKE_SPOTIFY=1 build/Notch.app/Contents/MacOS/Notch   # fake playing track, no Spotify needed
NOTCH_FAKE_SPOTIFY=1 NOTCH_SCREENSHOTS_DIR=docs/images swift test --filter Screenshots   # regenerate the README screenshots
```

Built on [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit).
