//
//  HomeLayout.swift
//  Dialed
//
//  Which Home cards show and in what order. Saved as plain strings so an
//  older layout never fails to load, and a card added in an update shows
//  up in its default spot instead of vanishing. Pure Foundation, tested.
//

import Foundation

enum HomeSection: String, CaseIterable, Identifiable {
    case morning, finalPush, wrapped, hero, today, quests, mile, challenge, race, sideBet, futureYou, workout, fun, tomorrow,
         weeklyReview, patterns, badges, paths, aiBrief, body, tiles, fuel, proteinPace, mealPlan, timeline, coach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:      return "Morning brief"
        case .finalPush:    return "Final push"
        case .wrapped:      return "Dialed Wrapped"
        case .hero:         return "Photo & vitals"
        case .today:        return "Dialed today"
        case .quests:       return "Daily quests"
        case .mile:         return "Mile a day"
        case .challenge:    return "Challenge"
        case .race:         return "Pace to win"
        case .sideBet:      return "Side bet"
        case .futureYou:    return "Future you"
        case .workout:      return "Today's workout"
        case .fun:          return "Fun stuff"
        case .tomorrow:     return "Tomorrow's wake-up"
        case .weeklyReview: return "Week in review"
        case .patterns:     return "Patterns"
        case .badges:       return "Badges"
        case .paths:        return "Paths"
        case .aiBrief:      return "AI brief"
        case .body:         return "Body state"
        case .tiles:        return "Health tiles"
        case .fuel:         return "Fuel"
        case .proteinPace:  return "Protein pace"
        case .mealPlan:     return "Next planned meal"
        case .timeline:     return "Timeline"
        case .coach:        return "Coach"
        }
    }

    var icon: String {
        switch self {
        case .morning:      return "sun.horizon.fill"
        case .finalPush:    return "flame.fill"
        case .wrapped:      return "gift.fill"
        case .hero:         return "person.crop.circle.fill"
        case .today:        return "gauge.with.dots.needle.67percent"
        case .quests:       return "checklist.checked"
        case .mile:         return "figure.walk"
        case .challenge:    return "flag.2.crossed.fill"
        case .race:         return "speedometer"
        case .sideBet:      return "dice.fill"
        case .futureYou:    return "sparkles"
        case .workout:      return "dumbbell.fill"
        case .fun:          return "figure.pickleball"
        case .tomorrow:     return "alarm.fill"
        case .weeklyReview: return "calendar.badge.checkmark"
        case .patterns:     return "chart.bar.xaxis"
        case .badges:       return "trophy.fill"
        case .paths:        return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .aiBrief:      return "apple.intelligence"
        case .body:         return "waveform.path.ecg"
        case .tiles:        return "square.grid.2x2.fill"
        case .fuel:         return "fork.knife"
        case .proteinPace:  return "bolt.heart.fill"
        case .mealPlan:     return "calendar.day.timeline.left"
        case .timeline:     return "clock.fill"
        case .coach:        return "bubble.left.and.text.bubble.right.fill"
        }
    }

    /// When a card only appears some of the time.
    var note: String? {
        switch self {
        case .morning:      return "Mornings until noon"
        case .finalPush:    return "Last 14 days of a challenge"
        case .wrapped:      return "Around the challenge's end"
        case .tomorrow:     return "Evenings"
        case .weeklyReview: return "Sundays and Mondays"
        case .race:         return "During a challenge"
        case .patterns:     return "Once there's enough data"
        default:            return nil
        }
    }
}

struct HomeLayout: Equatable {
    var order: [HomeSection]
    var hidden: Set<HomeSection>

    static let standard = HomeLayout(order: HomeSection.allCases, hidden: [])

    var visible: [HomeSection] { order.filter { !hidden.contains($0) } }

    /// From saved strings: unknown names dropped, duplicates removed, and
    /// any section the saved order doesn't know about slotted in right
    /// after the section it follows by default.
    init(savedOrder: [String], savedHidden: [String]) {
        var order: [HomeSection] = []
        for raw in savedOrder {
            if let s = HomeSection(rawValue: raw), !order.contains(s) { order.append(s) }
        }
        for (i, s) in HomeSection.allCases.enumerated() where !order.contains(s) {
            let before = HomeSection.allCases[..<i].last { order.contains($0) }
            let at = before.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            order.insert(s, at: at)
        }
        self.order = order
        hidden = Set(savedHidden.compactMap(HomeSection.init(rawValue:)))
    }

    init(order: [HomeSection], hidden: Set<HomeSection>) {
        self.order = order
        self.hidden = hidden
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { order[$0] }
        var rest = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let shift = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - shift)))
        order = rest
    }

    mutating func toggle(_ s: HomeSection) {
        if hidden.contains(s) { hidden.remove(s) } else { hidden.insert(s) }
    }

    // MARK: - Storage

    private static let orderKey = "home.layout.order"
    private static let hiddenKey = "home.layout.hidden"
    static let didChange = Notification.Name("HomeLayoutDidChange")

    static func load(_ defaults: UserDefaults = .standard) -> HomeLayout {
        guard let order = defaults.stringArray(forKey: orderKey) else { return .standard }
        return HomeLayout(savedOrder: order, savedHidden: defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: orderKey)
        defaults.removeObject(forKey: hiddenKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
