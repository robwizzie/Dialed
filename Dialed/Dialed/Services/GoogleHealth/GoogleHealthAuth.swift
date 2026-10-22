//
//  GoogleHealthAuth.swift
//  Dialed
//
//  Google OAuth 2.0 (PKCE, iOS client) for the Google Health API. Tokens
//  live in the Keychain and refresh silently before every call.
//
//  Note: while the Cloud project's consent screen is in "Testing", Google
//  expires refresh tokens after 7 days — publish it ("In production") to
//  stay connected. Personal use under 100 users needs no verification.
//

import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct GoogleHealthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

enum GoogleHealthTokenStore {
    private static let key = "googleHealth.tokens.v1"

    static func load() -> GoogleHealthTokens? {
        guard let data = try? KeychainStore.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GoogleHealthTokens.self, from: data)
    }

    static func save(_ tokens: GoogleHealthTokens) throws {
        try KeychainStore.setData(JSONEncoder().encode(tokens), forKey: key)
    }

    static func clear() {
        _ = KeychainStore.remove(forKey: key)
    }

    static var isConnected: Bool { load() != nil }
}

@MainActor
final class GoogleHealthAuth: NSObject, ObservableObject {
    static let shared = GoogleHealthAuth()

    @Published private(set) var isConnected: Bool = GoogleHealthTokenStore.isConnected

    private var session: ASWebAuthenticationSession?

    enum AuthError: LocalizedError {
        case notConfigured
        case cancelled
        case stateMismatch
        case noCode(String?)
        case tokenExchangeFailed(String)
        /// Google refused the refresh token (revoked, or the 7-day limit
        /// while the consent screen is in Testing). Only this disconnects.
        case refreshRejected(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Google Cloud iOS Client ID first (ends in .apps.googleusercontent.com)."
            case .cancelled:
                return "Sign-in cancelled."
            case .stateMismatch:
                return "Sign-in response didn't match — please try again."
            case .noCode(let error):
                return "Google didn't return an authorization code\(error.map { " (\($0))" } ?? "")."
            case .tokenExchangeFailed(let detail):
                return "Couldn't finish connecting: \(detail)"
            case .refreshRejected:
                return "Google ended Dialed's sign-in. Reconnect to keep syncing."
            case .notConnected:
                return "Google Health isn't connected."
            }
        }
    }

    // MARK: - Connect

    func connect() async throws {
        guard let clientID = GoogleHealthConfig.clientID,
              let scheme = GoogleHealthConfig.callbackScheme,
              let redirectURI = GoogleHealthConfig.redirectURI else {
            throw AuthError.notConfigured
        }

        let verifier = Self.makePKCEVerifier()
        let state = Self.makePKCEVerifier()

        var components = URLComponents(url: GoogleHealthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleHealthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: Self.pkceChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw AuthError.notConfigured }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.noCode(nil))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.tokenExchangeFailed("couldn't open the Google sign-in sheet"))
            }
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode(items.first(where: { $0.name == "error" })?.value)
        }

        let tokens = try await tokenRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ], previousRefreshToken: nil)
        try GoogleHealthTokenStore.save(tokens)
        isConnected = true
    }

    func disconnect() {
        GoogleHealthTokenStore.clear()
        isConnected = false
    }

    /// A valid access token, refreshing first if needed.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens = GoogleHealthTokenStore.load() else { throw AuthError.notConnected }
        if !tokens.isExpired && !forceRefresh { return tokens.accessToken }
        guard let clientID = GoogleHealthConfig.clientID else { throw AuthError.notConfigured }
        do {
            let fresh = try await tokenRequest([
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken
            ], previousRefreshToken: tokens.refreshToken)
            try GoogleHealthTokenStore.save(fresh)
            return fresh.accessToken
        } catch {
            // Revoked or expired (7-day limit in Testing) — ask to reconnect.
            // Anything else (offline, timeout, a Google hiccup) keeps the
            // tokens: the next sync just tries again.
            if case AuthError.refreshRejected = error { disconnect() }
            throw error
        }
    }

    // MARK: - Token endpoint

    private func tokenRequest(_ params: [String: String], previousRefreshToken: String?) async throws -> GoogleHealthTokens {
        var request = URLRequest(url: GoogleHealthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let detail = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) \(body.prefix(300))"
            // invalid_grant = this refresh token is dead for good.
            if previousRefreshToken != nil, body.contains("invalid_grant") {
                throw AuthError.refreshRejected(detail)
            }
            throw AuthError.tokenExchangeFailed(detail)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Refresh responses usually omit refresh_token — keep the old one.
        guard let refresh = decoded.refresh_token ?? previousRefreshToken else {
            throw AuthError.tokenExchangeFailed("no refresh token returned")
        }
        return GoogleHealthTokens(
            accessToken: decoded.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    // MARK: - PKCE

    static func makePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func pkceChallenge(from verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

extension GoogleHealthAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            return window ?? ASPresentationAnchor()
        }
    }
}
