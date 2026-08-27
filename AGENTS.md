# CodeRadio Agent Guide

## Project Purpose

CodeRadio is a native macOS menu bar client for
[freeCodeCamp Code Radio](https://coderadio.freecodecamp.org/). It should feel
like a small system utility: launch quietly, stay out of the Dock, expose the
essential playback controls in a compact popover, and require no embedded web
view.

The intended distribution path is GitHub Releases first and Homebrew Cask as
the primary installation method.

## Product Principles

- Keep the app native, lightweight, and focused on Code Radio.
- Prefer Swift, SwiftUI, AVFoundation, and Apple system frameworks.
- Do not embed the Code Radio website as the player UI.
- Keep the app menu-bar-only unless a dedicated Settings window is needed.
- Do not start audio automatically on first launch.
- Preserve App Sandbox compatibility and request only necessary entitlements.
- Support macOS 14 and later unless a feature has a strong reason to raise the
  deployment target.
- Make playback failures understandable and recoverable.
- Treat accessibility, keyboard control, and VoiceOver labels as product
  requirements rather than optional polish.

## Current Architecture

- `CodeRadio/CodeRadioApp.swift`
  - SwiftUI app entry point.
  - Owns the shared `CodeRadioPlayer` instance.
  - Presents a window-style `MenuBarExtra`.
- `CodeRadio/PlayerPopoverView.swift`
  - Menu bar popover UI.
  - Shows metadata, artwork, listeners, playback controls, stream quality,
    recent songs, refresh, website, and quit actions.
- `CodeRadio/CodeRadioPlayer.swift`
  - `@MainActor` observable playback model.
  - Owns `AVPlayer`, metadata refresh, user defaults, remote media commands,
    fallback behavior, and system now-playing information.
- `CodeRadio/CodeRadioModels.swift`
  - API response and stream quality models.
- `CodeRadioTests/CodeRadioTests.swift`
  - Swift Testing unit tests.

The Xcode project uses a file-synchronized source group, so Swift files placed
under `CodeRadio/` are normally included in the app target automatically.
Always verify Target Membership if Xcode cannot resolve a newly added type.

## External Services

- Station metadata:
  `https://coderadio-admin-v2.freecodecamp.org/api/nowplaying_static/coderadio.json`
- 128 kbps fallback stream:
  `https://coderadio-admin-v2.freecodecamp.org/listen/coderadio/radio.mp3`
- 64 kbps fallback stream:
  `https://coderadio-admin-v2.freecodecamp.org/listen/coderadio/low.mp3`
- Website: `https://coderadio.freecodecamp.org/`

Prefer mount URLs returned by the metadata endpoint. Keep fallback URLs for
startup and temporary metadata failures. Never add secrets for these public
endpoints.

## Build and Test

Open `CodeRadio.xcodeproj` in Xcode, select the `CodeRadio` scheme and `My Mac`,
then run with Command-R. The app does not open a normal window; inspect the
right side of the macOS menu bar.

Command-line verification:

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

Before committing, run `git diff --check` and at least the unit-test command.
For playback or menu bar changes, also launch the app and perform a short
manual smoke test.

## Implementation Guidelines

- Keep UI state in observable models instead of duplicating it across views.
- Perform UI and `AVPlayer` state changes on the main actor.
- Use structured concurrency for polling and network requests.
- Ensure long-running tasks are cancellable and do not create duplicate loops.
- Decode API responses defensively because upstream metadata can be incomplete.
- Persist only user preferences such as volume and stream quality.
- Use `OSLog` for diagnostics; do not use persistent ad-hoc log files.
- Avoid force unwraps except for static, developer-controlled URL literals.
- Keep user-facing strings concise and ready for localization.
- Add unit tests for model decoding and non-UI state transitions.
- Do not commit `xcuserdata`, DerivedData, archives, signing certificates, or
  notarization credentials.
- Do not hand-edit `project.pbxproj` unless an Xcode setting cannot reasonably
  be changed through Xcode or a deterministic project-editing tool.

## Target Configuration Invariants

The application target should remain configured with:

- macOS as the only supported platform.
- macOS 14.0 as the minimum deployment target.
- App Sandbox enabled.
- Outgoing network connections enabled.
- Hardened Runtime enabled for distributable builds.
- `LSUIElement = YES` so the app does not appear in the Dock.
- No file, microphone, camera, location, or other unrelated entitlements.

## Roadmap

### 1. Playback Reliability

- Observe `AVPlayer.timeControlStatus` instead of treating a `play()` call as
  proof that audio has started.
- Expose buffering, playing, stopped, offline, and failed states in the UI.
- Add retry with bounded backoff for temporary stream failures.
- Avoid switching quality recursively when a failed item emits repeated
  notifications.
- Add network reachability awareness and recover when connectivity returns.
- Add unit-testable playback state transitions behind a small abstraction.

### 2. Menu Bar Experience

- Add Launch at Login using `SMAppService`.
- Add a small Settings window for launch behavior, preferred quality, default
  volume, and optional automatic resume.
- Add keyboard shortcuts and improve VoiceOver descriptions.
- Replace generic artwork and status symbols with polished project branding.
- Decide whether the menu bar icon should visually indicate buffering/errors.
- Review layout with long track, artist, and album names.

### 3. System Integration

- Load artwork into `MPNowPlayingInfoCenter` without blocking the main actor.
- Confirm play/pause behavior from media keys and Control Center.
- Consider user notifications only for actionable prolonged outages; do not
  notify on normal song changes.

### 4. Quality

- Add decoding fixtures for missing or malformed metadata fields.
- Add tests for preference persistence and stream selection.
- Add a focused UI smoke test for launching the menu bar application.
- Add SwiftLint or SwiftFormat only if its configuration remains small and is
  enforced consistently in local development and CI.
- Add English and Simplified Chinese localization.

### 5. Release and Homebrew

- Create a proper AppIcon asset and settle the public app/bundle naming.
- Add a shared Xcode scheme suitable for CI.
- Add GitHub Actions for tests and release archives.
- Build universal release artifacts for Apple Silicon and Intel if practical.
- Sign with Developer ID, enable Hardened Runtime, and notarize release builds.
- Publish versioned zip artifacts and checksums in GitHub Releases.
- Create a Homebrew tap containing a `cask` for the signed/notarized app.
- Document installation, upgrading, uninstalling, privacy, and troubleshooting.

Apple Developer credentials and notarization secrets must be supplied through
local keychain or encrypted CI secrets and must never be committed.

## Definition of Done

A change is complete when it:

- Builds for the supported macOS deployment target.
- Keeps the app functional as a menu bar utility without an unintended Dock
  icon or main window.
- Preserves sandboxed network playback.
- Includes tests when behavior can be tested without real audio/network access.
- Has been manually smoke-tested when it changes playback or menu bar behavior.
- Updates this guide or user-facing documentation when it changes architecture,
  requirements, release steps, or roadmap status.
