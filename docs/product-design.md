# CodeRadio Product Design

This document is the source of truth for intended product behavior and release
scope. It describes the target product; source code and tests show what is
implemented today.

## Identity and scope

CodeRadio is a public, long-lived, native macOS client dedicated to freeCodeCamp
Code Radio. It is an independent, unofficial community project and must not imply
freeCodeCamp endorsement. `CodeRadio` names the client; `Code Radio` names the
station it plays.

The product stays single-station and account-free. It does not become a generic
radio directory, embed the website as its player, add on-demand history playback,
or collect analytics, telemetry, or third-party crash reports. GitHub Issues and
Pull Requests are the public support and contribution channels.

## Playback contract

- Every application launch, including Launch at Login, starts silently. Audio
  begins only after an explicit user action.
- The live stream has **play** and **stop** semantics. Starting after a stop joins
  the current live position; there is no resumable pause.
- Closing the popover does not stop playback.
- System media controls expose play and stop. Seeking, previous-track, and
  next-track commands remain unavailable because the source is live.
- Now Playing presents the available title, artist, album, and artwork without
  blocking playback.

## Menu-bar experience

The popover remains compact while providing:

- current artwork or an original branded placeholder;
- live/offline status and listener count when available;
- song title and artist;
- a read-only progress bar with elapsed and remaining time when duration exists;
- play/stop and a system-style horizontal volume slider;
- clear buffering, recovery, and failure feedback; and
- a collapsed list of the three most recently reported songs.

Recently played songs are informational only. They are neither interactive nor
persisted, and they cannot be replayed. Missing data removes or degrades only its
own presentation: missing duration hides progress, missing history shows no
history rows, and missing artwork uses the placeholder.

The menu-bar icon distinguishes stopped, playing, buffering or reconnecting, and
failed states without relying on color alone. The secondary menu contains
Settings, metadata refresh, the station website, and Quit rather than duplicating
stable preferences.

## Playback reliability

The visible state reflects observed player behavior, not the fact that `play()`
was called. The state model distinguishes stopped, connecting or buffering,
playing, reconnecting, offline, and failed.

An explicit play action establishes playback intent for the current application
session. Temporary failures use bounded backoff. Network recovery and wake from
sleep may restore that intent while the application remains alive; an explicit
stop cancels recovery. Once automatic attempts are exhausted, requests stop and
the popover presents the cause and a clear Retry action.

The saved stream quality is a preference, not a recovery state. A failed preferred
stream may temporarily fall back to the lower quality without changing the saved
choice. Recovery remains on that lower quality until Stop, Retry, or an explicit
quality change starts a new cycle. Changing the preference while playing
reconnects immediately; changing it while stopped only saves it.

Metadata and audio fail independently. When metadata is unavailable, playback may
use a fixed fallback stream, the last known song remains visible as stale, and the
UI communicates that its information may be out of date. Partial upstream data is
accepted wherever the remaining fields are usable.

## Accessibility

Accessibility is a release requirement. Every operation must be reachable by
keyboard, and VoiceOver must communicate controls, playback state, quality
fallback, stale metadata, retry behavior, and errors. State cannot depend on color
or motion alone. Motion and translucent effects respect the corresponding macOS
accessibility preferences.

System media keys provide global playback control. The app does not add a separate
global-hotkey system; focused popover and Settings controls use conventional local
keyboard shortcuts.

## Settings

Settings is planned after the first public release. It is a single compact window
containing:

- Launch at Login;
- preferred stream quality;
- the same persisted volume value used by the popover;
- application version and license information;
- Check for Updates; and
- links to the project and station.

These preferences live only in Settings, not in the popover’s secondary menu.
Settings does not add automatic playback, notifications, themes, or stored-history
options. While the window is open, CodeRadio behaves as a regular Dock and
Command-Tab application; closing the last Settings window returns it to its normal
menu-bar-only identity.

## Branding, language, and updates

CodeRadio uses original application, menu-bar, and placeholder artwork rather
than presenting freeCodeCamp artwork as the application identity.

The first release is English. User-facing strings and layouts remain ready for
localization, with Simplified Chinese as the next planned language.

The initial update experience checks GitHub Releases and directs the user to the
new release. A later milestone may provide signed in-app updating after its update
framework, trust model, and operational cost are evaluated.

## Privacy and network boundary

CodeRadio has no account system and sends no analytics or diagnostic telemetry.
Diagnostics stay in the local unified log.

Network access is limited to the Code Radio service and website, artwork locations
returned by station metadata, and GitHub Releases for update checks. A new service
requires an explicit product decision that accounts for its purpose, privacy
impact, and maintenance dependency.

## Release scope

The first public release requires:

- observed playback state, bounded recovery, and graceful metadata degradation;
- the specified popover, system media integration, and accessibility behavior;
- original application and menu-bar artwork;
- a Universal build supporting the agreed macOS baseline;
- Developer ID signing and Apple notarization;
- a versioned GitHub Release and a cask in a personal Homebrew tap;
- installation, upgrade, uninstall, privacy, and troubleshooting documentation;
- deterministic CI build and tests; and
- a manual release smoke test against real metadata and both stream qualities.

Settings, Simplified Chinese, and richer automatic updating follow the first
release. A stable personal cask may later be proposed to the official Homebrew
cask repository.

Releases follow semantic versioning without a fixed calendar. A version tag should
drive a least-privilege CI release workflow that builds, signs, notarizes, and
publishes artifacts using encrypted credentials. A paid Apple Developer Program
membership and Developer ID material are external prerequisites for a public
release, never repository content.
