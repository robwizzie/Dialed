# Motra Integration

Motra (formerly Train Fitness) writes every workout it tracks to Apple
HealthKit as an `HKWorkout` record. Dialed already reads HealthKit
workouts, so the integration is **zero-config from your side** — once you
grant Apple Health permissions and Motra writes data, those workouts show
up in Dialed.

What we do automatically:

- **Source recognition**: every workout we ingest from HealthKit is
  classified as `motra`, `appleNative`, `dialed`, or `other`. Phase 2's
  workout tile branches on this — Motra workouts get a Motra-styled card
  with an "Open in Motra" button; we suppress our own "log this workout"
  prompts for those days.
- **Branding tolerance**: we match both the current `Motra` source name
  and the legacy `Train Fitness` name (case-insensitive, substring), so
  older workouts from before the rebrand still classify correctly.

## What we *don't* get from HealthKit

HKWorkout stores duration, activity type, calories, and (sometimes)
distance. Per-set / per-rep / weight detail and PR analysis stay inside
Motra. For now we treat Motra as the source of truth for that data and
deep-link out when you want to see it.

A future enhancement (Phase 3) will let you import a Motra CSV export into
Dialed for richer in-app history. Out of scope for Phase 1.

## URL scheme for deep-linking

Motra hasn't published their URL scheme. `MotraIntegration.candidateSchemes`
tries a list of plausible candidates in order and falls back to the App
Store if nothing resolves:

```swift
static let candidateSchemes: [String] = [
    "motra",          // most likely
    "trainfitness",   // legacy branding
    "ai.motra",
    "ai.trainfitness"
]
```

**Once you test on-device** and confirm which scheme actually launches
Motra, edit `candidateSchemes` to put the working one first (and
optionally drop the rest). We'll also want to register that scheme under
`LSApplicationQueriesSchemes` in the target Info.plist so we can use
`UIApplication.canOpenURL(_:)` to detect "is Motra installed?" cleanly —
right now we just attempt `open(_:)` and fall through to the App Store.

## MCP — not used (yet)

Motra exposes an MCP server for ChatGPT (read-only, Claude support
"coming soon"). It's an HTTPS + OAuth + SSE endpoint designed for AI
assistants, not native iOS apps, and the on-device AI direction chosen
for Dialed (Apple Foundation Models) doesn't currently support remote MCP
tool-use. We'll revisit when either of those changes.
