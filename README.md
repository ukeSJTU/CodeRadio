# CodeRadio

A small, native macOS menu bar client for
[freeCodeCamp Code Radio](https://coderadio.freecodecamp.org/).

CodeRadio is built with SwiftUI and AVFoundation. It plays the official audio
stream directly and does not wrap the website in a web view.

> CodeRadio is an early-stage, unofficial community client and is not
> affiliated with or endorsed by freeCodeCamp.

## Features

- Lives in the macOS menu bar without a Dock icon.
- Shows the current song, artist, album artwork, listener count, and recent
  tracks.
- Uses a compact Native Pocket layout with play/stop and step volume controls.
- Uses native Liquid Glass controls on macOS 26 and a system-material fallback
  on macOS 14 and 15.
- Switches between the official 128 kbps and 64 kbps MP3 streams.
- Shows connecting, buffering, reconnecting, offline, and failed playback states.
- Retries temporary playback failures with bounded backoff and offers a manual
  **Retry** action when automatic recovery is exhausted.
- May temporarily use the 64 kbps stream during recovery without changing a
  saved 128 kbps preference.
- Refreshes station metadata automatically.
- Integrates with macOS media controls and Now Playing.
- Optionally launches when you log in using the native macOS login-item API.
- Runs inside App Sandbox with outgoing network access only.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 26 or later when building from source.

## Install

Prebuilt GitHub Releases and a Homebrew Cask are planned but are not available
yet. For now, build the app from source.

```sh
git clone https://github.com/ukeSJTU/CodeRadio.git
cd CodeRadio
open CodeRadio.xcodeproj
```

In Xcode:

1. Select the `CodeRadio` scheme.
2. Select `My Mac` as the destination.
3. Press Command-R.
4. Find the radio icon on the right side of the macOS menu bar.

The app intentionally does not open a normal window or appear in the Dock.

## Usage

Click the menu bar icon to open the player. The compact player contains the
current track, progress, playback, volume, and a collapsed recent-tracks list.
Use the ellipsis button in the top-right corner for secondary options.

From the popover you can:

- Start or stop the stream and change the volume from the control island.
- Expand **Recently played** to see the previous three tracks.
- Change stream quality from the ellipsis menu.
- Refresh metadata or open the official Code Radio website from that menu.
- Enable **Launch at Login** from that menu.
- Quit the application.

Stopping playback cancels pending recovery. If the network goes offline while
playback is active, CodeRadio keeps the play request and resumes automatically
after connectivity returns. The menu-bar icon and popover show the observed
playback state rather than treating a Play click as immediate success.

If macOS requires approval for Launch at Login, the ellipsis menu adds an
**Approve in System Settings…** action that opens **System Settings → General →
Login Items & Extensions**.

When running from Xcode, the login item points to the development build in
DerivedData. Use this only for testing and disable it before deleting
DerivedData. Installed release builds should live in `/Applications`.

## Build and Test from the Command Line

```sh
xcodebuild build \
  -project CodeRadio.xcodeproj \
  -scheme CodeRadio \
  -configuration Debug \
  -destination 'platform=macOS'

xcodebuild test \
  -project CodeRadio.xcodeproj \
  -scheme CodeRadio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:CodeRadioTests \
  CODE_SIGNING_ALLOWED=NO
```

Contributor conventions are documented in [AGENTS.md](AGENTS.md). Settled
product behavior and release scope live in
[docs/product-design.md](docs/product-design.md).

## Privacy

CodeRadio does not require an account and does not include analytics. It makes
network requests only to the official Code Radio website, metadata endpoint,
audio streams, and artwork URLs supplied by that metadata.

The app requests no file, microphone, camera, contacts, location, or other
personal-data permissions.

## Roadmap

See [docs/product-design.md](docs/product-design.md) for the product roadmap and
the boundary between the first public release and later work.

## Contributing

Issues and pull requests are welcome. Before submitting a change, make sure the
project builds, unit tests pass, and menu bar or playback changes receive a
short manual smoke test.
