//
//  FitbitConfig.swift
//  Dialed
//
//  Fitbit Web API configuration. Reads the client ID from Info.plist so the
//  app stays distributable without the developer's credentials. Uses the
//  Fitbit "Personal" app flow — OAuth 2.0 with PKCE, no client secret.
//
//  SETUP CHECKLIST (one-time, see SETUP_FITBIT.md):
//    1. Register an app at https://dev.fitbit.com/apps/new
//       - Application Type: Personal
//       - OAuth 2.0 Application Type: Client
//       - Callback URL: dialed://oauth/fitbit-callback
//    2. Copy the resulting OAuth 2.0 Client ID.
//    3. Add it to the target Info.plist as FitbitClientID = <your-id>.
//    4. Register the custom URL scheme `dialed` in the target's URL Types.
//

import Foundation

enum FitbitConfig {
    /// UserDefaults key for a Client ID pasted in Devices → Pixel Watch.
    static let clientIDDefaultsKey = "fitbit.clientID"

    /// Client ID from Info.plist (key: `FitbitClientID`), or the one pasted
    /// into the Devices screen. Returns nil when neither is set, which lets
    /// the connect flow show a helpful error instead of crashing.
    /// No URL-scheme registration is needed: ASWebAuthenticationSession
    /// intercepts the `dialed://` callback itself.
    static var clientID: String? {
        if let id = Bundle.main.object(forInfoDictionaryKey: "FitbitClientID") as? String,
           !id.isEmpty,
           id != "REPLACE_WITH_YOUR_FITBIT_CLIENT_ID" {
            return id
        }
        let saved = UserDefaults.standard.string(forKey: clientIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (saved?.isEmpty ?? true) ? nil : saved
    }

    /// Custom URL scheme + path Fitbit will redirect back to after authorization.
    static let redirectURI = "dialed://oauth/fitbit-callback"

    /// URL scheme component for ASWebAuthenticationSession.
    static let callbackURLScheme = "dialed"

    /// Authorization endpoint (browser-facing).
    static let authorizeURL = URL(string: "https://www.fitbit.com/oauth2/authorize")!

    /// Token endpoint (server-to-server JSON form post).
    static let tokenURL = URL(string: "https://api.fitbit.com/oauth2/token")!

    /// Base URL for Web API calls.
    static let apiBaseURL = URL(string: "https://api.fitbit.com")!

    /// Scopes we request. Keep this minimal — every scope here triggers a
    /// permission row on the Fitbit consent screen.
    static let scopes: [String] = [
        "activity",
        "heartrate",
        "sleep",
        "respiratory_rate",
        "oxygen_saturation",
        "temperature",
        "weight",       // smart-scale weigh-ins (Aria / anything synced to Fitbit)
        "nutrition",    // water logged in the Fitbit app
        "profile"
    ]

    var scopeString: String { Self.scopes.joined(separator: " ") }
}
