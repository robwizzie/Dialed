//
//  WidgetTimeline.swift
//  DialedWidgets
//
//  One timeline for every Dialed widget. Reads what the app published to
//  the App Group (today's intake, Home's insights, the mood avatar) plus
//  taps still waiting in the queue, and lays out an entry per hour until
//  the 4 AM day line so pace markers move through the day without the
//  app running.
//

import SwiftUI
import WidgetKit

struct DialedEntry: TimelineEntry {
    let date: Date
    let today: WidgetSnapshot
    /// Nil until Home has refreshed once with the App Group.
    let insights: WidgetInsights?
    let avatar: UIImage?
    var water: WaterPreset = .glasses
    /// The daily mile, per day (from the app's MileHistory).
    var mile: MileHistory? = nil

    var mileGoal: Double { MileSettings.load().goalMiles }
    /// The last seven days, oldest → today.
    var mileWeek: [MileDay] { mile?.last(7, today: date) ?? [] }
    var milesToday: Double { mileWeek.last?.miles ?? insights?.miles ?? 0 }
    var ranToday: Bool { mileWeek.last?.ran ?? false }
    var mileDone: Bool { MileADay.isDone(milesToday, goal: mileGoal) }
    var mileStreak: Int { mile?.currentStreak(today: date, goal: mileGoal) ?? insights?.mileStreak ?? 0 }
    /// "0.62/1 mi".
    var mileShort: String { String(format: "%.2f/", milesToday) + MileADay.format(mileGoal) }

    /// Share of the day's targets you'd have by now (7 AM → 9 PM), the same
    /// curve the app's day score uses.
    var pace: Double {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        return max(0, min(1, (hour - 7) / 14))
    }

    /// Ounces behind where you should be by now (0 when on pace).
    var waterBehind: Double { max(0, today.waterTargetOz * pace - today.waterOz) }

    var waterStatus: (text: String, icon: String, onTrack: Bool) {
        if today.waterProgress >= 1 { return ("Goal hit", "checkmark", true) }
        if waterBehind < 6 { return ("On pace", "bolt.fill", true) }
        return ("\(Fmt.int(waterBehind)) oz behind", "arrow.down.right", false)
    }

    static let preview = DialedEntry(date: Date(), today: .placeholder, insights: .placeholder, avatar: nil,
                                     mile: .placeholder)
}

enum DialedTimeline {
    static func entries(preview: Bool, water: WaterPreset = .glasses, now: Date = Date()) -> [DialedEntry] {
        let bridge = WidgetBridge()
        let stored = bridge.readSnapshot()
        let insights = bridge.readInsights()
        if preview && stored == nil {
            return [DialedEntry(date: now, today: .placeholder, insights: .placeholder, avatar: nil, water: water,
                                mile: .placeholder)]
        }
        let pending = bridge.pending()
        let avatar = WidgetBridge.avatarURL.flatMap { UIImage(contentsOfFile: $0.path) }
        let mile = MileHistory.load()

        return dates(from: now).map { date in
            DialedEntry(
                date: date,
                today: stored?.display(with: pending, now: date) ?? .empty,
                insights: insights?.display(now: date),
                avatar: avatar,
                water: water,
                mile: mile
            )
        }
    }

    static func timeline(water: WaterPreset = .glasses) -> Timeline<DialedEntry> {
        Timeline(entries: entries(preview: false, water: water), policy: .atEnd)
    }

    /// Now, then every hour on the hour through the next 4 AM rollover.
    static func dates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = WidgetBridge.logicalDay(for: now, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        let rollover = calendar.date(byAdding: .hour, value: WidgetBridge.dayCutoffHour, to: tomorrow)
            ?? now.addingTimeInterval(86_400)
        var dates = [now]
        var next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? rollover
        while next <= rollover {
            dates.append(next)
            next = next.addingTimeInterval(3_600)
        }
        if dates.last != rollover { dates.append(rollover) }
        return dates
    }
}

extension WidgetSnapshot {
    /// Before the app has run once with the App Group.
    static var empty: WidgetSnapshot {
        WidgetSnapshot(waterOz: 0, waterTargetOz: 120, protein: 0, proteinTarget: 190,
                       calories: 0, calorieTarget: 2_200, favorites: [], updatedAt: .distantPast, meals: [])
    }
}

// MARK: - Providers

struct DialedProvider: TimelineProvider {
    func placeholder(in context: Context) -> DialedEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (DialedEntry) -> Void) {
        completion(DialedTimeline.entries(preview: context.isPreview).first ?? .preview)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DialedEntry>) -> Void) {
        completion(DialedTimeline.timeline())
    }
}

/// The Water widget lets you pick the pour sizes on its buttons.
struct WaterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DialedEntry { .preview }

    func snapshot(for configuration: WaterWidgetConfiguration, in context: Context) async -> DialedEntry {
        DialedTimeline.entries(preview: context.isPreview, water: configuration.pours).first ?? .preview
    }

    func timeline(for configuration: WaterWidgetConfiguration, in context: Context) async -> Timeline<DialedEntry> {
        DialedTimeline.timeline(water: configuration.pours)
    }
}
