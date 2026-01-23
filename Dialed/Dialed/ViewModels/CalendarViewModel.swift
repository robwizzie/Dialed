//
//  CalendarViewModel.swift
//  Dialed
//
//  Manages Calendar view state, month navigation, and streak calculation
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class CalendarViewModel: ObservableObject {
    // Published state
    @Published var currentMonth: Date
    @Published var dayLogs: [Date: DayLog] = [:]
    @Published var photoDates: Set<Date> = []
    @Published var selectedDate: Date?
    @Published var isLoading = false
    
    // Model context
    private let modelContext: ModelContext
    
    // Calendar
    private let calendar = Calendar.current
    
    // Month info
    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        }
    }
    
    var firstWeekdayOfMonth: Int {
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return 1
        }
        return calendar.component(.weekday, from: firstDay)
    }
    
    var leadingEmptyDays: Int {
        // Sunday = 1, so we need firstWeekdayOfMonth - 1 empty days
        return firstWeekdayOfMonth - 1
    }
    
    // Stats
    var currentStreak: Int {
        calculateStreak()
    }
    
    var monthlyAverage: Int {
        let monthDays = daysInMonth.filter { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: Date()) }
        let scores = monthDays.compactMap { dayLogs[calendar.startOfDay(for: $0)]?.dailyScoreProvisional }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / scores.count
    }
    
    var bestDay: (date: Date, score: Int)? {
        let today = calendar.startOfDay(for: Date())
        let validLogs = dayLogs.filter { $0.key <= today && ($0.value.dailyScoreFinal ?? $0.value.dailyScoreProvisional) > 0 }
        guard let best = validLogs.max(by: { ($0.value.dailyScoreFinal ?? $0.value.dailyScoreProvisional) < ($1.value.dailyScoreFinal ?? $1.value.dailyScoreProvisional) }) else {
            return nil
        }
        return (date: best.key, score: best.value.dailyScoreFinal ?? best.value.dailyScoreProvisional)
    }
    
    var completedDaysCount: Int {
        let today = calendar.startOfDay(for: Date())
        return dayLogs.filter { $0.key <= today && ($0.value.dailyScoreFinal ?? $0.value.dailyScoreProvisional) >= 60 }.count
    }
    
    var totalPhotosThisMonth: Int {
        let monthDays = Set(daysInMonth.map { calendar.startOfDay(for: $0) })
        return photoDates.filter { monthDays.contains($0) }.count
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.currentMonth = Date()
        
        loadMonthData()
    }
    
    // MARK: - Data Loading
    
    func loadMonthData() {
        isLoading = true
        
        // Get start and end of month with buffer
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            isLoading = false
            return
        }
        
        // Extend range for streak calculation
        let extendedStart = calendar.date(byAdding: .day, value: -60, to: startOfMonth) ?? startOfMonth
        let extendedEnd = calendar.date(byAdding: .day, value: 1, to: endOfMonth) ?? endOfMonth
        
        // Fetch all DayLogs in range
        let fetchDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { log in
                log.date >= extendedStart && log.date <= extendedEnd
            }
        )
        
        if let logs = try? modelContext.fetch(fetchDescriptor) {
            var logsByDate: [Date: DayLog] = [:]
            for log in logs {
                let normalizedDate = calendar.startOfDay(for: log.date)
                logsByDate[normalizedDate] = log
            }
            dayLogs = logsByDate
        }
        
        // Fetch photos to track which dates have photos
        loadPhotoDates(startDate: extendedStart, endDate: extendedEnd)
        
        isLoading = false
    }
    
    private func loadPhotoDates(startDate: Date, endDate: Date) {
        let fetchDescriptor = FetchDescriptor<WorkoutPhoto>(
            predicate: #Predicate { photo in
                photo.capturedAt >= startDate && photo.capturedAt <= endDate
            }
        )
        
        if let photos = try? modelContext.fetch(fetchDescriptor) {
            var dates: Set<Date> = []
            for photo in photos {
                let normalizedDate = calendar.startOfDay(for: photo.capturedAt)
                dates.insert(normalizedDate)
            }
            photoDates = dates
        }
    }
    
    // MARK: - Navigation
    
    func goToPreviousMonth() {
        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = previousMonth
            loadMonthData()
        }
    }
    
    func goToNextMonth() {
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            // Don't go past current month
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
            let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))!
            
            if nextMonthStart <= currentMonthStart {
                currentMonth = nextMonth
                loadMonthData()
            }
        }
    }
    
    func goToCurrentMonth() {
        currentMonth = Date()
        loadMonthData()
    }
    
    var canGoToNextMonth: Bool {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else {
            return false
        }
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))!
        return nextMonthStart <= currentMonthStart
    }
    
    var isCurrentMonth: Bool {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let viewingMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        return currentMonthStart == viewingMonthStart
    }
    
    // MARK: - Day Data
    
    func dayLog(for date: Date) -> DayLog? {
        let normalizedDate = calendar.startOfDay(for: date)
        return dayLogs[normalizedDate]
    }
    
    func score(for date: Date) -> Int? {
        guard let log = dayLog(for: date) else { return nil }
        return log.dailyScoreFinal ?? log.dailyScoreProvisional
    }
    
    func hasPhoto(for date: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        return photoDates.contains(normalizedDate)
    }
    
    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
    
    func isFuture(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }
    
    func selectDate(_ date: Date) {
        // Don't select future dates
        guard !isFuture(date) else { return }
        selectedDate = date
    }
    
    func clearSelection() {
        selectedDate = nil
    }
    
    // MARK: - Streak Calculation
    
    private func calculateStreak(threshold: Int = 60) -> Int {
        var streak = 0
        var currentDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        
        while true {
            let normalizedDate = calendar.startOfDay(for: currentDate)
            
            if let log = dayLogs[normalizedDate] {
                let score = log.dailyScoreFinal ?? log.dailyScoreProvisional
                if score >= threshold {
                    streak += 1
                } else {
                    break
                }
            } else {
                // No log for this day - streak is broken
                break
            }
            
            // Go to previous day
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDay
        }
        
        return streak
    }
    
    func refreshData() {
        loadMonthData()
    }
}
