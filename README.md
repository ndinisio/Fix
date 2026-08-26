# FIX

FIX is an iOS app for fixing the things you own — and for keeping them working
once they are fixed. You tell it what the device is and what it is doing; it
gives you a diagnosis, an ordered set of things to try, the safety warnings that
apply, repair videos, and the habits that stop the problem coming back.

It is built to feel like a tool rather than a chatbot: you never talk to a
model, you work through steps and tell the app what happened.

- **Platform:** iOS 26, SwiftUI, SwiftData, Swift concurrency
- **AI provider:** Groq, behind a protocol so it can be swapped
- **Video search:** YouTube Data API, behind a protocol so it can be swapped

---

## Contents

- [Getting started](#getting-started)
- [Configuration and secrets](#configuration-and-secrets)
- [The relay contract](#the-relay-contract)
- [Architecture](#architecture)
- [How a diagnosis works](#how-a-diagnosis-works)
- [Design notes](#design-notes)
- [Privacy](#privacy)
- [Tests](#tests)
- [Implementation notes](#implementation-notes)

---

## Getting started

1. Open `FIX.xcodeproj` in Xcode 26 or later.
2. Select the **FIX** scheme and an iOS 26 simulator.
3. Build and run.

The app builds and runs with no configuration at all. Without an AI provider it
still launches, browses history and saved devices, and says plainly in Settings
that new diagnoses are unavailable — it never invents an answer to fill the gap.

Before running on a device, set your own team and bundle identifier in
**Signing & Capabilities**. The project ships with `com.example.FIX`.

### Add the app icon yourself

`FIX/Assets.xcassets/AppIcon.appiconset` is deliberately empty. Icons are worth
drawing rather than generating, and asset-catalog surgery is safer done in
Xcode: drop a 1024×1024 image onto the AppIcon slot when you have one.

---

## Configuration and secrets

No key is committed, and none is hard-coded. Configuration is resolved once at
launch by `AppConfiguration`, in this order:

1. **Scheme environment variables** — never written into the build products.
2. **`Info.plist`**, populated at build time from `Config/Secrets.xcconfig`.

Two transports are supported:

| Transport | What it does | Suitable for |
|---|---|---|
| **Relay** | Requests go to a backend you control, which holds the provider keys | Production |
| **Direct** | The app calls Groq/YouTube itself with a key from the build | Development only |

A relay always wins if both are configured, so a stray development key can never
be shipped by accident.

**Anything inside an app bundle can be extracted from it.** A direct key is fine
while you are building; it is not fine in the App Store. Ship the relay.

### Local development

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then fill in what you need. `Config/Secrets.xcconfig` is git-ignored:

```
FIX_GROQ_API_KEY = gsk_your_development_key
FIX_YOUTUBE_API_KEY = your_youtube_data_api_key
FIX_GROQ_MODEL = llama-3.3-70b-versatile
```

> **Note on URLs in xcconfig:** `//` starts a comment in an `.xcconfig` file, so
> a scheme cannot be written literally. Give `FIX_RELAY_BASE_URL` as a host and
> optional path — `fix-relay.example.com/v1` — and the app prepends `https://`.
> Full URLs work everywhere else, including scheme environment variables.

### Scheme environment variables

Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables:

| Variable | Purpose |
|---|---|
| `FIX_RELAY_BASE_URL` | Relay base URL (full URL or host) |
| `FIX_GROQ_API_KEY` | Groq key, development only |
| `FIX_YOUTUBE_API_KEY` | YouTube Data API key, development only |
| `FIX_GROQ_MODEL` | Override the model |

---

## The relay contract

A relay is a thin credential-adding proxy. It needs two routes.

**`POST {base}/chat/completions`** — forward the body verbatim to Groq's
OpenAI-compatible endpoint, adding the `Authorization` header, and return Groq's
response unchanged. The app sends the model, messages and `response_format`.

**`GET {base}/videos?q=…&limit=…`** — search for videos and return FIX's own
shape, so the relay decides which provider it uses:

```json
{
  "videos": [
    {
      "id": "abc123",
      "title": "Fix a MacBook that won't charge",
      "channelName": "Repair Workshop",
      "thumbnailURL": "https://…/thumb.jpg",
      "videoURL": "https://www.youtube.com/watch?v=abc123",
      "duration": "8:41",
      "publishedAt": "2024-03-01T10:00:00Z"
    }
  ]
}
```

`thumbnailURL`, `duration` and `publishedAt` are optional. Results are re-ranked
on the device either way.

---

## Architecture

```text
FIX/
├── App/              FIXApp, RootView, AppRouter, App Intents
├── Configuration/    AppConfiguration, AppSettings, ServiceContainer
├── Models/           Diagnosis, TroubleshootingSession, VideoResult, DeviceCatalog…
├── Networking/       APIClient, APIError
├── Services/         AIService, GroqService, VideoSearchService, TroubleshootingService…
├── Persistence/      SwiftData models and Library
├── ViewModels/       DiagnoseViewModel, SessionViewModel, DeviceCareViewModel
├── Views/            Diagnose, Session, History, Devices, Settings, Components
└── Utilities/        Text formatting
```

The dependency direction is one-way: views depend on view models, view models on
services, services on networking and models. Nothing points back up.

### The seams that matter

```swift
protocol AIService {
    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis
    func carePlan(for device: String) async throws -> CarePlan
}

protocol VideoSearchService {
    func searchVideos(query: String, limit: Int) async throws -> [VideoResult]
}
```

`GroqService` and `YouTubeVideoSearchService` implement them.
`FallbackAIService` takes an ordered list of providers and returns the first
answer — the chain a second provider slots into, without a second provider being
invented before one is configured. `ServiceContainer` wires it all up in one
place; `UnconfiguredAIService` stands in when nothing is set up so "not
configured" is an ordinary error rather than a special case threaded through the
app.

### Persistence

SwiftData stores saved devices and sessions. The searchable columns — device,
problem, date, solved — are real properties; the session itself is stored as
encoded JSON. That keeps the schema stable as the diagnosis format changes and
means a past answer stays fully readable offline. Views read with `@Query`;
every write goes through `Library`.

---

## How a diagnosis works

```text
Device + problem
      ↓
DiagnosisRequest              structured: device, problem, context, previous attempts
      ↓
AIService                     JSON in a fixed schema, never prose to scrape
      ↓
Diagnosis                     summary, category, causes, steps, warnings, care tips
      ↓
videoSearchQuery              written by the model for search, not the raw message
      ↓
VideoSearchService  →  ranked results
      ↓
Session                       saved, resumable, works offline afterwards
```

When every step has been tried without success, FIX sends the same problem back
with the failures attached and appends a new round. It does not restart the
diagnosis, and it does not repeat what already failed.

### Safety

The system prompt puts safety ahead of troubleshooting. Smoke, burning smells,
sparks, swollen or leaking batteries, liquid ingress, exposed mains wiring and
devices too hot to touch must produce a `danger` warning that tells the user to
stop and disconnect — and the app renders those warnings above everything else
on the screen, including the diagnosis.

### Degrading, not failing

A failed video search never costs the diagnosis: the answer is shown, and the
UI says video search was unavailable rather than implying no videos exist.
A failed follow-up round leaves the answer already on screen untouched.

---

## Design notes

Built to the Human Interface Guidelines, using native components throughout:
`TabView`, `NavigationStack`, `Form`, `List`, `ContentUnavailableView`,
`ShareLink`, `Menu`, `.confirmationDialog`, `.searchable`, SF Symbols and the
system type styles.

- **Three tabs, because the app does three things.** Diagnose, Devices, History.
  Settings is a sheet from the Diagnose toolbar, not a fourth tab.
- **The primary action is pinned.** "Diagnose" sits in a bottom safe-area inset,
  so the keyboard never covers it.
- **Progressive disclosure.** Optional context is behind a disclosure group;
  steps expand in place; difficulty and risk appear only when they are not
  routine, because labelling every step "Easy · Low risk" is noise.
- **Liquid Glass is left to the system.** Navigation bars, the tab bar and the
  pinned action bar are standard chrome, so they pick up the current material
  automatically. Glass is not applied to content — no glass cards, no floating
  panels.
- **Honest loading.** The progress screen lists the stages that are really
  running, and shows the video stage only when videos are switched on.
- **Colour is never the only signal.** Every status has a symbol and a word.
- **Accessibility is built in:** Dynamic Type throughout including a scaled video
  thumbnail, VoiceOver labels and values on every control, step outcomes exposed
  as accessibility actions so they work without expanding a row, and Reduce
  Motion respected on every animation.
- **No claims we cannot support.** Videos are ranked, never badged as
  "official" — the app cannot verify who made them, so it does not say.

---

## Privacy

No account, no sign-in, no analytics.

**Stays on the device:** history, saved devices, care guidance.

**Sent when you diagnose:** the device name, the problem description, any
optional details you filled in, and — when you continue — which steps did not
work. Nothing else: no identifiers, no contacts, no location, and nothing read
from the device you are holding.

The response cache is memory-only. What you keep is already in history; a second
copy of your problem descriptions on disk would be storing personal data for no
benefit.

---

## Tests

```sh
xcodebuild test -scheme FIX -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or ⌘U in Xcode. Written with Swift Testing, covering:

| Area | What is checked |
|---|---|
| Networking | success, malformed JSON, retry then recovery, giving up, 429 with `Retry-After`, 401 not retried, timeout, offline not retried |
| Parsing | full responses, missing optionals, unexpected fields, unknown enum values, a string where a list was expected, numeric confidence, required fields, storage round trip |
| Groq | envelope handling, fenced output, empty completions, key sent only on the direct transport, follow-up prompt content |
| Video search | mapping and ranking, HTML entities, empty results, API failure, results dropped rather than invented, missing thumbnails, relay carries no key, ISO 8601 durations |
| Troubleshooting | videos failing without losing the diagnosis, stage order, caching, follow-ups not served from the first round's cache, provider fallback |
| Session state | step outcomes, when to offer another round, solving and un-solving, care-tip de-duplication, saving and reopening |
| Interface state | when Diagnose is available, form clearing, history grouping, cache expiry and eviction, every error and category having something to show |

---

## Implementation notes

- **Where this differs from the brief.** The response type is `Diagnosis` rather
  than `TroubleshootingResponse` — it reads better at the call sites — and
  `confidence` is `low | medium | high` rather than a `Double`, because a
  two-decimal number implies a precision the model does not have. Numeric
  confidence still decodes, mapped onto those three.
- **Decoding is deliberately forgiving.** A model that omits an optional array or
  sends a bare string where an object was expected should not cost the user
  their answer. A response with no summary, or with nothing to do and nothing to
  ask, is still treated as a failure.
- **Cost control.** Prompts are compact and sent whole rather than accumulated;
  responses are capped; video search asks for a small page and adds durations
  with one extra request that costs a single unit of quota against search's
  hundred; identical requests inside a session are served from cache; follow-up
  rounds skip video search because the videos on screen came from the same
  problem.
- **Swift language mode.** The project builds in Swift 5 language mode. The code
  is written to be concurrency-clean — view models are `@MainActor`, models are
  `Sendable`, caches are actors — so moving the target to Swift 6 should be a
  build-setting change rather than a rewrite.
- **Project file.** `FIX.xcodeproj` lists every file explicitly, which is the
  format Xcode has always written and every version can open. Xcode maintains it
  for you when you add files through its UI; if you add or remove sources from
  the filesystem instead, run `python3 Scripts/generate-project.py` from the
  repository root to rebuild it from what is on disk.
