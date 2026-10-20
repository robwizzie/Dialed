//
//  ReadinessAdviceView.swift
//  Dialed
//
//  Today's readiness advice, on Home's workout card and at the top of the
//  logger: a chip with the score, the call ("Intervals instead of heavy
//  lifting", "Go for a PR"), why, the PR attempts with a warm-up, and
//  Use this / Keep plan. Once you've chosen, it folds to one line.
//

import SwiftUI
import SwiftData

struct ReadinessAdviceView: View {
    let advice: ReadinessCoach.Recommendation
    let choice: ReadinessChoiceStore.Choice?
    var onUse: () -> Void
    var onKeep: () -> Void
    var onUndo: () -> Void

    var body: some View {
        if let choice {
            chosenLine(choice)
        } else if advice.isActionable {
            card
        } else {
            HStack(spacing: 8) {
                ReadinessChip(advice: advice)
                Text(advice.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ReadinessChip(advice: advice)
                Spacer(minLength: 0)
            }
            Text(advice.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Neka.ink)
            Text(advice.detail)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(advice.attempts, id: \.exercise) { a in
                VStack(alignment: .leading, spacing: 2) {
                    Label(a.text, systemImage: "trophy.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(a.warmUp)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .padding(.leading, 22)
                }
            }
            Text(advice.reasons.joined(separator: " · "))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
            HStack(spacing: 8) {
                Button(action: onUse) {
                    Text(advice.attempts.isEmpty ? "Use this" : "Go for it")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                Button(action: onKeep) {
                    Text("Keep plan")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ReadinessChip.wash(advice.mode)))
    }

    private func chosenLine(_ choice: ReadinessChoiceStore.Choice) -> some View {
        HStack(spacing: 8) {
            ReadinessChip(advice: advice)
            Text(choice.applied
                 ? (advice.attempts.isEmpty ? "Adjusted for readiness" : "PR attempt set")
                 : "Keeping the plan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
                .buttonStyle(.plain)
        }
    }
}

/// "● 63 · Steady"
struct ReadinessChip: View {
    let advice: ReadinessCoach.Recommendation

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: Self.symbol(advice.mode))
                .font(.system(size: 10, weight: .bold))
            Text(advice.reasons.first { $0.hasPrefix("Readiness ") }?.replacingOccurrences(of: "Readiness ", with: "") ?? advice.label)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(Self.tint(advice.mode))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Neka.surface.opacity(0.9)))
    }

    static func symbol(_ mode: ReadinessCoach.Mode) -> String {
        switch mode {
        case .recovery:  return "leaf.fill"
        case .lighter:   return "gauge.with.dots.needle.33percent"
        case .asPlanned: return "checkmark.circle.fill"
        case .prAttempt: return "bolt.fill"
        }
    }

    static func tint(_ mode: ReadinessCoach.Mode) -> Color {
        switch mode {
        case .recovery:  return Neka.greenText
        case .lighter:   return Neka.orangeText
        case .asPlanned: return Neka.inkSecondary
        case .prAttempt: return Neka.lavenderText
        }
    }

    static func wash(_ mode: ReadinessCoach.Mode) -> Color {
        switch mode {
        case .recovery:  return Neka.greenSoft
        case .lighter:   return Neka.orangeSoft
        case .asPlanned: return Neka.track
        case .prAttempt: return Neka.lavenderSoft
        }
    }
}

// MARK: - Building today's advice

@MainActor
enum ReadinessAdvice {
    /// Advice for `day` from a readiness score and the planned (not
    /// swapped-in) session, your lift history and the last 3 days' load.
    static func make(readiness: Int?, illness: Bool, sleep: Int?, day: Date, context: ModelContext) -> ReadinessCoach.Recommendation? {
        guard readiness != nil else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let since = calendar.date(byAdding: .day, value: -3, to: start) ?? start
        let strength = WorkoutProgram.Session.Kind.strength.rawValue, bike = WorkoutProgram.Session.Kind.bike.rawValue
        let recent = (try? context.fetch(FetchDescriptor<PlanWorkoutLog>(
            predicate: #Predicate { $0.date >= since && $0.date < start && ($0.kindRaw == strength || $0.kindRaw == bike) }))) ?? []
        let sets = PlanWorkoutLogStore.allSets(context: context).filter { $0.completed && $0.date < start }
        let bests = StrengthMilestones.bests(sets.map {
            StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: $0.date, weight: $0.weightLbs, reps: $0.reps)
        })
        return ReadinessCoach.recommend(ReadinessCoach.Inputs(
            readiness: readiness, illnessWatch: illness, sleepScore: sleep,
            session: WorkoutPlanStore.plannedSession(on: day),
            recentHardDays: Set(recent.map(\.dayKey)).count, bests: bests))
    }

    static func choose(_ advice: ReadinessCoach.Recommendation, applied: Bool, day: Date) {
        ReadinessChoiceStore.set(.init(day: WorkoutPlanStore.key(day), mode: advice.mode, applied: applied,
                                       attempts: applied ? advice.attempts : []))
    }

    static func undo(day: Date) {
        ReadinessChoiceStore.clear(day: day)
    }
}
