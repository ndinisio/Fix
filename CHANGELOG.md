# Changelog

All notable changes to FIX. Grouped by version, newest first.

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
- `FIX.xcodeproj` was written using Xcode 16's synchronized folder groups, which
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
- `FIXPrompt`: the diagnostic instructions, including safety rules that take
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
