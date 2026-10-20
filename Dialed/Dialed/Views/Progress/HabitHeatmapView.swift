//
//  HabitHeatmapView.swift
//  Dialed
//
//  Twelve weeks of green squares. Pick a habit (mile, protein, logging,
//  workout) or "All" for how many you hit each day; tap a square for that
//  day's details. Current and best streaks for each habit underneath.
//

import SwiftUI
import SwiftData

struct HabitHeatmapView: View {
    /// Inside TrophyRoomView (which owns the navigation bar).
    var embedded = false

    @Environment(\.modelContext) private var context
    @State private var days: [HabitDays.Day] = []
    @State private var habit: HabitDays.Habit?
    @State private var selected: HabitDays.Day?
    @State private var loaded = false

    private let calendar = Calendar.current
    private let weeks = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picker
                if loaded {
                    gridCard
                    if let selected { dayCard(selected) }
                    streaks
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle(embedded ? "" : "Habits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let found = await GameService.habitDays(context: context, count: weeks * 7)
            withAnimation(.easeOut(duration: 0.25)) {
                days = found
                selected = found.last
                loaded = true
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", "square.grid.3x3.fill", nil)
                ForEach(HabitDays.Habit.allCases) { h in chip(h.title, h.symbol, h) }
            }
        }
    }

    private func chip(_ title: String, _ symbol: String, _ value: HabitDays.Habit?) -> some View {
        let on = habit == value
        return Button { withAnimation(.easeOut(duration: 0.2)) { habit = value } } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? Neka.onInk : Neka.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? Neka.ink : Neka.track))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    /// Columns are weeks (Monday first), rows are weekdays.
    private var columns: [[HabitDays.Day?]] {
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7      // Monday = 0
        guard let thisMonday = calendar.date(byAdding: .day, value: -weekday, to: today) else { return [] }
        return (0..<weeks).reversed().map { back in
            let monday = calendar.date(byAdding: .day, value: -7 * back, to: thisMonday) ?? thisMonday
            return (0..<7).map { i in
                let d = calendar.date(byAdding: .day, value: i, to: monday) ?? monday
                return d > today ? nil : byDay[d] ?? HabitDays.Day(date: d)
            }
        }
    }

    private func level(_ day: HabitDays.Day) -> Double {
        if let habit { return day.did(habit) ? 1 : 0 }
        return Double(day.score) / Double(HabitDays.Habit.allCases.count)
    }

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Neka.inkTertiary)
                            .frame(width: 12, height: 18)
                    }
                }
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            cell(week[i])
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less")
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3).fill(color(v)).frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.system(size: 10))
            .foregroundColor(Neka.inkTertiary)
        }
        .padding(14)
        .nekaCard()
    }

    @ViewBuilder
    private func cell(_ day: HabitDays.Day?) -> some View {
        if let day {
            let isSelected = selected.map { calendar.isDate($0.date, inSameDayAs: day.date) } ?? false
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color(level(day)))
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? Neka.ink : .clear, lineWidth: 1.5))
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) { selected = day }
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 18)
        }
    }

    private func color(_ v: Double) -> Color {
        v <= 0 ? Neka.track : Neka.green.opacity(0.25 + 0.75 * v)
    }

    // MARK: - Day

    private func dayCard(_ day: HabitDays.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(calendar.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                fact("figure.walk", String(format: "%.2f mi", day.miles), day.mileDone)
                fact("bolt.heart.fill", "\(Int(day.protein)) / \(Int(day.proteinTarget)) g protein", day.proteinHit)
                fact("fork.knife", day.logged ? "\(day.foodEntries) foods · \(Int(day.calories).formatted()) cal" : "Not logged", day.logged)
                fact("dumbbell.fill", day.workout ? "Workout done" : "No workout", day.workout)
                fact("drop.fill", "\(Int(day.waterOz)) / \(Int(day.waterTarget)) oz", day.waterHit)
                fact("scalemass.fill", day.weighedIn ? "Weighed in" : "No weigh-in", day.weighedIn)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    private func fact(_ symbol: String, _ text: String, _ done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(done ? Neka.greenText : Neka.inkTertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(done ? Neka.ink : Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Streaks

    private var streaks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Streaks")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            VStack(spacing: 0) {
                ForEach(HabitDays.Habit.allCases) { h in
                    let s = HabitDays.streak(days, habit: h, today: Date(), calendar: calendar)
                    HStack(spacing: 12) {
                        Image(systemName: h.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.greenText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Neka.greenSoft))
                        Text(h.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Neka.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(s.current > 0 ? "🔥 \(s.current) days" : "—")
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(Neka.ink)
                            Text("best \(s.best)")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkTertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    if h != HabitDays.Habit.allCases.last { Divider().overlay(Neka.hairline) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .nekaCard()
        }
    }
}
