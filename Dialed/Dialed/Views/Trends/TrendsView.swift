//
//  TrendsView.swift
//  Dialed
//
//  Comprehensive trends, charts, and insights
//

import SwiftUI
import SwiftData

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: TrendsViewModel
    
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"
        case threeMonths = "90D"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            case .threeMonths: return 90
            }
        }
        
        var title: String {
            switch self {
            case .week: return "Last 7 Days"
            case .twoWeeks: return "Last 14 Days"
            case .month: return "Last 30 Days"
            case .threeMonths: return "Last 90 Days"
            }
        }
    }
    
    init() {
        let container = try! DialedSchema.makeContainer()
        _viewModel = StateObject(wrappedValue: TrendsViewModel(modelContext: container.mainContext))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Time range selector
                    timeRangeSelector
                    
                    // Score overview
                    scoreOverview
                    
                    // Score chart
                    scoreChart
                    
                    // Key insights
                    insightsSection
                    
                    // Category breakdowns
                    categoryBreakdowns
                    
                    // Workout trends
                    workoutTrends
                    
                    // Personal bests
                    personalBests
                }
                .padding()
                .padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedTimeRange) { _, newValue in
                viewModel.loadData(for: newValue.days)
            }
            .onAppear {
                viewModel.loadData(for: selectedTimeRange.days)
            }
        }
    }
    
    // MARK: - Time Range Selector
    
    private var timeRangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeRange = range
                    }
                }) {
                    Text(range.rawValue)
                        .font(.subheadline.bold())
                        .foregroundColor(selectedTimeRange == range ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTimeRange == range ?
                                    LinearGradient(
                                        colors: [AppColors.primary, AppColors.primary.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color(white: 0.15), Color(white: 0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
            }
        }
    }
    
    // MARK: - Score Overview
    
    private var scoreOverview: some View {
        VStack(spacing: 16) {
            HStack {
                Text(selectedTimeRange.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Average score
                OverviewCard(
                    title: "Average",
                    value: "\(viewModel.averageScore)",
                    subtitle: viewModel.scoreTrend,
                    subtitleColor: viewModel.scoreTrendColor,
                    icon: "chart.line.uptrend.xyaxis",
                    iconColors: [.blue, .cyan]
                )
                
                // Best day
                OverviewCard(
                    title: "Best Day",
                    value: "\(viewModel.bestScore)",
                    subtitle: viewModel.bestDayLabel,
                    subtitleColor: .secondary,
                    icon: "trophy.fill",
                    iconColors: [.yellow, .orange]
                )
                
                // Consistency
                OverviewCard(
                    title: "Consistency",
                    value: "\(viewModel.consistencyPercentage)%",
                    subtitle: "\(viewModel.daysAbove60) days 60+",
                    subtitleColor: .secondary,
                    icon: "checkmark.seal.fill",
                    iconColors: [.green, .mint]
                )
            }
        }
    }
    
    // MARK: - Score Chart
    
    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Scores")
                .font(.headline)
                .foregroundStyle(.primary)
            
            // Chart
            GeometryReader { geometry in
                let maxScore = 100.0
                let height: CGFloat = 150
                let dataPoints = viewModel.dailyScores
                
                if dataPoints.isEmpty {
                    Text("No data for this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack {
                        // Grid lines
                        VStack(spacing: 0) {
                            ForEach([100, 75, 50, 25, 0], id: \.self) { level in
                                HStack {
                                    Text("\(level)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 25, alignment: .trailing)
                                    
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(height: 1)
                                }
                                if level > 0 {
                                    Spacer()
                                }
                            }
                        }
                        .frame(height: height)
                        
                        // Chart area
                        HStack(alignment: .bottom, spacing: 0) {
                            Spacer().frame(width: 30)
                            
                            // Bars
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, dataPoint in
                                    let barHeight = height * CGFloat(dataPoint.score) / maxScore
                                    
                                    VStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(
                                                LinearGradient(
                                                    colors: [AppColors.scoreColor(for: dataPoint.score), AppColors.scoreColor(for: dataPoint.score).opacity(0.6)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .frame(height: max(barHeight, 4))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(height: height)
                    }
                }
            }
            .frame(height: 150)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
    }
    
    // MARK: - Insights Section
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Insights")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(spacing: 10) {
                ForEach(viewModel.insights, id: \.title) { insight in
                    InsightCard(insight: insight)
                }
                
                if viewModel.insights.isEmpty {
                    Text("Log more days to see insights")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - Category Breakdowns
    
    private var categoryBreakdowns: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Performance")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(spacing: 10) {
                CategoryProgressRow(
                    category: "Sleep",
                    icon: "bed.double.fill",
                    iconColor: .purple,
                    average: viewModel.averageSleepScore,
                    trend: viewModel.sleepTrend
                )
                
                CategoryProgressRow(
                    category: "Workouts",
                    icon: "figure.strengthtraining.traditional",
                    iconColor: .green,
                    average: viewModel.workoutCompletionRate,
                    trend: viewModel.workoutTrend
                )
                
                CategoryProgressRow(
                    category: "Nutrition",
                    icon: "fork.knife",
                    iconColor: .orange,
                    average: viewModel.nutritionScore,
                    trend: viewModel.nutritionTrend
                )
                
                CategoryProgressRow(
                    category: "Hydration",
                    icon: "drop.fill",
                    iconColor: .cyan,
                    average: viewModel.hydrationScore,
                    trend: viewModel.hydrationTrend
                )
            }
        }
    }
    
    // MARK: - Workout Trends
    
    private var workoutTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                // Workouts completed
                MiniStatCard(
                    value: "\(viewModel.workoutsCompleted)",
                    label: "Workouts",
                    icon: "dumbbell.fill",
                    color: .green
                )
                
                // Total volume
                MiniStatCard(
                    value: viewModel.formattedTotalVolume,
                    label: "Volume",
                    icon: "scalemass.fill",
                    color: .purple
                )
                
                // Avg duration
                MiniStatCard(
                    value: "\(viewModel.averageWorkoutDuration)",
                    label: "Avg Min",
                    icon: "clock.fill",
                    color: .blue
                )
                
                // Total calories
                MiniStatCard(
                    value: viewModel.formattedTotalCalories,
                    label: "Burned",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Personal Bests
    
    private var personalBests: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Personal Bests")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if viewModel.personalBests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))
                    
                    Text("Keep training to set PRs!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.personalBests, id: \.exercise) { pb in
                        PersonalBestRow(pb: pb)
                    }
                }
            }
        }
    }
}

// MARK: - Overview Card

private struct OverviewCard: View {
    let title: String
    let value: String
    let subtitle: String
    let subtitleColor: Color
    let icon: String
    let iconColors: [Color]
    
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
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 14, padding: 12)
    }
}

// MARK: - Insight Card

private struct InsightCard: View {
    let insight: TrendsViewModel.Insight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundStyle(insight.color)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(insight.color.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(insight.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Category Progress Row

private struct CategoryProgressRow: View {
    let category: String
    let icon: String
    let iconColor: Color
    let average: Int
    let trend: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            Text(category)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(iconColor.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(iconColor)
                        .frame(width: geo.size.width * CGFloat(min(average, 100)) / 100)
                }
            }
            .frame(width: 80, height: 8)
            
            Text("\(average)%")
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .frame(width: 40, alignment: .trailing)
            
            Text(trend)
                .font(.caption2)
                .foregroundStyle(trend.hasPrefix("+") ? .green : (trend.hasPrefix("-") ? .red : .secondary))
                .frame(width: 35, alignment: .trailing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Mini Stat Card

private struct MiniStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Personal Best Row

private struct PersonalBestRow: View {
    let pb: TrendsViewModel.PersonalBest
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.body)
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pb.exercise)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                Text(pb.dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(Int(pb.weight)) lbs × \(pb.reps)")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.yellow.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Trends View Model

@MainActor
class TrendsViewModel: ObservableObject {
    @Published var dailyScores: [(date: Date, score: Int)] = []
    @Published var insights: [Insight] = []
    @Published var personalBests: [PersonalBest] = []
    
    // Computed stats
    @Published var averageScore: Int = 0
    @Published var bestScore: Int = 0
    @Published var bestDayLabel: String = "--"
    @Published var daysAbove60: Int = 0
    @Published var consistencyPercentage: Int = 0
    @Published var scoreTrend: String = "--"
    @Published var scoreTrendColor: Color = .secondary
    
    // Category stats
    @Published var averageSleepScore: Int = 0
    @Published var sleepTrend: String = "--"
    @Published var workoutCompletionRate: Int = 0
    @Published var workoutTrend: String = "--"
    @Published var nutritionScore: Int = 0
    @Published var nutritionTrend: String = "--"
    @Published var hydrationScore: Int = 0
    @Published var hydrationTrend: String = "--"
    
    // Workout stats
    @Published var workoutsCompleted: Int = 0
    @Published var averageWorkoutDuration: Int = 0
    @Published var formattedTotalVolume: String = "--"
    @Published var formattedTotalCalories: String = "--"
    
    private let modelContext: ModelContext
    private let calendar = Calendar.current
    
    struct Insight {
        let title: String
        let description: String
        let icon: String
        let color: Color
    }
    
    struct PersonalBest {
        let exercise: String
        let weight: Double
        let reps: Int
        let date: Date
        
        var dateString: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    struct DailyData {
        let date: Date
        let score: Int
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func loadData(for days: Int) {
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) else { return }
        
        // Fetch day logs
        let fetchDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { log in
                log.date >= startDate && log.date <= endDate
            },
            sortBy: [SortDescriptor(\.date)]
        )
        
        guard let logs = try? modelContext.fetch(fetchDescriptor) else { return }
        
        // Process daily scores
        processDailyScores(logs: logs, days: days, startDate: startDate)
        
        // Calculate stats
        calculateStats(logs: logs, days: days)
        
        // Generate insights
        generateInsights(logs: logs)
        
        // Load workout stats
        loadWorkoutStats(startDate: startDate, endDate: endDate)
        
        // Load personal bests
        loadPersonalBests()
    }
    
    private func processDailyScores(logs: [DayLog], days: Int, startDate: Date) {
        var scores: [(date: Date, score: Int)] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let normalizedDate = calendar.startOfDay(for: date)
            
            if let log = logs.first(where: { calendar.startOfDay(for: $0.date) == normalizedDate }) {
                scores.append((date: date, score: log.dailyScoreFinal ?? log.dailyScoreProvisional))
            } else {
                scores.append((date: date, score: 0))
            }
        }
        
        dailyScores = scores
    }
    
    private func calculateStats(logs: [DayLog], days: Int) {
        let validLogs = logs.filter { ($0.dailyScoreFinal ?? $0.dailyScoreProvisional) > 0 }
        
        // Average score
        if !validLogs.isEmpty {
            let totalScore = validLogs.reduce(0) { $0 + ($1.dailyScoreFinal ?? $1.dailyScoreProvisional) }
            averageScore = totalScore / validLogs.count
        } else {
            averageScore = 0
        }
        
        // Best score
        if let best = validLogs.max(by: { ($0.dailyScoreFinal ?? $0.dailyScoreProvisional) < ($1.dailyScoreFinal ?? $1.dailyScoreProvisional) }) {
            bestScore = best.dailyScoreFinal ?? best.dailyScoreProvisional
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            bestDayLabel = formatter.string(from: best.date)
        } else {
            bestScore = 0
            bestDayLabel = "--"
        }
        
        // Days above 60
        daysAbove60 = validLogs.filter { ($0.dailyScoreFinal ?? $0.dailyScoreProvisional) >= 60 }.count
        
        // Consistency
        consistencyPercentage = days > 0 ? (daysAbove60 * 100) / days : 0
        
        // Score trend (compare first half to second half)
        let halfPoint = validLogs.count / 2
        if halfPoint > 0 {
            let firstHalf = Array(validLogs.prefix(halfPoint))
            let secondHalf = Array(validLogs.suffix(halfPoint))
            
            let firstAvg = firstHalf.isEmpty ? 0 : firstHalf.reduce(0) { $0 + ($1.dailyScoreFinal ?? $1.dailyScoreProvisional) } / firstHalf.count
            let secondAvg = secondHalf.isEmpty ? 0 : secondHalf.reduce(0) { $0 + ($1.dailyScoreFinal ?? $1.dailyScoreProvisional) } / secondHalf.count
            
            let diff = secondAvg - firstAvg
            if diff > 0 {
                scoreTrend = "+\(diff) pts"
                scoreTrendColor = .green
            } else if diff < 0 {
                scoreTrend = "\(diff) pts"
                scoreTrendColor = .red
            } else {
                scoreTrend = "Stable"
                scoreTrendColor = .secondary
            }
        } else {
            scoreTrend = "--"
            scoreTrendColor = .secondary
        }
        
        // Category stats
        calculateCategoryStats(logs: validLogs)
    }
    
    private func calculateCategoryStats(logs: [DayLog]) {
        let settings = UserSettings.load()
        
        // Sleep
        let sleepLogs = logs.filter { $0.sleepScore != nil }
        if !sleepLogs.isEmpty {
            averageSleepScore = sleepLogs.reduce(0) { $0 + ($1.sleepScore ?? 0) } * 20 / sleepLogs.count // Convert 0-5 to percentage
        }
        sleepTrend = "--"
        
        // Workout completion
        let workoutLogs = logs.filter { $0.workoutTag != nil }
        workoutCompletionRate = logs.isEmpty ? 0 : (workoutLogs.count * 100) / logs.count
        workoutTrend = "--"
        
        // Nutrition (protein goal achievement)
        let nutritionLogs = logs.filter { $0.proteinGrams > 0 }
        if !nutritionLogs.isEmpty {
            let avgProtein = nutritionLogs.reduce(0.0) { $0 + $1.proteinGrams } / Double(nutritionLogs.count)
            nutritionScore = min(100, Int((avgProtein / settings.proteinTargetGrams) * 100))
        }
        nutritionTrend = "--"
        
        // Hydration
        let hydrationLogs = logs.filter { $0.waterOz > 0 }
        if !hydrationLogs.isEmpty {
            let avgWater = hydrationLogs.reduce(0.0) { $0 + $1.waterOz } / Double(hydrationLogs.count)
            hydrationScore = min(100, Int((avgWater / settings.waterTargetOz) * 100))
        }
        hydrationTrend = "--"
    }
    
    private func generateInsights(logs: [DayLog]) {
        var newInsights: [Insight] = []
        
        // Streak insight
        let streak = calculateStreak(logs: logs)
        if streak >= 3 {
            newInsights.append(Insight(
                title: "\(streak)-Day Streak!",
                description: "You've maintained a score above 60 for \(streak) consecutive days. Keep it up!",
                icon: "flame.fill",
                color: .orange
            ))
        }
        
        // Sleep insight
        let sleepLogs = logs.filter { $0.sleepScore != nil }
        if !sleepLogs.isEmpty {
            let avgSleep = sleepLogs.reduce(0) { $0 + ($1.sleepDurationMinutes ?? 0) } / sleepLogs.count
            let hours = avgSleep / 60
            if hours < 7 {
                newInsights.append(Insight(
                    title: "Sleep Opportunity",
                    description: "Your average sleep is \(hours)h. Aim for 7-8 hours for better recovery.",
                    icon: "bed.double.fill",
                    color: .purple
                ))
            } else if hours >= 7 {
                newInsights.append(Insight(
                    title: "Great Sleep Habits",
                    description: "Averaging \(hours)h of sleep. This supports muscle recovery and energy.",
                    icon: "moon.stars.fill",
                    color: .indigo
                ))
            }
        }
        
        // Workout consistency insight
        let workoutDays = logs.filter { $0.workoutTag != nil }.count
        let totalDays = logs.count
        if totalDays > 0 {
            let workoutRate = (workoutDays * 100) / totalDays
            if workoutRate >= 60 {
                newInsights.append(Insight(
                    title: "Consistent Training",
                    description: "You've worked out \(workoutDays) of the last \(totalDays) days. Excellent consistency!",
                    icon: "figure.strengthtraining.traditional",
                    color: .green
                ))
            } else if workoutRate < 40 && totalDays >= 7 {
                newInsights.append(Insight(
                    title: "Training Opportunity",
                    description: "Only \(workoutDays) workouts in \(totalDays) days. Consider adding more sessions.",
                    icon: "exclamationmark.triangle.fill",
                    color: .yellow
                ))
            }
        }
        
        // Best day insight
        if let best = logs.max(by: { ($0.dailyScoreFinal ?? $0.dailyScoreProvisional) < ($1.dailyScoreFinal ?? $1.dailyScoreProvisional) }) {
            let score = best.dailyScoreFinal ?? best.dailyScoreProvisional
            if score >= 90 {
                newInsights.append(Insight(
                    title: "Elite Performance",
                    description: "You hit \(score) points - that's elite level! You've got what it takes.",
                    icon: "star.fill",
                    color: AppColors.scoreElite
                ))
            }
        }
        
        insights = newInsights
    }
    
    private func calculateStreak(logs: [DayLog]) -> Int {
        var streak = 0
        let sortedLogs = logs.sorted { $0.date > $1.date }
        
        for log in sortedLogs {
            let score = log.dailyScoreFinal ?? log.dailyScoreProvisional
            if score >= 60 {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    private func loadWorkoutStats(startDate: Date, endDate: Date) {
        let fetchDescriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { log in
                log.dayDate >= startDate && log.dayDate <= endDate
            }
        )
        
        guard let workouts = try? modelContext.fetch(fetchDescriptor) else { return }
        
        workoutsCompleted = workouts.count
        
        // Average duration
        let durations = workouts.compactMap { $0.durationMinutes }
        averageWorkoutDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count
        
        // Total volume
        var totalVolume: Double = 0
        for workout in workouts {
            if let exercises = workout.exercises {
                for exercise in exercises {
                    totalVolume += exercise.totalVolume
                }
            }
        }
        formattedTotalVolume = totalVolume >= 1000 ? String(format: "%.1fk", totalVolume / 1000) : "\(Int(totalVolume))"
        
        // Total calories
        let totalCalories = workouts.compactMap { $0.caloriesBurned }.reduce(0, +)
        formattedTotalCalories = totalCalories >= 1000 ? String(format: "%.1fk", Double(totalCalories) / 1000) : "\(totalCalories)"
    }
    
    private func loadPersonalBests() {
        // Get recent exercises with high volume
        let fetchDescriptor = FetchDescriptor<WorkoutExercise>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        guard let exercises = try? modelContext.fetch(fetchDescriptor) else { return }
        
        // Group by exercise name and find top set for each
        var bestsByExercise: [String: PersonalBest] = [:]
        
        for exercise in exercises.prefix(100) { // Limit to recent 100 exercises
            guard let topSet = exercise.topSet else { continue }
            
            let volume = topSet.volume
            
            if let existing = bestsByExercise[exercise.exerciseName] {
                let existingVolume = existing.weight * Double(existing.reps)
                if volume > existingVolume {
                    bestsByExercise[exercise.exerciseName] = PersonalBest(
                        exercise: exercise.exerciseName,
                        weight: topSet.weightLbs,
                        reps: topSet.reps,
                        date: exercise.date
                    )
                }
            } else {
                bestsByExercise[exercise.exerciseName] = PersonalBest(
                    exercise: exercise.exerciseName,
                    weight: topSet.weightLbs,
                    reps: topSet.reps,
                    date: exercise.date
                )
            }
        }
        
        // Get top 5 by volume
        personalBests = Array(bestsByExercise.values)
            .sorted { ($0.weight * Double($0.reps)) > ($1.weight * Double($1.reps)) }
            .prefix(5)
            .map { $0 }
    }
}

#Preview {
    TrendsView()
}
