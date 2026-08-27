# CodeRadio Agent Guide

## Sources of truth

- **Product work:** Before changing playback behavior, menu-bar or Settings UX,
  accessibility, privacy and network boundaries, branding, distribution, or
  release scope, read [`docs/product-design.md`](docs/product-design.md). Update
  it when product intent changes, not when implementation catches up.
- **User-facing work:** Keep [`README.md`](README.md) aligned with behavior that
  users can observe, installation requirements, and support procedures.
- **Implementation facts:** Read source code, tests, assets, and Xcode settings
  for the current architecture, capabilities, identifiers, endpoints, target
  membership, and implemented status. Do not cache those facts in agent docs.

When implementation and product design differ, treat the difference as unfinished
work rather than silently rewriting the intended behavior.

## Engineering constraints

- Keep the app a focused native macOS menu-bar utility built with Swift,
  SwiftUI, AVFoundation, and Apple system frameworks.
- Preserve App Sandbox compatibility and the smallest practical entitlement and
  network surface.
- Keep UI and `AVPlayer` mutations on the main actor. Model user playback intent
  separately from observed player state.
- Use structured concurrency for polling and recovery. Long-running work must be
  cancellable, and each responsibility must have at most one active loop.
- Decode upstream responses defensively and let audio, metadata, and artwork fail
  independently where the product design permits.
- Put system and network boundaries behind small injectable interfaces when that
  makes state transitions deterministic to test.
- Persist only intentional user preferences. Temporary recovery choices must not
  overwrite those preferences.
- Use unified logging for diagnostics. Keep secrets, credentials, certificates,
  notarization material, and persistent ad-hoc logs out of the repository.
- Treat accessibility and localization readiness as acceptance criteria for UI
  changes, including failure and recovery states.
- Keep the playback core free of third-party dependencies. A future updater may
  add a mature dependency only after its security and maintenance costs are
  explicitly reviewed.

## Change discipline

- Preserve unrelated working-tree changes.
- Prefer adding Swift files through the project’s synchronized source layout;
  verify target membership whenever Xcode cannot resolve a new type.
- Change Xcode settings through Xcode or a deterministic edit, then inspect the
  project diff for unrelated churn.
- Add unit tests for decoding, preferences, state transitions, fallback choices,
  retry cancellation, and other behavior that can run without live audio or
  network access.
- Keep ordinary CI deterministic and independent of public Code Radio service
  availability.
- Update product design only for a changed decision. Update README only for
  user-visible behavior or workflows.

## Verification

Run the narrowest relevant checks while iterating. Before completing a change,
run:

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

git diff --check
```

Playback, menu-bar, media-key, Launch at Login, Settings-window, packaging, and
release changes also require a focused manual smoke test of the affected path.
Release candidates additionally require real metadata and both stream qualities
to be checked outside automated CI.

A change is done when the supported target builds, relevant automated tests pass,
the intended menu-bar lifecycle and sandbox boundary remain intact, required
manual checks are reported, and affected product or user documentation is current.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues using the `gh` CLI. See
`docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the default five-label vocabulary. See
`docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.
