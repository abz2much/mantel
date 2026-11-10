# Mantel

<p align="center"><img src="docs/images/app-icon.png" width="128" alt="Mantel's icon: the notch resting on a warm brass shelf"></p>

Mantel is a small Mac app that lives in your MacBook's notch. It tells you when a meeting is about to start, shows what's playing on Spotify or Apple Music, keeps your last few copies close by, runs a timer, and lets you know when you plug in or your battery runs low. It's there so you're on time and don't miss anything.

<p align="center">
  <img src="docs/images/music-tab.png" width="480" alt="The panel open on the Music tab, with album art, a progress bar and controls">
</p>

## What it does

Five minutes before a meeting, the notch drops down with a countdown, and it comes back for the final minute. If the invite has a Google Meet, Zoom or Teams link, there's a Join button right there. Meetings you've declined are left out.

While music plays, a small cover sits beside the notch. Hover over the notch and a panel opens with four tabs: Today, Clipboard, Timer and Music. Today shows the rest of your meetings for the day. If you turn on reminders in Settings, it also lists reminders that are overdue or due today. Tick one to mark it done, or type in Add a reminder to make a new one, due today, in your default Reminders list. Clipboard lists the last ten things you copied, and clicking one puts it back on your clipboard so you can paste it. You can also press ⌃⌥V to open it from the keyboard, or pick your own shortcut in Settings. Use the arrow keys and Return, or press 1 to 9, to copy an item, then paste it with ⌘V. Esc closes the panel. Timer runs a 5, 15, 25 or 45 minute countdown, and the 25 minute one is a focus session that offers you a short break when it ends. Music has the full player, with album art and a progress bar you can drag.

When you plug in, a green glow sweeps across the notch with your battery level. If you're running low, you get the same sweep in red at 20% and again at 10%.

<table>
  <tr>
    <td><img src="docs/images/meeting.png" alt="A meeting reminder counting down to a Zoom call, with a Join button"></td>
    <td><img src="docs/images/clipboard.png" alt="The Clipboard tab listing recent copies"></td>
  </tr>
  <tr>
    <td><img src="docs/images/timer-running.png" alt="The Timer tab with a 25 minute countdown"></td>
    <td><img src="docs/images/idle-panel.png" alt="The Today tab listing the rest of today's meetings"></td>
  </tr>
</table>

<sub>The screenshots are drawn from the app's own views using made-up data.</sub>

Mantel works on a monitor too. Move the pointer to the top centre of the screen and the same panel drops down. While music plays or a timer runs, a small black tab hangs there showing the song and the time left. Meeting reminders, battery alerts and the end of a timer appear on whichever screen the app you're using is on.

## Installing

You'll need macOS 14 Sonoma or later. Mantel works with the Spotify desktop app and with Apple Music.

1. Download the latest `Mantel-x.y.z.zip` from the [Releases page](https://github.com/abz2much/mantel/releases/latest) and open it.
2. Drag Mantel to your Applications folder and open it.
3. macOS will block it the first time, because Mantel isn't from the App Store. Go to System Settings, then Privacy & Security, scroll down and click Open Anyway. You need to do this within an hour of trying to open it.
4. Mantel then asks for a couple of permissions. Calendar access lets it read your meetings, and it never changes them. Permission to control Spotify or Music lets it show the current song and handle play, pause and skip.

Mantel adds itself to your login items the first time it runs, so it starts whenever you log in.

### Updates

Mantel keeps itself up to date. It checks this repository's releases in the background, installs new versions and reopens, and your permissions carry over. No GitHub account is needed. You can also check by hand at any time from the menu.

## Settings

The menu bar icon gives you the update status, a way to check for updates, Settings and Quit. If something needs your attention, like calendar access being turned off, a warning with a button to fix it appears at the top.

In Settings you can choose whether Mantel opens at login and installs updates automatically. You can also turn the music card, album art, battery alerts, clipboard history and its shortcut on or off, change that shortcut, pick which calendars to watch, and choose whether to show reminders and from which lists. Under Monitors you can stop Mantel appearing on screens without a notch, or keep it there but hide the small tab. With the lid closed and Mantel turned off for monitors, meeting reminders still appear, so you don't miss one.

## Privacy

Mantel only reads your calendar and never edits it. Reminders are off until you turn them on. Mantel then reads them, and only changes them when you tick one off or add one. It talks to Spotify and Music only while they're already open, and it never launches them. Clipboard history stays in memory, so it's gone when Mantel quits, and anything a password manager marks as private is skipped. Album art is off by default. When you turn it on, Spotify covers come from Spotify's image server and Apple Music covers come from the Music app itself. Update checks ask GitHub for the latest release, which shares your IP address with GitHub like any download. Nothing else leaves your Mac, and song titles are never written to logs.

## Troubleshooting

If macOS says Mantel is damaged and can't be opened, run this in Terminal and then open it again:

```sh
xattr -dr com.apple.quarantine /Applications/Mantel.app
```

If you said no to a permission by mistake, a warning appears in Mantel's menu with a button that takes you to the right page in System Settings.

## Building it yourself

You can build Mantel from source if you have Xcode 16 or later. The command line tools on their own aren't enough on recent versions of macOS.

```sh
git clone https://github.com/abz2much/mantel.git
cd mantel
./build.sh
```

That produces `build/Mantel.app`. Testing, debugging tricks and how releases work are covered in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Licence

MIT. See [LICENSE](LICENSE).
