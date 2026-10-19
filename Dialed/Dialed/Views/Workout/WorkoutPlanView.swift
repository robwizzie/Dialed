//
//  WorkoutPlanView.swift
//  Dialed
//
//  The basement + Peaches plan, day by day: this week's strip, the
//  selected day's session with a "done" check, and the how-to sections.
//  Open it from Home (Today's workout card or the Today menu → Go to).
//

import SwiftUI

/// Where the plan starts and ends, and which days are checked off.
enum WorkoutPlanStore {
    private static let startKey = "workout.startDate"
    static let doneKey = "workout.doneDays"

    /// First time you open the plan, unless set before.
    static var startDate: Date {
        if let saved = UserDefaults.standard.object(forKey: startKey) as? Date { return saved }
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: startKey)
        return today
    }

    /// Your goal day, else Nov 19, 2026.
    static var goalDate: Date {
        GoalEvent.load()?.date
            ?? Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19))
            ?? Date()
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func session(on date: Date) -> WorkoutProgram.Session {
        WorkoutProgram.session(on: date, start: startDate, goal: goalDate)
    }
}

struct WorkoutPlanView: View {
    @AppStorage(WorkoutPlanStore.doneKey) private var doneRaw = ""
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var start: Date { WorkoutPlanStore.startDate }
    private var goal: Date { WorkoutPlanStore.goalDate }
    private var done: Set<String> { Set(doneRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                weekStrip
                sessionCard(for: selected)
                guide
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Workout plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        let phase = WorkoutProgram.phase(on: today, start: start, goal: goal)
        let left = WorkoutProgram.daysToGoal(from: today, goal: goal)
        let thisWeek = week(containing: today)
        let weekDone = thisWeek.filter { done.contains(WorkoutPlanStore.key($0)) && WorkoutPlanStore.session(on: $0).kind != .rest }.count
        let weekPlanned = thisWeek.filter { WorkoutPlanStore.session(on: $0).kind != .rest }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                NekaPill(text: phase.title.uppercased(), tint: Neka.green, fill: Neka.greenSoft)
                Spacer()
                Text(left >= 0 ? "\(left) day\(left == 1 ? "" : "s") to go" : "Finished")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
            Text(GoalEvent.load()?.name ?? "Wedding shred")
                .font(Neka.display(28, weight: .bold))
                .foregroundColor(Neka.ink)
            Text(phase.focus)
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                NekaProgressBar(progress: weekPlanned > 0 ? Double(weekDone) / Double(weekPlanned) : 0, tint: Neka.green, height: 6)
                Text("\(weekDone)/\(weekPlanned) this week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize()
            }
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    // MARK: - Week strip

    /// Monday-to-Sunday of the selected day's week.
    private var weekDays: [Date] { week(containing: selected) }

    private func week(containing day: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: day)   // 1 = Sunday
        let back = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -back, to: day) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                .foregroundColor(Neka.inkSecondary)
            ForEach(weekDays, id: \.self) { day in
                let s = WorkoutPlanStore.session(on: day)
                let isDone = done.contains(WorkoutPlanStore.key(day))
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                Button { selected = day } label: {
                    VStack(spacing: 5) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(calendar.isDate(day, inSameDayAs: today) ? Neka.green : Neka.inkTertiary)
                        ZStack {
                            Circle().fill(isDone ? Neka.green : (isSelected ? Neka.ink : Neka.track))
                            Image(systemName: isDone ? "checkmark" : s.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isDone || isSelected ? Neka.onInk : Neka.inkSecondary)
                        }
                        .frame(width: 38, height: 38)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month().day())): \(s.title)\(isDone ? ", done" : "")")
            }
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                .foregroundColor(Neka.inkSecondary)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .nekaCard()
    }

    private func shiftWeek(_ by: Int) {
        selected = calendar.date(byAdding: .day, value: by * 7, to: selected) ?? selected
    }

    // MARK: - Session

    private func sessionCard(for day: Date) -> some View {
        let s = WorkoutPlanStore.session(on: day)
        let key = WorkoutPlanStore.key(day)
        let isDone = done.contains(key)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(calendar.isDate(day, inSameDayAs: today) ? "TODAY" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(s.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Neka.ink)
                }
                Spacer()
                if s.minutes > 0 {
                    NekaPill(text: "\(s.minutes) min", tint: Neka.ink, fill: Neka.track)
                }
            }

            ForEach(s.exercises, id: \.self) { e in
                HStack {
                    Text(e.name)
                        .font(.system(size: 14))
                        .foregroundColor(Neka.ink)
                    Spacer(minLength: 8)
                    Text(e.prescription)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                .padding(.vertical, 2)
            }

            if let walk = s.walk {
                Label(walk, systemImage: "pawprint.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.orangeSoft))
            }
            ForEach(s.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if s.kind != .rest {
                Button { toggle(key) } label: {
                    Label(isDone ? "Done — nice work" : "Mark done", systemImage: isDone ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                .disabled(day > today)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func toggle(_ key: String) {
        var set = done
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        doneRaw = set.sorted().joined(separator: ",")
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    // MARK: - Guide

    private var guide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            guideItem("calendar", "The week",
                      "Mon Strength A · Tue Bike · Wed Strength B · Thu long walk/run · Fri Circuit C · Sat Bike + long walk · Sun rest. 10,000+ steps every day.")
            guideItem("bicycle", "Bike intervals",
                      "Weeks 1–2: 8 × (30 s hard / 90 s easy). Weeks 3–4: 10 × (40 s hard / 80 s easy). 5 min easy either side.")
            guideItem("pawprint.fill", "Peaches",
                      "Week 1 brisk walks only. From week 2, Thursdays are 2 min jog / 3 min walk × 6–8. Build her up too, skip hot pavement, check with the vet if unsure.")
            guideItem("fork.knife", "Food & recovery",
                      "500–750 kcal/day deficit (never under 1,500), ~190 g protein, 120 oz water, 7.5+ h sleep, no alcohol until the day.")
            guideItem("sparkles", "Event week",
                      "Last hard session 3 days out, then walks and one light session. No crash dieting, no cutting water, no new foods.")
        }
        .padding(16)
        .nekaCard()
    }

    private func guideItem(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Neka.track))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Home card: today's session at a glance, with a quick done check.
struct HomeWorkoutCard: View {
    @AppStorage(WorkoutPlanStore.doneKey) private var doneRaw = ""
    var onOpen: () -> Void

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let s = WorkoutPlanStore.session(on: today)
        let key = WorkoutPlanStore.key(today)
        let isDone = doneRaw.split(separator: ",").contains { $0 == key }
        return Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: isDone ? "checkmark" : s.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isDone ? Neka.onInk : Neka.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(isDone ? Neka.green : Neka.greenSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDone ? "TODAY'S WORKOUT · DONE" : "TODAY'S WORKOUT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(s.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Text([s.minutes > 0 ? "\(s.minutes) min" : nil, s.walk].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard(wash: .mint)
        }
        .buttonStyle(.dialedScale)
    }
}
