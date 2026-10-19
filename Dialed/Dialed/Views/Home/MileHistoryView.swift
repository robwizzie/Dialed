//
//  MileHistoryView.swift
//  Dialed
//
//  Every day of the daily mile since your history start, as a calendar:
//  green = done, a partial ring = short, with the workouts behind it.
//  Open it from the Mile a day card or Settings → Mile a day.
//

import SwiftUI

struct MileHistoryView: View {
    @State private var history = MileHistory.load()
    @State private var selected: MileDay?
    private let goal = MileADay.goal
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let history {
                    stats(history)
                    ForEach(months(history), id: \.self) { month in
                        monthCard(month, history: history)
                    }
                } else {
                    Text("No history yet — open Home once with Apple Health connected.")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .nekaPageBackground()
        .navigationTitle("Mile history")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: MileSettings.didChange)) { _ in
            history = MileHistory.load()
        }
        .sheet(item: Binding(get: { selected.map(IdentifiedDay.init) }, set: { selected = $0?.day })) { item in
            dayDetail(item.day)
                .presentationDetents([.height(220)])
        }
    }

    private struct IdentifiedDay: Identifiable {
        let day: MileDay
        var id: Date { day.date }
    }

    // MARK: - Stats

    private func stats(_ h: MileHistory) -> some View {
        let total = h.days.count
        let done = h.doneCount(goal: goal)
        return HStack(spacing: 10) {
            stat("\(done)/\(total)", "days done", tint: Neka.green)
            stat("\(h.currentStreak(today: Date(), goal: goal))", "current streak", tint: Neka.orange)
            stat("\(h.longestStreak(goal: goal))", "longest streak", tint: Neka.lavender)
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Neka.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .nekaCard()
    }

    // MARK: - Months

    private func months(_ h: MileHistory) -> [Date] {
        guard let first = h.days.first?.date else { return [] }
        var out: [Date] = []
        var m = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: first)) ?? first
        while m >= firstMonth {
            out.append(m)
            guard let prev = calendar.date(byAdding: .month, value: -1, to: m) else { break }
            m = prev
        }
        return out
    }

    private func monthCard(_ month: Date, history: MileHistory) -> some View {
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: month)
        }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return VStack(alignment: .leading, spacing: 10) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 10, weight: .semibold)).foregroundColor(Neka.inkTertiary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date, history: history)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func dayCell(_ date: Date, history: MileHistory) -> some View {
        let day = history.day(date)
        let future = date > Date()
        let before = date < history.start
        let miles = day?.miles ?? 0
        let done = MileADay.isDone(miles, goal: goal)
        return Button {
            if let day { selected = day }
        } label: {
            ZStack {
                Circle().stroke(Neka.track, lineWidth: 3)
                if done {
                    Circle().fill(day?.ran == true ? Neka.sky : Neka.green)
                } else if !future && !before {
                    Circle().trim(from: 0, to: min(1, miles / goal))
                        .stroke(Neka.sky, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: done ? .bold : .medium))
                    .foregroundColor(done ? .white : (future || before ? Neka.inkTertiary : Neka.ink))
            }
            .frame(width: 32, height: 32)
            .opacity(future || before ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(String(format: "%.2f", miles)) miles")
    }

    private func dayDetail(_ day: MileDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.date, format: .dateTime.weekday(.wide).month().day())
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", day.miles))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("mi").foregroundColor(Neka.inkSecondary)
                Spacer()
                if MileADay.isDone(day.miles, goal: goal) {
                    Label(day.ran ? "Ran it" : "Done", systemImage: day.ran ? "figure.run" : "checkmark.circle.fill")
                        .foregroundColor(Neka.green)
                }
            }
            Text(sourceLine(day))
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceLine(_ day: MileDay) -> String {
        switch day.source {
        case .workout:
            return "From \(day.workouts) workout\(day.workouts == 1 ? "" : "s") in Apple Health (\(String(format: "%.2f", day.workoutMiles)) mi)."
        case .distance:
            let w = day.workouts > 0 ? " Workouts: \(String(format: "%.2f", day.workoutMiles)) mi." : ""
            return "Apple Health walking + running distance.\(w)"
        case .steps:
            return "Estimated from your steps at \(Int(MileSettings.load().stepsPerMile).formatted()) steps per mile."
        case .none:
            return "Nothing recorded."
        }
    }
}

#Preview {
    NavigationStack { MileHistoryView() }
}
