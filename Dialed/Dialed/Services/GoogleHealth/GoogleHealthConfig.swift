//
//  GoogleHealthConfig.swift
//  Dialed
//
//  Google Health API (health.googleapis.com/v4) — the replacement for the
//  Fitbit Web API, which Google turns off on Oct 30, 2026. Your Pixel Watch
//  syncs to your Google account; Dialed reads it from here.
//
//  SETUP (one-time, see SETUP_GOOGLE_HEALTH.md):
//    1. Google Cloud console → new project → enable "Google Health API".
//    2. OAuth consent screen: External, add yourself as a test user, add the
//       googlehealth.*.readonly scopes below.
//    3. Credentials → Create OAuth client ID → type **iOS**, bundle ID
//       org.robertwiscount.Dialed. Copy the Client ID.
//    4. Paste it into Dialed → Devices → Pixel Watch (or add
//       `GoogleHealthClientID` to Info.plist).
//
//  iOS clients use PKCE with no secret. The redirect is the reversed client
//  ID scheme, which ASWebAuthenticationSession intercepts directly — no URL
//  type registration needed.
//

import Foundation

enum GoogleHealthConfig {
    static let clientIDDefaultsKey = "googleHealth.clientID"

    /// iOS OAuth client ID ("1234-abc.apps.googleusercontent.com").
    static var clientID: String? {
        if let id = Bundle.main.object(forInfoDictionaryKey: "GoogleHealthClientID") as? String,
           reversedClientID(id) != nil {
            return id
        }
        let saved = UserDefaults.standard.string(forKey: clientIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved, reversedClientID(saved) != nil else { return nil }
        return saved
    }

    /// "1234-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.1234-abc".
    /// nil when the ID isn't an iOS/installed-app style client ID.
    static func reversedClientID(_ id: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(suffix), trimmed.count > suffix.count else { return nil }
        return "com.googleusercontent.apps." + trimmed.dropLast(suffix.count)
    }

    static var callbackScheme: String? { clientID.flatMap(reversedClientID) }
    static var redirectURI: String? { callbackScheme.map { "\($0):/oauth2redirect" } }

    static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static let apiBase = URL(string: "https://health.googleapis.com/v4/")!

    /// Read-only access to exactly what Dialed shows.
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",       // steps, exercise
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly", // HR, HRV, SpO₂, breathing, weight
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.nutrition.readonly",                  // hydration log
        "https://www.googleapis.com/auth/googlehealth.profile.readonly"
    ]
}
