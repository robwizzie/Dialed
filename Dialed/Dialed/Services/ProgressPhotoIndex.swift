//
//  ProgressPhotoIndex.swift
//  Dialed
//
//  The JSON index behind progress photos: one entry per photo (date,
//  weight at the time if known, note, file name). Pure Foundation so the
//  grouping / ordering / codec are unit-tested; ProgressPhotoStore does
//  the file I/O. Photos never leave the device.
//

import Foundation

struct ProgressPhotoEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var fileName: String
    var weightLbs: Double?
    var note: String?

    init(id: UUID = UUID(), date: Date, fileName: String? = nil, weightLbs: Double? = nil, note: String? = nil) {
        self.id = id
        self.date = date
        self.fileName = fileName ?? "\(id.uuidString).jpg"
        self.weightLbs = weightLbs
        self.note = note
    }

    var thumbnailName: String { "thumb-\(fileName)" }
}

struct ProgressPhotoIndex: Codable, Equatable {
    var version: Int = 1
    /// Always oldest first.
    private(set) var entries: [ProgressPhotoEntry] = []

    init(entries: [ProgressPhotoEntry] = []) {
        self.entries = entries.sorted { $0.date < $1.date }
    }

    struct Week: Equatable, Identifiable {
        var id: Date { start }
        let start: Date
        /// Newest first within the week.
        let photos: [ProgressPhotoEntry]
    }

    var latest: ProgressPhotoEntry? { entries.last }
    var first: ProgressPhotoEntry? { entries.first }

    mutating func add(_ entry: ProgressPhotoEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort { $0.date < $1.date }
    }

    @discardableResult
    mutating func remove(id: UUID) -> ProgressPhotoEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: i)
    }

    mutating func update(id: UUID, weightLbs: Double?, note: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].weightLbs = weightLbs
        entries[i].note = note
    }

    func entry(id: UUID) -> ProgressPhotoEntry? {
        entries.first { $0.id == id }
    }

    /// The most recent photo taken before `date` — the ghost to line up with.
    func latest(before date: Date) -> ProgressPhotoEntry? {
        entries.last { $0.date < date }
    }

    /// Photos grouped into calendar weeks, newest week first.
    func weeks(calendar: Calendar = .current) -> [Week] {
        var byWeek: [Date: [ProgressPhotoEntry]] = [:]
        for e in entries {
            let start = calendar.dateInterval(of: .weekOfYear, for: e.date)?.start
                ?? calendar.startOfDay(for: e.date)
            byWeek[start, default: []].append(e)
        }
        return byWeek.keys.sorted(by: >).map { start in
            Week(start: start, photos: byWeek[start]!.sorted { $0.date > $1.date })
        }
    }

    /// Whether a photo was already taken this week.
    func hasPhoto(inWeekOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        return entries.contains { week.contains($0.date) }
    }

    /// Weight change between two photos when both carry a weight.
    static func weightChange(from a: ProgressPhotoEntry, to b: ProgressPhotoEntry) -> Double? {
        guard let wa = a.weightLbs, let wb = b.weightLbs else { return nil }
        return wb - wa
    }

    // MARK: - Codec

    static func decode(_ data: Data) -> ProgressPhotoIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProgressPhotoIndex.self, from: data)) ?? ProgressPhotoIndex()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey { case version, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let raw = try c.decodeIfPresent([ProgressPhotoEntry].self, forKey: .entries) ?? []
        entries = raw.sorted { $0.date < $1.date }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(entries, forKey: .entries)
    }
}
