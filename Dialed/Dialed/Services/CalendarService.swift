//
//  CalendarService.swift
//  Dialed
//
//  Your calendars, read-only: Apple Calendar through EventKit (which also
//  carries Google, Outlook or iCloud calendars you've added in iOS
//  Settings › Calendar › Accounts — the easiest way to bring Google in),
//  plus Google Calendar directly through its API when you connect it.
//  Both are merged so an event synced to each shows once. Feeds the
//  wake-up suggestions and the Schedule screen.
//

import Foundation
import EventKit
import AuthenticationServices
import UIKit
import UserNotifications

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String?
        /// "iCloud", "Gmail", "Google Calendar"…
        let account: String
        let source: PlannedEvent.Source
    }

    @Published private(set) var appleAccess = CalendarService.appleAuthorized
    @Published private(set) var events: [PlannedEvent] = []
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var loadedAt: Date?
    @Published private(set) var lastError: String?

    static var appleAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isConnected: Bool { appleAccess || GoogleCalendarAuth.shared.isConnected }

    // MARK: - Apple Calendar

    @discardableResult
    func requestAppleAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            appleAccess = granted
            if granted { await refresh(force: true) }
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func appleCalendars() -> [CalendarInfo] {
        guard Self.appleAuthorized else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hex($0.cgColor),
                         account: $0.source?.title ?? "", source: .apple)
        }
    }

    private func appleEvents(from start: Date, to end: Date) -> [PlannedEvent] {
        guard Self.appleAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { e in
            PlannedEvent(id: "apple-" + (e.calendarItemIdentifier) + "-\(Int(e.startDate.timeIntervalSince1970))",
                         title: e.title ?? "Busy", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                         calendarID: e.calendar?.calendarIdentifier ?? "", calendarTitle: e.calendar?.title ?? "",
                         colorHex: Self.hex(e.calendar?.cgColor), location: e.location, notes: e.notes, source: .apple)
        }
    }

    // MARK: - Refresh

    /// The next `days` days from all connected sources (the past day too,
    /// so "today" on the Schedule screen is whole). Cached for 10 minutes.
    func refresh(force: Bool = false, days: Int = 14) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 600 { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: days + 1, to: start) ?? start
        appleAccess = Self.appleAuthorized
        lastError = nil

        var google: [PlannedEvent] = []
        var googleCals: [CalendarInfo] = []
        if GoogleCalendarAuth.shared.isConnected {
            do {
                let result = try await GoogleCalendarAPI.events(from: start, to: end)
                google = result.events
                googleCals = result.calendars
            } catch {
                lastError = "Google Calendar: \(error.localizedDescription)"
            }
        }
        calendars = appleCalendars() + googleCals
        events = WakeSuggestionEngine.merge(appleEvents(from: start, to: end), google)
        loadedAt = Date()
        NotificationCenter.default.post(name: Self.didRefresh, object: nil)
        await WakeSuggestionStore.scheduleEveningReminder()
    }

    static let didRefresh = Notification.Name("CalendarServiceDidRefresh")

    /// Events on one day, in the calendars you've switched on.
    func events(on day: Date, prefs: CalendarPrefs = .load()) -> [PlannedEvent] {
        events.filter { prefs.includes($0.calendarID) && WakeSuggestionEngine.occurs($0, on: day) }
    }

    // MARK: - Helpers

    static func hex(_ color: CGColor?) -> String? {
        guard let color, let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

// MARK: - Suggestions: accept, ignore, remind

@MainActor
enum WakeSuggestionStore {
    private static let dismissedKey = "calendar.wakeSuggestions.dismissed"
    private static let reminderID = "wake_suggestion_evening"

    static var dismissed: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    /// Pending suggestions for the next two weeks.
    static func current(now: Date = Date()) -> [WakeSuggestionEngine.Suggestion] {
        WakeSuggestionEngine.suggestions(schedule: WakeSchedule.load(), events: CalendarService.shared.events,
                                         prefs: .load(), from: now, dismissed: dismissed)
    }

    /// Use it: that one day's wake-up changes (and the alarm follows).
    static func accept(_ s: WakeSuggestionEngine.Suggestion) {
        var schedule = WakeSchedule.load()
        schedule.setDay(s.suggested, on: s.date)
        schedule.save()
        Task { await scheduleEveningReminder() }
    }

    static func ignore(_ s: WakeSuggestionEngine.Suggestion) {
        let today = WakeSchedule.key(Date())
        // Keep the list short: drop ignored suggestions for past days.
        var ids = dismissed.filter { $0.prefix(10) >= today }
        ids.insert(s.id)
        UserDefaults.standard.set(Array(ids), forKey: dismissedKey)
        NotificationCenter.default.post(name: CalendarService.didRefresh, object: nil)
        Task { await scheduleEveningReminder() }
    }

    /// 8 PM heads-up when tomorrow has a pending suggestion.
    static func scheduleEveningReminder(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard CalendarPrefs.load().eveningReminder else { return }
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let s = current(now: now).first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) }),
              let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now), fire > now else { return }
        let content = UNMutableNotificationContent()
        content.title = s.kind == .earlier
            ? "Earlier start tomorrow"
            : "Sleep in tomorrow?"
        content.body = "\(s.reason) Wake at \(WakeSchedule.clock(s.suggested)) instead of \(s.current.map(WakeSchedule.clock) ?? "no alarm")? Open Dialed to accept."
        content.sound = .default
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: reminderID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

// MARK: - Google Calendar (direct)

/// A separate Google sign-in just for Calendar (read-only), so connecting
/// it never re-asks for Health permissions and vice versa. Uses the same
/// iOS OAuth client as Google Health.
@MainActor
final class GoogleCalendarAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleCalendarAuth()
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let tokenKey = "googleCalendar.tokens.v1"

    @Published private(set) var isConnected = GoogleCalendarAuth.loadTokens() != nil
    private var session: ASWebAuthenticationSession?

    private static func loadTokens() -> GoogleHealthTokens? {
        guard let data = try? KeychainStore.data(forKey: tokenKey) else { return nil }
        return try? JSONDecoder().decode(GoogleHealthTokens.self, from: data)
    }

    private static func saveTokens(_ t: GoogleHealthTokens) throws {
        try KeychainStore.setData(JSONEncoder().encode(t), forKey: tokenKey)
    }

    func disconnect() {
        _ = KeychainStore.remove(forKey: Self.tokenKey)
        isConnected = false
    }

    func connect() async throws {
        guard let clientID = GoogleHealthConfig.clientID,
              let scheme = GoogleHealthConfig.callbackScheme,
              let redirectURI = GoogleHealthConfig.redirectURI else {
            throw GoogleHealthAuth.AuthError.notConfigured
        }
        let verifier = GoogleHealthAuth.makePKCEVerifier()
        let state = GoogleHealthAuth.makePKCEVerifier()
        var components = URLComponents(url: GoogleHealthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: GoogleHealthAuth.pkceChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw GoogleHealthAuth.AuthError.notConfigured }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let error { continuation.resume(throwing: error); return }
                if let url { continuation.resume(returning: url) } else {
                    continuation.resume(throwing: GoogleHealthAuth.AuthError.noCode(nil))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleHealthAuth.AuthError.tokenExchangeFailed("couldn't open the Google sign-in sheet"))
            }
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw GoogleHealthAuth.AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleHealthAuth.AuthError.noCode(items.first(where: { $0.name == "error" })?.value)
        }
        let tokens = try await Self.tokenRequest([
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirectURI
        ], previousRefresh: nil)
        try Self.saveTokens(tokens)
        isConnected = true
    }

    func validAccessToken() async throws -> String {
        guard let tokens = Self.loadTokens() else { throw GoogleHealthAuth.AuthError.notConnected }
        if !tokens.isExpired { return tokens.accessToken }
        guard let clientID = GoogleHealthConfig.clientID else { throw GoogleHealthAuth.AuthError.notConfigured }
        do {
            let fresh = try await Self.tokenRequest([
                "client_id": clientID, "grant_type": "refresh_token", "refresh_token": tokens.refreshToken
            ], previousRefresh: tokens.refreshToken)
            try Self.saveTokens(fresh)
            return fresh.accessToken
        } catch {
            disconnect()
            throw error
        }
    }

    private static func tokenRequest(_ params: [String: String], previousRefresh: String?) async throws -> GoogleHealthTokens {
        var request = URLRequest(url: GoogleHealthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = params
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleHealthAuth.AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "")
        }
        struct TokenResponse: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Int }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token ?? previousRefresh else {
            throw GoogleHealthAuth.AuthError.tokenExchangeFailed("no refresh token returned")
        }
        return GoogleHealthTokens(accessToken: decoded.access_token, refreshToken: refresh,
                                  expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)))
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

/// Calendar API v3: your calendar list, then each selected calendar's
/// events (single instances, so repeating events expand).
enum GoogleCalendarAPI {
    private static let base = "https://www.googleapis.com/calendar/v3/"

    private struct CalendarList: Decodable {
        struct Item: Decodable {
            let id: String
            let summary: String?
            let summaryOverride: String?
            let backgroundColor: String?
            let selected: Bool?
            let primary: Bool?
        }
        let items: [Item]?
    }

    private struct EventList: Decodable {
        struct When: Decodable { let dateTime: String?; let date: String? }
        struct Item: Decodable {
            let id: String
            let summary: String?
            let status: String?
            let location: String?
            let description: String?
            let start: When?
            let end: When?
        }
        let items: [Item]?
        let nextPageToken: String?
    }

    @MainActor
    static func events(from start: Date, to end: Date) async throws -> (events: [PlannedEvent], calendars: [CalendarService.CalendarInfo]) {
        let token = try await GoogleCalendarAuth.shared.validAccessToken()
        let list: CalendarList = try await get("users/me/calendarList?minAccessRole=reader", token: token)
        // Primary plus the calendars you show in Google Calendar.
        let cals = (list.items ?? []).filter { $0.primary == true || $0.selected == true }
        var out: [PlannedEvent] = []
        var infos: [CalendarService.CalendarInfo] = []
        let iso = ISO8601DateFormatter()
        for cal in cals {
            let title = cal.summaryOverride ?? cal.summary ?? "Google Calendar"
            infos.append(.init(id: "google-" + cal.id, title: title, colorHex: cal.backgroundColor,
                               account: "Google Calendar", source: .google))
            let id = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "@/"))) ?? cal.id
            var pageToken: String?
            repeat {
                var path = "calendars/\(id)/events?singleEvents=true&orderBy=startTime&maxResults=250"
                path += "&timeMin=\(iso.string(from: start))&timeMax=\(iso.string(from: end))"
                    .replacingOccurrences(of: "+", with: "%2B")
                if let pageToken { path += "&pageToken=\(pageToken)" }
                let page: EventList = try await get(path, token: token)
                for e in page.items ?? [] where e.status != "cancelled" {
                    guard let (s, f, allDay) = times(e.start, e.end) else { continue }
                    out.append(PlannedEvent(id: "google-\(e.id)", title: e.summary ?? "Busy", start: s, end: f,
                                            isAllDay: allDay, calendarID: "google-" + cal.id, calendarTitle: title,
                                            colorHex: cal.backgroundColor, location: e.location,
                                            notes: e.description, source: .google))
                }
                pageToken = page.nextPageToken
            } while pageToken != nil && out.count < 2_000
        }
        return (out, infos)
    }

    /// RFC 3339 dateTime for timed events, "yyyy-MM-dd" for all-day ones
    /// (end date exclusive, in your time zone).
    private static func times(_ start: EventList.When?, _ end: EventList.When?) -> (Date, Date, Bool)? {
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let s = start?.dateTime, let e = end?.dateTime,
           let sd = iso.date(from: s) ?? isoFrac.date(from: s), let ed = iso.date(from: e) ?? isoFrac.date(from: e) {
            return (sd, ed, false)
        }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        if let s = start?.date, let e = end?.date, let sd = day.date(from: s), let ed = day.date(from: e) {
            return (sd, ed, true)
        }
        return nil
    }

    private static func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleHealthAuth.AuthError.tokenExchangeFailed("Calendar HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) \(body.prefix(200))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
