# Changelog

All notable changes to Fix. Grouped by version, newest first.

## v1.7 — Keep machine-local files out of the project

### Fixed
- `Scripts/generate-project.py` referenced `Config/Local.xcconfig` and
  `Config/Secrets.xcconfig` when they happened to exist. Both are git-ignored,
  so the reference was committed by whoever had them and showed as a missing
  red file for everyone else — and the project file differed between machines
  depending on who last regenerated it. Both are skipped now, and
  `Base.xcconfig` includes them optionally, so nothing needs a reference.

## v1.4 — Keep signing out of the project file

### Changed
- The signing team is read from `Config/Local.xcconfig`, which is git-ignored,
  instead of being written into `project.pbxproj` by Xcode's Signing tab.
  Choosing a team there edited a tracked file, so every pull conflicted and
  every project regeneration discarded it.
- `Config/Local.example.xcconfig` is the template; the README explains where to
  find a Team ID.

## v1.3 — Say what the provider actually said

### Fixed
- A refused request (400, 404, 422…) was reported as `.server`, so a rejected
  request read as "the service is having trouble" and the provider's
  explanation was discarded. Those statuses now map to `APIError.rejected`,
  which carries the provider's own message — Groq and the YouTube Data API both
  put it at `error.message` — and is correctly not retryable.

### Added
- The AI model is chosen in Settings → AI Provider → Model, from a list the
  provider returns for that key. A model named in code is right only until it is
  retired, and this removes that failure mode rather than deferring it.
- `AppSettings.groqModel` persists the choice; `ServiceContainer` folds it into
  the effective configuration and rebuilds, so it applies without a restart.

## v1.2 — Real bundle identifier

### Changed
- Bundle identifiers are `com.ndinisio.Fix` and `com.ndinisio.FixTests`,
  replacing the `com.example` placeholders. The signing team stays out of the
  repository: it is tied to an Apple ID and belongs in Xcode.

## v1.1 — A place for the app icon

### Added
- `Scripts/generate-project.py` recognises Icon Composer documents: a `.icon`
  package under `Fix/` is referenced as an icon document and added to the app
  target's resources, so dropping one in and regenerating is all it takes.
- A guard for the case where an `AppIcon.icon` and an `AppIcon.appiconset` both
  exist. Both claim `ASSETCATALOG_COMPILER_APPICON_NAME`, and the build failure
  that follows does not explain itself.
- README documents both routes to an app icon — an Icon Composer document at
  `Fix/Resources/AppIcon.icon`, or a 1024×1024 PNG in the app icon set — and
  what to check in Xcode afterwards.

## v1.0 — One project, one layout

### Changed
- App resources are grouped under `Fix/Resources/`: `Assets.xcassets`,
  `Info.plist` and `Preview Content` now sit with the target they belong to, so
  `Fix/` contains code folders plus one resources folder and nothing else.
  `Config/` holds build configuration only.
- `INFOPLIST_FILE` and `DEVELOPMENT_ASSET_PATHS` follow. Info.plist stays a
  plain reference rather than a copied resource.

### Added
- `Scripts/generate-project.py` refuses to run when it finds more than one
  `.xcodeproj`, or one anywhere other than the repository root. A stray project
  merged into the sources folder by a case-insensitive filesystem is invisible
  in Finder but shadows the real one in Xcode.
- README documents the full layout, explains why `Fix/Fix/` is correct, and
  warns about cloning into a directory that already contains a similarly named
  folder.

## v0.9 — Rename FIX to Fix

### Changed
- The app is called **Fix**, not FIX, everywhere it is read: display name,
  interface copy, type names (`FixApp`, `FixPrompt`, `FixShortcuts`), file and
  folder names, the Xcode project, both targets, the scheme, the module, and
  the bundle identifiers (`com.example.Fix`, `com.example.FixTests`).
- The `FIX_` prefix on build settings and scheme environment variables is
  unchanged. Uppercase is the convention for environment variables, so
  `FIX_GROQ_API_KEY` stays as it is.

## v0.8 — Enter an API key in the app

### Added
- Settings → Services now leads to a setup screen per service where the user
  pastes their own key. Saving runs one real request against the provider, so
  "Ready" means the credentials were accepted rather than merely entered.
- `KeychainStorage` keeps keys in the device Keychain with
  `afterFirstUnlockThisDeviceOnly` — never in `UserDefaults`, never in the
  bundle, never in Git. `SecretStorage` abstracts it so the rules are testable.
- `AppConfiguration.applying(groqAPIKey:youTubeAPIKey:)` layers user keys over
  the build configuration. A relay is never overridden by a key on the device;
  without one, a key the user typed beats a key baked into the build.
- `ServiceContainer.credentialsDidChange()` rebuilds the pipeline in place, so a
  new key takes effect without restarting the app.
- The Diagnose bar and the diagnosis error state both offer the way to Settings
  when no provider is configured, instead of leaving a dead button.

### Notes
- A key the user enters on their own device and stores in the Keychain is a
  different thing from shipping a developer's secret inside the binary. A relay
  remains the right answer for a build distributed to other people.

## v0.7 — More first-build fixes

### Fixed
- `SafetyWarning` and `CareTip` decoded a bare string by calling `self.init`,
  which makes the whole initialiser delegating — and a delegating initialiser
  may not assign stored properties on any path, including the object path. Both
  paths now assign directly.
- Reverted the `nonisolated(unsafe)` added to `NetworkMonitor` in v0.6: both
  `NWPathMonitor` and `DispatchQueue` are `Sendable`, so the constants were
  already implicitly nonisolated and the attribute only produced warnings.
- Project marked as created and last checked by Xcode 26, so it stops
  offering to update to recommended settings.

## v0.6 — First build fixes

### Fixed
- `ServiceContainer` used `AppSettings()` and `NetworkMonitor()` as default
  argument values. Default argument expressions are evaluated outside the
  initialiser's isolation in Swift 5 language mode, so a main-actor type cannot
  be one — this failed to compile. The two initialisers are now one, with
  optional parameters and the services built in the body, where main-actor
  isolation applies. Previews and tests inject theirs unchanged.
- `NetworkMonitor`'s `deinit` reached main-actor-isolated stored properties.
  The monitor and its queue are now `nonisolated(unsafe)`, which is accurate:
  both are internally synchronised and neither is mutated after init.

## v0.5 — Make the project open with its files visible

### Fixed
- `Fix.xcodeproj` was written using Xcode 16's synchronized folder groups, which
  show an empty navigator in any Xcode that does not process them — the code was
  in the repository but invisible in the project. The project file now lists all
  59 sources explicitly, the format every Xcode version reads.
- The shared scheme referenced the previous target identifiers and would not
  have built or run.

### Added
- `Scripts/generate-project.py`, which rebuilds the project file from the files
  on disk, so adding sources outside Xcode cannot silently leave them out.

## v0.3 — Tests and documentation

### Added
- Swift Testing suite covering networking, parsing, the Groq layer, video
  search and ranking, diagnosis orchestration, session state, and the decisions
  the interface makes before rendering.
- `README.md` documenting setup, configuration, the relay contract,
  architecture, design decisions, privacy and testing.
- This changelog.

### Changed
- `DiagnosisRequest` now normalises optional details at the boundary, so what is
  sent is trimmed and a blank field is absent rather than an empty string,
  whichever route the value arrived by.

## v0.2 — Services, persistence and the full interface

### Added
- `AIService` and `VideoSearchService` protocols with `GroqService` and
  `YouTubeVideoSearchService` implementations, each supporting a relay or a
  direct key. `FallbackAIService` provides the provider chain.
- `FixPrompt`: the diagnostic instructions, including safety rules that take
  priority over troubleshooting, and a request for search terms written for
  video search rather than the user's raw text.
- `TroubleshootingService`, which runs a diagnosis end to end, reports the
  stages actually in progress, and caches results in memory.
- `VideoRelevanceRanker`, ordering results towards repair content and away from
  reviews and unboxings, without claiming any source is authoritative.
- SwiftData persistence for saved devices and sessions, with `Library` as the
  single place that writes.
- The interface: Diagnose, the session results screen, History, Devices,
  device care pages, Settings and Privacy.
- Interactive steps that expand in place and record what happened, with
  "Keep troubleshooting" appending a new round once everything has been tried.
- Care guidance on each diagnosis and on a device's own page.
- An App Intent and Shortcut for "Troubleshoot a device", opening the app with
  the device filled in.
- `NetworkMonitor`, so the app can say a diagnosis needs a connection before the
  user taps Diagnose.

### Notes
- A failed video search degrades a diagnosis instead of failing it.
- The response cache is memory-only: history already holds what the user keeps.

## v0.1 — Project scaffold, configuration and domain models

### Added
- Xcode project targeting iOS 26, with an app target and a test target using
  synchronized folder groups so files added on disk need no project-file edits.
- `Config/Base.xcconfig` with defaults and an optional include of a git-ignored
  `Config/Secrets.xcconfig`, so a fresh clone builds without configuration.
- `AppConfiguration`, resolving credentials from scheme environment variables
  first and `Info.plist` second, with a relay always winning over an on-device
  key.
- Domain models — `Diagnosis`, `TroubleshootingStep`, `SafetyWarning`,
  `CareTip`, `VideoResult`, `TroubleshootingSession`, `DeviceCatalog` — with
  lenient decoding so a slightly malformed response does not cost the user their
  answer.
- `APIClient` with retry, backoff and `Retry-After` handling, and `APIError`
  carrying user-facing titles and guidance so raw provider errors never reach
  the interface.
- `.gitignore` covering build products, user state and every secret path.
