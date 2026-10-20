//
//  ChallengeSync.swift
//  Dialed
//
//  Live challenge: puts your challenge on your own small server
//  (challenge-worker/, a Cloudflare Worker) so your friend can post
//  weigh-ins and trash talk from an invite link in any browser. Your scale
//  readings upload automatically; theirs flow back into the scoreboard.
//
//  The server URL is yours (set once after deploying). Your owner token
//  lives in the Keychain; the friend's token only exists in the invite link.
//

import Foundation
import HealthKit
#if canImport(Combine)
import Combine
#endif

@MainActor
final class ChallengeSync: ObservableObject {
    static let shared = ChallengeSync()

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }
    @Published var createKey: String {
        didSet { UserDefaults.standard.set(createKey, forKey: Keys.createKey) }
    }
    @Published private(set) var challengeID: String?
    @Published private(set) var inviteURL: URL?
    @Published private(set) var state: ChallengeWire.State?
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published var lastError: String?

    private enum Keys {
        static let baseURL = "challengeSync.baseURL"
        static let createKey = "challengeSync.createKey"
        static let id = "challengeSync.id"
        static let invite = "challengeSync.invite"
        static let token = "challengeSync.ownerToken"
    }

    private init() {
        let d = UserDefaults.standard
        baseURL = d.string(forKey: Keys.baseURL) ?? ""
        createKey = d.string(forKey: Keys.createKey) ?? ""
        challengeID = d.string(forKey: Keys.id)
        inviteURL = d.string(forKey: Keys.invite).flatMap(URL.init(string:))
    }

    var isLive: Bool { challengeID != nil && token != nil }

    /// Whether a live challenge was set up, readable off the main actor
    /// (background refresh scheduling).
    nonisolated static var hasLiveChallenge: Bool {
        UserDefaults.standard.string(forKey: "challengeSync.id") != nil
    }
    var messages: [ChallengeWire.Message] { state?.messages ?? [] }
    /// Your friend's side, summarized for the Challenge tab.
    var other: ChallengeWire.OtherSide? { state.map { ChallengeWire.otherSide($0) } }

    private var token: String? { try? KeychainStore.string(forKey: Keys.token) }

    private var server: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
    }

    // MARK: - Create / disconnect

    /// Puts the challenge on your server and returns the invite link.
    @discardableResult
    func create(challenge: WeightChallenge, ownerName: String, ownerStart: Double?) async -> URL? {
        guard let server else { lastError = "Add your challenge server address first."; return nil }
        let body = ChallengeWire.CreateRequest(
            ownerName: ownerName.isEmpty ? "Me" : ownerName,
            friendName: challenge.friendDisplayName,
            startDate: ChallengeWire.dayKey(challenge.startDate),
            endDate: ChallengeWire.dayKey(challenge.endDate),
            ownerStart: ownerStart,
            friendStart: challenge.friendStartWeight)
        var request = URLRequest(url: server.appendingPathComponent("api/challenges"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !createKey.isEmpty { request.setValue(createKey, forHTTPHeaderField: "x-create-key") }
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let created: ChallengeWire.CreateResponse = try await send(request)
            try? KeychainStore.setString(created.ownerToken, forKey: Keys.token)
            challengeID = created.id
            inviteURL = URL(string: created.inviteUrl)
            UserDefaults.standard.set(created.id, forKey: Keys.id)
            UserDefaults.standard.set(created.inviteUrl, forKey: Keys.invite)
            lastError = nil
            return inviteURL
        } catch {
            lastError = "Couldn't create the live challenge: \(error.localizedDescription)"
            return nil
        }
    }

    /// Stops syncing on this phone (the server copy stays until you delete it).
    func disconnect() {
        _ = KeychainStore.remove(forKey: Keys.token)
        UserDefaults.standard.removeObject(forKey: Keys.id)
        UserDefaults.standard.removeObject(forKey: Keys.invite)
        challengeID = nil
        inviteURL = nil
        state = nil
        lastSync = nil
    }

    // MARK: - Sync

    /// Upload your weigh-ins, pull your friend's, and fold them into the
    /// local challenge. Throttled to once a minute unless `force`.
    func sync(readings: [WeightReading], force: Bool = false) async {
        guard isLive, let challenge = WeightChallenge.load(), !isSyncing else { return }
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < 60 { return }
        isSyncing = true
        defer { isSyncing = false }

        let uploads = ChallengeWire.uploads(from: readings.map { ($0.date, $0.pounds) },
                                            start: challenge.startDate, end: challenge.endDate)
        do {
            let fresh: ChallengeWire.State
            if uploads.isEmpty {
                fresh = try await send(authorized("", method: "GET"))
            } else {
                var request = authorized("/weighins", method: "PUT")
                request.httpBody = try JSONEncoder().encode(ChallengeWire.WeighInBatch(weighins: uploads))
                fresh = try await send(request)
            }
            apply(fresh)
            lastError = nil
        } catch {
            lastError = "Sync failed: \(error.localizedDescription)"
            return
        }
        await pushStats(challenge: challenge)
    }

    /// Your stats card for the shared page; only sent when it changed.
    private var lastStats: ChallengeWire.OwnerStats?

    private func pushStats(challenge: WeightChallenge) async {
        let calendar = Calendar.current
        let doneDays = (UserDefaults.standard.string(forKey: "workout.doneDays") ?? "")
            .split(separator: ",").map(String.init)
        let workouts = ChallengeWire.workoutCounts(doneDays: doneDays)
        let steps = (try? await HealthKitManager.shared.fetchDailySums(.stepCount, unit: .count(), days: 7)) ?? [:]
        let today = calendar.startOfDay(for: Date())
        let past = steps.filter { $0.key < today }.map(\.value)
        let event = GoalEvent.load()
        let stats = ChallengeWire.OwnerStats(
            goalLossLbs: challenge.goalLossLbs,
            scoring: challenge.scoring.rawValue,
            stepsAvg7: past.isEmpty ? nil : (past.reduce(0, +) / Double(past.count)).rounded(),
            stepsToday: steps[today].map { $0.rounded() },
            workoutsWeek: workouts.week,
            workoutsTotal: workouts.total,
            goalDayName: event?.name,
            goalDayDate: event.map { ChallengeWire.dayKey($0.date) })
        guard stats != lastStats else { return }
        do {
            var request = authorized("/stats", method: "PUT")
            request.httpBody = try JSONEncoder().encode(stats)
            let fresh: ChallengeWire.State = try await send(request)
            state = fresh
            lastStats = stats
        } catch {
            // Stats are a nice-to-have; the next sync retries.
        }
    }

    func post(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLive, !trimmed.isEmpty else { return }
        struct Body: Encodable { let text: String }
        do {
            var request = authorized("/messages", method: "POST")
            request.httpBody = try JSONEncoder().encode(Body(text: String(trimmed.prefix(280))))
            apply(try await send(request))
        } catch {
            lastError = "Couldn't send: \(error.localizedDescription)"
        }
    }

    private func apply(_ fresh: ChallengeWire.State) {
        state = fresh
        lastSync = Date()
        guard let local = WeightChallenge.load() else { return }
        let merged = ChallengeWire.merge(fresh, into: local)
        // Only save real changes — saving posts didChangeNotification,
        // which refreshes the Challenge tab, which syncs again.
        if merged != local { merged.save() }
    }

    // MARK: - HTTP

    private struct ServerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ServerFailure: Decodable { let error: String }

    private func authorized(_ path: String, method: String) -> URLRequest {
        let base = server?.appendingPathComponent("api/challenges/\(challengeID ?? "")\(path)")
        var request = URLRequest(url: base ?? URL(string: "https://invalid.invalid")!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ServerFailure.self, from: data))?.error ?? "HTTP \(status)"
            throw ServerError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
