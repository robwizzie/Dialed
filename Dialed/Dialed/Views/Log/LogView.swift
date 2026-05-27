//
//  LogView.swift
//  Dialed
//
//  Food and workout logging with date selection
//

import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: LogViewModel
    
    @Query(sort: \WorkoutLog.dayDate, order: .reverse) private var allWorkouts: [WorkoutLog]
    
    @State private var showAddFood = false
    @State private var showWorkoutLog = false
    @State private var showWorkoutDetail = false
    @State private var showDatePicker = false
    @State private var editingFoodEntry: FoodEntry?
    @State private var dayLogBinding: DayLog?
    @State private var selectedPastWorkout: WorkoutLog?
    @State private var showPastWorkoutDetail = false
    
    // Recent workouts (exclude today)
    private var recentWorkouts: [WorkoutLog] {
        let today = Calendar.current.startOfDay(for: Date())
        return allWorkouts
            .filter { Calendar.current.startOfDay(for: $0.dayDate) < today }
            .prefix(5)
            .map { $0 }
    }
    
    init() {
        let container = try! DialedSchema.makeContainer()
        _viewModel = StateObject(wrappedValue: LogViewModel(modelContext: container.mainContext))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date selector
                    dateSelector
                    
                    // Workout section for selected date
                    workoutSection
                    
                    // Nutrition section
                    nutritionSection
                    
                    // Food entries
                    foodEntriesSection
                    
                    // Recent workouts section (when viewing today)
                    if viewModel.isToday && !recentWorkouts.isEmpty {
                        recentWorkoutsSection
                    }
                }
                .padding()
                .padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.formattedDate)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .sheet(isPresented: $showAddFood) {
                FoodEntrySheet(
                    existingEntry: nil,
                    onSave: { name, calories, protein, carbs, fat, saveAsMeal in
                        viewModel.addFoodEntry(
                            name: name,
                            calories: calories,
                            protein: protein,
                            carbs: carbs,
                            fat: fat,
                            saveAsMeal: saveAsMeal
                        )
                    }
                )
            }
            .sheet(item: $editingFoodEntry) { entry in
                FoodEntrySheet(
                    existingEntry: entry,
                    onSave: { name, calories, protein, carbs, fat, _ in
                        viewModel.updateFoodEntry(
                            entry,
                            name: name,
                            calories: calories,
                            protein: protein,
                            carbs: carbs,
                            fat: fat
                        )
                    }
                )
            }
            .sheet(isPresented: $showWorkoutLog) {
                if let dayLog = dayLogBinding {
                    WorkoutLogSheet(
                        dayLog: Binding(
                            get: { dayLog },
                            set: { self.dayLogBinding = $0 }
                        ),
                        onSave: {
                            viewModel.refreshData()
                        }
                    )
                }
            }
            .sheet(isPresented: $showWorkoutDetail) {
                if let workout = viewModel.workoutLog {
                    WorkoutDetailSheet(
                        workout: workout,
                        onDelete: {
                            viewModel.refreshData()
                        },
                        onUpdate: {
                            viewModel.refreshData()
                        }
                    )
                }
            }
            .sheet(isPresented: $showPastWorkoutDetail) {
                if let workout = selectedPastWorkout {
                    WorkoutDetailSheet(
                        workout: workout,
                        onDelete: {
                            selectedPastWorkout = nil
                        },
                        onUpdate: nil
                    )
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
        }
    }
    
    // MARK: - Date Selector
    
    private var dateSelector: some View {
        HStack(spacing: 12) {
            // Previous day
            Button(action: {
                viewModel.goToPreviousDay()
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
            
            // Date button
            Button(action: {
                showDatePicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    
                    Text(viewModel.formattedDate)
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
            
            // Next day / Today
            if viewModel.isToday {
                Circle()
                    .fill(.clear)
                    .frame(width: 36, height: 36)
            } else {
                Button(action: {
                    viewModel.goToNextDay()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
            
            Spacer()
            
            // Today button
            if !viewModel.isToday {
                Button(action: {
                    viewModel.goToToday()
                }) {
                    Text("Today")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.blue.opacity(0.15))
                        )
                }
            }
        }
    }
    
    // MARK: - Date Picker Sheet
    
    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.selectDate($0) }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Workout Section
    
    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.hasWorkout {
                WorkoutSummaryCard(
                    tag: viewModel.workoutSummary.tag,
                    score: viewModel.workoutSummary.score,
                    duration: viewModel.workoutSummary.duration,
                    calories: viewModel.workoutSummary.calories,
                    exerciseCount: viewModel.workoutSummary.exerciseCount,
                    onTap: {
                        if viewModel.workoutLog != nil {
                            showWorkoutDetail = true
                        } else {
                            dayLogBinding = viewModel.getOrCreateDayLog()
                            showWorkoutLog = true
                        }
                    }
                )
            } else {
                EmptyWorkoutCard(onTap: {
                    dayLogBinding = viewModel.getOrCreateDayLog()
                    showWorkoutLog = true
                })
            }
        }
    }
    
    // MARK: - Nutrition Section
    
    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                // Calories card
                NutritionStatCard(
                    title: "Calories",
                    current: Int(viewModel.totalCalories),
                    target: viewModel.settings.calorieTarget != nil ? Int(viewModel.settings.calorieTarget!) : nil,
                    unit: "cal",
                    color: .orange,
                    progress: viewModel.calorieProgress
                )
                
                // Protein card
                NutritionStatCard(
                    title: "Protein",
                    current: Int(viewModel.totalProtein),
                    target: Int(viewModel.settings.proteinTargetGrams),
                    unit: "g",
                    color: .blue,
                    progress: viewModel.proteinProgress
                )
            }
        }
    }
    
    // MARK: - Food Entries Section
    
    private var foodEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Food Log")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: {
                    showAddFood = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Food")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                }
            }
            
            if viewModel.foodEntries.isEmpty {
                emptyFoodState
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.foodEntries) { entry in
                        FoodEntryRow(
                            entry: entry,
                            onEdit: {
                                editingFoodEntry = entry
                            },
                            onDelete: {
                                viewModel.deleteFoodEntry(entry)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var emptyFoodState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.3))
            
            Text("No food logged yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Track your meals and nutrition")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
            
            Button(action: {
                showAddFood = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Food")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Recent Workouts Section
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Recent Workouts")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(allWorkouts.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(recentWorkouts) { workout in
                    Button(action: {
                        selectedPastWorkout = workout
                        showPastWorkoutDetail = true
                    }) {
                        RecentWorkoutRowCompact(workout: workout)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
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

// MARK: - Recent Workout Row Compact

private struct RecentWorkoutRowCompact: View {
    let workout: WorkoutLog
    
    private var tagDisplay: String {
        if let tag = Constants.WorkoutTag(rawValue: workout.tag) {
            return tag.shortName
        }
        return workout.tag
    }
    
    private var relativeDate: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workoutDay = calendar.startOfDay(for: workout.dayDate)
        
        let days = calendar.dateComponents([.day], from: workoutDay, to: today).day ?? 0
        
        switch days {
        case 1:
            return "Yesterday"
        case 2...6:
            return "\(days)d ago"
        case 7:
            return "1 week"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: workout.dayDate)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Workout type indicator
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.caption)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.green.opacity(0.1))
                )
            
            // Workout info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tagDisplay)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    if let duration = workout.durationMinutes {
                        Text("\(duration) min")
                            .font(.caption2)
                    }
                    
                    if let exercises = workout.exercises, !exercises.isEmpty {
                        Text("\(exercises.count) exercises")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Quality stars
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= workout.workoutScore ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundColor(index <= workout.workoutScore ? .yellow : Color.secondary.opacity(0.3))
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12))
        )
    }
}

// MARK: - Nutrition Stat Card

private struct NutritionStatCard: View {
    let title: String
    let current: Int
    let target: Int?
    let unit: String
    let color: Color
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(current)")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                
                if let target = target {
                    Text("/ \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Progress bar
            if target != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(progress, 1.0))
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 14)
    }
}

#Preview {
    LogView()
}
