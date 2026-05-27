//
//  FitbitTokenStore.swift
//  Dialed
//
//  Persistent storage for Fitbit OAuth tokens. Access + refresh tokens live
//  in Keychain; the expiry timestamp and Fitbit user ID live in UserDefaults
//  for cheap reads on every API call.
//

import Foundation

struct FitbitTokens {
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry timestamp (we refresh ~60s before this).
    var expiresAt: Date
    /// Fitbit's opaque user ID — used in /1/user/[id]/... endpoints, though "-" is the
    /// common shorthand for "current user". Keep it for sanity checking re-connects.
    var fitbitUserID: String

    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 60  // refresh ≥1 min before expiry
    }
}

enum FitbitTokenStore {
    private static let accessTokenKey = "fitbit.accessToken"
    private static let refreshTokenKey = "fitbit.refreshToken"
    private static let expiresAtKey = "fitbit.expiresAt"
    private static let userIDKey = "fitbit.userID"

    static func load() -> FitbitTokens? {
        guard let access = try? KeychainStore.string(forKey: accessTokenKey), let access,
              let refresh = try? KeychainStore.string(forKey: refreshTokenKey), let refresh else {
            return nil
        }

        let expiresAt = UserDefaults.standard.double(forKey: expiresAtKey)
        let userID = UserDefaults.standard.string(forKey: userIDKey) ?? "-"

        guard expiresAt > 0 else { return nil }

        return FitbitTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            fitbitUserID: userID
        )
    }

    static func save(_ tokens: FitbitTokens) throws {
        try KeychainStore.setString(tokens.accessToken, forKey: accessTokenKey)
        try KeychainStore.setString(tokens.refreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(tokens.expiresAt.timeIntervalSince1970, forKey: expiresAtKey)
        UserDefaults.standard.set(tokens.fitbitUserID, forKey: userIDKey)
    }

    static func clear() {
        KeychainStore.remove(forKey: accessTokenKey)
        KeychainStore.remove(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: expiresAtKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    static var isConnected: Bool { load() != nil }
}
