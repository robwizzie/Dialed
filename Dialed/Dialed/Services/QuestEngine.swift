//
//  QuestEngine.swift
//  Dialed
//
//  Three small missions a day ("30 g of protein before 11", "20 oz of
//  water before noon", "a 10-minute walk after dinner"), picked from the
//  date so they're the same all day, skipping ones that don't fit (no
//  workout quest on a rest day). Most check themselves off from your data;
//  the few Dialed can't see are a tap to claim. Points add up to levels
//  with names. Pure Foundation, tested.
//

import Foundation

enum QuestEngine {

    enum Kind: String, CaseIterable {
        case proteinBreakfast, waterBeforeNoon, eveningWalk, logEveryMeal, morningWeighIn, finishWorkout,
             hitProtein, bedOnTime, steps8k, kitchenClosed, mileDone, inBudget, hitWater, earlyMile

        /// Quests from different groups make a better mix.
        enum Group { case food, move, body }

        var group: Group {
            switch self {
            case .proteinBreakfast, .logEveryMeal, .hitProtein, .kitchenClosed, .inBudget: return .food
            case .eveningWalk, .finishWorkout, .steps8k, .mileDone, .earlyMile:            return .move
            case .waterBeforeNoon, .morningWeighIn, .bedOnTime, .hitWater:                 return .body
            }
        }
    }

    struct Quest: Equatable, Identifiable {
        var kind: Kind
        var title: String
        var detail: String
        var symbol: String
        var points: Int
        /// Dialed can't check it; you tap to claim.
        var selfReported: Bool = false
        var id: String { kind.rawValue }
    }

    /// What Dialed knows about today so far.
    struct Facts: Equatable {
        var now: Date
        var proteinBefore11: Double = 0
        var waterBeforeNoonOz: Double = 0
        /// Steps between 6 and 9 PM.
        var eveningSteps: Double = 0
        var steps: Double = 0
        /// Breakfast / lunch / dinner slots with something logged.
        var mealSlotsLogged = 0
        var weighInTime: Date?
        var workoutDone = false
        var isWorkoutDay = true
        var protein: Double = 0
        var proteinTarget: Double = 150
        var waterOz: Double = 0
        var waterTarget: Double = 100
        var lastMealTime: Date?
        var calories: Double = 0
        var calorieBudget: Double = 2_200
        var miles: Double = 0
        var mileGoal: Double = 1
        /// Miles by noon.
        var milesBeforeNoon: Double = 0
        /// Tonight's planned bedtime, when there is one.
        var bedtime: Date?
    }

    enum Status: Equatable {
        case done
        /// Still possible today.
        case open
        /// Its window has passed.
        case missed
        /// Self-reported and not claimed yet.
        case claimable
    }

    // MARK: - Today's three

    static func quest(_ kind: Kind, facts: Facts) -> Quest {
        switch kind {
        case .proteinBreakfast:
            return Quest(kind: kind, title: "30 g of protein before 11", detail: "Front-load it: eggs, yogurt or a shake",
                         symbol: "sunrise.fill", points: 20)
        case .waterBeforeNoon:
            return Quest(kind: kind, title: "20 oz of water before noon", detail: "Start the day hydrated",
                         symbol: "drop.fill", points: 10)
        case .eveningWalk:
            return Quest(kind: kind, title: "Walk 10 minutes after dinner", detail: "1,000 steps between 6 and 9 PM",
                         symbol: "figure.walk", points: 20)
        case .logEveryMeal:
            return Quest(kind: kind, title: "Log breakfast, lunch and dinner", detail: "Every meal, even the messy ones",
                         symbol: "list.bullet.clipboard.fill", points: 20)
        case .morningWeighIn:
            return Quest(kind: kind, title: "Weigh in before 9 AM", detail: "Same time, same conditions",
                         symbol: "scalemass.fill", points: 10)
        case .finishWorkout:
            return Quest(kind: kind, title: "Finish today's workout", detail: "Log it when you're done",
                         symbol: "dumbbell.fill", points: 30)
        case .hitProtein:
            return Quest(kind: kind, title: "Hit \(Int(facts.proteinTarget)) g of protein", detail: "The muscle-keeper",
                         symbol: "bolt.heart.fill", points: 25)
        case .bedOnTime:
            let time = facts.bedtime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "on time"
            return Quest(kind: kind, title: "In bed by \(time)", detail: "Tap to claim when you're in",
                         symbol: "moon.stars.fill", points: 20, selfReported: true)
        case .steps8k:
            return Quest(kind: kind, title: "8,000 steps", detail: "Pace calls, park far, take the stairs",
                         symbol: "shoeprints.fill", points: 20)
        case .kitchenClosed:
            return Quest(kind: kind, title: "Kitchen closed after 9 PM", detail: "Nothing logged after 9",
                         symbol: "lock.fill", points: 15)
        case .mileDone:
            return Quest(kind: kind, title: "Get your mile in", detail: "Walk or run, it all counts",
                         symbol: "figure.run", points: 15)
        case .inBudget:
            return Quest(kind: kind, title: "Finish under \(Int(facts.calorieBudget).formatted()) calories",
                         detail: "Log it all and stay under", symbol: "flame.fill", points: 25)
        case .hitWater:
            return Quest(kind: kind, title: "Drink \(Int(facts.waterTarget)) oz of water", detail: "Your full water target",
                         symbol: "waterbottle.fill", points: 15)
        case .earlyMile:
            return Quest(kind: kind, title: "Mile done before noon", detail: "Knock it out early",
                         symbol: "sun.max.fill", points: 25)
        }
    }

    /// Three quests for `date`: the same picks all day, one from each
    /// group when possible, skipping ones that don't apply.
    static func today(_ date: Date, facts: Facts, calendar: Calendar = .current) -> [Quest] {
        var pool = Kind.allCases.filter { applies($0, facts: facts) }
        // Seeded shuffle from the date (stable across launches).
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = c.year ?? 0, month: Int = c.month ?? 0, day: Int = c.day ?? 0
        var seed = UInt64(year * 10_000 + month * 100 + day)
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, Int(next() % UInt64(i + 1)))
        }
        var picked: [Kind] = []
        for group in [Kind.Group.food, .move, .body] {
            if let k = pool.first(where: { $0.group == group && !picked.contains($0) }) { picked.append(k) }
        }
        for k in pool where picked.count < 3 && !picked.contains(k) { picked.append(k) }
        return picked.prefix(3).map { quest($0, facts: facts) }
    }

    static func applies(_ kind: Kind, facts: Facts) -> Bool {
        switch kind {
        case .finishWorkout: return facts.isWorkoutDay
        case .bedOnTime:     return facts.bedtime != nil
        case .hitProtein:    return facts.proteinTarget > 0
        case .hitWater:      return facts.waterTarget > 0
        default:             return true
        }
    }

    // MARK: - Checking

    static func status(_ quest: Quest, facts: Facts, claimed: Bool = false, calendar: Calendar = .current) -> Status {
        let hour = calendar.component(.hour, from: facts.now)
        func by(_ h: Int, _ done: Bool) -> Status { done ? .done : (hour >= h ? .missed : .open) }
        switch quest.kind {
        case .proteinBreakfast: return by(11, facts.proteinBefore11 >= 30)
        case .waterBeforeNoon:  return by(12, facts.waterBeforeNoonOz >= 20)
        case .eveningWalk:      return by(21, facts.eveningSteps >= 1_000)
        case .logEveryMeal:     return facts.mealSlotsLogged >= 3 ? .done : .open
        case .morningWeighIn:
            if let t = facts.weighInTime { return calendar.component(.hour, from: t) < 9 ? .done : .missed }
            return hour >= 9 ? .missed : .open
        case .finishWorkout:    return facts.workoutDone ? .done : .open
        case .hitProtein:       return facts.protein >= facts.proteinTarget ? .done : .open
        case .bedOnTime:        return claimed ? .done : .claimable
        case .steps8k:          return facts.steps >= 8_000 ? .done : .open
        case .kitchenClosed:
            if let last = facts.lastMealTime, calendar.component(.hour, from: last) >= 21 { return .missed }
            return hour >= 21 ? .done : .open
        case .mileDone:         return facts.miles >= facts.mileGoal - 0.005 ? .done : .open
        case .inBudget:
            if facts.calories > facts.calorieBudget { return .missed }
            return hour >= 20 && facts.calories >= 800 ? .done : .open
        case .hitWater:         return facts.waterOz >= facts.waterTarget ? .done : .open
        case .earlyMile:        return by(12, facts.milesBeforeNoon >= facts.mileGoal - 0.005)
        }
    }

    /// All three done earns a bonus.
    static let sweepBonus = 25

    // MARK: - Levels

    struct Level: Equatable {
        var number: Int
        var title: String
        /// XP earned inside this level, and the size of the level.
        var into: Int
        var size: Int
        var progress: Double { size > 0 ? Double(into) / Double(size) : 0 }
    }

    /// Level n → n+1 takes 100 + 25·(n−1) XP: a few days a level early on,
    /// about a week and a half by level 20.
    static func size(of level: Int) -> Int { 100 + 25 * (level - 1) }

    static func level(xp: Int) -> Level {
        var n = 1
        var left = max(0, xp)
        while left >= size(of: n) {
            left -= size(of: n)
            n += 1
        }
        return Level(number: n, title: title(for: n), into: left, size: size(of: n))
    }

    static let titles: [(from: Int, title: String)] = [
        (1, "Rookie"), (3, "Grinder"), (5, "Locked In"), (8, "Dialed"), (12, "Elite"),
        (16, "Machine"), (20, "Legend"), (30, "Mythic")
    ]

    static func title(for level: Int) -> String {
        titles.last { level >= $0.from }?.title ?? "Rookie"
    }
}
