# Fitbit Integration Setup

Dialed 2.0 talks directly to the Fitbit Web API (OAuth 2.0 with PKCE) so it
can pull rich data your wrist tracker collects — HRV, resting HR, SpO2,
skin temperature delta, breathing rate, sleep stages with vendor sleep score,
and activity summaries. Some of these (notably nightly HRV and sleep stages)
are *not* available via Apple Health when you sync Fitbit through a bridge,
which is why we go direct.

This is a one-time, ~5 minute setup. You only need to do it on the device
you're building to.

## 1. Register a Personal Fitbit app

1. Sign in at <https://dev.fitbit.com> with your normal Fitbit account.
2. Click **Register a new app**.
3. Fill in:
   - **Application Name**: `Dialed` (or whatever you like)
   - **Description**: `Personal health OS`
   - **Application Website URL**: any URL you control (your GitHub profile is fine)
   - **Organization**: your name
   - **Organization Website URL**: same as above
   - **OAuth 2.0 Application Type**: **Client**
   - **Redirect URL**: `dialed://oauth/fitbit-callback`
   - **Default Access Type**: **Read-Only**
   - **Application Type**: **Personal**
4. Submit. Fitbit shows you an **OAuth 2.0 Client ID** (something like `23ABCD`).
   Copy it.

## 2. Add the client ID to the iOS target

Open `Dialed.xcodeproj` in Xcode and add a custom Info.plist key on the
**Dialed** target (Build Settings → search for "Info.plist Values" → scroll
or use the `+` to add the key, OR edit Info.plist directly if you've split
it out):

| Key             | Type   | Value                              |
|-----------------|--------|------------------------------------|
| `FitbitClientID`| String | `<paste your Client ID here>`      |

If you're editing the project via the file-system synchronized group (the
default for this project), the simplest path is:

1. Select the **Dialed** target → **Info** tab.
2. Under **Custom iOS Target Properties**, click `+`.
3. Add `FitbitClientID` (String) with your Client ID.

## 3. Register the custom URL scheme

ASWebAuthenticationSession needs the `dialed` scheme registered so the system
recognizes the Fitbit redirect.

1. Select the **Dialed** target → **Info** tab.
2. Expand **URL Types** → click `+`.
3. Set:
   - **Identifier**: `com.dialed.app.fitbit`
   - **URL Schemes**: `dialed`
   - **Role**: Editor

That's all. No backend, no client secret — PKCE handles authentication
entirely on-device.

## 4. Connect inside the app

Once Phase 2 wires up the Settings UI, you'll go to **Settings → Integrations
→ Connect Fitbit** and step through the consent screen. Until then, the
plumbing is reachable programmatically:

```swift
try await FitbitAuthService.shared.connect()
let svc = FitbitSyncService(modelContext: modelContext)
await svc.backfill(days: 28)
```

## Troubleshooting

- **"Fitbit Client ID is missing"** — the `FitbitClientID` Info.plist key isn't
  being read. Make sure it's on the **Dialed** target (not just the project)
  and that you've rebuilt.
- **OAuth redirect goes nowhere** — the `dialed` URL scheme isn't registered
  on the target. Re-check step 3.
- **"state did not match"** — usually a stale browser session. Retry; the new
  code generates fresh state every time.
- **Token exchange returns HTTP 400** — make sure your registered Redirect URL
  is *exactly* `dialed://oauth/fitbit-callback` (lowercase, trailing slash off).

## Data scopes

The Phase 1 client requests these scopes:

```
activity heartrate sleep respiratory_rate oxygen_saturation temperature profile
```

You'll see them listed on the Fitbit consent screen. If you want to drop any
of them later, edit `FitbitConfig.scopes` and reconnect.
