# Developing Mantel

This is for anyone working on Mantel's code. The [README](../README.md) covers installing and using the app.

Don't change the app's ID, `local.mantel.app`. Changing it resets the app's permissions and stops installed copies from accepting updates. The repository was renamed from `notch`, and GitHub redirects the old name, so never create a new repository called `notch` on this account.

## Building and testing

You need Xcode 16 or later. `swift build` builds the app for development and `swift test` runs the tests. To get a proper app bundle, run `./build.sh`, which creates `build/Mantel.app` signed for local use only.

```sh
swift build
swift test
./build.sh
```

The tests that talk to GitHub or need a signed build are skipped unless you ask for them. They're described at the top of `Tests/MantelTests/UpdateEndToEndTests.swift`.

## Trying things without the real thing

A couple of environment variables let you see features without setting them up for real. `MANTEL_FAKE_SPOTIFY=1` plays a made-up song instead of talking to Spotify, and `MANTEL_FAKE_BATTERY=1` pretends you plugged in and then dropped to 20%.

```sh
MANTEL_FAKE_SPOTIFY=1 build/Mantel.app/Contents/MacOS/Mantel
MANTEL_FAKE_BATTERY=1 build/Mantel.app/Contents/MacOS/Mantel
```

## Screenshots and icons

The README screenshots are drawn from the app's own views with made-up data. After changing how something looks, regenerate them with:

```sh
MANTEL_FAKE_SPOTIFY=1 MANTEL_SCREENSHOTS_DIR=docs/images swift test --filter Screenshots
```

The app icon is drawn in code. Run `swift scripts/make-app-icon.swift` from the repository root to rebuild `Resources/AppIcon.icns` and the preview in `docs/images/app-icon.png`. The menu bar icon is drawn in `Sources/Mantel/MenuBarIcon.swift`.

## Releasing

Releases come from the Release workflow on GitHub. Open Actions, choose Release, click Run workflow, leave it on `main` and type the new version, for example `1.6.0`. The version has to be higher than the last one, or installed copies won't pick it up. The workflow runs the tests, builds the app for Apple Silicon and Intel, signs it, checks that the zip will be accepted as an update, tags the commit and publishes the release. You can also start it from Terminal with `gh workflow run Release --ref main -f version=1.6.0`.

If a run fails before publishing, nothing has been released, so fix the problem and run it again with the same version. If it fails while uploading, delete any leftover draft on the Releases page first.

## Signing

Every release is signed with the same self-signed certificate. That's what lets macOS keep Mantel's permissions across updates, and it's how an installed copy knows an update really came from here. The workflow reads the certificate from two repository secrets, `MANTEL_SIGNING_P12` (the .p12 file, base64 encoded) and `MANTEL_SIGNING_PASSWORD`, and checks that the build is signed by the certificate with SHA-1 `e860aba5c846e315bae3f058b509d31c776ba0d7`.

Don't replace that certificate. Installed copies only accept updates signed with it, so a new one would mean everyone reinstalling by hand and allowing permissions again. Local builds made with `./build.sh` are signed ad hoc and never update themselves.
