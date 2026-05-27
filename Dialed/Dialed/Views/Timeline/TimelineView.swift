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

    /// True once `viewModel.refresh` has completed at least once. Prevents
    /// the empty state from flashing during the brief window between
    /// view mount and the initial fetch.
    @State private var hasLoaded: Bool = false

    var body: some View {
        ZStack {
            AppColors.nowBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                dayStrip
                    .padding(.vertical, Spacing.sm)
                    .background(AppColors.nowBackground.opacity(0.95))

                Divider()
                    .background(Color.white.opacity(0.06))

                content
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.refresh(context: modelContext)
            hasLoaded = true
        }
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.refresh(context: modelContext)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            // Subtle pre-load — empty space rather than the empty-state copy,
            // since the latter would flash for days that actually have data.
            Color.clear
                .frame(maxHeight: .infinity)
        } else if viewModel.eventCount == 0 {
            emptyState
                .transition(.opacity)
        } else {
            eventScroll
                .transition(.opacity)
        }
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(viewModel.dayStrip, id: \.self) { date in
                        dayCell(for: date)
                            .id(date)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .onAppear {
                proxy.scrollTo(viewModel.selectedDate, anchor: .center)
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        let showTodayDot = isToday && !isSelected
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                viewModel.select(date)
            }
        } label: {
            VStack(spacing: 4) {
                Text(weekdayLetter(for: date))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(isSelected ? 0.85 : 0.55))
                Text(dayNumber(for: date))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                if showTodayDot {
                    Circle()
                        .fill(AppColors.Pillar.readiness.gradient.last ?? .white)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(width: 48, height: 60)
            .background(
                RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                                colors: AppColors.Pillar.readiness.gradient.map { $0.opacity(0.28) },
                                startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                            .stroke(isSelected
                                    ? (AppColors.Pillar.readiness.gradient.last ?? .white).opacity(0.45)
                                    : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 1 : 0.6)
                    )
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("\(weekdayLetter(for: date)) \(dayNumber(for: date))\(isToday ? ", today" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(viewModel.groupedByHour, id: \.hour) { bucket in
                    hourSection(hour: bucket.hour, events: bucket.events)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md + 2)
        }
        // Crossfade when the day changes so events don't pop.
        .id(viewModel.selectedDate)
        .transition(.opacity)
    }

    private func hourSection(hour: Int, events: [ContextEvent]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DialedSectionHeader(hourLabel(hour))
                .padding(.leading, Spacing.xxs)
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
        VStack(spacing: Spacing.sm) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(.white.opacity(0.3))
            Text("Nothing logged yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            Text("Quick-add water, a meal, your mood, or a note from the Now tab.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
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
