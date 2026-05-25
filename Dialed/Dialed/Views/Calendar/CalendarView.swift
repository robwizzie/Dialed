//
//  CalendarView.swift
//  Dialed
//
//  Calendar view with daily scores, photos, and streaks
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: CalendarViewModel
    
    @State private var showDaySummary = false
    
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    init() {
        let container = try! DialedSchema.makeContainer()
        _viewModel = StateObject(wrappedValue: CalendarViewModel(modelContext: container.mainContext))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Month header
                    monthHeader
                    
                    // Legend
                    legendRow
                    
                    // Calendar grid
                    calendarGrid
                    
                    // Stats section
                    statsSection
                }
                .padding()
                .padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                viewModel.refreshData()
            }
            .sheet(isPresented: $showDaySummary) {
                if let selectedDate = viewModel.selectedDate {
                    DaySummarySheet(
                        date: selectedDate,
                        dayLog: viewModel.dayLog(for: selectedDate)
                    )
                    .onDisappear {
                        viewModel.clearSelection()
                    }
                }
            }
        }
    }
    
    // MARK: - Month Header
    
    private var monthHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.goToPreviousMonth()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            
            Spacer()
            
            Button(action: {
                viewModel.goToCurrentMonth()
            }) {
                Text(viewModel.monthTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .disabled(viewModel.isCurrentMonth)
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.goToNextMonth()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.body.bold())
                    .foregroundColor(viewModel.canGoToNextMonth ? .primary : Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .disabled(!viewModel.canGoToNextMonth)
        }
    }
    
    // MARK: - Legend
    
    private var legendRow: some View {
        HStack(spacing: 16) {
            // Score indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.scoreStrong)
                    .frame(width: 8, height: 8)
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Photo indicator
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.purple)
                Text("Photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Today indicator
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(AppColors.primary, lineWidth: 2)
                    .frame(width: 12, height: 12)
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if viewModel.totalPhotosThisMonth > 0 {
                Text("\(viewModel.totalPhotosThisMonth) photos")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Weekday labels
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(height: 30)
                }
            }
            
            // Days grid
            LazyVGrid(columns: columns, spacing: 4) {
                // Leading empty days
                ForEach(0..<viewModel.leadingEmptyDays, id: \.self) { _ in
                    Color.clear
                        .frame(height: 56)
                }
                
                // Actual days
                ForEach(viewModel.daysInMonth, id: \.self) { date in
                    CalendarDayCell(
                        date: date,
                        score: viewModel.score(for: date),
                        hasPhoto: viewModel.hasPhoto(for: date),
                        isToday: viewModel.isToday(date),
                        isFuture: viewModel.isFuture(date),
                        isSelected: viewModel.selectedDate == date,
                        onTap: {
                            viewModel.selectDate(date)
                            showDaySummary = true
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stats")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                // Streak
                StatTile(
                    icon: "flame.fill",
                    iconColors: [.orange, .red],
                    value: "\(viewModel.currentStreak)",
                    label: "Day Streak"
                )
                
                // Monthly average
                StatTile(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColors: [.blue, .cyan],
                    value: "\(viewModel.monthlyAverage)",
                    label: "Monthly Avg"
                )
                
                // Completed days
                StatTile(
                    icon: "checkmark.circle.fill",
                    iconColors: [.green, .mint],
                    value: "\(viewModel.completedDaysCount)",
                    label: "Days 60+"
                )
            }
            
            // Best day highlight
            if let best = viewModel.bestDay {
                bestDayCard(date: best.date, score: best.score)
            }
        }
    }
    
    private func bestDayCard(date: Date, score: Int) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let dateString = formatter.string(from: date)
        
        return HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Best Day This Month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(dateString)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(score)")
                    .font(.title2.bold())
                    .foregroundStyle(AppColors.scoreColor(for: score))
                
                Text(AppColors.scoreGrade(for: score))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.yellow.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let score: Int?
    let hasPhoto: Bool
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    private var cellColor: Color {
        if isFuture {
            return .clear
        }
        guard let score = score, score > 0 else {
            return Color(white: 0.15)
        }
        return AppColors.scoreColor(for: score).opacity(0.3)
    }
    
    private var textColor: Color {
        if isFuture {
            return Color.secondary.opacity(0.3)
        }
        if isToday {
            return .primary
        }
        guard let score = score, score > 0 else {
            return .secondary
        }
        return .primary
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.subheadline.bold())
                    .foregroundStyle(textColor)
                
                // Indicators row
                HStack(spacing: 3) {
                    // Score indicator
                    if let score = score, score > 0, !isFuture {
                        Circle()
                            .fill(AppColors.scoreColor(for: score))
                            .frame(width: 6, height: 6)
                    }
                    
                    // Photo indicator
                    if hasPhoto && !isFuture {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.purple)
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cellColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isToday ? AppColors.primary : (isSelected ? .white.opacity(0.3) : .clear),
                                lineWidth: isToday ? 2 : 1
                            )
                    )
            )
        }
        .disabled(isFuture)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Stat Tile

private struct StatTile: View {
    let icon: String
    let iconColors: [Color]
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: iconColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

#Preview {
    CalendarView()
}
