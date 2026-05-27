//
//  FitbitAuthService.swift
//  Dialed
//
//  Fitbit OAuth 2.0 (PKCE) flow. Drives ASWebAuthenticationSession to get
//  consent, exchanges the resulting auth code for tokens, and handles silent
//  refresh on every API call.
//

import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class FitbitAuthService: NSObject, ObservableObject {
    static let shared = FitbitAuthService()

    @Published private(set) var isConnected: Bool = FitbitTokenStore.isConnected
    @Published private(set) var lastError: String?

    private var currentSession: ASWebAuthenticationSession?
    private var pkceVerifier: String?
    private var pkceState: String?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    enum AuthError: LocalizedError {
        case notConfigured
        case userCancelled
        case stateMismatch
        case noCode
        case tokenExchangeFailed(String)
        case noTokens

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Fitbit Client ID is missing. Add FitbitClientID to Info.plist."
            case .userCancelled:
                return "Sign-in cancelled."
            case .stateMismatch:
                return "OAuth state did not match — possible tampering, please try again."
            case .noCode:
                return "Fitbit did not return an authorization code."
            case .tokenExchangeFailed(let detail):
                return "Token exchange failed: \(detail)"
            case .noTokens:
                return "Not signed in to Fitbit."
            }
        }
    }

    /// Kick off the OAuth flow. Resolves when tokens are stored.
    func connect() async throws {
        guard let clientID = FitbitConfig.clientID else { throw AuthError.notConfigured }

        let verifier = Self.makePKCEVerifier()
        let challenge = Self.pkceChallenge(from: verifier)
        let state = Self.makeRandomString(length: 32)

        self.pkceVerifier = verifier
        self.pkceState = state

        var components = URLComponents(url: FitbitConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: FitbitConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: FitbitConfig.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "login consent")
        ]
        guard let authURL = components.url else { throw AuthError.noCode }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: FitbitConfig.callbackURLScheme
            ) { url, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.noCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            session.start()
        }

        try await handleCallback(callbackURL)
    }

    /// Called when the OS routes a `dialed://oauth/fitbit-callback?...` URL
    /// back to us — also reachable directly from `connect()`'s completion.
    func handleCallback(_ url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw AuthError.noCode
        }

        let returnedState = items.first { $0.name == "state" }?.value
        guard returnedState == pkceState else {
            throw AuthError.stateMismatch
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }

        guard let verifier = pkceVerifier else {
            throw AuthError.noCode
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)

        // Reset transient state.
        pkceVerifier = nil
        pkceState = nil
    }

    /// Disconnect — clears local tokens. (We don't currently revoke server-side;
    /// Fitbit's revoke endpoint requires the access token and is best-effort.)
    func disconnect() {
        FitbitTokenStore.clear()
        isConnected = false
    }

    /// Return a valid (refreshed if needed) access token, or throw if not connected.
    func validAccessToken() async throws -> String {
        guard var tokens = FitbitTokenStore.load() else { throw AuthError.noTokens }
        if tokens.isExpired {
            tokens = try await refresh(using: tokens.refreshToken)
        }
        return tokens.accessToken
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        guard let clientID = FitbitConfig.clientID else { throw AuthError.notConfigured }

        var request = URLRequest(url: FitbitConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = formEncoded([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "redirect_uri": FitbitConfig.redirectURI,
            "code": code,
            "code_verifier": verifier
        ])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(data: data, response: response)

        let tokens = try parseTokens(from: data)
        try FitbitTokenStore.save(tokens)
        isConnected = true
        lastError = nil
    }

    private func refresh(using refreshToken: String) async throws -> FitbitTokens {
        guard let clientID = FitbitConfig.clientID else { throw AuthError.notConfigured }

        var request = URLRequest(url: FitbitConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        do {
            try Self.checkResponse(data: data, response: response)
        } catch {
            // If refresh fails (e.g. token revoked), wipe local state so the
            // user is prompted to reconnect rather than silently failing forever.
            FitbitTokenStore.clear()
            isConnected = false
            throw error
        }

        let tokens = try parseTokens(from: data)
        try FitbitTokenStore.save(tokens)
        isConnected = true
        return tokens
    }

    // MARK: - Helpers

    private func parseTokens(from data: Data) throws -> FitbitTokens {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
            let user_id: String?
        }

        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            return FitbitTokens(
                accessToken: decoded.access_token,
                refreshToken: decoded.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)),
                fitbitUserID: decoded.user_id ?? "-"
            )
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.tokenExchangeFailed("decode: \(error.localizedDescription) — body: \(body)")
        }
    }

    private func formEncoded(_ params: [String: String]) -> String {
        params
            .map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }
            .joined(separator: "&")
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func checkResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    // MARK: - PKCE

    static func makePKCEVerifier() -> String {
        // 64 bytes → 86-char base64url string, well within Fitbit's 43–128 range.
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func pkceChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makeRandomString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset.randomElement()!)
        }
        return result
    }
}

// MARK: - Presentation context provider

extension FitbitAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the first foreground active window; fall back to a new ASPresentationAnchor.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }
}
