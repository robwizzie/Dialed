//
//  TimelineView.swift
//  Dialed
//
//  Vertical scroll of ContextEvents for the selected day with a horizontal
//  day strip header. Read-only — capture happens via QuickAddBar.
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = TimelineViewModel()

    var body: some View {
        ZStack {
            AppColors.nowBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                dayStrip
                    .padding(.vertical, 12)
                    .background(AppColors.nowBackground.opacity(0.95))

                Divider()
                    .background(Color.white.opacity(0.05))

                if viewModel.eventCount == 0 {
                    emptyState
                } else {
                    eventScroll
                }
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.refresh(context: modelContext) }
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.refresh(context: modelContext)
        }
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.dayStrip, id: \.self) { date in
                        dayCell(for: date)
                            .id(date)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                proxy.scrollTo(viewModel.selectedDate, anchor: .center)
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        return Button {
            viewModel.select(date)
        } label: {
            VStack(spacing: 4) {
                Text(weekdayLetter(for: date))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(isSelected ? 0.85 : 0.45))
                Text(dayNumber(for: date))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                if isToday {
                    Circle()
                        .fill(AppColors.Pillar.readiness.gradient.last ?? .white)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(width: 44, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                                colors: AppColors.Pillar.readiness.gradient.map { $0.opacity(0.25) },
                                startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected
                                    ? (AppColors.Pillar.readiness.gradient.last ?? .white).opacity(0.45)
                                    : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 1 : 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    // MARK: - Event list

    private var eventScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.groupedByHour, id: \.hour) { bucket in
                    hourSection(hour: bucket.hour, events: bucket.events)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private func hourSection(hour: Int, events: [ContextEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hourLabel(hour))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
                .padding(.leading, 4)
            ForEach(events) { event in
                TimelineEventRow(event: event)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(.white.opacity(0.25))
            Text("Nothing logged yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("Quick-add water, a meal, your mood, or a note from the Now tab.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
    .preferredColorScheme(.dark)
}
