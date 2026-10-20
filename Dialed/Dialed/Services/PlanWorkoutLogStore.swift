//
//  PlanWorkoutLogStore.swift
//  Dialed
//
//  SwiftData reads and writes for the plan workout logger: the last
//  session of an exercise (for suggestions), the log already saved for a
//  day (to edit it), saving a session (and checking the day off in the
//  plan), and every logged set (for the strength-vs-weight screen).
//

import Foundation
import SwiftData

@MainActor
enum PlanWorkoutLogStore {

    /// The completed sets from the most recent session of `exerciseName`
    /// before `day`.
    static func lastSession(of exerciseName: String, before day: Date, context: ModelContext) -> [PlanSetLog] {
        let name = exerciseName
        let cutoff = Calendar.current.startOfDay(for: day)
        var desc = FetchDescriptor<PlanSetLog>(
            predicate: #Predicate<PlanSetLog> { $0.exerciseName == name && $0.date < cutoff },
            sortBy: [SortDescriptor(\PlanSetLog.date, order: .reverse)]
        )
        desc.fetchLimit = 60
        let rows = (try? context.fetch(desc)) ?? []
        guard let latest = rows.first else { return [] }
        let id = latest.workoutID
        return rows.filter { $0.workoutID == id }.sorted { $0.setIndex < $1.setIndex }
    }

    static func log(for dayKey: String, context: ModelContext) -> PlanWorkoutLog? {
        let key = dayKey
        var desc = FetchDescriptor<PlanWorkoutLog>(
            predicate: #Predicate<PlanWorkoutLog> { $0.dayKey == key },
            sortBy: [SortDescriptor(\PlanWorkoutLog.savedAt, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    static func sets(for workoutID: UUID, context: ModelContext) -> [PlanSetLog] {
        let id = workoutID
        let desc = FetchDescriptor<PlanSetLog>(
            predicate: #Predicate<PlanSetLog> { $0.workoutID == id },
            sortBy: [SortDescriptor(\PlanSetLog.exerciseOrder), SortDescriptor(\PlanSetLog.setIndex)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    static func allSets(context: ModelContext) -> [PlanSetLog] {
        let desc = FetchDescriptor<PlanSetLog>(sortBy: [SortDescriptor(\PlanSetLog.date)])
        return (try? context.fetch(desc)) ?? []
    }

    /// Removes the sets of an existing log (before re-saving it).
    static func deleteSets(of workoutID: UUID, context: ModelContext) {
        for s in sets(for: workoutID, context: context) { context.delete(s) }
    }

    static func delete(_ log: PlanWorkoutLog, context: ModelContext) {
        deleteSets(of: log.id, context: context)
        context.delete(log)
        try? context.save()
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    // MARK: - Plan check-off (UserDefaults "workout.doneDays")

    static func setDone(_ dayKey: String, _ done: Bool) {
        let defaults = UserDefaults.standard
        var set = Set((defaults.string(forKey: WorkoutPlanStore.doneKey) ?? "")
            .split(separator: ",").map(String.init))
        if done { set.insert(dayKey) } else { set.remove(dayKey) }
        defaults.set(set.sorted().joined(separator: ","), forKey: WorkoutPlanStore.doneKey)
    }

    // MARK: - Your exercises

    /// Exercises you've added that aren't in the plan ("Pec deck fly"),
    /// remembered so typing them next time lands on the same name.
    static let customKey = "workout.customExercises"

    static var customExercises: [String] {
        (UserDefaults.standard.stringArray(forKey: customKey) ?? [])
    }

    static func remember(_ names: [String]) {
        let plan = Set(WorkoutLoggerView.allPlanExercises)
        var list = customExercises
        for n in names where !plan.contains(n) && !list.contains(n) { list.append(n) }
        UserDefaults.standard.set(list, forKey: customKey)
    }

    /// Every name to match typed text against: the plan, your own, and
    /// anything you've logged before.
    static func knownExercises(context: ModelContext) -> [String] {
        var seen = Set<String>()
        let logged = allSets(context: context).map(\.exerciseName)
        return (WorkoutLoggerView.allPlanExercises + customExercises + logged).filter { seen.insert($0).inserted }
    }
}
