//
//  PulseSessionStore.swift
//  Dialed
//
//  Pulse Check sessions: start one when the movie starts, tap when
//  something gets you, end it when the credits roll. Heart rate comes
//  afterwards from Apple Health and Google Health (Pixel Watch) for the
//  exact window — watches sync on their own schedule, so a session with
//  no data yet is re-checked until it shows up.
//
//  Kept as a JSON file in Documents rather than a SwiftData model: it's a
//  self-contained list (dozens of sessions, a few thousand readings each)
//  and staying out of the shared schema means no migration risk.
//

import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

struct PulseSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var template: PulseTemplate
    var title: String
    var subtitle: String?
    var posterURL: URL?
    var start: Date
    var end: Date?
    /// Taps on the big button, in seconds since start.
    var marks: [Double] = []
    var samples: [PulseAnalyzer.Sample] = []
    var result: PulseAnalyzer.Result?
    /// Last time we asked the watches for this window.
    var fetchedAt: Date?
    /// 0–10: how good it was.
    var rating: Double?
    /// 0–10: how scared (stressed, hyped…) you felt.
    var felt: Double?
    var notes: String = ""

    var isLive: Bool { end == nil }
    var duration: Double { (end ?? Date()).timeIntervalSince(start) }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end ?? Date())) }
    var score: Int { result?.score ?? 0 }
    var hasHeartRate: Bool { result?.hasData ?? false }

    /// Still worth asking the watches again: ended within the last day with no readings yet.
    var awaitingSync: Bool {
        guard let end, !hasHeartRate else { return false }
        return Date().timeIntervalSince(end) < 24 * 3600
    }
}

@MainActor
final class PulseSessionStore: ObservableObject {
    static let shared = PulseSessionStore()

    @Published private(set) var sessions: [PulseSession] = []
    /// Latest live reading while a session runs.
    @Published private(set) var live: (bpm: Double, at: Date)?
    @Published private(set) var liveSamples: [PulseAnalyzer.Sample] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("pulse_sessions.json")
    }()

    private init() { load() }

    var active: PulseSession? { sessions.first { $0.isLive } }

    func session(_ id: UUID) -> PulseSession? { sessions.first { $0.id == id } }

    /// Finished sessions of one template, best (scariest / calmest) first.
    func leaderboard(_ template: PulseTemplate) -> [PulseSession] {
        let done = sessions.filter { $0.template == template && !$0.isLive && $0.hasHeartRate }
        let order = PulseAnalyzer.rank(done.map { .init(id: $0.id.uuidString, score: $0.score, biggest: $0.result?.biggest?.delta ?? 0) })
        return order.compactMap { id in done.first { $0.id.uuidString == id } }
    }

    /// 1-based place of a session on its template's board.
    func place(of session: PulseSession) -> Int? {
        leaderboard(session.template).firstIndex { $0.id == session.id }.map { $0 + 1 }
    }

    /// Windows to leave out of Suggested activity: a scary movie isn't exercise.
    func intervals(on day: Date, calendar: Calendar = .current) -> [DateInterval] {
        let start = calendar.startOfDay(for: day)
        let dayWindow = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        return sessions.map(\.interval).filter { $0.intersects(dayWindow) }
    }

    // MARK: - Running a session

    @discardableResult
    func start(_ template: PulseTemplate, title: String, subtitle: String? = nil, posterURL: URL? = nil) -> PulseSession {
        // One at a time: starting a new one ends the old.
        if let running = active { end(running.id) }
        let s = PulseSession(template: template, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.title : title,
                             subtitle: subtitle, posterURL: posterURL, start: Date())
        sessions.insert(s, at: 0)
        live = nil
        liveSamples = []
        save()
        return s
    }

    func mark(_ id: UUID) {
        update(id) { $0.marks.append(Date().timeIntervalSince($0.start)) }
    }

    func end(_ id: UUID) {
        update(id) { $0.end = Date() }
        live = nil
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func setRating(_ id: UUID, rating: Double?) { update(id) { $0.rating = rating } }
    func setFelt(_ id: UUID, felt: Double?) { update(id) { $0.felt = felt } }
    func setNotes(_ id: UUID, notes: String) { update(id) { $0.notes = notes } }
    func rename(_ id: UUID, title: String) { update(id) { $0.title = title } }

    // MARK: - Heart rate

    /// The last ten minutes, for the live screen. Watches lag, so the latest
    /// reading may be a few minutes old; the screen says how old.
    func pollLive(context: ModelContext) async {
        guard let s = active else { return }
        let from = max(s.start, Date().addingTimeInterval(-10 * 60))
        let readings = await PulseHeartRate.samples(from: from.addingTimeInterval(-60), to: Date(), context: context)
        guard let last = readings.max(by: { $0.date < $1.date }) else { return }
        live = (last.bpm, last.date)
        var merged = liveSamples
        for r in readings {
            let t = r.date.timeIntervalSince(s.start)
            if !merged.contains(where: { abs($0.t - t) < 1 }) { merged.append(.init(t: t, bpm: r.bpm)) }
        }
        liveSamples = merged.sorted { $0.t < $1.t }
    }

    /// The full window from the watches, analyzed. Safe to call again later
    /// when the watch hadn't synced yet.
    func fetchHeartRate(_ id: UUID, context: ModelContext) async {
        guard let s = session(id), let end = s.end else { return }
        let readings = await PulseHeartRate.samples(from: s.start.addingTimeInterval(-5 * 60), to: end.addingTimeInterval(60), context: context)
        let samples = readings.map { PulseAnalyzer.Sample(t: $0.date.timeIntervalSince(s.start), bpm: $0.bpm) }
            .sorted { $0.t < $1.t }
        update(id) {
            $0.fetchedAt = Date()
            if samples.count >= max(3, $0.samples.count) { $0.samples = samples }
            $0.result = PulseAnalyzer.analyze($0.samples, duration: end.timeIntervalSince(s.start),
                                              marks: $0.marks, direction: s.template.direction)
        }
    }

    /// Re-ask the watches for recent sessions that had no readings yet.
    func refreshPending(context: ModelContext) async {
        for s in sessions where s.awaitingSync {
            if let at = s.fetchedAt, Date().timeIntervalSince(at) < 120 { continue }
            await fetchHeartRate(s.id, context: context)
        }
    }

    // MARK: - Storage

    private func update(_ id: UUID, _ change: (inout PulseSession) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[i])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([PulseSession].self, from: data) else { return }
        sessions = list.sorted { $0.start > $1.start }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Heart rate for a window from Apple Health and Google Health, merged.
@MainActor
enum PulseHeartRate {
    struct Reading { let date: Date; let bpm: Double }

    static func samples(from start: Date, to end: Date, context: ModelContext) async -> [Reading] {
        var out: [Reading] = []
        #if canImport(HealthKit)
        let unit = HKUnit.count().unitDivided(by: .minute())
        if let hk = try? await HealthKitManager.shared.fetchSamples(.heartRate, unit: unit, from: start, to: end) {
            out += hk.map { Reading(date: $0.date, bpm: $0.value) }
        }
        #endif
        if GoogleHealthSyncService.isConnected {
            out += await GoogleHealthSyncService(modelContext: context).heartRate(from: start, to: end)
                .map { Reading(date: $0.date, bpm: $0.bpm) }
        }
        // Two sources can report the same second; keep one.
        var seen = Set<Int>()
        return out.sorted { $0.date < $1.date }.filter { seen.insert(Int($0.date.timeIntervalSince1970)).inserted }
    }
}

// MARK: - Movie search (iTunes)

enum MovieSearch {
    struct Movie: Identifiable, Equatable {
        let id: Int
        let title: String
        let year: String?
        let genre: String?
        let poster: URL?
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let releaseDate: String?
            let primaryGenreName: String?
            let artworkUrl100: String?
        }
        let results: [Item]
    }

    static func search(_ term: String) async -> [Movie] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, var c = URLComponents(string: "https://itunes.apple.com/search") else { return [] }
        c.queryItems = [.init(name: "term", value: q), .init(name: "media", value: "movie"),
                        .init(name: "entity", value: "movie"), .init(name: "limit", value: "15")]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return r.results.compactMap { i in
            guard let id = i.trackId, let title = i.trackName else { return nil }
            // Bigger artwork than the 100 px thumbnail the API returns.
            let poster = i.artworkUrl100.map { $0.replacingOccurrences(of: "100x100bb", with: "600x600bb") }.flatMap(URL.init(string:))
            return Movie(id: id, title: title, year: i.releaseDate.map { String($0.prefix(4)) },
                         genre: i.primaryGenreName, poster: poster)
        }
    }
}
